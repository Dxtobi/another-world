# Design notes and reference algorithms

Pseudo-GDScript for the remaining roadmap tasks. Adapt names to the actual code in `core/`.

## 1. Rain World principles (why the architecture looks like this)

- Two layers. **Logic**: simple float-vector physics (points locked at fixed distances), pathfinding, tile awareness;
  cheap, stable, always running. **Cosmetic**: curvy tentacles, dangly bits, sprites; heavy, decorative, switchable.
- Dependency is one-way: cosmetics read logic, logic never reads cosmetics. So cosmetics can be disabled off-screen
  while AI and simulation keep running.
- Illusionist's approach: fake it. Example: a floating body whose gravity and speed depend on **how many grips**
  it has (fewer = sag and slow, more = free) sells weight with no real physics.
- Grab scoring uses **random sampling** near the creature each frame (not a full scan) and drifts toward better
  scores. The imperfection reads as organic.
- Because animation and AI share state, a creature stuck, swaying or lunging reads as emotion.
- Build discipline: one locomotion mode at a time, circles-and-lines first, no sprites until the logic reads as alive.

## 2. Flight model (implemented in FlyLocomotor)

```
downstroke  = max(0, -cos(flap_phase)) * 2           # pulse, kept for cosmetics
lift_shape  = 0.45 + 0.40 * downstroke               # mean ~0.85, so lift does not live in the pulse
flap_lift   = lift_k * thrust * lift_shape
glide_lift  = clamp(|vel.x| * glide_k, 0, gravity * 0.75)   # stall illusion: slow = sink
hold        = clamp(dy * hold_k, -hold_cap, hold_cap)      # y-down spring toward goal altitude
vdamp       = -vel.y * vdrag_k                             # damps the bungee
g_v         = max(gravity + hold + vdamp - flap_lift - glide_lift, -up_cap)
thrust      = damp(thrust, max(clamp(-dy/150, 0, 1), hover_thrust), 6.0)   # hover_thrust = 0.38
wing angle  = PI + sin(flap_phase - lane*0.25) * amp * (0.35 + 0.65*thrust)   # sweeps back/up/down
```
Why the mean lift: with lift only in the pulse, the body rises hard for a few frames, thrust collapses, it falls,
and repeats — a visible bungee with no stable hover (measured: ±250 px vertical oscillation). Mean lift plus a
saturated hold spring turns hover into a spring settling (<25 px/s residual after ~1 s).
Sign convention trap: keep every vertical term y-down and ADD `hold`; writing `gravity - hold` inverts the
spring and pins the creature to the floor while it climbs (this was T0's second bug).
Hover thrust ~ gravity / (lift_k * 0.85) with the defaults above ≈ 0.85; `hover_thrust` 0.38 plus the spring
covers the rest, which keeps the pose lively instead of rigid.
Steering acts on the FRONT point only; gravity/lift on all points, so the body trails into a bank for free.

## 3. Grip scoring (T4)

```
func try_grip(limb, ideal: Vector2, samples: int):
    var best = limb.grip_pos if limb.gripping else null
    var best_score = score(limb.grip_pos, ideal) if limb.gripping else -INF
    for i in samples:                                   # 6-8 normally, 16 while landing
        var cand = ideal + Vector2(randf_range(-1,1), randf_range(-1,1)) * 40.0
        var s = score(cand, ideal)
        if s > best_score: best_score = s; best = cand
    limb.gripping = best_score > -INF
    if limb.gripping: limb.grip_pos = best

func score(p, ideal):
    if not world.is_solid_adjacent(p): return -INF      # thin air
    return -p.distance_to(ideal)                        # closer to ideal reach point = better
```
Release a grip when `anchor.distance_to(grip_pos) > max_reach`.

## 4. Climbing (T5)

The body does not move itself; the grips move it.

```
func emit(dt, intent, out):
    var dir = (target - body_center).normalized()       # target = next surface-path waypoint
    var grips = limb_system.grip_count()
    var grip_factor = grips / float(limbs.size())       # 0..1
    update_limbs(dir)
    var acc = Vector2.ZERO
    if grips > 0:
        acc += (grip_centroid + wall_normal_offset - center) * hang_stiffness   # spring to grips
        acc += dir * climb_accel * grip_factor
    acc += Vector2(0, gravity * (1 - grip_factor))                              # weight illusion
    acc -= vel * (1 - grip_factor) * 0.5                                        # no purchase, no momentum
    cap speed to climb_max_speed * lerp(0.3, 1.0, grip_factor)
    out.add_accel(each point, acc)

func update_limbs(dir):
    # gait rule: only the limb furthest BEHIND the travel direction may release, and only if >= 2 others hold
    for limb in gripping limbs:
        if anchor.distance_to(grip) > max_reach: release (always allowed)
        elif behind(limb, dir) is largest and grips > 2 and behind > threshold: release it
    for limb in free limbs: try_grip(limb, anchor + dir * max_reach * 0.8, 8)
```
Tuning order: hang_stiffness (too high = rigid, too low = balloon), max_reach, release threshold, sample count.

## 5. Mode switching and transitions (T6)

- `score()` per locomotor; `LocoManager` already adds stickiness + lock_time (hysteresis) and crossfades weights.
- Climb -> fly when no valid grip candidates for ~10 frames or goal unreachable by climbing.
- Fly -> climb when a cling surface is adjacent AND the goal is reachable on the surface grid.
- Launch (on entering fly): push away from the wall, `body.add_impulse(i, normal * 120, dt)`, set `thrust = 1`, release all grips.
- Landing (on entering climb): bleed speed (`prev[i] = prev[i].lerp(pos[i], 0.6)`), 0.4 s window with 16 grip samples.
- Verlet keeps velocity in `pos - prev`, so do not touch `prev` otherwise; switches stay continuous.

## 6. Making 2D feel 3D (T7, T8)

1. **Yaw instead of flip**: `yaw` is an angle damped toward the facing; horizontal squash `cos(yaw)` (clamp |.| >= 0.15).
2. **Per-part depth** `depth = lane * cos(yaw)` -> z_index sign, scale `1 + depth*0.08`, far side tinted darker.
3. **Lift out of the plane**: a stepping foot has hidden height h; draw it raised, slightly bigger, with a smaller shadow.
4. **Critically damped everything**: use `Steering.damp_*`, never assign visuals directly.
5. **Secondary motion**: Verlet chains / spring followers for tail, feathers, jaw (cosmetic layer only).
6. **Eased steps**: limb swings use ease in/out arcs; gait phase blends instead of snapping.
7. **Squash/stretch** from grip count and speed.
8. **Fixed tick + interpolation**: logic at 60 Hz, render interpolated (`Body.render_pos`, or Godot 2D physics interpolation for nodes).

## 7. Cosmetics notes (T9)

- Two-bone IK for legs (law of cosines) from anchor to grip point; smooth with `Curve2D.tessellate()`; skip Godot's
  deprecated 2D IK modification stack.
- Wings: node per wing at the shoulder anchor, rotated by the wing logic angle; feather splay from `sin(flap_phase)`.
- Everything here reads `Creature`/`Body` only. Off-screen: `VisibleOnScreenNotifier2D` -> set cosmetics `process_mode`/`visible`.

### Debug-view stand-in (implemented now, replaced at T7/T9)

No art until T7, so the vector debug view carries the read. Formulas worth keeping when the art lands:

1. **Wing presentation** — one scalar drives both shape axes:
   `presentation = clamp(0.62 * downstroke + 0.38 * (1 - abs(facing)), 0, 1)` with
   `downstroke = max(0, -cos(flap_phase))`.
   `span = reach * lerp(1.0, 0.58, presentation)` (short when toward camera) and
   `chord = lerp(4, 34, presentation)` (broad when toward camera). Edge-on is the opposite on both, which is what
   sells the turn — changing only the angle (a fan) reads as a hand, not a wing.
   The silhouette is leading edge + trailing edge swept along the body's -x + feather ribs.
2. **Two-bone knee** — `thigh = shin = 0.52 * reach`; with chord length `d = |tip - anchor|`,
   `along = (thigh^2 + d^2 - shin^2) / (2d)`, `height = sqrt(thigh^2 - along^2)`, knee =
   `anchor + dir * along + side * height`, where `side` is the component of the body's -x perpendicular to `dir`
   (both knees bend backwards, so they never cross into a bowtie).
3. **Depth by weight**, not just colour: the far leg gets `0.72 * reach` (foreshortening), a thinner line and a
   darker tint. The two legs stride in antiphase (`sin(flap_phase * 0.5 + lane * PI)`).

## 8. Framework changes
(Record here any time a new creature forced an edit in `core/`, and why.)

- **T0 (flight tuning):** no `core/` edit. All changes are inside `locomotors/fly_locomotor.gd`
  (mean lift, hold spring, vertical drag, hover thrust on `enter()`, wing sweep).
- **T0 (project fit):** the framework now lives inside *Another World* (`res://creature_framework/`) rather than
  its own project, and T2 will read the game's hand-drawn polygon platforms instead of a `TileMapLayer`. This is a
  project decision, not a core change; `WorldQuery`'s public API (`is_solid`, `resolve`) stays identical.
- **T1 polish (debug draw in `core/creature.gd`):** body hull, wing silhouette and two-bone legs were added to the
  glue node so the framework can be judged before any art exists. They only read `thrust`/`flap_phase`/`facing` and
  write nothing back, so the one-way rule holds; the whole block is deleted when T7/T9 cosmetics land.
