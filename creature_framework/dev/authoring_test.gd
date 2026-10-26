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
    await _check_runtime()
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


# ---------------------------------------------------------------- helpers

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
