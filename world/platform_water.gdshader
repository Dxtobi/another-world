shader_type canvas_item;
// Water platform surface: everything in platform_surface.gdshader plus the
// screen-space planar mirror.
//
// ENABLE_REFLECTIONS is defined here and only here. Sampling the screen forces
// a backbuffer copy, so keeping this flag out of the dry-surface wrapper means
// only water materials pay for it, and no non-water draw can ever be affected
// by the copy.
//
// Tuning knobs for the mirror: reflect_amount, reflect_floor (deep-water
// strength), reflect_squash (0 = exact 1:1 planar mirror; raise it to squeeze
// more scenery into shallow water, which shrinks tall reflections), reflect_blur
// /_grow/_max, reflect_sky (what a ray sees above the screen), reflect_absorb
// (depth darkening) and water_solid (how completely the water replaces the
// background). shore_wave_amp/_len break the straight polygon waterline into a
// hand-drawn curve; refract_amount is 0 for opaque water. See
// platform_styles.gd "swamp_water".

#define ENABLE_REFLECTIONS

#include "res://world/platform_surface_impl.gdshaderinc"
