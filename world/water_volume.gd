extends Area2D
## Non-solid water volume built by world/platform.gd for swamp_water.
##
## The platform's painted polygon is copied here as an Area2D shape. The
## platform's own StaticBody2D collision is disabled for water, so the player
## and creatures fall/wade into the volume instead of walking on top of it.
##
## Physics queries use WaterQuery (a point query on WATER_LAYER), so no sensor
## node is needed on the player or the creatures. This node additionally
## watches CharacterBody2D/RigidBody2D contacts for water splashes and to lift
## submerged characters above the opaque water surface (the cutaway view).
## Underwater scenery: any CanvasItem either a **direct child of this node**
## or in the **"water_content" group**, whose position falls inside this
## volume, is treated as underwater content. While the cutaway view is active
## it is lifted above the water polygon and washed with the same depth
## gradient (underwater_content.gdshader): dark silhouettes sinking into the
## water like the design reference. Props with an empty material get the tint
## material automatically; props with their own material should use that
## shader themselves, or be left behind the opaque water.

const WATER_LAYER := 1 << 4
const SPLASH_SCRIPT := preload("res://world/water_splash.gd")
const CONTENT_SHADER := preload("res://world/underwater_content.gdshader")
## Bodies disturb the surface continuously while inside: ripples repeat every
## `interval` seconds, speeding up and getting stronger with movement.
const RIPPLE_MIN_SPEED := 18.0
## Fallback vertical extent for bodies that don't declare `water_half_height`.
const DEFAULT_HALF_HEIGHT := 40.0
## Disturbance sources uploaded to the surface shader: (local x, age, strength).
const WAVE_SLOTS := 8
const WAVE_LIFE := 2.4
## The surface deformation is drawn in world px, so the shader scales it by the
## inverse camera zoom. Cap that so a very far camera cannot turn the water into
## a sawtooth.
const MAX_WAVE_ZOOM := 6.0

## World Y of the visible surface (the flat waterline).
var surface_y := 0.0
## Cutaway refraction: while the player is submerged the water body draws above
## them, so it must let the screen behind it through. 0 = keep the preset's
## opaque water; 1 = fully show the world (and the swimmer) through the tint.
@export_range(0.0, 1.0, 0.01) var underwater_refract := 0.9
## Depth (px) over which refraction ramps in. Kept tiny so the swimmer shows
## immediately below the surface instead of only in the deep.
@export_range(0.0, 400.0, 1.0, "suffix:px") var underwater_refract_depth := 2.0
## How hard the deep colour absorbs the refracted swimmer (0 = clear, 1 = deep).
@export_range(0.0, 1.0, 0.01) var underwater_refract_absorb := 0.6
## Z the water body rises to while the cutaway is active: above the player and
## any other body in the water, so the water truly covers them.
@export var underwater_draw_z := 6
## World Y of the deepest polygon point.
var bottom_y := 0.0
var water_depth := 0.0
## Underwater content is managed only for props inside this world rect.
var content_rect := Rect2()
## Set by the platform so the water shader can flatten into its underwater view.
var surface_material: ShaderMaterial
## The water polygon, used to convert world x into shader-local x for waves.
var surface_node: Node2D

var _shape: CollisionPolygon2D
var _last_origin := Vector2(INF, INF)
var _saved_z: Dictionary = {}
## Bodies currently overlapping the area. Creature controllers ask this instead
## of guessing where their feet are, which keeps a body standing on dry ground
## above the buried part of the water polygon from counting as submerged.
var _bodies: Dictionary = {}
## Per-body countdown to the next continuous surface ripple.
var _ripple_t: Dictionary = {}
## Live disturbance sources for the surface deformation: [local_x, age, strength].
var _waves: Array = []
var _wave_img: Image
var _wave_tex: ImageTexture
## Last wave_count pushed to the shader, so the idle case is a no-op.
var _wave_count_sent := -1.0
## Lifted underwater scenery: instance_id -> {"material", "z", "z_rel"} while
## the cutaway view is active.
var _content_saved: Dictionary = {}
var _underwater_amount := 0.0
## Base refraction uniforms captured the first time the cutaway turns on, so
## the air view always restores exactly what the preset authored.
var _refract_base: Dictionary = {}
## Saved draw order of the water polygon while it is lifted over the player.
var _surface_z_saved := 0
var _surface_z_saved_rel := true
var _surface_z_lifted := false


func _ready() -> void:
	add_to_group("water")
	collision_layer = WATER_LAYER
	# Detect player / enemies / movable props for splash + cutaway z-order.
	# (The direct point queries do not depend on monitoring.)
	collision_mask = 1 | 2 | 4
	monitoring = true
	monitorable = true
	_shape = get_node_or_null("WaterShape") as CollisionPolygon2D
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)
	refresh_bounds()


func is_water_volume() -> bool:
	return true


## True while `body`'s own collision shape overlaps this volume. The area is
## monitored, so this works for tall creatures whose origin sits above the
## waterline while their legs are already submerged.
func has_water_body(body: Node) -> bool:
	if body == null:
		return false
	var id := body.get_instance_id()
	if not _bodies.has(id):
		return false
	return is_instance_valid(_bodies[id])


func refresh_bounds(poly: PackedVector2Array = PackedVector2Array()) -> void:
	if _shape == null:
		_shape = get_node_or_null("WaterShape") as CollisionPolygon2D
	if _shape == null:
		return
	if not poly.is_empty():
		_shape.polygon = poly
	var points := _shape.polygon
	if points.is_empty():
		return
	var lo := points[0].y
	var hi := points[0].y
	for p in points:
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
	surface_y = global_position.y + lo
	bottom_y = global_position.y + hi
	water_depth = maxf(bottom_y - surface_y, 0.0)
	# World-space x extent too, so underwater content must sit inside the
	# volume's horizontal reach as well (banks can be deeper than visible).
	var min_x := points[0].x
	var max_x := points[0].x
	for p in points:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
	content_rect = Rect2(global_position.x + min_x, surface_y, max_x - min_x, water_depth)
	# Give the underwater cutaway its real vertical extent: the gradient in the
	# water shader starts at the waterline and darkens until this bottom, so the
	# tint is bounded by the actual water shape, not a screen-wide wash.
	if surface_material != null and surface_node != null:
		var top := surface_node.to_local(_shape.to_global(Vector2(0.0, lo)))
		var bottom := surface_node.to_local(_shape.to_global(Vector2(0.0, hi)))
		surface_material.set_shader_parameter(
				"underwater_max_depth", maxf(bottom.y - top.y, 1.0))
	if _underwater_amount > 0.01:
		_apply_content(_underwater_amount)
	_last_origin = global_position


func _process(delta: float) -> void:
	# Platforms can be moved/scaled by level scripting; keep the world-space
	# surface and bottom in sync without rebuilding the shape every frame.
	if global_position != _last_origin:
		refresh_bounds()
	_update_waves(delta)


func _physics_process(delta: float) -> void:
	# Continuous surface disturbance: everything physically inside the volume
	# emits faint wake ripples on a speed-scaled cadence (not just enter/exit).
	for id in _bodies.keys():
		if not _bodies.has(id):
			continue
		var body = _bodies[id]
		if not is_instance_valid(body):
			_bodies.erase(id)
			_ripple_t.erase(id)
			continue
		if not (body is CharacterBody2D or body is RigidBody2D):
			continue
		if not _touches_surface(body):
			continue
		var speed := 0.0
		if body is CharacterBody2D:
			speed = (body as CharacterBody2D).velocity.length()
		else:
			speed = (body as RigidBody2D).linear_velocity.length()

		var moving := speed > RIPPLE_MIN_SPEED
		var t := clampf(speed / 300.0, 0.0, 1.0)
		var interval := lerpf(0.5, 0.09, t) if moving else 1.1
		var strength := lerpf(0.3, 0.9, t) if moving else 0.25

		_ripple_t[id] = float(_ripple_t.get(id, 0.0)) - delta
		if _ripple_t[id] <= 0.0:
			_ripple_t[id] = interval
			_spawn_ripple(body.global_position.x, strength)


## True when the body's vertical extent crosses the waterline, so tall
## creatures with submerged legs ripple but fully sunk bodies don't.
func _touches_surface(body: Node2D) -> bool:
	var half: float = float(body.get_meta("water_half_height", DEFAULT_HALF_HEIGHT))
	var y := body.global_position.y
	return y - half - 12.0 <= surface_y and surface_y <= y + half + 12.0


func _spawn_ripple(at_x: float, strength: float) -> void:
	# The waterline itself deforms even if the ring sprite pool is full.
	add_surface_wave(at_x, strength)
	if SPLASH_SCRIPT.is_full():
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var ripple := SPLASH_SCRIPT.new()
	scene.add_child(ripple)
	ripple.global_position = Vector2(at_x, surface_y)
	ripple.start(strength, 0.7, false)


## A projectile punched the water: a small crest, droplets and a travelling
## ring at the surface. Bullets call this when their point query finds the
## volume (water is not solid, so the ray never reports it).
func bullet_impact(world_x: float, strength: float = 0.8) -> void:
	_spawn_splash(world_x, clampf(strength, 0.2, 1.6), 0.85)


## Queues one disturbance for the surface shader: a ring that travels outward
## and deforms the waterline. Called by splashes here and by the player.
func add_surface_wave(world_x: float, strength: float) -> void:
	if surface_material == null:
		return
	var x := world_x - global_position.x
	if is_instance_valid(surface_node):
		x = surface_node.to_local(Vector2(world_x, surface_y)).x
	# Two systems can fire for the same event (the player's own splash and the
	# volume's body loop), so merge near-identical sources instead of spending
	# two of the eight slots on one splash.
	for wave in _waves:
		if absf(float(wave[0]) - x) < 12.0 and float(wave[1]) < 0.08:
			wave[2] = maxf(float(wave[2]), strength)
			return
	_waves.append([x, 0.0, clampf(strength, 0.0, 2.0)])
	while _waves.size() > WAVE_SLOTS:
		_waves.pop_front()


func _update_waves(delta: float) -> void:
	if surface_material == null:
		return
	# Compensate for camera zoom: the deformation is authored in world px, and
	# the calm line can only sit `surface_baseline` px below the mesh edge, so
	# at a far zoom it would collapse to about a screen pixel without this.
	var cam := get_viewport().get_camera_2d()
	var zoom := cam.zoom.x if cam != null else 1.0
	surface_material.set_shader_parameter("surface_wave_zoom",
			clampf(1.0 / maxf(zoom, 0.01), 1.0, MAX_WAVE_ZOOM))
	for i in range(_waves.size() - 1, -1, -1):
		_waves[i][1] = float(_waves[i][1]) + delta
		if float(_waves[i][1]) >= WAVE_LIFE:
			_waves.remove_at(i)
	if _waves.is_empty():
		# Stop the shader looping over stale texels once the last ring dies.
		if _wave_count_sent != 0.0:
			_wave_count_sent = 0.0
			surface_material.set_shader_parameter("wave_count", 0.0)
		return
	_upload_waves()


func _upload_waves() -> void:
	if surface_material == null or _waves.is_empty():
		return
	if _wave_img == null:
		_wave_img = Image.create_empty(WAVE_SLOTS, 1, false, Image.FORMAT_RGBAF)
	var count := mini(_waves.size(), WAVE_SLOTS)
	for i in WAVE_SLOTS:
		var value := Color(0.0, 0.0, 0.0, 0.0)
		if i < count:
			var wave: Array = _waves[i]
			value = Color(float(wave[0]), float(wave[1]), float(wave[2]), 1.0)
		_wave_img.set_pixel(i, 0, value)
	if _wave_tex == null:
		_wave_tex = ImageTexture.create_from_image(_wave_img)
		surface_material.set_shader_parameter("wave_tex", _wave_tex)
	else:
		_wave_tex.update(_wave_img)
	_wave_count_sent = float(count)
	surface_material.set_shader_parameter("wave_count", _wave_count_sent)


func set_surface_material(mat: ShaderMaterial, node: Node2D = null) -> void:
	surface_material = mat
	if node != null:
		surface_node = node
	if surface_material != null:
		surface_material.set_shader_parameter("underwater_amount", 0.0)


## 0 = normal surface mirror, 1 = underwater cutaway (gradient body, lifted
## silhouette scenery). The fade is set by the player each frame.
func set_underwater(amount: float) -> void:
	amount = clampf(amount, 0.0, 1.0)
	var was := _underwater_amount
	_underwater_amount = amount
	if surface_material != null:
		surface_material.set_shader_parameter("underwater_amount", amount)
		_push_underwater_refraction(amount)
	_set_water_draw_z(amount > 0.5)
	if amount > 0.01:
		_apply_content(amount)
	elif was > 0.01:
		_clear_content()


## Raises the water polygon above the player while the cutaway is active, so
## the water is drawn over a submerged body instead of under it.
func _set_water_draw_z(over: bool) -> void:
	if not (surface_node is CanvasItem):
		return
	var ci := surface_node as CanvasItem
	if over == _surface_z_lifted:
		return
	if over:
		_surface_z_saved = ci.z_index
		_surface_z_saved_rel = ci.z_as_relative
		ci.z_as_relative = false
		ci.z_index = underwater_draw_z
	else:
		ci.z_index = _surface_z_saved
		ci.z_as_relative = _surface_z_saved_rel
	_surface_z_lifted = over


## The player is drawn UNDER the water body while submerged, so the polygon has
## to let what is behind it show through. Refraction samples the screen (which
## already holds the swimmer) and absorbs it toward the deep tone with depth,
## so the body reads as a silhouette inside the water instead of on top of it.
func _push_underwater_refraction(amount: float) -> void:
	if surface_material == null:
		return
	if _refract_base.is_empty():
		_refract_base = {
			"amount": _uniform_or(surface_material, "refract_amount", 0.0),
			"depth": _uniform_or(surface_material, "refract_depth", 120.0),
			"absorb": _uniform_or(surface_material, "refract_absorb", 0.55),
		}
	var base_amount := float(_refract_base["amount"])
	var want_amount := lerpf(base_amount, underwater_refract, amount)
	surface_material.set_shader_parameter("refract_amount", want_amount)
	# A short depth ramp means the swimmer shows right under the surface and
	# stays readable as they dive; absorption is what darkens them with depth.
	surface_material.set_shader_parameter("refract_depth",
			lerpf(float(_refract_base["depth"]), underwater_refract_depth, amount))
	surface_material.set_shader_parameter("refract_absorb",
			lerpf(float(_refract_base["absorb"]), underwater_refract_absorb, amount))


func _uniform_or(mat: ShaderMaterial, name: String, fallback: float) -> float:
	var v = mat.get_shader_parameter(name)
	return float(v) if v != null else fallback


## Underwater scenery: direct children plus "water_content" group nodes inside
## this volume's rect. While the cutaway is active each lifted above the water
## polygon and washed with this volume's depth gradient, so things in the water
## read as sinking silhouettes instead of floating flat colours.
func _apply_content(amount: float) -> void:
	for ci in _content_nodes():
		var id: int = ci.get_instance_id()
		if not _content_saved.has(id):
			_content_saved[id] = {
				"material": ci.material,
				"z": ci.z_index,
				"z_rel": ci.z_as_relative,
			}
			# Content sits above the lifted water body so the silhouettes stay
			# readable; the swimmer is behind the water, these are in front.
			ci.z_as_relative = false
			ci.z_index = underwater_draw_z + 1
		if ci.material == null:
			var mat := ShaderMaterial.new()
			mat.shader = CONTENT_SHADER
			_push_content_uniforms(mat)
			ci.material = mat
		var m := ci.material as ShaderMaterial
		if m != null and m.shader == CONTENT_SHADER:
			m.set_shader_parameter("reveal", clampf(amount * 1.25, 0.0, 1.0))
			_push_content_uniforms(m, true)


func _clear_content() -> void:
	for id in _content_saved:
		var ci := instance_from_id(id) as CanvasItem
		if is_instance_valid(ci):
			var saved: Dictionary = _content_saved[id]
			ci.material = saved["material"]
			ci.z_as_relative = saved["z_rel"]
			ci.z_index = int(saved["z"])
	_content_saved.clear()


func _content_nodes() -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group("water_content"):
		if n is CanvasItem and not (n is CollisionPolygon2D) and not (n is CollisionShape2D) \
				and _inside_content(n as CanvasItem):
			out.append(n)
	for n in get_children():
		if n is CanvasItem and not (n is CollisionPolygon2D) and not (n is CollisionShape2D) \
				and _inside_content(n as CanvasItem):
			out.append(n)
	return out


func _inside_content(ci: CanvasItem) -> bool:
	if not ci.visible:
		return false
	var gp: Vector2 = ci.global_position
	# A whole-subtree prop (anchored at its top-left) may hold its centre well
	# above its origin; accept anything whose centre or a probe below it bites.
	var probes := [gp, gp + Vector2(0.0, 60.0), gp + Vector2(0.0, 180.0)]
	for p in probes:
		if content_rect.has_point(p):
			return true
	return content_rect.position.x <= gp.x and gp.x <= content_rect.position.x + content_rect.size.x \
			and gp.y <= content_rect.position.y + content_rect.size.y


func _push_content_uniforms(mat: ShaderMaterial, skip_depth: bool = false) -> void:
	if not skip_depth:
		mat.set_shader_parameter("surface_y", surface_y)
		mat.set_shader_parameter("max_depth", maxf(water_depth, 1.0))
		if surface_material != null:
			var shallow = surface_material.get_shader_parameter("col_water_shallow")
			var deep = surface_material.get_shader_parameter("col_water_deep")
			if shallow is Color:
				mat.set_shader_parameter("gradient_top", shallow)
			if deep is Color:
				var bottom := (deep as Color)
				# Match the body shader's deep end (col_water_deep * 0.7).
				bottom = Color(bottom.r * 0.7, bottom.g * 0.7, bottom.b * 0.7, 1.0)
				mat.set_shader_parameter("gradient_bottom", bottom)


func _exit_tree() -> void:
	_clear_content()


func _on_body_entered(body: Node2D) -> void:
	if body == null:
		return
	_bodies[body.get_instance_id()] = body
	# Only moving bodies matter here; the land and the water body itself also
	# overlap the area in some layouts.
	if not (body is CharacterBody2D or body is RigidBody2D):
		return
	var is_player := body.is_in_group("player")
	if not is_player and not _saved_z.has(body.get_instance_id()):
		# Lift characters above the opaque surface so a submerged body reads
		# as a cutaway instead of disappearing behind the water fill.
		_saved_z[body.get_instance_id()] = body.z_index
		body.z_index = 5
	if not is_player:
		_spawn_splash(body.global_position.x, _impact_strength(body), 0.85)


func _on_body_exited(body: Node2D) -> void:
	if body == null:
		return
	var id := body.get_instance_id()
	_bodies.erase(id)
	_ripple_t.erase(id)
	if _saved_z.has(id):
		if is_instance_valid(body):
			body.z_index = int(_saved_z[id])
		_saved_z.erase(id)
	if body is CharacterBody2D or body is RigidBody2D:
		if not body.is_in_group("player"):
			_spawn_splash(body.global_position.x, 0.45, 0.55)


func _impact_strength(body: Node2D) -> float:
	var speed := 0.0
	if body is CharacterBody2D:
		speed = (body as CharacterBody2D).velocity.length()
	elif body is RigidBody2D:
		speed = (body as RigidBody2D).linear_velocity.length()
	return clampf(speed / 450.0, 0.45, 1.6)


func _spawn_splash(at_x: float, strength: float, alpha: float) -> void:
	add_surface_wave(at_x, strength)
	var scene := get_tree().current_scene
	if scene == null:
		return
	var splash := SPLASH_SCRIPT.new()
	scene.add_child(splash)
	splash.global_position = Vector2(at_x, surface_y)
	# The water polygon is lifted over submerged bodies, so crests have to sit
	# above it too or the surface would swallow its own splash.
	if _surface_z_lifted and splash is CanvasItem:
		(splash as CanvasItem).z_as_relative = false
		(splash as CanvasItem).z_index = underwater_draw_z + 2
	splash.start(strength, alpha)
