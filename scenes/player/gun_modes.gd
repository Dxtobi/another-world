class_name GunModes
extends Node
## The gun's brain for "what do I fire right now". Child of the player, with
## FireMode nodes as ITS children:
##
##   Player
##   └─ GunModes            (this script)
##      ├─ Bullets          (bullet_fire_mode.gd)
##      └─ Portal           (portal_gun.gd)
##
## The player only calls pull() once per physics frame. Everything else
## (switching, unlocking, HUD) talks to this node.

signal mode_changed(mode: FireMode)
signal mode_unlocked(mode: FireMode)

@export var next_action: StringName = &"weapon_next" ## optional, ignored if not in the Input Map
@export var prev_action: StringName = &"weapon_prev"

var modes: Array[FireMode] = []
var current: FireMode

var _was_held := false


func _ready() -> void:
	for c in get_children():
		if c is FireMode:
			modes.append(c)
	for m in modes:
		if m.unlocked:
			select(m)
			break
	if current == null:
		push_warning("GunModes: no unlocked FireMode children found.")


func _physics_process(_delta: float) -> void:
	if InputMap.has_action(next_action) and Input.is_action_just_pressed(next_action):
		cycle(1)
	if InputMap.has_action(prev_action) and Input.is_action_just_pressed(prev_action):
		cycle(-1)


## Call every physics frame with the trigger state.
## `auto_trigger` = shoot button OR crosshair auto-fire (already aim-gated).
## `manual_trigger` = the shoot button alone (aim-gated).
func pull(auto_trigger: bool, manual_trigger: bool, dir: Vector2) -> void:
	if current == null:
		return
	var held := auto_trigger if current.accepts_auto_fire else manual_trigger
	var edge := held and not _was_held
	_was_held = held
	if not held:
		return
	if current.semi_auto and not edge:
		return
	current.fire(dir)


func select(mode: FireMode) -> void:
	if mode == null or not mode.unlocked or mode == current:
		return
	if current != null:
		current.active = false
		current.on_deselected()
	current = mode
	current.active = true
	current.on_selected()
	_was_held = true # holding fire while switching must not shoot the new mode
	mode_changed.emit(current)


func select_by_name(mode_name: String) -> bool:
	for m in modes:
		if m.mode_name == mode_name and m.unlocked:
			select(m)
			return true
	return false


func cycle(step: int) -> void:
	var avail: Array[FireMode] = []
	for m in modes:
		if m.unlocked:
			avail.append(m)
	if avail.size() <= 1:
		return
	var i := avail.find(current)
	select(avail[posmod(i + step, avail.size())])


## Progression hook: call when the player picks the ability up.
func unlock_mode(mode_name: String, and_select := false) -> bool:
	for m in modes:
		if m.mode_name == mode_name:
			var was := m.unlocked
			m.unlocked = true
			if not was:
				mode_unlocked.emit(m)
			if and_select:
				select(m)
			return true
	return false
