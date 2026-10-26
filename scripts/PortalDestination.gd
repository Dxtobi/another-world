class_name PortalDestination
extends Node2D
## Anything a portal can lead to. The portal gun only knows about this class,
## so a fixed station, a pin the player drops at runtime, or a door in another
## room are all just subclasses (or instances) of it.
##
## Placement rule: this node's position is the point on the SURFACE the body
## arrives at. The body is placed so its back edge sits here and it faces out
## along `exit_direction()` (default up, so it stands on the point).

signal received(body: Node2D)

const GROUP := &"portal_destination"

@export var label := "Station"
@export var enabled := true
## Direction bodies leave in, in this node's local space. -90 = up.
@export_range(-180.0, 180.0, 1.0, "degrees") var exit_angle_deg := -90.0
## Widest thing that can arrive here (measured across the exit direction).
@export_range(16.0, 600.0, 1.0, "suffix:px") var span := 120.0
## Bodies leaving are given at least this much speed along the exit direction.
@export_range(0.0, 1500.0, 10.0, "suffix:px/s") var exit_speed_min := 160.0
@export_range(0.0, 40.0, 0.5, "suffix:px") var exit_clearance := 2.0
## Colour shared by the portal gun's shot and the portal it opens.
@export var accent := Color(0.3, 0.8, 1.0)


func _enter_tree() -> void:
	add_to_group(GROUP)


func exit_direction() -> Vector2:
	return Vector2.from_angle(global_rotation + deg_to_rad(exit_angle_deg))


func exit_position() -> Vector2:
	return global_position


func is_available() -> bool:
	return enabled


## Called by a Portal after it delivered `body`. Override for effects.
func notify_received(body: Node2D, _portal: Node) -> void:
	received.emit(body)


static func all(tree: SceneTree) -> Array[PortalDestination]:
	var out: Array[PortalDestination] = []
	for n in tree.get_nodes_in_group(GROUP):
		if n is PortalDestination:
			out.append(n)
	return out
