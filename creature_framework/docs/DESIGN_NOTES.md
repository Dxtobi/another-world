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
thrust      = damp(thrust, max(clamp(-dy/150, 0, 1), hover_thrust), 6.0)   # hover_thrust = 0.85
wing angle  = PI + sin(flap_phase - lane*0.25) * amp * (0.35 + 0.65*thrust)   # sweeps back/up/down
```
Why the mean lift: with lift only in the pulse, the body rises hard for a few frames, thrust collapses, it falls,
and repeats — a visible bungee with no stable hover (measured: ±250 px vertical oscillation). Mean lift plus a
saturated hold spring turns hover into a spring settling (<25 px/s residual after ~1 s).
Sign convention trap: keep every vertical term y-down and ADD `hold`; writing `gravity - hold` inverts the
spring and pins the creature to the floor while it climbs (this was T0's second bug).
Hover thrust ~ gravity / (lift_k * 0.85) with the defaults above ≈ 0.85. It must be that: at 0.38 the mean lift is
~400 against gravity 900, so a slow creature cannot station-keep, settles onto the floor and drags its tail
(found in T3 when waypoints were only 30-60 px above terrain). The hold spring is for correcting error, not for
carrying the creature's weight in steady state.
Steering acts on the FRONT point only; gravity/lift on all points, so the body trails into a bank for free.

## 2b. World query: solids and path grids (implemented in WorldQuery)

The level is hand-drawn: `StaticBody2D` + `CollisionPolygon2D`. There is no tilemap to read, so the physics space
is the source of truth and the creature asks it directly.

- **What is solid.** An `intersect_point` query on `solid_mask` (**layers 1 and 4**), filtered to `StaticBody2D`.
  Layer 1 is the playable ground; layer 4 is the large rock silhouette, which the player currently ignores but
  creatures must not fly through. The type filter is not cosmetic: the player is a `CharacterBody2D` on the same
  layer in some scenes, so a layer test alone would turn the player into floor. Areas (water) and projectiles never
  count.
- **Safety box.** `bounds` is checked first and anything outside it is solid. With no physics space attached, the
  box alone is the world — that is how the dev scene runs with no level loaded.
- **resolve(body)**, per point, per tick:
  1. **sweep** from `prev` to `pos` in sub-samples of `max(2, point_radius * 0.5)`, capped at 12 steps; stop at the
     last free one. This is what stops a fast body passing through a drawn platform.
  2. If the point is still inside, **depenetrate**: bisect back along the tick to the boundary (6 steps); if `prev`
     was inside too (spawned in a wall), ring-probe 16 directions at 2..64 px for the nearest free spot.
  3. **slide**: estimate the outward normal from 8 probes and project the remaining step onto the tangent, then
     sweep that small slide once. Without this, touching the ground kills the whole step and the body sticks.
  4. **bounds clamp** last, so nothing can escape the level box.
  Velocity is rebuilt from the corrected position, removing only the component into the surface — the body slides,
  it does not bounce.
- **Grids** (`bake(rect)`): rasterised by asking `is_solid` at each cell centre, not by reading polygons.
  `air` = non-solid cells, **inflated by `path_clearance` (34 px)**: a cell is also blocked if any of 8 probes at
  that radius hits terrain. A creature is bigger than a point, and without inflation A* routes through the single
  free cell 8 px from a wall face. `surface` = non-solid cells with a solid 8-neighbour and **no inflation** —
  gripping is supposed to hug terrain. `AStarGrid2D`, cell centres via `cell_pos()`,
  `DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES`. `path_air` / `path_surface` return world-space waypoints and an empty array
  if either end is blocked or outside the baked rect. `grid_solid()` / `grid_has()` expose the baked truth for
  tests and debug overlays.
- `get_point_position()` returns cell corners in this Godot, so paths use `cell_pos()` (centre) instead — do not
  mix the two or every waypoint is half a cell off.
- **Bake cost:** inflation makes each cell 9 point queries instead of 1, so bake a rect around the playable area,
  not the whole safety box, and do it once per level (the drawn platforms are static).

Acceptance numbers (`dev/world_test.tscn`): 2467 lattice samples against an independent polygon oracle with
**0 mismatches** across both drawn polygons; a vulture flown into the real ground for 7 s with **0 violations**;
air routes over a tower and through a 140x120 px wall hatch and a surface route along a floor, all with 0 solid
waypoints.

## 2c. Path following and wall feelers (implemented in PathFollower + FlyLocomotor)

`PathFollower` is a planner, not a brain: the brain writes `Intent.goal`, the follower answers "where next".

- **Advance from the HEAD** (`front_point`), because that is the point locomotors steer. Advancing from the centre
  parked the nose on a waypoint while the body hung a spine-length behind (measured: stuck 40 px short forever).
- A waypoint is consumed when within `waypoint_reach` (24 px) **or** once the creature has crossed the waypoint's
  plane along the segment: `(next - wp).dot(from - wp) > 0`. Without the plane test a fast flyer orbits a corner it
  overshot by more than the reach.
- Repath every 0.3 s or when the goal moves > 24 px. A spent path does **not** force a replan: `target()` is the
  goal itself then. Repathing on "spent" ran A* ~40 times a second while the creature hovered on its goal.
- Snap the start and goal to a cell the **baked** grid can use (`grid_has` + `grid_solid`), not just a free physics
  point: a point can be free while its cell centre is solid. A goal inside terrain ring-searches up to 5 cells for
  the nearest usable cell. No grid, or no route, both fall back to the raw goal, so navigation can never freeze a
  creature.
- `Creature.steer_is_goal()` tells a locomotor whether the target is a corner or the final goal. FlyLocomotor keeps
  full speed at corners (slow radius 16) and only brakes for the goal (radius 80). Braking at every 24 px corner
  bled the forward speed that glide lift depends on, and the flyer sank onto the floor.
- **Wall feelers**: 3 probes along velocity at 0 and ±30°, 3 cells long, sampled at 0.5/0.75/1.0 of the reach. The
  centre probe weighs 1.0, the sides 0.6. When blocked, push perpendicular to travel toward whichever side has more
  free reach (half-cell steps). This is the last-metre reflex for overshoot and gusts, not pathfinding.

Acceptance (`dev/path_test.tscn`): a synthetic slalom that forces UP over wall A and DOWN under wall B →
over A at `min y 166.5` (wall top 220), under B at `max y 448.1` (wall bottom 380), goal in 13.9 s, closest
approach 0.2 px, 0 body points in terrain, 150 repaths over 45 s. With no grid the follower returns the raw goal.

## 3. Grip scoring (implemented in LimbSystem)

Grips are found **along the limb**, not by sampling around the ideal tip:

```
reach = limb.reach * 1.25
base  = (ideal - anchor).normalized()
for k in 7:                                            # one ray exactly on the ideal line
    t    = k / 6.0 * 2.0 - 1.0                         # -1..+1 across the fan
    dir  = base.rotated(deg_to_rad(26) * t)
    hit  = ray(anchor + dir * 14, anchor + dir * reach) # terrain only
    if hit:
        score = abs(t) + 0.6 * abs(hit_dist - ideal_dist) / ideal_dist
latch the lowest score
if no ray hit: try world.surface_near(ideal, 10)
```

Why rays along the limb instead of random samples near the ideal tip: the ideal tip is often **inside**
the wall the limb is reaching into, because the locomotor does not know where the face is. A ray from
the anchor stops at the face where a real limb would touch it and returns that face's outward normal;
a sample inside the polygon is not a handhold. The fan covers overshoot and corners, while the `|t|`
term stops a limb grabbing a side wall when the centre line is free.

Why the fallback: a ledge *beside* the tip (the limb swings past it) is outside the fan. `surface_near`
casts 16 rays around the ideal point and refuses points inside terrain, so it cannot invent a grip.

Holding:
- The grip is a fixed world point and is **not re-scored**: a held limb cannot creep along a wall by itself.
- Release when `anchor.distance_to(grip_pos) > reach`, or by an explicit `release()`. That distance is the only
  automatic release; T5's gait rule releases the limb furthest behind the travel direction before it gets there.
- Attempts are throttled to one per limb every 0.06 s (staggered), so four limbs do not fan rays on the same tick.
- T4 is cosmetic: `Creature` pins `limb_tip` to the grip. Turning the grip into a body constraint is T5's job
  (`grip_centroid` in section 4).

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
