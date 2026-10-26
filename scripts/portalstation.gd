class_name PortalStation
extends PortalDestination
## The fixed station. Make a scene with a single Node2D root, attach this
## script, drop it where you want arrivals to land. It draws itself (pad, ring,
## arrow) so there is no art to wire up; swap _draw for sprites whenever.

@export_range(2.0, 20.0, 0.5, "suffix:px") var pad_thickness := 6.0

var _flash := 0.0


func _ready() -> void:
	set_process(false)
	queue_redraw()


func notify_received(body: Node2D, portal: Node) -> void:
	super(body, portal)
	_flash = 1.0
	set_process(true)


func _process(delta: float) -> void:
	_flash = maxf(_flash - delta * 2.5, 0.0)
	queue_redraw()
	if _flash <= 0.0:
		set_process(false)


## Paper-cut station: a stamped plate with a darker under-layer offset a
## couple of pixels (the classic cut-paper shadow), and a clear arrow floating
## above it. Local up (0,-1) is the exit direction, so the plate hangs BELOW
## the origin and bodies stand on its top edge.
func _draw() -> void:
	var col := accent if enabled else accent.darkened(0.6)
	var h := span * 0.5
	var thick := pad_thickness * 2.2

	# under-layer first: the same plate nudged down, as a paper shadow
	var plate := _plate(h, thick)
	var shadow := PackedVector2Array()
	for p in plate:
		shadow.append(p + Vector2(2.0, 3.0))
	draw_colored_polygon(shadow, Color(Color.BLACK, 0.25))

	# the plate
	draw_colored_polygon(plate, Color(col.darkened(0.4), 0.9))
	# lit top edge, so it reads as a surface rather than a bar
	draw_line(Vector2(-h, 0.0), Vector2(h, 0.0), col, 3.0)

	# Chevrons carved INTO the plate pointing the way things leave. They live
	# below the surface line on purpose: a body standing here always covers
	# anything drawn above the plate, which is where the old floating arrow
	# used to be.
	for i in 3:
		var cy := thick * (0.28 + 0.26 * float(i))
		var cw := h * 0.34
		var ch := thick * 0.2
		draw_polyline(PackedVector2Array([
			Vector2(-cw, cy + ch), Vector2(0.0, cy), Vector2(cw, cy + ch)]),
			Color(col.lightened(0.25), 0.85), 2.0, true)

	if _flash > 0.0:
		# arrival pulse: a ring pushing up out of the plate
		var r := lerpf(span * 0.15, span * 0.55, 1.0 - _flash)
		draw_arc(Vector2(0.0, -6.0), r, 0.0, TAU, 24, Color(col, _flash * 0.8), 3.0)


## The plate outline: a slab below the origin with lightly clipped corners.
func _plate(h: float, thick: float) -> PackedVector2Array:
	var c := thick * 0.4
	return PackedVector2Array([
		Vector2(-h, 0.0),
		Vector2(h, 0.0),
		Vector2(h - c, thick),
		Vector2(-h + c, thick),
	])
