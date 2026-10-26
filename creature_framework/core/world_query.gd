class_name WorldQuery
extends RefCounted
## The creature's only window into the level. Currently a plain box so the framework runs with no tilemap.
## TODO (see README task T2): back this with a TileMapLayer and expose is_solid(), grids, surface queries.

var bounds: Rect2 = Rect2(0.0, 0.0, 1280.0, 680.0)
var point_radius: float = 8.0


func is_solid(p: Vector2) -> bool:
    return not bounds.has_point(p)


## Push body points back inside the world and kill the velocity component that hit the wall.
func resolve(body: Body) -> void:
    var lo: Vector2 = bounds.position + Vector2(point_radius, point_radius)
    var hi: Vector2 = bounds.end - Vector2(point_radius, point_radius)
    for i in body.pos.size():
        var p: Vector2 = body.pos[i]
        var q: Vector2 = Vector2(clampf(p.x, lo.x, hi.x), clampf(p.y, lo.y, hi.y))
        if q == p:
            continue
        var pv: Vector2 = body.prev[i]
        if q.x != p.x:
            pv.x = q.x
        if q.y != p.y:
            pv.y = q.y
            pv.x = lerpf(pv.x, q.x, 0.15)   # a little ground friction
        body.pos[i] = q
        body.prev[i] = pv
