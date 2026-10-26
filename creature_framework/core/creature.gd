class_name Creature
extends Node2D
## Glue node: Brain -> Intent -> LocoManager -> MoveOutput -> Body -> WorldQuery.
## Also exposes the proxy variables cosmetics read (thrust, flap_phase, turn_rate, limb_tip).

var rig: CreatureRig
var body: Body
var brain: Brain
var loco: LocoManager
var world: WorldQuery
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
    loco = LocoManager.new()
    loco.setup(self, rig.locomotors)
    limb_tip.resize(rig.limbs.size())
    for i in rig.limbs.size():
        limb_tip[i] = anchor_pos(i)


func _physics_process(dt: float) -> void:
    if body == null:
        return
    brain.think(self, intent, dt)
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

    for l in rig.links:
        draw_line(rp[l.a], rp[l.b], Color(0.6, 0.6, 0.7), 2.0)
    for i in n:
        if i == rig.front_point:
            draw_circle(rp[i], 11.0, Color.ORANGE)
        else:
            draw_circle(rp[i], 8.0, Color.WHITE)

    for i in rig.limbs.size():
        var lm: LimbDef = rig.limbs[i]
        var col: Color = Color(0.5, 0.8, 1.0) if lm.kind == &"wing" else Color(0.9, 0.7, 0.4)
        if lm.lane < 0:
            col = col.darkened(0.4)
        var a: Vector2 = to_local(anchor_pos(i))
        var t: Vector2 = to_local(limb_tip[i])
        draw_line(a, t, col, 3.0)
        draw_circle(t, 4.0, col)

    if intent.has_goal:
        draw_circle(to_local(intent.goal), 6.0, Color.RED)
        draw_arc(to_local(intent.goal), 14.0, 0.0, TAU, 24, Color(1.0, 0.3, 0.3, 0.6), 1.5)
