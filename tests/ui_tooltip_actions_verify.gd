extends Node
## Phase 2C: production hover placement, overflow input and irreversible callbacks.
const C = preload("res://scripts/core/corruption_system.gd")
const T = preload("res://tests/test_corruption_system.gd")
const Character = preload("res://scripts/core/character_data.gd")
const OUT := "res://tests/screens_out_hud/tooltips_2c"
var main
var capture := false
var checks := 0
var failures := 0
var evidence := []
var clicked := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("Tooltip/actions: " + label)

func frames(n: int = 6) -> void:
	for i in n:
		await get_tree().process_frame

func move(point: Vector2) -> void:
	if DisplayServer.get_name() != "headless":
		Input.warp_mouse(point)
	var event := InputEventMouseMotion.new()
	event.position = point
	get_viewport().push_input(event, true)
	await frames(3)

func key(code: int) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		get_viewport().push_input(event)
		if not get_viewport().is_input_handled():
			get_viewport().push_unhandled_input(event)
	await frames(3)

func click_at(point: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	await move(point)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = button
		event.pressed = pressed
		get_viewport().push_input(event, true)
	await frames(3)

func shot(tag: String) -> void:
	await frames()
	if capture:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		check(img.get_size() == get_window().size, tag + " exact output")
		img.save_png(OUT + "/" + tag + ".png")

func sealed_fixture() -> Dictionary:
	var it: Dictionary = Loot.make_unique("widowmaker", 60)
	it["uid"] = Game.ch.take_uid()
	it["upgrade"] = 5
	it["locked"] = true
	it["sockets"] = 3
	it["gems"] = ["ruby:3", "sapphire:3", "emerald:3"]
	it["corruption"] = 100
	it["corruption_roll_version"] = 1
	var index := C.registry_index(Data.corruption_affixes)
	it["corrupted_prefix"] = C.roll_affix(index["cw_splintered_fate"], 60, Data.corruption_cfg, T.SequenceRng.new([], true))
	it["corrupted_suffix"] = C.roll_affix(index["cw_of_frenzy"], 60, Data.corruption_cfg, T.SequenceRng.new([], true))
	return it

func target() -> Dictionary:
	var it: Dictionary = Loot.roll_item_of("rusted_sword", "rare", 42)
	it["uid"] = Game.ch.take_uid()
	it["sockets"] = 1
	it["gems"] = ["ruby:0"]
	Game.ch.inventory[1] = it
	return it

func force_outcome(bs, low: int, high: int) -> void:
	var rng := RandomNumberGenerator.new()
	for seed_value in 10000:
		rng.seed = seed_value
		var roll := rng.randi_range(0, 9999)
		if roll >= low and roll <= high:
			bs.corr_rng.seed = seed_value
			return
	check(false, "deterministic outcome seed")

func bounds(tag: String) -> void:
	var ui = main.ui
	var area := Rect2(Vector2(7, 7), ui.root.size - Vector2(14, 14))
	check(area.encloses(ui.tooltip.get_global_rect()), tag + " candidate bounded")
	if ui.tooltip2.visible:
		check(area.encloses(ui.tooltip2.get_global_rect()), tag + " equipped bounded")
		check(not ui.tooltip.get_global_rect().intersects(ui.tooltip2.get_global_rect()), tag + " pair separated")
	evidence.append({"state": tag, "logical": str(ui.root.size), "candidate": str(ui.tooltip.get_global_rect()), "equipped": str(ui.tooltip2.get_global_rect()), "content_height": ui.tooltip_text.get_content_height()})

func _ready() -> void:
	Game.testing = true
	capture = OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name() != "headless"
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		get_window().borderless = true
	get_window().size = Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute(OUT)
	Loot.set_seed(20261105)
	main = load("res://scripts/main.gd").new()
	add_child(main)
	await frames()
	Game.new_character("ranger")
	var ch = Game.ch
	ch.level = 60
	ch.gold = 999999
	for material in Data.materials:
		ch.materials[material] = 100
	ch.inventory.fill(null)
	var item := sealed_fixture()
	ch.inventory[0] = item
	var equipped := sealed_fixture()
	equipped["locked"] = false
	ch.equipment["main_hand"] = equipped
	ch.recalc()
	main.start_game()
	await frames(12)
	Game.level.process_mode = Node.PROCESS_MODE_DISABLED
	var ui = main.ui
	ui.open("inventory")
	var inv = ui.panels["inventory"]
	await frames()
	inv.bag_slots[0].clicked.connect(func(_sl, _button, _shift): clicked += 1)
	var snapshot := JSON.stringify(ch.to_dict())
	var combat_state = Combat.rng.state
	# Actual bag hover, not a manually positioned card.
	await move(inv.bag_slots[0].get_global_rect().get_center())
	check(ui.tooltip.visible and ui.tooltip2.visible, "production slot hover opens pair")
	check(ui.tooltip_text.text == Loot.tooltip(item, ch) + "\n[color=#ffd060]Locked: cannot be sold, salvaged or destroyed[/color]" + ui._compare_lines(item), "complete source text and comparison maths")
	check(ui.tooltip2_text.text == "[color=#8a8494]Currently equipped[/color]\n" + Loot.tooltip(equipped, ch), "complete equipped text")
	check(ui.tooltip_text.text.contains("fixed") and ui.tooltip_text.text.contains("[SUFFIX]") and ui.tooltip_text.text.contains("FINAL"), "fixed, suffix and seal sections")
	check(ui.tooltip.overflowing and ui.tooltip2.overflowing and ui.tooltip.hint.visible, "both long cards expose reading hint")
	check(ui.tooltip.mouse_filter == Control.MOUSE_FILTER_IGNORE and ui.tooltip_text.mouse_filter == Control.MOUSE_FILTER_IGNORE, "ordinary hover ignores pointer")
	# Both full cards remain independently readable at all supported output sizes.
	for dims in [Vector2i(1280,720), Vector2i(1920,1080), Vector2i(2560,1440), Vector2i(1920,1200), Vector2i(2560,1080)]:
		get_window().size = dims
		await frames(10)
		ui.hide_tooltip(true)
		await move(Vector2(600, 280))
		await move(inv.bag_slots[0].get_global_rect().get_center())
		await frames()
		bounds("hover_%dx%d" % [dims.x,dims.y])
		await shot("hover_%dx%d" % [dims.x,dims.y])
		await key(KEY_F4)
		check(ui.tooltip_reading, "F4 enters reading " + str(dims))
		var frozen: Vector2 = ui.tooltip.position
		await move(Vector2(620, 400))
		check(ui.tooltip.visible and ui.tooltip.position == frozen, "reading survives unhover and freezes " + str(dims))
		await key(KEY_END)
		var bar = ui.tooltip_text.get_v_scroll_bar()
		check(bar.value > 0 and bar.value >= bar.max_value - bar.page - 1, "candidate last line reachable " + str(dims))
		await key(KEY_TAB)
		await key(KEY_END)
		bar = ui.tooltip2_text.get_v_scroll_bar()
		check(bar.value > 0 and bar.value >= bar.max_value - bar.page - 1, "equipped last line reachable " + str(dims))
		bounds("reading_%dx%d" % [dims.x,dims.y])
		await shot("reading_%dx%d" % [dims.x,dims.y])
		await key(KEY_PAGEUP)
		check(bar.value < bar.max_value - bar.page - 1, "equipped page-up " + str(dims))
		await key(KEY_ESCAPE)
		check(not ui.tooltip_reading and not ui.tooltip.visible and ui.is_open("inventory") and not ui.is_open("pause"), "Escape dismisses only reader " + str(dims))
	check(snapshot == JSON.stringify(ch.to_dict()) and combat_state == Combat.rng.state, "presentation preserves character and combat RNG")
	get_window().size = Vector2i(1280,720)
	await frames(10)
	# Independent edge placements; neither card may be pushed off any edge.
	for point in [Vector2(1,1), Vector2(ui.root.size.x - 1,1), ui.root.size - Vector2.ONE, Vector2(1,ui.root.size.y - 1)]:
		await move(point)
		ui.item_tooltip(item, true)
		await frames()
		bounds("edge " + str(point))
	# Reading consumes only its own keys and pointer area; dismiss click is inert.
	await key(KEY_F4)
	await key(KEY_HOME)
	await click_at(ui.tooltip.get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_DOWN)
	check(ui.tooltip_text.get_v_scroll_bar().value > 0, "wheel scrolls candidate")
	ui.item_tooltip(equipped, false)
	check(ui.tooltip2.visible, "other hover cannot replace frozen pair")
	var previous_clicks := clicked
	await click_at(inv.bag_slots[0].get_global_rect().get_center())
	check(not ui.tooltip_reading and clicked == previous_clicks, "outside dismiss click never reaches underlying slot")
	ui.item_tooltip(item, true)
	await frames()
	await key(KEY_F4)
	Events.inventory_changed.emit()
	check(not ui.tooltip.visible and not ui.tooltip_reading, "item mutation invalidates reader")
	ui.item_tooltip(item, true)
	await frames()
	await key(KEY_F4)
	get_window().size = Vector2i(1920,1200)
	await frames(10)
	bounds("resize_frozen_pair")
	check(ui.tooltip_reading, "resize preserves reader")
	get_window().size = Vector2i(1280,720)
	await frames(10)
	bounds("resize_frozen_pair_back")
	await key(KEY_ESCAPE)
	ui.show_tooltip("Short complete tooltip")
	await frames()
	check(ui.tooltip_text.get_content_height() <= ui.tooltip_text.size.y + 1 and ui.tooltip.size.y < 100 and not ui.tooltip.hint.visible and not ui.tooltip2.visible, "short single card fits naturally after long pair")
	await key(KEY_F4)
	check(not ui.tooltip_reading, "F4 inert for short tooltip")
	ui.item_tooltip(item, true)
	await frames()
	await key(KEY_F4)
	ui.close("inventory")
	check(not ui.tooltip.visible and not ui.tooltip_reading, "panel close clears reader")
	ui.open("inventory")
	ui.show_context([["Enabled action", func(): pass], ["Unavailable action", func(): pass, false]])
	await frames()
	check(Rect2(Vector2.ZERO,ui.root.size).encloses(ui.context.get_global_rect()), "context actions bounded")
	check(ui.context.get_child(0).get_child(1).disabled, "context refusal remains disabled")
	ui.item_tooltip(item, false)
	check(ui.tooltip_text.text.contains("Locked") and not ui.tooltip.visible, "modal keeps public tooltip text current without obscuring actions")
	await shot("context_actions")
	ui.hide_context()
	# Quarantine and ordinary tier text still use their authoritative helpers.
	var invalid := item.duplicate(true)
	invalid["corruption_invalid_prefix"] = {"id": "future"}
	ui.item_tooltip(invalid, false)
	check(ui.tooltip_text.text.contains("preserved but inactive"), "quarantine warning preserved")
	var plain := target()
	ui.item_tooltip(plain, false)
	check(ui.tooltip_text.text.contains("(T"), "normal affix tiers preserved")
	await verify_actions(item)
	var file := FileAccess.open(OUT + "/bounds.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence, "\t"))
	file.close()
	ui.close_all()
	Game.level = null
	main.queue_free()
	await frames()
	for audio in Sfx.players:
		audio.stop()
		audio.stream = null
	await frames()
	print("Tooltip/actions: %d passed, %d failed" % [checks - failures, failures])
	get_tree().quit(1 if failures else 0)

func verify_actions(sealed: Dictionary) -> void:
	var ui = main.ui
	var ch = Game.ch
	ui.close_all()
	ui.open_station("blacksmith")
	var bs = ui.panels["blacksmith"]
	var it := target()
	bs.select(it)
	bs.op = "corrupt"
	bs.refresh()
	await bs._show_preview()
	await shot("corruption_preview")
	var before := JSON.stringify(ch.to_dict())
	await click_at(bs.confirm_btn.get_global_rect().get_center())
	check(ui.confirm.visible and ui.confirm_text.text.contains(Loot.corruption_warning()), "real button opens authoritative irreversible warning")
	await frames()
	check(Rect2(Vector2.ZERO,ui.root.size).encloses(ui.confirm.get_global_rect()), "irreversible confirmation bounded")
	await shot("corruption_confirmation")
	await key(KEY_ESCAPE)
	check(not ui.confirm.visible and before == JSON.stringify(ch.to_dict()), "cancel has no transaction effects")
	# Confirmation retains original UID, rejects a missing item without payment.
	bs._craft()
	ch.inventory[1] = null
	var brands: int = ch.materials["abyssal_brand"]
	await key(KEY_SPACE)
	check(ch.materials["abyssal_brand"] == brands and ch.corruption_actions.is_empty(), "stale UID rejected by existing callback")
	ch.inventory[1] = it
	bs.select(it)
	bs._craft()
	var other = Character.new()
	other.setup_new("mage")
	Game.ch = other
	await key(KEY_SPACE)
	Game.ch = ch
	check(ch.materials["abyssal_brand"] == brands and int(it.get("corruption",0)) == 0, "changed character rejects pending confirmation")
	# Failure uses an invalid manual slot, so no real save can be written.
	bs.select(it)
	bs._craft()
	before = JSON.stringify(ch.to_dict())
	var slot_before: int = Game.current_slot
	Game.current_slot = 0
	Game.testing = false
	force_outcome(bs, 0, 1499)
	ui._on_confirm()
	Game.testing = true
	Game.current_slot = slot_before
	check(before == JSON.stringify(ch.to_dict()) and bs.selected == it and not bs.confirm_btn.disabled, "failed save restores item/cost/receipt and usable action")
	for outcome in [[0,1499,"destroyed"], [1500,3999,"no_modifier"], [4000,9599,"single"], [9600,9999,"double"]]:
		it = target()
		bs.select(it)
		bs.op = "corrupt"
		bs.refresh()
		force_outcome(bs,outcome[0],outcome[1])
		brands = ch.materials["abyssal_brand"]
		var gems_before: int = ch.gems.get("ruby:0",0)
		bs._craft()
		await key(KEY_SPACE)
		check(ch.materials["abyssal_brand"] == brands - 1, outcome[2] + " pays once")
		if outcome[2] == "destroyed":
			check(ch.inventory[1] == null and bs.selected == null and int(ch.gems.get("ruby:0",0)) == gems_before + 1 and bs.corruption_result.text.contains("gems recovered"), "destruction/result/gem recovery")
		else:
			check(bs.selected == it and int(it["corruption"]) == 100 and bs.confirm_btn.disabled and bs.corruption_result.text.contains("FINAL"), outcome[2] + " survival result sealed")
			var count := int(it.get("corrupted_prefix") != null) + int(it.get("corrupted_suffix") != null)
			check(count == {"no_modifier":0,"single":1,"double":2}[outcome[2]], outcome[2] + " authoritative implicits")
		await frames()
		check(bs.get_global_rect().encloses(bs.confirm_btn.get_global_rect()) and bs.scroll.get_global_rect().intersects(bs.corruption_result.get_global_rect()), outcome[2] + " result visible/action pinned")
		await shot("corruption_result_" + outcome[2])
	bs.select(sealed)
	bs.op = "corrupt"
	bs.refresh()
	check(bs.confirm_btn.disabled and bs.corr_bar.visible, "sealed action refused; percentage bar retained")
	ui.close_all()
	ui.open_station("jeweller")
	var jeweller = ui.panels["jeweller"]
	jeweller.select(sealed)
	await frames()
	for button in jeweller.socket_box.get_children():
		check(button is Button and button.disabled and button.tooltip_text.contains("Corrupted"), "jeweller sealed socket disabled with reason")
	before = JSON.stringify(ch.to_dict())
	jeweller._unsocket(0)
	jeweller._do_socket(0,"ruby:0")
	check(before == JSON.stringify(ch.to_dict()), "jeweller controller refuses sealed edits")
	await shot("jeweller_sealed")
	# Long confirmations scroll while keeping both actions inside the viewport.
	ui.ask("Warning\n".repeat(100), func(): pass)
	await frames()
	check(Rect2(Vector2.ZERO,ui.root.size).encloses(ui.confirm.get_global_rect()) and ui.confirm_text.get_content_height() > ui.confirm_text.size.y, "long confirmation bounded with scroll access")
	ui._on_cancel()
