class_name NrmBaker
extends RefCounted
## Bakes the two maps a world surface needs out of a height field.
##
## World art ships as flat silhouettes, or is generated straight from noise,
## so what we actually have is height. From that we derive:
##
##   mask   R8    the silhouette, read as .r by surface.gdshader
##   normal RGB8  standard 3D-style map (z toward viewer, green-up)
##
## The normal must go through NORMAL_MAP and never NORMAL. Godot 2D's native
## normal convention is flipped relative to a 3D map, so assigning to NORMAL
## lights every surface inside-out -- see surface.gdshader.

## Fraction of a shape's own peak height that the silhouette ramps across.
## Height rises as sqrt(distance from the edge) on any dome, so a fixed
## absolute softness aliases on thick shapes and smears on thin ones.
## Normalising by the field maximum lands the ramp near a pixel either way.
const OUTLINE_SOFTNESS := 0.12
## Sobel taps sum to 4x the true gradient; pull it back to a real slope.
const SOBEL_NORM := 0.25


static func height_to_mask(height: PackedFloat32Array, w: int, h: int) -> Image:
	# Silhouettes are scale-free, so the ramp is measured against this
	# shape's own peak rather than against pixels. The normal field below
	# deliberately stays in absolute pixels.
	var peak: float = 0.0
	for v in height:
		peak = maxf(peak, v)
	var inv_peak: float = 1.0 / maxf(peak, 0.0001)

	var img := Image.create_empty(w, h, false, Image.FORMAT_R8)
	var bytes := PackedByteArray()
	bytes.resize(w * h)
	for i in w * h:
		var t := smoothstep(0.0, OUTLINE_SOFTNESS, height[i] * inv_peak)
		bytes[i] = int(clampf(t, 0.0, 1.0) * 255.0)
	img.set_data(w, h, false, Image.FORMAT_R8, bytes)
	return img


static func height_to_normal(height: PackedFloat32Array, w: int, h: int, strength := 1.0) -> Image:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGB8)
	var bytes := PackedByteArray()
	bytes.resize(w * h * 3)
	var s := strength * SOBEL_NORM

	for y in h:
		var ym := maxi(y - 1, 0) * w
		var y0 := y * w
		var yp := mini(y + 1, h - 1) * w
		for x in w:
			var xm := maxi(x - 1, 0)
			var xp := mini(x + 1, w - 1)

			# Sobel taps, central differences. Image y points down.
			var gx := (height[ym + xp] + 2.0 * height[y0 + xp] + height[yp + xp]) \
					- (height[ym + xm] + 2.0 * height[y0 + xm] + height[yp + xm])
			var gy := (height[yp + xm] + 2.0 * height[yp + x] + height[yp + xp]) \
					- (height[ym + xm] + 2.0 * height[ym + x] + height[ym + xp])

			# Encoded green-up -- the OpenGL convention a 3D-authored map uses,
			# which is what NORMAL_MAP documents itself as accepting.
			#
			# Red and green consequently carry opposite signs. Red measures
			# against +x, which runs the same way as the image's x. Green
			# measures against "up", which runs against the image's +y. So
			# green is +gy where red is -gx.
			#
			# Getting this backwards fails quietly: every surface lights
			# inside-out, the log's upper face going bright when the light is
			# beneath it. Check with nrm_test.gd's probe_light() before trusting
			# it -- the control run there makes the flip unmistakable.
			var nx := -gx * s
			var ny := gy * s
			var inv_len := 1.0 / sqrt(nx * nx + ny * ny + 1.0)
			nx *= inv_len
			ny *= inv_len

			var o := (y0 + x) * 3
			bytes[o] = int(clampf(nx * 0.5 + 0.5, 0.0, 1.0) * 255.0)
			bytes[o + 1] = int(clampf(ny * 0.5 + 0.5, 0.0, 1.0) * 255.0)
			bytes[o + 2] = int(clampf(inv_len * 0.5 + 0.5, 0.0, 1.0) * 255.0)

	img.set_data(w, h, false, Image.FORMAT_RGB8, bytes)
	return img


## Raises a soft dome at each accent point, so a glowing nodule is also a
## physical bump that catches specular and rim.
##
## The accent list is deliberately shared between the height field and the
## shader. When only the shader knew about them the accents read as decals stuck
## onto a flat surface; in the references the glowing nodules are bumps *of* the
## form, and that shared relief is most of why they look embedded rather than
## pasted on.
##
## Points are [x_px, y_px, radius_px, height_px]. Mutates height in place.
static func stamp_nodules(height: PackedFloat32Array, w: int, h: int,
		points: Array) -> void:
	for p in points:
		var cx: float = p[0]
		var cy: float = p[1]
		var rad: float = p[2]
		var rise: float = p[3]
		if rad <= 0.0:
			continue
		var x0 := maxi(int(cx - rad), 0)
		var x1 := mini(int(ceil(cx + rad)), w)
		var y0 := maxi(int(cy - rad), 0)
		var y1 := mini(int(ceil(cy + rad)), h)
		for y in range(y0, y1):
			for x in range(x0, x1):
				var dx := x - cx
				var dy := y - cy
				var d := sqrt(dx * dx + dy * dy)
				if d >= rad:
					continue
				# sqrt profile: full height at the centre, and an infinite
				# slope at the rim, so the nodule meets the surface at a
				# defined edge instead of feathering away into nothing.
				height[y * w + x] += rise * sqrt(1.0 - pow(d / rad, 2.0))


## Cutout + normal, paired for CanvasTexture.diffuse / .normal_map.
static func bake(height: PackedFloat32Array, w: int, h: int, strength := 1.0) -> Dictionary:
	return {
		"mask": ImageTexture.create_from_image(height_to_mask(height, w, h)),
		"normal": ImageTexture.create_from_image(height_to_normal(height, w, h, strength)),
	}
