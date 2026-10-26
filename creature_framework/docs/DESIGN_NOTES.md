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
  The **landing window** (T6) is the exception: for 0.4 s every free limb tries every tick with 16 rays over ±34°,
  so a moving flyer catches a face on the transition.
- T4 was cosmetic: `Creature` pins `limb_tip` to the grip. T5 turns the grips into a body constraint by pulling
  toward `grip_centroid()` along `grip_normal_avg()` (section 4); the tip pin remains for the visual limb.

## 4. Climbing (implemented in ClimbLocomotor)

The body does not move itself; the grips drag it. The wall frame is the average outward normal of the **held**
grips. Only before the first grip does a `surface_near(body_center, 70)` probe find a face. Travel is the goal
direction projected onto the wall (`t = normalize(wish - n * wish.dot(n))`), so a goal straight into the wall
means "hold still" rather than "push inward".

Per tick, before `body.step`:

1. **Gait.** If not arrived, `limbs.release_furthest_behind(tangent, min_other = 2, min_behind = 20)`: at most one
   held limb is let go per tick, and only the one furthest *behind* the body along the travel tangent, and only
   while two others still hold. `LimbSystem.update` has already dropped any grip past `max_reach` (the hard
   constraint), so the gait release is what starts the next reach before the body pulls that limb off.
2. **Weight illusion.** `grip_factor = grips / limbs.size()`. Gravity is `900 * (1 - grip_factor)`, so fewer grips
   means more hang. With zero grips the body also gets `-vel * 1.2`: it coasts to a stop instead of chasing the
   goal with no purchase.
3. **Body line.** `hold = grip_centroid + n * (30 + 8 * free_limbs)` — each free limb lets the belly hang a little
   further out, so the hand-over-hand cycle rocks the body in and out instead of sliding up a rail. Each point's
   desired position is `hold + tangent * point.offset.x - n * point.offset.y`, i.e. the spine is laid **along** the
   travel direction with the belly toward the wall. A spring (`k = 14`) plus damping (`6`) pulls every point there.
   `tangent * 240 * grip_factor` is the climb push, capped at `130 px/s` along the tangent.
4. **Free limbs.** Each free limb reaches to `project(anchor, wall) + tangent * min(reach * 0.75, 52) + n * 5`, then
   `LimbSystem`'s normal ray fan grips the face. The 5 px offset keeps the ray's start clear of the surface.

`ClimbLocomotor.score()` returned 1 only while at least one grip was held in T5. T6 extends the score (section 5)
so a flyer lands when the goal sits on a reachable surface; `VultureRig` now lists `FlyLocomotor` then
`ClimbLocomotor`.

Tuning order: `climb_hang_k` (too high = rigid, too low = balloon), `climb_free_sag` / `climb_hold_offset`,
`climb_gait_behind`, then `climb_accel` / `climb_max_speed`.

Acceptance (`dev/climb_test.tscn`): a vulture with only `ClimbLocomotor` starts spine-vertical on a wall at x 340.
All four limbs hold at **0.05 s**; it climbs **238.1 px** (min y 191.9), comes within **15.5 px** of the goal and
reaches it in **6.33 s**. The gait makes **37** grip changes; every limb releases and re-grips (`1111`). In/out
sway is **3.32 px**, with **0** body points inside terrain. The no-grip case (open air, shoved to 180 px/s) sags
**254.9 px** in 1 s, decays `vx 180 -> 21.2`, and never finds a grip.

Demo (`dev/climb_demo.tscn`, MCP-verified at 640x360): the goal slides between y 180 and 380. The vulture climbs
to ~204, descends to ~379, the HUD shows 4/4 grips (3 during a gait release), and the game log has no errors.

## 5. Mode switching and transitions (implemented in LocoManager + locomotor scores)

The locomotion manager already adds stickiness and a switch lock, so the mode scores only have to answer
"which mode is better right now". Transitions are then a blend, not a snap.

```
climb held + goal climbable     2.00
climb held + goal left surface  0.25      # fly's 1.0 wins on the next decision
climb landed + goal climbable   1.80      # face adjacent + surface route to goal
fly                             1.00      # always possible
stickiness                      0.25      # score bonus for the current mode
lock                            0.50 s    # no switch sooner than this
crossfade                       0.35 s
```

- **What "goal climbable" means:** the goal is within `climb_goal_radius` (52 px) of terrain, **and** the
  surface grid has a path from the body to that goal. The result is cached for 12 physics frames and invalidated
  early when the goal moves more than 24 px; A* must not run every tick.
- **Probe the head first.** Flight steers by the head, so when a flyer hovers at a wall goal its head is on the
  face while its centre is a body-length back. Scoring therefore calls `surface_near(head)` and only falls back
  to the centre. Probing the centre alone left the flyer hovering at the goal without ever landing.
- **Landing (on entering climb):** if no grip is held and speed is above 60 px/s, bleed to 40 % of it with
  `prev[i] = prev[i].lerp(pos[i], 0.6)`. Open a 0.4 s landing window in `LimbSystem`: every free limb attempts on
  every tick with 16 rays over ±34°. The bleed itself is what keeps the body from spearing into the face at
  flight speed.
- **Launch (on entering fly):** read the average held-grip normal, add `120 px/s` to every point along it,
  release every grip with a 0.3 s re-grip lockout, and set `thrust = 1` so the wings catch the fall. The lockout
  matters: without it the wings immediately catch the face they just left.
- Verlet keeps velocity in `pos - prev`, so `prev` is only touched for the landing bleed; every other switch is
  continuous by construction.
- **Hysteresis in practice:** the mode harness asserts the exact switch count (1 / 1 / 0 / 1) rather than merely
  "ends in the right mode", so a one-frame flicker fails. The 0.5 s lock is what makes that stable.
- **Clearance is per body.** The mode harness bakes with `path_clearance = 58` because the vulture spine is 80 px;
  the default 34 px is a point-sized assumption and let the body wedge on tall corners. One shared bake per level
  (T11) needs the largest creature's clearance, or per-creature grids.

Acceptance (`dev/mode_test.tscn`): climb-only goal -> exactly 1 switch, reach in **4.08 s** in climb, closest
**29.4 px**, 4 grips; move the goal into open air -> exactly 1 switch, reach in **9.38 s** in fly, launch
`vx -96.8`, 0 grips; flight-only goal -> **0** switches, reach in **8.00 s**; ambiguous goal -> climb, exactly
**1** switch, reach in **3.35 s**, 4 grips. **0** body points inside terrain in every phase.

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

## 8. Authoring a creature as a scene

The baker is a one-way translation, scene -> `CreatureRig`. Nothing in `core/` knows that a scene exists. The entry
point is static: `RigBlueprint.load_rig(path, fresh := false)` loads and instantiates the packed scene, runs
`validate()`, logs every broken rule with the scene's file name, and returns the baked `CreatureRig` (or `null`).
`fresh` uses `CACHE_MODE_IGNORE` instead of `CACHE_MODE_REUSE`, so a scene saved in the editor can be rebuilt
without restarting the game. `VultureRig.build()` is now a one-line wrapper around it, so every harness still asks
for a `CreatureRig` and gets one, and no test knows a scene path.

The no-code authoring loop is `dev/playground.tscn` + `dev/playground.gd`: a small floor/wall/ledge level with an
exported `rig_scene` (default: the vulture), `spawn`, `path_clearance` and `show_path`. It bakes the level into
`WorldQuery`, follows the creature with a camera, drives it with `MouseBrain`, and draws the goal plus the current
A* path; the HUD shows the rig name, point/limb counts, active locomotor and blend weights, grip count and goal
distance. **R** calls `load_rig(rig_scene, true)` again, so the edit-save-rebuild loop needs no code at all. A new
creature is therefore: duplicate a rig scene, shape it in the inspector, point the playground's `rig_scene` at it.

| Scene | Baked into |
| --- | --- |
| `RigPoint.position` | `PointDef.offset` — the rest offset from the creature origin |
| `RigPoint.mass`, `base_depth` | `PointDef.mass`, `PointDef.base_depth` |
| consecutive `RigPoint`s | `LinkDef(a=i, b=i+1)` rest = pose distance, stiffness 1.0 |
| `RigLink.a/b/stiffness/rest_length` | extra `LinkDef`; `rest_length <= 0` means "pose distance" |
| `RigLimb` parent | `LimbDef.anchor_point` = the parent point's baked index |
| `RigLimb.position` | `LimbDef.local_offset` (spine frame: +x forward, +y belly) |
| `RigLimb.kind/style/lane/reach` | `LimbDef.kind/style/lane/reach` |
| `front_point/center_point/rear_point` | `CreatureRig.front_point/center_point/rear_point` (names -> indices) |
| `locomotor_flags` | `rig.locomotors` through `LocomotorCatalog`, in fly-then-climb order |
| `tuning` | deep copy into `rig.tuning` |

Why the layout is shaped that way:

- **Point order is the index**, so the inspector does not expose integer indices that go stale when a point is
  added or rearranged. The three roles are stored by *name* and resolved to indices at bake.
- **A limb's parent is its anchor.** "Add a leg to the chest" is an editor reparent, and there is no second
  anchor field to drift out of sync.
- **Consecutive links are automatic.** A spine is defined by the order the points appear in; `RigLink` exists only
  for the extra members (the vulture's weak front->rear bend-resist). Moving a point changes the rest length,
  because the rest pose *is* the scene pose.
- **Only positions bake.** Point/limb rotation and scale are rejected by validation rather than silently
  discarded. The solver owns the runtime transform; a rest offset is a position, not a pose. (The root's own
  transform is not read at all.)
- **Limbs bake in point order, then child order**, so `LimbSystem` indices are stable for a given scene.

Validation (all reported by `validate()`, and `build_rig()` returns `null` while anything is wrong): >= 3 points;
unique non-empty names; `mass > 0`; finite positions; no rotation/scale; the three role names exist and differ;
limbs are direct children of a `RigPoint` with a known `style`, a `lane` of -1/+1, `reach > 0`; link endpoints
exist and differ, stiffness 0..1, finite positive rest lengths; at least one locomotor flag and no unknown bits;
every tuning value finite. The **Validate rig** inspector button prints the same list.

Two Godot 4.7 details worth remembering:

- `@export_enum` rejects `StringName` ("requires int/String/arrays of them"). `RigLimb.kind`/`style` are therefore
  `String` in the inspector and converted to `StringName` at bake. The data layer stays typed.
- A `.gd` that failed to parse once can stay broken in a running editor even after the file is fixed; the MCP
  editor needed a filesystem scan plus a scene reload before the new exported fields appeared. Headless
  `--check-only` reads the global class cache from `.godot/`, so a brand-new `class_name` needs an editor scan
  before `--check-only` can resolve it.

The preview is editor-only drawing on the same nodes: `RigPoint` rings with a centred name above (mass/depth only
when non-default), `RigLimb` a solid stub plus a dashed reach guide with its label beside the tip (far limbs to the
left, near to the right, keyed by `lane`), `RigBlueprint` spine/brace links, an origin cross and a header centred
over the rest pose. `RigDraw.text()` adds a dark outline so labels survive any background. None of it is baked.

## 9. Framework changes
(Record here any time a new creature forced an edit in `core/`, and why.)

- **T0 (flight tuning):** no `core/` edit. All changes are inside `locomotors/fly_locomotor.gd`
  (mean lift, hold spring, vertical drag, hover thrust on `enter()`, wing sweep).
- **T0 (project fit):** the framework now lives inside *Another World* (`res://creature_framework/`) rather than
  its own project, and T2 will read the game's hand-drawn polygon platforms instead of a `TileMapLayer`. This is a
  project decision, not a core change; `WorldQuery`'s public API (`is_solid`, `resolve`) stays identical.
- **T1 polish (debug draw in `core/creature.gd`):** body hull, wing silhouette and two-bone legs were added to the
  glue node so the framework can be judged before any art exists. They only read `thrust`/`flap_phase`/`facing` and
  write nothing back, so the one-way rule holds; the whole block is deleted when T7/T9 cosmetics land.
- **T5 (grip helpers in `core/limb_system.gd`):** added `grip_centroid()`, `grip_normal_avg()` and
  `release_furthest_behind()` because the climb body constraint needs to read all grips through one API instead of
  reaching into the arrays from the locomotor. `grip_normal()` was renamed `grip_normal_avg()` to stop colliding
  with the `grip_normal` member array; the array itself is unchanged. No behaviour changed for `FlyLocomotor`.
- **T6 (surface reachability in `core/world_query.gd`):** added `surface_reachable(a, b, max_snap_cells)` and
  `nearest_surface_cell()`. Mode scoring needs to know whether the surface grid connects two points; doing it in
  the locomotor would duplicate grid internals, and both methods are useful to any future climber. With no grid the
  query returns true (the caller has already checked both points touch a surface), preserving dev-scene behaviour.
- **T6 (landing window + launch lockout in `core/limb_system.gd`):** added `begin_landing()`, `end_landing()` and
  an optional cooldown to `release_all(cooldown)`. The landing window changes the ray fan/attempt cadence, which is
  grip-search policy and belongs with the grip code, not in a locomotor. `release_all` previously had no way to
  prevent immediate re-gripping, so the launch could not leave the wall. Existing callers are unaffected by the
  default cooldown.
- **Authoring (new `LimbDef.style`):** the only data-layer change for scene authoring: an additive `style`
  `StringName` (`default`/`flap`/`walk2`/`reach`/`dangle`/`tentacle`) between `kind` and `anchor_point`. Nothing
  reads it yet — T9 binds the cosmetic behaviour to the catalog — but baking it now means a style picked in the
  inspector is never silently dropped. `kind` stays the coarse debug/collision family, so existing code that
  switches on `kind` is untouched.
