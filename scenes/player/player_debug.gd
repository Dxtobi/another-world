class_name PlayerDebug
extends Node2D
## Toggleable debug overlay for the aim rig, the weapon and the player.
## Add it as a child of Player. Press F1 (or `toggle_key`) in-game to show or
## hide everything; the three `show_*` flags pick which sections are drawn.
## World-space lines are drawn in _draw (aim ray, cursor, muzzle link, velocity)
## and the numbers live in a screen-space panel, so they stay readable at any zoom.

@export var enabled := false:
	set(value):
		enabled = value
		if is_node_ready():
			_apply_visibility()
@export var toggle_key := KEY_F1
@export_group("Sections")
@export var show_aim := true
@export var show_weapon := true
@export var show_player := true
@export_group("Aim drawing")
@export_range(100.0, 4000.0, 10.0, "suffix:px") var aim_ray_length := 1500.0
@export_range(1.0, 200.0, 1.0, "suffix:px") var line_width := 30.0

var player: Player
var gun_aim: GunAim
var gun: Node
var _panel: PanelContainer
var _label: Label
var _shots := 0
## Last mouse world positions, one per frame. If these stack in one spot while
## you move the physical mouse, the cursor data reaching the game is frozen
## (focus / capture issue) and the aim math is innocent.
var _trail: Array[Vector2] = []
const TRAIL_LEN := 40


func _ready() -> void:
	z_index = 4096
	var root := get_parent()
	if root is Player:
		player = root as Player
	else:
		player = root.find_child("Player", true, false) as Player
		if player == null and root.get_parent() != null:
			player = root.get_parent().find_child("Player", true, false) as Player
	if player != null:
		gun_aim = player.gun_aim
		gun = player.gun
		if gun != null and gun.has_signal("fired") and not gun.fired.is_connected(_on_shot):
			gun.fired.connect(_on_shot)

	_panel = PanelContainer.new()
	var layer := CanvasLayer.new()
	layer.layer = 128
	layer.add_child(_panel)
	add_child(layer)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85))
	_panel.add_child(_label)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.03, 0.02, 0.82)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	_panel.add_theme_stylebox_override("panel", style)
	_panel.position = Vector2(10, 10)
	_apply_visibility()


func _on_shot() -> void:
	_shots += 1


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == toggle_key:
			enabled = not enabled
			_apply_visibility()
			get_viewport().set_input_as_handled()


func _apply_visibility() -> void:
	_panel.visible = enabled
	visible = true # keep _draw alive; it early-outs when disabled


func _process(_delta: float) -> void:
	if not enabled:
		return
	if is_instance_valid(gun_aim) and gun_aim.gun_pivot != null:
		_trail.push_back(gun_aim.gun_pivot.get_global_mouse_position())
		while _trail.size() > TRAIL_LEN:
			_trail.pop_front()
	_update_text()
	queue_redraw()


func _update_text() -> void:
	var lines: Array[String] = []
	if show_aim and is_instance_valid(gun_aim):
		var pivot := gun_aim.gun_pivot
		var mouse_w := pivot.get_global_mouse_position() if pivot != null else Vector2.ZERO
		var mz := Vector2.ZERO
		if gun_aim.muzzle != null:
			mz = gun_aim.muzzle.global_position
		var err := 0.0
		if pivot != null and (mouse_w - mz).length() > 1.0:
			err = rad_to_deg((mouse_w - mz).angle_to(gun_aim.barrel_direction()))
		lines.append("[AIM] (F1 hides)")
		lines.append("  mouse screen %s" % str(Vector2i(get_viewport().get_mouse_position())))
		lines.append("  mouse world (%.1f, %.1f)" % [mouse_w.x, mouse_w.y])
		lines.append("  mode=%s aim_w=%.2f hands_w=%.2f facing=%+.0f" \
			% [gun_aim.mode, gun_aim.aim_w, gun_aim.hands_w, gun_aim.facing])
		lines.append("  pivot=%s rot=%.1f solve=%.1f muzzle=(%.1f, %.1f)" % [
			String(pivot.name) if pivot != null else "?",
			rad_to_deg(pivot.rotation) if pivot != null else 0.0,
			rad_to_deg(gun_aim.solve_aim_rotation()) if pivot != null else 0.0,
			mz.x, mz.y])
		lines.append("  shot->cursor err=%.2f deg (ignore when cursor is inside the gun)" % err)
		if player.crosshair != null:
			var ch: Crosshair = player.crosshair
			lines.append("  crosshair lock=%s auto_fire=%s" % [
				"HOSTILE" if ch.locked else "clear",
				"on" if ch.auto_fire else "off"])
	if show_weapon and gun != null:
		var clip := ""
		var cd := 0.0
		var rec := 0.0
		if gun.get("shoot_anim") != null and (gun.get("shoot_anim") as AnimationPlayer) != null:
			clip = String((gun.get("shoot_anim") as AnimationPlayer).current_animation)
		if gun.get("_cooldown") != null:
			cd = float(gun.get("_cooldown"))
		if gun.get("_recoil_offset") != null:
			rec = float(gun.get("_recoil_offset"))
		var flash := gun.find_child("MuzzleFlash", true, false)
		lines.append("[WEAPON]")
		lines.append("  clip=%s cooldown=%.3f recoil=%.2f flash=%s shots=%d" % [
			clip if clip != "" else "-", cd, rec,
			"on" if flash != null and (flash as CanvasItem).visible else "off", _shots])
	if show_player and is_instance_valid(player):
		var a := player.anim
		lines.append("[PLAYER] fps=%d" % Engine.get_frames_per_second())
		lines.append("  state=%d mode=%s anim=%s vel=(%.0f, %.0f) floor=%s" % [
			player.state, String(player.gun_aim.mode) if player.gun_aim != null else "?",
			String(a.current_animation) if a != null else "?",
			player.velocity.x, player.velocity.y,
			"yes" if player.is_on_floor() else "no"])
		lines.append("  shoot_button=%s shooting(logic)=%s dash=%s" % [
			"held" if Input.is_action_pressed("shoot") else "-",
			"yes" if player.get("_shooting") else "no",
			"ACTIVE" if float(player.get("_dash_t")) > 0.0 else "cd %.2f" % float(player.get("_dash_cd"))])
	_label.text = "\n".join(lines)


func _draw() -> void:
	if not enabled or player == null:
		return
	# Everything is drawn through to_local so the tiny player scale never matters.
	if show_aim and is_instance_valid(gun_aim) and gun_aim.gun_pivot != null:
		var pivot := gun_aim.gun_pivot
		var dir := gun_aim.barrel_direction()
		var mz := pivot.global_position
		if gun_aim.muzzle != null:
			mz = gun_aim.muzzle.global_position
		var mouse_w := pivot.get_global_mouse_position()
		# Shot line: where the next bullet actually goes.
		draw_line(to_local(mz), to_local(mz + dir * aim_ray_length),
				Color(1.0, 0.9, 0.25), line_width)
		# Muzzle dot + pivot->muzzle link.
		draw_circle(to_local(mz), line_width * 1.6, Color(1.0, 0.5, 0.1))
		draw_line(to_local(pivot.global_position), to_local(mz),
				Color(0.2, 0.9, 1.0), line_width * 0.5)
		# Cursor: what we are trying to hit.
		draw_circle(to_local(mouse_w), line_width * 1.6, Color(1.0, 0.15, 0.15))
		var r := line_width * 3.0
		draw_line(to_local(mouse_w + Vector2(-r, 0)), to_local(mouse_w + Vector2(r, 0)),
				Color(1.0, 0.15, 0.15), line_width * 0.5)
		draw_line(to_local(mouse_w + Vector2(0, -r)), to_local(mouse_w + Vector2(0, r)),
				Color(1.0, 0.15, 0.15), line_width * 0.5)
	if show_player:
		# Velocity arrow.
		var v := player.velocity
		if v.length() > 1.0:
			var tip := player.global_position + v.normalized() * minf(v.length() * 0.25, 600.0)
			draw_line(to_local(player.global_position), to_local(tip),
					Color(0.3, 1.0, 0.4), line_width * 0.6)
			var side := v.normalized().rotated(2.6) * line_width * 3.0
			var side2 := v.normalized().rotated(-2.6) * line_width * 3.0
			draw_line(to_local(tip), to_local(tip + side), Color(0.3, 1.0, 0.4), line_width * 0.6)
			draw_line(to_local(tip), to_local(tip + side2), Color(0.3, 1.0, 0.4), line_width * 0.6)
	if show_aim and _trail.size() > 1:
		# Mouse trail: newest is bright, oldest fades. A single stacked dot
		# while you move the mouse means the cursor data is frozen upstream.
		for i in _trail.size():
			var t := float(i) / float(_trail.size())
			draw_circle(to_local(_trail[i]), line_width * (0.5 + t),
					Color(1.0, 0.4, 1.0, 0.15 + 0.6 * t))
