extends Control
## Standalone UI study: local fixtures only; never creates or saves a Game character.

const CanvasStyle = preload("res://scripts/ui/preview/canvas_skin.gd")
const Frame = preload("res://scripts/ui/preview/canvas_frame.gd")
const Slot = preload("res://scripts/ui/preview/canvas_slot.gd")

var fixture: Dictionary = {}
var bag: Array = []
var equipment := {}
var initial_equipment := {}
var bag_slots: Array = []
var equip_slots := {}
var selected_id := ""
var hovered_id := ""
var ring_target := "ring1"
var rare_only := false
var comparison := {}
var design: Control
var candidate_card: Control
var equipped_card: Control
var equip_button: Button
var ring_button: Button
var filter_button: Button
var clear_button: Button
var status: Label
var count_label: Label
var focus_label: Label
var stat_values := {}
var checks := 0
var failures := 0

func _ready() -> void:
	# Autoloads apply the player's saved fullscreen setting before this scene starts.
	# Establish the preview window without writing any persistent settings.
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	get_window().size = Vector2i(1280, 720)
	fixture = JSON.parse_string(FileAccess.get_file_as_string("res://data/art/inventory_preview.json"))
	theme = CanvasStyle.theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	design = Control.new()
	design.size = Vector2(1280, 720)
	design.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(design)
	_build_header()
	_build_character()
	_build_inventory()
	_build_inspector()
	_build_hud()
	reset_sample()
	resized.connect(_layout)
	_layout()
	if OS.get_cmdline_user_args().has("--verify"):
		await get_tree().process_frame
		await verify_interactions()
		get_tree().quit(1 if failures else 0)

func _layout() -> void:
	var factor := minf(size.x / 1280.0, size.y / 720.0)
	design.scale = Vector2(factor, factor)
	design.position = (size - Vector2(1280, 720) * factor) / 2
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#090f0e"))
	var tr := Transform2D(0, design.scale, 0, design.position)
	draw_set_transform_matrix(tr)
	# A quiet crypt fragment: reused game textures, isolated from world simulation.
	for y in range(72, 600, 32):
		for x in range(336, 832, 32):
			draw_texture_rect(Art.floor_tile("crypt", (x / 32 + y / 32) % 4), Rect2(x, y, 32, 32), false, Color("#555c4e"))
	draw_rect(Rect2(334, 70, 498, 534), Color(0.02, 0.06, 0.05, 0.64))
	for i in 5:
		draw_rect(Rect2(362 + i * 100, 92, 4, 116), Color(0.42, 0.38, 0.24, 0.12))
	draw_texture_rect(Art.sprite("warrior"), Rect2(616, 150, 48, 48), false, Color("#c0b391"))
	draw_set_transform_matrix(Transform2D.IDENTITY)

func _frame(at: Vector2, extent: Vector2) -> Control:
	var p = Frame.new()
	p.position = at
	p.size = extent
	design.add_child(p)
	return p

func _button(parent: Node, caption: String, at: Vector2, extent: Vector2, action: Callable) -> Button:
	var b := Button.new()
	b.text = caption
	b.position = at
	b.size = extent
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(action)
	parent.add_child(b)
	return b

func _build_header() -> void:
	CanvasStyle.label(design, "PATH OF DAN", Vector2(20, 12), Vector2(210, 24), 20, CanvasStyle.GOLD)
	CanvasStyle.label(design, "THE DYING CANVAS  /  INTERACTIVE UI STUDY", Vector2(237, 17), Vector2(490, 22), 12, CanvasStyle.MUTED)
	CanvasStyle.label(design, "SAMPLE ITEMS  ·  SESSION ONLY", Vector2(802, 17), Vector2(310, 22), 12, CanvasStyle.MUTED)
	_button(design, "Reset sample", Vector2(1120, 10), Vector2(144, 32), reset_sample)
	CanvasStyle.rule(design, Vector2(20, 46), 1244)

func _heading(panel: Node, title: String, subtitle: String) -> void:
	CanvasStyle.label(panel, title, Vector2(20, 14), Vector2(350, 26), 20, CanvasStyle.GOLD)
	CanvasStyle.label(panel, subtitle, Vector2(20, 44), Vector2(350, 22), 12, CanvasStyle.MUTED)
	CanvasStyle.rule(panel, Vector2(20, 72), 270 if title == "CHARACTER" else 390)

func _row(panel: Node, title: String, value: String, y: int, colour: Color = CanvasStyle.TEXT) -> Label:
	CanvasStyle.label(panel, title, Vector2(24, y), Vector2(206, 21), 14, CanvasStyle.MUTED)
	var l := CanvasStyle.label(panel, value, Vector2(218, y), Vector2(66, 21), 14, colour)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l

func _section(panel: Node, title: String, y: int) -> void:
	CanvasStyle.label(panel, title, Vector2(24, y), Vector2(270, 20), 12, CanvasStyle.GOLD)
	CanvasStyle.rule(panel, Vector2(24, y + 24), 262)

func _build_character() -> void:
	var panel := _frame(Vector2(16, 60), Vector2(310, 548))
	_heading(panel, "CHARACTER", "Dan  /  Level 18 Warrior")
	_section(panel, "I.  THE IRON OATH", 86)
	for i in 6:
		var attribute_label := _row(panel, ["Strength", "Dexterity", "Intelligence", "Vitality", "Agility", "Willpower"][i], ["58", "20", "12", "54", "18", "12"][i], 119 + i * 23)
		if i == 0:
			stat_values["strength"] = attribute_label
	_section(panel, "II.  OFFENCE & DEFENCE", 264)
	var keys := ["damage", "armour", "life", "fire_res"]
	for i in keys.size():
		stat_values[keys[i]] = _row(panel, fixture.stat_names[keys[i]], "", 298 + i * 25, Color("#c9927b") if keys[i] == "life" else CanvasStyle.TEXT)
	_section(panel, "III.  RESISTANCES", 410)
	CanvasStyle.label(panel, "Ice 28%   ·   Lightning 35%", Vector2(24, 447), Vector2(268, 21), 13)
	CanvasStyle.label(panel, "Arcane 16%   ·   Void 12%", Vector2(24, 471), Vector2(268, 21), 13)
	CanvasStyle.label(panel, "Sample values; swaps show direct item changes.", Vector2(24, 514), Vector2(270, 20), 11, CanvasStyle.MUTED)

func _make_slot(parent: Node, at: Vector2, key: String, placeholder: String = ""):
	var slot = Slot.new()
	slot.position = at
	slot.size = Vector2(44, 44)
	slot.slot_key = key
	slot.placeholder = placeholder
	slot.mouse_entered.connect(_hover.bind(slot))
	slot.mouse_exited.connect(_leave.bind(slot))
	slot.focus_entered.connect(_hover.bind(slot))
	slot.focus_exited.connect(_leave.bind(slot))
	slot.pressed.connect(_select.bind(slot))
	parent.add_child(slot)
	return slot

func _build_inventory() -> void:
	var panel := _frame(Vector2(834, 60), Vector2(430, 548))
	_heading(panel, "INVENTORY", "The cabinet of things that remain")
	# A readable 4 x 3 arrangement; all equipment and bag slots have one size.
	for i in fixture.equipment_order.size():
		var key: String = fixture.equipment_order[i]
		var col: int = i % 4
		var row: int = i / 4
		equip_slots[key] = _make_slot(panel, Vector2(24 + col * 98, 82 + row * 56), key, fixture.placeholders[key])
		CanvasStyle.label(panel, fixture.slot_names[key], Vector2(70 + col * 98, 93 + row * 56), Vector2(52, 32), 10, CanvasStyle.MUTED)
	CanvasStyle.rule(panel, Vector2(20, 251), 390)
	CanvasStyle.label(panel, "SATCHEL", Vector2(24, 258), Vector2(140, 21), 12, CanvasStyle.GOLD)
	count_label = CanvasStyle.label(panel, "", Vector2(200, 258), Vector2(200, 21), 12, CanvasStyle.MUTED)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for i in 40:
		bag_slots.append(_make_slot(panel, Vector2(24 + (i % 8) * 48, 284 + (i / 8) * 48), "bag:%d" % i))
	CanvasStyle.label(panel, "GOLD  12,480", Vector2(24, 526), Vector2(170, 18), 11, CanvasStyle.GOLD)
	_button(design, "Sort by rarity", Vector2(834, 616), Vector2(150, 32), sort_bag)
	filter_button = _button(design, "Bag: all", Vector2(992, 616), Vector2(132, 32), toggle_filter)
	clear_button = _button(design, "Clear selection", Vector2(1132, 616), Vector2(132, 32), clear_selection)

func _build_inspector() -> void:
	var l := CanvasStyle.label(design, "THE IRON OATH", Vector2(350, 85), Vector2(462, 25), 18, CanvasStyle.GOLD)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l = CanvasStyle.label(design, "Forgotten Depths  /  Equipment study", Vector2(350, 114), Vector2(462, 21), 12, CanvasStyle.MUTED)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	focus_label = CanvasStyle.label(design, "Select an item to keep its comparison open.", Vector2(348, 222), Vector2(468, 36), 13)
	focus_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	focus_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	candidate_card = _frame(Vector2(346, 270), Vector2(230, 284))
	equipped_card = _frame(Vector2(584, 270), Vector2(230, 284))
	equip_button = _button(design, "Equip in preview", Vector2(346, 566), Vector2(230, 36), equip_inspected)
	ring_button = _button(design, "Compare: Ring I", Vector2(584, 566), Vector2(230, 36), toggle_ring)
	status = CanvasStyle.label(design, "", Vector2(348, 612), Vector2(468, 36), 12, CanvasStyle.MUTED)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD

func _build_hud() -> void:
	var hud := _frame(Vector2(16, 662), Vector2(1248, 48))
	CanvasStyle.label(hud, "LIFE  840 / 840", Vector2(20, 13), Vector2(160, 22), 13, Color("#cd8b7c"))
	CanvasStyle.label(hud, "MANA  180 / 180", Vector2(1060, 13), Vector2(165, 22), 13, Color("#8dbdb8"))
	var keys := ["LMB", "RMB", "Q", "E", "R", "T", "G"]
	var icons := ["sword", "shield", "axe", "flask_life", "charm", "gem", "rune"]
	for i in 7:
		var x := 344 + i * 78
		var texture := TextureRect.new()
		texture.texture = Art.icon(icons[i])
		texture.position = Vector2(x, 12)
		texture.size = Vector2(24, 24)
		texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.add_child(texture)
		CanvasStyle.label(hud, keys[i], Vector2(x + 28, 14), Vector2(45, 20), 11, CanvasStyle.MUTED)
	CanvasStyle.label(design, "Hover: inspect   ·   Click / Enter: pin   ·   Tab / arrows: focus   ·   Esc: clear", Vector2(20, 618), Vector2(307, 38), 11, CanvasStyle.MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD

func reset_sample() -> void:
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner is Slot:
		focus_owner.release_focus()
	bag = fixture.bag.duplicate(true)
	while bag.size() < 40:
		bag.append({})
	equipment.clear()
	for i in fixture.equipment_order.size():
		equipment[fixture.equipment_order[i]] = fixture.equipped[i].duplicate(true)
	initial_equipment = equipment.duplicate(true)
	selected_id = ""
	hovered_id = ""
	ring_target = "ring1"
	rare_only = false
	if status != null:
		status.text = "Hover an item to inspect. Click to pin; other items can still be previewed."
	_refresh()

func _find(id: String) -> Dictionary:
	if id == "":
		return {}
	for it in bag:
		if it.get("id", "") == id:
			return it
	for key in equipment:
		if equipment[key].get("id", "") == id:
			return equipment[key]
	return {}

func _in_bag(id: String) -> bool:
	for it in bag:
		if it.get("id", "") == id and id != "":
			return true
	return false

func _inspect() -> Dictionary:
	return _find(hovered_id if hovered_id != "" else selected_id)

func _target(item: Dictionary) -> String:
	return ring_target if item.get("slot", "") == "ring" else str(item.get("slot", ""))

func comparison_for(item: Dictionary) -> Dictionary:
	var target := _target(item)
	if item.is_empty() or not equipment.has(target):
		return {}
	var old: Dictionary = equipment[target]
	var diff := {}
	for key in fixture.stat_names:
		var change := float(item.get("stats", {}).get(key, 0)) - float(old.get("stats", {}).get(key, 0))
		if not is_zero_approx(change):
			diff[key] = change
	return {"target": target, "equipped": old, "delta": diff}

func _hover(slot) -> void:
	if slot.hidden_by_filter or slot.item.is_empty():
		return
	hovered_id = slot.item.id
	_update_inspector()

func _leave(slot) -> void:
	if hovered_id == slot.item.get("id", ""):
		hovered_id = ""
		_update_inspector()

func _select(slot) -> void:
	if slot.hidden_by_filter or slot.item.is_empty():
		return
	selected_id = slot.item.id
	hovered_id = ""
	status.text = "Pinned: %s. Hover another item to preview it; move away to return." % slot.item.name
	_refresh()

func clear_selection() -> void:
	selected_id = ""
	hovered_id = ""
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null:
		focused.release_focus()
	status.text = "Selection cleared. Hover an item to inspect it."
	_refresh()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		clear_selection()
		get_viewport().set_input_as_handled()

func _refresh() -> void:
	var count := 0
	var shown := 0
	for i in bag_slots.size():
		var slot = bag_slots[i]
		slot.item = bag[i]
		slot.selected = slot.item.get("id", "") == selected_id and selected_id != ""
		slot.unavailable = int(slot.item.get("level", 0)) > int(fixture.character.level)
		slot.hidden_by_filter = rare_only and not slot.item.is_empty() and Data.rarity_index(slot.item.get("rarity", "common")) < Data.rarity_index("rare")
		slot.disabled = slot.item.is_empty() or slot.hidden_by_filter
		slot.queue_redraw()
		if not slot.item.is_empty():
			count += 1
			if not slot.hidden_by_filter:
				shown += 1
	for key in equip_slots:
		var slot = equip_slots[key]
		slot.item = equipment[key]
		slot.selected = slot.item.get("id", "") == selected_id and selected_id != ""
		slot.queue_redraw()
	count_label.text = "%d / 40 items%s" % [count, "  (%d shown)" % shown if rare_only else ""]
	filter_button.text = "Bag: rare+" if rare_only else "Bag: all"
	clear_button.disabled = selected_id == "" and hovered_id == ""
	for stat in stat_values:
		var value := float(fixture.base_stats[stat])
		for key in equipment:
			value += float(equipment[key].stats.get(stat, 0)) - float(initial_equipment[key].stats.get(stat, 0))
		stat_values[stat].text = str(int(value)) + str(fixture.stat_suffix.get(stat, ""))
	_update_inspector()

func _empty_card(card: Control, title: String, message: String) -> void:
	for child in card.get_children():
		child.free()
	CanvasStyle.label(card, title, Vector2(16, 17), Vector2(198, 24), 12, CanvasStyle.GOLD)
	var l := CanvasStyle.label(card, message, Vector2(16, 62), Vector2(198, 170), 14, CanvasStyle.MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD

func _item_card(card: Control, item: Dictionary, title: String, delta: Dictionary = {}) -> void:
	_empty_card(card, title, "")
	var rarity: String = item.get("rarity", "common")
	var col := Data.rarity_color(rarity)
	var name_label := CanvasStyle.label(card, item.name, Vector2(16, 48), Vector2(198, 48), 17, col)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	CanvasStyle.label(card, "%s / %s" % [rarity.capitalize(), str(item.slot).replace("_", " ").capitalize()], Vector2(16, 98), Vector2(198, 21), 12, CanvasStyle.MUTED)
	CanvasStyle.rule(card, Vector2(16, 126), 198)
	var y := 138
	for stat in fixture.stat_names:
		if not item.stats.has(stat) and not delta.has(stat):
			continue
		var suffix: String = fixture.stat_suffix.get(stat, "")
		CanvasStyle.label(card, fixture.stat_names[stat], Vector2(16, y), Vector2(152, 20), 12, CanvasStyle.MUTED)
		var value := str(int(item.stats.get(stat, 0))) + suffix
		CanvasStyle.label(card, value, Vector2(169, y), Vector2(45, 20), 12)
		y += 19
		if delta.has(stat):
			var d: float = delta[stat]
			CanvasStyle.label(card, ("+" if d > 0 else "") + str(int(d)) + suffix + " vs equipped", Vector2(16, y), Vector2(198, 19), 11, CanvasStyle.GOOD if d > 0 else CanvasStyle.BAD)
			y += 20
	if item.stats.is_empty():
		CanvasStyle.label(card, "Crafting / skill material", Vector2(16, 145), Vector2(198, 22), 12, CanvasStyle.MUTED)
	CanvasStyle.label(card, "Requires level %d" % item.level, Vector2(16, 246), Vector2(198, 21), 12, CanvasStyle.BAD if int(item.level) > int(fixture.character.level) else CanvasStyle.MUTED)

func _update_inspector() -> void:
	var item := _inspect()
	clear_button.disabled = selected_id == "" and hovered_id == ""
	comparison = comparison_for(item)
	equip_button.disabled = true
	ring_button.visible = item.get("slot", "") == "ring"
	ring_button.text = "Compare: Ring I" if ring_target == "ring1" else "Compare: Ring II"
	if item.is_empty():
		_empty_card(candidate_card, "INSPECT AN ITEM", "Hover an item in your satchel.\n\nClick or press Enter to pin it.\n\nA pale inset and a check mark show selection.")
		_empty_card(equipped_card, "CURRENTLY EQUIPPED", "The matching equipped item appears here.\n\nSigned values show both gains and losses.\n\nRing comparisons can switch between both hands.")
		focus_label.text = "Select an item to keep its comparison open."
		equip_button.text = "Equip in preview"
		return
	var pinned: bool = item.id == selected_id
	focus_label.text = ("PINNED  /  " if pinned else "INSPECTING  /  ") + item.name
	_item_card(candidate_card, item, "PINNED SELECTION" if pinned else "UNDER CURSOR", comparison.get("delta", {}) if _in_bag(item.id) else {})
	if comparison.is_empty():
		_empty_card(equipped_card, "NO EQUIPMENT MATCH", "This is a material, not equipment.\n\nIt remains selectable and inspectable.")
	else:
		_item_card(equipped_card, comparison.equipped, "EQUIPPED / " + str(fixture.slot_names[comparison.target]).to_upper())
	var can_equip := _in_bag(item.id) and not comparison.is_empty() and int(item.level) <= int(fixture.character.level)
	equip_button.disabled = not can_equip
	equip_button.text = "Equip in preview" if can_equip else ("Requires level %d" % item.level if int(item.level) > int(fixture.character.level) else "Material / inspect only" if comparison.is_empty() else "Already equipped")

func equip_inspected() -> void:
	if equip_button.disabled:
		return
	var item := _inspect()
	var target := _target(item)
	for i in bag.size():
		if bag[i].get("id", "") == item.id:
			bag[i] = equipment[target]
			equipment[target] = item
			selected_id = item.id
			hovered_id = ""
			status.text = "%s equipped in this sample. The previous item is in your satchel." % item.name
			_refresh()
			return

func toggle_ring() -> void:
	ring_target = "ring2" if ring_target == "ring1" else "ring1"
	_update_inspector()

func sort_bag() -> void:
	bag.sort_custom(func(a, b):
		if a.is_empty():
			return false
		if b.is_empty():
			return true
		var ar: int = Data.rarity_index(a.rarity)
		var br: int = Data.rarity_index(b.rarity)
		return a.name < b.name if ar == br else ar > br)
	hovered_id = ""
	status.text = "Sorted by rarity, then name. Your pinned item stays selected."
	_refresh()

func toggle_filter() -> void:
	rare_only = not rare_only
	hovered_id = ""
	# A selected hidden item must not keep a hidden focus/inspection target.
	var selected := _find(selected_id)
	if rare_only and _in_bag(selected_id) and Data.rarity_index(selected.get("rarity", "common")) < Data.rarity_index("rare"):
		selected_id = ""
	status.text = "Bag view only: rare and legendary items." if rare_only else "All bag items visible."
	_refresh()

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("UI preview: " + description)

func verify_interactions() -> void:
	var game_character = Game.ch
	var combat_state: int = Combat.rng.state
	reset_sample()
	for i in 3:
		await get_tree().process_frame
	_check(bag_slots.size() == 40 and equip_slots.size() == 11, "40 bag slots and 11 equipment slots")
	_check(bag_slots[8].position.y > bag_slots[0].position.y and bag_slots[32].position.y == 476, "five rows of eight")
	_check(equip_button.disabled and clear_button.disabled, "empty inspection actions disabled")
	# Engine mouse input, not only direct state changes: hover and click the first cell.
	var motion := InputEventMouseMotion.new()
	motion.position = bag_slots[0].get_global_rect().get_center()
	get_viewport().push_input(motion, true)
	await get_tree().process_frame
	_check(hovered_id == "bag_sword", "actual pointer hover inspects item")
	_check(comparison.get("delta", {}).get("damage", 0) == 14, "damage gain is signed and correct")
	_check(comparison.get("delta", {}).get("strength", 0) == -5, "lost strength is shown")
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.position = motion.position
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		get_viewport().push_input(click, true)
	await get_tree().process_frame
	_check(selected_id == "bag_sword" and bag_slots[0].selected, "actual click pins and marks slot")
	_hover(bag_slots[1])
	_check(_inspect().id == "bag_helm" and selected_id == "bag_sword", "hover previews without replacing pin")
	_leave(bag_slots[1])
	_check(_inspect().get("id", "") == "bag_sword", "leaving transient hover restores pin")
	equip_inspected()
	_check(equipment.main_hand.id == "bag_sword" and bag[0].id == "eq_sword", "equip swaps fixture items")
	_check(stat_values.damage.text == "68" and stat_values.strength.text == "53", "fixture summary updates both gains and losses")
	_check(equip_button.disabled, "equipped candidate cannot be equipped twice")
	_select(bag_slots[2])
	_check(comparison.target == "ring1", "ring defaults to first slot")
	toggle_ring()
	_check(comparison.target == "ring2" and comparison.delta.life == 16, "second ring comparison uses second ring")
	_select(bag_slots[5])
	_check(equip_button.disabled and equip_button.text == "Requires level 24", "over-level item inspectable but unavailable")
	equip_inspected()
	_check(equipment.chest.id == "eq_chest", "disabled action cannot swap item")
	_select(bag_slots[4])
	_check(comparison.is_empty() and equip_button.disabled, "material has no misleading equipment comparison")
	_select(bag_slots[1])
	sort_bag()
	_check(selected_id == "bag_helm" and _find(selected_id).name == "Penitent's Sallet", "sort keeps selection by item id")
	toggle_filter()
	_check(selected_id == "" and not _find("bag_helm").is_empty(), "filter clears hidden selection without deleting item")
	var dimmed := 0
	for slot in bag_slots:
		if slot.hidden_by_filter:
			dimmed += 1
			_check(slot.disabled, "filtered cell cannot be clicked or focused")
	_check(dimmed > 0, "rare+ filter hides lower rarity")
	toggle_filter()
	reset_sample()
	bag_slots[0].grab_focus()
	await get_tree().process_frame
	_check(bag_slots[0].has_focus() and hovered_id == "bag_sword", "keyboard focus inspects item")
	for pressed in [true, false]:
		var enter := InputEventKey.new()
		enter.keycode = KEY_ENTER
		enter.pressed = pressed
		get_viewport().push_input(enter, true)
	await get_tree().process_frame
	_check(selected_id == "bag_sword", "Enter pins focused item")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	get_viewport().push_input(esc, true)
	await get_tree().process_frame
	_check(selected_id == "" and hovered_id == "", "Escape clears focus and selection")
	_check(Game.ch == game_character and Combat.rng.state == combat_state, "preview leaves live character and combat RNG alone")
	reset_sample()
	_check(bag[0].id == "bag_sword" and equipment.main_hand.id == "eq_sword", "reset restores fixture")
	print("==== UI inventory preview: %d passed, %d failed ====" % [checks - failures, failures])
