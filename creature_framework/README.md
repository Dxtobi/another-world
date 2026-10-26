# Creature Framework (Godot 4, GDScript)

A reusable framework for building **many different creatures with many different kinds of movement** in a
**2D side-scroller**, where the motion still feels **smooth and 3D-like**.

Inspired by the Rain World animation approach (GDC talk "The Rain World Animation Process"): a cheap, stable
**logic layer** (points + distance constraints) decorated by a heavy **cosmetic layer** that only ever *reads* the logic.

> **Status:** T0 done. The framework lives inside the *Another World* project (`res://creature_framework/`),
> runs on Godot 4.7.1, and is verified by a 60 s scripted run (0 errors, 0 NaN, bounded speeds).
> Steps 1-3 (Body, Intent/Brain, LocoManager, FlyLocomotor, debug view) are implemented; T1 is next.

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
  world_query.gd     the creature's only view of the level (currently just a box)
  locomotor.gd       base class: score(), enter(), exit(), emit()
  loco_manager.gd    scoring + hysteresis + weighted crossfade
  move_output.gd     accumulates accelerations and limb targets, scaled by blend weight
  steering.gd        arrive(), damp_f(), damp_v()
  creature.gd        glue node + proxy variables + debug draw
brains/mouse_brain.gd                 debug brain (goal = mouse)
brains/demo_brain.gd                  scripted brain for reproducible T0 runs
locomotors/fly_locomotor.gd           flight: flap lift + glide lift + steering
rigs/vulture_rig.gd                   3-point spine, 2 wings, 2 legs
docs/DESIGN_NOTES.md                  algorithms and reference code for the remaining tasks
```

Per-tick order (in `Creature._physics_process`):
`brain.think -> loco.update (emit forces) -> body.step -> world.resolve`. Cosmetics run in `_process`.

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

### T1. Facing without popping
- Replace the instant left/right flip in `Creature.dir_to_world()` with a smoothed `facing` value
  (damped toward `intent.look_dir.x`). Use it wherever a mirror is needed.
- **Accept:** reversing direction does not make wings/legs jump in one frame.

### T2. Real world: the game's platforms
- Make `WorldQuery` read the game's actual level instead of a box: `is_solid(p)` via physics point/ray queries
  against the `StaticBody2D`/`CollisionPolygon2D` platforms (`world/platform.gd`), keeping the same public API
  (`is_solid(p)`, `resolve(body)`). **No TileMapLayer** — this project hand-draws its level silhouettes.
- Add two `AStarGrid2D` grids **rasterised from those silhouettes** (not from a tileset): **air grid** (non-solid
  cells) and **surface grid** (non-solid cells adjacent to a solid cell). Expose `world.path_air(from, to)` and
  `world.path_surface(from, to)`. Cell size and bake are `@export`/tuning values.
- **Accept:** `is_solid` matches what is drawn; body points never end up inside a platform; paths exist where
  expected (around a tower, under a ceiling, along an overhang).

### T3. Path following and obstacle avoidance
- Add a `PathFollower` helper: advance waypoints at ~24 px, repath every ~0.3 s or when the goal moves > 1 tile.
- Put the current waypoint into the flow: Locomotors steer toward the *waypoint*, not the raw goal.
- Add wall avoidance to `FlyLocomotor` (2-3 tile lookups ahead along velocity, +-30 degrees; push away weighted by closeness).
- **Accept:** click goals behind walls; the creature routes around them smoothly without jitter or wall-hugging.

### T4. LimbSystem: grips
- Create `core/limb_system.gd`: per limb `gripping`, `grip_pos`, `max_reach`. Implement random-sample grip scoring
  (see DESIGN_NOTES "Grip scoring"). Draw grips in the debug view.
- **Accept:** a limb latches onto nearby wall tiles, releases when over-extended, and never latches onto thin air.

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
- [ ] T1 smooth facing
- [ ] T2 tilemap world and grids
- [ ] T3 path following and avoidance
- [ ] T4 limb grips
- [ ] T5 climb locomotor
- [ ] T6 mode switching
- [ ] T7 depth layer
- [ ] T8 smoothness pass
- [ ] T9 cosmetics and off-screen switch
- [ ] T10 second creature
