@tool
class_name RigBlueprint
extends Node2D
## Authors a CreatureRig as a SCENE instead of a GDScript builder.
##
## Scene layout (see `creatures/vulture.tscn`):
##
##   Vulture (RigBlueprint)
##   ├─ front        (RigPoint, position = rest offset, mass = 1.0)
##   ├─ center       (RigPoint)
##   │  ├─ wing_far  (RigLimb, position = local offset from the anchor point)
##   │  └─ wing_near (RigLimb)
##   ├─ rear         (RigPoint)
##   │  ├─ leg_far   (RigLimb)
##   │  ├─ leg_near  (RigLimb)
##   │  └─ tail      (RigBodyPart, position = aim handle, length = extra points)
##   └─ weak_bend    (RigLink, extra front -> rear constraint)
##
## Consecutive points are linked automatically. A RigLimb must be a direct child of the
## RigPoint it hangs from. A RigBodyPart is also a child of its anchor: it bakes `length`
## extra points and their links, so one node authors a whole tail or tentacle chain.
## `build_rig()` validates and bakes all of it into the same CreatureRig Resource the rest
## of the framework already consumes, so no core code knows whether a rig came from a scene
## or from code.
##
## Only positions are baked. Point/limb/body-part rotation and scale are rejected by
## validate(): the runtime solver owns the transform, and a rest offset is a position, not a
## pose. Extra links join hand-authored points only; generated chain points are linked for
## you.

@export var front_point: StringName = &"front"
@export var center_point: StringName = &"center"
@export var rear_point: StringName = &"rear"

## Bit order is the LocomotorCatalog order. Keep this in sync when adding a locomotor.
@export_flags("Fly", "Climb") var locomotor_flags: int = 3

## Per-creature overrides for locomotor defaults: StringName -> number.
@export var tuning: Dictionary = {}

@export_tool_button("Validate rig", "Check") var validate_action: Callable = _validate_from_editor


func _process(_dt: float) -> void:
    # Editor-only redraw: link lines and the summary follow point drags, limb edits and
    # child add/remove without wiring a notification per property.
    if Engine.is_editor_hint():
        queue_redraw()


## Points in scene order. This order is the baked point index order.
func points() -> Array[RigPoint]:
    var out: Array[RigPoint] = []
    for child in get_children():
        if child is RigPoint:
            out.append(child as RigPoint)
    return out


## Every validly parented limb, in baked order: point order, then child order.
func limbs() -> Array[RigLimb]:
    var out: Array[RigLimb] = []
    for point in points():
        for child in point.get_children():
            if child is RigLimb:
                out.append(child as RigLimb)
    return out


func extra_links() -> Array[RigLink]:
    var out: Array[RigLink] = []
    for child in get_children():
        if child is RigLink:
            out.append(child as RigLink)
    return out


## Every validly parented tail/tentacle, in baked order: point order, then child order.
func body_parts() -> Array[RigBodyPart]:
    var out: Array[RigBodyPart] = []
    for point in points():
        for child in point.get_children():
            if child is RigBodyPart:
                out.append(child as RigBodyPart)
    return out


## Human-readable problems, or an empty array when the scene can be baked. build_rig()
## refuses to return a partial rig when this is non-empty.
func validate() -> PackedStringArray:
    var errors: PackedStringArray = PackedStringArray()
    var pts: Array[RigPoint] = points()
    if pts.size() < 3:
        errors.append("a rig needs at least 3 points (front, centre, rear)")

    var names: Dictionary = {}
    for point in pts:
        var key: StringName = StringName(point.name)
        if String(key).is_empty():
            errors.append("a point has an empty name")
        elif names.has(key):
            errors.append("duplicate point name '%s'" % key)
        names[key] = true
        if point.mass <= 0.0:
            errors.append("point '%s' mass must be > 0 (got %.3f)" % [key, point.mass])
        if point.base_depth < -1.0 or point.base_depth > 1.0 or not is_finite(point.base_depth):
            errors.append("point '%s' base_depth must be -1..+1 (got %.3f)" % [key, point.base_depth])
        if not point.position.is_finite():
            errors.append("point '%s' position is not finite" % key)
        if not is_zero_approx(point.rotation) or not point.scale.is_equal_approx(Vector2.ONE):
            errors.append("point '%s' has rotation/scale; only position is baked" % key)

    var required: Array[StringName] = [front_point, center_point, rear_point]
    for key in required:
        if String(key).is_empty():
            errors.append("front/centre/rear point names must all be set")
        elif not names.has(key):
            errors.append("required point '%s' does not exist" % key)
    if front_point == center_point or front_point == rear_point or center_point == rear_point:
        errors.append("front, centre and rear must be three different points")

    var all_limbs: Array[RigLimb] = []
    _find_limbs(self, all_limbs)
    var limb_names: Dictionary = {}
    for limb in all_limbs:
        var key: StringName = StringName(limb.name)
        if String(key).is_empty():
            errors.append("a limb has an empty name")
        elif limb_names.has(key):
            errors.append("duplicate limb name '%s'" % key)
        limb_names[key] = true
        if not (limb.get_parent() is RigPoint):
            errors.append("limb '%s' must be a direct child of a RigPoint" % key)
        if String(limb.kind).is_empty():
            errors.append("limb '%s' has no kind" % key)
        if not LimbStyleCatalog.has_style(StringName(limb.style)):
            errors.append("limb '%s' style '%s' is unknown (valid: %s)" % [
                key, limb.style, LimbStyleCatalog.ids_text()])
        if limb.lane == 0:
            errors.append("limb '%s' lane must be -1 (far) or +1 (near)" % key)
        if limb.reach <= 0.0:
            errors.append("limb '%s' reach must be > 0" % key)
        if not limb.position.is_finite():
            errors.append("limb '%s' position is not finite" % key)
        if not is_zero_approx(limb.rotation) or not limb.scale.is_equal_approx(Vector2.ONE):
            errors.append("limb '%s' has rotation/scale; only position is baked" % key)

    var all_parts: Array[RigBodyPart] = []
    _find_body_parts(self, all_parts)
    var part_names: Dictionary = {}
    var chain_names: Dictionary = {}
    for part in all_parts:
        var key: StringName = StringName(part.name)
        if String(key).is_empty():
            errors.append("a body part has an empty name")
        elif part_names.has(key):
            errors.append("duplicate body part name '%s'" % key)
        part_names[key] = true

        var anchor: Node = part.get_parent()
        if not (anchor is RigPoint):
            errors.append("body part '%s' must be a direct child of a RigPoint" % key)
        elif not pts.has(anchor):
            errors.append("body part '%s' hangs from a RigPoint that is not a direct child of the rig" % key)
        if not (StringName(part.kind) in [&"tail", &"tentacle"]):
            errors.append("body part '%s' kind '%s' is unknown (valid: tail, tentacle)" % [
                key, part.kind])
        if part.length < 1:
            errors.append("body part '%s' length must be at least 1 extra point (got %d)" % [
                key, part.length])
        if part.spacing <= 0.0 or not is_finite(part.spacing):
            errors.append("body part '%s' spacing must be finite and > 0 (got %.2f)" % [
                key, part.spacing])
        if part.base_mass <= 0.0 or part.tip_mass <= 0.0:
            errors.append("body part '%s' masses must be > 0 (base %.2f, tip %.2f)" % [
                key, part.base_mass, part.tip_mass])
        if not part.position.is_finite() or not part.direction.is_finite():
            errors.append("body part '%s' position/direction is not finite" % key)
        if part.auto_direction and part.position.length_squared() <= 0.000001 \
                and part.direction.length_squared() <= 0.000001:
            errors.append("body part '%s' has no direction (move the node or set direction)" % key)
        if not is_zero_approx(part.rotation) or not part.scale.is_equal_approx(Vector2.ONE):
            errors.append("body part '%s' has rotation/scale; only position is baked" % key)

        for i in range(1, maxi(part.length, 0) + 1):
            var chain_key: StringName = part.point_name(i)
            if names.has(chain_key):
                errors.append("body part '%s' generates point '%s', which collides with an authored point" % [
                    key, chain_key])
            elif chain_names.has(chain_key):
                errors.append("body part '%s' generates duplicate point '%s'" % [key, chain_key])
            chain_names[chain_key] = true

    for link in extra_links():
        if not names.has(link.a):
            errors.append("link point '%s' does not exist" % link.a)
        if not names.has(link.b):
            errors.append("link point '%s' does not exist" % link.b)
        if link.a == link.b:
            errors.append("link '%s' -> '%s' links a point to itself" % [link.a, link.b])
        if link.stiffness < 0.0 or link.stiffness > 1.0:
            errors.append("link '%s' -> '%s' stiffness must be 0..1" % [link.a, link.b])
        if link.rest_length > 0.0 and not is_finite(link.rest_length):
            errors.append("link '%s' -> '%s' rest_length is not finite" % [link.a, link.b])

    if locomotor_flags == 0:
        errors.append("select at least one locomotor")
    var unknown_bits: int = locomotor_flags & ~LocomotorCatalog.valid_mask()
    if unknown_bits != 0:
        errors.append("unknown locomotor flag bits 0x%x" % unknown_bits)

    for key in tuning:
        var value: Variant = tuning[key]
        if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
            errors.append("tuning[%s] must be a number" % str(key))
        elif not is_finite(float(value)):
            errors.append("tuning[%s] must be finite" % str(key))

    return errors


## Bake the scene into the data Resource the framework consumes. Returns null (without
## logging) when validate() reports a problem; callers decide how loudly to fail.
func build_rig() -> CreatureRig:
    if not validate().is_empty():
        return null

    var pts: Array[RigPoint] = points()
    var rig: CreatureRig = CreatureRig.new()
    var index: Dictionary = {}

    for i in pts.size():
        var point: RigPoint = pts[i]
        var def: PointDef = PointDef.new()
        def.name = StringName(point.name)
        def.offset = point.position
        def.mass = point.mass
        def.base_depth = point.base_depth
        rig.points.append(def)
        index[def.name] = i

    rig.front_point = int(index[front_point])
    rig.center_point = int(index[center_point])
    rig.rear_point = int(index[rear_point])

    # Consecutive spine links: full stiffness, exact rest-pose length.
    for i in range(1, pts.size()):
        rig.links.append(_link(i - 1, i,
            pts[i - 1].position.distance_to(pts[i].position), 1.0))

    # Explicit cross-braces (weak bend-resist links etc.).
    for extra in extra_links():
        var a: int = int(index[extra.a])
        var b: int = int(index[extra.b])
        var rest: float = extra.rest_length if extra.rest_length > 0.0 \
            else pts[a].position.distance_to(pts[b].position)
        rig.links.append(_link(a, b, rest, extra.stiffness))

    # Limbs are baked in point order, then child order. For the vulture that is
    # wing_far, wing_near, leg_far, leg_near.
    for i in pts.size():
        for child in pts[i].get_children():
            if not (child is RigLimb):
                continue
            var limb: RigLimb = child as RigLimb
            var def: LimbDef = LimbDef.new()
            def.name = StringName(limb.name)
            def.kind = StringName(limb.kind)
            def.style = StringName(limb.style)
            def.anchor_point = i
            def.local_offset = limb.position
            def.reach = limb.reach
            def.lane = limb.lane
            rig.limbs.append(def)

    # Authored tails/tentacles. Generated points are appended AFTER every authored point so
    # hand-authored indices never move, and each link run starts at the chain's anchor.
    for part in body_parts():
        var anchor_node: RigPoint = part.get_parent() as RigPoint
        var anchor_index: int = int(index[StringName(anchor_node.name)])
        var base: Vector2 = anchor_node.position
        var chain: PackedInt32Array = PackedInt32Array()
        chain.append(anchor_index)
        var prev: int = anchor_index
        var prev_offset: Vector2 = base
        for k in range(1, part.length + 1):
            var point_def: PointDef = PointDef.new()
            point_def.name = part.point_name(k)
            point_def.offset = base + part.point_offset(k)
            point_def.mass = part.point_mass(k)
            point_def.base_depth = anchor_node.base_depth
            point_def.driven = false
            rig.points.append(point_def)
            var idx: int = rig.points.size() - 1
            index[point_def.name] = idx
            rig.links.append(_link(prev, idx, prev_offset.distance_to(point_def.offset), 1.0))
            chain.append(idx)
            prev = idx
            prev_offset = point_def.offset

        var body: BodyPartDef = BodyPartDef.new()
        body.name = StringName(part.name)
        body.kind = StringName(part.kind)
        body.points = chain
        rig.body_parts.append(body)
        if body.kind == &"tail":
            rig.authored_tail = true

    var tuning_copy: Dictionary = tuning.duplicate(true)
    rig.tuning = tuning_copy
    rig.locomotors = LocomotorCatalog.from_mask(locomotor_flags)
    return rig


## Load a rig SCENE and bake it, logging exactly which rules it broke.
##
## This is the no-code entry point: a dev scene only needs a scene path (`dev/playground.tscn`
## exports one), and every harness keeps its own one-line wrapper (`VultureRig.build()`).
## `fresh` bypasses the resource cache so the playground can pick up a scene just saved in the
## editor without restarting the game.
static func load_rig(scene_path: String, fresh: bool = false) -> CreatureRig:
    var cache_mode: int = ResourceLoader.CACHE_MODE_REUSE
    if fresh:
        cache_mode = ResourceLoader.CACHE_MODE_IGNORE
    var packed: PackedScene = ResourceLoader.load(scene_path, "", cache_mode) as PackedScene
    if packed == null:
        push_error("RigBlueprint: cannot load '%s'" % scene_path)
        return null

    var root: Node = packed.instantiate()
    if not (root is RigBlueprint):
        push_error("RigBlueprint: '%s' root is not a RigBlueprint" % scene_path)
        root.free()
        return null

    var blueprint: RigBlueprint = root as RigBlueprint
    var errors: PackedStringArray = blueprint.validate()
    if not errors.is_empty():
        for error in errors:
            push_error("RigBlueprint '%s': %s" % [scene_path.get_file(), error])
        root.free()
        return null

    var rig: CreatureRig = blueprint.build_rig()
    root.free()
    return rig


func _validate_from_editor() -> void:
    var errors: PackedStringArray = validate()
    if errors.is_empty():
        print("RigBlueprint '%s': OK (%d points, %d limbs, %d body parts)" % [
            name, points().size(), limbs().size(), body_parts().size()])
        return
    for error in errors:
        push_error("RigBlueprint '%s': %s" % [name, error])


func _link(a: int, b: int, rest_length: float, stiffness: float) -> LinkDef:
    var link: LinkDef = LinkDef.new()
    link.a = a
    link.b = b
    link.rest_length = rest_length
    link.stiffness = stiffness
    return link


func _find_limbs(node: Node, out: Array[RigLimb]) -> void:
    for child in node.get_children():
        if child is RigLimb:
            out.append(child as RigLimb)
        _find_limbs(child, out)


func _find_body_parts(node: Node, out: Array[RigBodyPart]) -> void:
    for child in node.get_children():
        if child is RigBodyPart:
            out.append(child as RigBodyPart)
        _find_body_parts(child, out)


func _point_by_name(key: StringName) -> RigPoint:
    for point in points():
        if StringName(point.name) == key:
            return point
    return null


func _locomotor_text() -> String:
    var parts: PackedStringArray = PackedStringArray()
    if (locomotor_flags & LocomotorCatalog.FLY) != 0:
        parts.append("fly")
    if (locomotor_flags & LocomotorCatalog.CLIMB) != 0:
        parts.append("climb")
    return ", ".join(parts) if not parts.is_empty() else "none"


func _draw() -> void:
    if not Engine.is_editor_hint():
        return
    var pts: Array[RigPoint] = points()
    if pts.is_empty():
        return
    var link_col: Color = Color(0.50, 0.65, 0.90, 0.65)
    for i in range(1, pts.size()):
        draw_line(pts[i - 1].position, pts[i].position, link_col, 2.0)
    for link in extra_links():
        var a: RigPoint = _point_by_name(link.a)
        var b: RigPoint = _point_by_name(link.b)
        if a != null and b != null:
            draw_dashed_line(a.position, b.position, Color(0.45, 1.0, 0.65, 0.45), 1.0, 6.0)

    # Origin marker: the creature's spawn/rest origin, not a point.
    draw_line(Vector2(-9.0, 0.0), Vector2(9.0, 0.0), Color(0.6, 0.6, 0.7, 0.5), 1.0)
    draw_line(Vector2(0.0, -9.0), Vector2(0.0, 9.0), Color(0.6, 0.6, 0.7, 0.5), 1.0)

    # Header sits over the middle of the rig (limbs included) so it stays attached to the
    # creature instead of drifting off when points move.
    var bounds: Rect2 = _bounds(pts)
    var mid: float = bounds.position.x + bounds.size.x * 0.5
    var parts_suffix: String = ""
    if not body_parts().is_empty():
        parts_suffix = "  ·  %d parts" % body_parts().size()
    RigDraw.text(self, Vector2(mid, bounds.position.y - 24.0),
        "%s  ·  %d points  ·  %d limbs%s  ·  %s" % [
            name, pts.size(), limbs().size(), parts_suffix, _locomotor_text()],
        12, Color(0.80, 0.90, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
    RigDraw.text(self, Vector2(mid, bounds.position.y - 10.0),
        "RigBlueprint — points, limbs on their anchor, a BodyPart for each tail",
        10, Color(0.60, 0.70, 0.85, 0.8), HORIZONTAL_ALIGNMENT_CENTER)


## Bounding box of the rest pose, limb reach and body-part chains included. Used to place
## the header.
func _bounds(pts: Array[RigPoint]) -> Rect2:
    var box: Rect2 = Rect2(pts[0].position, Vector2.ZERO)
    for point in pts:
        box = box.expand(point.position)
        for child in point.get_children():
            if child is RigLimb:
                var limb: RigLimb = child as RigLimb
                var origin: Vector2 = point.position + limb.position
                box = box.expand(origin)
                box = box.expand(origin + Vector2(0.0, limb.reach))
            elif child is RigBodyPart:
                var part: RigBodyPart = child as RigBodyPart
                for k in range(1, part.length + 1):
                    box = box.expand(point.position + part.point_offset(k))
    return box

