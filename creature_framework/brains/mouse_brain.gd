class_name MouseBrain
extends Brain
## Debug brain: the goal is the mouse cursor.


func think(creature: Creature, intent: Intent, _dt: float) -> void:
    intent.has_goal = true
    intent.goal = creature.get_global_mouse_position()
    intent.desired_speed = 1.0
    var d: Vector2 = intent.goal - creature.body.pos[creature.rig.center_point]
    intent.urgency = clampf(d.length() / 400.0, 0.0, 1.0)
    if absf(d.x) > 30.0:
        intent.look_dir = Vector2(signf(d.x), 0.0)
