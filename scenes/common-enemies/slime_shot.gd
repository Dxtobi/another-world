class_name SlimeShot
extends Area2D
## Poison glob lobbed by the ranged enemy. Flies a ballistic arc to a fixed
## destination (dodgeable), with a pulsing red ring telegraphing where it lands.
## Touching the player mid-air starts erosion and consumes the glob; touching
## the floor makes a puddle that keeps eroding for `puddle_life`. Durations are
## the difficulty knobs: 3 s easy, 5 s hard.

enum State { FLY, PUDDLE }

@export_group("Size")
## One-knob sizing: the sprite, the hitbox and (via ring_radius) the warning
## all follow these. Smaller blob = harder to land a direct hit, smaller
## puddle coverage.
@export_range(0.2, 2.0, 0.05) var visual_scale := 0.45
@export_range(2.0, 40.0, 0.5, "suffix:px") var hitbox_radius := 12.0

@export_group("Flight")
@export_range(0.2, 3.0, 0.05, "suffix:s") var max_air_time := 5.0 ## safety: never fly longer
@export_range(0.1, 3.0, 0.1) var gravity_scale := 1.0

@export_group("Poison")
@export_range(1.0, 8.0, 0.5, "suffix:s") var erosion_duration := 4.0
@export_range(1.0, 8.0, 0.5, "suffix:s") var puddle_life := 4.0

@export_group("Warning")
@export_range(8.0, 80.0, 1.0, "suffix:px") var ring_radius := 20.0

@export var sprite: Sprite2D

var grav: float = ProjectSettings.get_setting("physics/2d/default_gravity")
# fall acceleration for the lobbed arc (Area2D already owns `gravity`)

var _state := State.FLY
var _vel := Vector2.ZERO
var _air := 0.0
var _life := 0.0
var _wob := 0.0
var _base_scale := Vector2.ONE
var _ring: LandingRing
var _col: CollisionShape2D


func _ready() -> void:
	if sprite == null:
		sprite = find_child("Sprite2D", true, false) as Sprite2D
	# Own copy of the shape so per-instance hitbox_radius edits never leak
	# across slimes sharing this scene.
	_col = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if _col != null and _col.shape != null:
		_col.shape = _col.shape.duplicate()
	_apply_hitbox()
	add_to_group("slime")


## Lob from `from_world` so it lands on `target_world` after `flight` seconds.
func launch(from_world: Vector2, target_world: Vector2, flight: float) -> void:
	global_position = from_world
	_apply_hitbox() # late edits to hitbox_radius still count
	flight = maxf(flight, 0.05)
	var g := grav * gravity_scale
	_vel = Vector2(
		(target_world.x - from_world.x) / flight,
		(target_world.y - from_world.y - 0.5 * g * flight * flight) / flight)
	_state = State.FLY
	_air = 0.0
	_wob = 0.0
	_base_scale = Vector2.ONE * visual_scale
	if sprite != null:
		sprite.scale = _base_scale
	_ring = LandingRing.new()
	_ring.radius = ring_radius
	get_tree().current_scene.add_child(_ring)
	_ring.global_position = target_world


func _physics_process(delta: float) -> void:
	if _state == State.FLY:
		_air += delta
		_vel.y += grav * gravity_scale * delta
		global_position += _vel * delta
		_wob += delta
		if sprite != null:
			var s := 1.0 + 0.12 * sin(_wob * 18.0)
			sprite.scale = _base_scale * s
		if _air >= max_air_time:
			_despawn()
			return
		for b in get_overlapping_bodies():
			if b != null and b.has_method("apply_erosion"):
				b.apply_erosion(erosion_duration)
				_despawn() # direct hit: consumed, no puddle
				return
			if b is StaticBody2D or b is TileMapLayer or b is AnimatableBody2D:
				_become_puddle()
				return
	else:
		_life -= delta
		if _life <= 0.0:
			_despawn()
			return
		for b in get_overlapping_bodies():
			if b != null and b.has_method("apply_erosion") \
					and b.has_method("is_eroded") and not b.is_eroded():
				b.apply_erosion(erosion_duration)


func _become_puddle() -> void:
	_state = State.PUDDLE
	_life = puddle_life
	_base_scale = Vector2(1.7, 0.5) * visual_scale
	if sprite != null:
		sprite.scale = _base_scale
		sprite.modulate = Color(0.85, 0.95, 0.85)
	_free_ring()


func _despawn() -> void:
	_free_ring()
	queue_free()


func _free_ring() -> void:
	if is_instance_valid(_ring):
		_ring.queue_free()
	_ring = null


## Push hitbox_radius into our private shape copy.
func _apply_hitbox() -> void:
	if _col == null or _col.shape == null:
		return
	var circle := _col.shape as CircleShape2D
	if circle != null:
		circle.radius = hitbox_radius


## Pulsing red ring pinned at the landing spot while the glob is airborne:
## the "incoming!" warning.
class LandingRing extends Node2D:
	var radius := 26.0
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var a := 0.45 + 0.35 * sin(_t * 10.0)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(1.0, 0.2, 0.2, a), 3.0)
		draw_arc(Vector2.ZERO, radius * 0.55, 0.0, TAU, 32, Color(1.0, 0.2, 0.2, a * 0.7), 2.0)
