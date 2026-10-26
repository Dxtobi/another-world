extends Node2D
## T8 acceptance harness. Run headless:
##   godot --headless --path . res://creature_framework/dev/smooth_test.tscn
##
## Proves the smoothness pass is cosmetic and frame-rate independent:
##   * the tail chain lags, overshoots and settles, keeps exact segment lengths,
##     stays finite and bounded after a teleport,
##   * the swing ease is smoothstep (zero slope at both ends, never linear),
##   * a stepping leg follows an eased arc and still lands on the target; the logic
##     tip is untouched, wings do not lag, and a grip is met quickly,
##   * stretch is neutral at rest, rises with speed and with missing grips, damps
##     toward its target, clamps at 1 and deforms along/across the spine,
##   * a live creature runs with finite points, a bounded chain and a real sway.
##
## Prints "SMOOTH SUMMARY ..." and exits non-zero on failure.

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
    _check_chain_rest()
    _check_chain_lag()
    _check_chain_teleport()
    _check_ease()
    _check_arcs()
    _check_stretch()
    await _check_runtime()
    _report()


# ---------------------------------------------------------------- chain

func _check_chain_rest() -> void:
    var ch: CosmeticChain = CosmeticChain.new()
    ch.setup(5, Vector2.ZERO, Vector2.LEFT, 9.0)
    _expect(ch.points.size() == 5, "chain has 5 points")
    _expect(ch.max_segment() > 8.99 and ch.max_segment() < 9.01,
        "chain starts at its segment length (%.3f)" % ch.max_segment())
    _expect(ch.points[0].is_equal_approx(Vector2.ZERO), "chain root sits on the anchor")
    _expect(ch.points[4].is_equal_approx(Vector2(-36.0, 0.0)),
        "chain tip starts on the rest line")
    _expect(ch.is_finite(), "chain starts finite")


func _check_chain_lag() -> void:
    var ch: CosmeticChain = CosmeticChain.new()
    ch.setup(5, Vector2.ZERO, Vector2.LEFT, 9.0)
    var anchor: Vector2 = Vector2.ZERO
    # Move across the rest line, not along it: a chain dragged along its own axis is
    # already fully extended behind the anchor, so only sideways motion shows a swing.
    for _i in 30:
        anchor.y -= 6.0
        ch.step(anchor, Vector2.LEFT, 1.0 / 60.0)

    var rest_tip: Vector2 = anchor + Vector2(-36.0, 0.0)
    var lag: float = ch.tip().distance_to(rest_tip)
    _expect(lag > 5.0, "a moving anchor drags the tail behind its rest pose (%.2f px)" % lag)
    _expect(ch.max_segment() < 9.01, "the dragged chain keeps its segment length")
    _expect(ch.is_finite(), "the dragged chain stays finite")

    for _i in 600:
        ch.step(anchor, Vector2.LEFT, 1.0 / 60.0)
    var settled: float = ch.tip().distance_to(rest_tip)
    _expect(settled < 0.3, "the tail settles back to rest (%.3f px)" % settled)
    _expect(ch.max_segment() < 9.01, "the resting chain keeps its segment length")
    notes.append("chain lag %.2f -> settle %.3f" % [lag, settled])


func _check_chain_teleport() -> void:
    var ch: CosmeticChain = CosmeticChain.new()
    ch.setup(5, Vector2.ZERO, Vector2.LEFT, 9.0)
    var jumped: Vector2 = Vector2(400.0, 0.0)
    ch.step(jumped, Vector2.LEFT, 1.0 / 60.0)
    var reach: float = jumped.distance_to(ch.tip())
    _expect(reach < 36.5, "a teleported anchor cannot stretch the chain (%.2f px)" % reach)
    _expect(ch.max_segment() < 9.01, "the chain keeps its segment length after a teleport")
    _expect(ch.is_finite(), "the chain stays finite after a teleport")
    for _i in 120:
        ch.step(jumped, Vector2.LEFT, 1.0 / 60.0)
    _expect(ch.tip().is_finite(), "the chain recovers after a teleport")


# ---------------------------------------------------------------- eased arcs

func _check_ease() -> void:
    _expect(is_zero_approx(Creature.ease_swing(0.0)), "ease starts at 0")
    _expect(is_equal_approx(Creature.ease_swing(1.0), 1.0), "ease ends at 1")
    _expect(is_equal_approx(Creature.ease_swing(0.5), 0.5), "ease is symmetric at the midpoint")
    _expect(absf(Creature.ease_swing(0.25) - 0.15625) < 0.0001,
        "ease at a quarter is smoothstep (%.5f)" % Creature.ease_swing(0.25))
    _expect(Creature.ease_swing(0.25) < 0.24, "ease is never linear (slow start)")
    _expect(Creature.ease_swing(0.75) > 0.76, "ease is never linear (slow finish)")
    var monotone: bool = true
    var prev: float = -1.0
    for i in 21:
        var v: float = Creature.ease_swing(float(i) / 20.0)
        if v < prev:
            monotone = false
        prev = v
    _expect(monotone, "ease is monotone")


func _check_arcs() -> void:
    var rig: CreatureRig = VultureRig.build()
    _expect(rig != null, "vulture rig loads for the limb arcs")
    if rig == null:
        return
    var c: Creature = Creature.new()
    add_child(c)
    c.set_process(false)
    c.set_physics_process(false)
    var brain: GoalBrain = GoalBrain.new()
    c.setup(rig, brain, WorldQuery.new(), Vector2.ZERO)

    var leg: int = -1
    var wing: int = -1
    for i in rig.limbs.size():
        if rig.limbs[i].kind == &"leg" and leg < 0:
            leg = i
        elif rig.limbs[i].kind == &"wing" and wing < 0:
            wing = i
    _expect(leg >= 0 and wing >= 0, "rig has a leg and a wing for the arc test")
    if leg < 0 or wing < 0:
        c.queue_free()
        return

    var start: Vector2 = c.anchor_pos(leg) + Vector2(0.0, 40.0)
    var target: Vector2 = start + Vector2(140.0, 0.0)
    c.limb_view_tip[leg] = start
    c.limb_tip[leg] = start
    c._swing_to[leg] = start
    c._swing_t[leg] = 1.0
    c.limb_tip[leg] = target

    var chord: Vector2 = (target - start).normalized()
    var max_dev: float = 0.0
    var mid_along: float = -1.0
    var frame: int = 0
    while frame < 120:
        c._update_limb_views(1.0 / 60.0)
        var v: Vector2 = c.limb_view_tip[leg] - start
        max_dev = maxf(max_dev, absf(v.cross(chord)))
        if mid_along < 0.0 and c._swing_t[leg] >= 0.5:
            mid_along = v.dot(chord)
        frame += 1
        if c._swing_t[leg] >= 1.0:
            break

    _expect(max_dev > 5.0, "the leg swing bows off the straight chord (%.2f px)" % max_dev)
    _expect(mid_along > 58.0 and mid_along < 82.0,
        "the swing is at half travel near half time (%.1f px)" % mid_along)
    _expect(c.limb_view_tip[leg].distance_to(target) < 0.01,
        "the swing lands on the target (%.4f px)" % c.limb_view_tip[leg].distance_to(target))
    _expect(c.limb_tip[leg].is_equal_approx(target),
        "the logic limb tip is untouched by the arc")
    _expect(c._swing_dur[leg] <= 0.26, "the swing duration stays bounded (%.3f s)" % c._swing_dur[leg])

    # Wings copy the target: their flap is already smooth, so added lag would smear it.
    var wstart: Vector2 = c.anchor_pos(wing)
    c.limb_view_tip[wing] = wstart
    c.limb_tip[wing] = wstart + Vector2(80.0, 0.0)
    c._swing_to[wing] = wstart
    c._swing_t[wing] = 1.0
    c._update_limb_views(1.0 / 60.0)
    _expect(c.limb_view_tip[wing].is_equal_approx(c.limb_tip[wing]),
        "a wing tip follows its target without lag")

    # A grip is a contact: the eased tip has to meet the dot quickly.
    var hold: Vector2 = c.anchor_pos(leg) + Vector2(0.0, 55.0)
    c.limbs.gripping[leg] = 1
    c.limbs.grip_pos[leg] = hold
    c.limb_view_tip[leg] = start
    c._swing_to[leg] = start
    c._swing_t[leg] = 1.0
    c._update_limb_views(1.0 / 60.0)
    var grip_dur: float = c._swing_dur[leg]
    for _i in 60:
        c._update_limb_views(1.0 / 60.0)
    _expect(c.limb_view_tip[leg].distance_to(hold) < 0.05,
        "a gripping limb meets its hold (%.3f px)" % c.limb_view_tip[leg].distance_to(hold))
    _expect(grip_dur <= 0.10, "a gripping limb uses a short arc (%.3f s)" % grip_dur)
    c.limbs.gripping[leg] = 0
    notes.append("arc dev %.1f px mid %.1f px grip %.3f s" % [max_dev, mid_along, grip_dur])
    c.queue_free()


# ---------------------------------------------------------------- stretch

func _check_stretch() -> void:
    var d: DepthLayer = DepthLayer.new()
    d.reset(1.0)
    for _i in 60:
        d.update_stretch(0.0, 0.0, 6.0, 1.0 / 60.0)
    _expect(d.stretch < 0.001, "stretch is neutral at rest (%.4f)" % d.stretch)
    _expect(is_equal_approx(d.stretch_along(), 1.0) and is_equal_approx(d.stretch_across(), 1.0),
        "neutral stretch leaves both axes alone")
    var centre: Vector2 = Vector2(100.0, 100.0)
    var p_along: Vector2 = centre + Vector2(100.0, 0.0)
    var p_across: Vector2 = centre + Vector2(0.0, 100.0)
    _expect(d.stretch_point(p_along, centre, Vector2.RIGHT, d.stretch_along(), d.stretch_across())
        .is_equal_approx(p_along), "a neutral body point is not moved")

    d.update_stretch(1.0, 0.0, 6.0, 1.0 / 60.0)
    var first: float = d.stretch
    _expect(first > 0.0 and first < 0.2, "stretch damps in instead of snapping (%.3f)" % first)
    for _i in 300:
        d.update_stretch(1.0, 0.0, 6.0, 1.0 / 60.0)
    _expect(d.stretch > 0.70 and d.stretch < 0.80, "speed reaches its stretch target (%.3f)" % d.stretch)
    _expect(d.stretch_along() > 1.06, "speed stretches along the spine (%.4f)" % d.stretch_along())
    _expect(d.stretch_across() < 0.97, "speed narrows across the spine (%.4f)" % d.stretch_across())
    var moved_along: Vector2 = d.stretch_point(p_along, centre, Vector2.RIGHT,
        d.stretch_along(), d.stretch_across())
    var moved_across: Vector2 = d.stretch_point(p_across, centre, Vector2.RIGHT,
        d.stretch_along(), d.stretch_across())
    _expect(moved_along.distance_to(centre) > 100.0, "an axial point moves outward")
    _expect(moved_across.distance_to(centre) < 100.0, "a perpendicular point moves inward")

    var hang: DepthLayer = DepthLayer.new()
    hang.reset(1.0)
    for _i in 240:
        hang.update_stretch(0.0, 1.0, 6.0, 1.0 / 60.0)
    _expect(hang.stretch > 0.85, "missing grips sag the body (%.3f)" % hang.stretch)
    _expect(hang.stretch_along() > 1.07, "the sag stretches along the spine")

    var clamped: DepthLayer = DepthLayer.new()
    clamped.reset(1.0)
    for _i in 240:
        clamped.update_stretch(9.0, 9.0, 60.0, 1.0 / 60.0)
    _expect(clamped.stretch <= 1.0001, "stretch clamps at 1 (%.4f)" % clamped.stretch)
    _expect(clamped.stretch_along() <= 1.0901, "the stretched axis stays bounded")
    _expect(clamped.stretch_across() >= 0.9499, "the narrowed axis stays positive")
    notes.append("stretch speed %.2f (%.3f/%.3f) sag %.2f first %.3f" % [
        d.stretch, d.stretch_along(), d.stretch_across(), hang.stretch, first])


# ---------------------------------------------------------------- live integration

func _check_runtime() -> void:
    var rig: CreatureRig = VultureRig.build()
    _expect(rig != null, "vulture rig loads for the live smoothness run")
    if rig == null:
        return
    var c: Creature = Creature.new()
    add_child(c)
    var brain: GoalBrain = GoalBrain.new()
    brain.goal = Vector2(-600.0, 300.0)
    var world: WorldQuery = WorldQuery.new()
    world.bounds = Rect2(-800.0, -100.0, 1600.0, 800.0)
    world.path_clearance = 58.0
    c.setup(rig, brain, world, Vector2(0.0, 300.0))

    var n: int = c.tail.points.size()
    var max_sway: float = 0.0
    var max_stretch: float = 0.0
    var max_speed: float = 0.0
    for _i in 150:
        await get_tree().physics_frame
        await get_tree().process_frame
        var rest: Vector2 = c.tail.points[0] + c._secondary_dir() * c.tail.seg_len * float(n - 1)
        max_sway = maxf(max_sway, c.tail.tip().distance_to(rest))
        max_stretch = maxf(max_stretch, c.depth_layer.stretch)
        max_speed = maxf(max_speed, c.body.velocity(c.rig.center_point, c._logic_dt).length())

    var all_finite: bool = true
    for p in c.body.pos:
        if not p.is_finite():
            all_finite = false
    _expect(all_finite, "live body points stay finite")
    _expect(c.tail.is_finite(), "the live tail stays finite")
    _expect(c.tail.max_segment() < c.tail.seg_len + 0.5, "the live tail keeps its segment length")
    _expect(max_sway > 3.0, "the tail visibly sways through the turn (%.2f px)" % max_sway)
    _expect(c.depth_layer.stretch >= 0.0 and c.depth_layer.stretch <= 1.0,
        "live stretch stays in 0..1 (%.3f)" % c.depth_layer.stretch)
    _expect(max_stretch > 0.05, "speed produced a real stretch (%.3f)" % max_stretch)
    var views_ok: bool = true
    for i in rig.limbs.size():
        if not c.limb_view_tip[i].is_finite():
            views_ok = false
        if c.limb_view_tip[i].distance_to(c.anchor_pos(i)) > rig.limbs[i].reach * 2.5:
            views_ok = false
    _expect(views_ok, "eased limb tips stay finite and bounded")
    notes.append("runtime tail sway %.1f stretch %.2f speed %.0f seg %.2f centre %s facing %.2f" % [
        max_sway, max_stretch, max_speed, c.tail.max_segment(),
        str(c.body.pos[c.rig.center_point].round()), c.facing])
    c.queue_free()


# ---------------------------------------------------------------- helpers

func _expect(condition: bool, message: String) -> void:
    checks += 1
    if not condition:
        fails.append(message)


func _report() -> void:
    for note in notes:
        print("SMOOTH NOTE ", note)
    if fails.is_empty():
        print("SMOOTH SUMMARY PASS checks=%d notes=%d" % [checks, notes.size()])
        get_tree().quit(0)
    else:
        for failure in fails:
            print("SMOOTH FAIL ", failure)
        print("SMOOTH SUMMARY FAIL fails=%d checks=%d" % [fails.size(), checks])
        get_tree().quit(1)
