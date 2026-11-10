extends Node
## Phase 3A: live tree chrome, layout and controller input; fixtures never save.

const OUT := "res://tests/screens_out_hud/tree_3a"
var main
var panel
var checks := 0
var failures := 0
var capture := false
var evidence := []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("Tree chrome: " + message)

func frames(n: int = 8) -> void:
	for i in n:
		await get_tree().process_frame

func button(text: String, root: Node = panel) -> Button:
	for child in root.get_children():
		if child is Button and child.text == text:
			return child
		var found := button(text, child)
		if found != null:
			return found
	return null

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
	await frames(2)

func click(control: Control) -> void:
	await click_at(control.get_global_rect().get_center())

func verify_controls(root: Node, bounds: Rect2) -> void:
	for child in root.get_children():
		if child is Control and child.is_visible_in_tree():
			if child is BaseButton or child is LineEdit or child == panel.help_label or child == panel.info:
				check(bounds.grow(0.1).encloses(child.get_global_rect()), "reachable " + str(child.get_class()) + " " + str(child.get_path()))
			if child is Button:
				# Fractional stretch factors round container widths to physical pixels.
				check(child.size.x + 1.0 >= child.get_minimum_size().x, "button text fits " + child.text)
		verify_controls(child, bounds)

func layout(tag: String) -> void:
	await frames(12)
	var bounds: Rect2 = panel.get_global_rect()
	check(Rect2(Vector2.ZERO, main.ui.root.size).grow(0.1).encloses(bounds), tag + " panel fits")
	verify_controls(panel, bounds)
	check(bounds.encloses(panel.view.get_global_rect()) and panel.view.size.x >= 480 and panel.view.size.y >= 240, tag + " usable tree canvas")
	check(panel.view.minimap_rect().end.x <= panel.view.size.x and panel.view.minimap_rect().end.y <= panel.view.size.y, tag + " minimap fits")
	if panel.summary_box.visible:
		check(bounds.encloses(panel.summary_box.get_global_rect()) and not panel.summary_box.get_global_rect().intersects(panel.view.get_global_rect()), tag + " separate summary")
		check(panel.summary.get_content_width() <= panel.summary.size.x + 1, tag + " summary wraps")
	var controls := []
	controls.append_array(panel.chips.values())
	controls.append_array(panel.preset_btns)
	controls.append_array([panel.search, panel.more_tags, panel.behaviour_btn, panel.planner_btn, panel.code_edit])
	for i in controls.size():
		for j in range(i + 1, controls.size()):
			if controls[i].is_visible_in_tree() and controls[j].is_visible_in_tree():
				check(not controls[i].get_global_rect().intersects(controls[j].get_global_rect()), tag + " independent hit areas %d/%d" % [i, j])
	evidence.append({"state": tag, "window": str(get_window().size), "panel": str(bounds), "view": str(panel.view.get_global_rect()), "summary": str(panel.summary_box.get_global_rect())})
	if capture:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		check(img.get_size() == get_window().size, tag + " exact output")
		img.save_png(OUT + "/" + tag + ".png")

func node_click(id: String, which: int = MOUSE_BUTTON_LEFT) -> void:
	panel.view.center_on(panel.view.node_pos(Data.passives[id]), 1.2)
	await frames(2)
	await click_at(panel.view.global_position + panel.view.to_screen(panel.view.node_pos(Data.passives[id])), which)

func _ready() -> void:
	Game.testing = true
	capture = OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name() != "headless"
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		get_window().borderless = true
	get_window().size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(OUT)
	main = load("res://scripts/main.gd").new()
	add_child(main)
	await frames(3)
	Game.new_character("warrior")
	var ch = Game.ch
	ch.level = 60
	ch.gold = 500000
	ch.recalc()
	main.start_game()
	await frames(10)
	Game.level.process_mode = Node.PROCESS_MODE_DISABLED
	main.ui.open("passives")
	panel = main.ui.panels["passives"]
	await frames()
	check(panel.theme != main.ui.root.theme and main.ui.panels["options"].theme == null, "scoped theme")
	var snapshot := JSON.stringify(ch.to_dict())
	var geometry := JSON.stringify(Data.passive_list)
	var rng_state = Combat.rng.state
	for i in 10:
		panel.refresh()
		panel.reposition()
	check(snapshot == JSON.stringify(ch.to_dict()) and geometry == JSON.stringify(Data.passive_list) and rng_state == Combat.rng.state, "presentation preserves character, geometry and RNG")
	await click(panel.chips["fire"])
	await click(panel.chips["cold"])
	check(panel.view.tag_filter.has("fire") and panel.view.tag_filter.has("cold"), "tag chip input")
	await click(panel.behaviour_btn)
	check(panel.view.behaviour_only, "behaviour input")
	await click(button("Clear"))
	check(not panel.view.filter_active() and not panel.behaviour_btn.button_pressed, "clear filters input")
	panel.more_tags.select(1)
	panel.more_tags.item_selected.emit(1)
	check(panel.view.tag_filter.has(str(panel.more_tags.get_item_metadata(1))), "more tag selection")
	await click(button("Clear"))
	panel.search.text = "Momentum"
	panel.search.text_changed.emit(panel.search.text)
	await click(button(">"))
	check(panel.view.search_hits().has("ks_momentum") and panel.view.hit_index == 0 and panel.view.zoom >= panel.view.LOD_NEAR, "search jump input")
	panel.search.clear()
	panel.search.text_changed.emit("")
	await click(button("Minimap"))
	check(not panel.view.show_minimap, "minimap toggle")
	await click(button("Minimap"))
	await click_at(panel.view.global_position + panel.view.minimap_rect().get_center())
	check(panel.view.view_world_rect().get_center().distance_to(panel.view.tree_bounds().get_center()) < 1.0, "minimap jump input")
	var zoom_before: float = panel.view.zoom
	await click_at(panel.view.get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_UP)
	check(panel.view.zoom > zoom_before, "wheel zoom input")
	var pan_before: Vector2 = panel.view.offset
	var drag := InputEventMouseButton.new()
	drag.position = panel.view.get_global_rect().get_center()
	drag.button_index = MOUSE_BUTTON_MIDDLE
	drag.pressed = true
	get_viewport().push_input(drag, true)
	var move := InputEventMouseMotion.new()
	move.position = drag.position + Vector2(30, 20)
	move.relative = Vector2(30, 20)
	move.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	get_viewport().push_input(move, true)
	drag.position = move.position
	drag.pressed = false
	get_viewport().push_input(drag, true)
	check(panel.view.offset.distance_to(pan_before + Vector2(30, 20)) < 0.1, "drag pan input")
	await click(panel.planner_btn)
	await node_click("w_mel1")
	check(ch.plan_has("w_mel1") and not ch.allocated.has("w_mel1") and panel.help_label.text.begins_with("PLANNER"), "planner node input and mode hint")
	await click(button("Apply plan"))
	check(ch.allocated.has("w_mel1"), "apply plan input")
	await click(panel.planner_btn)
	await node_click("w_mel2")
	check(ch.allocated.has("w_mel2"), "allocate input")
	await node_click("w_mel2", MOUSE_BUTTON_RIGHT)
	check(main.ui.confirm.visible and main.ui.confirm_text.text.contains("Refund"), "refund confirmation")
	main.ui.confirm_cb.call()
	main.ui.confirm.visible = false
	check(not ch.allocated.has("w_mel2"), "refund callback")
	await click(panel.preset_btns[1])
	check(main.ui.confirm.visible and main.ui.confirm_text.text.contains("Copy"), "preset confirmation input")
	main.ui.confirm_cb.call()
	main.ui.confirm.visible = false
	check(ch.active_preset == 1 and panel.preset_btns[1].text.begins_with("> 2"), "preset callback")
	# Mastery/gem context menus retain the existing owners and callbacks.
	ch.allocate_path("p4_m_melee", "melee_fury")
	ch.allocate_path("p4_s_w_in")
	ch.add_gem("onyx:2")
	await node_click("p4_s_w_in")
	check(main.ui.context.visible, "socket menu input")
	main.ui.hide_context()
	check(ch.socket_tree_gem("p4_s_w_in", "onyx:2") == "", "socket fixture")
	await node_click("p4_m_melee")
	check(main.ui.context.visible, "mastery menu input")
	main.ui.hide_context()
	await click(button("Build code..."))
	check(panel.code_box.visible and panel.code_edit.has_focus(), "build code focus")
	# Avoid changing the user's clipboard in verification; use the same export API.
	panel.code_edit.text = ch.export_build_code(true)
	await click(button("Import as plan"))
	check(panel.view.planner and panel.code_edit.text.begins_with("POD1-"), "import input")
	ch.plan_add("ks_momentum")
	panel.refresh()
	await click(button("Summary"))
	check(panel.summary_box.visible and panel.summary.text.contains("Masteries") and panel.summary.text.contains("Socketed gems"), "summary input and source text")
	for toast in main.ui.toasts.get_children():
		toast.queue_free()
	for dims in [Vector2i(1280,720), Vector2i(1920,1080), Vector2i(2560,1440), Vector2i(1920,1200), Vector2i(2560,1080)]:
		get_window().size = dims
		await frames(12)
		panel.view.center_on_class()
		await layout("expanded_%dx%d" % [dims.x, dims.y])
		panel.toggle_summary()
		panel.toggle_code()
		panel.view.fit()
		await layout("tree_%dx%d" % [dims.x, dims.y])
		panel.toggle_summary()
		panel.toggle_code()
	get_window().size = Vector2i(1280, 720)
	await frames(12)
	panel.summary_box.scroll_vertical = 0
	for i in 12:
		await click_at(panel.summary_box.get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_DOWN)
	check(panel.summary_box.scroll_vertical > 0, "summary wheel input reaches remaining content")
	panel.summary_box.scroll_vertical = int(panel.summary_box.get_v_scroll_bar().max_value)
	check(panel.summary_box.scroll_vertical + panel.summary_box.size.y >= panel.summary.size.y - 16, "summary end reachable")
	await click(button("Clear plan"))
	check(ch.plan.is_empty(), "clear plan input")
	panel.search.grab_focus()
	check(panel.search.get_theme_stylebox("focus") is StyleBoxFlat and panel.planner_btn.get_theme_stylebox("focus") is StyleBoxFlat, "visible keyboard focus materials")
	await click(panel.title_label.get_parent().get_child(1))
	check(not main.ui.is_open("passives"), "close input")
	main.ui.open("passives")
	check(panel.view.planner and ch.tree_gems.get("p4_s_w_in") == "onyx:2", "reopen preserves mode and socket")
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
	print("Tree chrome: %d passed, %d failed" % [checks - failures, failures])
	get_tree().quit(1 if failures else 0)
