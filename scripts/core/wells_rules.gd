extends RefCounted
## Endgame Phase 3C: Pigment Wells (docs/ENDGAME_PHASE3.md Stage 3C, data/atlas.json mechanics.wells).
## Pure rules: well count and colours, fill per kill / second, the danger a well lends nearby
## monsters, and the mix (which reward chest the fills buy). The dungeon (scripts/world/zone_wells.gd)
## owns the live state and passes its mech_rng stream in.

const AtlasRules = preload("res://scripts/core/atlas_rules.gd")

static func cfg() -> Dictionary:
	return AtlasRules.mech_cfg().get("wells", {})

static func colour_ids(t: Dictionary = {}) -> Array:
	if t.is_empty():
		t = cfg()
	var out := []
	for c in t.get("colours", []):
		out.append(str(c.get("id", "")))
	return out

## {id, name, color, ...} of a colour (umber included).
static func colour_info(id: String, t: Dictionary = {}) -> Dictionary:
	if t.is_empty():
		t = cfg()
	for c in t.get("colours", []):
		if str(c.get("id", "")) == id:
			return c
	var u: Dictionary = t.get("umber", {})
	if str(u.get("id", "umber")) == id:
		return u
	return {}

## Colour wells in a zone: count [lo, hi] seeded, at least min_count (Triptych), at most the palette.
static func roll_count(rng: RandomNumberGenerator, t: Dictionary) -> int:
	var c: Array = t.get("count", [2, 3])
	var n := rng.randi_range(int(c[0]), int(c[1]))
	return clampi(maxi(n, int(t.get("min_count", 0))), 1, colour_ids(t).size())

## n distinct colour ids, seeded.
static func pick_colours(rng: RandomNumberGenerator, n: int, t: Dictionary) -> Array:
	var ids := colour_ids(t)
	var out := []
	while out.size() < n and not ids.is_empty():
		out.append(ids.pop_at(rng.randi_range(0, ids.size() - 1)))
	return out

## Fill one kill adds (elite: elites and minibosses).
static func kill_fill(elite: bool, t: Dictionary) -> float:
	return float(t.get("elite_fill" if elite else "kill_fill", 0.04)) * float(t.get("kill_fill_mult", 1.0)) * float(t.get("fill_mult", 1.0))

## Fill `dt` seconds near a well add.
static func time_fill(dt: float, t: Dictionary) -> float:
	return float(t.get("time_fill", 0.01)) * dt * float(t.get("time_fill_mult", 1.0)) * float(t.get("fill_mult", 1.0))

## What a well of colour `id` at fill f lends the monsters of its chamber:
## {fire: added fire fraction, ignite: %, armour: more armour fraction, poison: %}.
static func danger(id: String, f: float, t: Dictionary) -> Dictionary:
	var c := colour_info(id, t)
	var k := clampf(f, 0.0, 1.0) * float(t.get("danger_mult", 1.0))
	return {"fire": float(c.get("fire", 0.0)) * k, "ignite": float(c.get("ignite", 0.0)) * k,
		"armour": float(c.get("armour", 0.0)) * k, "poison": float(c.get("poison", 0.0)) * k}

## The mix. fills: {colour id: fill 0..1} for every colour well of the zone (untouched = 0); umber:
## the umber fill (-1 = no umber well). -> {kind: none|pure|mixed|balanced, draws: [colour ids, one per
## draw], total, shares: {id: share}, dominant, second, legendary: chance, unique: chance}
static func mix(fills: Dictionary, umber: float, rot: int, t: Dictionary) -> Dictionary:
	var ids := []
	for id in colour_ids(t):   # palette order (no lambdas in static functions: Godot 4.0)
		if fills.has(id):
			ids.append(id)
	var total := 0.0
	for id in ids:
		total += clampf(float(fills[id]), 0.0, 1.0)
	var out := {"kind": "none", "draws": [], "total": total, "shares": {}, "dominant": "", "second": "",
		"legendary": 0.0, "unique": clampf(umber, 0.0, 1.0) if umber >= 0.0 else 0.0}
	if total <= 0.0001:
		return out
	var n := maxi(1, int(round(total))) + int(rot / maxi(1, int(t.get("rot_draws_per", 2)))) + int(t.get("draws", 0))
	var order := []   # by fill, highest first; ties keep palette order (stable insertion)
	for id in ids:
		var at := order.size()
		for j in order.size():
			if float(fills[id]) > float(fills[order[j]]):
				at = j
				break
		order.insert(at, id)
	for id in ids:
		out["shares"][id] = clampf(float(fills[id]), 0.0, 1.0) / total
	var dom: String = order[0]
	var sec: String = order[1] if order.size() > 1 and float(fills[order[1]]) > 0.0 else ""
	out["dominant"] = dom
	out["second"] = sec
	var s1: float = out["shares"][dom]
	var balanced := false
	if ids.size() >= 3:
		balanced = s1 <= float(t.get("balanced_3", 0.45)) + 0.0001
	elif ids.size() == 2:
		balanced = absf(float(out["shares"][ids[0]]) - float(out["shares"][ids[1]])) <= float(t.get("balanced_2", 0.15)) + 0.0001
	var draws := []
	if balanced:
		out["kind"] = "balanced"
		n = maxi(n, ids.size())
		for i in n:
			draws.append(order[i % order.size()])
		out["legendary"] = clampf(float(t.get("legendary", 0.25)) + float(t.get("legendary_per_fill", 0.1)) * maxf(0.0, total - 1.0), 0.0, float(t.get("legendary_max", 0.6)))
	elif s1 >= float(t.get("pure_share", 0.5)) - 0.0001 or sec == "":
		out["kind"] = "pure"
		for i in n:
			draws.append(dom)
	else:
		out["kind"] = "mixed"
		for i in n:
			draws.append(dom)
		draws.append(sec)
	out["draws"] = draws
	return out

## True when an item has at least one affix on `stats`.
static func has_stat_affix(it: Dictionary, stats: Array) -> bool:
	for a in it.get("affixes", []):
		if stats.has(str(Data.affixes.get(str(a.get("id", "")), {}).get("stat", ""))):
			return true
	return false

## The drops of one draw of colour `id` (spawn_drop dictionaries). first: the chest's first item draw.
static func roll_draw(id: String, lvl: int, class_id: String, first: bool, rarity_extra: float, t: Dictionary) -> Array:
	var GuildRules = load("res://scripts/core/guild_rules.gd")
	var out := []
	match id:
		"crimson":
			var c: Dictionary = t.get("crimson", {})
			var slots: Array = c.get("slots", ["main_hand", "off_hand"])
			var it := {}
			for i in maxi(1, int(c.get("tries", 8))):
				var rar := "rare"
				var bonus := (float(c.get("first_rarity", 400)) if first else 0.0) + rarity_extra
				if bonus > 0.0:
					rar = Loot.roll_rarity(bonus)
					if Data.rarity_index(rar) < Data.rarity_index("rare") or rar == "legendary":
						rar = "rare"
				var bid: String = GuildRules._base_for(slots, lvl, class_id)
				if bid == "":
					bid = GuildRules._base_for(slots, lvl, "")
				if bid == "":
					break
				it = Loot.roll_item_of(bid, rar, lvl)
				if has_stat_affix(it, c.get("offensive", [])):
					break
			if not it.is_empty():
				out.append({"kind": "item", "item": it})
		"ochre":
			var o: Dictionary = t.get("ochre", {})
			out.append({"kind": "gold", "amount": int(o.get("gold_per_level", 120)) * lvl})
			for i in int(o.get("materials", 3)):
				out.append({"kind": "material", "id": Loot._roll_material(), "amount": 1})
			for k in [["glaze_flake", "flakes"], ["pigment_dust", "dust"], ["ash", "ash"]]:
				if int(o.get(k[1], 0)) > 0:
					out.append({"kind": "material", "id": k[0], "amount": int(o.get(k[1], 0))})
		"verdigris":
			var v: Dictionary = t.get("verdigris", {})
			var iw := float(v.get("item_w", 2))
			var gw := float(v.get("gem_w", 1))
			if Loot.rng.randf() * (iw + gw) < gw:
				var gid: String = Loot.random_gem(lvl)
				if gid != "":
					out.append({"kind": "gem", "id": gid})
			else:
				var rar := "rare"
				if rarity_extra > 0.0:
					rar = Loot.roll_rarity(rarity_extra)
					if Data.rarity_index(rar) < Data.rarity_index("rare") or rar == "legendary":
						rar = "rare"
				var bid: String = GuildRules._base_for(v.get("slots", ["ring", "amulet", "belt", "charm"]), lvl, class_id)
				if bid != "":
					out.append({"kind": "item", "item": Loot.roll_item_of(bid, rar, lvl)})
	return out
