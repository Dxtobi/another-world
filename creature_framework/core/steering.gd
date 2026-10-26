class_name Steering
extends RefCounted
## Small stateless helpers shared by locomotors.


## "Arrive" steering: accelerate toward target, slow down inside slow_radius. Returns an acceleration.
static func arrive(p: Vector2, vel: Vector2, target: Vector2, max_speed: float, max_accel: float, slow_radius: float = 80.0) -> Vector2:
    var to_target: Vector2 = target - p
    var dist: float = to_target.length()
    if dist < 0.001:
        return (-vel).limit_length(max_accel)
    var desired: Vector2 = to_target / dist * max_speed * clampf(dist / slow_radius, 0.0, 1.0)
    return (desired - vel).limit_length(max_accel)


## Frame-rate independent smoothing toward a target. Use this instead of assigning values directly.
static func damp_f(current: float, target: float, rate: float, dt: float) -> float:
    return lerpf(current, target, 1.0 - exp(-rate * dt))


static func damp_v(current: Vector2, target: Vector2, rate: float, dt: float) -> Vector2:
    return current.lerp(target, 1.0 - exp(-rate * dt))
