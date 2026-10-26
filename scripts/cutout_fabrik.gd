@tool
extends Node2D

@export var first_bone: Bone2D:
	set(v):
		first_bone = v
		_setup()
@export var bone_count := 0:
	set(v):
		bone_count = v
		_setup()
@export var target: Node2D

@export_range(1, 20) var iterations := 8
@export var tolerance := 0.5

@export_group("Constraints")
@export_range(0.0, 180.0) var max_angle_root := 15.0
@export_range(0.0, 180.0) var max_angle_tip := 35.0

@export_group("Cutout feel")
@export var follow_speed := 14.0
@export var snap_fps := 0.0
@export_range(0.0, 1.0) var influence := 1.0

@export_group("Editor")
@export var preview_in_editor := false:
	set(v):
		preview_in_editor = v
		if not v:
			_restore_rest()
@export var show_limits := true
@export var show_in_game := false
@export var limit_color := Color(0.2, 0.8, 1.0, 0.25)
@export var pose_color := Color(1.0, 0.85, 0.2, 1.0)

var bones: Array[Bone2D] = []
var local_len: Array[float] = []
var bone_off: Array[float] = []
var rel_rest: Array[float] = []
var rest_rot: Array[float] = []
var _acc := 0.0

func _ready():
	_setup()

func _notification(what):
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		_restore_rest()   # never save a previewed pose into the scene

func _setup():
	_restore_rest()
	bones.clear(); local_len.clear(); bone_off.clear(); rel_rest.clear(); rest_rot.clear()
	if first_bone == null or not first_bone.is_inside_tree():
		return
	var b := first_bone
	while b and (bone_count == 0 or bones.size() < bone_count):
		bones.append(b)
		b = _child_bone(b)
	for i in bones.size():
		var child := _child_bone(bones[i])
		if child:
			local_len.append(child.position.length())
			bone_off.append(child.position.angle())
		else:
			local_len.append(bones[i].get_length())
			bone_off.append(bones[i].get_bone_angle())
		rest_rot.append(bones[i].rotation)
	for i in bones.size():
		if i == 0:
			rel_rest.append(wrapf(rest_rot[0] + bone_off[0], -PI, PI))
		else:
			rel_rest.append(wrapf(rest_rot[i] + bone_off[i] - bone_off[i - 1], -PI, PI))

func _restore_rest():
	if not Engine.is_editor_hint():
		return
	for i in mini(bones.size(), rest_rot.size()):
		if is_instance_valid(bones[i]):
			bones[i].rotation = rest_rot[i]

func _child_bone(b: Bone2D) -> Bone2D:
	for c in b.get_children():
		if c is Bone2D:
			return c
	return null

func _limit_rad(i: int) -> float:
	return deg_to_rad(lerpf(max_angle_root, max_angle_tip, float(i) / maxf(bones.size() - 1, 1)))

func _process(delta):
	if Engine.is_editor_hint():
		if show_limits:
			queue_redraw()
		if not preview_in_editor:
			return
	elif show_in_game:
		queue_redraw()
	if bones.is_empty() or target == null:
		return
	if snap_fps > 0.0:
		_acc += delta
		if _acc < 1.0 / snap_fps:
			return
		_acc = 0.0
		_apply(_solve(), 1.0)
	else:
		_apply(_solve(), 1.0 - exp(-follow_speed * delta))

func _solve() -> Array[float]:
	var n := bones.size()
	var s := absf(bones[0].global_scale.x)
	var parent := bones[0].get_parent() as Node2D
	var base_dir := parent.global_transform.basis_xform(Vector2.RIGHT).normalized()
	var root := bones[0].global_position
	var tgt := target.global_position

	var lens: Array[float] = []
	for l in local_len:
		lens.append(l * s)

	var pts: Array[Vector2] = []
	pts.resize(n + 1)
	for i in n:
		pts[i] = bones[i].global_position
	pts[n] = pts[n - 1] + Vector2.RIGHT.rotated(bones[n - 1].global_rotation + bone_off[n - 1]) * lens[n - 1]

	for it in iterations:
		pts[n] = tgt
		for i in range(n - 1, -1, -1):
			var d := (pts[i] - pts[i + 1]).normalized()
			pts[i] = pts[i + 1] + d * lens[i]
		pts[0] = root
		for i in n:
			var d := (pts[i + 1] - pts[i]).normalized()
			var ref := base_dir if i == 0 else (pts[i] - pts[i - 1]).normalized()
			var rel := ref.angle_to(d)
			var m := _limit_rad(i)
			var dev := clampf(wrapf(rel - rel_rest[i], -PI, PI), -m, m)
			d = ref.rotated(rel_rest[i] + dev)
			pts[i + 1] = pts[i] + d * lens[i]
		if pts[n].distance_to(tgt) < tolerance:
			break

	var out: Array[float] = []
	for i in n:
		out.append((pts[i + 1] - pts[i]).angle())
	return out

func _apply(angles: Array[float], w: float):
	for i in bones.size():
		var want := angles[i] - bone_off[i]
		bones[i].global_rotation = lerp_angle(bones[i].global_rotation, want, w * influence)

func _draw():
	if bones.is_empty():
		return
	if not (show_limits if Engine.is_editor_hint() else show_in_game):
		return
	draw_set_transform_matrix(global_transform.affine_inverse())   # draw in world space
	var n := bones.size()
	var s := absf(bones[0].global_scale.x)
	var parent := bones[0].get_parent() as Node2D
	var ref := parent.global_transform.basis_xform(Vector2.RIGHT).normalized()
	var tip := Vector2.ZERO
	for i in n:
		var origin := bones[i].global_position
		var l := local_len[i] * s
		var m := minf(_limit_rad(i), 3.0)
		var center := ref.rotated(rel_rest[i])
		var cur := Vector2.RIGHT.rotated(bones[i].global_rotation + bone_off[i])
		var col := limit_color.lerp(Color(1.0, 0.4, 0.3, limit_color.a), float(i) / maxf(n - 1, 1))
		if m > 0.01:
			var poly := PackedVector2Array([origin])
			for k in 13:
				poly.append(origin + center.rotated(-m + 2.0 * m * k / 12.0) * l)
			draw_colored_polygon(poly, col)
			draw_line(origin, origin + center.rotated(-m) * l, Color(col, 0.9), 1.5)
			draw_line(origin, origin + center.rotated(m) * l, Color(col, 0.9), 1.5)
		draw_line(origin, origin + cur * l, pose_color, 2.5)
		draw_circle(origin, 3.0, pose_color)
		tip = origin + cur * l
		ref = cur
	if target:
		draw_line(tip, target.global_position, Color(1, 1, 1, 0.4), 1.0)
		draw_circle(target.global_position, 5.0, Color(1, 0.3, 0.3, 0.9))
