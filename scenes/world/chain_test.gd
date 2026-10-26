extends Node2D
## Look-dev / motion harness for the dot-and-line system (ChainSim +
## ChainCostume + ChainBody). Builds itself in _ready() so there is no .tscn
## to hand-author and every value is one export away from being retuned.
##
## What it is here to answer, in order:
##   1. Does the spectrum read? FLUID / ROPE / TENTACLE / RIGID / CUSTOM are
##      the same solver with different numbers -- so if they all look the
##      same here, the presets are wrong, not the solver.
##   2. Do cut-out sections ride the dots without a seam opening at any
##      bend? That is what `overlap_px` buys.
##   3. Does the background split hold? The teal rectangle is what the
##      camera sees: outside it the chains keep simulating (the beast walks
##      out of frame and back) but their costumes are switched off, so it
##      reappears mid-stride in a believable pose instead of snapping.
##
## Move the mouse to steer the fluid whip. Click to whip it.

const BG := Color("0b0810")
const GRID := Color(1.0, 1.0, 1.0, 0.035)
const FLOOR := Color("2a2233")
const FRAME := Color("39d6c0")

var _whip: ChainBody
var _whip_anchor: Node2D
var _rod_pivot: Node2D
var _custom: ChainBody
var _beast: Node2D
var _tentacles: Array[ChainBody] = []
var _tentacle_turns: Array[float] = []
var _tentacle_set: ChainTentacles
var _time := 0.0
var _mouse_hot := 0.0
var _hud: Label


func _ready() -> void:
	randomize()
	_build_scene()
	_hud = _label(Vector2.ZERO, "", Color("6fe3d0"))
	var cam := Camera2D.new()
	cam.name = "Camera"
	add_child(cam)
	cam.make_current()
	queue_redraw()


func _physics_process(delta: float) -> void:
	_time += delta
	_mouse_hot = maxf(0.0, _mouse_hot - delta)

	# FLUID whip: the anchor chases the mouse while the mouse is being moved
	# (and then lets go and orbits again), because a whip should follow a
	# hand -- it should never be the thing teleporting.
	var target := Vector2(-430.0, -170.0) + Vector2(cos(_time * 0.6), sin(_time * 0.43)) * Vector2(130.0, 70.0)
	var screen := get_viewport().get_mouse_position()
	var world: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * screen
	if _mouse_hot > 0.0 and _camera_rect().has_point(world):
		target = world
	_whip_anchor.position = _whip_anchor.position.lerp(target, 1.0 - exp(-6.0 * delta))

	# RIGID rod: a pendulum. It should read as a rod with give, not a rope.
	_rod_pivot.rotation = sin(_time * 1.7) * 0.85

	# The beast wanders right across and past the frame edge.
	var swing := _time * 0.085
	_beast.position = Vector2(60.0 + 980.0 * sin(swing), 120.0 + 16.0 * sin(_time * 1.6))
	_beast.rotation = cos(swing) * 0.28

	# The tentacle set runs its own behaviour (SWAY here), and the rig link
	# feeds the beast's movement into it. Nothing in this function touches an
	# individual tentacle any more.
	if _tentacle_set != null and _tentacle_set.behaviour_mode == ChainTentacles.Behaviour.REACH:
		for i in _tentacles.size():
			var phase := _tentacle_turns[i]
			var goal := _beast.position + Vector2(
				cos(_time * 0.5 + phase) * (170.0 + 30.0 * i),
				-30.0 + sin(_time * 0.8 + phase) * (80.0 + 10.0 * i))
			_tentacles[i].reach(goal, 55.0)

	_update_hud()
	queue_redraw()


## Proof, on screen, of the split this system is built around: the beast
## walks out of frame, its costume is switched off and its solver drops to
## background quality -- but the dots keep moving, so it walks back in
## mid-stride instead of snapping into shape.
func _update_hud() -> void:
	if _hud == null or _tentacles.is_empty():
		return
	var t := _tentacles[0]
	var dress := "ON (full solver)" if t.is_painted() else "OFF (background only)"
	var lo := INF
	var hi := 0.0
	for c in _tentacles:
		var l := c.segment_length * float(c.dots - 1)
		lo = minf(lo, l)
		hi = maxf(hi, l)
	_hud.text = "whip stretch %.1f%%   ·   beast x %+.0f   ·   tentacle costume %s   ·   solver %.0f%%   ·   tentacles %.0f-%.0fpx long" % [
		_whip.sim.stretch_error() * 100.0, _beast.position.x, dress, t.sim.quality * 100.0,
		lo, hi]
	_hud.position = Vector2(_camera_rect().end.x - 780.0, _camera_rect().position.y + 14.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_hot = 2.5
	elif event is InputEventMouseButton and event.pressed:
		_whip.sim.whip(900.0)
		if _tentacle_set != null:
			_tentacle_set.whip_all(300.0)


# ----- building -------------------------------------------------------------

func _build_scene() -> void:
	_build_whip()
	_build_rod()
	_build_rope()
	_build_custom()
	_build_beast()
	_label(Vector2(-556.0, -232.0), "FLUID  ·  elastic lines + drag, dots follow the dot in front", FRAME)
	_label(Vector2(452.0, -232.0), "RIGID", FRAME)
	_label(Vector2(-30.0, -300.0), "ROPE", FRAME)
	_label(Vector2(-556.0, 96.0), "CUSTOM  ·  per-dot max angle: 6° at the base, 110° at the tip", FRAME)
	_label(Vector2(-556.0, 250.0),
		"TENTACLES  ·  7 GENERATED from one description: different lengths, stiffnesses and phases, dressed by one shared costume",
			Color("ff8a7a"))
	_label(Vector2(-556.0, 278.0), "move the mouse to steer the whip · click to whip everything", Color(0.7, 0.7, 0.8))


func _build_whip() -> void:
	_whip_anchor = Node2D.new()
	_whip_anchor.name = "WhipAnchor"
	_whip_anchor.position = Vector2(-430.0, -170.0)
	add_child(_whip_anchor)
	_whip = _chain(_whip_anchor, "Whip", Vector2.ZERO, {
		"dots": 20, "seg": 12.0, "style": ChainBody.Style.FLUID,
		"costume": _line_costume(Color("2f6f7a"), Color("0c1f26"), Color("9ff0ff"), 11.0, 2.0, 2.0),
	})


func _build_rod() -> void:
	_rod_pivot = Node2D.new()
	_rod_pivot.name = "RodPivot"
	_rod_pivot.position = Vector2(452.0, -170.0)
	add_child(_rod_pivot)
	# Art is authored at exactly the ratio it gets stretched to (one line
	# plus its overlap, by the width the section asks for), so the cut-out is
	# never distorted -- and because the overlap is baked in, neighbouring
	# pieces always share a couple of pixels and no bend opens a seam.
	var plates := _cutout(30.0 + 16.0, 14.0, Color("3a3550"), Color("b0a8ff"))
	var costume := _line_costume(Color("3a3550"), Color("14121f"), Color("b0a8ff"), 15.0, 11.0, 2.0)
	costume.sections.append(_section(0, -1, plates, 14.0, 8.0))
	_chain(_rod_pivot, "Rod", Vector2.ZERO, {
		"dots": 8, "seg": 30.0, "style": ChainBody.Style.RIGID, "costume": costume,
	})


func _build_rope() -> void:
	var pivot := Node2D.new()
	pivot.name = "RopePivot"
	pivot.position = Vector2(-30.0, -290.0)
	add_child(pivot)
	_chain(pivot, "Rope", Vector2.ZERO, {
		"dots": 16, "seg": 16.0, "style": ChainBody.Style.ROPE,
		"costume": _line_costume(Color("6b4a2a"), Color("1d1208"), Color("d8b06a"), 9.0, 6.0, 1.5),
	})


## The case the presets cannot cover: a curve of bend limits, one value per
## dot. Stiff where it meets the body, floppy at the tip.
func _build_custom() -> void:
	var pivot := Node2D.new()
	pivot.name = "CustomPivot"
	pivot.position = Vector2(-520.0, 130.0)
	add_child(pivot)
	var profile := Curve.new()
	profile.add_point(Vector2(0.0, 6.0))
	profile.add_point(Vector2(1.0, 110.0))
	var costume := _line_costume(Color("2a5a3c"), Color("0a1a12"), Color("a8ffcf"), 12.0, 3.0, 1.5)
	_chain(pivot, "Custom", Vector2.ZERO, {
		"dots": 18, "seg": 15.0, "style": ChainBody.Style.CUSTOM,
		"tweak": {"gravity": 500.0, "damping": 0.97, "drag": 0.4, "iterations": 8},
		"profile": profile, "costume": costume,
	})


func _build_beast() -> void:
	_beast = Node2D.new()
	_beast.name = "Beast"
	_beast.position = Vector2(60.0, 120.0)
	add_child(_beast)

	# The body is itself a chain: a soft spine that lags behind the creature
	# instead of being nailed to it.
	var seg := 26.0
	var overlap := 12.0
	var hide := _cutout(seg + overlap * 2.0, 38.0, Color("5a1f2c"), Color("ff9a8a"))
	var body_costume := _line_costume(Color("5a1f2c"), Color("180810"), Color("ff9a8a"), 44.0, 30.0, 3.0)
	body_costume.sections.append(_section(0, -1, hide, 38.0, overlap))
	var body := _chain(_beast, "Body", Vector2.ZERO, {
		"dots": 6, "seg": seg, "style": ChainBody.Style.CUSTOM,
		"tweak": {
			"gravity": 260.0, "damping": 0.93, "drag": 1.4, "follow_rate": 1.0,
			"iterations": 12, "stiffness": 1.0, "root_align": 0.75,
			"max_angle_head_deg": 40.0, "max_angle_tail_deg": 40.0,
		},
		"costume": body_costume,
	})
	# An eye, so the direction it is heading is readable at a glance.
	_eye(body, 4, 9.0)

	# The set is GENERATED, not hand-placed: ChainTentacles builds every
	# tentacle from a description of how much they may differ, so the variety
	# is a few numbers instead of six configured nodes.
	var t_seg := 13.0
	var t_over := 8.0
	var skin := Color("6d2b3a")
	var rim := Color("d98a8a")
	var tentacle_costume := _line_costume(skin, Color("12040a"), rim, 14.0, 5.0, 2.0)
	tentacle_costume.sections.append(
		_section(0, 3, _cutout(t_seg + t_over * 2.0, 13.0, skin, rim), 13.0, t_over))
	tentacle_costume.sections.append(
		_section(4, 7, _cutout(t_seg + t_over * 2.0, 10.0, skin, rim), 10.0, t_over))
	tentacle_costume.sections.append(
		_section(8, -1, _cutout(t_seg + t_over * 2.0, 7.0, skin, rim), 7.0, t_over))
	tentacle_costume.sections.append(_sucker_section(_sucker(40, Color("e8c9b8"), Color("2a0d14"))))

	var set_node := ChainTentacles.new()
	set_node.name = "Tentacles"
	_beast.add_child(set_node)
	set_node.anchor_chain_path = NodePath("../Body")
	set_node.anchor_index = 3
	set_node.count = 7
	set_node.dots = 11
	set_node.segment_length = t_seg
	set_node.length_variation = 0.85
	set_node.length_jitter = 0.3
	set_node.angle_head_deg = 64.0
	set_node.angle_tail_deg = 30.0
	set_node.stiffness_variation = 0.7
	set_node.spread_deg = 340.0
	set_node.body_radius = 20.0
	set_node.costume = tentacle_costume
	set_node.behaviour_mode = ChainTentacles.Behaviour.SWAY
	set_node.inherit_motion = 0.9
	# build(), not the regenerate toggle: the exports above have only just
	# been assigned, so the set is built exactly once, from final values.
	set_node.build()
	_tentacle_set = set_node
	_tentacles = set_node.tentacles
	for i in _tentacles.size():
		_tentacle_turns.append(float(i))

	# And the set is coupled to the beast's own movement, the same way a
	# real creature's would be: velocity streams them, spin swings them, and
	# sprinting loosens their bend limits.
	var link := ChainRigLink.new()
	link.name = "RigLink"
	_beast.add_child(link)
	link.source_path = NodePath("..")
	link.velocity_gain = 0.9
	link.rotation_gain = 0.25
	link.speed_relax = 0.4


## A dot sprite that only sits still because the body chain holds it still.
func _eye(body: ChainBody, dot: int, size: float) -> void:
	var s := ChainSection.new()
	s.texture = _eye_texture(int(size))
	s.mode = ChainSection.Mode.JOINT
	s.first = dot
	s.last = dot
	s.width_px = size
	var c: ChainCostume = body.costume
	c.sections.append(s)


# ----- look helpers ---------------------------------------------------------

func _chain(parent: Node2D, node_name: String, at: Vector2, cfg: Dictionary) -> ChainBody:
	var c := ChainBody.new()
	c.name = node_name
	parent.add_child(c)
	c.position = at
	c.dots = cfg.get("dots", 12)
	c.segment_length = cfg.get("seg", 16.0)
	c.style = cfg.get("style", ChainBody.Style.TENTACLE)
	for key in cfg.get("tweak", {}):
		c.set(key, cfg["tweak"][key])
	if cfg.has("profile"):
		c.angle_profile = cfg["profile"]
	c.costume = cfg.get("costume", null)
	c.rebuild = true
	return c


func _line_costume(fill: Color, outline: Color, rim: Color, w0: float, w1: float,
		extra: float) -> ChainCostume:
	var c := ChainCostume.new()
	c.fill_color = fill
	c.outline_color = outline
	c.highlight_color = rim
	c.width_head = w0
	c.width_tail = w1
	c.outline_extra = extra
	return c


func _section(first: int, last: int, tex: Texture2D, width: float, overlap: float) -> ChainSection:
	var s := ChainSection.new()
	s.texture = tex
	s.mode = ChainSection.Mode.SEGMENT
	s.first = first
	s.last = last
	s.width_px = width
	s.overlap_px = overlap
	return s


func _sucker_section(tex: Texture2D) -> ChainSection:
	var s := ChainSection.new()
	s.texture = tex
	s.mode = ChainSection.Mode.JOINT
	s.first = -1
	s.last = -1
	s.width_px = 15.0
	s.overlap_px = 2.0
	return s


func _label(at: Vector2, text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.position = at
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", color)
	add_child(l)
	return l


# ----- background -----------------------------------------------------------

func _camera_rect() -> Rect2:
	var xf := get_viewport().get_canvas_transform().affine_inverse()
	var a: Vector2 = xf * Vector2.ZERO
	var b: Vector2 = xf * get_viewport_rect().size
	return Rect2(a, b - a)


func _draw() -> void:
	var vr := _camera_rect()
	draw_rect(Rect2(vr.position - Vector2(2000, 2000), Vector2(4000, 4000)), BG)
	for x in range(-1600, 1601, 80):
		draw_line(Vector2(x, vr.position.y - 2000.0), Vector2(x, vr.end.y + 2000.0), GRID, 1.0)
	for y in range(-1600, 1601, 80):
		draw_line(Vector2(vr.position.x - 2000.0, y), Vector2(vr.end.x + 2000.0, y), GRID, 1.0)
	draw_line(Vector2(vr.position.x - 900.0, 300.0), Vector2(vr.end.x + 900.0, 300.0), FLOOR, 2.0)
	draw_rect(vr, Color(FRAME, 0.10), false, 2.0)


# ----- generated art --------------------------------------------------------
## Capsule cut-out, drawn horizontal, its own thickness baked in. This is the
## shape a costume expects: long axis along the chain, height across it.

static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Art for a section that will be stretched to `length` x `width`.
##
## The texture is authored at twice that size, so at runtime a section lands
## at a uniform 0.5 scale: cut-out art is never squashed by the chain, and
## the rounded caps stay the size they were drawn at. Authoring art to the
## exact stretch ratio is the costume equivalent of drawing a sprite to fit
## its bone.
static func _cutout(length: float, width: float, base: Color, rim: Color) -> ImageTexture:
	var ss := 2
	var w := int(round(length * ss))
	var h := int(round(width * ss))
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var r := h * 0.5
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var d := _seg_dist(p, Vector2(r, r), Vector2(w - r, r)) - r
			var alpha := clampf(0.5 - d, 0.0, 1.0)
			if alpha <= 0.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var shade := 1.0 - 0.42 * (p.y / float(h)) + 0.10 * (1.0 - p.x / float(w))
			var col := Color(base.r * shade, base.g * shade, base.b * shade)
			col = col.lerp(rim, clampf(1.0 - p.y / maxf(r * 1.05, 1.0), 0.0, 1.0) * 0.55)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, alpha))
	return ImageTexture.create_from_image(img)


static func _sucker(size: int, base: Color, rim: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) * 0.5
	var r := size * 0.5
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5)
			var d := p.distance_to(c) - r
			var alpha := clampf(0.5 - d, 0.0, 1.0)
			if alpha <= 0.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var hole := p.distance_to(c) - r * 0.52
			var col := base if hole > 0.0 else rim
			img.set_pixel(x, y, Color(col.r, col.g, col.b, alpha))
	return ImageTexture.create_from_image(img)


static func _eye_texture(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) * 0.5
	var r := size * 0.5
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5)
			var d := p.distance_to(c) - r
			var alpha := clampf(0.5 - d, 0.0, 1.0)
			if alpha <= 0.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var t := clampf(p.distance_to(c) / r, 0.0, 1.0)
			var col := Color("ffe9c8").lerp(Color("3a0d14"), t * t)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, alpha))
	return ImageTexture.create_from_image(img)
