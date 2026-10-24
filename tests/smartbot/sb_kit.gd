extends RefCounted
## Entry-kit generator: a plausible character for a tier and level, as a competent
## player would have it after farming the previous tiers. NOT min-maxed:
##  - each slot gets the best of KIT_CHOICES natural drops (Loot.roll_item, normal rarity
##    rolls with half the tier's rarity bonus) at item level L-4..L
##  - gems, runes, gold and materials in amounts proportional to level
##  - earlier tiers' bosses counted as killed (first-kill passive points granted)
##  - then a normal town visit (hotbar, passives, spec, crafting, gems, runes)

const KIT_CHOICES := 3

var hub = null

func default_level(tier: int) -> int:
	var d := _dungeon_for_tier(tier)
	return int(d.get("min_level", 1)) + 3

func _dungeon_for_tier(tier: int) -> Dictionary:
	for d in Data.dungeon_list:
		if int(d.get("tier", 1)) == tier:
			return d
	return Data.dungeon_list[0]

func _roll_for_slot(ch, slot: String, lvl: int, rarity_bonus: float, rng: RandomNumberGenerator) -> Dictionary:
	var want: String = "ring" if slot.begins_with("ring") else slot
	for i in 600:
		var il := clampi(lvl - rng.randi_range(0, 4), 1, 99)
		var it: Dictionary = Loot.roll_item(il, rarity_bonus, ch.class_id)
		if it.is_empty() or it.get("slot", "") != want:
			continue
		if ch.equip_restriction(it) != "":
			continue
		return it
	return {}

func make(cls: String, tier: int, lvl: int, rng: RandomNumberGenerator) -> Dictionary:
	Game.new_character(cls)
	var ch = Game.ch
	var d := _dungeon_for_tier(tier)
	ch.level = maxi(1, lvl)
	ch.xp = 0
	ch.progress["highest_tier"] = mini(6, maxi(1, tier))
	# earlier tiers: bosses were killed once (first-kill passive point each)
	for od in Data.dungeon_list:
		if int(od.get("tier", 1)) < tier:
			ch.progress["bosses_killed"][od["id"]] = 1
			ch.bonus_passive_points += 1
	ch.progress["runs"] = maxi(0, (tier - 1) * 4)
	ch.refresh_unlocks(false)
	hub.choose_hotbar(ch)
	ch.recalc()
	# gear: best of a few natural drops per slot
	var rb := float(d.get("rarity_bonus", 0)) * 0.5
	var order := ["main_hand", "off_hand", "chest", "helmet", "gloves", "boots", "belt", "amulet", "ring1", "ring2", "charm"]
	for slot in order:
		if slot == "off_hand":
			var mh = ch.equipment.get("main_hand")
			if mh != null and mh.get("two_handed", false) and not mh.get("tags", []).has("bow"):
				continue
		var best = null
		var best_s := -INF
		for k in KIT_CHOICES:
			var it: Dictionary = _roll_for_slot(ch, slot, ch.level, rb, rng)
			if it.is_empty():
				continue
			it["uid"] = ch.take_uid()
			var eq: Dictionary = hub._eq_with(ch, it, slot)
			var s: float = hub.score(ch, eq) + hub.item_extra(it)
			if s > best_s:
				best_s = s
				best = it
		if best != null:
			var cur = ch.equipment.get(slot)
			var cur_s: float = hub.score(ch) + hub.item_extra(cur)
			if cur == null or best_s > cur_s:
				var eq2: Dictionary = hub._eq_with(ch, best, slot)
				for s2 in eq2:
					ch.equipment[s2] = eq2[s2]
				ch.recalc()
	# starting items left over go to the bag (sold in the town visit)
	for i in ch.inventory.size():
		ch.inventory[i] = null
	# currencies proportional to level
	var L: int = ch.level
	ch.gold = 25 + 30 * L
	ch.materials = {"scrap": 2 * L, "iron_fragment": int(L / 2.0), "arcane_dust": int(L / 5.0), "monster_core": int(L / 10.0),
		"elemental_essence": int(L / 15.0), "catalyst": int(L / 20.0)}
	for i in int(L / 3.0):
		ch.add_gem(Loot.random_gem(L))
	for i in int(L / 6.0):
		ch.add_rune(Loot.random_rune())
	ch.recalc()
	hub.town_visit(ch)
	return {"level": ch.level, "gear_power": hub.gear_power(ch)}
