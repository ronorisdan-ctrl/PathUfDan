extends RefCounted
## Endgame Phase 2D: the Collector's Wager and Pentimento Vaults (docs/ENDGAME_PHASE2.md,
## data/atlas.json mechanics.wager / mechanics.vault). Pure rules: offers, stakes, payouts, vault
## counts and types. The dungeon owns the live state and passes its own mech_rng stream in, so the
## main run stream (layout, packs, loot) is never touched by these rolls.

const AtlasRules = preload("res://scripts/core/atlas_rules.gd")

static func wcfg() -> Dictionary:
	return AtlasRules.mech_cfg().get("wager", {})

static func vcfg() -> Dictionary:
	return AtlasRules.mech_cfg().get("vault", {})

# ------------------------------------------------------------------ the Collector's Wager
static func bets() -> Array:
	return wcfg().get("bets", [])

static func bet_info(id: String) -> Dictionary:
	for b in bets():
		if str(b.get("id", "")) == id:
			return b
	return {}

## Can the Collector offer bet b in a zone with these mechanics and this many living elites /
## monsters ahead (-1 = not checked)? `min_monsters` (Phase 2E): Frenzy needs packs left to kill.
static func bet_ok(b: Dictionary, mechs: Array, elites_left: int, monsters_left: int = -1) -> bool:
	var nm := str(b.get("needs_mech", ""))
	if nm != "" and not mechs.has(nm):
		return false
	if b.get("needs_elites", false) and elites_left <= 0:
		return false
	if monsters_left >= 0 and monsters_left < int(b.get("min_monsters", 0)):
		return false
	return true

## `n` distinct bet ids (weighted, without repeats) drawn with rng.
static func offers(rng: RandomNumberGenerator, mechs: Array, elites_left: int, n: int = -1, monsters_left: int = -1) -> Array:
	if n < 0:
		n = int(wcfg().get("offers", 3))
	var pool := []
	for b in bets():
		if bet_ok(b, mechs, elites_left, monsters_left):
			pool.append(b)
	var out := []
	while out.size() < n and not pool.is_empty():
		var total := 0.0
		for b in pool:
			total += float(b.get("w", 1))
		var roll := rng.randf() * total
		var pick: Dictionary = pool[pool.size() - 1]
		for b in pool:
			roll -= float(b.get("w", 1))
			if roll <= 0.0:
				pick = b
				break
		out.append(str(pick["id"]))
		pool.erase(pick)
	return out

## The numbers of a bet in this zone: {time, count, skills, life, hits}. `chambers` = chamber links
## from the Collector to the boss arena (boss_rush time).
static func limits(id: String, chambers: int = 0) -> Dictionary:
	var b := bet_info(id)
	var t := float(b.get("time", 0))
	if b.has("base_time"):
		t = float(b.get("base_time", 45)) + float(b.get("per_chamber", 20)) * maxi(0, chambers)
	return {"time": t, "count": int(b.get("count", 0)), "skills": int(b.get("max_skills", 0)), "life": int(b.get("life_pct", 0)), "hits": int(b.get("max_hits", 0))}

static func text(id: String, lim: Dictionary) -> String:
	var s := str(bet_info(id).get("text", id))
	s = s.replace("{time}", str(int(round(float(lim.get("time", 0))))))
	s = s.replace("{count}", str(int(lim.get("count", 0))))
	s = s.replace("{skills}", str(int(lim.get("skills", 0))))
	s = s.replace("{life}", str(int(lim.get("life", 0))))
	s = s.replace("{hits}", str(int(lim.get("hits", 0))))
	return s

static func mults() -> Array:
	var out := []
	for m in wcfg().get("mults", [1, 2, 3]):
		out.append(int(m))
	return out

## Gold staked at multiplier `mult` in a zone of this level.
static func stake(level: int, mult: int) -> int:
	return int(round(float(wcfg().get("stake_per_level", 20)) * maxi(1, level))) * maxi(1, mult)

## What a win pays: {gold, materials, flakes, dust, rare}. gold includes the stake returned.
static func payout(id: String, level: int, mult: int, rot: int = 0) -> Dictionary:
	var w := wcfg()
	var odds := float(bet_info(id).get("odds", 1.0))
	var st := stake(level, mult)
	return {"gold": int(round(st * (1.0 + odds) * (1.0 + float(w.get("rot_bonus", 0.1)) * maxi(0, rot)))),
		"materials": int(w.get("materials_per_mult", 2)) * mult,
		"flakes": int(w.get("flakes_per_mult", 8)) * mult,
		"dust": int(w.get("dust_per_mult", 2)) * mult,
		"rare": mult >= int(w.get("rare_at", 3))}

## Why the player cannot take this stake ("" = can).
static func stake_refusal(gold: int, level: int, mult: int) -> String:
	var need := stake(level, mult)
	if gold < need:
		return "Not enough gold (%d needed)" % need
	return ""

## Does the bet resolve when the zone boss dies (true) or on its own trigger (false)?
static func ends_at_boss(id: String) -> bool:
	return id in ["boss_rush", "few_skills", "abstinence", "iron_will"]

# ------------------------------------------------------------------ Pentimento Vaults
static func vault_count(ring: int, rot: int) -> int:
	var v := vcfg()
	var n := int(v.get("count", 1))
	if ring >= int(v.get("extra_ring", 3)) or rot >= int(v.get("extra_rot", 3)):
		n += 1
	return clampi(n, 0, int(v.get("max", 2)))

static func vault_types() -> Array:
	return vcfg().get("types", [])

static func type_info(id: String) -> Dictionary:
	for t in vault_types():
		if str(t.get("id", "")) == id:
			return t
	return {}

static func roll_type(rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for t in vault_types():
		total += float(t.get("w", 1))
	var roll := rng.randf() * total
	for t in vault_types():
		roll -= float(t.get("w", 1))
		if roll <= 0.0:
			return str(t["id"])
	return "treasure"

## A riddle's sigil order: a shuffled permutation of 0..n-1.
static func riddle_order(rng: RandomNumberGenerator, n: int = -1) -> Array:
	if n < 0:
		n = int(vcfg().get("riddle", {}).get("sigils", 3))
	var left := []
	for i in n:
		left.append(i)
	var out := []
	while not left.is_empty():
		out.append(left.pop_at(rng.randi_range(0, left.size() - 1)))
	return out

static func sigil_name(i: int) -> String:
	var names: Array = vcfg().get("riddle", {}).get("names", [])
	return str(names[i][0]) if i < names.size() else "Sigil %d" % (i + 1)

static func sigil_color(i: int) -> String:
	var names: Array = vcfg().get("riddle", {}).get("names", [])
	return str(names[i][1]) if i < names.size() else "#80c0ff"

static func shard_chance(rot: int) -> float:
	var v := vcfg()
	return clampf(float(v.get("shard_chance", 0.08)) + float(v.get("shard_rot_bonus", 0.02)) * maxi(0, rot), 0.0, 1.0)

## The cache of an opened vault: {rares, rarity, gems, materials, gold, legendary_chance}.
## A solved riddle adds riddle.bonus_rares.
static func cache(level: int, rot: int, kind: String) -> Dictionary:
	var c: Dictionary = vcfg().get("cache", {})
	var rares := int(c.get("rares", 2)) + int(c.get("rares_per_2_rot", 1)) * int(maxi(0, rot) / 2)
	if kind == "riddle":
		rares += int(vcfg().get("riddle", {}).get("bonus_rares", 1))
	return {"rares": rares, "rarity": float(c.get("rarity", 300)), "gems": int(c.get("gems", 1)),
		"materials": int(c.get("materials", 3)), "gold": int(c.get("gold_per_level", 15)) * maxi(1, level),
		"legendary_chance": float(c.get("legendary_chance", 0.08))}
