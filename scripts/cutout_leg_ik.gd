@tool
extends Node2D

@export var first_bone: Bone2D:
	set(v):
		first_bone = v
		_setup()
@export_range(2, 3) var bone_count := 3:
	set(v):
		bone_count = v
		_setup()
@export var target: Node2D            # the paw. Its ROTATION sets the foot angle (3 bones)
@export var bend_flip := false        # flip if the knee/elbow points the wrong way

@export_group("Joint limits (degrees from rest pose)")
@export var hip_range := Vector2(-70, 70)
@export var knee_range := Vector2(-70, 70)
@export var hock_range := Vector2(-70, 70)

@export_group("Foot (3 bones only)")
@export var foot_angle := -120.0      # degrees, paw -> hock direction, added to the target's rotation

@export_group("Cutout feel")
@export var follow_speed := 18.0
@export var snap_fps := 0.0           # 0 = smooth, 12 = stop-motion stepping
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
		_restore_rest()

func _setup():
	_restore_rest()
	bones.clear(); local_len.clear(); bone_off.clear(); rel_rest.clear(); rest_rot.clear()
	if first_bone == null or not first_bone.is_inside_tree():
		return
	var b := first_bone
	while b and bones.size() < bone_count:
		bones.append(b)
		b = _child_bone(b)
	if bones.size() < 2:
		push_warning("CutoutLegIK needs at least 2 bones in the chain")
		bones.clear()
		return
	for i in bones.size():
		var child := _child_bone(bones[i])
		if child:
			local_len.append(child.position.length())
			bone_off.append(child.position.angle())
		else:
			local_len.append(bones[i].get_length())
			bone_off.append(bones[i].get_bone_angle())
			if bones[i].get_length() <= 0.0:
				push_warning("Last bone has no length: set its Length or add a child Bone2D at the paw tip")
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

func _range(i: int) -> Vector2:
	match i:
		0: return hip_range
		1: return knee_range
		_: return hock_range

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
	var hip := bones[0].global_position
	var parent := bones[0].get_parent() as Node2D
	var ref0 := parent.global_transform.basis_xform(Vector2.RIGHT).normalized()
	var L: Array[float] = []
	for l in local_len:
		L.append(l * s)
	var tgt := target.global_position
	var bend := 1.0 if bend_flip else -1.0

	# the point the first two bones aim at: the paw (2 bones) or the hock (3 bones)
	var reach_pt := tgt
	if n == 3:
		var foot_world := target.global_rotation + deg_to_rad(foot_angle)
		var hock := tgt + Vector2.RIGHT.rotated(foot_world) * L[2]
		if hip.distance_to(hock) > L[0] + L[1]:
			# too far: swing the foot toward the hip until the hock is reachable
			var toward := (hip - tgt).angle()
			for k in range(1, 11):
				var fa := lerp_angle(foot_world, toward, k / 10.0)
				hock = tgt + Vector2.RIGHT.rotated(fa) * L[2]
				if hip.distance_to(hock) <= L[0] + L[1]:
					break
		reach_pt = hock

	# two-bone solve (law of cosines)
	var v := reach_pt - hip
	var dist := clampf(v.length(), absf(L[0] - L[1]) + 0.01, L[0] + L[1] - 0.01)
	var base := v.angle()
	var cos_a := clampf((L[0] * L[0] + dist * dist - L[1] * L[1]) / (2.0 * L[0] * dist), -1.0, 1.0)
	var hip_a := acos(cos_a)
	var ang: Array[float] = []
	ang.append(base + bend * hip_a)
	var knee := hip + Vector2.RIGHT.rotated(ang[0]) * L[0]
	var p := hip + Vector2.RIGHT.rotated(base) * dist
	ang.append((p - knee).angle())
	if n == 3:
		ang.append((tgt - p).angle())

	# joint limits, applied down the chain (each relative to the previous segment)
	var ref := ref0
	for i in n:
		var dir := Vector2.RIGHT.rotated(ang[i])
		var rel := ref.angle_to(dir)
		var dev := wrapf(rel - rel_rest[i], -PI, PI)
		var r := _range(i)
		dev = clampf(dev, deg_to_rad(r.x), deg_to_rad(r.y))
		ang[i] = ref.angle() + rel_rest[i] + dev
		ref = Vector2.RIGHT.rotated(ang[i])
	return ang

func _apply(angles: Array[float], w: float):
	for i in bones.size():
		var want := angles[i] - bone_off[i]
		bones[i].global_rotation = lerp_angle(bones[i].global_rotation, want, w * influence)

func _draw():
	if bones.is_empty():
		return
	if not (show_limits if Engine.is_editor_hint() else show_in_game):
		return
	draw_set_transform_matrix(global_transform.affine_inverse())
	var n := bones.size()
	var s := absf(bones[0].global_scale.x)
	var parent := bones[0].get_parent() as Node2D
	var ref := parent.global_transform.basis_xform(Vector2.RIGHT).normalized()
	var tip := Vector2.ZERO
	for i in n:
		var origin := bones[i].global_position
		var l := local_len[i] * s
		var r := _range(i)
		var lo := deg_to_rad(r.x)
		var hi := deg_to_rad(r.y)
		var center := ref.rotated(rel_rest[i])
		var cur := Vector2.RIGHT.rotated(bones[i].global_rotation + bone_off[i])
		var col := limit_color.lerp(Color(1.0, 0.4, 0.3, limit_color.a), float(i) / maxf(n - 1, 1))
		if hi - lo > 0.01:
			var poly := PackedVector2Array([origin])
			for k in 13:
				poly.append(origin + center.rotated(lerpf(lo, hi, k / 12.0)) * l)
			draw_colored_polygon(poly, col)
			draw_line(origin, origin + center.rotated(lo) * l, Color(col, 0.9), 1.5)
			draw_line(origin, origin + center.rotated(hi) * l, Color(col, 0.9), 1.5)
		draw_line(origin, origin + cur * l, pose_color, 2.5)
		draw_circle(origin, 3.0, pose_color)
		tip = origin + cur * l
		ref = cur
	if target:
		draw_line(tip, target.global_position, Color(1, 1, 1, 0.4), 1.0)
		draw_circle(target.global_position, 5.0, Color(1, 0.3, 0.3, 0.9))
