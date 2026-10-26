extends Node2D

@export var sway := 35.0
@export var speed := 2.5
var base: Vector2
var t := 0.0

func _ready():
	base = position

func _process(delta):
	t += delta * speed
	position = base + Vector2(sin(t * 0.5) * 8.0, sin(t) * sway)
