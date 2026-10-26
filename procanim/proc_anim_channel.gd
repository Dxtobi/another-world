@tool
class_name ProcAnimChannel
extends Resource
## One moving target inside a clip.

enum Shape { SINE, NOISE, ELLIPSE, STEP }

## Name of the Marker2D to move. It is searched for under the animator's Targets Root.
@export var target_name: StringName = &""
## SINE: back-and-forth. NOISE: random-looking drift. ELLIPSE: loop. STEP: foot lifting then planting.
@export var shape: Shape = Shape.SINE
## Pixels. SINE/NOISE: swing size. ELLIPSE: radius. STEP: X = half stride, Y = lift height.
## A creature facing left should use a NEGATIVE X for STEP.
@export var amplitude := Vector2(0.0, 4.0)
@export_range(-180.0, 180.0, 0.1, "or_greater", "or_less", "suffix:°") var rotation_amplitude := 0.0
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:Hz") var frequency := 0.5
## Offset inside the cycle (0 to 1). Stagger this to make legs step in sequence.
@export_range(0.0, 1.0, 0.01) var phase := 0.0


static func _wobble(t: float) -> float:
	return 0.6 * sin(t) + 0.3 * sin(t * 2.17 + 1.3) + 0.1 * sin(t * 3.71 + 2.1)


func sample_position(a: float) -> Vector2:
	match shape:
		Shape.SINE:
			return amplitude * sin(a)
		Shape.NOISE:
			return Vector2(_wobble(a) * amplitude.x, _wobble(a * 1.37 + 5.1) * amplitude.y)
		Shape.ELLIPSE:
			return Vector2(cos(a) * amplitude.x, sin(a) * amplitude.y)
		Shape.STEP:
			return Vector2(cos(a) * amplitude.x, minf(0.0, sin(a)) * amplitude.y)
	return Vector2.ZERO


func sample_rotation(a: float) -> float:
	var wave := sin(a)
	if shape == Shape.NOISE:
		wave = _wobble(a * 0.83 + 2.0)
	return deg_to_rad(rotation_amplitude) * wave
