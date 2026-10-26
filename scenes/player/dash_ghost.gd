class_name DashGhost
extends Node2D
## One dash afterimage cluster, drawn as a SINGLE canvas item.
##
## The rig holds ~18 sprites. Cloning them per stamp, then freeing ~500 nodes
## a dash later, was the expensive half of the old trail. This caches each
## part's texture and local draw rect once and repaints them inside _draw(),
## so a whole ghost is exactly one node in the scene tree.
##
## The per-part phase offsets that live in the same loop are also what makes
## it dissolve LIMB BY LIMB instead of all at once, which is the ghostly half
## of the effect.
##
## TIMING: while the dash runs the ghost HOLDS its stamped pose and shimmers
## (a freeze-frame trail). When the dash ends it REELS in, accelerating into
## the player's body and dissolving on contact. It never pops: arrival shrinks
## it into nothing while the alpha curve finishes, so nothing ever blinks out.

## Fired once, right before the ghost leaves the tree. The player uses it to
## drop it from its live list instead of holding dead refs.
signal finished(g: DashGhost)

## Where the ghost converges. The player points this at its `body` node, NOT
## its root origin: the root sits at the hips, and ghosts chasing it used to
## collapse into empty space below the character.
var target: Node2D
var parts: Array[Dictionary] = []

var chase_speed := 1400.0
var rise := 55.0      ## px/s upward drift while reeling
var swell := 0.08     ## scale gain across the dissolve
var life := 0.55      ## dissolve length once reeling
var peak_alpha := 0.45
var tint := Color(1.0, 0.6, 0.2) ## sampled from the rig's own palette
var shimmer_px := 1.6 ## wobble while holding
## Parts smaller than this many ON-SCREEN px are not worth drawing: a dot a
## couple of pixels across costs a full textured quad of overdraw and reads as
## nothing. The rig is small in world terms, so this is what keeps a ghost
## affordable on weak hardware.
var min_part_px := 3.0

var reeling := false
## Arrival must sit well above ONE frame of `rise` (rise/fps) or the upward
## drift and the chase cancel each other just short of the threshold and the
## ghost hangs on the player forever instead of dissolving.
var arrive_dist := 6.0
## While the dash runs, ghosts drift toward whoever is AHEAD of them in the
## trail (the next ghost stamped, or the player for the newest one) instead
## of sitting rigidly where they were stamped. Drift has to beat dash_speed
## or a fixed time-lag becomes a fixed distance and the ribbon stretches into
## a row of lagging clones.
var leader: Node2D
var hold_drift := 1100.0
var hold_gap := 30.0 ## px standoff kept from whoever it follows

var _reel_t := 0.0
var _age := 0.0      ## seconds since stamped; drives the hold fade
var _drawn_alpha := -1.0 ## last painted alpha/scale, for redraw throttling
var _drawn_scale := -1.0
## Diagnostics: how many times this ghost has actually repainted. A ghost
## holding its pose should paint a handful of times over a dash, not once per
## frame - that ratio is the whole cost of the trail.
var draw_calls := 0
var _dissolve := 0.0  ## 0..1 arrival shrink
var _arrived := false
var _t := 0.0


## Record one rig sprite in the ghost's own frame. `inv` is the inverse of
## the ghost's global transform, so the pose lands in local space and the
## ghost can then be moved and scaled freely.
##
## The part is stored as four transformed corners + UVs rather than a
## transform handed to draw_set_transform: the rig mirrors by negative
## scale when it faces left, and get_rotation()/get_scale() cannot
## round-trip a mirror. Corners are exact for any affine transform.
func add_part(src: Sprite2D, inv: Transform2D) -> void:
	var tex := src.texture
	if tex == null or not src.is_visible_in_tree():
		return
	var size := Vector2(tex.get_size())
	var src_rect: Rect2 = src.region_rect if src.region_enabled \
		else Rect2(Vector2.ZERO, size)
	var half := src_rect.size * 0.5 if src.centered else Vector2.ZERO
	var rect := Rect2(-half + src.offset, src_rect.size)
	# Every ancestor flip, rotation and scale (including the facing mirror)
	# is already inside src.global_transform, so the pose comes for free.
	var xf := inv * src.global_transform
	# On-screen size of this part: local size scaled by the transform. Tiny
	# parts are dropped rather than drawn as invisible overdraw.
	if rect.size.length() * xf.x.length() < min_part_px:
		return
	var pts := PackedVector2Array([
		Vector2(rect.position.x, rect.position.y),
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	])
	for i in pts.size():
		pts[i] = xf * pts[i]
	# draw_polygon takes UVs NORMALIZED to 0..1, not texture pixels. Feeding
	# it atlas pixels wraps every quad onto a single texel, which is
	# invisible. The regions here can sit a hair outside the atlas (some
	# have negative x), which is why a straight divide is right: the render
	# clamps, and the neighbouring part fills the seam.
	var tsize := Vector2(tex.get_size())
	var uv := PackedVector2Array([
		src_rect.position / tsize,
		Vector2(src_rect.end.x, src_rect.position.y) / tsize,
		src_rect.end / tsize,
		Vector2(src_rect.position.x, src_rect.end.y) / tsize,
	])
	parts.append({
		"tex": tex,
		"pts": pts,
		"uv": uv,
		"mod": src.self_modulate * src.modulate,
		"phase": randf() * TAU,
	})


## The dash is over: stop holding and collapse into the player.
func reel() -> void:
	reeling = true


func _process(delta: float) -> void:
	if not is_instance_valid(target):
		_die()
		return
	_t += delta
	var k := 0.0
	if not reeling:
		# Hold: follow whoever is ahead in the trail, so the ribbon tucks in
		# behind the player instead of hanging at a fixed lag.
		_age += delta
		var lead: Node2D = leader if is_instance_valid(leader) else target
		if is_instance_valid(lead) and hold_drift > 0.0:
			var dv := lead.global_position - global_position
			var dist := dv.length()
			if dist > hold_gap:
				global_position += dv.normalized() \
					* minf(hold_drift * delta, dist - hold_gap)
	if reeling:
		_reel_t += delta
		k = clampf(_reel_t / maxf(life, 0.01), 0.0, 1.0)
		var d: Vector2 = target.global_position - global_position
		if not _arrived and d.length() > arrive_dist:
			# Lift off while it flies: the drift applies first, so the trail
			# rises as it closes in, then the chase pulls it the rest of the way.
			global_position.y -= rise * delta
			d = target.global_position - global_position
			# Older ghosts snap hardest: the speed ramps with how long they
			# have been reeling, so the trail rushes in instead of drifting.
			var ramp := 0.35 + 0.65 * k
			global_position += d.normalized() * minf(chase_speed * ramp * delta, d.length())
		else:
			# Latched: it keeps lifting as it burns away, but it can never
			# wander back out of the dissolve.
			_arrived = true
			global_position.y -= rise * delta
			_dissolve = minf(_dissolve + delta * 3.5, 1.0)
			if _dissolve >= 1.0:
				_die()
				return
	scale = Vector2.ONE * ((1.0 + swell * k) * (1.0 - _dissolve))
	_refresh()


func _die() -> void:
	finished.emit(self)
	queue_free()


## Push a redraw only when the picture actually changes. A ghost holding its
## pose is a STATIC image, so repainting ~34 textured quads for it sixty times
## a second is pure waste - and it is the kind of waste that stutters a
## 32-bit phone. Alpha and scale are quantised so a slow fade repaints a few
## times a second instead of every frame.
func _refresh() -> void:
	if shimmer_px > 0.0:
		queue_redraw() # the wobble animates every frame, so it must repaint
		return
	var a := _quantize(_vis_alpha())
	var s := _quantize(scale.x, 4.0) # the swell is slow and subtle: coarser
	if a != _drawn_alpha or s != _drawn_scale:
		_drawn_alpha = a
		_drawn_scale = s
		queue_redraw()


func _quantize(v: float, steps: float = 10.0) -> float:
	# ~10 alpha steps across a fade: invisible as banding (a step is under
	# 2% of peak alpha), but it is the difference between repainting a ghost
	# every 4 frames and every single one.
	return roundf(v * steps) / steps


## The ghost's alpha envelope: a bright head fading down the tail of the
## ribbon while it holds, then a long tail across the dissolve.
func _vis_alpha() -> float:
	var a := 1.0
	if reeling:
		a = 1.0 - k_ramp() * k_ramp() # long tail across the dissolve
	else:
		a = 1.0 - 0.45 * clampf(_age / maxf(life, 0.01), 0.0, 1.0)
	return a * (1.0 - _dissolve)


func k_ramp() -> float:
	return clampf(_reel_t / maxf(life, 0.01), 0.0, 1.0)


func _draw() -> void:
	draw_calls += 1
	var k := k_ramp() if reeling else 0.0
	var root_alpha := _vis_alpha() * peak_alpha
	var hot := tint * 1.5
	for p in parts:
		var ph: float = p["phase"]
		var part_a := 1.0
		var off := Vector2.ZERO
		if not reeling and shimmer_px > 0.0:
			# Held ghosts shimmer rather than sit dead still, so the freeze
			# frame still reads as a spirit instead of a photograph.
			var w := sin(_t * 6.0 + ph)
			off = Vector2(w, sin(_t * 4.3 + ph * 1.7)) * shimmer_px
			part_a = 0.78 + 0.22 * (0.5 + 0.5 * w)
		var pts: PackedVector2Array = p["pts"]
		if off != Vector2.ZERO:
			var moved := PackedVector2Array()
			moved.resize(pts.size())
			for i in pts.size():
				moved[i] = pts[i] + off
			pts = moved
		var col: Color = p["mod"]
		col = col.lerp(hot, k * 0.65)
		col.a = root_alpha * part_a
		draw_polygon(pts, [col], p["uv"], p["tex"])
