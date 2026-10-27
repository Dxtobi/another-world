class_name ClimbLocomotor
extends Locomotor
## Climbing: the grips hold the world, the body is dragged between them.
##
## There is no grip physics. Each point is pulled toward a line on the wall built from the
## held-grip centroid, a stiff spring holds the belly off the wall, and a climb force pushes
## along the surface. The gait lets go of the limb furthest behind the body (never with fewer
## than `climb_min_other` others holding, capped at one fewer than the rig's limb count) so it
## can reach ahead on the next tick; that cycle is what moves the grip centroid and therefore
## the body.
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
var _stuck_cd: float = 0.0
## Damped body heading along the surface. The raw travel tangent can reverse 180 degrees in
## one tick when the goal moves to the other side of the body; the desired pose would then be
## collinear with the current one and the springs would pull head and tail straight through
## each other (a symmetric deadlock). Turning the desired line at a finite rate through the
## open side of the wall gives the body a real arc to follow.
var _heading: Vector2 = Vector2.ZERO


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
    _stuck_cd = 0.0
    _heading = Vector2.ZERO
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

    # Wall frame. Held grips give the most stable normal; before the first grip, probe.
    var probe: WorldQuery.SurfaceHit = _local_surface()
    var n: Vector2 = limbs.grip_normal_avg()
    if n.length_squared() < 0.0001 and probe != null:
        n = probe.normal

    var tangent: Vector2 = _tangent_toward(intent, centre, n)
    var arrived: bool = intent.has_goal \
        and centre.distance_to(intent.goal) <= c.tune(&"climb_arrive", 26.0)

    var limb_count: int = maxi(rig.limbs.size(), 1)
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

    # Gait: the limb furthest behind gets to re-reach, as long as enough others still hold.
    # A two-limb crawler can only ever let go with one hand left, so the floor is capped at
    # `limb_count - 1`; the old fixed 2 deadlocked every two-legged rig with both feet down.
    # The "behind" threshold follows the same spring that decides how far the body leads the
    # grip centroid (climb_accel / hang_k) instead of a fixed 20 px, which sat just above
    # that lead and made a short-bodied climber's grips never count as behind.
    var min_other: int = mini(int(c.tune(&"climb_min_other", 2.0)), limb_count - 1)
    var gait_behind: float = c.tune(&"climb_gait_behind", -1.0)
    if gait_behind < 0.0:
        gait_behind = clampf(climb_accel / maxf(hang_k, 0.001) * 0.5, 3.0, 20.0)
    var released: int = -1
    if tangent != Vector2.ZERO and not arrived:
        released = limbs.release_furthest_behind(tangent, maxi(min_other, 0), gait_behind)

    # Corner hand-off. At a wall base both feet can end up *ahead* of the body (it is wedged
    # into the corner), so the "furthest behind" rule has nothing to release and the rig
    # stalls forever. When the head probes a different face than the feet hold and the body is
    # not moving along the current tangent, let the rearmost foot go: it reaches onto the new
    # face, and the next grip turns the body onto it.
    _stuck_cd = maxf(_stuck_cd - dt, 0.0)
    var corner: bool = probe != null and n.length_squared() > 0.0001 \
        and probe.normal.dot(n) < c.tune(&"climb_corner_dot", 0.7)
    if released < 0 and corner and _stuck_cd <= 0.0 and limbs.grip_count() > 1:
        var tangent_speed: float = b.velocity(mid, dt).dot(tangent)
        if absf(tangent_speed) < c.tune(&"climb_stuck_speed", 18.0):
            released = limbs.release_furthest_behind(tangent, maxi(min_other, 0), -INF)
            if released >= 0:
                _stuck_cd = c.tune(&"climb_stuck_retry", 0.5)

    var grip_count: int = limbs.grip_count()
    var grip_factor: float = float(grip_count) / float(limb_count)

    var hold: Vector2 = limbs.grip_centroid() + n * (hold_offset + free_sag * float(limb_count - grip_count))
    var wall_ref: Vector2 = limbs.grip_centroid() if grip_count > 0 else (probe.pos if probe != null else centre)

    var reach_n: Vector2 = n
    var reach_ref: Vector2 = wall_ref
    var reach_tangent: Vector2 = tangent
    if corner:
        # A free limb reaches for the face the head can see, not the one the feet stand on.
        reach_n = probe.normal
        reach_ref = probe.pos
        reach_tangent = _tangent_toward(intent, centre, reach_n)

    # Turn the desired body line toward the travel direction at a finite rate. A 180 degree
    # reversal swings through the open side of the surface (the outward normal), not through
    # the wall; see `_heading`.
    if tangent != Vector2.ZERO:
        if _heading.length_squared() < 0.0001:
            var spine: Vector2 = c.spine_dir()
            _heading = spine.normalized() if spine.length_squared() > 1.0 else tangent
        var diff: float = _heading.angle_to(tangent)
        if absf(diff) > PI - 0.1:
            diff = PI * signf(_heading.rotated(PI * 0.5).dot(n))
        var max_turn: float = c.tune(&"climb_turn_rate", 5.0) * dt
        _heading = _heading.rotated(clampf(diff, -max_turn, max_turn)).normalized()

    for i in b.pos.size():
        var p: PointDef = rig.points[i]
        var v: Vector2 = b.velocity(i, dt)
        var acc: Vector2 = Vector2.ZERO
        if not p.driven:
            # Trailing chain (tail/tentacle): nothing steers it. Gravity makes it hang,
            # damping kills the solver's whip, and its links drag it after the body. Pinning
            # it to the wall line like a spine point would lever the body off the surface.
            acc -= v * c.tune(&"climb_trail_damp", 2.5)
            acc.y += gravity * c.tune(&"climb_trail_gravity", 0.2)
            out.add_accel(i, acc)
            continue
        if grip_count > 0 and tangent != Vector2.ZERO:
            # Desired point on the wall-parallel body line: gripped centroid, spine offsets
            # along the (damped) heading, belly toward the wall.
            var desired: Vector2 = hold + _heading * p.offset.x - n * p.offset.y
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

    _emit_limbs(out, reach_tangent, reach_n, limbs, reach_ref)


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
