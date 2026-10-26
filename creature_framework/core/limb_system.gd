class_name LimbSystem
extends RefCounted
## Per-limb grip state: is this limb holding a surface, where, and which way does it face.
##
## T4 is **cosmetic-only**: a gripping limb's tip is pinned to `grip_pos`, and the debug view
## draws that point. The grip becomes a physical constraint in T5, so nothing here touches
## the body yet.
##
## How a grip is found: `SAMPLES` short rays are fanned out along the limb from its anchor,
## toward the tip the locomotor asked for. A ray hit gives both a contact point and an outward
## normal — exactly a handhold. The fan matters because the ideal tip is often *inside* a wall
## the limb is reaching into; the ray stops at the face where a real limb would touch it.
## `WorldQuery.surface_near` is the fallback for a surface beside the tip instead of in front
## of it (a ledge the limb is reaching past).
##
## A grip is never re-scored while held: it is a fixed point in the world, so the limb cannot
## crawl along a wall by itself. It releases only when the anchor moves out of reach, which is
## what hands the next grip to the locomotion mode (T5's gait rule).

## How far past the limb's nominal reach a grip may be taken. A limb that grabs a wall just
## beyond its drawn tip reads better than one that refuses to touch the wall in front of it.
const REACH_SCALE := 1.25
## Radius of the fallback probe around the ideal tip.
const GRIP_RADIUS := 10.0
## Rays fanned along the limb per attempt. Odd, so one ray is exactly on the ideal line.
const SAMPLES := 7
## Half-angle of that fan, in degrees.
const SAMPLE_SPREAD := 26.0
## Never latch to terrain this close to the anchor: that is the creature's own body, not a
## handhold, and the limb would fold into the chest.
const MIN_HOLD := 14.0
## Seconds between attempts for a limb that is not holding anything (staggered per limb, so
## four limbs never fan their rays on the same tick).
const ATTEMPT_INTERVAL := 0.06

var rig: CreatureRig = null
var world: WorldQuery = null
var c: Creature = null

## 1 while a limb is holding. PackedByteArray is the cheapest bool array in GDScript.
var gripping: PackedByteArray = PackedByteArray()
## World-space contact point and outward surface normal per limb.
var grip_pos: PackedVector2Array = PackedVector2Array()
var grip_normal: PackedVector2Array = PackedVector2Array()

var _cooldown: PackedFloat32Array = PackedFloat32Array()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func setup(p_rig: CreatureRig, p_world: WorldQuery, p_creature: Creature, seed_value: int = 0) -> void:
    rig = p_rig
    world = p_world
    c = p_creature
    _rng.seed = seed_value
    var n: int = rig.limbs.size()
    gripping.resize(n)
    gripping.fill(0)
    grip_pos.resize(n)
    grip_normal.resize(n)
    _cooldown.resize(n)
    for i in n:
        grip_pos[i] = c.anchor_pos(i)
        grip_normal[i] = Vector2.UP
        # Spread first attempts over one interval: phase + a small seeded jitter.
        var phase: float = (float(i) + _rng.randf()) / float(maxi(n, 1))
        _cooldown[i] = ATTEMPT_INTERVAL * phase


## Per-tick housekeeping: age the attempt cooldowns and drop grips the body has walked away
## from. Call before locomotor output so a released limb is free to be re-targeted this tick.
func update(dt: float) -> void:
    for i in rig.limbs.size():
        if _cooldown[i] > 0.0:
            _cooldown[i] = maxf(0.0, _cooldown[i] - dt)
        if gripping[i] == 1 and c.anchor_pos(i).distance_to(grip_pos[i]) > max_reach(i):
            release(i)


## Try to take hold with limb `i`, aiming at an ideal tip in world space.
## Returns true when this call produced a grip. Respects the per-limb attempt cooldown.
func try_grip(i: int, ideal: Vector2) -> bool:
    if gripping[i] == 1 or _cooldown[i] > 0.0:
        return false
    _cooldown[i] = ATTEMPT_INTERVAL
    if world == null or world.space_state == null:
        return false

    var anchor: Vector2 = c.anchor_pos(i)
    var to_ideal: Vector2 = ideal - anchor
    var ideal_len: float = to_ideal.length()
    if ideal_len < 1.0:
        return false
    var reach: float = max_reach(i)
    if ideal_len > reach:
        return false                     # the locomotor is asking for more than this limb has

    var base: Vector2 = to_ideal / ideal_len
    var spread: float = deg_to_rad(SAMPLE_SPREAD)
    var from: Vector2 = anchor + base * MIN_HOLD
    var q: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(from, from, world.solid_mask, [])
    q.collide_with_areas = false
    q.collide_with_bodies = true
    q.hit_from_inside = false

    var best_pos: Vector2 = Vector2.ZERO
    var best_normal: Vector2 = Vector2.ZERO
    var best_score: float = INF

    for k in SAMPLES:
        var t: float = float(k) / float(SAMPLES - 1) * 2.0 - 1.0
        var ang: float = spread * t
        var dir: Vector2 = base.rotated(ang)
        q.to = anchor + dir * reach
        var hit: Dictionary = world.space_state.intersect_ray(q)
        if hit.is_empty() or not WorldQuery.is_terrain(hit.get("collider")):
            continue
        var p: Vector2 = hit["position"]
        var d: float = anchor.distance_to(p)
        if d < MIN_HOLD:
            continue
        # Prefer the ray closest to the ideal line, then the hit closest to the ideal length.
        var score: float = absf(t) + 0.6 * absf(d - ideal_len) / maxf(ideal_len, 1.0)
        if score < best_score:
            best_score = score
            best_pos = p
            best_normal = hit.get("normal", Vector2.ZERO)

    if best_score < INF:
        _latch(i, best_pos, best_normal)
        return true

    # Fallback: a surface beside the tip, not along the limb. `surface_near` refuses points
    # inside terrain, so this cannot invent a grip inside a wall.
    var near: WorldQuery.SurfaceHit = world.surface_near(ideal, GRIP_RADIUS)
    if near != null:
        var d_anchor: float = anchor.distance_to(near.pos)
        if d_anchor >= MIN_HOLD and d_anchor <= reach:
            _latch(i, near.pos, near.normal)
            return true
    return false


func is_gripping(i: int) -> bool:
    return gripping[i] == 1


## World position of limb i's grip. Only meaningful while `is_gripping(i)`.
func grip_of(i: int) -> Vector2:
    return grip_pos[i]


func grip_count() -> int:
    var n: int = 0
    for i in rig.limbs.size():
        n += gripping[i]
    return n


## Average of all held grip points. With no grips this returns the body centre, so a
## locomotor can use it without a null check.
func grip_centroid() -> Vector2:
    var sum: Vector2 = Vector2.ZERO
    var n: int = 0
    for i in rig.limbs.size():
        if gripping[i] == 1:
            sum += grip_pos[i]
            n += 1
    if n == 0:
        return c.body.pos[rig.center_point]
    return sum / float(n)


## Normalized sum of the held grips' outward normals (which way the wall faces), or ZERO
## when nothing is held. (`grip_normal` is the per-limb array, so this is the average.)
func grip_normal_avg() -> Vector2:
    var sum: Vector2 = Vector2.ZERO
    for i in rig.limbs.size():
        if gripping[i] == 1:
            sum += grip_normal[i]
    return sum.normalized() if sum.length_squared() > 0.0001 else Vector2.ZERO


## Release the held limb furthest BEHIND the body along `tangent`, but only while at least
## `min_other` limbs would still hold. This is the gait rule: never let go with fewer than
## two other hands on the wall. `min_behind` is how far past the body a grip must be before
## it counts as "behind" (small values would creep; large values would over-stretch).
## Returns the released limb index, or -1 when nothing was let go.
func release_furthest_behind(tangent: Vector2, min_other: int = 2, min_behind: float = 0.0) -> int:
    if grip_count() - 1 < min_other:
        return -1
    if tangent.length_squared() < 0.0001:
        return -1
    var d: Vector2 = tangent.normalized()
    var centre: Vector2 = c.body.pos[rig.center_point]
    var best: int = -1
    var best_behind: float = min_behind
    for i in rig.limbs.size():
        if gripping[i] == 0:
            continue
        var behind: float = (centre - grip_pos[i]).dot(d)
        if behind > best_behind:
            best_behind = behind
            best = i
    if best >= 0:
        release(best)
    return best


## How far a grip may be from the anchor before it is dropped.
func max_reach(i: int) -> float:
    return rig.limbs[i].reach * REACH_SCALE


func release(i: int) -> void:
    if gripping[i] == 0:
        return
    gripping[i] = 0
    _cooldown[i] = ATTEMPT_INTERVAL      # do not re-grab the same surface on the same tick


func release_all() -> void:
    for i in rig.limbs.size():
        release(i)


func _latch(i: int, p: Vector2, normal: Vector2) -> void:
    gripping[i] = 1
    grip_pos[i] = p
    grip_normal[i] = normal.normalized() if normal.length_squared() > 0.0001 else Vector2.UP
    _cooldown[i] = 0.0
