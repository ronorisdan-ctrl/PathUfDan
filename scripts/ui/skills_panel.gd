extends "res://scripts/ui/base_panel.gd"
## Active skill loadout. Select a hotbar slot, then pick a skill for it.
## Changes are allowed in town or when no enemy is nearby.

var slot_bar: HBoxContainer
var list: VBoxContainer
var note: Label
var selected_slot := 0
var runes_label: RichTextLabel

class SkillIcon extends Control:
	var sk := {}
	var dim := false
	var sel := false
	var key_text := ""
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if sk.is_empty():
			draw_rect(r, Color(0.1, 0.09, 0.1))
		else:
			load("res://scripts/ui/ui_kit.gd").draw_skill_icon(self, r, sk, dim)
		draw_rect(r, Color("#ffd060") if sel else Color(0.35, 0.3, 0.25), false, 2.0 if sel else 1.0)
		if key_text != "":
			draw_string_outline(ThemeDB.fallback_font, Vector2(3, 12), key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color.BLACK)
			draw_string(ThemeDB.fallback_font, Vector2(3, 12), key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#f0e0b0"))

func _init() -> void:
	place = "center"
	build("Skills", Vector2(640, 640))
	body.add_child(UIKit.label("Hotbar - click a slot, then choose a skill below", 13, UIKit.MUTED))
	slot_bar = HBoxContainer.new()
	slot_bar.add_theme_constant_override("separation", 8)
	body.add_child(slot_bar)
	note = UIKit.label("", 12, UIKit.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	note.custom_minimum_size.x = 600
	body.add_child(note)
	runes_label = UIKit.rich("", 600)
	body.add_child(runes_label)
	body.add_child(HSeparator.new())
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(610, 440)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(sc)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	Events.loadout_changed.connect(refresh)
	Events.currency_changed.connect(refresh)
	Events.skill_unlocked.connect(func(_s): refresh())

func can_change() -> String:
	var lv = Game.level
	if lv == null:
		return ""
	if not lv.allow_combat:
		return ""
	var p = lv.player
	for e in lv.enemies:
		if is_instance_valid(e) and e.alive and e.aggro and e.global_position.distance_to(p.global_position) < 320:
			return "Cannot change skills while enemies are nearby"
	return ""

func refresh() -> void:
	var ch = Game.ch
	if ch == null or not visible:
		return
	for c in slot_bar.get_children():
		c.queue_free()
	var keys := ["LMB", "RMB", "Q", "E", "R", "T", "G"]
	for i in keys.size():
		var ic := SkillIcon.new()
		ic.custom_minimum_size = Vector2(56, 56)
		ic.sk = Data.skills.get(ch.loadout[i], {})
		ic.sel = i == selected_slot
		ic.key_text = keys[i]
		ic.mouse_filter = Control.MOUSE_FILTER_STOP
		ic.gui_input.connect(_slot_input.bind(i))
		ic.mouse_entered.connect(func():
			if not ic.sk.is_empty():
				ui.show_tooltip(UIKit.skill_tooltip(ch.resolved_skill(ic.sk["id"]), ch)))
		ic.mouse_exited.connect(func(): ui.hide_tooltip())
		slot_bar.add_child(ic)
	var why := can_change()
	note.text = why if why != "" else "Skill levels rise as you level up. Runes socket into skills (1 socket, +1 at skill level 6 and 12)."
	var owned := []
	for rid in ch.runes:
		owned.append("[color=%s]%s x%d[/color]" % [Data.skill_runes[rid]["color"], Data.skill_runes[rid]["name"].replace("Rune of ", "").replace(" Rune", ""), int(ch.runes[rid])])
	runes_label.text = "Runes: " + (", ".join(owned) if owned.size() > 0 else "[color=#8a8494]none yet - they drop from monsters and the merchant sells them[/color]")
	note.add_theme_color_override("font_color", UIKit.BAD if why != "" else UIKit.MUTED)
	for c in list.get_children():
		c.queue_free()
	for sk in Data.skills_for_class(ch.class_id):
		var unlocked: bool = ch.unlocked_skills.has(sk["id"])
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		var ic2 := SkillIcon.new()
		ic2.custom_minimum_size = Vector2(44, 44)
		ic2.sk = sk
		ic2.dim = not unlocked
		ic2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(ic2)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var title := "%s  (Lv %d)" % [sk["name"], ch.skill_level(sk["id"])] if unlocked else "%s  - unlocks at level %d" % [sk["name"], int(sk.get("unlock_level", 1))]
		var tl := UIKit.label(title, 14, UIKit.TEXT if unlocked else UIKit.MUTED)
		tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(tl)
		var dl := UIKit.label(sk.get("desc", ""), 11, UIKit.MUTED)
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD
		dl.custom_minimum_size.x = 420
		dl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(dl)
		row.add_child(v)
		if ch.loadout.has(sk["id"]):
			var on := UIKit.label("[%s]" % keys[ch.loadout.find(sk["id"])], 12, UIKit.GOLD)
			on.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(on)
		if unlocked:
			var sockets := HBoxContainer.new()
			var cur: Array = ch.skill_runes.get(sk["id"], [])
			for si in 3:
				var b := Button.new()
				b.custom_minimum_size = Vector2(0, 22)
				b.add_theme_font_size_override("font_size", 11)
				if si < cur.size():
					var rd: Dictionary = Data.skill_runes.get(cur[si], {})
					b.text = rd.get("name", "?").replace("Rune of ", "").replace(" Rune", "")
					b.add_theme_color_override("font_color", Color(rd.get("color", "#ffffff")))
					b.tooltip_text = rd.get("desc", "") + "\nClick to remove (the rune returns to you)"
					b.pressed.connect(_unsocket.bind(sk["id"], si))
				elif si < ch.rune_sockets(sk["id"]):
					b.text = "+ rune"
					b.pressed.connect(_socket_menu.bind(sk["id"]))
				else:
					b.text = "locked"
					b.disabled = true
					b.tooltip_text = "Opens at skill level %d" % (6 if si == 1 else 12)
				sockets.add_child(b)
			v.add_child(sockets)
		row.gui_input.connect(_row_input.bind(sk["id"]))
		row.mouse_entered.connect(func(): ui.show_tooltip(UIKit.skill_tooltip(ch.resolved_skill(sk["id"]), ch)))
		row.mouse_exited.connect(func(): ui.hide_tooltip())
		list.add_child(row)

func _unsocket(sid: String, idx: int) -> void:
	var why := can_change()
	if why != "":
		ui.toast(why, UIKit.BAD)
		return
	Game.ch.unsocket_rune(sid, idx)

func _socket_menu(sid: String) -> void:
	var ch = Game.ch
	var why := can_change()
	if why != "":
		ui.toast(why, UIKit.BAD)
		return
	var opts := []
	for rid in ch.runes:
		var fit: String = ch.rune_fits(rid, sid)
		var rd: Dictionary = Data.skill_runes[rid]
		opts.append(["%s (x%d) - %s" % [rd["name"], int(ch.runes[rid]), rd["desc"] if fit == "" else fit], _do_socket.bind(sid, rid), fit == ""])
	if opts.is_empty():
		ui.toast("You have no runes yet", UIKit.BAD)
		return
	ui.show_context(opts)

func _do_socket(sid: String, rid: String) -> void:
	var e: String = Game.ch.socket_rune(sid, rid)
	if e != "":
		ui.toast(e, UIKit.BAD)

func _slot_input(event: InputEvent, i: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			assign(i, "")
		else:
			selected_slot = i
			refresh()

func _row_input(event: InputEvent, sid: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		assign(selected_slot, sid)

func assign(slot: int, sid: String) -> void:
	var ch = Game.ch
	var why := can_change()
	if why != "":
		ui.toast(why, UIKit.BAD)
		return
	if sid != "" and not ch.unlocked_skills.has(sid):
		ui.toast("That skill is not unlocked yet", UIKit.BAD)
		return
	var prev: int = ch.loadout.find(sid) if sid != "" else -1
	if prev >= 0:
		ch.loadout[prev] = ch.loadout[slot]   # swap
	ch.loadout[slot] = sid
	Events.loadout_changed.emit()
	selected_slot = mini(slot + 1, 6)
	refresh()
