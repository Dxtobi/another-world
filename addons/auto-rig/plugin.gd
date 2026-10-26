@tool
extends EditorPlugin

const MENU_NAME := "Auto Rig From Selected Sprite"
const RigBuilder := preload("res://addons/auto-rig/rig_builder.gd")

var button: Button

func _enter_tree() -> void:
	add_tool_menu_item(MENU_NAME, _on_run)
	button = Button.new()
	button.text = "Auto Rig"
	button.tooltip_text = "Select the root sprite, then click to generate a skeleton.\nSprites become direct children of their bones (mirror-safe: the whole rig can be flipped with scale.x = -1 without scattering)."
	button.pressed.connect(_on_run)
	add_control_to_container(CONTAINER_CANVAS_EDITOR_MENU, button)

func _exit_tree() -> void:
	remove_tool_menu_item(MENU_NAME)
	if button:
		remove_control_from_container(CONTAINER_CANVAS_EDITOR_MENU, button)
		button.queue_free()

func _on_run() -> void:
	var root := EditorInterface.get_edited_scene_root()
	var sel := EditorInterface.get_selection().get_selected_nodes()
	if root == null or sel.size() != 1 or not (sel[0] is Node2D):
		push_warning("Auto Rig: select exactly one Node2D (the root sprite of the hierarchy)")
		return

	# Build off-scene: one SoupBone2D per sprite, sprite->bone reparent recipe.
	# Parent frame = the scene root (where the skeleton will live), so bones
	# stay scale-free and sprites land exactly where they stood.
	var parent_global := Transform2D.IDENTITY
	if root is Node2D:
		parent_global = (root as Node2D).global_transform
	var res: Dictionary = RigBuilder.build(sel[0], parent_global)
	var skeleton: Skeleton2D = res["skeleton"]
	var moves: Array = res["moves"]

	var ur := get_undo_redo()
	ur.create_action("Auto Rig")
	ur.add_do_method(self, "_do_attach", root, skeleton, moves)
	ur.add_do_reference(skeleton)
	ur.add_undo_method(self, "_do_detach", root, skeleton, moves)
	ur.commit_action()
	push_warning("Auto Rig: %d bones, sprites parented to bones (no RemoteTransform2D)" % moves.size())

func _do_attach(root: Node, skeleton: Skeleton2D, moves: Array) -> void:
	RigBuilder.attach(root, skeleton, moves)

func _do_detach(root: Node, skeleton: Skeleton2D, moves: Array) -> void:
	RigBuilder.detach(root, skeleton, moves)
