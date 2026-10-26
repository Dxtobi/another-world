class_name Crosshair
extends Node2D
## Screen-space crosshair that replaces the OS mouse pointer.
##
## Add it as a child of Player. It hides the OS cursor, draws `texture`
## (your target-mouse art) glued to the cursor, and every physics frame checks
## what is under it: red over anything in `hostile_group`, green otherwise.
## `locked` / `locked_target` are the hook the auto-fire setting reads, so the
## gun can start shooting the moment the crosshair sits on an enemy.

@export var enabled := true:
	set(value):
		enabled = value
		if is_node_ready():
			_apply_visibility()
			_apply_mouse_mode()
@export var hide_os_cursor := false ## hide the real pointer, draw the sprite instead
@export var confine_cursor := true ## keep the pointer inside the game window
@export var texture: Texture2D = preload("res://assets/gun/target-mouse-replace.png")
@export_range(0.2, 4.0, 0.05) var crosshair_scale := 1.0
@export var neutral_color := Color(0.35, 1.0, 0.35) ## over nothing hostile (green)
@export var hostile_color := Color(1.0, 0.25, 0.25) ## over an enemy (red)
@export_range(1.0, 2.0, 0.05) var lock_scale := 1.2 ## size pop while locked on

@export_group("Target scan")
@export var hostile_group := "enemy" ## put enemy roots in this group
@export_flags_2d_physics var scan_mask := 5 ## 1 = world, 4 = enemies
@export var scan_bodies := true
@export var scan_areas := true

@export_group("Auto fire")
## When on, the crosshair itself pulls the trigger: the player fires without
## you holding shoot. With `auto_fire_needs_lock` it only fires while red.
@export var auto_fire := false
@export var auto_fire_needs_lock := true

var player: Player
var locked := false
var locked_target: Node
var mouse_screen := Vector2.ZERO
var mouse_world := Vector2.ZERO

var _sprite: Sprite2D
var _hid_cursor := false


func _ready() -> void:
	var root := get_parent()
	if root is Player:
		player = root as Player
	else:
		push_warning("Crosshair: parent is not the Player. Hover scan needs the player ref.")

	var layer := CanvasLayer.new()
	layer.name = "CrosshairLayer"
	layer.layer = 200
	add_child(layer)
	_sprite = Sprite2D.new()
	_sprite.name = "CrosshairSprite"
	_sprite.texture = texture
	_sprite.centered = true
	layer.add_child(_sprite)
	if texture == null:
		push_warning("Crosshair: no texture assigned.")

	_apply_visibility()
	_apply_mouse_mode()


func set_enabled(value: bool) -> void:
	enabled = value
	_apply_visibility()
	_apply_mouse_mode()


func _apply_visibility() -> void:
	if _sprite != null:
		_sprite.visible = enabled


func _apply_mouse_mode() -> void:
	if enabled and hide_os_cursor:
		Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN if confine_cursor \
				else Input.MOUSE_MODE_HIDDEN
		_hid_cursor = true
	elif _hid_cursor:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_hid_cursor = false


func _exit_tree() -> void:
	if _hid_cursor:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_hid_cursor = false


## What the player asks every physics frame: should the gun fire on its own?
func want_fire() -> bool:
	if not enabled or not auto_fire:
		return false
	return locked if auto_fire_needs_lock else true


func _physics_process(_delta: float) -> void:
	if not enabled or player == null:
		locked = false
		locked_target = null
		return
	mouse_screen = get_viewport().get_mouse_position()
	mouse_world = get_global_mouse_position()

	var query := PhysicsPointQueryParameters2D.new()
	query.position = mouse_world
	query.collision_mask = scan_mask
	query.collide_with_bodies = scan_bodies
	query.collide_with_areas = scan_areas
	query.exclude = [player.get_rid()]

	locked = false
	locked_target = null
	for hit in get_world_2d().direct_space_state.intersect_point(query):
		var node := hit.collider as Node if hit.collider is Node else null
		var up := node
		var depth := 0
		while up != null and depth < 4:
			if up.is_in_group(hostile_group):
				locked = true
				locked_target = node
				break
			up = up.get_parent()
			depth += 1
		if locked:
			break


func _process(_delta: float) -> void:
	if _sprite == null or not enabled:
		return
	_sprite.position = get_viewport().get_mouse_position()
	_sprite.modulate = hostile_color if locked else neutral_color
	var s := crosshair_scale * (lock_scale if locked else 1.0)
	_sprite.scale = Vector2(s, s)
