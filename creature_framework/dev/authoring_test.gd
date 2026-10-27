extends Node2D
## Authoring acceptance harness. Run headless:
##   godot --headless --path . res://creature_framework/dev/authoring_test.tscn
##
## Proves the authored vulture scene bakes to the same rig the framework used before:
##   * the scene loads as a RigBlueprint and validates clean,
##   * points, masses, consecutive links, the extra weak link, limbs, anchors, styles,
##     front/centre/rear and locomotor order all match the vulture reference values,
##   * editing a node changes the baked rig (the scene is the source of truth, not code),
##   * missing points / bad styles / lane 0 / orphan limbs / self links are rejected,
##   * VultureRig.build() loads the scene and a creature using it moves without NaNs.
##
## Prints "AUTHORING SUMMARY ..." and exits non-zero on failure.

const SCENE := "res://creature_framework/creatures/vulture.tscn"

var fails: PackedStringArray = PackedStringArray()
var notes: PackedStringArray = PackedStringArray()
var checks: int = 0


class GoalBrain extends Brain:
    var goal: Vector2 = Vector2.ZERO

    func think(creature: Creature, intent: Intent, _dt: float) -> void:
        intent.has_goal = true
        intent.goal = goal
        intent.desired_speed = 1.0
        var d: Vector2 = goal - creature.body.pos[creature.rig.center_point]
        intent.look_dir = d.normalized() if d.length_squared() > 0.01 else Vector2.RIGHT


func _ready() -> void:
    _check_scene()
    _check_loader()
    _check_mutation()
    _check_validation()
    _check_body_parts()
    await _check_runtime()
    await _check_runtime_tail()
    _report()


# ---------------------------------------------------------------- scene bake

func _check_scene() -> void:
    var bp: RigBlueprint = _fresh()
    _expect(bp != null, "scene instantiates as a RigBlueprint")
    if bp == null:
        return

    var pts: Array[RigPoint] = bp.points()
    var limbs: Array[RigLimb] = bp.limbs()
    var links: Array[RigLink] = bp.extra_links()
    notes.append("scene points=%d limbs=%d extra_links=%d" % [
        pts.size(), limbs.size(), links.size()])
    _expect(pts.size() == 3, "scene has 3 points")
    _expect(limbs.size() == 4, "scene has 4 limbs")
    _expect(links.size() == 1, "scene has 1 extra link")

    var errors: PackedStringArray = bp.validate()
    _expect(errors.is_empty(), "scene validates clean (%s)" % ", ".join(errors))
    if not errors.is_empty():
        bp.free()
        return

    var rig: CreatureRig = bp.build_rig()
    _expect(rig != null, "scene bakes a CreatureRig")
    if rig == null:
        bp.free()
        return

    _expect(rig.points.size() == 3, "baked 3 points")
    _expect(rig.links.size() == 3, "baked 3 links (2 spine + 1 brace)")
    _expect(rig.limbs.size() == 4, "baked 4 limbs")
    _expect(rig.front_point == 0 and rig.center_point == 1 and rig.rear_point == 2,
        "baked front/centre/rear indices are 0/1/2")
    _expect(rig.tuning.is_empty(), "baked tuning is empty")
    _expect(rig.locomotors.size() == 2, "baked 2 locomotors")
    if rig.locomotors.size() == 2:
        _expect(rig.locomotors[0] == FlyLocomotor and rig.locomotors[1] == ClimbLocomotor,
            "locomotor order is Fly then Climb")

    var p_names: Array[StringName] = [&"front", &"center", &"rear"]
    var p_offsets: Array[Vector2] = [Vector2(40.0, 0.0), Vector2.ZERO, Vector2(-40.0, 0.0)]
    var p_mass: Array[float] = [1.0, 1.5, 1.0]
    for i in 3:
        var p: PointDef = rig.points[i]
        _expect(p.name == p_names[i] and p.offset.is_equal_approx(p_offsets[i])
            and is_equal_approx(p.mass, p_mass[i]) and is_zero_approx(p.base_depth),
            "point %d is %s offset %s mass %.1f" % [i, p.name, str(p.offset), p.mass])

    var l_a: Array[int] = [0, 1, 0]
    var l_b: Array[int] = [1, 2, 2]
    var l_rest: Array[float] = [40.0, 40.0, 80.0]
    var l_stiff: Array[float] = [1.0, 1.0, 0.15]
    for k in 3:
        var link: LinkDef = rig.links[k]
        _expect(link.a == l_a[k] and link.b == l_b[k]
            and is_equal_approx(link.rest_length, l_rest[k])
            and is_equal_approx(link.stiffness, l_stiff[k]),
            "link %d is %d->%d rest %.0f stiffness %.2f" % [
                k, link.a, link.b, link.rest_length, link.stiffness])

    var lm_names: Array[StringName] = [&"wing_far", &"wing_near", &"leg_far", &"leg_near"]
    var lm_kind: Array[StringName] = [&"wing", &"wing", &"leg", &"leg"]
    var lm_style: Array[StringName] = [&"flap", &"flap", &"walk2", &"walk2"]
    var lm_anchor: Array[int] = [1, 1, 2, 2]
    var lm_offset: Array[Vector2] = [
        Vector2(2.0, -7.0), Vector2(2.0, -7.0), Vector2(-4.0, 5.0), Vector2(1.0, 8.0)]
    var lm_reach: Array[float] = [95.0, 95.0, 55.0, 55.0]
    var lm_lane: Array[int] = [-1, 1, -1, 1]
    for i in 4:
        var limb: LimbDef = rig.limbs[i]
        _expect(limb.name == lm_names[i] and limb.kind == lm_kind[i]
            and limb.style == lm_style[i] and limb.anchor_point == lm_anchor[i]
            and limb.local_offset.is_equal_approx(lm_offset[i])
            and is_equal_approx(limb.reach, lm_reach[i]) and limb.lane == lm_lane[i],
            "limb %d is %s %s/%s anchor %d reach %.0f lane %d" % [
                i, limb.name, limb.kind, limb.style, limb.anchor_point, limb.reach, limb.lane])
        _expect(LimbStyleCatalog.has_style(limb.style), "style %s is in the catalog" % limb.style)

    _expect(LimbStyleCatalog.IDS.size() == 6, "limb style catalog has 6 ids")
    _expect(LimbStyleCatalog.bone_hint(&"walk2") == 2, "walk2 style hints 2 bones")
    _expect(LimbStyleCatalog.bone_hint(&"tentacle") == 6, "tentacle style hints 6 bones")

    bp.free()


# ---------------------------------------------------------------- scene loader

func _check_loader() -> void:
    var rig: CreatureRig = RigBlueprint.load_rig(SCENE)
    _expect(rig != null, "RigBlueprint.load_rig() loads the authored scene")
    if rig == null:
        return
    _expect(rig.points.size() == 3 and rig.limbs.size() == 4,
        "load_rig() returns the baked scene rig")
    _expect(rig.locomotors.size() == 2, "load_rig() keeps the locomotor choices")


# ---------------------------------------------------------------- source of truth

func _check_mutation() -> void:
    var bp: RigBlueprint = _fresh()
    _expect(bp != null, "fresh scene for mutation test")
    if bp == null:
        return

    var rear: RigPoint = bp.points()[2]
    rear.position = Vector2(-55.0, 0.0)
    rear.mass = 2.2
    var wing: RigLimb = bp.limbs()[0]
    wing.reach = 120.0
    wing.style = "reach"

    var rig: CreatureRig = bp.build_rig()
    _expect(rig != null, "mutated scene still bakes")
    if rig != null:
        _expect(rig.points[2].offset.is_equal_approx(Vector2(-55.0, 0.0))
            and is_equal_approx(rig.points[2].mass, 2.2),
            "point edit reaches the bake (offset -55, mass 2.2)")
        _expect(is_equal_approx(rig.links[1].rest_length, 55.0),
            "edited point distance becomes the link rest length (55)")
        _expect(is_equal_approx(rig.links[2].rest_length, 95.0),
            "brace rest length follows the edited point (95)")
        _expect(is_equal_approx(rig.limbs[0].reach, 120.0) and rig.limbs[0].style == &"reach",
            "limb edit reaches the bake (reach 120, style reach)")
    bp.free()


# ---------------------------------------------------------------- validation

func _check_validation() -> void:
    var bad: RigBlueprint = _fresh()
    if bad == null:
        _expect(false, "fresh scene for validation tests")
        return

    bad.front_point = &"missing"
    _expect(not bad.validate().is_empty(), "missing front point is rejected")
    _expect(bad.build_rig() == null, "an invalid rig refuses to bake")
    bad.free()

    bad = _fresh()
    bad.limbs()[0].style = "bogus"
    _expect(not bad.validate().is_empty(), "unknown limb style is rejected")
    bad.free()

    bad = _fresh()
    bad.limbs()[0].lane = 0
    _expect(not bad.validate().is_empty(), "lane 0 is rejected")
    bad.free()

    bad = _fresh()
    var orphan: RigLimb = RigLimb.new()
    orphan.name = "orphan"
    bad.add_child(orphan)
    _expect(not bad.validate().is_empty(), "a limb outside a point is rejected")
    bad.free()

    bad = _fresh()
    bad.extra_links()[0].b = &"front"
    _expect(not bad.validate().is_empty(), "a self link is rejected")
    bad.free()

    bad = _fresh()
    bad.locomotor_flags = 0
    _expect(not bad.validate().is_empty(), "no locomotor is rejected")
    bad.free()


# ---------------------------------------------------------------- body parts

## One RigBodyPart authors a whole chain: `length` extra points, their links, mass falloff
## and a baked BodyPartDef. The tail is real logic, and the rig flags that so the creature
## does not also grow its cosmetic follower tail.
func _check_body_parts() -> void:
    var bp: RigBlueprint = _fresh()
    if bp == null:
        _expect(false, "fresh scene for body-part tests")
        return

    var part: RigBodyPart = _add_part(bp, 2, "tail")
    part.kind = "tail"
    part.length = 4
    part.spacing = 10.0
    part.base_mass = 0.9
    part.tip_mass = 0.4

    _expect(bp.body_parts().size() == 1, "a BodyPart under a point is collected")
    _expect(bp.limbs().size() == 4, "a BodyPart is not baked as a limb")
    var errors: PackedStringArray = bp.validate()
    _expect(errors.is_empty(), "authored tail validates clean (%s)" % ", ".join(errors))

    # Preview geometry: the node's position is the aim handle, not an offset.
    _expect(part.rest_dir().is_equal_approx(Vector2.LEFT),
        "auto direction aims along the node position")
    _expect(part.point_offset(1).is_equal_approx(Vector2(-10.0, 0.0))
        and part.point_offset(4).is_equal_approx(Vector2(-40.0, 0.0)),
        "preview points step one spacing per extra point")
    _expect(part.point_name(2) == &"tail_2", "generated point names are name_index")
    _expect(is_equal_approx(part.point_mass(1), 0.9)
        and is_equal_approx(part.point_mass(4), 0.4),
        "preview mass falls off base -> tip")

    var rig: CreatureRig = bp.build_rig()
    _expect(rig != null, "authored tail bakes")
    if rig == null:
        bp.free()
        return

    notes.append("tail points=%d links=%d parts=%d" % [
        rig.points.size(), rig.links.size(), rig.body_parts.size()])
    _expect(rig.points.size() == 7, "tail appends 4 extra points after the 3 authored ones")
    _expect(rig.links.size() == 7, "tail appends 4 links (chain from the rear point)")
    _expect(rig.limbs.size() == 4, "tail leaves the limb list alone")
    _expect(rig.authored_tail, "a tail BodyPart marks the rig as tail-authored")

    var tail_names: Array[StringName] = [&"tail_1", &"tail_2", &"tail_3", &"tail_4"]
    var tail_offsets: Array[float] = [-50.0, -60.0, -70.0, -80.0]
    for k in 4:
        var p: PointDef = rig.points[3 + k]
        _expect(p.name == tail_names[k] and is_equal_approx(p.offset.x, tail_offsets[k])
            and is_zero_approx(p.offset.y) and is_zero_approx(p.base_depth),
            "tail point %s is at x %.0f" % [p.name, p.offset.x])
    _expect(is_equal_approx(rig.points[3].mass, 0.9)
        and is_equal_approx(rig.points[6].mass, 0.4),
        "tail masses fall off into the bake (0.90 -> 0.40)")

    var tail_links: Array[Vector2i] = [
        Vector2i(2, 3), Vector2i(3, 4), Vector2i(4, 5), Vector2i(5, 6)]
    for k in 4:
        var link: LinkDef = rig.links[3 + k]
        _expect(link.a == tail_links[k].x and link.b == tail_links[k].y
            and is_equal_approx(link.rest_length, 10.0)
            and is_equal_approx(link.stiffness, 1.0),
            "tail link %d is %d->%d rest 10" % [k, link.a, link.b])

    _expect(rig.body_parts.size() == 1, "baked one body part")
    if rig.body_parts.size() == 1:
        var baked: BodyPartDef = rig.body_parts[0]
        _expect(baked.name == &"tail" and baked.kind == &"tail",
            "body part keeps its name and kind")
        var chain: Array[int] = [2, 3, 4, 5, 6]
        var chain_ok: bool = baked.points.size() == chain.size()
        for k in mini(baked.points.size(), chain.size()):
            chain_ok = chain_ok and baked.points[k] == chain[k]
        _expect(chain_ok, "body part records anchor -> tip indices %s" % str(chain))

    # A tentacle is the same generated chain, but it is not the creature's tail.
    part.kind = "tentacle"
    var tentacle: CreatureRig = bp.build_rig()
    _expect(tentacle != null and not tentacle.authored_tail
        and tentacle.body_parts[0].kind == &"tentacle",
        "a tentacle bakes a chain without becoming the authored tail")
    bp.free()

    _check_body_part_validation()


func _check_body_part_validation() -> void:
    var bad: RigBlueprint = _fresh()
    if bad == null:
        _expect(false, "fresh scene for body-part validation")
        return

    var part: RigBodyPart = _add_part(bad, 2, "tail")
    part.length = 0
    _expect(not bad.validate().is_empty(), "body part length 0 is rejected")
    bad.free()

    bad = _fresh()
    part = _add_part(bad, 2, "tail")
    part.spacing = 0.0
    _expect(not bad.validate().is_empty(), "body part spacing 0 is rejected")
    bad.free()

    bad = _fresh()
    part = RigBodyPart.new()
    part.name = "orphan"
    bad.add_child(part)
    _expect(not bad.validate().is_empty(), "a body part outside a point is rejected")
    bad.free()

    bad = _fresh()
    var clash: RigPoint = RigPoint.new()
    clash.name = "tail_1"
    clash.position = Vector2(0.0, -30.0)
    bad.add_child(clash)
    _add_part(bad, 2, "tail")
    _expect(not bad.validate().is_empty(), "a generated name that collides with a point is rejected")
    bad.free()

    bad = _fresh()
    _add_part(bad, 2, "tail")
    var second: RigBodyPart = RigBodyPart.new()
    second.name = "tail"
    second.position = Vector2(0.0, 1.0)
    bad.points()[1].add_child(second)
    _expect(not bad.validate().is_empty(), "two body parts with the same name are rejected")
    bad.free()

    bad = _fresh()
    part = _add_part(bad, 2, "tail")
    part.position = Vector2.ZERO
    part.direction = Vector2.ZERO
    _expect(not bad.validate().is_empty(), "a body part with no direction is rejected")
    bad.free()

    bad = _fresh()
    part = _add_part(bad, 2, "tail")
    part.rotation = 0.4
    _expect(not bad.validate().is_empty(), "body part rotation/scale is rejected")
    bad.free()

    bad = _fresh()
    part = _add_part(bad, 2, "tail")
    part.kind = "fin"
    _expect(not bad.validate().is_empty(), "an unknown body-part kind is rejected")
    bad.free()


# ---------------------------------------------------------------- runtime

func _check_runtime() -> void:
    var rig: CreatureRig = VultureRig.build()
    _expect(rig != null, "VultureRig.build() loads the authored scene")
    if rig == null:
        return
    _expect(rig.points.size() == 3 and rig.limbs.size() == 4,
        "loader returns the baked scene rig")

    var c: Creature = Creature.new()
    add_child(c)
    var brain: GoalBrain = GoalBrain.new()
    brain.goal = Vector2(650.0, 300.0)
    var world: WorldQuery = WorldQuery.new()
    world.bounds = Rect2(0.0, 0.0, 900.0, 600.0)
    c.setup(rig, brain, world, Vector2(200.0, 300.0))

    var start: Vector2 = c.body.pos[c.rig.center_point]
    var bad_points: int = 0
    for _i in 150:
        await get_tree().physics_frame
        for p in c.body.pos:
            if not p.is_finite():
                bad_points += 1

    var moved: float = start.distance_to(c.body.pos[c.rig.center_point])
    notes.append("runtime moved=%.1f px bad_points=%d" % [moved, bad_points])
    _expect(moved > 80.0, "authored rig moves (%.1f px in 2.5 s)" % moved)
    _expect(bad_points == 0, "authored rig has no NaN body points")
    c.queue_free()


## An authored chain is real logic: it follows the body, its links keep their rest length,
## and the cosmetic follower tail stays off.
func _check_runtime_tail() -> void:
    var bp: RigBlueprint = _fresh()
    if bp == null:
        _expect(false, "fresh scene for tail runtime")
        return
    var part: RigBodyPart = _add_part(bp, 2, "tail")
    part.length = 5
    part.spacing = 9.0
    var rig: CreatureRig = bp.build_rig()
    bp.free()
    if rig == null:
        _expect(false, "tail runtime rig bakes")
        return

    var c: Creature = Creature.new()
    add_child(c)
    var brain: GoalBrain = GoalBrain.new()
    brain.goal = Vector2(650.0, 300.0)
    var world: WorldQuery = WorldQuery.new()
    world.bounds = Rect2(0.0, 0.0, 900.0, 600.0)
    c.setup(rig, brain, world, Vector2(200.0, 300.0))
    _expect(c.tail.points.is_empty(), "authored tail suppresses the cosmetic follower chain")

    var chain: PackedInt32Array = rig.body_parts[0].points
    var rest: PackedFloat32Array = PackedFloat32Array()
    for k in range(1, chain.size()):
        rest.append(c.body.pos[chain[k - 1]].distance_to(c.body.pos[chain[k]]))
    var tip_index: int = chain[chain.size() - 1]
    var start_tip: Vector2 = c.body.pos[tip_index]
    var max_stretch: float = 0.0
    var bad_points: int = 0
    for _i in 180:
        await get_tree().physics_frame
        for p in c.body.pos:
            if not p.is_finite():
                bad_points += 1
        for k in range(1, chain.size()):
            var d: float = c.body.pos[chain[k - 1]].distance_to(c.body.pos[chain[k]])
            max_stretch = maxf(max_stretch, absf(d - rest[k - 1]) / maxf(rest[k - 1], 0.001))

    # The chain is articulated, not a rigid rod: push the tip sideways and it bends.
    var span_before: float = c.body.pos[chain[0]].distance_to(c.body.pos[tip_index])
    c.body.add_impulse(tip_index, Vector2(0.0, 140.0), 1.0 / 60.0)
    var span_min: float = span_before
    for _i in 45:
        await get_tree().physics_frame
        span_min = minf(span_min, c.body.pos[chain[0]].distance_to(c.body.pos[tip_index]))
    var bent: float = span_before - span_min

    var tip_moved: float = start_tip.distance_to(c.body.pos[tip_index])
    notes.append("tail runtime moved=%.1f px stretch=%.3f bent=%.1f bad=%d" % [
        tip_moved, max_stretch, bent, bad_points])
    _expect(bad_points == 0, "authored tail stays finite")
    _expect(tip_moved > 20.0, "authored tail follows the body (%.1f px)" % tip_moved)
    _expect(bent > 1.0, "authored tail articulates instead of staying a rigid rod (%.1f px)" % bent)
    _expect(max_stretch < 0.30, "authored tail links hold their rest length (%.3f max)" % max_stretch)
    c.queue_free()


# ---------------------------------------------------------------- helpers

## Add a backwards-aimed BodyPart to a point of a fresh blueprint.
func _add_part(bp: RigBlueprint, point_index: int, part_name: String) -> RigBodyPart:
    var part: RigBodyPart = RigBodyPart.new()
    part.name = part_name
    part.position = Vector2(-1.0, 0.0)
    bp.points()[point_index].add_child(part)
    return part

func _fresh() -> RigBlueprint:
    var packed: PackedScene = load(SCENE) as PackedScene
    if packed == null:
        return null
    return packed.instantiate() as RigBlueprint


func _expect(condition: bool, message: String) -> void:
    checks += 1
    if not condition:
        fails.append(message)


func _report() -> void:
    for note in notes:
        print("AUTHORING NOTE ", note)
    if fails.is_empty():
        print("AUTHORING SUMMARY PASS checks=%d notes=%d" % [checks, notes.size()])
        get_tree().quit(0)
    else:
        for failure in fails:
            print("AUTHORING FAIL ", failure)
        print("AUTHORING SUMMARY FAIL fails=%d checks=%d" % [fails.size(), checks])
        get_tree().quit(1)
