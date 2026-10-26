# Creature Framework (Godot 4, GDScript)

A reusable framework for building **many different creatures with many different kinds of movement** in a
**2D side-scroller**, where the motion still feels **smooth and 3D-like**.

Inspired by the Rain World animation approach (GDC talk "The Rain World Animation Process"): a cheap, stable
**logic layer** (points + distance constraints) decorated by a heavy **cosmetic layer** that only ever *reads* the logic.

> **Status:** T0-T4 done. The framework lives inside the *Another World* project (`res://creature_framework/`),
> runs on Godot 4.7.1, and is verified by a self-terminating 60 s scripted run (0 errors, 0 NaN, bounded speeds,
> no single-frame pose pops), a world harness that checks the real level's drawn polygons and path grids, a
> flight harness that flies a slalom to a goal, and a grip harness that latches limbs onto a wall. Steps 1-4
> (Body, Intent/Brain, LocoManager, FlyLocomotor, debug view, world query, path following, limb grips) are
> implemented; T5 (climb locomotor) is next.

Requires **Godot 4.7+** (developed against 4.7.1).

**How to run it in this project:** open `creature_framework/dev/creature_test.tscn` and press F6.
It runs the scripted `DemoBrain` (climb / hover / sink / bank, 6 s each) with metrics printed to the
console. Set the environment variable `CF_MOUSE=1` to chase the cursor with `MouseBrain` instead.
The game's own main scene is untouched.

---

## Rules you must not break

1. **One-way dependency.** Cosmetics read from logic. Logic never reads cosmetics. Ever.
2. **Locomotors never move things directly.** They only call `out.add_accel(point, accel)` and
   `out.set_limb_target(limb, world_pos)` on the `MoveOutput`. The `LocoManager` blends them by weight.
3. **Brains only write an `Intent`.** They never touch the body or call locomotor code.
4. **Creatures are data.** A new creature is a new `CreatureRig` builder in `rigs/` plus a list of locomotor
   classes. Adding a creature must not require editing `core/`. If it does, fix the abstraction, not the creature.
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
  creature_rig.gd    /
  body.gd            Verlet points + distance constraints (the logic layer)
  world_query.gd     the creature's only view of the level (physics solids + air/surface path grids)
  path_follower.gd   goal -> next waypoint, with repathing and hole-free fallback
  limb_system.gd     per-limb grip state: ray-fan grip search, fixed hold, over-reach release
  locomotor.gd       base class: score(), enter(), exit(), emit()
  loco_manager.gd    scoring + hysteresis + weighted crossfade
  move_output.gd     accumulates accelerations and limb targets, scaled by blend weight
  steering.gd        arrive(), damp_f(), damp_v()
  creature.gd        glue node + proxy variables + debug draw
brains/mouse_brain.gd                 debug brain (goal = mouse)
brains/demo_brain.gd                  scripted brain for reproducible T0 runs
dev/creature_test.tscn                one creature + HUD; 60 s self-terminating metrics run
dev/world_test.tscn                   T2 harness: real-level oracle, dive test, path grids (exits non-zero)
dev/path_test.tscn                    T3 harness: up-and-down slalom flight to a goal (exits non-zero)
dev/grip_test.tscn                    T4 harness: wall latch, thin air, reach limit, hold/release (exits non-zero)
locomotors/fly_locomotor.gd           flight: flap lift + glide lift + path steering + wall feelers
rigs/vulture_rig.gd                   3-point spine, 2 wings, 2 legs
docs/DESIGN_NOTES.md                  algorithms and reference code for the remaining tasks
```

Per-tick order (in `Creature._physics_process`):
`brain.think -> path.update -> limbs.update (drop over-extended grips) -> loco.update (emit forces; free limbs
try to grip) -> body.step -> world.resolve`. Cosmetics run in `_process`.

### Debug view (dev aid; deleted when T7/T9 art lands)
Circles and lines only, but it has to carry the read until then:

- **Body**: a tapered hull through the three spine points plus a head disc, so limbs have something to attach to.
- **Wing**: leading edge (shoulder → tip), a trailing edge swept back in the body frame, and 3 feather ribs.
  A single `presentation` scalar widens the chord *and* shortens the span, so the wing is broad when it faces the
  camera (downstroke, or turning through edge-on) and long/thin side-on — the Rain World depth swap.
- **Leg**: two bones (`0.52 * reach` each) with the knee placed by the law of cosines, bending backwards. The far leg
  is shorter (foreshortened), thinner and darker, and the two legs stride in antiphase, so it reads as two legs at
  different depths rather than one line copied.
- **Grip**: a translucent green dot on the contact point, a bright core, and a short tick along the surface normal.
  The limb tip is pinned to that dot, so "holding" reads even while the limb itself is still a line.
- In `dev/creature_test.tscn`, **Z** toggles a 3.2× camera that follows the creature.

---

## Roadmap (do in order, one task at a time)

Each task has an **acceptance test**. Do not start the next task until the current one passes.
Keep the debug view (circles and lines) working at all times. **No art until T7.**
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

### T5. ClimbLocomotor
- `locomotors/climb_locomotor.gd`: body pulled toward the grip centroid, limb gait rule (>= 2 other limbs holding
  before one may release the one furthest behind), weight illusion from grip count (see DESIGN_NOTES "Climbing").
- **Accept:** the creature crawls up a vertical wall hand-over-hand with sway; with 0 grips it sags and slows.

### T6. Mode switching and transitions
- `FlyLocomotor.score` / `ClimbLocomotor.score` use `WorldQuery` (surface adjacent? goal climb-reachable? grips lost?).
- Add launch impulse (climb -> fly) and landing window with more grip samples (fly -> climb). See DESIGN_NOTES.
- **Accept:** three goals behave sensibly: climb-only spot, flight-only spot, ambiguous spot. No flicker between modes.

### T7. Depth layer: make 2D feel 3D
- `core/depth.gd`: `yaw` as an angle (damped toward facing), `squash = cos(yaw)` clamped away from 0,
  per-part `depth = lane * cos(yaw)`, used for `z_index`, scale (`1 + depth * 0.08`) and a darker tint on the far side.
- Feet/limb tips get a hidden "height" during steps (raise + scale + shrink shadow).
- **Accept:** turning around passes through a front/back view and near/far limbs swap draw order smoothly.

### T8. Smoothness pass
- Everything driven through `damp_*`. Secondary motion: Verlet chains for tails/feathers/dangly bits (cosmetic only).
  Eased limb arcs (ease in/out, never linear). Squash/stretch tied to grip count and speed.
- For any **node-based** cosmetics (Sprite2D/Line2D/Polygon2D following logic), enable 2D physics interpolation
  (Project Settings > Physics > Common > Physics Interpolation, Godot 4.3+). The debug view already interpolates
  manually through `Body.render_pos()`.
- **Accept:** no visible stepping at 60/120/144 Hz refresh; no sudden pose changes anywhere.

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

## Planned: editor authoring (after T6, before art)

The point of the framework is that every creature is data, not code. The end state:

```
creature.tscn
└─ Creature
   ├─ Points          places with the mouse, names them
   │  ├─ head      (mass 1.0, is_head)
   │  ├─ chest     (mass 1.5)          <- "which part is heavier"
   │  └─ tail      (mass 0.7)
   ├─ Limbs           "add leg to chest"
   │  ├─ wing_l  (kind=wing, style=flap,   lane=-1, reach=95)
   │  ├─ wing_r  (kind=wing, style=flap,   lane=+1)
   │  ├─ leg_l   (kind=leg,  style=walk2,  lane=-1)
   │  └─ tent_1  (kind=limb, style=tentacle, segments=6)
   ├─ Brain           per-creature movement pattern / behaviour
   └─ Skin            one sprite child per point and limb
```

- Rigs stop being `VultureRig.build()` in GDScript and become a scene: `@tool` point/limb nodes you place, with
  `CreatureRig` baked from them at runtime (`offset` = rest pose; the solver still owns the motion).
- Limb `style` becomes a registry (`flap`, `walk2`, `reach`, `dangle`, `tentacle`), one small behaviour class each,
  so "tentacle type of legs" is a choice in the inspector, not a new creature script.
- Sprites are cosmetic children only. **Until a part has a sprite, the debug view draws its dot/line/square** — a
  creature with no art is fully playable, and swapping in art cannot change how it moves.

Do this after locomotion (T2-T6) is proven, so the authoring layer is built on a model that already works.

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
- [ ] T5 climb locomotor
- [ ] T6 mode switching
- [ ] T7 depth layer
- [ ] T8 smoothness pass
- [ ] T9 cosmetics and off-screen switch
- [ ] T10 second creature
