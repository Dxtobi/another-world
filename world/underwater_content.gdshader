shader_type canvas_item;
render_mode unshaded;

// Underwater scenery drawn inside a water volume's cutaway view. The prop is
// lifted above the water polygon (z 4, below the player cutaway at 5) and
// washed with the SAME depth gradient the water body itself uses, so scenery
// reads as dark silhouettes sinking into the water the deeper it sits --
// like the ruins/machinery layers in the design reference.
//
// WaterVolume pushes surface_y / max_depth / the gradient colours, so a prop
// always matches the volume it sits in. Give a prop this material yourself
// (and keep it applied) or leave the material empty and let WaterVolume
// manage lift + tinting.

// World px of the waterline the prop sinks from.
uniform float surface_y = 0.0;
// World px from the waterline down to the volume bottom. Zero/negative falls
// back to a readable 900 px span.
uniform float max_depth = 900.0;
uniform vec3 gradient_top : source_color = vec3(0.28, 0.66, 0.68);
uniform vec3 gradient_bottom : source_color = vec3(0.02, 0.09, 0.13);
// How strongly the prop is dissolved into water colour (1 = pure silhouette).
uniform float silhouette : hint_range(0.0, 1.0) = 0.82;
// Extra depth fog: deep props fade toward the gradient itself.
uniform float fog_amount : hint_range(0.0, 1.0) = 0.5;
// Crossfade set by WaterVolume while the head is underwater (1 = shown).
uniform float reveal : hint_range(0.0, 1.0) = 1.0;

varying float v_depth;

void vertex() {
	vec2 world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	v_depth = clamp((world.y - surface_y) / max(abs(max_depth), 1.0), 0.0, 1.0);
}

void fragment() {
	vec4 src = COLOR * texture(TEXTURE, UV);
	vec3 water = mix(gradient_top, gradient_bottom, v_depth);
	// Near the surface the prop keeps most of its own colour under a wash;
	// deeper it flattens toward a plain water-coloured silhouette.
	float wash = clamp(silhouette * (0.35 + 0.65 * (1.0 - v_depth)), 0.0, 1.0);
	vec3 outc = mix(src.rgb, water, wash);
	// A last touch of the prop's own dark/light so it never reads as a flat fill.
	outc *= 0.72 + 0.35 * (1.0 - v_depth);
	outc = mix(outc, water, clamp(fog_amount * v_depth, 0.0, 1.0));
	// reveal fades the whole prop in/out with the cutaway; below the reveal
	// threshold the alpha bottoms out to nothing.
	COLOR = vec4(outc, src.a * reveal);
}
