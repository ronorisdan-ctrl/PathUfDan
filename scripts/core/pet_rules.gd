extends RefCounted
## Pure pet rules (no scene access): per-tier capabilities, signature tweaks,
## upgrade costs and what a pet may fetch. Numbers live in data/pets.json.

const MAX_TIER := 5

static func cfg() -> Dictionary:
	return Data.pets_cfg

static func setting(key: String, default_value = 0):
	return Data.pets_cfg.get("settings", {}).get(key, default_value)

static func tier_def(tier: int) -> Dictionary:
	var tl: Array = Data.pets_cfg.get("tiers", [])
	if tl.is_empty():
		return {}
	return tl[clampi(tier, 0, tl.size() - 1)]

static func max_tier() -> int:
	return mini(MAX_TIER, Data.pets_cfg.get("tiers", []).size() - 1)

## Resolved capabilities of one pet at one tier, signature tweaks included.
static func stats(pet_id: String, tier: int) -> Dictionary:
	var td := tier_def(tier)
	var sig: Dictionary = Data.pets.get(pet_id, {}).get("signature", {})
	var s := {
		"tier": tier,
		"fetch_rarity": int(td.get("fetch_rarity", -1)),
		"speed": float(td.get("speed", 90)) * float(sig.get("speed_mult", 1.0)),
		"auto_cd": float(td.get("auto_cd", 0.4)),
		"auto_radius": float(td.get("auto_radius", 150)),
		"fetch_cd": float(td.get("fetch_cd", 2.5)),
		"fetch_range": float(td.get("fetch_range", 200)),
		"blink": bool(td.get("blink", false)),
		"wall_pass": bool(td.get("wall_pass", false)),
		"magnet_radius": float(td.get("magnet_radius", 0)),
		"magnet_speed": float(td.get("magnet_speed", 0)),
	}
	# -1 means "the whole camera rectangle"
	if s["auto_radius"] >= 0:
		s["auto_radius"] += float(sig.get("auto_radius_bonus", 0))
	if s["fetch_range"] >= 0:
		s["fetch_range"] += float(sig.get("range_bonus", 0))
	if sig.has("wall_pass_tier") and tier >= int(sig["wall_pass_tier"]):
		s["wall_pass"] = true
	if sig.has("blink_tier") and tier >= int(sig["blink_tier"]):
		s["blink"] = true
	if s["magnet_radius"] > 0:
		s["magnet_radius"] += float(sig.get("magnet_bonus", 0))
	return s

## Materials needed to go from `tier` to `tier + 1` (empty at max tier).
static func upgrade_cost(pet_id: String, tier: int) -> Dictionary:
	if tier >= max_tier() or not Data.pets.has(pet_id):
		return {}
	var td := tier_def(tier + 1)
	var units := float(td.get("cost_units", 0)) * float(Data.pets_cfg.get("material_unit", 100)) \
		* float(Data.pets[pet_id].get("upgrade_cost_mult", 1.0))
	var mix: Dictionary = td.get("cost_mix", {})
	var out := {}
	for k in mix:
		var n := int(round(units * float(mix[k])))
		if n > 0:
			out[k] = n
	return out

## Total materials to take a pet from tier 0 to max.
static func total_cost(pet_id: String) -> int:
	var t := 0
	for tier in max_tier():
		for k in upgrade_cost(pet_id, tier):
			t += int(upgrade_cost(pet_id, tier)[k])
	return t

## The minimum pet tier that may fetch a drop of this kind / rarity.
static func required_tier(kind: String, rarity: String = "common") -> int:
	match kind:
		"gold", "material":
			return 0
		"gem", "rune":
			return int(setting("gem_rune_min_tier", 1))
		_:
			# fetch_rarity of tier t is the highest rarity index it can carry
			var r := Data.rarity_index(rarity)
			for td in Data.pets_cfg.get("tiers", []):
				if int(td.get("fetch_rarity", -1)) >= r:
					return int(td.get("tier", 0))
			return MAX_TIER + 1

static func clean_name(nm: String, fallback: String) -> String:
	var s := nm.strip_edges().replace("[", "(").replace("]", ")")
	s = s.substr(0, int(setting("name_max_length", 16)))
	return s if s != "" else fallback
