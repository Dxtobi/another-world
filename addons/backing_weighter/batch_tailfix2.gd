@tool
extends Node

# TEMP one-shot (deleted after verification). Re-weights Tail scoped to the
# tail subtree so leg/claw bones can't own tail verts.
func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	for i in 90:
		await get_tree().process_frame
		if not is_inside_tree():
			return
	_go()
	queue_free()

func _go() -> void:
	var W = load("res://addons/backing_weighter/backer.gd")
	var root = EditorInterface.get_edited_scene_root()
	var poly := root.get_node_or_null("body/beast-sprite/toso-midle/Tail") as Polygon2D
	if poly == null:
		push_warning("TailFix2: Tail polygon not found")
		return
	var skels = root.find_children("*", "Skeleton2D", true, false)
	if skels.is_empty():
		push_warning("TailFix2: no skeleton")
		return
	var sk: Skeleton2D = skels[0]
	var rb := sk.find_child("section-4_bone", true, false) as Bone2D
	if rb == null:
		push_warning("TailFix2: no section-4")
		return
	var res: Dictionary = W.weight(poly, sk, 10.0, 15.0, rb)
	push_warning("TailFix2 v1: ok=%s verts=%s bones=%s blended=%s" % [
		str(res.get("ok")), str(res.get("verts")), str(res.get("bones")), str(res.get("blended"))])
