@tool
## == HAND-DRAWN PLATFORM WITH A PAINTED SURFACE STYLE ===================
##
## HOW TO USE
## 1. Instance scenes/world/platform.tscn, or add a StaticBody2D and attach
##    this script -- it builds its own Collision / Visual children.
## 2. Draw the shape: select the Collision child and drag its polygon
##    handles in the viewport. That polygon is both the physics floor and
##    the silhouette in game -- the painted surface follows live while you
##    drag.
## 3. Style it (Inspector, on the platform ROOT, not the children):
##      style       - dry_ground | rocky | sand | snow | swamp_water | moss.
##                    Preview updates instantly in the editor.
##      color       - tint over the style's palette. White = as authored.
##      depth_rank - 0 foreground, 1 far backdrop. Push scenery pieces
##                    (branches, upper structure) back into the shared haze.
##      visual_rise - how far the painted surface sits above the physics
##                    floor (0-16 px). The player's feet sink into the
##                    surface by this much, like walking through snow or
##                    moss; the collision stays exactly where you drew it.
##                    Styles bias the rise themselves: sand and snow sit
##                    higher, the water film sits close to its line.
##      shader_overrides - optional per-platform uniform tweaks for whichever
##                    style is active (see the "Custom Shader" group below).
## 4. From code use set_platform_polygon(points) -- it moves the physics
##    and the painted surface in the same frame.
##
## Style presets live in world/platform_styles.gd (palettes, feature
## amounts, rise biases). Dry styles use world/platform_surface.gdshader;
## swamp_water uses world/platform_water.gdshader, the only variant that
## samples the screen for reflections (screen sampling forces a backbuffer
## copy, so rocks and ground must not compile it in).
##
## No class_name on purpose: a global class name is what stalls the
## editor's script hot-reload here -- the MCP addon's offline validation
## rejects rewrites of any script that declares one, its refresh path gets
## skipped, and the editor keeps serving the old bytes. Neither this script
## nor the registry is referenced through a global class; the registry
## arrives by preload. Loss: no "Add Node -> Platform" palette entry --
## instance the platform.tscn template instead.
##
## The body owns exactly two parts, searched for by type so renames
## survive: the polygon the artist edits (Collision) and the polygon the
## game draws (Visual, kept visual_rise px above the physics floor).
## Anything missing is rebuilt and adopted by the edited scene.

extends StaticBody2D

const PlatformStyles := preload("res://world/platform_styles.gd")
const SURFACE_SHADER := preload("res://world/platform_surface.gdshader")
const WATER_SHADER := preload("res://world/platform_water.gdshader")
const WATER_VOLUME := preload("res://world/water_volume.gd")
## swamp_water is the only style that reflects; it needs the screen-reading
## variant of the surface shader.
const WATER_STYLE := "swamp_water"

const VPOINT_LIMIT := 128

@export_group("Shape")
## Pixels the painted surface floats above the physics floor, before the
## style's own bias. 4 is enough for a slight sink into moss; push higher
## for deep snow drifts.
@export_range(0.0, 16.0, 0.5) var visual_rise := 4.0:
	set(value):
		visual_rise = value
		_mirror()

## Backdrop staging for atmosphere: 0 = foreground/playable terrain, 1 =
## far backdrop mass. Backdrop pieces lose their rim, darken and quiet into
## the shared haze, so you can stage a fallen branch or the upper forest
## reaches exactly as far back as they should read.
@export_range(0.0, 1.0, 0.05) var depth_rank := 0.0:
	set(value):
		depth_rank = value
		_push_depth()

@export_group("Look")
## Surface style, one per platform. Recolours the Visual instantly.
@export_enum("moss", "dry_ground", "rocky", "sand", "snow", "swamp_water")
var style: String = "moss":
	set(value):
		style = value
		_apply_style()

## Tint over the style's palette, not a repaint: white wears the style as
## authored, and values below 1 push the platform back into the mass.
@export var color := Color.WHITE:
	set(value):
		color = value
		_apply_tint()

@export_group("Water")
## Water only: clip the visible surface to one horizontal level instead of
## following a sloped polygon top. A big lake/ocean then reads as a single
## continuous plane at a constant Y. The physics polygon is left as drawn.
@export var flat_waterline := true:
	set(value):
		flat_waterline = value
		_mirror()

## Water only: shift the flat waterline up (-) or down (+) in local px from the
## average level of the authored upper outline. 0 keeps that level.
@export_range(-400.0, 400.0, 1.0) var waterline_offset := 0.0:
	set(value):
		waterline_offset = value
		_mirror()

@export_group("Custom Shader")
## Per-platform overrides applied AFTER the style preset, for any uniform of
## the shared surface/water shader. Keys are uniform names, values use the
## uniform's type. Works for every style / shader type, e.g.:
##   "reflect_squash": 0.0        exact 1:1 water mirror (no shrink)
##   "reflect_floor": 0.4         how strong the mirror stays in deep water
##   "water_depth": 70.0          depth at which the water reads as deep
##   "surface_wave_height": 12.0  px the waterline deforms per disturbance
##   "surface_wave_speed": 150.0  px/s the surface ring travels outward
##   "surface_baseline": 4.0      px of crest headroom under the mesh edge
##   "col_water_deep": Color("06171c")
##   "rim_strength": 0.8          dry styles: painted outline light
## For a change that applies to every platform of a style, edit that style's
## preset in world/platform_styles.gd instead. Removing a key restores that
## uniform to the style preset.
@export var shader_overrides: Dictionary = {}:
	set(value):
		var removed := false
		for key in shader_overrides:
			if not value.has(key):
				removed = true
				break
		shader_overrides = value
		if _visual == null:
			return
		# Dropping an override has to restore what it was hiding, so rebuild
		# from the preset; adding or changing keys can simply land on top.
		if removed:
			_apply_style()
			_mirror()
		else:
			_apply_overrides()

var _collision: CollisionPolygon2D
var _visual: Polygon2D
var _water_area: Area2D
var _mirrored := PackedVector2Array()
# What the material was last told: geometry edits through tooling bypass
# script setters, so the editor poll reconciles. Defaults deliberately never
# match a settled state.
var _applied_style := StringName("")
var _applied_rank := -123.0
var _applied_tint := Color(-1, -1, -1)
var _applied_rise := -123.0
var _applied_flat := false
var _applied_waterline := -123456.0
var _applied_overrides: Dictionary = {}


func _ready() -> void:
	_ensure_children()
	# _apply_style() rebuilds the material and mirrors the polygon, so the
	# surface is fully set up in one pass.
	_apply_style()


## Godot's automatic screen-texture copy is taken once per frame, at the
## first CanvasItem that reads it. Here that copy landed before the far
## scenery was drawn, so the water reflected the player and the shore but
## not the mushroom forest. A BackBufferCopy immediately before the water
## forces a fresh copy exactly where the reflection needs it, with the
## whole environment already in it.
func _ensure_screen_copy() -> void:
	if _visual == null:
		return
	for child in get_children():
		if child is BackBufferCopy:
			return
	var copy := BackBufferCopy.new()
	copy.name = &"ScreenCopy"
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(copy)
	# The copy must be drawn before the water surface, not after it.
	move_child(copy, _visual.get_index())


func _process(_delta: float) -> void:
	# CollisionPolygon2D has no "changed" signal for polygon edits, so while
	# the tool script lives in the editor it polls: when the handles moved the
	# painted surface follows next frame. Idle at runtime, where a platform
	# stops being polygon-driven once it exists in gameplay.
	if not Engine.is_editor_hint():
		return
	# Fresh nodes created by tooling may never see _ready in the editor, so
	# the poll builds the children too, not just the pixels.
	if _collision == null or _visual == null:
		_ensure_children()
	# Reconcile exports the setters could not express (external tooling, find
	# and replace, scripted edits): anything out of sync with the material
	# converges next frame.
	if _applied_style != style or _applied_rank != depth_rank:
		_apply_style()
	if _applied_tint != color:
		_apply_tint()
	if _collision != null and (_mirrored != _collision.polygon
			or _applied_rise != visual_rise):
		_mirror()
	if _applied_flat != flat_waterline or _applied_waterline != waterline_offset:
		_mirror()
	if _applied_overrides != shader_overrides:
		_apply_style()
		_mirror()


## Replaces the shape from code (world generator, level scripting). Sets the
## physics, the painted surface and the shader's copy of the outline in one
## call, because the runtime does not poll.
func set_platform_polygon(points: PackedVector2Array) -> void:
	_collision.polygon = points
	_mirror()


func _ensure_children() -> void:
	for child in get_children():
		if child is CollisionPolygon2D:
			_collision = child
		elif child is Polygon2D:
			_visual = child
	if _collision == null:
		_collision = _adopt(CollisionPolygon2D.new(), &"Collision")
	if _visual == null:
		_visual = _adopt(Polygon2D.new(), &"Visual")


func _adopt(part: Node, part_name: StringName) -> Node:
	part.name = part_name
	add_child(part)
	# Children made at editor time must be claimed by the scene themselves, or
	# the save keeps only the parent and the fill never comes back next load.
	if Engine.is_editor_hint() and owner != null:
		part.owner = owner
	return part


## Copies the drawn physics polygon into the painted surface, raised by
## visual_rise (plus the style's bias), and feeds the raised outline to the
## shader's edge walk. The rim hugs the *visible* top edge, which is this
## many pixels above where the player actually stands.
func _mirror() -> void:
	if _collision == null or _visual == null:
		return
	var points := _collision.polygon
	_mirrored = points
	_applied_rise = visual_rise
	_applied_flat = flat_waterline
	_applied_waterline = waterline_offset
	# Water is a volume, not a floor. Keeping the drawn polygon as the source
	# of the painted surface is fine, but the physics body must stop blocking
	# the player. The WaterVolume Area2D below does the actual detection.
	_collision.disabled = style == WATER_STYLE
	var rise := visual_rise + PlatformStyles.rise_bias(style)
	var visual := PackedVector2Array()
	visual.resize(points.size())
	for i in points.size():
		visual[i] = points[i] - Vector2(0.0, rise)
	# Water reads as one continuous ocean level: cut the painted surface at a
	# horizontal line so a sloped polygon top cannot show as a tilted ruler.
	# The collision polygon stays exactly where the artist drew it.
	if style == WATER_STYLE and flat_waterline:
		visual = _flatten_waterline(visual)
	if visual.size() > VPOINT_LIMIT:
		push_warning("Platform %s: %d points exceeds the shader's %d-point outline; the rim ignores the rest."
				% [name, visual.size(), VPOINT_LIMIT])
	_visual.polygon = visual
	_sync_water_volume(visual)
	var mat := _visual.material as ShaderMaterial
	if mat != null and _is_surface_shader(mat.shader):
		# Loop bound of the shader's outline walk. Points beyond it are a
		# warning above.
		mat.set_shader_parameter("pt_count", float(mini(visual.size(), VPOINT_LIMIT)))
		# The outline as a 128x1 RGBA32F texture (one point per texel). A
		# vec2 uniform array silently fails under dynamic indexing on some
		# canvas backends; a texture fetch does not.
		if not visual.is_empty():
			var img := Image.create_empty(VPOINT_LIMIT, 1, false, Image.FORMAT_RGBAF)
			for i in mini(visual.size(), VPOINT_LIMIT):
				img.set_pixel(i, 0, Color(visual[i].x, visual[i].y, 0.0, 1.0))
			mat.set_shader_parameter("pts_tex", ImageTexture.create_from_image(img))
		# Proportional surface detail: features are authored against a ~600px
		# platform, so scale by this polygon's bounding size. A tiny ledge
		# keeps ~1, a 20,000px ground gets ~33x rims and mottling.
		if not visual.is_empty():
			var bounds := Rect2(visual[0], Vector2.ZERO)
			for point in visual:
				bounds = bounds.expand(point)
			var detail := clampf(maxf(bounds.size.x, bounds.size.y) / 600.0, 1.0, 32.0)
			mat.set_shader_parameter("detail_scale", detail)
			# Shoelace sign of the drawn polygon: the shader's edge walk needs to
			# know which way "over the interior" is, because the artist's
			# handle order decides the walk direction, not the surface's
			# orientation. Positive shoelace (this formula) = top edges walk
			# left-to-right with the interior below.
			var area2 := 0.0
			for i in visual.size():
				var a := visual[i]
				var b := visual[(i + 1) % visual.size()]
				area2 += a.x * b.y - b.x * a.y
			mat.set_shader_parameter("winding", 1.0 if area2 > 0.0 else -1.0)
			# Ground mist sizes to the shape's itself short side: deep ground
			# keeps the full dissolve band, shallow props stay clear.
			var lo := visual[0]
			var hi := visual[0]
			for p in visual:
				hi.x = maxf(hi.x, p.x)
				hi.y = maxf(hi.y, p.y)
				lo.x = minf(lo.x, p.x)
				lo.y = minf(lo.y, p.y)
			var short_side := minf(hi.x - lo.x, hi.y - lo.y)
			mat.set_shader_parameter("mist_band",
				clampf(short_side * 0.15, 20.0, 170.0))
		mat.set_shader_parameter("depth_rank", depth_rank)
	# Last word goes to the artist: overrides win over the preset and over the
	# geometry-derived uniforms above (detail_scale, pt_count, winding).
	_apply_overrides()


## Mirrors the painted water polygon into a non-solid Area2D. The area carries
## the same shape as the visible water, so walking on the surface is gone but
## point queries (WaterQuery) and body contact still find the volume.
func _sync_water_volume(poly: PackedVector2Array) -> void:
	if style != WATER_STYLE:
		if is_instance_valid(_water_area):
			_water_area.queue_free()
		_water_area = null
		return
	if not is_instance_valid(_water_area) or not _water_area.has_method("is_water_volume"):
		if is_instance_valid(_water_area):
			_water_area.queue_free()
		_water_area = get_node_or_null("WaterVolume") as Area2D
		if _water_area == null or not _water_area.has_method("is_water_volume"):
			_water_area = Area2D.new()
			_water_area.name = &"WaterVolume"
			_water_area.set_script(WATER_VOLUME)
			add_child(_water_area)
			if Engine.is_editor_hint() and owner != null:
				_water_area.owner = owner
	var shape := _water_area.get_node_or_null("WaterShape") as CollisionPolygon2D
	if shape == null:
		shape = CollisionPolygon2D.new()
		shape.name = &"WaterShape"
		_water_area.add_child(shape)
		if Engine.is_editor_hint() and owner != null:
			shape.owner = owner
	shape.polygon = poly
	_water_area.collision_layer = 1 << 4
	_water_area.collision_mask = 1 | 2 | 4
	_water_area.monitoring = true
	_water_area.monitorable = true
	if not Engine.is_editor_hint():
		_water_area.call("set_surface_material", _visual.material as ShaderMaterial, _visual)
		_water_area.call("refresh_bounds", poly)


## Forces the upper points of a water outline onto one horizontal level. The level
## is the average Y of the upper half (plus waterline_offset): the surface is
## extended where the authored top sat below it and cut where it sat above, so
## a sloped polygon still reads as one continuous ocean plane. Side and bottom
## points stay put, so the banks and depth keep their shape. The collision
## polygon is never modified.
func _flatten_waterline(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var min_y := points[0].y
	var max_y := points[0].y
	for p in points:
		min_y = minf(min_y, p.y)
		max_y = maxf(max_y, p.y)
	var mid_y := (min_y + max_y) * 0.5
	var top_sum := 0.0
	var top_count := 0
	for p in points:
		if p.y <= mid_y:
			top_sum += p.y
			top_count += 1
	var level := top_sum / maxf(float(top_count), 1.0) + waterline_offset
	var out := points.duplicate()
	for i in out.size():
		if out[i].y <= mid_y:
			var p := out[i]
			p.y = level
			out[i] = p
	return out


## Pushes the style preset onto the Visual's material. A fresh ShaderMaterial
## every time: never reuse a material that came from a duplicated scene node,
## because Godot shares sub-resources on duplicate and one platform's uniforms
## would then leak into every sibling copy.
func _apply_style() -> void:
	if _visual == null:
		return
	# The Polygon2D's own colour multiplies the shader output -- a legacy tint
	# from the flat-fill era would mute the style to near-black. The tint
	# uniform on the material is the colour knob from here on.
	_visual.color = Color.WHITE
	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER if style == WATER_STYLE else SURFACE_SHADER
	_visual.material = mat
	PlatformStyles.apply(style, mat)
	_push_depth()
	_apply_tint()
	_applied_style = style
	_applied_rank = depth_rank
	if style == WATER_STYLE and not Engine.is_editor_hint():
		_ensure_screen_copy()
	# A style rebuild makes a fresh material, so the geometry-derived uniforms
	# (outline texture, detail scale, winding) have to be pushed again.
	_mirror()
	_apply_overrides()


## Pushes the per-platform custom uniforms last. Any uniform in either
## shader variant can be overridden this way; unknown keys are harmless, so a
## typo never breaks the scene (the Inspector does flag them, though).
func _apply_overrides() -> void:
	if _visual == null:
		return
	var mat := _visual.material as ShaderMaterial
	if mat == null or not _is_surface_shader(mat.shader):
		return
	for key in shader_overrides:
		mat.set_shader_parameter(StringName(key), shader_overrides[key])
	_applied_overrides = shader_overrides.duplicate(true)


## Catches misspelled uniform names before they silently do nothing: the
## Inspector shows a warning triangle on the platform node listing the keys
## that the active shader does not know.
func _get_configuration_warnings() -> PackedStringArray:
	var shader := WATER_SHADER if style == WATER_STYLE else SURFACE_SHADER
	var valid := {}
	for uniform in shader.get_shader_uniform_list():
		valid[String(uniform.name)] = true
	var unknown: Array[String] = []
	for key in shader_overrides:
		if not valid.has(String(key)):
			unknown.append(str(key))
	if unknown.is_empty():
		return PackedStringArray()
	return PackedStringArray([
		"Unknown shader override(s) for style '%s': %s" % [style, ", ".join(unknown)],
	])


## Both variants are the same surface; only water adds the screen-reading
## reflection, so every parameter push accepts either.
func _is_surface_shader(s: Shader) -> bool:
	return s == SURFACE_SHADER or s == WATER_SHADER


## Feeds the per-platform depth staging value to the material.
func _push_depth() -> void:
	if _visual == null:
		return
	var mat := _visual.material as ShaderMaterial
	if mat != null and _is_surface_shader(mat.shader):
		mat.set_shader_parameter("depth_rank", depth_rank)


func _apply_tint() -> void:
	if _visual == null:
		return
	var mat := _visual.material as ShaderMaterial
	if mat != null and _is_surface_shader(mat.shader):
		mat.set_shader_parameter("tint", color)
	_applied_tint = color
