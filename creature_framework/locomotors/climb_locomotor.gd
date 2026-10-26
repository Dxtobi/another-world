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
## T6 selects this mode automatically: a held grip scores high, and a nearby surface whose
## grid path reaches a goal that also touches terrain scores high enough to land. A goal in
## open air scores low, so a climber lets go and flies to it.
##
## Entering the mode bleeds some speed and opens a short landing window with more grip rays;
## leaving it is handled by FlyLocomotor.enter(), which reads the last wall normal, pushes
## off and releases every grip.

const SCORE_HELD := 2.0          # already holding: stay unless the goal leaves the surface
const SCORE_HELD_EXIT := 0.25    # goal no longer climbable: fly wins on the next decision
const SCORE_LAND := 1.8          # surface adjacent + goal climb-reachable: beat fly's 1.0
const SCORE_CHECK_FRAMES := 12   # re-check grid reachability ~5x/s, not every tick

var _goal_cache: Vector2 = Vector2.INF
var _goal_cache_ok: bool = false
var _goal_cache_frame: int = 0
var _probe_cache: WorldQuery.SurfaceHit = null
var _probe_cache_frame: int = -1


func _init() -> void:
    id = &"climb"


func score(intent: Intent) -> float:
    if c == null or c.limbs == null:
        return 0.0
    if c.limbs.grip_count() > 0:
        return SCORE_HELD if _goal_climbable(intent) else SCORE_HELD_EXIT
    if not _goal_climbable(intent):
        return 0.0
    var hit: WorldQuery.SurfaceHit = _local_surface()
    if hit == null:
        return 0.0
    return SCORE_LAND if hit.distance <= c.tune(&"climb_land_radius", 46.0) else 0.0


func enter() -> void:
    _goal_cache = Vector2.INF
    _goal_cache_ok = false
    _goal_cache_frame = 0
    _probe_cache = null
    _probe_cache_frame = -1
    # LimbSystem is created after LocoManager, so the very first enter() has no limbs yet.
    if c == null or c.body == null or c.limbs == null:
        return
    var dt: float = 1.0 / 60.0
    var v: Vector2 = c.body.velocity(c.rig.center_point, dt)
    if c.limbs.grip_count() == 0 and v.length() > c.tune(&"climb_land_bleed_min", 60.0):
        # Keep `keep` of the velocity: the landing must not throw the body into the wall.
        var keep: float = c.tune(&"climb_land_bleed_keep", 0.4)
        for i in c.body.pos.size():
            c.body.prev[i] = c.body.prev[i].lerp(c.body.pos[i], 1.0 - keep)
    c.limbs.begin_landing(c.tune(&"climb_land_window", 0.4))


func exit() -> void:
    if c != null and c.limbs != null:
        c.limbs.end_landing()


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
        hit = _local_surface()
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


## Find the face to land on. Probe the HEAD first: flight steers by the head, so a flyer
## hovering at a wall goal has its head on the face and its centre a body-length back.
## Falling back to the centre keeps backing/climbing cases working.
func _probe() -> WorldQuery.SurfaceHit:
    if c == null or c.world == null:
        return null
    var radius: float = c.tune(&"climb_wall_probe", 70.0)
    var hit: WorldQuery.SurfaceHit = c.world.surface_near(c.body.pos[c.rig.front_point], radius)
    if hit != null:
        return hit
    return c.world.surface_near(c.body.pos[c.rig.center_point], radius)


## The surface probe is needed by score() and emit() in the same tick; cast its rays once.
func _local_surface() -> WorldQuery.SurfaceHit:
    var frame: int = Engine.get_physics_frames()
    if frame == _probe_cache_frame:
        return _probe_cache
    _probe_cache_frame = frame
    _probe_cache = _probe()
    return _probe_cache


## Is the brain's goal a place a climber can actually get to? Both the goal and the body
## must touch terrain, and (when a grid exists) the surface grid must connect them. Cached
## for a few frames and invalidated when the goal moves, because A* must not run per tick.
func _goal_climbable(intent: Intent) -> bool:
    if c == null or c.world == null or not intent.has_goal:
        return false
    var frame: int = Engine.get_physics_frames()
    var moved: bool = _goal_cache == Vector2.INF \
        or _goal_cache.distance_to(intent.goal) > c.tune(&"climb_goal_tolerance", 24.0)
    if not moved and frame < _goal_cache_frame:
        return _goal_cache_ok
    _goal_cache = intent.goal
    _goal_cache_frame = frame + SCORE_CHECK_FRAMES
    var goal_hit: WorldQuery.SurfaceHit = c.world.surface_near(
        intent.goal, c.tune(&"climb_goal_radius", 52.0))
    _goal_cache_ok = goal_hit != null and c.world.surface_reachable(
        c.body.pos[c.rig.center_point], intent.goal, 3)
    return _goal_cache_ok
