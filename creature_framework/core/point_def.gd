class_name PointDef
extends Resource
## One Verlet point of a creature's logic skeleton.

@export var name: StringName = &""
@export var offset: Vector2 = Vector2.ZERO   # spawn offset from the creature origin (+x = forward)
@export var mass: float = 1.0
@export var base_depth: float = 0.0          # -1 far side .. +1 near side (read by DepthLayer)
