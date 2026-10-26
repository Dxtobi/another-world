class_name MoveOutput
extends RefCounted
## Everything locomotors want to do this tick. Locomotors never touch the body directly:
## they add accelerations and limb targets here, scaled by their blend weight.

var scale: float = 1.0                       # set by LocoManager before each emit()
var accels: PackedVector2Array = PackedVector2Array()
var _limb_sum: PackedVector2Array = PackedVector2Array()
var _limb_w: PackedFloat32Array = PackedFloat32Array()


func reset(point_count: int, limb_count: int) -> void:
    accels.resize(point_count)
    accels.fill(Vector2.ZERO)
    _limb_sum.resize(limb_count)
    _limb_sum.fill(Vector2.ZERO)
    _limb_w.resize(limb_count)
    _limb_w.fill(0.0)
    scale = 1.0


## Acceleration in px/s^2 on one body point.
func add_accel(point_index: int, a: Vector2) -> void:
    accels[point_index] += a * scale


## World-space target for the tip of one limb. Blended across locomotors by weight.
func set_limb_target(limb_index: int, target: Vector2) -> void:
    _limb_sum[limb_index] += target * scale
    _limb_w[limb_index] += scale


func get_limb_target(limb_index: int, fallback: Vector2) -> Vector2:
    if _limb_w[limb_index] <= 0.0001:
        return fallback
    return _limb_sum[limb_index] / _limb_w[limb_index]
