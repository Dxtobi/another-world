@tool
extends RefCounted
## Builds the Skeleton2D from a Node2D sprite hierarchy and parents each sprite
## DIRECTLY onto its bone, instead of driving sprites with RemoteTransform2D.
##
## Why: RemoteTransform2D decomposes a transform into position+rotation+scale
## and re-applies those three separately. That decomposition is lossy under a
## mirrored (negative) scale, so flipping a rig with body.scale.x = -1 made
## every piece scatter by a different amount. A sprite that is a real child of
## its bone inherits the mirror by pure matrix math and can never separate.
##
## Visual parity with the old remote setup: remotes pushed the bone's global
## position + rotation onto each sprite while leaving its scale alone. attach()
## reproduces exactly that (bone rotation+origin, sprite's own scale), so an
## unmirrored pose is identical to before — and a mirrored one now holds.

const LEAF_BONE_LENGTH := 30.0

## Builds the skeleton off-scene. `parent_global` must be the global transform
## of the node attach() will parent the skeleton to (the scene root), so the
## bone chain comes out scale-free and lands the sprites exactly where they
## were. Returns { "skeleton": Skeleton2D, "moves": Array } where each move is
## [bone, sprite, orig_global, orig_parent, orig_local, orig_index, orig_owner].
## Nothing is modified in the scene until attach().
static func build(top: Node2D, parent_global: Transform2D) -> Dictionary:
	var skeleton := Skeleton2D.new()
	skeleton.name = "Skeleton2D"
	var moves: Array = []
	_build_bone(top, skeleton, parent_global, moves)
	return {"skeleton": skeleton, "moves": moves}


## Do/redo: adds the sprite's exact original global transform back (which,
## since the bone is scale-free, equals the old remote result — bone position
## + rotation, sprite's own scale), parents it under its bone and re-links
## owners so the scene save keeps the moved nodes.
static func attach(root: Node, skeleton: Skeleton2D, moves: Array) -> void:
	root.add_child(skeleton)
	_set_owner_recursive(skeleton, root)
	for m in moves:
		var bone: Node2D = m[0]
		var spr: Node2D = m[1]
		spr.get_parent().remove_child(spr)
		bone.add_child(spr)
		spr.global_transform = m[2]   # exact pre-rig global; local = bone^-1 * it
		_set_owner_recursive(spr, root)


## Undo: sprites return to their original parents, transforms and sibling
## order; the skeleton is removed. Children are restored before parents so
## sibling indices stay valid.
static func detach(root: Node, skeleton: Skeleton2D, moves: Array) -> void:
	for i in range(moves.size() - 1, -1, -1):
		var m: Array = moves[i]
		var spr: Node2D = m[1]
		var orig_parent: Node = m[3]
		if not is_instance_valid(orig_parent) or not is_instance_valid(spr):
			continue
		spr.get_parent().remove_child(spr)
		orig_parent.add_child(spr)
		orig_parent.move_child(spr, m[5])
		spr.transform = m[4]
		spr.owner = m[6]   # undo attach()'s owner re-link (captured pre-rig)
	root.remove_child(skeleton)


# Pre-order walk of the sprite tree: one SoupBone2D per sprite, plus the
# reparent recipe. Captures happen here, BEFORE any move.
static func _build_bone(sprite: Node2D, parent: Node, parent_global: Transform2D, moves: Array) -> void:
	var g := sprite.global_transform
	var clean := Transform2D(g.get_rotation(), g.origin)  # no scale on bones

	var bone := Bone2D.new()
	bone.name = str(sprite.name) + "_bone"
	bone.transform = parent_global.affine_inverse() * clean
	bone.rest = bone.transform
	
	parent.add_child(bone)

	# the sprite's exact pre-rig global; attach() re-applies it on the bone
	moves.append([bone, sprite, g,
			sprite.get_parent(), sprite.transform, sprite.get_index(),
			sprite.owner])

	var has_child_bone := false
	for child in sprite.get_children():
		if child is Node2D:
			has_child_bone = true
			_build_bone(child, bone, clean, moves)

	if not has_child_bone:
		bone.set_autocalculate_length_and_angle(false)
		bone.set_length(LEAF_BONE_LENGTH)


static func _set_owner_recursive(node: Node, owner_node: Node) -> void:
	node.owner = owner_node
	for c in node.get_children():
		_set_owner_recursive(c, owner_node)
