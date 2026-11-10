extends Node
## Phase 2B: independent marker combinations and real shared-slot input paths.
const Slot = preload("res://scripts/ui/item_slot.gd")
const SlotStyle = preload("res://scripts/ui/components/item_slot_skin.gd")
const UIKit = preload("res://scripts/ui/ui_kit.gd")
const OUT := "res://tests/screens_out_hud/item_slots_2b"
var checks := 0
var failures := 0
var capture := false
var main
var signal_log := []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("Item slots: " + message)

func frames(n: int = 5) -> void:
	for i in n:
		await get_tree().process_frame

func move(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	get_viewport().push_input(event, true)
	await frames(2)

func click(cell: Control, button: int = MOUSE_BUTTON_LEFT, shift: bool = false, double: bool = false) -> void:
	var point := cell.get_global_rect().get_center()
	await move(point)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.pressed = pressed
		event.button_index = button
		event.shift_pressed = shift
		event.double_click = double and pressed
		get_viewport().push_input(event, true)
	await frames(2)

func shot(tag: String) -> void:
	main.ui.hide_tooltip()
	await frames()
	if capture:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		check(img.get_size() == get_window().size, tag + " exact output")
		img.save_png(OUT + "/" + tag + ".png")

func fixture() -> Dictionary:
	var it := {}
	for base in Data.item_base_list:
		if base.get("slot") == "ring":
			it = Loot.roll_item_of(base["id"], "uncommon", 10)
			break
	it["uid"] = Game.ch.take_uid()
	it["req_level"] = 1
	return it

func _ready() -> void:
	Game.testing = true
	capture = OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name() != "headless"
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		get_window().borderless = true
	get_window().size = Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute(OUT)
	Loot.set_seed(20261104)
	main = load("res://scripts/main.gd").new()
	add_child(main)
	await frames()
	Game.new_character("ranger")
	var ch = Game.ch
	ch.level = 60
	ch.gold = 999999
	ch.recalc()
	main.start_game()
	await frames(12)
	Game.level.process_mode = Node.PROCESS_MODE_DISABLED
	var ui = main.ui
	var inv = ui.panels["inventory"]
	for i in ch.inventory.size():
		ch.inventory[i] = null
	var item := fixture()
	ch.inventory[0] = item
	ui.open("inventory")
	await frames()
	# Verify actual viewport events, signal order, double-click equip and ring targets.
	var cell = inv.bag_slots[0]
	cell.clicked.connect(func(_s, button, shift): signal_log.append(["click", button, shift]))
	cell.double_clicked.connect(func(_s): signal_log.append(["double"]))
	cell.hovered.connect(func(_s): signal_log.append(["hover"]))
	cell.unhovered.connect(func(_s): signal_log.append(["exit"]))
	await move(Vector2(600,300))
	await click(cell)
	check(cell.pointer_over and ui.tooltip.visible and signal_log.has(["hover"]), "hover skin and existing tooltip")
	check(ch.inventory[0] == item, "single click does not equip")
	await click(cell, MOUSE_BUTTON_LEFT, false, true)
	check(ch.equipment["ring1"] == item, "double-click existing equip path")
	check(signal_log.slice(signal_log.size() - 2) == [["click", MOUSE_BUTTON_LEFT, false], ["double"]], "clicked precedes double-click")
	await move(Vector2(600,300))
	check(not cell.pointer_over and signal_log.has(["exit"]), "hover clears and unhover signal retained")
	check(ch.unequip("ring1"), "return fixture")
	inv._equip_idx(0, "ring2")
	check(ch.equipment["ring2"] == item, "existing second ring action")
	ch.unequip("ring2")
	for station in ["blacksmith", "jeweller"]:
		ui.close_all()
		ui.open_station(station)
		await click(cell, MOUSE_BUTTON_LEFT, false, true)
		check(ui.panels[station].selected == item and cell.selected and ch.inventory[0] == item, station + " selection keeps double-click ownership")
		await click(cell, MOUSE_BUTTON_RIGHT)
		check(ui.context.visible, station + " right-click actions")
		ui.hide_context()
	# The same slot receives vendor clicks; exact transaction prices stay authoritative.
	ui.close_all()
	Game.vendor_stock = [item.duplicate(true)]
	ui.open_station("merchant")
	await frames()
	var vendor = ui.panels["vendor"]
	check(vendor.slots[0].get_script() == Slot and vendor.slots[0].price == Loot.buy_value(Game.vendor_stock[0]), "vendor shared slot and exact price")
	await click(vendor.slots[0])
	check(ui.confirm.visible and ui.confirm_text.text.contains(str(vendor.slots[0].price)), "vendor click opens exact-price confirmation")
	ui.confirm.visible = false
	item["corruption"] = 100
	item["upgrade"] = 5
	item["locked"] = true
	inv.refresh()
	check(cell.price == -1, "player-locked bag price suppressed")
	item["locked"] = false
	inv.refresh()
	check(cell.price == Loot.sell_value(item), "unlocked sealed upgraded item remains priced")
	await click(cell, MOUSE_BUTTON_LEFT, true)
	check(ch.inventory[0] == null and signal_log.has(["click", MOUSE_BUTTON_LEFT, true]), "shift sell keeps callback and modifiers")
	ch.inventory[0] = item
	# Personal/shared stash round trips through viewport clicks, with testing save guard.
	var shared_before: Array = SharedStash.slots.duplicate(true)
	for mode in ["stash", "shared"]:
		ui.close_all()
		ui.open_station("stash")
		var stash = ui.panels["stash"]
		stash._set_mode(mode)
		if mode == "shared":
			SharedStash.slots.fill(null)
		await click(cell)
		check(ch.inventory[0] == null and stash.slots[0].item == item, mode + " deposit through skinned cell")
		await click(stash.slots[0])
		check(ch.inventory[0] == item and stash.slots[0].item == null, mode + " withdraw through skinned cell")
	SharedStash.slots = shared_before
	# Native marker bounds, including the largest live equipment and minimum bag cells.
	for dims in [Vector2(44,44), Vector2(46,46)]:
		var markers := [Slot.upgrade_rect(dims), Slot.padlock_rect(dims), Slot.price_rect(dims), Slot.corrupted_rect(dims)]
		for a in markers.size():
			check(Rect2(Vector2.ZERO, dims).encloses(markers[a]), "marker inside " + str(dims))
			for b in range(a + 1, markers.size()):
				check(not markers[a].intersects(markers[b]), "independent marker corners " + str(dims))
		for value in [0, 999, 9999, 10000, 99999, 999999, 999999999]:
			check(ThemeDB.fallback_font.get_string_size(SlotStyle.price_text(value), HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 1 <= Slot.price_rect(dims).size.x, "price badge fits " + str(value))
	ui.close_all()
	var matrix := PanelContainer.new()
	matrix.position = Vector2(40,40)
	matrix.size = Vector2(1150,620)
	ui.root.add_child(matrix)
	var rows := VBoxContainer.new()
	matrix.add_child(rows)
	rows.add_child(UIKit.label("SHARED ITEM WELLS — PHASE 2B", 24))
	rows.add_child(UIKit.label("Rarity rows; every upgrade / player-lock / seal / price combination. Prices compact above 9,999.", 14))
	var matrix_cells := []
	for rarity in ["common", "uncommon", "rare", "epic", "legendary"]:
		var row := HBoxContainer.new()
		rows.add_child(row)
		var label := UIKit.label(rarity.capitalize(), 14)
		label.custom_minimum_size.x = 100
		row.add_child(label)
		for flags in 16:
			var sl = Slot.new()
			var it: Dictionary = item.duplicate(true)
			it["rarity"] = rarity
			it["upgrade"] = 5 if flags & 1 else 0
			it["locked"] = bool(flags & 2)
			it["corruption"] = 100 if flags & 4 else 37
			sl.set_item(it)
			sl.price = 9999 if flags & 8 else -1
			row.add_child(sl)
			matrix_cells.append(sl)
	var state_row := HBoxContainer.new()
	rows.add_child(state_row)
	for state in ["Empty", "Equipment", "Hover", "Selected", "Restricted", "Dim", "All states", "Large price"]:
		var column := VBoxContainer.new()
		column.custom_minimum_size.x = 120
		state_row.add_child(column)
		column.add_child(UIKit.label(state, 12))
		var sl = Slot.new()
		sl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		column.add_child(sl)
		if state == "Equipment":
			sl.placeholder = "helm"
		elif state != "Empty":
			var it: Dictionary = item.duplicate(true)
			it["locked"] = true
			it["upgrade"] = 5
			it["corruption"] = 100
			it["req_level"] = 99 if state in ["Restricted", "All states"] else 1
			sl.set_item(it)
			sl.selected = state in ["Selected", "All states"]
			sl.pointer_over = state in ["Hover", "All states"]
			sl.dim = state in ["Dim", "All states"]
			sl.price = 999999999 if state == "Large price" else 999
	# Repainting must not mutate any character, slot fixture or combat RNG state.
	var snapshot := JSON.stringify(ch.to_dict())
	var rng_state = Combat.rng.state
	for dims in [Vector2i(1280,720), Vector2i(1920,1080), Vector2i(2560,1440), Vector2i(1920,1200), Vector2i(2560,1080)]:
		get_window().size = dims
		await frames(10)
		for sl in matrix_cells:
			sl.queue_redraw()
			check(sl.size == Vector2(44,44) and sl.mouse_filter == Control.MOUSE_FILTER_STOP and sl.get_child_count() == 0, "original hit area; no input-blocking decorations")
		await shot("matrix_%dx%d" % [dims.x,dims.y])
	check(snapshot == JSON.stringify(ch.to_dict()) and rng_state == Combat.rng.state, "drawing preserves character and combat RNG")
	for i in 16:
		ch.inventory[i] = matrix_cells[i].item.duplicate(true)
	matrix.queue_free()
	await frames()
	get_window().size = Vector2i(1280,720)
	# Reuse production surfaces for rendered evidence of the same skin.
	Game.vendor_stock = ch.inventory.slice(0,16).duplicate(true)
	for station in ["blacksmith", "jeweller", "merchant", "stash"]:
		ui.close_all()
		ui.open_station(station)
		if station in ["blacksmith", "jeweller"]:
			ui.panels[station].select(ch.inventory[0])
		if station == "stash":
			ch.stash[0] = item.duplicate(true)
			ui.panels[station]._set_mode("stash")
		await move(Vector2(600,300))
		await shot(station + "_1280x720")
	ui.panels["stash"]._set_mode("shared")
	SharedStash.slots[0] = item.duplicate(true)
	ui.panels["stash"].refresh()
	await shot("shared_1280x720")
	SharedStash.slots = shared_before
	ui.close_all()
	Game.level = null
	main.queue_free()
	await frames()
	for audio in Sfx.players:
		audio.stop()
		audio.stream = null
	await frames()
	print("Item slots: %d passed, %d failed" % [checks - failures, failures])
	get_tree().quit(1 if failures else 0)
