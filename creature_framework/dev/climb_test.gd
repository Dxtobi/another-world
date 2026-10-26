extends Node2D
## T5 acceptance harness. Run headless:
##   godot --headless --path . res://creature_framework/dev/climb_test.tscn
##
## A vulture with ONLY the climb locomotor starts in a climbing pose on a tall wall:
##
##        +----+  <- goal (near the wall, high up)
##        |    |
##        |  c |  <- creature, spine parallel to the wall
##        |    |
##        +----+
##
## Asserts:
##   * all four limbs take hold before the body moves far,
##   * the creature climbs toward the goal (height gain, then holds near it),
##   * the gait cycles: every limb is released and re-grips at least once,
##   * it sways in/out while climbing (free limbs let the body hang further out),
##   * no body point ever enters terrain,
##   * a second creature in open air (0 grips) sags and loses its horizontal speed
##     instead of chasing its goal.
##
## Prints "CLIMB SUMMARY ..." and exits non-zero on failure.

const WALL := Rect2(340.0, 60.0, 60.0, 440.0)
const SPAWN := Vector2(300.0, 430.0)
const GOAL := Vector2(320.0, 180.0)
const SPINE := 40.0
const CLIMB_FRAMES := 20 * 60
const AIR_SPAWN := Vector2(700.0, 300.0)

var world: WorldQuery
var fails: PackedStringArray = PackedStringArray()
var notes: PackedStringArray = PackedStringArray()


class GoalBrain extends Brain:
    var goal: Vector2 = Vector2.ZERO

    func think(_creature: Creature, intent: Intent, _dt: float) -> void:
        intent.has_goal = true
        intent.goal = goal
        intent.desired_speed = 1.0
        intent.look_dir = Vector2(0.0, -1.0)


func _ready() -> void:
    await _build_level()
    await _climb()
    await _no_grips()
    _report()


# ---------------------------------------------------------------- level

func _build_level() -> void:
    world = WorldQuery.new()
    world.bounds = Rect2(-100.0, -100.0, 1200.0, 900.0)
    _platform(WALL)
    await get_tree().physics_frame
    await get_tree().physics_frame
    await get_tree().physics_frame
    world.attach(self)

    var h: WorldQuery.SurfaceHit = world.surface_near(Vector2(330.0, 300.0), 20.0)
    notes.append("space=%s wall_face=%s" % [
        str(world.space_state != null),
        str(h.pos.round()) if h != null else "NONE"])
    if h == null or absf(h.pos.x - WALL.position.x) > 0.5:
        fails.append("test setup: wall face not found at x %.0f" % WALL.position.x)
    if world.is_solid_point(SPAWN):
        fails.append("test setup: the climbing spawn is inside terrain")


# ---------------------------------------------------------------- climb

func _climb() -> void:
    var c: Creature = Creature.new()
    add_child(c)
    var brain: GoalBrain = GoalBrain.new()
    brain.goal = GOAL
    c.setup(_climb_rig(), brain, world, SPAWN)
    _pose_upright(c)

    var start: Vector2 = c.body.pos[c.rig.center_point]
    var min_y: float = start.y
    var closest: float = start.distance_to(GOAL)
    var reached_at: float = -1.0
    var first_all: float = -1.0
    var grips_seen: int = 0
    var releases_seen: int = 0
    var transitions: int = 0
    var prev_mask: int = 0
    var violations: int = 0
    var x_min: float = 99999.0
    var x_max: float = -99999.0
    var y_min: float = 99999.0

    for frame in CLIMB_FRAMES:
        await get_tree().physics_frame
        var centre: Vector2 = c.body.pos[c.rig.center_point]
        var mask: int = _grip_mask(c)
        grips_seen |= mask
        releases_seen |= prev_mask & ~mask
        if mask != prev_mask:
            transitions += 1
        prev_mask = mask

        if mask == 15 and first_all < 0.0:
            first_all = float(frame + 1) / 60.0

        min_y = minf(min_y, centre.y)
        y_min = minf(y_min, centre.y)
        closest = minf(closest, centre.distance_to(GOAL))
        if reached_at < 0.0 and centre.distance_to(GOAL) <= 30.0:
            reached_at = float(frame + 1) / 60.0
        if frame > 60:
            x_min = minf(x_min, centre.x)
            x_max = maxf(x_max, centre.x)

        for k in c.body.pos.size():
            if world.is_solid_point(c.body.pos[k]):
                violations += 1

    var climbed: float = start.y - min_y
    var sway: float = x_max - x_min if x_max >= x_min else 0.0
    notes.append("climb start=%s min_y=%.1f climbed=%.1f closest=%.1f reached_at=%.2f" % [
        str(start.round()), min_y, climbed, closest, reached_at])
    notes.append("gait first_all=%.2fs transitions=%d grips_seen=%s releases_seen=%s" % [
        first_all, transitions, _mask_str(grips_seen), _mask_str(releases_seen)])
    notes.append("sway x=[%.1f, %.1f] range=%.2f violations=%d" % [
        x_min, x_max, sway, violations])

    if first_all < 0.0 or grips_seen != 15:
        fails.append("not all four limbs took hold (seen %s)" % _mask_str(grips_seen))
    if climbed < 120.0:
        fails.append("climbed only %.1f px in %d s" % [climbed, CLIMB_FRAMES / 60])
    if reached_at < 0.0:
        fails.append("never arrived near the goal (closest %.1f px)" % closest)
    if releases_seen != 15:
        fails.append("some limbs never let go and re-reached (released %s)" % _mask_str(releases_seen))
    if transitions < 8:
        fails.append("gait barely cycled (%d grip changes)" % transitions)
    if sway < 1.0:
        fails.append("no visible sway (x range %.2f px)" % sway)
    if violations > 0:
        fails.append("body point inside terrain %d times" % violations)

    c.queue_free()


# ---------------------------------------------------------------- no grips

func _no_grips() -> void:
    var c: Creature = Creature.new()
    add_child(c)
    var brain: GoalBrain = GoalBrain.new()
    brain.goal = AIR_SPAWN + Vector2(250.0, 0.0)
    c.setup(_climb_rig(), brain, world, AIR_SPAWN)
    # Shove it toward the goal: with no purchase it must coast down and slow, not climb.
    var dt: float = 1.0 / 60.0
    for i in c.body.pos.size():
        c.body.prev[i] = c.body.pos[i] - Vector2(180.0, 0.0) * dt

    var start: Vector2 = c.body.pos[c.rig.center_point]
    var start_vx: float = c.body.velocity(c.rig.center_point, dt).x
    var grips_latched: int = 0

    for _frame in 60:
        await get_tree().physics_frame
        grips_latched = maxi(grips_latched, _grip_mask(c))

    var centre: Vector2 = c.body.pos[c.rig.center_point]
    var vx: float = c.body.velocity(c.rig.center_point, dt).x
    var sag: float = centre.y - start.y
    notes.append("no-grips sag=%.1f vx=%.1f->%.1f grips=%s" % [
        sag, start_vx, vx, _mask_str(grips_latched)])

    if grips_latched != 0:
        fails.append("the open-air creature found a grip (%s)" % _mask_str(grips_latched))
    if sag < 100.0:
        fails.append("0-grip creature did not sag (%.1f px in 1 s)" % sag)
    if vx > start_vx * 0.75:
        fails.append("0-grip creature kept its horizontal momentum (%.1f -> %.1f)" % [start_vx, vx])
    if vx > 100.0:
        fails.append("0-grip creature is chasing its goal horizontally (vx %.1f)" % vx)

    c.queue_free()


# ---------------------------------------------------------------- helpers

func _climb_rig() -> CreatureRig:
    var rig: CreatureRig = VultureRig.build()
    rig.locomotors.clear()
    rig.locomotors.append(ClimbLocomotor)
    return rig


## Put the spine parallel to the wall, head up, so T5 starts in a climbing pose (T6 will
## handle the fly -> climb transition).
func _pose_upright(c: Creature) -> void:
    var pts: Array[Vector2] = [
        SPAWN + Vector2(0.0, -SPINE),
        SPAWN,
        SPAWN + Vector2(0.0, SPINE),
    ]
    for i in c.body.pos.size():
        c.body.pos[i] = pts[i]
        c.body.prev[i] = pts[i]


func _grip_mask(c: Creature) -> int:
    var mask: int = 0
    for i in c.rig.limbs.size():
        if c.limbs.is_gripping(i):
            mask |= 1 << i
    return mask


func _mask_str(mask: int) -> String:
    var s: String = ""
    for i in 4:
        s += "1" if mask & (1 << i) else "0"
    return s


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
        print("CLIMB NOTE ", n)
    if fails.is_empty():
        print("CLIMB SUMMARY PASS notes=%d" % notes.size())
        get_tree().quit(0)
    else:
        for f in fails:
            print("CLIMB FAIL ", f)
        print("CLIMB SUMMARY FAIL fails=%d" % fails.size())
        get_tree().quit(1)
