class_name Intent
extends RefCounted
## What the brain wants. Brains WRITE this, locomotors READ it. Nothing else crosses that boundary.

var has_goal: bool = false
var goal: Vector2 = Vector2.ZERO
var desired_speed: float = 1.0   # 0..1 fraction of a locomotor's max speed
var urgency: float = 0.0         # 0 calm .. 1 panicked (locomotors may use it)
var look_dir: Vector2 = Vector2.RIGHT
