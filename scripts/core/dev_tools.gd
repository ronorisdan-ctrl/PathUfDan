extends Node
## Developer tools (autoload "Dev"). Off by default; switched on in Settings.
## Holds the runtime flags (never saved) and applies one-click test actions to the
## live game. Every action goes through the real game function where one exists
## (level-up, pickup/drop, loot roll, kills, objective completion, stash purchase).
##
## Rules:
## - Nothing runs unless Game.settings["dev_tools"] is true, and never under
##   Game.testing (bots, tests) unless Game.dev_in_tests is set.
## - Actions that change progress mark the character with ch.dev_used.
## - Every action returns {"ok": bool, "msg": String}; the UI shows msg as a toast.
## Pure maths lives in scripts/core/dev_rules.gd; presets in data/dev_tools.json.

const DevRules = preload("res://scripts/core/dev_rules.gd")
const CharacterData = preload("res://scripts/core/character_data.gd")
const PetRules = preload("res://scripts/core/pet_rules.gd")
const CorruptionRules = preload("res://scripts/core/corruption_rules.gd")

signal changed   # enabled state or a flag changed (panel, HUD)

var flags := DevRules.default_flags()
var last_cursor := Vector2.INF   # last world position of the mouse over the game (not over a panel)
var pending_seed := 0            # seed for the next "Start run" (0 = random)
var attr_bonus := 0              # +N to every attribute (temporary buff, until you change zone)
# spawn choice used by the F3 hotkey (set from the panel)
var spawn_choice := {"id": "", "mods": [], "count": 1}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func cfg() -> Dictionary:
	return Data.dev_cfg

# ================================================================== state
## True when developer tools may act. Off in bots and tests unless Game.dev_in_tests.
func enabled() -> bool:
	if not bool(Game.settings.get("dev_tools", false)):
		return false
	return not Game.testing or Game.dev_in_tests

## Settings checkbox. Switching off resets every flag to its default.
func set_enabled(on: bool) -> void:
	Game.settings["dev_tools"] = on
	if not on:
		reset_flags()
	Game.save_settings()
	changed.emit()

func reset_flags() -> void:
	flags = DevRules.default_flags()
	attr_bonus = 0
	pending_seed = 0
	var p = _player()
	if p != null:
		_remove_attr_buff(p)
	Game.set_base_time_scale(1.0)
	_apply_hitboxes(false)
	_apply_pause()
	changed.emit()

# ---- hooks read by the game every frame / hit (cheap; defaults when off)
func god() -> bool:
	return flags["god"] and enabled()

func infinite_mana() -> bool:
	return flags["infinite_mana"] and enabled()

func no_cooldowns() -> bool:
	return flags["no_cooldowns"] and enabled()

func infinite_flasks() -> bool:
	return flags["infinite_flasks"] and enabled()

func freeze_ai() -> bool:
	return flags["freeze_ai"] and enabled()

func reveal_hidden() -> bool:
	return flags["reveal_hidden"] and enabled()

func frame_paused() -> bool:
	return flags["frame_pause"] and enabled()

func move_mult() -> float:
	return float(flags["move_mult"]) if enabled() else 1.0

func hit_mult() -> float:
	if float(flags["damage_mult"]) == 1.0 and not flags["one_hit"]:
		return 1.0
	return DevRules.hit_mult(cfg(), flags) if enabled() else 1.0

func loot_luck() -> float:
	if float(flags["loot_luck"]) == 1.0:
		return 1.0
	return float(flags["loot_luck"]) if enabled() else 1.0

# ================================================================== helpers
func _ok(msg: String) -> Dictionary:
	return {"ok": true, "msg": msg}

func _fail(msg: String) -> Dictionary:
	return {"ok": false, "msg": msg}

func _off() -> Dictionary:
	return _fail("Developer tools are off")

## Common gate: tools on and a character loaded.
func _gate() -> String:
	if not enabled():
		return "Developer tools are off"
	if Game.ch == null:
		return "No character loaded"
	return ""

func _taint() -> void:
	if Game.ch != null:
		Game.ch.dev_used = true

func _level():
	var lv = Game.level
	if lv == null or not is_instance_valid(lv):
		return null
	return lv

func _player():
	var lv = _level()
	if lv == null or lv.player == null or not is_instance_valid(lv.player):
		return null
	return lv.player

func _dungeon():
	var lv = _level()
	if lv == null or not ("objectives" in lv):
		return null
	return lv

func _fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out

## World cursor for "at cursor" actions: the mouse if it is over the game, else the
## last place it was over the game, else just in front of the player.
func cursor() -> Vector2:
	var p = _player()
	if last_cursor != Vector2.INF:
		return last_cursor
	return p.global_position + Vector2(40, 0) if p != null else Vector2.ZERO

func _floor_at(lv, pos: Vector2) -> Vector2:
	if not lv.is_solid(pos):
		return pos
	return lv.cell_center(lv.nearest_floor(lv.to_cell(pos)))

# ================================================================== hotkeys
func _unhandled_input(event: InputEvent) -> void:
	if not enabled():
		return
	var lv = _level()
	if lv == null:
		return
	if event is InputEventMouseMotion:
		last_cursor = lv.get_global_mouse_position()   # only reaches here when not over a panel
		return
	if event.is_action_pressed("dev_teleport"):
		_say(teleport_to(lv.get_global_mouse_position()))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("dev_spawn"):
		if spawn_choice["id"] == "":
			_say(_fail("Pick an enemy in the Developer panel (Dungeon tab) first"))
		else:
			_say(spawn_enemy(spawn_choice["id"], spawn_choice["mods"], int(spawn_choice["count"]), lv.get_global_mouse_position()))
		get_viewport().set_input_as_handled()

func _say(r: Dictionary) -> void:
	Events.message.emit(r["msg"], Color("#80e0ff") if r["ok"] else Color("#ff8080"))

# ================================================================== flags
func set_flag(flag: String, value) -> Dictionary:
	if not enabled():
		return _off()
	var d := DevRules.default_flags()
	if not d.has(flag):
		return _fail("Unknown flag " + flag)
	if typeof(d[flag]) == TYPE_FLOAT:
		value = float(value)
	if flag == "time_scale":
		value = DevRules.clamp_time_scale(cfg(), value)
	flags[flag] = value
	if DevRules.flag_taints(flag) and value != d[flag]:
		_taint()
	_apply_flag(flag)
	changed.emit()
	return _ok(_flag_text(flag, value))

func toggle_flag(flag: String) -> Dictionary:
	return set_flag(flag, not bool(flags.get(flag, false)))

func _flag_text(flag: String, value) -> String:
	var names := {"god": "God mode", "one_hit": "One-hit kills", "damage_mult": "Damage", "infinite_mana": "Infinite mana",
		"no_cooldowns": "No cooldowns", "infinite_flasks": "Infinite flasks", "move_mult": "Move speed", "freeze_ai": "Enemy AI frozen",
		"loot_luck": "Loot luck", "reveal_hidden": "Hidden items shown", "overlay": "Debug overlay", "hitboxes": "Hitboxes",
		"time_scale": "Time scale", "frame_pause": "World paused"}
	var n: String = names.get(flag, flag)
	if typeof(value) == TYPE_BOOL:
		return "%s %s" % [n, "ON" if value else "off"]
	return "%s x%s" % [n, str(snappedf(float(value), 0.01))]

func _apply_flag(flag: String) -> void:
	var p = _player()
	match flag:
		"time_scale":
			Game.set_base_time_scale(float(flags["time_scale"]))
		"hitboxes":
			_apply_hitboxes(bool(flags["hitboxes"]))
		"frame_pause":
			_apply_pause()
		"no_cooldowns":
			if flags["no_cooldowns"] and p != null:
				p.cooldowns.clear()
		"infinite_mana":
			if flags["infinite_mana"] and p != null:
				p.mana = Game.ch.final.get("max_mana", p.mana)
		"god":
			if flags["god"] and p != null:
				p.statuses.clear()
		"reveal_hidden":
			LootFilter.reveal_hidden = reveal_hidden() or Input.is_key_pressed(KEY_ALT)
			LootFilter.emit_signal("reveal_changed", LootFilter.reveal_hidden)

func _apply_pause() -> void:
	if Game.main != null and is_instance_valid(Game.main) and Game.main.ui != null:
		Game.main.ui._update_pause()
	elif is_inside_tree():
		get_tree().paused = frame_paused()

func _apply_hitboxes(on: bool) -> void:
	if not is_inside_tree():
		return
	get_tree().debug_collisions_hint = on
	# existing shapes only redraw when asked
	for n in get_tree().root.find_children("*", "CollisionShape2D", true, false):
		n.queue_redraw()

## Advances the paused world by one physics frame. The world is unpaused and Dev
## (which runs before the world each frame) pauses it again one frame later.
var _step_frames := 0

func step_frame() -> Dictionary:
	if not frame_paused():
		return _fail("Pause the world first")
	_step_frames = 2
	get_tree().paused = false
	return _ok("Stepped one frame")

func _physics_process(_delta: float) -> void:
	if _step_frames > 0:
		_step_frames -= 1
		if _step_frames == 0:
			_apply_pause()

# ================================================================== A. character
func set_level(n: int) -> Dictionary:
	var why := _gate()
	if why != "":
		return _fail(why)
	var ch = Game.ch
	var target := DevRules.clamp_level(cfg(), n)
	if target <= ch.level:
		return _fail("Already level %d (levels can only go up)" % ch.level)
	var amount := DevRules.xp_to_reach(ch.level, ch.xp, target, func(l): return CharacterData.xp_for_level(l))
	_taint()
	ch.add_xp(amount)   # the real level-up path: passive points, skill unlocks, events
	return _ok("Level %d (+%s XP)" % [ch.level, _fmt(amount)])

func add_levels(n: int) -> Dictionary:
	if Game.ch == null:
		return _fail(_gate() if _gate() != "" else "No character loaded")
	return set_level(Game.ch.level + n)

func set_max_level() -> Dictionary:
	return set_level(DevRules.max_level(cfg()))

## Raises the level to the last specialisation level so every spec point is available.
func spec_ready() -> Dictionary:
	if Game.ch == null:
		return _fail(_gate() if _gate() != "" else "No character loaded")
	var lvl := int(DevRules.cfg_value(cfg(), "spec_level", 44))
	if Game.ch.level >= lvl:
		return _ok("All specialisation points are already unlocked")
	return set_level(lvl)

func add_xp(n: int) -> Dictionary:
	var why := _gate()
	if why != "":
		return _fail(why)
	_taint()
	var before: int = Game.ch.level
	Game.ch.add_xp(n)
	var lv_txt: String = "" if Game.ch.level == before else " (level %d)" % Game.ch.level
	return _ok("+%s XP%s" % [_fmt(n), lv_txt])

func respec_passives() -> Dictionary:
	var why := _gate()
	if why != "":
		return _fail(why)
	var ch = Game.ch
	_taint()
	ch.allocated = [ch.class_def().get("start_passive", "")]
	ch.recalc()
	Events.passive_changed.emit()
	return _ok("Passives reset for free (%d points available)" % ch.available_passive_points())

func grant_passive_points(n: int) -> Dictionary:
	var why := _gate()
	if why != "":
		return _fail(why)
	_taint()
	Game.ch.bonus_passive_points += maxi(0, n)
	Events.passive_changed.emit()
	return _ok("+%d passive points" % n)

func unlock_all_skills() -> Dictionary:
	var why := _gate()
	if why != "":
		return _fail(why)
	var ch = Game.ch
	var n := 0
	for s in Data.skills_for_class(ch.class_id):
		if not ch.unlocked_skills.has(s["id"]):
			ch.unlocked_skills.append(s["id"])
			n += 1
	_taint()
	Events.loadout_changed.emit()
	return _ok("Unlocked %d skills (%d total)" % [n, ch.unlocked_skills.size()])

func full_heal() -> Dictionary:
	var why := _gate()
	if why != "":
		return _fail(why)
	var p = _player()
	if p == null:
		return _fail("No player in the world")
	p.life = p.max_life
	p.mana = Game.ch.final.get("max_mana", p.mana)
	p.statuses.clear()
	return _ok("Full life and mana, statuses cleared")

func full_mana() -> Dictionary:
	var why := _gate()
	if why != "":
		return _fail(why)
	var p = _player()
	if p == null:
		return _fail("No player in the world")
	p.mana = Game.ch.final.get("max_mana", p.mana)
	return _ok("Full mana")

func clear_statuses() -> Dictionary:
	var why := _gate()
	if why != "":
		return _fail(why)
	var p = _player()
	if p == null:
		return _fail("No player in the world")
	var n: int = p.statuses.size()
	p.statuses.clear()
	return _ok("Cleared %d status%s" % [n, "" if n == 1 else "es"])

## +step to every attribute as a temporary buff (lasts until you change zone).
func add_attributes() -> Dictionary:
	var why := _gate()
	if why != "":
		return _fail(why)
	var p = _player()
	if p == null:
		return _fail("No player in the world")
	attr_bonus += int(DevRules.cfg_value(cfg(), "attribute_step", 10))
	_remove_attr_buff(p)
	var mods := []
	for a in Data.attributes.get("order", ["str", "dex", "int", "vit", "agi", "wil"]):
		mods.append({"stat": a, "type": "flat", "value": attr_bonus})
	p.add_buff("dev_attributes", mods, 1.0e9)
	return _ok("+%d to every attribute (until you change zone)" % attr_bonus)

func _remove_attr_buff(p) -> void:
	for b in p.buffs.duplicate():
		if b["id"] == "dev_attributes":
			p.buffs.erase(b)
			p.refresh_stats()

# ================================================================== B. combat
func kill_all_enemies() -> Dictionary:
	var why := _gate()
	if why != "":
		return _fail(why)
	var lv = _level()
	var p = _player()
	if lv == null or p == null:
		return _fail("No level loaded")
	_taint()
	var n := 0
	for e in lv.enemies.duplicate():
		if is_instance_valid(e) and e.alive:
			e.die(p)   # the real kill: XP, loot, objectives, boss rewards
			n += 1
	return _ok("Killed %d enem%s" % [n, "y" if n == 1 else "ies"])

# ================================================================== C. economy
func add_gold(n: int) -> Dictionary:
	var why := _gate()
	if why != "":
		return _fail(why)
	_taint()
	var before: int = Game.ch.gold
	Game.ch.gold = DevRules.add_amount(cfg(), before, n)
	Events.currency_changed.emit()
	return _ok("%s%s gold (now %s)" % ["+" if n >= 0 else "", _fmt(Game.ch.gold - before), _fmt(Game.ch.gold)])

func set_gold(n: int) -> Dictionary:
	var why := _gate()
	if why != "":
		return _fail(why)
	_taint()
	Game.ch.gold = DevRules.set_amount(cfg(), n)
	Events.currency_changed.emit()
	return _ok("Gold set to %s" % _fmt(Game.ch.gold))

func add_material(id: String, n: int) -> Dictionary:
	var why := _gate()
	if why != "":
		return _fail(why)
	if not Data.materials.has(id):
		return _fail("Unknown material " + id)
	var cur := int(Game.ch.materials.get(id, 0))
	var add := DevRules.add_amount(cfg(), cur, n) - cur
	_taint()
	Game.ch.add_material(id, add)
	return _ok("+%s %s" % [_fmt(add), Data.materials[id].get("name", id)])

func add_all_materials(n: int) -> Dictionary:
	var why := _gate()
	if why != "":
		return _fail(why)
	for id in Data.materials:
		add_material(id, n)
	return _ok("+%s of every material (%d types)" % [_fmt(n), Data.materials.size()])

func gem_ids() -> Array:
	var out := []
	var tiers: int = Data.gem_cfg.get("tiers", []).size()
	for g in Data.gem_list:
		for t in tiers:
			out.append(Loot.gem_id(g["id"], t))
	return out

func add_gem(gid: String, n: int) -> Dictionary:
	var why := _gate()
	if why != "":
		return _fail(why)
	if not Loot.gem_valid(gid):
		return _fail("Unknown gem " + gid)
	_taint()
	Game.ch.add_gem(gid, maxi(0, n))
	return _ok("+%d %s" % [n, Loot.gem_name(gid)])

func add_all_gems(n: int = 1) -> Dictionary:
	var why := _gate()
	if why != "":
		return _fail(why)
	var ids := gem_ids()
	for gid in ids:
		add_gem(gid, n)
	return _ok("+%d of every gem (%d types x grades)" % [n, ids.size()])

func add_all_runes(n: int = 1) -> Dictionary:
	var why := _gate()
	if why != "":
		return _fail(why)
	_taint()
	for r in Data.skill_rune_list:
		Game.ch.add_rune(r["id"], n)
	return _ok("+%d of every skill rune (%d)" % [n, Data.skill_rune_list.size()])

## Charms are items (slot "charm"); one rare of each charm base.
func add_all_charms() -> Dictionary:
	var why := _gate()
	if why != "":
		return _fail(why)
	var n := 0
	var where := ""
	for b in Data.item_base_list:
		if b.get("slot", "") == "charm":
			var r := _give(Loot.roll_item_of(b["id"], "rare", maxi(Game.ch.level, int(b.get("req_level", 1)))))
			if r["ok"]:
				n += 1
				where = r["msg"]
	_taint()
	return _ok("Added %d charms" % n + (" (bag full: the rest dropped at your feet)" if where.contains("feet") else ""))

## One free stash tab through the real purchase (the price is granted, then paid).
func free_stash_tab(shared: bool = false) -> Dictionary:
	var why := _gate()
	if why != "":
		return _fail(why)
	var ch = Game.ch
	var cost: int = SharedStash.next_cost() if shared else ch.stash_next_cost()
	ch.gold += cost
	var refusal: String = SharedStash.buy_tab(ch) if shared else ch.buy_stash_tab()
	if refusal != "":
		ch.gold -= cost
		Events.currency_changed.emit()
		return _fail(refusal)
	_taint()
	var tabs: int = SharedStash.tab_total() if shared else ch.stash_tab_count()
	return _ok("Free %s stash tab (%d tabs)" % ["shared" if shared else "personal", tabs])

func all_stash_tabs(shared: bool = false) -> Dictionary:
	var why := _gate()
	if why != "":
		return _fail(why)
	var n := 0
	while free_stash_tab(shared)["ok"]:
		n += 1
		if n > 100:
			break
	var tabs: int = SharedStash.tab_total() if shared else Game.ch.stash_tab_count()
	return _ok("+%d %s tabs (%d tabs, the maximum)" % [n, "shared" if shared else "personal", tabs])

# ================================================================== D. items
## Puts an item in the bag, or at the player's feet when the bag is full.
func _give(it: Dictionary) -> Dictionary:
	var ch = Game.ch
	if it.is_empty():
		return _fail("Could not create the item")
	it["uid"] = ch.take_uid()
	if ch._fix_item(it.duplicate(true)) == null:
		return _fail("Item failed validation")
	if ch.add_to_bag(it):
		return {"ok": true, "msg": "%s added to your bag" % it["name"], "item": it}
	var lv = _level()
	var p = _player()
	if lv == null or p == null:
		return _fail("Bag full")
	lv.spawn_drop({"kind": "item", "item": it}, p.global_position + Vector2(0, 10))
	return {"ok": true, "msg": "%s dropped at your feet (bag full)" % it["name"], "item": it}

## Sets the corruption of the bag item in slot `bag_idx` through corruption_rules.set_level.
## Counts as dev use (taints the save), like the other item tools.
func set_item_corruption(bag_idx: int, value: int) -> Dictionary:
	var why := _gate()
	if why != "":
		return _fail(why)
	var ch = Game.ch
	if bag_idx < 0 or bag_idx >= ch.inventory.size() or ch.inventory[bag_idx] == null:
		return _fail("Pick a bag item first")
	var it: Dictionary = ch.inventory[bag_idx]
	CorruptionRules.set_level(it, value)
	_taint()
	Events.inventory_changed.emit()
	return _ok("%s: corruption set to %d%%" % [it.get("name", "Item"), CorruptionRules.get_level(it)])

## Clears one bag item back to 0%.
func clear_item_corruption(bag_idx: int) -> Dictionary:
	return set_item_corruption(bag_idx, 0)

## Clears every bag item back to 0%.
func clear_bag_corruption() -> Dictionary:
	var why := _gate()
	if why != "":
		return _fail(why)
	var ch = Game.ch
	var n := 0
	for it in ch.inventory:
		if it != null and CorruptionRules.get_level(it) > 0:
			CorruptionRules.set_level(it, 0)
			n += 1
	_taint()
	Events.inventory_changed.emit()
	return _ok("Corruption cleared on %d bag item%s" % [n, "" if n == 1 else "s"])

func unique_for_base(base_id: String) -> String:
	for u in Data.unique_list:
		if u.get("base", "") == base_id:
			return u["id"]
	return ""

func spawn_item(base_id: String, rarity: String, ilvl: int, sockets: int, max_roll: bool = false) -> Dictionary:
	var why := _gate()
	if why != "":
		return _fail(why)
	var probe := Loot.make_item(base_id, "common", 1) if Data.item_bases.has(base_id) else {}
	why = DevRules.spawn_refusal(cfg(), Data.item_bases, Data.rarities, base_id, rarity, ilvl, sockets, Loot.max_sockets(probe) if not probe.is_empty() else 0)
	if why != "":
		return _fail(why)
	var it: Dictionary
	if rarity == "legendary":
		var uid := unique_for_base(base_id)
		if uid == "":
			return _fail("No legendary uses this base (use Spawn legendary)")
		it = Loot.make_unique(uid, ilvl)
	else:
		it = Loot.roll_item_of(base_id, rarity, ilvl)
	set_sockets(it, sockets)
	if max_roll:
		max_roll_item(it)
	_taint()
	return _give(it)

func spawn_legendary(uid: String, ilvl: int = -1) -> Dictionary:
	var why := _gate()
	if why != "":
		return _fail(why)
	if not Data.uniques.has(uid):
		return _fail("Unknown legendary " + uid)
	var lvl := ilvl if ilvl > 0 else maxi(Game.ch.level, int(Data.uniques[uid].get("req_level", 1)))
	_taint()
	return _give(Loot.make_unique(uid, lvl))

func set_sockets(it: Dictionary, n: int) -> void:
	n = clampi(n, 0, Loot.max_sockets(it))
	it["sockets"] = n
	var g := []
	for i in n:
		g.append("")
	it["gems"] = g

## Every affix at the best tier its item level allows, with that tier's top value;
## legendary ranges at their maximum.
func max_roll_item(it: Dictionary) -> void:
	var ilvl := int(it.get("ilvl", 1))
	for a in it.get("affixes", []):
		var ad: Dictionary = Data.affixes.get(a.get("id", ""), {})
		if ad.is_empty():
			continue
		var r: Array = DevRules.max_affix_roll(ad.get("tiers", []), ilvl)
		a["tier"] = int(r[0]) + 1
		a["value"] = float(r[1])
		a["tier_ilvl"] = int(r[2])
	if it.has("unique"):
		var u: Dictionary = Data.uniques.get(it["unique"], {})
		var fixed := []
		for m in u.get("mods", []):
			var v := float(m["range"][1]) if m.has("range") else float(m.get("value", 0))
			fixed.append({"stat": m["stat"], "type": m["type"], "value": v})
		it["fixed"] = fixed
	Loot._update_req(it)

## Drops N items through the real drop path (level.spawn_drop), so the loot filter,
## beams, labels and sounds are exercised. rarity "" rolls rarity normally.
func drop_random(n: int, rarity: String = "") -> Dictionary:
	var why := _gate()
	if why != "":
		return _fail(why)
	var lv = _level()
	var p = _player()
	if lv == null or p == null:
		return _fail("No level loaded")
	if rarity != "" and not Data.rarities.has(rarity):
		return _fail("Unknown rarity")
	_taint()
	var pts: Array = DevRules.spread_points(p.global_position, n, float(DevRules.cfg_value(cfg(), "cursor_spawn_spread", 18)) + 2.0 * n)
	var ilvl: int = int(lv.monster_level) if "monster_level" in lv else Game.ch.level
	for pt in pts:
		lv.spawn_drop({"kind": "item", "item": Loot.roll_item(ilvl, 0.0, Game.ch.class_id, rarity)}, _floor_at(lv, pt))
	return _ok("Dropped %d %s items" % [n, rarity if rarity != "" else "random"])

func clear_bag() -> Dictionary:
	var why := _gate()
	if why != "":
		return _fail(why)
	var ch = Game.ch
	var n := 0
	for i in ch.inventory.size():
		if ch.inventory[i] != null:
			ch.reclaim_gems(ch.inventory[i])   # socketed gems go back to the pouch, as when selling
			ch.inventory[i] = null
			n += 1
	_taint()
	Events.inventory_changed.emit()
	return _ok("Bag cleared (%d items)" % n)

## Equips a rare item for every slot, at the character's level, through the normal equip path.
func decent_kit() -> Dictionary:
	var why := _gate()
	if why != "":
		return _fail(why)
	var ch = Game.ch
	_taint()
	var n := 0
	var two_handed := false
	var bow := false
	for slot in ch.EQUIP_SLOTS:
		var want: String = "ring" if slot in ["ring1", "ring2"] else slot
		var best := []
		var best_req := -1
		for b in Data.item_base_list:
			if b.get("slot", "") != want or int(b.get("req_level", 1)) > ch.level or not Loot.base_usable_by(b, ch.class_id):
				continue
			if slot == "off_hand" and two_handed and not (b.get("category", "") == "quiver" and bow):
				continue
			var req := int(b.get("req_level", 1))
			if req > best_req:
				best = [b["id"]]
				best_req = req
			elif req == best_req:
				best.append(b["id"])
		if best.is_empty():
			continue
		var it := Loot.roll_item_of(best[Loot.rng.randi() % best.size()], "rare", ch.level)
		it["uid"] = ch.take_uid()
		if not ch.add_to_bag(it):
			continue
		var idx: int = ch.inventory.find(it)
		if ch.equip_from_bag(idx, slot) == "":
			n += 1
			if slot == "main_hand":
				two_handed = it.get("two_handed", false)
				bow = it.get("tags", []).has("bow")
	return _ok("Equipped %d rare items (old gear is in your bag)" % n)

# ================================================================== E. dungeon & progression
func unlock_all_tiers() -> Dictionary:
	var why := _gate()
	if why != "":
		return _fail(why)
	var top := 1
	for d in Data.dungeon_list:
		top = maxi(top, int(d.get("tier", 1)))
	_taint()
	Game.ch.progress["highest_tier"] = top
	return _ok("All tiers unlocked (T1-T%d, including the Abyss)" % top)

## Starts a run in any dungeon from anywhere, with chosen run modifiers and depth.
func start_run(dungeon_id: String, mods: Array = [], depth: int = 1) -> Dictionary:
	var why := _gate()
	if why != "":
		return _fail(why)
	var def: Dictionary = Data.dungeons.get(dungeon_id, {})
	if def.is_empty():
		return _fail("Unknown dungeon")
	if Game.main == null or not is_instance_valid(Game.main):
		return _fail("Game not running")
	var clean := []
	for m in mods:
		if Data.dungeon_mods.has(m):
			clean.append(m)
	_taint()
	var s := pending_seed
	pending_seed = 0
	if not Game.main.enter_dungeon(dungeon_id, s, {"mods": clean, "depth": maxi(1, depth)}):
		return _fail("Could not build the dungeon")
	return _ok("Entered %s%s%s" % [def["name"], (" depth %d" % depth) if depth > 1 else "", (" with %d modifiers" % clean.size()) if clean.size() > 0 else ""])

func set_abyss_depth(depth: int) -> Dictionary:
	var abyss := ""
	for d in Data.dungeon_list:
		if d.get("endless", false):
			abyss = d["id"]
	if abyss == "":
		return _fail("No endless dungeon in the data")
	return start_run(abyss, Game.roll_run_mods(Data.dungeons[abyss]) if Game.ch != null else [], depth)

func current_objective(lv = null) -> Dictionary:
	if lv == null:
		lv = _dungeon()
	if lv == null:
		return {}
	for o in lv.objectives:
		if not o["done"]:
			return o
	return {}

## Completes the current objective through the real code paths (kills, interactions,
## relic pickups, wave ticks), so the boss arena unseals exactly as in play.
func complete_objective() -> Dictionary:
	var why := _gate()
	if why != "":
		return _fail(why)
	var lv = _dungeon()
	var p = _player()
	if lv == null or p == null:
		return _fail("Not in a dungeon")
	if lv.boss_dead:
		return _fail("Dungeon already complete")
	var o := current_objective(lv)
	if o.is_empty():
		return _fail("No objective left")
	_taint()
	var obj_name: String = lv._obj_name(o)
	match o["type"]:
		"guardian":
			if lv.guardian != null and is_instance_valid(lv.guardian) and lv.guardian.alive:
				lv.guardian.die(p)
		"mechanisms":
			for it in lv.interactables.duplicate():
				if String(it["kind"]).begins_with("mechanism_") and not o["done"]:
					lv.on_interact(it)
		"relics":
			var back: Vector2 = p.global_position
			for k in lv.markers.keys():
				var m = lv.markers.get(k)
				if String(k).begins_with("relic_") and m != null and is_instance_valid(m) and not o["done"]:
					p.global_position = m.global_position
					lv._check_relics()
			p.global_position = back
		"waves":
			if not lv.wave_state.get("active", false) and int(lv.wave_state.get("wave", 0)) == 0:
				for it in lv.interactables.duplicate():
					if it["kind"] == "altar":
						lv.on_interact(it)
			var guard := 0
			while not o["done"] and guard < 20 and lv.wave_state.get("active", false):
				guard += 1
				for e in lv.wave_state.get("alive", []).duplicate():
					if is_instance_valid(e) and e.alive:
						e.die(p)
				lv._tick_waves(0.0)
		"boss":
			if not lv.boss_spawned:
				lv._spawn_boss(lv.rooms[lv.layout["boss"]])
			if lv.boss != null and is_instance_valid(lv.boss) and lv.boss.alive:
				lv.boss.die(p)
	if not o["done"] and o["type"] != "boss":
		lv._complete(o)   # safety net: the objective could not be driven (missing marker)
	Events.objective_changed.emit(lv.objective_text())
	return _ok("Objective complete: %s" % obj_name)

## Completes every objective before the boss, then puts you inside the boss arena.
func teleport_to_boss() -> Dictionary:
	var why := _gate()
	if why != "":
		return _fail(why)
	var lv = _dungeon()
	var p = _player()
	if lv == null or p == null:
		return _fail("Not in a dungeon")
	var guard := 0
	while guard < 10:
		guard += 1
		var o := current_objective(lv)
		if o.is_empty() or o["type"] == "boss":
			break
		complete_objective()
	_taint()
	var br: Dictionary = lv.rooms[lv.layout["boss"]]
	p.global_position = _floor_at(lv, lv.cell_center(br["anchor"]) + Vector2(0, 40))
	p.velocity = Vector2.ZERO
	lv._track_room()   # spawns the boss now, as walking in would
	return _ok("Teleported into the boss arena")

func teleport_to(pos: Vector2) -> Dictionary:
	var why := _gate()
	if why != "":
		return _fail(why)
	var lv = _level()
	var p = _player()
	if lv == null or p == null:
		return _fail("No level loaded")
	p.global_position = _floor_at(lv, pos)
	p.velocity = Vector2.ZERO
	return _ok("Teleported")

func teleport_to_exit() -> Dictionary:
	var lv = _level()
	if lv == null:
		return _fail("No level loaded")
	for kind in ["exit_portal", "town_portal"]:
		for it in lv.interactables:
			if it["kind"] == kind:
				var r := teleport_to(it["pos"] + Vector2(0, 14))
				if r["ok"]:
					r["msg"] = "Teleported to the %s" % it["name"]
				return r
	return _fail("No portal here")

func return_to_hub() -> Dictionary:
	var why := _gate()
	if why != "":
		return _fail(why)
	if Game.main == null or not is_instance_valid(Game.main):
		return _fail("Game not running")
	Game.main.go_hub(false)   # the town portal path: keeps gear, no completion
	return _ok("Returned to town")

func spawn_enemy(id: String, mods: Array = [], count: int = 1, pos = null) -> Dictionary:
	var why := _gate()
	if why != "":
		return _fail(why)
	var lv = _level()
	var p = _player()
	if lv == null or p == null:
		return _fail("No level loaded")
	if not lv.allow_combat:
		return _fail("Enemies cannot be spawned in town")
	var def: Dictionary = Data.enemies.get(id, {})
	if def.is_empty():
		return _fail("Unknown enemy " + id)
	var clean := []
	for m in mods:
		if Data.elite_mods.has(m):
			clean.append(m)
	var at: Vector2 = pos if pos != null else cursor()
	var lvl: int = int(lv.monster_level) if "monster_level" in lv else Game.ch.level
	_taint()
	var made := []
	for pt in DevRules.spread_points(at, clampi(count, 1, 50), float(DevRules.cfg_value(cfg(), "cursor_spawn_spread", 18))):
		var e = lv.spawn_enemy(def, lvl, clean, _floor_at(lv, pt))
		e.aggro = true
		made.append(e)
		if e.is_boss:
			Events.boss_spawned.emit(e)
	return {"ok": true, "msg": "Spawned %d x %s%s" % [made.size(), def.get("name", id), (" (%s)" % ", ".join(clean)) if clean.size() > 0 else ""], "enemies": made}

# ================================================================== F. recent systems
func unlock_all_pets() -> Dictionary:
	var why := _gate()
	if why != "":
		return _fail(why)
	var ch = Game.ch
	var n := 0
	for pd in Data.pet_list:
		if ch.owns_pet(pd["id"]):
			continue
		var price := int(pd.get("price", 0))
		ch.gold += price          # the real purchase: grant the price, then buy
		if ch.buy_pet(pd["id"]) == "":
			n += 1
		else:
			ch.gold -= price
	_taint()
	Events.currency_changed.emit()
	return _ok("Unlocked %d pets (%d owned)" % [n, ch.pets.size()])

func set_pet_tier(t: int) -> Dictionary:
	var why := _gate()
	if why != "":
		return _fail(why)
	var ch = Game.ch
	var id: String = ch.active_pet
	if id == "":
		return _fail("No active pet")
	_taint()
	ch.pets[id]["tier"] = clampi(t, 0, PetRules.max_tier())
	Events.pet_changed.emit()
	return _ok("%s is now tier %d" % [ch.pet_name(id), ch.pet_tier(id)])

func rename_pet(nm: String) -> Dictionary:
	var why := _gate()
	if why != "":
		return _fail(why)
	var ch = Game.ch
	if ch.active_pet == "":
		return _fail("No active pet")
	ch.rename_pet(ch.active_pet, nm)
	return _ok("Pet renamed to %s" % ch.pet_name(ch.active_pet))

func stun_self() -> Dictionary:
	var why := _gate()
	if why != "":
		return _fail(why)
	var p = _player()
	if p == null:
		return _fail("No player in the world")
	if god():
		return _fail("God mode blocks stuns (turn it off first)")
	p.stun_immune_t = 0.0
	var dur: float = p.try_hit_stun(p.max_life, "player")   # the real stun roll, guaranteed by the size of the hit
	if dur <= 0.0:
		return _fail("Stuns are disabled in data/stun.json")
	return _ok("Stunned for %.2f s" % dur)

func _boss_target():
	var lv = _level()
	if lv == null:
		return null
	if "boss" in lv and lv.boss != null and is_instance_valid(lv.boss) and lv.boss.alive:
		return lv.boss
	for e in lv.enemies:
		if is_instance_valid(e) and e.alive and e.is_boss:
			return e
	return null

## Breaks the boss's poise: the same state change as a full poise bar, then the real stagger.
func break_boss_poise() -> Dictionary:
	var why := _gate()
	if why != "":
		return _fail(why)
	var b = _boss_target()
	if b == null:
		return _fail("No boss alive")
	var ps: Dictionary = b.poise_state
	var pc: Dictionary = Data.stun_cfg.get("poise", {})
	if ps.is_empty() or pc.is_empty():
		return _fail("Poise is disabled")
	ps["poise"] = 0.0
	ps["stagger"] = float(pc.get("stagger_duration", 1.0))
	ps["immune"] = float(pc.get("immunity_after_stagger", 8.0)) + float(pc.get("stagger_duration", 1.0))
	b._stagger()
	return _ok("%s staggered" % b.display_name)

## Which loot filter rule matches the item drop nearest the cursor (hidden ones too).
func filter_rule_at(pos = null) -> Dictionary:
	var why := _gate()
	if why != "":
		return _fail(why)
	var lv = _level()
	if lv == null:
		return _fail("No level loaded")
	var at: Vector2 = pos if pos != null else cursor()
	var best = null
	var bd := 80.0
	for n in lv.loot:
		if is_instance_valid(n) and n.kind == "item":
			var d: float = n.global_position.distance_to(at)
			if d < bd:
				bd = d
				best = n
	if best == null:
		return _fail("No item drop near the cursor")
	var tier := 0
	if "def" in lv and typeof(lv.def) == TYPE_DICTIONARY:
		tier = int(lv.def.get("tier", 0))
	var res: Dictionary = LootFilter.evaluate(best.item, {"player_level": Game.ch.level, "tier": tier})
	var rule: String = res.get("rule", "")
	var r := _ok("%s: %s (%s%s)" % [best.item.get("name", "?"), ("rule \"%s\"" % rule) if rule != "" else "no rule matched", res.get("visibility", "show"),
		", safety override" if res.get("safety_override", false) else ""])
	r["rule"] = rule
	return r

# ================================================================== G. debug & utilities
static func mix(parts: Array) -> int:
	# same mixing as tests/smartbot/smartbot.gd, so a bot seed can be replayed by hand
	var h: int = hash(parts) & 0x7fffffff
	return h if h != 0 else 1

## Seeds every game RNG the way the smartbot does, and uses the seed for the next run.
func set_seed(s: int) -> Dictionary:
	var why := _gate()
	if why != "":
		return _fail(why)
	if s == 0:
		return _fail("Seed 0 means random; pick another number")
	seed(s)
	Loot.set_seed(mix([s, "loot"]))
	Combat.rng.seed = mix([s, "combat"])
	pending_seed = s
	return _ok("RNG seeded with %d (the next Start run uses it)" % s)

func current_seed() -> int:
	var lv = _level()
	if lv != null and "run_seed" in lv:
		return int(lv.run_seed)
	return 0

func quick_save() -> Dictionary:
	var why := _gate()
	if why != "":
		return _fail(why)
	return _ok("Saved to slot %d and the autosave" % Game.current_slot) if Game.save_now() else _fail("Could not save")

func quick_load() -> Dictionary:
	var why := _gate()
	if why != "":
		return _fail(why)
	var slot: int = Game.current_slot
	if not Game.has_slot(slot):
		return _fail("Slot %d is empty" % slot)
	if not Game.load_game(slot):
		return _fail("Could not load slot %d" % slot)
	if Game.main != null and is_instance_valid(Game.main):
		Game.main.start_game()   # the normal load path: rebuild the hub around the loaded character
	return _ok("Loaded slot %d" % slot)

func diagnostics() -> String:
	var info := {"game": "Path of Dan", "engine": Engine.get_version_info().get("string", "4.0"),
		"save_version": CharacterData.SAVE_VERSION, "flags": ", ".join(DevRules.active_flags(flags)) if enabled() else "dev tools off"}
	var ch = Game.ch
	if ch != null:
		info["class"] = ch.class_id
		info["level"] = ch.level
		info["dev_used"] = ch.dev_used
	var lv = _level()
	if lv != null and "def" in lv and typeof(lv.def) == TYPE_DICTIONARY:
		info["dungeon"] = lv.def.get("id", "")
		info["tier"] = int(lv.def.get("tier", 0))
		info["depth"] = int(lv.depth)
		info["seed"] = int(lv.run_seed)
	elif lv != null:
		info["dungeon"] = "town"
	return DevRules.diagnostics(info)

func copy_diagnostics() -> Dictionary:
	var t := diagnostics()
	if DisplayServer.get_name() != "headless":
		DisplayServer.clipboard_set(t)
	return _ok("Diagnostic info copied to the clipboard")

## Lines for the HUD debug overlay.
func overlay_lines() -> Array:
	var out := []
	out.append("FPS %d" % Engine.get_frames_per_second())
	var lv = _level()
	var p = _player()
	if lv == null:
		return out
	var alive := 0
	for e in lv.enemies:
		if is_instance_valid(e) and e.alive:
			alive += 1
	out.append("Enemies %d   Projectiles %d" % [alive, lv.projectile_layer.get_child_count() if lv.projectile_layer != null else 0])
	if "run_seed" in lv:
		out.append("Seed %d   Room %d" % [int(lv.run_seed), int(lv.current_room)])
	if p != null:
		out.append("Player %d, %d   cell %s" % [int(p.global_position.x), int(p.global_position.y), str(lv.to_cell(p.global_position))])
	var c := cursor()
	out.append("Flow under cursor %d" % lv.flow_value(lv.to_cell(c)))
	if "mods" in lv and lv.mods.size() > 0:
		var names := []
		for m in lv.mods:
			names.append(m.get("name", "?"))
		out.append("Mods: " + ", ".join(names))
	out.append("Time x%s%s" % [str(snappedf(Game.base_time_scale, 0.01)), "  PAUSED" if frame_paused() else ""])
	return out
