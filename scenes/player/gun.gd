class_name Gun
extends Node2D
## Attach to the ROOT of your gun scene.
## Add a Marker2D called "Muzzle" at the tip of the barrel: bullets spawn there
## (otherwise they spawn at the gun's origin, which is the middle of the gun and
## looks like nothing came out at all). player.gd tells the gun which way to
## fire, using GunAim's barrel_direction().
##
## Firing feedback (recoil kick, muzzle flash, slide animation) is all visual:
## it never touches the aim, so the gun stays fully steerable while the trigger
## is held.

signal fired

@export var muzzle: Node2D
@export var fire_rate := 8.0 ## shots per second
@export var bullet_speed := 1600.0
@export var bullet_life := 1.2 ## seconds
@export var spread_deg := 1.0
## Layers bullets hit: 1 = world, 4 = enemies (project layer scheme in
## CommonEnemy's docs). The player is layer 2 and excluded via _ignore anyway.
@export_flags_2d_physics var bullet_mask := 5 ## physics layers bullets hit
## Nudge the spawn point along the barrel, in pixels. Useful if the marker sits
## a little inside the barrel and you want the tracer to clear the muzzle flash.
@export var spawn_offset := 0.0

@export_group("Shoot animation")
## AnimationPlayer inside the gun scene, and the clip it plays while firing.
## Your library already has "shooting" (the roller slide, looped): while shots
## keep coming it stays on, and `shoot_anim_hold` seconds after the last shot it
## goes back to "idle". If you author a one-shot clip instead (loop off), every
## shot retriggers it.
@export var shoot_anim: AnimationPlayer
@export var shoot_clip := "shooting"
## How long after the last shot the firing clip keeps playing.
@export_range(0.05, 1.0, 0.01, "suffix:s") var shoot_anim_hold := 0.18

@export_group("Recoil")
## The whole gun body kicks backwards along the barrel and springs back.
## Purely visual: the grips move with it (the hands absorb it) and the aim is
## untouched, so you keep full control while firing.
@export var recoil_enabled := true
@export_range(0.0, 80.0, 1.0, "suffix:px") var recoil_distance := 22.0 ## how far back, in gun pixels
@export_range(0.0, 1200.0, 10.0) var recoil_kick := 340.0 ## velocity added per shot
@export_range(1.0, 900.0, 1.0) var recoil_stiffness := 260.0 ## spring back strength
@export_range(0.0, 120.0, 0.5) var recoil_damping := 22.0 ## spring friction

@export_group("Muzzle flash")
## A Polygon2D named "MuzzleFlash" under the muzzle, shown for `flash_time`
## with a random tilt and size on every shot. Colors live here (not on the
## polygons): _ready pushes these two down onto MuzzleFlash / MuzzleFlashCore,
## so this is the one place you recolor the flash.
@export var flash_enabled := true
@export_range(0.01, 0.5, 0.005, "suffix:s") var flash_time := 0.055
@export_range(0.5, 4.0, 0.05) var flash_scale_min := 1.0
@export_range(0.5, 4.0, 0.05) var flash_scale_max := 1.7
@export_range(0.0, 45.0, 1.0, "suffix:°") var flash_tilt_deg := 18.0
@export var flash_color := Color(1.0, 0.82, 0.3, 1.0) ## outer star
@export var flash_core_color := Color(1.0, 1.0, 1.0, 1.0) ## inner core

@export_group("Bullet tracer")
## Plasma bolt colour: the halo and the tail take this hue, the core stays
## white-hot. Set it to whatever the gun's energy colour is.
@export var bullet_color := Color(0.45, 0.92, 1.0) ## plasma halo / tail
@export_range(1.0, 12.0, 0.5, "suffix:px") var bullet_width := 3.4
@export_range(8.0, 60.0, 1.0, "suffix:px") var bullet_tail := 26.0

@export_group("Audio")
## Player for the shot. Auto-found ("ShotSound") if left empty. Its stream is
## whatever you drop in the inspector; the gun only pulls the trigger.
@export var shot_sound: AudioStreamPlayer
## Pitch jitter per shot, so a held burst does not sound like a machine loop.
@export_range(0.0, 0.3, 0.01) var shot_pitch_jitter := 0.06

@export_group("Impact audio")
## One stream per surface. A bullet picks the closest match from what it hit:
## creature, rigid object, floor (normal facing up), wall, or water.
@export var impact_flesh: AudioStream
@export var impact_object: AudioStream
@export var impact_floor: AudioStream
@export var impact_wall: AudioStream
@export var impact_water: AudioStream
@export_range(-40.0, 6.0, 0.5) var impact_volume_db := -5.0

@export_group("Impact particles")
## Hard hits throw a small burst of glowing shards. There are no decals: the
## spray is the only mark a bolt leaves behind.
@export var burst_enabled := true

var _cooldown := 0.0
var _ignore: Array[RID] = []
var _rest_position := Vector2.ZERO ## where the artist put the gun
var _barrel_back := Vector2.LEFT ## gun-local backwards, in the parent's space
var _recoil_offset := 0.0
var _recoil_vel := 0.0
var _flash: Polygon2D
var _flash_core: Polygon2D
var _flash_timer := 0.0
var _since_shot := 999.0
var _firing_anim_active := false
var _warned := {}


func _ready() -> void:
	if muzzle == null:
		for n in find_children("*", "Node2D", true, false):
			var low := String(n.name).to_lower()
			if low.contains("muzzle") or low.contains("barrel") or low.contains("tip"):
				muzzle = n as Node2D
				break
	if muzzle == null:
		push_warning("Gun: no 'Muzzle' marker found. Bullets will spawn at the gun's "\
			+ "origin instead of the barrel tip. Add a Marker2D named 'Muzzle' at the end.")
	if shoot_anim == null:
		shoot_anim = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if shot_sound == null:
		shot_sound = find_child("ShotSound", true, false) as AudioStreamPlayer
	if shoot_anim == null or shoot_clip == &"" or not shoot_anim.has_animation(shoot_clip):
		_warn_once(shoot_clip, "Gun: shoot clip '%s' not found. Shots won't play a gun animation." % shoot_clip)
	_flash = find_child("MuzzleFlash", true, false) as Polygon2D
	if _flash != null:
		_flash.color = flash_color
		_flash.visible = false
		_flash_core = _flash.find_child("MuzzleFlashCore", true, false) as Polygon2D
		if _flash_core != null:
			_flash_core.color = flash_core_color
	elif flash_enabled:
		_warn_once("flash", "Gun: no 'MuzzleFlash' node found. Shots won't show a flash.")

	# The gun node itself may sit rotated inside its pivot; capture that once so
	# the kick always runs along the barrel no matter how the gun is hung.
	_rest_position = position
	_barrel_back = Vector2.LEFT.rotated(rotation)

	# Bullets must not hit the body that's firing them.
	var p := get_parent()
	while p != null:
		if p is CollisionObject2D:
			_ignore.append((p as CollisionObject2D).get_rid())
		p = p.get_parent()


func _warn_once(key: String, text: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning(text)


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)

	# Firing clip: stays on while shots keep coming, drops back to idle after
	# the burst so a tap of the trigger doesn't leave the rollers sliding.
	if _firing_anim_active:
		_since_shot += delta
		if _since_shot >= shoot_anim_hold and shoot_anim != null:
			_firing_anim_active = false
			if shoot_anim.has_animation(&"idle"):
				shoot_anim.play(&"idle")

	# Recoil spring: kicked per shot, settles back to the rest pose on its own.
	if recoil_enabled and (_recoil_offset != 0.0 or _recoil_vel != 0.0):
		var accel := -_recoil_offset * recoil_stiffness - _recoil_vel * recoil_damping
		_recoil_vel += accel * delta
		_recoil_offset = clampf(_recoil_offset + _recoil_vel * delta, 0.0, recoil_distance)
		if absf(_recoil_offset) < 0.01 and absf(_recoil_vel) < 0.5:
			_recoil_offset = 0.0
			_recoil_vel = 0.0
		position = _rest_position + _barrel_back * _recoil_offset

	# Muzzle flash: visible for a few frames, then gone.
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0 and is_instance_valid(_flash):
			_flash.visible = false


## `direction` is a world-space direction. If omitted, the muzzle's +X axis is used.
func shoot(direction := Vector2.ZERO) -> void:
	if _cooldown > 0.0:
		return
	_cooldown = 1.0 / fire_rate

	var src: Node2D = muzzle if muzzle != null else self
	var dir: Vector2 = direction.normalized() if direction != Vector2.ZERO else src.global_transform.x.normalized()
	dir = dir.rotated(deg_to_rad(randf_range(-spread_deg, spread_deg)))

	var b := Bullet.new()
	b.direction = dir
	b.speed = bullet_speed
	b.life = bullet_life
	b.mask = bullet_mask
	b.ignore = _ignore
	b.tint = bullet_color
	b.width = bullet_width
	b.tail_len = bullet_tail
	b.impacts = {
		"flesh": impact_flesh,
		"object": impact_object,
		"floor": impact_floor,
		"wall": impact_wall,
		"water": impact_water,
	}
	b.impact_volume_db = impact_volume_db
	b.burst_enabled = burst_enabled
	# Everything that flies lives on the projectile layer: above the player,
	# the water body and its content, below any foreground CanvasLayer.
	var layer := ProjectileLayer.find(get_tree())
	if layer != null:
		layer.add_child(b)
	else:
		get_tree().current_scene.add_child(b)
	b.global_position = src.global_position + dir * spawn_offset
	b.rotation = dir.angle()

	if recoil_enabled:
		_recoil_vel += recoil_kick
	if shot_sound != null:
		shot_sound.pitch_scale = 1.0 + randf_range(-shot_pitch_jitter, shot_pitch_jitter)
		shot_sound.play()
	_play_firing_clip()
	if _flash != null and flash_enabled:
		# Pushed every shot so inspector (or runtime) color edits apply at once.
		_flash.color = flash_color
		if _flash_core != null:
			_flash_core.color = flash_core_color
		_flash.visible = true
		_flash.rotation = deg_to_rad(randf_range(-flash_tilt_deg, flash_tilt_deg))
		var s := randf_range(flash_scale_min, flash_scale_max)
		_flash.scale = Vector2(s, s * randf_range(0.8, 1.2))
		_flash_timer = flash_time

	fired.emit()


## Keeps the firing clip on while the trigger is down. A looped clip (your
## "shooting") starts once per burst; a one-shot clip retriggers every shot.
func _play_firing_clip() -> void:
	if shoot_anim == null or shoot_clip == &"" or not shoot_anim.has_animation(shoot_clip):
		return
	_since_shot = 0.0
	if _firing_anim_active and shoot_anim.get_animation(shoot_clip).loop_mode != Animation.LOOP_NONE:
		return
	_firing_anim_active = true
	shoot_anim.play(shoot_clip)


## Plasma bolt. A glowing head with a fading energy tail, swept with a ray each
## physics step so it never tunnels. It reports the surface it hit (creature,
## object, floor, wall, water) and plays that surface's impact sound. Water is
## not solid, so it is found with a point query instead of the ray, and the
## bolt fizzles with a splash and a surface ripple.
class Bullet extends Node2D:
	const WATER_QUERY := preload("res://world/water_query.gd")

	var direction := Vector2.RIGHT
	var speed := 1600.0
	var life := 1.2
	var mask := 1
	var ignore: Array[RID] = []
	var tint := Color(0.45, 0.92, 1.0)
	var width := 3.4
	var tail_len := 26.0
	var impacts: Dictionary = {}
	var impact_volume_db := -5.0
	var burst_enabled := true
	var _age := 0.0

	func _ready() -> void:
		# Additive blending is what makes it read as light instead of a sprite.
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = mat

	func _process(delta: float) -> void:
		_age += delta
		queue_redraw()

	func _draw() -> void:
		# Tail: soft wide halo -> hot core -> white needle. The head pulses a
		# little so a held burst shimmers instead of looking like a decal.
		var pulse := 1.0 + 0.18 * sin(_age * 46.0)
		var halo := Color(tint.r, tint.g, tint.b, 0.16)
		var mid := Color(tint.r, tint.g, tint.b, 0.45)
		draw_line(Vector2(-tail_len, 0), Vector2.ZERO, halo, width * 3.4 * pulse)
		draw_line(Vector2(-tail_len * 0.72, 0), Vector2.ZERO, mid, width * 1.7)
		draw_line(Vector2(-tail_len * 0.42, 0), Vector2.ZERO,
				Color(1.0, 1.0, 1.0, 0.9), width * 0.55)
		draw_circle(Vector2.ZERO, width * 1.9 * pulse, halo)
		draw_circle(Vector2.ZERO, width * 1.05, Color(tint.r, tint.g, tint.b, 0.55))
		draw_circle(Vector2.ZERO, width * 0.55, Color(1.0, 1.0, 1.0, 0.98))

	func _physics_process(delta: float) -> void:
		life -= delta
		if life <= 0.0:
			queue_free()
			return

		# Water is an Area2D on its own layer: the ray ignores it. A point
		# query catches the moment the bolt crosses into the volume, so it
		# splashes and fizzles instead of flying on underwater.
		var volume := WATER_QUERY.at_point(get_world_2d(), global_position)
		if volume != null:
			_impact("water", global_position)
			if volume.has_method("bullet_impact"):
				volume.call("bullet_impact", global_position.x, 0.85)
			queue_free()
			return

		var from := global_position
		var to := from + direction * speed * delta
		var query := PhysicsRayQueryParameters2D.create(from, to, mask, ignore)
		var result := get_world_2d().direct_space_state.intersect_ray(query)
		if result:
			var target: Object = result.collider
			var at: Vector2 = result.position
			var kind := _hit_kind(target, result.normal)
			_impact(kind, at)
			_hard_hit(kind, at, result.normal)
			if target != null and target.has_method("take_damage"):
				# Two-arg form gets the hit position for directional knockback;
				# single-arg targets just take the damage.
				var arity := 1
				for m in target.get_method_list():
					if String(m.name) == "take_damage":
						arity = (m.args as Array).size()
						break
				if arity >= 4:
					target.take_damage(Damage.damage_for(target, at, 1), at,
							-1.0, -1.0)
				elif arity >= 2:
					target.take_damage(Damage.damage_for(target, at, 1), at)
				else:
					target.take_damage(1)
			queue_free()
			return
		global_position = to

	## Which surface sound fits this hit. Creatures first (they also take
	## damage), then loose bodies, then the world split by the face normal:
	## a surface pointing up is a floor, down is a ceiling, else a wall.
	func _hit_kind(target: Object, normal: Vector2) -> String:
		if target is Node:
			var n := target as Node
			if n.is_in_group("enemy") or n.is_in_group("enemies"):
				return "flesh"
		if target != null and target.has_method("take_damage"):
			return "flesh"
		if target is RigidBody2D:
			return "object"
		if normal.y < -0.55:
			return "floor"
		if normal.y > 0.55:
			return "ceiling"
		return "wall"

	## Hard surfaces and loose objects throw a burst of glowing shards. There is
	## no scorch decal: the spray is the whole effect, so the world never fills
	## up with marks.
	func _hard_hit(kind: String, at: Vector2, normal: Vector2) -> void:
		var hard := kind == "floor" or kind == "wall" or kind == "ceiling"
		if burst_enabled and (hard or kind == "object"):
			BulletBurst.spawn(get_tree(), at, normal, kind, 1.0)

	## One-shot positional sound at the impact point. Lives in the scene, not
	## on the bolt, so it survives the bolt freeing itself.
	func _impact(kind: String, at: Vector2) -> void:
		var stream: AudioStream = impacts.get(kind)
		if stream == null:
			stream = impacts.get("wall") ## ceiling reuses the wall sample
		if stream == null:
			return
		var p := AudioStreamPlayer2D.new()
		p.stream = stream
		p.volume_db = impact_volume_db
		p.pitch_scale = randf_range(0.94, 1.06)
		p.max_distance = 1600.0
		get_tree().current_scene.add_child(p)
		p.global_position = at
		p.finished.connect(p.queue_free)
		p.play()
