class_name ProjectileLayer
extends Node2D
## Draw-order bucket for everything that flies through the world: gun bullets,
## enemy globs, portal shots.
##
## It is a plain Node2D sitting high in the z order, so projectiles draw over
## the player, the water body (which lifts to z 6 while submerged) and its
## underwater content (z 7) - but still under any foreground CanvasLayer,
## because CanvasLayers always draw over Node2D content.
##
## Add it to the "projectile_layer" group. Spawners look the node up through
## find(); if a scene has no layer the spawner falls back to the scene root, so
## nothing breaks in a bare test scene.

## Group every ProjectileLayer registers itself in.
const GROUP := &"projectile_layer"

## Returns the layer node for this tree, or the current scene as a fallback.
static func find(tree: SceneTree) -> Node:
	if tree == null:
		return null
	var n := tree.get_first_node_in_group(GROUP)
	if n != null:
		return n
	return tree.current_scene


func _ready() -> void:
	if not is_in_group(GROUP):
		add_to_group(GROUP)
