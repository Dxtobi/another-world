extends Node2D
## T7 acceptance harness. Run headless:
##   godot --headless --path . res://creature_framework/dev/depth_test.tscn
##
## Proves the depth layer turns a side-on 2D body through a front/back view:
##   * profile: near lane depth +1, far lane -1, near scales up, far darkens,
##   * a reversal sweeps yaw 0 -> PI and dips through a narrow front/back view,
##   * the two sides cross depth 0 exactly once, so draw order swaps once at edge-on,
##   * a free leg lifts while climbing and drops when held; wings never step,
##   * a live creature's depth layer follows its facing.
##
## Prints "DEPTH SUMMARY ..." and exits non-zero on failure.

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
    _check_profile()
    _check_turn()
    _check_step_lift()
    await _check_runtime_turn()
    _report()


# ---------------------------------------------------------------- depth math

func _check_profile() -> void:
    var d: DepthLayer = DepthLayer.new()
    d.reset(1.0)
    _expect(absf(d.yaw) < 0.001, "profile starts at yaw 0")
    _expect(is_equal_approx(d.squash, 1.0), "profile is full width")
    var near: float = d.depth_of(1.0)
    var far: float = d.depth_of(-1.0)
    _expect(near > 0.99 and far < -0.99, "near lane is +depth, far lane is -depth")
    _expect(d.scale_for(near) > 1.0 and d.scale_for(far) < 1.0,
        "near scales up, far scales down")
    _expect(d.tint(Color.WHITE, far).v < d.tint(Color.WHITE, near).v,
        "far side is darker")
    _expect(d.z_for(near) > 0 and d.z_for(far) < 0, "z order sign follows depth")
    var centre: Vector2 = Vector2(10.0, 20.0)
    var sq: Vector2 = d.squash_point(centre + Vector2(40.0, 5.0), centre)
    _expect(sq.is_equal_approx(centre + Vector2(40.0, 5.0)),
        "profile squash leaves the point alone")
    notes.append("profile near %.2f far %.2f scale %.2f/%.2f" % [
        near, far, d.scale_for(near), d.scale_for(far)])


func _check_turn() -> void:
    var d: DepthLayer = DepthLayer.new()
    d.reset(1.0)
    var facing: float = 1.0
    var prev_yaw: float = d.yaw
    var yaw_ok: bool = true
    var min_squash: float = d.squash
    var prev_order: Array[int] = _order_for(d)
    var swaps: int = 0
    var swap_depth: float = 1.0
    var dt: float = 1.0 / 60.0

    for _i in 240:
        facing = Steering.damp_f(facing, -1.0, 9.0, dt)
        d.update(facing, 10.0, dt)
        if d.yaw < prev_yaw - 0.0001:
            yaw_ok = false
        prev_yaw = d.yaw
        min_squash = minf(min_squash, d.squash)
        var cur_order: Array[int] = _order_for(d)
        if cur_order[0] != prev_order[0] or cur_order[1] != prev_order[1]:
            swaps += 1
            swap_depth = maxf(absf(d.depth_of(1.0)), absf(d.depth_of(-1.0)))
            prev_order = cur_order

    _expect(yaw_ok, "yaw sweeps forward through the turn (0 -> PI)")
    _expect(min_squash < 0.2, "the turn passes through a narrow front/back view (%.2f)" % min_squash)
    _expect(d.yaw > PI - 0.1, "the turn ends at the opposite profile (yaw %.2f)" % d.yaw)
    _expect(d.squash > 0.90, "the opposite profile is full width again (%.2f)" % d.squash)
    _expect(facing < -0.99, "facing reaches the new direction")
    _expect(swaps == 1, "near/far draw order swaps exactly once (got %d)" % swaps)
    _expect(swap_depth < 0.2, "the swap happens at edge-on (|depth| %.2f)" % swap_depth)
    notes.append("turn yaw %.2f squash_min %.2f swaps %d swap_depth %.2f" % [
        d.yaw, min_squash, swaps, swap_depth])


## Draw order for a sample near (+1) and far (-1) part: lower depth first.
func _order_for(d: DepthLayer) -> Array[int]:
    var order: Array[int] = [0, 1]
    order.sort_custom(func(a: int, b: int) -> bool:
        var da: float = d.depth_of(1.0 if a == 0 else -1.0)
        var db: float = d.depth_of(1.0 if b == 0 else -1.0)
        if is_equal_approx(da, db):
            return a < b
        return da < db)
    return order


# ---------------------------------------------------------------- step lift

func _check_step_lift() -> void:
    var rig: CreatureRig = VultureRig.build()
    _expect(rig != null, "vulture rig loads for the step-lift test")
    if rig == null:
        return
    var c: Creature = Creature.new()
    add_child(c)
    var brain: GoalBrain = GoalBrain.new()
    var world: WorldQuery = WorldQuery.new()
    c.setup(rig, brain, world, Vector2.ZERO)

    var leg: int = -1
    var wing: int = -1
    for i in rig.limbs.size():
        if rig.limbs[i].kind == &"leg" and leg < 0:
            leg = i
        elif rig.limbs[i].kind == &"wing" and wing < 0:
            wing = i
    _expect(leg >= 0 and wing >= 0, "rig has a leg and a wing")
    if leg >= 0:
        c.limbs.gripping[leg] = 0
        for _i in 30:
            c._update_step_lift(1.0 / 60.0, true)
        _expect(c.step_lift[leg] > 0.8, "a free leg lifts while stepping (%.2f)" % c.step_lift[leg])
        c.limbs.gripping[leg] = 1
        for _i in 30:
            c._update_step_lift(1.0 / 60.0, true)
        _expect(c.step_lift[leg] < 0.2, "a held leg drops back onto the surface")
        c.limbs.gripping[leg] = 0
        for _i in 30:
            c._update_step_lift(1.0 / 60.0, false)
        _expect(c.step_lift[leg] < 0.05, "flight does not lift the leg")
    if wing >= 0:
        c.limbs.gripping[wing] = 0
        for _i in 30:
            c._update_step_lift(1.0 / 60.0, true)
        _expect(c.step_lift[wing] < 0.05, "wings never step-lift")
    c.queue_free()


# ---------------------------------------------------------------- live integration

func _check_runtime_turn() -> void:
    var rig: CreatureRig = VultureRig.build()
    _expect(rig != null, "vulture rig loads for the runtime turn")
    if rig == null:
        return
    var c: Creature = Creature.new()
    add_child(c)
    var brain: GoalBrain = GoalBrain.new()
    brain.goal = Vector2(-500.0, 300.0)
    var world: WorldQuery = WorldQuery.new()
    world.bounds = Rect2(-800.0, -100.0, 1600.0, 800.0)
    world.path_clearance = 58.0
    c.setup(rig, brain, world, Vector2(0.0, 300.0))

    for _i in 150:
        await get_tree().physics_frame
        await get_tree().process_frame

    _expect(c.facing < -0.9, "runtime creature turns to face left (facing %.2f)" % c.facing)
    _expect(c.depth_layer.yaw > 2.7, "runtime depth yaw follows the turn (%.2f)" % c.depth_layer.yaw)
    _expect(c.depth_layer.squash > 0.9, "runtime turn ends in a full profile (%.2f)" % c.depth_layer.squash)
    _expect(c.depth_layer.depth_of(1.0) < -0.8 and c.depth_layer.depth_of(-1.0) > 0.8,
        "runtime near/far depths have swapped")
    notes.append("runtime facing %.2f yaw %.2f squash %.2f" % [
        c.facing, c.depth_layer.yaw, c.depth_layer.squash])
    c.queue_free()


# ---------------------------------------------------------------- helpers

func _expect(condition: bool, message: String) -> void:
    checks += 1
    if not condition:
        fails.append(message)


func _report() -> void:
    for note in notes:
        print("DEPTH NOTE ", note)
    if fails.is_empty():
        print("DEPTH SUMMARY PASS checks=%d notes=%d" % [checks, notes.size()])
        get_tree().quit(0)
    else:
        for failure in fails:
            print("DEPTH FAIL ", failure)
        print("DEPTH SUMMARY FAIL fails=%d checks=%d" % [fails.size(), checks])
        get_tree().quit(1)
