class_name LimbStyleCatalog
extends RefCounted
## The single source of truth for limb style ids.
##
## A style is how a limb behaves when cosmetics/gait code looks at it: `flap` for a wing,
## `walk2` for a two-bone leg, `tentacle` for a segmented chain. T9 binds the actual
## behaviour; the authoring layer only needs the ids to validate and round-trip them, so a
## style selected in the inspector can never be silently dropped by the bake.
##
## Keep `IDS` in sync with the `@export_enum` list on RigLimb. The authoring test checks
## every baked style against this catalog.

const DEFAULT := &"default"
const IDS: Array[StringName] = [
    &"default", &"flap", &"walk2", &"reach", &"dangle", &"tentacle",
]

## What a style usually means, used by the editor to pre-fill a new limb.
const KIND_HINT: Dictionary = {
    &"default": &"leg",
    &"flap": &"wing",
    &"walk2": &"leg",
    &"reach": &"leg",
    &"dangle": &"leg",
    &"tentacle": &"tentacle",
}

## Suggested bone count for the debug/cosmetic layer. Wings are one span; legs two bones;
## dangly and tentacle parts are chains.
const BONE_HINT: Dictionary = {
    &"default": 1,
    &"flap": 1,
    &"walk2": 2,
    &"reach": 2,
    &"dangle": 3,
    &"tentacle": 6,
}


static func has_style(id: StringName) -> bool:
    return KIND_HINT.has(id)


static func kind_hint(id: StringName) -> StringName:
    return KIND_HINT.get(id, &"leg")


static func bone_hint(id: StringName) -> int:
    return int(BONE_HINT.get(id, 1))


static func ids_text() -> String:
    var parts: PackedStringArray = PackedStringArray()
    for id in IDS:
        parts.append(String(id))
    return ", ".join(parts)
