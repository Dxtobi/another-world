class_name PortalGun
extends FireMode
## Portal fire mode. Lives under GunModes, so it fires from the SAME gun and
## the same trigger as everything else: select Portal mode, then shoot.
## Fires a PortalShot along the barrel; where it lands on a surface a Portal
## opens, linked to the currently selected PortalDestination.
##
## Destinations are discovered through the "portal_destination" group, so a
## second station, or pins created at runtime later, show up automatically.
## Use set_destination() from your own UI/pinning code, or the cycle action
## (only while Portal mode is selected) to step through whatever exists.

signal portal_opened(portal: Portal)
signal destination_changed(dest: PortalDestination)
signal shot_fizzled

@export_group("Setup")
@export var owner_body: Node2D ## defaults to the player (nearest ancestor with a gun_aim)
@export var muzzle: Node2D ## defaults to owner.gun_aim.muzzle, else the owner
@export var cycle_action: StringName = &"portal_next" ## optional, ignored if not in the Input Map

@export_group("Shot")
@export_range(300.0, 4000.0, 50.0, "suffix:px/s") var shot_speed := 1800.0
@export_range(100.0, 2000.0, 10.0, "suffix:px") var max_range := 900.0
@export_range(0.0, 3.0, 0.05, "suffix:s") var cooldown := 0.35
@export_flags_2d_physics var surface_mask := 1 ## what a portal can stick to
@export var blocked_groups: Array[StringName] = [&"no_portal"] ## surfaces that refuse portals

@export_group("Portals")
## Art frame hung under every portal. Greyscale is fine - the portal tints it
## through `modulate`, so both ends of a pair come out in their own colour.
## Leave empty to use the portal's built-in drawn dome instead.
@export var portal_texture: Texture2D = preload("res://sprites/portal.png")
## Two open portals link to each other: walk into one, come out the other.
## With only one open it falls back to the selected station.
@export_range(1, 4) var max_portals := 2 ## opening another closes the oldest
@export_range(16.0, 400.0, 1.0, "suffix:px") var portal_span := 96.0
@export_range(0.0, 60.0, 0.5, "suffix:s") var portal_lifetime := 7.0 ## 0 = stays until replaced
## The two ends of a pair are different colours so you can read which way the
## pair runs at a glance.
@export var color_first := Color(0.25, 0.85, 1.0)
@export var color_second := Color(1.0, 0.45, 0.25)
## Dismisses the most recently opened portal; press again for the next one.
## The lifetime above still runs regardless.
@export var cancel_action: StringName = &"portal_cancel"

var destination: PortalDestination

var _cd := 0.0
var _portals: Array[Portal] = []


func _init() -> void:
	mode_name = "Portal"
	semi_auto = true # one portal per click
	accepts_auto_fire = false # hover auto-fire must never spam portals


func _ready() -> void:
	if owner_body == null:
		var n := get_parent()
		while n != null and not (n is Node2D and n.get("gun_aim") != null):
			n = n.get_parent()
		owner_body = n as Node2D
	if owner_body == null:
		push_error("PortalGun: couldn't find the player. Assign `owner_body`.")
		set_physics_process(false)


func _physics_process(delta: float) -> void:
	_cd = maxf(_cd - delta, 0.0)
	_refresh_destination()
	_prune()
	if active and InputMap.has_action(cancel_action) \
			and Input.is_action_just_pressed(cancel_action):
		cancel_newest()
	if active and InputMap.has_action(cycle_action) and Input.is_action_just_pressed(cycle_action):
		cycle_destination(1)


## Fire along `dir` from the muzzle. GunModes calls this; AI, cutscenes or
## other input schemes can call it too.
func fire(dir: Vector2) -> bool:
	if _cd > 0.0:
		return false
	# No station required. With no destination the portal simply waits for a
	# partner to pair with, so a level without a station still works.
	var scene := get_tree().current_scene
	if scene == null or dir.length_squared() < 0.000001:
		return false
	_cd = cooldown
	var shot := PortalShot.new()
	shot.velocity = dir.normalized() * shot_speed
	shot.max_range = max_range
	shot.mask = surface_mask
	shot.color = destination.accent
	if owner_body is CollisionObject2D:
		shot.exclude = [(owner_body as CollisionObject2D).get_rid()]
	shot.landed.connect(_on_shot_landed.bind(destination))
	shot.fizzled.connect(func(): shot_fizzled.emit())
	var layer := ProjectileLayer.find(get_tree())
	if layer != null:
		layer.add_child(shot)
	else:
		scene.add_child(shot)
	shot.global_position = _muzzle_pos()
	fired.emit()
	return true


func set_destination(dest: PortalDestination) -> void:
	if dest == destination:
		return
	destination = dest
	destination_changed.emit(dest)


func cycle_destination(step: int) -> void:
	var list: Array[PortalDestination] = []
	for d in PortalDestination.all(get_tree()):
		if d.is_available():
			list.append(d)
	if list.is_empty():
		return
	var i := list.find(destination)
	set_destination(list[posmod(i + step, list.size())])


func close_all() -> void:
	for p in _portals:
		if is_instance_valid(p):
			p.close()
	_portals.clear()
	_relink()


## Manual dismiss, one portal at a time: the most recently opened goes first,
## then the next, and so on. A lone portal that gets cancelled leaves nothing
## behind rather than quietly falling back to the station.
func cancel_newest() -> void:
	_prune()
	if _portals.is_empty():
		return
	var newest: Portal = _portals.pop_back()
	if is_instance_valid(newest):
		newest.close()
	_relink()


func _prune() -> void:
	var live: Array[Portal] = []
	for p in _portals:
		if is_instance_valid(p):
			live.append(p)
	_portals = live


## (Re)build the pairings from whatever is open right now: two portals face
## each other, one on its own falls back to the station. Called whenever the
## set changes so a partner closing leaves its mate pointing somewhere valid.
func _relink() -> void:
	for p in _portals:
		if not is_instance_valid(p):
			continue
		p.exit_portal = null
		p.destination = destination
	if _portals.size() >= 2:
		for i in _portals.size():
			var a := _portals[i]
			var b := _portals[(i + 1) % _portals.size()]
			if is_instance_valid(a) and is_instance_valid(b):
				a.exit_portal = b


## Never hand out a colour that is already on screen. Slot counting looked
## right but counted portals that were still fading out, so a third shot could
## land on a colour you could already see. Asking what is actually open is the
## only version that cannot duplicate.
## The colour for a portal that is about to open.
##
## The subtle part: when the ribbon is full the OLDEST portal is about to be
## closed, so the newcomer must take THAT one's colour. Picking "any colour
## not currently in use" instead looks right and is not - the oldest is still
## in the list at this point, so the picker falls through to color_first, which
## is very often the evicted portal's own colour, and the survivor is left
## holding the same one.
func _color_for_slot() -> Color:
	_prune()
	if _portals.size() >= max_portals and not _portals.is_empty():
		var old: Portal = _portals[0]
		if is_instance_valid(old):
			return old.color
	var in_use: Array[Color] = []
	for p in _portals:
		if is_instance_valid(p):
			in_use.append(p.color)
	if not in_use.has(color_first):
		return color_first
	if not in_use.has(color_second):
		return color_second
	return color_first


func _refresh_destination() -> void:
	if is_instance_valid(destination) and destination.is_available():
		return
	for d in PortalDestination.all(get_tree()):
		if d.is_available():
			set_destination(d)
			return
	set_destination(null)


func _muzzle_pos() -> Vector2:
	if is_instance_valid(muzzle):
		return muzzle.global_position
	var ga = owner_body.get("gun_aim")
	if ga != null and is_instance_valid(ga.muzzle):
		return ga.muzzle.global_position
	return owner_body.global_position


func _on_shot_landed(point: Vector2, normal: Vector2, collider: Object, dest: PortalDestination) -> void:
	# dest may legitimately be null (no station in this level): the portal
	# opens anyway and falls back to pairing once a second one is fired.
	if is_instance_valid(dest) and not dest.is_available():
		return
	if collider is Node:
		for g in blocked_groups:
			if (collider as Node).is_in_group(g):
				shot_fizzled.emit()
				return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var p := Portal.new()
	p.span = portal_span
	p.lifetime = portal_lifetime
	p.border_texture = portal_texture
	p.color = _color_for_slot()
	scene.add_child(p)
	p.place(point + normal * 0.5, normal, dest)
	_portals.append(p)
	p.tree_exited.connect(func(): _relink())
	while _portals.size() > max_portals:
		var old: Portal = _portals.pop_front()
		if is_instance_valid(old):
			old.close()
	_relink()
	portal_opened.emit(p)
