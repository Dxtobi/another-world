extends Node2D
## Creature playground. Pick a rig scene in the inspector, press F6, chase the mouse.
##
## No code per creature: `rig_scene` is a path, baked through `RigBlueprint.load_rig()`. The
## level is a floor, a wall and a ledge, so flight, landing and climbing all have somewhere to
## go. The HUD shows the mode blend and the grip count; the path overlay is the flyer's current
## A* route.
##
## Editing a rig while the game runs: save the scene, then press R to rebuild in place.

const FLOOR := Rect2(60.0, 560.0, 900.0, 60.0)
const WALL := Rect2(640.0, 140.0, 56.0, 480.0)
const LEDGE := Rect2(800.0, 300.0, 160.0, 24.0)
const BOUNDS := Rect2(-100.0, -100.0, 1200.0, 820.0)
const TINT := Color(0.17, 0.16, 0.20)
const GRID := Color(0.55, 0.62, 0.78, 0.07)

@export_file("*.tscn") var rig_scene: String = "res://creature_framework/creatures/vulture.tscn"
@export var spawn: Vector2 = Vector2(240.0, 380.0)
## Air-grid clearance. The vulture spine is 80 px, so 58 px lets a whole body round a corner.
@export_range(8.0, 200.0, 1.0) var path_clearance: float = 58.0
@export var show_path: bool = true

var world: WorldQuery
var creature: Creature
var brain: MouseBrain
var cam: Camera2D
var hud: Label
var _error: String = ""


func _ready() -> void:
    _build_level()
    for _i in 3:
        await get_tree().physics_frame

    world = WorldQuery.new()
    world.bounds = BOUNDS
    world.attach(self)
    world.path_clearance = path_clearance
    world.bake(BOUNDS)

    brain = MouseBrain.new()

    cam = Camera2D.new()
    cam.position = spawn
    cam.zoom = Vector2(1.15, 1.15)
    add_child(cam)
    cam.make_current()

    var layer: CanvasLayer = CanvasLayer.new()
    add_child(layer)
    hud = Label.new()
    hud.position = Vector2(16.0, 12.0)
    hud.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
    layer.add_child(hud)

    _spawn()
    print("PLAYGROUND ready rig=%s" % rig_scene)


func _unhandled_input(event: InputEvent) -> void:
    if world == null or hud == null:
        return
    if event is InputEventKey and event.pressed and not event.echo \
            and (event as InputEventKey).keycode == KEY_R:
        _spawn()


## Build the rig from the exported scene path. Reused by R so a saved rig can be retried
## without restarting; `fresh` skips the resource cache for that.
func _spawn() -> void:
    if creature != null:
        remove_child(creature)
        creature.queue_free()
        creature = null

    var rig: CreatureRig = RigBlueprint.load_rig(rig_scene, true)
    if rig == null:
        _error = "could not build %s — see Output" % rig_scene.get_file()
        push_error("PLAYGROUND: %s" % _error)
        return
    _error = ""

    creature = Creature.new()
    add_child(creature)
    creature.setup(rig, brain, world, spawn)
    print("PLAYGROUND spawn %s points=%d limbs=%d" % [
        rig_scene.get_file(), rig.points.size(), rig.limbs.size()])


func _process(dt: float) -> void:
    if creature != null:
        var centre: Vector2 = creature.body.pos[creature.rig.center_point]
        var follow: Vector2 = Vector2(centre.x, clampf(centre.y, 220.0, 500.0))
        cam.global_position = cam.global_position.lerp(follow, 1.0 - exp(-3.0 * dt))
    _update_hud()
    queue_redraw()


func _update_hud() -> void:
    if hud == null:
        return
    if creature == null:
        hud.text = "PLAYGROUND  %s\n%s\n\nmouse: goal    R: reload rig" % [
            rig_scene.get_file(), _error]
        return

    var mode: StringName = creature.loco.current.id
    var weights: PackedStringArray = PackedStringArray()
    for loco in creature.loco.locomotors:
        weights.append("%s %.2f" % [loco.id, loco.weight])
    var centre: Vector2 = creature.body.pos[creature.rig.center_point]
    hud.text = "PLAYGROUND  %s    mouse: goal    R: reload rig\npoints %d   limbs %d   mode %s   grips %d/%d\n%s\ngoal %s   d %.0f" % [
        rig_scene.get_file(), creature.rig.points.size(), creature.rig.limbs.size(),
        mode, creature.limbs.grip_count(), creature.rig.limbs.size(),
        "  ".join(weights), str(creature.intent.goal.round()),
        centre.distance_to(creature.intent.goal)]


func _draw() -> void:
    _draw_grid()
    if creature == null:
        return

    var goal: Vector2 = creature.intent.goal
    draw_circle(goal, 22.0, Color(0.2, 0.9, 0.6, 0.10))
    draw_arc(goal, 22.0, 0.0, TAU, 24, Color(0.2, 0.9, 0.6, 0.7), 1.5)
    draw_line(goal - Vector2(7.0, 0.0), goal + Vector2(7.0, 0.0), Color(0.2, 0.9, 0.6), 1.5)
    draw_line(goal - Vector2(0.0, 7.0), goal + Vector2(0.0, 7.0), Color(0.2, 0.9, 0.6), 1.5)

    if show_path and creature.path != null and creature.path.path.size() > 1:
        for i in range(creature.path.index, creature.path.path.size() - 1):
            draw_line(creature.path.path[i], creature.path.path[i + 1],
                Color(0.3, 0.6, 1.0, 0.35), 1.0)


func _draw_grid() -> void:
    var step: float = 50.0
    var x: float = floorf(BOUNDS.position.x / step) * step
    while x <= BOUNDS.end.x:
        draw_line(Vector2(x, BOUNDS.position.y), Vector2(x, BOUNDS.end.y), GRID, 1.0)
        x += step
    var y: float = floorf(BOUNDS.position.y / step) * step
    while y <= BOUNDS.end.y:
        draw_line(Vector2(BOUNDS.position.x, y), Vector2(BOUNDS.end.x, y), GRID, 1.0)
        y += step


func _build_level() -> void:
    _solid(FLOOR)
    _solid(WALL)
    _solid(LEDGE)


## One drawn rectangle that is also terrain for WorldQuery (StaticBody2D + polygon).
func _solid(rect: Rect2) -> void:
    var visual: Polygon2D = Polygon2D.new()
    visual.polygon = PackedVector2Array([
        rect.position,
        Vector2(rect.end.x, rect.position.y),
        rect.end,
        Vector2(rect.position.x, rect.end.y),
    ])
    visual.color = TINT
    add_child(visual)

    var body: StaticBody2D = StaticBody2D.new()
    var poly: CollisionPolygon2D = CollisionPolygon2D.new()
    poly.polygon = visual.polygon
    body.add_child(poly)
    add_child(body)
