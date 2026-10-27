class_name BodyPartDef
extends Resource
## A baked tail or tentacle: real body points from the base to the tip.
##
## `points[0]` is the anchor point; the rest are the generated chain points, in order.
## The chain is logic (`PointDef`s joined by `LinkDef`s), so it moves with the solver.
## `kind` is &"tail" or &"tentacle"; it only drives cosmetics and validation.

@export var name: StringName = &""
@export var kind: StringName = &"tail"
@export var points: PackedInt32Array = PackedInt32Array()
