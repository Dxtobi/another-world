class_name Player
extends CharacterBody2D
## Side-view movement + animation selection.
## GunAim owns facing/flip and the gun + hand IK; this script decides which
## animation plays, where the body moves, and tells GunAim what "mode" we're in.
##
## What the gun fires is chosen by GunModes (child node "GunModes"), whose
## FireMode children - Bullets, Portal - each pull the same trigger. This
## script only exposes on_portal_teleported() for portals.

signal hit_taken

enum State { NORMAL, BACKFLIP, VAULT, HIT }
## The dash is three beats, not one: the clip winds up BEFORE anything moves,
## the burst overrides movement, then the pose hangs for a beat after the
## burst while control stays live.
enum DashPhase { NONE, WINDUP, BURST, HOLD }

## How a clip is re-timed against the flight of an arc move.
enum Retime {
	FIT_FLIGHT,   ## stretch/squash so the clip ends exactly when you land
	ALIGN_APEX,   ## line the clip's top-of-flip pose up with the top of the arc
	FIXED,        ## play at `clip_speed` and let the clip run its own length
}

const REQUIRED_ACTIONS := ["move_left", "move_right", "jump", "shoot", "backflip", "vault", "dash", "debug_hit"]
const WATER_QUERY := preload("res://world/water_query.gd")
const WATER_SPLASH := preload("res://world/water_splash.gd")

@export_group("Nodes")
@export var anim: AnimationPlayer
@export var gun_aim: GunAim
@export var gun: Node ## gun scene root (gun.gd); fires through its shoot() method
## What the gun is currently set to fire: bullets, portal, whatever you add.
## A GunModes child owns the list and the selection; this script only forwards
## the trigger. Left empty it is found by name, and if there is no GunModes at
## all the old direct gun.shoot() path still runs.
@export var gun_modes: GunModes
@export var crosshair: Crosshair ## screen cursor + hover scan; feeds auto-fire

@export_group("Animation names")
## If your clips are named differently, type the exact names here.
@export var anim_idle := "idle"
@export var anim_run := "running"
@export var anim_shoot_run := "shoot-and-run"
@export var anim_jump := "jump"
@export var anim_dash := "dash"
@export var anim_land := "landing"
@export var anim_push := "push"
@export var anim_backflip := "backflip"
@export var anim_vault := "vault"
@export var anim_hit := "hit"
## Optional clips. If missing, swim falls back to running / idle.
@export var anim_swim := "swim"
@export var anim_swim_idle := "swim-idle"

@export_group("Animation blending")
## Needs an animation called RESET (see notes). With it, any property a clip
## doesn't animate goes back to its rest value instead of keeping the last
## clip's pose, so nothing carries over from one clip into the next.
@export var reset_between_clips := true
@export var land_must_finish := false ## play the whole landing clip even if you start moving
@export var shoot_linger := 0.3 ## seconds "shooting" sticks after you stop pressing shoot
@export_range(0.0, 0.5, 0.01, "suffix:s") var blend_time := 0.1 ## crossfade between clips
## Once the run clip is playing, keep it for this long even if you stop moving
## or swap direction. Stops the character popping through idle for a few frames
## when you press the other way, and stops a tap of fire mid-run flickering
## between running and shoot-and-run.
@export_range(0.0, 1.0, 0.01, "suffix:s") var run_hold_time := 0.18
## aim_w above which the gun counts as "up" and allowed to fire.
@export_range(0.0, 1.0, 0.05) var shoot_aim_gate := 0.7

@export_group("Run")
@export var run_speed := 280.0
## Above this horizontal speed you count as running (picks run / shoot-and-run).
@export_range(0.0, 400.0, 1.0, "suffix:px/s") var run_enter_speed := 40.0
@export var ground_accel := 2400.0
@export var ground_friction := 2800.0
@export var air_accel := 1400.0
@export var push_speed_mult := 0.5
@export var push_force := 1500.0 ## force on RigidBody2Ds in the "pushable" group

@export_group("Slopes")
## Slopes up to this angle count as floor and carry the walk, in either
## direction (up climbs and down rides the surface). Anything steeper is not
## floor any more: the body leaves the ground and glides down the incline, as
## if the ridge was a slide, instead of standing over it.
@export_range(5.0, 85.0, 1.0, "degrees") var walkable_slope := 45.0
## How hard the body sticks to the ground through descents. Low values let a
## convex ridge launch the player on the way down. 0 disables the stick.
@export_range(0.0, 80.0, 2.0, "suffix:px") var slope_stick := 26.0
## Top glide speed on a too-steep slope, as a share of run speed.
@export_range(0.4, 4.0, 0.05) var glide_speed_mult := 1.3
## How quickly the glide builds toward its top speed (px/s per second).
@export_range(200.0, 4000.0, 50.0, "suffix:px/s") var glide_accel := 1200.0

@export_group("Procedural rig")
## Toggle the SOURCE of the ordinary movement poses (idle, run, air, landing,
## push). ON = a code gait drives the leg IK targets and the torso bone, off
## the rig nodes the soup IK already reads. OFF = the custom clips exactly as
## you authored them, no cleanup needed. Aim hold, dash, backflip, vault and
## hit keep their clips either way, so the gun layer and one-shot moves are
## never affected by this toggle.
@export var use_procedural := false
## Step length of the run gait (rig px, half a full stride's travel).
@export_range(20.0, 260.0, 2.0, "suffix:px(rig)") var proc_stride_len := 92.0
## How high every mid-swing foot lifts off the ground.
@export_range(0.0, 140.0, 2.0, "suffix:px(rig)") var proc_step_height := 26.0
## Torso bob under the steps.
@export_range(0.0, 40.0, 1.0, "suffix:px(rig)") var proc_bob_height := 6.0
## Body lean into the run direction.
@export_range(0.0, 35.0, 0.5, "suffix:°") var proc_lean_deg := 10.0
## Idle breathing bob, fades out once you run.
@export_range(0.0, 20.0, 0.5, "suffix:px(rig)") var proc_breath := 2.5
## Rising jump tucks both feet back and up this much.
@export_range(0.0, 120.0, 2.0, "suffix:px(rig)") var proc_air_tuck := 20.0
## Falling feet dangle this much lower than their rest pose.
@export_range(0.0, 80.0, 2.0, "suffix:px(rig)") var proc_air_dangle := 7.0
## Landing squash depth (px), eased over the landing beat.
@export_range(0.0, 40.0, 1.0, "suffix:px(rig)") var proc_land_squash := 7.0
## Gait clock multiplier: pure feel for how fast the steps ride by.
@export_range(0.4, 2.5, 0.05) var proc_cadence_scale := 1.0

@export_group("Jump")
@export var jump_velocity := -560.0
@export var jump_cut := 0.45 ## velocity multiplier when jump is released early
@export var coyote_time := 0.1
@export var jump_buffer := 0.12
@export var max_fall_speed := 900.0
@export var landing_min_air_time := 0.1 ## filters floor flicker; any real jump lasts longer

@export_group("Backflip")
@export_range(0.0, 800.0, 1.0, "suffix:px") var backflip_distance := 180.0 ## horizontal travel, away from where you face
@export_range(1.0, 600.0, 1.0, "suffix:px") var backflip_height := 110.0 ## peak height above the start
@export_range(0.0, 3.0, 0.01, "suffix:s") var backflip_air_time := 0.0 ## 0 = work it out from height + gravity
@export var backflip_retime: Retime = Retime.FIT_FLIGHT
## Seconds into the backflip clip where the pose is at the top of the flip.
## Only used with Retime.ALIGN_APEX: scrub the clip until this lands on the peak.
@export_range(0.0, 3.0, 0.01, "suffix:s") var backflip_apex_in_clip := 0.55
## Start the clip this far in, so the move doesn't begin with dead frames.
@export_range(0.0, 3.0, 0.01, "suffix:s") var backflip_clip_offset := 0.0
@export_range(0.1, 4.0, 0.05) var backflip_clip_speed := 1.0 ## only used with Retime.FIXED
## End the move the moment you touch the floor again, even if the clip isn't done.
@export var backflip_end_on_land := true
## Keep the move running for at least this long, so a low bump can't cancel it.
@export_range(0.0, 0.5, 0.01, "suffix:s") var backflip_min_time := 0.12

@export_group("Vault")
@export_range(0.0, 800.0, 1.0, "suffix:px") var vault_distance := 140.0 ## horizontal travel, toward where you face
@export_range(1.0, 600.0, 1.0, "suffix:px") var vault_height := 70.0
@export_range(0.0, 3.0, 0.01, "suffix:s") var vault_air_time := 0.0 ## 0 = work it out from height + gravity
@export var vault_retime: Retime = Retime.FIT_FLIGHT
@export_range(0.0, 3.0, 0.01, "suffix:s") var vault_apex_in_clip := 0.6
@export_range(0.0, 3.0, 0.01, "suffix:s") var vault_clip_offset := 0.0
@export_range(0.1, 4.0, 0.05) var vault_clip_speed := 1.0
@export var vault_end_on_land := true
@export_range(0.0, 0.5, 0.01, "suffix:s") var vault_min_time := 0.12

@export_group("Hit")
@export var hit_knockback_speed := 220.0 ## horizontal only, no vertical knockback
@export var hit_cancels_moves := true ## a hit interrupts a backflip / vault in progress
@export_group("Hit flash")
@export var hit_flash_enabled := true
@export var hit_flash_color := Color(4.0, 4.0, 4.0) ## overbright = white-hot blink
@export_range(0.02, 0.5, 0.01, "suffix:s") var hit_flash_time := 0.08

@export_group("Erosion")
## Poison feedback that does NOT knock back or steal control: while it runs the
## rig is tinted sickly green and hit_taken ticks (for future HP), then colors
## restore on their own.
@export_range(0.1, 2.0, 0.05, "suffix:s") var erosion_tick_interval := 0.5
@export var erosion_tint := Color(0.45, 1.5, 0.45)

@export_group("Dash")
## A short horizontal burst. While it lasts the body keeps its animation state
## (run / shoot-and-run / jump all keep playing) but velocity is overridden,
## gravity freezes, the gun stays aimed, and afterimages trail behind.
@export var dash_speed := 900.0
@export_range(0.05, 0.6, 0.01, "suffix:s") var dash_time := 0.18
## Wind-up: the dash clip starts playing this long BEFORE the burst moves
## you, so the rig is already winding up when it goes. Costs this much input
## latency per dash - keep it short.
@export_range(0.0, 0.3, 0.005, "suffix:s") var dash_preroll := 0.07
## After a burst ends the dash pose hangs for this long before normal
## animation resumes. Control stays live throughout; only the pose is held.
@export_range(0.0, 0.5, 0.01, "suffix:s") var dash_hold_time := 0.12
## The afterimage ribbon hangs this long after the burst before it rushes in,
## so the collapse snaps off the impact beat instead of leaking out of it.
@export_range(0.0, 0.5, 0.01, "suffix:s") var dash_reel_delay := 0.06
## The dash clip is 1s long but all of its motion lands in the first
## `dash_pose_time`; the rest just holds the pose. The clip's action is
## retimed to fill the real dash, so the pose arrives exactly as the burst
## ends instead of the rig lagging half a second behind the movement.
@export_range(0.05, 1.5, 0.01, "suffix:s") var dash_pose_time := 0.44
@export_range(0.1, 3.0, 0.05, "suffix:s") var dash_cooldown := 0.65
@export var dash_freeze_gravity := true ## hover flat instead of dipping mid-dash
## What the dash does to whatever it touches. Force knockback is divided by
## the victim's power_level (CommonEnemy), so grunts die/fly and heavies shrug.
@export_range(0, 20) var dash_damage := 3
@export_range(0.0, 3000.0, 50.0) var dash_knockback := 900.0
@export_range(0.0, 1.5, 0.05, "suffix:s") var dash_stun := 0.6
@export_range(0.0, 5000.0, 50.0) var dash_push_force := 1500.0 ## shove to RigidBodies
## Dash scan: one circle query per dash frame finds bodies to phase through AND
## hurt. Bodies in these groups are phased (walls/floors never are, so they
## still block). Anything damageable also takes the hit, once per dash.
@export_range(10.0, 300.0, 5.0, "suffix:px") var dash_radius := 80.0
@export_flags_2d_physics var dash_scan_mask := 5 ## 1 = world/props, 4 = enemies
@export var dash_phase_groups: Array[String] = ["enemy", "pushable"]
@export_group("Afterimages")
## Dash trail. Stamps are placed by DISTANCE, not by the clock: the dash
## measures how far the body actually moved and drops a stamp every
## `afterimage_spacing` pixels along that path. Even spacing at any speed,
## and how many ghosts you get follows the distance actually covered.
@export_range(0.0, 200.0, 2.0, "suffix:px") var afterimage_spacing := 0.0 ## 0 = derive from dash_speed x dash_time / afterimage_max
@export_range(0.1, 2.0, 0.05, "suffix:s") var afterimage_life := 0.55
@export_range(0.05, 1.0, 0.05) var afterimage_opacity := 0.28 ## ghosts start here, fade to 0
## Live ghosts at once. Together with `afterimage_hold_gap` this sets how
## long the ribbon is (count x gap), and it is the main perf dial.
@export_range(1, 24) var afterimage_max := 7
## How hard the survivors reel into you once the dash ends.
@export_range(200.0, 4000.0, 50.0, "suffix:px/s") var afterimage_chase_speed := 1400.0
## While the dash runs, ghosts drift toward whoever is AHEAD of them in the
## trail rather than sitting where they were stamped. This has to beat
## dash_speed, or a fixed time-lag becomes a fixed distance and the ribbon
## stretches out into a row of lagging clones instead of tucking in.
@export_range(0.0, 3000.0, 50.0, "suffix:px/s") var afterimage_drift := 1100.0
## Standoff each ghost keeps from whoever it follows. The ribbon is
## afterimage_max x this long, so this is what stops the trail reading as a
## row of lagging clones.
@export_range(0.0, 200.0, 5.0, "suffix:px") var afterimage_hold_gap := 26.0
@export_range(0.0, 300.0, 5.0, "suffix:px/s") var afterimage_rise := 55.0 ## drift up while dissipating
@export_range(0.0, 0.5, 0.01) var afterimage_swell := 0.08 ## grow as they burn away
@export_range(0.0, 12.0, 0.5) var afterimage_min_part := 3.0 ## skip parts smaller than this on screen (overdraw)
## Per-limb wobble while a ghost holds. OFF by default and worth keeping
## off on weak hardware: it animates every part every frame, which forces a
## full repaint each time (see DashGhost._refresh).
@export_range(0.0, 6.0, 0.2) var afterimage_shimmer := 0.0

@export_group("Water")
## Water is a non-solid volume. Wading and swimming use the same movement
## controller, just slower; deep water adds buoyancy, diving, and a cutaway
## overlay. Feet use the collision capsule's bottom (the actual floor contact),
## while the head probe uses the visible helmet so the overlay starts when the
## head - not the waist - goes under.
@export_range(0.1, 1.0, 0.05) var water_speed_mult := 0.55
@export_range(0.1, 1.0, 0.05) var water_accel_mult := 0.7
@export_range(0.0, 1.0, 0.02) var water_gravity_mult := 0.16
@export var water_max_sink_speed := 220.0
@export var water_max_rise_speed := 260.0
@export var water_swim_speed := 190.0
@export var water_swim_accel := 900.0
@export var water_dive_speed := 180.0
@export_range(0.1, 1.0, 0.02) var water_float_submersion := 0.62
@export var water_buoyancy_spring := 2.6
@export var water_buoyancy_accel := 1100.0
@export_range(0.2, 1.0, 0.02) var water_exit_jump_mult := 0.82
@export var water_swim_impulse := 130.0
@export var water_feet_offset := 227.0
@export var water_head_offset := -235.0
## Z the player uses while the head is under. The water volume lifts its own
## polygon above this (see WaterVolume.underwater_draw_z), so the swimmer is
## covered by the water; keep this at the normal base z unless a scene needs
## the player nudged in the draw order.
@export var water_submerged_z := 0
## Z used when lifting a tag-along cutaway prop above the water canvas (the
## water body itself sits at WaterVolume.underwater_draw_z = 6 while submerged).
@export var water_draw_z := 7
@export var water_ripple_interval := 0.26
## Body submersion (0..1) at which you start swimming when off the floor.
@export_range(0.2, 1.0, 0.02) var water_swim_enter := 0.55
## Drops back out of swimming below this (hysteresis stops flicker at the surface).
@export_range(0.1, 1.0, 0.02) var water_swim_exit := 0.4
## gun_aim mode used while swimming. Use one GunAim already knows; "swim" only
## works if you add a matching case in GunAim.
@export var swim_gun_mode: StringName = &"jump"
## Horizontal and vertical drag when you release the stick (px/s per second).
@export var water_swim_drag := 650.0
## Slow sink while idling fully underwater (px/s). 0 = neutral buoyancy.
@export var water_swim_sink := 18.0
## Pressing jump with the head this close to (or under) the surface hops out. World px.
@export var water_surface_hop_band := 70.0
## Click steering: a swim target counts as reached within this world radius.
@export var water_swim_target_radius := 26.0

@export_group("Deep swim")
## Fully under: clips are suspended and a seal-style controller owns movement + pose.
## Head must be this deep (world px) to enter, and shallower than exit_depth to leave.
@export_range(0.0, 200.0, 1.0, "suffix:px") var deep_enter_depth := 30.0
@export_range(0.0, 200.0, 1.0, "suffix:px") var deep_exit_depth := 8.0
## Stroke strength. Top speed is roughly deep_thrust / deep_drag.
@export var deep_thrust := 350.0
## Water resistance. Low = long glides, high = stops quickly.
@export_range(0.5, 6.0, 0.1) var deep_drag := 1.8
@export var deep_max_speed := 230.0
## How much each stroke pulses the thrust (0 = smooth, 1 = hard kick-and-glide).
@export_range(0.0, 1.0, 0.05) var deep_surge := 0.6
## Idle sink speed. The body never rests, it drifts down at this rate.
@export var deep_sink_speed := 22.0
## How fast the body turns toward its travel direction.
@export_range(1.0, 20.0, 0.5) var deep_turn_rate := 6.0
## Idle pose: horizontal, nose tipped down by this much.
@export_range(0.0, 45.0, 1.0, "suffix:deg") var deep_idle_tilt := 12.0
@export_range(0.0, 30.0, 0.5, "suffix:deg") var deep_wiggle_deg := 8.0
@export_range(0.5, 12.0, 0.1) var deep_idle_cadence := 2.0 ## stroke clock, rad/s
@export_range(0.5, 16.0, 0.1) var deep_move_cadence := 7.0
@export_range(0.0, 60.0, 1.0, "suffix:px(rig)") var deep_flutter_px := 40.0
## How far the dog-paddle stroke stretches the hands down the heading (rig units).
@export_range(0.0, 240.0, 1.0, "suffix:px(rig)") var deep_arm_reach := 110.0
## Pose pointers for the deep pose -- rig units, the same space the IK rests
## use (body/IK local, y+ = down toward the feet, y- = toward the head).
## Legs extend from EACH OWN HIP along deep_leg_dir, so both start at the
## pelvis and stay parallel instead of splaying from their authored rests.
@export var deep_leg_dir := Vector2(0, 1)
@export_range(0.0, 500.0, 1.0, "suffix:px(rig)") var deep_leg_len := 330.0
@export_range(0.0, 80.0, 1.0, "suffix:px(rig)") var deep_leg_sep := 10.0
@export var deep_leg_off_r := Vector2.ZERO ## per-leg fine tune
@export var deep_leg_off_l := Vector2.ZERO
## Hands extend from EACH OWN SHOULDER along deep_hand_dir (toward the head).
@export var deep_hand_dir := Vector2(0, -1)
@export_range(0.0, 300.0, 1.0, "suffix:px(rig)") var deep_hand_len := 140.0
@export_range(0.0, 80.0, 1.0, "suffix:px(rig)") var deep_hand_sep := 0.0
@export var deep_hand_off_r := Vector2.ZERO ## per-hand fine tune
@export var deep_hand_off_l := Vector2.ZERO
## Head: rotate the head bone so the face aims at the world surface (the
## head art's face points along -x, so bone rotation + 180 is the face angle;
## +90 puts the face straight up). Trim the exact aim with the offset, or
## toggle off to let the head ride the body pitch as before.
@export var deep_head_look_up := true
@export_range(-180.0, 180.0, 1.0, "suffix:deg") var deep_head_up_offset_deg := 0.0
## Below this speed the body drifts to its idle pose instead of pointing along velocity.
@export var deep_heading_min_speed := 40.0
## Point in the body node's local space the rotation pivots around (torso centre).
@export var deep_pivot := Vector2.ZERO
@export var deep_hide_gun := true

@export_group("Booster")
## Mini jump-jet: HOLD jump in the air to burn fuel for extra lift. Tap = hop.
@export var booster_enabled := true
@export_range(500.0, 5000.0, 100.0, "suffix:px/s²") var booster_thrust := 2400.0
@export var booster_max_rise := -700.0 ## fastest allowed upward speed
@export_range(0.1, 2.0, 0.05, "suffix:s") var booster_fuel := 0.55 ## seconds of burn
@export_range(0.2, 5.0, 0.1, "suffix:fuel/s") var booster_recharge := 1.6

var state := State.NORMAL
var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

var _state_time := 0.0
var _state_elapsed := 0.0
var _state_ends_on_land := false
var _state_min_time := 0.0
## Gravity for the current arc move, or 0 to use the project's. Set when an arc
## move asks for a specific air time, because the launch speed and the pull both
## have to agree or the arc won't land where `height` says it should.
var _state_gravity := 0.0
var _coyote := 0.0
var _buffer := 0.0
var _air_time := 0.0
var _landing_time := 0.0
var _run_hold := 0.0
var _shoot_timer := 0.0
var _shooting := false
var _was_on_floor := true
var _pushing := false
var _warned := {}
## What the AnimationPlayer was last told to play, so a change of direction on a
## looping clip (shoot-and-run forwards / backwards) actually re-applies.
var _cur_clip := &""
var _cur_speed := 1.0
var _cur_from_end := false
var _body_fx: CanvasItem ## whole rig flashes this on take_hit
var _base_modulate := Color.WHITE
var _flash := 0.0
var _erosion_t := 0.0
var _erosion_tick := 0.0
var _dash_cd := 0.0
var _dash_t := 0.0
var _dash_dir := 1.0
var _dash_spacing := 0.0 ## px between stamps, derived from dash_speed x dash_time
var _dash_stamp_x := 0.0 ## where along the path the last stamp landed
var _dash_phase: DashPhase = DashPhase.NONE
var _windup_t := 0.0     ## left in the WINDUP beat
var _dash_hold_t := 0.0  ## left in the HOLD beat
var _dash_reel_t := 0.0  ## ribbon hang before the ghosts rush in
var _ghosts: Array[DashGhost] = []
var _ghost_src: Array[Sprite2D] = [] # cached rig sprites, walked once
var _ghost_tint := Color(1.0, 0.6, 0.2)
var _ghost_tint_set := false
var _dash_hit: Array[int] = [] ## instance ids already hurt this dash
var _dash_except: Array = [] ## bodies currently phased through
var _ghost_seq := 0
var _fuel := 0.0 ## booster fuel left (seconds of burn)
var _burning := false
var _flame: Node2D ## exhaust flame, visible while the booster burns
var _aim_t := 0.0 ## aim lock after firing: pose held, run ignored

## --- water ------------------------------------------------------------------
var _water_volume: Node
var _in_water := false
var _was_in_water := false
## True while the water owns the pose/movement as a swim (deep enough off the
## floor, or the head is under). Wading stays walking.
var _swimming := false
## Deep swim: fully-under mode (hysteresis in _update_water_state).
var _deep_swim := false      ## fully under (computed in _update_water_state)
var _deep_active := false    ## the pose/anim takeover is currently applied
var _deep_face := 1.0
## Mirrored-space heading: 0 = head up, PI = head down.
var _deep_pitch := PI * 0.5
var _deep_phase := 0.0
## Click steering while in water: point to swim toward (armed by mouse press).
var _swim_target := Vector2.ZERO
var _swim_target_on := false
var _swim_body: Node2D
var _body_rest_pos := Vector2.ZERO
var _body_abs_scale := Vector2.ONE
var _gun_was_visible := true
## Deep-pose anchors, cached in IK-local space at dive entry: each limb is
## driven outward from its own joint, so legs stay together from the pelvis.
var _hip_r := Vector2.ZERO
var _hip_l := Vector2.ZERO
var _shoulder_r := Vector2.ZERO
var _shoulder_l := Vector2.ZERO
var _head_bone: Node2D
var _head_solver: Node
var _water_surface_y := 0.0
var _water_bottom_y := 0.0
var _water_feet_y := 0.0
var _water_head_y := 0.0
var _water_submersion := 0.0
var _water_head_under := false
var _water_head_depth := 0.0
var _water_feet_off := 227.0
var _water_head_off := -235.0
var _water_ripple_t := 0.0
var _underwater_fade := 0.0
var _base_z_index := 0
var _cutaway_saved: Dictionary = {}

## --- procedural rig (the code gait) ----------------------------------------
var _proc_owned := false ## we wrote the rig last frame and owe a teardown
var _proc_rest_r := Vector2.ZERO
var _proc_rest_l := Vector2.ZERO
var _proc_rest_head := Vector2.ZERO
var _proc_hand_r: Node2D
var _proc_hand_l: Node2D
var _proc_rest_hand_r := Vector2.ZERO
var _proc_rest_hand_l := Vector2.ZERO
var _proc_toso_rest := Vector2.ZERO
var _proc_toso_rest_rot := 0.0
var _proc_phase := 0.0 ## gait clock in radians (one foot step = PI)
var _proc_t := 0.0 ## free-running clock for the breath, independent of the gait
var _proc_w := 0.0 ## eased 0..1 blend from the clip rest pose to the code pose
var _ik_root: Node2D ## body/IK, parent of the leg/head targets
var _proc_ik_r: Node2D
var _proc_ik_l: Node2D
var _proc_ik_head: Node2D
var _proc_toso: Bone2D


func _ready() -> void:
	# Fill in anything the inspector left empty.
	if anim == null:
		anim = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if gun_aim == null:
		gun_aim = find_child("GunAim", true, false) as GunAim
	if gun == null:
		for n in find_children("*", "Node2D", true, false):
			if n.has_method("shoot"):
				gun = n
				break
	if crosshair == null:
		crosshair = find_child("Crosshair", true, false) as Crosshair
	if gun_modes == null:
		gun_modes = find_child("GunModes", true, false) as GunModes
	if gun_modes == null:
		push_warning("Player: no GunModes child found; firing straight down `gun`.")

	if anim == null:
		push_error("Player: no AnimationPlayer found. Assign `anim` in the inspector.")
	if gun_aim == null:
		push_error("Player: no GunAim node found. Add one as a child of Player and assign `gun_aim`.")
	if gun == null:
		push_warning("Player: no gun with a shoot() method found. Attach gun.gd to the gun scene's root.")
	_body_fx = gun_aim.body as CanvasItem if gun_aim != null and gun_aim.body != null else null
	if _body_fx == null:
		_body_fx = find_child("body", true, false) as CanvasItem
	if _body_fx != null:
		_base_modulate = _body_fx.modulate
	_fuel = booster_fuel
	_proc_setup() # cache the scene-authored stance before any clip can move it
	# Slopes: the walkable angle and how hard descents stick to the ground.
	# The stick matters when running downhill -- with the default 1px snap the
	# body un-glues every frame and hops down the slope instead of riding it.
	floor_max_angle = deg_to_rad(walkable_slope)
	if slope_stick > 0.0:
		floor_snap_length = slope_stick
	_build_booster_flame()
	_base_z_index = z_index
	for action in REQUIRED_ACTIONS:
		if not InputMap.has_action(action):
			push_warning("Player: input action '%s' is missing from the Input Map." % action)

	if anim != null:
		_check_animation_names()
		if reset_between_clips:
			if anim.has_animation(&"RESET"):
				anim.deterministic = true
			else:
				push_warning("Player: no RESET animation, so poses can carry from one clip into the next. Create one (see notes).")
		_cur_clip = anim.assigned_animation
	set_physics_process(anim != null and gun_aim != null)


## Portals call this on any body that has it (see Portal.gd). A teleport
## cancels anything that depends on where you were standing.
func on_portal_teleported(_portal: Node, _from_pos: Vector2, _to_pos: Vector2) -> void:
	_end_dash(false)
	_coyote = 0.0


func _check_animation_names() -> void:
	# The vault clip is the one most likely to be named differently ("vault-jump", ...).
	if not anim.has_animation(anim_vault):
		for n in anim.get_animation_list():
			var low := String(n).to_lower()
			if low.contains("vault") or low.contains("voul"):
				anim_vault = String(n)
				break
	for clip in [anim_idle, anim_run, anim_shoot_run, anim_jump, anim_dash, anim_land,
			anim_push, anim_backflip, anim_vault, anim_hit]:
		if not anim.has_animation(clip):
			_warn_missing(clip)


func _warn_missing(clip: String) -> void:
	if _warned.has(clip):
		return
	_warned[clip] = true
	push_warning("Player: animation '%s' not found. Your clips: %s"
			% [clip, ", ".join(anim.get_animation_list())])


## Exhaust flame under the body, shown while the booster burns. Built in code
## so no scene changes are needed; parked below the collision shape.
func _build_booster_flame() -> void:
	var flame_y := 34.0
	var flame_x := 0.0
	var col := find_child("CollisionShape2D", true, false) as CollisionShape2D
	if col != null and col.shape != null:
		flame_x = col.position.x
		var half := 30.0
		if col.shape is RectangleShape2D:
			half = (col.shape as RectangleShape2D).size.y * 0.5
		elif col.shape is CapsuleShape2D:
			half = (col.shape as CapsuleShape2D).height * 0.5
		elif col.shape is CircleShape2D:
			half = (col.shape as CircleShape2D).radius
		flame_y = col.position.y + half + 4.0
	_flame = Node2D.new()
	_flame.name = "BoosterFlame"
	_flame.position = Vector2(flame_x, flame_y)
	_flame.visible = false
	add_child(_flame)
	var outer := Polygon2D.new()
	outer.polygon = PackedVector2Array([Vector2(-8, 0), Vector2(8, 0), Vector2(0, 18)])
	outer.color = Color(1.0, 0.45, 0.1, 0.9)
	_flame.add_child(outer)
	var inner := Polygon2D.new()
	inner.polygon = PackedVector2Array([Vector2(-4, 0), Vector2(4, 0), Vector2(0, 11)])
	inner.color = Color(1.0, 0.85, 0.3, 0.95)
	_flame.add_child(inner)


func _physics_process(delta: float) -> void:
	# Fresh aim before anything else runs, so movement and shots in this step
	# use the current mouse, not last render frame's (matters most mid-stride,
	# when the shoulder never stops moving).
	if gun_aim != null and not _deep_swim:
		gun_aim.solve_and_apply()
	var dir := Input.get_axis("move_left", "move_right")

	# "Shooting" sticks for a moment, so tapping fire while running doesn't flicker
	# between running and shoot-and-run, and shooting from idle carries into moving.
	# The trigger is the shoot button OR the crosshair's auto-fire.
	var trigger := Input.is_action_pressed("shoot")
	if crosshair != null and crosshair.want_fire():
		trigger = true
	if _deep_swim:
		trigger = false # no firing underwater
	elif _swimming:
		trigger = false # water owns the mouse: clicks steer the swim, not shoot; the timer can't linger either
	if trigger:
		_shoot_timer = shoot_linger
	else:
		_shoot_timer = maxf(_shoot_timer - delta, 0.0)
	_shooting = trigger or _shoot_timer > 0.0

	_update_water_state(delta, true)
	if not _in_water and not is_on_floor():
		var g := _state_gravity if _state_gravity > 0.0 else gravity
		velocity.y = minf(velocity.y + g * delta, max_fall_speed)
	_dash_cd = maxf(_dash_cd - delta, 0.0)
	_aim_t = maxf(_aim_t - delta, 0.0)

	if _in_water:
		_water_movement(dir, delta)
	elif state == State.NORMAL:
		_normal_movement(dir, delta)
	else:
		# Backflip / vault / hit are locked until their clip is done: no input,
		# just friction once they're back on the ground.
		_run_locked_state(delta)

	move_and_slide()
	_water_clamp_bottom()
	_update_water_state(delta, false)
	_update_water_view()

	_track_landing(delta)
	_detect_push(dir)
	_update_run_hold(delta)
	_update_animation(delta)
	_update_shooting(trigger)
	_update_flash(delta)

	if Input.is_action_just_pressed("debug_hit"):
		take_hit(-gun_aim.facing)


## Reads the non-solid water volume under the feet (or the capsule centre for
## teleports/edge cases). `allow_events` is true for the pre-move sample, where
## crossing the surface should splash and cancel a dash; the post-move sample
## only refreshes depth/z/overlay values.
func _update_water_state(delta: float, allow_events: bool) -> void:
	# The player scene is authored at 0.2 scale; the rig offsets are in local
	# units, so convert them to the world size the waterline lives in.
	var sy := absf(global_scale.y)
	_water_feet_off = water_feet_offset * sy
	_water_head_off = water_head_offset * sy
	var feet := global_position + Vector2(0.0, _water_feet_off)
	var head := global_position + Vector2(0.0, _water_head_off)
	var probe := global_position + Vector2(0.0, 96.0 * sy)
	var world := get_world_2d()
	var area := WATER_QUERY.at_point(world, feet)
	if area == null:
		area = WATER_QUERY.at_point(world, probe)
	if area != null:
		_in_water = true
		_water_volume = area
		_water_surface_y = float(area.get("surface_y"))
		_water_bottom_y = float(area.get("bottom_y"))
		_water_feet_y = feet.y
		_water_head_y = head.y
		var span := maxf(feet.y - head.y, 1.0)
		_water_submersion = clampf((feet.y - _water_surface_y) / span, 0.0, 1.0)
		_water_head_depth = _water_head_y - _water_surface_y
		_water_head_under = _water_head_depth > 0.0
	else:
		_in_water = false
		_water_submersion = 0.0
		_water_head_under = false
		_water_head_depth = 0.0

	# Swim = in the water AND below the surface. Head under always swims; a body
	# floating off the floor swims once it is deep enough, and keeps swimming
	# until it rises past the (lower) exit threshold.
	if not _in_water:
		_swimming = false
	elif _water_head_under:
		_swimming = true
	elif is_on_floor():
		_swimming = false
	else:
		var threshold := water_swim_exit if _swimming else water_swim_enter
		_swimming = _water_submersion >= threshold

	# Fully under, with hysteresis so the surface doesn't flicker the mode.
	if _swimming:
		var need := deep_exit_depth if _deep_swim else deep_enter_depth
		_deep_swim = _water_head_depth >= need
	else:
		_deep_swim = false

	if not allow_events:
		return
	if _in_water and not _was_in_water:
		_on_water_entered()
	elif not _in_water and _was_in_water:
		_on_water_exited()
	_was_in_water = _in_water
	if _in_water:
		_water_ripple_t -= delta
		if _water_ripple_t <= 0.0 and absf(velocity.x) > run_enter_speed \
				and (_water_submersion < 0.82 or _water_head_depth < 40.0):
			_spawn_water_splash(0.34 + minf(absf(velocity.x) / 700.0, 0.35), 0.52)
			_water_ripple_t = water_ripple_interval


func _on_water_entered() -> void:
	# Water cancels a dash/backflip/vault rather than leaving a locked state
	# that would never tick down while the water branch owns movement.
	if state != State.NORMAL:
		state = State.NORMAL
		_state_ends_on_land = false
		_state_gravity = 0.0
	if _dash_phase != DashPhase.NONE:
		_end_dash(false)
	# The entry splash is the reaction; let the walking ripple wait a beat.
	_water_ripple_t = water_ripple_interval
	var strength := clampf(absf(velocity.y) / 420.0, 0.55, 1.65)
	_spawn_water_splash(strength, 0.95)


func _on_water_exited() -> void:
	_swimming = false
	_swim_target_on = false
	_spawn_water_splash(0.55, 0.55)
	_underwater_fade = 0.0
	if is_instance_valid(_water_volume) and _water_volume.has_method("set_underwater"):
		_water_volume.call("set_underwater", 0.0)
	_water_volume = null


func _spawn_water_splash(strength: float, alpha: float) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	# Deform the waterline itself, not just draw rings on top of it.
	if is_instance_valid(_water_volume):
		if _water_volume.has_method("add_wave_source"):
			_water_volume.call("add_wave_source", global_position.x, strength)
		elif _water_volume.has_method("add_surface_wave"):
			_water_volume.call("add_surface_wave", global_position.x, strength)
	var splash := WATER_SPLASH.new()
	scene.add_child(splash)
	splash.global_position = Vector2(global_position.x, _water_surface_y)
	splash.start(strength, alpha)


func _water_movement(dir: float, delta: float) -> void:
	if state != State.NORMAL:
		state = State.NORMAL
		_state_ends_on_land = false
		_state_gravity = 0.0
	if _dash_phase != DashPhase.NONE:
		_end_dash(false)
	_burning = false
	if _flame != null:
		_flame.visible = false

	# Dedicated swim controllers: the wading walk stays below; while swimming
	# the regular or seal-style controller owns movement.
	if _swimming:
		var key := Vector2(dir,
				(1.0 if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_DOWN) else 0.0)
				- (1.0 if Input.is_action_pressed("jump") else 0.0))
		if key.length() > 1.0:
			key = key.normalized()
		var input := key
		# Water mouse steering: holding (or clicking) the mouse swims toward
		# the cursor in all directions. A single click arms a target the body
		# keeps swimming to after release; keyboard input always wins over it.
		if Input.is_action_pressed("shoot"):
			_swim_target = get_global_mouse_position()
			_swim_target_on = true
		elif _swim_target_on and key.is_zero_approx():
			var to_target := _swim_target - global_position
			if to_target.length() < water_swim_target_radius:
				_swim_target_on = false # arrived
			else:
				input = to_target.normalized()
		if _deep_swim:
			_deep_swim_movement(input, delta)
		else:
			_swim_movement(input, delta)
		return

	# Wading controller: walks on the submerged floor with the head above water.
	var on_floor := is_on_floor()
	if _aim_t > 0.0:
		dir = 0.0
	var speed := run_speed * water_speed_mult * (push_speed_mult if _pushing else 1.0)
	var accel := (ground_accel if on_floor else air_accel) * water_accel_mult
	if dir != 0.0:
		velocity.x = move_toward(velocity.x, dir * speed, accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0,
				(ground_friction if on_floor else air_accel) * water_accel_mult * delta)

	var dive := Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_DOWN)
	var swim_up := Input.is_action_pressed("jump")
	var jump_now := Input.is_action_just_pressed("jump")
	if not on_floor and not dive:
		velocity.y = minf(velocity.y + gravity * water_gravity_mult * delta, water_max_sink_speed)
	elif on_floor and velocity.y > 0.0:
		velocity.y = 0.0

	if jump_now:
		if on_floor or _water_submersion < 0.32:
			velocity.y = jump_velocity * water_exit_jump_mult
		else:
			velocity.y = maxf(velocity.y - water_swim_impulse, -water_swim_speed)
	elif swim_up:
		velocity.y = move_toward(velocity.y, -water_swim_speed, water_swim_accel * delta)
	if dive and not jump_now:
		velocity.y = move_toward(velocity.y, water_dive_speed, water_swim_accel * delta)
	if Input.is_action_just_released("jump") and velocity.y < 0.0 and not on_floor:
		velocity.y *= 0.8

	# Neutral buoyancy toward a body mostly above the surface. Standing on a
	# submerged floor skips this: the floor already decides the wading depth.
	if not on_floor and not dive and not swim_up and not jump_now:
		var target_y := _water_surface_y - _water_feet_off \
				+ water_float_submersion * (_water_feet_off - _water_head_off)
		var desired := clampf((target_y - global_position.y) * water_buoyancy_spring,
				-water_max_rise_speed, water_max_sink_speed)
		velocity.y = move_toward(velocity.y, desired, water_buoyancy_accel * delta)

	velocity.y = clampf(velocity.y, -water_max_rise_speed, water_max_sink_speed)


## A dedicated swim controller: 4-directional, drag with inertia, a slow idle
## sink fully underwater, a float-at-the-surface stop, and a hop out of the
## water from the surface layer. Runs while `_swimming`; the wading controller
## below owns everything else.
func _swim_movement(input: Vector2, delta: float) -> void:
	if _aim_t > 0.0:
		input.x = 0.0
	var dir := signf(input.x)

	# Y where the body floats with its head just above the surface.
	var float_y := _water_surface_y - _water_feet_off \
			+ water_float_submersion * (_water_feet_off - _water_head_off)

	# Hop out of the water from the surface layer.
	if Input.is_action_just_pressed("jump") and _water_head_depth < water_surface_hop_band:
		velocity.y = jump_velocity * water_exit_jump_mult
		velocity.x = move_toward(velocity.x, dir * run_speed * water_speed_mult, water_swim_accel * delta)
		return

	# Horizontal: accelerate toward input, drag to a stop otherwise.
	var tx := input.x * water_swim_speed
	var ax := water_swim_accel if input.x != 0.0 else water_swim_drag
	velocity.x = move_toward(velocity.x, tx, ax * delta)

	# Vertical.
	if input.y != 0.0:
		var ty := input.y * (water_dive_speed if input.y > 0.0 else water_swim_speed)
		velocity.y = move_toward(velocity.y, ty, water_swim_accel * delta)
	elif not _water_head_under:
		# Near the surface and idle: spring to the floating height.
		var desired := clampf((float_y - global_position.y) * water_buoyancy_spring,
				-water_max_rise_speed, water_max_sink_speed)
		velocity.y = move_toward(velocity.y, desired, water_buoyancy_accel * delta)
	else:
		# Fully under and idle: coast to a slow sink.
		velocity.y = move_toward(velocity.y, water_swim_sink, water_swim_drag * delta)

	# Swimming up can't carry the body out of the water; it stops at float height.
	if velocity.y < 0.0 and global_position.y <= float_y:
		velocity.y = 0.0

	velocity.y = clampf(velocity.y, -water_max_rise_speed, water_max_sink_speed)


## Seal-style deep swim: stroke pulses push you along your input direction,
## water drag bleeds the speed off, and with no input you glide to a slow sink.
## No standing, no floor logic, no jump.
func _deep_swim_movement(input: Vector2, delta: float) -> void:
	# Each stroke pushes harder at its peak, which gives the kick-and-glide feel.
	var surge := 1.0 + deep_surge * sin(_deep_phase)
	velocity += input * deep_thrust * surge * delta
	# Drag toward the idle sink velocity, so letting go always ends in a slow
	# drift down rather than a dead stop.
	velocity += (Vector2(0.0, deep_sink_speed) - velocity) * (1.0 - exp(-deep_drag * delta))
	velocity = velocity.limit_length(deep_max_speed)


## Deep swim pose owner. Returns true while the takeover is applied, so
## _update_animation stops here and neither clips nor the procedural gait run.
func _deep_swim_pose(delta: float) -> bool:
	if _swim_body == null:
		_swim_body = get_node_or_null("body") as Node2D
	if _deep_swim != _deep_active:
		_deep_active = _deep_swim
		if _deep_active:
			_enter_deep_swim()
		else:
			_exit_deep_swim()
	if not _deep_active:
		return false
	if _swim_body == null:
		return true

	var speed := velocity.length()
	var speed_w := clampf(speed / maxf(deep_max_speed, 1.0), 0.0, 1.0)
	var moving := speed > deep_heading_min_speed

	# Facing follows the horizontal swim direction (with a dead zone so a
	# near-vertical dive doesn't flip it back and forth).
	var d: Vector2 = velocity / speed if moving else Vector2.ZERO
	if moving and absf(d.x) > 0.3:
		_deep_face = signf(d.x)

	# Pitch is kept in mirrored space (0 = head up, PI = head down) so flipping
	# left/right never makes the body spin through the vertical.
	var target := PI * 0.5 + deg_to_rad(deep_idle_tilt)
	if moving:
		target = atan2(_deep_face * d.x, -d.y)
	_deep_pitch = lerp_angle(_deep_pitch, target, 1.0 - exp(-deep_turn_rate * delta))

	_deep_phase = fposmod(_deep_phase
			+ lerpf(deep_idle_cadence, deep_move_cadence, speed_w) * delta, TAU)
	var wiggle := sin(_deep_phase - 0.6) * deg_to_rad(deep_wiggle_deg) * (0.25 + 0.75 * speed_w)

	# Whole-body orientation. The rig stands upright, so rotation 0 = head up
	# and the head points along travel. The collision capsule is a sibling,
	# not a child of `body`, so it stays upright.
	var sc := Vector2(_deep_face * _body_abs_scale.x, _body_abs_scale.y)
	var rot := _deep_face * (_deep_pitch + wiggle)
	_swim_body.scale = sc
	_swim_body.rotation = rot
	# Rotate around deep_pivot instead of the node origin.
	var rest_xf := Transform2D(0.0, sc, 0.0, Vector2.ZERO)
	var now_xf := Transform2D(rot, sc, 0.0, Vector2.ZERO)
	_swim_body.position = _body_rest_pos \
			+ rest_xf.basis_xform(deep_pivot) - now_xf.basis_xform(deep_pivot)

	# Limbs, driven by the exported pose pointers. Each leg extends from its
	# own hip (they sit ~25 rig px apart at the pelvis) along ONE shared
	# direction, so both legs read as a single tail instead of splaying from
	# their authored idle targets. Hands do the same from the shoulders.
	var kick_w := 0.3 + 0.7 * speed_w
	var fl := deep_flutter_px * kick_w
	var leg_swing := Vector2(cos(_deep_phase) * 0.35, sin(_deep_phase)) * fl
	var leg_dir := deep_leg_dir.normalized()
	if _proc_ik_r != null:
		_proc_ik_r.position = _hip_r + leg_dir * deep_leg_len \
				+ Vector2(-deep_leg_sep * 0.5, 0.0) + leg_swing + deep_leg_off_r
	if _proc_ik_l != null:
		_proc_ik_l.position = _hip_l + leg_dir * deep_leg_len \
				+ Vector2(deep_leg_sep * 0.5, 0.0) + leg_swing + deep_leg_off_l
	if _proc_hand_r != null or _proc_hand_l != null:
		var reach := 0.5 + 0.5 * cos(_deep_phase) ### 0 = pulled back, 1 = stretched forward
		var hand_dir := deep_hand_dir.normalized()
		var hand_swing := hand_dir * (deep_arm_reach * reach * kick_w) \
				+ Vector2(sin(_deep_phase) * 8.0, 0.0) * kick_w
		if _proc_hand_r != null:
			_proc_hand_r.position = _shoulder_r + hand_dir * deep_hand_len \
					+ Vector2(-deep_hand_sep * 0.5, 0.0) + hand_swing + deep_hand_off_r
		if _proc_hand_l != null:
			_proc_hand_l.position = _shoulder_l + hand_dir * deep_hand_len \
					+ Vector2(deep_hand_sep * 0.5, 0.0) + hand_swing + deep_hand_off_l
	# Head: face the world surface whichever way the body is pitched. The
	# sprite follows the head bone 1:1, so rotating the bone is exact; the
	# bone's own IK solver is parked while the takeover runs.
	if _head_bone != null and deep_head_look_up:
		_head_bone.global_rotation = PI * 0.5 \
				+ deg_to_rad(deep_head_up_offset_deg)
	elif _proc_ik_head != null:
		_proc_ik_head.position = _proc_rest_head \
				+ Vector2(sin(_deep_phase - 1.0) * fl * 0.15, 0.0)
	if _proc_toso != null:
		_proc_toso.position = _proc_toso_rest
		_proc_toso.rotation = _proc_toso_rest_rot \
				+ sin(_deep_phase - 0.4) * deg_to_rad(5.0) * (0.3 + 0.7 * speed_w)
	return true


func _enter_deep_swim() -> void:
	if _swim_body != null:
		_body_rest_pos = _swim_body.position
		_body_abs_scale = _swim_body.scale.abs()
		_deep_face = signf(_swim_body.scale.x) if _swim_body.scale.x != 0.0 else 1.0
	_deep_pitch = PI * 0.5
	if _proc_toso == null or _ik_root == null:
		_proc_setup() # retry the rig lookup before caching pose anchors
	if _swim_body != null and _ik_root != null:
		var leg_r_b := _swim_body.get_node_or_null("Skeleton2D/toso/leg-r") as Node2D
		var leg_l_b := _swim_body.get_node_or_null("Skeleton2D/toso/leg-l") as Node2D
		var arm_r_b := _swim_body.get_node_or_null("Skeleton2D/toso/spine/upper-arm-r") as Node2D
		var arm_l_b := _swim_body.get_node_or_null("Skeleton2D/toso/spine/upper-arm-l") as Node2D
		if leg_r_b != null and leg_l_b != null:
			_hip_r = _ik_root.to_local(leg_r_b.global_position)
			_hip_l = _ik_root.to_local(leg_l_b.global_position)
		if arm_r_b != null and arm_l_b != null:
			_shoulder_r = _ik_root.to_local(arm_r_b.global_position)
			_shoulder_l = _ik_root.to_local(arm_l_b.global_position)
		_head_bone = _swim_body.get_node_or_null("Skeleton2D/toso/spine/head") as Node2D
		_head_solver = _swim_body.get_node_or_null("soup/head")
	if deep_head_look_up and _head_solver != null:
		_head_solver.set_process(false)
		_head_solver.set_physics_process(false)
	if _proc_owned:
		_proc_restore()
		_proc_owned = false
	if anim != null:
		anim.active = false # clips frozen, nothing animates the rig but us
	if gun_aim != null:
		gun_aim.set_process(false)
		gun_aim.set_physics_process(false)
	if deep_hide_gun and gun is CanvasItem:
		_gun_was_visible = (gun as CanvasItem).visible
		(gun as CanvasItem).visible = false


func _exit_deep_swim() -> void:
	if _swim_body != null:
		_swim_body.rotation = 0.0
		_swim_body.position = _body_rest_pos
		# scale.x is left alone: GunAim re-applies facing on its next solve.
	_proc_restore() # feet, head and torso back to the authored stance
	if _head_solver != null:
		_head_solver.set_process(true)
		_head_solver.set_physics_process(true)
	if _proc_hand_r != null:
		_proc_hand_r.position = _proc_rest_hand_r
	if _proc_hand_l != null:
		_proc_hand_l.position = _proc_rest_hand_l
	if anim != null:
		anim.active = true
		_cur_clip = &"" # force _play() to re-issue a clip instead of assuming one is playing
	if gun_aim != null:
		gun_aim.set_process(true)
		gun_aim.set_physics_process(true)
	if deep_hide_gun and gun is CanvasItem:
		(gun as CanvasItem).visible = _gun_was_visible


## A soft boundary at the painted bottom of the volume. This only catches a
## player who dives past every solid sunken platform; normal stages stand on
## their own underwater floor first.
func _water_clamp_bottom() -> void:
	if not _in_water:
		return
	var limit := _water_bottom_y - _water_feet_off
	if global_position.y > limit:
		global_position.y = limit
		velocity.y = minf(velocity.y, 0.0)


func _update_water_view() -> void:
	# While the head is under, the water volume lifts its polygon above the
	# player (WaterVolume.underwater_draw_z) and its shader refracts the
	# swimmer through the surface, tinted by depth. That reads as "inside the
	# water" instead of the swimmer floating on top of a flat teal fill.
	var cutaway := _in_water and _water_head_under
	z_index = water_submerged_z if cutaway else _base_z_index
	if cutaway:
		for n in get_tree().get_nodes_in_group("water_cutaway"):
			if n is CanvasItem:
				var id := n.get_instance_id()
				if not _cutaway_saved.has(id):
					_cutaway_saved[id] = (n as CanvasItem).z_index
					# Above the lifted water body (underwater_draw_z), so
					# tag-along cutaway props stay readable.
					(n as CanvasItem).z_index = water_draw_z
	else:
		for id in _cutaway_saved:
			var n := instance_from_id(id) as CanvasItem
			if is_instance_valid(n):
				n.z_index = int(_cutaway_saved[id])
		_cutaway_saved.clear()


func _process(delta: float) -> void:
	# The underwater look is drawn by the water volume's own shader (an opaque
	# depth gradient inside the actual water polygon), so there is no full-screen
	# wash over the air above the waterline. The fade only drives the shader's
	# cross-section switch now.
	var target := 1.0 if (_in_water and _water_head_under) else 0.0
	_underwater_fade = lerpf(_underwater_fade, target, 1.0 - exp(-7.0 * delta))
	if is_instance_valid(_water_volume) and _water_volume.has_method("set_underwater"):
		_water_volume.call("set_underwater", _underwater_fade)


func _run_locked_state(delta: float) -> void:
	if is_on_floor() and velocity.y >= 0.0:
		velocity.x = move_toward(velocity.x, 0.0, ground_friction * delta)
	_state_time -= delta
	_state_elapsed += delta
	var landed := _state_ends_on_land and _state_elapsed >= _state_min_time and is_on_floor()
	if landed or _state_time <= 0.0:
		state = State.NORMAL
		_state_ends_on_land = false
		_state_gravity = 0.0


func _normal_movement(dir: float, delta: float) -> void:
	_tick_dash_beats(delta)
	# Dashing overrides everything else this frame but stays in NORMAL, so the
	# animation, gun and shooting all keep working through it.
	if _dash_phase == DashPhase.BURST:
		_run_dash(delta)
		return
	if Input.is_action_just_pressed("dash") and _dash_cd <= 0.0:
		# Allowed from HOLD too: a new dash out of the impact beat is fine.
		# The cooldown was set when the wind-up began, so this cannot re-fire
		# during the wind-up itself.
		_start_dash(dir if dir != 0.0 else gun_aim.facing)
		return
	var on_floor := is_on_floor()
	_coyote = coyote_time if on_floor else _coyote - delta
	_buffer -= delta
	if Input.is_action_just_pressed("jump"):
		_buffer = jump_buffer

	var jumped := false
	# Jump (buffered + coyote) with variable height
	if _buffer > 0.0 and _coyote > 0.0:
		velocity.y = jump_velocity
		_buffer = 0.0
		_coyote = 0.0
		jumped = true
		_release_dash_hold() # a real jump always beats the impact pose
	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= jump_cut

	# Booster: holding jump in the air burns fuel for extra lift (mini jump-jet).
	# Tap = normal hop, hold = higher. Never weaker than a plain jump, refills
	# on the ground.
	_burning = false
	if on_floor:
		_fuel = minf(_fuel + booster_recharge * delta, booster_fuel)
	elif booster_enabled and Input.is_action_pressed("jump") and _fuel > 0.0:
		var cap := minf(jump_velocity, booster_max_rise)
		if velocity.y > cap:
			velocity.y = maxf(velocity.y - booster_thrust * delta, cap)
			_fuel = maxf(_fuel - delta, 0.0)
			_burning = true
	_flame.visible = _burning
	if _burning:
		var f := 0.8 + 0.4 * absf(sin(Time.get_ticks_msec() * 0.06))
		_flame.scale = Vector2(1.0, f)

	# Ground moves (never mid aim-beat: the shot owns those frames)
	if on_floor and _aim_t <= 0.0:
		if Input.is_action_just_pressed("backflip"):
			_start_arc(State.BACKFLIP, &"backflip", anim_backflip, -gun_aim.facing,
					backflip_distance, backflip_height, backflip_air_time,
					backflip_retime, backflip_apex_in_clip, backflip_clip_offset,
					backflip_clip_speed, backflip_end_on_land, backflip_min_time)
			return
		if Input.is_action_just_pressed("vault"):
			_start_arc(State.VAULT, &"vault", anim_vault, gun_aim.facing,
					vault_distance, vault_height, vault_air_time,
					vault_retime, vault_apex_in_clip, vault_clip_offset,
					vault_clip_speed, vault_end_on_land, vault_min_time)
			return

	# Run (locked out mid aim-beat: the pose holds still)
	if _aim_t > 0.0:
		dir = 0.0
	var speed := run_speed * (push_speed_mult if _pushing else 1.0)
	if dir != 0.0:
		velocity.x = move_toward(velocity.x, dir * speed, (ground_accel if on_floor else air_accel) * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, (ground_friction if on_floor else air_accel) * delta)

	# Too-steep ground: instead of jamming against the incline, the body
	# glides down its surface toward the valley (called after the run velocity
	# so the glide can win over a run pressed into the slope).
	_glide_on_steep(delta)


## On a surface steeper than walkable_slope, gravity turns into downhill
## glide. The floor system already refuses such surfaces (is_on_floor() goes
## false), so this picks the steepest slideable contact and steers the
## velocity along its downhill tangent until real floor catches the body.
func _glide_on_steep(delta: float) -> void:
	# Upward motion means a jump or an upward launch: a glide must not fight it.
	if velocity.y < 0.0:
		return
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var n := col.get_normal()
		# Normals in Godot's y-down space: -1.0 = flat floor, 0.0 = wall.
		# Past -cos(45 deg) = -0.707 the surface is steeper than the walkable
		# band. The glide only claims the slope-like band below 75-ish
		# degrees; anything more wall-like falls and slides the normal way so
		# a free fall along a cliff face keeps its own speed.
		if n.y <= -0.707 or n.y >= -0.26:
			continue
		var tangent := Vector2(n.y, -n.x) ## downhill on this incline
		velocity = velocity.move_toward(tangent * (run_speed * glide_speed_mult),
				glide_accel * delta)
		return


func _start_dash(dir: float) -> void:
	# A dash out of the impact beat: any ribbon still hanging collapses now
	# rather than being orphaned.
	_reel_ghosts()
	_dash_dir = signf(dir) if dir != 0.0 else gun_aim.facing
	_dash_cd = dash_cooldown
	# Stamps go down by DISTANCE. Default spacing spreads one dash's worth of
	# travel over the ghost budget, so the cost stays fixed however fast or
	# long the dash is.
	_dash_spacing = afterimage_spacing
	if _dash_spacing <= 0.0:
		_dash_spacing = maxf(10.0, dash_speed * dash_time / float(maxi(afterimage_max, 1)))
	_dash_stamp_x = global_position.x
	_dash_hit.clear()
	# Wind-up first: the clip starts now, the burst starts in dash_preroll.
	_dash_phase = DashPhase.WINDUP
	_windup_t = dash_preroll
	_dash_t = 0.0
	_dash_hold_t = 0.0
	_dash_reel_t = 0.0


## Advance the wind-up and impact beats. The burst counts itself down in
## _run_dash, so it is not ticked here.
func _tick_dash_beats(delta: float) -> void:
	match _dash_phase:
		DashPhase.WINDUP:
			_windup_t -= delta
			if _windup_t <= 0.0:
				_windup_t = 0.0
				_dash_t = dash_time # the burst begins
				_dash_phase = DashPhase.BURST
		DashPhase.HOLD:
			_dash_hold_t -= delta
			if _dash_reel_t > 0.0:
				_dash_reel_t -= delta
				if _dash_reel_t <= 0.0:
					_dash_reel_t = 0.0
					_reel_ghosts()
			if _dash_hold_t <= 0.0:
				_dash_phase = DashPhase.NONE


## Drop the impact pose early because something more important happened.
## Ordinary running does NOT cut it short: it just blends once the hold ends.
func _release_dash_hold() -> void:
	if _dash_phase != DashPhase.HOLD:
		return
	_dash_phase = DashPhase.NONE
	_dash_hold_t = 0.0
	if _dash_reel_t > 0.0:
		_dash_reel_t = 0.0
		_reel_ghosts()


## Drop a stamp every `_dash_spacing` pixels the body actually covers. The
## stamp sits at the exact spacing point along the path, not at wherever the
## body happens to be at the end of the frame, and any spacings outrun in a
## single frame are caught up so the trail never bunches.
func _dash_stamps(delta: float) -> void:
	var x := global_position.x
	var moved := x - _dash_stamp_x
	while absf(moved) >= _dash_spacing:
		var step: float = signf(moved) * _dash_spacing
		_dash_stamp_x += step
		_spawn_afterimage(Vector2(_dash_stamp_x, global_position.y))
		moved = x - _dash_stamp_x


func _run_dash(delta: float) -> void:
	_dash_t -= delta
	velocity.x = _dash_dir * dash_speed
	if dash_freeze_gravity:
		velocity.y = 0.0
	_dash_scan()
	_dash_stamps(delta)
	if _dash_t <= 0.0:
		_end_dash()
	# No move_and_slide here: _physics_process does the single shared one.


## Drop every phase exception. `natural` is true when a burst simply ran its
## course; false when a locked state (hit / backflip / vault) cancels it. Only
## a natural end gets the impact beat - being knocked out of a dash should not
## freeze you in the dash pose.
func _end_dash(natural := true) -> void:
	_dash_t = 0.0
	for n in _dash_except:
		if is_instance_valid(n):
			remove_collision_exception_with(n)
	_dash_except.clear()
	if natural and _dash_phase == DashPhase.BURST:
		# Impact beat: hang on the dash pose while the ribbon hangs too, then
		# let the trail rush in as the pose releases. Control stays live.
		_dash_phase = DashPhase.HOLD
		_dash_hold_t = dash_hold_time
		_dash_reel_t = minf(dash_reel_delay, dash_hold_time)
		if _dash_reel_t <= 0.0:
			_reel_ghosts()
		return
	_dash_phase = DashPhase.NONE
	_dash_hold_t = 0.0
	# The burst is over: whatever trail survived the dash stops holding and
	# rushes into the body.
	_reel_ghosts()


## One circle query finds bodies to pass through AND hurt: exceptions let us
## slide through them, and anything damageable takes the dash hit once.
func _dash_scan() -> void:
	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = dash_radius
	query.shape = circle
	query.transform = Transform2D(0.0, global_position)
	query.collision_mask = dash_scan_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [get_rid()]
	for hit in get_world_2d().direct_space_state.intersect_shape(query):
		var body := hit.collider as CollisionObject2D
		if body == null or body == self:
			continue
		var node := body as Node
		var phase := false
		for group_name in dash_phase_groups:
			if node.is_in_group(group_name):
				phase = true
				break
		if not phase and node.has_method("take_damage") \
				and (body is CharacterBody2D or body is RigidBody2D):
			phase = true
		if phase and not _dash_except.has(body):
			add_collision_exception_with(body)
			_dash_except.append(body)
		var id := body.get_instance_id()
		if _dash_hit.has(id):
			continue
		var hurt := false
		if node.has_method("take_damage"):
			var arity := 1
			for m in node.get_method_list():
				if String(m.name) == "take_damage":
					arity = (m.args as Array).size()
					break
			var dmg := Damage.damage_for(node, global_position, dash_damage)
			if arity >= 4:
				node.take_damage(dmg, global_position, dash_knockback, dash_stun)
			elif arity >= 2:
				node.take_damage(dmg, global_position)
			else:
				node.take_damage(dmg)
			hurt = true
		if body is RigidBody2D:
			(body as RigidBody2D).apply_central_impulse(
					Vector2(_dash_dir * dash_push_force, -dash_push_force * 0.25))
			hurt = true
		if hurt:
			_dash_hit.append(id)


## A snapshot of the rig's pose, drawn as ONE canvas item per ghost (see
## DashGhost), anchored where the body was `at` along the dash path. The rig's
## sprite list is cached once; every stamp only reads the current transforms.
func _spawn_afterimage(at: Vector2) -> void:
	var scene := get_tree().current_scene
	var body_node := get_node_or_null("body") as Node2D
	if scene == null or body_node == null:
		return
	var srcs := _ghost_sources()
	if srcs.is_empty():
		return
	var live: Array[DashGhost] = []
	for g in _ghosts:
		if is_instance_valid(g):
			live.append(g)
	_ghosts = live
	# Over budget: retire the oldest and carry on, so a long or fast dash
	# keeps an evenly spaced ribbon instead of refusing new stamps and
	# leaving a gap. The oldest is the faintest and furthest back, so this
	# is close to invisible.
	while _ghosts.size() >= afterimage_max:
		var old: DashGhost = _ghosts.pop_front()
		if is_instance_valid(old):
			old.reel()
	var anchor := at
	# Ghost-local = world - anchor, so the stored corners survive the ghost
	# being moved and scaled later. This MUST be a pure translation: the Y
	# basis is (0, 1) in Godot's 2D basis, while Vector2.UP is (0, -1) (screen
	# "up"). Using Vector2.UP here flips every corner and throws the whole
	# ghost off-screen.
	var inv := Transform2D(0.0, -anchor)
	var ghost := DashGhost.new()
	_ghost_seq += 1
	ghost.name = "Afterimage%d" % _ghost_seq
	ghost.target = body_node
	ghost.chase_speed = afterimage_chase_speed
	ghost.rise = afterimage_rise
	ghost.swell = afterimage_swell
	ghost.life = afterimage_life
	ghost.peak_alpha = afterimage_opacity
	ghost.shimmer_px = afterimage_shimmer
	ghost.min_part_px = afterimage_min_part
	ghost.tint = _sample_ghost_tint(srcs)
	ghost.hold_drift = afterimage_drift
	ghost.hold_gap = afterimage_hold_gap
	ghost.leader = body_node
	for s in srcs:
		ghost.add_part(s, inv)
	if ghost.parts.is_empty():
		ghost.free()
		return
	# Chain the ribbon: the newest ghost so far now follows this one, so the
	# trail pulls taut from the player forward instead of each ghost sitting
	# on its own.
	if not _ghosts.is_empty():
		var prev := _ghosts[_ghosts.size() - 1]
		if is_instance_valid(prev):
			prev.leader = ghost
	scene.add_child(ghost)
	ghost.global_position = anchor
	ghost.finished.connect(_ghost_finished)
	_ghosts.append(ghost)


## The rig's drawable sprites, cached. Walking the whole subtree on every
## stamp (50x/s) was pure overhead.
func _ghost_sources() -> Array[Sprite2D]:
	if not _ghost_src.is_empty():
		return _ghost_src
	var body_node := get_node_or_null("body")
	if body_node == null:
		return _ghost_src
	for n in body_node.find_children("*", "Sprite2D", true, false):
		var s := n as Sprite2D
		if s != null and s.texture != null:
			_ghost_src.append(s)
	# One canvas item cannot use per-part z_index, so keep the layering by
	# ordering the parts (stable: tree order stands between equals).
	var sorted: Array[Sprite2D] = []
	for s in _ghost_src:
		var at := sorted.size()
		for j in sorted.size():
			if sorted[j].z_index > s.z_index:
				at = j
				break
		sorted.insert(at, s)
	_ghost_src = sorted
	return _ghost_src


## The ghost burns in the rig's OWN palette: the brightest, most saturated
## part colour is sampled once, so a recoloured player tints its own trail.
func _sample_ghost_tint(srcs: Array[Sprite2D]) -> Color:
	if _ghost_tint_set:
		return _ghost_tint
	var best := -1.0
	for s in srcs:
		var c: Color = s.self_modulate * s.modulate
		var score := c.s * c.v
		if score > best:
			best = score
			_ghost_tint = c
	_ghost_tint_set = true
	return _ghost_tint


## The dash is over: survivors stop holding their pose and start collapsing.
func _reel_ghosts() -> void:
	for g in _ghosts:
		if is_instance_valid(g):
			g.reel()


## A ghost dissolved: drop it from the live list (signal, not a sweep).
func _ghost_finished(g: DashGhost) -> void:
	_ghosts.erase(g)


## A leap defined by how far and how high it goes. The launch speeds are worked
## out from gravity, so `distance` and `height` are what you actually see on
## screen. `air_time` > 0 overrides gravity for this move instead of deriving
## the flight from `height`. The clip is then re-timed to match, which is what
## makes the pose you see line up with the arc.
func _start_arc(new_state: State, mode: StringName, clip: String, dir: float,
		distance: float, height: float, air_time: float, retime: Retime,
		apex_in_clip: float, clip_offset: float, clip_speed: float,
		end_on_land: bool, min_time: float) -> void:
	if not anim.has_animation(clip):
		_warn_missing(clip)
		return
	var clip_len := maxf(anim.get_animation(clip).length, 0.01)
	var offset := clampf(clip_offset, 0.0, clip_len - 0.01)

	var h := maxf(height, 1.0)
	# A symmetric hop: up to `h` and back down to where it started, so
	# flight = 2*sqrt(2h/g). Solve g for a requested flight time instead of
	# leaving it at the project's, because the launch speed below and the pull
	# in _physics_process have to use the same number or the arc won't land
	# where `height` says it should.
	var g := gravity
	var flight := 2.0 * sqrt(2.0 * h / g)
	if air_time > 0.0:
		flight = air_time
		g = 8.0 * h / maxf(flight * flight, 0.0001)
		_state_gravity = g
	var launch := -sqrt(2.0 * g * h)
	var impulse := Vector2(dir * distance / maxf(flight, 0.01), launch)

	# Re-time the clip so the flight and the artwork agree.
	var play_speed := clip_speed
	match retime:
		Retime.FIT_FLIGHT:
			play_speed = (clip_len - offset) / maxf(flight, 0.01)
		Retime.ALIGN_APEX:
			# The clip's apex pose should arrive at the top of the arc, which is
			# half way up a symmetric flight.
			var apex_at := flight * 0.5
			play_speed = maxf(apex_in_clip - offset, 0.01) / maxf(apex_at, 0.01)
		Retime.FIXED:
			play_speed = clip_speed
	play_speed = maxf(play_speed, 0.05)

	_start(new_state, mode, clip, impulse, play_speed, offset)
	_state_ends_on_land = end_on_land
	_state_min_time = maxf(min_time, 0.0)


## Enter a locked one-shot state. The state lasts as long as its clip plays.
func _start(new_state: State, mode: StringName, clip: String, impulse: Vector2,
		play_speed := 1.0, clip_offset := 0.0) -> void:
	if not anim.has_animation(clip):
		_warn_missing(clip)
		return
	play_speed = maxf(play_speed, 0.05)
	state = new_state
	_end_dash(false) # a locked move always cancels an in-flight dash
	velocity = impulse
	_landing_time = 0.0
	_state_time = (anim.get_animation(clip).length - clip_offset) / play_speed
	_state_elapsed = 0.0
	_state_ends_on_land = false
	_play(mode, clip, play_speed, false, clip_offset)


## Call this from enemies / bullets / hazards. knock_dir is -1 or 1 (which way to fling the player).
func take_hit(knock_dir: float) -> void:
	if state == State.HIT:
		return
	if state != State.NORMAL and not hit_cancels_moves:
		return
	# Horizontal knockback only: vertical speed is left alone so gravity behaves normally.
	_start(State.HIT, &"hit", anim_hit, Vector2(knock_dir * hit_knockback_speed, velocity.y))
	_flash = hit_flash_time
	if hit_flash_enabled and _body_fx != null:
		_body_fx.modulate = hit_flash_color
	hit_taken.emit()


func _track_landing(delta: float) -> void:
	_landing_time = maxf(_landing_time - delta, 0.0)
	# Water never counts as a landing: the swim controller owns the pose.
	if _in_water:
		_landing_time = 0.0
	var on_floor := is_on_floor()
	if not on_floor:
		_air_time += delta
	else:
		if not _was_on_floor and _air_time >= landing_min_air_time and state == State.NORMAL:
			_landing_time = anim.get_animation(anim_land).length if anim.has_animation(anim_land) else 0.0
		_air_time = 0.0
	_was_on_floor = on_floor


## Pushing = holding toward a body in the "pushable" group while standing on the floor.
func _detect_push(dir: float) -> void:
	_pushing = false
	if state != State.NORMAL or dir == 0.0 or not is_on_floor():
		return
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var n := col.get_normal()
		if absf(n.x) < 0.7 or signf(-n.x) != signf(dir):
			continue
		var other := col.get_collider()
		if other is Node and (other as Node).is_in_group("pushable"):
			_pushing = true
			if other is RigidBody2D:
				(other as RigidBody2D).apply_central_force(Vector2(dir * push_force, 0.0))
			return


## Hysteresis on "am I running?". Without it, swapping direction drops velocity
## through zero and the character plays idle for a few frames, so starting to
## shoot while moving could land you back on idle -> running instead of going
## straight to shoot-and-run.
func _update_run_hold(delta: float) -> void:
	if state != State.NORMAL:
		_run_hold = 0.0
		return
	if absf(velocity.x) > run_enter_speed:
		_run_hold = run_hold_time
	else:
		_run_hold = maxf(_run_hold - delta, 0.0)


func _is_running() -> bool:
	return absf(velocity.x) > run_enter_speed or _run_hold > 0.0


## Priority: air > landing > push > run > idle.
## Idle is the default when nothing else applies. We never force a pass through
## idle between clips: switching crossfades straight from one clip to the next.
## Swim clip selection: prefers dedicated swim clips, falls back to
## run/idle so the feature works before the clips are authored.
func _swim_clip(moving: bool) -> String:
	if moving:
		if anim.has_animation(anim_swim):
			return anim_swim
		_warn_missing(anim_swim)
		return anim_run
	if anim.has_animation(anim_swim_idle):
		return anim_swim_idle
	if anim.has_animation(anim_swim):
		return anim_swim
	return anim_idle


func _update_animation(delta: float) -> void:
	if _deep_swim_pose(delta):
		return
	# --- procedural toggle -------------------------------------------------------
	# The code gait owns the pose only for ordinary movement. Every special
	# beat (dash), the aim hold, locked states (backflip, vault, hit) and a
	# toggle-off hand the rig straight back to the clips: suspending the
	# player (active = false) keeps each clip exactly where it was, and
	# re-activating resumes it there.
	var proc_move := use_procedural and state == State.NORMAL \
			and _dash_phase == DashPhase.NONE and _aim_t <= 0.0 and not _swimming
	if anim != null and anim.active == proc_move:
		anim.active = not proc_move
	if _proc_owned and not proc_move:
		_proc_restore()
		_proc_owned = false
	if proc_move:
		# The gun layer still needs to know what we are doing; pick the same
		# mode names the clips would have asked for, so aim/hands/face rules
		# keep working unchanged.
		var running := _is_running()
		var mode := &"idle"
		if not is_on_floor():
			mode = &"jump"
		elif _landing_time > 0.0 and (land_must_finish or not running):
			mode = &"land"
		elif _pushing:
			mode = &"push"
		elif running:
			mode = &"shoot_run" if _shooting else &"run"
		gun_aim.mode = mode
		_proc_pose(delta)
		return
	if state != State.NORMAL:
		return # the locked state already started its clip
	if _swimming:
		var moving := absf(velocity.x) > run_enter_speed * 0.4 or absf(velocity.y) > 30.0
		_play(swim_gun_mode, _swim_clip(moving))
		return
	if _dash_phase == DashPhase.HOLD:
		# Impact beat: the pose hangs and _play is not called, so gun_aim stays
		# in "dash" - the aim is never dropped by the hold. Movement, jump and
		# shooting are all still live; only the pose is pinned.
		return
	if _dash_phase != DashPhase.NONE:
		# Wind-up and burst share one clip pass: the action is retimed across
		# the WHOLE of wind-up + burst, so the pose is already developing when
		# the burst starts and peaks exactly as it ends.
		var span: float = dash_preroll + dash_time
		_play(&"dash", anim_dash, dash_pose_time / maxf(span, 0.01))
		return
	if _aim_t > 0.0:
		# Aim beat: hold still, gun up at the cursor like shooting.
		if is_on_floor():
			_play(&"idle", anim_idle)
		else:
			_play(&"jump", anim_jump)
		return
	var running := _is_running()
	if not is_on_floor():
		_landing_time = 0.0
		_play(&"jump", anim_jump)
	elif _landing_time > 0.0 and (land_must_finish or not running):
		_play(&"land", anim_land)
	elif _pushing:
		_play(&"push", anim_push)
	elif running:
		if _shooting:
			# Moving against the way the gun faces: play shoot-and-run in reverse.
			var backwards := signf(velocity.x) != gun_aim.facing
			_play(&"shoot_run", anim_shoot_run, -1.0 if backwards else 1.0, backwards)
		else:
			_play(&"run", anim_run)
	else:
		_play(&"idle", anim_idle)


## ---- procedural rig ---------------------------------------------------------
## The code gait. Leg IK targets get two-phase foot trajectories (a stance
## sweep with no lift, a lifted swing), the torso bone bobs, leans, breathes
## and squashes. Every pose is written additively on top of the stance cached
## in _ready(), so nothing depends on wherever the clips left the rig and the
## authored clips are never modified.


## Cache the scene-authored stance once. Called from _ready so the rest pose
## is the saved neutral stance, not wherever some clip happened to be.
func _proc_setup() -> void:
	_proc_toso = null
	_ik_root = null
	var body := get_node_or_null(^"body") as Node2D
	if body == null:
		return
	# "toso" names both the torso sprite and the bone root, so ask for Bone2D.
	var bones := body.find_children("toso", "Bone2D", true, false)
	if not bones.is_empty():
		_proc_toso = bones[0] as Bone2D
	_ik_root = body.find_child("IK", true, false) as Node2D
	if _ik_root != null:
		_proc_ik_r = _ik_root.find_child("rl", true, false) as Node2D
		_proc_ik_l = _ik_root.find_child("ll", true, false) as Node2D
		_proc_ik_head = _ik_root.find_child("head", true, false) as Node2D
		_proc_hand_r = _ik_root.find_child("rh", true, false) as Node2D
		_proc_hand_l = _ik_root.find_child("lh", true, false) as Node2D
	if _proc_ik_r == null or _proc_ik_l == null or _proc_ik_head == null or _proc_toso == null:
		push_warning("Player: procedural rig needs IK/{rl,ll,head} targets and the toso bone.")
		_ik_root = null
		_proc_toso = null
		return
	_proc_rest_r = _proc_ik_r.position
	_proc_rest_l = _proc_ik_l.position
	_proc_rest_head = _proc_ik_head.position
	if _proc_hand_r != null:
		_proc_rest_hand_r = _proc_hand_r.position
	if _proc_hand_l != null:
		_proc_rest_hand_l = _proc_hand_l.position
	_proc_toso_rest = _proc_toso.position
	_proc_toso_rest_rot = _proc_toso.rotation


## Hand the rig back to the clips: every node we own goes back on the cached
## stance. The AnimationPlayer unpauses the same frame and takes over from
## wherever its clip was parked.
func _proc_restore() -> void:
	if _proc_ik_r != null:
		_proc_ik_r.position = _proc_rest_r
	if _proc_ik_l != null:
		_proc_ik_l.position = _proc_rest_l
	if _proc_ik_head != null:
		_proc_ik_head.position = _proc_rest_head
	if _proc_toso != null:
		_proc_toso.position = _proc_toso_rest
		_proc_toso.rotation = _proc_toso_rest_rot


func _proc_pose(delta: float) -> void:
	if _proc_toso == null:
		_proc_setup() # allows retrying after a first failed lookup
	if _proc_toso == null or _ik_root == null:
		return
	_proc_owned = true
	_proc_t += delta
	_proc_w = move_toward(_proc_w, 1.0, delta * 6.0)
	var w := _proc_w

	# Local space: body.scale.x mirrors the rig, so the IK container's +x axis
	# in world space IS the rig's facing -- local +x offsets are always
	# "forward" no matter which way the body is flipped. (Transform2D.x is the
	# transformed basis column, i.e. local +x expressed in parent space.)
	var facing_x := signf(_ik_root.global_transform.x.x)
	# +1 = moving toward the rig's front (running), -1 = backpedalling.
	var run_local := signf(velocity.x) * facing_x
	var speed_w := clampf(absf(velocity.x) / maxf(run_speed, 1.0), 0.0, 1.0)
	var run_w := smoothstep(0.08, 0.55, speed_w)
	var rise := clampf(-velocity.y / 400.0, 0.0, 1.0)
	var fall := clampf(velocity.y / 400.0, 0.0, 1.0)
	var air_w := 0.0 if is_on_floor() else clampf(_air_time / 0.12, 0.0, 1.0)
	var land_w := 0.0 if air_w > 0.9 else clampf(minf(_landing_time, 0.18) / 0.16, 0.0, 1.0)

	# The gait clock advances by the distance actually covered, so the feet
	# track the ground (no moonwalk on slopes); the clock freezes when idle.
	var rate := absf(velocity.x) / maxf(proc_stride_len, 1.0) * PI * proc_cadence_scale
	_proc_phase = fposmod(_proc_phase + rate * delta, TAU)

	# One step per half cycle: stance sweeps the foot from front contact to
	# back contact (no lift), the swing lifts it and moves it forward again.
	# The authored rest stance has one heel raised, so while running BOTH feet
	# plant on the deepest authored foot's ground line (eased in with the run
	# weight and released back to the rest stance when idle) -- otherwise that
	# leg hovers its whole cycle and reads as dragging.
	var ground := maxf(_proc_rest_r.y, _proc_rest_l.y)
	var half := proc_stride_len * 0.5
	var feet: Array = [[_proc_ik_r, _proc_rest_r, _proc_phase],
			[_proc_ik_l, _proc_rest_l, _proc_phase + PI]]
	for foot in feet:
		var node: Node2D = foot[0]
		var rest: Vector2 = foot[1]
		var ph: float = foot[2]
		var base := Vector2(rest.x, lerpf(rest.y, ground, run_w))
		var run_off := Vector2(
				-cos(ph) * half * run_w * run_local,
				-maxf(0.0, sin(ph)) * proc_step_height * run_w)
		# Air: rising tucks both feet back and up, falling dangles them lower.
		var air_off := Vector2(
				-0.4 * proc_air_tuck * rise,
				-0.7 * proc_air_tuck * rise + proc_air_dangle * fall)
		node.position = base + (run_off * (1.0 - air_w) + air_off * air_w) * w

	# Torso: two bobs per cycle, lean into the run, breathing while idle,
	# squash down on landing (from wherever toso rest sits).
	var bob := -absf(sin(_proc_phase)) * proc_bob_height * run_w
	var breath := sin(_proc_t * 2.2) * proc_breath * (1.0 - run_w) * (1.0 - air_w)
	var lean := deg_to_rad(proc_lean_deg) * run_local * run_w
	_proc_toso.position = _proc_toso_rest + \
			Vector2(0.0, bob + breath + proc_land_squash * land_w) * w
	_proc_toso.rotation = _proc_toso_rest_rot \
			+ (lean - deg_to_rad(4.0) * land_w * run_local) * w

	# The head target counters the bob a touch, so the gaze stays level.
	if _proc_ik_head != null:
		_proc_ik_head.position = _proc_rest_head + \
				Vector2(3.0 * run_local * run_w, (-bob - breath) * 0.35) * w


func _play(mode: StringName, clip: String, speed := 1.0, from_end := false,
		offset := 0.0) -> void:
	gun_aim.mode = mode
	if not anim.has_animation(clip):
		_warn_missing(clip)
		return
	# Re-issue when the clip changes OR when a looping clip flips direction,
	# otherwise play() is never called again and speed_scale / from_end are ignored.
	if _cur_clip == clip and is_equal_approx(_cur_speed, speed) and _cur_from_end == from_end:
		return
	_cur_clip = clip
	_cur_speed = speed
	_cur_from_end = from_end
	anim.speed_scale = speed
	# assigned_animation, so one-shots (jump, landing) hold their last pose
	# instead of restarting every frame once they finish.
	anim.play(clip, blend_time, 1.0, from_end)
	if offset > 0.0:
		anim.seek(offset, true)


## Route the trigger to whichever FireMode is selected. The mode decides
## whether that trigger means "fire once" (portal) or "fire while held"
## (rifle), so this stays a straight forward.
func _update_shooting(trigger: bool) -> void:
	if _deep_swim:
		if gun_modes != null and gun_aim != null:
			# release held fire; barrels stay silent underwater
			gun_modes.pull(false, false, gun_aim.barrel_direction())
		return
	if state != State.NORMAL:
		return
	# aim_w gate: don't fire while the gun is still swinging up from the carry pose
	var aimed: bool = gun_aim.aim_w > shoot_aim_gate
	if gun_modes != null:
		gun_modes.pull(trigger and aimed,
				Input.is_action_pressed("shoot") and aimed,
				gun_aim.barrel_direction())
		return
	# No GunModes node: original behaviour.
	if gun == null or not gun.has_method("shoot"):
		return
	if trigger and aimed:
		gun.shoot(gun_aim.barrel_direction())


## White-hot blink while `_flash` runs, then back to the rig's own colors.
## Erosion tint sits underneath: flash wins while it blinks, tint the rest.
func _update_flash(delta: float) -> void:
	if _erosion_t > 0.0:
		_erosion_t -= delta
		_erosion_tick -= delta
		if _erosion_tick <= 0.0:
			_erosion_tick = erosion_tick_interval
			hit_taken.emit()
	if _flash > 0.0 and _body_fx != null:
		_flash -= delta
		if _flash <= 0.0:
			_body_fx.modulate = erosion_tint if _erosion_t > 0.0 else _base_modulate
	elif _body_fx != null:
		_body_fx.modulate = erosion_tint if _erosion_t > 0.0 else _base_modulate


## Poison from slime: damage-over-time without knockback or control loss.
## Refreshes (never stacks), ticks hit_taken on `erosion_tick_interval`.
func apply_erosion(duration: float) -> void:
	var fresh := _erosion_t <= 0.0
	_erosion_t = maxf(_erosion_t, duration)
	if fresh:
		_erosion_tick = 0.0


func is_eroded() -> bool:
	return _erosion_t > 0.0
