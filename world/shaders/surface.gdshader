shader_type canvas_item;
render_mode blend_mix;

// Surface material for the world.
//
// Texture carries no colour: TEXTURE is a silhouette mask and NORMAL_TEXTURE
// carries the relief. Albedo comes from uniforms plus vertex colour, which is
// what lets a whole biome share one material and one texture pair.
//
// The normal goes through NORMAL_MAP, never NORMAL. Godot 2D's native normal
// convention is flipped against a 3D-authored map, so assigning NORMAL directly
// lights every surface inside-out.

// --- surface look -------------------------------------------------------
uniform vec4 albedo : source_color = vec4(0.36, 0.42, 0.37, 1.0);
uniform float normal_strength : hint_range(0.0, 4.0) = 1.0;
uniform float mask_threshold : hint_range(0.0, 1.0) = 0.5;
// Baked world masks store the silhouette in .r (R8 is a quarter of RGBA8).
// Imported RGBA art should flip this to read .a instead.
uniform bool mask_in_alpha = false;

// --- world rig ----------------------------------------------------------
uniform vec4 ambient : source_color = vec4(0.20, 0.24, 0.27, 1.0);
uniform vec4 haze_color : source_color = vec4(0.33, 0.52, 0.55, 1.0);
uniform float haze_amount : hint_range(0.0, 1.0) = 0.0;

// --- rim / edge light ---------------------------------------------------
uniform vec4 rim_color : source_color = vec4(0.82, 0.93, 0.92, 1.0);
uniform float rim_strength : hint_range(0.0, 3.0) = 0.7;

// --- specular -----------------------------------------------------------
// The interior references get nearly all their read from highlights catching
// raised, slightly wet bumps -- the crater rims in int-3, the nodules in
// int-2. Diffuse relief on its own reads as fuzz: every bump goes matte grey.
uniform vec4 specular_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float specular : hint_range(0.0, 2.0) = 0.35;
// 12, not 24. The derived normals are low-frequency by construction, and a
// tight exponent turns every grain bump into a separate sparkle -- sandpaper
// rather than a damp surface.
uniform float specular_power : hint_range(1.0, 128.0) = 12.0;

// --- sparse bioluminescent accents ---------------------------------------
// Discrete glowing nodules rather than a uniformly emissive surface, which is
// how the references actually read -- int-2's orange nodules, int-3's lit eggs.
// A short list of points per platform keeps the world atlas at 3 bytes/px: no
// third texture channel, no per-pixel emission mask to store or stream.
// Count written out literally rather than via a preprocessor macro: the
// shading language tokenizer rejects a hash anywhere in the file, comments
// included, and reports it as a bare "unknown character" with no context.
uniform vec4 glow_pos[8];  // xy = centre in UV, z = radius px, w = intensity
uniform vec4 glow_col[8];
uniform int glow_count = 0;

// Vertex colour alone, so albedo tints independently of the mask.
varying vec4 vcol;

void vertex() {
	vcol = COLOR;
}

void fragment() {
	vec4 mask_tex = texture(TEXTURE, UV);
	float mask = mask_in_alpha ? mask_tex.a : mask_tex.r;

	// Shading language has no early return in fragment(), hence the branch.
	if (mask < mask_threshold) {
		COLOR = vec4(0.0);
	} else {
		NORMAL_MAP = texture(NORMAL_TEXTURE, UV).rgb;
		NORMAL_MAP_DEPTH = normal_strength;

		// Accumulated here, not in light(). light() runs once per light, so
		// anything added there is scaled by the light count -- three glow
		// lights would give three times the emission. Emissive is also
		// independent of incoming light by definition, which is the other
		// reason it cannot live in the lighting path.
		vec2 size_px = 1.0 / TEXTURE_PIXEL_SIZE;
		vec3 emissive = vec3(0.0);
		for (int i = 0; i < 8; i++) {
			if (i >= glow_count) {
				break;
			}
			vec4 g = glow_pos[i];
			// Correct for aspect: UV is 0..1 on both axes, so a circular
			// falloff has to be measured in pixels, not UV.
			vec2 d = (UV - g.xy) * size_px;
			float f = 1.0 - smoothstep(0.0, max(g.z, 1.0), length(d));
			// Hot core plus a wide soft halo. Squaring alone gives a pinpoint
			// that reads as a firefly rather than a lit nodule.
			// Explicit type, no ":=" -- the shading language rejects inferred
			// declarations here even though GDScript accepts them, and the
			// parse error points at the declaration rather than the keyword.
			float hot = f * f * f;
			emissive += glow_col[i].rgb * (g.w * (hot + f * 0.28));
		}

		// Masked too: an accent must not bleed past the silhouette.
		COLOR = vec4((albedo.rgb * vcol.rgb + emissive) * mask, vcol.a);
	}
}

// --- value grouping ------------------------------------------------------
// 0 = smooth shading, which reads as a render. 3+ posterises light into
// discrete steps, which is how the reference sheets handle form: values are
// grouped into shapes rather than continuously modelled. This is the single
// biggest lever between "3D render" and "painting".
uniform float value_bands : hint_range(0.0, 8.0) = 3.0;

// Posterises v into value_bands steps. Each boundary gets a narrow blend so
// the steps do not alias into stair-stepping along their edge.
float banded(float v) {
	if (value_bands < 1.5) {
		return v;
	}
	float s = v * value_bands;
	float f = floor(s);
	return (f + smoothstep(0.40, 0.60, s - f)) / value_bands;
}

void light() {
	vec3 n = NORMAL;
	float ndl = dot(n, LIGHT_DIRECTION);
	// Wrap keeps organic forms from crushing to flat black on the far side.
	float lit = mix(clamp(ndl, 0.0, 1.0), clamp((ndl + 0.45) / 1.45, 0.0, 1.0), 0.7);
	lit = banded(lit);

	vec3 out_col = COLOR.rgb * (ambient.rgb + LIGHT_COLOR.rgb * LIGHT_ENERGY * lit);

	// Normals near perpendicular to the camera sit on the bevel; that is where
	// the rim reads as a lit lip rather than an outline.
	float edge = 1.0 - abs(n.z);
	// smoothstep rather than a power curve: a defined band of edge light is
	// illustrative, a wide soft falloff is photographic.
	float rim = smoothstep(0.35, 0.85, edge) * rim_strength * clamp(ndl * 0.5 + 0.5, 0.0, 1.0);
	out_col += rim_color.rgb * rim * LIGHT_ENERGY;

	// Specular. A 2D light carries no view vector, so the eye is assumed to sit
	// straight down +Z and the half-vector is built against that.
	//
	// Kept low and tight on purpose. Broad wet highlights are the most
	// aggressively "photoreal" thing this shader could do, and the references
	// get their form from value grouping instead.
	vec3 half_vec = normalize(LIGHT_DIRECTION + vec3(0.0, 0.0, 1.0));
	float spec = pow(clamp(dot(n, half_vec), 0.0, 1.0), specular_power) * specular;
	out_col += specular_color.rgb * spec * LIGHT_ENERGY;

	// Atmospheric perspective. Applied after lighting so it flattens contrast
	// instead of just tinting the lit result.
	out_col = mix(out_col, haze_color.rgb, haze_amount);

	LIGHT = vec4(out_col, COLOR.a);
}
