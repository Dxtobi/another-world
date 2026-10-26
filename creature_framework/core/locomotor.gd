class_name Locomotor
extends RefCounted
## Base class for one way of moving (fly, climb, crawl, swim...).
## RULE: a locomotor never moves points or limbs directly. It only calls out.add_accel() and
## out.set_limb_target(). That is what makes locomotors blendable and swappable.

var c: Creature
var weight: float = 0.0          # blend weight, driven by LocoManager
var id: StringName = &"base"


## How suited am I right now? Higher wins. Return <= 0 for "cannot do this here".
func score(_intent: Intent) -> float:
    return 0.0


func enter() -> void:
    pass


func exit() -> void:
    pass


func emit(_dt: float, _intent: Intent, _out: MoveOutput) -> void:
    pass
