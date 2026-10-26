extends CharacterBody2D
class_name BeastLegs

const WaterQuery := preload("res://world/water_query.gd")

signal arrived
signal path_failed
signal died
signal damaged(amount: int)

@export var foot_targets: Array[Node2D] = []   # ankle targets, each with a RayCast2D child
@export_flags_2d_physics var surface_mask := 1 # terrain layer ONLY (not the player)

@export_group("Movement (hold right mouse = manual)")
@export var move_speed := 140.0
@export var accel := 800.0
## Water slows the beast unless it is explicitly a water creature.
@export_range(0.1, 1.0, 0.05) var water_speed_mult := 0.55

@export_group("Ground follow")
@export var snap_to_ground := true
@export var ride_height_override := 0.0   # 0 = auto (shape center -> ray tip distance in rest pose)
@export var ground_tolerance := 60.0      # surface further than ride_height + this = "no ground" (falls)
@export var max_snap_speed := 600.0       # max px/s the body is pulled toward a surface
@export var height_follow := 12.0

@export_group("Wall climb")
@export var climb_walls := true     # body up follows the surface normal: floors, walls, ceilings
@export var wall_probe_len := 70.0  # feeler reach PAST the collision shape while moving
@export_range(1.0, 20.0, 0.5) var align_speed := 6.0

@export_group("Gait")
@export var step_distance := 26.0   # how far a foot lags before it steps
@export var step_duration := 0.20
@export var step_height := 16.0
@export var stride_lead := 0.8
@export var ray_raise := 20.0       # foot ray starts this far above the ankle
@export var ray_reach := 1.6        # foot ray length = tip length * this
@export var max_leg_stretch := 80.0

@export_group("Facing")
## Node holding the whole visual (Skeleton2D + sprites). Flipped to turn.
## Default: the "body" child. Empty = no flipping.
@export var visual_root: Node2D
## true if the art looks LEFT in its rest pose (kaiju tail sticks out right).
@export var art_faces_left := true

@export_group("Hunt")
## Find and hunt the player: inside aggro_range the beast links its
## destination to the player and the contour navigator walks it there
## (floors, walls, ceilings). Manual drive (test_drive / right mouse) always
## wins while held; hunting resumes after. Drops off past deaggro_range.
@export var hunt_player := true
@export_range(100.0, 2000.0, 10.0, "suffix:px") var aggro_range := 700.0
@export_range(100.0, 2500.0, 10.0, "suffix:px") var deaggro_range := 950.0
@export_group("Attack")
## Bite range from the shape center. No Area2D needed: a cooldown + distance
## check calls the player's take_hit directly.
@export_range(20.0, 400.0, 5.0, "suffix:px") var attack_range := 110.0
@export_range(0.2, 5.0, 0.1, "suffix:s") var attack_cooldown := 1.2
@export_group("Health")
## Gun bullets and the dash call take_damage(...): same convention as
## CommonEnemy, so the existing weapons hurt it with zero extra wiring.
@export_range(1, 100) var max_health := 25
## Heavier beasts shrug off shoves: incoming force knockback is divided by
## this. The kaiju barely budges.
@export_range(0.1, 10.0, 0.1) var power_level := 4.0
@export_range(0.0, 900.0, 10.0, "suffix:px/s") var hit_knockback := 260.0
@export_range(0.0, 1.0, 0.05, "suffix:s") var hit_stun := 0.4
@export_range(0.02, 0.5, 0.01, "suffix:s") var hit_flash_time := 0.08
@export var hit_flash_color := Color(4.0, 4.0, 4.0)

@export_group("Navigation")
@export var auto_navigate := true
## Optional: the creature walks to (and follows) this node.
@export var destination_node: Node2D
## Left click sets the destination.
@export var click_to_set_destination := true
@export var nav_cell := 32.0              # grid resolution. Smaller = tighter paths, slower build
@export var nav_margin := 600.0           # grid extends this far around creature + destination
@export var nav_arrive := 60.0            # stop this close (plus ride height) to the destination
@export var nav_lookahead := 3            # path points ahead it steers toward
@export var nav_repath_interval := 0.6
@export var nav_rebuild_interval := 3.0   # re-scan terrain while travelling. 0 = only on new destination
@export var nav_stuck_time := 1.2

@export_group("Tail")
## IK target for the tail. Empty = auto-find a node named "tail".
@export var tail_target: Node2D
@export var tail_mass := 3.0          # heavier = slower, lazier, bigger swings
@export var tail_stiffness := 55.0    # spring pull toward the goal
@export var tail_damping := 6.0       # lower = swings longer and overshoots more
@export var tail_sway := 34.0         # side-to-side wave amplitude
@export var tail_sway_speed := 1.5
@export var tail_gravity := 600.0     # droop (hangs on walls, swings under on ceilings)
@export var tail_turn_kick := 320.0   # whip impulse when the creature turns around
@export var tail_clearance := 6.0
@export var tail_max_offset := 170.0

@export_group("Head")
## IK target for the head. Empty = auto-find a node named "head2".
@export var head_target: Node2D
@export var head_stiffness := 90.0
@export var head_damping := 11.0
@export var head_bob := 7.0
@export var head_reach := 36.0
@export var head_look_range := 55.0
@export var head_wall_touch := 0.8
@export var head_clearance := 8.0

@export_group("Debug")
@export var debug_draw := true
## Hands-free testing: -1 / +1 walks without holding right mouse. 0 = off.
@export_range(-1.0, 1.0, 1.0) var test_drive := 0.0

class Foot:
	var target: Node2D
	var parent: Node2D
	var home_local := Vector2.ZERO
	var tip_local := Vector2(0, 60)
	var planted := Vector2.ZERO
	var from := Vector2.ZERO
	var to := Vector2.ZERO
	var stepping := false
	var t := 0.0
	var dbg_from := Vector2.ZERO
	var dbg_to := Vector2.ZERO
	var dbg_hit := Vector2.ZERO
	var dbg_ok := false

# Draws on top of everything, in world coordinates
class DebugLayer extends Node2D:
	var beast
	func _draw() -> void:
		if beast:
			beast.draw_debug(self)

const NO_CELL := Vector2i(-1, -1)

var feet: Array[Foot] = []
var ride_height := 40.0
var move_dir := 0.0
var vel_t := 0.0   # signed speed along the surface tangent
var any_grounded := false
var body_ground_ok := false
var _body_from := Vector2.ZERO
var _body_to := Vector2.ZERO
var _body_hit := Vector2.ZERO
var _wall_from := Vector2.ZERO
var _wall_hit := Vector2.ZERO
var _wall_ok := false
var _wrap_hold := 0.0    # >0 while wrapping round a convex edge: don't fall
var _up := Vector2.UP    # body up: follows the surface normal when climbing
var _tan := Vector2.RIGHT
var _no_ground := 0.0
var _fall := 0.0         # downward speed when airborne (no thrust in mid-air)
var _first_snap := true
var _dbg: DebugLayer
var _facing := 0            # -1 = art points left, +1 = art points right
var _speed_mul := 1.0
var _water_mult := 1.0
# Rigid body transform: the art node (_bn) rotates about the collision
# shape's center and mirrors in its own pre-rotation frame, so turning and
# wall alignment can never offset the art from the collision (or scatter it).
var _bn: Node2D           # art node that rotates/flips: visual_root, else self
var _phi := 0.0           # smoothed body angle (surface alignment + rest angle)
var _B0 := Vector2.ZERO   # _bn.position at rest
var _th0 := 0.0           # _bn.rotation at rest
var _vx0 := 1.0           # |_bn.scale.x| at rest
var _vy0 := 1.0           # _bn.scale.y at rest
var _piv := Vector2.ZERO  # pivot (shape center) in _bn-host space
var _pq := Vector2.ZERO   # pivot in _bn's pre-scale local frame
var _pivot_x := 0.0       # pivot x, for the debug view
var _probe_local := Vector2.ZERO  # shape center in ROOT space (feeler origin)
var _probe_reach := 100.0         # shape extent + wall_probe_len

# Secondary motion (tail + head)
var _time := 0.0
var _gait_phase := 0.0
var _tail_rest := Vector2.ZERO   # rest position in _bn space (flips/rotates with the art)
var _tail_p := Vector2.ZERO
var _tail_v := Vector2.ZERO
var _head_rest := Vector2.ZERO
var _head_p := Vector2.ZERO
var _head_v := Vector2.ZERO

# Navigation
var _nav: AStarGrid2D
var _nav_origin := Vector2.ZERO    # world center of grid cell (0,0)
var _nav_shape := CircleShape2D.new()
var _band_lo := 3                  # cells from terrain the path hugs (~ride height)
var _dest := Vector2(1e12, 1e12)
var _has_dest := false
var _path := PackedVector2Array()
var _path_i := 0
var _nav_dir := 0.0
var _repath_t := 0.0
var _rebuild_t := 0.0
var _stuck_t := 0.0
var _stuck_n := 0
var _stuck_pos := Vector2.ZERO

# Hunt + combat
var health := 25
var _player: Node2D
var _hunting := false
var _hunt_link := false  # destination_node currently points at OUR player link
var _attack_cd := 0.0
var _stun := 0.0
var _flash := 0.0
var _knock := Vector2.ZERO
var _base_modulate := Color.WHITE


func _ready() -> void:
	if foot_targets.is_empty():
		for n in ["backleg_ankle-left-leg", "backleg_ankle-1"]:
			var node := find_child(n, true, false) as Node2D
			if node:
				foot_targets.append(node)

	if tail_target == null:
		tail_target = find_child("tail", true, false) as Node2D
	if head_target == null:
		head_target = find_child("head2", true, false) as Node2D

	for t in foot_targets:
		var f := Foot.new()
		f.target = t
		f.parent = t.get_parent() as Node2D
		f.home_local = t.position
		f.planted = t.global_position
		for c in t.get_children():
			if c is RayCast2D:
				var r := c as RayCast2D
				f.tip_local = r.transform * r.target_position
				r.enabled = false
				break
		feet.append(f)

	# Shape frame first: the ride measure below is shape-based.
	var sh := _find_shape()
	if sh != null:
		_probe_local = sh.position
		_probe_reach = _shape_extent(sh) + wall_probe_len

	# ride height = how far the SHAPE CENTER sits above the ray tips in the
	# rest pose (shape-based: the root origin can sit far from the body bulk,
	# and on a wall only the shape-to-surface distance is meaningful)
	if ride_height_override > 0.0:
		ride_height = ride_height_override
	elif not feet.is_empty():
		var sc := to_global(_probe_local)
		var sum := 0.0
		for f in feet:
			sum += (f.target.global_position + _tip(f)).y - sc.y
		ride_height = sum / feet.size()
	if ride_height < 1.0:
		push_warning("BeastLegs: ride_height is %.1f - check the RayCast2D target_position on the ankles" % ride_height)

	_dbg = DebugLayer.new()
	_dbg.beast = self
	_dbg.top_level = true
	_dbg.z_index = 4096
	add_child(_dbg)

	if visual_root == null:
		visual_root = get_node_or_null("body") as Node2D
	_bn = visual_root if visual_root != null else self
	_B0 = _bn.position
	_th0 = _bn.rotation
	_phi = _th0
	_vx0 = absf(_bn.scale.x)
	_vy0 = _bn.scale.y
	_pivot_x = _find_pivot_x()
	_facing = -1 if art_faces_left else 1
	# Pivot + rotation frame from the collision shape.
	var sh2 := _find_shape()
	if sh2 != null:
		var host := _bn.get_parent()
		_piv = host.to_local(sh2.global_position) if host != null else sh2.position
	var c0 := cos(_th0)
	var s0 := sin(_th0)
	var d0 := _piv - _B0
	var uq := Vector2(c0 * d0.x + s0 * d0.y, -s0 * d0.x + c0 * d0.y)
	_pq = Vector2(uq.x / _vx0, uq.y / _vy0)
	_apply_body_transform()
	health = max_health
	if _bn is CanvasItem:
		_base_modulate = (_bn as CanvasItem).modulate

	# Secondary targets: remember their rest spot in the art's frame so the
	# home position follows body flips and wall rotation automatically.
	if tail_target:
		_tail_rest = _bn.to_local(tail_target.global_position)
		_tail_p = tail_target.global_position
	else:
		push_warning("BeastLegs: no tail target (name a node 'tail' or assign tail_target)")
	if head_target:
		_head_rest = _bn.to_local(head_target.global_position)
		_head_p = head_target.global_position
	else:
		push_warning("BeastLegs: no head target (name a node 'head2' or assign head_target)")

	print("BeastLegs ready. feet: ", feet.size(), "  ride_height: ", ride_height, "  mask: ", surface_mask)


func _unhandled_input(event: InputEvent) -> void:
	if not click_to_set_destination:
		return
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		set_destination(get_global_mouse_position())


func _read_move() -> float:
	if test_drive != 0.0:
		return signf(test_drive)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		# manual override. Projected onto the surface tangent so "toward the
		# mouse" also means "up the wall" when the body is on one
		var dt := (get_global_mouse_position() - global_position).dot(_tan)
		if absf(dt) > 20.0:
			return signf(dt)
		return 0.0
	return _nav_move()


# Mirror axis: the collision shape's x, so the art flips in place over the
# body instead of jumping to the other side of the origin.
func _find_pivot_x() -> float:
	for c in get_children():
		if c is CollisionShape2D or c is CollisionPolygon2D:
			return (c as Node2D).position.x
	return 0.0


func _find_shape() -> Node2D:
	for c in get_children():
		if c is CollisionShape2D or c is CollisionPolygon2D:
			return c as Node2D
	return null


# Bounding extent of the shape around its own center (so feelers start at
# the shape, not at the root origin, which can sit far from the body).
func _shape_extent(sh: Node2D) -> float:
	var s: Shape2D = (sh as CollisionShape2D).shape if sh is CollisionShape2D else null
	if s is CircleShape2D:
		return (s as CircleShape2D).radius
	if s is RectangleShape2D:
		var sz := (s as RectangleShape2D).size
		return maxf(sz.x, sz.y) * 0.5
	if s is CapsuleShape2D:
		var cp := s as CapsuleShape2D
		return maxf(cp.radius, cp.height * 0.5)
	return 40.0


func _flip_sign() -> float:
	return float(-_facing if art_faces_left else _facing)


## Flip the art around the pivot. Mirror happens in the body's own
## pre-rotation frame (Node2D scale), composed with the surface-alignment
## rotation -- one rigid transform, pieces cannot scatter or drift off the
## collision. The tail/head spring state is carried across the flip in the
## art's local frame, so they keep their shape and the tail whips.
func _face(dir: int) -> void:
	if dir == 0 or dir == _facing:
		return
	var old_gt := _bn.global_transform
	_facing = dir
	_apply_body_transform()
	_flip_secondary(old_gt)


func _flip_secondary(old_gt: Transform2D) -> void:
	var inv := old_gt.affine_inverse()
	var new_gt := _bn.global_transform
	if tail_target:
		var lo := inv.basis_xform(_tail_p - old_gt * _tail_rest)
		var lv := inv.basis_xform(_tail_v)
		_tail_p = new_gt * _tail_rest + new_gt.basis_xform(lo)
		_tail_v = new_gt.basis_xform(lv) + (_up * 0.6 - _fwd() * 0.4) * tail_turn_kick
	if head_target:
		var ho := inv.basis_xform(_head_p - old_gt * _head_rest)
		var hv := inv.basis_xform(_head_v)
		_head_p = new_gt * _head_rest + new_gt.basis_xform(ho)
		_head_v = new_gt.basis_xform(hv)


# Recompute the art node's full transform from the smoothed angle (_phi)
# and the facing sign: rotate about the pivot, mirror about the body axis.
func _apply_body_transform() -> void:
	if _bn == null:
		return
	var f := _flip_sign()
	_bn.rotation = _phi
	_bn.scale = Vector2(f * _vx0, _vy0)
	var loc := Vector2(f * _vx0 * _pq.x, _vy0 * _pq.y)
	var c := cos(_phi)
	var s := sin(_phi)
	_bn.position = _piv - Vector2(c * loc.x - s * loc.y, s * loc.x + c * loc.y)


func _physics_process(delta: float) -> void:
	_tan = Vector2(-_up.y, _up.x)
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	_stun = maxf(_stun - delta, 0.0)
	if _flash > 0.0:
		_flash -= delta
		if _bn is CanvasItem:
			(_bn as CanvasItem).modulate = hit_flash_color if _flash > 0.0 else _base_modulate
	_hunt_tick()
	_nav_tick(delta)
	move_dir = _read_move()
	_water_mult = 1.0
	if not is_in_group("water_creature") and WaterQuery.body_in_water(self):
		_water_mult = water_speed_mult
	# No thrust in mid-air: a crawler that loses its surface brakes instead
	# of launching off the edge (legs dangle until it lands).
	var want := move_dir * move_speed * _speed_mul * _water_mult if body_ground_ok else 0.0
	if _stun > 0.0:
		want = 0.0 # hit-stunned: legs still work, but no voluntary motion
	var rate := accel if body_ground_ok else accel * 3.0
	vel_t = move_toward(vel_t, want, rate * delta)

	if climb_walls:
		_update_surface(delta)
		_tan = Vector2(-_up.y, _up.x)

	# Kinematic step, but collision-guarded: never phase into a wall/floor,
	# or the surface probes go insane inside solid geometry. If blocked,
	# hold still -- the wall feeler rotates the body onto the face instead.
	# Sub-stepped: test_move only checks the target pose, so one long step
	# could jump clean over a thin wall.
	_guarded_move(_tan * vel_t * delta)
	# Knockback from hits rides along as a decaying shove (same guards).
	if _knock.length_squared() > 1.0:
		_guarded_move(_knock * delta)
		_knock = _knock.move_toward(Vector2.ZERO, 1600.0 * delta)
	# Emergency eject: if anything ever overlaps us, let the physics server
	# push the body out along the CONTACT NORMAL (move_and_slide recovers
	# penetration even with zero velocity). Never shove blindly along _up --
	# that slides the body along the inside of a wall instead of out of it.
	up_direction = _up
	velocity = Vector2.ZERO
	move_and_slide()
	if move_dir != 0.0:
		_face(int(move_dir))

	if snap_to_ground:
		_snap_to_surface(delta)

	_update_feet(delta)
	_update_secondary(delta)
	_attack_tick()

	if _dbg:
		_dbg.visible = debug_draw
		_dbg.queue_redraw()


func _ray(from: Vector2, to: Vector2) -> Dictionary:
	var q := PhysicsRayQueryParameters2D.create(from, to, surface_mask)
	q.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_ray(q)


# Move in collision-safe chunks: a single long step could tunnel past thin
# geometry because test_move only tests the target pose, not the swept path.
func _guarded_move(step: Vector2, chunk := 8.0) -> void:
	if step.length_squared() < 0.000001:
		return
	var n := mini(int(ceil(step.length() / chunk)), 32)
	var part := step / float(n)
	for i in n:
		if test_move(global_transform, part):
			break
		global_position += part


## Body up follows the surface normal so floors, walls and ceilings are all
## walkable. While moving, a feeler ahead looks for a wall: a wall whose
## normal differs from the current up wins over the floor probe, which is
## what starts the floor -> wall rotation. If the surface under the body
## ends (convex edge / ledge top), a wrap probe looks back round the corner
## so the body rotates onto the new face instead of dropping or flying.
func _update_surface(delta: float) -> void:
	var target := _up
	var found := false
	var sc0 := to_global(_probe_local)
	_wall_ok = false
	_wrap_hold = maxf(_wrap_hold - delta, 0.0)

	if move_dir != 0.0:
		# Feeler starts at the collision shape's center and reaches past it:
		# the root origin can sit far behind the body's leading edge.
		_wall_from = sc0
		var ahead := _ray(_wall_from, _wall_from + _tan * move_dir * _probe_reach)
		_wall_ok = not ahead.is_empty()
		if _wall_ok:
			_wall_hit = ahead.position
			var n := (ahead.normal as Vector2).normalized()
			if absf(n.angle_to(_up)) > deg_to_rad(30.0):
				target = n
				found = true

	if not found:
		# Down-probe from the shape center, short on purpose: a surface
		# further than ride + tolerance is not "ground".
		var reach := ride_height + ground_tolerance
		var down_hit := _ray(sc0 + _up * 30.0, sc0 - _up * reach)
		if not down_hit.is_empty():
			target = (down_hit.normal as Vector2).normalized()
			found = true
		elif move_dir != 0.0:
			# Convex edge: start inside the empty space past the edge and
			# shoot back along the way we came to find the new face.
			var back := -_tan * move_dir
			var o := sc0 - _up * (ride_height + ground_tolerance * 0.5)
			var wrap := _ray(o, o + back * (reach + 40.0))
			if not wrap.is_empty():
				var wn := (wrap.normal as Vector2).normalized()
				var ang := absf(wn.angle_to(_up))
				if ang > deg_to_rad(40.0) and ang < deg_to_rad(140.0):
					target = wn
					found = true
					_wrap_hold = 0.4

	if found:
		_no_ground = 0.0
	else:
		_no_ground += delta
		if _no_ground > 0.35:
			target = Vector2.UP
	var k := 1.0 - exp(-align_speed * delta)
	_up = (_up.lerp(target, k)).normalized()
	# Body angle = rest angle + rotation from world-up to body-up. The root
	# itself never rotates (so the collision shape and pivot math stay put);
	# only the art node turns, about the shape center.
	_phi = _th0 + wrapf(_up.angle() - Vector2.UP.angle(), -PI, PI)
	_apply_body_transform()


func _snap_to_surface(delta: float) -> void:
	# All distances measured from the shape center: on a wall the root
	# origin can sit far behind the body, and root-based snap would drag
	# the shape INTO the surface.
	var sc := to_global(_probe_local)
	# Short reach: only a surface within ride + tolerance counts as ground.
	# (A long ray hit the far wall across an opening and dragged the body
	# over the gap.) Spawn gets a long reach once, to find the floor.
	var reach := 2000.0 if _first_snap else ride_height + ground_tolerance
	_body_from = sc + _up * 30.0
	_body_to = sc - _up * reach
	var hit := _ray(_body_from, _body_to)
	body_ground_ok = not hit.is_empty()
	if not body_ground_ok:
		if _wrap_hold > 0.0:
			# rounding a corner: hold position while the body rotates round
			body_ground_ok = true
			_fall = 0.0
			return
		# airborne: fall straight down (guarded), feet dangle till landing
		_fall = minf(_fall + 980.0 * delta, 900.0)
		_guarded_move(Vector2.DOWN * _fall * delta)
		return
	_fall = 0.0
	_body_hit = hit.position
	if _first_snap:
		# spawn flush: sit at ride height AND take the surface's orientation
		_up = (hit.normal as Vector2).normalized()
		_phi = _th0 + wrapf(_up.angle() - Vector2.UP.angle(), -PI, PI)
		_apply_body_transform()
		global_position = hit.position + _up * ride_height - (sc - global_position)
		_first_snap = false
		return
	# correct only along the normal: never fights tangent motion.
	# Rate-limited and collision-guarded: rest against a surface, never
	# enter it, never get yanked across a gap.
	var err: float = (sc - hit.position).dot(_up) - ride_height
	var step := err * (1.0 - exp(-height_follow * delta))
	var lim := max_snap_speed * delta
	_guarded_move(-_up * clampf(step, -lim, lim))


func _tip(f: Foot) -> Vector2:
	return f.target.global_transform.basis_xform(f.tip_local)


func _home_world(f: Foot) -> Vector2:
	return f.parent.to_global(f.home_local)


# Where the ankle should be so the ray TIP touches the ground. Null if no ground.
# If the home ray misses (body rotating onto a wall, cresting an edge), the
# foot keeps its planted spot when that is still on something reachable --
# legs stay on the floor/wall instead of dangling mid-transition.
func _ideal(f: Foot, lead: Vector2):
	var tip := _tip(f)
	var dir := tip.normalized()
	var origin := _home_world(f) + lead - dir * ray_raise
	var end := origin + dir * (ray_raise + tip.length() * ray_reach)
	f.dbg_from = origin
	f.dbg_to = end
	var hit := _ray(origin, end)
	if hit.is_empty():
		if (f.planted - _home_world(f)).length() > max_leg_stretch:
			f.dbg_ok = false
			return null
		origin = f.planted - dir * ray_raise
		end = origin + dir * (ray_raise + tip.length() * ray_reach)
		hit = _ray(origin, end)
		if hit.is_empty():
			f.dbg_ok = false
			return null
	f.dbg_ok = true
	f.dbg_hit = hit.position
	return hit.position - tip


func _update_feet(delta: float) -> void:
	var lead := _tan * vel_t / move_speed * step_distance * stride_lead

	any_grounded = false
	for f in feet:
		if _ideal(f, Vector2.ZERO) != null:
			any_grounded = true

	var stepping := 0
	var best: Foot = null
	var best_d := 0.0
	var best_pos := Vector2.ZERO

	for f in feet:
		if not any_grounded:
			f.stepping = false
			f.planted = _home_world(f)
			f.target.global_position = f.planted
			continue

		if f.stepping:
			var ideal = _ideal(f, lead)
			if ideal != null:
				f.to = ideal
			f.t += delta / step_duration
			if f.t >= 1.0:
				f.stepping = false
				f.planted = f.to
				f.target.global_position = f.planted
			else:
				var k := smoothstep(0.0, 1.0, f.t)
				var arc := sin(f.t * PI)
				f.target.global_position = f.from.lerp(f.to, k) + _up * arc * step_height
				stepping += 1
		else:
			f.target.global_position = f.planted
			var ideal = _ideal(f, lead)
			if ideal != null:
				var d := f.planted.distance_to(ideal)
				if d > step_distance and d > best_d:
					best = f
					best_d = d
					best_pos = ideal

	if best != null and (stepping == 0 or best_d > max_leg_stretch):
		best.from = best.planted
		best.to = best_pos
		best.t = 0.0
		best.stepping = true


# ---------------------------------------------------------------------------
# Navigation
#
# The creature crawls on surfaces, so the route is a contour that hugs the
# terrain at ride height (floors, walls, ceilings, round corners). The grid
# is built from real physics queries against surface_mask, then A* finds the
# way and the creature steers along it with the same movement as manual mode.
# ---------------------------------------------------------------------------

## Send the creature to a world position.
func set_destination(p: Vector2) -> void:
	_dest = p
	_has_dest = true
	_nav_dir = 0.0
	_stuck_n = 0
	_stuck_t = 0.0
	_stuck_pos = to_global(_probe_local)
	var sc := to_global(_probe_local)
	if _nav == null or not _in_nav(p) or not _in_nav(sc):
		_build_nav()
	_repath()
	_repath_t = nav_repath_interval
	_rebuild_t = nav_rebuild_interval


func clear_destination() -> void:
	_has_dest = false
	_path = PackedVector2Array()
	_nav_dir = 0.0


## True while the user is driving by hand: manual input always outranks the
## hunt, which resumes when released.
func _manual_drive() -> bool:
	return test_drive != 0.0 or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)


## Find-and-hunt: link the navigator's destination to the player inside
## aggro range, drop it past deaggro range. Only manages the link it made
## itself (never clears a destination you assigned).
func _hunt_tick() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
	if not hunt_player or _manual_drive() or not is_instance_valid(_player):
		return
	var d := to_global(_probe_local).distance_to(_player.global_position)
	if _hunting:
		if d > deaggro_range:
			_hunting = false
			if _hunt_link:
				destination_node = null
				_hunt_link = false
			clear_destination()
	elif d < aggro_range:
		_hunting = true
		destination_node = _player
		_hunt_link = true


## Bite in range: cooldown + distance check straight onto take_hit.
func _attack_tick() -> void:
	if _attack_cd > 0.0 or _stun > 0.0 or not is_instance_valid(_player):
		return
	if to_global(_probe_local).distance_to(_player.global_position) > attack_range:
		return
	if _player.has_method("take_hit"):
		var dir := signf(_player.global_position.x - global_position.x)
		_player.take_hit(dir if dir != 0.0 else 1.0)
	_attack_cd = attack_cooldown


## Bullets and the dash call this (same signature as CommonEnemy, so the
## existing weapons just work). `force` knockback is divided by power_level.
func take_damage(amount: int = 1, from_pos: Vector2 = Vector2.INF,
		force := -1.0, stun := -1.0) -> void:
	if health <= 0:
		return
	health -= amount
	damaged.emit(amount)
	_flash = hit_flash_time
	if _bn is CanvasItem:
		(_bn as CanvasItem).modulate = hit_flash_color
	var away := Vector2.RIGHT
	if from_pos != Vector2.INF and from_pos != global_position:
		away = (global_position - from_pos).normalized()
	elif is_instance_valid(_player) and _player.global_position != global_position:
		away = (global_position - _player.global_position).normalized()
	var knockback := hit_knockback
	if force >= 0.0:
		knockback = force / maxf(power_level, 0.01)
	_knock += away * knockback
	_stun = stun if stun >= 0.0 else hit_stun
	if health <= 0:
		remove_from_group("enemy")
		died.emit()
		queue_free()


func _nav_center(c: Vector2i) -> Vector2:
	return _nav_origin + Vector2(c) * nav_cell


func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(((p - _nav_origin) / nav_cell).round())


func _in_nav(p: Vector2) -> bool:
	return _nav != null and _nav.is_in_boundsv(_cell_of(p))


@warning_ignore("integer_division")
func _build_nav() -> void:
	var sc := to_global(_probe_local)
	var rect := Rect2(sc, Vector2.ZERO).expand(_dest).grow(nav_margin)
	var size := Vector2i(ceili(rect.size.x / nav_cell), ceili(rect.size.y / nav_cell))
	size = size.clamp(Vector2i.ONE, Vector2i(500, 500))
	_nav_origin = rect.position + Vector2(nav_cell, nav_cell) * 0.5
	_band_lo = maxi(1, roundi(ride_height / nav_cell))

	# 1) which cells touch terrain (shape query, so thin walls count)
	var space := get_world_2d().direct_space_state
	_nav_shape.radius = nav_cell * 0.6
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = _nav_shape
	q.collision_mask = surface_mask
	q.exclude = [get_rid()]
	var dist := PackedInt32Array()
	dist.resize(size.x * size.y)
	dist.fill(-1)
	var queue: Array[int] = []
	for y in size.y:
		for x in size.x:
			q.transform = Transform2D(0.0, _nav_center(Vector2i(x, y)))
			if not space.intersect_shape(q, 1).is_empty():
				dist[y * size.x + x] = 0
				queue.append(y * size.x + x)

	# 2) distance from terrain in cells (8-neighbour BFS), only out to the band
	var cap := _band_lo + 1
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var d := dist[i]
		if d >= cap:
			continue
		var cx := i % size.x
		var cy := i / size.x
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				if ox == 0 and oy == 0:
					continue
				var nx := cx + ox
				var ny := cy + oy
				if nx < 0 or ny < 0 or nx >= size.x or ny >= size.y:
					continue
				var j := ny * size.x + nx
				if dist[j] == -1:
					dist[j] = d + 1
					queue.append(j)

	# 3) walkable = the band of cells one body-height off the terrain
	_nav = AStarGrid2D.new()
	_nav.region = Rect2i(0, 0, size.x, size.y)
	_nav.cell_size = Vector2(nav_cell, nav_cell)
	_nav.offset = _nav_origin
	_nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_nav.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_nav.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_nav.update()
	for y in size.y:
		for x in size.x:
			var d := dist[y * size.x + x]
			var ok := d >= _band_lo and d <= _band_lo + 1
			var id := Vector2i(x, y)
			_nav.set_point_solid(id, not ok)
			if ok:
				# prefer hugging the terrain closely
				_nav.set_point_weight_scale(id, 1.0 + float(d - _band_lo) * 0.6)


func _nearest_open(p: Vector2) -> Vector2i:
	var c := _cell_of(p)
	var best := NO_CELL
	var bd := INF
	for oy in range(-12, 13):
		for ox in range(-12, 13):
			var k := c + Vector2i(ox, oy)
			if not _nav.is_in_boundsv(k) or _nav.is_point_solid(k):
				continue
			var d := _nav_center(k).distance_squared_to(p)
			if d < bd:
				bd = d
				best = k
	return best


func _repath() -> void:
	if _nav == null or not _has_dest:
		return
	var a := _nearest_open(to_global(_probe_local))
	var b := _nearest_open(_dest)
	if a == NO_CELL or b == NO_CELL:
		_path = PackedVector2Array()
		return
	_path = _nav.get_point_path(a, b)
	_path_i = 0


func _nav_tick(delta: float) -> void:
	if not auto_navigate:
		return
	if destination_node != null:
		var dp := destination_node.global_position
		if dp.distance_to(_dest) > nav_cell * 1.5:
			set_destination(dp)
	if not _has_dest:
		return

	var sc := to_global(_probe_local)
	if sc.distance_to(_dest) < ride_height + nav_arrive:
		clear_destination()
		arrived.emit()
		return

	_repath_t -= delta
	if _repath_t <= 0.0:
		_repath_t = nav_repath_interval
		_repath()

	if nav_rebuild_interval > 0.0:
		_rebuild_t -= delta
		if _rebuild_t <= 0.0:
			_rebuild_t = nav_rebuild_interval
			_build_nav()
			_repath()

	# stuck detection: no progress for a while -> re-scan and re-plan; give up after a few tries
	_stuck_t += delta
	if _stuck_t >= nav_stuck_time:
		_stuck_t = 0.0
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or sc.distance_to(_stuck_pos) > 12.0:
			_stuck_n = 0
		else:
			_stuck_n += 1
			_build_nav()
			_repath()
			if _stuck_n >= 3:
				clear_destination()
				path_failed.emit()
		_stuck_pos = sc


func _nav_move() -> float:
	_speed_mul = 1.0
	if not auto_navigate or not _has_dest or _path.size() < 2:
		return 0.0
	var sc := to_global(_probe_local)
	# closest path point in a small forward window = our progress
	var best := _path_i
	var bd := INF
	for i in range(_path_i, mini(_path_i + 8, _path.size())):
		var d := sc.distance_squared_to(_path[i])
		if d < bd:
			bd = d
			best = i
	_path_i = best
	var wi := mini(_path_i + nav_lookahead, _path.size() - 1)
	# steer along the surface toward the lookahead point; a dead zone keeps the
	# last direction so it doesn't dither at corners
	var dt := (_path[wi] - sc).dot(_tan)
	if absf(dt) > 10.0:
		_nav_dir = signf(dt)
	_speed_mul = clampf(sc.distance_to(_dest) / 200.0, 0.4, 1.0)
	return _nav_dir


# ---------------------------------------------------------------------------
# Secondary motion: tail + head
# ---------------------------------------------------------------------------

func _update_secondary(delta: float) -> void:
	_time += delta
	var spd := absf(vel_t) / move_speed
	# advances with distance travelled, so the wave matches the stride
	_gait_phase += vel_t * delta / step_distance * PI
	if tail_target:
		_update_tail(delta, spd)
	if head_target:
		_update_head(delta, spd)


# Direction the creature is heading along the surface.
func _fwd() -> Vector2:
	return _tan * float(_facing)


# Keeps a point out of terrain and kills velocity going into the surface.
func _push_out(p: Vector2, v: Vector2, clearance: float) -> Array:
	var hit := _ray(p + _up * 30.0, p - _up * 30.0)
	if not hit.is_empty():
		var n: Vector2 = hit.normal
		p = hit.position + n * clearance
		v -= n * minf(v.dot(n), 0.0)
	return [p, v]


func _update_tail(delta: float, spd: float) -> void:
	var home := _bn.to_global(_tail_rest)

	# slow travelling wave, bigger when running
	var ph := _time * tail_sway_speed + _gait_phase * 0.5
	var sway := _up * sin(ph) * tail_sway * (0.4 + spd) \
		+ _fwd() * cos(ph * 0.5) * tail_sway * 0.4 * spd

	# weight: hangs on walls, swings underneath on ceilings (m*g/k droop)
	var droop := Vector2.DOWN * (tail_mass * tail_gravity / tail_stiffness)
	var goal := home + sway + droop

	# heavy spring-damper: a = F / m, so a big mass lags, overshoots and swings on
	var acc := ((goal - _tail_p) * tail_stiffness - _tail_v * tail_damping) / tail_mass
	_tail_v += acc * delta
	_tail_p += _tail_v * delta

	# never stray further than the IK chain can reach
	var off := _tail_p - home
	if off.length() > tail_max_offset:
		_tail_p = home + off.normalized() * tail_max_offset

	var r := _push_out(_tail_p, _tail_v, tail_clearance)
	_tail_p = r[0]
	_tail_v = r[1]
	tail_target.global_position = _tail_p


func _update_head(delta: float, spd: float) -> void:
	var home := _bn.to_global(_head_rest)
	var fwd := _fwd()
	var off := Vector2.ZERO

	# stretches out while running
	off += fwd * head_reach * spd

	# bob with the gait + slow breathing
	off += _up * (sin(_gait_phase * 2.0) * head_bob * spd + sin(_time * 1.6) * 2.0)

	# look where it is going (route ahead), else glance toward the mouse
	var navigating := _has_dest and _path.size() > 1
	var look_pt := get_global_mouse_position()
	if navigating:
		look_pt = _path[mini(_path_i + 6, _path.size() - 1)]
	var idle := clampf(1.0 - spd * 3.0, 0.0, 1.0)
	var look_w := maxf(idle, 0.5) if navigating else idle
	if look_w > 0.0:
		off += (look_pt - home).limit_length(head_look_range) * 0.5 * look_w

	# anticipate and touch the wall the feeler sees
	if _wall_ok:
		var to_wall := _wall_hit - home
		var close := clampf(1.0 - to_wall.length() / _probe_reach, 0.0, 1.0)
		off += (to_wall - fwd * 8.0 - off) * close * head_wall_touch

	# on a wall/ceiling: lift off the surface and sniff side to side
	var tilt := clampf(absf(_up.angle_to(Vector2.UP)) / (PI * 0.5), 0.0, 1.0)
	off += _up * tilt * 14.0 + fwd * sin(_time * 3.0) * 6.0 * tilt

	_head_v += ((home + off - _head_p) * head_stiffness - _head_v * head_damping) * delta
	_head_p += _head_v * delta

	var r := _push_out(_head_p, _head_v, head_clearance)
	_head_p = r[0]
	_head_v = r[1]
	head_target.global_position = _head_p


# Drawn in world coordinates on the top debug layer
func draw_debug(c: CanvasItem) -> void:
	# body -> ground ray (along surface-in)
	if body_ground_ok:
		c.draw_line(_body_from, _body_hit, Color.WHITE, 1.0)
		c.draw_circle(_body_hit, 4.0, Color.WHITE)
	else:
		c.draw_line(_body_from, _body_to, Color.RED, 1.0)

	# body up + wall feeler
	c.draw_line(global_position, global_position + _up * 60.0, Color.GREEN, 2.0)
	if _wall_ok:
		c.draw_line(_wall_from, _wall_hit, Color.ORANGE, 2.0)
		c.draw_circle(_wall_hit, 5.0, Color.ORANGE)

	for f in feet:
		if f.dbg_ok:
			c.draw_line(f.dbg_from, f.dbg_hit, Color.LIME_GREEN, 3.0)       # ground ray: HIT
			c.draw_circle(f.dbg_hit, 6.0, Color.LIME_GREEN)
		else:
			c.draw_line(f.dbg_from, f.dbg_to, Color.RED, 3.0)               # ground ray: MISS
		c.draw_circle(_home_world(f), 3.0, Color.YELLOW)                     # rest position
		c.draw_circle(f.target.global_position, 5.0, Color.CYAN)             # ankle target
		c.draw_circle(f.target.global_position + _tip(f), 4.0, Color.MAGENTA)  # ray tip

	# tail + head: home (yellow ring) -> live target (orange)
	if tail_target:
		c.draw_arc(_bn.to_global(_tail_rest), 6.0, 0.0, TAU, 16, Color.YELLOW, 1.5)
		c.draw_circle(tail_target.global_position, 5.0, Color.ORANGE)
	if head_target:
		c.draw_arc(_bn.to_global(_head_rest), 6.0, 0.0, TAU, 16, Color.YELLOW, 1.5)
		c.draw_circle(head_target.global_position, 5.0, Color.ORANGE)

	# navigation route + destination
	if _path.size() > 1:
		c.draw_polyline(_path, Color.AQUA, 2.0)
	if _has_dest:
		c.draw_circle(_dest, 8.0, Color.AQUA)

	var msg := "feet: %d  foot rays hit: %s  body ray hit: %s  ride: %.0f  dir: %d  surf: %ddeg  nav: %s  hp: %d%s" % [
		feet.size(), any_grounded, body_ground_ok, ride_height, int(move_dir),
		int(rad_to_deg(Vector2.UP.angle_to(_up))),
		("%d pts" % _path.size()) if _has_dest else "idle", health,
		" HUNT" if _hunting else ""]
	if not body_ground_ok:
		msg += "   NO GROUND FOUND - check surface_mask"
	c.draw_string(ThemeDB.fallback_font, global_position + Vector2(-100, -170), msg,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
