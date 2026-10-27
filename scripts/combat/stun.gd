extends RefCounted
# Stun and boss poise rules (Godot 4.0, no class_name).
# Pure functions: no scene access, so they are easy to unit test.
# Usage: const Stun = preload("res://scripts/combat/stun.gd")
# Config: data/stun.json, loaded as Data.stun_cfg.
#
# `dmg` must be the damage AFTER armour / resist mitigation (the amount that
# actually leaves the life pool). Armour therefore never double dips.
# `max_life` is the final max life including passives, gear and gems.
# `thr_mult` is the "stun threshold" stat (1.0 = default). Higher = harder to stun.

# kind: "player", "normal" or "elite". Bosses use the poise functions instead;
# passing "boss" here is an error (there is no "boss" entry in kinds).
static func stun_ratio(dmg: float, max_life: float) -> float:
	if max_life <= 0.0 or dmg <= 0.0:
		return 0.0
	return dmg / max_life


static func _threshold(cfg: Dictionary, kind: String, thr_mult: float) -> float:
	var base: float = cfg.kinds[kind].threshold
	return base * maxf(thr_mult, float(cfg.min_threshold_mult))


# 0 below threshold, rises linearly from min_chance to 100% at guarantee_ratio.
static func stun_chance(cfg: Dictionary, kind: String, dmg: float, max_life: float, thr_mult: float = 1.0) -> float:
	if not cfg.enabled:
		return 0.0
	var ratio := stun_ratio(dmg, max_life)
	var thr := _threshold(cfg, kind, thr_mult)
	var guarantee: float = cfg.guarantee_ratio
	# Guarantee is checked first so a high threshold stat can never block a 50%+ hit.
	if ratio >= guarantee:
		return 1.0
	if ratio <= thr:
		return 0.0
	var t := (ratio - thr) / (guarantee - thr)
	return lerpf(float(cfg.min_chance), 1.0, t)


# min_duration at the threshold, max_duration at the guarantee ratio, capped.
static func stun_duration(cfg: Dictionary, kind: String, dmg: float, max_life: float, thr_mult: float = 1.0) -> float:
	var k: Dictionary = cfg.kinds[kind]
	var thr := _threshold(cfg, kind, thr_mult)
	var guarantee: float = cfg.guarantee_ratio
	var t := 1.0
	if thr < guarantee:
		t = clampf((stun_ratio(dmg, max_life) - thr) / (guarantee - thr), 0.0, 1.0)
	return lerpf(float(k.min_duration), float(k.max_duration), t)


# Roll the stun. `rng_value` is a 0..1 float from your seeded RNG so the
# smartbot stays deterministic. Returns the stun duration, or 0.0 for no stun.
# The caller checks and sets its own immunity timer (cfg.immunity_after_stun).
static func try_stun(cfg: Dictionary, kind: String, dmg: float, max_life: float, rng_value: float, thr_mult: float = 1.0) -> float:
	var chance := stun_chance(cfg, kind, dmg, max_life, thr_mult)
	if chance <= 0.0 or rng_value > chance:
		return 0.0
	return stun_duration(cfg, kind, dmg, max_life, thr_mult)


# ---------- Boss poise ----------
# Boss keeps: var poise_state := Stun.new_poise()
static func new_poise() -> Dictionary:
	return {"poise": 0.0, "since_hit": 0.0, "immune": 0.0, "stagger": 0.0}


# Returns true when this hit staggers the boss.
# Big hits get a bonus that ramps smoothly: 1x at big_hit_start (5% of max life)
# up to big_hit_multiplier (1.75x) at big_hit_full (15%), so there is no cliff.
static func poise_hit(cfg: Dictionary, st: Dictionary, dmg: float, max_life: float) -> bool:
	if not cfg.enabled or st["immune"] > 0.0 or st["stagger"] > 0.0:
		return false
	var p: Dictionary = cfg.poise
	var ratio := stun_ratio(dmg, max_life)
	var pts := ratio / float(p.fill_fraction) * 100.0 * poise_multiplier(cfg, ratio)
	st["poise"] = st["poise"] + pts
	st["since_hit"] = 0.0
	if st["poise"] >= 100.0:
		st["poise"] = 0.0
		st["stagger"] = float(p.stagger_duration)
		# Both timers tick together, so this leaves 8 s of immunity after the stagger ends.
		st["immune"] = float(p.immunity_after_stagger) + float(p.stagger_duration)
		return true
	return false


# Bonus multiplier for a hit of `ratio` (damage / boss max life).
static func poise_multiplier(cfg: Dictionary, ratio: float) -> float:
	var p: Dictionary = cfg.poise
	var a: float = p.big_hit_start
	var b: float = p.big_hit_full
	var t := 1.0
	if b > a:
		t = clampf((ratio - a) / (b - a), 0.0, 1.0)
	elif ratio < a:
		t = 0.0
	return lerpf(1.0, float(p.big_hit_multiplier), t)


# Call every physics frame. Timers count down; poise regenerates when not hit.
static func poise_tick(cfg: Dictionary, st: Dictionary, delta: float) -> void:
	var p: Dictionary = cfg.poise
	st["stagger"] = maxf(0.0, st["stagger"] - delta)
	st["immune"] = maxf(0.0, st["immune"] - delta)
	st["since_hit"] = st["since_hit"] + delta
	if st["since_hit"] > float(p.regen_delay) and st["poise"] > 0.0:
		st["poise"] = maxf(0.0, st["poise"] - float(p.regen_per_sec) * delta)
