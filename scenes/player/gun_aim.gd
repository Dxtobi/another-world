class_name GunAim
extends Node2D
## Procedural rifle aiming + hand IK layer.
##
## player.gd sets `mode` to say what the character is doing right now.
## For that mode, this node decides:
##   aim   - the gun swings to the mouse
##   hands - hands are pulled onto the gun's grip markers
##   face  - who decides which way the body faces: "mouse", "move" or "lock"
## It runs late in the frame (high process priority) so it lands on top of
## whatever the AnimationPlayer just did, and the IK nodes are bumped to run
## after it. Weights fade, so constraints come off and back on smoothly.
##
## THE PIVOT MUST NOT BE A BONE. Rotating a Bone2D does not stick: the
## Skeleton2D rewrites every bone pose and the two-bone IK lerps the arm
## bones toward its own solution, so the gun ends up fighting the skeleton
## and trails behind the cursor by a frame or more. Put a plain Node2D
## ("GunPivot") under the arm bone, hang the gun off that, and point
## `gun_pivot` at the plain node. The bone then only *carries* the pivot.

const RULES := {
	&"idle":      {"aim": true,  "hands": true,  "face": "mouse"},
	&"shoot_run": {"aim": true,  "hands": true,  "face": "mouse"},
	&"jump":      {"aim": true,  "hands": true,  "face": "mouse"},
	&"land":      {"aim": true,  "hands": true,  "face": "mouse"},
	# A dash freezes gravity and overrides the pose, but the gun stays on the
	# cursor - same as mid-air. Needs its own entry: an unlisted mode falls
	# back to FREE, which would drop the aim and lock the facing mid-burst.
	&"dash":      {"aim": true,  "hands": true,  "face": "mouse"},
	&"run":       {"aim": false, "hands": false, "face": "move"},
	&"push":      {"aim": false, "hands": false, "face": "move"},
	&"backflip":  {"aim": false, "hands": false, "face": "lock"},
	&"vault":     {"aim": false, "hands": false, "face": "lock"},
	&"hit":       {"aim": false, "hands": false, "face": "lock"},
}
## Any mode not listed above is treated as "hands are busy".
const FREE := {"aim": false, "hands": false, "face": "lock"}

const ACT_LEFT := "move_left"   # rename to your input actions
const ACT_RIGHT := "move_right"

## Frame order. Godot runs lower process_priority values FIRST, so these are
## just "how late do I run": animation (0) < skeleton < IK < us < bone sprites.
const PRI_SKELETON := 600
const PRI_IK := 700
const PRI_AIM := 800
const PRI_BONE_SPRITES := 900

@export var body: Node2D ## the node you mirror with scale.x (your "body" node)
@export var gun_pivot: Node2D ## plain Node2D that rotates to aim (NOT a Bone2D)
@export var gun_grip_r: Node2D ## right-hand marker inside the gun scene
@export var gun_grip_l: Node2D ## left-hand marker inside the gun scene
@export var hand_r: Node2D ## IK/rh
@export var hand_l: Node2D ## IK/lh
## Marker at the barrel tip (inside the gun). With it, the MUZZLE aims at the
## mouse instead of the pivot, which is what you want when the mouse is close
## to the player. Put it on the barrel axis (same y as the barrel) or the
## parallax correction below will aim slightly off.
@export var muzzle: Node2D

@export_group("Tuning")
## Direction the barrel points inside the gun scene, measured in `gun_pivot`'s
## un-rotated space. With the gun hung straight off the pivot that is simply the
## gun node's own rotation: 0 = right, 90 = down, 180 = left, -90 = up.
## If the drawn gun and the bullets disagree on direction, this is the number.
@export_range(-180.0, 180.0, 0.5, "suffix:°") var barrel_angle_deg := 0.0
## Where the barrel points when not aiming (0 = straight ahead, 90 = straight down).
@export_range(-180.0, 180.0, 1.0, "suffix:°") var carry_angle_deg := 60.0
## Rotate the extra little bit that puts the muzzle (not the shoulder) on the
## cursor line. Leave it on: with the muzzle on the barrel axis it is a no-op,
## and with the muzzle off-axis it is what makes the shot land on the cursor.
@export var correct_parallax := true
@export var blend_speed := 8.0 ## weight change per second (8 = about 0.12s)
@export var face_deadzone := 12.0 ## px around the player before the body flips
@export_range(0.0, 4000.0, 10.0, "suffix:px") var aim_max_distance := 0.0 ## 0 = no clamp. World pixels, not bone pixels.

## Set by player.gd every frame.
var mode: StringName = &"idle"
var facing := 1.0
var aim_w := 0.0
var hands_w := 0.0
## The rotation written to gun_pivot last frame; used only for reference.
var aim_local_rotation := 0.0


func _ready() -> void:
	process_priority = PRI_AIM # run after the AnimationPlayer so we apply on top of it

	# Fill in anything the inspector left empty, using the names in your scene.
	var root := get_parent()
	if body == null:
		body = root.get_node_or_null("body") as Node2D
	if hand_r == null:
		hand_r = root.find_child("rh", true, false) as Node2D
	if hand_l == null:
		hand_l = root.find_child("lh", true, false) as Node2D
	if gun_pivot == null:
		gun_pivot = _find_by_name(root, ["gunpivot", "pivot"])
	if gun_pivot != null:
		if gun_grip_r == null:
			gun_grip_r = _find_by_name(gun_pivot, ["gun-right", "right-hand", "rh"])
		if gun_grip_l == null:
			gun_grip_l = _find_by_name(gun_pivot, ["gun-left", "left-hand", "lh"])
		if muzzle == null:
			muzzle = _find_by_name(gun_pivot, ["muzzle", "barrel", "tip"])
	if muzzle == null and gun_pivot != null:
		# Last resort: the tip of the gun, so the parallax fix and the bullet
		# spawn point at least agree with each other.
		muzzle = gun_pivot

	# The IK must run AFTER the animation and after we've moved the hand targets,
	# otherwise the arms trail the gun by a frame.
	var soup := root.find_child("soup", true, false)
	if soup != null:
		soup.process_priority = PRI_IK
	for sk in root.find_children("*", "Skeleton2D", true, false):
		sk.process_priority = PRI_SKELETON
	# Bone2D -> Sprite2D copies have to happen after both the skeleton and the
	# IK, or every arm / leg sprite is drawn one frame behind its bone.
	for rt in root.find_children("*", "RemoteTransform2D", true, false):
		rt.process_priority = PRI_BONE_SPRITES

	var needed := {
		"body": body, "gun_pivot": gun_pivot,
		"gun_grip_r": gun_grip_r, "gun_grip_l": gun_grip_l,
		"hand_r": hand_r, "hand_l": hand_l,
	}
	var ok := true
	for key in needed:
		if needed[key] == null:
			push_error("GunAim: couldn't find '%s'. Assign it in the inspector." % key)
			ok = false
	if gun_pivot is Bone2D:
		push_error("GunAim: `gun_pivot` is a Bone2D. The skeleton and the arm IK "\
			+ "rewrite it every frame, so the gun can never track the mouse. Add a "\
			+ "plain Node2D (GunPivot) under the arm bone, hang the gun off that, "\
			+ "and point `gun_pivot` at it instead.")
	set_process(ok)


## First descendant of `root` whose name contains one of `words` (earlier words win).
func _find_by_name(root: Node, words: Array) -> Node2D:
	var nodes := root.find_children("*", "Node2D", true, false)
	for w in words:
		for n in nodes:
			if String(n.name).to_lower().contains(w):
				return n as Node2D
	return null


## Where the mouse is, in world space.
func _mouse_world() -> Vector2:
	var node: CanvasItem = gun_pivot if gun_pivot != null else self
	return node.get_global_mouse_position()


## The exact rotation `gun_pivot.rotation` needs so a shot fired from the muzzle
## lands on the cursor. Pure function of the mouse and the pivot's parent
## transform, so it gives the same answer however many times it is called and no
## matter what the skeleton did last frame.
func solve_aim_rotation() -> float:
	var axis := deg_to_rad(barrel_angle_deg)
	var parent := gun_pivot.get_parent() as Node2D if gun_pivot != null else null
	if parent == null:
		return axis

	# Direction pivot -> cursor, measured in the pivot's PARENT space. The parent
	# frame is the one that does not rotate when we turn the gun, so the answer
	# stays valid while we write it. Because it is the parent's space, the body
	# flip (scale.x = -1) and the bone's own rotation are handled for free.
	# The optional clamp is measured in world pixels first (the parent space is
	# scaled by the rig, so a number typed there would be meaningless).
	var pivot_w := gun_pivot.global_position
	var to_mouse := _mouse_world() - pivot_w
	if aim_max_distance > 0.0 and to_mouse.length() > aim_max_distance:
		to_mouse = to_mouse.normalized() * aim_max_distance
	var d := parent.to_local(pivot_w + to_mouse) - gun_pivot.position
	var dist := d.length()
	var aim := d.angle()

	if correct_parallax and muzzle != null and dist > 0.001:
		# The muzzle sits off the pivot, so pointing the barrel line at the cursor
		# leaves the shot a few degrees off. `to_local` strips the pivot's own
		# rotation, so this offset is the same every frame no matter where the gun
		# currently points.
		var m := gun_pivot.to_local(muzzle.global_position)
		# Only worth correcting while the cursor is outside the circle the muzzle
		# swings on. Closer than that the cursor is inside your own gun, and
		# "shoot back at it" would flip the barrel through 180 degrees.
		if m.length_squared() > 0.0001 and dist > m.length():
			# Perpendicular distance from the muzzle to the barrel axis. Turning
			# the pivot swings the muzzle by the same angle, so subtracting
			# asin(off / dist) is what swings it back onto the cursor. This is the
			# same small-angle term the old code used, but measured against the
			# barrel axis and the pivot -> cursor distance instead of a constant.
			var off := Vector2.RIGHT.rotated(axis).cross(m)
			aim -= asin(clampf(off / dist, -1.0, 1.0))

	# Blended against the carry pose. Both angles are pivot rotations, so the two
	# mean the same thing.
	return lerp_angle(deg_to_rad(carry_angle_deg) - axis, aim - axis, aim_w)


## The world-space direction the barrel is pointing (use it for bullets).
## Recomputed live, from the parent's transform rather than the pivot's, so a
## shot fired from _physics_process leaves the muzzle on exactly the line the gun
## is about to be drawn along instead of one frame behind it.
func barrel_direction() -> Vector2:
	if gun_pivot == null:
		return Vector2.RIGHT.rotated(deg_to_rad(barrel_angle_deg))
	var parent := gun_pivot.get_parent() as CanvasItem
	if parent == null:
		return gun_pivot.global_transform.basis_xform(
				Vector2.RIGHT.rotated(deg_to_rad(barrel_angle_deg))).normalized()
	var local := Vector2.RIGHT.rotated(solve_aim_rotation() + deg_to_rad(barrel_angle_deg))
	return parent.get_global_transform().basis_xform(local).normalized()


func _process(delta: float) -> void:
	var rule: Dictionary = RULES.get(mode, FREE)

	# 1. Facing
	match rule.face:
		"mouse":
			var dx := body.get_global_mouse_position().x - body.global_position.x
			if absf(dx) > face_deadzone:
				facing = signf(dx)
		"move":
			var dir := Input.get_axis(ACT_LEFT, ACT_RIGHT)
			if dir != 0.0:
				facing = signf(dir)
	body.scale.x = absf(body.scale.x) * facing

	# 2. Blend weights: this is what "constraints come off, then back on" means
	aim_w = move_toward(aim_w, 1.0 if rule.aim else 0.0, blend_speed * delta)
	hands_w = move_toward(hands_w, 1.0 if rule.hands else 0.0, blend_speed * delta)

	# 3. Gun -> mouse. Plain math, applied to a plain Node2D: nothing can stomp it.
	solve_and_apply()

	# 4. Hands -> gun grips, blended over whatever the animation just did
	if hands_w > 0.0:
		hand_r.global_position = hand_r.global_position.lerp(gun_grip_r.global_position, hands_w)
		hand_l.global_position = hand_l.global_position.lerp(gun_grip_l.global_position, hands_w)


## Solve the aim from the live mouse and write it to the pivot now. Called
## every render frame from _process, and also every physics frame by the player
## before it moves/shoots, so firing uses this step's aim instead of last
## render frame's. Pure function of mouse + transforms: calling it twice with
## no new input in between answers identically, so the double call is safe.
func solve_and_apply() -> float:
	aim_local_rotation = solve_aim_rotation()
	gun_pivot.rotation = aim_local_rotation
	return aim_local_rotation
