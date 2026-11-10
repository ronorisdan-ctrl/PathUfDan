extends RefCounted
## Endgame Phase 2B (pure rules; reads only Data.atlas_cfg unless a cfg is passed).
##  - Fixative: a Blacksmith craft paid with Glaze Flakes that lowers an item's crafting
##    corruption. Item field "fixative" (int uses, key absent at 0).
##  - Rot-touched implicits: Atlas drops at Rot 4+ may gain one extra implicit with a bonus
##    and a drawback. Item field "rot_implicit" {id, tier, mods}; key absent when none.

const CorruptionRules = preload("res://scripts/core/corruption_rules.gd")

static func _a(c) -> Dictionary:
	return c if c != null else Data.atlas_cfg

# ------------------------------------------------------------------ Fixative
static func fix_cfg(c = null) -> Dictionary:
	return _a(c).get("fixative", {})

static func fix_reduce(c = null) -> int:
	return maxi(1, int(fix_cfg(c).get("reduce", 25)))

static func fix_max_uses(c = null) -> int:
	return maxi(0, int(fix_cfg(c).get("max_uses", 2)))

static func fix_uses(it) -> int:
	if it == null or typeof(it) != TYPE_DICTIONARY:
		return 0
	var v = it.get("fixative", 0)
	return maxi(0, int(v)) if (v is int or v is float) else 0

static func fix_uses_left(it, c = null) -> int:
	return maxi(0, fix_max_uses(c) - fix_uses(it))

## True for an item that went through the Abyssal Brand "Corrupt Item" action.
static func brand_corrupted(it) -> bool:
	if it == null or typeof(it) != TYPE_DICTIONARY:
		return false
	return int(it.get("corruption_roll_version", 0)) > 0 or it.get("corrupted_prefix") != null or it.get("corrupted_suffix") != null \
		or it.has("corruption_invalid_prefix") or it.has("corruption_invalid_suffix")

static func fix_cost(it: Dictionary, c = null) -> Dictionary:
	var f := fix_cfg(c)
	var lv := int(it.get("ilvl", 1))
	return {"gold": int(f.get("gold_base", 20)) + int(f.get("gold_per_ilvl", 3)) * lv, "glaze_flake": int(f.get("flakes", 60))}

## "" = allowed. Called after the generic seal check (100% refuses every craft first).
static func fix_refusal(it: Dictionary, c = null, ccfg = null) -> String:
	if brand_corrupted(it) or CorruptionRules.is_maxed(it, ccfg):
		return "Fixative cannot restore a fully corrupted item"
	if CorruptionRules.get_level(it, ccfg) <= 0:
		return "This item has no crafting corruption to fix"
	if fix_uses_left(it, c) <= 0:
		return "Fixative already applied %d times (the most this item can take)" % fix_max_uses(c)
	return ""

## Applies one Fixative. Returns {before, after} or {} when refused.
static func apply_fix(it: Dictionary, c = null, ccfg = null) -> Dictionary:
	if fix_refusal(it, c, ccfg) != "":
		return {}
	var before := CorruptionRules.get_level(it, ccfg)
	CorruptionRules.set_level(it, before - fix_reduce(c), ccfg)
	it["fixative"] = fix_uses(it) + 1
	return {"before": before, "after": CorruptionRules.get_level(it, ccfg)}

static func fix_preview(it: Dictionary, c = null, ccfg = null) -> String:
	var lv := CorruptionRules.get_level(it, ccfg)
	return "Corruption %d%% -> %d%%. Fixative uses left on this item: %d -> %d (max %d)." % [lv, maxi(0, lv - fix_reduce(c)), fix_uses_left(it, c), maxi(0, fix_uses_left(it, c) - 1), fix_max_uses(c)]

static func fix_tooltip(it) -> String:
	var n := fix_uses(it)
	if n <= 0:
		return ""
	return "[color=#e0c890]Fixative applied: %d of %d[/color]" % [n, fix_max_uses()]

# ------------------------------------------------------------------ Rot-touched implicits
static func rot_cfg(c = null) -> Dictionary:
	return _a(c).get("rot_touched", {})

static func pool(c = null) -> Array:
	return rot_cfg(c).get("pool", [])

static func entry(id: String, c = null) -> Dictionary:
	for e in pool(c):
		if str(e.get("id", "")) == id:
			return e
	return {}

## Chance that one item drop is Rot-touched at this Rot level (highest listed level at or below it).
static func chance(rot: int, c = null) -> float:
	return float(_by_rot(rot_cfg(c).get("chance", {}), rot, 0.0))

static func tier_for(rot: int, c = null) -> int:
	return int(_by_rot(rot_cfg(c).get("tier", {}), rot, 0))

static func _by_rot(table: Dictionary, rot: int, dflt):
	var best := -1
	var out = dflt
	for k in table:
		var lv := int(k)
		if lv <= rot and lv > best:
			best = lv
			out = table[k]
	return out

## Builds the stored record for entry e at tier t, bonus rolled with rng.
static func make_record(e: Dictionary, t: int, rng: RandomNumberGenerator) -> Dictionary:
	var tiers: Array = e.get("tiers", [])
	if tiers.is_empty():
		return {}
	var ti := clampi(t, 1, tiers.size())
	var row: Array = tiers[ti - 1]
	var b: Dictionary = e.get("bonus", {})
	var d: Dictionary = e.get("drawback", {})
	var bv := rng.randi_range(int(row[0]), int(row[1]))
	return {"id": str(e["id"]), "tier": ti, "mods": [
		{"stat": str(b.get("stat", "")), "type": str(b.get("type", "flat")), "value": bv},
		{"stat": str(d.get("stat", "")), "type": str(d.get("type", "flat")), "value": int(row[2])}]}

## One roll for an item drop in a Rot zone. Mutates the item and returns true when touched.
## Uses only the given rng (never the global, Loot or combat streams). Items that already
## carry one are left alone; nothing is rolled below the lowest listed Rot level.
static func roll(it: Dictionary, rot: int, rng: RandomNumberGenerator, c = null) -> bool:
	if it.is_empty() or it.has("rot_implicit"):
		return false
	var ch := chance(rot, c)
	if ch <= 0.0:
		return false
	if rng.randf() >= ch:
		return false
	var p := pool(c)
	var total := 0.0
	for e in p:
		total += maxf(0.0, float(e.get("weight", 1)))
	if total <= 0.0:
		return false
	var x := rng.randf() * total
	var pick: Dictionary = p[p.size() - 1]
	for e in p:
		x -= maxf(0.0, float(e.get("weight", 1)))
		if x < 0.0:
			pick = e
			break
	var rec := make_record(pick, tier_for(rot, c), rng)
	if rec.is_empty():
		return false
	it["rot_implicit"] = rec
	return true

## Stat modifiers of the item's Rot-touched implicit ([] when none or unknown).
static func mods(it, c = null) -> Array:
	if it == null or typeof(it) != TYPE_DICTIONARY:
		return []
	var r = it.get("rot_implicit")
	if typeof(r) != TYPE_DICTIONARY or entry(str(r.get("id", "")), c).is_empty():
		return []
	var out := []
	for m in r.get("mods", []):
		if typeof(m) == TYPE_DICTIONARY and Data.stat_info.has(str(m.get("stat", ""))):
			out.append({"stat": str(m["stat"]), "type": str(m.get("type", "flat")), "value": float(m.get("value", 0))})
	return out

## Load-time cleanup: ints back to ints; a malformed record is dropped, an unknown id is kept (inactive).
static func normalize(it: Dictionary) -> void:
	if it.has("fixative"):
		var n := fix_uses(it)
		if n <= 0:
			it.erase("fixative")
		else:
			it["fixative"] = n
	if not it.has("rot_implicit"):
		return
	var r = it["rot_implicit"]
	if typeof(r) != TYPE_DICTIONARY or typeof(r.get("mods")) != TYPE_ARRAY:
		it.erase("rot_implicit")
		return
	r["tier"] = int(r.get("tier", 1))
	for m in r["mods"]:
		if typeof(m) == TYPE_DICTIONARY and m.has("value"):
			m["value"] = int(m["value"]) if absf(float(m["value"]) - round(float(m["value"]))) < 0.001 else float(m["value"])

static func name_of(it) -> String:
	if it == null or typeof(it) != TYPE_DICTIONARY or typeof(it.get("rot_implicit")) != TYPE_DICTIONARY:
		return ""
	return str(entry(str(it["rot_implicit"].get("id", ""))).get("name", ""))
