shader_type canvas_item;
// Vertical atmosphere for the scene's giant backdrop rect. The reference
// paintings stack backwards: near-black canopy far up top, a pale luminous
// bloom right above the horizon line, then dark water under the ground line.
//
// The rect is many times taller than the camera ever sees, so rect UV would
// only ever show a mostly-constant slice. The gradient is therefore keyed to
// absolute world Y instead -- the vertex space of this rect equals world
// space because the node sits at the origin unscaled.
//
// horizon_world = the ground line: the walk surface's top edge, where the
// mound tops and the platform rim catch the painted light.

uniform vec4 col_canopy : source_color = vec4(0.035, 0.065, 0.095, 1.0);
uniform vec4 col_mid : source_color = vec4(0.14, 0.30, 0.33, 1.0);
uniform vec4 col_glow : source_color = vec4(0.50, 0.76, 0.68, 1.0);
uniform vec4 col_water : source_color = vec4(0.07, 0.16, 0.17, 1.0);
// Ground-line height in world units.
uniform float horizon_world = 520.0;
// Half-width of the bright bloom around the horizon line, world units.
uniform float glow_width = 110.0;

varying vec2 world_pos;

void vertex() {
	// VERTEX here is the rect's LOCAL space; the node's origin sits far up
	// left of the world origin, so map through the transform instead.
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	// dy > 0 = below the ground line, up = height above it.
	float dy = world_pos.y - horizon_world;
	float up = -dy;

	// Canopy band: mid cool tone, sinking toward near-black. At the current
	// framing only ~0-300 world px of sky shows, so the ramps go dark fast.
	vec3 col = col_mid.rgb;
	col = mix(col, col_canopy.rgb, smoothstep(150.0, 900.0, up));

	// The glow hugging the walk line, the pale bloom behind the playing band.
	float near_h = 1.0 - smoothstep(60.0, 260.0, up);
	vec3 horizon_zone = mix(col, col_glow.rgb, near_h);
	col = horizon_zone;

	// Below the line the water tone drowns the glow.
	col = mix(col, col_water.rgb, smoothstep(0.0, 500.0, dy) * 0.94);

	// Luminous bloom hugging the ground line itself.
	float glow = 1.0 - clamp(abs(dy) / glow_width, 0.0, 1.0);
	col = mix(col, col_glow.rgb, glow * glow * 0.8);

	COLOR = vec4(col, 1.0);
}
