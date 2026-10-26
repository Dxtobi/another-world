class_name FlyLocomotor
extends Locomotor
## Fake-aerodynamics flight. No fluid sim: lift comes from flap frequency + forward speed.
##   flap lift  = pulses on the downstroke, scaled by thrust
##   glide lift = proportional to horizontal speed (fast = holds altitude, slow = sinks / stalls)
## Tuning keys (override per creature in rig.tuning): see the c.tune() calls below.
##
## Steering aims at `Creature.steer_target()` (the current path waypoint, or the goal when
## there is no plan) and adds a short wall-avoidance push, so a fast flyer that overshoots a
## path corner still turns away from terrain instead of grinding into it.

## Half-angle of the three feeler probes used for wall avoidance.
const WALL_PROBE_ANGLE := deg_to_rad(30.0)
## How far ahead the feelers reach, in world cells.
const WALL_PROBE_CELLS := 3.0


func _init() -> void:
    id = &"fly"


func enter() -> void:
    # Spawn / mode-entry: start at hover effort instead of a gravity gulp.
    if c != null:
        c.thrust = c.tune(&"fly_hover_thrust", 0.85)


func score(_intent: Intent) -> float:
    # Flight is always possible. ClimbLocomotor will score higher when a grip surface is adjacent
    # and the goal is climb-reachable (see README task T6).
    return 1.0


func emit(dt: float, intent: Intent, out: MoveOutput) -> void:
    var b: Body = c.body
    var rig: CreatureRig = c.rig
    var f: int = rig.front_point
    var m: int = rig.center_point
    var r: int = rig.rear_point

    var gravity: float = c.tune(&"gravity", 900.0)
    var lift_k: float = c.tune(&"fly_lift_k", 1250.0)
    var glide_k: float = c.tune(&"fly_glide_k", 2.2)
    var max_speed: float = c.tune(&"fly_max_speed", 420.0)
    var max_accel: float = c.tune(&"fly_accel", 900.0)
    var freq_min: float = c.tune(&"fly_freq_min", 1.5)
    var freq_max: float = c.tune(&"fly_freq_max", 5.0)
    var wing_amp: float = c.tune(&"fly_wing_amp", 1.35)
    # Baseline effort that actually holds altitude. Mean flap lift is
    # lift_k * thrust * ~0.85, so 0.85 here balances gravity (900 / (1250 * 0.85)).
    # A lower baseline makes a slow creature sink and drag along the floor.
    var hover_thrust: float = c.tune(&"fly_hover_thrust", 0.85)
    var hold_k: float = c.tune(&"fly_hold_k", 14.0)               # spring toward goal altitude (accel per px of error)
    var hold_cap: float = c.tune(&"fly_hold_cap", 1100.0)         # saturation of the hold spring
    var vdrag_k: float = c.tune(&"fly_vdrag_k", 1.4)              # vertical velocity damping (per s) — kills the bungee
    var up_cap: float = c.tune(&"fly_up_cap", 1600.0)             # max upward accel of a single flap burst

    var target: Vector2 = c.steer_target()
    var vel_m: Vector2 = b.velocity(m, dt)
    var vel_f: Vector2 = b.velocity(f, dt)

    # Brain-ish logic that belongs to the mode: how hard to flap depends on how far above us the goal is.
    var dy: float = target.y - b.pos[m].y                  # negative = goal is above
    var want: float = clampf(-dy / 150.0, 0.0, 1.0)
    c.thrust = Steering.damp_f(c.thrust, maxf(want, hover_thrust), 6.0, dt)

    var flap_freq: float = lerpf(freq_min, freq_max, c.thrust)
    c.flap_phase = fmod(c.flap_phase + flap_freq * TAU * dt, TAU)

    # Mean lift with a small alive pulse on the downstroke, instead of lift living
    # entirely in the pulse (which turns the body into a bungee around the goal).
    var downstroke: float = maxf(0.0, -cos(c.flap_phase)) * 2.0
    var lift_shape: float = 0.45 + 0.4 * downstroke        # avg ~0.85 across the cycle
    var flap_lift: float = lift_k * c.thrust * lift_shape
    var glide_lift: float = clampf(absf(vel_m.x) * glide_k, 0.0, gravity * 0.75)

    # Hold assist: saturated spring toward goal altitude + vertical drag, so hovering
    # is a spring settling, not a pump. Prestaged for T6 (climb->fly needs gentle entries).
    var a_hold: float = clampf(dy * hold_k, -hold_cap, hold_cap)   # y-down accel toward goal altitude
    var a_vdamp: float = -vel_m.y * vdrag_k                        # opposes vertical velocity
    var g_v: float = gravity + a_hold + a_vdamp - flap_lift - glide_lift
    g_v = maxf(g_v, -up_cap)          # cap upward burst only; falling accelerates honestly

    # Steering acts on the head; the body trails behind through the constraints (gives banking for free).
    # Brake only for the final arrival. Slowing at every 24 px waypoint bleeds the forward speed
    # that glide lift depends on, and the creature sinks onto the floor between corners.
    var slow_radius: float = 80.0 if c.steer_is_goal() else 16.0
    var steer: Vector2 = Steering.arrive(b.pos[f], vel_f, target, max_speed * intent.desired_speed, max_accel * (0.4 + 0.6 * c.thrust), slow_radius)
    steer += _avoid_force(b.pos[m], vel_m, max_accel)

    var g: Vector2 = Vector2(0.0, g_v)
    out.add_accel(f, steer + g)
    out.add_accel(m, g)
    out.add_accel(r, g)

    c.turn_rate = Steering.damp_f(c.turn_rate, clampf((target.x - b.pos[m].x) * 0.01, -1.0, 1.0), 3.0, dt)

    _emit_limbs(out, wing_amp)


## Short feelers in front of the body: if terrain is ahead, push sideways toward the freer
## side. This is not pathfinding (the grid already did that) - it is the last-metre reflex
## for overshoot, gusts and creatures whose turn radius is bigger than a cell.
func _avoid_force(from: Vector2, vel: Vector2, max_accel: float) -> Vector2:
    var w: WorldQuery = c.world
    if w == null:
        return Vector2.ZERO
    var speed: float = vel.length()
    if speed < 24.0:
        return Vector2.ZERO      # hovering: steering already holds position, save the queries
    var dir: Vector2 = vel / speed if speed > 1.0 else Vector2(c.facing, 0.0)
    var reach: float = w.cell_size * WALL_PROBE_CELLS

    var blocked: float = 0.0
    for k in 3:
        var off: float = (float(k) - 1.0) * WALL_PROBE_ANGLE
        if _blocked(w, from, dir.rotated(off), reach):
            blocked += 1.0 - absf(off) / WALL_PROBE_ANGLE * 0.4   # the centre feeler counts most
    if blocked <= 0.0:
        return Vector2.ZERO

    var perp: Vector2 = dir.orthogonal()
    var plus: float = _free_reach(w, from, perp, reach)
    var minus: float = _free_reach(w, from, -perp, reach)
    var side: Vector2 = perp if plus >= minus else -perp
    return side * max_accel * clampf(blocked / 1.6, 0.0, 1.0)


func _blocked(w: WorldQuery, from: Vector2, dir: Vector2, reach: float) -> bool:
    for f: float in [0.5, 0.75, 1.0]:
        if w.is_solid_point(from + dir * reach * f):
            return true
    return false


## Free distance along a direction, in half-cell steps. Used to pick the escape side.
func _free_reach(w: WorldQuery, from: Vector2, dir: Vector2, reach: float) -> float:
    var step: float = w.cell_size * 0.5
    var d: float = step
    while d < reach:
        if w.is_solid_point(from + dir * d):
            return d
        d += step
    return reach


func _emit_limbs(out: MoveOutput, wing_amp: float) -> void:
    var rig: CreatureRig = c.rig
    for i in rig.limbs.size():
        var lm: LimbDef = rig.limbs[i]
        var anchor: Vector2 = c.anchor_pos(i)
        if lm.kind == &"wing":
            var amp: float = wing_amp * (0.35 + 0.65 * c.thrust)
            var swing: float = sin(c.flap_phase - float(lm.lane) * 0.25) * amp
            # Sweep back through up and down, so the debug lines read as a beat
            # (straight up looked like antennae). The lane fan keeps the near and
            # far wing from collapsing into one line.
            var wing_dir: Vector2 = Vector2.from_angle(PI + swing + float(lm.lane) * 0.22)
            out.set_limb_target(i, anchor + c.dir_to_world(wing_dir) * lm.reach)
        elif lm.kind == &"leg":
            # Two legs, not one line copied twice: the far leg splays further out,
            # sits shorter (it is behind the body) and strides in opposition to the
            # near leg. The debug view draws it thinner and darker.
            var near: bool = lm.lane > 0
            var splay: float = float(lm.lane) * (0.30 if near else 0.44)
            var stride: float = sin(c.flap_phase * 0.5 + (0.0 if near else PI)) * 0.15
            var leg_dir: Vector2 = Vector2(-0.35 + splay + stride, 1.0).normalized()
            var stretch: float = 0.90 if near else 0.72
            out.set_limb_target(i, anchor + c.dir_to_world(leg_dir) * lm.reach * stretch)
