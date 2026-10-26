extends Node2D
## Look-dev harness for the normal-mapped surface pipeline.
##
## Answers one question before any world or streaming code gets written:
## does derived-normal -> CanvasTexture -> light() hold up, and does it read
## like the reference art? Everything downstream depends on that being yes.
##
## Builds itself in _ready() so there is no .tscn to hand-author and every
## value is one export away from being retuned.
##
## Drag with the left mouse button to move the key light -- that is the test:
## the relief should relight in real time rather than sit there as a decal.

@export_group("Tiles")
@export var log_size := Vector2i(520, 170)
@export var rock_size := Vector2i(340, 300)
@export var rib_size := Vector2i(470, 330)
@export_range(0.1, 4.0, 0.05) var normal_strength := 1.0

@export_group("Look")
# Darker than instinct suggests. Every reference is a dark mass with light
# picking out the bumps. A mid-value albedo under a strong fill flattens the
# whole frame to one tone, and relief has nothing to read against.
# Near-black and cool. The references put their read in the accent, not the
# body -- int-2 is a dark olive mound whose punch comes entirely from the hot
# orange nodules on it. A mid-value body competes with them and the contrast
# collapses.
@export var albedo := Color("18211e")
@export var rim_color := Color("b9dcd2")
@export var haze_color := Color("173437")
@export_range(0.0, 1.0, 0.01) var haze_amount := 0.10
@export var ambient := Color("141c22")
@export_range(0.0, 2.0, 0.05) var specular := 0.16
@export var specular_color := Color("e8f2e4")
# 0 = smooth render, 3+ = grouped values. The references are painted, and
# smooth N.L falloff is the thing that most makes relief read as a 3D render.
@export_range(0.0, 8.0, 1.0) var value_bands := 3.0

@export_group("Lights")
@export var key_color := Color("f2ecd8")
@export var key_energy := 1.75
@export var key_rest := Vector2(180.0, -520.0)
# Deliberately weak. The accent is a bioluminescent kicker, not a second key;
# at 1.7 it filled the frame with cyan and dissolved the forms.
@export var glow_color := Color("2fd9bd")
@export_range(0.0, 4.0, 0.05) var glow_energy := 0.45
# Warm and saturated on purpose. The bodies are near-black and cool, the scene
# light is teal, so the accents are the only warm thing in frame -- which is
# where all the contrast comes from. Teal accents on teal-lit bodies had none.
@export var glow_tint := Color("ff7a2a")

## Bioluminescent accents, in UV so each follows its own shape's texture.
## Entry is [u, v, radius_px, intensity].
##
## Fewer and much larger than instinct suggests. Small bright points read as
## fireflies or lens flares sitting on top; the references glow in patches
## where a whole nodule is lit. Radii are also spaced so no two accents
## overlap -- additive overlap clips the tint to white.
const LOG_GLOW := [[0.25, 0.38, 40.0, 0.60], [0.52, 0.32, 36.0, 0.50],
		[0.80, 0.44, 38.0, 0.65]]
const ROCK_GLOW := [[0.32, 0.42, 40.0, 0.65], [0.66, 0.60, 36.0, 0.55]]
const RIB_GLOW := [[0.28, 0.40, 40.0, 0.60], [0.56, 0.20, 44.0, 0.70],
		[0.82, 0.30, 34.0, 0.50]]

var _shader: Shader
var _key: PointLight2D


func _ready() -> void:
	_shader = load("res://world/shaders/surface.gdshader")
	_add_backdrop()
	_add_platform(&"log", log_size, 11, Vector2(-470.0, 120.0), Color("7c7360"), LOG_GLOW)
	_add_platform(&"rock", rock_size, 23, Vector2(40.0, 175.0), Color("64736a"), ROCK_GLOW)
	_add_platform(&"rib", rib_size, 37, Vector2(540.0, 55.0), Color("9ba18d"), RIB_GLOW)
	_add_lights()
	_add_camera()


func _process(_delta: float) -> void:
	# Hold the left button to swing the key light around the shapes.
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_key.global_position = get_global_mouse_position()


func _add_backdrop() -> void:
	var bg := ColorRect.new()
	bg.name = "Backdrop"
	bg.color = Color("0d1a1e")
	bg.position = Vector2(-3000.0, -2200.0)
	bg.size = Vector2(6000.0, 4400.0)
	bg.z_index = -10
	add_child(bg)


func _add_platform(kind: StringName, size: Vector2i, seed_v: int, at: Vector2,
		tint: Color, glows: Array) -> void:
	var height := PlatformShapes.make(kind, size.x, size.y, seed_v)

	# The same accent list drives both the shader's emission and a physical
	# swelling in the height field, so a nodule catches specular and rim like
	# the surface it grows out of. The bump is a little smaller than the glow
	# so the halo spills past its edge the way real bioluminescence does.
	var nodules: Array = []
	for g in glows:
		nodules.append([g[0] * size.x, g[1] * size.y, g[2] * 0.75, 7.0])
	NrmBaker.stamp_nodules(height, size.x, size.y, nodules)

	var maps := NrmBaker.bake(height, size.x, size.y, normal_strength)

	var ct := CanvasTexture.new()
	ct.diffuse_texture = maps.mask
	ct.normal_texture = maps.normal
	ct.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("albedo", albedo)
	mat.set_shader_parameter("normal_strength", normal_strength)
	mat.set_shader_parameter("rim_color", rim_color)
	mat.set_shader_parameter("rim_strength", 0.75)
	mat.set_shader_parameter("haze_color", haze_color)
	mat.set_shader_parameter("haze_amount", haze_amount)
	mat.set_shader_parameter("ambient", ambient)
	mat.set_shader_parameter("specular", specular)
	mat.set_shader_parameter("specular_color", specular_color)
	mat.set_shader_parameter("value_bands", value_bands)

	var gp := PackedVector4Array()
	var gc := PackedVector4Array()
	for idx in glows.size():
		var g: Array = glows[idx]
		gp.append(Vector4(g[0], g[1], g[2], g[3]))
		# Vary hue and value per accent. A cluster of identically-tinted dots
		# reads as printed decals; a spread reads as a colony of related but
		# separate growths, which is what int-2's nodules do.
		var accent := glow_tint
		accent = accent.lightened(0.09 * float(idx % 3))
		accent = accent.darkened(0.10 * float(idx % 2))
		accent.h = fposmod(accent.h + 0.028 * float(idx), 1.0)
		gc.append(Vector4(accent.r, accent.g, accent.b, 1.0))
	mat.set_shader_parameter("glow_pos", gp)
	mat.set_shader_parameter("glow_col", gc)
	mat.set_shader_parameter("glow_count", glows.size())

	var sprite := Sprite2D.new()
	sprite.name = String(kind)
	sprite.texture = ct
	sprite.material = mat
	sprite.self_modulate = tint
	sprite.position = at
	add_child(sprite)


## Radial falloff built as an Image rather than a GradientTexture2D.
##
## GradientTexture2D with hand-assigned offsets and colors rendered as a flat
## white square -- no radial ramp at all. Each light was therefore a hard-edged
## rectangle, and every shape showed a straight cut along the quad's border.
## It looked fine at texture_scale 9 only because the quad was then wider than
## the whole scene; dropping to 5.5 exposed it immediately.
##
## Reaches zero at the inscribed circle, so the quad border is never the
## brightest thing in frame.
func _falloff(size_px: int = 96) -> ImageTexture:
	var img := Image.create_empty(size_px, size_px, false, Image.FORMAT_RGBA8)
	var c := (size_px - 1) * 0.5
	for y in size_px:
		for x in size_px:
			var dx := (x - c) / c
			var dy := (y - c) / c
			var r := sqrt(dx * dx + dy * dy)
			var a := 1.0 - smoothstep(0.0, 1.0, r)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)


func _add_lights() -> void:
	var falloff := _falloff()

	_key = PointLight2D.new()
	_key.name = "KeyLight"
	_key.texture = falloff
	_key.color = key_color
	_key.energy = key_energy
	_key.texture_scale = 29.0
	_key.position = key_rest
	add_child(_key)

	# Local bioluminescent accent: proves coloured lights mix onto the surfaces.
	# Dropped low and behind so it rims rather than fills.
	var glow := PointLight2D.new()
	glow.name = "GlowAccent"
	glow.texture = falloff
	glow.color = glow_color
	glow.energy = glow_energy
	glow.texture_scale = 4.0
	glow.position = Vector2(-320.0, 600.0)
	add_child(glow)


func _add_camera() -> void:
	var cam := Camera2D.new()
	cam.name = "LookDevCam"
	cam.position = Vector2(20.0, 140.0)
	cam.zoom = Vector2(0.72, 0.72)
	add_child(cam)
	cam.make_current()


## Numerical stand-in for eyeballing a screenshot.
##
## Two things get measured. First a light is rotated around a shape's centre at
## a fixed radius, so distance falloff is identical in both readings and cancels
## out; opposite-signed deltas at two opposite sample points then mean the
## surface genuinely relights instead of sitting there as a decal.
##
## Second the identical sweep is repeated with normal_strength forced to zero.
## That is the control. With relief off, every other contributor to the frame
## is still present -- falloff, the ambient term, the static glow light, the
## rim -- so a directional difference that *disappears* is attributable to the
## normal map and nothing else.
##
## The log is swept vertically because a horizontal cylinder's normal only
## turns through the vertical axis; a left/right sweep on it is near blind.
func probe_light() -> Dictionary:
	var key: PointLight2D = get_node("KeyLight")
	var rest: Vector2 = key.position
	var log_sp: Sprite2D = get_node("log")
	var mat: ShaderMaterial = log_sp.material

	# Symmetric about the cylinder axis, which sits at image y = 93.5 (the
	# sprite centre is y = 85, hence the +8.5 shift). At t = +/-0.5 the barrel
	# has a real vertical normal, and the 32px box spans several bark periods so
	# the grooves average out instead of biasing one sample.
	var points: Dictionary = {"top": Vector2(0.0, -29.0), "bottom": Vector2(0.0, 46.0)}
	var axis: Vector2 = Vector2(0.0, -640.0)

	mat.set_shader_parameter("normal_strength", 1.0)
	var relief_on: Dictionary = await _sweep(key, log_sp, axis, points, 16)

	mat.set_shader_parameter("normal_strength", 0.0)
	var relief_off: Dictionary = await _sweep(key, log_sp, axis, points, 16)

	mat.set_shader_parameter("normal_strength", 1.0)
	key.position = rest
	return {"relief_on": relief_on, "relief_off": relief_off}


## Reads each sample point with the light at center-offset (A) and again at
## center+offset (B). Returns {point: [A, B]}. A and B should disagree when the
## surface has relief, and match when it does not.
##
## Waits on frame_post_draw rather than process_frame: reading the viewport
## texture before the draw lands returns the previous frame twice, which looks
## exactly like "the light did nothing".
func _sweep(key: PointLight2D, sprite: Sprite2D, offset: Vector2,
		points: Dictionary, half: int) -> Dictionary:
	var center: Vector2 = sprite.position

	key.position = center - offset
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var reading_a: Image = get_viewport().get_texture().get_image()

	key.position = center + offset
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var reading_b: Image = get_viewport().get_texture().get_image()

	var out: Dictionary = {}
	for label in points:
		var local: Vector2 = points[label]
		var screen: Vector2 = sprite.get_global_transform_with_canvas() * local
		var rect: Rect2i = Rect2i(
				int(screen.x) - half, int(screen.y) - half, half * 2, half * 2)
		out[label] = [_lum(reading_a, rect), _lum(reading_b, rect)]
	return out


## Reads the baked normal and mask maps straight back out of the shipped
## texture pair, bypassing the framebuffer entirely. The framebuffer tells us
## what the screen shows; this tells us whether the *artifact* is right, which
## separates a bad bake from a bad probe.
##
## Log geometry: 520x170, cylinder axis at image y = 85 + sin(u*PI)*0.05*170,
## so about y = 93.5 at mid-length.
func dump_normals() -> Dictionary:
	var ct: CanvasTexture = get_node("log").texture
	var nrm: Image = (ct.normal_texture as ImageTexture).get_image()
	var msk: Image = (ct.diffuse_texture as ImageTexture).get_image()

	var probes: Dictionary = {
		"outside": Vector2i(260, 5),
		"near_top_edge": Vector2i(260, 45),
		"above_axis": Vector2i(260, 59),
		"at_axis": Vector2i(260, 94),
		"below_axis": Vector2i(260, 127),
	}
	var out: Dictionary = {}
	for k in probes:
		var p: Vector2i = probes[k]
		var n: Color = nrm.get_pixelv(p)
		out[k] = {
			"rg": [snappedf(n.r, 0.001), snappedf(n.g, 0.001)],
			"mask": snappedf(msk.get_pixelv(p).r, 0.001),
		}
	return out


## Writes the derived mask and normal maps out as PNGs so the pipeline's own
## output can be looked at directly. The framebuffer shows where the light
## ended up; these show what it was given, which is what separates a bad bake
## from a bad material when a surface shades oddly.
##
## Lands in res://.nrm_preview/. The leading dot keeps the folder out of
## Godot's importer, so it does not turn into a pile of .import files.
func dump_maps() -> Dictionary:
	var dir := "res://.nrm_preview"
	DirAccess.make_dir_recursive_absolute(dir)
	var out: Dictionary = {}
	for kind in ["log", "rock", "rib"]:
		var sp: Sprite2D = get_node(kind)
		var ct: CanvasTexture = sp.texture
		var mask: Image = (ct.diffuse_texture as ImageTexture).get_image()
		var normal: Image = (ct.normal_texture as ImageTexture).get_image()
		var mp: String = "%s/%s_mask.png" % [dir, kind]
		var np: String = "%s/%s_normal.png" % [dir, kind]
		out[kind] = {
			"size": [mask.get_width(), mask.get_height()],
			"mask_err": mask.save_png(mp),
			"normal_err": normal.save_png(np),
		}
	return out


## Mean luminance of a screen-space box. The stride keeps it cheap; these
## boxes are flat enough that every 4th pixel is representative.
func _lum(img: Image, rect: Rect2i) -> float:
	var acc: float = 0.0
	var n: int = 0
	for y in range(rect.position.y, rect.end.y, 4):
		for x in range(rect.position.x, rect.end.x, 4):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var px: Color = img.get_pixel(x, y)
			acc += px.r * 0.3 + px.g * 0.5 + px.b * 0.2
			n += 1
	if n == 0:
		return 0.0
	return acc / float(n)
