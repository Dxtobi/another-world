class_name CreatureRig
extends Resource
## A creature defined as DATA. New creature = new rig + a choice of locomotors.

@export var points: Array[PointDef] = []
@export var links: Array[LinkDef] = []
@export var limbs: Array[LimbDef] = []
@export var front_point: int = 0
@export var center_point: int = 1
@export var rear_point: int = 2
@export var tuning: Dictionary = {}      # StringName -> float, overrides locomotor defaults

# GDScript classes of the locomotors this creature can use, e.g. [FlyLocomotor, ClimbLocomotor]
var locomotors: Array[GDScript] = []
