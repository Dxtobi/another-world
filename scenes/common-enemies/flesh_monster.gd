
extends CharacterBody2D
class_name FleshMonster

const WaterQuery := preload("res://world/water_query.gd")

## Procedural crawling, tentacled monster for Godot 4.x.

@export_group("Movement")
@export var move_speed: float = 85.0
## Wading creatures slow down; add "water_creature" to the group to opt out.
@export_range(0.1, 1.0, 0.05) var water_speed_mult := 0.55
@export var acceleration: float = 180.0
@export var gravity: float = 900.0
@export var jump_force: float = 280.0
@export var detection_range: float = 360.0

@export_group("Body")
@export var body_radius: float = 48.0
@export var flesh_lumps: int = 24
@export var tentacle_count: int = 16
@export var tentacle_length: float = 135.0
@export var tentacle_segments: int = 12
@export var wiggle_speed: float = 2.0
@export var body_bob: float = 4.0

@export_group("Surface Grabbing")
@export var grab_range: float = 190.0
@export var pull_strength: float = 100.0
@export var anchor_weight: float = 0.7
@export var raycast_mask: int = 1

@export_group("Appearance")
@export var flesh_color := Color(0.32, 0.075, 0.12)
@export var highlight_color := Color(0.68, 0.25, 0.29)
@export var dark_color := Color(0.12, 0.035, 0.065)
@export var bone_color := Color(0.85, 0.65, 0.57)

var time_passed: float = 0.0
var facing: float = 1.0
var body_offset := Vector2.ZERO
var prey: Node2D

# Each tentacle stores its current surface anchor, if attached.
var tentacles: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()

var prey_scan_timer: float = 0.0
var water_mult: float = 1.0
@export var prey_scan_interval: float = 0.3

func _ready() -> void:
	rng.randomize()
	_create_tentacles()
	add_to_group("enemies")
	queue_redraw()


func _create_tentacles() -> void:
	tentacles.clear()

	for i in range(tentacle_count):
		var angle := TAU * float(i) / float(tentacle_count)
		tentacles.append({
			"angle": angle,
			"phase": rng.randf_range(0.0, TAU),
			"length": tentacle_length * rng.randf_range(0.7, 1.25),
			"width": rng.randf_range(5.0, 10.0),
			"anchor": Vector2.ZERO,
			"normal": Vector2.UP,
			"attached": false,
			"cooldown": rng.randf_range(0.0, 1.0),
			"points": PackedVector2Array()
		})


func _physics_process(delta: float) -> void:
	time_passed += delta
	body_offset.y = sin(time_passed * wiggle_speed) * body_bob
	water_mult = 1.0
	if not is_in_group("water_creature") and WaterQuery.body_in_water(self):
		water_mult = water_speed_mult

	prey_scan_timer -= delta

	if prey_scan_timer <= 0.0:
		prey_scan_timer = prey_scan_interval
		_find_prey()
	_update_tentacles(delta)
	_move_body(delta)

	queue_redraw()


func _find_prey() -> void:
	prey = null
	var nearest_distance := detection_range

	for node in get_tree().get_nodes_in_group("prey"):
		if not node is Node2D:
			continue

		var candidate := node as Node2D
		var distance := global_position.distance_to(
			candidate.global_position
		)

		if distance < nearest_distance:
			nearest_distance = distance
			prey = candidate

	if prey:
		facing = signf(prey.global_position.x - global_position.x)
		if is_zero_approx(facing):
			facing = 1.0


func _update_tentacles(delta: float) -> void:
	var space := get_world_2d().direct_space_state

	for i in range(tentacles.size()):
		var t: Dictionary = tentacles[i]
		var angle: float = t["angle"]
		var phase: float = t["phase"]
		var length: float = t["length"]

		t["cooldown"] = maxf(0.0, float(t["cooldown"]) - delta)

		var origin := global_position + Vector2(
			cos(angle) * body_radius * 0.7,
			sin(angle) * body_radius * 0.7
		)

		# Reach toward prey when it is nearby.
		var direction := Vector2(cos(angle), sin(angle))

		if prey and origin.distance_to(prey.global_position) < detection_range:
			var toward_prey := (
				prey.global_position - origin
			).normalized()

			# A few tentacles preferentially reach toward prey.
			if i % 3 == 0:
				direction = direction.lerp(toward_prey, 0.7).normalized()

		# Slowly wave free tentacles.
		direction = direction.rotated(
			sin(time_passed * wiggle_speed + phase) * 0.38
		)

		var attached: bool = t["attached"]
		var anchor: Vector2 = t["anchor"]

		# Release anchors that have become too far away.
		if attached and origin.distance_to(anchor) > length * 1.7:
			attached = false
			t["cooldown"] = 0.25

		# Try to latch onto nearby solid surfaces.
		if not attached and float(t["cooldown"]) <= 0.0:
			var reach_direction := direction

			# Alternate reaching toward the ground and around the body.
			if i % 4 == 0:
				reach_direction = Vector2(
					facing * 0.8,
					0.6 + sin(time_passed + phase) * 0.2
				).normalized()

			var end_point := origin + reach_direction * minf(
				length, grab_range
			)

			var query := PhysicsRayQueryParameters2D.create(
				origin,
				end_point,
				raycast_mask
			)
			query.exclude = [get_rid()]

			var hit := space.intersect_ray(query)

			if not hit.is_empty():
				var hit_position: Vector2 = hit["position"]
				var hit_normal: Vector2 = hit["normal"]

				if origin.distance_to(hit_position) > 20.0:
					anchor = hit_position
					t["normal"] = hit_normal
					attached = true

		t["attached"] = attached
		t["anchor"] = anchor

		# Build a curved, segmented tentacle.
		var points := PackedVector2Array()
		var tip := anchor if attached else (
			origin + direction * length * 0.75
		)

		var bend := Vector2(
			sin(time_passed * 1.7 + phase) * 18.0,
			cos(time_passed * 1.3 + phase) * 12.0
		)

		for j in range(tentacle_segments + 1):
			var u := float(j) / float(tentacle_segments)

			# Quadratic Bezier curve from body to tentacle tip.
			var control := origin.lerp(tip, 0.5) + bend
			var p := (
				origin * pow(1.0 - u, 2.0)
				+ control * 2.0 * (1.0 - u) * u
				+ tip * pow(u, 2.0)
			)

			points.append(p)

		t["points"] = points
		tentacles[i] = t


func _move_body(delta: float) -> void:
	var pull := Vector2.ZERO
	var attached_count := 0

	for t in tentacles:
		if t["attached"]:
			var anchor: Vector2 = t["anchor"]
			var offset := anchor - global_position

			if offset.length() > body_radius:
				pull += offset.normalized()
				attached_count += 1

	if attached_count > 0:
		pull /= float(attached_count)

	# Prefer to pull toward attached tentacles when climbing.
	if pull.length() > 0.1:
		velocity += pull.normalized() * pull_strength * delta

	var target_speed := 0.0

	if prey:
		target_speed = signf(prey.global_position.x - global_position.x)
	else:
		# Slow wandering when no prey is detected.
		target_speed = facing * 0.25

	velocity.x = move_toward(
		velocity.x,
		target_speed * move_speed * water_mult,
		acceleration * delta
	)

	if not is_on_floor():
		velocity.y += gravity * delta
	else:
		# Keep the creature on the ground.
		if velocity.y > 0.0:
			velocity.y = 0.0

		# Small random hops to help it traverse platforms.
		if prey and absf(prey.global_position.x - global_position.x) > 100.0:
			if rng.randf() < 0.008:
				velocity.y = -jump_force

	# Prevent runaway speeds from repeated tentacle pulls.
	velocity.x = clampf(velocity.x, -move_speed * 2.5, move_speed * 2.5)
	velocity.y = clampf(velocity.y, -jump_force * 1.8, 600.0)

	move_and_slide()


func _draw() -> void:
	# Draw tentacles behind the main body.
	for t in tentacles:
		var points: PackedVector2Array = t["points"]

		if points.size() < 2:
			continue

		var local_points := PackedVector2Array()
		for p in points:
			local_points.append(to_local(p))

		var width: float = t["width"]

		# Thick flesh underneath, thin highlight on top.
		draw_polyline(local_points, dark_color, width + 4.0, true)
		draw_polyline(local_points, flesh_color, width, true)

		# Small highlight down one side.
		if local_points.size() > 2:
			var highlights := PackedVector2Array()
			for j in range(0, local_points.size(), 2):
				highlights.append(
					local_points[j] + Vector2(-1.5, -1.5)
				)

			if highlights.size() > 1:
				draw_polyline(
					highlights, highlight_color,
					maxf(1.0, width * 0.2), true
				)

		# Hook-shaped gripping claw at the tip.
		var tip: Vector2 = local_points[-1]
		var prev: Vector2 = local_points[-2]
		var claw_direction := (tip - prev).normalized()
		var claw_side := claw_direction.rotated(PI * 0.7)

		draw_line(
			tip,
			tip - claw_direction * 10.0 + claw_side * 9.0,
			bone_color, 3.0, true
		)

	_draw_body()
	_draw_faces()


func _draw_body() -> void:
	var center := body_offset
	var radius := body_radius

	# Irregular outline made from overlapping circles.
	for i in range(flesh_lumps):
		var angle := TAU * float(i) / float(flesh_lumps)
		var wobble := sin(angle * 3.0 + time_passed * 2.0) * 4.0
		wobble += sin(angle * 7.0 - time_passed) * 2.5

		var lump_radius := radius * rngless_noise(i)
		var offset := Vector2(cos(angle), sin(angle)) * (
			radius * 0.65 + wobble
		)

		draw_circle(
			center + offset,
			lump_radius,
			flesh_color
		)

	draw_circle(center, radius * 0.82, flesh_color)

	# Shaded flesh nodules embedded in the body.
	for i in range(12):
		var a := float(i) * 2.39996
		var distance := radius * (0.15 + 0.52 * float(i % 4) / 4.0)
		var p := center + Vector2(cos(a), sin(a)) * distance

		draw_circle(p + Vector2(2.0, 3.0), 8.0, dark_color)
		draw_circle(p, 7.0 + float(i % 3), highlight_color)
		draw_circle(p + Vector2(-2.0, -2.0), 2.5, bone_color)


func _draw_faces() -> void:
	# Embedded eye sockets and distorted little mouths.
	for i in range(7):
		var angle := float(i) * 2.39996 + 0.5
		var distance := body_radius * (0.15 + 0.38 * float(i % 3) / 3.0)
		var p := body_offset + Vector2(cos(angle), sin(angle)) * distance

		# Socket.
		draw_circle(p, 6.0, dark_color)

		# Eye.
		draw_circle(
			p + Vector2(facing * 1.5, 0.0),
			2.0,
			Color(0.95, 0.72, 0.58)
		)

		# Small distorted mouth.
		if i % 2 == 0:
			draw_arc(
				p + Vector2(0.0, 10.0),
				5.0,
				0.2,
				PI - 0.2,
				8,
				dark_color,
				3.0,
				true
			)


func rngless_noise(index: int) -> float:
	# Stable pseudo-random-looking radius, avoiding visual flicker.
	var value := sin(float(index) * 127.1 + 311.7) * 43758.5453
	value = value - floor(value)
	return 7.0 + value * 8.0
