class_name CommonEnemy
extends CharacterBody2D

const WaterQuery := preload("res://world/water_query.gd")
## Simple melee enemy: walks at the player while playing "moving", swings
## "attack" in range, and plays "hit" with a white-hot flash whenever
## take_damage lands. Damage to the player comes from the "can-hurt-player"
## Area2D(s) touching them (with a cooldown), not from the swing timer.
##
## COLLISION LAYERS (project convention, all pass-through by design):
##   1 = world (floors, walls)   2 = player   4 = enemies
## Enemies sit on layer 4 scanning only 1: they walk the world but never
## hard-block the player (or each other) — contact damage is via Area2D.
## Keep it that way or the bodies wedge into each other and pop free.
##
## Death is simulated while `debug_no_kill` is on: the enemy drops, holds the
## hit pose as a corpse for `simulated_death_time`, then gets back up at full
## health. Turn it off for real death (frees the node).

signal died
signal revived
signal damaged(amount: int)

@export_group("Nodes")
@export var anim: AnimationPlayer
@export var body: Node2D ## everything visual hangs under here; flashed on hit
@export var hurt_area: Area2D ## main "can-hurt-player"; every such area counts
@export var ray_front: RayCast2D ## "front": wall feeler ahead (stops advance into walls)
@export var ray_back: RayCast2D ## "back": wall feeler behind (stops retreat into walls)

@export_group("Animation names")
@export var anim_moving := "moving"
@export var anim_attack := "attack"
@export var anim_ranged := "long-range-attack"
@export var anim_hit := "hit"
@export var anim_idle := "idle" ## played standing still; falls back to "moving" until you add the clip

@export_group("Health")
@export_range(1, 20) var max_health := 3
## Heavier enemies shrug off shoves: incoming force knockback is divided by
## this. 1.0 = standard grunt, 3.0+ = beast that barely budges.
@export_range(0.1, 10.0, 0.1) var power_level := 1.0
@export_range(0.0, 900.0, 10.0, "suffix:px/s") var hit_knockback := 260.0
@export_range(0.0, 1.0, 0.05, "suffix:s") var hit_stun := 0.3 ## can't act right after a hit

@export_group("Attack")
@export_range(0.0, 600.0, 5.0, "suffix:px/s") var move_speed := 120.0
## Water slows ordinary enemies; creatures in the "water_creature" group keep
## their full speed.
@export_range(0.1, 1.0, 0.05) var water_speed_mult := 0.55
@export_range(0.0, 400.0, 5.0, "suffix:px") var attack_range := 70.0
@export_range(0.0, 400.0, 5.0, "suffix:px") var attack_height := 120.0
@export_range(0.1, 5.0, 0.05, "suffix:s") var attack_cooldown := 1.2

@export_group("Spacing")
## How it positions itself. It advances while the player is further than
## `hold_range`, plants its feet inside it, and backs off inside
## `personal_space` — so it never crowds into you while the hand can still
## reach. The swing itself still triggers on `attack_range`.
@export_range(0.0, 600.0, 5.0, "suffix:px") var hold_range := 0.0 ## 0 = same as attack_range
@export_range(0.0, 400.0, 5.0, "suffix:px") var personal_space := 35.0
@export_range(0.0, 600.0, 5.0, "suffix:px/s") var retreat_speed := 70.0
## The hold has no idle clip yet, so "moving" plays slowed down: a menacing
## shuffle instead of running in place. Unused once `anim_idle` exists.
@export_range(0.1, 1.0, 0.05) var hold_anim_speed := 0.45

@export_group("Senses")
## Walls closer than this stop advance/retreat (world px). The rays only ever
## stop on walls — touching the player never counts, so they can't block the
## chase. Ray lengths live on the RayCast2D nodes in enemy-local px.
@export_range(0.0, 400.0, 5.0, "suffix:px") var wall_stop_range := 60.0

@export_group("Contact damage")
## Touching the hurt Area2D hurts the player, at most this often. The swing
## animation is the visual; this is the actual teeth.
@export_range(0.1, 3.0, 0.05, "suffix:s") var contact_cooldown := 1.0

@export_group("Ranged")
## Lobbed poison attack (enemy 2). Off unless enabled: melee-only enemies never
## touch any of this. The glob flies an arc to where the player stands at the
## fire moment, with a red ring warning where it will land.
@export var ranged_enabled := false
@export_range(0.0, 900.0, 10.0, "suffix:px") var ranged_range := 520.0
@export_range(0.0, 900.0, 10.0, "suffix:px") var ranged_height := 300.0
@export_range(0.5, 8.0, 0.1, "suffix:s") var ranged_cooldown := 2.6
@export_range(0.0, 1.5, 0.05, "suffix:s") var ranged_fire_delay := 0.45 ## glob leaves this far into the cast
@export var ranged_muzzle: Marker2D ## auto-found ("slime"/"projectile"/"muzzle"/"mouth")
@export var slime_scene: PackedScene = preload("res://scenes/common-enemies/slime_shot.tscn")
@export_range(0.3, 2.5, 0.05, "suffix:s") var slime_flight := 0.9 ## arc time to the target

@export_group("Critical hits")
## The "critical-hit-area" (usually the head): hits landing inside it deal
## `crit_mult` instead. Only rect / circle / capsule shapes are tested.
@export var crit_area_name := "critical-hit-area"
@export_range(1.0, 10.0, 0.25, "suffix:x") var crit_mult := 2.0

@export_group("Facing")
@export var art_faces_right := true ## turn off if your sprite looks left at scale.x = 1

@export_group("Hit flash")
@export var hit_flash_enabled := true
@export var hit_flash_color := Color(4.0, 4.0, 4.0) ## overbright = white-hot blink
@export_range(0.02, 0.5, 0.01, "suffix:s") var hit_flash_time := 0.08

@export_group("Debug death")
@export var debug_no_kill := true ## simulate death instead of freeing the node
@export_range(0.1, 1.5, 0.05, "suffix:s") var death_time := 0.35 ## collapse beat on the hit pose
@export_range(1.0, 30.0, 0.5, "suffix:s") var simulated_death_time := 5.0

var health: int
var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

var _player: Node2D
var _attack_cd := 0.0
var _swing := 0.0 ## seconds left in the attack swing (visual lock)
var _ranged_t := 0.0 ## seconds left in the ranged cast
var _ranged_cd := 0.0
var _ranged_fired := false
var _stun := 0.0
var _contact_cd := 0.0
var _dying := false
var _death := 0.0 ## collapse beat
var _corpse := 0.0 ## lying timer (debug mode only)
var _flash := 0.0
var _base_modulate := Color.WHITE
var _cur := &""
var crit_area: Area2D
## Every "can-hurt-player" Area2D: all of them deal contact damage, all go
## quiet on death. (The export above is just the first / an explicit one.)
var _hurt_areas: Array[Area2D] = []
## Bullet rays ignore Area2Ds, so without this the head zone could never be
## hit: a small body hitbox that rides the crit zone every frame. The ray stops
## on it, and is_critical_hit makes the exact crit / graze call.
var _head_col: CollisionShape2D
var _crit_shape: CollisionShape2D


func _ready() -> void:
	health = max_health
	if anim == null:
		anim = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if body == null:
		body = get_node_or_null("body") as Node2D
		if body == null:
			body = find_child("body", true, false) as Node2D
	if hurt_area == null:
		hurt_area = find_child("can-hurt-player", true, false) as Area2D
	_hurt_areas.clear()
	if hurt_area != null:
		_hurt_areas.append(hurt_area)
	for n in find_children("can-hurt-player", "Area2D", true, false):
		var area := n as Area2D
		if area != null and not _hurt_areas.has(area):
			_hurt_areas.append(area)
	if _hurt_areas.is_empty():
		push_warning("CommonEnemy: no 'can-hurt-player' Area2D found, contact damage disabled.")
	if crit_area == null and crit_area_name != &"":
		crit_area = find_child(crit_area_name, true, false) as Area2D
	_create_head_hitbox()
	if ray_front == null:
		ray_front = find_child("front", true, false) as RayCast2D
	if ray_back == null:
		ray_back = find_child("back", true, false) as RayCast2D
	if ranged_muzzle == null and ranged_enabled:
		for word in ["slime", "projectile", "muzzle", "mouth"]:
			ranged_muzzle = _find_marker(word)
			if ranged_muzzle != null:
				break
		if ranged_muzzle == null:
			push_warning("CommonEnemy: ranged is on but no muzzle marker found.")
	# The rays start inside our own capsule: without these they hit ourselves.
	for ray in [ray_front, ray_back]:
		if ray != null:
			ray.add_exception_rid(get_rid())
			for area in _hurt_areas:
				ray.add_exception_rid(area.get_rid())
	if anim == null:
		push_error("CommonEnemy: no AnimationPlayer found.")
	if body == null:
		push_warning("CommonEnemy: no 'body' node found, hit flash disabled.")
	else:
		_base_modulate = (body as CanvasItem).modulate
	if _hurt_areas.is_empty():
		push_warning("CommonEnemy: no 'can-hurt-player' Area2D found, contact damage disabled.")


func _find_player() -> void:
	if is_instance_valid(_player):
		return
	_player = get_tree().get_first_node_in_group("player") as Node2D


## The crit zone is an Area2D (rays fly through those), so plant a small body
## circle on it that rays DO stop on. Sized as the bounding circle of the real
## zone and re-pinned to it every frame, so the head can bob with animation.
## is_critical_hit stays the exact judge; this just makes the ray halt.
func _create_head_hitbox() -> void:
	if crit_area == null:
		return
	var src: CollisionShape2D = null
	for child in crit_area.get_children():
		var cs := child as CollisionShape2D
		if cs != null and not cs.disabled and cs.shape != null:
			src = cs
			break
	if src == null:
		return
	var r := 0.0
	if src.shape is CircleShape2D:
		r = (src.shape as CircleShape2D).radius
	elif src.shape is RectangleShape2D:
		r = (src.shape as RectangleShape2D).size.length() * 0.5
	elif src.shape is CapsuleShape2D:
		r = (src.shape as CapsuleShape2D).height * 0.5
	if r <= 0.0:
		push_warning("CommonEnemy: crit zone shape not supported for the head hitbox.")
		return
	_crit_shape = src
	_head_col = CollisionShape2D.new()
	_head_col.name = "HeadHitbox"
	var circle := CircleShape2D.new()
	circle.radius = r
	_head_col.shape = circle
	add_child(_head_col)


func _track_head_hitbox() -> void:
	if _head_col == null or not is_instance_valid(_crit_shape):
		return
	_head_col.position = to_local(_crit_shape.global_position)


## First Marker2D descendant whose name contains `word`.
func _find_marker(word: String) -> Marker2D:
	for n in find_children("*", "Marker2D", true, false):
		if String(n.name).to_lower().contains(word):
			return n as Marker2D
	return null


func crit_multiplier() -> float:
	return crit_mult


## True when a world-space hit position lands inside the critical-hit-area.
## Tests rect / circle / capsule shapes in the area's own (scaled) space, so
## the zone you placed in the editor is exactly what counts.
func is_critical_hit(world_pos: Vector2) -> bool:
	if crit_area == null:
		return false
	for child in crit_area.get_children():
		var cs := child as CollisionShape2D
		if cs == null or cs.disabled or cs.shape == null:
			continue
		var local: Vector2 = cs.to_local(world_pos)
		var shape := cs.shape
		if shape is RectangleShape2D:
			var half := (shape as RectangleShape2D).size * 0.5
			if absf(local.x) <= half.x and absf(local.y) <= half.y:
				return true
		elif shape is CircleShape2D:
			if local.length() <= (shape as CircleShape2D).radius:
				return true
		elif shape is CapsuleShape2D:
			var cap := shape as CapsuleShape2D
			var seg := maxf(cap.height * 0.5 - cap.radius, 0.0)
			var closest := Vector2(0.0, clampf(local.y, -seg, seg))
			if local.distance_to(closest) <= cap.radius:
				return true
	return false


## Shared crit math for bullets and dashes: base damage, or base x mult when
## the hit position is inside the victim's critical zone. Duck-typed, so any
## future enemy with is_critical_hit + crit_mult plugs in untouched.
static func damage_for(target: Object, pos: Vector2, base: int) -> int:
	if target != null and target.has_method("is_critical_hit") \
			and bool(target.call("is_critical_hit", pos)):
		var mult := 2.0
		var stored = target.get("crit_mult")
		if stored != null:
			mult = float(stored)
		return maxi(1, int(round(float(base) * mult)))
	return base


## Bullets call take_damage(1, bullet_position). The dash calls it with force +
## stun. `force` replaces the plain knockback and is divided by power_level,
## so the same dash kills a grunt and merely shoves a beast.
func take_damage(amount: int = 1, from_pos: Vector2 = Vector2.INF,
		force := -1.0, stun := -1.0) -> void:
	if _dying:
		return
	health -= amount
	damaged.emit(amount)
	_flash = hit_flash_time
	if hit_flash_enabled and body != null:
		(body as CanvasItem).modulate = hit_flash_color
	# Knock away from whatever hit us (or keep drifting if we don't know).
	var away := 0.0
	if from_pos != Vector2.INF and from_pos.x != global_position.x:
		away = signf(global_position.x - from_pos.x)
	elif is_instance_valid(_player) and _player.global_position.x != global_position.x:
		away = signf(global_position.x - _player.global_position.x)
	var knockback := hit_knockback
	if force >= 0.0:
		knockback = force / maxf(power_level, 0.01)
	velocity.x = away * knockback
	_stun = stun if stun >= 0.0 else hit_stun
	if anim != null:
		anim.speed_scale = 1.0
	_play(anim_hit, true)
	if health <= 0:
		_enter_death()


## Zero health: collapse, and either free or (debug) lie as a corpse and revive.
func _enter_death() -> void:
	_dying = true
	_death = death_time
	_corpse = simulated_death_time if debug_no_kill else 0.0
	_swing = 0.0
	_ranged_t = 0.0
	_stun = 0.0
	velocity = Vector2.ZERO
	if anim != null:
		anim.speed_scale = 1.0
	# A corpse is not hostile: crosshair goes green, auto-fire leaves it alone.
	remove_from_group("enemy")
	for area in _hurt_areas:
		area.set_deferred("monitoring", false)
	_play(anim_hit, true)
	died.emit()


func _revive() -> void:
	health = max_health
	_dying = false
	_corpse = 0.0
	_death = 0.0
	_stun = hit_stun # wake-up grace before it can act
	_flash = 0.0
	if anim != null:
		anim.speed_scale = 1.0
	if body != null:
		(body as CanvasItem).modulate = _base_modulate
	add_to_group("enemy")
	for area in _hurt_areas:
		area.set_deferred("monitoring", true)
	_play(anim_moving, true)
	revived.emit()


func _physics_process(delta: float) -> void:
	_find_player()
	_track_head_hitbox()
	var water_mult := 1.0
	if not is_in_group("water_creature") and WaterQuery.body_in_water(self):
		water_mult = water_speed_mult
	if not is_on_floor():
		velocity.y = minf(velocity.y + gravity * delta, 900.0)

	if _flash > 0.0:
		_flash -= delta
		if _flash <= 0.0 and body != null:
			(body as CanvasItem).modulate = _base_modulate

	if _dying:
		velocity.x = move_toward(velocity.x, 0.0, 1200.0 * delta)
		move_and_slide()
		if _death > 0.0:
			_death -= delta
			if _death <= 0.0 and _corpse <= 0.0:
				queue_free() # real death: collapse beat over
		elif _corpse > 0.0:
			_corpse -= delta
			if _corpse <= 0.0:
				_revive()
		return

	_attack_cd = maxf(_attack_cd - delta, 0.0)
	_ranged_cd = maxf(_ranged_cd - delta, 0.0)
	_contact_cd = maxf(_contact_cd - delta, 0.0)
	if _stun > 0.0:
		_stun -= delta
		anim.speed_scale = 1.0
		velocity.x = move_toward(velocity.x, 0.0, 1600.0 * delta)
		move_and_slide()
		_contact_damage()
		return # the hit clip keeps playing

	if not is_instance_valid(_player):
		_hold_still()
		velocity.x = move_toward(velocity.x, 0.0, 1200.0 * delta)
		move_and_slide()
		return

	var dx: float = signf(_player.global_position.x - global_position.x)
	if dx == 0.0:
		dx = 1.0
	if body != null:
		var s := dx if art_faces_right else -dx
		body.scale.x = absf(body.scale.x) * s if absf(body.scale.x) > 0.001 else s

	var hold := hold_range if hold_range > 0.0 else attack_range
	var dist := absf(_player.global_position.x - global_position.x)
	var dy := absf(_player.global_position.y - global_position.y)
	var in_range := dist <= attack_range and dy <= attack_height

	if _swing > 0.0:
		# Mid-swing: planted feet. The hurtbox riding the hand does the damage.
		anim.speed_scale = 1.0
		_swing -= delta
		velocity.x = move_toward(velocity.x, 0.0, 2000.0 * delta)
		if _swing <= 0.0:
			_attack_cd = attack_cooldown
	elif _ranged_t > 0.0:
		# Mid-cast: planted feet, glob leaves partway through.
		anim.speed_scale = 1.0
		_ranged_t -= delta
		velocity.x = move_toward(velocity.x, 0.0, 2000.0 * delta)
		var cast_len := anim.get_animation(anim_ranged).length \
				if anim != null and anim.has_animation(anim_ranged) else 0.9
		if not _ranged_fired and _ranged_t <= cast_len - ranged_fire_delay:
			_ranged_fired = true
			_fire_slime()
		if _ranged_t <= 0.0:
			_ranged_cd = ranged_cooldown
	elif in_range and _attack_cd <= 0.0:
		anim.speed_scale = 1.0
		_swing = anim.get_animation(anim_attack).length \
				if anim != null and anim.has_animation(anim_attack) else 0.9
		velocity.x = 0.0
		_play(anim_attack, true)
	elif ranged_enabled and _ranged_cd <= 0.0 and dist <= ranged_range and dy <= ranged_height:
		anim.speed_scale = 1.0
		_ranged_t = anim.get_animation(anim_ranged).length \
				if anim != null and anim.has_animation(anim_ranged) else 0.9
		_ranged_fired = false
		velocity.x = 0.0
		_play(anim_ranged, true)
	elif dist < personal_space:
		# Inside their guard: give ground instead of crowding in,
		# unless a wall is right behind.
		if _ray_wall(ray_back):
			_hold_still()
			velocity.x = move_toward(velocity.x, 0.0, 2000.0 * delta)
		else:
			anim.speed_scale = 1.0
			velocity.x = -dx * retreat_speed * water_mult
			_play(anim_moving)
	elif dist > hold:
		# Out of reach: close in, unless a wall is in the way.
		if _ray_wall(ray_front):
			_hold_still()
			velocity.x = move_toward(velocity.x, 0.0, 2000.0 * delta)
		else:
			anim.speed_scale = 1.0
			velocity.x = dx * move_speed * water_mult
			_play(anim_moving)
	else:
		# In the pocket: hold still, swing whenever ready.
		_hold_still()
		velocity.x = move_toward(velocity.x, 0.0, 2000.0 * delta)

	move_and_slide()
	_contact_damage()


## Standing still: idle if the clip exists yet, otherwise the slowed "moving"
## shuffle so it never runs in place at full speed.
func _hold_still() -> void:
	if anim == null:
		return
	if anim.has_animation(anim_idle):
		anim.speed_scale = 1.0
		_play(anim_idle)
	else:
		anim.speed_scale = hold_anim_speed
		_play(anim_moving)


## True when the ray touches a wall close ahead. Touching the player never
## counts (that's the prey, not a wall), so the rays can't block the chase.
func _ray_wall(ray: RayCast2D) -> bool:
	if ray == null or not ray.is_colliding():
		return false
	var c := ray.get_collider()
	if c is Node and ((c as Node).is_in_group("player") or (c as Node).has_method("take_hit")):
		return false
	return ray.global_position.distance_to(ray.get_collision_point()) <= wall_stop_range


## Lob the glob from the head marker at where the player stands right now.
## A fixed destination (not tracking) means sidestepping dodges it.
func _fire_slime() -> void:
	if not is_instance_valid(_player) or ranged_muzzle == null or slime_scene == null:
		return
	var slime := slime_scene.instantiate() as Area2D
	if slime == null:
		return
	var layer := ProjectileLayer.find(get_tree())
	if layer != null:
		layer.add_child(slime)
	else:
		get_tree().current_scene.add_child(slime)
	slime.global_position = ranged_muzzle.global_position
	if slime.has_method("launch"):
		slime.launch(ranged_muzzle.global_position, _player.global_position, slime_flight)


## Whoever touches any hurt Area2D gets hit, at most every contact_cooldown.
func _contact_damage() -> void:
	if _dying or _contact_cd > 0.0 or _hurt_areas.is_empty():
		return
	for area in _hurt_areas:
		if not area.monitoring:
			continue
		for b in area.get_overlapping_bodies():
			var node := b as Node
			if node == null or not node.has_method("take_hit"):
				continue
			var dir := signf(node.global_position.x - global_position.x)
			node.take_hit(dir if dir != 0.0 else 1.0)
			_contact_cd = contact_cooldown
			return


func _play(clip: String, force := false) -> void:
	if anim == null or not anim.has_animation(clip):
		return
	if not force and _cur == clip:
		return
	_cur = clip
	anim.play(clip)
