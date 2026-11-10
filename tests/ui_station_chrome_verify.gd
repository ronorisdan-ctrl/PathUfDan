extends Node
## Phase 3C: existing station controllers, viewport input and bounded cabinet layout.
const OUT := "res://tests/screens_out_hud/stations_3c"
var main
var checks := 0
var failures := 0
var capture := false
var evidence := []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("Station chrome: " + message)

func frames(n: int = 8) -> void:
	for i in n:
		await get_tree().process_frame

func click_at(point: Vector2, which: int = MOUSE_BUTTON_LEFT) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	get_viewport().push_input(motion, true)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = which
		event.pressed = down
		get_viewport().push_input(event, true)
	await frames(3)

func click(control: Control) -> void:
	check(control.is_visible_in_tree(), "input target visible " + str(control.get_path()))
	await click_at(control.get_global_rect().get_center())

func buttons(root: Node) -> Array:
	var result := []
	for child in root.get_children():
		if child is Button:
			result.append(child)
		result.append_array(buttons(child))
	return result

func find_button(root: Node, prefix: String) -> Button:
	for button in buttons(root):
		if button.text.strip_edges().begins_with(prefix):
			return button
	check(false, "button found: " + prefix)
	return null

func reveal(control: Control) -> void:
	var parent := control.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			parent.ensure_control_visible(control)
			await frames()
		parent = parent.get_parent()

func confirm_choice(accept: bool) -> void:
	check(main.ui.confirm.visible, "existing UI root owns confirmation")
	await click(find_button(main.ui.confirm, "Confirm" if accept else "Cancel"))

func validate(root: Node) -> void:
	for child in root.get_children():
		if child is Control and child.is_visible_in_tree():
			if child is Button or child is Label:
				check(child.size.x + 1 >= child.get_minimum_size().x, "text fits " + str(child.get_path()))
			if child is RichTextLabel:
				check(child.get_content_width() <= child.size.x + 1, "rich text fits " + str(child.get_path()))
			if child is ScrollContainer:
				check(child.get_h_scroll_bar().max_value <= child.size.x + 1, "no hidden horizontal overflow " + str(child.get_path()))
				check(child.size.y >= 48, "usable scroll " + str(child.get_path()))
		validate(child)

func layout(panel, tag: String) -> void:
	main.ui.hide_tooltip(true)
	for toast in main.ui.toasts.get_children():
		toast.queue_free()
	panel.reposition()
	await frames(12)
	var bounds: Rect2 = panel.get_global_rect()
	var viewport := Rect2(Vector2.ZERO, main.ui.root.size)
	check(viewport.grow(0.1).encloses(bounds), tag + " panel fits " + str(bounds))
	check(bounds.encloses(panel.title_label.get_parent().get_child(1).get_global_rect()), tag + " close reachable")
	if main.ui.is_open("inventory"):
		var bag: Rect2 = main.ui.panels.inventory.get_global_rect()
		check(viewport.grow(0.1).encloses(bag) and not bounds.intersects(bag), tag + " station and inventory coexist")
	validate(panel)
	for button in ["confirm_btn", "buy_btn", "upgrade_btn", "follow_btn", "rename_btn", "enter_btn", "reroll_btn"]:
		var action = panel.get(button)
		if action is Button and action.is_visible_in_tree():
			check(bounds.encloses(action.get_global_rect()), tag + " pinned " + button)
	evidence.append({"state": tag, "window": str(get_window().size), "panel": str(bounds)})
	if capture:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		check(img.get_size() == get_window().size, tag + " exact capture dimensions")
		img.save_png(OUT + "/" + tag + ".png")

func fixture() -> Dictionary:
	var it: Dictionary = Loot.roll_item_of("rusted_sword", "rare", 42)
	it["uid"] = Game.ch.take_uid()
	it["sockets"] = 3
	it["gems"] = ["ruby:0", "", ""]
	return it

func verify_vendor() -> void:
	var ch = Game.ch
	main.ui.open_station("merchant")
	var panel = main.ui.panels.vendor
	await frames()
	var it: Dictionary = Game.vendor_stock[0]
	var gold: int = ch.gold
	await click(panel.slots[0])
	await confirm_choice(false)
	check(ch.gold == gold and Game.vendor_stock.has(it), "cancel purchase keeps gold and stock")
	await click(panel.slots[0])
	await confirm_choice(true)
	check(ch.gold == gold - Loot.buy_value(it) and ch.inventory.has(it) and not Game.vendor_stock.has(it), "buy transfers exactly once")
	ch.flask_charges = [0.0, 0.0]
	await click(find_button(panel, "Refill"))
	check(ch.flask_charges == [3.0, 3.0], "refill input")
	gold = ch.gold
	await click(find_button(panel, "New stock"))
	check(ch.gold == gold - 25 and Game.vendor_stock.size() == 8, "reroll stock input and cost")
	gold = ch.gold
	var runes: Dictionary = ch.runes.duplicate()
	await click(find_button(panel, "Buy random rune"))
	await confirm_choice(true)
	check(ch.gold == gold - panel.rune_price() and ch.runes != runes, "rune purchase callback")
	ch.gold = 0
	it = Game.vendor_stock[0]
	await click(panel.slots[0])
	check(not main.ui.confirm.visible and Game.vendor_stock.has(it), "unaffordable purchase refused")
	ch.gold = 500000
	main.ui.close_all()

func verify_crafting() -> void:
	var ch = Game.ch
	var it := fixture()
	ch.inventory[0] = it
	main.ui.open_station("blacksmith")
	var panel = main.ui.panels.blacksmith
	await frames()
	await click(main.ui.panels.inventory.bag_slots[0])
	check(panel.selected == it and main.ui.panels.inventory.bag_slots[0].selected, "bag single click selects crafting item")
	var upgrade := find_button(panel.op_box, "> Upgrade")
	if upgrade == null:
		return
	await reveal(upgrade)
	await click(upgrade)
	var before := JSON.stringify(ch.to_dict())
	await click(panel.confirm_btn)
	await confirm_choice(false)
	check(JSON.stringify(ch.to_dict()) == before, "craft cancellation keeps item and currency")
	var cost: Dictionary = Loot.craft_cost("upgrade", it)
	var old_gold: int = ch.gold
	await click(panel.confirm_btn)
	await confirm_choice(true)
	check(int(it.get("upgrade", 0)) == 1 and ch.gold == old_gold - int(cost.get("gold", 0)), "craft confirmation preserves cost/upgrade controller")
	for i in 25:
		await click_at(panel.scroll.get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_DOWN)
	check(panel.scroll.scroll_vertical > 0, "craft content scrolls with pinned action")
	it["corruption"] = 100
	panel.select(it)
	await frames()
	check(panel.confirm_btn.disabled, "sealed craft disabled")
	for button in buttons(panel.op_box):
		check(button.disabled, "sealed operations disabled")
	await layout(panel, "blacksmith_sealed_1280x720")
	main.ui.close_all()
	check(panel.selected == null and not main.ui.is_open("inventory"), "station close resets selection and closes inventory")
	it["corruption"] = 0
	main.ui.open_station("jeweller")
	panel = main.ui.panels.jeweller
	await frames()
	await click(main.ui.panels.inventory.bag_slots[0])
	check(panel.selected == it, "bag single click selects socket item")
	var gems: int = ch.gems.get("ruby:0", 0)
	await reveal(panel.socket_box.get_child(1))
	await click(panel.socket_box.get_child(1))
	check(main.ui.context.visible, "socket action opens existing gem context")
	await click(find_button(main.ui.context, Loot.gem_name("ruby:0")))
	check(it.gems[1] == "ruby:0" and ch.gems.get("ruby:0", 0) == gems - 1, "socket transfers gem")
	await click(panel.socket_box.get_child(1))
	check(it.gems[1] == "" and ch.gems.get("ruby:0", 0) == gems, "unsocket returns gem")
	var combine := find_button(panel.pouch_box, "Combine 3")
	await reveal(combine)
	await click(combine)
	check(ch.gems.get("ruby:0", 0) == gems - 3 and int(ch.gems.get("ruby:1", 0)) >= 1, "combine action")
	old_gold = ch.gold
	await click(panel.buy_btn)
	check(ch.gold == old_gold - panel.gem_price(), "gem purchase action")
	it["corruption"] = 100
	panel.refresh()
	await frames()
	for button in buttons(panel.socket_box):
		check(button.disabled, "sealed socket visibly disabled")
	await layout(panel, "jeweller_sealed_1280x720")
	main.ui.close_all()

func verify_stash() -> void:
	var ch = Game.ch
	var panel = main.ui.panels.stash
	for mode in ["stash", "shared"]:
		var it := fixture()
		ch.inventory[0] = it
		main.ui.open_station("stash")
		await frames()
		await click(panel.mode_btns[mode])
		await click(main.ui.panels.inventory.bag_slots[0])
		check(ch.inventory[0] == null and panel._array().has(it), mode + " bag deposit input")
		var index: int = panel._array().find(it)
		await click(panel.slots[index])
		check(ch.inventory.has(it) and not panel._array().has(it), mode + " withdrawal input")
		var total: int = panel._tab_total()
		var gold: int = ch.gold
		await click(find_button(panel.tab_row, "+ Buy tab"))
		await confirm_choice(false)
		check(panel._tab_total() == total and ch.gold == gold, mode + " tab purchase cancel")
		await click(find_button(panel.tab_row, "+ Buy tab"))
		await confirm_choice(true)
		check(panel._tab_total() == total + 1 and panel.tab[mode] == total and ch.gold < gold, mode + " tab purchase callback")
		main.ui.close_all()
	# Maximum tab strip wraps/scrolls without displacing the item grid or footer.
	ch.stash_extra_tabs = 10
	ch.stash.resize(11 * 56)
	SharedStash.extra_tabs = 10
	SharedStash.slots.resize(11 * 56)

func verify_pets() -> void:
	var ch = Game.ch
	main.ui.open_station("pets")
	var panel = main.ui.panels.pets
	await frames()
	var id: String = Data.pet_list[0].id
	await click(find_button(panel.list_box, "Buy"))
	check(ch.owns_pet(id), "pet buy input")
	check(ch.active_pet == id, "newly bought pet follows through existing controller")
	await click(panel.follow_btn)
	check(ch.active_pet == "", "send home input")
	await click(panel.follow_btn)
	check(ch.active_pet == id, "follow input")
	panel.name_edit.text = "Cabinet Friend"
	await click(panel.rename_btn)
	check(ch.pet_name(id) == "Cabinet Friend", "rename input")
	var tier: int = ch.pet_tier(id)
	await click(panel.upgrade_btn)
	await confirm_choice(false)
	check(ch.pet_tier(id) == tier, "pet upgrade cancel")
	await click(panel.upgrade_btn)
	await confirm_choice(true)
	check(ch.pet_tier(id) == tier + 1, "pet upgrade callback")
	Game.level.is_town = false
	panel.refresh()
	await frames()
	check(panel.upgrade_btn.disabled, "away upgrade disabled")
	for button in buttons(panel.list_box):
		if button.text == "Buy":
			check(button.disabled, "away purchase disabled")
	await click(panel.follow_btn)
	check(ch.active_pet == "", "dismiss works away from town")
	await layout(panel, "pets_away_1280x720")
	Game.level.is_town = true
	main.ui.close_all()

func verify_training() -> void:
	Game.training_in_tests = true
	main.ui.open_station("training")
	var panel = main.ui.panels.training
	await frames()
	await click(panel.choice_btns.type.aoe)
	check(TrainingLog.settings.type == "aoe" and panel.spacing_row.visible, "AoE choice input reveals spacing")
	await click(panel.choice_btns.spacing.spread)
	await click(panel.choice_btns.profile.t6_boss)
	check(TrainingLog.settings.spacing == "spread" and TrainingLog.settings.profile == "t6_boss", "flowing choices preserve settings")
	await click(panel.spawn_btn)
	check(TrainingLog.has_run() and Game.level.training_dummies.size() == 3, "spawn input uses hub controller")
	TrainingLog.report({"kind":"hit", "amount":12345.0, "skill_id":"fireball", "dummy":1, "crit":false, "cast_id":1})
	TrainingLog.tick(100.0)
	check(not TrainingLog.last_result.is_empty(), "existing training result generated")
	await click(panel.tab_btns.result)
	check(panel.result_box.visible and not panel.setup_box.get_parent().visible, "result tab replaces setup scroll")
	await layout(panel, "training_result_1280x720")
	await click(panel.tab_btns.history)
	await click(buttons(panel.history_list)[0])
	check(panel.open_row == 0, "history expand input")
	await layout(panel, "training_history_1280x720")
	await click(panel.clear_btn)
	await confirm_choice(false)
	check(not TrainingLog.history().is_empty(), "history clear cancel")
	await click(panel.clear_btn)
	await confirm_choice(true)
	check(TrainingLog.history().is_empty() and panel.clear_btn.disabled, "history clear callback")
	await click(panel.tab_btns.setup)
	await click(panel.reset_btn)
	check(TrainingLog.last_result.is_empty() and not TrainingLog.is_running(), "training reset input")
	await click(panel.remove_btn)
	check(not TrainingLog.has_run(), "training remove input")
	main.ui.close_all()

func verify_dungeon() -> void:
	main.ui.open_station("dungeon")
	var panel = main.ui.panels.dungeon
	await frames()
	var last: Button = buttons(panel.list)[-1]
	await reveal(last)
	await click(last)
	check(panel.enter_btn.disabled, "locked tier enter disabled")
	await layout(panel, "dungeon_locked_1280x720")
	Game.ch.progress.highest_tier = 99
	panel.refresh()
	await frames()
	for dungeon in Data.dungeon_list:
		if int(dungeon.get("mod_count", [0,0])[1]) > 0:
			panel._choose(dungeon.id)
			break
	await frames()
	var gold: int = Game.ch.gold
	var cost: int = panel.reroll_cost(Data.dungeons[panel.chosen])
	await click(panel.reroll_btn)
	check(Game.ch.gold == gold - cost and not panel.enter_btn.disabled, "modifier reroll input and cost")
	main.ui.close_all()

func _ready() -> void:
	print("Station chrome: initialize")
	Game.testing = true
	capture = OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name() != "headless"
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		get_window().borderless = true
	get_window().size = Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute(OUT)
	var shared_before: Array = SharedStash.slots.duplicate(true)
	var shared_extra: int = SharedStash.extra_tabs
	SharedStash.extra_tabs = 0
	SharedStash.slots = []
	SharedStash.slots.resize(56)
	main = load("res://scripts/main.gd").new()
	add_child(main)
	print("Station chrome: main ready")
	await frames(3)
	Game.new_character("mage")
	var ch = Game.ch
	ch.level = 60
	ch.gold = 500000
	for material in Data.materials:
		ch.materials[material] = 9999
	ch.gems = {"ruby:0":9}
	ch.refresh_unlocks(false)
	ch.recalc()
	main.start_game()
	print("Station chrome: game ready")
	await frames(10)
	Game.level.process_mode = Node.PROCESS_MODE_DISABLED
	Game.refresh_vendor()
	print("Station chrome: vendor")
	await verify_vendor()
	print("Station chrome: crafting")
	await verify_crafting()
	print("Station chrome: stash")
	await verify_stash()
	print("Station chrome: pets")
	await verify_pets()
	print("Station chrome: training")
	await verify_training()
	print("Station chrome: dungeon")
	await verify_dungeon()
	for gem in Data.gems:
		for tier in 4:
			ch.gems[Loot.gem_id(gem, tier)] = 999
	for dims in [Vector2i(1280,720), Vector2i(1920,1080), Vector2i(2560,1440), Vector2i(1920,1200), Vector2i(2560,1080)]:
		get_window().size = dims
		await frames(12)
		for station in ["merchant", "blacksmith", "jeweller", "stash", "pets", "training", "dungeon"]:
			main.ui.close_all()
			main.ui.open_station(station)
			var name: String = "vendor" if station == "merchant" else station
			var panel = main.ui.panels[name]
			if name in ["blacksmith", "jeweller"]:
				ch.inventory[0] = fixture()
				panel.select(ch.inventory[0])
			await frames()
			await layout(panel, "%s_%dx%d" % [name, dims.x, dims.y])
			var before := JSON.stringify(ch.to_dict())
			var rng_state = Combat.rng.state
			for i in 3:
				panel.refresh()
				panel.reposition()
			await frames()
			check(before == JSON.stringify(ch.to_dict()) and Combat.rng.state == rng_state, name + " presentation preserves character and combat RNG")
			check(panel.theme != null and panel.theme != main.ui.root.theme, name + " local theme")
			await click(panel.title_label.get_parent().get_child(1))
			check(not main.ui.is_open(name), name + " close input")
	check(main.ui.panels.options.theme == null and main.ui.panels.pause.theme == null, "menus remain outside assigned batch")
	main.ui.close_all()
	main.ui.open_station("jeweller")
	await frames()
	var jeweller = main.ui.panels.jeweller
	var gold: int = ch.gold
	jeweller.buy_btn.grab_focus()
	check(jeweller.buy_btn.has_focus() and jeweller.buy_btn.get_theme_stylebox("focus") is StyleBoxFlat, "native keyboard focus visible")
	for down in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_ENTER
		key.pressed = down
		get_viewport().push_input(key, true)
	await frames()
	check(ch.gold == gold - jeweller.gem_price(), "native focused action keyboard activation")
	var pouch: ScrollContainer = jeweller.pouch_box.get_parent()
	for i in 30:
		await click_at(pouch.get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_DOWN)
	check(pouch.scroll_vertical > 0, "full gem pouch scroll input")
	await reveal(jeweller.pouch_box.get_child(jeweller.pouch_box.get_child_count() - 1))
	check(jeweller.pouch_box.get_child(jeweller.pouch_box.get_child_count() - 1).get_global_rect().end.y <= pouch.get_global_rect().end.y + 1, "last gem row reachable")
	main.ui.close_all()
	main.ui.open_station("dungeon")
	await frames()
	await click(main.ui.panels.dungeon.enter_btn)
	await frames(12)
	check(not Game.level.is_town and main.ui.open_set.is_empty(), "Enter Dungeon input preserves real transition and closes panels")
	SharedStash.slots = shared_before
	SharedStash.extra_tabs = shared_extra
	var file := FileAccess.open(OUT + "/bounds.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence, "\t"))
	file.close()
	main.ui.close_all()
	Game.level = null
	main.queue_free()
	await frames(3)
	for player in Sfx.players:
		player.stop()
		player.stream = null
	await get_tree().create_timer(0.1).timeout
	print("Station chrome: %d passed, %d failed" % [checks - failures, failures])
	get_tree().quit(1 if failures else 0)
