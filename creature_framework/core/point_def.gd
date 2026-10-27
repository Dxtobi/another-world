class_name PointDef
extends Resource
## One Verlet point of a creature's logic skeleton.

@export var name: StringName = &""
@export var offset: Vector2 = Vector2.ZERO   # spawn offset from the creature origin (+x = forward)
@export var mass: float = 1.0
@export var base_depth: float = 0.0          # -1 far side .. +1 near side (read by DepthLayer)
## True when a locomotor may position this point directly and treat it as the spine.
## Generated tail/tentacle points set this false: they hang from their links instead of
## being pinned to a wall line, so a long tail cannot lever the body off a climb.
@export var driven: bool = true
