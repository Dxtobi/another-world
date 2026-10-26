class_name CosmeticChain
extends RefCounted
## Cosmetic follow chain for tails, feathers and other dangly bits. Cosmetic only: it
## reads an anchor position and a rest direction each render frame and writes its own
## points. Nothing in the logic layer ever reads it.
##
## Each segment is a Verlet particle pulled toward the rest pose one segment behind its
## parent. Momentum makes it overshoot and settle instead of snapping, and a distance
## pass keeps the chain from stretching. Both the spring step and the damping are in
## seconds, so a 30 Hz and a 144 Hz display settle the same way.

## Clamp the step so a frame spike cannot pump the springs.
const MAX_DT: float = 0.0333

var points: PackedVector2Array = PackedVector2Array()
var prev: PackedVector2Array = PackedVector2Array()
var seg_len: float = 9.0
## Spring attraction toward the rest pose, in px/s^2 per px of error.
var spring: float = 320.0
## Velocity decay per second (not per frame): higher = less overshoot.
var drag: float = 6.0


func setup(count: int, anchor: Vector2, rest_dir: Vector2, seg: float) -> void:
    points.resize(maxi(count, 2))
    prev.resize(points.size())
    seg_len = maxf(seg, 0.5)
    reset(anchor, rest_dir)


## Put every segment on the rest line without sweeping in from wherever it was.
func reset(anchor: Vector2, rest_dir: Vector2) -> void:
    var d: Vector2 = _safe_dir(rest_dir, Vector2.DOWN)
    for i in points.size():
        points[i] = anchor + d * seg_len * float(i)
        prev[i] = points[i]


## One render-frame step. `anchor` is the live (interpolated) attachment point and
## `rest_dir` the direction the chain wants to hang in. A zero dt is a no-op.
func step(anchor: Vector2, rest_dir: Vector2, dt: float) -> void:
    var n: int = points.size()
    if n < 2 or dt <= 0.0:
        return
    var h: float = minf(dt, MAX_DT)
    var keep: float = exp(-drag * h)
    var d: Vector2 = _safe_dir(rest_dir, points[1] - points[0])

    points[0] = anchor
    prev[0] = anchor
    for i in range(1, n):
        var target: Vector2 = points[i - 1] + d * seg_len
        var v: Vector2 = (points[i] - prev[i]) * keep
        prev[i] = points[i]
        points[i] += v + (target - points[i]) * spring * h * h

    # Exact segment lengths, root -> tip. Two sweeps are enough for five segments.
    for _pass in 2:
        points[0] = anchor
        for i in range(1, n):
            var delta: Vector2 = points[i] - points[i - 1]
            var dist: float = delta.length()
            if dist > 0.0001:
                points[i] = points[i - 1] + delta / dist * seg_len


## Tip in world space (ZERO for an empty chain).
func tip() -> Vector2:
    return points[points.size() - 1] if points.size() > 0 else Vector2.ZERO


## Longest segment, for tests and debug overlays.
func max_segment() -> float:
    var m: float = 0.0
    for i in range(1, points.size()):
        m = maxf(m, points[i - 1].distance_to(points[i]))
    return m


func is_finite() -> bool:
    for p in points:
        if not p.is_finite():
            return false
    for p in prev:
        if not p.is_finite():
            return false
    return true


func _safe_dir(v: Vector2, fallback: Vector2) -> Vector2:
    if v.length_squared() > 0.000001:
        return v.normalized()
    if fallback.length_squared() > 0.000001:
        return fallback.normalized()
    return Vector2.DOWN
