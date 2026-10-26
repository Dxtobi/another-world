class_name VultureRig
extends RefCounted
## Compatibility entry point: every harness calls `VultureRig.build()`.
##
## The rig itself lives in `creatures/vulture.tscn` (the source of truth). This class is just
## a stable name for "the vulture", so no test or creature code has to know about scene paths.
## A new creature does not need a class like this — point `dev/playground.tscn` at its scene,
## or call `RigBlueprint.load_rig()` directly.

const SCENE_PATH := "res://creature_framework/creatures/vulture.tscn"


static func build() -> CreatureRig:
    return RigBlueprint.load_rig(SCENE_PATH)
