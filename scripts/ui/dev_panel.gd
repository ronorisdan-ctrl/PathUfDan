extends "res://scripts/ui/base_panel.gd"
## Developer panel (F1, or Pause > Developer tools). Only usable while
## Settings > Developer tools is on. Every button calls one Dev action and shows
## its result as a toast. Presets come from data/dev_tools.json.

const DevRules = preload("res://scripts/core/dev_rules.gd")

const RARITIES := ["common", "uncommon", "rare", "epic", "legendary"]

var off_label: Label
var tabs: TabContainer
var flag_boxes := {}        # flag -> CheckBox
var mult_rows := {}         # flag -> [[value, Button], ...]
var level_spin: SpinBox
var gold_spin: SpinBox
var gem_type: OptionButton
var gem_grade: OptionButton
var gem_spin: SpinBox
var base_filter: LineEdit
var base_pick: OptionButton
var rarity_pick: OptionButton
var ilvl_spin: SpinBox
var socket_spin: SpinBox
var max_roll: CheckBox
var uniq_pick: OptionButton
var drop_rarity: OptionButton
var dungeon_pick: OptionButton
var run_mod_boxes := {}
var depth_spin: SpinBox
var enemy_pick: OptionButton
var elite_boxes := {}
var spawn_count := 1
var count_btns := []
var abyss_spin: SpinBox
var pet_tier_spin: SpinBox
var pet_name_edit: LineEdit
var time_slider: HSlider
var time_label: Label
var seed_edit: LineEdit
var seed_label: Label
var status_label: Label

func _init() -> void:
	place = "right"
	build("Developer Tools", Vector2(580, 620))
	off_label = UIKit.label("Developer tools are off. Turn them on in Settings (main menu or pause menu).", 13, UIKit.MUTED)
	off_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	off_label.custom_minimum_size = Vector2(540, 0)
	body.add_child(off_label)
	status_label = UIKit.label("", 12, UIKit.MUTED)
	body.add_child(status_label)
	tabs = TabContainer.new()
	tabs.custom_minimum_size = Vector2(556, 520)
	body.add_child(tabs)
	_build_character(_tab("Character"))
	_build_combat(_tab("Combat"))
	_build_economy(_tab("Economy"))
	_build_items(_tab("Items"))
	_build_dungeon(_tab("Dungeon"))
	_build_systems(_tab("Systems"))
	_build_debug(_tab("Debug"))
	Dev.changed.connect(func(): if visible: refresh())

# ================================================================== builders
func _tab(t: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = t
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(sc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	return v

func _head(parent: Control, t: String) -> void:
	parent.add_child(UIKit.label(t, 14, UIKit.GOLD))

func _row(parent: Control, t: String = "") -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	if t != "":
		var l := UIKit.label(t, 13, UIKit.TEXT)
		l.custom_minimum_size = Vector2(104, 0)
		h.add_child(l)
	parent.add_child(h)
	return h

func _flow(parent: Control) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.custom_minimum_size = Vector2(530, 0)
	parent.add_child(f)
	return f

## A button that runs a Dev action (Callable returning {ok, msg}) and toasts the result.
func _btn(parent: Control, t: String, tip: String, action: Callable) -> Button:
	var b := UIKit.button(t, func(): _run(action.call()))
	b.tooltip_text = tip
	parent.add_child(b)
	return b

func _run(r) -> void:
	if typeof(r) != TYPE_DICTIONARY:
		return
	if ui != null:
		ui.toast(r.get("msg", ""), UIKit.GOOD if r.get("ok", false) else UIKit.BAD)
	refresh()

func _check(parent: Control, flag: String, t: String, tip: String) -> CheckBox:
	var c := CheckBox.new()
	c.text = t
	c.tooltip_text = tip
	c.toggled.connect(func(on):
		if bool(Dev.flags.get(flag, false)) != on:
			_run(Dev.set_flag(flag, on)))
	parent.add_child(c)
	flag_boxes[flag] = c
	return c

## A row of preset buttons for a multiplier flag; the current one is highlighted.
func _mult_row(parent: Control, t: String, flag: String, key: String, tip: String) -> void:
	var h := _row(parent, t)
	var list := []
	for v in DevRules.cfg_value(Data.dev_cfg, key, [1]):
		var val := float(v)
		var b := UIKit.button("x%s" % str(v), func(): _run(Dev.set_flag(flag, val)), 46)
		b.tooltip_text = tip + " (x%s)" % str(v)
		h.add_child(b)
		list.append([val, b])
	mult_rows[flag] = list

func _spin(parent: Control, lo: float, hi: float, val: float, step: float = 1.0, w: int = 90) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = val
	s.custom_minimum_size = Vector2(w, 0)
	parent.add_child(s)
	return s

func _option(parent: Control, items: Array, w: int = 160) -> OptionButton:
	## items: [[label, id_string], ...]
	var o := OptionButton.new()
	o.custom_minimum_size = Vector2(w, 0)
	o.clip_text = true
	for i in items.size():
		o.add_item(items[i][0], i)
		o.set_item_metadata(i, items[i][1])
	parent.add_child(o)
	return o

func _picked(o: OptionButton) -> String:
	if o.selected < 0:
		return ""
	return str(o.get_item_metadata(o.selected))

func _steps(key: String, fallback: Array) -> Array:
	return DevRules.cfg_value(Data.dev_cfg, key, fallback)

func _num(n) -> String:
	var v := int(n)
	if v >= 1000000 and v % 1000000 == 0:
		return "%dM" % (v / 1000000)
	if v >= 1000 and v % 1000 == 0:
		return "%dk" % (v / 1000)
	return str(v)

# ---------------------------------------------------------------- A. character
func _build_character(v: VBoxContainer) -> void:
	_head(v, "Level and experience (real level-ups: passive points, skills, specialisations)")
	var h := _row(v, "Level")
	for n in _steps("level_steps", [1, 5, 10]):
		_btn(h, "+%d" % n, "Gain %d levels through the normal level-up (XP bar stays correct)" % n, Dev.add_levels.bind(int(n)))
	level_spin = _spin(h, 1, DevRules.max_level(Data.dev_cfg), 10, 1, 70)
	_btn(h, "Set", "Raise the level to the number on the left (levels can only go up)", func(): return Dev.set_level(int(level_spin.value)))
	_btn(h, "Max", "Raise the level to %d" % DevRules.max_level(Data.dev_cfg), Dev.set_max_level)
	var hx := _row(v, "Experience")
	for n in _steps("xp_steps", [1000, 10000, 100000]):
		_btn(hx, "+%s XP" % _num(n), "Add %d experience" % int(n), Dev.add_xp.bind(int(n)))
	_head(v, "Passives and skills")
	var hp := _row(v, "Passives")
	_btn(hp, "Free respec", "Unallocate every passive for free", Dev.respec_passives)
	for n in _steps("passive_point_steps", [1, 5, 20]):
		_btn(hp, "+%d pts" % n, "Grant %d bonus passive points" % n, Dev.grant_passive_points.bind(int(n)))
	var hs := _row(v, "Skills")
	_btn(hs, "Unlock all skills", "Every skill of your class becomes available for the hotbar", Dev.unlock_all_skills)
	_btn(hs, "+1 every rune", "Add one of every skill rune to your rune pouch", Dev.add_all_runes.bind(1))
	_btn(hs, "Spec points", "Raise to level %d so all five specialisation points are unlocked" % int(DevRules.cfg_value(Data.dev_cfg, "spec_level", 44)), Dev.spec_ready)
	_head(v, "Life and statuses")
	var hl := _row(v, "Recovery")
	_btn(hl, "Full heal", "Full life and mana, clears every status", Dev.full_heal)
	_btn(hl, "Full mana", "Fill the mana pool", Dev.full_mana)
	_btn(hl, "Clear statuses", "Removes stun, freeze, poison, agony, frailty, marked, snare and the rest", Dev.clear_statuses)
	var ha := _row(v, "Attributes")
	_btn(ha, "+%d to each" % int(DevRules.cfg_value(Data.dev_cfg, "attribute_step", 10)), "Temporary buff to every attribute; lasts until you change zone", Dev.add_attributes)

# ---------------------------------------------------------------- B. combat
func _build_combat(v: VBoxContainer) -> void:
	_head(v, "Survivability and combat (runtime only, reset when the tools are switched off)")
	var f := _flow(v)
	_check(f, "god", "God mode", "No damage, damage over time, stun or status reaches you (hits still land)")
	_check(f, "one_hit", "One-hit kills", "Your hits are multiplied by %s" % str(DevRules.cfg_value(Data.dev_cfg, "one_hit_mult", 1000)))
	_check(f, "infinite_mana", "Infinite mana", "Skills cost no mana (or life)")
	_check(f, "no_cooldowns", "No cooldowns", "Skills never go on cooldown")
	_check(f, "infinite_flasks", "Infinite flasks", "Flasks never lose charges")
	_check(f, "freeze_ai", "Freeze enemy AI", "Enemies stand still and never attack (good for checking skills and visuals)")
	_mult_row(v, "Damage", "damage_mult", "damage_mults", "Multiply every hit you deal")
	_mult_row(v, "Move speed", "move_mult", "move_mults", "Multiply your movement speed")
	var h := _row(v, "Enemies")
	_btn(h, "Kill all enemies", "Kills every enemy on the level as a real kill (XP, loot, objectives)", Dev.kill_all_enemies)

# ---------------------------------------------------------------- C. economy
func _build_economy(v: VBoxContainer) -> void:
	_head(v, "Gold")
	var h := _row(v, "Gold")
	for n in _steps("gold_steps", [1000, 10000, 100000, 1000000]):
		_btn(h, "+%s" % _num(n), "Add %d gold" % int(n), Dev.add_gold.bind(int(n)))
	var h2 := _row(v, "")
	h2.add_child(UIKit.label("Set to", 13))
	gold_spin = _spin(h2, 0, 2000000000, 1000, 1, 120)
	_btn(h2, "Set", "Set gold to the number on the left", func(): return Dev.set_gold(int(gold_spin.value)))
	_btn(h2, "Set to 0", "Set gold to zero", Dev.set_gold.bind(0))
	_head(v, "Materials")
	for id in Data.materials:
		var hm := _row(v, str(Data.materials[id].get("name", id)))
		for n in _steps("material_steps", [100, 1000, 10000]):
			_btn(hm, "+%s" % _num(n), "Add %d %s" % [int(n), Data.materials[id].get("name", id)], Dev.add_material.bind(id, int(n)))
	var all_n := int(DevRules.cfg_value(Data.dev_cfg, "material_all", 1000))
	_btn(_row(v, ""), "+%s of every material" % _num(all_n), "Add %d of each material type" % all_n, Dev.add_all_materials.bind(all_n))
	_head(v, "Gems, runes and charms")
	var hg := _row(v, "Gem")
	var types := []
	for g in Data.gem_list:
		types.append([g.get("name", g["id"]), g["id"]])
	gem_type = _option(hg, types, 110)
	var grades := []
	var tiers: Array = Data.gem_cfg.get("tiers", [])
	for i in tiers.size():
		grades.append([tiers[i].get("name", "Grade %d" % (i + 1)), str(i)])
	gem_grade = _option(hg, grades, 100)
	gem_spin = _spin(hg, 1, 999, 1, 1, 70)
	_btn(hg, "Add", "Add N gems of the chosen type and grade", func(): return Dev.add_gem(Loot.gem_id(_picked(gem_type), int(_picked(gem_grade))), int(gem_spin.value)))
	var hr := _row(v, "")
	_btn(hr, "One of every gem", "Add one gem of every type and grade", Dev.add_all_gems.bind(1))
	_btn(hr, "One of every rune", "Add one of every skill rune", Dev.add_all_runes.bind(1))
	_btn(hr, "One of every charm", "Add one rare of every charm base", Dev.add_all_charms)
	_head(v, "Stash tabs (bought through the normal purchase, price refunded)")
	var ht := _row(v, "Personal")
	_btn(ht, "+1 free tab", "Buy one personal stash tab for free", Dev.free_stash_tab.bind(false))
	_btn(ht, "All tabs", "Buy every remaining personal stash tab for free", Dev.all_stash_tabs.bind(false))
	var ht2 := _row(v, "Shared")
	_btn(ht2, "+1 free tab", "Buy one shared stash tab for free", Dev.free_stash_tab.bind(true))
	_btn(ht2, "All tabs", "Buy every remaining shared stash tab for free", Dev.all_stash_tabs.bind(true))

# ---------------------------------------------------------------- D. items
func _build_items(v: VBoxContainer) -> void:
	_head(v, "Spawn item (goes to the bag, or your feet when it is full)")
	var h := _row(v, "Base")
	base_filter = LineEdit.new()
	base_filter.placeholder_text = "filter..."
	base_filter.custom_minimum_size = Vector2(110, 0)
	base_filter.tooltip_text = "Type to filter the base list"
	base_filter.text_changed.connect(func(_t): _fill_bases())
	h.add_child(base_filter)
	base_pick = _option(h, [], 300)
	base_pick.tooltip_text = "Item base (data/item_bases.json)"
	_fill_bases()
	var h2 := _row(v, "Rarity")
	var rl := []
	for r in RARITIES:
		rl.append([r.capitalize(), r])
	rarity_pick = _option(h2, rl, 110)
	rarity_pick.select(2)
	h2.add_child(UIKit.label(" ilvl", 13))
	ilvl_spin = _spin(h2, 1, int(DevRules.cfg_value(Data.dev_cfg, "spawn_ilvl_max", 100)), 10, 1, 70)
	h2.add_child(UIKit.label(" sockets", 13))
	socket_spin = _spin(h2, 0, 3, 0, 1, 60)
	var h3 := _row(v, "")
	max_roll = CheckBox.new()
	max_roll.text = "Max-roll affixes"
	max_roll.tooltip_text = "Best affix tier the item level allows, top value"
	h3.add_child(max_roll)
	_btn(h3, "Spawn item", "Create the item with the settings above", func():
		return Dev.spawn_item(_picked(base_pick), _picked(rarity_pick), int(ilvl_spin.value), int(socket_spin.value), max_roll.button_pressed))
	_head(v, "Legendaries")
	var hu := _row(v, "Legendary")
	var ul := []
	for u in Data.unique_list:
		ul.append([u.get("name", u["id"]), u["id"]])
	uniq_pick = _option(hu, ul, 240)
	_btn(hu, "Spawn legendary", "Create the chosen legendary at your level", func(): return Dev.spawn_legendary(_picked(uniq_pick)))
	_head(v, "Drops (the real drop path: filter, beams, labels and sounds)")
	var hd := _row(v, "Drop")
	var dr := [["Any rarity", ""]]
	for r in RARITIES:
		dr.append([r.capitalize(), r])
	drop_rarity = _option(hd, dr, 110)
	for n in _steps("drop_counts", [5, 10, 25]):
		_btn(hd, "%d items" % n, "Drop %d items of the chosen rarity at your feet" % n, func(): return Dev.drop_random(int(n), _picked(drop_rarity)))
	_mult_row(v, "Loot luck", "loot_luck", "loot_luck", "Multiply drop chance and rarity while on")
	var hf := _row(v, "Filter")
	_check(hf, "reveal_hidden", "Reveal hidden items", "Show items the loot filter hides (same as holding Alt)")
	_head(v, "Bag")
	var hb := _row(v, "")
	var cb := UIKit.button("Clear bag", func():
		if ui != null:
			ui.ask("Destroy every item in your bag? Socketed gems go back to your pouch.", func(): _run(Dev.clear_bag()))
		else:
			_run(Dev.clear_bag()))
	cb.tooltip_text = "Destroy everything in the bag (asks first)"
	hb.add_child(cb)
	_btn(hb, "Give me a decent kit", "Equip a rare item in every slot at your level (old gear goes to the bag)", Dev.decent_kit)

func _fill_bases() -> void:
	if base_pick == null:
		return
	var keep := _picked(base_pick)
	base_pick.clear()
	var ft := base_filter.text.strip_edges().to_lower() if base_filter != null else ""
	var i := 0
	for b in Data.item_base_list:
		var label := "%s  (%s, lvl %d)" % [b.get("name", b["id"]), b.get("slot", ""), int(b.get("req_level", 1))]
		if ft != "" and not label.to_lower().contains(ft) and not String(b["id"]).contains(ft):
			continue
		base_pick.add_item(label, i)
		base_pick.set_item_metadata(i, b["id"])
		if b["id"] == keep:
			base_pick.select(i)
		i += 1

# ---------------------------------------------------------------- E. dungeon
func _build_dungeon(v: VBoxContainer) -> void:
	var h := _row(v, "Progression")
	_btn(h, "Unlock all tiers", "Unlock tiers 1-6 including the Endless Abyss", Dev.unlock_all_tiers)
	_btn(h, "Return to town", "Leave the dungeon the normal way (keeps gear)", Dev.return_to_hub)
	var hr := _row(v, "Start run")
	var dl := []
	for d in Data.dungeon_list:
		dl.append(["T%d %s" % [int(d.get("tier", 1)), d["name"]], d["id"]])
	dungeon_pick = _option(hr, dl, 250)
	hr.add_child(UIKit.label(" depth", 13))
	depth_spin = _spin(hr, 1, 99, 1, 1, 64)
	_btn(hr, "Go", "Start a run in this dungeon now, with the modifiers ticked below", _start_run)
	var f := _flow(v)
	for m in Data.dungeon_mod_list:
		var c := CheckBox.new()
		c.text = m.get("name", m["id"])
		c.tooltip_text = m.get("desc", "")
		f.add_child(c)
		run_mod_boxes[m["id"]] = c
	var ho := _row(v, "Objectives")
	_btn(ho, "Complete objective", "Complete the current objective through the real code path (the arena unseals as in play)", Dev.complete_objective)
	_btn(ho, "Teleport to boss", "Complete everything before the boss, then step into the boss arena", Dev.teleport_to_boss)
	var ht := _row(v, "Teleport")
	_btn(ht, "To cursor (F2)", "Teleport to where the mouse last was over the game", func(): return Dev.teleport_to(Dev.cursor()))
	_btn(ht, "To exit portal", "Teleport to the exit portal (or the town portal before the boss is dead)", Dev.teleport_to_exit)
	var hab := _row(v, "Abyss depth")
	abyss_spin = _spin(hab, 1, 99, 5, 1, 70)
	_btn(hab, "Descend", "Start the Endless Abyss at this depth", func(): return Dev.set_abyss_depth(int(abyss_spin.value)))
	_head(v, "Spawn enemy (at the cursor; F3 repeats it)")
	var he := _row(v, "Enemy")
	var el := []
	for id in Data.enemies:
		var e: Dictionary = Data.enemies[id]
		el.append(["%s%s" % [e.get("name", id), "  (boss)" if e.get("boss", false) else ""], id])
	el.sort_custom(func(a, b): return a[0] < b[0])
	enemy_pick = _option(he, el, 190)
	enemy_pick.item_selected.connect(func(_i): _sync_spawn_choice())
	for n in _steps("spawn_counts", [1, 5, 10]):
		var pick_count := func():
			spawn_count = int(n)
			_sync_spawn_choice()
			refresh()
		var b := UIKit.button("x%d" % n, pick_count, 40)
		b.tooltip_text = "Spawn %d at a time" % n
		he.add_child(b)
		count_btns.append([int(n), b])
	var spawn_now := func():
		_sync_spawn_choice()
		return Dev.spawn_enemy(_picked(enemy_pick), _ticked(elite_boxes), spawn_count)
	_btn(he, "Spawn", "Spawn the chosen enemy (with ticked elite mods) where the mouse last was over the game", spawn_now)
	var f2 := _flow(v)
	for m in Data.elite_mod_list:
		var c2 := CheckBox.new()
		c2.text = m.get("name", m["id"])
		c2.tooltip_text = "Elite modifier"
		c2.toggled.connect(func(_on): _sync_spawn_choice())
		f2.add_child(c2)
		elite_boxes[m["id"]] = c2
	_sync_spawn_choice()

func _ticked(boxes: Dictionary) -> Array:
	var out := []
	for k in boxes:
		if boxes[k].button_pressed:
			out.append(k)
	return out

func _sync_spawn_choice() -> void:
	if enemy_pick == null:
		return
	Dev.spawn_choice = {"id": _picked(enemy_pick), "mods": _ticked(elite_boxes), "count": spawn_count}

func _start_run():
	var r = Dev.start_run(_picked(dungeon_pick), _ticked(run_mod_boxes), int(depth_spin.value))
	if r.get("ok", false) and ui != null:
		ui.close(panel_name)
	return r

# ---------------------------------------------------------------- F. systems
func _build_systems(v: VBoxContainer) -> void:
	_head(v, "Pets")
	var h := _row(v, "Pets")
	_btn(h, "Unlock all pets", "Own every pet (bought through the normal purchase, price refunded)", Dev.unlock_all_pets)
	var h2 := _row(v, "Active pet tier")
	pet_tier_spin = _spin(h2, 0, 5, 5, 1, 60)
	_btn(h2, "Set tier", "Set the active pet's tier (0-5)", func(): return Dev.set_pet_tier(int(pet_tier_spin.value)))
	var h3 := _row(v, "Rename")
	pet_name_edit = LineEdit.new()
	pet_name_edit.placeholder_text = "New name"
	pet_name_edit.custom_minimum_size = Vector2(180, 0)
	h3.add_child(pet_name_edit)
	_btn(h3, "Rename", "Rename the active pet (free)", func(): return Dev.rename_pet(pet_name_edit.text))
	_head(v, "Stun and poise")
	var hs := _row(v, "Stun")
	_btn(hs, "Stun myself", "Apply a hit stun to yourself through the real stun roll", Dev.stun_self)
	_btn(hs, "Break boss poise", "Fill the boss poise bar: the boss staggers", Dev.break_boss_poise)
	_head(v, "Loot filter")
	_btn(_row(v, ""), "Which rule matches the item at the cursor?", "Prints the loot filter rule for the item drop nearest the cursor (hidden ones too)", Dev.filter_rule_at)

# ---------------------------------------------------------------- G. debug
func _build_debug(v: VBoxContainer) -> void:
	_head(v, "Time")
	var h := _row(v, "Time scale")
	var ts: Dictionary = DevRules.cfg_value(Data.dev_cfg, "time_scale", {})
	time_slider = HSlider.new()
	time_slider.min_value = float(ts.get("min", 0.1))
	time_slider.max_value = float(ts.get("max", 4.0))
	time_slider.step = float(ts.get("step", 0.1))
	time_slider.value = 1.0
	time_slider.custom_minimum_size = Vector2(220, 0)
	time_slider.tooltip_text = "World speed (hit-stop still works on top of it)"
	time_slider.drag_ended.connect(func(_c): _run(Dev.set_flag("time_scale", time_slider.value)))
	h.add_child(time_slider)
	time_label = UIKit.label("x1.0", 13)
	h.add_child(time_label)
	_btn(h, "x1", "Normal speed", Dev.set_flag.bind("time_scale", 1.0))
	var hp := _row(v, "Frame")
	_check(hp, "frame_pause", "Pause world", "Freeze the world (UI still works); use Step to advance one frame")
	_btn(hp, "Step", "Advance the paused world by one physics frame", Dev.step_frame)
	_head(v, "Display")
	var hd := _row(v, "")
	_check(hd, "overlay", "Debug overlay", "FPS, enemy and projectile counts, seed, flow field under the cursor, position, room, modifiers")
	_check(hd, "hitboxes", "Draw hitboxes", "Godot collision shape debug draw")
	_head(v, "RNG seed (same seeding as the smartbot)")
	var hs := _row(v, "Seed")
	seed_edit = LineEdit.new()
	seed_edit.placeholder_text = "e.g. 4242"
	seed_edit.custom_minimum_size = Vector2(140, 0)
	hs.add_child(seed_edit)
	_btn(hs, "Set seed", "Seed every RNG now; the next Start run uses this seed for the dungeon", func(): return Dev.set_seed(int(seed_edit.text.to_int())))
	seed_label = UIKit.label("", 12, UIKit.MUTED)
	hs.add_child(seed_label)
	_head(v, "Save and diagnostics")
	var hq := _row(v, "")
	_btn(hq, "Quick save", "Save to the current slot and the autosave", Dev.quick_save)
	_btn(hq, "Quick load", "Reload the current slot (back to town)", Dev.quick_load)
	_btn(hq, "Copy diagnostic info", "Version, class, level, tier, seed and active dev flags to the clipboard", Dev.copy_diagnostics)

# ================================================================== refresh
func on_open() -> void:
	var ch = Game.ch
	if ch != null:
		level_spin.value = clampi(ch.level + 1, 1, int(level_spin.max_value))
		ilvl_spin.value = clampi(ch.level, 1, int(ilvl_spin.max_value))
	refresh()

func refresh() -> void:
	var on: bool = Dev.enabled()
	off_label.visible = not on
	tabs.visible = on
	if not on:
		status_label.text = ""
		return
	var ch = Game.ch
	if ch != null:
		status_label.text = "%s, level %d %s   Gold %s%s" % [ch.char_name, ch.level, ch.class_def().get("name", ch.class_id), Dev._fmt(ch.gold), "   (dev)" if ch.dev_used else ""]
	for flag in flag_boxes:
		flag_boxes[flag].set_pressed_no_signal(bool(Dev.flags.get(flag, false)))
	for flag in mult_rows:
		for pair in mult_rows[flag]:
			var b: Button = pair[1]
			var cur := absf(float(Dev.flags.get(flag, 1.0)) - float(pair[0])) < 0.001
			b.add_theme_color_override("font_color", UIKit.GOLD if cur else UIKit.TEXT)
	for pair in count_btns:
		pair[1].add_theme_color_override("font_color", UIKit.GOLD if pair[0] == spawn_count else UIKit.TEXT)
	var ts := float(Dev.flags.get("time_scale", 1.0))
	if time_slider != null:
		time_slider.value = ts
		time_label.text = "x%s" % str(snappedf(ts, 0.1))
	if seed_label != null:
		var s: int = Dev.current_seed()
		seed_label.text = ("run seed %d" % s if s != 0 else "not in a dungeon") + (("   next run: %d" % Dev.pending_seed) if Dev.pending_seed != 0 else "")
