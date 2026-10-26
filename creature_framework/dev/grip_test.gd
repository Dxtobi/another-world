extends Node2D
## T4 acceptance harness. Run headless:
##   godot --headless --path . res://creature_framework/dev/grip_test.tscn
##
## A vulture hovers between a near wall and a far block:
##
##        (sky)
##                        +----+
##      creature  ->      |wall|          +----+
##                        |    |          |far |
##                        +----+          +----+
##
## Asserts:
##   * `WorldQuery.surface_near` returns the wall face, its outward normal and the distance,
##     and returns null in thin air.
##   * A wing reaches the near wall and latches onto it (x = wall face, normal points back
##     at the creature). Its tip is pinned to that point on the next tick.
##   * A limb never latches onto thin air, nor onto a surface beyond its `max_reach`.
##   * A held grip survives a small body move and is released when over-extended.
##
## Prints "GRIP SUMMARY ..." and exits non-zero on failure.

const SPAWN := Vector2(250.0, 300.0)
const WALL := Rect2(340.0, 150.0, 60.0, 300.0)
const FAR := Rect2(600.0, 250.0, 60.0, 100.0)
const REACH_SCALE := 1.25

var world: WorldQuery
var creature: Creature
var wing_near: int = -1
var wing_far: int = -1
var leg_near: int = -1
var fails: PackedStringArray = PackedStringArray()
var notes: PackedStringArray = PackedStringArray()


func _ready() -> void:
    await _build_level()
    _check_probe()
    _add_creature()
    _check_near_wall()
    _check_air()
    _check_reach()
    _check_hold_and_release()
    await _check_tick_and_draw()
    _report()


# ---------------------------------------------------------------- level

func _build_level() -> void:
    world = WorldQuery.new()
    world.bounds = Rect2(-100.0, -100.0, 1000.0, 800.0)
    _platform(WALL)
    _platform(FAR)

    # The polygons must exist in the physics server before rays can hit them.
    await get_tree().physics_frame
    await get_tree().physics_frame
    await get_tree().physics_frame
    world.attach(self)
    notes.append("space=%s wall=%s far=%s" % [
        str(world.space_state != null), str(WALL), str(FAR)])
    if world.space_state == null:
        fails.append("test setup: no physics space attached")


func _check_probe() -> void:
    var h: WorldQuery.SurfaceHit = world.surface_near(Vector2(332.0, 300.0), 12.0)
    if h == null:
        fails.append("surface_near found nothing 8 px from the wall")
        return
    var on_face: bool = absf(h.pos.x - WALL.position.x) <= 0.5
    var faces_back: bool = h.normal.x < -0.9
    var dist_ok: bool = absf(h.distance - 8.0) <= 0.5
    notes.append("probe face=%s pos=%s normal=%s dist=%.2f" % [
        str(on_face), str(h.pos.round()), str(h.normal.round()), h.distance])
    if not on_face:
        fails.append("surface_near did not return the wall face (x %.2f)" % h.pos.x)
    if not faces_back:
        fails.append("surface_near normal points into the wall: %s" % str(h.normal))
    if not dist_ok:
        fails.append("surface_near distance was %.2f, expected 8" % h.distance)

    if world.surface_near(Vector2(250.0, 120.0), 40.0) != null:
        fails.append("surface_near found a surface in thin air")
    if not world.is_solid_adjacent(Vector2(335.0, 300.0), 12.0):
        fails.append("is_solid_adjacent missed the wall")
    if world.is_solid_adjacent(SPAWN, 12.0):
        fails.append("is_solid_adjacent claimed terrain at the spawn point")


func _add_creature() -> void:
    creature = Creature.new()
    add_child(creature)
    creature.setup(VultureRig.build(), Brain.new(), world, SPAWN)
    for i in creature.rig.limbs.size():
        match creature.rig.limbs[i].name:
            &"wing_near": wing_near = i
            &"wing_far": wing_far = i
            &"leg_near": leg_near = i
    notes.append("limbs=%d wing_near=%d wing_far=%d leg_near=%d wing_max_reach=%.1f leg_max_reach=%.1f" % [
        creature.rig.limbs.size(), wing_near, wing_far, leg_near,
        creature.limbs.max_reach(wing_near), creature.limbs.max_reach(leg_near)])
    if wing_near < 0 or wing_far < 0 or leg_near < 0:
        fails.append("test setup: rig is missing a named limb")
    # setup staggers attempt cooldowns; a long update clears them without moving anything.
    creature.limbs.update(0.5)


# ---------------------------------------------------------------- grips

func _check_near_wall() -> void:
    var a: Vector2 = creature.anchor_pos(wing_near)
    var ideal: Vector2 = a + Vector2(110.0, 0.0)
    var ok: bool = creature.limbs.try_grip(wing_near, ideal)
    notes.append("near-wall ideal=%s anchor=%s latched=%s" % [
        str(ideal.round()), str(a.round()), str(ok)])
    if not ok:
        fails.append("wing did not latch onto the near wall")
        return
    var p: Vector2 = creature.limbs.grip_pos[wing_near]
    var n: Vector2 = creature.limbs.grip_normal[wing_near]
    var outward: Vector2 = (a - p).normalized()
    var on_face: bool = absf(p.x - WALL.position.x) <= 1.0
    var faces_out: bool = n.x < -0.9 and n.dot(outward) > 0.8
    var height_ok: bool = absf(p.y - a.y) <= 10.0
    notes.append("near-wall grip=%s normal=%s reach=%.1f outward_dot=%.2f" % [
        str(p.round()), str(n.round()), a.distance_to(p), n.dot(outward)])
    if not on_face:
        fails.append("grip was not on the wall face (x %.2f)" % p.x)
    if not faces_out:
        fails.append("grip normal does not face the creature: %s" % str(n))
    if not height_ok:
        fails.append("grip slid %.1f px vertically off the ideal line" % (p.y - a.y))
    if creature.limbs.grip_count() != 1:
        fails.append("grip count was %d after one latch" % creature.limbs.grip_count())


func _check_air() -> void:
    creature.limbs.update(1.0)
    var a: Vector2 = creature.anchor_pos(wing_far)
    var ok: bool = creature.limbs.try_grip(wing_far, a + Vector2(0.0, -110.0))
    notes.append("thin-air upward latched=%s grips=%d" % [str(ok), creature.limbs.grip_count()])
    if ok:
        fails.append("a limb latched onto thin air")
    if creature.limbs.grip_count() != 1:
        fails.append("thin-air probe changed the grip count")


func _check_reach() -> void:
    creature.limbs.update(1.0)
    var a_far: Vector2 = creature.anchor_pos(wing_far)
    var beyond: Vector2 = Vector2(FAR.get_center().x, a_far.y)     # ~380 px away
    var ok_far: bool = creature.limbs.try_grip(wing_far, beyond)

    creature.limbs.update(1.0)
    var a_leg: Vector2 = creature.anchor_pos(leg_near)
    var leg_max: float = creature.limbs.max_reach(leg_near)
    var ok_leg: bool = creature.limbs.try_grip(leg_near, a_leg + Vector2(60.0, 0.0))

    notes.append("reach wing_max=%.1f far_dist=%.1f far_latched=%s leg_max=%.1f leg_latched=%s" % [
        creature.limbs.max_reach(wing_far), a_far.distance_to(beyond), str(ok_far), leg_max, str(ok_leg)])
    if ok_far:
        fails.append("a wing latched onto a block beyond its max_reach")
    if ok_leg:
        fails.append("a short leg latched onto a wall %d px away (max %.1f)" % [
            int(a_leg.distance_to(Vector2(WALL.position.x, a_leg.y))), leg_max])
    if creature.limbs.grip_count() != 1:
        fails.append("out-of-reach probes changed the grip count")


func _check_hold_and_release() -> void:
    var i: int = wing_near
    if not creature.limbs.is_gripping(i):
        fails.append("test setup: the near-wing grip was lost before the hold test")
        return
    var g: Vector2 = creature.limbs.grip_pos[i]

    # Small body move: still in reach, so the grip must hold AND stay fixed in the world.
    _shift(creature, 18.0)
    creature.limbs.update(1.0 / 60.0)
    var held: bool = creature.limbs.is_gripping(i)
    var fixed_point: bool = creature.limbs.grip_pos[i] == g
    notes.append("hold +18px held=%s fixed=%s" % [str(held), str(fixed_point)])
    if not held:
        fails.append("a small move released the grip")
    if not fixed_point:
        fails.append("the grip point moved with the body instead of staying on the wall")

    # Big body move: out of reach, so the grip must drop.
    _shift(creature, 200.0)
    creature.limbs.update(1.0 / 60.0)
    var released: bool = not creature.limbs.is_gripping(i)
    notes.append("over-extend +200px released=%s grips=%d" % [
        str(released), creature.limbs.grip_count()])
    if not released:
        fails.append("the grip did not release when over-extended")
    if creature.limbs.grip_count() != 0:
        fails.append("grip count was not 0 after the only grip released")

    # Back to spawn and take hold again, so the tick-integration check has a grip to pin.
    _shift(creature, -218.0)
    creature.limbs.update(1.0)
    var a: Vector2 = creature.anchor_pos(i)
    if not creature.limbs.try_grip(i, a + Vector2(110.0, 0.0)):
        fails.append("could not re-latch after moving back to the spawn point")


func _check_tick_and_draw() -> void:
    if wing_near < 0 or not creature.limbs.is_gripping(wing_near):
        fails.append("test setup: no grip for the tick check")
        return
    var g: Vector2 = creature.limbs.grip_pos[wing_near]
    # Let the Creature tick: its tip must follow the grip, and the debug view must draw the
    # new grip marker without errors.
    for _k in 3:
        await get_tree().physics_frame
    await get_tree().process_frame

    var still: bool = creature.limbs.is_gripping(wing_near)
    var pinned: bool = creature.limb_tip[wing_near] == g
    notes.append("tick grip_held=%s tip_pinned=%s tip=%s" % [
        str(still), str(pinned), str(creature.limb_tip[wing_near].round())])
    if not still:
        fails.append("the grip was lost during a normal tick")
    if not pinned:
        fails.append("the limb tip was not pinned to the grip during the tick")
    if not creature.is_visible_in_tree():
        fails.append("the creature was not in the tree, so the debug view never drew")


# ---------------------------------------------------------------- helpers

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


## Translate the whole body without changing its velocity state (pos and prev together).
func _shift(c: Creature, dx: float) -> void:
    for k in c.body.pos.size():
        c.body.pos[k] = c.body.pos[k] + Vector2(dx, 0.0)
        c.body.prev[k] = c.body.prev[k] + Vector2(dx, 0.0)


func _report() -> void:
    for n in notes:
        print("GRIP NOTE ", n)
    if fails.is_empty():
        print("GRIP SUMMARY PASS notes=%d" % notes.size())
        get_tree().quit(0)
    else:
        for f in fails:
            print("GRIP FAIL ", f)
        print("GRIP SUMMARY FAIL fails=%d" % fails.size())
        get_tree().quit(1)
