@tool
class_name BoneLine2D
extends Line2D
## Follows a linear Bone2D chain (e.g. tail section-5..9) and draws a
## tapered line through the joints behind the art. One node, one tiny
## per-frame update, no skinning, no baking.

@export var skeleton_path: NodePath: set = _set_sk
@export var chain_root_path: NodePath: set = _set_cr
@export var width_head := 24.0: set = _set_wh
@export var width_tail := 6.0: set = _set_wt
@export var line_color := Color(0.12, 0.05, 0.16, 1.0): set = _set_lc
@export var tip_extra := 26.0
@export var rebuild := false: set = _set_rb

var skeleton: Skeleton2D
var chain_root: Bone2D
var _bones: Array[Bone2D] = []
var proc_ticks := 0
var phys_ticks := 0

func _set_sk(v: NodePath) -> void:
	skeleton_path = v
	_resolve()
func _set_cr(v: NodePath) -> void:
	chain_root_path = v
	_resolve()
func _set_rb(v: bool) -> void:
	rebuild = false
	if v and is_inside_tree():
		_resolve()
		_bake_curve()
		_update_points()

func _set_wh(v: float) -> void:
	width_head = v
	_bake_curve()
func _set_wt(v: float) -> void:
	width_tail = v
	_bake_curve()
func _set_lc(v: Color) -> void:
	line_color = v
	default_color = v

func _ready() -> void:
	joint_mode = Line2D.LINE_JOINT_ROUND
	begin_cap_mode = Line2D.LINE_CAP_ROUND
	end_cap_mode = Line2D.LINE_CAP_ROUND
	antialiased = true
	texture_mode = Line2D.LINE_TEXTURE_NONE
	default_color = line_color
	set_process(true)
	_resolve()
	_bake_curve()
	_update_points()

func _physics_process(_delta: float) -> void:
	phys_ticks += 1
	_update_points()

func _resolve() -> void:
	skeleton = get_node_or_null(skeleton_path) as Skeleton2D
	chain_root = get_node_or_null(chain_root_path) as Bone2D
	_collect()

func _process(_delta: float) -> void:
	proc_ticks += 1
	if skeleton == null or _bones.is_empty():
		return
	_update_points()

func _collect() -> void:
	_bones.clear()
	if chain_root == null:
		return
	var b := chain_root
	while b != null:
		_bones.append(b)
		var nxt: Bone2D = null
		for c in b.get_children():
			if c is Bone2D:
				nxt = c
				break
		b = nxt

func _bake_curve() -> void:
	var c := Curve.new()
	c.add_point(Vector2(0, 1.0))
	c.add_point(Vector2(0.5, lerpf(1.0, width_tail / maxf(width_head, 0.01), 0.55)))
	c.add_point(Vector2(1, width_tail / maxf(width_head, 0.01)))
	width_curve = c
	width = width_head

func _update_points() -> void:
	if not is_inside_tree() or _bones.is_empty():
		return
	var pts := PackedVector2Array()
	for b in _bones:
		if not is_instance_valid(b):
			return
		pts.append(to_local((b as Node2D).global_position))
	var last := _bones[_bones.size() - 1] as Node2D
	pts.append(to_local(last.global_position + Vector2.RIGHT.rotated(last.global_rotation) * tip_extra))
	points = pts
