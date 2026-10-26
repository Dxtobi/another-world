class_name PlatformShapes
extends RefCounted
## Height fields for the natural platform archetypes: fallen log, boulder,
## giant monster rib. Each returns PackedFloat32Array of size w*h where 0.0 is
## outside the silhouette and >0.0 is surface height inside it. NrmBaker turns
## that into the mask + normal pair.
##
## These are real volumes (cylinder cross-sections, radial domes), not flat
## shapes with a bevel faked on afterward. That distinction is the whole point:
## a bevelled outline reads as a sticker with a rim, a true volume reads as a
## form that lighting can wrap around.
##
## Height is in PIXELS, not a normalised ramp. The baker takes a gradient, and
## a normalised field spread over a few hundred pixels yields a slope near
## 1/200 -- a normal that reads as flat and never catches the light. Pixel units
## also make surface detail physical: grain is a couple of millimetres of
## relief sitting on a form, not a percentage of however big the form is.
##
## That is why macro and detail stay separate below. The macro form is scaled
## by its own radius; detail is added afterwards in absolute pixels. Folding
## them together -- dome = sqrt(1 - rr*rr) + noise * 0.17, then * base_r --
## produced 27px of relief across a 48px wavelength, a slope above 1. That is a
## cliff, not a surface, and it rendered as cauliflower.

## Pixels the silhouette is allowed to breathe into. Too small and the edge
## aliases into a hard stair-step that lights as a bright wire; too large and
## platforms stop reading as solid.
const EDGE_FADE := 6.0

## Surface grain amplitude, as a fraction of the form's own radius.
const SURFACE_RELIEF := 0.028

## Bark gets its own, lower figure. A log is 520px long and only ~150px deep, so
## the relative amplitude that suits a boulder becomes corrugation across the
## whole visible face.
const BARK_RELIEF := 0.016


static func _noise(seed_v: int, freq: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = freq
	# Two octaves, not four. Each octave doubles frequency while halving
	# amplitude, so the slopes roughly cancel -- but the top octave still sits
	# at 8x the base frequency and shows up as uniform fizz over the form.
	n.fractal_octaves = 2
	return n


## Value noise sampled on a circle, so angular lookups wrap seamlessly.
static func _ring(noise: FastNoiseLite, angle: float, radius: float) -> float:
	return noise.get_noise_2d(cos(angle) * radius, sin(angle) * radius)


## Lengthwise bark furrows, signed and in [-1, 1].
##
## Bark is broad plates split by narrow cracks, so the profile is asymmetric:
## long flat stretches, occasional deep splits. A pure sine is symmetric by
## construction, which is why the log kept reading as corrugated iron.
##
## Built from noise rather than trigonometry -- the sine only contributes a
## slow lengthwise drift, so the furrows wander and merge the way real bark
## does instead of marching in even parallel ranks.
static func _bark(noise: FastNoiseLite, x: float, y: float) -> float:
	var stretch := noise.get_noise_2d(x * 0.06, y * 0.9)
	var crack := noise.get_noise_2d(x * 0.22, y * 2.1)
	# Noise is in [-1, 1]; abs() folds it so the zeros become ridges rather
	# than the sign flips producing mirrored bands.
	var ridge := 1.0 - absf(stretch * 1.6 + crack * 0.5)
	# Cubed: near-flat plate tops, narrow splits at the troughs.
	var shaped := pow(clampf(ridge, 0.0, 1.0), 3.0)
	var drift := sin(y * 0.08 + noise.get_noise_2d(x * 0.3, 0.0) * 3.0) * 0.18
	return clampf(shaped * 2.0 - 1.0 + drift, -1.0, 1.0)


# ---------------------------------------------------------------- fallen log

static func fallen_log(w: int, h: int, seed_v := 11, sag := 0.05) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(w * h)
	var edge_n := _noise(seed_v, 0.018)
	# Separate from edge_n: _bark samples at very different coordinate scales
	# (x * 0.06 against x * 0.22), and sharing one field couples the silhouette
	# wobble to the surface grooves.
	var bark_n := _noise(seed_v + 7, 0.09)

	var r_max := h * 0.44

	for x in w:
		var u := x / float(maxi(w - 1, 1))
		for y in h:
			var i := y * w + x
			# Broken ends: the cut line moves with y, so the break is ragged
			# instead of a clean vertical slice.
			var lx := (0.02 + 0.06 * (_ring(edge_n, y * 0.09, 1.0) * 0.5 + 0.5)) * w
			var rx := w - 1.0 - (0.02 + 0.06 * (_ring(edge_n, y * 0.09 + 1.7, 1.0) * 0.5 + 0.5)) * w
			if x < lx or x > rx:
				continue

			var axis := h * 0.5 + sin(u * PI) * sag * h
			# Slightly fatter through the middle; ends never taper to a point.
			var r := r_max * (1.0 - 0.18 * pow(absf(u * 2.0 - 1.0), 2.0))
			r *= 1.0 + 0.11 * _ring(edge_n, u * TAU, 3.0)
			# Bark ridges break the silhouette as well as the surface. Without
			# this, top and bottom run as clean arcs and the log reads as a
			# lathe-turned dowel rather than something that fell and split.
			r *= 1.0 + 0.07 * bark_n.get_noise_2d(x * 0.05, y * 0.45)

			var t := (y - axis) / r
			if absf(t) >= 1.0:
				continue
			var dome := sqrt(1.0 - t * t)

			# Grain in absolute pixels, and faded out near the very edge so it
			# does not fight the chamfer. Slope is what matters here, not
			# amplitude: 0.03 of the dome over a 25px wavelength still landed
			# near the barrel's own curvature, which is why the log came out
			# looking like corduroy rather than wood.
			var grain := _bark(bark_n, x, y) * r * BARK_RELIEF

			# Chamfer toward the broken ends so they read as a cut face.
			var end_dist := minf(x - lx, rx - x)
			out[i] = (maxf(dome, 0.0) * r + grain * smoothstep(0.0, 0.25, dome)) \
					* smoothstep(0.0, EDGE_FADE, end_dist)
	return out


# -------------------------------------------------------------------- boulder

static func boulder(w: int, h: int, seed_v := 23) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(w * h)
	# Ring lookups are sampled on a circle of radius R, so the cycles per
	# revolution are freq * 2*pi*R -- not freq * R. At R = base_r * 1.1 = 176,
	# a frequency of 0.05 gave 55 cycles, which warped the dome into a
	# starburst. These target ~5 broad lobes and ~11 chips.
	var angular := _noise(seed_v, 0.010)
	var chips := _noise(seed_v + 17, 0.010)
	var lumps := _noise(seed_v + 3, 0.008)
	var grit := _noise(seed_v + 11, 0.020)

	var cx := w * 0.5
	var cy := h * 0.58
	var aspect := 1.0 - 0.22 * (float(h) / float(maxi(w, 1)))  # rocks sit wider than tall
	# Limited by cx * aspect, not cx. aspect shrinks dx, so the horizontal
	# half-extent is really base_r / aspect -- at 0.806 that came to 198px
	# against a 170px half-width, clipping the rock into a rounded square.
	var base_r := minf(cx * aspect, cy) * 0.94

	for y in h:
		for x in w:
			var i := y * w + x
			var dx := (x - cx) * aspect
			var dy := y - cy
			var rad := sqrt(dx * dx + dy * dy)
			if rad >= base_r * 1.45:
				continue

			var ang := atan2(dy, dx)
			# Two ring lookups at different radii: broad lobes from the inner
			# one, chipped edges from the outer. The ring is sampled at radius
			# base_r * 0.5, so 0.010 there is about 5 cycles per revolution.
			var wob := 1.0 + 0.28 * _ring(angular, ang, base_r * 0.5) \
					+ 0.09 * _ring(chips, ang, base_r * 1.1)
			var edge := base_r * wob
			if rad >= edge:
				continue

			# The dome deliberately ignores the angle. Driving it from
			# rad / (base_r * wob) makes the surface polar, and then every
			# radial ridge converges on a singularity at the centre -- the
			# pinwheel. Wobble decides where the rock ends; the grain decides
			# what its surface looks like.
			var dome := sqrt(maxf(1.0 - pow(rad / base_r, 2.0), 0.0))
			# Fade to nothing at the rim so the mask edge stays a clean
			# antialiased line rather than a cliff.
			var rim := smoothstep(0.0, 0.14, (edge - rad) / maxf(base_r, 1.0))
			# Weighted toward the low-frequency lumps. Fine, even micro-texture is
			# what makes procedural relief read as a photograph; the reference
			# sheets put their detail in a few large, deliberate forms.
			var grain := (lumps.get_noise_2d(x, y) * 0.82
					+ grit.get_noise_2d(x, y) * 0.18) * base_r * SURFACE_RELIEF
			out[i] = (dome * base_r + grain * smoothstep(0.0, 0.3, dome)) * rim
	return out


# ------------------------------------------------------------- monster rib

## A giant rib as a bowed arc. Thick where it met the spine (left), tapering
## to the free tip (right), with the knuckle of the joint bulging at the root.
static func rib(w: int, h: int, seed_v := 37) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(w * h)
	var bone_n := _noise(seed_v, 0.028)
	var poro_n := _noise(seed_v + 5, 0.07)

	# Axis as y = f(x) first, so we can get its slope for perpendicular distance.
	var axis := PackedFloat32Array()
	axis.resize(w)
	for x in w:
		var u := x / float(maxi(w - 1, 1))
		axis[x] = h * 0.82 - h * 0.66 * sin(u * PI * 0.92)

	for y in h:
		for x in w:
			var i := y * w + x
			var u := x / float(maxi(w - 1, 1))

			var daxis := (axis[mini(x + 1, w - 1)] - axis[maxi(x - 1, 0)]) * 0.5
			var slope_len := sqrt(1.0 + daxis * daxis)

			# Free-end taper plus a knuckle where it joined the vertebra.
			var t := h * 0.115 * (0.34 + 0.66 * pow(1.0 - u, 0.75))
			t += h * 0.075 * exp(-pow((u - 0.055) / 0.075, 2.0))
			t *= 1.0 + 0.12 * bone_n.get_noise_2d(x * 0.5, y * 0.5)
			if t < 0.5:
				continue

			# Distance measured perpendicular to the axis, not straight down.
			var d := absf(y - axis[x]) / slope_len
			if d >= t:
				continue

			var dome := sqrt(1.0 - pow(d / t, 2.0))
			dome += poro_n.get_noise_2d(x, y) * 0.05 * smoothstep(0.0, 0.4, dome)
			dome *= smoothstep(0.0, EDGE_FADE, minf(x, w - 1 - x))

			# Pixel units, in keeping with the other shapes.
			out[i] = maxf(dome, 0.0) * t
	return out


## Registry the test scene and, later, the world generator both read from.
static func make(kind: StringName, w: int, h: int, seed_v: int) -> PackedFloat32Array:
	match kind:
		&"log":
			return fallen_log(w, h, seed_v)
		&"rock":
			return boulder(w, h, seed_v)
		&"rib":
			return rib(w, h, seed_v)
	return boulder(w, h, seed_v)
