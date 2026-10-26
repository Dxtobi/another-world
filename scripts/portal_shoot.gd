class_name PortalShot
extends Node2D
## The projectile a PortalGun fires. One swept raycast per step so it can't
## tunnel. It only reports; the gun decides what a landing means.

signal landed(point: Vector2, normal: Vector2, collider: Object)
signal fizzled

var velocity := Vector2.ZERO
var max_range := 900.0
var mask := 1
var exclude: Array[RID] = []
var color := Color(0.3, 0.8, 1.0)

var _travelled := 0.0
var _age := 0.0


func _physics_process(delta: float) -> void:
	var step := velocity * delta
	var q := PhysicsRayQueryParameters2D.create(global_position, global_position + step, mask)
	q.exclude = exclude
	q.collide_with_areas = false
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		landed.emit(hit.position, hit.normal, hit.collider)
		queue_free()
		return
	global_position += step
	_travelled += step.length()
	if _travelled >= max_range:
		fizzled.emit()
		queue_free()


func _process(delta: float) -> void:
	_age += delta
	queue_redraw()


func _draw() -> void:
	var d := velocity.normalized()
	draw_line(-d * 26.0, Vector2.ZERO, Color(color, 0.35), 5.0)
	draw_circle(Vector2.ZERO, 7.0 + sin(_age * 30.0), Color(color, 0.35))
	draw_circle(Vector2.ZERO, 4.0, color)
