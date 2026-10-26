class_name WorldQuery
extends RefCounted
## The creature's only window into the level.
##
## **Solid** means a `StaticBody2D` on `solid_mask`. This project hand-draws its level as
## `StaticBody2D + CollisionPolygon2D`, so point queries against the physics space are the
## source of truth — no tilemap, no re-authored collision. Actors (the player is a
## `CharacterBody2D`), areas and projectiles are ignored *by type*, so a creature can never
## mistake a body for terrain.
##
## `bounds` is a safety box: a point outside it is solid. When no physics space is attached
## (the bare dev scene), the box alone is the world, which is how the framework runs with
## no level loaded.
##
## Two `AStarGrid2D` grids are rasterised from those same queries (`bake`):
##   air     - cells a body can occupy
##   surface - air cells touching terrain (grips, crawling: T4-T6)

## Hard cap on collision sweep samples, so a teleport cannot stall a tick.
const MAX_SWEEP_STEPS := 12
const DEPENETRATE_STEPS := 6

## Safety box in world pixels. Outside = solid.
var bounds: Rect2 = Rect2(0.0, 0.0, 1280.0, 680.0)
var point_radius: float = 8.0
## Physics layer(s) that count as terrain for a creature. Layers 1 (playable ground) and 4
## (the big rock silhouette). The player ignores layer 4 for now; creatures must not fly
## through it.
var solid_mask: int = 1 | 4
var space_state: PhysicsDirectSpaceState2D = null

## Raster size for the two path grids, in pixels.
var cell_size: float = 24.0
## Extra room kept between an air-path cell and terrain, in pixels. A creature is bigger
## than a point, and a flyer sags below its target altitude, so the air grid is inflated by
## this and waypoints are never drawn tight against a wall face. Tune per creature size.
## The surface grid deliberately ignores it: hugging terrain is the whole point of a grip path.
var path_clearance: float = 34.0

var _point_query: PhysicsPointQueryParameters2D = null
var _air: AStarGrid2D = null
var _surface: AStarGrid2D = null
var _grid_rect: Rect2 = Rect2()


## Bind to a live node so queries hit its physics space. Call after the node is in the tree.
func attach(node: Node2D) -> void:
    space_state = node.get_world_2d().direct_space_state


# ---------------------------------------------------------------- solids

func is_solid(p: Vector2) -> bool:
    if not bounds.has_point(p):
        return true
    return is_solid_point(p)


## Terrain test only (ignores the safety box). Used for rasterising and for probes.
func is_solid_point(p: Vector2) -> bool:
    if space_state == null:
        return false
    var q: PhysicsPointQueryParameters2D = _query()
    q.position = p
    q.collision_mask = solid_mask
    for hit in space_state.intersect_point(q, 8):
        if is_terrain(hit.get("collider")):
            return true
    return false


## The one place that decides what "terrain" is. Static bodies only: actors, areas and
## anything that can move are not floor.
static func is_terrain(obj: Object) -> bool:
    return obj is StaticBody2D


# ---------------------------------------------------------------- resolve

## Keep every body point out of the level and slide it along whatever it hit.
func resolve(body: Body) -> void:
    for i in body.pos.size():
        var prev: Vector2 = body.prev[i]
        var target: Vector2 = body.pos[i]

        var p: Vector2 = _sweep(prev, target)
        if is_solid_point(p):
            p = _depenetrate(p, prev)
        # Slide: whatever part of the step was blocked can move along the surface.
        if p != target:
            var slide_n: Vector2 = _surface_normal(p, target - p)
            var rest: Vector2 = target - p
            var slide: Vector2 = rest - slide_n * rest.dot(slide_n)
            if slide.length_squared() > 0.01:
                p = _sweep(p, p + slide)
        p = _clamp_bounds(p)

        if p == target:
            continue

        var n: Vector2 = _surface_normal(p, target - p)
        var v: Vector2 = p - prev
        if n != Vector2.ZERO and v.dot(n) < 0.0:
            v -= n * v.dot(n)              # kill only the component into the surface: slides
        body.pos[i] = p
        body.prev[i] = p - v


## Walk the step in sub-samples and stop at the last free one. Cheap, deterministic, and it
## cannot tunnel through a wall thicker than `point_radius * 0.5`.
func _sweep(from: Vector2, to: Vector2) -> Vector2:
    var d: Vector2 = to - from
    var step: float = maxf(2.0, point_radius * 0.5)
    var steps: int = clampi(int(ceil(d.length() / step)), 1, MAX_SWEEP_STEPS)
    var last_free: Vector2 = from
    for s in range(1, steps + 1):
        var q: Vector2 = from + d * (float(s) / float(steps))
        if is_solid_point(q):
            return last_free
        last_free = q
    return to


## The point is inside terrain. Back up along the tick to the boundary; if the previous
## position was inside too (spawned in a wall), walk out to the nearest free sample.
func _depenetrate(p: Vector2, prev: Vector2) -> Vector2:
    if not is_solid_point(prev):
        var lo: Vector2 = prev
        var hi: Vector2 = p
        for _k in DEPENETRATE_STEPS:
            var mid: Vector2 = (lo + hi) * 0.5
            if is_solid_point(mid):
                hi = mid
            else:
                lo = mid
        return lo
    for ring: float in [2.0, 4.0, 8.0, 16.0, 32.0, 64.0]:
        for k in 16:
            var q: Vector2 = p + Vector2.from_angle(TAU * float(k) / 16.0) * ring
            if not is_solid_point(q):
                return q
    return p


## Outward normal estimated from which of 8 probes are free. Used to slide, not to bounce.
func _surface_normal(p: Vector2, into: Vector2) -> Vector2:
    var n: Vector2 = Vector2.ZERO
    var r: float = maxf(2.0, point_radius * 0.5)
    for k in 8:
        var dir: Vector2 = Vector2.from_angle(TAU * float(k) / 8.0)
        if not is_solid_point(p + dir * r):
            n += dir
    if n.length_squared() > 0.0001:
        return n.normalized()
    return -into.normalized() if into.length_squared() > 0.0001 else Vector2.ZERO


func _clamp_bounds(p: Vector2) -> Vector2:
    var lo: Vector2 = bounds.position + Vector2(point_radius, point_radius)
    var hi: Vector2 = bounds.end - Vector2(point_radius, point_radius)
    if lo.x > hi.x or lo.y > hi.y:
        return p
    return Vector2(clampf(p.x, lo.x, hi.x), clampf(p.y, lo.y, hi.y))


func _query() -> PhysicsPointQueryParameters2D:
    if _point_query == null:
        _point_query = PhysicsPointQueryParameters2D.new()
        _point_query.collide_with_areas = false
        _point_query.collide_with_bodies = true
    return _point_query


# ---------------------------------------------------------------- grids

## Rasterise air + surface grids over `rect` (default: `bounds`).
func bake(rect: Rect2 = Rect2()) -> void:
    var area: Rect2 = rect if rect.size != Vector2.ZERO else bounds
    _grid_rect = area
    var w: int = maxi(1, int(ceil(area.size.x / cell_size)))
    var h: int = maxi(1, int(ceil(area.size.y / cell_size)))

    var solid: PackedByteArray = PackedByteArray()
    solid.resize(w * h)
    for y in h:
        for x in w:
            solid[y * w + x] = 1 if is_solid(cell_pos(Vector2i(x, y))) else 0

    _air = _make_grid(w, h, area)
    _surface = _make_grid(w, h, area)

    for y in h:
        for x in w:
            var id: Vector2i = Vector2i(x, y)
            var centre: Vector2 = cell_pos(id)
            var blocked: bool = is_solid(centre)
            _air.set_point_solid(id, blocked or _clearance_blocked(centre))
            var walkable: bool = not blocked and _near_solid(solid, w, h, x, y)
            _surface.set_point_solid(id, not walkable)
    _air.update()
    _surface.update()


func has_grids() -> bool:
    return _air != null and _surface != null


## Baked-grid truth for one cell (not a live physics query). Diagnostics and debug overlays.
func grid_solid(id: Vector2i) -> bool:
    if _air == null or not _air.is_in_boundsv(id):
        return false
    return _air.is_point_solid(id)


## True when the baked grid covers this cell. A* can only use cells inside the bake rect.
func grid_has(id: Vector2i) -> bool:
    return _air != null and _air.is_in_boundsv(id)


## How many cells the last bake marked solid. Proves the bake actually saw terrain.
func solid_cells() -> int:
    if _air == null or _grid_rect.size == Vector2.ZERO:
        return 0
    var n: int = 0
    var w: int = int(ceil(_grid_rect.size.x / cell_size))
    var h: int = int(ceil(_grid_rect.size.y / cell_size))
    for y in h:
        for x in w:
            if _air.is_point_solid(Vector2i(x, y)):
                n += 1
    return n


## World position of a cell's centre. Also the snapped form of any point.
func cell_pos(id: Vector2i) -> Vector2:
    return _grid_rect.position + (Vector2(id) + Vector2(0.5, 0.5)) * cell_size


func path_air(from: Vector2, to: Vector2) -> PackedVector2Array:
    return _path(_air, from, to)


func path_surface(from: Vector2, to: Vector2) -> PackedVector2Array:
    return _path(_surface, from, to)


func _path(grid: AStarGrid2D, from: Vector2, to: Vector2) -> PackedVector2Array:
    var out: PackedVector2Array = PackedVector2Array()
    if grid == null or _grid_rect.size == Vector2.ZERO:
        return out
    var a: Vector2i = to_cell(from)
    var b: Vector2i = to_cell(to)
    if not grid.is_in_boundsv(a) or not grid.is_in_boundsv(b):
        return out
    if grid.is_point_solid(a) or grid.is_point_solid(b):
        return out
    for id: Vector2i in grid.get_id_path(a, b):
        out.append(cell_pos(id))
    return out


func to_cell(p: Vector2) -> Vector2i:
    return Vector2i(
        int(floor((p.x - _grid_rect.position.x) / cell_size)),
        int(floor((p.y - _grid_rect.position.y) / cell_size)))


func _make_grid(w: int, h: int, area: Rect2) -> AStarGrid2D:
    var g: AStarGrid2D = AStarGrid2D.new()
    g.region = Rect2i(0, 0, w, h)
    g.cell_size = Vector2(cell_size, cell_size)
    g.offset = area.position
    g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
    g.update()
    return g


## True when terrain is within `path_clearance` of a point, in 8 directions.
func _clearance_blocked(p: Vector2) -> bool:
    if path_clearance <= 0.0:
        return false
    for k in 8:
        if is_solid_point(p + Vector2.from_angle(TAU * float(k) / 8.0) * path_clearance):
            return true
    return false


func _near_solid(solid: PackedByteArray, w: int, h: int, x: int, y: int) -> bool:
    for dy in [-1, 0, 1]:
        for dx in [-1, 0, 1]:
            if dx == 0 and dy == 0:
                continue
            var nx: int = x + dx
            var ny: int = y + dy
            if nx < 0 or ny < 0 or nx >= w or ny >= h:
                continue
            if solid[ny * w + nx] == 1:
                return true
    return false
