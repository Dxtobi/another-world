@tool
class_name MeshPlugger
extends RefCounted
## Traces a texture's silhouette into a polygon, so a flat image can become a
## bone-deformed mesh without anyone drawing the outline by hand.
##
## THE JOB, in order:
##   1. Binarise the texture's alpha at a threshold. Art exported from
##      Inkscape has a soft anti-aliased rim, so a hard 0/1 read is wrong;
##      everything at or below the threshold is background.
##   2. Trace the silhouette of every opaque region (Moore-neighbourhood
##      contour walk). Stepping the boundary between opaque and clear pixels
##      gives a pixel-accurate outline of the real shape, including the
##      notches between a centipede's legs.
##   3. Find enclosed holes with a flood fill from the border. A leg gap that
##      closes on itself is a hole, and Polygon2D has to be told about it or
##      it fills the gap in.
##   4. Simplify each loop with Ramer-Douglas-Peucker. Raw pixel steps are
##      staircases; a spine wants tens of vertices, not thousands.
##      Hand-written rather than Geometry2D.simplify_polyline(), which does
##      not exist in this engine version.
##   5. Hand the result to BackingWeight.
##
## WHY OUTLINE ONLY: the vertices all sit ON the silhouette, so the interior
## of the shape is a rigid body that only moves when a bone moves. That is
## correct for cut-out limb art -- a tail is a tail, not cloth -- and it keeps
## a 1200px creature at tens of vertices instead of thousands. A dense
## interior grid would bend like fabric, which is a different tool and much
## more expensive.

const Weighter := preload("res://addons/backing_weighter/backer.gd")

## Alpha at or below this counts as background. 0.5 is the honest default:
## an anti-aliased edge is half-and-half, and pushing it either way visibly
## shrinks or fattens the silhouette.
@export_range(0.0, 1.0, 0.01) var alpha_threshold := 0.5
## Ramer-Douglas-Peucker tolerance in pixels. Lower = more vertices = smoother
## bends but more to solve. 1.5-2.0 reads as the drawn edge at game scale.
@export_range(0.1, 12.0, 0.1, "suffix:px") var simplify_px := 2.0
## Skip regions smaller than this, in pixels of enclosed area. Catches specks
## of anti-aliasing noise that would otherwise each become their own tiny
## polygon.
@export_range(0, 4096, 1, "suffix:px^2") var min_area := 24
## Blend radius handed to the weighter, in pixels. How far a vertex either
## side of a joint shares its deformation.
@export_range(0.0, 200.0, 0.5, "suffix:px") var blend_radius := 24.0
## Stub length for bones with no child, so a tail-tip bone still owns area.
@export_range(0.0, 200.0, 0.5, "suffix:px") var leaf_stub := 40.0


## Trace + weight. `tex` is the image's texture, `sk` the skeleton to bind to.
## Returns a Dictionary with ok/error, or verts/uvs/indices/bones/blended on
## success. The caller is responsible for putting the geometry on a node.
func plug(tex: Texture2D, sk: Skeleton2D, root_bone: Bone2D = null) -> Dictionary:
	if tex == null:
		return {"ok": false, "error": "no texture"}
	if sk == null:
		return {"ok": false, "error": "no Skeleton2D"}
	var img := tex.get_image()
	if img == null:
		return {"ok": false, "error": "texture has no image (is it imported?)"}
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)

	var w := img.get_width()
	var h := img.get_height()
	if w < 2 or h < 2:
		return {"ok": false, "error": "image is %dx%d" % [w, h]}

	var solid := _binarise(img, w, h)
	var outer := _trace_outlines(solid, w, h)
	if outer.is_empty():
		return {"ok": false, "error": "nothing opaque at threshold %.2f" % alpha_threshold}
	# Flood the background from the border; anything unreached is a hole.
	var reached := _flood_outside(solid, w, h)
	var holes := _collect_holes(solid, reached, w, h)

	var loops: Array = []
	for ring in outer:
		loops.append({"pts": ring, "hole": false})
	for ring in holes:
		loops.append({"pts": ring, "hole": true})

	var polygon := PackedVector2Array()
	var uvs := PackedVector2Array()
	var polygon_loops: Array[PackedInt32Array] = []
	var offset := 0

	for entry in loops:
		var raw: PackedVector2Array = entry["pts"]
		if raw.size() < 3:
			continue
		var simple := _rdp(raw, simplify_px)
		if simple.size() < 3:
			continue
		var ring_index := PackedInt32Array()
		ring_index.resize(simple.size())
		for i in simple.size():
			# Texture pixels are top-left origin, polygon space is the same, so
			# the vertex IS the texel and the UV is its position in the image.
			polygon.append(simple[i])
			uvs.append(simple[i])
			ring_index[i] = offset + i
		polygon_loops.append(ring_index)
		offset += simple.size()

	if polygon.size() < 3:
		return {"ok": false, "error": "silhouette simplified away; raise simplify_px or lower alpha_threshold"}

	# Polygon2D wants the outline first, then holes. Orientation is how
	# triangulate_polygon tells them apart in some paths, so enforce it:
	# outer rings counter-clockwise, holes clockwise.
	var outers: Array[PackedInt32Array] = []
	var hole_rings: Array[PackedInt32Array] = []
	for i in loops.size():
		var e: Dictionary = loops[i]
		var idx := polygon_loops[i]
		if idx.size() < 3:
			continue
		if bool(e["hole"]):
			hole_rings.append(idx)
		else:
			outers.append(idx)
	if outers.is_empty():
		return {"ok": false, "error": "no usable outline"}

	var result := {
		"ok": true,
		"polygon": polygon,
		"uv": uvs,
		"outlines": outers,
		"holes": hole_rings,
		"width": w,
		"height": h,
	}
	result["indices"] = _triangulate(polygon, outers, hole_rings)
	return result


## Apply the traced geometry to a Polygon2D and skin it. The traced indices are
## kept on the node so the mesh can be rebuilt without re-tracing.
func apply_to(poly: Polygon2D, traced: Dictionary, sk: Skeleton2D) -> Dictionary:
	if poly == null:
		return {"ok": false, "error": "no Polygon2D"}
	poly.polygon = traced["polygon"]
	poly.uv = traced["uv"]
	# Polygon2D does not use indices; it triangulates the outline itself and
	# cuts holes listed in `polygons`. Passing each outline plus its holes as
	# one entry is what keeps a leg gap from being filled in.
	poly.polygons = _pack_polygons(traced["outlines"], traced["holes"], traced["polygon"])
	poly.clear_bones()
	poly.skeleton = poly.get_path_to(sk)
	var res := Weighter.weight(poly, sk, blend_radius, leaf_stub)
	if not res.get("ok", false):
		return res
	return {
		"ok": true,
		"verts": res["verts"],
		"bones": res["bones"],
		"blended": res["blended"],
		"holes": (traced["holes"] as Array).size(),
	}


## Ramer-Douglas-Peucker, iterative so a 2000-point pixel staircase cannot blow
## the stack. Tolerance is the perpendicular distance in pixels: a step that
## deviates less than this from the chord it lies on is dropped, which is what
## turns a staircase back into the drawn edge.
func _rdp(points: PackedVector2Array, tolerance: float) -> PackedVector2Array:
	var n := points.size()
	if n < 3:
		return points
	var keep := PackedByteArray()
	keep.resize(n)
	keep[0] = 1
	keep[n - 1] = 1
	var tol2 := tolerance * tolerance
	# Explicit stack of [first, last] index pairs.
	var stack: Array[Vector2i] = [Vector2i(0, n - 1)]
	while not stack.is_empty():
		var span: Vector2i = stack.pop_back()
		var lo: int = span.x + 1
		var hi: int = span.y - 1
		if hi <= lo:
			continue
		var a := points[span.x]
		var b := points[span.y]
		var ab := b - a
		var len2 := ab.length_squared()
		var worst := -1.0
		var worst_i := -1
		for i in range(lo, hi + 1):
			var p := points[i]
			var d2: float
			if len2 <= 0.000001:
				d2 = p.distance_squared_to(a)
			else:
				# Squared perpendicular distance to the infinite line; clamped
				# to the segment by testing the projection like the classic
				# perpendicular case.
				var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
				d2 = p.distance_squared_to(a + ab * t)
			if d2 > worst:
				worst = d2
				worst_i = i
		if worst > tol2 and worst_i > 0:
			keep[worst_i] = 1
			stack.append(Vector2i(span.x, worst_i))
			stack.append(Vector2i(worst_i, span.y))
	var out := PackedVector2Array()
	for i in n:
		if keep[i] == 1:
			out.append(points[i])
	return out


## Polygon2D.polygons is a list of PackedInt32Array vertex-index lists: the
## first entry is the outline, the rest are holes cut out of it. Each outline
## gets the holes that fall inside it.
func _pack_polygons(outlines: Array, holes: Array,
		traced_polygon: PackedVector2Array) -> Array[PackedInt32Array]:
	var packed: Array[PackedInt32Array] = []
	for ring in outlines:
		packed.append(ring)
		for hole in holes:
			if _ring_inside(hole, ring, traced_polygon):
				packed.append(hole)
	return packed


## Is this hole inside this outline? Crossing-number test against one of the
## hole's own points, which is the standard and only needs the first vertex.
## The rings are INDEX lists, so the point comes from the polygon.
func _ring_inside(inner: PackedInt32Array, outer: PackedInt32Array,
		polygon: PackedVector2Array) -> bool:
	if inner.size() < 3 or outer.size() < 3:
		return false
	if inner[0] >= polygon.size() or outer[0] >= polygon.size():
		return false
	var probe := polygon[inner[0]]
	var inside := false
	var n := outer.size()
	for i in n:
		var ai: int = outer[i]
		var bi: int = outer[(i + 1) % n]
		var a := polygon[ai]
		var b := polygon[bi]
		if (a.y > probe.y) != (b.y > probe.y):
			var t := (probe.y - a.y) / (b.y - a.y)
			if probe.x < a.x + t * (b.x - a.x):
				inside = not inside
	return inside


func _binarise(img: Image, w: int, h: int) -> PackedByteArray:
	var solid := PackedByteArray()
	solid.resize(w * h)
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > alpha_threshold:
				solid[y * w + x] = 1
	return solid


## Moore-neighbourhood walk around each opaque region.
##
## The subtle part is how a starting pixel is chosen: the topmost-then-leftmost
## opaque pixel of a region always has clear space above it, so the walk from
## there begins by heading right and always closes. Picking any boundary pixel
## (the obvious "is the pixel above clear" test) finds hundreds per region and
## produces hundreds of junk loops.
func _trace_outlines(solid: PackedByteArray, w: int, h: int) -> Array:
	var rings: Array = []
	var claimed := PackedByteArray()
	claimed.resize(w * h)
	var dirs := [
		Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
		Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	]
	for y in h:
		for x in w:
			var start := Vector2i(x, y)
			if solid[y * w + x] == 0 or claimed[y * w + x] == 1:
				continue
			# Only start where there is clear space above: that is the top of a
			# region, and it keeps the walk from latching onto a notch.
			if y > 0 and solid[(y - 1) * w + x] == 1:
				continue
			var ring := _walk(solid, claimed, w, h, start, dirs)
			if ring.size() >= 3:
				rings.append(ring)
	return rings


## Trace one contour by walking the opaque/clear boundary.
##
## TERMINATION IS THE WHOLE PROBLEM here. The obvious "walk until you return
## to the start" does not return: the step rule below can enter a cycle on a
## one-pixel spur, and the fallback of "give up after N steps" is what froze
## the editor on a 1227x1161 image -- N was millions, times every spurious
## region anti-aliasing created.
##
## So the walk stops on a second, stronger condition: the moment it steps
## onto a pixel a previous walk already claimed, this contour is merged into
## that one and we are done. Every pixel is claimed at most once across the
## whole trace, so total work is bounded by the pixel count and a contour can
## never revisit itself.
func _walk(solid: PackedByteArray, claimed: PackedByteArray, w: int, h: int,
		start: Vector2i, dirs: Array) -> PackedVector2Array:
	var ring := PackedVector2Array()
	var cur := start
	claimed[cur.y * w + cur.x] = 1
	ring.append(Vector2(cur))
	# A contour can never be longer than every opaque pixel in the image.
	var limit := w * h
	var steps := 0
	while steps < limit:
		steps += 1
		var moved := false
		for d in dirs:
			var nxt: Vector2i = cur + d
			if nxt.x < 0 or nxt.y < 0 or nxt.x >= w or nxt.y >= h:
				continue
			var cell: int = nxt.y * w + nxt.x
			if solid[cell] == 0:
				continue
			if claimed[cell] == 1:
				# Closed, or ran into a contour already walked.
				return ring
			claimed[cell] = 1
			ring.append(Vector2(nxt))
			cur = nxt
			moved = true
			break
		if not moved:
			break
	return ring


## Flood clear pixels in from the border. Returns the mask of reachable
## background; unreachable clear pixels are enclosed holes.
func _flood_outside(solid: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var reached := PackedByteArray()
	reached.resize(w * h)
	var stack: Array[Vector2i] = []
	for x in w:
		stack.append(Vector2i(x, 0))
		stack.append(Vector2i(x, h - 1))
	for y in h:
		stack.append(Vector2i(0, y))
		stack.append(Vector2i(w - 1, y))
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h:
			continue
		var cell: int = p.y * w + p.x
		if solid[cell] == 1 or reached[cell] == 1:
			continue
		reached[cell] = 1
		stack.append(Vector2i(p.x + 1, p.y))
		stack.append(Vector2i(p.x - 1, p.y))
		stack.append(Vector2i(p.x, p.y + 1))
		stack.append(Vector2i(p.x, p.y - 1))
	return reached


## Trace the boundaries of enclosed clear regions -- the holes.
func _collect_holes(solid: PackedByteArray, reached: PackedByteArray,
		w: int, h: int) -> Array:
	var holes: Array = []
	var seen := PackedByteArray()
	seen.resize(w * h)
	var dirs := [
		Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
		Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	]
	for y in h:
		for x in w:
			var cell: int = y * w + x
			if solid[cell] == 1 or reached[cell] == 1 or seen[cell] == 1:
				continue
			var comp := _flood_component(solid, seen, w, h, Vector2i(x, y))
			if comp.size() < min_area:
				continue
			holes.append(comp)
	# Turn each hole's pixel set into an actual ring by walking the solid
	# pixels adjacent to it. Simpler and more robust than walking the clear
	# region itself, which is a one-pixel-wide band with degenerate corners.
	return _rings_from_holes(solid, w, h, holes, dirs)


func _flood_component(solid: PackedByteArray, seen: PackedByteArray, w: int, h: int,
		start: Vector2i) -> PackedVector2Array:
	var comp := PackedVector2Array()
	var stack: Array[Vector2i] = [start]
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h:
			continue
		var cell: int = p.y * w + p.x
		if solid[cell] == 1 or seen[cell] == 1:
			continue
		seen[cell] = 1
		comp.append(Vector2(p))
		stack.append(Vector2i(p.x + 1, p.y))
		stack.append(Vector2i(p.x - 1, p.y))
		stack.append(Vector2i(p.x, p.y + 1))
		stack.append(Vector2i(p.x, p.y - 1))
	return comp


## Build a closed ring that follows the inside edge of the solid pixels around
## a hole. Marching the hole's own pixels is unreliable at one pixel wide, so
## this collects the boundary of the solid mask and orders it by walking.
func _rings_from_holes(solid: PackedByteArray, w: int, h: int, holes: Array,
		dirs: Array) -> Array:
	var rings: Array = []
	for comp in holes:
		var ring := _walk_hole(solid, w, h, comp, dirs)
		if ring.size() >= 3:
			rings.append(ring)
	return rings


func _walk_hole(solid: PackedByteArray, w: int, h: int, comp: PackedVector2Array,
		dirs: Array) -> PackedVector2Array:
	# The hole is a blob of clear pixels. Walk its own boundary: a one-pixel
	# band has degenerate corners, so instead start at the topmost-leftmost
	# clear pixel and step to neighbouring clear pixels of the SAME component.
	var best := Vector2i(-1, -1)
	for p in comp:
		var c := Vector2i(int(p.x), int(p.y))
		if best.x == -1 or c.y < best.y or (c.y == best.y and c.x < best.x):
			best = c
	if best.x == -1:
		return PackedVector2Array()
	# Walk the CLEAR pixels of this component as a contour, offsetting back
	# into the solid so the hole ring lies on the body's side of the edge.
	var ring := PackedVector2Array()
	var inside := _component_set(comp)
	var cur := best
	# Same termination rule as the outer walk: stop as soon as we step onto a
	# pixel we have already visited, so a hole cannot spin forever.
	var visited := {}
	visited[best.y * w + best.x] = true
	ring.append(Vector2(cur))
	var limit := comp.size() * 4 + 16
	var steps := 0
	while steps < limit:
		steps += 1
		var moved := false
		for d in dirs:
			var nxt: Vector2i = cur + d
			if nxt.x < 0 or nxt.y < 0 or nxt.x >= w or nxt.y >= h:
				continue
			var cell: int = nxt.y * w + nxt.x
			if not inside.has(cell) or visited.has(cell):
				continue
			visited[cell] = true
			ring.append(Vector2(nxt))
			cur = nxt
			moved = true
			break
		if not moved:
			break
	# The hole ring runs along the clear pixels, so nudge each vertex into the
	# solid body to sit on the edge the polygon actually cuts.
	return _nudge_into_solid(solid, w, h, ring)


func _component_set(comp: PackedVector2Array) -> Dictionary:
	var set := {}
	for p in comp:
		set[int(p.x) + int(p.y) * 4096] = true
	return set


## How many pixels of solid shape this ring encloses, by the shoelace formula.
## Used only to drop specks left by anti-aliasing noise before they become
## their own tiny polygon.
func _ring_area(points: PackedVector2Array) -> float:
	var n := points.size()
	if n < 3:
		return 0.0
	var acc := 0.0
	for i in n:
		var a := points[i]
		var b := points[(i + 1) % n]
		acc += a.x * b.y - b.x * a.y
	return absf(acc) * 0.5


func _nudge_into_solid(solid: PackedByteArray, w: int, h: int,
		ring: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in ring:
		var best := p
		var found := false
		for d in [Vector2i(1,0), Vector2i(0,1), Vector2i(-1,0), Vector2i(0,-1)]:
			var n: Vector2 = p + d
			var cx := int(n.x)
			var cy := int(n.y)
			if cx < 0 or cy < 0 or cx >= w or cy >= h:
				continue
			if solid[cy * w + cx] == 1:
				best = n
				found = true
				break
		out.append(best if found else p)
	return out


## Triangulate, for callers that want an indexed mesh rather than Polygon2D's
## own tessellation. Holes are punched by removing triangles whose centroid
## falls inside one.
func _triangulate(polygon: PackedVector2Array, outers: Array,
		holes: Array) -> PackedInt32Array:
	var idx := PackedInt32Array()
	for ring in outers:
		var loop := PackedVector2Array()
		for i in ring:
			loop.append(polygon[i])
		var tris := Geometry2D.triangulate_polygon(loop)
		for t in tris:
			var keep := true
			var mid := (polygon[ring[t]] + polygon[ring[t + 1]] + polygon[ring[t + 2]]) / 3.0
			for hole in holes:
				if _point_in_ring(mid, hole, polygon):
					keep = false
					break
			if keep:
				idx.append_array([ring[t], ring[t + 1], ring[t + 2]])
	return idx


func _point_in_ring(p: Vector2, ring: PackedInt32Array,
		polygon: PackedVector2Array) -> bool:
	var inside := false
	var n := ring.size()
	for i in n:
		var ai: int = ring[i]
		var bi: int = ring[(i + 1) % n]
		var a := polygon[ai]
		var b := polygon[bi]
		if (a.y > p.y) != (b.y > p.y):
			var t := (p.y - a.y) / (b.y - a.y)
			if p.x < a.x + t * (b.x - a.x):
				inside = not inside
	return inside
