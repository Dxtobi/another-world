extends Node2D
## T3 acceptance harness. Run headless:
##   godot --headless --path . res://creature_framework/dev/path_test.tscn
##
## The creature does not get to fly at the goal in a straight line, because a straight line
## is blocked twice:
##
##        ceiling ==============================
##                     wall A          wall B
##                        |              |
##        spawn ->  UP     |    DOWN      |   -> goal
##                        |              |
##        floor   ==============================
##
## wall A hangs from y 220 down to the floor, so the creature must climb over it.
## wall B hangs from the ceiling down to y 380, so it must then dive under it.
##
## Asserts:
##   * PathFollower falls back to the raw goal when there is no grid.
##   * A goal inside terrain is snapped to a free cell and still produces a path.
##   * The creature reaches the goal (< 30 px) inside 45 s.
##   * No body point is ever inside terrain.
##   * It really climbs over A (min y < 220) and dives under B (max y > 380).
##
## Prints "PATH SUMMARY ..." and exits non-zero on failure.

const CELL := 24.0
const SPAWN := Vector2(100.0, 300.0)
const GOAL := Vector2(1350.0, 300.0)
const GOAL_RADIUS := 30.0
const RUN_FRAMES := 45 * 60

const WALL_A_X := Vector2(500.0, 560.0)
const WALL_A_TOP := 220.0
const WALL_B_X := Vector2(900.0, 960.0)
const WALL_B_BOTTOM := 380.0

var world: WorldQuery
var fails: PackedStringArray = PackedStringArray()
var notes: PackedStringArray = PackedStringArray()


class GoalBrain extends Brain:
    var goal: Vector2 = Vector2.ZERO

    func think(creature: Creature, intent: Intent, _dt: float) -> void:
        intent.has_goal = true
        intent.goal = goal
        intent.desired_speed = 1.0
        intent.urgency = 1.0
        var here: Vector2 = creature.body.pos[creature.rig.center_point]
        intent.look_dir = Vector2(signf(goal.x - here.x), 0.0)


func _ready() -> void:
    _check_fallback()
    await _build_level()
    _check_inside_goal()
    await _fly()
    _report()


# ---------------------------------------------------------------- follower alone

func _check_fallback() -> void:
    var plain: WorldQuery = WorldQuery.new()
    var pf: PathFollower = PathFollower.new(plain)
    pf.update(SPAWN, GOAL, true, 0.016)
    var got: Vector2 = pf.target(GOAL)
    notes.append("no-grid fallback=%s repaths=%d" % [str(got == GOAL), pf.repaths])
    if got != GOAL:
        fails.append("steer target did not fall back to the goal without grids")
    if pf.repaths != 0:
        fails.append("PathFollower repathed with no grids")


# ---------------------------------------------------------------- level

func _build_level() -> void:
    world = WorldQuery.new()
    world.bounds = Rect2(-100.0, -100.0, 1700.0, 900.0)
    world.cell_size = CELL

    # Ground is a block, not a slab: a thin slab leaves free space underneath, which would
    # let the "snap a goal out of terrain" search find an unreachable cell below the floor.
    _platform(PackedVector2Array([
        Vector2(0, 500), Vector2(1500, 500), Vector2(1500, 800), Vector2(0, 800)]))
    _platform(PackedVector2Array([
        Vector2(0, 60), Vector2(1500, 60), Vector2(1500, 100), Vector2(0, 100)]))
    _platform(PackedVector2Array([
        Vector2(WALL_A_X.x, WALL_A_TOP), Vector2(WALL_A_X.y, WALL_A_TOP),
        Vector2(WALL_A_X.y, 500), Vector2(WALL_A_X.x, 500)]))
    _platform(PackedVector2Array([
        Vector2(WALL_B_X.x, 60), Vector2(WALL_B_X.y, 60),
        Vector2(WALL_B_X.y, WALL_B_BOTTOM), Vector2(WALL_B_X.x, WALL_B_BOTTOM)]))

    # The polygons must exist in the physics server before the grid is rasterised.
    await get_tree().physics_frame
    await get_tree().physics_frame
    await get_tree().physics_frame
    world.attach(self)
    world.bake(Rect2(0.0, 0.0, 1500.0, 600.0))
    notes.append("grids baked=%s solid_cells=%d" % [str(world.has_grids()), world.solid_cells()])
    if not world.has_grids():
        fails.append("world grids did not bake")


func _check_inside_goal() -> void:
    var inside: Vector2 = Vector2(700.0, 530.0)      # buried in the floor
    if not world.is_solid(inside):
        fails.append("test setup: expected (700, 530) to be inside the floor")
        return
    var pf: PathFollower = PathFollower.new(world)
    pf.update(SPAWN, inside, true, 0.016)
    var end: Vector2 = pf.path[pf.path.size() - 1] if not pf.path.is_empty() else Vector2.INF
    notes.append("inside-goal waypoints=%d end=%s solid=%s" % [
        pf.path.size(), str(end.round()), str(end != Vector2.INF and world.is_solid_point(end))])
    if pf.path.is_empty():
        fails.append("no path when the goal is inside terrain")
    elif world.is_solid_point(end):
        fails.append("path ends inside terrain")


# ---------------------------------------------------------------- flight

func _fly() -> void:
    var creature: Creature = Creature.new()
    add_child(creature)
    var brain: GoalBrain = GoalBrain.new()
    brain.goal = GOAL
    creature.setup(VultureRig.build(), brain, world, SPAWN)

    var reached_at: float = -1.0
    var closest: float = 99999.0
    var violations: int = 0
    var first_violation: Vector2 = Vector2.INF
    var saw_path: bool = false
    var repaths: int = 0
    var min_y_a: float = 99999.0
    var max_y_b: float = -99999.0

    for frame in RUN_FRAMES:
        await get_tree().physics_frame
        var centre: Vector2 = creature.body.pos[creature.rig.center_point]
        var head: Vector2 = creature.body.pos[creature.rig.front_point]

        for k in creature.body.pos.size():
            if world.is_solid_point(creature.body.pos[k]):
                violations += 1
                if first_violation == Vector2.INF:
                    first_violation = creature.body.pos[k]

        # "Reached" is measured at the head: that is the point the locomotor steers, and a
        # long body legitimately trails a spine-length behind it.
        closest = minf(closest, head.distance_to(GOAL))
        if reached_at < 0.0 and closest <= GOAL_RADIUS:
            reached_at = float(frame + 1) / 60.0

        if creature.path != null:
            saw_path = saw_path or creature.path.has_path()
            repaths = maxi(repaths, creature.path.repaths)

        if centre.x >= WALL_A_X.x - 80.0 and centre.x <= WALL_A_X.y:
            min_y_a = minf(min_y_a, centre.y)
        if centre.x >= WALL_B_X.x - 40.0 and centre.x <= WALL_B_X.y + 40.0:
            max_y_b = maxf(max_y_b, centre.y)

    creature.queue_free()
    await get_tree().physics_frame

    notes.append("flight reached=%s t=%.2fs closest=%.1f" % [
        str(reached_at >= 0.0), reached_at, closest])
    notes.append("flight violations=%d first=%s" % [
        violations, str(first_violation.round() if first_violation != Vector2.INF else Vector2.ZERO)])
    notes.append("path used=%s repaths=%d" % [str(saw_path), repaths])
    notes.append("slalom min_y_at_A=%.1f (< %.0f required) max_y_at_B=%.1f (> %.0f required)" % [
        min_y_a, WALL_A_TOP, max_y_b, WALL_B_BOTTOM])

    if reached_at < 0.0:
        fails.append("did not reach the goal in %d s (closest %.1f px)" % [RUN_FRAMES / 60, closest])
    if violations > 0:
        fails.append("body point inside terrain %d times" % violations)
    if not saw_path:
        fails.append("creature never followed a path")
    if min_y_a >= WALL_A_TOP:
        fails.append("creature did not climb over wall A (min y %.1f)" % min_y_a)
    if max_y_b <= WALL_B_BOTTOM:
        fails.append("creature did not dive under wall B (max y %.1f)" % max_y_b)


# ---------------------------------------------------------------- helpers

func _platform(points: PackedVector2Array) -> void:
    var body: StaticBody2D = StaticBody2D.new()
    var poly: CollisionPolygon2D = CollisionPolygon2D.new()
    poly.polygon = points
    body.add_child(poly)
    add_child(body)


func _report() -> void:
    for n in notes:
        print("PATH NOTE ", n)
    if fails.is_empty():
        print("PATH SUMMARY PASS notes=%d" % notes.size())
        get_tree().quit(0)
    else:
        for f in fails:
            print("PATH FAIL ", f)
        print("PATH SUMMARY FAIL fails=%d" % fails.size())
        get_tree().quit(1)
