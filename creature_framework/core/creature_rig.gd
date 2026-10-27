class_name CreatureRig
extends Resource
## A creature defined as DATA. New creature = new rig + a choice of locomotors.

@export var points: Array[PointDef] = []
@export var links: Array[LinkDef] = []
@export var limbs: Array[LimbDef] = []
## Authored tails/tentacles. Their generated points are already appended to `points` and
## joined by `links`; this records which indices belong to which chain.
@export var body_parts: Array[BodyPartDef] = []
@export var front_point: int = 0
@export var center_point: int = 1
@export var rear_point: int = 2
@export var tuning: Dictionary = {}      # StringName -> float, overrides locomotor defaults

## Set by the baker when a tail BodyPart generated the rear chain. `Creature` then skips its
## cosmetic follower tail, so an authored tail is the only tail.
var authored_tail: bool = false

# GDScript classes of the locomotors this creature can use, e.g. [FlyLocomotor, ClimbLocomotor]
var locomotors: Array[GDScript] = []
