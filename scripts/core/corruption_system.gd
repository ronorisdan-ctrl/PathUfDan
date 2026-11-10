extends RefCounted
const Effects = preload("res://scripts/core/corruption_effects.gd")
## Dedicated implicit registry and pure planning. Never consumes normal affix slots.
## All draws accept an injected RNG; previews only call eligibility/description.

static func tags_for(it: Dictionary, cfg: Dictionary) -> Array:
	var base: Dictionary = Data.item_bases.get(it.get("base", ""), {})
	if base.is_empty() or not base.get("slot", "") in cfg.get("equipment_slots", []):
		return []
	var tags: Array = base.get("tags", []).duplicate()
	for tag in [base.get("slot", ""), base.get("category", "")]:
		if tag != "" and not tags.has(tag):
			tags.append(tag)
	var aliases: Dictionary = cfg.get("tag_aliases", {})
	var i := 0
	while i < tags.size():
		for tag in aliases.get(tags[i], []):
			if not tags.has(tag):
				tags.append(tag)
		i += 1
	return tags

static func pool_for(it: Dictionary, cfg: Dictionary) -> String:
	var tags := tags_for(it, cfg)
	if tags.is_empty():
		return ""
	if tags.has("weapon"):
		return "weapon"
	return "amulet" if tags.has("amulet") else "equipment"

static func enabled(family: Dictionary, cfg: Dictionary) -> bool:
	var feature: String = family.get("requires_feature", "")
	return feature == "" or (cfg.get("features", {}).get(feature, false) and feature in cfg.get("implemented_features", []))

static func eligible(it: Dictionary, side: String, cfg: Dictionary, registry: Array) -> Array:
	var tags := tags_for(it, cfg)
	var pool := pool_for(it, cfg)
	var out := []
	for f in registry:
		if f.get("side") != side or f.get("pool") != pool or not enabled(f, cfg):
			continue
		if int(it.get("ilvl", 1)) < int(f.get("min_item_level", 1)):
			continue
		for tag in f.get("eligible_any_tags", []):
			if tags.has(tag):
				out.append(f)
				break
	return out

static func compatible(a: Dictionary, b: Dictionary, cfg: Dictionary) -> bool:
	var pair := [a.get("group", a["id"]), b.get("group", b["id"])]
	for ex in cfg.get("pair_exceptions", []):
		if a["id"] in ex and b["id"] in ex:
			return true
	if pair[0] == pair[1]:
		return false
	for forbidden in cfg.get("forbidden_same_item_pairs", []):
		if pair[0] in forbidden and pair[1] in forbidden:
			return false
	return true

static func paired_prefixes(prefixes: Array, suffixes: Array, cfg: Dictionary) -> Array:
	var out := []
	for p in prefixes:
		for s in suffixes:
			if compatible(p, s, cfg):
				out.append(p)
				break
	return out

static func weighted_key(weights: Dictionary, random) -> String:
	var total := 0
	for k in weights:
		total += int(weights[k])
	if total <= 0:
		return ""
	var roll: int = random.randi_range(0, total - 1)
	for k in weights:
		roll -= int(weights[k])
		if roll < 0:
			return str(k)
	return ""

static func outcome_for_roll(roll: int, cfg: Dictionary) -> String:
	if roll < 0 or roll >= 10000:
		return ""
	for key in cfg.get("outcome_weights_basis_points", {}):
		roll -= int(cfg["outcome_weights_basis_points"][key])
		if roll < 0:
			return key
	return ""

static func draw_family(candidates: Array, cfg: Dictionary, random) -> Dictionary:
	var categories := {}
	for key in cfg["rarity_category_weights"]:
		for f in candidates:
			if f["rarity_class"] == key:
				categories[key] = cfg["rarity_category_weights"][key]
				break
	var category := weighted_key(categories, random)
	var weights := {}
	for f in candidates:
		if f["rarity_class"] == category:
			weights[f["id"]] = f["family_weight"]
	var id := weighted_key(weights, random)
	for f in candidates:
		if f["id"] == id:
			return f
	return {}

static func roll_affix(f: Dictionary, ilvl: int, cfg: Dictionary, random) -> Dictionary:
	if f.is_empty():
		return {}
	var tier = null
	var value: float = float(f.get("fixed_value", 0))
	if not f.get("fixed_tier", false):
		var weights := {}
		for band in f.get("tiers", []):
			if ilvl >= int(band["min_item_level"]):
				weights[str(int(band["tier"]))] = cfg["ordinary_tier_weights"][str(int(band["tier"]))]
		tier = int(weighted_key(weights, random))
		for band in f["tiers"]:
			if int(band["tier"]) == tier:
				value = random.randi_range(int(band["min"]), int(band["max"]))
	return {"id": f["id"], "tier": tier, "value": value, "effects": expand_effects(f, value)}

static func expand_effects(f: Dictionary, value: float) -> Array:
	var out := []
	for effect in f.get("effects", []):
		var m: Dictionary = effect.duplicate(true)
		m.erase("value_source")
		m["value"] = value
		out.append(m)
	return out

## Validates before the outcome draw, even for destruction/no-modifier.
static func plan(it: Dictionary, cfg: Dictionary, registry: Array, random) -> Dictionary:
	var prefixes := eligible(it, "prefix", cfg, registry)
	var suffixes := eligible(it, "suffix", cfg, registry)
	var paired := paired_prefixes(prefixes, suffixes, cfg)
	if prefixes.is_empty() or suffixes.is_empty() or paired.is_empty():
		return {"err": "Corruption pool unavailable for this item"}
	var outcome := outcome_for_roll(random.randi_range(0, 9999), cfg)
	var provisional := it.duplicate(true)
	provisional["corrupted_prefix"] = null
	provisional["corrupted_suffix"] = null
	if outcome == "single":
		var side := weighted_key(cfg["single_side_weights"], random)
		var family := draw_family(prefixes if side == "prefix" else suffixes, cfg, random)
		provisional["corrupted_" + side] = roll_affix(family, int(it.get("ilvl", 1)), cfg, random)
	elif outcome == "double":
		var p := draw_family(paired, cfg, random)
		var compatible_suffixes := []
		for s in suffixes:
			if compatible(p, s, cfg):
				compatible_suffixes.append(s)
		var s := draw_family(compatible_suffixes, cfg, random)
		provisional["corrupted_prefix"] = roll_affix(p, int(it.get("ilvl", 1)), cfg, random)
		provisional["corrupted_suffix"] = roll_affix(s, int(it.get("ilvl", 1)), cfg, random)
	provisional["corruption"] = int(cfg["max"])
	provisional["corruption_roll_version"] = int(cfg["roll_version"])
	return {"err": "", "outcome": outcome, "item": provisional}

static func registry_index(registry: Array) -> Dictionary:
	var out := {}
	for f in registry:
		out[f["id"]] = f
	return out

static func validate(cfg: Dictionary, registry: Array) -> Array:
	var shape_errors := validate_shapes(cfg,registry)
	if not shape_errors.is_empty():
		return shape_errors
	var errors := []
	for key in ["outcome_weights_basis_points", "single_side_weights", "rarity_category_weights", "ordinary_tier_weights", "tier_min_item_level", "fixed_rarity_min_item_level", "tag_aliases", "required_material", "features"]:
		if not cfg.get(key) is Dictionary or cfg[key].is_empty() and key != "features":
			errors.append("Missing/invalid corruption setting: " + key)
	if not errors.is_empty():
		return errors
	var total := 0
	for key in cfg["outcome_weights_basis_points"]:
		var w = cfg["outcome_weights_basis_points"][key]
		if not key in ["destroyed", "no_modifier", "single", "double"] or not numeric(w) or w <= 0 or int(w) != w:
			errors.append("Invalid outcome weight")
		else:
			total += int(w)
	if total != 10000 or cfg["outcome_weights_basis_points"].size() != 4:
		errors.append("Outcome weights must sum to 10000")
	for weights in [cfg["single_side_weights"], cfg["rarity_category_weights"], cfg["ordinary_tier_weights"]]:
		for w in weights.values():
			if not numeric(w) or w <= 0 or int(w) != w:
				errors.append("Invalid lottery weight")
	if not cfg["single_side_weights"].has("prefix") or not cfg["single_side_weights"].has("suffix") or cfg["single_side_weights"].size() != 2:
		errors.append("Invalid single-side weights")
	if cfg["ordinary_tier_weights"].size() != 3 or cfg["rarity_category_weights"].size() != 4:
		errors.append("Invalid tier/category count")
	if int(cfg.get("max", 0)) != 100 or int(cfg.get("roll_version", 0)) < 1 or int(cfg.get("corruption_gold_fee", -1)) < 0:
		errors.append("Invalid seal/version/fee")
	if cfg["corruption_gold_fee"] != int(cfg["corruption_gold_fee"]):
		errors.append("Gold fee must be an integer")
	if not numeric(cfg["required_material"].get("quantity")) or float(cfg["required_material"].get("quantity",0)) != int(cfg["required_material"].get("quantity",0)) or int(cfg["required_material"].get("quantity", 0)) <= 0 or not Data.materials.has(cfg["required_material"].get("id", "")):
		errors.append("Invalid corruption material")
	for tier in ["3", "2", "1"]:
		if not cfg["ordinary_tier_weights"].has(tier) or not cfg["tier_min_item_level"].has(tier):
			errors.append("Missing ordinary tier " + tier)
	var ids := {}
	for f in registry:
		if not f is Dictionary:
			errors.append("Invalid family record")
			continue
		var id: String = str(f.get("id", ""))
		if id == "" or ids.has(id):
			errors.append("Missing/duplicate family ID: " + id)
		ids[id] = true
		if not int(f["phase"]) in [2,3,4] or f["phase"] != int(f["phase"]) or f["family_weight"] != int(f["family_weight"]):
			errors.append("Invalid phase/family weight: " + id)
		if not f.get("pool") in ["weapon", "amulet", "equipment"] or not f.get("side") in ["prefix", "suffix"] or not cfg["rarity_category_weights"].has(f.get("rarity_class", "")):
			errors.append("Invalid pool/side/rarity: " + id)
		if not numeric(f.get("family_weight")) or float(f.get("family_weight", 0)) <= 0 or not f.get("eligible_any_tags") is Array or f.get("eligible_any_tags", []).is_empty():
			errors.append("Invalid family weight/tags: " + id)
		if not f.get("effects") is Array or f.get("effects", []).is_empty():
			errors.append("Missing effects: " + id)
			continue
		if int(f.get("phase", 0)) == 4 and f.get("requires_feature", "") == "":
			errors.append("P4 family requires feature gate: " + id)
		for m in f["effects"]:
			if not m is Dictionary:
				errors.append("Invalid effect: " + id)
			elif m.has("op"):
				if enabled(f, cfg) and not Effects.supports(str(m["op"])):
					errors.append("Unsupported operation enabled: " + id)
			elif not Data.stat_info.has(m.get("stat", "")) or not m.get("type") in ["flat", "inc"]:
				errors.append("Unknown stat/type: " + id)
		var fixed: bool = f.get("rarity_class") in ["signature", "mythic"]
		if fixed != bool(f.get("fixed_tier", false)):
			errors.append("Incorrect tier mode: " + id)
		if fixed:
			if not numeric(f.get("fixed_value")) or int(f.get("min_item_level", 0)) != int(cfg["fixed_rarity_min_item_level"].get(f.get("rarity_class"), -1)):
				errors.append("Invalid fixed family: " + id)
		else:
			var seen := []
			for band in f.get("tiers", []):
				var t := str(int(band.get("tier", 0)))
				if t in seen or not t in ["3", "2", "1"] or not numeric(band.get("min")) or not numeric(band.get("max")):
					errors.append("Invalid tier: " + id)
				elif band["min"] > band["max"] or int(band["min"]) != band["min"] or int(band["max"]) != band["max"] or int(band.get("min_item_level", 0)) != int(cfg["tier_min_item_level"].get(t, -1)):
					errors.append("Invalid tier range/level: " + id)
				seen.append(t)
			if seen.size() != 3 or int(f.get("min_item_level", 0)) != 1:
				errors.append("Ordinary family must have three tiers: " + id)
	if registry.is_empty():
		errors.append("Empty corruption registry")
	return errors

static func validate_shapes(cfg: Dictionary, registry: Array) -> Array:
	var errors := []
	for key in ["outcome_weights_basis_points","single_side_weights","rarity_category_weights","ordinary_tier_weights","tier_min_item_level","fixed_rarity_min_item_level","tag_aliases","required_material","features","brand_drops","effect_text"]:
		if not cfg.get(key) is Dictionary:
			errors.append("Expected setting dictionary: " + key)
	for key in ["equipment_slots","restricted_item_flags","implemented_features","forbidden_same_item_pairs","pair_exceptions"]:
		if not cfg.get(key) is Array:
			errors.append("Expected setting array: " + key)
	for key in ["max","roll_version","corruption_gold_fee","corrupted_projectile_bonus_character_cap","max_elemental_resistance_absolute_safety_cap"]:
		if not numeric(cfg.get(key)):
			errors.append("Expected numeric setting: " + key)
	if not errors.is_empty():
		return errors
	for tag in cfg["tag_aliases"]:
		if not cfg["tag_aliases"][tag] is Array:
			errors.append("Expected alias array: " + str(tag))
	for pairs in [cfg["forbidden_same_item_pairs"],cfg["pair_exceptions"]]:
		for pair in pairs:
			if not pair is Array or pair.size() != 2:
				errors.append("Invalid compatibility pair")
	for f in registry:
		if not f is Dictionary:
			errors.append("Expected family dictionary")
			continue
		for key in ["id","name","pool","side","rarity_class","group"]:
			if not f.get(key) is String or str(f.get(key,"")) == "":
				errors.append("Expected family string: " + key)
		for key in ["family_weight","min_item_level","phase"]:
			if not numeric(f.get(key)):
				errors.append("Expected numeric family field: " + key)
		if not f.get("eligible_any_tags") is Array or not f.get("effects") is Array or not f.get("fixed_tier") is bool:
			errors.append("Expected family tags/effects/tier mode")
		if f.has("tiers"):
			if not f["tiers"] is Array:
				errors.append("Expected tier array")
				continue
			for band in f["tiers"]:
				if not band is Dictionary:
					errors.append("Expected tier dictionary")
					continue
				for key in ["tier","min_item_level","min","max"]:
					if not numeric(band.get(key)):
						errors.append("Expected numeric tier field: " + key)
	return errors

static func numeric(value) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func coverage_errors(cfg: Dictionary, registry: Array) -> Array:
	var errors := []
	for base in Data.item_base_list:
		for level in [1, 27, 28, 29, 30, 39, 40, 42]:
			var it := {"base": base["id"], "ilvl": level}
			var p := eligible(it, "prefix", cfg, registry)
			var s := eligible(it, "suffix", cfg, registry)
			if p.is_empty() or s.is_empty() or paired_prefixes(p, s, cfg).is_empty():
				errors.append("Missing corruption pair: %s level %d" % [base["id"], level])
	return errors

## Unknown/malformed implicit records are quarantined without deleting the item.
## Stored effects are checked against the registry; arbitrary save-supplied stats never execute.
static func valid_record(record, side: String, it: Dictionary, cfg: Dictionary, index: Dictionary) -> bool:
	if not record is Dictionary or not index.has(record.get("id", "")) or not numeric(record.get("value")):
		return false
	var f: Dictionary = index[record["id"]]
	if f.get("side") != side or f.get("pool") != pool_for(it, cfg) or int(it.get("ilvl", 1)) < int(f["min_item_level"]):
		return false
	var tags := tags_for(it, cfg)
	var matches := false
	for tag in f["eligible_any_tags"]:
		matches = matches or tag in tags
	if not matches:
		return false
	if f.get("fixed_tier", false):
		return record.get("tier") == null and record["value"] == f["fixed_value"] and record.get("effects") == expand_effects(f, record["value"])
	if not numeric(record.get("tier")):
		return false
	for band in f["tiers"]:
		if record["tier"] == band["tier"] and int(it.get("ilvl", 1)) >= int(band["min_item_level"]):
			return record["value"] >= band["min"] and record["value"] <= band["max"] and int(record["value"]) == record["value"] and record.get("effects") == expand_effects(f, record["value"])
	return false

static func normalize_item(it: Dictionary, cfg: Dictionary, registry: Array) -> void:
	var index := registry_index(registry)
	it["corruption_roll_version"] = int(it.get("corruption_roll_version", 0))
	for side in ["prefix", "suffix"]:
		var key: String = "corrupted_" + side
		var record = it.get(key)
		if record != null and not valid_record(record, side, it, cfg, index):
			it["corruption_invalid_" + side] = record.duplicate(true) if record is Dictionary else record
			record = null
		it[key] = record
	var p = it["corrupted_prefix"]
	var s = it["corrupted_suffix"]
	if p != null and s != null and not compatible(index[p["id"]], index[s["id"]], cfg):
		it["corruption_invalid_suffix"] = s
		it["corrupted_suffix"] = null
	if p != null or s != null or it.has("corruption_invalid_prefix") or it.has("corruption_invalid_suffix"):
		it["corruption"] = int(cfg.get("max", 100))

static func item_mods(it: Dictionary, cfg: Dictionary, registry: Array) -> Array:
	var out := []
	var index := registry_index(registry)
	for side in ["prefix", "suffix"]:
		var record = it.get("corrupted_" + side)
		if not valid_record(record, side, it, cfg, index):
			continue
		var f: Dictionary = index[record["id"]]
		if not enabled(f, cfg):
			continue
		for effect in expand_effects(f, record["value"]):
			var m: Dictionary = effect.duplicate(true)
			m["source"] = "Corruption: %s #%d / %s" % [it.get("name", it.get("base", "Item")), int(it.get("uid", 0)), f["name"]]
			out.append(m)
	return out

static func brand_chance(tier: int, depth: int, endless: bool, boss: bool, elite: bool, cfg: Dictionary) -> float:
	var drops: Dictionary = cfg.get("brand_drops", {})
	if boss:
		var chance: float = float(drops.get("boss_by_tier", {}).get(str(tier), 0.0))
		if endless and chance > 0:
			chance = minf(float(drops.get("endless_boss_cap", chance)), chance + maxi(0, depth - 1) * float(drops.get("endless_per_depth", 0)))
		return chance
	return float(drops.get("elite_chance", 0)) if elite and tier >= int(drops.get("elite_min_tier", 5)) else 0.0
