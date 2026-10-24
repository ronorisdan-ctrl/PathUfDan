extends "res://scripts/ui/base_panel.gd"
## Dungeon selection: every tier with unlock state, recommended level, difficulty,
## boss info, objectives, rewards and the pre-rolled run modifiers.

var list: VBoxContainer
var detail: RichTextLabel
var enter_btn: Button
var reroll_btn: Button
var chosen := ""

func _init() -> void:
	place = "center"
	build("The Dungeon Gate", Vector2(760, 540))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	body.add_child(h)
	list = VBoxContainer.new()
	list.custom_minimum_size = Vector2(250, 460)
	h.add_child(list)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(470, 420)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	detail = UIKit.rich("", 450)
	sc.add_child(detail)
	var hb := HBoxContainer.new()
	enter_btn = UIKit.button("Enter Dungeon", _enter)
	enter_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(enter_btn)
	reroll_btn = UIKit.button("Reroll modifiers", _reroll)
	hb.add_child(reroll_btn)
	v.add_child(hb)

func _unlocked(d: Dictionary) -> bool:
	return int(d.get("tier", 1)) <= int(Game.ch.progress.get("highest_tier", 1))

func reroll_cost(d: Dictionary) -> int:
	return 20 * int(d.get("tier", 1))

func refresh() -> void:
	var ch = Game.ch
	for c in list.get_children():
		c.queue_free()
	for d in Data.dungeon_list:
		var unlocked := _unlocked(d)
		var b := UIKit.button(("Tier %d - %s" % [int(d["tier"]), d["name"]]) + ("" if unlocked else "  (locked)"), _choose.bind(d["id"]))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if d["id"] == chosen:
			b.add_theme_color_override("font_color", UIKit.GOLD)
		list.add_child(b)
	if chosen == "" or not Data.dungeons.has(chosen):
		for d in Data.dungeon_list:
			if _unlocked(d):
				chosen = d["id"]
	var d2: Dictionary = Data.dungeons.get(chosen, {})
	if d2.is_empty():
		detail.text = "No dungeon selected"
		enter_btn.disabled = true
		return
	var unlocked2 := _unlocked(d2)
	var kills: int = int(ch.progress["bosses_killed"].get(chosen, 0))
	var ml := clampi(ch.level, int(d2.get("min_level", 1)), int(d2.get("max_level", 10)))
	var lines := [
		"[font_size=18][color=#e8c890]%s[/color][/font_size]" % d2["name"],
		"[color=#8a8494]Tier %d   Recommended level %s   Difficulty: %s[/color]" % [int(d2["tier"]), d2.get("recommended", "?"), d2.get("difficulty", "?")],
		"", d2.get("desc", ""), "",
	]
	if not unlocked2:
		lines.append("[color=#ff8080]Locked - %s[/color]" % d2.get("unlock_text", ""))
		lines.append("")
	if ch.level < int(d2.get("min_level", 1)) - 2:
		lines.append("[color=#ff8080]Warning: you are well below the recommended level.[/color]")
	lines.append("[color=#c8a060]Monster level:[/color] %d (scales with you from %d to %d)" % [ml, int(d2.get("min_level", 1)), int(d2.get("max_level", 10))])
	lines.append("[color=#c8a060]Monsters:[/color] %d%% more life, %d%% more damage, +%d%% resistances" % [int(round((float(d2.get("life_mult", 1)) - 1) * 100)), int(round((float(d2.get("damage_mult", 1)) - 1) * 100)), int(d2.get("resist_bonus", 0))])
	lines.append("[color=#c8a060]Objectives:[/color] %s" % d2.get("objective", ""))
	lines.append("[color=#c8a060]Boss:[/color] %s" % d2.get("boss_info", ""))
	if d2.get("hazards", []).size() > 0:
		lines.append("[color=#c8a060]Hazards:[/color] %s" % ", ".join(d2["hazards"]))
	lines.append("[color=#c8a060]Rewards:[/color] %s (+%d%% item rarity)" % [d2.get("rewards", ""), int(d2.get("rarity_bonus", 0))])
	var pr: Dictionary = Game.prepared_run(d2)
	var mods: Array = pr.get("mods", [])
	if mods.is_empty():
		lines.append("[color=#c8a060]Modifiers:[/color] none")
	else:
		var total := 0
		lines.append("[color=#c8a060]Modifiers for your next run:[/color]")
		for id in mods:
			var m: Dictionary = Data.dungeon_mods.get(id, {})
			total += int(m.get("reward", 0))
			lines.append("  [color=#ff9070]%s[/color] - %s  [color=#80e080](+%d%% rewards)[/color]" % [m.get("name", id), m.get("desc", ""), int(m.get("reward", 0))])
		lines.append("  [color=#80e080]Total: +%d%% item quantity, rarity and experience[/color]" % total)
	if d2.get("endless", false):
		lines.append("[color=#c8a060]Deepest depth reached:[/color] %d" % int(ch.progress.get("abyss_best", 0)))
	lines.append("[color=#c8a060]Boss defeated:[/color] %d time%s" % [kills, "" if kills == 1 else "s"])
	detail.text = "\n".join(lines)
	enter_btn.disabled = not unlocked2
	reroll_btn.disabled = not unlocked2 or int(d2.get("mod_count", [0, 0])[1]) == 0
	reroll_btn.text = "Reroll modifiers (%d gold)" % reroll_cost(d2)

func _choose(id: String) -> void:
	chosen = id
	refresh()

func _reroll() -> void:
	var d: Dictionary = Data.dungeons.get(chosen, {})
	var ch = Game.ch
	if ch.gold < reroll_cost(d):
		ui.toast("Not enough gold", UIKit.BAD)
		return
	ch.gold -= reroll_cost(d)
	Game.reroll_prepared(d)
	Events.currency_changed.emit()
	refresh()

func _enter() -> void:
	if chosen == "" or not _unlocked(Data.dungeons.get(chosen, {})):
		return
	ui.close_all()
	Game.main.enter_dungeon(chosen)
