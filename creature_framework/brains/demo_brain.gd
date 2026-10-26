class_name DemoBrain
extends Brain
## Debug brain for automated T0 tuning. Drives the goal through four scripted
## regimes on a fixed loop so a run is reproducible and measurable without a
## human mouse: climb, hover, sink/glide, and a long bank turn.
## RULE: writes the Intent only; never touches the body or locomotors.

const REGIME_SECONDS := 6.0
const REGIME_COUNT := 4

var total: float = 0.0
var origin: Vector2 = Vector2.INF


func think(creature: Creature, intent: Intent, dt: float) -> void:
    if origin == Vector2.INF:
        origin = creature.body.pos[creature.rig.center_point]
    total += dt
    var regime := int(total / REGIME_SECONDS) % REGIME_COUNT
    var t: float = fmod(total, REGIME_SECONDS)
    intent.has_goal = true
    intent.desired_speed = 1.0
    match regime:
        0:   # climb: goal high and slightly forward, so lift must beat gravity
            intent.goal = origin + Vector2(120.0 + sin(t * 1.1) * 60.0, -260.0)
        1:   # hover: goal parked near the spawn point, no motion to lean on
            intent.goal = origin + Vector2(30.0, 40.0)
        2:   # sink/glide: goal low, arrival by gliding rather than flapping
            intent.goal = origin + Vector2(260.0, 230.0)
        3:   # bank: goal swaps sides hard, forcing a turn and re-facing
            intent.goal = origin + Vector2(-420.0 + sin(t * 1.3) * 70.0, -90.0 + cos(t * 0.7) * 50.0)
    var d: Vector2 = intent.goal - creature.body.pos[creature.rig.center_point]
    intent.urgency = clampf(d.length() / 400.0, 0.0, 1.0)
    if absf(d.x) > 30.0:
        intent.look_dir = Vector2(signf(d.x), 0.0)


func regime_label() -> String:
    var names: PackedStringArray = ["climb", "hover", "sink", "bank"]
    return names[int(total / REGIME_SECONDS) % REGIME_COUNT]
