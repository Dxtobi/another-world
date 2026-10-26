extends Node2D
## T6 acceptance harness. Run headless:
##   godot --headless --path . res://creature_framework/dev/mode_test.tscn
##
## One tall wall, a baked world, and three goals that must each pick a sensible mode:
##
##   1. climb-only: goal 20 px off the wall, high up. A flyer starts in open air, must
##      LAND (fly -> climb), climb to the goal, then -- when the goal moves to open air --
##      LAUNCH (climb -> fly) and fly to it.
##   2. flight-only: the same open-air goal, reached by routing over the wall. It must never
##      switch to climb, even while passing close to the wall.
##   3. ambiguous: a goal 20 px off the wall, low down. Both an air route and a surface route
##      exist; the policy is "goal touches climbable terrain -> climb". It must land, reach
##      it, and not flicker back.
##
## Also checks the surface-grid helper directly: the wall goal is reachable, the open-air
## goal is not.
##
## Prints "MODE SUMMARY ..." and exits non-zero on failure.

const WALL := Rect2(340.0, 60.0, 60.0, 440.0)
const BOUNDS := Rect2(-100.0, -100.0, 1200.0, 900.0)

const CLIMB_SPAWN := Vector2(140.0, 350.0)
const CLIMB_GOAL := Vector2(320.0, 150.0)
const LAUNCH_GOAL := Vector2(760.0, 240.0)

const FLY_SPAWN := Vector2(140.0, 350.0)
const FLY_GOAL := Vector2(760.0, 240.0)

const AMBIG_SPAWN := Vector2(200.0, 360.0)
const AMBIG_GOAL := Vector2(320.0, 420.0)

const GOAL_RADIUS := 30.0

var world: WorldQuery
var fails: PackedStringArray = PackedStringArray()
var notes: PackedStringArray = PackedStringArray()

var _frame: int = 0


class GoalBrain extends Brain:
    var goal: Vector2 = Vector2.ZERO

    func think(creature: Creature, intent: Intent, _dt: float) -> void:
        intent.has_goal = true
        intent.goal = goal
        intent.desired_speed = 1.0
        var d: Vector2 = goal - creature.body.pos[creature.rig.center_point]
        intent.look_dir = d.normalized() if d.length_squared() > 0.01 else Vector2.RIGHT


## Per-phase observations. Sampling happens after each physics tick, so a mode change made
## inside that tick is already visible.
class Track extends RefCounted:
    var modes: Dictionary = {}
    var switches: int = 0
    var min_switch_gap: float = 999.0
    var grips_max: int = 0
    var closest: float = 99999.0
    var reach_at: float = -1.0
    var reach_mode: StringName = &""
    var violations: int = 0
    var launch_vx: float = 0.0
    var grips_after_launch: int = -1

    var _last_mode: StringName = &""
    var _last_switch: float = -999.0

    ## Start tracking from the current mode without counting it as a switch. Needed when the
    ## mode may change on the very next tick (moving the goal off the wall).
    func seed(c: Creature, t: float) -> void:
        _last_mode = c.loco.current.id
        _last_switch = t

    func sample(c: Creature, goal: Vector2, w: WorldQuery, t: float) -> void:
        var id: StringName = c.loco.current.id
        modes[id] = true
        if _last_mode == &"":
            _last_mode = id
            _last_switch = t
        elif id != _last_mode:
            switches += 1
            min_switch_gap = minf(min_switch_gap, t - _last_switch)
            if id == &"fly":
                launch_vx = c.body.velocity(c.rig.center_point, 1.0 / 60.0).x
                grips_after_launch = c.limbs.grip_count()
            _last_mode = id
            _last_switch = t

        grips_max = maxi(grips_max, c.limbs.grip_count())
        var centre: Vector2 = c.body.pos[c.rig.center_point]
        var d: float = centre.distance_to(goal)
        closest = minf(closest, d)
        if reach_at < 0.0 and d <= GOAL_RADIUS:
            reach_at = t
            reach_mode = id
        for i in c.body.pos.size():
            if w.is_solid_point(c.body.pos[i]):
                violations += 1


func _ready() -> void:
    await _build_level()
    await _climb_then_launch()
    await _flight_only()
    await _ambiguous()
    _report()


# ---------------------------------------------------------------- level

func _build_level() -> void:
    world = WorldQuery.new()
    world.bounds = BOUNDS
    _platform(WALL)
    for _i in 3:
        await get_tree().physics_frame
    world.attach(self)
    # The vulture spine is 80 px long. The default 34 px clearance is tuned for a point,
    # and the body catches tall wall corners; bake with room for the whole body here.
    world.path_clearance = 58.0
    world.bake(BOUNDS)

    var wall_hit: WorldQuery.SurfaceHit = world.surface_near(CLIMB_GOAL, 52.0)
    var air_hit: WorldQuery.SurfaceHit = world.surface_near(FLY_GOAL, 52.0)
    var wall_reach: bool = world.surface_reachable(Vector2(300.0, 430.0), CLIMB_GOAL, 3)
    var air_reach: bool = world.surface_reachable(Vector2(300.0, 430.0), FLY_GOAL, 3)
    var air_path: PackedVector2Array = world.path_air(FLY_SPAWN, FLY_GOAL)
    notes.append("grids=%s solid_cells=%d goal_hit=%s goal_reach=%s air_hit=%s air_reach=%s air_path=%d" % [
        str(world.has_grids()), world.solid_cells(),
        str(wall_hit != null), str(wall_reach),
        str(air_hit != null), str(air_reach), air_path.size()])

    if not world.has_grids() or world.solid_cells() <= 0:
        fails.append("test setup: world grid did not bake")
    if wall_hit == null or not wall_reach:
        fails.append("test setup: the wall goal is not on the surface grid")
    if air_hit != null or air_reach:
        fails.append("test setup: the open-air goal is climbable")


# ---------------------------------------------------------------- 1. climb then launch

func _climb_then_launch() -> void:
    var c: Creature = _spawn(CLIMB_SPAWN, CLIMB_GOAL)
    var brain: GoalBrain = c.brain as GoalBrain
    var up: Track = Track.new()
    var t: float = 0.0
    var limit: int = 20 * 60
    while _frame < limit and not (up.reach_at >= 0.0 and c.loco.current.id == &"climb"):
        await get_tree().physics_frame
        t += 1.0 / 60.0
        up.sample(c, CLIMB_GOAL, world, t)
        _frame += 1

    notes.append("climb up modes=%s switches=%d reach=%.2fs(%s) closest=%.1f grips_max=%d" % [
        str(up.modes.keys()), up.switches, up.reach_at, up.reach_mode, up.closest, up.grips_max])

    if not up.modes.has(&"fly") or not up.modes.has(&"climb"):
        fails.append("climb-only: did not use both fly and climb (modes %s)" % str(up.modes.keys()))
    if up.switches != 1:
        fails.append("climb-only: expected exactly 1 switch, saw %d" % up.switches)
    if up.reach_at < 0.0:
        fails.append("climb-only: never reached the wall goal (closest %.1f)" % up.closest)
    elif up.reach_mode != &"climb":
        fails.append("climb-only: reached the wall goal while in %s, not climb" % up.reach_mode)
    if up.grips_max < 2:
        fails.append("climb-only: landing only ever had %d grips" % up.grips_max)
    if up.violations > 0:
        fails.append("climb-only: body point inside terrain %d times" % up.violations)

    # Move the goal into open air: climb must hand over to fly and launch away from the wall.
    brain.goal = LAUNCH_GOAL
    var away: Track = Track.new()
    away.seed(c, 0.0)
    t = 0.0
    _frame = 0
    limit = 22 * 60
    while _frame < limit and not (away.reach_at >= 0.0 and c.loco.current.id == &"fly"):
        await get_tree().physics_frame
        t += 1.0 / 60.0
        away.sample(c, LAUNCH_GOAL, world, t)
        _frame += 1

    notes.append("launch modes=%s switches=%d reach=%.2fs(%s) closest=%.1f vx=%.1f grips=%d" % [
        str(away.modes.keys()), away.switches, away.reach_at, away.reach_mode,
        away.closest, away.launch_vx, away.grips_after_launch])

    if not away.modes.has(&"fly") or away.switches != 1:
        fails.append("launch: expected exactly one climb -> fly switch (modes %s, switches %d)" % [
            str(away.modes.keys()), away.switches])
    if away.launch_vx > -20.0:
        fails.append("launch: did not push away from the wall (vx %.1f)" % away.launch_vx)
    if away.grips_after_launch != 0:
        fails.append("launch: still holding %d grips after switching to fly" % away.grips_after_launch)
    if away.reach_at < 0.0:
        fails.append("launch: never reached the open-air goal (closest %.1f)" % away.closest)
    elif away.reach_mode != &"fly":
        fails.append("launch: reached the open-air goal in %s, not fly" % away.reach_mode)
    if away.violations > 0:
        fails.append("launch: body point inside terrain %d times" % away.violations)

    c.queue_free()


# ---------------------------------------------------------------- 2. flight only

func _flight_only() -> void:
    var c: Creature = _spawn(FLY_SPAWN, FLY_GOAL)
    var tr: Track = Track.new()
    var t: float = 0.0
    var limit: int = 22 * 60
    _frame = 0
    while _frame < limit and tr.reach_at < 0.0:
        await get_tree().physics_frame
        t += 1.0 / 60.0
        tr.sample(c, FLY_GOAL, world, t)
        _frame += 1

    notes.append("flight only modes=%s switches=%d reach=%.2fs(%s) closest=%.1f" % [
        str(tr.modes.keys()), tr.switches, tr.reach_at, tr.reach_mode, tr.closest])

    if tr.switches != 0 or tr.modes.has(&"climb"):
        fails.append("flight-only: switched to climb (modes %s, switches %d)" % [
            str(tr.modes.keys()), tr.switches])
    if tr.reach_at < 0.0:
        fails.append("flight-only: never reached the goal (closest %.1f)" % tr.closest)
    elif tr.reach_mode != &"fly":
        fails.append("flight-only: reached in %s, not fly" % tr.reach_mode)
    if tr.violations > 0:
        fails.append("flight-only: body point inside terrain %d times" % tr.violations)

    c.queue_free()


# ---------------------------------------------------------------- 3. ambiguous

func _ambiguous() -> void:
    var c: Creature = _spawn(AMBIG_SPAWN, AMBIG_GOAL)
    var tr: Track = Track.new()
    var t: float = 0.0
    var limit: int = 20 * 60
    _frame = 0
    while _frame < limit and not (tr.reach_at >= 0.0 and c.loco.current.id == &"climb"):
        await get_tree().physics_frame
        t += 1.0 / 60.0
        tr.sample(c, AMBIG_GOAL, world, t)
        _frame += 1

    notes.append("ambiguous modes=%s switches=%d reach=%.2fs(%s) closest=%.1f grips_max=%d" % [
        str(tr.modes.keys()), tr.switches, tr.reach_at, tr.reach_mode, tr.closest, tr.grips_max])

    if not tr.modes.has(&"climb"):
        fails.append("ambiguous: did not choose climb (modes %s)" % str(tr.modes.keys()))
    if tr.switches != 1:
        fails.append("ambiguous: expected exactly 1 switch, saw %d (flicker)" % tr.switches)
    if tr.reach_at < 0.0:
        fails.append("ambiguous: never reached the goal (closest %.1f)" % tr.closest)
    elif tr.reach_mode != &"climb":
        fails.append("ambiguous: reached in %s, not climb" % tr.reach_mode)
    if tr.grips_max < 2:
        fails.append("ambiguous: landing only ever had %d grips" % tr.grips_max)
    if tr.violations > 0:
        fails.append("ambiguous: body point inside terrain %d times" % tr.violations)

    c.queue_free()


# ---------------------------------------------------------------- helpers

func _spawn(origin: Vector2, goal: Vector2) -> Creature:
    var c: Creature = Creature.new()
    add_child(c)
    var brain: GoalBrain = GoalBrain.new()
    brain.goal = goal
    c.setup(VultureRig.build(), brain, world, origin)
    return c


func _platform(rect: Rect2) -> void:
    var body: StaticBody2D = StaticBody2D.new()
    var poly: CollisionPolygon2D = CollisionPolygon2D.new()
    poly.polygon = PackedVector2Array([
        rect.position,
        Vector2(rect.end.x, rect.position.y),
        rect.end,
        Vector2(rect.position.x, rect.end.y),
    ])
    body.add_child(poly)
    add_child(body)


func _report() -> void:
    for n in notes:
        print("MODE NOTE ", n)
    if fails.is_empty():
        print("MODE SUMMARY PASS notes=%d" % notes.size())
        get_tree().quit(0)
    else:
        for f in fails:
            print("MODE FAIL ", f)
        print("MODE SUMMARY FAIL fails=%d" % fails.size())
        get_tree().quit(1)
