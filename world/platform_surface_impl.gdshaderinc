// Painted surface for hand-drawn platforms, v2. SHARED IMPLEMENTATION.
//
// This file is #included by two thin wrappers so the screen-reading mirror
// only compiles into the shader that needs it:
//   platform_surface.gdshader  - rock/ground/moss/snow/sand: no screen copy.
//   platform_water.gdshader    - defines ENABLE_REFLECTIONS before including
//                                this file, so water (and only water) pays
//                                the backbuffer-copy cost.
// Do not add shader_type here; it belongs in the wrappers.
//
// Everything from v1 is kept (same uniform names, same outline texture, same
// atmosphere), so platform_styles.gd keeps working. New in v2:
//
// WATER   depth gradient (shallow -> deep), real mirrored REFLECTIONS of what
//         is drawn behind the water, ripple distortion + blur growing with
//         depth, fresnel fade, perspective ripple streaks, sun glint column,
//         bright shoreline sheen.
// ROCK    planar facets (painterly chiselled planes), sedimentary strata,
//         dark pits/pores, ragged chipped edges, backlit silhouette glow.
// MOSS    lumpy lit moss mounds that cap flat tops, with a shadow lip under
//         them, like the lime mounds in the forest reference.
// GLOW    drifting bioluminescent flecks.
//
// All new features default to 0 = off, so existing presets look the same
// (except water, which now uses the new water colours).
//
// REFLECTION COST: sampling the screen forces a backbuffer copy. Only
// platform_water.gdshader defines ENABLE_REFLECTIONS, so only water pays it.
//
// REFLECTION MODEL (v3): the water is a planar mirror. A pixel vd below the
// visible surface line samples the screen vd above it, so the mirrored world
// hangs under the waterline exactly as it does in the reference paintings.
// Because the screen copy only holds what is currently on screen, the mirror
// fades into reflect_sky once it runs off the top edge instead of clamping a
// bright row into a smear -- that clamp was the "only half the reflection is
// there" bug. Reflections also composite opaquely (water_solid) now: blending
// a mirror over the unmirrored background at ~50% alpha was cancelling most
// of the effect. Lower water_solid / reflect_floor for a glassy overlay.
//
// NOTE: shader files accept // comments only.

#ifdef ENABLE_REFLECTIONS
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
#endif

// ---------------------------------------------------------------- palettes

uniform vec4 tint : source_color = vec4(1.0);

// mass -> band -> accent is the value ramp, darkest at the walls.
uniform vec4 col_mass : source_color = vec4(0.10, 0.12, 0.11, 1.0);
uniform vec4 col_band : source_color = vec4(0.16, 0.19, 0.17, 1.0);
uniform vec4 col_accent : source_color = vec4(0.30, 0.34, 0.27, 1.0);
uniform vec4 col_rim : source_color = vec4(0.73, 0.86, 0.82, 1.0);
uniform vec4 col_haze : source_color = vec4(0.10, 0.16, 0.19, 1.0);
uniform vec4 col_fog : source_color = vec4(0.60, 0.70, 0.66, 1.0);

// Moss: dark inner colour and the sunlit lime at the top of each mound.
uniform vec4 col_moss : source_color = vec4(0.22, 0.34, 0.12, 1.0);
uniform vec4 col_moss_lit : source_color = vec4(0.62, 0.78, 0.26, 1.0);
// Cyan-ish glow used for backlight and flecks.
uniform vec4 col_glow : source_color = vec4(0.25, 0.85, 0.95, 1.0);

uniform float rim_strength = 0.8;
uniform float rim_width = 7.0;
uniform float value_bands = 3.0;
uniform float detail_scale = 1.0;

// ---------------------------------------------------------------- depth

uniform float haze_amount = 0.0;
uniform float mist_band = 300.0;
uniform float depth_rank = 0.0;
uniform float focus_near = 600.0;
uniform float focus_far = 1800.0;
uniform float feather = 3.0;

// ---------------------------------------------------------------- features

uniform float grain_amount = 0.20;
uniform float mottle_amount = 0.0;
uniform float crack_amount = 0.0;
uniform float dune_amount = 0.0;
uniform float snow_amount = 0.0;
uniform float alpha_body = 1.0;

// ---- new rock features
uniform float facet_amount = 0.0;    // chiselled planes: rock, cliffs
uniform float strata_amount = 0.0;   // horizontal rock layers
uniform float pit_amount = 0.0;      // dark pores / knots (tree bark, pocked stone)
uniform float edge_wobble = 0.0;     // ragged rim/moss edge, in px (try 3-6)
uniform float backlight_amount = 0.0;// glow bleeding on unlit silhouettes
uniform float brush_amount = 0.0;    // stretched painterly streaks in the grain

// ---- moss
uniform float moss_amount = 0.0;     // 0..1 coverage strength
uniform float moss_depth = 22.0;     // px thickness of moss on flat tops

// ---- glow flecks
uniform float fleck_amount = 0.0;

// ---- water
uniform float water_amount = 0.0;
uniform float water_opacity = 0.82;
uniform vec4 col_water_shallow : source_color = vec4(0.28, 0.66, 0.68, 1.0);
uniform vec4 col_water_deep : source_color = vec4(0.03, 0.14, 0.20, 1.0);
// px of depth at which the water has reached ~63% of the deep colour.
uniform float water_depth = 140.0;
// Reflection strength, how far down it fades (px), ripple wobble (px).
uniform float reflect_amount = 0.85;
uniform float reflect_fade = 260.0;
uniform float reflect_distort = 5.0;
uniform vec4 reflect_tint : source_color = vec4(0.80, 0.93, 1.0, 1.0);
// Strength the mirror keeps in deep water (fresnel floor). 0 = the old
// "only the first 100 px reflect" look, 0.55-0.75 = full body reflection.
uniform float reflect_floor = 0.55;
// 0 = true planar mirror: an object h px above the waterline appears h px
// below it, with the same proportions. > 0 squeezes more of the scene into
// the visible water band, which shrinks tall scenery (a whole forest can fit
// in ~100 px of water, but it looks compressed). Use 0 for correct geometry.
uniform float reflect_squash = 0.0;
// Blur in screen px at the surface and per screen px of depth, capped so deep
// water goes soft rather than turning into three separated copies.
uniform float reflect_blur = 1.2;
uniform float reflect_blur_grow = 0.05;
uniform float reflect_blur_max = 12.0;
// What a mirror ray sees once it leaves the top of the screen: sky/haze.
uniform vec4 reflect_sky : source_color = vec4(0.10, 0.20, 0.22, 1.0);
// How much the water body absorbs the mirror with depth (0 = none).
uniform float reflect_absorb = 0.25;
// How opaque the water body is over the background, 0 = old translucent
// blend, 1 = the mirror fully replaces what is behind the water.
uniform float water_solid = 0.85;
// Set by the player while their head is under the surface. At 1 the surface
// mirror/sky is replaced by a depth gradient, giving the vertical cutaway
// read instead of a bright reflected sky above the submerged player.
uniform float underwater_amount = 0.0;
// Local px from the waterline down to the volume's actual bottom. WaterVolume
// pushes it from its collision polygon so the underwater gradient spans the
// real water shape (shallow at the line, darkest at the bottom).
uniform float underwater_max_depth = 1800.0;
// See-through water is OPT-IN. A planar mirror can only show what is ABOVE
// the waterline; scenery drawn behind/below it can only be seen by sampling
// straight through the surface. 0 = opaque water (default: submerged objects
// stay hidden), > 0 lets the environment read through the surface, bent by
// the ripples and absorbed by the deep colour.
uniform float refract_amount = 0.0;
uniform float refract_distort = 4.0;
uniform float refract_depth = 120.0;
uniform float refract_absorb = 0.55;
uniform vec4 refract_tint : source_color = vec4(0.72, 0.90, 0.86, 1.0);
// White dash ripples seen in the reference.
uniform float streak_amount = 0.7;
// Sun/moon glint column: screen-space x (0..1) and strength.
uniform float glint_amount = 0.0;
uniform float glint_x = 0.5;
uniform float glint_width = 0.06;
// Bright thin sheen where water meets the air.
uniform float surface_sheen = 0.8;
// Optional hand-drawn shoreline. Godot polygon edges are straight segments,
// so the waterline between two vertices is a ruler line no matter how the rest
// of the art reads. This cuts a gentle, non-repeating wave into the water's top
// alpha: the water starts a few px lower where the wave dips, and the land
// drawn behind it fills the difference. 0 = perfectly straight edge (default).
uniform float shore_wave_amp = 0.0;
uniform float shore_wave_len = 1400.0;

// ---- moving surface deformation (water only) ---------------------------
// The waterline is the polygon's top edge, so the mesh itself cannot rise
// above it. These knobs instead cut the visible surface a few px BELOW that
// edge at rest (surface_baseline) and let it dip further or rise back up to
// the edge when disturbed. Disturbance sources are fed per frame as a small
// texture (x local px, age seconds, strength); each one is a ring that
// travels outward, so a splash leaves a moving ring in the waterline itself
// rather than only a flat ring drawn on top of a ruler-straight edge.
uniform float surface_wave_amount = 1.0;
uniform float surface_wave_height = 10.0;  // px of crest/trough per source
uniform float surface_wave_speed = 150.0;  // px/s the ring travels outward
uniform float surface_wave_len = 70.0;     // px between ripples in the train
uniform float surface_wave_decay = 260.0;  // px falloff away from a source
uniform float surface_wave_life = 2.2;     // s until a source has faded out
uniform float surface_swell = 1.4;         // px of always-on idle swell
uniform float surface_baseline = 6.0;      // px the calm line sits below the edge
// Set by WaterVolume from the camera zoom (1 = normal, 2.5 = zoomed out to 0.4,
// capped). The deformation is in world px, so it has to grow to stay readable
// on screen when the camera pulls back. Scaling here rather than rewriting the
// uniforms above keeps per-platform shader_overrides intact.
uniform float surface_wave_zoom = 1.0;
uniform sampler2D wave_tex : filter_nearest;
uniform float wave_count = 0.0;

// ---------------------------------------------------------------- outline

uniform float pt_count = 0.0;
uniform sampler2D pts_tex : filter_nearest;
uniform float winding = 1.0;

varying vec2 local_pos;
// Screen UV travelled per local pixel (so reflections are zoom-correct).
varying float uv_per_y;
varying float uv_per_x;

void vertex() {
	local_pos = VERTEX;
	mat4 m = SCREEN_MATRIX * CANVAS_MATRIX * MODEL_MATRIX;
	vec4 o = m * vec4(0.0, 0.0, 0.0, 1.0);
	vec4 ux = m * vec4(1.0, 0.0, 0.0, 1.0);
	vec4 uy = m * vec4(0.0, 1.0, 0.0, 1.0);
	uv_per_x = max(abs(ux.x - o.x) * 0.5, 0.00001);
	uv_per_y = max(abs(uy.y - o.y) * 0.5, 0.00001);
}

vec2 pt_get(float idx) {
	return texture(pts_tex, vec2((idx + 0.5) / 128.0, 0.5)).xy;
}

// ------------------------------------------------------------------ noise

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float out_v = 0.0;
	float amp = 0.55;
	for (int o = 0; o < 3; o++) {
		out_v += vnoise(p) * amp;
		p *= 2.13;
		amp *= 0.5;
	}
	return out_v;
}

float banded(float x, float n) {
	if (n < 2.0) {
		return x;
	}
	return floor(x * n + 0.5) / n;
}

// Horizontal dash ripples. Rows bunch up toward the surface (far water) and
// spread out with depth (near water), which is what sells the perspective in
// the lake reference.
float water_streaks(vec2 pos, float vd, float sc, float t) {
	float persp = log(1.0 + vd / (16.0 * sc));
	float n1 = vnoise(vec2(pos.x * (0.018 / sc) + t * 0.10, persp * 9.0));
	float n2 = vnoise(vec2(pos.x * (0.040 / sc) - t * 0.17, persp * 15.0 + 7.0));
	float s1 = smoothstep(0.64, 0.80, n1);
	float s2 = smoothstep(0.68, 0.82, n2) * 0.7;
	return clamp(s1 + s2, 0.0, 1.0);
}

// Visible offset of the waterline below the polygon's top edge, in local px.
// 0 = at the edge (a crest), larger = the surface has dipped down. The calm
// surface rests at surface_baseline so crests have headroom to rise into;
// ambient swell keeps the line alive, and every disturbance source adds a
// ring travelling outward at surface_wave_speed.
float surface_waves(vec2 pos, float wsc) {
	if (surface_wave_amount < 0.001) {
		return 0.0;
	}
	// World-pixel features scale with the inverse camera zoom so the motion
	// keeps the same on-screen size far out.
	float k = clamp(surface_wave_zoom, 1.0, 8.0);
	float len_px = max(surface_wave_len * k, 1.0);
	float speed = surface_wave_speed * k;
	float base_h = max(surface_baseline, 0.0) * k;

	float h = base_h;
	h += surface_swell * k * (0.62 * sin(pos.x * (0.021 / wsc) + TIME * 0.8)
			+ 0.38 * sin(pos.x * (0.052 / wsc) - TIME * 1.25));

	int wc = int(min(wave_count, 8.0));
	for (int i = 0; i < 8; i++) {
		if (i >= wc) {
			break;
		}
		vec4 w = texture(wave_tex, vec2((float(i) + 0.5) / 8.0, 0.5));
		float age = w.y;
		float str = w.z;
		if (str < 0.001) {
			continue;
		}
		float d = abs(pos.x - w.x);
		float front = age * speed;
		float fall = exp(-d / max(surface_wave_decay * k, 1.0));
		float fade = exp(-age * (2.4 / max(surface_wave_life, 0.05)));
		// Nothing in front of the travelling front: the disturbance has not
		// arrived there yet, so the water must not wobble ahead of it.
		float behind = 1.0 - smoothstep(-6.0, 22.0, d - front);
		// A wave train of ~3 cycles trailing behind the front, with a second
		// harmonic so chop follows a splash instead of one smooth hill.
		float trail = max(front - d, 0.0);
		float envelope = exp(-trail / (len_px * 3.5));
		float ph = trail * (6.2831853 / len_px);
		float chop = sin(ph) * 0.8 + 0.35 * sin(ph * 1.87 + 1.1);
		// Fade the very centre: a source is a ring, not a spike. Crests lead
		// the travel outward, troughs trail behind them.
		h -= surface_wave_height * k * str * fall * fade * behind * envelope
				* chop * smoothstep(0.0, 24.0 * k, d + 1.0);
	}
	return clamp(h, 0.0, 60.0 * wsc * k);
}

void fragment() {
	vec2 pos = local_pos;
	float sc = max(detail_scale, 1.0);

	// ---- outline walk: nearest lit face, nearest any, nearest unlit ------
	int count = int(min(pt_count, 128.0));
	float best = 1e9;
	float d_any = 1e9;
	float d_unlit = 1e9;
	float flatness = 0.0;
	float vdepth = 0.0; // vertical distance below the lit top face
	// Depth below the *deformed* waterline (set in the water block, used again
	// by the alpha section so the cut follows the same moving surface).
	float vd_visible = 0.0;
	vec2 first = pt_get(0.0);
	vec2 prev = first;
	for (int i = 0; i < 128; i++) {
		if (i >= count) {
			break;
		}
		vec2 a = prev;
		vec2 b = (i + 1 >= count) ? first : pt_get(float(i + 1));
		prev = b;
		vec2 dir = b - a;
		float len = length(dir);
		if (len < 0.001) {
			continue;
		}
		dir /= len;
		vec2 rel = pos - a;
		float t = clamp(dot(rel, dir), 0.0, len);
		float d = distance(pos, a + dir * t);
		if (d < d_any) {
			d_any = d;
		}
		if (dir.x * winding < 0.05) {
			if (d < d_unlit) {
				d_unlit = d;
			}
			continue;
		}
		if (d < best) {
			best = d;
			flatness = 1.0 - abs(dir.y);
			vdepth = abs(dir.x) > 0.2 ? pos.y - (a.y + dir.y / dir.x * (pos.x - a.x)) : d;
		}
	}

	// Ragged edge: chipped rock / uneven moss line. Used by every edge effect.
	float wob = (fbm(pos * (0.07 / sc)) - 0.4) * edge_wobble * sc;
	float best_n = max(best + wob, 0.0);

	// ---- surface focus ---------------------------------------------------
	float focus = smoothstep(focus_near, focus_far, best);
	float detail_keep = 1.0 - focus * 0.9;

	// ---- body ------------------------------------------------------------
	vec3 albedo = mix(col_mass.rgb, col_band.rgb, banded(flatness, value_bands));

	if (mottle_amount > 0.001) {
		float mottle = mottle_amount * detail_keep;
		float mpatch = smoothstep(0.42, 0.6, fbm(pos * (0.013 / sc)));
		albedo = mix(albedo, col_accent.rgb * (0.85 + 0.3 * fbm(pos * (0.06 / sc))),
				mottle * mpatch);
	}

	// Chiselled planes: voronoi cells, each given a fake facing against a
	// light from the upper left, then grouped into value bands.
	if (facet_amount > 0.001) {
		vec2 fp = pos * (0.045 / sc);
		fp += vec2(fp.y * 0.35, -fp.x * 0.2);
		vec2 ip = floor(fp);
		vec2 fr = fract(fp);
		float md = 8.0;
		vec2 mc = ip;
		for (int cy = -1; cy <= 1; cy++) {
			for (int cx = -1; cx <= 1; cx++) {
				vec2 g = vec2(float(cx), float(cy));
				vec2 o = vec2(hash21(ip + g), hash21(ip + g + 17.3));
				vec2 r = g + o - fr;
				float dd = dot(r, r);
				if (dd < md) {
					md = dd;
					mc = ip + g;
				}
			}
		}
		float ang = hash21(mc + 4.1) * 6.2831;
		vec2 light = normalize(vec2(-0.4, -1.0));
		float facing = 0.5 + 0.5 * dot(vec2(cos(ang), sin(ang)), light);
		if (value_bands >= 2.0) {
			facing = banded(facing, value_bands);
		}
		albedo *= 1.0 + facet_amount * detail_keep * (facing - 0.5) * 0.9;
	}

	// Sedimentary layers: warped stripes, dark seam plus a pale ledge above.
	if (strata_amount > 0.001) {
		float warp = fbm(pos * (0.012 / sc)) * 8.0;
		float s = sin(pos.y * (0.085 / sc) + warp);
		float seam = smoothstep(0.80, 0.98, s);
		float ledge = smoothstep(0.55, 0.80, s) * (1.0 - seam);
		albedo *= 1.0 - strata_amount * detail_keep * 0.35 * seam;
		albedo += col_accent.rgb * strata_amount * detail_keep * 0.10 * ledge;
	}

	if (crack_amount > 0.001) {
		float crack = crack_amount * detail_keep;
		float ridge = 1.0 - abs(fbm(pos * (0.055 / sc)) * 2.0 - 1.0);
		albedo *= 1.0 - crack * 0.55 * smoothstep(0.86, 0.995, ridge);
	}

	if (dune_amount > 0.001) {
		float dune = dune_amount * detail_keep;
		float warp = fbm(pos * (0.021 / sc)) * 9.0;
		float band = smoothstep(0.45, 1.0, sin(pos.y * (0.16 / sc) + warp));
		albedo = mix(albedo, col_accent.rgb * 1.12, dune * 0.30 * band);
	}

	// Dark pores / knots, like the pocked bark in the forest reference.
	if (pit_amount > 0.001) {
		vec2 pp = pos * (0.03 / sc);
		vec2 pc = floor(pp);
		vec2 pf = fract(pp) - 0.5;
		float ph = hash21(pc + 9.7);
		if (ph < 0.32) {
			vec2 off = (vec2(hash21(pc + 1.3), hash21(pc + 2.9)) - 0.5) * 0.4;
			vec2 q = (pf - off) * vec2(1.0, 1.0 + ph * 5.0);
			float pit = 1.0 - smoothstep(0.09, 0.17, length(q));
			albedo = mix(albedo, col_mass.rgb * 0.35, pit * pit_amount * (0.4 + 0.6 * detail_keep));
		}
	}

	// Fine grain plus optional stretched brush strokes.
	float grain_v = vnoise(pos * (0.75 / sc)) - 0.5;
	albedo *= 1.0 + grain_amount * detail_keep * grain_v * mix(0.35, 1.0, flatness);
	if (brush_amount > 0.001) {
		float brush = vnoise(vec2(pos.x * (0.035 / sc), pos.y * (0.35 / sc))) - 0.5;
		albedo *= 1.0 + brush_amount * detail_keep * brush * 0.7;
	}

	albedo = mix(albedo, col_mass.rgb, focus * 0.75);

	// ---- moss mounds on lit flat faces ----------------------------------
	if (moss_amount > 0.001) {
		float lump = 0.35 + 1.0 * vnoise(vec2(pos.x * (0.045 / sc), 5.0))
				+ 0.4 * vnoise(vec2(pos.x * (0.13 / sc), 9.0));
		float mdepth = max(moss_depth * sc * lump * smoothstep(0.25, 0.85, flatness), 0.001);
		float cover = 1.0 - smoothstep(mdepth * 0.82, mdepth, best_n);
		float mh = clamp(1.0 - best_n / mdepth, 0.0, 1.0);
		float leaf = 0.85 + 0.3 * vnoise(pos * (0.5 / sc));
		vec3 mcol = mix(col_moss.rgb, col_moss_lit.rgb, banded(mh * (0.55 + 0.45 * fbm(pos * (0.08 / sc))), value_bands));
		albedo = mix(albedo, mcol * leaf, cover * moss_amount);
		// Shadow lip just under the mound so it reads as sitting on the rock.
		float lip = smoothstep(mdepth, mdepth * 1.2, best_n)
				* (1.0 - smoothstep(mdepth * 1.2, mdepth * 1.7, best_n));
		albedo *= 1.0 - lip * 0.35 * moss_amount * smoothstep(0.25, 0.85, flatness);
	}

	albedo *= 1.0 - depth_rank * 0.45;

	// ---- edges: rim light, snow ------------------------------------------
	float rim_px = rim_width * sc;
	float edge = 1.0 - smoothstep(0.0, rim_px, best_n);
	float rim_foot = rim_strength * (1.0 - depth_rank * 0.8);
	float rim_var = smoothstep(0.30, 0.68, fbm(vec2(pos.x * (0.006 / sc), 3.0)));
	float rim = edge * banded((0.3 + 0.7 * flatness) * edge, value_bands)
			* (0.2 + 0.8 * rim_var);
	vec3 out_col = albedo + col_rim.rgb * rim * rim_foot;

	float core = 1.0 - smoothstep(0.0, max(1.5, 1.5 * sc), best_n);
	out_col += col_rim.rgb * core * rim_foot * 0.55 * (0.35 + 0.65 * rim_var);

	// Backlight: the glow behind the scene bleeds onto unlit silhouettes.
	if (backlight_amount > 0.001) {
		float back = smoothstep(0.5 * sc, 2.0 * sc, d_unlit)
				* (1.0 - smoothstep(2.0 * sc, 9.0 * sc, d_unlit));
		out_col += col_glow.rgb * back * backlight_amount * 0.45 * (1.0 - depth_rank * 0.5);
	}

	if (snow_amount > 0.001) {
		float settle = fbm(pos * (0.09 / sc));
		float snow_edge = 1.0 - smoothstep(0.0, rim_px * (0.9 + settle * 0.8), best_n);
		float snow = snow_amount * snow_edge * (0.55 + 0.45 * flatness);
		out_col = mix(out_col, vec3(0.90, 0.94, 0.95), clamp(snow, 0.0, 1.0));
	}

	// ---- glow flecks -----------------------------------------------------
	if (fleck_amount > 0.001) {
		vec2 fq = pos * (0.11 / sc);
		vec2 fc = floor(fq);
		float fh = hash21(fc + 3.3);
		if (fh < 0.07) {
			vec2 fo = vec2(hash21(fc + 5.1), hash21(fc + 8.7)) * 0.6 + 0.2;
			float dotv = 1.0 - smoothstep(0.05, 0.16, length(fract(fq) - fo));
			float tw = 0.65 + 0.35 * sin(TIME * (1.0 + fh * 12.0) + fh * 40.0);
			out_col += col_glow.rgb * dotv * tw * fleck_amount * detail_keep * (1.0 - depth_rank * 0.5);
		}
	}

	// ---- water -------------------------------------------------------------
	if (water_amount > 0.001) {
		// Detail scale is proportional to the platform's size (1..32) so
		// grain and rims stay readable on huge ground pieces. Water optics
		// must NOT grow like that: a 20,000 px lake would get a 4,500 px
		// "deep" colour and 160 px ripples, i.e. a flat mirror. Clamp it.
		float wsc = clamp(sc, 1.0, 3.0);
		// The surface line itself moves. `wave_off` is how far below the
		// polygon's top edge the visible waterline sits right now, so the
		// depth gradient, mirror, streaks and sheen all hang off the moving
		// line instead of the straight mesh edge.
		float wave_off = surface_waves(pos, wsc);
		float vd = max(max(vdepth, 0.0) - wave_off, 0.0);
		vd_visible = vd;
		float depth_t = 1.0 - exp(-vd / (water_depth * wsc));
		vec3 wcol = mix(col_water_shallow.rgb, col_water_deep.rgb, depth_t);

		// Slow broad luminosity swell so the body is never a flat gradient.
		wcol *= 0.92 + 0.16 * fbm(vec2(pos.x * (0.010 / sc) + TIME * 0.03, vd * (0.020 / sc)));

		// Dash ripples. Also used to break up the mirror so it reads as a
		// water surface instead of a pasted-on photograph.
		float st = water_streaks(pos, vd, sc, TIME);

		// Grazing angle / depth fade, with a floor: the mirror survives all
		// the way down instead of dying ~100 px below the surface.
		float fres = mix(reflect_floor, 1.0, exp(-vd / (reflect_fade * wsc)));

		vec3 mirror_col = wcol;
		float mirror_mask = 0.0;
		// How much of the screen behind the water the refraction let through;
		// the underwater gradient is mixed with this kept, so submerged
		// bodies show as tinted silhouettes instead of being painted over.
		float refract_mix = 0.0;

#ifdef ENABLE_REFLECTIONS
		if (reflect_amount > 0.001) {
			// Ripple wobble, in local px. Grows with depth so the waterline
			// itself stays crisp while the deeper mirror swims.
			float wob_x = (vnoise(vec2(pos.x * (0.05 / sc) + TIME * 0.45, vd * (0.10 / sc))) - 0.5)
					* 2.0 * reflect_distort * wsc * (0.25 + min(vd / (70.0 * wsc), 1.0));
			float wob_y = (vnoise(vec2(pos.x * (0.09 / sc) - TIME * 0.35, vd * (0.25 / sc) + 11.0)) - 0.5)
					* 2.0 * reflect_distort * 0.5 * wsc * min(vd / (50.0 * wsc), 1.0);

			// Screen line of the water surface at this x. The sample is
			// (1 + reflect_squash) * vd above the pixel; 0 is the exact
			// planar mirror (vd above the line), > 0 compresses.
			float surf_y = SCREEN_UV.y - vd * uv_per_y;
			float mirror = vd * (1.0 + reflect_squash);
			vec2 ruv = vec2(SCREEN_UV.x + wob_x * uv_per_x,
					surf_y - mirror * uv_per_y + wob_y * uv_per_y);

			// Never sample back through the surface: that pixel is this water
			// itself, and self-sampling is what washed the mirror out before.
			ruv.y = min(ruv.y, surf_y - 0.5 * uv_per_y);

			// Blur in screen px, growing with depth but capped: soft deep
			// water, no triple-image ghosting from huge tap spacing.
			float vd_px = vd * uv_per_y / max(SCREEN_PIXEL_SIZE.y, 0.000001);
			float blur_px = min(reflect_blur + reflect_blur_grow * vd_px, reflect_blur_max);
			vec2 b = SCREEN_PIXEL_SIZE * blur_px;
			vec2 suv = clamp(ruv, vec2(0.0), vec2(1.0));
			vec3 refl = texture(screen_tex, suv).rgb * 0.36;
			refl += texture(screen_tex, clamp(suv + vec2(b.x, 0.0), vec2(0.0), vec2(1.0))).rgb * 0.16;
			refl += texture(screen_tex, clamp(suv - vec2(b.x, 0.0), vec2(0.0), vec2(1.0))).rgb * 0.16;
			refl += texture(screen_tex, clamp(suv + vec2(0.0, b.y), vec2(0.0), vec2(1.0))).rgb * 0.16;
			refl += texture(screen_tex, clamp(suv - vec2(0.0, b.y), vec2(0.0), vec2(1.0))).rgb * 0.16;
			refl *= reflect_tint.rgb;

			// Past the top of the screen there is nothing left to mirror.
			// Fall back to the sky colour instead of clamping a bright row
			// into a vertical smear -- the old `clamp(ruv.y, 0, 1)`.
			// Keep this narrow: a squashed mirror legitimately samples close
			// to the top of the screen, and a wide fade painted the whole
			// upper water body with flat sky colour, erasing the forest.
			float off_top = 1.0 - smoothstep(0.0, 0.012, ruv.y);
			refl = mix(refl, reflect_sky.rgb, off_top);

			// The water body absorbs light with depth, reflection included.
			refl *= mix(1.0, 1.0 - reflect_absorb, depth_t);

			// Ripples break the mirror up. Keep some structure so it still
			// reads as a reflection, not as flat tinted water.
			float breakup = mix(0.62, 1.0, st);
			mirror_col = refl;
			mirror_mask = clamp(reflect_amount * fres, 0.0, 1.0) * mix(1.0, breakup, 0.45);
		}

		// ---- refraction: the world behind the water ---------------------
		// The mirror only has the world above the waterline. Everything drawn
		// behind/below it is still in the screen copy, so look straight
		// through the surface and let the deep colour absorb it. The same
		// ripples bend the view, which is what sells the water as a volume.
		if (refract_amount > 0.001) {
			vec2 duv = vec2(
					(vnoise(vec2(pos.x * (0.030 / sc), vd * (0.060 / sc) + TIME * 0.20)) - 0.5)
							* 2.0 * refract_distort * wsc * uv_per_x,
					(vnoise(vec2(pos.x * (0.050 / sc) + 9.0, vd * (0.100 / sc))) - 0.5)
							* refract_distort * wsc * uv_per_y);
			vec3 through = texture(screen_tex,
					clamp(SCREEN_UV + duv, vec2(0.0), vec2(1.0))).rgb;
			through = mix(through, col_water_deep.rgb, clamp(depth_t * refract_absorb, 0.0, 1.0));
			through *= refract_tint.rgb;
			float rm = refract_amount * smoothstep(0.0, refract_depth * wsc, vd);
			wcol = mix(wcol, through, rm);
			refract_mix = rm;
			// The surface still belongs to the mirror; refraction owns depth.
			mirror_mask *= 1.0 - rm * 0.5;
		}
#endif

		// Under the cutaway the mirror would reflect the sky from above the
		// waterline, which reads as a hole in the water: drop it entirely.
		mirror_mask *= 1.0 - clamp(underwater_amount, 0.0, 1.0);
		wcol = mix(wcol, mirror_col, clamp(mirror_mask, 0.0, 1.0));

		// Dash ripples, brightest near the surface, thinning out with depth.
		wcol += col_rim.rgb * st * streak_amount * (1.0 - depth_t * 0.55) * 0.45;

		// Glint column under the sun/moon, broken up by the same ripples.
		if (glint_amount > 0.001) {
			float gx = (SCREEN_UV.x - glint_x) / max(glint_width, 0.001);
			float col_mask = exp(-gx * gx);
			float broken = 0.35 + 0.65 * water_streaks(pos * vec2(1.0, 1.0) + vec2(37.0, 0.0), vd, sc, TIME * 1.3);
			wcol += vec3(1.0, 0.97, 0.88) * col_mask * broken * glint_amount * fres;
		}

		// Sheen where the water meets the air.
		float sheen = (1.0 - smoothstep(0.0, 2.2 * sc, vd))
				* (0.55 + 0.45 * vnoise(vec2(pos.x * (0.08 / sc) + TIME * 0.5, 2.0)));
		float soft_edge = edge * 0.25;
		wcol += col_rim.rgb * (sheen + soft_edge) * surface_sheen;

		// Cross-section view: when the camera/player is under the surface the
		// mirror is meaningless (it would reflect the sky above the waterline).
		// Replace the whole surface look with a plain depth gradient anchored
		// on the moving waterline: shallow colour at the top, then a long
		// linear falloff toward the deep tone at the volume's real bottom, so
		// the tint is bounded by the actual water shape and never screens wide.
		float under_t = clamp(vd / max(underwater_max_depth, 1.0), 0.0, 1.0);
		float under_ease = under_t * under_t * (3.0 - 2.0 * under_t);
		vec3 under_grad = mix(col_water_shallow.rgb, col_water_deep.rgb * 0.7, under_ease);
		// Keep whatever the refraction showed through (submerged bodies and
		// scenery) instead of painting the gradient straight over it. The
		// gradient still gets a share, so the water keeps its depth colour.
		float grad_amount = clamp(underwater_amount, 0.0, 1.0)
				* (1.0 - clamp(refract_mix, 0.0, 1.0) * 0.55);
		wcol = mix(wcol, under_grad, grad_amount);

		out_col = mix(albedo, wcol, water_amount);
	}

	// ---- ground-line mist --------------------------------------------------
	// Water keeps its reflection clean, so mist is fully suppressed on it.
	float mist = (1.0 - smoothstep(0.0, mist_band, best)) * haze_amount
			* (1.0 - water_amount);
	out_col = mix(out_col, col_fog.rgb, clamp(mist, 0.0, 0.85));

	// ---- shared atmosphere ------------------------------------------------
	// Haze still unifies the scene, but it is pulled back over water so it
	// cannot grey the mirror out.
	float atmo = smoothstep(0.42, 0.92, 1.0 - SCREEN_UV.y);
	float haze_mix = clamp(atmo * haze_amount + depth_rank * 0.55, 0.0, 0.85)
			* (1.0 - water_amount * 0.5);
	out_col = mix(out_col, col_haze.rgb, haze_mix);

	// ---- soft silhouette on unlit edges ----------------------------------
	float feather_px = feather * sc;
	float alpha_edge = smoothstep(0.0, feather_px, d_unlit);
	// Dry body fades with alpha_body; water composites over the background at
	// water_solid, because the mirror *is* the background of a planar
	// reflection. Blending it at alpha_body (~0.5) cancelled half the effect.
	float alpha = alpha_body * alpha_edge;
	if (water_amount > 0.001) {
		// Opaque right up to the line. Scaling the dry feather by sc (a huge
		// lake has sc=32) faded the first ~100 px to transparent and read as
		// see-through water. Keep only a hairline of AA.
		float water_feather_px = max(feather * 0.4, 0.75);
		float water_edge = smoothstep(0.0, water_feather_px, d_unlit);
		float solid = water_opacity;
#ifdef ENABLE_REFLECTIONS
		solid = mix(water_opacity, 1.0, clamp(water_solid, 0.0, 1.0));
#endif
		// Keep a soft shoreline in the opacity blend, but let water_solid = 1
		// reach full opacity all the way to the edge.
		float shore_fade = mix(0.72, 1.0,
				smoothstep(0.0, 24.0 * clamp(sc, 1.0, 3.0), vd_visible));
		solid *= mix(shore_fade, 1.0, clamp(water_solid, 0.0, 1.0));
		alpha = mix(alpha_body, solid, clamp(water_amount, 0.0, 1.0))
				* water_edge;
		// Break the ruler-straight polygon edge. The water mesh stops at the
		// authored top edge, so the wave can only pull the visible surface
		// DOWN; the land/backdrop behind the water fills the exposed strip.
		if (shore_wave_amp > 0.001) {
			float sx = pos.x / max(shore_wave_len, 1.0);
			float wave = 0.55 + 0.45 * sin(sx * 6.2831853)
					+ 0.22 * sin(sx * 13.64 + 1.3);
			wave = clamp(wave, 0.0, 1.0) * shore_wave_amp;
			alpha *= smoothstep(wave, wave + water_feather_px, vd_visible);
		}
		// Deformed waterline: everything above the moving surface is air, so
		// crests rise and troughs dip while the mesh stays put.
		alpha *= smoothstep(0.0, water_feather_px, vd_visible);
	}
	COLOR = vec4(out_col * tint.rgb, alpha * tint.a);
}
