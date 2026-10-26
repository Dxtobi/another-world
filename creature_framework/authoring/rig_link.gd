@tool
class_name RigLink
extends Node
## An EXTRA distance constraint between two named points.
##
## Consecutive points are linked automatically by RigBlueprint. Use this node for a
## bend-resist member (front to rear on the vulture) or any other cross-brace. `a`/`b` are
## point node names, not indices, so points can be reordered without breaking the link.

@export var a: StringName = &"front"
@export var b: StringName = &"rear"
@export_range(0.0, 1.0, 0.01) var stiffness: float = 0.15
## <= 0 means "use the rest-pose distance between the two points".
@export var rest_length: float = -1.0
