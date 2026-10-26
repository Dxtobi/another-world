class_name Creature
extends Node2D
## Glue node: Brain -> Intent -> LocoManager -> MoveOutput -> Body -> WorldQuery.
## Also exposes the proxy variables cosmetics read (thrust, flap_phase, turn_rate, limb_tip).

var rig: CreatureRig
var body: Body
var brain: Brain
var loco: LocoManager
var world: WorldQuery
## Turns the goal into the next waypoint a locomotor should steer at. Never writes the
## intent: the brain stays the only thing that decides *where* to go.
var path: PathFollower = null
## Grip state per limb. Cosmetic in T4 (it pins limb tips); the forces come in T5.
var limbs: LimbSystem = null
var intent: Intent = Intent.new()
var out: MoveOutput = MoveOutput.new()
## Cosmetic 2.5D view. Updated in `_process`; never read by logic.
var depth_layer: DepthLayer = DepthLayer.new()
## Per-limb hidden step height (0..1). Cosmetic; drives the raised foot + shrunken shadow.
var step_lift: PackedFloat32Array = PackedFloat32Array()

# Proxy variables: written by locomotors, read by cosmetics. Never the other way round.
var thrust: float = 0.0
var flap_phase: float = 0.0
var turn_rate: float = 0.0
## Damped facing in -1..+1. Sign = direction, |value| = how committed; it passes
## smoothly through 0 on a reversal (the edge-on turn) instead of snapping.
var facing: float = 1.0
var limb_tip: PackedVector2Array = PackedVector2Array()

var debug_draw: bool = true


func setup(p_rig: CreatureRig, p_brain: Brain, p_world: WorldQuery, origin: Vector2) -> void:
    rig = p_rig
    brain = p_brain
    world = p_world
    body = Body.new()
    body.setup(rig, origin)
    path = PathFollower.new(world)
    loco = LocoManager.new()
    loco.setup(self, rig.locomotors)
    limbs = LimbSystem.new()
    limbs.setup(rig, world, self)
    limb_tip.resize(rig.limbs.size())
    for i in rig.limbs.size():
        limb_tip[i] = anchor_pos(i)
    step_lift.resize(rig.limbs.size())
    step_lift.fill(0.0)
    depth_layer.reset(facing)


func _physics_process(dt: float) -> void:
    if body == null:
        return
    brain.think(self, intent, dt)
    if path != null:
        # Advance from the HEAD, because that is the point locomotors steer. Advancing from
        # the centre parks the head on a waypoint while the body hangs a spine-length behind.
        path.update(body.pos[rig.front_point], intent.goal, intent.has_goal, dt)
    if absf(intent.look_dir.x) > 0.01:
        facing = Steering.damp_f(facing, signf(intent.look_dir.x), tune(&"facing_rate", 9.0), dt)
    limbs.update(dt)
    out.reset(body.pos.size(), rig.limbs.size())
    loco.update(dt, intent, out)
    for i in body.pos.size():
        body.add_accel(i, out.accels[i])
    for i in rig.limbs.size():
        limb_tip[i] = out.get_limb_target(i, anchor_pos(i))
        # Free limbs look for a handhold where the locomotor wanted the tip. A limb that
        # finds one is pinned to the surface instead of following the swing.
        if not limbs.is_gripping(i):
            limbs.try_grip(i, limb_tip[i])
        if limbs.is_gripping(i):
            limb_tip[i] = limbs.grip_pos[i]
    body.step(dt)
    world.resolve(body)


func _process(dt: float) -> void:
    if body == null:
        return
    # Depth is a render-rate cosmetic: smoothing it here keeps the turn free of 60 Hz
    # stepping even when the physics tick is slower than the display.
    var stepping: bool = loco.current != null and loco.current.id != &"fly"
    _update_step_lift(dt, stepping)
    depth_layer.update(facing, tune(&"yaw_rate", 10.0), dt)
    queue_redraw()


## Read a per-creature tuning value, falling back to the locomotor's default.
func tune(key: StringName, default_value: float) -> float:
    return float(rig.tuning.get(key, default_value))


## The point a locomotor should steer at this tick: the current path waypoint, or the
## raw goal when there is no plan (no grids, unreachable goal, or the path is used up).
## Locomotors call this instead of reading `intent.goal` directly.
func steer_target() -> Vector2:
    var fallback: Vector2 = intent.goal if intent.has_goal else body.pos[rig.center_point]
    if path == null:
        return fallback
    return path.target(fallback)


## True when steering is aimed at the goal itself, not an intermediate waypoint. Locomotors
## use this to brake only for the final arrival and keep full speed around corners.
func steer_is_goal() -> bool:
    return intent.has_goal and (path == null or path.at_goal())


## Direction of the spine, rear -> front.
func spine_dir() -> Vector2:
    return body.pos[rig.front_point] - body.pos[rig.rear_point]


## Convert a vector in the spine frame (+x forward, +y belly) to world space.
## Uses the damped `facing` value rather than a hard spine-sign test: a reversal
## passes through edge-on (x collapses to 0) and pitch fades out with it, so
## limbs foreshorten instead of mirroring in one frame.
func dir_to_world(local_dir: Vector2) -> Vector2:
    var d: Vector2 = spine_dir()
    var f: Vector2 = d.normalized() if d.length_squared() > 0.0001 else Vector2(facing, 0.0)
    # Pitch in the facing frame. atan2 against the facing-mirrored vector stays
    # continuous through vertical (no wrap seam at +-90 degrees, which the spine
    # crosses on hard climbs).
    var pitch: float = atan2(f.y * facing, f.x * facing) * absf(facing)
    return Vector2(local_dir.x * facing, local_dir.y).rotated(pitch)


func anchor_pos(limb_index: int) -> Vector2:
    var lm: LimbDef = rig.limbs[limb_index]
    return body.pos[lm.anchor_point] + dir_to_world(lm.local_offset)


## Same anchor, but on the interpolated render position, so the debug limbs stay
## welded to the interpolated body hull at high speed.
func anchor_render(limb_index: int, alpha: float) -> Vector2:
    var lm: LimbDef = rig.limbs[limb_index]
    return body.render_pos(lm.anchor_point, alpha) + dir_to_world(lm.local_offset)


## A free leg lifts while the creature is climbing (or crawling); a held leg drops back onto
## the surface. Wings never step. This is feel, not logic: the grip itself is unchanged.
func _update_step_lift(dt: float, stepping: bool) -> void:
    if limbs == null:
        return
    var rate: float = tune(&"step_lift_rate", 10.0)
    for i in rig.limbs.size():
        var want: float = 0.0
        if stepping and not limbs.is_gripping(i) and rig.limbs[i].kind == &"leg":
            want = 1.0
        step_lift[i] = Steering.damp_f(step_lift[i], want, rate, dt)


# ---------------------------------------------------------------- debug view (circles and lines only)
func _draw() -> void:
    if body == null or not debug_draw:
        return
    var alpha: float = Engine.get_physics_interpolation_fraction()
    var n: int = body.pos.size()
    var rp: PackedVector2Array = PackedVector2Array()
    rp.resize(n)
    for i in n:
        rp[i] = to_local(body.render_pos(i, alpha))
    var centre: Vector2 = rp[rig.center_point]

    # Depth decides draw order: far limbs before the hull, near limbs after it. During a
    # turnaround both sides cross zero together, so the order changes at edge-on instead of
    # popping. The same values scale and tint each part.
    var order: Array[int] = []
    var depths: PackedFloat32Array = PackedFloat32Array()
    depths.resize(rig.limbs.size())
    for i in rig.limbs.size():
        order.append(i)
        depths[i] = depth_layer.depth_of(float(rig.limbs[i].lane))
    order.sort_custom(func(a: int, b: int) -> bool:
        if is_equal_approx(depths[a], depths[b]):
            return a < b
        return depths[a] < depths[b])

    for i in order:
        if depths[i] < 0.0:
            _draw_limb(i, centre, alpha, depths[i])

    _draw_body(rp, centre)
    for l in rig.links:
        draw_line(_view(rp[l.a], centre), _view(rp[l.b], centre),
            Color(0.6, 0.65, 0.8, 0.45), 1.0)
    for i in n:
        var pd: float = depth_layer.depth_of(rig.points[i].base_depth)
        draw_circle(_view(rp[i], centre), 2.5 * depth_layer.scale_for(pd),
            depth_layer.tint(Color(1.0, 1.0, 1.0, 0.55), pd))

    for i in order:
        if depths[i] >= 0.0:
            _draw_limb(i, centre, alpha, depths[i])

    if path != null and path.has_path():
        var col: Color = Color(0.45, 1.0, 0.75, 0.55)
        var prev: Vector2 = to_local(body.render_pos(rig.front_point, alpha))
        for i in range(path.index, path.path.size()):
            var wp: Vector2 = to_local(path.path[i])
            draw_line(prev, wp, col, 1.0)
            draw_circle(wp, 2.0, col)
            prev = wp
        draw_circle(to_local(steer_target()), 5.0, Color(0.4, 1.0, 0.7, 0.85))

    if intent.has_goal:
        draw_circle(to_local(intent.goal), 6.0, Color.RED)
        draw_arc(to_local(intent.goal), 14.0, 0.0, TAU, 24, Color(1.0, 0.3, 0.3, 0.6), 1.5)


## Cosmetic squash about the body centre. Logic positions and the path overlay stay exact.
func _view(p: Vector2, centre: Vector2) -> Vector2:
    return depth_layer.squash_point(p, centre)


## A world-space direction under the same squash, for wings and step lift.
func _view_dir(world_dir: Vector2) -> Vector2:
    var local_dir: Vector2 = to_local(world_dir) - to_local(Vector2.ZERO)
    return Vector2(local_dir.x * depth_layer.squash, local_dir.y)


func _draw_limb(i: int, centre: Vector2, alpha: float, d: float) -> void:
    var lm: LimbDef = rig.limbs[i]
    var is_wing: bool = lm.kind == &"wing"
    var col: Color = Color(0.55, 0.82, 1.0) if is_wing else Color(0.95, 0.72, 0.42)
    col = depth_layer.tint(col, d)
    var a: Vector2 = _view(to_local(anchor_render(i, alpha)), centre)
    var tip_world: Vector2 = anchor_render(i, alpha) + (limb_tip[i] - anchor_pos(i))
    var t: Vector2 = _view(to_local(tip_world), centre)
    if is_wing:
        _draw_wing(a, t, col, d)
    else:
        var lift_dir: Vector2 = Vector2.UP
        if limbs != null and limbs.grip_count() > 0:
            lift_dir = limbs.grip_normal_avg()
        _draw_leg(a, t, col, d, step_lift[i], lift_dir, lm.reach)
    _draw_grip(i, centre, d)


## A grip reads as a bright dot on the surface plus a tick along its outward normal.
func _draw_grip(i: int, centre: Vector2, d: float) -> void:
    if limbs == null or not limbs.is_gripping(i):
        return
    var scale: float = depth_layer.scale_for(d)
    var g: Vector2 = _view(to_local(limbs.grip_pos[i]), centre)
    var gn: Vector2 = _view_dir(limbs.grip_normal[i])
    if gn.length_squared() > 0.0001:
        gn = gn.normalized()
    draw_circle(g, 4.5 * scale, Color(0.2, 0.9, 0.45, 0.55))
    draw_circle(g, 2.2 * scale, Color(0.85, 1.0, 0.9))
    draw_line(g, g + gn * 9.0 * scale, Color(0.45, 1.0, 0.65, 0.8), 1.5)


## Translucent tapered hull through the three spine points, so the limbs read as
## attached to a body instead of four lines growing out of one dot. Debug only.
func _draw_body(rp: PackedVector2Array, centre: Vector2) -> void:
    var f: Vector2 = rp[rig.front_point]
    var m: Vector2 = rp[rig.center_point]
    var r: Vector2 = rp[rig.rear_point]
    var axis: Vector2 = f - r
    if axis.length_squared() < 0.0001:
        return
    var perp: Vector2 = axis.normalized().orthogonal()
    # Widen toward the middle, taper at the head and into a tail.
    var rf: float = 7.0
    var rm: float = 11.0
    var rr: float = 4.5
    var poly: PackedVector2Array = PackedVector2Array([
        f + perp * rf, m + perp * rm, r + perp * rr,
        r - perp * rr, m - perp * rm, f - perp * rf,
    ])
    for i in poly.size():
        poly[i] = _view(poly[i], centre)

    var hull_depth: float = 0.0
    for p in rig.points:
        hull_depth += depth_layer.depth_of(p.base_depth)
    hull_depth /= float(maxi(rig.points.size(), 1))
    var hull_col: Color = depth_layer.tint(Color(0.15, 0.17, 0.23, 0.88), hull_depth)
    draw_colored_polygon(poly, hull_col)
    var outline: PackedVector2Array = poly.duplicate()
    outline.append(poly[0])
    draw_polyline(outline, Color(0.55, 0.62, 0.82, 0.9), 1.5)
    var head: Vector2 = _view(f, centre)
    var head_r: float = (rf + 0.5) * lerpf(1.0, depth_layer.squash, 0.7)
    draw_circle(head, head_r, Color(0.19, 0.23, 0.31, 0.95))
    draw_circle(head, 2.5 * depth_layer.squash, Color.ORANGE)


## A wing, not a fan: leading edge from the shoulder to the tip, a trailing edge
## that sweeps back, and 3 feather ribs. Depth is sold by span and chord together —
## turning toward camera makes it SHORT AND BROAD, edge-on makes it LONG AND THIN.
func _draw_wing(a: Vector2, tip: Vector2, col: Color, d: float) -> void:
    var v: Vector2 = tip - a
    var length: float = v.length()
    if length < 1.0:
        return
    var dir: Vector2 = v / length
    var ds: float = maxf(0.0, -cos(flap_phase))                 # 0 on recovery, 1 mid downstroke
    var presentation: float = clampf(0.62 * ds + 0.38 * (1.0 - absf(facing)), 0.0, 1.0)
    var scale: float = depth_layer.scale_for(d)
    var span: float = length * lerpf(1.0, 0.58, presentation) * scale
    var chord: float = lerpf(4.0, 34.0, presentation) * scale
    if d < 0.0:
        chord *= 0.84
        span *= 0.92
    var t: Vector2 = a + dir * span

    # Trailing edge points backwards in the body frame, flattened onto the wing plane.
    var back: Vector2 = _view_dir(dir_to_world(Vector2(-1.0, 0.0)))
    var trail: Vector2 = back - dir * back.dot(dir)
    if trail.length_squared() < 0.0001:
        trail = dir.orthogonal()
    trail = trail.normalized()

    var edge_1: Vector2 = a + dir * (span * 0.12) + trail * chord * 0.30
    var edge_2: Vector2 = a + dir * (span * 0.46) + trail * chord * 0.90
    var edge_3: Vector2 = a + dir * (span * 0.80) + trail * chord * 0.62
    var lead: Vector2 = a + dir * (span * 0.55) - trail * 1.2
    var poly: PackedVector2Array = PackedVector2Array([a, edge_1, edge_2, edge_3, t, lead])
    draw_colored_polygon(poly, Color(col.r, col.g, col.b, 0.20))
    var outline: PackedVector2Array = poly.duplicate()
    outline.append(poly[0])
    draw_polyline(outline, col, 1.6)
    for k: float in [0.30, 0.52, 0.74]:
        var base: Vector2 = a + dir * (span * k)
        draw_line(base, a + dir * (span * (k + 0.16)) + trail * chord * (0.55 - 0.35 * k),
            col.darkened(0.15), 1.0)
    draw_line(a, t, col.lightened(0.3), 2.0)          # leading edge, reads as the bone
    draw_circle(t, 2.5 * scale, col)


## Leg drawn as two bones with a knee. Depth reads through weight, not just colour:
## the far leg is thinner, shorter (foreshortened) and darker than the near one.
func _draw_leg(a: Vector2, tip: Vector2, col: Color, d: float, lift: float,
        lift_dir: Vector2, reach: float) -> void:
    var near: bool = d >= 0.0
    var lift_norm: float = clampf(lift, 0.0, 1.0)
    var shadow_alpha: float = 0.22 * (1.0 - lift_norm)
    if shadow_alpha > 0.005:
        draw_circle(tip, 3.2 * (1.0 - 0.45 * lift_norm) * depth_layer.scale_for(d),
            Color(0.0, 0.0, 0.0, shadow_alpha))

    # Hidden height: raise the foot out of the surface, then fatten it a little. The shadow
    # stays where the logic tip is, so the gap between foot and shadow reads as height.
    var raised: Vector2 = tip
    var lift_local: Vector2 = _view_dir(lift_dir)
    if lift_local.length_squared() > 0.0001:
        raised += lift_local.normalized() * (lift_norm * tune(&"step_height", 9.0))

    var thigh: float = reach * 0.52
    var shin: float = reach * 0.52
    var bend: Vector2 = _view_dir(dir_to_world(Vector2(-1.0, 0.0)))
    var knee: Vector2 = _two_bone_knee(a, raised, thigh, shin, bend)
    var scale: float = depth_layer.scale_for(d) * (1.0 + 0.18 * lift_norm)
    var w: float = (3.5 if near else 2.0) * scale
    draw_line(a, knee, col, w)
    draw_line(knee, raised, col, w)
    draw_circle(a, 2.0 * scale, col.darkened(0.25))
    draw_circle(knee, (2.5 if near else 1.8) * scale, col.lightened(0.3))
    # Short foot segment so the leg ends in a claw instead of a dot.
    var shin_dir: Vector2 = (raised - knee).normalized()
    if shin_dir.length_squared() > 0.0001:
        var foot: Vector2 = raised + shin_dir.orthogonal() * (5.0 if near else 3.5) * scale
        draw_line(raised, foot, col, w)
    draw_circle(raised, 2.2 * scale, col)


func _two_bone_knee(a: Vector2, tip: Vector2, thigh: float, shin: float, bend: Vector2) -> Vector2:
    var d: Vector2 = tip - a
    var dist: float = clampf(d.length(), 1.0, thigh + shin - 0.5)
    var dir: Vector2 = d.normalized() if d.length() > 0.001 else Vector2.DOWN
    var along: float = (thigh * thigh + dist * dist - shin * shin) / (2.0 * dist)
    along = clampf(along, 0.0, thigh)
    var height: float = sqrt(maxf(0.0, thigh * thigh - along * along))
    var side: Vector2 = bend - dir * bend.dot(dir)       # perpendicular part of the bend hint
    if side.length_squared() < 0.0001:
        side = dir.orthogonal()
    side = side.normalized()
    return a + dir * along + side * height
