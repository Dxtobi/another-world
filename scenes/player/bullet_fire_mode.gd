class_name BulletFireMode
extends FireMode
## Wraps your existing gun scene (the one with gun.gd and shoot()) as a mode,
## so normal shooting behaves exactly as before.

## The gun node with a shoot(dir) method. Defaults to the player's `gun`.
@export var gun: Node


func _ready() -> void:
	if mode_name == "Mode":
		mode_name = "Bullets"
	if gun == null:
		var host := get_parent()
		while host != null and gun == null:
			var g = host.get("gun")
			if g is Node:
				gun = g
			host = host.get_parent()
	if gun == null:
		push_warning("BulletFireMode: no gun found. Assign `gun` in the inspector.")


func fire(dir: Vector2) -> bool:
	if gun == null or not gun.has_method("shoot"):
		return false
	gun.shoot(dir)
	fired.emit()
	return true
