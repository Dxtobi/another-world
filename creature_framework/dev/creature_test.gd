extends Node2D
## Test scene: one vulture-rig creature with a debug HUD.
## Default runs a scripted DemoBrain (metrics on); set CF_MOUSE=1 to chase the cursor instead.

var creature: Creature
var world: WorldQuery
var label: Label
var _cam: Camera2D

var demo: bool = true
var _metrics_t: float = 0.0
var _max_speed_tick: float = 0.0
var _bad_frames: int = 0
var _start: float = 0.0
var _prev_tips: PackedVector2Array = PackedVector2Array()
var _max_tip_jump: float = 0.0
var _tip_jump_window: float = 0.0
var _elapsed: float = 0.0

const RUN_SECONDS := 60.0


func _ready() -> void:
	var size: Vector2 = get_viewport_rect().size
	world = WorldQuery.new()
	world.bounds = Rect2(0.0, 0.0, size.x, size.y - 40.0)

	creature = Creature.new()
	add_child(creature)
	var brain: Brain = DemoBrain.new()   # scripted regimes by default; CF_MOUSE=1 chases the cursor
	if OS.get_environment("CF_MOUSE") != "":
		brain = MouseBrain.new()
	creature.setup(VultureRig.build(), brain, world, Vector2(340.0, 300.0))

	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	label = Label.new()
	label.position = Vector2(12.0, 8.0)
	layer.add_child(label)

	# QA camera: follows the creature so a zoomed close-up is one key away (Z).
	# At zoom 1 the framing is unchanged.
	_cam = Camera2D.new()
	_cam.zoom = Vector2.ONE
	add_child(_cam)
	_cam.make_current()


func _physics_process(dt: float) -> void:
	if not demo or creature.body == null:
		return
	_metrics_t += dt
	var n: int = creature.body.pos.size()
	var vmax: float = 0.0
	for i in n:
		var v: float = (creature.body.pos[i] - creature.body.prev[i]).length() / dt
		if v > vmax:
			vmax = v
		if is_nan(creature.body.pos[i].x) or is_nan(creature.body.pos[i].y):
			_bad_frames += 1
	_max_speed_tick = maxf(_max_speed_tick, vmax)
	_elapsed += dt
	# Largest single-frame limb-tip move: a facing pop shows up here as ~2x reach.
	# Skip the first frames: the pose is still being seeded from the anchors.
	if _elapsed < 0.25:
		_prev_tips = creature.limb_tip.duplicate()
	else:
		for i in creature.limb_tip.size():
			var jump: float = _prev_tips[i].distance_to(creature.limb_tip[i])
			_tip_jump_window = maxf(_tip_jump_window, jump)
			_max_tip_jump = maxf(_max_tip_jump, jump)
			if jump > 80.0:
				print("BIGJUMP t=%.2f limb=%d kind=%s jump=%.1f facing=%.2f anchor_d=%.1f" \
					% [_elapsed, i, creature.rig.limbs[i].kind, jump, creature.facing, creature.anchor_pos(i).distance_to(creature.body.pos[creature.rig.center_point])])
	_prev_tips = creature.limb_tip.duplicate()
	if _metrics_t >= 0.5:
		_metrics_t = 0.0
		var p: Vector2 = creature.body.pos[creature.rig.center_point]
		var regime: String = "manual"
		var b: Brain = creature.brain
		if b is DemoBrain:
			regime = (b as DemoBrain).regime_label()
		print("t=%05.1f regime=%-5s pos=%4.0f,%4.0f vmax=%5.0f thrust=%.2f flap=%.1f tipjump=%4.1f facing=%5.2f bad=%d" \
			% [_elapsed, regime, p.x, p.y, vmax, creature.thrust, creature.flap_phase, _tip_jump_window, creature.facing, _bad_frames])
		_tip_jump_window = 0.0
	if _elapsed >= RUN_SECONDS:
		print("SUMMARY t=%.1f peak_speed=%.0f peak_tip_jump=%.1f bad=%d errors=see_log" \
			% [_elapsed, _max_speed_tick, _max_tip_jump, _bad_frames])
		get_tree().quit()


func _process(_dt: float) -> void:
	queue_redraw()
	if _cam != null:
		_cam.position = creature.body.pos[creature.rig.center_point]


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_Z:
		_cam.zoom = Vector2.ONE if _cam.zoom.x > 1.5 else Vector2(3.2, 3.2)
	var lines: PackedStringArray = PackedStringArray()
	lines.append("thrust %.2f   flap_phase %.1f   turn_rate %.2f   facing %+.2f" % [creature.thrust, creature.flap_phase, creature.turn_rate, creature.facing])
	for l in creature.loco.locomotors:
		lines.append("%s  weight=%.2f" % [l.id, l.weight])
	label.text = "\n".join(lines)


func _draw() -> void:
	var y: float = world.bounds.end.y
	draw_line(Vector2(0.0, y), Vector2(world.bounds.end.x, y), Color(0.35, 0.35, 0.4), 2.0)
