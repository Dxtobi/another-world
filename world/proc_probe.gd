extends Node
## One-shot live probe for the procedural movement rig in player.gd.
## Timeline: settle idle -> run right with samples -> dash and check the clip
## takes back over -> dump a JSON report and print PROC_PROBE_FINISHED.

var _p: CharacterBody2D
var _anim: AnimationPlayer
var _rl: Node2D
var _ll: Node2D
var _head: Node2D
var _toso: Bone2D

var _t := 0.0
var _stage := 0
var _next_sample := 0.0
var _rows: Array = []
var _dash_rows: Array = []
var _rest := {}


func _ready() -> void:
	var scene := get_tree().current_scene
	_p = scene.get_node("Player") as CharacterBody2D
	_anim = _p.anim
	var ik := _p.get_node("body/IK") as Node2D
	_rl = ik.get_node("rl") as Node2D
	_ll = ik.get_node("ll") as Node2D
	_head = ik.get_node("head") as Node2D
	var bones := _p.get_node("body").find_children("toso", "Bone2D", true, false)
	_toso = bones[0] as Bone2D if not bones.is_empty() else null
	for entry in [[_rl, "rl"], [_ll, "ll"], [_head, "head"], [_toso, "toso"]]:
		if entry[0] != null:
			_rest[entry[1]] = {
				"x": entry[0].position.x, "y": entry[0].position.y,
				"rot": entry[0].rotation,
			}


func _row() -> Dictionary:
	return {
		"t": snappedf(_t, 0.001),
		"vx": snappedf(_p.velocity.x, 1.0),
		"vy": snappedf(_p.velocity.y, 1.0),
		"on_floor": _p.is_on_floor(),
		"paused": not _anim.active,
		"clip": String(_anim.assigned_animation),
		"mode": String(_p.gun_aim.mode),
		"rl": {"x": snappedf(_rl.position.x, 0.1), "y": snappedf(_rl.position.y, 0.1)},
		"ll": {"x": snappedf(_ll.position.x, 0.1), "y": snappedf(_ll.position.y, 0.1)},
		"toso": "gone" if _toso == null else Vector2(_toso.position.x, _toso.position.y),
		"toso_rot": 0.0 if _toso == null else snappedf(_toso.rotation, 0.001),
	}


func _physics_process(delta: float) -> void:
	_t += delta
	match _stage:
		0: # settle into the procedural idle
			if _t >= 0.7:
				_rows.append(_row())
				_stage = 1
				_next_sample = _t
				Input.action_press("move_right")
		1: # run right, sample the gait
			if _t >= _next_sample:
				_rows.append(_row())
				_next_sample += 0.13
			if _t >= 1.7:
				Input.action_release("move_right")
				_stage = 2
				Input.action_press("dash")
		2: # dash must hand the pose back to the clips
			Input.action_release("dash")
			if _t >= _next_sample:
				_dash_rows.append(_row())
				_next_sample = _t + 0.09
			if _t >= 2.5:
				_stage = 3
		3: # release, settle, dump
			Input.action_release("move_right")
			if _t >= 3.0:
				var f := FileAccess.open("res://proc_report.json", FileAccess.WRITE)
				if f != null:
					f.store_string(JSON.stringify({
						"rest": _rest,
						"run_rows": _rows,
						"dash_rows": _dash_rows,
					}, "  "))
				print("PROC_PROBE_FINISHED")
				set_physics_process(false)
