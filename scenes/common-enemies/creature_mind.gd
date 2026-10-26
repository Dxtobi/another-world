class_name CreatureMind
extends Node
## Shared survival brain for the ecosystem. Any creature scene gets one as a
## child (named "CreatureMind") and is then graded on the same hierarchy:
##
##   HOW IT WORKS
##   - Every creature has a threat_level. When two meet, each side assesses:
##     ENGAGE (I outclass it), IGNORE (evenly matched, not worth it), or
##     FLEE (it outclasses me). The ratios below tune where those lines sit.
##   - Pain teaches fear: take a hard hit and you memorize the attacker and
##     run from it on sight until the memory fades. The player is not special
##     here — hurt something that lives and it will remember YOU.
##   - hive_linked creatures (the boss's brood) NEVER flee and NEVER learn
##     fear: they attack regardless, even what outclasses them.
##
##   ADOPTING IT (CommonEnemy, flesh monsters, ...):
##   1. Add a CreatureMind child, set threat_level (grunt ~1, beast ~3, boss 8+).
##   2. On a timer, pick the nearest foe and call assess() with its threat
##      (CreatureMind.threat_of(node) reads a mind child, a threat_level var,
##      or 1.0 when the foe isn't graded yet).
##   3. ENGAGE -> steer at it / strike it. FLEE -> run away while it is visible.
##   4. In your take_damage, call mind.remember(attacker) past your trauma line.
##   That's the whole contract; everything else is per-creature locomotion.

enum Stance { IGNORE, ENGAGE, FLEE }

## Graded scariness of the owner. Fights break out (or don't) on RATIOS of
## these, so a 3.0 beast bullies 1.0 grunts, ignores 3.0 rivals, and runs
## from 6.0 apexes — no per-matchup scripting needed.
@export var threat_level := 1.0
## Hive brood: fearless and unteachable. ENGAGE everything, remember nothing.
@export var hive_linked := false
## Engage at/above this threat ratio (mine / theirs).
@export_range(0.2, 5.0, 0.05) var fight_at := 1.0
## Flee at/below this threat ratio. Between the two lines: ignore.
@export_range(0.1, 5.0, 0.05) var flee_below := 0.7
## A single hit this big (or more) traumatizes: memorize + immediately flee.
@export_range(1, 20) var trauma_damage := 3
## How long one trauma is remembered (seconds). The nightmare stays scary
## this long after the last painful reminder.
@export_range(5.0, 120.0, 1.0, "suffix:s") var memory_time := 20.0

## instance_id -> seconds of fear left.
var fears := {}


## Re-grade a foe. Hive minds always come back ENGAGE.
func assess(foe_threat: float, foe_id: int) -> int:
	if hive_linked:
		return Stance.ENGAGE
	if fears.has(foe_id):
		return Stance.FLEE
	var ratio := threat_level / maxf(foe_threat, 0.01)
	if ratio >= fight_at:
		return Stance.ENGAGE
	if ratio <= flee_below:
		return Stance.FLEE
	return Stance.IGNORE


## Learn to fear a specific attacker (called from take_damage past trauma).
## Hive minds do not learn fear.
func remember(foe: Node) -> void:
	if foe == null or hive_linked:
		return
	fears[foe.get_instance_id()] = memory_time


func is_feared(foe: Node) -> bool:
	return foe != null and fears.has(foe.get_instance_id())


func _process(delta: float) -> void:
	if fears.is_empty():
		return
	for id in fears.keys():
		fears[id] = float(fears[id]) - delta
		if float(fears[id]) <= 0.0:
			fears.erase(id)


## Read any node's graded threat: its CreatureMind child wins, then a plain
## threat_level var (future-proof for non-mind scenes), else 1.0 ungraded.
static func threat_of(node: Node) -> float:
	if node == null:
		return 0.0
	var mind := node.get_node_or_null("CreatureMind")
	if mind != null:
		var t = mind.get("threat_level")
		if t != null:
			return maxf(float(t), 0.01)
	var v = node.get("threat_level")
	if v != null:
		return maxf(float(v), 0.01)
	return 1.0
