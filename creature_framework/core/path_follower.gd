class_name PathFollower
extends RefCounted
## Turns the world's air grid into the point a locomotor should actually steer at.
##
## The brain still writes `Intent.goal`; this only answers "where next". It keeps a path,
## advances the waypoint as the creature reaches it, and repaths when the goal moves more
## than `goal_tolerance` or every `repath_interval`. If there is no grid (dev scene) or no
## path, `target()` returns the raw goal, so navigation is never able to freeze a creature.

var world: WorldQuery = null
## Distance at which the current waypoint counts as reached.
var waypoint_reach: float = 24.0
## Replan cadence. 0.3 s is cheap and still reacts to a moving goal.
var repath_interval: float = 0.3
## Repath immediately when the goal drifts further than this.
var goal_tolerance: float = 24.0

var path: PackedVector2Array = PackedVector2Array()
var index: int = 0
var repaths: int = 0

var _goal: Vector2 = Vector2.INF
var _timer: float = 0.0
var _has_goal: bool = false


func _init(p_world: WorldQuery) -> void:
    world = p_world


## Advance the plan. Call once per physics tick, after the brain and before locomotors.
func update(from: Vector2, goal: Vector2, has_goal: bool, dt: float) -> void:
    _has_goal = has_goal and world != null
    if not _has_goal:
        path = PackedVector2Array()
        index = 0
        return

    # Move the waypoint pointer as the creature arrives, or once it has crossed the
    # waypoint's plane along the segment. The second test is what stops a fast flyer from
    # orbiting a corner it overshot by more than `waypoint_reach`.
    while index < path.size():
        if from.distance_to(path[index]) <= waypoint_reach:
            index += 1
        elif index + 1 < path.size() and (path[index + 1] - path[index]).dot(from - path[index]) > 0.0:
            index += 1
        else:
            break

    _timer += dt
    var goal_moved: bool = _goal == Vector2.INF or _goal.distance_to(goal) > goal_tolerance
    # A spent path is not a reason to repath every tick: while it is spent, `target()` is the
    # goal itself, and the interval below replans soon enough. Repathing on `spent` made the
    # follower run A* 40 times a second while the creature hovered on its goal.
    if not (goal_moved or _timer >= repath_interval):
        return
    _timer = 0.0
    _goal = goal
    _repath(from, goal)


## True when there are no waypoints left, so steering is aimed at the goal itself.
func at_goal() -> bool:
    return not _has_goal or index >= path.size()


## Where to steer. Falls back to the raw goal whenever the plan cannot answer.
func target(fallback: Vector2) -> Vector2:
    if _has_goal and index < path.size():
        return path[index]
    return fallback


func has_path() -> bool:
    return index < path.size()


func remaining() -> int:
    return maxi(0, path.size() - index)


func _repath(from: Vector2, goal: Vector2) -> void:
    path = PackedVector2Array()
    index = 0
    if world == null or not world.has_grids():
        return
    var start: Vector2 = _free_cell(from, from)
    var aim: Vector2 = _free_cell(goal, goal)
    path = world.path_air(start, aim)
    repaths += 1


## Snap a point to a cell the air grid can actually use. A point can be "free" in the
## physics sense yet share a cell whose centre is solid, so both are checked; the grid is
## what A* walks. Returns `fallback` when there is no free cell nearby, which degrades to
## steering straight at the goal instead of freezing the creature.
func _free_cell(p: Vector2, fallback: Vector2) -> Vector2:
    if _cell_free(p):
        return world.cell_pos(world.to_cell(p))
    for ring in range(1, 6):
        for k in 16:
            var q: Vector2 = p + Vector2.from_angle(TAU * float(k) / 16.0) * (ring * world.cell_size)
            if _cell_free(q):
                return world.cell_pos(world.to_cell(q))
    return fallback


func _cell_free(p: Vector2) -> bool:
    if world.is_solid(p):
        return false
    var cell: Vector2i = world.to_cell(p)
    return world.grid_has(cell) and not world.grid_solid(cell)
