extends Node
## Phase 2A: real inventory layout and station coexistence; no saved fixture data.

var checks := 0
var failures := 0
var main
var evidence := []
var capture := false
const OUT := "res://tests/screens_out_hud/inventory_2a"

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("Inventory chrome: " + message)

func frames(n: int = 8) -> void:
	for i in n:
		await get_tree().process_frame

func inside(child: Control, parent: Control) -> bool:
	return parent.get_global_rect().grow(0.1).encloses(child.get_global_rect())

func click(control: Control, button: int = MOUSE_BUTTON_LEFT) -> void:
	var point := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	get_viewport().push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = button
		event.pressed = pressed
		get_viewport().push_input(event, true)
	await frames(2)

func verify_layout(tag: String) -> void:
	await frames()
	var ui = main.ui
	var inv = ui.panels["inventory"]
	check(Rect2(Vector2.ZERO, ui.root.size).encloses(inv.get_global_rect()), tag + " inventory fits")
	check(inv.bag_slots.size() == 40 and inv.equip_slots.size() == 11, tag + " all cells")
	var cells: Array = inv.bag_slots.duplicate()
	cells.append_array(inv.equip_slots.values())
	for i in cells.size():
		var cell: Control = cells[i]
		check(inside(cell, cell.get_parent()) and inside(cell, inv) and cell.size.x >= 44 and cell.size.y >= 44, tag + " cell bounds %d" % i)
		for j in range(i + 1, cells.size()):
			if cell.get_global_rect().intersects(cells[j].get_global_rect()):
				check(false, tag + " overlapping cells %d/%d" % [i, j])
	check(inside(inv.mats_label, inv) and inv.mats_label.get_content_height() <= inv.mats_label.size.y + 1, tag + " complete materials")
	check(inv.mats_label.text.contains("Abyssal Brand:") and inv.mats_label.text.contains("Rare Catalyst:"), tag + " all material names")
	check(inside(inv.info_label, inv) and inv.info_label.get_line_count() * inv.info_label.get_line_height() <= inv.info_label.size.y + 1, tag + " complete hint")
	check(inside(inv.filter_btn, inv) and inside(inv.destroy_btn, inv), tag + " reachable actions")
	var row := {"state": tag, "window": str(get_window().size), "logical": str(ui.root.size), "inventory": str(inv.get_global_rect())}
	for station in ["blacksmith", "jeweller", "vendor", "stash"]:
		if not ui.is_open(station):
			continue
		var panel = ui.panels[station]
		check(Rect2(Vector2.ZERO, ui.root.size).encloses(panel.get_global_rect()), tag + " station fits")
		check(not inv.get_global_rect().intersects(panel.get_global_rect()), tag + " station separated")
		row[station] = str(panel.get_global_rect())
		if station == "blacksmith":
			check(inside(panel.confirm_btn, panel) and inside(panel.mats, panel), tag + " pinned craft/materials")
		if station == "jeweller":
			check(inside(panel.buy_btn, panel), tag + " jeweller action")
	evidence.append(row)
	if capture:
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		check(image.get_size() == get_window().size, tag + " exact output")
		image.save_png(OUT + "/" + tag + ".png")

func _ready() -> void:
	Game.testing = true
	capture = OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name() != "headless"
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		get_window().borderless = true
	get_window().size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(OUT)
	Loot.set_seed(20261104)
	main = load("res://scripts/main.gd").new()
	add_child(main)
	await frames(3)
	Game.new_character("ranger")
	var ch = Game.ch
	ch.level = 60
	ch.gold = 5000
	for key in Data.materials:
		ch.materials[key] = 30
	for slot in ch.equipment:
		for base in Data.item_base_list:
			if base.get("slot") == ("ring" if slot in ["ring1", "ring2"] else slot):
				ch.equipment[slot] = Loot.roll_item_of(base["id"], "rare", 42)
				break
	for i in 40:
		var base: Dictionary = Data.item_base_list[i % Data.item_base_list.size()]
		ch.inventory[i] = Loot.roll_item_of(base["id"], ["common", "uncommon", "rare", "epic"][i % 4], 42)
		ch.inventory[i]["uid"] = ch.take_uid()
	ch.inventory[0] = Loot.make_unique("widowmaker", 42)
	ch.inventory[0]["uid"] = ch.take_uid()
	ch.inventory[0]["corruption"] = 100
	ch.inventory[0]["locked"] = true
	ch.inventory[0]["upgrade"] = 5
	ch.recalc()
	main.start_game()
	await frames(12)
	Game.level.process_mode = Node.PROCESS_MODE_DISABLED
	var ui = main.ui
	ui.open("inventory")
	await frames()
	var inv = ui.panels["inventory"]
	check(inv.bag_count.text == "40 / 40", "full count")
	check(inv.theme != ui.root.theme and ui.panels["blacksmith"].theme != inv.theme and ui.panels["passives"].theme != inv.theme, "inventory theme remains independently scoped")
	var snapshot := JSON.stringify(ch.to_dict())
	var rng_state = Combat.rng.state
	for i in 120:
		inv.refresh()
		inv.reposition()
	check(snapshot == JSON.stringify(ch.to_dict()) and rng_state == Combat.rng.state, "presentation preserves character and combat RNG")
	for dims in [Vector2i(1280,720), Vector2i(1920,1080), Vector2i(2560,1440), Vector2i(1920,1200), Vector2i(2560,1080)]:
		get_window().size = dims
		await frames(10)
		for station in ["blacksmith", "jeweller", "merchant", "stash"]:
			ui.close_all()
			ui.open_station(station)
			if station in ["blacksmith", "jeweller"]:
				ui.panels[station].select(ch.inventory[1])
				inv.refresh()
				check(inv.bag_slots[1].selected, station + " existing selection")
			await verify_layout("%s_%dx%d" % [station, dims.x, dims.y])
			if station in ["blacksmith", "jeweller"]:
				for index in [0, 7, 32, 39]:
					await click(inv.bag_slots[index])
					check(ui.panels[station].selected == ch.inventory[index], station + " bag corner click %d" % index)
				for slot in ["charm", "ring1", "ring2"]:
					await click(inv.equip_slots[slot])
					check(ui.panels[station].selected == ch.equipment[slot], station + " equipment click " + slot)
				await click(inv.bag_slots[0], MOUSE_BUTTON_RIGHT)
				check(ui.context.visible, station + " context callback")
				ui.hide_context()
				ui.hide_tooltip()
	get_window().size = Vector2i(1280,720)
	ui.panels["stash"]._set_mode("shared")
	await verify_layout("shared_1280x720")
	check(inv.info_label.text.contains("shared stash"), "shared stash hint")
	ui.close_all()
	ui.open("inventory")
	for key in Data.materials:
		ch.materials[key] = 999999999
	ch.gold = 999999999
	Events.currency_changed.emit()
	await verify_layout("large_currency_1280x720")
	for i in 40:
		ch.inventory[i] = null
	for slot in ch.equipment:
		ch.equipment[slot] = null
	for key in Data.materials:
		ch.materials[key] = 0
	ch.gold = 0
	Events.inventory_changed.emit()
	Events.currency_changed.emit()
	await verify_layout("empty_1280x720")
	check(inv.bag_count.text == "0 / 40", "empty count")
	await click(inv.destroy_btn)
	check(ui.context.visible, "destroy menu reachable")
	ui.hide_context()
	# Existing title close callback still closes through UIRoot.
	await click(inv.title_label.get_parent().get_child(1))
	check(not ui.is_open("inventory"), "close callback")
	var file := FileAccess.open(OUT + "/bounds.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence, "\t"))
	file.close()
	ui.close_all()
	Game.level = null
	main.queue_free()
	await frames(3)
	for audio in Sfx.players:
		audio.stop()
		audio.stream = null
	await frames(3)
	print("Inventory chrome: %d passed, %d failed" % [checks - failures, failures])
	get_tree().quit(1 if failures else 0)
