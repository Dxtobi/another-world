shader_type canvas_item;
render_mode unshaded, blend_mix;

// Full-screen underwater wash. The player is drawn above the opaque water
// polygon while submerged; this overlay tints that cutaway and adds slow
// caustic bands. It deliberately does not read the screen texture, so it also
// works in the compatibility renderer without another backbuffer copy.

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 shallow_tint : source_color = vec4(0.05, 0.33, 0.34, 1.0);
uniform vec4 deep_tint : source_color = vec4(0.015, 0.095, 0.14, 1.0);
uniform float caustic_amount : hint_range(0.0, 0.5) = 0.16;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.5;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME;

	float depth = clamp(uv.y * 0.85 + (value_noise(uv * 3.0 + t * 0.03) - 0.5) * 0.18, 0.0, 1.0);
	vec3 col = mix(shallow_tint.rgb, deep_tint.rgb, depth);

	// Two interfering bands make slow, soft caustics instead of a moving
	// striped texture. Kept low so it never competes with the player.
	float w1 = sin(uv.x * 34.0 + t * 0.55 + sin(uv.y * 19.0 - t * 0.42) * 2.1);
	float w2 = sin(uv.x * 19.0 - t * 0.38 + sin(uv.y * 27.0 + t * 0.31) * 1.7);
	float caustic = smoothstep(0.72, 0.99, abs(w1 * 0.6 + w2 * 0.4));
	col += caustic * caustic_amount * vec3(0.30, 0.62, 0.58);
	col += (value_noise(uv * 5.0 - t * 0.02) - 0.5) * 0.035;

	vec2 q = uv - vec2(0.5);
	float vig = smoothstep(0.78, 0.20, length(q));
	float alpha = intensity * mix(0.34, 0.58, vignette_strength * (1.0 - vig));
	alpha += caustic * intensity * 0.035;
	COLOR = vec4(col, clamp(alpha, 0.0, 0.86));
}
