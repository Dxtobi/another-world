@tool
class_name ProcAnimator
extends Node2D
## Plays ProcAnimClips by moving IK target markers. Put it under your Rig node.

signal clip_changed(clip_name: String)

const PATH_STEPS := 48

@export var clips: Array[ProcAnimClip] = []:
	set(value):
		clips = value
		notify_property_list_changed()
		if Engine.is_editor_hint() and is_inside_tree():
			update_configuration_warnings()

## Which clip is playing (a dropdown of your clip names).
@export var current_clip: String = "":
	set(value):
		current_clip = value
		_target_clip = value
		if is_inside_tree():
			clip_changed.emit(value)

## Markers are searched for under this node. Leave empty to use the parent (your Rig).
@export var targets_root: Node
@export_range(0.0, 3.0, 0.01, "or_greater") var blend_time := 0.25
## Playback speed. In game, set this from the creature's speed.
@export_range(0.0, 4.0, 0.01, "or_greater") var speed_scale := 1.0
## Overall strength of all motion.
@export_range(0.0, 1.0, 0.01) var intensity := 1.0

@export_group("Editor Preview")
## Tick to animate in the editor. Untick before moving markers by hand.
@export var preview := false:
	set(value):
		if preview and not value:
			_remove_pose()
		preview = value
@export_tool_button("Refresh targets") var _refresh_button = refresh_targets

@export_group("Debug")
@export var draw_debug := true
@export var draw_paths := true
@export var draw_trails := true
@export_range(10, 300, 1) var trail_length := 90
@export var debug_in_game := false

var _target_clip := ""
var _time := 0.0
var _weights := {}
var _applied_pos := {}
var _applied_rot := {}
var _cache := {}
var _trails := {}


func _init() -> void:
	process_priority = -100 # run before the SoupIK nodes
	z_index = 100
	z_as_relative = false


func _validate_property(property: Dictionary) -> void:
	if property.name == "current_clip":
		var names := PackedStringArray()
		for c in clips:
			if c:
				names.append(c.clip_name)
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = ",".join(names)


func _get_configuration_warnings() -> PackedStringArray:
	var w := PackedStringArray()
	if clips.is_empty():
		w.append("Add at least one ProcAnimClip to Clips.")
	var seen := {}
	for c in clips:
		if c == null:
			continue
		if seen.has(c.clip_name):
			w.append("Duplicate clip name: " + c.clip_name)
		seen[c.clip_name] = true
		for ch in c.channels:
			if ch and _target(ch.target_name, true) == null:
				w.append("Clip '%s': no Node2D named '%s' under the targets root." % [c.clip_name, ch.target_name])
	return w


# ---------- public API ----------

func play(clip_name: String) -> void:
	if clip_name != current_clip:
		current_clip = clip_name


func stop() -> void:
	current_clip = ""


func get_weight(clip_name: String) -> float:
	return _weights.get(clip_name, 0.0)


func refresh_targets() -> void:
	_cache.clear()
	_trails.clear()
	if Engine.is_editor_hint():
		update_configuration_warnings()


# ---------- main loop ----------

func _process(delta: float) -> void:
	var editing := Engine.is_editor_hint()
	if editing and not preview:
		if draw_debug:
			queue_redraw()
		return
	_time += delta * speed_scale
	_update_weights(delta)
	_update_pose()
	if draw_debug and (editing or debug_in_game):
		if draw_trails:
			_record_trails()
		queue_redraw()


func _update_weights(delta: float) -> void:
	var step := delta / maxf(blend_time, 0.001)
	for clip in clips:
		if clip == null:
			continue
		var goal := 1.0 if clip.clip_name == _target_clip else 0.0
		var w: float = _weights.get(clip.clip_name, 0.0)
		_weights[clip.clip_name] = move_toward(w, goal, step)


func _update_pose() -> void:
	var pos_acc := {}
	var rot_acc := {}
	for clip in clips:
		if clip == null:
			continue
		var w: float = _weights.get(clip.clip_name, 0.0) * intensity
		if w <= 0.0001:
			continue
		for ch in clip.channels:
			if ch == null:
				continue
			var n := _target(ch.target_name)
			if n == null:
				continue
			var a := TAU * (_time * clip.speed * ch.frequency + ch.phase)
			pos_acc[n] = pos_acc.get(n, Vector2.ZERO) + ch.sample_position(a) * w
			rot_acc[n] = rot_acc.get(n, 0.0) + ch.sample_rotation(a) * w

	var all_nodes := {}
	for n in _applied_pos.keys():
		all_nodes[n] = true
	for n in pos_acc.keys():
		all_nodes[n] = true

	for n in all_nodes.keys():
		if not is_instance_valid(n):
			_applied_pos.erase(n)
			_applied_rot.erase(n)
			continue
		var new_pos: Vector2 = pos_acc.get(n, Vector2.ZERO)
		var new_rot: float = rot_acc.get(n, 0.0)
		var old_pos: Vector2 = _applied_pos.get(n, Vector2.ZERO)
		var old_rot: float = _applied_rot.get(n, 0.0)
		n.position += new_pos - old_pos
		n.rotation += new_rot - old_rot
		_applied_pos[n] = new_pos
		_applied_rot[n] = new_rot


func _remove_pose() -> void:
	for n in _applied_pos.keys():
		if is_instance_valid(n):
			n.position -= _applied_pos[n]
			n.rotation -= _applied_rot.get(n, 0.0)
	_applied_pos.clear()
	_applied_rot.clear()


func _notification(what: int) -> void:
	# keep the saved scene clean: markers are saved at rest, not mid-animation
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		_remove_pose()


func _exit_tree() -> void:
	_remove_pose()


# ---------- targets ----------

func _root() -> Node:
	return targets_root if targets_root else get_parent()


func _target(target_name: StringName, force := false) -> Node2D:
	if target_name == &"":
		return null
	var cached: Variant = _cache.get(target_name)
	if is_instance_valid(cached):
		return cached
	if not force and _cache.has(target_name) and Engine.get_process_frames() % 30 != 0:
		return null
	var found: Node2D = null
	var root := _root()
	if root:
		found = root.find_child(String(target_name), true, false) as Node2D
	_cache[target_name] = found
	return found


# ---------- debug drawing ----------

func _record_trails() -> void:
	for n in _applied_pos.keys():
		if not is_instance_valid(n):
			continue
		var t: PackedVector2Array = _trails.get(n, PackedVector2Array())
		t.append(to_local(n.global_position))
		if t.size() > trail_length:
			t = t.slice(t.size() - trail_length)
		_trails[n] = t


func _get_clip(clip_name: String) -> ProcAnimClip:
	for c in clips:
		if c and c.clip_name == clip_name:
			return c
	return null


func _draw() -> void:
	if not draw_debug:
		return
	if not Engine.is_editor_hint() and not debug_in_game:
		return
	var font := ThemeDB.fallback_font

	# HUD: clip weights
	var line := 0
	draw_string(font, Vector2(10, -10), "ProcAnimator  t=%.1f  %s" % [_time, "PREVIEW" if preview else "static"],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
	for c in clips:
		if c == null:
			continue
		line += 1
		var col := Color.YELLOW if c.clip_name == _target_clip else Color(1, 1, 1, 0.6)
		draw_string(font, Vector2(10, -10 + line * 14), "%s  %.2f" % [c.clip_name, _weights.get(c.clip_name, 0.0)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)

	# trails
	if draw_trails:
		for n in _trails.keys():
			var t: PackedVector2Array = _trails[n]
			if t.size() >= 2:
				draw_polyline(t, Color(0.4, 1.0, 0.4, 0.5), 1.0)

	# channels of the selected clip
	var clip := _get_clip(_target_clip)
	if clip == null:
		return
	for ch in clip.channels:
		if ch == null:
			continue
		var n := _target(ch.target_name)
		if n == null:
			line += 1
			draw_string(font, Vector2(10, -10 + line * 14), "MISSING: " + String(ch.target_name),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.RED)
			continue
		var parent := n.get_parent() as Node2D
		if parent == null:
			continue
		var applied: Vector2 = _applied_pos.get(n, Vector2.ZERO)
		var base := n.position - applied
		var rest_local := to_local(parent.to_global(base))
		var cur_local := to_local(n.global_position)

		if draw_paths:
			if ch.shape == ProcAnimChannel.Shape.NOISE:
				var ax := absf(ch.amplitude.x)
				var ay := absf(ch.amplitude.y)
				var box := PackedVector2Array()
				for corner in [Vector2(-ax, -ay), Vector2(ax, -ay), Vector2(ax, ay), Vector2(-ax, ay), Vector2(-ax, -ay)]:
					box.append(to_local(parent.to_global(base + corner)))
				draw_polyline(box, Color(1.0, 0.8, 0.2, 0.6), 1.0)
			else:
				var pts := PackedVector2Array()
				for i in range(PATH_STEPS + 1):
					var a := TAU * float(i) / PATH_STEPS
					pts.append(to_local(parent.to_global(base + ch.sample_position(a))))
				draw_polyline(pts, Color(1.0, 0.8, 0.2, 0.6), 1.0)

		draw_line(rest_local, cur_local, Color(1, 1, 1, 0.4), 1.0)
		draw_circle(rest_local, 2.0, Color(0.3, 0.8, 1.0, 0.9))
		draw_circle(cur_local, 3.0, Color(1.0, 0.3, 0.3))
		draw_string(font, cur_local + Vector2(5, -5), String(ch.target_name),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
