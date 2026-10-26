class_name BulletBurst
extends Node2D
## One-shot impact spray for a plasma bolt hitting something hard.
##
## A handful of glowing shards thrown into the hemisphere around the surface
## normal, pulled down by gravity, fading out over half a second. Drawn in
## code (no texture, no particle system) so it is cheap and deterministic.

var life := 0.6
var gravity := 950.0

var _age := 0.0
var _parts: Array[Dictionary] = []


## `kind` only picks the shard palette: stone dust, pale wall sparks or hot
## metal. `strength` scales count, speed and size.
static func spawn(tree: SceneTree, at: Vector2, normal: Vector2, kind: String,
		strength: float = 1.0) -> BulletBurst:
	if tree == null or tree.current_scene == null:
		return null
	var burst := BulletBurst.new()
	burst._build(normal, kind, clampf(strength, 0.5, 2.0))
	tree.current_scene.add_child(burst)
	burst.global_position = at + normal * 2.0
	return burst


func _build(normal: Vector2, kind: String, strength: float) -> void:
	var base := Color(0.75, 0.68, 0.55) ## floor: warm dust
	if kind == "wall" or kind == "ceiling":
		base = Color(0.72, 0.76, 0.82) ## cool stone sparks
	elif kind == "object":
		base = Color(1.0, 0.62, 0.22) ## hot metal
	var count := 10 + int(round(strength * 6.0))
	for i in count:
		var spread := deg_to_rad(randf_range(22.0, 68.0))
		var dir := normal.rotated(randf_range(-spread, spread))
		var speed := randf_range(110.0, 320.0) * strength
		var col := base.lerp(Color(1.0, 1.0, 1.0), randf_range(0.0, 0.35))
		_parts.append({
			"p": Vector2(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0)),
			"v": dir * speed,
			"r": randf_range(1.0, 2.8) * strength,
			"c": col,
			"drag": randf_range(0.6, 2.0),
		})


func _ready() -> void:
	# Normal alpha blending, not additive: additive shards vanish against the
	# bright sky and the pale water. The streaks are drawn in solid colour so
	# the spray reads on light and dark backdrops alike.
	# Above the terrain and the characters, below the flying bolts (z 10).
	z_index = 4
	z_as_relative = false


func _process(delta: float) -> void:
	_age += delta
	if _age >= life:
		queue_free()
		return
	for part in _parts:
		var v: Vector2 = part["v"]
		v.y += gravity * delta
		v *= maxf(0.0, 1.0 - float(part["drag"]) * delta)
		part["v"] = v
		part["p"] = (part["p"] as Vector2) + v * delta
	queue_redraw()


func _draw() -> void:
	var t := clampf(_age / life, 0.0, 1.0)
	var fade := 1.0 - t
	for part in _parts:
		var p: Vector2 = part["p"]
		var v: Vector2 = part["v"]
		var r := float(part["r"]) * (1.0 - t * 0.55)
		var c: Color = part["c"]
		var dir := v.normalized() if v != Vector2.ZERO else Vector2.UP
		# Short streak along the shard's own velocity: reads as spray rather
		# than a bubble, and stays visible over pale water and bright sky.
		var tail := p - dir * (5.0 + r * 2.0) * (1.0 - t * 0.4)
		draw_line(tail, p, Color(c, 0.30 * fade), r * 1.2)
		draw_line(p - dir * r * 1.8, p, Color(c, 0.95 * fade), r * 0.75)
		if t < 0.35:
			draw_circle(p, r * 0.55, Color(1.0, 1.0, 1.0, (0.35 - t) * 2.4))
