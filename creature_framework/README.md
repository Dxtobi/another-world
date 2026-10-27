# Creature Framework (Godot 4, GDScript)

A reusable framework for building **many different creatures with many different kinds of movement** in a
**2D side-scroller**, where the motion still feels **smooth and 3D-like**.

Inspired by the Rain World animation approach (GDC talk "The Rain World Animation Process"): a cheap, stable
**logic layer** (points + distance constraints) decorated by a heavy **cosmetic layer** that only ever *reads* the logic.

> **Status:** T0-T8 done, plus the editor-authoring layer. The framework lives inside the *Another World*
> project (`res://creature_framework/`), runs on Godot 4.7.1, and is verified by a self-terminating 60 s
> scripted run (0 errors, 0 NaN, bounded speeds, no single-frame pose pops), a world harness that checks the
> real level's drawn polygons and path grids, a flight harness that flies a slalom to a goal, a grip harness
> that latches limbs onto a wall, a climb harness that crawls a wall hand-over-hand and sags with no grips, a
> mode harness that lands, climbs, launches and refuses to switch when the goal is in open air, an
> authoring harness that bakes the authored vulture scene back to the exact reference rig (and proves a
> one-node tail/tentacle bakes into a real, articulated chain), a depth harness
> that turns a profile body through a front/back view and swaps near/far exactly once, and a smoothness harness
> that proves the tail lags and settles, limb swings are eased arcs, and stretch damps with speed and grip count.
> Steps 1-8 (Body, Intent/Brain, LocoManager, FlyLocomotor, debug view, world query, path following, limb grips,
> climb locomotor, mode switching, depth layer, smoothness) and the scene-based rig editor are implemented;
> T9 (cosmetics) is next.

Requires **Godot 4.7+** (developed against 4.7.1).

**How to run it in this project:** open `creature_framework/dev/creature_test.tscn` and press F6.
It runs the scripted `DemoBrain` (climb / hover / sink / bank, 6 s each) with metrics printed to the
console. Set the environment variable `CF_MOUSE=1` to chase the cursor with `MouseBrain` instead.
For the T5 climb read, open `creature_framework/dev/climb_demo.tscn` and press F6: a vulture clings to
a wall while the goal slides up and down it, with the grip count in the HUD.
For the T6 mode read, open `creature_framework/dev/mode_demo.tscn` and press F6: the goal alternates between
the wall and open air, so the vulture lands, climbs, launches off the wall and returns. The HUD shows the active
locomotor, both blend weights, the grip count and the current phase.
For the T7 depth read, open `creature_framework/dev/depth_demo.tscn` and press F6: the vulture flies between a
left and a right goal, so every crossing is a turnaround through edge-on. The HUD shows yaw, squash, facing and
the current near/far draw order; **T** flips the goal now and **S** toggles slow motion.
For the T8 smoothness read, open `creature_framework/dev/smooth_demo.tscn` and press F6: the same crossings now
show the tail lagging and swinging, the eased leg arcs and the body stretching along its spine at speed. The HUD
prints speed, stretch and tail sway; **T** flips the goal and **S** toggles slow motion.
To author a creature, open `creature_framework/creatures/vulture.tscn`: the rig is a normal scene, and the
**Validate rig** button in the inspector checks it before anything runs.
To *try* a rig without touching code, open `creature_framework/dev/playground.tscn`, set its `rig_scene`
to any authored scene, and press F6: the creature flies at the mouse, and **R** rebuilds it after you save.
The game's own main scene is untouched.

---

## Rules you must not break

1. **One-way dependency.** Cosmetics read from logic. Logic never reads cosmetics. Ever.
2. **Locomotors never move things directly.** They only call `out.add_accel(point, accel)` and
   `out.set_limb_target(limb, world_pos)` on the `MoveOutput`. The `LocoManager` blends them by weight.
3. **Brains only write an `Intent`.** They never touch the body or call locomotor code.
4. **Creatures are data.** A new creature is a new authored rig scene in `creatures/` (points, limbs, links,
   locomotor choices, tuning) — or, for a code-only test, a builder in `rigs/`. Adding a creature must not require
   editing `core/`. If it does, fix the abstraction, not the creature.
5. **Never assign a position/angle/scale directly for visuals.** Run it through `Steering.damp_f/damp_v`.
6. **Units:** pixels and seconds. Accelerations are px/s^2. Logic runs in `_physics_process` at a fixed 60 Hz.
7. **Typing:** static types everywhere, 4-space indentation, one `class_name` per file.
8. **Fake it, don't simulate it.** Prefer cheap proxy variables (`thrust`, `flap_phase`, `turn_rate`,
   grip count) over real physics. They are also what cosmetics read.

---

## File map

```
dev/creature_test.tscn / dev/creature_test.gd   dev scene: creature + HUD (+ scripted demo metrics)
core/
  intent.gd          what the brain wants (goal, desired_speed, urgency, look_dir)
  brain.gd           base class, fills an Intent
  point_def.gd       \
  link_def.gd         |  Resources that describe a creature as data
  limb_def.gd         |
  body_part_def.gd    |
  creature_rig.gd    /
  body.gd            Verlet points + distance constraints (the logic layer)
  world_query.gd     the creature's only view of the level (physics solids + air/surface path grids)
  path_follower.gd   goal -> next waypoint, with repathing and hole-free fallback
  limb_system.gd     per-limb grip state: ray-fan grip search, fixed hold, over-reach release
  locomotor.gd       base class: score(), enter(), exit(), emit()
  loco_manager.gd    scoring + hysteresis + weighted crossfade
  move_output.gd     accumulates accelerations and limb targets, scaled by blend weight
  steering.gd        arrive(), damp_f(), damp_v()
  depth.gd           T7 cosmetic 2.5D: yaw, squash, per-part depth, scale/tint/z helpers
  secondary.gd       T8 cosmetic follow chain (tail/feathers): Verlet + spring + exact segments
                     (skipped when a rig authors a tail BodyPart)
  creature.gd        glue node + proxy variables + debug draw
brains/mouse_brain.gd                 debug brain (goal = mouse)
brains/demo_brain.gd                  scripted brain for reproducible T0 runs
authoring/
  rig_blueprint.gd     authors a CreatureRig as a scene: bake, validation, editor preview
  rig_point.gd         one spine point (position = rest offset, mass, base_depth)
  rig_limb.gd          one limb, child of its anchor point (kind/style/lane/reach)
  rig_body_part.gd     one tail/tentacle: length = extra points, generates an auto-linked chain
  rig_link.gd          extra distance constraint between two named points
  limb_style_catalog.gd  valid limb style ids + kind/bone hints
  locomotor_catalog.gd   authored locomotor flags -> GDScript classes
  rig_draw.gd          outlined-label helper shared by the @tool nodes
creatures/vulture.tscn                the authored vulture rig: the source of truth
dev/creature_test.tscn                one creature + HUD; 60 s self-terminating metrics run
dev/world_test.tscn                   T2 harness: real-level oracle, dive test, path grids (exits non-zero)
dev/path_test.tscn                    T3 harness: up-and-down slalom flight to a goal (exits non-zero)
dev/grip_test.tscn                    T4 harness: wall latch, thin air, reach limit, hold/release (exits non-zero)
dev/climb_test.tscn                   T5 harness: wall climb, gait cycle, sway, no-grip sag (exits non-zero)
dev/climb_demo.tscn                   T5 live demo: visible wall, oscillating goal, HUD grip count
dev/mode_test.tscn                    T6 harness: land/climb/launch, flight-only, ambiguous goal (exits non-zero)
dev/mode_demo.tscn                    T6 live demo: wall vs open-air goal, mode HUD + path overlay
dev/depth_test.tscn                   T7 harness: turn sweep, draw-order swap, step lift, live facing (exits non-zero)
dev/depth_demo.tscn                   T7 live demo: left/right goals, yaw/squash/draw-order HUD, T turn, S slow
dev/smooth_test.tscn                  T8 harness: chain lag/settle, eased arcs, stretch, live sway (exits non-zero)
dev/smooth_demo.tscn                  T8 live demo: tail, eased legs, spine stretch HUD, T turn, S slow
dev/authoring_test.tscn               authoring harness: scene bake, mutation, validation, runtime (exits non-zero)
dev/playground.tscn                   no-code playground: exported rig scene + mouse goal + R rebuild
locomotors/fly_locomotor.gd           flight: flap lift + glide lift + path steering + wall feelers
locomotors/climb_locomotor.gd         climbing: grip-centroid body spring + hand-over-hand gait
rigs/vulture_rig.gd                   loads `creatures/vulture.tscn` and bakes it (harness entry point)
docs/DESIGN_NOTES.md                  algorithms and reference code for the remaining tasks
```

Per-tick order (in `Creature._physics_process`):
`brain.think -> path.update -> limbs.update (drop over-extended grips) -> loco.update (emit forces; free limbs
try to grip) -> body.step -> world.resolve`. Cosmetics run in `_process`.

### Debug view (dev aid; replaced by T9 art)
Circles and lines only, but it has to carry the read until then:

- **Depth**: `DepthLayer` gives every part a signed depth from its side (`lane` or a point's
  `base_depth`). Far parts draw before the body hull and are darker/smaller; near parts draw after it. During a
  turnaround both sides cross zero at edge-on, so the order swaps once, smoothly. The whole creature is also
  squashed horizontally around its centre by `abs(cos(yaw))`, never below 0.15, which is the front/back view.
- **Stretch**: at speed the body elongates along its spine by up to 9 % and narrows across it by up to 5 %;
  a climber missing grips sags into the same axis. Damped, composed with the squash, never below a zero scale.
- **Tail**: a five-segment cosmetic chain on the rear point with a small feather fan. It lags and swings through a
  turn, trails further behind at speed and droops under its own weight. The logic never reads it.
- **Eased limbs**: a stepping leg's drawn tip follows a smoothstep arc (ease in/out, bowed away from the shoulder),
  then lands exactly on the logic target; grips use a short arc so the limb meets the dot. Wings stay direct.
- **Body**: a tapered hull through the three spine points plus a head disc, so limbs have something to attach to.
- **Wing**: leading edge (shoulder → tip), a trailing edge swept back in the body frame, and 3 feather ribs.
  A single `presentation` scalar widens the chord *and* shortens the span, so the wing is broad when it faces the
  camera (downstroke, or turning through edge-on) and long/thin side-on — the Rain World depth swap.
- **Leg**: two bones (`0.52 * reach` each) with the knee placed by the law of cosines, bending backwards. The far leg
  is shorter (foreshortened), thinner and darker, and the two legs stride in antiphase, so it reads as two legs at
  different depths rather than one line copied.
- **Step lift**: a free leg while climbing/crawling raises its foot off the surface along the grip normal, fattens
  it slightly and shrinks its shadow; a held leg drops back. Wings never step.
- **Grip**: a translucent green dot on the contact point, a bright core, and a short tick along the surface normal.
  The limb tip is pinned to that dot, so "holding" reads even while the limb itself is still a line.
- In `dev/creature_test.tscn`, **Z** toggles a 3.2× camera that follows the creature.

---

## Roadmap (do in order, one task at a time)

Each task has an **acceptance test**. Do not start the next task until the current one passes.
Keep the debug view (circles and lines) working at all times. **No art until T9.**
Read `docs/DESIGN_NOTES.md` for the algorithms referenced below.

### T0. Run it and fix it  ✅ done
- Open in Godot 4.7, run `dev/creature_test.tscn`, fix any parse/runtime errors.
- Tune `FlyLocomotor` defaults (or `rig.tuning`) until: goal high = flaps harder and rises; goal low = glides
  down; goal behind = turns and banks; creature can hover near a still cursor without wild oscillation.
- **Accept:** 60 seconds of mouse-chasing with no errors, no explosions (NaN/huge velocities), movement reads as alive.
- **Done:** 60 s scripted run (4 regimes), 0 errors, 0 NaN frames, peak speed ~510 px/s (one goal-step transient),
  hover settles to <25 px/s. Two fixes were needed: (a) lift lived entirely in the flap pulse, so the body
  bungeed around the goal — replaced with mean lift + a small alive pulse, a saturated hold spring and vertical
  drag; (b) a sign inversion in that hold term pinned the creature to the floor while climbing. Both are in
  `FlyLocomotor` only; `core/` was not touched.

### T1. Facing without popping  ✅ done
- Replace the instant left/right flip in `Creature.dir_to_world()` with a smoothed `facing` value
  (damped toward `intent.look_dir.x`). Use it wherever a mirror is needed.
- **Accept:** reversing direction does not make wings/legs jump in one frame.
- **Done:** `Creature.facing` (-1..+1) is damped toward `look_dir.x` at `facing_rate` (9.0, tunable). It passes
  through 0 — the edge-on view — so the x component foreshortens instead of mirroring, and pitch is derived with
  `atan2` in the facing frame (continuous through vertical; a `wrapf` version created a new seam at ±90°).
  Measured single-frame limb-tip jumps over the 60 s run: old mirror **153.9 px** wings / **85.3 px** legs at every
  reversal; now ~70 px wings (that peak also occurs with facing held steady, i.e. it is flap speed, not a pop)
  and ~26 px legs. Dev scene prints `tipjump` and `facing`, and logs `BIGJUMP` above 80 px.

### T2. Real world: the game's platforms  ✅ done
- Make `WorldQuery` read the game's actual level instead of a box: `is_solid(p)` via physics point/ray queries
  against the `StaticBody2D`/`CollisionPolygon2D` platforms (`world/platform.gd`), keeping the same public API
  (`is_solid(p)`, `resolve(body)`). **No TileMapLayer** — this project hand-draws its level silhouettes.
- Add two `AStarGrid2D` grids **rasterised from those silhouettes** (not from a tileset): **air grid** (non-solid
  cells) and **surface grid** (non-solid cells adjacent to a solid cell). Expose `world.path_air(from, to)` and
  `world.path_surface(from, to)`. Cell size and bake are `@export`/tuning values.
- **Accept:** `is_solid` matches what is drawn; body points never end up inside a platform; paths exist where
  expected (around a tower, under a ceiling, along an overhang).
- **Done:** `WorldQuery.attach(node)` binds to the level's physics space and `is_solid` is an
  `intersect_point` query filtered to `StaticBody2D` on `solid_mask` (**layers 1 and 4**). Layer 1 is the playable
  ground; layer 4 is the big hand-drawn rock silhouette, which the player currently ignores but creatures must not
  fly through. The type filter also matters: the player is a `CharacterBody2D` on layer 1, so a layer test alone
  would make actors solid. `bounds` remains a safety box (outside = solid), which also keeps the no-level dev
  scene working.
  `resolve` now sub-samples the tick (max 12 steps, `point_radius/2` apart, so no tunnelling through a drawn
  platform), bisects back to the boundary if a point starts inside, estimates an outward normal from 8 probes, and
  projects velocity onto the tangent — so bodies slide instead of sticking. `bake(rect)` rasterises the air grid
  and the surface grid (free cells with a solid 8-neighbour) from the same queries. The air grid is **inflated by
  `path_clearance` (34 px)** so a path never hugs a wall face that a creature's body cannot fit against; the
  surface grid deliberately is not, because gripping means hugging terrain.
  Verified by `dev/world_test.tscn` (headless, exits non-zero on failure):
  `oracle samples=2467 mismatches=0` across both drawn polygons, `dive 7s violations=0`, air paths over a tower
  and through a wall hatch, surface path along a floor, all with 0 solid waypoints.

  ```
  godot --headless --path . res://creature_framework/dev/world_test.tscn
  ```

### T3. Path following and obstacle avoidance  ✅ done
- Add a `PathFollower` helper: advance waypoints at ~24 px, repath every ~0.3 s or when the goal moves > 1 tile.
- Put the current waypoint into the flow: Locomotors steer toward the *waypoint*, not the raw goal.
- Add wall avoidance to `FlyLocomotor` (2-3 tile lookups ahead along velocity, +-30 degrees; push away weighted by closeness).
- **Accept:** click goals behind walls; the creature routes around them smoothly without jitter or wall-hugging.
- **Done:** `core/path_follower.gd` keeps a path, advances it, and repaths every 0.3 s or when the goal drifts more
  than 24 px. `Creature.steer_target()` returns the current waypoint; `FlyLocomotor` steers at that instead of
  `intent.goal`, so the brain still owns the goal and the follower only answers "where next". Locomotors also ask
  `Creature.steer_is_goal()`: they keep full speed around corners and only brake (80 px slow radius) for the final
  arrival — braking at every 24 px waypoint bled the forward speed that glide lift depends on, and the flyer sank
  onto the floor. The follower advances from the **head**, not the centre, because the head is what steers;
  advancing from the centre parks the nose on a waypoint with the body a spine-length behind. Waypoints are also
  skipped once their plane is crossed, so a fast flyer cannot orbit an overshot corner. `FlyLocomotor` adds three
  3-cell feelers along velocity at 0, +30 and -30 degrees; if any is blocked it pushes perpendicular toward the
  freer side. **Also fixed in T3:** the hover baseline was `0.38`, which gives ~400 px/s² of lift against 900
  gravity — the flyer could not station-keep and dragged its tail on the floor. `hover_thrust` is now `0.85`
  (mean flap lift ≈ gravity), so a hovering creature actually holds altitude; the stronger flap raised the
  measured flap-driven wing-tip peak from ~74 to 85.5 px, with the shoulder anchor stable (7 px from the centre),
  i.e. still flap speed, not a facing pop.
  Verified by `dev/path_test.tscn` (headless, exits non-zero on failure): a synthetic level with a floor, a
  ceiling and two walls that force an up-then-down slalom. The creature climbs **over wall A (min y 166.5 < 220)**
  and dives **under wall B (max y 448.1 > 380)**, reaches the goal in **13.9 s**, closest approach **0.2 px**,
  with **0 body points inside terrain** and **150 repaths** over 45 s.

  ```
  godot --headless --path . res://creature_framework/dev/path_test.tscn
  ```

  **Still open:** nothing in the game bakes the grid yet, so in-game steering still falls back to the raw goal.
  The T11 actor shell should build **one** baked `WorldQuery` per level (the drawn platforms are static) and share
  it across creatures. `path_clearance` is bake-time, so a much larger creature needs its own bake or a larger
  clearance.

### T4. LimbSystem: grips  ✅ done
- Create `core/limb_system.gd`: per limb `gripping`, `grip_pos`, `max_reach`. Implement random-sample grip scoring
  (see DESIGN_NOTES "Grip scoring"). Draw grips in the debug view.
- **Accept:** a limb latches onto nearby wall tiles, releases when over-extended, and never latches onto thin air.
- **Done:** `core/limb_system.gd` keeps per-limb `gripping` / `grip_pos` / `grip_normal`, with
  `max_reach = limb.reach * 1.25`. Each free limb gets one attempt every 0.06 s (staggered so four limbs never fan
  their rays on the same tick): **7 rays fanned ±26°** around the direction to the ideal tip, from
  `anchor + 14 px` out to `max_reach`, filtered to terrain by `WorldQuery.is_terrain` — the same rule as
  `is_solid`. The best ray wins on `|t| + 0.6 * |hit_dist - ideal_dist| / ideal_dist`: closest to the ideal line,
  then closest to the ideal length. A ray is used instead of random samples around the tip because the locomotor's
  ideal tip is frequently *inside* the wall the limb is reaching into; the ray stops at the face where a real limb
  would touch it. `WorldQuery.surface_near(ideal, 10)` is the fallback for a surface beside the tip (a ledge the
  limb reaches past). A grip is never re-scored while held — it is a fixed world point, so a limb cannot crawl along
  a wall by itself — and releases only when `anchor.distance_to(grip_pos) > max_reach`. The grip is **cosmetic in
  T4**: `Creature` pins `limb_tip[i]` to `grip_pos[i]`; T5 turns it into a body constraint. The debug view draws the
  contact dot and its outward normal.
  Verified by `dev/grip_test.tscn` (headless, exits non-zero on failure): a wall at x 340 and a block at x 600.
  `surface_near` hits the wall face at **(340, 300), normal (-1, 0), distance 8** and finds nothing in thin air.
  The near wing latches at **(340, 293), normal (-1, 0)**, 88 px from the anchor (max reach 118.8). Upward thin air
  does not latch; a block 378 px away does not latch; the near leg (max reach 68.8) cannot reach the wall 129 px
  away. A **+18 px** body move keeps the grip fixed at the same world point; **+200 px** releases it; on the next
  tick the tip is still pinned to the grip.

  ```
  godot --headless --path . res://creature_framework/dev/grip_test.tscn
  ```

### T5. ClimbLocomotor  ✅ done
- `locomotors/climb_locomotor.gd`: body pulled toward the grip centroid, limb gait rule (>= 2 other limbs holding
  before one may release the one furthest behind), weight illusion from grip count (see DESIGN_NOTES "Climbing").
- **Accept:** the creature crawls up a vertical wall hand-over-hand with sway; with 0 grips it sags and slows.
- **Done:** the grips are fixed world points; the body is dragged between them. The wall frame is the average
  outward normal of the held grips (a `surface_near` probe only runs before the first grip), and travel is the goal
  direction projected onto the wall. Each tick may release **one** limb: the one furthest behind the body along the
  travel tangent, and only while two others still hold (`release_furthest_behind`). Free limbs reach ahead by
  `min(reach * 0.75, 52)` and re-grip through the T4 ray fan. Every spine point is spring-pulled (`k = 14`) to a
  wall-parallel line built from the grip centroid, with the belly 30 px off the face plus 8 px per free limb; that
  free-limb sag is the visible in/out sway. Climb push is `240 * grip_factor` along the tangent, capped at 130 px/s.
  Gravity and no-purchase damping are weighted by `1 - grip_factor`, so losing grips fakes weight: at zero grips the
  creature sags and coasts to a stop instead of chasing the goal. **T5 keeps climb isolated**: `ClimbLocomotor` is
  not in `VultureRig` yet and its `score()` only returns 1 while a grip is held; T6 adds the landing window and
  adjacency score.
  Verified by `dev/climb_test.tscn` (headless and through the live MCP editor, exits non-zero on failure): all four
  limbs hold at **0.05 s**, it climbs **238.1 px** (min y 191.9), comes within **15.5 px** of the goal and reaches
  it in **6.33 s**, with **37** grip changes, every limb released and re-gripped (`1111`), **3.32 px** of sway and
  **0** body points inside terrain. The 0-grip creature sags **254.9 px** in 1 s, decays `vx 180 -> 21.2`, and never
  grips. `dev/climb_demo.tscn` shows the same motion live with a goal sliding between y 180 and 380 (MCP run:
  climbed to ~204, descended to ~379, 4/4 grips with a dip to 3 on a release, no errors).

  ```
  godot --headless --path . res://creature_framework/dev/climb_test.tscn
  ```

### Two-limb crawlers and wall corners (post-T8 fixes)

The copied vulture is a **Climb-only, two-limb** rig, and it exposed three assumptions that only held for
four-limb flyers:

- **Gait floor.** The release rule required two OTHER grips before letting go, which a two-limb rig can never
  satisfy. It is now `min(climb_min_other, limb_count - 1)`, and the "behind" threshold is derived from the same
  spring that sets how far the body leads the grip centroid (`0.5 * climb_accel / climb_hang_k`, 3..20 px)
  instead of a fixed 20 px that sat above that lead. Two-legged rigs hand over hand; four-legged rigs are
  unchanged.
- **Corner hand-off.** At a wall base both feet can end up ahead of the body (it is wedged into the corner), so
  "release the furthest behind" has nothing to release and the rig stalls. A head probe now compares the face it
  can see with the face being held; when they differ and the body is not advancing (`climb_corner_dot`,
  `climb_stuck_speed`, `climb_stuck_retry`), the rearmost grip is released so the free limb reaches onto the new
  face.
- **180° reversal.** When the goal moves from above the body to below it, the desired pose is collinear with the
  current one and the springs pull head and tail through each other. A damped `_heading` now turns the desired
  body line through the open side of the wall at `climb_turn_rate` (5 rad/s) instead of reversing instantly.
- **Surface-owned belly.** While climbing, `Creature.body_frame()` takes the belly from the held surface normal
  (`-grip_normal_avg()`), not from the mirrored `facing` value. A vertical spine cannot say which side is the
  belly; using `facing` put the legs on the far side of a descending climber (the "upside down" read). Air
  behaviour is untouched, and the frame is flattened onto the surface so it stays orthonormal.
- **Trailing chains are not spine.** Points generated by a tail/tentacle bake `PointDef.driven = false`. A
  locomotor positions driven points and steers them; a trailing chain gets gravity and damping instead, so it
  hangs from its links and cannot lever the body off the wall. `FlyLocomotor` applies its lift/gravity to every
  body point (the head still owns steering), so an authored tail flies in the body frame.

`mode_test` keeps a two-limb regression (`up=164 px down=85 px`, belly `-n` dot min 1.00, both feet down), and
the live playground run of the copied vulture crawls ~750 px, climbs to `(609,300)`, turns around and descends to
`(609,470)` with the belly still on the wall.

### T6. Mode switching and transitions  ✅ done
- `FlyLocomotor.score` / `ClimbLocomotor.score` use `WorldQuery` (surface adjacent? goal climb-reachable? grips lost?).
- Add launch impulse (climb -> fly) and landing window with more grip samples (fly -> climb). See DESIGN_NOTES.
- **Accept:** three goals behave sensibly: climb-only spot, flight-only spot, ambiguous spot. No flicker between modes.
- **Done:** `ClimbLocomotor` scores **2.0** while gripping when the goal is climbable and **0.25** when the goal has
  left the surface (so flight's 1.0 wins). With no grips it scores **1.8** when a face is within
  `climb_land_radius` (46 px) **and** the goal touches terrain within `climb_goal_radius` (52 px) **and** the
  surface grid connects the body to the goal; otherwise 0. `LocoManager` keeps 0.25 stickiness, a 0.5 s switch
  lock and a 0.35 s crossfade, so the transition is a short blend rather than a pop.
  Grid reachability is cached for 12 physics frames and invalidated when the goal moves > 24 px, because A* must
  not run every tick. Scoring probes the **head first** and the centre second: flight steers by the head, so a
  flyer hovering at a wall goal has its head on the face and its centre a body-length back.
  Entering climb bleeds speed above 60 px/s to 40 % (so the body does not spear into the face) and opens a
  0.4 s landing window: every free limb attempts every tick with **16 rays over ±34°** instead of the usual 7
  rays / 0.06 s. Entering fly from a grip adds a **120 px/s** impulse along the average grip normal, releases all
  grips with a 0.3 s re-grip lockout, and sets `thrust = 1`.
  Verified by `dev/mode_test.tscn` (headless, exits non-zero on failure): the
  climb-only goal gives **exactly 1** switch (fly -> climb), reaches in **4.08 s** while climbing, closest
  **29.4 px**, **4** grips; moving that goal into open air gives **exactly 1** switch back (climb -> fly), reaches
  in **9.38 s**, launch `vx -96.8` with **0** grips. The flight-only goal gives **0** switches and reaches in
  **8.00 s**. The ambiguous goal (wall and air routes both exist) chooses climb, **1** switch, reaches in
  **3.35 s** with **4** grips. All three have **0** body points inside terrain.
  The harness bakes `path_clearance = 58` because the vulture's spine is 80 px; the default 34 px is tuned for a
  point and let the body wedge on tall wall corners. Per-creature clearance belongs to the shared level bake in
  T11.
  `dev/mode_demo.tscn` shows the whole cycle live (MCP run at 1152x648): fly -> climb at **2.4 s** with 1 grip,
  4/4 grips while climbing, climb -> fly at **4.3 s** (`vx -101.1`, 0 grips), fly -> climb again on the return,
  no game-log errors.

  ```
  godot --headless --path . res://creature_framework/dev/mode_test.tscn
  ```

### T7. Depth layer: make 2D feel 3D ✅ done
- `core/depth.gd`: `DepthLayer` holds `yaw`, with a continuous target from the logic-facing value
  (`+1 -> 0`, `0 -> PI/2`, `-1 -> PI`), damped through `Steering.damp_f`. `squash = max(|cos(yaw)|, 0.15)`.
  `depth_of(side) = side * cos(yaw)`, so a near limb is `+1` at one profile, `0` at edge-on and `-1` at the
  other; `scale_for()` is `1 + depth * 0.08`, `tint()` darkens the far side, and `z_for()` gives a future
  per-part CanvasItem z index.
- The debug view sorts limbs by depth: far limbs before the body hull, near limbs after it. It squashes every
  creature point around the body centre by `squash`, so the turn passes through a visibly narrow front/back
  view. `RigPoint.base_depth` is now read for spine-point depth/tint (and validated to -1..+1).
- Feet/limb tips get a hidden "height" during steps: a free leg while climbing/crawling raises its foot along
  the grip normal (`step_height`, default 9 px), fattens slightly and shrinks a shadow; a held leg drops back.
  Wings never step.
- **Accept:** `dev/depth_test.tscn` passes 25 checks: profile depths are +1/-1; a 240-frame reversal sweeps
  yaw 0 → 3.14, dips to squash **0.15**, and swaps near/far draw order **exactly once** at **|depth| 0.13**;
  a live creature's depth layer follows its facing to the opposite profile. `dev/depth_demo.tscn` shows the
  turn live (console logs the swap at `squash=0.15`, e.g. `near=-0.13 far=+0.13`).

  ```
  godot --headless --path . res://creature_framework/dev/depth_test.tscn
  ```

### T8. Smoothness pass: secondary motion, eased arcs, stretch ✅ done
- `core/secondary.gd`: `CosmeticChain`, a five-point Verlet follow chain for tails/feathers/dangly bits. The root
  is pinned to the interpolated rear point; every segment is pulled toward a rest pose one segment behind its
  parent, then a two-pass root→tip distance solve keeps every segment at exactly `seg_len`. Spring and drag are in
  seconds (`exp(-drag * dt)`, `min(dt, 0.0333)`), so a 30 Hz and a 144 Hz display settle identically. The rest
  direction blends spine-back, a pull behind travel and a droop.
- `core/depth.gd`: `stretch` (0..1) is damped from normalized speed (weight **0.75**) and missing-grip hang
  (weight **0.90**). It deforms the body about its centre on the spine axis by `1 + stretch * 0.09` and across it
  by `1 - stretch * 0.05`, composed after the depth squash. `stretch_point()`/`stretch_vector()` are the position
  and direction forms.
- `core/creature.gd`: a stepping leg's **drawn** tip follows a smoothstep arc (`t²(3−2t)`, bowed away from the
  shoulder, 0.08–0.26 s); a grip uses a ≤0.10 s arc so the limb meets the dot, and wings stay direct. The logic
  `limb_tip`, grips and `Body` are untouched. `_process` advances stretch, eased tips and the tail at render rate;
  `_draw` uses the eased tips and the stretched view.
- For any **node-based** cosmetics (Sprite2D/Line2D/Polygon2D following logic), enable 2D physics interpolation
  (Project Settings > Physics > Common > Physics Interpolation, Godot 4.3+). The debug view already interpolates
  manually through `Body.render_pos()`.
- **Accept:** `dev/smooth_test.tscn` passes 53 checks: the chain lags **12.65 px** behind a moving anchor, keeps
  **9.00 px** segments, survives a teleport and settles to **0.000 px**; a 140 px leg swing bows **16.0 px** off
  the chord, sits at **72.7 px** at half time and lands exactly on target, with a **0.080 s** grip arc; full speed
  gives **0.75** stretch (`1.067 / 0.963`), no grips sag to **0.90**, and the first frame moves only **0.071**.
  A live run stays finite with **30-32 px** tail sway and **0.18** max stretch. `dev/smooth_demo.tscn` shows the
  tail, eased legs and spine stretch live (`T` turn, `S` slow motion).

  ```
  godot --headless --path . res://creature_framework/dev/smooth_test.tscn
  ```

- **Authored tails skip the cosmetic one.** If a rig has a tail BodyPart (below), its chain is real body points,
  so `Creature.setup()` leaves the `CosmeticChain` empty (`rig.authored_tail`). A rig without a BodyPart keeps
  the five-segment follower tail. T9 owns the drawn tail gesture for both; logic never reads either.

### T9. Cosmetics layer + off-screen switch
- `Cosmetics` node (child of Creature) that only reads `Creature` and `Body`: wing sprites/polygons driven by
  `flap_phase`, leg curves (two-bone IK + Catmull-Rom/Curve2D) through grip points, body bank from `turn_rate`.
- `VisibleOnScreenNotifier2D` disables cosmetics processing + visibility off-screen; the logic keeps running.
- **Accept:** toggling cosmetics off changes nothing about where the creature goes.

### T10. Prove the framework: second creature
- Add `rigs/gecko_rig.gd` + `locomotors/crawl_locomotor.gd` (ground/wall crawl, long chain body, 4 legs) reusing
  `ClimbLocomotor`/`LimbSystem` where possible.
- **Accept:** the gecko works **without editing anything in `core/`**. If something in `core/` had to change,
  record why in `docs/DESIGN_NOTES.md` under "Framework changes".
- Later creatures to validate against: heavy 4-legged kaiju (slow, wall/ceiling climb), anchored tentacle monster
  (reach limbs, no locomotion of the core).

---

## Editor authoring (pre-T7) ✅ done

Rigs are **scenes**, not GDScript builders. `creatures/vulture.tscn` is the source of truth for the
vulture: points, masses, links, limbs, styles, locomotor choices and tuning are all editable in the
inspector, and the rest of the framework consumes the same `CreatureRig` Resource it always did.

```
Vulture                 (RigBlueprint)   front/centre/rear point names, locomotor flags, tuning
├─ front                (RigPoint)       position = rest offset, mass, base_depth
├─ center               (RigPoint)
│  ├─ wing_far          (RigLimb)        kind/style/lane/reach, position = offset from the anchor
│  └─ wing_near         (RigLimb)
├─ rear                 (RigPoint)
│  ├─ leg_far           (RigLimb)
│  ├─ leg_near          (RigLimb)
│  └─ tail              (RigBodyPart)    kind = tail/tentacle, length = extra points
└─ weak_bend            (RigLink)        extra constraint between two named points
```

### How a scene becomes a rig

- **Points are baked in scene order**; that order is the point index. `front_point` / `center_point` /
  `rear_point` refer to nodes by name, so reordering points does not break the rig.
- **A limb is a direct child of its anchor point.** Its `position` is `local_offset` in the spine frame
  (+x forward, +y belly), and its parent *is* `anchor_point`; there is no second place to say "which
  point". `RigPoint` and `RigLimb` have transform notifications, so the preview follows a drag/rotate live.
- **Consecutive points are linked automatically** at stiffness 1.0 with rest length = the rest-pose
  distance. `RigLink` adds any *other* member (the vulture's weak front→rear bend-resist at 0.15).
  `rest_length <= 0` means "use the current pose distance".
- **Only positions are baked.** Point/limb rotation and scale are *rejected*, not silently ignored: the
  runtime solver owns the transform, and a rest offset is a position, not a pose.
- **Limbs bake in point order, then child order** (wing_far, wing_near, leg_far, leg_near for the
  vulture), so indices in `LimbSystem` are stable and reproducible.
- `tuning` is deep-copied per bake (`StringName -> number` overrides of locomotor defaults).

### Tails and tentacles

A tail or tentacle is **one `RigBodyPart` node under its anchor point**, not a row of hand-placed points.
`length` is the number of **extra points**, so `length = 5` on a rear point bakes anchor -> p1..p5. The baker:

- appends the generated points **after every authored point**, so hand-authored indices never move;
- names them `<part>_1 .. <part>_<length>` and gives them `mass` interpolated `base_mass -> tip_mass`,
  the anchor's `base_depth`, and `driven = false` (a trailing chain is not steered as spine);
- joins the chain from the anchor with stiffness-1 links whose rest length is the posed spacing, and records
  the index run (anchor first) in `BodyPartDef.points` / `CreatureRig.body_parts`;
- sets `CreatureRig.authored_tail` when `kind = tail`, so `Creature` skips its cosmetic follower tail.

Aim it by dragging the node: its **position is a direction handle**, not an offset. The chain always starts one
`spacing` from the anchor and extends along the handle (`auto_direction = true`), or along the numeric
`direction` vector (`-x` is backwards) when the handle is off. `spacing` is the rest distance between points.
Keep a chain light (default `base_mass 0.5`, `tip_mass 0.15`): it hangs from the body, so a tail as heavy as the
spine drags the gait and stretches its links against the floor. `kind` is `tail` or `tentacle`; both bake the
same body chain, and `tentacle` does not claim the rear-tail slot.

### Validation and failure

`RigBlueprint.validate()` returns human-readable problems; `build_rig()` returns `null` (without
logging) while any exist, so a broken scene never half-builds. The **Validate rig** button in the
inspector prints the result to the Output panel. It checks:

- at least 3 points, unique non-empty names, `mass > 0`, finite positions, no point rotation/scale;
- `front`/`centre`/`rear` all exist and are three different points;
- limbs are direct children of a `RigPoint`, have a name/kind, a style in `LimbStyleCatalog`, `lane`
  of -1 or +1, `reach > 0`, a finite position, no rotation/scale;
- body parts are direct children of an authored `RigPoint`, have a unique name, a known `kind`
  (`tail`/`tentacle`), `length >= 1`, `spacing > 0`, positive masses, a finite position and a direction
  (handle or fallback), no rotation/scale, and their generated `<part>_N` names do not collide with an
  authored point or another part's chain;
- link endpoints exist, are distinct, and `stiffness` is 0..1 with a finite positive `rest_length`;
- at least one locomotor is selected, with no unknown flag bits;
- every `tuning` value is a finite number.

`RigBlueprint.load_rig(path, fresh := false)` is the no-code loader: it loads the packed scene,
instantiates it, validates, logs each broken rule with the scene's name, and returns the baked rig (or
`null`). `VultureRig.build()` is now a one-line wrapper around it, so every harness still works and no
test or creature code needs to know that rigs come from scenes. `fresh` skips the resource cache, which
is what lets the playground rebuild a scene you just saved without restarting the game.

### Inspectors and registries

- **`RigPoint`**: `mass` (1.0 default), `base_depth` (-1 far .. +1 near; read by the T7 depth layer's tint/scale).
- **`RigLimb`**: `kind` (`wing`/`leg`/`tentacle`/`claw`/`fin`), `style` (`default`/`flap`/`walk2`/
  `reach`/`dangle`/`tentacle`), `lane` (`Far:-1`/`Near:1`), `reach`, `show_reach`.
- **`RigBodyPart`**: `kind` (`tail`/`tentacle`), `length` (extra points), `spacing`, `auto_direction`,
  `direction`, `base_mass`, `tip_mass`, `show_chain`.
- **`RigBlueprint`**: the three point names, `locomotor_flags` (`Fly`, `Climb`), `tuning`, **Validate rig**.
- `LimbStyleCatalog` owns the style ids, plus a `kind` hint and a suggested bone count per style
  (wing 1, leg 2, dangle 3, tentacle 6). T9 binds the actual behaviour, but the ids already ride
  through the bake, so a style chosen in the inspector can never be dropped.
- `LocomotorCatalog` maps authored bits to classes: `Fly = 1`, `Climb = 2`, emitted **fly first, then
  climb** because that order decides the manager's initial mode. Adding a locomotor = add the bit
  constant, the branch, and the flag name on `RigBlueprint`.

### Working in the scene

The `@tool` nodes draw their own preview: spine links solid, extra links dashed, an origin cross, points
as rings with their name above (mass/depth below, and only when non-default), limbs as a solid stub plus
a dashed reach guide with the limb's name/style/reach beside its tip. Far limbs print to the left of
their tip and near limbs to the right, so a far/near pair never stacks. Limb `kind` sets the colour.
A body part draws its whole generated chain as a line of dots from the anchor (a small cross) through
each point, shrinking toward the tip, with `<name> <kind> <n> pts <spacing>` beside the tip; the chain
label is right-aligned so a backwards tail never overlaps its own points. The scene is small — the
vulture spine is 80 px — so author at 2-4x zoom. Nothing here is baked; it is editor-only drawing, and it
disappears in the game.

A new creature is a copy of `creatures/vulture.tscn`: rename the root, move/add points, add limbs under
their anchor points, pick locomotor flags, and you are done — **no code**. Open
`dev/playground.tscn`, set its `rig_scene` to your scene in the inspector, press F6, and the creature
flies at the mouse. **R** rebuilds the rig in place after you save it. The playground also exports
`spawn`, `path_clearance` (58 px suits an 80 px spine) and `show_path`. No `core/` change.

`RigBlueprint.load_rig()` is the only API involved: any scene that needs a specific creature (a demo, a
test, a level spawner) calls it with a path. `rigs/` is now just stable names for the creatures that
already have harnesses (`VultureRig.build()`).

```
godot --headless --path . res://creature_framework/dev/authoring_test.tscn
```

`dev/authoring_test.tscn` is the acceptance gate: **88 checks** across scene, loader, mutation, validation,
body-part and runtime groups — the scene bakes to the
exact reference vulture (3 points, 2 spine links + 1 brace, 4 limbs, anchors, styles, front/centre/rear,
locomotor order), `load_rig()` returns that same rig, edits to nodes reach the bake (the scene really is
the source of truth), invalid rigs are rejected (missing point, bad style, lane 0, orphan limb, self
link, no locomotor, and the body-part rules above), and a creature built through the loader moves 172 px
in 2.5 s with 0 NaN points. The body-part group proves one `RigBodyPart` node bakes a whole chain: four
extra points and links after the authored ones, base->tip mass falloff, a recorded `BodyPartDef` index run,
`authored_tail` set for a tail and not for a tentacle, generated names colliding with authored points
rejected, and — at runtime — the rig runs 180 ticks with a finite tail, no cosmetic follower chain, and a
tip that can be pushed sideways (**~16-18 px** bend) while links hold rest length.
`grip_test`, `climb_test`, `path_test`, `world_test` and `mode_test` all still pass unchanged against the
scene-loaded rig.


---

## Conventions for AI agents working on this repo

- Read this README and `docs/DESIGN_NOTES.md` before changing anything.
- Work on exactly one roadmap task at a time. Finish its acceptance test, then update the **Status** line above and
  tick the task here (`[x]`), then stop and report.
- Keep changes small and runnable. After every change the project must still open and run `main.tscn`.
- Do not rename public APIs in `core/` without updating every caller and this file.
- When unsure about a behaviour, add an `@export`/`rig.tuning` value and expose it, instead of hard-coding.
- Prefer new files over growing existing ones; one `class_name` per file.

### Task checklist
- [x] T0 run and fix
- [x] T1 smooth facing
- [x] T2 real world (platform grids)
- [x] T3 path following and avoidance
- [x] T4 limb grips
- [x] T5 climb locomotor
- [x] T6 mode switching
- [x] Editor authoring (scene rigs, registries, validation)
- [x] T7 depth layer
- [x] T8 smoothness pass
- [ ] T9 cosmetics and off-screen switch
- [ ] T10 second creature
