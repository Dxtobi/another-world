extends RefCounted
## Tiny read-only helper for finding the water volume under a world point.
##
## Water is an Area2D on its own physics layer; nothing solid is created for
## it. Any script can ask "is this point / this body in water?" without needing
## a sensor node or a signal connection.
##
## Kept as a plain RefCounted with static functions (no class_name) so it can
## be preloaded by the player and the enemy controllers without adding another
## autoload or a global script class.

const WATER_LAYER := 1 << 4


static func at_point(world: World2D, point: Vector2) -> Node:
	if world == null:
		return null
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collision_mask = WATER_LAYER
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hits := world.direct_space_state.intersect_point(query, 8)
	for hit in hits:
		var collider = hit.get("collider")
		if collider != null and collider.has_method("is_water_volume"):
			return collider
	return null


## True when the body's collision shape overlaps a water volume. Area overlap
## is the authority: it works for tall creatures whose origin is above the
## waterline, and it does not mistake dry ground sitting above the buried part
## of the water polygon for water. The centre point is a one-frame fallback
## before the area's body_entered signal has fired.
static func body_in_water(body: Node2D, below: float = 0.0) -> bool:
	if body == null or not body.is_inside_tree():
		return false
	var tree := body.get_tree()
	if tree != null:
		for volume in tree.get_nodes_in_group("water"):
			if volume.has_method("has_water_body") and volume.has_water_body(body):
				return true
	var world := body.get_world_2d()
	if at_point(world, body.global_position) != null:
		return true
	if below > 0.0 and at_point(world, body.global_position + Vector2(0.0, below)) != null:
		return true
	return false
