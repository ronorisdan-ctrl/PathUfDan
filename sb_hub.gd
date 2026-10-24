extends RefCounted
## Between-run (and level-up) character management for the smart bot:
## gear scoring and equipping, selling / salvaging, blacksmith crafting with a gold
## budget, vendor purchases, gems (socket, upgrade, combine, buy), hotbar, runes,
## specialisation. Everything calls the same CharacterData / Loot / Game functions the
## UI panels call; only the confirmation dialogs (ui.ask) are skipped.

const Planner = preload("res://tests/smartbot/sb_planner.gd")

var bot = null              # the smartbot node (for flags / logging)
var build := "balanced"
var flags := {}             # no_gems, no_passives, no_crafting
var planner = Planner.new()
var main_skills := []       # damage skills used by the power score
var log_lines := []

const SLOT_ORDER := ["main_hand", "chest", "off_hand", "helmet", "gloves", "boots", "belt", "amulet", "ring1", "ring2", "charm"]
const WEIGHTS := {"balanced": [1.0, 1.0], "glass": [1.25, 0.8], "defensive": [0.8, 1.3]}

func setup(b, build_name: String, fl: Dictionary) -> void:
	bot = b
	build = build_name
	flags = fl
	planner.hub = self

func L(s: String) -> void:
	log_lines.append(s)
	if bot != null:
		bot.trace(s)

# ================================================================== scoring
func _groups_for(w) -> Array:
	if w == null:
		return ["unarmed", "melee"]
	var g: Array = [w.get("category", "")]
	var tags: Array = w.get("tags", [])
	for t in [["melee_weapon", "melee"], ["ranged_weapon", "ranged"], ["caster_weapon", "caster"], ["bow", "bow"], ["firearm", "firearm"]]:
		if tags.has(t[0]):
			g.append(t[1])
	return g

func weapon_ok_for(sk: Dictionary, w) -> bool:
	var req: Array = sk.get("weapon_req", [])
	if req.is_empty():
		return true
	var g := _groups_for(w)
	for r in req:
		if g.has(r):
			return true
	return false

func use_time(sk: Dictionary, f: Dictionary) -> float:
	match sk.get("kind", "spell"):
		"attack":
			return (1.0 / maxf(0.2, f.get("weapon_aps", 1.2))) * float(sk.get("speed_mult", 1.0)) / maxf(0.1, f.get("attack_speed_mult", 1.0))
		"spell", "trap", "minion", "turret":
			return float(sk.get("use_time", 0.6)) / maxf(0.1, f.get("cast_speed_mult", 1.0))
	return float(sk.get("use_time", 0.3))

func targets_factor(sk: Dictionary, aoe: bool) -> float:
	var b: String = sk.get("behavior", "")
	var tags: Array = sk.get("tags", [])
	var n := 1.0
	match b:
		"projectile":
			var c := int(sk.get("count", 1))
			n = (minf(c, 3.0) if aoe else 1.0 + (c - 1) * 0.15)
			if sk.has("explode_radius") and aoe:
				n = maxf(n, 2.5)
			if int(sk.get("pierce", 0)) > 0 and aoe:
				n = maxf(n, 2.0)
		"ground_aoe", "nova", "zone", "leap":
			n = 3.0 if aoe else 1.0
			if b == "zone":
				n *= float(sk.get("duration", 4)) / float(sk.get("tick", 0.5)) * float(sk.get("tick_fraction", 0.35)) * 0.5
		"chain":
			n = minf(float(sk.get("chains", 3)) + 1.0, 3.0) if aoe else 1.0
		"melee_arc":
			if tags.has("area") or float(sk.get("arc", 120)) >= 150:
				n = 2.5 if aoe else 1.0
		"beam":
			n = 1.8 if aoe else 1.0
	return n

## Estimated sustained damage per second of a skill under a hypothetical setup.
func skill_dps(ch, sid: String, alloc, eq, f: Dictionary, aoe: bool) -> float:
	var sk: Dictionary = ch.resolved_skill(sid)
	if sk.is_empty() or not (sk.has("weapon_eff") or sk.has("base_damage")):
		return 0.0
	var w = (eq if eq != null else ch.equipment).get("main_hand")
	if not weapon_ok_for(sk, w):
		return 0.0
	var avg: float = ch.preview_skill_avg(sid, alloc, eq)
	var ut := use_time(sk, f)
	var cd := float(sk.get("cooldown", 0)) * f.get("cdr_mult", 1.0)
	return avg * targets_factor(sk, aoe) / maxf(ut, cd if cd > ut * 3.0 else ut)

func power(ch, eq = null, alloc = null) -> Dictionary:
	var al: Array = ch.allocated if alloc == null else alloc
	var f: Dictionary = ch.preview_final(al, eq)
	var dps := 0.0
	var skills: Array = main_skills if not main_skills.is_empty() else Data.classes[ch.class_id].get("start_skills", [])
	var i := 0
	for sid in skills:
		var d := skill_dps(ch, sid, al, eq, f, i == 1)
		dps = maxf(dps, d)
		i += 1
	var lvl: int = ch.level
	var hit := 10.0 * (1.0 + 0.13 * (lvl - 1)) * 1.3
	var phys := 1.0 - Combat.armour_reduction(f.get("armour", 0.0), hit)
	var ev := Combat.evade_chance(f.get("evasion", 0.0), lvl)
	var blk: float = f.get("block_chance", 0.0) / 100.0
	var phys_taken := phys * (1.0 - ev) * (1.0 - blk)
	var ele := 0.0
	for r in ["fire", "cold", "lightning"]:
		ele += (1.0 - clampf(f.get("res_" + r, 0.0), -100, 75) / 100.0) / 3.0
	ele *= 1.0 - blk * 0.5
	var vd := 1.0 - clampf(f.get("res_void", 0.0), -100, 75) / 100.0
	var taken := (0.5 * phys_taken + 0.4 * ele + 0.1 * vd) * (1.0 - minf(f.get("damage_reduction", 0.0), 75.0) / 100.0)
	var ehp: float = f.get("max_life", 1.0) / maxf(taken, 0.05)
	# sustain: regen / leech-ish stats count a little
	ehp *= 1.0 + minf(0.3, (f.get("life_regen", 0.0) * 4.0 + f.get("life_on_hit", 0.0) * 2.0 + f.get("life_on_kill", 0.0)) / maxf(1.0, f.get("max_life", 1.0)))
	var w: Array = WEIGHTS.get(build, [1.0, 1.0])
	var score: float = w[0] * log(dps + 1.0) + w[1] * log(ehp + 1.0) + 0.15 * log(maxf(30.0, f.get("move_speed", 100.0)))
	# mana: a skill you cannot afford is worth less
	if f.get("max_mana", 0.0) < 20.0:
		score -= 0.1
	return {"dps": dps, "ehp": ehp, "score": score, "life": f.get("max_life", 0.0)}

func score(ch, eq = null, alloc = null) -> float:
	return power(ch, eq, alloc)["score"]

func item_extra(it) -> float:
	## small preference for empty sockets (future gems) and item level as a tie-break
	if it == null:
		return 0.0
	var empty := 0
	var gl: Array = it.get("gems", [])
	for i in Loot.item_sockets(it):
		if i >= gl.size() or gl[i] == "":
			empty += 1
	return 0.006 * empty + 0.00005 * int(it.get("ilvl", 1))

func gear_power(ch) -> int:
	var pw := power(ch)
	return int(round(sqrt(maxf(0.0, pw["dps"]) * maxf(0.0, pw["ehp"]))))

# ================================================================== equipping
func _eq_with(ch, it: Dictionary, slot: String) -> Dictionary:
	var eq: Dictionary = ch.equipment.duplicate()
	eq[slot] = it
	if slot == "main_hand" and it.get("two_handed", false):
		var off = eq.get("off_hand")
		if off != null and not (off.get("category") == "quiver" and it.get("tags", []).has("bow")):
			eq["off_hand"] = null
	if slot == "off_hand":
		var mh = eq.get("main_hand")
		if mh != null and mh.get("two_handed", false) and not (it.get("category") == "quiver" and mh.get("tags", []).has("bow")):
			eq["main_hand"] = null
	return eq

func _slots_for(it: Dictionary) -> Array:
	var s: String = it.get("slot", "")
	if s == "ring":
		return ["ring1", "ring2"]
	return [s]

func _eq_extra(eq: Dictionary) -> float:
	var t := 0.0
	for s in eq:
		t += item_extra(eq[s])
	return t

## Equip the best bag items. Returns number of items equipped.
func equip_best(ch, min_gain: float = 0.004, quiet: bool = false) -> int:
	var n := 0
	var tried := {}
	for guard in 14:
		var base := score(ch) + _eq_extra(ch.equipment)
		var best_gain := min_gain
		var best_i := -1
		var best_slot := ""
		for i in ch.inventory.size():
			var it = ch.inventory[i]
			if it == null or ch.equip_restriction(it) != "" or tried.has(str(it.get("uid", i))):
				continue
			for s in _slots_for(it):
				var eq := _eq_with(ch, it, s)
				var g := score(ch, eq) + _eq_extra(eq) - base
				if g > best_gain:
					best_gain = g
					best_i = i
					best_slot = s
		if best_i < 0:
			break
		var it2: Dictionary = ch.inventory[best_i]
		var old = ch.equipment.get(best_slot)
		var why: String = ch.equip_from_bag(best_i, best_slot)
		tried[str(it2.get("uid", best_i))] = true
		if why == "":
			n += 1
			if not quiet:
				L("EQUIP %s <- %s %s (ilvl %d, %d sockets) replacing %s, score +%.3f" % [best_slot, it2.get("rarity", ""), it2.get("name", ""), int(it2.get("ilvl", 0)), Loot.item_sockets(it2), old.get("name", "-") if old != null else "nothing", best_gain])
	return n

## Mid-run: equip only an obvious upgrade (>= 3% better). Returns true if equipped.
func quick_upgrade(ch) -> bool:
	return equip_best(ch, 0.03) > 0

# ================================================================== selling / salvage
func _sell(ch, idx: int) -> void:
	## same as inventory_panel.sell() without the confirmation dialog
	var it = ch.inventory[idx]
	if it == null:
		return
	ch.reclaim_gems(it)
	ch.inventory[idx] = null
	ch.gold += Loot.sell_value(it)
	Game.vendor_stock.append(it)
	while Game.vendor_stock.size() > 16:
		Game.vendor_stock.pop_front()
	Events.inventory_changed.emit()
	Events.currency_changed.emit()

func _salvage(ch, idx: int) -> void:
	## same as inventory_panel.salvage() without the confirmation dialog
	var it = ch.inventory[idx]
	if it == null:
		return
	var y: Dictionary = Loot.salvage_yield(it)
	ch.reclaim_gems(it)
	ch.inventory[idx] = null
	for k in y:
		ch.add_material(k, int(y[k]))
	Events.inventory_changed.emit()

func clear_bag(ch) -> void:
	var sold := 0
	var salv := 0
	var gold0: int = ch.gold
	var keep := 0
	for i in ch.inventory.size():
		var it = ch.inventory[i]
		if it == null:
			continue
		var r := Data.rarity_index(it.get("rarity", "common"))
		# keep a few good items we cannot wear yet
		if int(it.get("req_level", 1)) > ch.level and int(it.get("req_level", 1)) <= ch.level + 4 and r >= 2 and keep < 6:
			keep += 1
			continue
		var do_salvage: bool = not flags.get("no_crafting", false) and (r >= 2 or (r == 1 and (int(ch.materials.get("scrap", 0)) < 30 or int(ch.materials.get("iron_fragment", 0)) < 10)))
		if do_salvage:
			_salvage(ch, i)
			salv += 1
		else:
			_sell(ch, i)
			sold += 1
	if sold + salv > 0:
		L("BAG sold %d (+%d gold), salvaged %d, kept %d" % [sold, ch.gold - gold0, salv, keep])

# ================================================================== crafting
func _try_craft(ch, op: String, it: Dictionary, ai: int, budget: Array) -> bool:
	if Loot.craft_check(op, it, ai) != "":
		return false
	var cost: Dictionary = Loot.craft_cost(op, it)
	if int(cost.get("gold", 0)) > budget[0] or not ch.has_materials(cost):
		return false
	if not ch.pay(cost):
		return false
	budget[0] -= int(cost.get("gold", 0))
	var before := score(ch)
	Loot.craft_apply(op, it, ai)
	ch.recalc()
	Events.inventory_changed.emit()
	L("CRAFT %s on %s (%s) cost %s, score %+.3f" % [Loot.craft_name(op), it.get("name", ""), it.get("slot", ""), Loot.cost_text(cost), score(ch) - before])
	return true

func _pouch_gems(ch) -> int:
	var n := 0
	for g in ch.gems:
		if Loot.gem_req(g) <= ch.level:
			n += int(ch.gems[g])
	return n

func _empty_sockets(ch) -> int:
	var n := 0
	for s in ch.equipment:
		var it = ch.equipment[s]
		if it == null:
			continue
		var gl: Array = it.get("gems", [])
		for i in Loot.item_sockets(it):
			if i >= gl.size() or gl[i] == "":
				n += 1
	return n

func craft(ch) -> void:
	if flags.get("no_crafting", false):
		return
	var budget := [int(ch.gold * 0.5)]
	var items := []
	for s in SLOT_ORDER:
		if ch.equipment.get(s) != null:
			items.append(ch.equipment[s])
	# 1. add sockets when we have gems waiting for them
	if not flags.get("no_gems", false):
		for it in items:
			if _pouch_gems(ch) > _empty_sockets(ch):
				_try_craft(ch, "socket", it, -1, budget)
	# 2. upgrade bases (weapon first)
	for it in items:
		_try_craft(ch, "upgrade", it, -1, budget)
	# 3. raise rarity, 4. add affixes
	for it in items:
		if it.get("rarity", "") in ["uncommon", "rare"]:
			_try_craft(ch, "rarity", it, -1, budget)
	for it in items:
		_try_craft(ch, "add", it, -1, budget)
	# 5. reroll the weakest affix of rare / epic gear
	for it in items:
		if not it.get("rarity", "") in ["rare", "epic"]:
			continue
		var affs: Array = it.get("affixes", [])
		if affs.is_empty():
			continue
		var full := score(ch)
		var worst := -1
		var worst_loss := INF
		for ai in affs.size():
			var a = affs[ai]
			affs.remove_at(ai)
			ch.recalc()
			var loss := full - score(ch)
			affs.insert(ai, a)
			if loss < worst_loss:
				worst_loss = loss
				worst = ai
		ch.recalc()
		if worst >= 0 and worst_loss < 0.006:
			_try_craft(ch, "reroll", it, worst, budget)

# ================================================================== vendor
func shop(ch) -> void:
	if Game.vendor_stock.is_empty():
		Game.refresh_vendor()     # what vendor_panel.on_open() does
	for guard in 3:
		var base := score(ch) + _eq_extra(ch.equipment)
		var best = null
		var best_gain := 0.02
		for it in Game.vendor_stock:
			if ch.equip_restriction(it) != "":
				continue
			var price := Loot.buy_value(it)
			if price > int(ch.gold * 0.6):
				continue
			for s in _slots_for(it):
				var eq := _eq_with(ch, it, s)
				var g := score(ch, eq) + _eq_extra(eq) - base
				if g > best_gain:
					best_gain = g
					best = it
		if best == null or ch.free_bag_slot() < 0:
			break
		var price2 := Loot.buy_value(best)
		ch.gold -= price2      # vendor_panel._on_click confirmed purchase
		Game.vendor_stock.erase(best)
		ch.add_to_bag(best)
		Events.currency_changed.emit()
		L("BUY %s %s for %d gold (expected score +%.3f)" % [best.get("rarity", ""), best.get("name", ""), price2, best_gain])
		equip_best(ch)

# ================================================================== gems
func gems(ch) -> void:
	if flags.get("no_gems", false):
		return
	# combine 3 -> next grade when the next grade is usable
	var changed := true
	while changed:
		changed = false
		var ids: Array = ch.gems.keys()
		ids.sort()
		for gid in ids:
			var t := Loot.gem_tier(gid)
			var tiers: Array = Data.gem_cfg.get("tiers", [])
			if t + 1 < tiers.size() and int(tiers[t + 1].get("req", 1)) <= ch.level and ch.can_combine(gid) == "" and ch.combine_cost(gid) <= int(ch.gold * 0.6):
				var e: String = ch.combine_gems(gid)
				if e == "":
					L("GEM combine 3x %s -> %s" % [gid, Loot.gem_id(gid.get_slice(":", 0), t + 1)])
					changed = true
					break
	# buy random gems when there are empty sockets and gold to spare
	var price := 30 + 10 * ch.level      # jeweller_panel.gem_price()
	var bought := 0
	while bought < 2 and _empty_sockets(ch) > _pouch_gems(ch) and ch.gold >= price * 3:
		ch.gold -= price
		var gid: String = Loot.random_gem(ch.level)
		ch.add_gem(gid)
		bought += 1
		L("GEM bought %s for %d gold" % [gid, price])
	socket_all(ch)

func socket_all(ch) -> void:
	if flags.get("no_gems", false):
		return
	for s in SLOT_ORDER:
		var it = ch.equipment.get(s)
		if it == null or Loot.item_sockets(it) == 0 or Loot.socket_category(it) == "":
			continue
		var gl: Array = it.get("gems", [])
		while gl.size() < Loot.item_sockets(it):
			gl.append("")
		it["gems"] = gl
		for idx in Loot.item_sockets(it):
			var cur: String = gl[idx]
			var base := score(ch)
			var best := ""
			var best_gain := 0.0
			for gid in ch.gems.keys():
				if Loot.gem_req(gid) > ch.level or int(ch.gems[gid]) <= 0:
					continue
				gl[idx] = gid
				ch.recalc()
				var g := score(ch) - base
				gl[idx] = cur
				if g > best_gain:
					best_gain = g
					best = gid
			ch.recalc()
			if best == "":
				continue
			if cur != "":
				if best_gain < 0.005 or ch.gold < ch.unsocket_cost(cur) * 2:
					continue
				if ch.unsocket_gem(it, idx) != "":
					continue
				L("GEM unsocket %s from %s" % [cur, it.get("name", "")])
			var e: String = ch.socket_gem(it, idx, best)
			if e == "":
				L("GEM socket %s into %s socket %d (score +%.3f)" % [best, s, idx + 1, best_gain])

# ================================================================== skills
static func role(sk: Dictionary) -> String:
	var b: String = sk.get("behavior", "")
	match b:
		"blink", "leap", "dash":
			return "mobility"
		"buff":
			if sk.get("tags", []).has("defence") or sk.has("heal_pct") or sk["id"] == "smoke_bomb":
				return "buff_def"
			return "buff_off"
		"summon":
			return "summon"
		"deploy":
			return "turret" if sk.get("deployable", "") == "turret" else "trap"
		"curse":
			return "curse" if not sk.has("base_damage") else "damage"
		"zone":
			return "zone" if sk.has("base_damage") else "zone_util"
		"nova":
			if not sk.get("damage", true):
				return "warcry"
	return "damage"

const ROLE_ORDER := {
	"warrior": ["st", "aoe", "buff_off", "buff_def", "mobility", "warcry", "buff_off", "damage"],
	"ranger": ["st", "aoe", "buff_off", "turret", "buff_def", "trap", "curse", "damage"],
	"mage": ["st", "aoe", "summon", "buff_off", "mobility", "curse", "zone", "damage"],
}

func choose_hotbar(ch) -> void:
	var f: Dictionary = ch.final
	var st := []
	var aoe := []
	var by_role := {}
	for sid in ch.unlocked_skills:
		var sk: Dictionary = ch.resolved_skill(sid)
		if sk.is_empty() or not weapon_ok_for(sk, ch.weapon()):
			continue
		var r := role(sk)
		if r == "damage" or r == "zone" or (r == "mobility" and (sk.has("weapon_eff") or sk.has("base_damage"))):
			var cost := float(sk.get("cost", 0)) * f.get("mana_cost_mult", 1.0)
			var ut := use_time(sk, f)
			var sustain := 1.0
			if cost / maxf(ut, 0.1) > f.get("mana_regen", 1.0) * 2.5:
				sustain = 0.6
			var cd := float(sk.get("cooldown", 0))
			var cdpen := 0.4 if cd > 3.0 else 1.0
			if r == "damage" or r == "zone":
				st.append([skill_dps(ch, sid, ch.allocated, null, f, false) * sustain * cdpen, sid])
				aoe.append([skill_dps(ch, sid, ch.allocated, null, f, true) * sustain * cdpen, sid])
		if not by_role.has(r):
			by_role[r] = []
		by_role[r].append([int(sk.get("unlock_level", 1)), sid])
	st.sort_custom(func(a, b): return a[0] > b[0])
	aoe.sort_custom(func(a, b): return a[0] > b[0])
	for r in by_role:
		by_role[r].sort_custom(func(a, b): return a[0] > b[0])    # newest (strongest) first
	var bar := []
	var order: Array = ROLE_ORDER.get(ch.class_id, ROLE_ORDER["warrior"])
	for r in order:
		if bar.size() >= ch.HOTBAR_SIZE:
			break
		var pick := ""
		if r == "st":
			for e in st:
				if not bar.has(e[1]) and e[0] > 0:
					pick = e[1]
					break
		elif r == "aoe":
			for e in aoe:
				if not bar.has(e[1]) and e[0] > 0:
					pick = e[1]
					break
		elif r == "damage":
			pass
		else:
			for e in by_role.get(r, []):
				if not bar.has(e[1]):
					pick = e[1]
					break
		if pick != "":
			bar.append(pick)
	# fill the rest with the next best damage skills
	for e in st:
		if bar.size() >= ch.HOTBAR_SIZE:
			break
		if not bar.has(e[1]) and e[0] > 0:
			bar.append(e[1])
	while bar.size() < ch.HOTBAR_SIZE:
		bar.append("")
	var old: Array = ch.loadout.duplicate()
	for i in ch.HOTBAR_SIZE:
		ch.loadout[i] = bar[i]       # skills_panel.assign()
	Events.loadout_changed.emit()
	main_skills = []
	for i in 2:
		if bar[i] != "":
			main_skills.append(bar[i])
	if old != ch.loadout:
		L("HOTBAR %s" % ", ".join(bar.filter(func(x): return x != "")))

func rune_value(rid: String, sk: Dictionary, slot: int) -> float:
	var base: float = [1.0, 0.9, 0.5, 0.5, 0.5, 0.5, 0.5][mini(slot, 6)]
	var b: String = sk.get("behavior", "")
	var r := role(sk)
	var dmg: bool = r == "damage" or r == "zone"
	var v := 0.0
	match rid:
		"split":
			v = (1.0 if int(sk.get("count", 1)) == 1 else 0.6) if dmg else 0.0
		"piercing":
			v = 0.6 if dmg else 0.0
		"chaining":
			v = 0.7 if dmg else 0.0
		"volatile":
			v = 0.6 if dmg else 0.0
		"concentrated":
			v = 0.6 if dmg and slot == 0 else 0.35
		"widened":
			v = 0.6 if dmg and slot == 1 else 0.3
		"echo":
			v = 0.8 if dmg else 0.0
		"haste":
			v = 0.8 if dmg else 0.2
		"efficiency":
			v = 0.6 if float(sk.get("cost", 0)) >= 8 else 0.3
		"recharge":
			v = 0.7
		"horde":
			v = 0.8
		"bone_frenzy":
			v = 0.5
		"longshot":
			v = 0.2
		"lingering":
			v = 0.6
		"concussive":
			v = 0.6 if dmg else 0.4
		_:
			v = 0.1     # elemental conversions: only if nothing better
	return base * v

func runes(ch) -> void:
	var pairs := []
	for rid in ch.runes:
		for i in ch.HOTBAR_SIZE:
			var sid: String = ch.loadout[i]
			if sid == "" or ch.rune_fits(rid, sid) != "":
				continue
			var v := rune_value(rid, Data.skills[sid], i)
			if v > 0.15:
				pairs.append([v, rid, sid])
	pairs.sort_custom(func(a, b): return a[0] > b[0])
	for pr in pairs:
		var sid: String = pr[2]
		if int(ch.runes.get(pr[1], 0)) <= 0 or ch.skill_runes.get(sid, []).size() >= ch.rune_sockets(sid):
			continue
		if ch.socket_rune(sid, pr[1]) == "":
			L("RUNE %s -> %s" % [pr[1], sid])

const SPECS := {
	"warrior": {"balanced": ["weapon_master", "weapon_master_6"], "glass": ["berserker", "berserker_6"], "defensive": ["juggernaut", "juggernaut_6"]},
	"ranger": {"balanced": ["deadeye", "deadeye_6"], "glass": ["deadeye", "deadeye_5"], "defensive": ["wraith_hunter", "wraith_hunter_6"]},
	"mage": {"balanced": ["", "_6"], "glass": ["", "_6"], "defensive": ["cryomancer", "cryomancer_6"]},
}

func spec(ch) -> void:
	if ch.level < ch.SPEC_LEVELS[0]:
		return
	var plan: Array = SPECS.get(ch.class_id, {}).get(build, ["", ""])
	var sid: String = plan[0]
	var cap: String = plan[1]
	if sid == "":
		# element of the main damage skill decides the mage specialisation
		var el := "fire"
		if not main_skills.is_empty():
			el = Data.skills.get(main_skills[0], {}).get("dmg_type", "fire")
		sid = {"fire": "pyromancer", "cold": "cryomancer", "lightning": "stormcaller"}.get(el, "arcanist")
		cap = sid + cap
	if ch.spec_id == "":
		if ch.choose_spec(sid) == "":
			L("SPEC chose %s" % sid)
	if ch.spec_id == "":
		return
	var order := [ch.spec_id + "_1", ch.spec_id + "_2", ch.spec_id + "_3", ch.spec_id + "_4", cap]
	for n in order:
		if ch.spec_points_available() <= 0:
			break
		if ch.spec_nodes.has(n):
			continue
		if ch.alloc_spec(n):
			L("SPEC node %s" % n)

# ================================================================== full visit
func passives(ch) -> void:
	if flags.get("no_passives", false):
		return
	for line in planner.spend(ch, build):
		L(line)

## Everything a player does in town between runs.
func town_visit(ch) -> void:
	choose_hotbar(ch)
	passives(ch)
	spec(ch)
	equip_best(ch)
	clear_bag(ch)
	shop(ch)
	craft(ch)
	gems(ch)
	equip_best(ch)
	clear_bag(ch)
	choose_hotbar(ch)
	runes(ch)
	ch.flask_charges = [3.0, 3.0]

## On level-up inside a dungeon: passive points and spec points only.
func on_level_up(ch) -> void:
	passives(ch)
	spec(ch)
