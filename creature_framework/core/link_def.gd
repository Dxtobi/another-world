class_name LinkDef
extends Resource
## Distance constraint between two points.

@export var a: int = 0
@export var b: int = 1
@export var rest_length: float = -1.0   # <= 0 means "use the spawn distance"
@export var stiffness: float = 1.0      # 0..1, how hard the solver corrects per iteration
