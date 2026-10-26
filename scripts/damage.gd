class_name Damage
extends RefCounted
## Damage helpers for anything that implements take_damage().
## Extracted from the old CommonEnemy base class so the player and weapons do not
## depend on a specific enemy implementation. Crit/power rules live here, once.

## Ask a target whether this hit is critical at `pos`; apply its `crit_mult`
## (default 2x) when it is. Targets that do not implement the duck-typed API are
## simply hit for `base`.
static func damage_for(target: Object, pos: Vector2, base: int) -> int:
	if target != null and target.has_method("is_critical_hit") \
			and bool(target.call("is_critical_hit", pos)):
		var mult := 2.0
		var stored = target.get("crit_mult")
		if stored != null:
			mult = float(stored)
		return maxi(1, int(round(float(base) * mult)))
	return base
