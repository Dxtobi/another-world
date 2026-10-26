extends Node2D
## Live T5 demo. Open this scene in the editor and press F6.
##
## The goal marker slides up and down the wall, so the vulture climbs up, holds, then climbs
## back down. Limbs release only while two others still hold (the gait), so the motion should
## read as hand-over-hand with a small in/out sway. The HUD shows the grip count; 0 grips is
## the sag case (move the goal off the wall by editing GOAL_X to see it).

const WALL := Rect2(340.0, 60.0, 60.0, 440.0)
const SPAWN := Vector2(300.0, 430.0)
const SPINE := 40.0
const GOAL_X := 320.0
const WALL_TINT := Color(0.17, 0.16, 0.20)

var world: WorldQuery
var creature: Creature
var brain: GoalBrain
var cam: Camera2D
var hud: Label
var _t: float = 0.0
var _log: float = 0.0


class GoalBrain extends Brain:
    var goal: Vector2 = Vector2.ZERO

    func think(creature: Creature, intent: Intent, _dt: float) -> void:
        intent.has_goal = true
        intent.goal = goal
        intent.desired_speed = 1.0
        var d: Vector2 = goal - creature.body.pos[creature.rig.center_point]
        intent.look_dir = Vector2(signf(d.x), signf(d.y))


func _ready() -> void:
    _build_wall()
    await get_tree().physics_frame
    await get_tree().physics_frame
    await get_tree().physics_frame

    world = WorldQuery.new()
    world.bounds = Rect2(-100.0, -100.0, 1200.0, 900.0)
    world.attach(self)

    brain = GoalBrain.new()
    brain.goal = Vector2(GOAL_X, 180.0)
    var rig: CreatureRig = VultureRig.build()
    rig.locomotors.clear()
    rig.locomotors.append(ClimbLocomotor)
    creature = Creature.new()
    add_child(creature)
    creature.setup(rig, brain, world, SPAWN)
    _pose_upright()
    brain.goal = creature.body.pos[creature.rig.center_point] + Vector2(20.0, -250.0)

    cam = Camera2D.new()
    cam.position = SPAWN
    cam.zoom = Vector2(1.4, 1.4)
    add_child(cam)
    cam.make_current()

    var layer: CanvasLayer = CanvasLayer.new()
    add_child(layer)
    hud = Label.new()
    hud.position = Vector2(16.0, 12.0)
    hud.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
    layer.add_child(hud)

    print("CLIMB DEMO ready")


func _process(dt: float) -> void:
    if creature == null:
        return
    _t += dt
    # Slide the goal along the wall between y 180 and y 380.
    brain.goal = Vector2(GOAL_X, 280.0 + sin(_t * 0.45) * 100.0)

    var centre: Vector2 = creature.body.pos[creature.rig.center_point]
    var follow: Vector2 = Vector2(320.0, clampf(centre.y, 220.0, 400.0))
    cam.global_position = cam.global_position.lerp(follow, 1.0 - exp(-4.0 * dt))
    hud.text = "T5 climb    grips %d/%d    y %.0f    goal y %.0f" % [
        creature.limbs.grip_count(), creature.rig.limbs.size(), centre.y, brain.goal.y]

    _log += dt
    if _log >= 2.0:
        _log = 0.0
        print("CLIMB DEMO t=%.0f grips=%d centre=%s" % [
            _t, creature.limbs.grip_count(), str(centre.round())])


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


func _pose_upright() -> void:
    var pts: Array[Vector2] = [
        SPAWN + Vector2(0.0, -SPINE),
        SPAWN,
        SPAWN + Vector2(0.0, SPINE),
    ]
    for i in creature.body.pos.size():
        creature.body.pos[i] = pts[i]
        creature.body.prev[i] = pts[i]
