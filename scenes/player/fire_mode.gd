class_name FireMode
extends Node
## One thing the gun can fire: bullets, a portal, and whatever you add later.
## Put FireMode nodes as children of a GunModes node. The controller decides
## which one is active and forwards the trigger; a mode only has to know how
## to fire along a direction.
##
## To add a new weapon type: extend this, set the exports, override fire().

signal fired

## Shown in a HUD and used by GunModes.unlock_mode("Portal").
@export var mode_name := "Mode"
## Locked modes can't be selected. Flip it from pickups / story progress.
@export var unlocked := true
## One shot per trigger pull (portals, grenades). False = fires every frame
## the trigger is held and relies on the mode's own cooldown (rifles).
@export var semi_auto := false
## Can the crosshair's hover auto-fire pull this trigger? Leave off for
## anything that should only happen when the player really presses fire.
@export var accepts_auto_fire := true

## Set by GunModes. True while this is the selected mode.
var active := false


## Fire along `dir` (already normalized or not; modes normalize themselves).
## Return true if something actually fired.
func fire(_dir: Vector2) -> bool:
	return false


func on_selected() -> void:
	pass


func on_deselected() -> void:
	pass
