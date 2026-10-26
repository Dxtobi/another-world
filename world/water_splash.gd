extends Node2D
## Short-lived splash accents at the waterline: two travelling crests per ring
## (left/right along the surface) plus a few droplets on entry impacts.
## Spawned in world space by WaterVolume and the player.

## Hard cap on live splash nodes so a crowd of creatures can never flood the
## scene; WaterVolume checks is_full() before spawning wake ripples.
const MAX_LIVE_SPLASHES := 28
static var _live_count := 0

var life := 0.9
var age := 0.0
var strength := 1.0
var alpha_mul := 1.0
var _drops_enabled := true
var _rings: Array[float] = []
var _drops: Array[Dictionary] = []


static func is_full() -> bool:
	return _live_count >= MAX_LIVE_SPLASHES


## `with_drops = false` gives a dropless, longer-lived wake ripple: use it for
## continuous water disturbance (walking/hovering in the surface), keeping the
## droplet-laden splash for real impacts (enter/exit).
func start(p_strength: float, p_alpha: float = 0.9, with_drops: bool = true) -> void:
	strength = clampf(p_strength, 0.2, 2.0)
	alpha_mul = clampf(p_alpha, 0.0, 1.0)
	_drops_enabled = with_drops
	_drops.clear()
	if with_drops:
		life = 0.62 + 0.22 * strength
		_rings = [0.0, 0.16, 0.33]
		var count := int(round(4.0 + 5.0 * strength))
		for i in count:
			var side := -1.0 if i % 2 == 0 else 1.0
			_drops.append({
				"x": side * randf_range(2.0, 16.0),
				"vx": side * randf_range(25.0, 90.0) * strength,
				"vy": -randf_range(70.0, 190.0) * strength,
				"r": randf_range(1.5, 4.0) * minf(strength, 1.5),
			})
	else:
		life = 1.1 + 0.3 * strength
		_rings = [0.0, 0.3]
	_live_count += 1
	# Side-view water: the crest marks must sit in front of the water body
	# (z 0) but behind the characters, which the player lifts to z 5 and the
	# volume lifts creatures to as cutaway figures. z 1 fills that slot without
	# caring what the parent canvas order is.
	z_index = 1
	z_as_relative = false
	_apply_zoom_scale()
	queue_redraw()


func _exit_tree() -> void:
	_live_count -= 1


## Water splashes are drawn in world pixels, so they shrink toward invisibility
## when the camera is far out. Scale the node by the inverse zoom (clamped so
## close-up views never blow the rings up too big). Scaling the node also keeps
## the ring line width readable.
func _apply_zoom_scale() -> void:
	var cam := get_viewport().get_camera_2d()
	var zoom := cam.zoom.x if cam != null else 1.0
	# Gentler than a full 1/zoom so close-up splashes are not oversized; the
	# 8.0 cap covers cameras pulled far back.
	var s := clampf(pow(1.0 / maxf(zoom, 0.01), 0.85), 1.0, 8.0)
	scale = Vector2.ONE * s


func _process(delta: float) -> void:
	age += delta
	if age >= life:
		queue_free()
		return
	_apply_zoom_scale()
	queue_redraw()


func _draw() -> void:
	var t := clampf(age / life, 0.0, 1.0)
	for i in _rings.size():
		var delay: float = _rings[i]
		var rt := clampf((t - delay) / (1.0 - delay), 0.0, 1.0)
		if rt <= 0.0:
			continue
		var travel := lerpf(6.0, 150.0 * strength, 1.0 - pow(1.0 - rt, 2.2))
		var a := pow(1.0 - rt, 1.6) * (0.7 - 0.15 * i) * alpha_mul
		var crest_len := lerpf(10.0, 36.0, rt) * (0.6 + 0.4 * strength)
		var crest_h := lerpf(3.5, 1.0, rt) * (0.6 + 0.4 * strength)
		# Side-on view: a ripple is a disturbance running along the waterline,
		# not a hoop seen from above. Draw one crest per direction, each a lens
		# that starts at the source, tapers away from the front and hugs the
		# surface below it (the calm line rests a few px under the mesh edge,
		# so keep crests low instead of an arch in the air).
		for side_i in 2:
			var side := -1.0 if side_i == 0 else 1.0
			var pts := PackedVector2Array()
			for s in 13:
				var u := float(s) / 12.0
				var x := side * (travel - crest_len * u)
				var y := 2.0 + sin(u * PI) * crest_h
				pts.append(Vector2(x, y))
			draw_polyline(pts, Color(0.02, 0.2, 0.26, a * 0.8), 3.0, true)
			draw_polyline(pts, Color(0.9, 1.0, 1.0, a), 1.4, true)

	if _drops_enabled:
		for d in _drops:
			var dt := minf(age, life)
			var p := Vector2(
				float(d["x"]) + float(d["vx"]) * dt,
				float(d["vy"]) * dt + 0.5 * 620.0 * dt * dt
			)
			if p.y > 0.0:
				continue  # never draw a droplet below the waterline
			var a := (1.0 - t) * 0.9 * alpha_mul
			draw_circle(p, float(d["r"]), Color(0.75, 0.97, 1.0, a))
