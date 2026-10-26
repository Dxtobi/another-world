@tool
extends RefCounted
## Style presets for the hand-drawn platform surface shader.
##
## Each entry is a bundle of shader uniforms (keys match the shared
## world/platform_surface_impl.gdshaderinc exactly), so "choosing a style" is just
## pushing one of these onto the platform's ShaderMaterial. The look follows
## the shared art rules: near-black cool mass, the read lives in the accent
## and the rim, shading walks grouped value bands.
##
## Every style carries the shared aerial colour (col_haze) and how hard the
## shared screen-space atmosphere grabs it (haze_amount), so all pieces cool
## and quiet the same way far away -- that is what makes the terrain read as
## one environment instead of separate platforms. Per-platform depth_rank
## (on the Platform script) pushes an individual piece further back on top
## of the shared gradient.
##
## rise_bias is the only non-shader key: the extra pixels that style's
## painted surface floats above the physics floor, on top of the platform's
## own visual_rise. Soft ground (snow, sand, moss) sits higher; the water
## film sits close to its drawn line.
##
## Deliberately no class_name: platform.gd reaches it through a preload, and
## a global class_name is exactly what stalls the editor's script hot-reload
## in this session (the MCP addon's offline validation rejects rewrites of
## any script that declares one, so the refresh path is skipped and the
## editor keeps serving the old bytes).

const PRESETS := {
	"dry_ground": {
		"col_haze": Color("1a2a31"),
		"haze_amount": 0.22,
		"col_mass": Color("241c12"),
		"col_band": Color("322415"),
		"col_accent": Color("5a4630"),
		"col_rim": Color("b7a07b"),
		"rim_strength": 0.55,
		"rim_width": 6.0,
		"value_bands": 3.0,
		"grain_amount": 0.34,
		"mottle_amount": 0.22,
		"crack_amount": 0.0,
		"dune_amount": 0.0,
		"snow_amount": 0.0,
		"water_amount": 0.0,
		"alpha_body": 1.0,
		"rise_bias": 0.0,
	},
	"rocky": {
		"col_haze": Color("1a2a31"),
		"haze_amount": 0.26,
		"col_mass": Color("1f1d1e"),
		"col_band": Color("282423"),
		"col_accent": Color("45403c"),
		"col_rim": Color("9ba18d"),
		"rim_strength": 0.6,
		"rim_width": 7.0,
		"value_bands": 3.0,
		"grain_amount": 0.24,
		"mottle_amount": 0.0,
		"crack_amount": 0.65,
		"dune_amount": 0.0,
		"snow_amount": 0.0,
		"water_amount": 0.0,
		"alpha_body": 1.0,
		"rise_bias": 0.0,
	},
	"sand": {
		"col_haze": Color("1a2a31"),
		"haze_amount": 0.16,
		"col_mass": Color("452f1d"),
		"col_band": Color("553c24"),
		"col_accent": Color("83643f"),
		"col_rim": Color("caa875"),
		"rim_strength": 0.5,
		"rim_width": 6.0,
		"value_bands": 3.0,
		"grain_amount": 0.5,
		"mottle_amount": 0.0,
		"crack_amount": 0.0,
		"dune_amount": 0.8,
		"snow_amount": 0.0,
		"water_amount": 0.0,
		"alpha_body": 1.0,
		"rise_bias": 2.0,
	},
	"snow": {
		"col_haze": Color("1a2a31"),
		"haze_amount": 0.2,
		"col_mass": Color("262b31"),
		"col_band": Color("334049"),
		"col_accent": Color("6b7a86"),
		"col_rim": Color("e6eef1"),
		"rim_strength": 0.7,
		"rim_width": 9.0,
		"value_bands": 3.0,
		"grain_amount": 0.12,
		"mottle_amount": 0.0,
		"crack_amount": 0.0,
		"dune_amount": 0.0,
		"snow_amount": 0.95,
		"water_amount": 0.0,
		"alpha_body": 1.0,
		"rise_bias": 2.0,
	},
	"swamp_water": {
		"col_haze": Color("1a2a31"),
		"haze_amount": 0.3,
		"col_mass": Color("0b1413"),
		"col_band": Color("12241f"),
		"col_accent": Color("1e3d33"),
		"col_rim": Color("57a08c"),
		"rim_strength": 0.65,
		"rim_width": 10.0,
		"value_bands": 3.0,
		"grain_amount": 0.08,
		"mottle_amount": 0.3,
		"crack_amount": 0.0,
		"dune_amount": 0.0,
		"snow_amount": 0.0,
		"water_amount": 0.9,
		# Opaque water: submerged scenery must not read through the surface.
		"alpha_body": 1.0,
		# Full-body planar mirror: keep the reflection alive in deep water and
		# let the water body replace the background instead of blending an
		# unmirrored copy back over the reflection.
		"water_solid": 1.0,
		"reflect_floor": 0.62,
		# True 1:1 planar mirror: no vertical shrink. Tall scenery that is
		# higher above the waterline than the water band is deep simply runs
		# past the bottom of the screen, exactly as a real reflection would.
		# Raise this to squeeze more scenery in (at the cost of squashing it),
		# or override it per platform in the Inspector.
		"reflect_squash": 0.0,
		"reflect_blur": 0.8,
		"reflect_blur_grow": 0.025,
		"reflect_blur_max": 6.0,
		"reflect_sky": Color("1a2a31"),
		# See-through water is opt-in. 0 keeps the surface opaque so objects
		# below the waterline stay hidden. Raise it only for a glassy look.
		"refract_amount": 0.0,
		"refract_distort": 3.0,
		"refract_depth": 120.0,
		"refract_absorb": 0.55,
		"refract_tint": Color("b3d6c9"),
		# 0 keeps the waterline a straight, continuous level (the ocean read).
		# Raise it only for a pond with a wavy hand-drawn shoreline; the land
		# behind the water fills the dips.
		"shore_wave_amp": 0.0,
		"shore_wave_len": 1500.0,
		# Swamp water is darker and murkier than the default tropical teal:
		# the reflection of the bright horizon still carries near the
		# shoreline, but the body itself reads as deep water.
		"col_water_shallow": Color("2a6b66"),
		"col_water_deep": Color("06171c"),
		"water_depth": 95.0,
		"reflect_absorb": 0.32,
		"streak_amount": 0.5,
		"rise_bias": -1.0,
	},
	"moss": {
		"col_haze": Color("1a2a31"),
		"haze_amount": 0.24,
		"col_mass": Color("151c17"),
		"col_band": Color("1e2a20"),
		"col_accent": Color("31502e"),
		"col_rim": Color("b9dcd2"),
		"rim_strength": 0.5,
		"rim_width": 3.5,
		"value_bands": 3.0,
		"grain_amount": 0.3,
		"mottle_amount": 0.85,
		"crack_amount": 0.12,
		"dune_amount": 0.0,
		"snow_amount": 0.0,
		"water_amount": 0.0,
		"alpha_body": 1.0,
		"rise_bias": 1.0,
	},
}


static func preset(style: String) -> Dictionary:
	return PRESETS.get(style, PRESETS["dry_ground"])


## Extra pixels of painted surface above the physics floor for this style,
## stacked onto the platform's own visual_rise.
static func rise_bias(style: String) -> float:
	return float(preset(style).get("rise_bias", 0.0))


## Pushes the style's uniforms onto the material. Everything that is not a
## shader parameter stays behind: rise_bias is consumed by the platform
## script itself, never handed to the shader.
static func apply(style: String, mat: ShaderMaterial) -> void:
	var values := preset(style)
	for key in values:
		if key == "rise_bias":
			continue
		mat.set_shader_parameter(key, values[key])
