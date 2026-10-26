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
var intent: Intent = Intent.new()
var out: MoveOutput = MoveOutput.new()

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
    limb_tip.resize(rig.limbs.size())
    for i in rig.limbs.size():
        limb_tip[i] = anchor_pos(i)


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
    out.reset(body.pos.size(), rig.limbs.size())
    loco.update(dt, intent, out)
    for i in body.pos.size():
        body.add_accel(i, out.accels[i])
    for i in rig.limbs.size():
        limb_tip[i] = out.get_limb_target(i, anchor_pos(i))
    body.step(dt)
    world.resolve(body)


func _process(_dt: float) -> void:
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

    _draw_body(rp)
    for l in rig.links:
        draw_line(rp[l.a], rp[l.b], Color(0.6, 0.65, 0.8, 0.45), 1.0)
    for i in n:
        draw_circle(rp[i], 2.5, Color(1.0, 1.0, 1.0, 0.55))

    for i in rig.limbs.size():
        var lm: LimbDef = rig.limbs[i]
        var is_wing: bool = lm.kind == &"wing"
        var col: Color = Color(0.55, 0.82, 1.0) if is_wing else Color(0.95, 0.72, 0.42)
        if lm.lane < 0:
            col = col.darkened(0.35)
        var a: Vector2 = to_local(anchor_render(i, alpha))
        var t: Vector2 = to_local(anchor_render(i, alpha) + (limb_tip[i] - anchor_pos(i)))
        if is_wing:
            _draw_wing(a, t, col, lm)
        else:
            _draw_leg(a, t, col, lm)
            draw_circle(t, 2.5, col)

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


## Translucent tapered hull through the three spine points, so the limbs read as
## attached to a body instead of four lines growing out of one dot. Debug only.
func _draw_body(rp: PackedVector2Array) -> void:
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
    draw_colored_polygon(poly, Color(0.15, 0.17, 0.23, 0.88))
    var outline: PackedVector2Array = poly.duplicate()
    outline.append(poly[0])
    draw_polyline(outline, Color(0.55, 0.62, 0.82, 0.9), 1.5)
    draw_circle(f, rf + 0.5, Color(0.19, 0.23, 0.31, 0.95))
    draw_circle(f, 2.5, Color.ORANGE)


## A wing, not a fan: leading edge from the shoulder to the tip, a trailing edge
## that sweeps back, and 3 feather ribs. Depth is sold by span and chord together —
## turning toward camera makes it SHORT AND BROAD, edge-on makes it LONG AND THIN.
func _draw_wing(a: Vector2, tip: Vector2, col: Color, lm: LimbDef) -> void:
    var v: Vector2 = tip - a
    var length: float = v.length()
    if length < 1.0:
        return
    var d: Vector2 = v / length
    var ds: float = maxf(0.0, -cos(flap_phase))                 # 0 on recovery, 1 mid downstroke
    var presentation: float = clampf(0.62 * ds + 0.38 * (1.0 - absf(facing)), 0.0, 1.0)
    var span: float = length * lerpf(1.0, 0.58, presentation)
    var chord: float = lerpf(4.0, 34.0, presentation)
    if lm.lane < 0:
        chord *= 0.84
        span *= 0.92
    var t: Vector2 = a + d * span

    # Trailing edge points backwards in the body frame, flattened onto the wing plane.
    var back_w: Vector2 = dir_to_world(Vector2(-1.0, 0.0))
    var back: Vector2 = (to_local(back_w) - to_local(Vector2.ZERO))
    var trail: Vector2 = back - d * back.dot(d)
    if trail.length_squared() < 0.0001:
        trail = d.orthogonal()
    trail = trail.normalized()

    var edge_1: Vector2 = a + d * (span * 0.12) + trail * chord * 0.30
    var edge_2: Vector2 = a + d * (span * 0.46) + trail * chord * 0.90
    var edge_3: Vector2 = a + d * (span * 0.80) + trail * chord * 0.62
    var lead: Vector2 = a + d * (span * 0.55) - trail * 1.2
    var poly: PackedVector2Array = PackedVector2Array([a, edge_1, edge_2, edge_3, t, lead])
    draw_colored_polygon(poly, Color(col.r, col.g, col.b, 0.20))
    var outline: PackedVector2Array = poly.duplicate()
    outline.append(poly[0])
    draw_polyline(outline, col, 1.6)
    for k: float in [0.30, 0.52, 0.74]:
        var base: Vector2 = a + d * (span * k)
        draw_line(base, a + d * (span * (k + 0.16)) + trail * chord * (0.55 - 0.35 * k),
            col.darkened(0.15), 1.0)
    draw_line(a, t, col.lightened(0.3), 2.0)          # leading edge, reads as the bone
    draw_circle(t, 2.5, col)


## Leg drawn as two bones with a knee. Depth reads through weight, not just colour:
## the far leg is thinner, shorter (foreshortened) and darker than the near one.
func _draw_leg(a: Vector2, tip: Vector2, col: Color, lm: LimbDef) -> void:
    var near: bool = lm.lane > 0
    var thigh: float = lm.reach * 0.52
    var shin: float = lm.reach * 0.52
    var back_w: Vector2 = dir_to_world(Vector2(-1.0, 0.0))
    var bend: Vector2 = to_local(back_w) - to_local(Vector2.ZERO)
    var knee: Vector2 = _two_bone_knee(a, tip, thigh, shin, bend)
    var w: float = 3.5 if near else 2.0
    draw_line(a, knee, col, w)
    draw_line(knee, tip, col, w)
    draw_circle(a, 2.0, col.darkened(0.25))
    draw_circle(knee, 2.5 if near else 1.8, col.lightened(0.3))
    # Short foot segment so the leg ends in a claw instead of a dot.
    var shin_dir: Vector2 = (tip - knee).normalized()
    if shin_dir.length_squared() > 0.0001:
        var foot: Vector2 = tip + shin_dir.orthogonal() * (5.0 if near else 3.5)
        draw_line(tip, foot, col, w)


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
