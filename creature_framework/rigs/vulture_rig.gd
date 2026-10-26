class_name VultureRig
extends RefCounted
## Loads the AUTHORED vulture rig scene and bakes it into a CreatureRig.
##
## The scene (`creatures/vulture.tscn`) is the source of truth: points, masses, links, limbs,
## styles, locomotor choices and tuning are all editable in the inspector. This class stays
## as the small compatibility entry point every dev harness already calls, so no test or
## creature code needs to know about scene loading.

const SCENE_PATH := "res://creature_framework/creatures/vulture.tscn"

static var _cached_scene: PackedScene = null


static func build() -> CreatureRig:
    var packed: PackedScene = _scene()
    if packed == null:
        return null
    var root: Node = packed.instantiate()
    if not (root is RigBlueprint):
        push_error("VultureRig: %s root is not a RigBlueprint" % SCENE_PATH)
        root.free()
        return null
    var blueprint: RigBlueprint = root as RigBlueprint
    var errors: PackedStringArray = blueprint.validate()
    if not errors.is_empty():
        for error in errors:
            push_error("VultureRig: %s" % error)
        root.free()
        return null
    var rig: CreatureRig = blueprint.build_rig()
    root.free()
    return rig


static func _scene() -> PackedScene:
    if _cached_scene == null:
        _cached_scene = load(SCENE_PATH) as PackedScene
    return _cached_scene
