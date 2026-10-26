extends Node2D
## Test scene: one vulture-rig creature with a debug HUD.
## Default runs a scripted DemoBrain (metrics on); set CF_MOUSE=1 to chase the cursor instead.

var creature: Creature
var world: WorldQuery
var label: Label

var demo: bool = true
var _metrics_t: float = 0.0
var _max_speed_tick: float = 0.0
var _bad_frames: int = 0
var _start: float = 0.0


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
	if _metrics_t >= 0.5:
		_metrics_t = 0.0
		var p: Vector2 = creature.body.pos[creature.rig.center_point]
		var regime: String = "manual"
		var b: Brain = creature.brain
		if b is DemoBrain:
			regime = (b as DemoBrain).regime_label()
		print("t=%05.1f regime=%-5s pos=%4.0f,%4.0f vmax=%5.0f thrust=%.2f flap=%.1f bad=%d" \
			% [Time.get_ticks_msec() / 1000.0 - _start, regime, p.x, p.y, vmax, creature.thrust, creature.flap_phase, _bad_frames])


func _process(_dt: float) -> void:
	queue_redraw()
	var lines: PackedStringArray = PackedStringArray()
	lines.append("thrust %.2f   flap_phase %.1f   turn_rate %.2f" % [creature.thrust, creature.flap_phase, creature.turn_rate])
	for l in creature.loco.locomotors:
		lines.append("%s  weight=%.2f" % [l.id, l.weight])
	label.text = "\n".join(lines)


func _draw() -> void:
	var y: float = world.bounds.end.y
	draw_line(Vector2(0.0, y), Vector2(world.bounds.end.x, y), Color(0.35, 0.35, 0.4), 2.0)
