extends Node2D
## Live T6 demo. Open this scene in the editor and press F6.
##
## One vulture, one wall, and a goal that moves between the wall and open air:
##
##   LAND    goal on the wall, high up      -> flyer lands (fly -> climb)
##   CLIMB   hold the wall goal             -> hand-over-hand climb
##   LAUNCH  goal into open air             -> push off the wall (climb -> fly)
##   RETURN  goal back on the wall, lower   -> fly around/over and land again
##
## It then repeats launch/return, so the mode HUD keeps cycling. The HUD shows the current
## locomotor, blend weights and grip count; a 0-grip frame is the sag case.

const WALL := Rect2(340.0, 60.0, 60.0, 440.0)
const SPAWN := Vector2(140.0, 350.0)
const WALL_GOAL_HIGH := Vector2(320.0, 180.0)
const WALL_GOAL_LOW := Vector2(320.0, 420.0)
const OPEN_GOAL := Vector2(100.0, 240.0)
const GOAL_RADIUS := 44.0
const HOLD_TIME := 1.5
const WALL_TINT := Color(0.17, 0.16, 0.20)

var world: WorldQuery
var creature: Creature
var brain: GoalBrain
var cam: Camera2D
var hud: Label
var _phase: String = "land"
var _hold: float = 0.0
var _t: float = 0.0
var _log: float = 0.0
var _last_mode: StringName = &""


class GoalBrain extends Brain:
    var goal: Vector2 = Vector2.ZERO

    func think(creature: Creature, intent: Intent, _dt: float) -> void:
        intent.has_goal = true
        intent.goal = goal
        intent.desired_speed = 1.0
        var d: Vector2 = goal - creature.body.pos[creature.rig.center_point]
        intent.look_dir = d.normalized() if d.length_squared() > 0.01 else Vector2.RIGHT


func _ready() -> void:
    _build_wall()
    for _i in 3:
        await get_tree().physics_frame

    world = WorldQuery.new()
    world.bounds = Rect2(-100.0, -100.0, 1200.0, 900.0)
    world.attach(self)
    # The vulture spine is 80 px; give the air grid room for a whole body.
    world.path_clearance = 58.0
    world.bake(world.bounds)

    brain = GoalBrain.new()
    brain.goal = WALL_GOAL_HIGH
    creature = Creature.new()
    add_child(creature)
    creature.setup(VultureRig.build(), brain, world, SPAWN)

    cam = Camera2D.new()
    cam.position = SPAWN
    cam.zoom = Vector2(1.25, 1.25)
    add_child(cam)
    cam.make_current()

    var layer: CanvasLayer = CanvasLayer.new()
    add_child(layer)
    hud = Label.new()
    hud.position = Vector2(16.0, 12.0)
    hud.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
    layer.add_child(hud)

    print("MODE DEMO ready")


func _process(dt: float) -> void:
    if creature == null or creature.body == null:
        return
    _t += dt
    var mode: StringName = creature.loco.current.id
    var centre: Vector2 = creature.body.pos[creature.rig.center_point]
    var dist: float = centre.distance_to(brain.goal)
    var reached: bool = dist <= GOAL_RADIUS

    if mode != _last_mode:
        if _last_mode != &"":
            print("MODE DEMO t=%.1f switch %s -> %s grips=%d vx=%.1f phase=%s" % [
                _t, _last_mode, mode, creature.limbs.grip_count(),
                creature.body.velocity(creature.rig.center_point, dt).x, _phase])
        _last_mode = mode

    _hold = _hold + dt if reached else 0.0
    if _hold >= HOLD_TIME:
        _advance()

    var follow: Vector2 = Vector2(300.0, clampf(centre.y, 180.0, 500.0))
    cam.global_position = cam.global_position.lerp(follow, 1.0 - exp(-3.0 * dt))

    var weights: PackedStringArray = PackedStringArray()
    for l in creature.loco.locomotors:
        weights.append("%s %.2f" % [l.id, l.weight])
    hud.text = "T6 mode switch    phase %s    mode %s    grips %d/%d\n%s\ncentre %s   goal %s   d %.0f" % [
        _phase, mode, creature.limbs.grip_count(), creature.rig.limbs.size(),
        "  ".join(weights), str(centre.round()), str(brain.goal.round()), dist]

    _log += dt
    if _log >= 2.0:
        _log = 0.0
        print("MODE DEMO t=%.0f phase=%s mode=%s grips=%d centre=%s" % [
            _t, _phase, mode, creature.limbs.grip_count(), str(centre.round())])

    queue_redraw()


func _advance() -> void:
    _hold = 0.0
    match _phase:
        "land":
            _phase = "launch"
            brain.goal = OPEN_GOAL
        "launch":
            _phase = "return"
            brain.goal = WALL_GOAL_LOW
        _:
            # return / relaunch alternate forever
            _phase = "relaunch" if _phase == "return" else "return"
            brain.goal = OPEN_GOAL if _phase == "relaunch" else WALL_GOAL_LOW


func _draw() -> void:
    if creature == null or creature.body == null:
        return
    # Goal marker.
    var g: Vector2 = brain.goal
    draw_circle(g, GOAL_RADIUS, Color(0.2, 0.9, 0.6, 0.10))
    draw_arc(g, GOAL_RADIUS, 0.0, TAU, 32, Color(0.2, 0.9, 0.6, 0.8), 2.0)
    draw_line(g - Vector2(8.0, 0.0), g + Vector2(8.0, 0.0), Color(0.2, 0.9, 0.6), 2.0)
    draw_line(g - Vector2(0.0, 8.0), g + Vector2(0.0, 8.0), Color(0.2, 0.9, 0.6), 2.0)
    # Air path the flyer is following.
    if creature.path != null and creature.path.path.size() > 1:
        for i in range(creature.path.index, creature.path.path.size() - 1):
            draw_line(creature.path.path[i], creature.path.path[i + 1], Color(0.3, 0.6, 1.0, 0.35), 1.0)


func _build_wall() -> void:
    var visual: Polygon2D = Polygon2D.new()
    visual.polygon = PackedVector2Array([
        WALL.position,
        Vector2(WALL.end.x, WALL.position.y),
        WALL.end,
        Vector2(WALL.position.x, WALL.end.y),
    ])
    visual.color = WALL_TINT
    add_child(visual)

    var body: StaticBody2D = StaticBody2D.new()
    var poly: CollisionPolygon2D = CollisionPolygon2D.new()
    poly.polygon = visual.polygon
    body.add_child(poly)
    add_child(body)
