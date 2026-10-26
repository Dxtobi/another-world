class_name LimbDef
extends Resource
## A limb: wing, leg, tentacle, claw... Anchored to a body point, never simulated itself.
## local_offset is in the SPINE FRAME: +x = forward, +y = belly/down, -y = back/up.

@export var name: StringName = &""
@export var kind: StringName = &"leg"    # &"wing", &"leg", &"tentacle", ...
@export var style: StringName = &"default"  # LimbStyleCatalog id (gait/cosmetic behaviour)
@export var anchor_point: int = 0
@export var local_offset: Vector2 = Vector2.ZERO
@export var reach: float = 40.0
@export var lane: int = 1                # -1 far side, +1 near side
