class_name LocoManager
extends RefCounted
## Picks the best locomotor (with hysteresis) and crossfades their outputs by weight.

var c: Creature
var locomotors: Array[Locomotor] = []
var current: Locomotor
var blend_time: float = 0.35     # seconds for a full crossfade
var stickiness: float = 0.25     # score bonus for the current locomotor (anti-flicker)
var lock_time: float = 0.5       # minimum seconds between switches
var _lock: float = 0.0


func setup(creature: Creature, scripts: Array[GDScript]) -> void:
    c = creature
    for s in scripts:
        var l: Locomotor = s.new()
        l.c = creature
        locomotors.append(l)
    if locomotors.size() > 0:
        current = locomotors[0]
        current.weight = 1.0
        current.enter()


func update(dt: float, intent: Intent, out: MoveOutput) -> void:
    if current == null:
        return
    _lock -= dt
    _maybe_switch(intent)

    var total: float = 0.0
    for l in locomotors:
        var target_w: float = 1.0 if l == current else 0.0
        l.weight = move_toward(l.weight, target_w, dt / blend_time)
        total += l.weight
    if total <= 0.0001:
        return
    for l in locomotors:
        if l.weight > 0.001:
            out.scale = l.weight / total      # normalised so blended forces never double up
            l.emit(dt, intent, out)
    out.scale = 1.0


func _maybe_switch(intent: Intent) -> void:
    if _lock > 0.0 or locomotors.size() < 2:
        return
    var best: Locomotor = current
    var best_score: float = current.score(intent) + stickiness
    for l in locomotors:
        if l == current:
            continue
        var s: float = l.score(intent)
        if s > best_score:
            best = l
            best_score = s
    if best != current:
        current.exit()
        current = best
        current.enter()
        _lock = lock_time
