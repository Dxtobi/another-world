extends Node2D
## Live T8 demo. Open this scene in the editor and press F6.
##
## The vulture crosses between a left and a right goal, so every crossing is a fast run
## followed by a turnaround. Watch:
##   * the tail lag and swing through each turn (the faint line is its rest direction),
##   * the legs' eased arcs as they stride,
##   * the body stretch along the spine at speed.
## The HUD prints the numbers the view is using. `T` flips the goal now, `S` toggles slow
## motion (0.15x, restored on exit).

const SPAWN := Vector2(580.0, 320.0)
const LEFT_GOAL := Vector2(240.0, 240.0)
const RIGHT_GOAL := Vector2(920.0, 240.0)
const ARRIVE := 70.0
const HOLD := 1.4

var world: WorldQuery
var creature: Creature
var brain: GoalBrain
var cam: Camera2D
var hud: Label
var _goal: Vector2 = RIGHT_GOAL
var _hold: float = 0.0
var _slow: bool = false


class GoalBrain extends Brain:
    var goal: Vector2 = Vector2.ZERO

    func think(creature: Creature, intent: Intent, _dt: float) -> void:
        intent.has_goal = true
        intent.goal = goal
        intent.desired_speed = 1.0
        var d: Vector2 = goal - creature.body.pos[creature.rig.center_point]
        intent.look_dir = d.normalized() if d.length_squared() > 0.01 else Vector2.RIGHT


func _ready() -> void:
    world = WorldQuery.new()
    world.bounds = Rect2(0.0, 0.0, 1120.0, 640.0)
    world.attach(self)
    world.path_clearance = 58.0
    world.bake(world.bounds)

    brain = GoalBrain.new()
    brain.goal = _goal
    creature = Creature.new()
    add_child(creature)
    creature.setup(VultureRig.build(), brain, world, SPAWN)

    cam = Camera2D.new()
    cam.position = SPAWN
    cam.zoom = Vector2(1.05, 1.05)
    add_child(cam)
    cam.make_current()

    var layer: CanvasLayer = CanvasLayer.new()
    add_child(layer)
    hud = Label.new()
    hud.position = Vector2(16.0, 12.0)
    hud.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
    layer.add_child(hud)

    print("SMOOTH DEMO ready")


func _unhandled_input(event: InputEvent) -> void:
    if creature == null:
        return
    if event is InputEventKey and event.pressed and not event.echo:
        match (event as InputEventKey).keycode:
            KEY_T:
                _flip_goal()
            KEY_S:
                _slow = not _slow
                Engine.time_scale = 0.15 if _slow else 1.0
                print("SMOOTH DEMO slowmo %s" % str(_slow))


func _exit_tree() -> void:
    Engine.time_scale = 1.0


func _flip_goal() -> void:
    _hold = 0.0
    _goal = LEFT_GOAL if brain.goal == RIGHT_GOAL else RIGHT_GOAL
    brain.goal = _goal
    print("SMOOTH DEMO goal %s" % str(_goal.round()))


func _process(dt: float) -> void:
    if creature == null or creature.body == null:
        return
    var centre: Vector2 = creature.body.pos[creature.rig.center_point]
    if centre.distance_to(brain.goal) <= ARRIVE:
        _hold += dt
        if _hold >= HOLD:
            _flip_goal()
    else:
        _hold = 0.0

    var follow: Vector2 = Vector2(580.0, clampf(centre.y, 220.0, 480.0))
    cam.global_position = cam.global_position.lerp(follow, 1.0 - exp(-3.0 * dt))

    var speed: float = creature.body.velocity(creature.rig.center_point, creature._logic_dt).length()
    var n: int = creature.tail.points.size()
    var rest_tip: Vector2 = creature.tail.points[0] \
        + creature._secondary_dir() * creature.tail.seg_len * float(n - 1)
    var sway: float = creature.tail.tip().distance_to(rest_tip)

    hud.text = "T8 smooth    speed %.0f px/s    stretch %.2f  (along %.3f / across %.3f)\ntail sway %.1f px   segment %.2f   yaw %.2f\ngoal %s   centre %s   d %.0f    T: turn   S: slow" % [
        speed, creature.depth_layer.stretch, creature.depth_layer.stretch_along(),
        creature.depth_layer.stretch_across(), sway, creature.tail.seg_len,
        creature.depth_layer.yaw, str(brain.goal.round()), str(centre.round()),
        centre.distance_to(brain.goal)]

    queue_redraw()


func _draw() -> void:
    if creature == null or creature.body == null:
        return
    var g: Vector2 = brain.goal
    draw_circle(g, 30.0, Color(0.2, 0.9, 0.6, 0.08))
    draw_arc(g, 30.0, 0.0, TAU, 32, Color(0.2, 0.9, 0.6, 0.7), 2.0)
    draw_line(g - Vector2(9.0, 0.0), g + Vector2(9.0, 0.0), Color(0.2, 0.9, 0.6), 2.0)
    draw_line(g - Vector2(0.0, 9.0), g + Vector2(0.0, 9.0), Color(0.2, 0.9, 0.6), 2.0)

    draw_line(Vector2(0.0, 560.0), Vector2(1120.0, 560.0), Color(0.55, 0.62, 0.78, 0.10), 2.0)

    # Rest line for the tail, so the lag/sway has a visible reference.
    var n: int = creature.tail.points.size()
    if n > 1:
        var root: Vector2 = creature.tail.points[0]
        var rest_tip: Vector2 = root + creature._secondary_dir() * creature.tail.seg_len * float(n - 1)
        draw_line(root, rest_tip, Color(0.95, 0.80, 0.55, 0.20), 1.0)

    if creature.path != null and creature.path.has_path():
        for i in range(creature.path.index, creature.path.path.size() - 1):
            draw_line(creature.path.path[i], creature.path.path[i + 1],
                Color(0.3, 0.6, 1.0, 0.35), 1.0)
