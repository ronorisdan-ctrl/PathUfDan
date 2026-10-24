extends Node
## Item generation, affix rolling, drop tables, item text and crafting rules.
## Everything is driven by data/item_bases.json, affixes.json, uniques.json and loot.json.

var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()

func set_seed(s: int) -> void:
	rng.seed = s

# ------------------------------------------------------------------ creation
func make_item(base_id: String, rarity: String, ilvl: int) -> Dictionary:
	var b: Dictionary = Data.item_bases.get(base_id, {})
	if b.is_empty():
		push_warning("Unknown item base " + base_id)
		return {}
	var it := {
		"base": base_id, "base_name": b["name"], "name": b["name"], "rarity": rarity,
		"ilvl": ilvl, "req_level": int(b.get("req_level", 1)), "slot": b["slot"],
		"category": b.get("category", ""), "icon": b.get("icon", "charm"),
		"two_handed": b.get("two_handed", false), "tags": b.get("tags", []).duplicate(),
		"armour_type": b.get("armour_type", ""), "implicit": b.get("implicit", []).duplicate(true),
		"affixes": [], "upgrade": 0, "uid": 0,
	}
	for k in ["damage", "aps", "crit", "armour", "evasion", "block"]:
		if b.has(k):
			it[k] = b[k]
	return it

func roll_item(ilvl: int, rarity_bonus: float = 0.0, class_id: String = "", forced_rarity: String = "") -> Dictionary:
	var rarity := forced_rarity if forced_rarity != "" else roll_rarity(rarity_bonus)
	if rarity == "legendary":
		var u := roll_unique(ilvl, class_id)
		if not u.is_empty():
			return u
		rarity = "epic"
	var base_id := pick_base(ilvl, class_id)
	var it := make_item(base_id, rarity, ilvl)
	var rd: Dictionary = Data.rarities.get(rarity, {})
	var rng_aff: Array = rd.get("affixes", [0, 0])
	var n := rng.randi_range(int(rng_aff[0]), int(rng_aff[1]))
	for i in n:
		add_random_affix(it, int(rd.get("tier_bonus", 0)))
	roll_sockets(it)
	_rename(it)
	return it

# ------------------------------------------------------------------ sockets & gems
## Gems socket into gear; what a gem grants depends on where it sits
## (weapon / armour / jewellery), Diablo-style.
func socket_category(it: Dictionary) -> String:
	match it.get("slot", ""):
		"main_hand":
			return "weapon"
		"off_hand":
			return "armour" if it.get("category", "") == "shield" else "weapon"
		"helmet", "chest", "gloves", "boots", "belt":
			return "armour"
		"ring", "amulet":
			return "jewelry"
	return ""

func max_sockets(it: Dictionary) -> int:
	match it.get("slot", ""):
		"main_hand":
			return 3 if it.get("two_handed", false) else 2
		"chest":
			return 3
		"off_hand", "helmet", "gloves", "boots":
			return 2
		"belt", "ring", "amulet":
			return 1
	return 0

func roll_sockets(it: Dictionary) -> void:
	var mx := max_sockets(it)
	var n := 0
	var p := clampf(0.12 + 0.01 * int(it.get("ilvl", 1)), 0.12, 0.5)
	for i in mx:
		if rng.randf() < p:
			n += 1
		else:
			break
	it["sockets"] = n
	it["gems"] = []
	for i in n:
		it["gems"].append("")

func item_sockets(it: Dictionary) -> int:
	return int(it.get("sockets", 0))

func add_socket(it: Dictionary) -> void:
	it["sockets"] = item_sockets(it) + 1
	var g: Array = it.get("gems", [])
	while g.size() < it["sockets"]:
		g.append("")
	it["gems"] = g

func gem_base(gid: String) -> Dictionary:
	return Data.gems.get(gid.get_slice(":", 0), {})

func gem_tier(gid: String) -> int:
	return clampi(int(gid.get_slice(":", 1)), 0, Data.gem_cfg.get("tiers", [{}]).size() - 1)

func gem_id(base_id: String, tier: int) -> String:
	return "%s:%d" % [base_id, tier]

func gem_valid(gid: String) -> bool:
	return gid.contains(":") and not gem_base(gid).is_empty() and int(gid.get_slice(":", 1)) < Data.gem_cfg.get("tiers", []).size()

func gem_name(gid: String) -> String:
	var t: Dictionary = Data.gem_cfg["tiers"][gem_tier(gid)]
	return "%s %s" % [t["name"], gem_base(gid).get("name", "Gem")]

func gem_color(gid: String) -> Color:
	return Color(gem_base(gid).get("color", "#ffffff"))

func gem_req(gid: String) -> int:
	return int(Data.gem_cfg["tiers"][gem_tier(gid)].get("req", 1))

func gem_mods(gid: String, category: String) -> Array:
	var g := gem_base(gid)
	if g.is_empty() or category == "":
		return []
	var mult := float(Data.gem_cfg["tiers"][gem_tier(gid)].get("mult", 1.0))
	var out := []
	for m in g.get(category, []):
		var v: float = float(m["value"]) * mult
		v = round(v * 10.0) / 10.0 if absf(v) < 10 else round(v)
		out.append({"stat": m["stat"], "type": m["type"], "value": v})
	return out

func gem_summary(gid: String) -> String:
	var parts := []
	for cat in [["weapon", "Weapon"], ["armour", "Armour"], ["jewelry", "Jewellery"]]:
		var ms := []
		for m in gem_mods(gid, cat[0]):
			ms.append(mod_text(m))
		parts.append("%s: %s" % [cat[1], ", ".join(ms)])
	return "\n".join(parts)

func random_gem(monster_level: int) -> String:
	var gl: Array = Data.gem_list
	if gl.is_empty():
		return ""
	var tiers: Array = Data.gem_cfg.get("tiers", [])
	var best := 0
	for i in tiers.size():
		if int(tiers[i].get("req", 1)) <= monster_level:
			best = i
	# mostly the best tier for the level, sometimes one below
	var t := best if (best == 0 or rng.randf() < 0.65) else best - 1
	return gem_id(gl[rng.randi() % gl.size()]["id"], t)

func roll_rarity(bonus: float) -> String:
	var total := 0.0
	var weights := []
	for i in Data.rarity_list.size():
		var r: Dictionary = Data.rarity_list[i]
		var w := float(r["weight"])
		if i == 1:
			w *= 1.0 + bonus / 200.0
		elif i >= 2:
			w *= 1.0 + bonus / 100.0
		weights.append(w)
		total += w
	var roll := rng.randf() * total
	for i in weights.size():
		roll -= weights[i]
		if roll <= 0:
			return Data.rarity_list[i]["id"]
	return "common"

func pick_base(ilvl: int, class_id: String) -> String:
	var bias := float(Data.loot.get("class_bias", 0.7))
	var want_class := class_id != "" and rng.randf() < bias
	var pool := []
	# prefer bases close to the item level so endgame drops use the stronger base tiers
	var recent := rng.randf() < 0.75
	for b in Data.item_base_list:
		var req := int(b.get("req_level", 1))
		if req > ilvl + 1:
			continue
		if recent and req < ilvl - 18 and int(b.get("base_tier", 1)) < 3 and not b.get("slot", "") in ["ring", "amulet", "belt", "charm"]:
			continue
		if want_class and not base_usable_by(b, class_id):
			continue
		pool.append(b["id"])
	if pool.is_empty():
		for b in Data.item_base_list:
			pool.append(b["id"])
	return pool[rng.randi() % pool.size()]

func base_usable_by(b: Dictionary, class_id: String) -> bool:
	var cd: Dictionary = Data.classes.get(class_id, {})
	var slot: String = b.get("slot", "")
	if slot == "main_hand" or slot == "off_hand":
		return cd.get("weapon_types", []).has(b.get("category", ""))
	var at: String = b.get("armour_type", "")
	if at != "":
		return cd.get("armour_types", []).has(at)
	return true

func roll_unique(ilvl: int, class_id: String) -> Dictionary:
	var pool := []
	for u in Data.unique_list:
		if int(u.get("req_level", 1)) <= ilvl + 2:
			var b: Dictionary = Data.item_bases.get(u["base"], {})
			# lean towards uniques the character can use
			var w := 3 if (class_id == "" or base_usable_by(b, class_id)) else 1
			for i in w:
				pool.append(u["id"])
	if pool.is_empty():
		return {}
	return make_unique(pool[rng.randi() % pool.size()], ilvl)

func make_unique(uid: String, ilvl: int) -> Dictionary:
	var u: Dictionary = Data.uniques.get(uid, {})
	var it := make_item(u["base"], "legendary", ilvl)
	it["name"] = u["name"]
	it["unique"] = uid
	it["req_level"] = maxi(int(it["req_level"]), int(u.get("req_level", 1)))
	it["legendary_effect"] = u.get("effect", "")
	var fixed := []
	for m in u.get("mods", []):
		var v: float
		if m.has("range"):
			v = float(rng.randi_range(int(m["range"][0]), int(m["range"][1])))
		else:
			v = float(m.get("value", 0))
		fixed.append({"stat": m["stat"], "type": m["type"], "value": v})
	it["fixed"] = fixed
	roll_sockets(it)
	return it

# ------------------------------------------------------------------ affixes
func eligible_affixes(it: Dictionary, kind: String) -> Array:
	var used_groups := {}
	for a in it.get("affixes", []):
		used_groups[Data.affixes.get(a["id"], {}).get("group", a["id"])] = true
	var out := []
	var tags: Array = it.get("tags", [])
	for a in Data.affix_list:
		if kind != "" and a["kind"] != kind:
			continue
		if used_groups.has(a.get("group", a["id"])):
			continue
		var ok := false
		for s in a.get("slots", []):
			if tags.has(s) or s == it.get("slot", "") or s == it.get("category", ""):
				ok = true
				break
		if not ok:
			continue
		if int(a["tiers"][0][0]) > int(it.get("ilvl", 1)):
			continue
		out.append(a)
	return out

func open_kinds(it: Dictionary) -> Array:
	var p := 0
	var s := 0
	for a in it.get("affixes", []):
		if a["kind"] == "prefix":
			p += 1
		else:
			s += 1
	var kinds := []
	if p < int(Data.loot.get("max_prefixes", 3)):
		kinds.append("prefix")
	if s < int(Data.loot.get("max_suffixes", 3)):
		kinds.append("suffix")
	return kinds

func add_random_affix(it: Dictionary, tier_bonus: int = 0, kind: String = "") -> bool:
	var kinds := open_kinds(it)
	if kind != "":
		if not kinds.has(kind):
			return false
		kinds = [kind]
	kinds.shuffle()
	for k in kinds:
		var pool := eligible_affixes(it, k)
		if pool.is_empty():
			continue
		var a := _weighted(pool)
		it["affixes"].append(roll_affix(a, int(it.get("ilvl", 1)), tier_bonus))
		_update_req(it)
		return true
	return false

func roll_affix(a: Dictionary, ilvl: int, tier_bonus: int = 0) -> Dictionary:
	var tiers: Array = a["tiers"]
	var max_t := 0
	for i in tiers.size():
		if int(tiers[i][0]) <= ilvl:
			max_t = i
	var t := rng.randi_range(0, max_t)
	for i in tier_bonus:
		t = maxi(t, rng.randi_range(0, max_t))
	var tier: Array = tiers[t]
	var v := float(rng.randi_range(int(tier[1]), int(tier[2])))
	return {"id": a["id"], "kind": a["kind"], "stat": a["stat"], "type": a["type"], "value": v, "tier": t + 1, "tier_ilvl": int(tier[0])}

func _weighted(pool: Array) -> Dictionary:
	var total := 0.0
	for a in pool:
		total += float(a.get("weight", 100))
	var r := rng.randf() * total
	for a in pool:
		r -= float(a.get("weight", 100))
		if r <= 0:
			return a
	return pool[pool.size() - 1]

func _update_req(it: Dictionary) -> void:
	var req := int(Data.item_bases.get(it["base"], {}).get("req_level", 1))
	if it.has("unique"):
		req = maxi(req, int(Data.uniques.get(it["unique"], {}).get("req_level", 1)))
	for a in it.get("affixes", []):
		req = maxi(req, int(a.get("tier_ilvl", 1)))
	it["req_level"] = req

func _rename(it: Dictionary) -> void:
	var r: String = it.get("rarity", "common")
	if r == "legendary":
		return
	var base_name: String = it["base_name"]
	if r == "common" or it["affixes"].is_empty():
		it["name"] = base_name
	elif r == "uncommon":
		var pre := ""
		var suf := ""
		for a in it["affixes"]:
			var d: Dictionary = Data.affixes.get(a["id"], {})
			if a["kind"] == "prefix" and pre == "":
				pre = d.get("name", "")
			elif a["kind"] == "suffix" and suf == "":
				suf = d.get("name", "")
		it["name"] = ("%s %s %s" % [pre, base_name, suf]).strip_edges()
	else:
		if not it.has("rare_name"):
			var A: Array = Data.loot.get("rare_name_a", ["Grim"])
			var B: Array = Data.loot.get("rare_name_b", ["Bane"])
			it["rare_name"] = "%s %s" % [A[rng.randi() % A.size()], B[rng.randi() % B.size()]]
		it["name"] = it["rare_name"]

# ------------------------------------------------------------------ queries
func item_mods(it: Dictionary) -> Array:
	## every stat modifier the item grants (global, non-local)
	var out := []
	var up := 1.0 + 0.1 * int(it.get("upgrade", 0))
	if it.has("armour"):
		out.append({"stat": "armour", "type": "flat", "value": round(float(it["armour"]) * up)})
	if it.has("evasion"):
		out.append({"stat": "evasion", "type": "flat", "value": round(float(it["evasion"]) * up)})
	for m in it.get("implicit", []):
		out.append(m)
	for m in it.get("fixed", []):
		out.append(m)
	for a in it.get("affixes", []):
		out.append({"stat": a["stat"], "type": a["type"], "value": a["value"]})
	for r in it.get("runes", []):
		out.append(r)
	var cat := socket_category(it)
	for g in it.get("gems", []):
		if g != "":
			out.append_array(gem_mods(g, cat))
	return out

func weapon_damage(it: Dictionary) -> Array:
	var d: Array = it.get("damage", [2, 4])
	var up := 1.0 + 0.1 * int(it.get("upgrade", 0))
	return [float(d[0]) * up, float(d[1]) * up]

func affix_text(a: Dictionary) -> String:
	var d: Dictionary = Data.affixes.get(a.get("id", ""), {})
	var t: String = d.get("text", "")
	if t == "":
		return mod_text(a)
	return t.replace("{v}", _num(a["value"]))

func mod_text(m: Dictionary) -> String:
	var v := float(m.get("value", 0))
	var nm := Data.stat_name(m.get("stat", ""))
	match m.get("type", "flat"):
		"inc":
			return ("%s%% increased %s" % [_num(v), nm]) if v >= 0 else ("%s%% reduced %s" % [_num(-v), nm])
		"more":
			return ("%s%% more %s" % [_num(v), nm]) if v >= 0 else ("%s%% less %s" % [_num(-v), nm])
		_:
			var info: Dictionary = Data.stat_info.get(m.get("stat", ""), {})
			var pct := "%" if info.get("pct", false) else ""
			return "%s%s%s %s" % ["+" if v >= 0 else "", _num(v), pct, nm]

func _num(v) -> String:
	var f := float(v)
	if absf(f - round(f)) < 0.01:
		return str(int(round(f)))
	return "%.1f" % f

func sell_value(it: Dictionary) -> int:
	var rd: Dictionary = Data.rarities.get(it.get("rarity", "common"), {})
	return int(round((3 + int(it.get("ilvl", 1)) * 1.5) * float(rd.get("value_mult", 1.0)) * (1.0 + 0.25 * int(it.get("upgrade", 0)))))

func buy_value(it: Dictionary) -> int:
	return sell_value(it) * 4

func salvage_yield(it: Dictionary) -> Dictionary:
	var r := Data.rarity_index(it.get("rarity", "common"))
	var lv := int(it.get("ilvl", 1))
	var y := {"scrap": 1 + int(lv / 4.0) + r}
	if r >= 1:
		y["iron_fragment"] = 1 + int(r / 2.0)
	if r >= 2:
		y["arcane_dust"] = r - 1
	if r >= 3:
		y["monster_core"] = 1
	if r >= 4:
		y["elemental_essence"] = 1
		y["catalyst"] = 1
	return y

func cost_text(cost: Dictionary) -> String:
	var parts := []
	for k in cost:
		if k == "gold":
			parts.append("%d gold" % int(cost[k]))
		else:
			parts.append("%d %s" % [int(cost[k]), Data.materials.get(k, {}).get("name", k)])
	return ", ".join(parts)

# ------------------------------------------------------------------ tooltip
func tooltip(it: Dictionary, ch = null) -> String:
	var col := Data.rarity_color(it.get("rarity", "common")).to_html(false)
	var lines := []
	var up := int(it.get("upgrade", 0))
	lines.append("[font_size=17][color=#%s]%s%s[/color][/font_size]" % [col, it["name"], (" +%d" % up) if up > 0 else ""])
	var rname: String = Data.rarities.get(it.get("rarity", "common"), {}).get("name", "")
	if it["name"] != it["base_name"] or it.get("rarity") == "legendary":
		lines.append("[color=#%s]%s[/color]" % [col, it["base_name"]])
	var typ: String = it.get("category", "").capitalize()
	if it.get("two_handed", false):
		typ = "Two-Handed " + typ
	if it.get("armour_type", "") != "":
		typ = "%s (%s)" % [typ, it["armour_type"].capitalize()]
	lines.append("[color=#8a8494]%s %s  -  Item Level %d[/color]" % [rname, typ, int(it.get("ilvl", 1))])
	lines.append("[color=#3a3440]────────────────────[/color]")
	if it.has("damage"):
		var d := weapon_damage(it)
		lines.append("Physical Damage: [color=#ffffff]%d-%d[/color]" % [int(d[0]), int(d[1])])
		lines.append("Attacks per Second: [color=#ffffff]%.2f[/color]   Crit: [color=#ffffff]%d%%[/color]" % [float(it.get("aps", 1)), int(it.get("crit", 5))])
	if it.has("armour"):
		lines.append("Armour: [color=#ffffff]%d[/color]" % int(round(float(it["armour"]) * (1.0 + 0.1 * up))))
	if it.has("evasion"):
		lines.append("Evasion: [color=#ffffff]%d[/color]" % int(round(float(it["evasion"]) * (1.0 + 0.1 * up))))
	if it.has("block"):
		lines.append("Block Chance: [color=#ffffff]%d%%[/color]" % int(it["block"]))
	var req := "Requires Level %d" % int(it.get("req_level", 1))
	if ch != null:
		var why: String = ch.equip_restriction(it)
		if why != "":
			lines.append("[color=#ff5050]%s[/color]" % why)
		else:
			lines.append("[color=#8a8494]%s[/color]" % req)
	else:
		lines.append("[color=#8a8494]%s[/color]" % req)
	var impl: Array = it.get("implicit", [])
	if impl.size() > 0:
		lines.append("[color=#3a3440]────────────────────[/color]")
		for m in impl:
			lines.append("[color=#c8c0d8]%s[/color]" % mod_text(m))
	var fixed: Array = it.get("fixed", [])
	var affs: Array = it.get("affixes", [])
	if fixed.size() + affs.size() > 0:
		lines.append("[color=#3a3440]────────────────────[/color]")
		for m in fixed:
			lines.append("[color=#ffb060]%s[/color]" % mod_text(m))
		for a in affs:
			lines.append("[color=#8ab8ff]%s[/color] [color=#4a4a60](T%d %s)[/color]" % [affix_text(a), int(a.get("tier", 1)), a.get("kind", "")])
	var ns := item_sockets(it)
	if ns > 0:
		lines.append("[color=#3a3440]────────────────────[/color]")
		var gl: Array = it.get("gems", [])
		var cat := socket_category(it)
		for i in ns:
			var g: String = gl[i] if i < gl.size() else ""
			if g == "":
				lines.append("[color=#6a6474]( ) Empty socket[/color]")
			else:
				var ms := []
				for m in gem_mods(g, cat):
					ms.append(mod_text(m))
				lines.append("[color=#%s](o) %s[/color] [color=#c8c0d8]%s[/color]" % [gem_color(g).to_html(false), gem_name(g), ", ".join(ms)])
	if it.get("legendary_effect", "") != "":
		var u: Dictionary = Data.uniques.get(it.get("unique", ""), {})
		lines.append("[color=#ff8c2a]%s[/color]" % u.get("effect_text", ""))
		if u.get("flavor", "") != "":
			lines.append("[i][color=#a07850]\"%s\"[/color][/i]" % u["flavor"])
	lines.append("[color=#3a3440]────────────────────[/color]")
	lines.append("[color=#8a8494]Sell: %d gold   Salvage: %s[/color]" % [sell_value(it), cost_text(salvage_yield(it))])
	return "\n".join(lines)

# ------------------------------------------------------------------ drops
## Returns a list of drops: {"kind": "item"|"gold"|"material", ...}
func roll_drops(monster_level: int, loot_mult: float, is_elite: bool, is_boss: bool, class_id: String, rarity_stat: float) -> Array:
	var out := []
	var L: Dictionary = Data.loot
	var rolls := 1
	var bonus := rarity_stat
	if is_elite:
		rolls = int(L.get("elite_item_rolls", 2))
		bonus += float(L.get("elite_rarity_bonus", 150))
	if is_boss:
		rolls = int(L.get("boss_item_rolls", 4))
		bonus += float(L.get("boss_rarity_bonus", 400))
	var chance := float(L.get("item_drop_chance", 0.16)) * loot_mult
	for i in rolls:
		if is_boss or rng.randf() < chance:
			var rar := ""
			if is_boss and i == 0:
				rar = "rare" if rng.randf() < 0.8 else "epic"
			out.append({"kind": "item", "item": roll_item(monster_level, bonus, class_id, rar)})
	if rng.randf() < float(L.get("gold_drop_chance", 0.4)) * minf(loot_mult, 3.0) or is_elite or is_boss:
		var g := int(round(monster_level * rng.randf_range(2.0, 5.0) * maxf(1.0, loot_mult)))
		if is_boss:
			g *= 5
		out.append({"kind": "gold", "amount": maxi(1, g)})
	var rune_chance := 0.02 * loot_mult
	if is_elite:
		rune_chance = 0.12
	if is_boss:
		rune_chance = 1.0
	if rng.randf() < rune_chance:
		out.append({"kind": "rune", "id": random_rune()})
	if is_boss and rng.randf() < 0.5:
		out.append({"kind": "rune", "id": random_rune()})
	var gem_chance := 0.03 * loot_mult
	if is_elite:
		gem_chance = 0.18
	if is_boss:
		gem_chance = 1.0
	if rng.randf() < gem_chance:
		out.append({"kind": "gem", "id": random_gem(monster_level)})
	var mat_rolls := 1 + (2 if is_elite else 0) + (5 if is_boss else 0)
	for i in mat_rolls:
		if is_boss or rng.randf() < float(L.get("material_drop_chance", 0.12)) * loot_mult:
			out.append({"kind": "material", "id": _roll_material(), "amount": 1})
	return out

func random_rune() -> String:
	var l: Array = Data.skill_rune_list
	if l.is_empty():
		return ""
	return l[rng.randi() % l.size()]["id"]

func _roll_material() -> String:
	var mats: Dictionary = Data.materials
	var total := 0.0
	for k in mats:
		total += float(mats[k].get("weight", 10))
	var r := rng.randf() * total
	for k in mats:
		r -= float(mats[k].get("weight", 10))
		if r <= 0:
			return k
	return "scrap"

# ------------------------------------------------------------------ crafting
## Each operation exposes cost(), validity and apply(). Results are previewed in the UI
## before the player confirms. Operations never destroy an item except salvage.

const MAX_UPGRADE := 5

func craft_ops() -> Array:
	return ["upgrade", "reroll", "add", "remove", "rarity", "socket"]

func craft_name(op: String) -> String:
	return {"upgrade": "Upgrade Base", "reroll": "Reroll Affix", "add": "Add Affix", "remove": "Remove Affix", "rarity": "Raise Rarity", "socket": "Add Socket"}.get(op, op)

func craft_cost(op: String, it: Dictionary) -> Dictionary:
	var lv := int(it.get("ilvl", 1))
	match op:
		"upgrade":
			var u := int(it.get("upgrade", 0))
			return {"gold": 15 + lv * 3 * (u + 1), "scrap": 2 + u, "iron_fragment": 1 + u}
		"reroll":
			return {"gold": 10 + lv * 2, "arcane_dust": 1}
		"add":
			return {"gold": 25 + lv * 4, "catalyst": 1, "arcane_dust": 1}
		"remove":
			return {"gold": 20 + lv * 3, "monster_core": 1}
		"rarity":
			var r := Data.rarity_index(it.get("rarity", "common"))
			return {"gold": 30 + lv * 5 * (r + 1), "elemental_essence": 1 + int(r / 2.0), "scrap": 3}
		"socket":
			var ns := item_sockets(it)
			return {"gold": 40 + lv * 4 * (ns + 1), "iron_fragment": 2 + ns, "monster_core": 1}
	return {}

func craft_check(op: String, it: Dictionary, affix_index: int = -1) -> String:
	if it.is_empty():
		return "Select an item"
	var legendary: bool = it.get("rarity") == "legendary"
	match op:
		"upgrade":
			if int(it.get("upgrade", 0)) >= MAX_UPGRADE:
				return "Already fully upgraded (+%d)" % MAX_UPGRADE
			if not (it.has("damage") or it.has("armour") or it.has("evasion")):
				return "This item has no base damage or defence to upgrade"
		"reroll", "remove":
			if legendary:
				return "Legendary affixes cannot be changed"
			if it.get("affixes", []).is_empty():
				return "Item has no affixes"
			if affix_index < 0 or affix_index >= it["affixes"].size():
				return "Choose an affix"
		"add":
			if legendary:
				return "Legendary items cannot gain affixes"
			var rd: Dictionary = Data.rarities.get(it.get("rarity", "common"), {})
			if it["affixes"].size() >= int(rd.get("affixes", [0, 0])[1]):
				return "No free affix slot for this rarity (raise rarity first)"
			if open_kinds(it).is_empty():
				return "No free prefix or suffix slot"
			var any := false
			for k in open_kinds(it):
				if eligible_affixes(it, k).size() > 0:
					any = true
			if not any:
				return "No valid affixes remain for this item"
		"rarity":
			var r := Data.rarity_index(it.get("rarity", "common"))
			if r >= 3:
				return "Epic and Legendary items cannot be raised further"
		"socket":
			if max_sockets(it) == 0:
				return "This item cannot hold sockets"
			if item_sockets(it) >= max_sockets(it):
				return "Already has the maximum of %d sockets" % max_sockets(it)
	return ""

func craft_apply(op: String, it: Dictionary, affix_index: int = -1) -> Dictionary:
	## mutates and returns the item
	match op:
		"upgrade":
			it["upgrade"] = int(it.get("upgrade", 0)) + 1
		"reroll":
			var old: Dictionary = it["affixes"][affix_index]
			it["affixes"].remove_at(affix_index)
			var pool := eligible_affixes(it, old["kind"])
			pool = pool.filter(func(a): return a["id"] != old["id"])
			if pool.is_empty():
				pool = eligible_affixes(it, old["kind"])
			var a := _weighted(pool)
			it["affixes"].insert(affix_index, roll_affix(a, int(it["ilvl"]), 0))
		"add":
			add_random_affix(it, 0)
		"remove":
			it["affixes"].remove_at(affix_index)
		"socket":
			add_socket(it)
		"rarity":
			var r := Data.rarity_index(it.get("rarity", "common"))
			var nr: Dictionary = Data.rarity_list[r + 1]
			it["rarity"] = nr["id"]
			while it["affixes"].size() < int(nr["affixes"][0]):
				if not add_random_affix(it, int(nr.get("tier_bonus", 0))):
					break
	_update_req(it)
	_rename(it)
	return it

func craft_preview(op: String, it: Dictionary, affix_index: int = -1) -> String:
	match op:
		"upgrade":
			var u := int(it.get("upgrade", 0))
			var s := "Base damage and defence: +%d%% -> +%d%%" % [u * 10, (u + 1) * 10]
			if it.has("damage"):
				var d := weapon_damage(it)
				s += "\nPhysical damage %d-%d -> %d-%d" % [int(d[0]), int(d[1]), int(float(it["damage"][0]) * (1.1 + 0.1 * u)), int(float(it["damage"][1]) * (1.1 + 0.1 * u))]
			return s
		"reroll":
			if affix_index >= 0 and affix_index < it["affixes"].size():
				var a: Dictionary = it["affixes"][affix_index]
				var n := eligible_affixes(it, a["kind"]).size()
				return "Replace \"%s\" with a random %s (one of %d options)" % [affix_text(a), a["kind"], n + 1]
		"remove":
			if affix_index >= 0 and affix_index < it["affixes"].size():
				return "Permanently remove \"%s\"" % affix_text(it["affixes"][affix_index])
		"add":
			return "Add one random affix to a free prefix/suffix slot"
		"socket":
			return "Sockets: %d -> %d (max %d). Socket gems at the Jeweller." % [item_sockets(it), item_sockets(it) + 1, max_sockets(it)]
		"rarity":
			var r := Data.rarity_index(it.get("rarity", "common"))
			if r + 1 < Data.rarity_list.size():
				var nr: Dictionary = Data.rarity_list[r + 1]
				return "%s -> %s. Existing affixes are kept; new ones fill up to %d affixes." % [Data.rarity_list[r]["name"], nr["name"], int(nr["affixes"][0])]
	return ""
