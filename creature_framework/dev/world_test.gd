extends Node2D
## T2 acceptance harness. Run headless:
##   godot --headless --path . res://creature_framework/dev/world_test.tscn
##
## Phase A - the REAL level (`scenes/world/test_scene.tscn`):
##   * `is_solid` is compared against an independent oracle: every enabled
##     CollisionPolygon2D on a terrain-layer StaticBody2D, via Geometry2D.
##   * a vulture is flown into the ground for 7 s; no body point may end up inside.
##
## Phase B - a synthetic level built in code (floor + tower + ceiling with a gap):
##   * `path_air` routes OVER the tower instead of through it.
##   * `path_air` threads the ceiling gap when both ends are above the ceiling.
##   * `path_surface` runs along the floor top.
##
## Prints "WORLD SUMMARY ..." and exits non-zero on failure.

const LEVEL_SCENE := preload("res://scenes/world/test_scene.tscn")

const CELL := 24.0
const REAL_REGION := Rect2(-400.0, 150.0, 1700.0, 650.0)

var world: WorldQuery
var fails: PackedStringArray = PackedStringArray()
var notes: PackedStringArray = PackedStringArray()


class DiveBrain extends Brain:
    var goal: Vector2 = Vector2.ZERO

    func think(_creature: Creature, intent: Intent, _dt: float) -> void:
        intent.has_goal = true
        intent.goal = goal
        intent.desired_speed = 1.0
        intent.urgency = 1.0
        intent.look_dir = Vector2.RIGHT


func _ready() -> void:
    await _phase_real_level()
    await _phase_synthetic()
    _report()


# ---------------------------------------------------------------- phase A

func _phase_real_level() -> void:
    var level: Node2D = LEVEL_SCENE.instantiate()
    add_child(level)
    await get_tree().physics_frame
    await get_tree().physics_frame

    world = WorldQuery.new()
    world.bounds = Rect2(-2000.0, -600.0, 6000.0, 2600.0)
    world.attach(level)

    var polys: Array[PackedVector2Array] = _terrain_polys(level)
    notes.append("level polys=%d" % polys.size())
    if polys.is_empty():
        fails.append("no terrain polygons found in the real level")
    _check_oracle(polys)
    await _dive_test()

    level.queue_free()
    await get_tree().physics_frame
    await get_tree().physics_frame


## Independent truth: the drawn polygons, not the physics engine answering itself.
func _check_oracle(polys: Array[PackedVector2Array]) -> void:
    var tested: int = 0
    var bad: int = 0
    var first_bad: String = ""
    var x: float = REAL_REGION.position.x
    while x <= REAL_REGION.end.x:
        var y: float = REAL_REGION.position.y
        while y <= REAL_REGION.end.y:
            var p: Vector2 = Vector2(x, y)
            if not _near_edge(p, polys, 5.0):
                tested += 1
                var expected: bool = _inside_any(p, polys)
                if world.is_solid(p) != expected:
                    bad += 1
                    if first_bad == "":
                        first_bad = "%s expected=%s" % [str(p.round()), str(expected)]
            y += 21.0
        x += 21.0
    notes.append("oracle samples=%d mismatches=%d" % [tested, bad])
    if bad > 0:
        fails.append("is_solid disagrees with drawn polygons at %d points (first %s)" % [bad, first_bad])


func _terrain_polys(level: Node) -> Array[PackedVector2Array]:
    var out: Array[PackedVector2Array] = []
    for body in level.find_children("*", "StaticBody2D", true, false):
        var sb: StaticBody2D = body as StaticBody2D
        if sb == null or int(sb.collision_layer) & world.solid_mask == 0:
            continue
        for child in sb.get_children():
            var cp: CollisionPolygon2D = child as CollisionPolygon2D
            if cp == null or cp.disabled or cp.polygon.size() < 3:
                continue
            var pts: PackedVector2Array = PackedVector2Array()
            for v in cp.polygon:
                pts.append(cp.global_transform * v)
            out.append(pts)
    return out


func _inside_any(p: Vector2, polys: Array[PackedVector2Array]) -> bool:
    for poly in polys:
        if Geometry2D.is_point_in_polygon(p, poly):
            return true
    return false


func _near_edge(p: Vector2, polys: Array[PackedVector2Array], margin: float) -> bool:
    for poly in polys:
        for i in poly.size():
            var a: Vector2 = poly[i]
            var b: Vector2 = poly[(i + 1) % poly.size()]
            var ab: Vector2 = b - a
            var t: float = clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
            if p.distance_to(a + ab * t) < margin:
                return true
    return false


## Fly a real creature straight into the ground; the solver must keep every point out.
func _dive_test() -> void:
    var creature: Creature = Creature.new()
    add_child(creature)
    var brain: DiveBrain = DiveBrain.new()
    brain.goal = Vector2(400.0, 1600.0)
    creature.setup(VultureRig.build(), brain, world, Vector2(400.0, 250.0))

    var violations: int = 0
    var worst: Vector2 = Vector2.INF
    for _i in 420:
        await get_tree().physics_frame
        for k in creature.body.pos.size():
            if world.is_solid_point(creature.body.pos[k]):
                violations += 1
                if worst == Vector2.INF:
                    worst = creature.body.pos[k]
    creature.queue_free()
    await get_tree().physics_frame
    notes.append("dive 7s violations=%d" % violations)
    if violations > 0:
        fails.append("body point inside terrain %d times (first %s)" % [violations, str(worst.round())])


# ---------------------------------------------------------------- phase B

func _phase_synthetic() -> void:
    world = WorldQuery.new()
    world.bounds = Rect2(-100.0, -100.0, 1400.0, 800.0)
    world.cell_size = CELL

    # floor | tower | ceiling with a gap at x 640..700
    _platform(PackedVector2Array([
        Vector2(0, 500), Vector2(1200, 500), Vector2(1200, 560), Vector2(0, 560)]))
    _platform(PackedVector2Array([
        Vector2(500, 260), Vector2(580, 260), Vector2(580, 500), Vector2(500, 500)]))
    _platform(PackedVector2Array([
        Vector2(0, 60), Vector2(640, 60), Vector2(640, 100), Vector2(0, 100)]))
    _platform(PackedVector2Array([
        Vector2(700, 60), Vector2(1200, 60), Vector2(1200, 100), Vector2(700, 100)]))

    await get_tree().physics_frame
    world.attach(self)
    world.bake(Rect2(0.0, 0.0, 1200.0, 600.0))

    _check_air_route("over the tower",
        Vector2(120.0, 420.0), Vector2(1080.0, 420.0),
        func(p: Vector2) -> bool: return p.y < 260.0)
    _check_air_route("through the ceiling gap",
        Vector2(120.0, 30.0), Vector2(1080.0, 30.0),
        func(p: Vector2) -> bool: return p.x > 600.0 and p.x < 720.0)
    _check_surface_route("along the floor top",
        Vector2(120.0, 490.0), Vector2(420.0, 490.0))


func _check_air_route(label: String, from: Vector2, to: Vector2, detour: Callable) -> void:
    var path: PackedVector2Array = world.path_air(from, to)
    if path.size() < 2:
        fails.append("air path (%s) is empty" % label)
        return
    var solid_steps: int = 0
    var hit_detour: bool = false
    for p in path:
        if world.is_solid_point(p):
            solid_steps += 1
        if detour.call(p):
            hit_detour = true
    notes.append("air path (%s) waypoints=%d solid=%d detour=%s" % [label, path.size(), solid_steps, str(hit_detour)])
    if solid_steps > 0:
        fails.append("air path (%s) crosses terrain (%d waypoints)" % [label, solid_steps])
    if not hit_detour:
        fails.append("air path (%s) did not take the expected detour" % label)


func _check_surface_route(label: String, from: Vector2, to: Vector2) -> void:
    var path: PackedVector2Array = world.path_surface(from, to)
    if path.size() < 2:
        fails.append("surface path (%s) is empty" % label)
        return
    var off_surface: int = 0
    for p in path:
        if world.is_solid_point(p) or p.y < 440.0 or p.y > 500.0:
            off_surface += 1
    notes.append("surface path (%s) waypoints=%d off=%d" % [label, path.size(), off_surface])
    if off_surface > 0:
        fails.append("surface path (%s) left the floor band (%d waypoints)" % [label, off_surface])


func _platform(points: PackedVector2Array) -> void:
    var body: StaticBody2D = StaticBody2D.new()
    var poly: CollisionPolygon2D = CollisionPolygon2D.new()
    poly.polygon = points
    body.add_child(poly)
    add_child(body)


# ---------------------------------------------------------------- report

func _report() -> void:
    for n in notes:
        print("WORLD NOTE ", n)
    if fails.is_empty():
        print("WORLD SUMMARY PASS notes=%d" % notes.size())
        get_tree().quit(0)
    else:
        for f in fails:
            print("WORLD FAIL ", f)
        print("WORLD SUMMARY FAIL fails=%d" % fails.size())
        get_tree().quit(1)
