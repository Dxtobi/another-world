class_name Body
extends RefCounted
## The logic layer: Verlet point masses + distance constraints. Generic for every creature.
## Cosmetics may READ this. Nothing in here may read cosmetics.

var pos: PackedVector2Array = PackedVector2Array()
var prev: PackedVector2Array = PackedVector2Array()
var mass: PackedFloat32Array = PackedFloat32Array()
var accel: PackedVector2Array = PackedVector2Array()
var links: Array[LinkDef] = []
var rest: PackedFloat32Array = PackedFloat32Array()
var damping: float = 0.985
var iterations: int = 4


func setup(rig: CreatureRig, origin: Vector2) -> void:
    var n: int = rig.points.size()
    pos.resize(n)
    prev.resize(n)
    mass.resize(n)
    accel.resize(n)
    for i in n:
        var p: PointDef = rig.points[i]
        pos[i] = origin + p.offset
        prev[i] = pos[i]
        mass[i] = maxf(p.mass, 0.01)
        accel[i] = Vector2.ZERO
    links = rig.links
    rest.resize(links.size())
    for k in links.size():
        var l: LinkDef = links[k]
        rest[k] = l.rest_length if l.rest_length > 0.0 else pos[l.a].distance_to(pos[l.b])


func add_accel(i: int, a: Vector2) -> void:
    accel[i] += a


## Instant velocity change in px/s (used for launches / landings).
func add_impulse(i: int, vel: Vector2, dt: float) -> void:
    prev[i] -= vel * dt


## Velocity in px/s derived from the Verlet state.
func velocity(i: int, dt: float) -> Vector2:
    return (pos[i] - prev[i]) / dt


## Position for rendering, interpolated between the last two physics ticks.
func render_pos(i: int, alpha: float) -> Vector2:
    return prev[i].lerp(pos[i], alpha)


func step(dt: float) -> void:
    for i in pos.size():
        var v: Vector2 = (pos[i] - prev[i]) * damping
        prev[i] = pos[i]
        pos[i] = pos[i] + v + accel[i] * dt * dt
        accel[i] = Vector2.ZERO
    for _it in iterations:
        for k in links.size():
            _solve_link(k)


func _solve_link(k: int) -> void:
    var l: LinkDef = links[k]
    var d: Vector2 = pos[l.b] - pos[l.a]
    var dist: float = d.length()
    if dist < 0.0001:
        return
    var diff: float = (dist - rest[k]) / dist
    var wa: float = 1.0 / mass[l.a]
    var wb: float = 1.0 / mass[l.b]
    var wsum: float = wa + wb
    pos[l.a] += d * diff * (wa / wsum) * l.stiffness
    pos[l.b] -= d * diff * (wb / wsum) * l.stiffness
