class_name ClimbLocomotor
extends Locomotor
## Climbing: the grips hold the world, the body is dragged between them.
##
## There is no grip physics. Each point is pulled toward a line on the wall built from the
## held-grip centroid, a stiff spring holds the belly off the wall, and a climb force pushes
## along the surface. The gait lets go of the limb furthest behind the body (never with fewer
## than `climb_min_other` others holding) so it can reach ahead on the next tick; that cycle is
## what moves the grip centroid and therefore the body.
##
## Weight illusion from grip count: fewer grips means more gravity, more damping and less
## climb authority. With zero grips nothing pulls the body and it sags and slows.
##
## This mode is not selected automatically yet. T6 adds the landing window and the score that
## hands a flyer over to it; in T5 the dev harness gives a creature this locomotor directly.

func _init() -> void:
    id = &"climb"


## T5: holding a surface is the hard requirement. T6 will also score a surface that is only
## adjacent, so a flyer can land and switch.
func score(_intent: Intent) -> float:
    if c == null or c.limbs == null:
        return 0.0
    return 1.0 if c.limbs.grip_count() > 0 else 0.0


func emit(dt: float, intent: Intent, out: MoveOutput) -> void:
    var b: Body = c.body
    var rig: CreatureRig = c.rig
    var limbs: LimbSystem = c.limbs
    var mid: int = rig.center_point
    var centre: Vector2 = b.pos[mid]

    # Wall frame. Held grips give the most stable normal; probe only before the first grip.
    var n: Vector2 = limbs.grip_normal_avg()
    var hit: WorldQuery.SurfaceHit = null
    if n.length_squared() < 0.0001:
        hit = _probe()
        if hit != null:
            n = hit.normal

    var tangent: Vector2 = _tangent_toward(intent, centre, n)
    var arrived: bool = intent.has_goal \
        and centre.distance_to(intent.goal) <= c.tune(&"climb_arrive", 26.0)

    # Gait: the limb furthest behind gets to re-reach, as long as enough others still hold.
    if tangent != Vector2.ZERO and not arrived:
        limbs.release_furthest_behind(
            tangent,
            int(c.tune(&"climb_min_other", 2.0)),
            c.tune(&"climb_gait_behind", 20.0))

    var grip_count: int = limbs.grip_count()
    var limb_count: int = maxi(rig.limbs.size(), 1)
    var grip_factor: float = float(grip_count) / float(limb_count)
    var gravity: float = c.tune(&"gravity", 900.0)
    var hang_k: float = c.tune(&"climb_hang_k", 14.0)
    var hang_damp: float = c.tune(&"climb_hang_damp", 6.0)
    var hold_offset: float = c.tune(&"climb_hold_offset", 30.0)
    # Each free limb lets the body hang a little further out, so the hand-over-hand cycle
    # rocks the body in and out instead of gliding up a rail.
    var free_sag: float = c.tune(&"climb_free_sag", 8.0)
    var climb_accel: float = c.tune(&"climb_accel", 240.0)
    var max_speed: float = c.tune(&"climb_max_speed", 130.0)
    var no_grip_damp: float = c.tune(&"climb_no_grip_damp", 1.2)

    var hold: Vector2 = limbs.grip_centroid() + n * (hold_offset + free_sag * float(limb_count - grip_count))
    var wall_ref: Vector2 = limbs.grip_centroid() if grip_count > 0 else (hit.pos if hit != null else centre)

    for i in b.pos.size():
        var p: PointDef = rig.points[i]
        var v: Vector2 = b.velocity(i, dt)
        var acc: Vector2 = Vector2.ZERO
        if grip_count > 0 and tangent != Vector2.ZERO:
            # Desired point on the wall-parallel body line: gripped centroid, spine offsets
            # along the travel tangent, belly toward the wall.
            var desired: Vector2 = hold + tangent * p.offset.x - n * p.offset.y
            acc += (desired - b.pos[i]) * hang_k
            acc -= v * hang_damp
            acc += tangent * climb_accel * grip_factor
            var vt: float = v.dot(tangent)
            if vt > max_speed:
                acc -= tangent * (vt - max_speed) * 8.0
        else:
            acc -= v * no_grip_damp
        acc.y += gravity * (1.0 - grip_factor)
        out.add_accel(i, acc)

    _emit_limbs(out, tangent, n, limbs, wall_ref)


## Free limbs reach ahead along the wall from their own anchor. The target sits 5 px off the
## face so the grip ray has a clear line into it; the ray stops on the face itself.
func _emit_limbs(out: MoveOutput, tangent: Vector2, n: Vector2, limbs: LimbSystem, wall_ref: Vector2) -> void:
    if tangent == Vector2.ZERO or n.length_squared() < 0.0001:
        return
    var rig: CreatureRig = c.rig
    var step_frac: float = c.tune(&"climb_step", 0.75)
    var step_cap: float = c.tune(&"climb_step_cap", 52.0)
    for i in rig.limbs.size():
        if limbs.is_gripping(i):
            continue
        var lm: LimbDef = rig.limbs[i]
        var anchor: Vector2 = c.anchor_pos(i)
        var on_wall: Vector2 = anchor - n * (anchor - wall_ref).dot(n)
        var step: float = minf(lm.reach * step_frac, step_cap)
        out.set_limb_target(i, on_wall + tangent * step + n * 5.0)


## Direction of travel projected onto the surface (ZERO when there is no goal or the goal is
## straight into the wall).
func _tangent_toward(intent: Intent, centre: Vector2, n: Vector2) -> Vector2:
    if not intent.has_goal:
        return Vector2.ZERO
    var wish: Vector2 = intent.goal - centre
    if wish.length_squared() < 0.0001:
        return Vector2.ZERO
    var t: Vector2 = wish
    if n.length_squared() > 0.0001:
        t -= n * wish.dot(n)
    return t.normalized() if t.length_squared() > 0.0001 else Vector2.ZERO


func _probe() -> WorldQuery.SurfaceHit:
    if c == null or c.world == null:
        return null
    var radius: float = c.tune(&"climb_wall_probe", 70.0)
    return c.world.surface_near(c.body.pos[c.rig.center_point], radius)
