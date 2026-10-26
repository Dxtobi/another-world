extends Node2D
## TEMPORARY slope playtest: runs three movement tests and writes samples to
## res://world/slope_report.json, then prints SLOPE_PROBE_FINISHED.
## A = walk a 30-degree climb. B = idle physics on a 60-degree face (glide).
## C = run off the crest and down the steep side (stick + glide).

func _ready() -> void:
	await get_tree().create_timer(0.8).timeout
	var lines: Array = []
	lines.append("A_climb=" + str(await _run_climb()))
	lines.append("B_glide=" + str(await _test_glide()))
	lines.append("C_descend=" + str(await _test_descend()))
	var f := FileAccess.open("res://world/slope_report.json", FileAccess.WRITE)
	if f != null:
		f.store_string("[\n" + ",\n".join(lines) + "\n]")
		f.close()
	print("SLOPE_PROBE_FINISHED")


func _player() -> Node:
	return get_tree().root.get_node_or_null("Test-scene/Player")


func _sample(p: Node, out: Array) -> void:
	var tag := "air"
	if p.is_on_floor():
		tag = "F"
	elif p.is_on_wall():
		tag = "W"
	var ang := -1.0
	if p.is_on_floor():
		ang = rad_to_deg(Vector2.UP.angle_to(p.get_floor_normal()))
	out.append([int(p.global_position.x), int(p.global_position.y), tag, snappedf(ang, 1.0)])


func _run_climb() -> Array:
	var p := _player()
	if p == null:
		return ["NO_PLAYER"]
	p.global_position = Vector2(1080, 600)
	p.velocity = Vector2.ZERO
	var out: Array = []
	Input.action_press("move_right")
	for i in 12:
		await get_tree().create_timer(0.12).timeout
		_sample(p, out)
	Input.action_release("move_right")
	return out


func _test_glide() -> Array:
	var p := _player()
	if p == null:
		return ["NO_PLAYER"]
	# Spawn just off the 60-degree face so the body presses into it while
	# gravity pulls. Standing still on it must end in a slide, not a stand.
	p.global_position = Vector2(1455, 420)
	p.velocity = Vector2.ZERO
	var out: Array = []
	Input.action_release("move_left")
	Input.action_release("move_right")
	for i in 8:
		await get_tree().create_timer(0.12).timeout
		_sample(p, out)
	return out


func _test_descend() -> Array:
	var p := _player()
	if p == null:
		return ["NO_PLAYER"]
	# On the crest, then run right: down the 66-degree far side and onto the
	# buried pad. The snap must hold contact all the way down.
	p.global_position = Vector2(1580, 250)
	p.velocity = Vector2.ZERO
	var out: Array = []
	Input.action_press("move_right")
	for i in 12:
		await get_tree().create_timer(0.12).timeout
		_sample(p, out)
	Input.action_release("move_right")
	return out
