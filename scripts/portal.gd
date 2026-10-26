class_name Portal
extends Area2D
## An open portal on a surface. Anything that touches it, is a CharacterBody2D
## or RigidBody2D, FITS, and has room to arrive, is moved to `destination`.
## The player is not special: enemies, crates and bullets-with-bodies all go.
##
## Bodies can opt out with the "no_portal" group. A body can react by having
##   func on_portal_teleported(portal, from_pos, to_pos) -> void
## (the player uses it to drop its dash).

signal teleported(body: Node2D, from_pos: Vector2, to_pos: Vector2)
signal rejected(body: Node2D, reason: StringName) ## &"too_big" or &"blocked"
signal closed

const NO_PORTAL_GROUP := &"no_portal"
const IMMUNITY_META := &"portal_free_at_msec"

## Art hung under the portal as its frame. Because the tint is `modulate` on
## this node, ANY greyscale art dropped in here gets the pair colour for free -
## nothing has to be told about hues. Leave it empty for the built-in _draw.
@export var border_texture: Texture2D:
	set(v):
		border_texture = v
		if is_instance_valid(_border):
			_border.texture = v
			_fit_border()
## Frame width as a multiple of `span`, measured on the WHOLE texture - so
## the visible art ends up ~0.39x that (portal.png has wide transparent
## margins: 595px of art inside a 1536px canvas). 2.6 makes the visible ring
## come out about as wide as the opening it frames.
@export_range(0.4, 6.0, 0.05) var border_scale := 2.6
## How far the frame's bottom is tucked under the surface, in half-heights.
## Near 0 leaves the ring standing on the surface; more buries it.
@export_range(-1.0, 1.0, 0.05) var border_sink := 0.05

var _border: Sprite2D
var _border_base := Vector2.ONE

@export var destination: PortalDestination
## Another Portal to leave from instead of a fixed station. When this is set the
## two are a pair: walk into one, come out of the other. Left null, the portal
## falls back to `destination` (the station). GunModes keeps this current.
@export var exit_portal: Portal
## Kept in step with PortalDestination so a Portal can stand in for one.
@export_range(0.0, 40.0, 0.5, "suffix:px") var exit_clearance := 2.0
## Size of the opening along the surface. Bodies wider than this don't fit.
@export_range(16.0, 400.0, 1.0, "suffix:px") var span := 96.0
## How far in front of the surface the portal catches bodies.
@export_range(4.0, 120.0, 1.0, "suffix:px") var depth := 30.0
## 0 = stays open until closed or replaced.
@export_range(0.0, 60.0, 0.5, "suffix:s") var lifetime := 0.0
## After arriving, a body ignores ALL portals this long (stops ping-pong).
@export_range(0.0, 3.0, 0.05, "suffix:s") var reentry_cooldown := 0.5
## The tint for this end of the pair. It is applied as `modulate` on the node
## itself, so ANY art hung under the portal - sprites, a greyscale cut-out, a
## ShaderMaterial - is tinted by simply setting this, with no per-draw colour
## needed. The built-in _draw below is deliberately drawn in greys so the
## modulate is the only source of hue.
@export var color := Color(0.3, 0.8, 1.0):
	set(v):
		color = v
		modulate = v
@export_flags_2d_physics var body_mask := 0xFFFFFFFF

## Surface normal: points out of the wall into open space.
var normal := Vector2.UP
var open_amount := 0.0

var _age := 0.0
var _closing := false
var _rejected := {} ## instance_id -> true while a rejected body is still touching


func _ready() -> void:
	collision_layer = 0
	collision_mask = body_mask
	monitorable = false
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = Vector2(span, depth)
	cs.shape = rs
	cs.position = Vector2(0.0, -depth * 0.5) # local up = out of the surface
	add_child(cs)
	_build_border()
	create_tween().tween_property(self, "open_amount", 1.0, 0.18)


## Optional art frame. It is a plain child Sprite2D, so `modulate` on this node
## tints it along with everything else - which is the whole point: the art can
## be greyscale and still come out in the pair's colour.
func _build_border() -> void:
	if border_texture == null:
		return
	_border = Sprite2D.new()
	_border.texture = border_texture
	_border.centered = true
	# it is a child of an Area2D that never collides with art, so nothing to
	# exclude: sprites carry no collision
	add_child(_border)
	_fit_border()


func _fit_border() -> void:
	if not is_instance_valid(_border) or _border.texture == null:
		return
	var tw := float(_border.texture.get_width())
	var th := float(_border.texture.get_height())
	if tw <= 0.0 or th <= 0.0:
		return
	var s := (span * border_scale) / tw
	_border_base = Vector2(s, s)
	_border.scale = _border_base
	# sit the frame on the surface with a little of its bottom tucked under, so
	# the ring reads as set into the wall rather than floating on it
	var half_h := th * s * 0.5
	_border.position = Vector2(0.0, -half_h + half_h * 2.0 * border_sink)


## Call after add_child(). `at` is on the surface, `surface_normal` points out.
func place(at: Vector2, surface_normal: Vector2, dest: PortalDestination) -> void:
	normal = surface_normal.normalized()
	destination = dest
	global_position = at
	global_rotation = normal.angle() + PI * 0.5 # local up -> normal
	# NOTE: colour is NOT taken from the destination. A paired portal is
	# tinted by the gun so the two ends read as different ends of a pair.


func close() -> void:
	if _closing:
		return
	_closing = true
	var tw := create_tween()
	tw.tween_property(self, "open_amount", 0.0, 0.15)
	tw.tween_callback(queue_free)
	closed.emit()


func _process(delta: float) -> void:
	_age += delta
	queue_redraw()
	if lifetime > 0.0 and _age >= lifetime:
		close()


## What this portal leads to: its pair-mate if there is one, otherwise the
## fixed station. Everything the exit needs is read off this, so a Portal and a
## PortalDestination are interchangeable here.
func _exit() -> Node2D:
	if is_instance_valid(exit_portal) and not exit_portal._closing \
			and exit_portal.open_amount > 0.5:
		return exit_portal
	if is_instance_valid(destination) and destination.is_available():
		return destination
	return null


## The pair-mate interface, so one Portal can be another Portal's destination.
func exit_direction() -> Vector2:
	return normal


func exit_position() -> Vector2:
	return global_position


func is_available() -> bool:
	return not _closing and open_amount > 0.5


func _physics_process(_delta: float) -> void:
	if _closing or open_amount < 0.6:
		return
	var exit := _exit()
	if exit == null:
		return
	var touching := get_overlapping_bodies()
	var live := {}
	for b in touching:
		live[b.get_instance_id()] = true
		_try_transport(b)
	for id in _rejected.keys():
		if not live.has(id):
			_rejected.erase(id)


func _try_transport(body: Node2D) -> void:
	if not (body is CharacterBody2D or body is RigidBody2D):
		return # walls, platforms, etc.
	if body.is_in_group(NO_PORTAL_GROUP):
		return
	if Time.get_ticks_msec() < int(body.get_meta(IMMUNITY_META, 0)):
		return
	var bounds := PortalUtil.body_bounds(body)
	if bounds.size == Vector2.ZERO:
		return

	var rigid := body is RigidBody2D
	var exit := _exit()
	if exit == null:
		return
	var n_out: Vector2 = exit.exit_direction()
	var t_in := normal.orthogonal()
	# Rotation that maps "into this portal" onto "out of the destination".
	var angle := n_out.angle() - (-normal).angle()
	var t_out := t_in.rotated(angle)

	# --- does it fit? Measured across the opening at BOTH ends. Characters keep
	# their orientation, so their width at the far end is measured on the far
	# axis; rigid bodies turn with the portal and keep the same extent.
	var ext_in := PortalUtil.extent_along(bounds, t_in)
	var ext_out := ext_in if rigid else PortalUtil.extent_along(bounds, n_out.orthogonal())
	var exit_span: float = exit.span
	var exit_clear: float = exit.exit_clearance
	if ext_in > span or ext_out > exit_span:
		_reject(body, &"too_big")
		return

	# --- where does it arrive? Back edge on the station point, same offset
	# across the opening, kept inside the opening.
	var half_n := (PortalUtil.extent_along(bounds, normal) if rigid \
			else PortalUtil.extent_along(bounds, n_out)) * 0.5
	var limit := maxf(minf(span, exit_span) * 0.5 - ext_in * 0.5, 0.0)
	var off_t := clampf((bounds.get_center() - global_position).dot(t_in), -limit, limit)
	var center_out: Vector2 = exit.exit_position() \
			+ n_out * (half_n + exit_clear) + t_out * off_t
	var center_off := bounds.get_center() - body.global_position
	if rigid:
		center_off = center_off.rotated(angle)
	var origin_out := center_out - center_off

	var rot := angle if rigid else 0.0
	if not PortalUtil.is_clear(body as CollisionObject2D, origin_out, rot):
		_reject(body, &"blocked")
		return

	var from := body.global_position
	if body is CharacterBody2D:
		var cb := body as CharacterBody2D
		cb.global_position = origin_out
		cb.velocity = _exit_velocity(cb.velocity.rotated(angle), n_out)
	else:
		var rb := body as RigidBody2D
		var xf := Transform2D(rb.global_rotation + angle, origin_out)
		var rid := rb.get_rid()
		PhysicsServer2D.body_set_state(rid, PhysicsServer2D.BODY_STATE_TRANSFORM, xf)
		PhysicsServer2D.body_set_state(rid, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY,
				_exit_velocity(rb.linear_velocity.rotated(angle), n_out))

	body.set_meta(IMMUNITY_META, Time.get_ticks_msec() + int(reentry_cooldown * 1000.0))
	if body.has_method("reset_physics_interpolation"):
		body.reset_physics_interpolation()
	if body.has_method("on_portal_teleported"):
		body.on_portal_teleported(self, from, origin_out)
	if exit.has_method("notify_received"):
		exit.notify_received(body, self)
	teleported.emit(body, from, origin_out)


func _exit_velocity(v: Vector2, n_out: Vector2) -> Vector2:
	var exit := _exit()
	var floor_speed := 160.0
	if exit != null:
		var s = exit.get("exit_speed_min")
		if s != null:
			floor_speed = float(s)
	var along := v.dot(n_out)
	if along < floor_speed:
		v += n_out * (floor_speed - along)
	return v


func _reject(body: Node2D, reason: StringName) -> void:
	var id := body.get_instance_id()
	if _rejected.has(id):
		return
	_rejected[id] = true
	rejected.emit(body, reason)


## The mouth as a TEAR in the paper rather than a dome: a ragged slit with
## inset paper layers behind it and a bright torn lip. The ragged edge is
## deterministic per portal (seeded off the instance id) so it does not crawl
## between redraws, but no two portals tear the same way.
func _draw() -> void:
	var a := open_amount
	# the frame opens and closes with the portal, same as the drawn dome
	if is_instance_valid(_border):
		_border.scale = _border_base * a
	if a <= 0.0:
		return
	var breathe := 1.0 + sin(_age * 2.4) * 0.03
	# With art hung under it, the drawn dome is only a glow behind the ring, not
	# the portal itself. Squeeze it in and fade the lip, otherwise the torn
	# edges poke out past the ring where the art tapers toward its base.
	var dw := 0.62 if is_instance_valid(_border) else 1.0
	var da := 0.35 if is_instance_valid(_border) else 1.0
	var half := span * 0.5 * dw * a * breathe
	var h := depth * a * breathe
	var seed := float(get_instance_id() % 997)

	# shadow where the slit meets the surface, so it sits IN the paper.
	# Every colour below is GREY: the hue comes from `modulate`, so swapping
	# this _draw for real art only needs the same modulate to carry across.
	draw_line(Vector2(-half, 0.0), Vector2(half, 0.0),
			Color(0.25, 0.25, 0.25, 0.5 * a * da), 5.0)

	# three paper layers, furthest first (farther = whiter + fainter)
	draw_colored_polygon(_tear(half, h, 1.0, seed), Color(0.55, 0.55, 0.55, 0.16 * a * da))
	draw_colored_polygon(_tear(half, h, 0.66, seed), Color(0.8, 0.8, 0.8, 0.22 * a * da))
	draw_colored_polygon(_tear(half, h, 0.34, seed), Color(1.0, 1.0, 1.0, 0.26 * a * da))

	# the torn lip
	draw_polyline(_tear(half, h, 1.0, seed), Color(1.0, 1.0, 1.0, 0.85 * a * da), 2.0, true)

	# motes lifting out of the slit, so it reads as drawing something in
	for i in 3:
		var t := fmod(_age * 0.5 + float(i) * 0.37 + seed, 1.0)
		var mx := sin(t * 9.0 + seed + float(i)) * half * 0.7
		var my := -h * t * 1.25
		draw_circle(Vector2(mx, my), 1.6 * (1.0 - t) * a,
				Color(1.0, 1.0, 1.0, (1.0 - t) * 0.55 * a))


## One ragged half-slit, scaled toward its base. Local up = out of the surface.
func _tear(half: float, h: float, shrink: float, seed: float) -> PackedVector2Array:
	var s := seed * 0.017
	var pts := PackedVector2Array([Vector2(-half * shrink, 0.0)])
	var steps := 9
	for i in range(1, steps):
		var t := float(i) / float(steps)
		var x := lerpf(-half * shrink, half * shrink, t)
		# two out-of-phase waves = an irregular torn edge, not a wavy line
		var jag := sin(t * 11.0 + s * 3.1) * 3.2 + sin(t * 23.0 + s * 7.7) * 1.7
		pts.append(Vector2(x, -h * shrink + jag))
	pts.append(Vector2(half * shrink, 0.0))
	return pts
