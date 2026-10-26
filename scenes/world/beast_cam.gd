class_name BeastCam
extends Camera2D
## Mouse-look camera for the beast demo: frames the beast, drifts toward
## the mouse so you can look ahead. Drop as a sibling of the beast,
## set Target to the beast node.

@export var target_path: NodePath
@export_range(0.0, 1.0, 0.05) var lookahead := 0.35
@export_range(40.0, 800.0, 10.0, "suffix:px") var max_dist := 280.0
@export_range(1.0, 20.0, 0.5) var follow_speed := 5.0
@export_range(0.4, 2.0, 0.05) var min_zoom := 0.4
@export_range(1.0, 4.0, 0.05) var max_zoom := 2.0
@export_range(0.05, 1.0, 0.05) var zoom_step := 0.25
@export_range(1.0, 20.0, 0.5) var zoom_speed := 8.0

var _t: Node2D
var _zoom_target := 0.3


func _ready() -> void:
	_t = get_node_or_null(target_path) as Node2D
	_zoom_target = clampf(_zoom_target, min_zoom, max_zoom)
	zoom = Vector2.ONE * _zoom_target
	make_current()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		_bump_zoom(zoom_step)
	elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_bump_zoom(-zoom_step)


# Step the zoom target, sliding the camera toward the cursor so the zoom
# feels anchored where you aim. Exact anchor math: the world point under
# the cursor stays fixed across the zoom change.
func _bump_zoom(delta: float) -> void:
	var new_zoom := clampf(_zoom_target + delta, min_zoom, max_zoom)
	if is_equal_approx(new_zoom, _zoom_target):
		return
	var m := get_global_mouse_position()
	# Zoom stays anchored on the cursor's x -- the wheel may not shove the
	# vertical framing around either, matching the X-only mouse lookahead.
	var anchored_x := m.x + (global_position.x - m.x) * (_zoom_target / new_zoom)
	global_position.x = anchored_x
	_zoom_target = new_zoom


func _process(delta: float) -> void:
	if _t == null or not is_instance_valid(_t):
		return
	var a := _t.global_position
	var m := get_global_mouse_position()
	var want := a + (m - a).limit_length(max_dist) * lookahead
	# X-only mouse lookahead: the cursor drags the camera sideways, never
	# up or down -- the vertical framing rides the target alone, so looking
	# around while the beast climbs or falls doesn't bob the frame.
	want.y = a.y
	var k := 1.0 - exp(-follow_speed * delta)
	global_position = global_position.lerp(want, k)
	zoom = zoom.lerp(Vector2.ONE * _zoom_target, 1.0 - exp(-zoom_speed * delta))
