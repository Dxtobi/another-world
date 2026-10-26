@tool
extends EditorPlugin

const Weighter := preload("backer.gd")

const BLEND_RADIUS := 10.0
const LEAF_STUB := 15.0

var btn: Button


func _enter_tree() -> void:
	btn = Button.new()
	btn.text = "Weight Backing"
	btn.tooltip_text = "Select the backing Polygon2D (or the creature root), then click"
	btn.pressed.connect(_run)
	add_control_to_container(CONTAINER_CANVAS_EDITOR_MENU, btn)


func _exit_tree() -> void:
	remove_control_from_container(CONTAINER_CANVAS_EDITOR_MENU, btn)
	btn.queue_free()


func _run() -> void:
	var root := EditorInterface.get_edited_scene_root()
	var sel := EditorInterface.get_selection().get_selected_nodes()
	if root == null or sel.is_empty():
		push_warning("Backing Weighter: select the backing Polygon2D (or the creature root) first.")
		return
	var poly := _find_backing(sel[0])
	if poly == null:
		push_warning("Backing Weighter: no Polygon2D backing found under selection.")
		return
	var sk := _find_skeleton(poly, root)
	if sk == null:
		push_warning("Backing Weighter: no Skeleton2D found.")
		return
	var res: Dictionary = Weighter.weight(poly, sk, BLEND_RADIUS, LEAF_STUB)
	if not res.get("ok", false):
		push_warning("Backing Weighter: %s" % res.get("error", "failed"))
		return
	print("Backing Weighter: %d verts, %d bones, %d blended" % [res["verts"], res["bones"], res["blended"]])


func _find_backing(n: Node) -> Polygon2D:
	if n is Polygon2D:
		return n
	var named := n.find_children("*Backing*", "Polygon2D", true, false)
	if not named.is_empty():
		return named[0]
	var any := n.find_children("*", "Polygon2D", true, false)
	return any[0] if not any.is_empty() else null


func _find_skeleton(poly: Node, root: Node) -> Skeleton2D:
	var cur := poly.get_parent()
	while cur != null:
		if cur is Skeleton2D:
			return cur
		cur = cur.get_parent()
	var r := root.find_children("*", "Skeleton2D", true, false)
	return r[0] if not r.is_empty() else null
