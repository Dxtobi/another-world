class_name DepthLayer
extends RefCounted
## Cosmetic 2.5D view of a 2D creature. It reads only the logic-facing proxy and writes
## nothing back, so the one-way rule holds.
##
## `yaw` is the body's turn away from a side profile: 0 = profile, PI/2 = front/back view,
## PI = the opposite profile. `depth_of(side)` returns +near / -far; the two sides cross
## zero at edge-on, which is what makes near/far limbs swap draw order smoothly instead of
## popping when the creature turns around.
##
## `squash` is the magnitude of that same cosine, clamped away from zero. It is applied as a
## horizontal compression around the body centre by `squash_point()`; it never changes a
## logic position.

## Never collapse a whole body to a line, even at the exact edge-on frame.
const MIN_SQUASH: float = 0.15
## Near parts grow a little, far parts shrink a little (1 + depth * SCALE_K).
const SCALE_K: float = 0.08
## How much darker a far part is at depth -1.
const TINT_K: float = 0.35
## Integer z_index step for future per-part CanvasItems.
const Z_K: float = 4.0

var yaw: float = 0.0
var squash: float = 1.0


## Place the layer at the profile implied by a spawn facing, without sweeping 180 degrees.
func reset(facing_value: float = 1.0) -> void:
    var f: float = clampf(facing_value, -1.0, 1.0)
    yaw = (1.0 - f) * 0.5 * PI
    squash = maxf(absf(cos(yaw)), MIN_SQUASH)


## Damp `yaw` toward the angle implied by the logic-facing value. The target is continuous
## (+1 -> 0, 0 -> PI/2, -1 -> PI), so a reversal is a sweep through the front/back view,
## not a snap at the sign change.
func update(facing_value: float, rate: float, dt: float) -> void:
    var f: float = clampf(facing_value, -1.0, 1.0)
    var target: float = (1.0 - f) * 0.5 * PI
    yaw = Steering.damp_f(yaw, target, rate, dt)
    squash = maxf(absf(cos(yaw)), MIN_SQUASH)


## Depth for a part whose authored side is -1 (far) .. +1 (near). Crosses 0 at edge-on.
func depth_of(side: float) -> float:
    return clampf(side, -1.0, 1.0) * cos(yaw)


## Magnitude scale: near parts slightly larger, far parts slightly smaller.
func scale_for(depth_value: float) -> float:
    return 1.0 + depth_value * SCALE_K


## Far parts are darker; near parts keep their colour.
func tint(col: Color, depth_value: float) -> Color:
    if depth_value < 0.0:
        return col.darkened(-depth_value * TINT_K)
    return col


## Draw-order key for future per-part CanvasItems. The debug view sorts by `depth_of()`
## because a single `_draw()` can only order its own primitives by call order.
func z_for(depth_value: float) -> int:
    return roundi(depth_value * Z_K)


## Cosmetic horizontal squash about `centre`. Positions only; logic never sees this.
func squash_point(p: Vector2, centre: Vector2) -> Vector2:
    return centre + Vector2((p.x - centre.x) * squash, p.y - centre.y)
