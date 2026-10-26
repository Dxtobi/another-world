class_name PortalUtil
extends RefCounted
## Measuring things for portals. Works on ANY physics body by reading its
## collision shapes, so nothing needs to opt in.


## World-space bounding box of all enabled collision shapes on the body.
## Returns an empty Rect2 if it has none.
static func body_bounds(body: Node2D) -> Rect2:
	var have := false
	var out := Rect2()
	for n in body.find_children("*", "CollisionShape2D", true, false):
		var cs := n as CollisionShape2D
		if cs == null or cs.disabled or cs.shape == null:
			continue
		var r := cs.shape.get_rect()
		var xf := cs.global_transform
		var corners := [
			xf * r.position, xf * Vector2(r.end.x, r.position.y),
			xf * r.end, xf * Vector2(r.position.x, r.end.y)]
		for c in corners:
			if not have:
				out = Rect2(c, Vector2.ZERO)
				have = true
			else:
				out = out.expand(c)
	for n in body.find_children("*", "CollisionPolygon2D", true, false):
		var cp := n as CollisionPolygon2D
		if cp == null or cp.disabled:
			continue
		for pt in cp.polygon:
			var c: Vector2 = cp.global_transform * pt
			if not have:
				out = Rect2(c, Vector2.ZERO)
				have = true
			else:
				out = out.expand(c)
	return out


## How wide the box is when measured along a direction.
static func extent_along(bounds: Rect2, dir: Vector2) -> float:
	var d := dir.normalized()
	return absf(d.x) * bounds.size.x + absf(d.y) * bounds.size.y


## True if the body's shapes, moved to `new_origin` and turned by `rot_delta`,
## touch nothing in the body's own collision mask.
##
## The probe has to carry the shape's WORLD scale, not its raw dimensions: the
## player node is scaled down (the rig is authored large and shrunk), so a
## shape queried at raw size comes out roughly ten times too big. It then
## overlaps the floor at the destination every single time and every teleport
## gets rejected as "blocked".
static func is_clear(body: CollisionObject2D, new_origin: Vector2, rot_delta: float) -> bool:
	var space := body.get_world_2d().direct_space_state
	for n in body.find_children("*", "CollisionShape2D", true, false):
		var cs := n as CollisionShape2D
		if cs == null or cs.disabled or cs.shape == null:
			continue
		var q := PhysicsShapeQueryParameters2D.new()
		q.shape = cs.shape
		var off := (cs.global_position - body.global_position).rotated(rot_delta)
		# Scale from the basis columns, NOT Transform2D.get_scale(): that
		# reports (0, 0) on a parent-scaled shape like the player's, which
		# would make the probe a zero-size ghost. Column lengths are the true
		# world scale and survive any ancestor scaling.
		var xf := cs.global_transform
		var scl := Vector2(xf.x.length(), xf.y.length())
		q.transform = Transform2D(cs.global_rotation + rot_delta, scl, 0.0, new_origin + off)
		q.collision_mask = body.collision_mask
		q.exclude = [body.get_rid()]
		q.collide_with_areas = false
		if not space.intersect_shape(q, 1).is_empty():
			return false
	return true
