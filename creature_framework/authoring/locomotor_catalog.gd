class_name LocomotorCatalog
extends RefCounted
## Maps authored locomotor choices to GDScript classes.
##
## RigBlueprint exposes these as bit flags (`@export_flags("Fly", "Climb")`), so the order
## here and in that annotation are the same contract. Add a new locomotor by adding a bit
## constant and a branch below, then extending the flag list in RigBlueprint.

const FLY := 1
const CLIMB := 2
const VALID_MASK := FLY | CLIMB


## Locomotors selected by `mask`, in the stable order the rig expects: fly first, then
## climb. The order matters for LocoManager's initial mode.
static func from_mask(mask: int) -> Array[GDScript]:
    var scripts: Array[GDScript] = []
    if (mask & FLY) != 0:
        scripts.append(FlyLocomotor)
    if (mask & CLIMB) != 0:
        scripts.append(ClimbLocomotor)
    return scripts


static func valid_mask() -> int:
    return VALID_MASK
