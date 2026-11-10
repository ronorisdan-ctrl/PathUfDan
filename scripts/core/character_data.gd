extends RefCounted
## Persistent character state: class, level, passives, items, currency, skills.
## Also resolves the final StatBlock from every source.

const StatBlock = preload("res://scripts/core/stat_block.gd")
const PetRules = preload("res://scripts/core/pet_rules.gd")
const StashRules = preload("res://scripts/core/stash_rules.gd")
const TreeRules = preload("res://scripts/core/tree_rules.gd")
const CorruptionSystem = preload("res://scripts/core/corruption_system.gd")
const CorruptionRules = preload("res://scripts/core/corruption_rules.gd")
const CorruptionEffects = preload("res://scripts/core/corruption_effects.gd")
const AtlasRules = preload("res://scripts/core/atlas_rules.gd")

const SAVE_VERSION := 5   # 2: adds the pets block; 3: stash tabs (stash_extra_tabs); 4: tree_version (full passive refund when the tree changes); 5: atlas (Endgame Phase 1A)
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
var mastery_choices := {}   # Phase 4a: allocated mastery node id -> chosen option id
var tree_gems := {}         # Phase 4b: allocated socket node id -> gem id ("ruby:2")
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
var atlas := {}            # Atlas of Ruin state (AtlasRules); {} until the Atlas is first opened
var next_uid := 1
var pets := {}              # pet id -> {"tier": int, "name": String}; upgrades belong to each pet
var active_pet := ""        # which owned pet follows you ("" = none)
var dev_used := false       # set by developer tools that change progress; shown as "(dev)" in the load menu
var corruption_actions := {}  # committed confirmation IDs, persisted to reject replay after load
var corruption_action_serial := 0
var _corruption_busy := false
var corruption_cooldowns := {}  # remaining game-time seconds; saved to prevent ICD reset on reload

# runtime (not saved)
const PRESET_SLOTS := 3      # Phase 5b
const PRESET_FREE_LEVEL := 20
var presets := [{}, {}, {}]  # Phase 5b: see preset_slot(); presets[active_preset] stays {}
var active_preset := 0
var presets_dropped := 0      # presets emptied on load because they were no longer legal
var last_preset_missing := []  # gem ids the last switch_preset could not socket again
var plan := []              # Phase 5b planner: ghost node ids, nearest to the web first
var plan_choices := {}      # planned mastery id -> option id
var plan_gems := {}         # socket id -> gem base id suggested by a build code
var tree_refund := {}      # set by from_dict when the passive tree was reset: {from_version, reason, points}
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
	mastery_choices = {}
	tree_gems = {}
	presets = [{}, {}, {}]
	active_preset = 0
	plan = []
	plan_choices = {}
	plan_gems = {}
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
	return (level - 1) + bonus_passive_points + abyss_passive_points()

## Phase 3: +1 point per Endless Abyss milestone depth reached (data/passive_flags.json
## abyss_point_depths). Derived from progress.abyss_best, so it is retroactive and never doubles.
func abyss_passive_points(best: int = -1) -> int:
	if best < 0:
		best = int(progress.get("abyss_best", 0)) if typeof(progress) == TYPE_DICTIONARY else 0
	var n := 0
	for d in Data.passive_flags.get("abyss_point_depths", []):
		if best >= int(d):
			n += 1
	return n

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
	var items := 0
	if stats != null:
		items = int(stats.value("skill_level"))
		if sd.get("tags", []).has("spell"):
			items += int(stats.value("spell_skill_level"))
		if not sd.is_empty() and sd.get("class") == class_id and level >= int(sd.get("unlock_level", 1)):
			lvl += CorruptionEffects.skill_levels(stats, sd)
	# natural and corruption levels respect the cap; item levels may exceed it by caster.overcap
	var over := int(Data.loot.get("caster", {}).get("overcap", 0))
	var capped := clampi(lvl, 1, MAX_SKILL_LEVEL)
	if over <= 0:
		return clampi(lvl + items, 1, MAX_SKILL_LEVEL)
	return clampi(mini(lvl + items, capped + items), 1, MAX_SKILL_LEVEL + over)

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
	var ex := excluded_by(node_id)
	if ex != "":
		return "Cannot be taken with %s" % Data.passives[ex].get("name", ex)
	for l in n.get("links", []):
		if allocated.has(l):
			return ""
	return "Must connect to an allocated node"

## option: the chosen effect when node_id is a mastery (required there, ignored elsewhere).
func allocate(node_id: String, option: String = "") -> bool:
	if can_allocate(node_id) != "":
		return false
	if is_mastery(node_id) and can_choose_mastery(node_id, option) != "":
		return false
	allocated.append(node_id)
	if is_mastery(node_id):
		mastery_choices[node_id] = option
	recalc()
	Events.passive_changed.emit()
	return true

# ---------------------------------------------------------------- masteries (Phase 4a)
func is_mastery(node_id: String) -> bool:
	return str(Data.passives.get(node_id, {}).get("type", "")) == "mastery"

## The registry group of a mastery node ({} for other nodes).
func mastery_group(node_id: String) -> Dictionary:
	return Data.passive_flags.get("masteries", {}).get(str(Data.passives.get(node_id, {}).get("mastery", "")), {})

func mastery_options(node_id: String) -> Array:
	return mastery_group(node_id).get("options", [])

func mastery_option(node_id: String, option: String) -> Dictionary:
	return TreeRules.mastery_option(Data.passive_flags.get("masteries", {}), str(Data.passives.get(node_id, {}).get("mastery", "")), option)

## The allocated mastery (other than except) that already holds option ("" = free).
func option_taken_by(option: String, except: String = "") -> String:
	for id in mastery_choices:
		if id != except and allocated.has(id) and str(mastery_choices[id]) == option:
			return id
	return ""

func can_choose_mastery(node_id: String, option: String) -> String:
	if not is_mastery(node_id):
		return "Not a mastery"
	if option == "":
		return "Choose an effect"
	if mastery_option(node_id, option).is_empty():
		return "Not an effect of this mastery"
	var other := option_taken_by(option, node_id)
	if other != "":
		return "Already chosen at %s" % Data.passives[other].get("name", other)
	return ""

func mastery_change_cost() -> int:
	return refund_cost()

## Swap the effect of an allocated mastery; costs the refund price of one node.
func change_mastery(node_id: String, option: String) -> String:
	if not allocated.has(node_id) or not is_mastery(node_id):
		return "Not an allocated mastery"
	if str(mastery_choices.get(node_id, "")) == option:
		return "Already chosen"
	var why := can_choose_mastery(node_id, option)
	if why != "":
		return why
	if gold < mastery_change_cost():
		return "Changing costs %d gold" % mastery_change_cost()
	gold -= mastery_change_cost()
	mastery_choices[node_id] = option
	recalc()
	Events.passive_changed.emit()
	Events.currency_changed.emit()
	return ""

## The allocated node that node_id is mutually exclusive with ("" = none).
func excluded_by(node_id: String) -> String:
	for x in Data.passives.get(node_id, {}).get("exclusive_with", []):
		if allocated.has(x):
			return x
	return ""

## Shortest chain of unallocated nodes that connects node_id to the
## allocated web (ending with node_id). Empty if unreachable.
## Routes never pass through nodes that are exclusive with the current web.
func path_to(node_id: String) -> Array:
	if allocated.has(node_id) or not Data.passives.has(node_id) or excluded_by(node_id) != "":
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
			if ln.get("type") in TreeRules.NO_ROUTE or excluded_by(l) != "":
				continue
			prev[l] = cur
			queue.append(l)
	return []

func path_cost(path: Array) -> int:
	var c := 0
	for id in path:
		c += int(Data.passives[id].get("cost", 1))
	return c

func allocate_path(node_id: String, option: String = "") -> bool:
	var path := path_to(node_id)
	if path.is_empty() or path_cost(path) > available_passive_points():
		return false
	if is_mastery(node_id) and can_choose_mastery(node_id, option) != "":
		return false
	for id in path:
		allocated.append(id)
	if is_mastery(node_id):
		mastery_choices[node_id] = option
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
	mastery_choices.erase(node_id)
	_return_tree_gem(node_id)
	recalc()
	Events.passive_changed.emit()
	Events.currency_changed.emit()
	return true

# ---------------------------------------------------------------- tree sockets (Phase 4b)
func is_socket(node_id: String) -> bool:
	return str(Data.passives.get(node_id, {}).get("type", "")) == "socket"

func tree_socket_cfg() -> Dictionary:
	return Data.passive_flags.get("tree_sockets", {})

## Why gid cannot go into the socket node_id ("" = it can). A gem already in the socket is
## swapped back to the pouch, so swapping needs only the new gem.
func can_socket_tree_gem(node_id: String, gid: String) -> String:
	if not is_socket(node_id):
		return "Not a gem socket"
	if not allocated.has(node_id):
		return "Allocate the socket first"
	if not Loot.gem_valid(gid):
		return "Unknown gem"
	if str(tree_gems.get(node_id, "")) == gid:
		return "Already socketed"
	if level < Loot.gem_req(gid):
		return "Requires level %d" % Loot.gem_req(gid)
	if int(gems.get(gid, 0)) <= 0:
		return "You have no such gem"
	return ""

## Socket (or swap) a gem from the pouch into an allocated tree socket. Free.
func socket_tree_gem(node_id: String, gid: String) -> String:
	var why := can_socket_tree_gem(node_id, gid)
	if why != "":
		return why
	_take_gem(gid)
	_return_tree_gem(node_id)
	tree_gems[node_id] = gid
	recalc()
	Events.passive_changed.emit()
	return ""

## Take the gem out of a tree socket back into the pouch. Free.
func unsocket_tree_gem(node_id: String) -> String:
	if not tree_gems.has(node_id):
		return "The socket is empty"
	_return_tree_gem(node_id)
	recalc()
	Events.passive_changed.emit()
	return ""

## Every socketed tree gem back to the pouch (used by full respecs).
func clear_tree_gems() -> void:
	for id in tree_gems.keys():
		_return_tree_gem(id)

func _return_tree_gem(node_id: String) -> void:
	if tree_gems.has(node_id):
		var gid := str(tree_gems[node_id])
		tree_gems.erase(node_id)
		if Loot.gem_valid(gid):
			add_gem(gid)

## {node_id: percent} radius boosts for an allocation (TreeRules.socket_boosts).
func socket_boosts(passive_ids: Array) -> Dictionary:
	if tree_gems.is_empty():
		return {}
	return TreeRules.socket_boosts(Data.passives, passive_ids, tree_gems, tree_socket_cfg(), Data.gems)

## Phase 5a: "what does my tree do". Sums every allocated mod (socket boosts, mastery
## effects and socket gem stats included) by stat and groups the sums by theme
## (TreeRules.stat_theme). Returns {themes: {theme: [mod]}, order: [theme], keystones,
## behaviours, masteries: [[node, option]], gems: [[socket, gem]], tags: {tag: count},
## nodes, points}.
func tree_summary(passive_ids = null) -> Dictionary:
	var ids: Array = allocated if passive_ids == null else passive_ids
	var boosts := socket_boosts(ids)
	var sums := {}
	var out := {"keystones": [], "behaviours": [], "masteries": [], "gems": [], "tags": {}, "nodes": 0, "points": 0}
	for pid in ids:
		var n: Dictionary = Data.passives.get(pid, {})
		var ty := str(n.get("type", ""))
		if n.is_empty():
			continue
		if ty == "start":   # the class start's stats count, the node itself does not
			for m in n.get("mods", []):
				TreeRules.sum_mod(sums, m)
			continue
		out["nodes"] += 1
		out["points"] += int(n.get("cost", 1))
		for tg in n.get("tags", []):
			out["tags"][tg] = int(out["tags"].get(tg, 0)) + 1
		var bm := 1.0 + float(boosts.get(pid, 0.0)) / 100.0
		for m in n.get("mods", []):
			TreeRules.sum_mod(sums, m, bm)
		if ty == "keystone":
			out["keystones"].append(pid)
		elif not n.get("flags", []).is_empty():
			out["behaviours"].append(pid)
		if ty == "mastery":
			var oid := str(mastery_choices.get(pid, ""))
			out["masteries"].append([pid, oid])
			for m in mastery_option(pid, oid).get("mods", []):
				TreeRules.sum_mod(sums, m)
		if ty == "socket" and tree_gems.has(pid):
			out["gems"].append([pid, str(tree_gems[pid])])
			for m in Loot.gem_mods(str(tree_gems[pid]), "tree"):
				TreeRules.sum_mod(sums, m)
	var themes := {}
	for k in sums:
		var m: Dictionary = sums[k]
		if absf(float(m["value"])) < 0.01:
			continue
		var th := TreeRules.stat_theme(str(m["stat"]))
		if not themes.has(th):
			themes[th] = []
		themes[th].append(m)
	var order := []
	for th in TreeRules.theme_order():
		if themes.has(th):
			themes[th].sort_custom(func(a, b): return str(a["stat"]) + str(a["type"]) < str(b["stat"]) + str(b["type"]))
			order.append(th)
	out["themes"] = themes
	out["order"] = order
	return out

# ---------------------------------------------------------------- presets, planner, build codes (Phase 5b)
## Presets: PRESET_SLOTS tree loadouts per character. The live tree (allocated,
## mastery_choices, tree_gems) IS the active preset, so presets[active_preset] stays {};
## the other slots hold {"allocated", "mastery_choices", "gems": {socket: gem id}} or {}.
## Switching costs refund_cost() per node it removes (and per mastery whose effect changes);
## free below PRESET_FREE_LEVEL. Switching to an empty slot copies the current tree (free).
func preset_slot(i: int) -> Dictionary:
	if i < 0 or i >= presets.size():
		return {}
	return presets[i]

func preset_empty(i: int) -> bool:
	return i != active_preset and preset_slot(i).is_empty()

## Nodes in preset i (start excluded); the active preset counts the live tree.
func preset_nodes(i: int) -> int:
	if i == active_preset:
		return allocated.size() - 1
	return maxi(0, Array(preset_slot(i).get("allocated", [])).size() - 1)

func _tree_snapshot() -> Dictionary:
	var mc := {}
	for id in mastery_choices:
		if allocated.has(id):
			mc[id] = mastery_choices[id]
	return {"allocated": allocated.duplicate(), "mastery_choices": mc, "gems": tree_gems.duplicate()}

## Live nodes the switch to preset i would take away, plus masteries whose effect changes.
func preset_changes(i: int) -> int:
	if i == active_preset or preset_empty(i):
		return 0
	var tgt: Dictionary = preset_slot(i)
	var ta: Array = tgt.get("allocated", [])
	var tc: Dictionary = tgt.get("mastery_choices", {})
	var n := 0
	for id in allocated:
		if not ta.has(id):
			n += 1
		elif is_mastery(id) and str(tc.get(id, "")) != str(mastery_choices.get(id, "")):
			n += 1
	return n

func preset_switch_cost(i: int) -> int:
	if level < PRESET_FREE_LEVEL:
		return 0
	return preset_changes(i) * refund_cost()

func can_switch_preset(i: int) -> String:
	if i < 0 or i >= PRESET_SLOTS:
		return "No such preset"
	if i == active_preset:
		return "Already using this preset"
	if not preset_empty(i):
		var tgt: Dictionary = preset_slot(i)
		var start: String = class_def().get("start_passive", "")
		var why := TreeRules.allocation_problem(Array(tgt.get("allocated", [])), start, total_passive_points(), Data.passives,
			tgt.get("mastery_choices", {}), Data.passive_flags.get("masteries", {}))
		if why != "":
			return "That preset no longer fits (%s)" % why
	if gold < preset_switch_cost(i):
		return "Switching costs %d gold" % preset_switch_cost(i)
	return ""

## Switch the live tree to preset i. Socketed gems go back to the pouch; the target's gems
## are socketed again when the pouch still holds them (missing ones end in last_preset_missing).
func switch_preset(i: int) -> String:
	var why := can_switch_preset(i)
	if why != "":
		return why
	var cost := preset_switch_cost(i)
	var tgt: Dictionary = preset_slot(i)
	presets[active_preset] = _tree_snapshot()
	presets[i] = {}
	active_preset = i
	last_preset_missing = []
	gold -= cost
	if not tgt.is_empty():
		clear_tree_gems()
		allocated = Array(tgt.get("allocated", [])).duplicate()
		mastery_choices = Dictionary(tgt.get("mastery_choices", {})).duplicate()
		var tg: Dictionary = tgt.get("gems", {})
		for sid in tg:
			var gid := str(tg[sid])
			if allocated.has(sid) and is_socket(sid) and int(gems.get(gid, 0)) > 0 and level >= Loot.gem_req(gid):
				_take_gem(gid)
				tree_gems[sid] = gid
			else:
				last_preset_missing.append(gid)
	_prune_plan()
	recalc()
	Events.passive_changed.emit()
	Events.currency_changed.emit()
	return ""

## Planner: ghost nodes that cost nothing until "apply plan". plan keeps route order
## (nearest to the web first); plan_choices holds planned mastery effects; plan_gems holds
## socket -> gem base suggestions from an imported build code.
func plan_has(id: String) -> bool:
	return plan.has(id)

func plan_points() -> int:
	var c := 0
	for id in plan:
		c += int(Data.passives.get(id, {}).get("cost", 1))
	return c

func _plan_excluded(id: String) -> bool:
	for x in Data.passives.get(id, {}).get("exclusive_with", []):
		if allocated.has(x) or plan.has(x):
			return true
	return false

func _plan_options_used(except: String = "") -> Dictionary:
	var used := {}
	for id in mastery_choices:
		if allocated.has(id):
			used[str(mastery_choices[id])] = true
	for id in plan_choices:
		if id != except and plan.has(id):
			used[str(plan_choices[id])] = true
	return used

## Shortest chain of nodes (neither allocated nor planned) that joins id to the allocated
## web or the plan, target last. Same routing rules as path_to.
func plan_route(id: String) -> Array:
	if allocated.has(id) or plan.has(id) or not Data.passives.has(id) or _plan_excluded(id):
		return []
	if Data.passives[id].get("type") == "start":
		return []
	var prev := {id: ""}
	var queue := [id]
	var qi := 0
	while qi < queue.size():
		var cur: String = queue[qi]
		qi += 1
		for l in Data.passives[cur].get("links", []):
			if prev.has(l):
				continue
			if allocated.has(l) or plan.has(l):
				var path := [cur]
				var c: String = cur
				while prev[c] != "":
					c = prev[c]
					path.append(c)
				return path
			var ln: Dictionary = Data.passives[l]
			if ln.get("type") in TreeRules.NO_ROUTE or _plan_excluded(l):
				continue
			prev[l] = cur
			queue.append(l)
	return []

## Why id cannot be planned with option ("" = it can).
func can_plan(id: String, option: String = "") -> String:
	if allocated.has(id):
		return "Already allocated"
	if plan.has(id):
		return "Already planned"
	if not Data.passives.has(id):
		return "Unknown node"
	if Data.passives[id].get("type") == "start":
		return "Starting points cannot be planned"
	if _plan_excluded(id):
		return "Exclusive with an allocated or planned node"
	if is_mastery(id):
		if option == "" or mastery_option(id, option).is_empty():
			return "Choose an effect"
		if _plan_options_used().has(option):
			return "That effect is already taken"
	if plan_route(id).is_empty():
		return "No route to that node"
	return ""

func plan_add(id: String, option: String = "") -> String:
	var why := can_plan(id, option)
	if why != "":
		return why
	for p in plan_route(id):
		plan.append(p)
	if is_mastery(id):
		plan_choices[id] = option
	Events.passive_changed.emit()
	return ""

## Remove id from the plan, and every planned node that no longer connects to the web.
func plan_remove(id: String) -> bool:
	if not plan.has(id):
		return false
	plan.erase(id)
	_prune_plan()
	Events.passive_changed.emit()
	return true

func clear_plan() -> void:
	plan = []
	plan_choices = {}
	plan_gems = {}
	Events.passive_changed.emit()

## Drops planned nodes that are allocated, exclusive with the allocation, or cut off from it.
func _prune_plan() -> void:
	var r := TreeRules.sanitize_plan(plan, plan_choices, allocated, Data.passives, Data.passive_flags.get("masteries", {}), _alloc_options_used())
	plan = r["nodes"]
	plan_choices = r["choices"]
	for sid in plan_gems.keys():
		if not plan.has(sid) and not allocated.has(sid):
			plan_gems.erase(sid)

func _alloc_options_used() -> Dictionary:
	var used := {}
	for id in mastery_choices:
		if allocated.has(id):
			used[str(mastery_choices[id])] = true
	return used

## Allocate planned nodes, nearest first, as far as the points allow. Returns how many.
func apply_plan() -> int:
	var added := 0
	var progress := true
	while progress:
		progress = false
		for id in plan.duplicate():
			if allocated.has(id) or can_allocate(id) != "":
				continue
			if is_mastery(id) and can_choose_mastery(id, str(plan_choices.get(id, ""))) != "":
				continue
			allocated.append(id)
			if is_mastery(id):
				mastery_choices[id] = str(plan_choices[id])
			added += 1
			progress = true
	_prune_plan()
	if added > 0:
		recalc()
	Events.passive_changed.emit()
	return added

## Build code of the live tree; with include_plan the planned nodes are part of it.
func export_build_code(include_plan: bool = true) -> String:
	var start: String = class_def().get("start_passive", "")
	var ids := []
	for id in allocated:
		if id != start:
			ids.append(id)
	var mc := {}
	for id in mastery_choices:
		if allocated.has(id):
			mc[id] = str(mastery_choices[id])
	var g := {}
	for sid in tree_gems:
		g[sid] = str(tree_gems[sid]).get_slice(":", 0)
	if include_plan:
		for id in plan:
			ids.append(id)
		for id in plan_choices:
			if plan.has(id):
				mc[id] = str(plan_choices[id])
		for sid in plan_gems:
			if not g.has(sid):
				g[sid] = str(plan_gems[sid])
	return TreeRules.encode_build({"v": TreeRules.BUILD_FORMAT, "c": class_id, "t": TreeRules.tree_version(Data.passive_migrations), "n": ids, "m": mc, "g": g})

## Import a build code as the plan (replacing it). Allocated nodes stay; illegal nodes are
## dropped. Returns {"error", "planned", "dropped", "gems": [gem base ids suggested]}.
func import_build_code(code: String) -> Dictionary:
	var res := TreeRules.decode_build(code)
	if res["error"] != "":
		return {"error": res["error"], "planned": 0, "dropped": 0, "gems": []}
	var d: Dictionary = res["data"]
	if d["c"] != class_id:
		return {"error": "This build is for a %s" % Data.classes.get(d["c"], {}).get("name", "different class"), "planned": 0, "dropped": 0, "gems": []}
	var cur_tree := TreeRules.tree_version(Data.passive_migrations)
	var ids := []
	var mc := {}
	for id in d["n"]:
		var nid: String = id
		if int(d["t"]) < cur_tree:
			nid = TreeRules.migrate_id(id, int(d["t"]), Data.passive_migrations)
		if nid != "":
			ids.append(nid)
			if d["m"].has(id):
				mc[nid] = d["m"][id]
	# a mastery already allocated with another effect keeps the current effect
	var r := TreeRules.sanitize_plan(ids, mc, allocated, Data.passives, Data.passive_flags.get("masteries", {}), _alloc_options_used())
	plan = r["nodes"]
	plan_choices = r["choices"]
	plan_gems = {}
	var sugg := []
	for sid in d["g"]:
		var base := str(d["g"][sid])
		if Data.gems.has(base) and is_socket(sid) and (plan.has(sid) or allocated.has(sid)):
			plan_gems[sid] = base
			sugg.append(base)
	var dropped: int = r["dropped"].size() + (Array(d["n"]).size() - ids.size())
	Events.passive_changed.emit()
	return {"error": "", "planned": plan.size(), "dropped": dropped, "gems": sugg}

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
	if it.get("destroyed", false):
		return "This item was destroyed"
	if CorruptionRules.is_maxed(it):
		return "Corrupted: cannot edit sockets or gems"
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
	if it.get("destroyed", false):
		return "This item was destroyed"
	if CorruptionRules.is_maxed(it):
		return "Corrupted: cannot edit sockets or gems"
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
	if int(item.get("uid", 0)) <= 0:
		item["uid"] = take_uid()
	inventory[i] = item
	Events.inventory_changed.emit()
	return true

func new_corruption_action_id() -> String:
	corruption_action_serial += 1
	return "corrupt:%d" % corruption_action_serial

func tick_corruption_cooldowns(delta: float) -> void:
	for key in corruption_cooldowns.keys():
		corruption_cooldowns[key] = maxf(0.0, float(corruption_cooldowns[key]) - maxf(0.0, delta))
		if corruption_cooldowns[key] <= 0:
			corruption_cooldowns.erase(key)

func corruption_cost() -> Dictionary:
	var mat: Dictionary = Data.corruption_cfg.get("required_material", {})
	var cost := {str(mat.get("id", "abyssal_brand")): int(mat.get("quantity", 1))}
	var fee := int(Data.corruption_cfg.get("corruption_gold_fee", 0))
	if fee > 0:
		cost["gold"] = fee
	return cost

func corruption_item(uid: int):
	var found = null
	for it in inventory:
		if it != null and int(it.get("uid", 0)) == uid:
			if found != null:
				return null  # ambiguous ownership fails closed
			found = it
	return found

func corruption_refusal(uid: int, action_id: String = "") -> String:
	if _corruption_busy:
		return "A corruption action is already in progress"
	if action_id != "" and corruption_actions.has(action_id):
		return "This corruption confirmation was already used"
	if uid <= 0:
		return "Select an owned inventory item"
	for it in equipment.values():
		if it != null and int(it.get("uid", 0)) == uid:
			return "Unequip this item before corrupting it"
	var it = corruption_item(uid)
	if it == null:
		return "Item is missing, unowned or has a duplicate ID"
	if is_locked(it):
		return "Unlock this protected item before risking destruction"
	for flag in Data.corruption_cfg.get("restricted_item_flags", []):
		if it.get(flag, false) or Data.item_bases.get(it.get("base",""),{}).get(flag,false):
			return "This item is restricted: " + str(flag)
	var c = it.get("corruption", 0)
	if not CorruptionSystem.numeric(c) or float(c) < 0:
		return "Invalid item corruption value"
	if float(c) >= 100:
		return "Corrupted: this item can no longer be crafted"
	if it.get("corrupted_prefix") != null or it.get("corrupted_suffix") != null:
		return "This item already has corrupted implicits"
	if not CorruptionSystem.validate(Data.corruption_cfg, Data.corruption_affixes).is_empty():
		return "Corruption registry unavailable"
	if CorruptionSystem.pool_for(it, Data.corruption_cfg) == "":
		return "This item is not eligible equipment"
	var p := CorruptionSystem.eligible(it, "prefix", Data.corruption_cfg, Data.corruption_affixes)
	var s := CorruptionSystem.eligible(it, "suffix", Data.corruption_cfg, Data.corruption_affixes)
	if p.is_empty() or s.is_empty() or CorruptionSystem.paired_prefixes(p, s, Data.corruption_cfg).is_empty():
		return "Corruption pool unavailable for this item"
	if not has_materials(corruption_cost()):
		return "Need " + Loot.cost_text(corruption_cost())
	return ""

## Synchronous transaction: plan first, mutate without signals, persist, then notify.
## On write failure restore the original item/resources and leave the confirmation unused.
func corrupt_item(uid: int, action_id: String, random) -> Dictionary:
	if action_id == "":
		return {"err": "Missing corruption confirmation ID"}
	var why := corruption_refusal(uid, action_id)
	if why != "":
		return {"err": why}
	_corruption_busy = true
	var original: Dictionary = corruption_item(uid)
	var plan := CorruptionSystem.plan(original, Data.corruption_cfg, Data.corruption_affixes, random)
	if plan["err"] != "":
		_corruption_busy = false
		return plan
	var slot := -1
	for i in inventory.size():
		if inventory[i] != null and int(inventory[i].get("uid", 0)) == uid:
			slot = i
	var gold_before := gold
	var mats_before := materials.duplicate(true)
	var gems_before := gems.duplicate(true)
	for key in corruption_cost():
		if key == "gold":
			gold -= int(corruption_cost()[key])
		else:
			materials[key] = int(materials.get(key, 0)) - int(corruption_cost()[key])
	if plan["outcome"] == "destroyed":
		# Same recovery policy as reclaim_gems; defer its signals until commit.
		for gem in original.get("gems", []):
			if gem != "" and Loot.gem_valid(gem):
				gems[gem] = int(gems.get(gem, 0)) + 1
		inventory[slot] = null
	else:
		inventory[slot] = plan["item"]
	corruption_actions[action_id] = true
	if Game.ch == self and not Game.testing and not Game.save_game():
		inventory[slot] = original
		gold = gold_before
		materials = mats_before
		gems = gems_before
		corruption_actions.erase(action_id)
		_corruption_busy = false
		return {"err": "Could not save corruption; item and cost restored"}
	if Game.ch == self and not Game.testing:
		Game.autosave()  # manual save is authoritative; never autosave an aborted transaction
	if plan["outcome"] == "destroyed":
		original["gems"] = []
		original["destroyed"] = true  # invalidate stale UI/callback references too
	else:
		original.clear()
		original.merge(plan["item"], true)
		inventory[slot] = original  # preserve dictionary references used by inventory UI
	_corruption_busy = false
	recalc()
	Events.currency_changed.emit()
	Events.inventory_changed.emit()
	return {"err": "", "outcome": plan["outcome"], "item": inventory[slot], "uid": uid}

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

## choices: mastery node id -> option id (null = this character's mastery_choices).
func build_stats(passive_ids: Array, buffs: Array = [], equip_override = null, choices = null):
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
			sb.add_mod(m, m.get("source", "equipment"))
		if it.get("legendary_effect", "") != "":
			sb.add_flag(it["legendary_effect"])
	for sn in spec_nodes:
		var nd: Dictionary = Data.spec_nodes.get(sn, {})
		for m in nd.get("mods", []):
			sb.add_mod(m, "specialisation")
		for f in nd.get("flags", []):
			sb.add_flag(f)
	var boosts := socket_boosts(passive_ids)
	for pid in passive_ids:
		var n: Dictionary = Data.passives.get(pid, {})
		var bm := 1.0 + float(boosts.get(pid, 0.0)) / 100.0
		for m in n.get("mods", []):
			var mm: Dictionary = m
			if bm != 1.0 and str(m.get("type", "")) != "more":
				mm = m.duplicate()
				mm["value"] = float(m["value"]) * bm
			sb.add_mod(mm, "passive")
		for f in n.get("flags", []):
			sb.add_flag(f)
		if n.get("type", "") == "mastery":
			var ch_map: Dictionary = mastery_choices if choices == null else choices
			var o := mastery_option(pid, str(ch_map.get(pid, "")))
			for m in o.get("mods", []):
				sb.add_mod(m, "passive")
			for f in o.get("flags", []):
				sb.add_flag(f)
		if n.get("type", "") == "socket" and tree_gems.has(pid):
			for m in Loot.gem_mods(str(tree_gems[pid]), "tree"):
				sb.add_mod(m, "passive")
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
		var cap := 75.0
		if r in ["fire", "cold", "lightning"]:
			cap = minf(float(Data.corruption_cfg.get("max_elemental_resistance_absolute_safety_cap", 78)), cap + CorruptionEffects.total(sb,"maximum_elemental_resistance"))
		f["res_cap_" + r] = cap
		f["res_" + r] = clampf(sb.value("res_" + r), -100, cap)
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
func preview_final(passive_ids: Array, equip_override = null, choices = null) -> Dictionary:
	return resolve(build_stats(passive_ids, active_buffs, equip_override, choices), equip_override)

## Average hit of a skill under hypothetical passives/equipment (for previews).
func preview_skill_avg(skill_id: String, passive_ids: Array, equip_override = null, choices = null) -> float:
	var sk: Dictionary = resolved_skill(skill_id)
	if sk.is_empty() or not (sk.has("weapon_eff") or sk.has("base_damage")):
		return 0.0
	var old_s = stats
	var old_f := final
	var old_eq := equipment
	stats = build_stats(passive_ids, active_buffs, equip_override, choices)
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
		"tree_version": TreeRules.tree_version(Data.passive_migrations),
		"allocated": allocated, "inventory": inventory, "stash": stash, "stash_extra_tabs": stash_extra_tabs, "equipment": equipment,
		"gold": gold, "materials": materials, "loadout": loadout, "unlocked_skills": unlocked_skills,
		"flask_charges": flask_charges, "progress": progress, "next_uid": next_uid,
		"runes": runes, "skill_runes": skill_runes, "spec": spec_id, "spec_nodes": spec_nodes,
		"gems": gems,
		"pets": pets, "active_pet": active_pet,
	}
	var mc := {}
	for id in mastery_choices:
		if allocated.has(id):
			mc[id] = mastery_choices[id]
	if not mc.is_empty():
		d["mastery_choices"] = mc   # Phase 4a; written only when set
	if not tree_gems.is_empty():
		d["tree_gems"] = tree_gems.duplicate()   # Phase 4b; written only when set
	var ps := []
	var any_preset := active_preset != 0
	for i in PRESET_SLOTS:
		ps.append({} if i == active_preset else preset_slot(i).duplicate(true))
		any_preset = any_preset or not ps[i].is_empty()
	if any_preset:
		d["passive_presets"] = {"active": active_preset, "slots": ps}   # Phase 5b; written only when used
	if not plan.is_empty():
		d["tree_plan"] = {"nodes": plan.duplicate(), "choices": plan_choices.duplicate(), "gems": plan_gems.duplicate()}   # Phase 5b
	if dev_used:
		d["dev_used"] = true   # written only when set, so normal saves are unchanged
	if not atlas.is_empty():
		d["atlas"] = atlas.duplicate(true)   # v5; written only once the Atlas is opened
	if not corruption_actions.is_empty():
		d["corruption_actions"] = corruption_actions.duplicate()
		d["corruption_action_serial"] = corruption_action_serial
	if not corruption_cooldowns.is_empty():
		d["corruption_cooldowns"] = corruption_cooldowns.duplicate()
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
	_load_passives(d)
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
	_load_tree_gems(d)
	_load_presets_and_plan(d)
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
	var saved_actions = d.get("corruption_actions", {})
	corruption_actions = saved_actions.duplicate() if saved_actions is Dictionary else {}
	corruption_action_serial = int(d.get("corruption_action_serial", 0))
	corruption_cooldowns = {}
	var saved_cooldowns = d.get("corruption_cooldowns", {})
	if saved_cooldowns is Dictionary:
		for key in saved_cooldowns:
			if key == "dodge_mana" and CorruptionSystem.numeric(saved_cooldowns[key]):
				corruption_cooldowns[key] = clampf(float(saved_cooldowns[key]),0,8)
	# Older items could lack an ID. Preserve valid IDs and allocate above all existing ones.
	for it in inventory + stash + equipment.values():
		if it != null:
			next_uid = maxi(next_uid, int(it.get("uid", 0)))
	for it in inventory + stash + equipment.values():
		if it != null and int(it.get("uid", 0)) <= 0:
			it["uid"] = take_uid()
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
	atlas = AtlasRules.sanitize(d.get("atlas", {}))   # v5; older saves have no Atlas yet
	refresh_unlocks(false)
	recalc()

## Restores the passive allocation. Policy (Dan, 2026-11-04): if the save was made with an
## older tree_version, or the allocation is no longer legal for any reason (missing or
## disconnected nodes, too many points, exclusive pair), the whole tree is refunded for free
## and tree_refund records why (Game shows a one-time message and keeps a .bak of the file).
## Saves before version 4 carry no tree_version and count as tree version 1.
func _load_passives(d: Dictionary) -> void:
	tree_refund = {}
	mastery_choices = {}
	var start: String = class_def().get("start_passive", "")
	var raw_choices := {}
	var mc = d.get("mastery_choices", {})
	if typeof(mc) == TYPE_DICTIONARY:
		for k in mc:
			raw_choices[str(k)] = str(mc[k])
	var raw := []
	for id in Array(d.get("allocated", [])):
		raw.append(str(id))
	var saved_tree := int(d.get("tree_version", 1))
	var cur_tree := TreeRules.tree_version(Data.passive_migrations)
	var problem := ""
	if saved_tree < cur_tree:
		problem = "passive tree updated (version %d -> %d)" % [saved_tree, cur_tree]
	else:
		if saved_tree > cur_tree:
			push_warning("Save uses a newer passive tree (%d > %d)" % [saved_tree, cur_tree])
		if not raw.has(start):
			raw.push_front(start)   # older saves could miss it; not worth a refund
		problem = TreeRules.allocation_problem(raw, start, total_passive_points(), Data.passives, raw_choices, Data.passive_flags.get("masteries", {}))
	if problem == "":
		allocated = raw
		mastery_choices = raw_choices
		return
	var spent := 0
	for id in raw:
		if id != start and Data.passives.has(id):   # removed nodes give nothing back
			spent += int(Data.passives[id].get("cost", 1))
	allocated = [start]
	if spent > 0:   # nothing to give back = nothing to tell the player
		# ids: refunded nodes that still exist (Phase 5a: shown as "refunded" in the tree view)
		var ids := []
		for id in raw:
			if id != start and Data.passives.has(id) and not ids.has(id):
				ids.append(id)
		tree_refund = {"from_version": saved_tree, "reason": problem, "points": spent, "ids": ids}

## Phase 5b: presets and the plan. A tree refund (new tree_version or illegal allocation)
## empties every preset and the plan, like the live tree; otherwise each preset is checked
## with allocation_problem and an illegal one is emptied (counted in presets_dropped).
func _load_presets_and_plan(d: Dictionary) -> void:
	presets = [{}, {}, {}]
	active_preset = 0
	plan = []
	plan_choices = {}
	plan_gems = {}
	presets_dropped = 0
	var refunded := not tree_refund.is_empty() or int(d.get("tree_version", 1)) < TreeRules.tree_version(Data.passive_migrations)
	var pp = d.get("passive_presets", {})
	if typeof(pp) == TYPE_DICTIONARY:
		active_preset = clampi(int(pp.get("active", 0)), 0, PRESET_SLOTS - 1)
		var slots = pp.get("slots", [])
		if typeof(slots) == TYPE_ARRAY:
			var start: String = class_def().get("start_passive", "")
			for i in mini(slots.size(), PRESET_SLOTS):
				if i == active_preset or typeof(slots[i]) != TYPE_DICTIONARY or slots[i].is_empty():
					continue
				if refunded:
					presets_dropped += 1
					continue
				var al := []
				for id in Array(slots[i].get("allocated", [])):
					al.append(str(id))
				var mc := {}
				var smc = slots[i].get("mastery_choices", {})
				if typeof(smc) == TYPE_DICTIONARY:
					for k in smc:
						mc[str(k)] = str(smc[k])
				var gm := {}
				var sg = slots[i].get("gems", {})
				if typeof(sg) == TYPE_DICTIONARY:
					for k in sg:
						if Loot.gem_valid(str(sg[k])):
							gm[str(k)] = str(sg[k])
				if TreeRules.allocation_problem(al, start, total_passive_points(), Data.passives, mc, Data.passive_flags.get("masteries", {})) != "":
					presets_dropped += 1
					continue
				presets[i] = {"allocated": al, "mastery_choices": mc, "gems": gm}
	var tp = d.get("tree_plan", {})
	if refunded or typeof(tp) != TYPE_DICTIONARY:
		return
	var ids := []
	for id in Array(tp.get("nodes", [])):
		ids.append(str(id))
	var pc := {}
	var tpc = tp.get("choices", {})
	if typeof(tpc) == TYPE_DICTIONARY:
		for k in tpc:
			pc[str(k)] = str(tpc[k])
	plan = ids
	plan_choices = pc
	var tpg = tp.get("gems", {})
	if typeof(tpg) == TYPE_DICTIONARY:
		for k in tpg:
			if Data.gems.has(str(tpg[k])):
				plan_gems[str(k)] = str(tpg[k])
	_prune_plan()

## Phase 4b: gems kept in tree sockets. A gem whose socket is no longer allocated (for
## example after a full tree refund) goes back to the pouch; unknown gem ids are dropped.
## Must run after the allocation and the pouch are loaded.
func _load_tree_gems(d: Dictionary) -> void:
	tree_gems = {}
	var tg = d.get("tree_gems", {})
	if typeof(tg) != TYPE_DICTIONARY:
		return
	for k in tg:
		var gid := str(tg[k])
		if not Loot.gem_valid(gid):
			continue
		if allocated.has(str(k)) and is_socket(str(k)):
			tree_gems[str(k)] = gid
		else:
			add_gem(gid)

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
	for k in ["ilvl", "req_level", "upgrade", "uid", "sockets"]:
		if it.has(k):
			it[k] = int(it[k])
	if it.has("corruption") and CorruptionSystem.numeric(it["corruption"]):
		it["corruption"] = int(it["corruption"])
	if it.has("gems"):
		var gl := []
		for g in it["gems"]:
			gl.append(g if (typeof(g) == TYPE_STRING and (g == "" or Loot.gem_valid(g))) else "")
		it["gems"] = gl
	CorruptionSystem.normalize_item(it, Data.corruption_cfg, Data.corruption_affixes)
	preload("res://scripts/core/atlas_craft_rules.gd").normalize(it)   # Endgame 2B fields
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
