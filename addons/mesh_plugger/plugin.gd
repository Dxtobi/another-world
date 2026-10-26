@tool
extends EditorPlugin
## "Plug" -- turn a flat image plus a Skeleton2D into a bone-deformed mesh,
## with no outline drawn by hand.
##
## THE WORKFLOW THIS IS FOR
##   1. Import your creature art (Inkscape PNG, transparent background).
##   2. Add a Skeleton2D and lay Bone2D nodes over the art however you like --
##      one per limb segment, named whatever. No special tool needed.
##   3. Add a Polygon2D on the same node, set its texture to the art.
##   4. Select it, click Plug.
##
## The polygon is traced from the image's alpha and weighted to the nearest
## bone automatically, using the same weighting rules as the Backing Weighter
## that already ships with this project.
##
## THE LIMITS, so nothing here is a surprise:
##   - Vertices sit on the silhouette, so the shape's interior is rigid. Right
##     for cut-out limbs; a torso that should squash like cloth needs an
##     interior grid instead, which this does not build.
##   - Weights are nearest-bone with a blend near joints. Bend a bone far from
##     the silhouette and it will not stretch the middle -- that is the outline
##     limitation again, not a bug.
##   - Tracing cost scales with image pixels, so huge source art is slow. It
##     runs once at plug time, never per frame.

const Mesher := preload("res://addons/mesh_plugger/mesher.gd")

var _btn: Button
var _mesher: Mesher


func _enter_tree() -> void:
	_mesher = Mesher.new()
	_btn = Button.new()
	_btn.text = "Plug"
	_btn.tooltip_text = "Trace the selected image into a mesh and bind it to the nearest Skeleton2D"
	_btn.pressed.connect(_run)
	add_control_to_container(CONTAINER_CANVAS_EDITOR_MENU, _btn)


func _exit_tree() -> void:
	remove_control_from_container(CONTAINER_CANVAS_EDITOR_MENU, _btn)
	_btn.queue_free()


func _run() -> void:
	var poly := _find_poly()
	if poly == null:
		push_warning("Mesh Plugger: select a Polygon2D with a texture (or a node containing one).")
		return
	if poly.texture == null:
		push_warning("Mesh Plugger: that Polygon2D has no texture to trace.")
		return
	var sk := _find_skeleton(poly)
	if sk == null:
		push_warning("Mesh Plugger: no Skeleton2D found above the polygon.")
		return
	# Bones must be at their rest pose or every weight is measured against the
	# wrong shape. The weighter warns about this; doing it here means the user
	# gets one clear message instead of a wrong mesh.
	var off := _off_rest_bones(sk)
	if not off.is_empty():
		push_warning("Mesh Plugger: %d bone(s) are off their rest pose (%s). Skeleton2D > Make Rest Pose first."
			% [off.size(), ", ".join(off)])
		return

	var traced: Dictionary = _mesher.plug(poly.texture, sk)
	if not traced.get("ok", false):
		push_warning("Mesh Plugger: %s" % traced.get("error", "trace failed"))
		return

	var res: Dictionary = _mesher.apply_to(poly, traced, sk)
	if not res.get("ok", false):
		push_warning("Mesh Plugger: %s" % res.get("error", "weighting failed"))
		return

	# Centre the polygon on its own bounding box so the art lands where the
	# bones are, instead of at the image's top-left origin.
	var used: Rect2 = poly.get_rect()
	poly.position = -used.size * 0.5 - used.position

	print("Mesh Plugger: %d verts, %d bones, %d blended, %d hole(s)"
		% [res["verts"], res["bones"], res["blended"], res.get("holes", 0)])


func _find_poly() -> Polygon2D:
	var sel := EditorInterface.get_selection().get_selected_nodes()
	if sel.is_empty():
		return null
	var n: Node = sel[0]
	if n is Polygon2D:
		return n
	var found := n.find_children("*", "Polygon2D", true, false)
	for f in found:
		if (f as Polygon2D).texture != null:
			return f as Polygon2D
	return found[0] as Polygon2D if not found.is_empty() else null


func _find_skeleton(poly: Node) -> Skeleton2D:
	var cur := poly.get_parent()
	while cur != null:
		if cur is Skeleton2D:
			return cur
		cur = cur.get_parent()
	return null


func _off_rest_bones(sk: Skeleton2D) -> PackedStringArray:
	var bad := PackedStringArray()
	var bones: Array[Bone2D] = []
	_collect(sk, bones)
	for b in bones:
		var node := b as Node2D
		if not node.transform.origin.is_equal_approx(b.rest.origin) \
				or absf(wrapf(b.rotation - b.rest.get_rotation(), -PI, PI)) > 0.02:
			bad.append(b.name)
	return bad


func _collect(n: Node, out: Array[Bone2D]) -> void:
	for c in n.get_children():
		if c is Bone2D:
			out.append(c as Bone2D)
		_collect(c, out)