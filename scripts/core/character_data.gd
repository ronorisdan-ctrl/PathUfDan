extends RefCounted
## Persistent character state: class, level, passives, items, currency, skills.
## Also resolves the final StatBlock from every source.

const StatBlock = preload("res://scripts/core/stat_block.gd")
const PetRules = preload("res://scripts/core/pet_rules.gd")
const StashRules = preload("res://scripts/core/stash_rules.gd")

const SAVE_VERSION := 3   # 2: adds the pets block; 3: stash tabs (stash_extra_tabs)
const BAG_SIZE := 40
const EQUIP_SLOTS := ["main_hand", "off_hand", "helmet", "chest", "gloves", "boots", "belt", "amulet", "ring1", "ring2", "charm"]
const HOTBAR_SIZE := 7
const MAX_SKILL_LEVEL := 20
const MAX_LEVEL := 60

var char_name := "Dan"
var class_id := "warrior"
var level := 1
var xp := 0
var passive_points := 0
var bonus_passive_points := 0
var allocated := []
var inventory := []
var stash := []
var stash_extra_tabs := 0   # extra stash tabs bought with gold (the first tab is free)
var equipment := {}
var gold := 0
var materials := {}
var loadout := ["", "", "", "", "", "", ""]
var unlocked_skills := []
var flask_charges := [3.0, 3.0]
var runes := {}             # rune id -> count (unsocketed)
var gems := {}              # gem id ("ruby:1") -> count (unsocketed)
var skill_runes := {}       # skill id -> [rune ids]
var spec_id := ""
var spec_nodes := []
var progress := {"bosses_killed": {}, "runs": 0, "deaths": 0, "highest_tier": 1}
var next_uid := 1
var pets := {}              # pet id -> {"tier": int, "name": String}; upgrades belong to each pet
var active_pet := ""        # which owned pet follows you ("" = none)
var dev_used := false       # set by developer tools that change progress; shown as "(dev)" in the load menu

# runtime (not saved)
var stats = null          # StatBlock
var active_buffs := []    # set by the player so every recalc includes temporary buffs
var final := {}           # resolved numbers used by gameplay

func _init() -> void:
	inventory.resize(BAG_SIZE)
	stash.resize(StashRules.total_slots(Data.stash_cfg, 0, false))
	for s in EQUIP_SLOTS:
		equipment[s] = null

func class_def() -> Dictionary:
	return Data.classes.get(class_id, {})

# ---------------------------------------------------------------- creation
func setup_new(cls: String, nm: String = "Dan") -> void:
	class_id = cls
	char_name = nm
	var cd := class_def()
	allocated = [cd.get("start_passive", "")]
	for base_id in cd.get("start_items", []):
		var it = Loot.make_item(base_id, "common", 1)
		if it.is_empty():
			continue
		it["uid"] = take_uid()
		var slot := slot_for(it)
		if slot != "" and equipment.get(slot) == null:
			equipment[slot] = it
		else:
			add_to_bag(it)
	var hp = Loot.make_item("leather_belt", "common", 1)
	hp["uid"] = take_uid()
	add_to_bag(hp)
	refresh_unlocks(false)
	var ss: Array = cd.get("start_skills", [])
	for i in ss.size():
		loadout[i] = ss[i]
	gold = 25
	recalc()

func take_uid() -> int:
	next_uid += 1
	return next_uid

# ---------------------------------------------------------------- progression
## XP needed to go from level l to l + 1.
static func xp_for_level(l: int) -> int:
	return int(round(60.0 * pow(l, 1.55) + 40.0 * l))

func xp_to_next() -> int:
	return xp_for_level(level)

func add_xp(amount: int) -> void:
	xp += amount
	var leveled := false
	while xp >= xp_to_next() and level < MAX_LEVEL:
		xp -= xp_to_next()
		level += 1
		passive_points += 1
		leveled = true
		Events.player_leveled.emit(level)
	if leveled:
		refresh_unlocks(true)
		recalc()
	Events.xp_changed.emit()

func total_passive_points() -> int:
	return (level - 1) + bonus_passive_points

func spent_passive_points() -> int:
	var t := 0
	for id in allocated:
		t += int(Data.passives.get(id, {}).get("cost", 1))
	return t

func available_passive_points() -> int:
	return total_passive_points() - spent_passive_points()

func refresh_unlocks(announce: bool) -> void:
	for s in Data.skills_for_class(class_id):
		if int(s.get("unlock_level", 1)) <= level and not unlocked_skills.has(s["id"]):
			unlocked_skills.append(s["id"])
			if announce:
				Events.skill_unlocked.emit(s["id"])
				# auto-slot into the first empty hotbar slot
				for i in HOTBAR_SIZE:
					if loadout[i] == "":
						loadout[i] = s["id"]
						Events.loadout_changed.emit()
						break

func skill_level(skill_id: String) -> int:
	var sd: Dictionary = Data.skills.get(skill_id, {})
	var lvl := 1 + int(floor(float(level - int(sd.get("unlock_level", 1))) / 2.0))
	if stats != null:
		lvl += int(stats.value("skill_level"))
	return clampi(lvl, 1, MAX_SKILL_LEVEL)

# ---------------------------------------------------------------- passives
func can_allocate(node_id: String) -> String:
	## returns "" if allowed, otherwise the reason
	if allocated.has(node_id):
		return "Already allocated"
	var n: Dictionary = Data.passives.get(node_id, {})
	if n.is_empty():
		return "Unknown node"
	if n.get("type") == "start":
		return "Starting points cannot be allocated"
	if int(n.get("cost", 1)) > available_passive_points():
		return "Not enough passive points"
	for l in n.get("links", []):
		if allocated.has(l):
			return ""
	return "Must connect to an allocated node"

func allocate(node_id: String) -> bool:
	if can_allocate(node_id) != "":
		return false
	allocated.append(node_id)
	recalc()
	Events.passive_changed.emit()
	return true

## Shortest chain of unallocated nodes that connects node_id to the
## allocated web (ending with node_id). Empty if unreachable.
func path_to(node_id: String) -> Array:
	if allocated.has(node_id) or not Data.passives.has(node_id):
		return []
	var prev := {node_id: ""}
	var queue := [node_id]
	var qi := 0
	while qi < queue.size():
		var cur: String = queue[qi]
		qi += 1
		for l in Data.passives[cur].get("links", []):
			if prev.has(l):
				continue
			if allocated.has(l):
				var path := [cur]
				var c: String = cur
				while prev[c] != "":
					c = prev[c]
					path.append(c)
				return path   # nearest-to-web first, target last
			var ln: Dictionary = Data.passives[l]
			if ln.get("type") in ["start", "keystone"]:
				continue
			prev[l] = cur
			queue.append(l)
	return []

func path_cost(path: Array) -> int:
	var c := 0
	for id in path:
		c += int(Data.passives[id].get("cost", 1))
	return c

func allocate_path(node_id: String) -> bool:
	var path := path_to(node_id)
	if path.is_empty() or path_cost(path) > available_passive_points():
		return false
	for id in path:
		allocated.append(id)
	recalc()
	Events.passive_changed.emit()
	return true

func refund_cost() -> int:
	return 10 + level * 6

func can_refund(node_id: String) -> String:
	if not allocated.has(node_id):
		return "Not allocated"
	var n: Dictionary = Data.passives.get(node_id, {})
	if n.get("type") == "start":
		return "Cannot refund a starting point"
	if gold < refund_cost():
		return "Refunding costs %d gold" % refund_cost()
	# every remaining node must still connect back to the class start
	var remaining := allocated.duplicate()
	remaining.erase(node_id)
	var start: String = class_def().get("start_passive", "")
	var seen := {start: true}
	var queue := [start]
	while queue.size() > 0:
		var cur = queue.pop_back()
		for l in Data.passives.get(cur, {}).get("links", []):
			if remaining.has(l) and not seen.has(l):
				seen[l] = true
				queue.append(l)
	for r in remaining:
		if not seen.has(r):
			return "Would disconnect other passives"
	return ""

func refund(node_id: String) -> bool:
	if can_refund(node_id) != "":
		return false
	gold -= refund_cost()
	allocated.erase(node_id)
	recalc()
	Events.passive_changed.emit()
	Events.currency_changed.emit()
	return true

# ---------------------------------------------------------------- skill runes
## Runes socket into a skill and change how it behaves (data/skill_runes.json).
func rune_sockets(skill_id: String) -> int:
	var lvl := skill_level(skill_id)
	return 1 + (1 if lvl >= 6 else 0) + (1 if lvl >= 12 else 0)

func rune_fits(rune_id: String, skill_id: String) -> String:
	var r: Dictionary = Data.skill_runes.get(rune_id, {})
	var sk: Dictionary = Data.skills.get(skill_id, {})
	if r.is_empty() or sk.is_empty():
		return "Unknown"
	var ok := false
	var ap: Array = r.get("applies", [])
	if ap.has("any") or ap.has(sk.get("behavior", "")):
		ok = true
	for t in r.get("applies_tag", []):
		if sk.get("tags", []).has(t):
			ok = true
	if not ok:
		return "Does not fit this skill"
	match r.get("requires", ""):
		"cooldown":
			if float(sk.get("cooldown", 0)) <= 0:
				return "Skill has no cooldown"
		"range":
			if not sk.has("range"):
				return "Skill has no range to extend"
		"damage":
			if not (sk.has("weapon_eff") or sk.has("base_damage")):
				return "Skill deals no direct damage"
	if skill_runes.get(skill_id, []).has(rune_id):
		return "Already socketed in this skill"
	return ""

func socket_rune(skill_id: String, rune_id: String) -> String:
	var why := rune_fits(rune_id, skill_id)
	if why != "":
		return why
	if int(runes.get(rune_id, 0)) <= 0:
		return "You have no such rune"
	var cur: Array = skill_runes.get(skill_id, [])
	if cur.size() >= rune_sockets(skill_id):
		return "No free rune socket"
	cur.append(rune_id)
	skill_runes[skill_id] = cur
	runes[rune_id] = int(runes[rune_id]) - 1
	if runes[rune_id] <= 0:
		runes.erase(rune_id)
	Events.loadout_changed.emit()
	return ""

func unsocket_rune(skill_id: String, idx: int) -> void:
	var cur: Array = skill_runes.get(skill_id, [])
	if idx < 0 or idx >= cur.size():
		return
	var r: String = cur[idx]
	cur.remove_at(idx)
	skill_runes[skill_id] = cur
	runes[r] = int(runes.get(r, 0)) + 1
	Events.loadout_changed.emit()

func add_rune(rune_id: String, n: int = 1) -> void:
	runes[rune_id] = int(runes.get(rune_id, 0)) + n
	Events.currency_changed.emit()

# ---------------------------------------------------------------- gems
func add_gem(gid: String, n: int = 1) -> void:
	if not Loot.gem_valid(gid):
		return
	gems[gid] = int(gems.get(gid, 0)) + n
	Events.currency_changed.emit()

func _take_gem(gid: String) -> bool:
	if int(gems.get(gid, 0)) <= 0:
		return false
	gems[gid] = int(gems[gid]) - 1
	if gems[gid] <= 0:
		gems.erase(gid)
	return true

## Gems in an item that is sold, salvaged or destroyed go back to the pouch.
func reclaim_gems(it) -> void:
	if it == null:
		return
	for g in it.get("gems", []):
		if g != "":
			add_gem(g)
	it["gems"] = []
	it["sockets"] = int(it.get("sockets", 0))

func is_equipped(it) -> bool:
	for s in equipment:
		if equipment[s] == it:
			return true
	return false

func socket_gem(it: Dictionary, idx: int, gid: String) -> String:
	if idx < 0 or idx >= Loot.item_sockets(it):
		return "No such socket"
	if Loot.socket_category(it) == "":
		return "This item cannot hold gems"
	var gl: Array = it.get("gems", [])
	while gl.size() < Loot.item_sockets(it):
		gl.append("")
	it["gems"] = gl
	if gl[idx] != "":
		return "Socket is occupied"
	if level < Loot.gem_req(gid):
		return "Requires level %d" % Loot.gem_req(gid)
	if not _take_gem(gid):
		return "You have no such gem"
	gl[idx] = gid
	if is_equipped(it):
		recalc()
	Events.inventory_changed.emit()
	Events.currency_changed.emit()
	return ""

func unsocket_cost(gid: String) -> int:
	var c: Array = Data.gem_cfg.get("unsocket_gold", [10])
	return int(c[mini(Loot.gem_tier(gid), c.size() - 1)])

func unsocket_gem(it: Dictionary, idx: int) -> String:
	var gl: Array = it.get("gems", [])
	if idx < 0 or idx >= gl.size() or gl[idx] == "":
		return "Socket is empty"
	var gid: String = gl[idx]
	var cost := unsocket_cost(gid)
	if gold < cost:
		return "Need %d gold" % cost
	gold -= cost
	gl[idx] = ""
	add_gem(gid)
	if is_equipped(it):
		recalc()
	Events.inventory_changed.emit()
	return ""

func combine_cost(gid: String) -> int:
	var c: Array = Data.gem_cfg.get("combine_gold", [])
	var t := Loot.gem_tier(gid)
	return int(c[t]) if t < c.size() else -1

func can_combine(gid: String) -> String:
	var t := Loot.gem_tier(gid)
	if t + 1 >= Data.gem_cfg.get("tiers", []).size():
		return "Already the highest grade"
	if int(gems.get(gid, 0)) < 3:
		return "Needs 3 gems"
	if gold < combine_cost(gid):
		return "Need %d gold" % combine_cost(gid)
	return ""

func combine_gems(gid: String) -> String:
	var why := can_combine(gid)
	if why != "":
		return why
	gold -= combine_cost(gid)
	for i in 3:
		_take_gem(gid)
	add_gem(Loot.gem_id(gid.get_slice(":", 0), Loot.gem_tier(gid) + 1))
	return ""

## The skill definition with its socketed runes applied.
func resolved_skill(skill_id: String) -> Dictionary:
	var base: Dictionary = Data.skills.get(skill_id, {})
	var rl: Array = skill_runes.get(skill_id, [])
	if base.is_empty() or rl.is_empty():
		return base
	var sk: Dictionary = base.duplicate(true)
	var names := []
	for rid in rl:
		var r: Dictionary = Data.skill_runes.get(rid, {})
		names.append(r.get("name", rid))
		for m in r.get("mods", []):
			var key: String = m[0]
			var op: String = m[1]
			var v = m[2]
			match op:
				"add":
					sk[key] = float(sk.get(key, 0)) + float(v)
				"mult":
					if key == "area":
						for k2 in ["radius", "range", "explode_radius"]:
							if sk.has(k2):
								sk[k2] = float(sk[k2]) * float(v)
					elif key in ["damage_mult", "minion_speed_mult", "minion_life_mult"]:
						sk[key] = float(sk.get(key, 1.0)) * float(v)
					elif sk.has(key):
						sk[key] = float(sk[key]) * float(v)
				"max":
					sk[key] = maxf(float(sk.get(key, 0)), float(v))
				"set":
					sk[key] = v
	sk["rune_names"] = names
	return sk

# ---------------------------------------------------------------- specialisation
const SPEC_LEVELS := [12, 20, 28, 36, 44]

func spec_points_total() -> int:
	var n := 0
	for l in SPEC_LEVELS:
		if level >= l:
			n += 1
	return n

func spec_points_available() -> int:
	return spec_points_total() - spec_nodes.size()

func choose_spec(id: String) -> String:
	var sp: Dictionary = Data.specs.get(id, {})
	if sp.is_empty() or sp.get("class") != class_id:
		return "Not a specialisation of your class"
	if spec_id != "":
		return "Reset your current specialisation first"
	if level < SPEC_LEVELS[0]:
		return "Specialisations unlock at level %d" % SPEC_LEVELS[0]
	spec_id = id
	recalc()
	Events.passive_changed.emit()
	return ""

func can_alloc_spec(node_id: String) -> String:
	var n: Dictionary = Data.spec_nodes.get(node_id, {})
	if n.is_empty() or n.get("spec") != spec_id:
		return "Not part of your specialisation"
	if spec_nodes.has(node_id):
		return "Already allocated"
	if spec_points_available() <= 0:
		return "No specialisation points (next at level %d)" % _next_spec_level()
	var req: Array = n.get("req", [])
	if req.size() > 0:
		var ok := false
		for r in req:
			if spec_nodes.has(r):
				ok = true
		if not ok:
			return "Requires a connected node"
	if n.get("capstone", false):
		for other in spec_nodes:
			if Data.spec_nodes.get(other, {}).get("capstone", false):
				return "Only one capstone can be chosen"
	return ""

func _next_spec_level() -> int:
	for l in SPEC_LEVELS:
		if level < l:
			return l
	return 99

func alloc_spec(node_id: String) -> bool:
	if can_alloc_spec(node_id) != "":
		return false
	spec_nodes.append(node_id)
	recalc()
	Events.passive_changed.emit()
	return true

func spec_reset_cost() -> int:
	return 40 * level

func reset_spec() -> String:
	if spec_id == "":
		return "No specialisation chosen"
	if gold < spec_reset_cost():
		return "Resetting costs %d gold" % spec_reset_cost()
	gold -= spec_reset_cost()
	spec_id = ""
	spec_nodes.clear()
	recalc()
	Events.passive_changed.emit()
	Events.currency_changed.emit()
	return ""

# ---------------------------------------------------------------- inventory
func free_bag_slot() -> int:
	for i in inventory.size():
		if inventory[i] == null:
			return i
	return -1

func bag_free_count() -> int:
	var c := 0
	for i in inventory:
		if i == null:
			c += 1
	return c

func add_to_bag(item: Dictionary) -> bool:
	var i := free_bag_slot()
	if i < 0:
		return false
	inventory[i] = item
	Events.inventory_changed.emit()
	return true

func add_material(id: String, n: int) -> void:
	materials[id] = int(materials.get(id, 0)) + n
	Events.currency_changed.emit()

func has_materials(cost: Dictionary) -> bool:
	for k in cost:
		if k == "gold":
			if gold < int(cost[k]):
				return false
		elif int(materials.get(k, 0)) < int(cost[k]):
			return false
	return true

func pay(cost: Dictionary) -> bool:
	if not has_materials(cost):
		return false
	for k in cost:
		if k == "gold":
			gold -= int(cost[k])
		else:
			materials[k] = int(materials.get(k, 0)) - int(cost[k])
	Events.currency_changed.emit()
	return true

func slot_for(item: Dictionary) -> String:
	var s: String = item.get("slot", "")
	if s == "ring":
		if equipment.get("ring1") == null:
			return "ring1"
		if equipment.get("ring2") == null:
			return "ring2"
		return "ring1"
	return s

func equip_restriction(item: Dictionary) -> String:
	## "" when the item can be equipped by this character
	if item.is_empty():
		return "No item"
	if int(item.get("req_level", 1)) > level:
		return "Requires level %d" % int(item.get("req_level", 1))
	var cd := class_def()
	var cat: String = item.get("category", "")
	var slot: String = item.get("slot", "")
	if slot == "main_hand" or slot == "off_hand":
		if not cd.get("weapon_types", []).has(cat):
			return "%s cannot use %s" % [cd.get("name", ""), cat.capitalize() + "s"]
	var at: String = item.get("armour_type", "")
	if at != "" and not cd.get("armour_types", []).has(at):
		return "%s cannot wear %s armour" % [cd.get("name", ""), at]
	return ""

func is_two_handed(item) -> bool:
	return item != null and item.get("two_handed", false)

## Equip the bag item at index. Returns "" on success or an error string.
func equip_from_bag(index: int, force_slot: String = "") -> String:
	var item = inventory[index]
	if item == null:
		return "Empty"
	var why := equip_restriction(item)
	if why != "":
		return why
	var slot := force_slot if force_slot != "" else slot_for(item)
	var to_bag := []
	var main = equipment.get("main_hand")
	if slot == "main_hand" and is_two_handed(item):
		var off = equipment.get("off_hand")
		if off != null and not (off.get("category") == "quiver" and item.get("tags", []).has("bow")):
			to_bag.append("off_hand")
	if slot == "off_hand" and is_two_handed(main):
		if not (item.get("category") == "quiver" and main.get("tags", []).has("bow")):
			to_bag.append("main_hand")
	# space check: the swapped-out item takes the vacated bag slot, extras need room
	var needed := to_bag.size()
	if equipment.get(slot) == null:
		needed -= 1
	if needed > bag_free_count():
		return "Not enough bag space"
	var old = equipment.get(slot)
	equipment[slot] = item
	inventory[index] = old
	for s in to_bag:
		var it = equipment[s]
		equipment[s] = null
		if inventory[index] == null:
			inventory[index] = it
		else:
			add_to_bag(it)
	recalc()
	Events.inventory_changed.emit()
	return ""

func unequip(slot: String) -> bool:
	var it = equipment.get(slot)
	if it == null:
		return false
	var i := free_bag_slot()
	if i < 0:
		return false
	inventory[i] = it
	equipment[slot] = null
	recalc()
	Events.inventory_changed.emit()
	return true

func sort_bag() -> void:
	var items := []
	for it in inventory:
		if it != null:
			items.append(it)
	items.sort_custom(func(a, b):
		var ra := Data.rarity_index(a.get("rarity", "common"))
		var rb := Data.rarity_index(b.get("rarity", "common"))
		if ra != rb:
			return ra > rb
		if a.get("slot", "") != b.get("slot", ""):
			return a.get("slot", "") < b.get("slot", "")
		return int(a.get("ilvl", 0)) > int(b.get("ilvl", 0)))
	for i in inventory.size():
		inventory[i] = items[i] if i < items.size() else null
	Events.inventory_changed.emit()

## Locked items can't be sold, salvaged or destroyed. The flag lives on the item dictionary
## (so it is saved, stashed and withdrawn with it) and is only written while true.
static func is_locked(it) -> bool:
	return it != null and typeof(it) == TYPE_DICTIONARY and bool(it.get("locked", false))

func set_item_locked(it, locked: bool) -> void:
	if it == null:
		return
	if locked:
		it["locked"] = true
	else:
		it.erase("locked")
	Events.inventory_changed.emit()

## Bag slot indices holding an unlocked item of `rarity` or lower (equipped gear is not in the bag).
func bag_slots_up_to(rarity: String) -> Array:
	var limit: int = Data.rarity_index(rarity)
	var out := []
	for i in inventory.size():
		var it = inventory[i]
		if it != null and not is_locked(it) and Data.rarity_index(it.get("rarity", "common")) <= limit:
			out.append(i)
	return out

## Locked items of `rarity` or lower that a sweep leaves alone.
func bag_locked_up_to(rarity: String) -> int:
	var limit: int = Data.rarity_index(rarity)
	var n := 0
	for it in inventory:
		if it != null and is_locked(it) and Data.rarity_index(it.get("rarity", "common")) <= limit:
			n += 1
	return n

## How many of those are upgraded (so the confirm dialog can warn about them).
func bag_upgraded_up_to(rarity: String) -> int:
	var n := 0
	for i in bag_slots_up_to(rarity):
		if int(inventory[i].get("upgrade", 0)) > 0:
			n += 1
	return n

## Destroys every bag item of `rarity` or lower. Socketed gems return to the pouch.
## Returns the number of items destroyed.
func destroy_bag_up_to(rarity: String) -> int:
	var idxs := bag_slots_up_to(rarity)
	for i in idxs:
		reclaim_gems(inventory[i])
		inventory[i] = null
	if not idxs.is_empty():
		Events.inventory_changed.emit()
	return idxs.size()

func weapon():
	return equipment.get("main_hand")

func weapon_groups() -> Array:
	## tags used for skill weapon requirements
	var w = weapon()
	if w == null:
		return ["unarmed", "melee"]
	var g: Array = [w.get("category", "")]
	var tags: Array = w.get("tags", [])
	if tags.has("melee_weapon"):
		g.append("melee")
	if tags.has("ranged_weapon"):
		g.append("ranged")
	if tags.has("caster_weapon"):
		g.append("caster")
	if tags.has("bow"):
		g.append("bow")
	if tags.has("firearm"):
		g.append("firearm")
	return g

func has_shield() -> bool:
	var o = equipment.get("off_hand")
	return o != null and o.get("category") == "shield"

# ---------------------------------------------------------------- stats
func recalc(buffs = null) -> void:
	if buffs != null:
		active_buffs = buffs
	stats = build_stats(allocated, active_buffs)
	final = resolve(stats)
	Events.stats_changed.emit()

func build_stats(passive_ids: Array, buffs: Array = [], equip_override = null):
	var sb = StatBlock.new()
	var cd := class_def()
	for k in cd.get("base_attributes", {}):
		sb.add(k, "flat", float(cd["base_attributes"][k]), "base")
	for k in cd.get("per_level", {}):
		sb.add(k, "flat", float(cd["per_level"][k]) * (level - 1), "level")
	var bs: Dictionary = cd.get("base_stats", {})
	for k in bs:
		sb.add(k, "flat", float(bs[k]), "base")
	sb.add("max_life", "flat", float(cd.get("life_per_level", 8)) * (level - 1), "level")
	sb.add("max_mana", "flat", float(cd.get("mana_per_level", 3)) * (level - 1), "level")
	var eq: Dictionary = equipment if equip_override == null else equip_override
	for slot in eq:
		var it = eq[slot]
		if it == null:
			continue
		if equip_restriction(it) != "":
			continue  # items whose requirements are no longer met give nothing
		for m in Loot.item_mods(it):
			sb.add_mod(m, "equipment")
		if it.get("legendary_effect", "") != "":
			sb.add_flag(it["legendary_effect"])
	for sn in spec_nodes:
		var nd: Dictionary = Data.spec_nodes.get(sn, {})
		for m in nd.get("mods", []):
			sb.add_mod(m, "specialisation")
		for f in nd.get("flags", []):
			sb.add_flag(f)
	for pid in passive_ids:
		var n: Dictionary = Data.passives.get(pid, {})
		for m in n.get("mods", []):
			sb.add_mod(m, "passive")
		for f in n.get("flags", []):
			sb.add_flag(f)
	for b in buffs:
		for m in b.get("mods", []):
			sb.add_mod(m, "buff")
	# attributes feed derived stats
	var ae: Dictionary = Data.attributes.get("effects", {})
	for attr in ae:
		var a: float = sb.value(attr)
		for e in ae[attr]:
			sb.add(e["stat"], e["type"], a * float(e["per"]), "attribute")
	return sb

func resolve(sb, equip_override = null) -> Dictionary:
	var eqd: Dictionary = equipment if equip_override == null else equip_override
	var f := {}
	for a in ["str", "dex", "int", "vit", "agi", "wil"]:
		f[a] = sb.value(a)
	f["max_life"] = maxf(1.0, round(sb.value("max_life")))
	f["max_mana"] = maxf(0.0, round(sb.value("max_mana")))
	f["life_regen"] = sb.value("life_regen")
	f["mana_regen"] = sb.value("mana_regen")
	f["armour"] = round(sb.value("armour"))
	f["evasion"] = round(sb.value("evasion"))
	f["block_chance"] = clampf(sb.value("block_chance"), 0, 75)
	f["damage_reduction"] = clampf(sb.value("damage_reduction"), 0, 60)
	for r in ["fire", "cold", "lightning", "arcane", "void"]:
		f["res_" + r] = clampf(sb.value("res_" + r), -100, 75)
	f["move_speed"] = sb.value("move_speed")
	f["attack_speed_mult"] = maxf(0.2, 1.0 + sb.inc("attack_speed") / 100.0) * sb.more("attack_speed")
	f["cast_speed_mult"] = maxf(0.2, 1.0 + sb.inc("cast_speed") / 100.0) * sb.more("cast_speed")
	f["cdr_mult"] = 1.0 / maxf(0.2, 1.0 + sb.inc("cooldown_recovery") / 100.0)
	f["mana_cost_mult"] = maxf(0.1, 1.0 + sb.inc("mana_cost") / 100.0)
	f["minion_limit"] = int(sb.value("minion_limit"))
	f["turret_limit"] = int(sb.value("turret_limit"))
	f["projectile_count"] = int(sb.value("projectile_count"))
	f["pierce"] = int(sb.value("pierce"))
	f["chain"] = int(sb.value("chain"))
	f["area_mult"] = maxf(0.3, 1.0 + sb.inc("area") / 100.0)
	f["life_on_kill"] = sb.value("life_on_kill")
	f["mana_on_kill"] = sb.value("mana_on_kill")
	f["life_on_hit"] = sb.value("life_on_hit")
	f["item_rarity"] = sb.inc("item_rarity")
	f["flask_mult"] = 1.0 + sb.inc("flask_effect") / 100.0
	var w = eqd.get("main_hand")
	if w != null and equip_restriction(w) == "":
		var d := Loot.weapon_damage(w)
		f["weapon_min"] = d[0]
		f["weapon_max"] = d[1]
		f["weapon_aps"] = float(w.get("aps", 1.2))
		f["weapon_crit"] = float(w.get("crit", 5))
	else:
		f["weapon_min"] = 2.0
		f["weapon_max"] = 4.0
		f["weapon_aps"] = 1.2
		f["weapon_crit"] = 5.0
	var o = eqd.get("off_hand")
	if o != null and o.get("category") == "shield" and equip_restriction(o) == "":
		f["block_chance"] = clampf(f["block_chance"] + float(o.get("block", 0)), 0, 75)
	return f

## Stat preview used by the passive tree and item comparison.
func preview_final(passive_ids: Array, equip_override = null) -> Dictionary:
	return resolve(build_stats(passive_ids, active_buffs, equip_override), equip_override)

## Average hit of a skill under hypothetical passives/equipment (for previews).
func preview_skill_avg(skill_id: String, passive_ids: Array, equip_override = null) -> float:
	var sk: Dictionary = resolved_skill(skill_id)
	if sk.is_empty() or not (sk.has("weapon_eff") or sk.has("base_damage")):
		return 0.0
	var old_s = stats
	var old_f := final
	var old_eq := equipment
	stats = build_stats(passive_ids, active_buffs, equip_override)
	final = resolve(stats, equip_override)
	if equip_override != null:
		equipment = equip_override
	var avg: float = Combat.packet_average(Combat.player_packet(self, sk))
	stats = old_s
	final = old_f
	equipment = old_eq
	return avg

## Equipment dictionary as it would be after equipping item (for comparisons).
func equipment_with(item: Dictionary) -> Dictionary:
	var eq := equipment.duplicate()
	var slot := slot_for(item)
	if item.get("slot") == "ring":
		slot = "ring1" if equipment.get("ring1") != null else slot
	eq[slot] = item
	if slot == "main_hand" and is_two_handed(item):
		var off = eq.get("off_hand")
		if off != null and not (off.get("category") == "quiver" and item.get("tags", []).has("bow")):
			eq["off_hand"] = null
	if slot == "off_hand" and is_two_handed(eq.get("main_hand")):
		if not (item.get("category") == "quiver" and eq["main_hand"].get("tags", []).has("bow")):
			eq["main_hand"] = null
	return eq

# ---------------------------------------------------------------- save / load
func to_dict() -> Dictionary:
	var d := {
		"version": SAVE_VERSION,
		"name": char_name, "class": class_id, "level": level, "xp": xp,
		"bonus_passive_points": bonus_passive_points,
		"allocated": allocated, "inventory": inventory, "stash": stash, "stash_extra_tabs": stash_extra_tabs, "equipment": equipment,
		"gold": gold, "materials": materials, "loadout": loadout, "unlocked_skills": unlocked_skills,
		"flask_charges": flask_charges, "progress": progress, "next_uid": next_uid,
		"runes": runes, "skill_runes": skill_runes, "spec": spec_id, "spec_nodes": spec_nodes,
		"gems": gems,
		"pets": pets, "active_pet": active_pet,
	}
	if dev_used:
		d["dev_used"] = true   # written only when set, so normal saves are unchanged
	return d

func from_dict(d: Dictionary) -> void:
	var ver := int(d.get("version", 1))
	if ver > SAVE_VERSION:
		push_warning("Save is from a newer version (%d)" % ver)
	char_name = d.get("name", "Dan")
	class_id = d.get("class", "warrior")
	level = int(d.get("level", 1))
	xp = int(d.get("xp", 0))
	bonus_passive_points = int(d.get("bonus_passive_points", 0))
	allocated = Array(d.get("allocated", []))
	# drop passives removed from the data since the save was made
	allocated = allocated.filter(func(id): return Data.passives.has(id))
	if not allocated.has(class_def().get("start_passive", "")):
		allocated.push_front(class_def().get("start_passive", ""))
	inventory = _fix_list(d.get("inventory", []), BAG_SIZE)
	_load_stash(d, ver)
	var eq: Dictionary = d.get("equipment", {})
	for s in EQUIP_SLOTS:
		var it = eq.get(s)
		equipment[s] = _fix_item(it)
	gold = int(d.get("gold", 0))
	materials = {}
	var mats: Dictionary = d.get("materials", {})
	for k in mats:
		materials[k] = int(mats[k])
	loadout = Array(d.get("loadout", []))
	while loadout.size() < HOTBAR_SIZE:
		loadout.append("")
	unlocked_skills = Array(d.get("unlocked_skills", []))
	var fc: Array = d.get("flask_charges", [3, 3])
	flask_charges = [float(fc[0]), float(fc[1])]
	progress = d.get("progress", progress)
	runes = {}
	var rd: Dictionary = d.get("runes", {})
	for k in rd:
		if Data.skill_runes.has(k):
			runes[k] = int(rd[k])
	gems = {}
	var gd: Dictionary = d.get("gems", {})
	for k in gd:
		if Loot.gem_valid(k):
			gems[k] = int(gd[k])
	skill_runes = {}
	var sr: Dictionary = d.get("skill_runes", {})
	for k in sr:
		if Data.skills.has(k):
			skill_runes[k] = Array(sr[k]).filter(func(r): return Data.skill_runes.has(r))
	spec_id = d.get("spec", "")
	if not Data.specs.has(spec_id):
		spec_id = ""
	spec_nodes = Array(d.get("spec_nodes", [])).filter(func(n): return Data.spec_nodes.has(n))
	next_uid = int(d.get("next_uid", 1))
	pets = {}
	var pd = d.get("pets", {})
	if typeof(pd) == TYPE_DICTIONARY:
		for k in pd:
			if Data.pets.has(k) and typeof(pd[k]) == TYPE_DICTIONARY:
				pets[k] = {"tier": clampi(int(pd[k].get("tier", 0)), 0, PetRules.max_tier()),
					"name": PetRules.clean_name(str(pd[k].get("name", "")), Data.pets[k]["name"])}
	active_pet = str(d.get("active_pet", ""))
	if not pets.has(active_pet):
		active_pet = ""
	dev_used = bool(d.get("dev_used", false))   # optional field: older saves load as false
	refresh_unlocks(false)
	recalc()

## Restores the stash tabs. Version 2 and older saves held 60 slots of which only 56 were
## ever shown; StashRules.migrate_legacy rescues anything in the hidden four. The tab
## count is also raised if items sit beyond it, so a load can never drop an item.
func _load_stash(d: Dictionary, ver: int) -> void:
	var cfg: Dictionary = Data.stash_cfg
	var raw: Array = Array(d.get("stash", []))
	var extra := StashRules.clamp_extra(cfg, int(d.get("stash_extra_tabs", 0)))
	if ver < 3:
		var mg := StashRules.migrate_legacy(cfg, raw)
		raw = mg["slots"]
		extra = StashRules.clamp_extra(cfg, extra + int(mg["extra_added"]))
	var per := StashRules.slots_per_tab(cfg)
	var last := -1
	for i in raw.size():
		if raw[i] != null:
			last = i
	if last >= 0:
		var need_tabs := int(ceil(float(last + 1) / float(per)))
		extra = maxi(extra, need_tabs - StashRules.free_tabs(cfg, false))
	stash_extra_tabs = extra
	stash = _fix_list(raw, StashRules.total_slots(cfg, extra, false))

func _fix_list(arr, size: int) -> Array:
	var out := []
	for i in size:
		out.append(_fix_item(arr[i]) if i < arr.size() else null)
	return out

func _fix_item(it):
	if it == null or typeof(it) != TYPE_DICTIONARY:
		return null
	if not Data.item_bases.has(it.get("base", "")):
		return null
	# JSON turns ints into floats; normalise the integer fields
	for k in ["ilvl", "req_level", "upgrade", "uid", "sockets", "corruption"]:
		if it.has(k):
			it[k] = int(it[k])
	if it.has("gems"):
		var gl := []
		for g in it["gems"]:
			gl.append(g if (typeof(g) == TYPE_STRING and (g == "" or Loot.gem_valid(g))) else "")
		it["gems"] = gl
	return it

# ---------------------------------------------------------------- stash tabs
func stash_tab_count() -> int:
	return StashRules.tab_total(Data.stash_cfg, stash_extra_tabs, false)

func stash_next_cost() -> int:
	return StashRules.tab_cost(Data.stash_cfg, stash_extra_tabs)

## Buys one extra personal stash tab. Returns "" or the refusal reason.
func buy_stash_tab() -> String:
	var why := StashRules.buy_refusal(Data.stash_cfg, stash_extra_tabs, gold)
	if why != "":
		return why
	gold -= stash_next_cost()
	stash_extra_tabs += 1
	StashRules.ensure_slots(Data.stash_cfg, stash, stash_tab_count())
	Events.currency_changed.emit()
	return ""

# ---------------------------------------------------------------- pets
# Each pet keeps its own tier and name. Switching is free and never refunds or
# resets anything, so you can always switch back to a pet exactly as you left it.
func owns_pet(id: String) -> bool:
	return pets.has(id)

func pet_tier(id: String) -> int:
	return int(pets.get(id, {}).get("tier", 0))

func pet_name(id: String) -> String:
	return str(pets.get(id, {}).get("name", Data.pets.get(id, {}).get("name", id)))

func can_buy_pet(id: String) -> String:
	if not Data.pets.has(id):
		return "Unknown pet"
	if pets.has(id):
		return "Already owned"
	if gold < int(Data.pets[id].get("price", 0)):
		return "Not enough gold"
	return ""

## Buys a pet with gold. The first pet you buy starts following you.
func buy_pet(id: String) -> String:
	var why := can_buy_pet(id)
	if why != "":
		return why
	gold -= int(Data.pets[id].get("price", 0))
	pets[id] = {"tier": 0, "name": Data.pets[id]["name"]}
	Events.currency_changed.emit()
	if active_pet == "":
		set_active_pet(id)
	return ""

func set_active_pet(id: String) -> bool:
	if id != "" and not pets.has(id):
		return false
	if id == active_pet:
		return true
	active_pet = id
	Events.pet_changed.emit()
	return true

func pet_upgrade_cost(id: String) -> Dictionary:
	return PetRules.upgrade_cost(id, pet_tier(id))

func can_upgrade_pet(id: String) -> String:
	if not pets.has(id):
		return "You don't own this pet"
	if pet_tier(id) >= PetRules.max_tier():
		return "Already at the highest tier"
	if not has_materials(pet_upgrade_cost(id)):
		return "Not enough materials"
	return ""

func upgrade_pet(id: String) -> String:
	var why := can_upgrade_pet(id)
	if why != "":
		return why
	if not pay(pet_upgrade_cost(id)):
		return "Not enough materials"
	pets[id]["tier"] = pet_tier(id) + 1
	if id == active_pet:
		Events.pet_changed.emit()
	return ""

func rename_pet(id: String, nm: String) -> bool:
	if not pets.has(id):
		return false
	pets[id]["name"] = PetRules.clean_name(nm, Data.pets[id]["name"])
	if id == active_pet:
		Events.pet_changed.emit()
	return true
