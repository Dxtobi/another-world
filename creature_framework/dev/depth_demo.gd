extends Node2D
## Live T7 demo. Open this scene in the editor and press F6.
##
## The vulture flies between a left and a right goal. Each crossing is a full turnaround:
## yaw sweeps through PI/2 (the front/back view), the body squashes, the far limbs darken
## and shrink, and the near/far draw order swaps at edge-on. The HUD shows the numbers the
## debug view is using; the console logs each swap.
##
## No terrain: this is the cleanest read of depth alone. For depth + climb, run
## `dev/mode_demo.tscn` or the playground.

const SPAWN := Vector2(560.0, 320.0)
const LEFT_GOAL := Vector2(220.0, 220.0)
const RIGHT_GOAL := Vector2(900.0, 220.0)
const ARRIVE := 70.0
const HOLD := 1.6

var world: WorldQuery
var creature: Creature
var brain: GoalBrain
var cam: Camera2D
var hud: Label
var _goal: Vector2 = RIGHT_GOAL
var _hold: float = 0.0
var _t: float = 0.0
var _last_sign: int = 1
var _swaps: int = 0
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

    print("DEPTH DEMO ready")


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
                print("DEPTH DEMO slowmo %s" % str(_slow))


func _exit_tree() -> void:
    Engine.time_scale = 1.0


func _flip_goal() -> void:
    _hold = 0.0
    _goal = LEFT_GOAL if brain.goal == RIGHT_GOAL else RIGHT_GOAL
    brain.goal = _goal
    print("DEPTH DEMO t=%.1f goal %s (T)" % [_t, str(_goal.round())])


func _process(dt: float) -> void:
    if creature == null or creature.body == null:
        return
    _t += dt
    var centre: Vector2 = creature.body.pos[creature.rig.center_point]

    if centre.distance_to(brain.goal) <= ARRIVE:
        _hold += dt
        if _hold >= HOLD:
            _flip_goal()
    else:
        _hold = 0.0

    var near_d: float = creature.depth_layer.depth_of(1.0)
    var far_d: float = creature.depth_layer.depth_of(-1.0)
    var sign_now: int = 1 if near_d >= 0.0 else -1
    if sign_now != _last_sign:
        _last_sign = sign_now
        _swaps += 1
        print("DEPTH DEMO t=%.1f swap yaw=%.2f squash=%.2f near=%.2f far=%.2f" % [
            _t, creature.depth_layer.yaw, creature.depth_layer.squash, near_d, far_d])

    var follow: Vector2 = Vector2(560.0, clampf(centre.y, 220.0, 480.0))
    cam.global_position = cam.global_position.lerp(follow, 1.0 - exp(-3.0 * dt))

    hud.text = "T7 depth    yaw %.2f    squash %.2f    facing %+.2f    swaps %d\nnear %+.2f   far %+.2f   draw order %s\ngoal %s   centre %s   d %.0f    T: turn   S: slow" % [
        creature.depth_layer.yaw, creature.depth_layer.squash, creature.facing, _swaps,
        near_d, far_d, "far -> near" if near_d >= 0.0 else "near -> far",
        str(brain.goal.round()), str(centre.round()), centre.distance_to(brain.goal)]

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

    if creature.path != null and creature.path.has_path():
        for i in range(creature.path.index, creature.path.path.size() - 1):
            draw_line(creature.path.path[i], creature.path.path[i + 1],
                Color(0.3, 0.6, 1.0, 0.35), 1.0)
