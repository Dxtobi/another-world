@tool
class_name CreatureController
extends CharacterBody2D

const WaterQuery := preload("res://world/water_query.gd")
## Mouse-driven creature (side view).
##   Left click (or hold)  -> walk / run toward the point
##   Right click           -> wind up, then pounce (ballistic leap) at the point
## Feet are placed procedurally: planted feet stay put, and a foot steps when the
## body has moved too far from it. Idle uses your AnimationPlayer.

signal pounced(target: Vector2)
signal landed
signal hit_body(body: Node)

enum State { IDLE, WALK, WINDUP, POUNCE, RECOVER }

@export_group("Nodes")
## A Node2D that contains Rig, the sprites and Skeleton2D. It is flipped when the creature turns.
@export var visual_root: Node2D:
	set(value):
		visual_root = value
		if Engine.is_editor_hint():
			update_configuration_warnings()
@export var animation_player: AnimationPlayer
## The IK foot target markers as paths (arrays of node refs do not survive
## scene save/load — NodePaths do). List them going around the body so
## diagonals share a gait group: front-left, front-right, back-right, back-left.
@export var feet: Array[NodePath] = []:
	set(value):
		feet = value
		if Engine.is_editor_hint():
			update_configuration_warnings()
## Optional marker that your SoupLookAt head modification targets.
@export var head_target: Node2D
## Optional marker that a tail modification targets. It trails behind the movement.
@export var tail_target: Node2D
## Optional Area2D that is only active during a pounce. Emits hit_body.
@export var attack_area: Area2D

@export_group("Movement")
@export var walk_speed := 90.0
@export var run_speed := 200.0
## Farther than this from the click point and the creature runs.
@export var run_distance := 250.0
@export var accel := 900.0
@export var decel := 1400.0
## Closer than this to the click point and it stops.
@export var stop_distance := 14.0
@export var gravity_scale := 1.0
## Wading/swimming creatures move this much slower. Add a creature to the
## "water_creature" group to exempt it from the slowdown.
@export_range(0.1, 1.0, 0.05) var water_speed_mult := 0.55
## Does the original art face left?
@export var art_faces_left := true

@export_group("Feet")
## Distance a planted foot can fall behind before it steps (while moving).
@export var step_distance := 28.0
## Same, but when standing still (feet tidy up into a neutral stance).
@export var settle_distance := 8.0
@export var step_time := 0.18
@export var step_height := 14.0
## How far ahead of the body the foot lands (1 = speed * step_time).
@export var lead_factor := 1.0
## Height of each marker above the ground when standing, in the same order as Feet.
## Leave EMPTY for automatic: it is measured the first time the creature stands on the ground.
## Markers at the ankle (not the toe) are handled by this.
@export var foot_heights: PackedFloat32Array = PackedFloat32Array()
@export_flags_2d_physics var ground_mask := 1
@export var ray_up := 60.0
@export var ray_down := 200.0

@export_group("Wall crawl")
## When on, the body aligns its up vector to the surface normal, so floors,
## walls and ceilings are all walkable. Uses the ground probes plus wall
## contact; turn off for classic side-view gravity.
@export var climb_walls := true
@export_range(40.0, 300.0, 5.0, "suffix:px") var surface_probe_len := 120.0
@export_range(1.0, 20.0, 0.5) var align_speed := 6.0
@export_group("Wander")
## With no click target, picks nearby points on its own so the creature
## prowls instead of standing dead still.
@export var wander_enabled := true
@export_range(1.0, 12.0, 0.5, "suffix:s") var wander_min_time := 3.0
@export_range(1.0, 20.0, 0.5, "suffix:s") var wander_max_time := 7.0
@export_range(40.0, 600.0, 10.0, "suffix:px") var wander_range := 260.0
@export_range(0.1, 1.2, 0.05, "suffix:rad") var max_plant_angle := 0.3
@export_range(40.0, 400.0, 5.0, "suffix:px") var max_plant_dist := 170.0
@export_group("Pounce")
@export var pounce_max_range := 420.0
@export var pounce_speed := 700.0
@export var windup_time := 0.28
@export var recover_time := 0.4
@export var pounce_cooldown := 0.6
## Pixels the body sinks while crouching.
@export var crouch_depth := 14.0
@export_subgroup("Airborne leg pose")
@export var air_reach := 30.0
@export var air_trail := 24.0
@export var air_lift := 14.0
@export var air_pose_speed := 18.0

@export_group("Look / Idle")
@export var idle_animation := "idle"
@export var head_look_range := 300.0
@export var tail_lag := 0.05
@export var tail_follow := 6.0
## Pixels the body bobs up and down while walking.
@export var bob_height := 3.0

@export_group("Debug")
@export var debug_draw := true


class Foot:
	var marker: Node2D
	var parent: Node2D
	var rest_local := Vector2.ZERO
	var group := 0
	var is_front := false
	var pos := Vector2.ZERO
	var planted := Vector2.ZERO
	var stepping := false
	var p0 := Vector2.ZERO
	var p1 := Vector2.ZERO
	var t := 0.0
	var dur := 0.2
	var height := 0.0
	var plant_rot := 0.0
	## Optional RayCast2D riding the marker (your leg feelers): a dangling
	## foot steps sooner. Self-collision is excluded in _build_feet.
	var feeler: RayCast2D


var state: State = State.IDLE

var _feet: Array[Foot] = []
var _gravity := 980.0
var _facing := -1
var _state_time := 0.0
var _cooldown_left := 0.0
var _air_time := 0.0
var _was_airborne := false
var _crouch := 0.0
var _bob_phase := 0.0
var _visual_base_y := 0.0
var _visual_scale_x := 1.0
var _visual_base_x := 0.0
var _pivot_x := 0.0
var _heights_ready := false
var _move_target := Vector2.ZERO
var _has_target := false
var _dragging := false
var _wander_t := 2.0
var _up := Vector2.UP
var _tan := Vector2.RIGHT
var _no_ground := 0.0
var _pounce_target := Vector2.ZERO
var _tail_parent: Node2D
var _tail_rest_local := Vector2.ZERO
var _tail_off := Vector2.ZERO
var _debug: Node2D


func _get_configuration_warnings() -> PackedStringArray:
	var w := PackedStringArray()
	if visual_root == null:
		w.append("Set Visual Root: a Node2D that holds Rig, the sprites and Skeleton2D. It is flipped when the creature turns.")
	if feet.is_empty():
		w.append("Add the foot target markers to Feet.")
	var has_shape := false
	for c in get_children():
		if c is CollisionShape2D or c is CollisionPolygon2D:
			has_shape = true
	if not has_shape:
		w.append("Add a CollisionShape2D so the creature can stand on the ground.")
	return w


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	floor_snap_length = 12.0
	_gravity = float(ProjectSettings.get_setting("physics/2d/default_gravity")) * gravity_scale
	if visual_root:
		_visual_base_y = visual_root.position.y
		_visual_base_x = visual_root.position.x
		_visual_scale_x = absf(visual_root.scale.x)
	_pivot_x = _find_pivot_x()
	_facing = -1 if art_faces_left else 1
	_build_feet()
	if tail_target:
		_tail_parent = tail_target.get_parent() as Node2D
		_tail_rest_local = tail_target.position
	if attack_area:
		attack_area.monitoring = false
		attack_area.body_entered.connect(_on_attack_body_entered)
	if debug_draw:
		_debug = Node2D.new()
		_debug.top_level = true
		_debug.z_index = 100
		add_child(_debug)
		_debug.draw.connect(_on_debug_draw)


func _build_feet() -> void:
	_feet.clear()
	var sum_x := 0.0
	for i in feet.size():
		var m := get_node_or_null(feet[i]) as Node2D
		if m == null:
			push_warning("CreatureController: Feet[%d] path is not a Node2D: %s" % [i, str(feet[i])])
			continue
		var f := Foot.new()
		f.marker = m
		var p := m.get_parent() as Node2D
		f.parent = p if p else self
		f.rest_local = m.position
		f.group = i % 2
		f.pos = m.global_position
		f.planted = f.pos
		f.plant_rot = rotation
		for rc in m.get_children():
			var ray := rc as RayCast2D
			if ray != null:
				f.feeler = ray
				ray.add_exception_rid(get_rid())
				ray.collide_with_areas = false
				break
		_feet.append(f)
		sum_x += f.rest_local.x
	if _feet.is_empty():
		return
	var center_x := sum_x / float(_feet.size())
	for f in _feet:
		if art_faces_left:
			f.is_front = f.rest_local.x < center_x
		else:
			f.is_front = f.rest_local.x > center_x


# ---------------------------------------------------------------- public API

func move_to(world_x: float) -> void:
	_move_target = Vector2(world_x, global_position.y)
	_has_target = true


func pounce(target: Vector2) -> void:
	if state == State.WINDUP or state == State.POUNCE or state == State.RECOVER:
		return
	if not is_on_floor() or _cooldown_left > 0.0:
		return
	_pounce_target = target
	_has_target = false
	_face_toward(target.x)
	_set_state(State.WINDUP)


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			if mb.pressed:
				_move_target = get_global_mouse_position()
				_has_target = true
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			pounce(get_global_mouse_position())


# ---------------------------------------------------------------- main loop

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_state_time += delta
	_cooldown_left = maxf(0.0, _cooldown_left - delta)

	if _dragging:
		_move_target = get_global_mouse_position()
		_has_target = true

	_tan = Vector2(-_up.y, _up.x)
	up_direction = _up
	if is_on_floor():
		_air_time = 0.0
	else:
		_air_time += delta
		velocity += -_up * _gravity * delta

	match state:
		State.IDLE, State.WALK:
			_ground_move(delta)
		State.WINDUP:
			_damp_tangent(decel, delta)
			_crouch = move_toward(_crouch, 1.0, delta / maxf(windup_time, 0.01))
			if _state_time >= windup_time:
				_launch()
		State.POUNCE:
			_crouch = move_toward(_crouch, 0.0, delta * 8.0)
			if (is_on_floor() and _state_time > 0.12) or _state_time > 2.5:
				_land()
		State.RECOVER:
			_damp_tangent(decel, delta)
			_crouch = move_toward(_crouch, 0.0, delta / maxf(recover_time, 0.01))
			if _state_time >= recover_time:
				_set_state(State.IDLE)

	move_and_slide()
	_update_surface(delta)
	_update_feet(delta)
	_update_body(delta)
	_update_look(delta)
	_update_animation()
	if _debug:
		_debug.queue_redraw()


func _set_state(new_state: State) -> void:
	state = new_state
	_state_time = 0.0


func _damp_tangent(rate: float, delta: float) -> void:
	var nt := move_toward(velocity.dot(_tan), 0.0, rate * delta)
	velocity = _tan * nt + (-_up) * velocity.dot(-_up)


func _ground_move(_delta: float) -> void:
	var want := 0.0
	if _has_target:
		var dt := (_move_target - global_position).dot(_tan)
		if absf(dt) > stop_distance:
			var dir := 1 if dt > 0.0 else -1
			var spd := run_speed if absf(dt) > run_distance else walk_speed
			if not is_in_group("water_creature") and WaterQuery.body_in_water(self):
				spd *= water_speed_mult
			want = float(dir) * spd
			_set_facing(dir)
		elif not _dragging:
			_has_target = false
	elif wander_enabled and is_on_floor():
		_wander_t -= _delta
		if _wander_t <= 0.0:
			_wander_t = randf_range(wander_min_time, wander_max_time)
			_move_target = global_position + _tan * randf_range(-wander_range, wander_range)
			_has_target = true
	var rate := accel if absf(want) > 0.0 else decel
	var nt := move_toward(velocity.dot(_tan), want, rate * _delta)
	var nn := velocity.dot(-_up)
	velocity = _tan * nt + (-_up) * nn
	var next := State.WALK if absf(nt) > 8.0 else State.IDLE
	if next != state:
		_set_state(next)


## Body up follows the surface normal (probe average, wall contact wins),
## so floors, walls and ceilings are all walkable when climb_walls is on.
func _update_surface(delta: float) -> void:
	var target := Vector2.UP
	var found := false
	var hit := _probe_surface(global_position)
	if not hit.is_empty():
		target = (hit["normal"] as Vector2).normalized()
		found = true
	elif is_on_wall():
		target = get_wall_normal().normalized()
		found = true
	if found:
		_no_ground = 0.0
	else:
		_no_ground += delta
		if _no_ground > 0.35:
			target = Vector2.UP
	if not climb_walls:
		target = Vector2.UP
	var rate := align_speed * (2.0 if is_on_wall() else 1.0)
	var k := 1.0 - exp(-rate * delta)
	_up = (_up.lerp(target, k)).normalized()
	rotation = lerp_angle(rotation, atan2(_up.x, -_up.y), k)


func _probe_surface(p: Vector2) -> Dictionary:
	var space := get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.create(p + _up * 30.0, p - _up * surface_probe_len, ground_mask)
	q.exclude = [get_rid()]
	return space.intersect_ray(q)


## The visuals are mirrored around the collision shape's centre, so the body never
## jumps sideways relative to its collision shape when the creature turns.
func _find_pivot_x() -> float:
	for c in get_children():
		if c is CollisionShape2D or c is CollisionPolygon2D:
			return (c as Node2D).position.x
	return _visual_base_x


func _set_facing(dir: int) -> void:
	_facing = dir
	if visual_root:
		var flip := -dir if art_faces_left else dir
		visual_root.scale.x = _visual_scale_x * float(flip)
		visual_root.position.x = _pivot_x + (_visual_base_x - _pivot_x) * float(flip)


func _face_toward(world_x: float) -> void:
	var dx := world_x - global_position.x
	if absf(dx) > 8.0:
		_set_facing(1 if dx > 0.0 else -1)


# ---------------------------------------------------------------- pounce

## Returns (vx, vy, flight_time) of a ballistic arc that reaches the target.
func _plan_pounce(target: Vector2) -> Vector3:
	var d := (target - global_position).limit_length(pounce_max_range)
	var t := clampf(d.length() / maxf(pounce_speed, 1.0), 0.25, 0.9)
	return Vector3(d.x / t, (d.y - 0.5 * _gravity * t * t) / t, t)


func _launch() -> void:
	var plan := _plan_pounce(_pounce_target)
	velocity = Vector2(plan.x, plan.y)
	_set_state(State.POUNCE)
	if attack_area:
		attack_area.set_deferred("monitoring", true)
	pounced.emit(_pounce_target)


func _land() -> void:
	velocity.x *= 0.15
	_crouch = 1.0
	_cooldown_left = pounce_cooldown
	if attack_area:
		attack_area.set_deferred("monitoring", false)
	_set_state(State.RECOVER)
	landed.emit()


func _on_attack_body_entered(body: Node) -> void:
	if body != self:
		hit_body.emit(body)


# ---------------------------------------------------------------- feet

func _home(f: Foot) -> Vector2:
	return f.parent.to_global(f.rest_local)


## Finds the ground below p along the surface down. Returns the point where
## the MARKER should be (the ground point raised by `height`), or p itself
## if there is no ground.
func _ground_point(p: Vector2, height: float) -> Vector2:
	var hit := _raycast_down(p)
	if hit.is_empty():
		return p
	return (hit["position"] as Vector2) + _up * height


func _raycast_down(p: Vector2) -> Dictionary:
	var space := get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.create(p + _up * ray_up, p - _up * ray_down, ground_mask)
	q.exclude = [get_rid()]
	return space.intersect_ray(q)


## Measures how high each marker sits above the ground in the standing pose.
func _measure_foot_heights() -> void:
	for i in _feet.size():
		var f := _feet[i]
		if i < foot_heights.size():
			f.height = foot_heights[i]
			continue
		var home := _home(f)
		var hit := _raycast_down(home)
		f.height = ((home - (hit["position"] as Vector2)).dot(_up)) if not hit.is_empty() else 0.0


func _begin_step(f: Foot, to: Vector2, dur: float) -> void:
	f.p0 = f.pos
	f.p1 = to
	f.t = 0.0
	f.dur = maxf(dur, 0.04)
	f.stepping = true


func _air_pose(f: Foot, delta: float) -> void:
	f.stepping = false
	var s := -1.0 if art_faces_left else 1.0
	var off := _tan * (s * air_reach) + _up * air_lift if f.is_front else _tan * (-s * air_trail) + _up * air_lift
	var goal := f.parent.to_global(f.rest_local) + off
	f.pos = f.pos.lerp(goal, 1.0 - exp(-air_pose_speed * delta))
	f.planted = f.pos
	f.plant_rot = rotation
	f.marker.global_position = f.pos


func _update_feet(delta: float) -> void:
	if _feet.is_empty():
		return
	if not _heights_ready and is_on_floor():
		_measure_foot_heights()
		_heights_ready = true

	var airborne := state == State.POUNCE or (not is_on_floor() and _air_time > 0.1)
	if airborne:
		_was_airborne = true
		for f in _feet:
			_air_pose(f, delta)
		return
	if _was_airborne:
		_was_airborne = false
		for f in _feet:
			_begin_step(f, _ground_point(_home(f), f.height), 0.12)

	var speed := absf(velocity.dot(_tan))
	var threshold := step_distance if speed > 12.0 else settle_distance
	var busy := [0, 0]
	for f in _feet:
		if f.stepping:
			busy[f.group] += 1

	# decide which feet start a step (the two gait groups take turns)
	for f in _feet:
		if f.stepping:
			continue
		var home := _home(f)
		var over := absf((f.planted - home).dot(_tan))
		# Body rotated under a planted foot (wall transitions) or the foot
		# got left beyond leg reach: re-step instead of hyperextending.
		if absf(angle_difference(rotation, f.plant_rot)) > max_plant_angle:
			over = maxf(over, threshold * 2.0)
		if (f.planted - home).length() > max_plant_dist:
			over = maxf(over, threshold * 2.0)
		if over <= threshold:
			continue
		if busy[1 - f.group] > 0 and over < threshold * 2.0:
			continue
		# A dangling feeler (your leg ray lost the ground) steps early.
		if f.feeler != null and not f.feeler.is_colliding():
			over = maxf(over, threshold * 2.0)
		var lead := clampf(velocity.dot(_tan) * step_time * lead_factor, -step_distance, step_distance)
		var dur := step_time / maxf(1.0, speed / maxf(walk_speed, 1.0))
		_begin_step(f, _ground_point(home + _tan * lead, f.height), dur)
		busy[f.group] += 1

	# move the markers
	for f in _feet:
		if f.stepping:
			f.t += delta / f.dur
			if f.t >= 1.0:
				f.stepping = false
				f.planted = f.p1
				f.plant_rot = rotation
				f.pos = f.p1
			else:
				var e := f.t * f.t * (3.0 - 2.0 * f.t)
				var p := f.p0.lerp(f.p1, e)
				p += _up * (sin(f.t * PI) * step_height)
				f.pos = p
		else:
			f.pos = f.planted
		f.marker.global_position = f.pos


# ---------------------------------------------------------------- body / look / animation

func _update_body(delta: float) -> void:
	if visual_root == null:
		return
	var on_ground := is_on_floor()
	var speed_ratio := clampf(absf(velocity.x) / maxf(run_speed, 1.0), 0.0, 1.0)
	if on_ground:
		_bob_phase += absf(velocity.x) * delta * PI / maxf(step_distance, 1.0)
	var bob := absf(sin(_bob_phase)) * bob_height * speed_ratio if on_ground else 0.0
	visual_root.position.y = _visual_base_y + _crouch * crouch_depth - bob


func _update_look(delta: float) -> void:
	if head_target:
		var look := get_global_mouse_position()
		if state == State.WINDUP or state == State.POUNCE:
			look = _pounce_target
		head_target.global_position = global_position + (look - global_position).limit_length(head_look_range)
	if tail_target and _tail_parent:
		var desired := -velocity * tail_lag
		_tail_off = _tail_off.lerp(desired, 1.0 - exp(-tail_follow * delta))
		tail_target.global_position = _tail_parent.to_global(_tail_rest_local) + _tail_off


func _update_animation() -> void:
	if animation_player == null:
		return
	var want_idle := state == State.IDLE
	var playing_idle := animation_player.is_playing() and animation_player.current_animation == idle_animation
	if want_idle and not playing_idle:
		if animation_player.has_animation(idle_animation):
			animation_player.play(idle_animation, 0.25)
	elif not want_idle and playing_idle:
		if animation_player.has_animation("RESET"):
			animation_player.play("RESET", 0.25)
		else:
			animation_player.pause()


# ---------------------------------------------------------------- debug drawing

func _on_debug_draw() -> void:
	var d := _debug
	var font := ThemeDB.fallback_font
	d.draw_string(font, global_position + Vector2(-40.0, -150.0),
		"%s  vx=%d" % [State.keys()[state], int(velocity.x)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)

	for f in _feet:
		var home := _home(f)
		d.draw_circle(home, 3.0, Color(0.3, 0.8, 1.0, 0.8))
		d.draw_line(home, f.pos, Color(1, 1, 1, 0.3), 1.0)
		if f.stepping:
			d.draw_circle(f.p1, 3.0, Color.ORANGE)
		else:
			d.draw_circle(f.planted, 3.0, Color.LIME)

	# collision shape outline and the point the visuals mirror around
	var pivot := to_global(Vector2(_pivot_x, 0.0))
	d.draw_line(pivot + Vector2(0, -120), pivot + Vector2(0, 120), Color.MAGENTA, 1.0)
	for c in get_children():
		if c is CollisionShape2D and (c as CollisionShape2D).shape:
			var cs := c as CollisionShape2D
			d.draw_set_transform_matrix(cs.global_transform)
			var sh := cs.shape
			if sh is RectangleShape2D:
				d.draw_rect(Rect2(-sh.size * 0.5, sh.size), Color(0.2, 1.0, 0.4, 0.9), false, 2.0)
			elif sh is CapsuleShape2D:
				d.draw_rect(Rect2(Vector2(-sh.radius, -sh.height * 0.5), Vector2(sh.radius * 2.0, sh.height)), Color(0.2, 1.0, 0.4, 0.9), false, 2.0)
			elif sh is CircleShape2D:
				d.draw_arc(Vector2.ZERO, sh.radius, 0.0, TAU, 32, Color(0.2, 1.0, 0.4, 0.9), 2.0)
			d.draw_set_transform_matrix(Transform2D.IDENTITY)
			break

	if _has_target:
		var m := _move_target
		d.draw_line(m + Vector2(-8, 0), m + Vector2(8, 0), Color.YELLOW, 2.0)
		d.draw_line(m + Vector2(0, -8), m + Vector2(0, 8), Color.YELLOW, 2.0)

	if state == State.WINDUP or state == State.POUNCE:
		var plan := _plan_pounce(_pounce_target)
		var pts := PackedVector2Array()
		for i in range(21):
			var t := plan.z * float(i) / 20.0
			pts.append(global_position + Vector2(plan.x * t, plan.y * t + 0.5 * _gravity * t * t))
		d.draw_polyline(pts, Color(1.0, 0.3, 0.3, 0.8), 2.0)
		d.draw_circle(_pounce_target, 5.0, Color.RED)
