class_name FlyLocomotor
extends Locomotor
## Fake-aerodynamics flight. No fluid sim: lift comes from flap frequency + forward speed.
##   flap lift  = pulses on the downstroke, scaled by thrust
##   glide lift = proportional to horizontal speed (fast = holds altitude, slow = sinks / stalls)
## Tuning keys (override per creature in rig.tuning): see the c.tune() calls below.


func _init() -> void:
    id = &"fly"


func enter() -> void:
    # Spawn / mode-entry: start at hover effort instead of a gravity gulp.
    if c != null:
        c.thrust = c.tune(&"fly_hover_thrust", 0.38)


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
    var wing_amp: float = c.tune(&"fly_wing_amp", 1.1)
    var hover_thrust: float = c.tune(&"fly_hover_thrust", 0.38)   # baseline effort so lift survives the arrive-stop
    var hold_k: float = c.tune(&"fly_hold_k", 14.0)               # spring toward goal altitude (accel per px of error)
    var hold_cap: float = c.tune(&"fly_hold_cap", 1100.0)         # saturation of the hold spring
    var vdrag_k: float = c.tune(&"fly_vdrag_k", 1.4)              # vertical velocity damping (per s) — kills the bungee
    var up_cap: float = c.tune(&"fly_up_cap", 1600.0)             # max upward accel of a single flap burst

    var target: Vector2 = intent.goal if intent.has_goal else b.pos[m]
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
    var steer: Vector2 = Steering.arrive(b.pos[f], vel_f, target, max_speed * intent.desired_speed, max_accel * (0.4 + 0.6 * c.thrust))

    var g: Vector2 = Vector2(0.0, g_v)
    out.add_accel(f, steer + g)
    out.add_accel(m, g)
    out.add_accel(r, g)

    c.turn_rate = Steering.damp_f(c.turn_rate, clampf((target.x - b.pos[m].x) * 0.01, -1.0, 1.0), 3.0, dt)

    _emit_limbs(out, wing_amp)


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
            var leg_dir: Vector2 = Vector2(-0.45, 1.0).normalized()   # dangle down and back
            out.set_limb_target(i, anchor + c.dir_to_world(leg_dir) * lm.reach * 0.8)
