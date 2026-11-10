extends RefCounted
## Phase B gear profiles for the entry kit (docs/BOT_GEAR_PROFILES.md).
##
##   legacy  : unchanged sb_kit.gd behaviour (best of 3 natural drops per slot). Default.
##   typical : what a player has after the runs it takes to level to this point:
##             every item that dropped in the last WINDOW_LEVELS levels of play (rolled
##             with the game's own drop code at the right monster level, rarity bonus and
##             elite / boss bonuses), the best one per slot equipped, the rest salvaged,
##             then crafted with the materials and gold those runs gave, following the
##             crafting-corruption meter like a player (sealed at 100%).
##   geared  : the same player after FARM["geared"] times as many runs. In the Atlas it
##             also gets Rot-touched drops (ring 2+) and the Fixative craft.
##
## Never used: the Abyssal Brand "Corrupt Item" action.
## The run counts are maths over game data (XP curve, enemy XP, drop chances) plus one
## measured input per tier: mean kills per run (KILLS, from the frozen smartbot baselines).

const CorruptionRules = preload("res://scripts/core/corruption_rules.gd")
const AtlasCraft = preload("res://scripts/core/atlas_craft_rules.gd")

const PROFILES := ["legacy", "typical", "geared"]
const FARM := {"typical": 1.0, "geared": 3.0}
## Mean kills per dungeon run. T3 and T6: measured (tree_v4_bot2e + caster_v1 baselines,
## all classes). T1/T2/T4/T5: scaled from T3/T6 by packs_per_room x pack_size.
const KILLS := {1: 84.0, 2: 95.0, 3: 98.0, 4: 126.0, 5: 150.0, 6: 148.0}
const WINDOW_LEVELS := 6     # drops from the last 6 levels of play are the candidate pool
const GEM_LEVELS := 10       # gems from the last 10 levels are still in the pouch
const SLOTS := ["main_hand", "off_hand", "chest", "helmet", "gloves", "boots", "belt", "amulet", "ring1", "ring2", "charm"]
const CRAFT_PRIORITY := {"main_hand": 1.0, "off_hand": 0.8, "chest": 0.8, "amulet": 0.8, "gloves": 0.7, "helmet": 0.7, "boots": 0.7, "ring1": 0.7, "ring2": 0.7, "belt": 0.6, "charm": 0.5}
## how precious a material is when ranking crafts (about 1 / drop weight)
const MAT_COST := {"gold": 0.0004, "scrap": 0.5, "iron_fragment": 1.0, "arcane_dust": 2.0, "monster_core": 3.5, "elemental_essence": 4.5, "catalyst": 9.0, "glaze_flake": 0.05}

var hub = null
var rng := RandomNumberGenerator.new()
var last := {}               # report of the last make() (for dumps and the stage table)

# ================================================================== economy
func _dungeon(tier: int) -> Dictionary:
	for d in Data.dungeon_list:
		if int(d.get("tier", 1)) == tier:
			return d
	return Data.dungeon_list[0]

func _ring(r: int) -> Dictionary:
	for x in Data.atlas_cfg.get("rings", []):
		if int(x.get("ring", 0)) == r:
			return x
	return {}

## Highest tier a player is running at character level l (capped at max_tier).
func tier_for_level(l: int, max_tier: int) -> int:
	var t := 1
	for d in Data.dungeon_list:
		var dt := int(d.get("tier", 1))
		if dt <= max_tier and int(d.get("min_level", 1)) <= l:
			t = maxi(t, dt)
	return t

## Expected yield of one run at character level l. ring > 0: an Atlas zone of that ring.
func segment(l: int, tier: int, ring: int) -> Dictionary:
	var d := _dungeon(6 if ring > 0 else tier)
	var ml: int
	var rb: float
	var ec: float
	var t: int = 6 if ring > 0 else tier
	if ring > 0:
		var rd := _ring(ring)
		ml = int(rd.get("level", 40))
		rb = float(rd.get("rarity_bonus", 170))
		ec = float(rd.get("elite_chance", 0.4))
	else:
		ml = clampi(maxi(l, int(d.get("min_level", 1))), int(d.get("min_level", 1)), int(d.get("max_level", 10)))
		rb = float(d.get("rarity_bonus", 0))
		ec = float(d.get("elite_chance", 0.2))
	var ps: Array = d.get("pack_size", [3, 5])
	var pack := (float(ps[0]) + float(ps[1])) * 0.5
	var kills: float = KILLS.get(t, 100.0)
	var elites := kills / pack * ec
	var normals := kills - elites
	var wsum := 0.0
	var xsum := 0.0
	for e in d.get("pool", []):
		var w := float(e.get("w", 1))
		wsum += w
		xsum += w * float(Data.enemies.get(str(e.get("id", "")), {}).get("xp", 10))
	var avg_xp := xsum / maxf(1.0, wsum)
	var L: Dictionary = Data.loot
	var ic := float(L.get("item_drop_chance", 0.16))
	var mc := float(L.get("material_drop_chance", 0.12))
	var gc := float(L.get("gold_drop_chance", 0.4))
	return {
		"tier": t, "ring": ring, "ml": ml, "rb": rb, "normals": normals, "elites": elites,
		"xp": kills * avg_xp * (1.0 + 0.18 * (ml - 1)) + 60.0 * ml * t,
		"items_normal": normals * ic, "items_elite": elites * float(L.get("elite_item_rolls", 2)) * ic, "items_boss": float(L.get("boss_item_rolls", 4)),
		"mats": normals * mc + elites * 3.0 * mc + 6.0,
		"gold": (normals * gc + elites) * ml * 3.5 + ml * 3.5 * 5.0,
		"gems": normals * 0.03 + elites * 0.18 + 1.0,
		"runes": normals * 0.02 + elites * 0.12 + 1.5,
	}

func _xp_for_level(l: int) -> float:
	return float(int(round(60.0 * pow(l, 1.55) + 40.0 * l)))

## Run counts for a stage: total runs to reach lvl, and the per-level runs of the last
## WINDOW_LEVELS levels (scaled by the farm factor).
func plan(profile: String, tier: int, lvl: int, ring: int) -> Dictionary:
	var farm: float = FARM.get(profile, 1.0)
	var total := 0.0
	var window := []
	var gem_runs := []
	for l in range(1, maxi(2, lvl)):
		var r := 0
		var t := tier_for_level(l, tier)
		if ring > 0 and l >= lvl - WINDOW_LEVELS:
			r = ring
		var seg := segment(l, t, r)
		var runs := _xp_for_level(l) / maxf(1.0, seg["xp"])
		total += runs
		if l >= lvl - WINDOW_LEVELS:
			window.append({"seg": seg, "runs": runs * farm})
		if l >= lvl - GEM_LEVELS:
			gem_runs.append({"seg": seg, "runs": runs * farm})
	var wr := 0.0
	for w in window:
		wr += w["runs"]
	return {"farm": farm, "runs_total": total, "runs_window": wr, "window": window, "gem_window": gem_runs}

## Expected totals over the window (items by source, materials, gold, gems, runes).
func totals(p: Dictionary) -> Dictionary:
	var o := {"items_normal": 0.0, "items_elite": 0.0, "items_boss": 0.0, "mats": 0.0, "gold": 0.0, "gems": 0.0}
	for w in p["window"]:
		for k in ["items_normal", "items_elite", "items_boss", "mats", "gold"]:
			o[k] += float(w["seg"][k]) * float(w["runs"])
	for w in p["gem_window"]:
		o["gems"] += float(w["seg"]["gems"]) * float(w["runs"])
	o["runes"] = 0.0
	return o

func _count(x: float) -> int:
	## an expected count as an integer: floor + one Bernoulli for the fraction
	var n := int(floor(x))
	if rng.randf() < x - n:
		n += 1
	return n

# ================================================================== drops
## Every item the player saw in the window, rolled with Loot.roll_item.
func roll_window(ch, p: Dictionary, profile: String) -> Array:
	var L: Dictionary = Data.loot
	var out := []
	for w in p["window"]:
		var seg: Dictionary = w["seg"]
		var runs: float = w["runs"]
		var ml: int = seg["ml"]
		var rb: float = seg["rb"] + float(ch.final.get("item_rarity", 0.0))
		var rot := 0
		if profile == "geared" and int(seg["ring"]) >= 2:
			rot = 4 if int(seg["ring"]) == 2 else 5
		var srcs := [
			[_count(seg["items_normal"] * runs), rb, ""],
			[_count(seg["items_elite"] * runs), rb + float(L.get("elite_rarity_bonus", 150)), ""],
		]
		var bosses := _count(runs)
		for b in bosses:
			for i in int(L.get("boss_item_rolls", 4)):
				var forced := ""
				if i == 0:
					forced = "rare" if Loot.rng.randf() < 0.8 else "epic"
				out.append(_drop(ch, ml, rb + float(L.get("boss_rarity_bonus", 400)), forced, rot))
		for s in srcs:
			for i in int(s[0]):
				out.append(_drop(ch, ml, s[1], s[2], rot))
	return out.filter(func(x): return not x.is_empty())

func _drop(ch, ml: int, bonus: float, forced: String, rot: int) -> Dictionary:
	var it: Dictionary = Loot.roll_item(ml, bonus, ch.class_id, forced)
	if it.is_empty():
		return it
	if rot > 0:
		AtlasCraft.roll(it, rot, rng)
	it["uid"] = ch.take_uid()
	return it

# ================================================================== selection
func _slot_of(it: Dictionary) -> Array:
	var s: String = it.get("slot", "")
	return ["ring1", "ring2"] if s == "ring" else [s]

func equip_best_of(ch, items: Array) -> int:
	var usable := items.filter(func(x): return ch.equip_restriction(x) == "")
	var by_slot := {}
	for it in usable:
		for s in _slot_of(it):
			if not by_slot.has(s):
				by_slot[s] = []
			by_slot[s].append(it)
	var used := {}
	var n := 0
	for pass_i in 2:
		for slot in SLOTS:
			if slot == "off_hand":
				var mh = ch.equipment.get("main_hand")
				if mh != null and mh.get("two_handed", false) and not mh.get("tags", []).has("bow"):
					continue
			var cur = ch.equipment.get(slot)
			var best = null
			var best_s: float = hub.score(ch) + hub.item_extra(cur)
			for it in by_slot.get(slot, []):
				if used.has(it["uid"]) and (cur == null or cur["uid"] != it["uid"]):
					continue
				var eq: Dictionary = hub._eq_with(ch, it, slot)
				var s: float = hub.score(ch, eq) + hub.item_extra(it)
				if s > best_s + 0.0005:
					best_s = s
					best = it
			if best != null:
				if cur != null:
					used.erase(cur["uid"])
				var eq2: Dictionary = hub._eq_with(ch, best, slot)
				for s2 in eq2:
					ch.equipment[s2] = eq2[s2]
				used[best["uid"]] = true
				ch.recalc()
				n += 1
	return n

## Leftover drops: commons sold, the rest salvaged (what a player does with them).
func dispose(ch, items: Array) -> Dictionary:
	var eq_uids := {}
	for s in ch.equipment:
		if ch.equipment[s] != null:
			eq_uids[ch.equipment[s].get("uid", -1)] = true
	var sold := 0
	var salv := 0
	for it in items:
		if eq_uids.has(it.get("uid", -2)):
			continue
		if Data.rarity_index(it.get("rarity", "common")) == 0:
			ch.gold += Loot.sell_value(it)
			sold += 1
		else:
			var y: Dictionary = Loot.salvage_yield(it)
			for k in y:
				ch.add_material(k, int(y[k]))
			salv += 1
	return {"sold": sold, "salvaged": salv}

# ================================================================== crafting (meter-aware)
func _mat_value(cost: Dictionary) -> float:
	var v := 0.0
	for k in cost:
		v += float(cost[k]) * float(MAT_COST.get(k, 1.0))
	return maxf(0.05, v)

func _worst_affix(ch, it: Dictionary) -> Array:
	var affs: Array = it.get("affixes", [])
	var full: float = hub.score(ch)
	var worst := -1
	var worst_loss := INF
	for ai in affs.size():
		var a = affs[ai]
		affs.remove_at(ai)
		ch.recalc()
		var loss: float = full - hub.score(ch)
		affs.insert(ai, a)
		if loss < worst_loss:
			worst_loss = loss
			worst = ai
	ch.recalc()
	return [worst, worst_loss]

## Expected score gain of a craft, from `samples` trial rolls on a copy (the player does not
## see the result before paying: the real craft is rolled afresh).
func _expected_gain(ch, slot: String, op: String, ai: int, samples: int) -> float:
	var it: Dictionary = ch.equipment[slot]
	var base: float = hub.score(ch)
	var tot := 0.0
	for k in samples:
		var cp: Dictionary = it.duplicate(true)
		if op == "swap":
			cp["affixes"].remove_at(ai)
			Loot.add_random_affix(cp, 0)
		else:
			Loot.craft_apply(op, cp, ai)
		var eq: Dictionary = ch.equipment.duplicate()
		eq[slot] = cp
		tot += hub.score(ch, eq) - base
	return tot / samples

func _ops_for(ch, slot: String) -> Array:
	var it = ch.equipment.get(slot)
	if it == null or CorruptionRules.is_maxed(it) or AtlasCraft.brand_corrupted(it):
		return []
	var ops := []
	if Loot.craft_check("upgrade", it) == "":
		ops.append(["upgrade", -1])
	if it.get("rarity", "") == "legendary":
		return ops
	if Loot.craft_check("rarity", it) == "":
		ops.append(["rarity", -1])
	if Loot.craft_check("add", it) == "":
		ops.append(["add", -1])
	elif not it.get("affixes", []).is_empty():
		var w := _worst_affix(ch, it)
		if w[0] >= 0:
			ops.append(["reroll", w[0]])
			ops.append(["swap", w[0]])
	return ops

func _cost_of(op: String, it: Dictionary) -> Dictionary:
	if op == "swap":
		var c: Dictionary = Loot.craft_cost("remove", it).duplicate()
		for k in Loot.craft_cost("add", it):
			c[k] = int(c.get(k, 0)) + int(Loot.craft_cost("add", it)[k])
		return c
	return Loot.craft_cost(op, it)

## Crafts the equipped gear with what the character owns. Upgrades first (no meter),
## then rolling crafts (add / reroll / raise rarity, and remove+add) ranked by expected
## score gain per material value, until nothing pays or every item is sealed.
func craft_gear(ch, gold_share: float, fixatives: int) -> Dictionary:
	var log := {"upgrade": 0, "rarity": 0, "add": 0, "reroll": 0, "swap": 0, "fixative": 0, "sealed": 0}
	var gold_budget := int(ch.gold * gold_share)
	var gold0: int = ch.gold
	# 1. upgrades (exempt from the meter), most valuable slots first
	for slot in SLOTS:
		var it = ch.equipment.get(slot)
		if it == null:
			continue
		while Loot.craft_check("upgrade", it) == "":
			var c: Dictionary = Loot.craft_cost("upgrade", it)
			if gold0 - ch.gold + int(c.get("gold", 0)) > gold_budget or not ch.pay(c):
				break
			Loot.craft_apply("upgrade", it)
			log["upgrade"] += 1
		ch.recalc()
	# 2. rolling crafts, greedy on expected gain per material value
	var cache := {}
	var fix_left := fixatives
	for step in 120:
		var best := []
		var best_v := 0.0015
		for slot in SLOTS:
			var it = ch.equipment.get(slot)
			if it == null:
				continue
			if not cache.has(slot):
				var rows := []
				for o in _ops_for(ch, slot):
					if o[0] == "upgrade":
						continue
					var g := _expected_gain(ch, slot, o[0], o[1], 2)
					rows.append([o[0], o[1], g])
				cache[slot] = rows
			for r in cache[slot]:
				var c := _cost_of(r[0], it)
				if not ch.has_materials(c) or gold0 - ch.gold + int(c.get("gold", 0)) > gold_budget:
					continue
				var v: float = r[2] * float(CRAFT_PRIORITY.get(slot, 0.6)) / _mat_value(c)
				if v > best_v:
					best_v = v
					best = [slot, r[0], r[1]]
		if best.is_empty():
			break
		var slot: String = best[0]
		var it2: Dictionary = ch.equipment[slot]
		var op: String = best[1]
		# a player with Fixative lowers the meter while one more hit would seal the item
		if fix_left > 0 and CorruptionRules.events_remaining(it2) <= 1 and Loot.craft_check("fixative", it2) == "":
			var fc: Dictionary = Loot.craft_cost("fixative", it2)
			if ch.pay(fc):
				Loot.craft_apply("fixative", it2)
				fix_left -= 1
				log["fixative"] += 1
		if op == "swap":
			ch.pay(Loot.craft_cost("remove", it2))
			Loot.craft_apply("remove", it2, best[2])
			ch.pay(Loot.craft_cost("add", it2))
			Loot.add_random_affix(it2, 0)
			CorruptionRules.roll(it2, "add", rng)
		else:
			ch.pay(Loot.craft_cost(op, it2))
			Loot.craft_apply(op, it2, best[2])
			CorruptionRules.roll(it2, op, rng)
		log[op] += 1
		if CorruptionRules.is_maxed(it2):
			log["sealed"] += 1
		ch.recalc()
		cache.erase(slot)
	return log

# ================================================================== the kit
## Replaces sb_kit's gear, gems, runes and currencies for a typical / geared character.
## Call after the class, level and points are set and the first hotbar is chosen.
func make(ch, profile: String, tier: int, ring: int) -> Dictionary:
	var p := plan(profile, tier, ch.level, ring)
	var tt := totals(p)
	# the starting gear stays equipped until a drop beats it
	var drops := roll_window(ch, p, profile)
	var n_eq := equip_best_of(ch, drops)
	# currencies: gold and materials the window earned (half the gold already spent elsewhere)
	ch.gold = int(tt["gold"] * 0.5)
	ch.materials = {}
	var mats: Dictionary = Data.materials
	var wsum := 0.0
	for k in mats:
		wsum += maxf(0.0, float(mats[k].get("weight", 0)))
	for k in mats:
		var w := float(mats[k].get("weight", 0))
		if w > 0:
			ch.materials[k] = _count(tt["mats"] * w / wsum)
	var disp := dispose(ch, drops)
	var fix := 0
	if profile == "geared" and ring > 0:
		fix = 8                                  # Restorers' Guild rank 3: up to 2 uses on 4 items
		ch.add_material("glaze_flake", fix * int(AtlasCraft.fix_cfg().get("flakes", 60)))
	var gold_before_craft: int = ch.gold
	var cl := craft_gear(ch, 0.7, fix)
	# gems from the last GEM_LEVELS levels, runes from the whole game (capped)
	for i in _count(tt["gems"]):
		ch.add_gem(Loot.random_gem(int(p["gem_window"][rng.randi() % p["gem_window"].size()]["seg"]["ml"]) if not p["gem_window"].is_empty() else ch.level))
	var rn := mini(36, int(p["runs_total"] * 2.5))
	for i in rn:
		ch.add_rune(Loot.random_rune())
	ch.recalc()
	var rc := {}
	for s in ch.equipment:
		var it = ch.equipment[s]
		if it != null:
			rc[it.get("rarity", "")] = int(rc.get(it.get("rarity", ""), 0)) + 1
	last = {"profile": profile, "runs_total": snapped(p["runs_total"], 0.1), "runs_window": snapped(p["runs_window"], 0.1),
		"drops": drops.size(), "equipped_from_drops": n_eq, "disposed": disp, "craft": cl,
		"gold_after_window": gold_before_craft, "gold_left": ch.gold, "materials_left": ch.materials.duplicate(),
		"gems": int(tt["gems"]), "runes": rn, "rarity": rc}
	return last
