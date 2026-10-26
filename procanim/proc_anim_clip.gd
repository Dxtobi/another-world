@tool
class_name ProcAnimClip
extends Resource
## A named procedural animation, such as "idle" or "walk".

@export var clip_name := "idle":
	set(value):
		clip_name = value
		emit_changed()
@export_range(0.0, 5.0, 0.01, "or_greater") var speed := 1.0
@export var channels: Array[ProcAnimChannel] = []
