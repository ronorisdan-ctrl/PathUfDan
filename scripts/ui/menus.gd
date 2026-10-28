extends Control
## Main menu, character selection and the settings sub-menu.

const UIKit = preload("res://scripts/ui/ui_kit.gd")

var main = null
var screen := "menu"
var t := 0.0
var box: VBoxContainer
var embers := []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.make_theme()
	for i in 70:
		embers.append(Vector3(randf(), randf(), randf_range(0.3, 1.0)))
	Game.migrate_legacy_save()
	show_menu()

func _process(delta: float) -> void:
	t += delta
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.025, 0.035))
	for i in 12:
		draw_circle(Vector2(size.x / 2, size.y + 200), 300 + i * 60 + sin(t * 0.5 + i) * 10, Color(0.25, 0.08, 0.04, 0.025))
	for e in embers:
		var y: float = fmod(e.y - t * 0.03 * e.z + 2.0, 1.0)
		var x: float = e.x + sin(t * e.z + e.y * 10.0) * 0.01
		draw_circle(Vector2(x * size.x, y * size.y), 1.5 * e.z, Color(1, 0.5 + 0.3 * e.z, 0.2, 0.5 * e.z))

func _clear() -> void:
	if box != null:
		box.queue_free()
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(box)

func _center(c: Control) -> void:
	var cc := CenterContainer.new()
	cc.add_child(c)
	box.add_child(cc)

func show_menu() -> void:
	screen = "menu"
	_clear()
	var title := UIKit.label("PATH OF DAN", 64, Color("#d8a860"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_constant_override("outline_size", 8)
	title.add_theme_color_override("font_outline_color", Color("#2a1008"))
	box.add_child(title)
	var sub := UIKit.label("A dark fantasy action RPG", 18, UIKit.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	box.add_child(Control.new())
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	var has_save := Game.has_save()
	var cont := UIKit.button("Continue", _continue, 280)
	cont.disabled = not has_save
	v.add_child(cont)
	if has_save:
		var sl := UIKit.label(Game.latest_summary(), 12, UIKit.MUTED)
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(sl)
	v.add_child(UIKit.button("New Game", show_class_select, 280))
	v.add_child(UIKit.button("Settings", show_settings, 280))
	v.add_child(UIKit.button("Exit", func(): get_tree().quit(), 280))
	_center(v)
	var ver := UIKit.label("Vertical slice build - Godot 4", 11, Color(0.4, 0.38, 0.36))
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(ver)

func _continue() -> void:
	show_slot_select("load")

func show_settings() -> void:
	screen = "settings"
	_clear()
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(360, 0)
	v.add_child(UIKit.label("Settings", 28, UIKit.GOLD))
	v.add_child(UIKit.label("Volume", 14))
	var vol := HSlider.new()
	vol.min_value = 0
	vol.max_value = 1
	vol.step = 0.05
	vol.value = float(Game.settings.get("volume", 0.7))
	vol.value_changed.connect(func(x):
		Game.settings["volume"] = x
		Game.apply_settings())
	v.add_child(vol)
	v.add_child(UIKit.label("Screen shake", 14))
	var sh := HSlider.new()
	sh.min_value = 0
	sh.max_value = 1.5
	sh.step = 0.1
	sh.value = float(Game.settings.get("screen_shake", 1.0))
	sh.value_changed.connect(func(x): Game.settings["screen_shake"] = x)
	v.add_child(sh)
	var fs := CheckBox.new()
	fs.text = "Fullscreen"
	fs.button_pressed = bool(Game.settings.get("fullscreen", false))
	fs.toggled.connect(func(on):
		Game.settings["fullscreen"] = on
		Game.apply_settings())
	v.add_child(fs)
	var dev := CheckBox.new()
	dev.text = "Developer tools"
	dev.tooltip_text = "Testing cheats: F1 opens the Developer panel in game. Characters that use them are marked (dev)."
	dev.button_pressed = bool(Game.settings.get("dev_tools", false))
	dev.toggled.connect(func(on): Dev.set_enabled(on))
	v.add_child(dev)
	v.add_child(UIKit.label("Controls: WASD move, LMB/RMB/Q/E/R skills, Space dodge, 1/2 flasks,\nF interact/pick up, I inventory, C character, P passives, K skills,\nTab map, Z loot filter, Esc menu", 12, UIKit.MUTED))
	v.add_child(UIKit.button("Back", func():
		Game.save_settings()
		show_menu()))
	_center(v)

func show_class_select() -> void:
	screen = "class"
	_clear()
	var title := UIKit.label("Choose your path", 34, UIKit.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	for cd in Data.class_list:
		h.add_child(_class_card(cd))
	_center(h)
	var back := UIKit.button("Back", show_menu, 160)
	_center(back)

func _class_card(cd: Dictionary) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(330, 470)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	var portrait := TextureRect.new()
	portrait.texture = Art.sprite(cd.get("sprite", "warrior"))
	portrait.custom_minimum_size = Vector2(96, 96)
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	v.add_child(portrait)
	var nm := UIKit.label(cd["name"], 26, Color(cd.get("color", "#ffffff")).lightened(0.3))
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(nm)
	var tl := UIKit.label(cd.get("title", ""), 13, UIKit.MUTED)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tl)
	var lines := []
	lines.append(cd.get("desc", ""))
	lines.append("")
	lines.append("[color=#c8a060]Combat:[/color] %s" % cd.get("identity", ""))
	lines.append("[color=#c8a060]Difficulty:[/color] %s" % cd.get("difficulty", ""))
	var attrs := []
	for a in Data.attributes.get("order", []):
		attrs.append("%s %d" % [a.to_upper(), int(cd["base_attributes"].get(a, 0))])
	lines.append("[color=#c8a060]Attributes:[/color] " + "  ".join(attrs))
	var items := []
	for b in cd.get("start_items", []):
		items.append(Data.item_bases.get(b, {}).get("name", b))
	lines.append("[color=#c8a060]Starts with:[/color] " + ", ".join(items))
	var sks := []
	for s in cd.get("start_skills", []):
		sks.append(Data.skills.get(s, {}).get("name", s))
	lines.append("[color=#c8a060]Skills:[/color] " + ", ".join(sks))
	var cats := []
	for w in cd.get("weapon_types", []):
		cats.append(w.capitalize())
	lines.append("[color=#c8a060]Weapons:[/color] " + ", ".join(cats))
	lines.append("[color=#c8a060]Armour:[/color] " + ", ".join(cd.get("armour_types", [])))
	var r := UIKit.rich("\n".join(lines), 300)
	r.custom_minimum_size = Vector2(300, 250)
	r.add_theme_font_size_override("normal_font_size", 13)
	v.add_child(r)
	v.add_child(UIKit.button("Play as %s" % cd["name"], _pick.bind(cd["id"])))
	return p

func _pick(cls: String) -> void:
	show_slot_select("new", cls)

func _start(cls: String, slot: int) -> void:
	Game.new_character(cls)
	Game.current_slot = slot
	Game.select_filter_character(true)
	Game.save_game(slot)
	main.start_game()

func _load_slot(slot: int) -> void:
	if Game.load_game(slot):
		main.start_game()
	else:
		show_slot_select("load")

func _confirm(text: String, on_yes: Callable) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = text
	dlg.confirmed.connect(on_yes)
	dlg.canceled.connect(dlg.queue_free)
	dlg.confirmed.connect(dlg.queue_free)
	dlg.window_input.connect(func(e):
		if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_SPACE:
			dlg.set_input_as_handled()
			dlg.get_ok_button().emit_signal("pressed"))
	add_child(dlg)
	dlg.popup_centered()

## Slot picker. mode "load": choose a save to continue. mode "new": choose the
## slot a new character of class `cls` will be saved into.
func show_slot_select(mode: String, cls: String = "") -> void:
	screen = "slots"
	_clear()
	var heading := "Choose a save" if mode == "load" else "Choose a save slot for your new character"
	var title := UIKit.label(heading, 30, UIKit.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(820, 470)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	# the autosave can only be loaded, never chosen as a target for a new game
	if mode == "load" and Game.has_slot(Game.AUTOSAVE_SLOT):
		list.add_child(_slot_row(mode, cls, Game.AUTOSAVE_SLOT))
	for s in range(1, Game.SLOT_COUNT + 1):
		list.add_child(_slot_row(mode, cls, s))
	_center(sc)
	_center(UIKit.button("Back", show_menu if mode == "load" else show_class_select, 160))

func _slot_row(mode: String, cls: String, slot: int) -> Control:
	var info: Dictionary = Game.slot_info(slot)
	var pc := PanelContainer.new()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	pc.add_child(h)
	var slot_name := "Autosave" if slot == Game.AUTOSAVE_SLOT else "Slot %d" % slot
	var head := UIKit.label(slot_name, 16, UIKit.GOLD)
	head.custom_minimum_size = Vector2(90, 0)
	h.add_child(head)
	var text: String = "Empty"
	if info["exists"]:
		text = info["summary"]
		if info["date"] != "":
			text += "\n" + info["date"]
	var lab := UIKit.label(text, 13, UIKit.MUTED if not info["exists"] else UIKit.TEXT)
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(lab)
	if mode == "load":
		var ld := UIKit.button("Load", _load_slot.bind(slot), 90)
		ld.disabled = not info["exists"] or info["corrupt"]
		h.add_child(ld)
	else:
		var label := "Overwrite" if info["exists"] else "Start here"
		h.add_child(UIKit.button(label, _new_in_slot.bind(cls, slot, bool(info["exists"])), 100))
	if info["exists"]:
		h.add_child(UIKit.button("Delete", _delete_slot.bind(mode, cls, slot), 80))
	return pc

func _new_in_slot(cls: String, slot: int, exists: bool) -> void:
	if exists:
		_confirm("Overwrite slot %d?\n%s" % [slot, Game.slot_info(slot)["summary"]], func(): _start(cls, slot))
	else:
		_start(cls, slot)

func _delete_slot(mode: String, cls: String, slot: int) -> void:
	var what := "the autosave" if slot == Game.AUTOSAVE_SLOT else "slot %d" % slot
	_confirm("Delete %s permanently?\n%s" % [what, Game.slot_info(slot)["summary"]], func():
		Game.delete_slot(slot)
		if mode == "load" and not Game.has_save():
			show_menu()
		else:
			show_slot_select(mode, cls))
