extends Node
## Phase 3B: presentation, viewport input and existing character controllers.

const OUT := "res://tests/screens_out_hud/character_3b"
var main
var checks := 0
var failures := 0
var capture := false
var evidence := []

class NearbyEnemy extends Node2D:
	var alive := true
	var aggro := true

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("Character chrome: " + message)

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
	await frames(2)

func click(control: Control, which: int = MOUSE_BUTTON_LEFT) -> void:
	await click_at(control.get_global_rect().get_center(), which)

func buttons(root: Node) -> Array:
	var result := []
	for child in root.get_children():
		if child is Button:
			result.append(child)
		result.append_array(buttons(child))
	return result

func skill_row(panel, sid: String) -> Control:
	for card in panel.list.get_children():
		var row = card.get_child(0)
		if row.get_child(0).sk.get("id") == sid:
			return row
	return null

func reveal(scroll: ScrollContainer, control: Control) -> void:
	scroll.ensure_control_visible(control)
	await frames(6)

func validate_text(root: Node) -> void:
	for child in root.get_children():
		if child is Control and child.is_visible_in_tree():
			if child is Button or child is Label:
				check(child.size.x + 1 >= child.get_minimum_size().x, "text width " + str(child.get_path()))
				if child is Label and child.autowrap_mode != TextServer.AUTOWRAP_OFF:
					check(child.size.y + 1 >= child.get_minimum_size().y, "wrapped height " + child.text)
			if child is RichTextLabel:
				check(child.get_content_width() <= child.size.x + 1, "rich text wraps")
		validate_text(child)

func layout(panel, tag: String) -> void:
	main.ui.hide_tooltip(true)
	for toast in main.ui.toasts.get_children():
		toast.queue_free()
	panel.reposition()
	await frames(12)
	var bounds: Rect2 = panel.get_global_rect()
	check(Rect2(Vector2.ZERO, main.ui.root.size).grow(0.1).encloses(bounds), tag + " panel fits")
	check(bounds.encloses(panel.title_label.get_parent().get_child(1).get_global_rect()), tag + " close reachable")
	validate_text(panel)
	if panel.panel_name in ["character", "skills"]:
		check(bounds.encloses(panel.scroll.get_global_rect()) and panel.scroll.size.y >= 200, tag + " usable scroll area")
		check(panel.scroll.get_h_scroll_bar().max_value <= panel.scroll.size.x, tag + " no horizontal overflow")
	if panel.panel_name == "spec":
		if panel.chooser_scroll.visible:
			check(bounds.encloses(panel.chooser_scroll.get_global_rect()), tag + " chooser fits")
			check(panel.area.size.x <= panel.chooser_scroll.size.x, tag + " all choices fit width")
		else:
			check(bounds.encloses(panel.graph_frame.get_global_rect()) and bounds.encloses(panel.reset_btn.get_global_rect()), tag + " graph and reset fit")
			for node in panel.graph.spec.nodes:
				check(Rect2(Vector2.ZERO, panel.graph.size).encloses(Rect2(panel.graph._pos(node) - Vector2(22,22), Vector2(44,60))), tag + " graph node fits")
	evidence.append({"state": tag, "window": str(get_window().size), "panel": str(bounds)})
	if capture:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		check(img.get_size() == get_window().size, tag + " exact output")
		img.save_png(OUT + "/" + tag + ".png")

func confirm_choice(accept: bool) -> void:
	check(main.ui.confirm.visible, "confirmation owned by UI root")
	var choices := buttons(main.ui.confirm)
	for button in choices:
		if button.text == ("Confirm" if accept else "Cancel"):
			await click(button)
			return
	check(false, "confirmation button found")

func verify_skills(cls: String) -> void:
	var ch = Game.ch
	main.ui.toggle("skills")
	var panel = main.ui.panels.skills
	await frames()
	var slots: Array = ch.loadout.duplicate()
	var first: String = slots[0]
	var second: String = slots[1]
	await click(panel.slot_bar.get_child(1))
	check(panel.selected_slot == 1 and panel.slot_bar.get_child(1).sel, cls + " select hotbar input")
	var row := skill_row(panel, first)
	await reveal(panel.scroll, row)
	await click(row.get_child(0))
	check(ch.loadout[1] == first and ch.loadout[0] == second, cls + " assignment swaps via row input")
	await click(panel.slot_bar.get_child(1), MOUSE_BUTTON_RIGHT)
	check(ch.loadout[1] == "", cls + " right click clears")
	ch.loadout = slots.duplicate()
	Events.loadout_changed.emit()
	await frames()
	var original_events := InputMap.action_get_events("skill_3")
	InputMap.action_erase_events("skill_3")
	var remap := InputEventKey.new()
	remap.physical_keycode = KEY_H
	InputMap.action_add_event("skill_3", remap)
	panel.refresh()
	await frames()
	check(panel.slot_bar.get_child(2).key_text == "H", "real remapped key in Skills")
	InputMap.action_erase_events("skill_3")
	for event in original_events:
		InputMap.action_add_event("skill_3", event)
	# A compatible owned rune must pass through the existing context callback.
	var rid := ""
	for id in Data.skill_runes:
		if ch.rune_fits(id, first) == "":
			rid = id
			break
	check(rid != "", cls + " compatible rune fixture")
	ch.runes[rid] = 2
	panel.refresh()
	await frames()
	row = skill_row(panel, first)
	await reveal(panel.scroll, row)
	await click(buttons(row)[0])
	check(main.ui.context.visible, cls + " rune menu input")
	await click(buttons(main.ui.context)[0])
	check(ch.skill_runes.get(first, []).has(rid) and ch.runes.get(rid) == 1, cls + " socket consumes one rune")
	row = skill_row(panel, first)
	await reveal(panel.scroll, row)
	await click(buttons(row)[0])
	check(not ch.skill_runes.get(first, []).has(rid) and ch.runes.get(rid) == 2, cls + " unsocket returns rune")
	# Existing nearby-enemy guard rejects assignment, socket menu and unsocket.
	var enemy := NearbyEnemy.new()
	enemy.position = Game.level.player.global_position
	Game.level.enemies.append(enemy)
	Game.level.allow_combat = true
	var before := JSON.stringify(ch.to_dict())
	panel.assign(0, "")
	panel._socket_menu(first)
	panel._unsocket(first, 0)
	check(before == JSON.stringify(ch.to_dict()) and panel.can_change() != "", cls + " nearby enemy restriction preserved")
	Game.level.enemies.erase(enemy)
	enemy.free()
	Game.level.allow_combat = false
	panel.refresh()
	await frames()
	await layout(panel, "skills_" + cls + "_1280x720")
	panel.scroll.scroll_vertical = 0
	for i in 16:
		await click_at(panel.scroll.get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_DOWN)
	check(panel.scroll.scroll_vertical > 0, cls + " skill list wheel input")
	await reveal(panel.scroll, panel.list.get_child(panel.list.get_child_count() - 1))
	check(panel.scroll.get_global_rect().end.y + 1 >= panel.list.get_child(panel.list.get_child_count() - 1).get_global_rect().end.y, cls + " final skill reachable")
	var selection: int = panel.selected_slot
	main.ui.close("skills")
	main.ui.open("skills")
	await frames()
	check(panel.selected_slot == selection and ch.loadout == slots, cls + " reopen preserves selection/loadout")
	# Level-one presentation keeps locked skills and rune sockets explicit.
	ch.level = 1
	ch.unlocked_skills.clear()
	ch.refresh_unlocks(false)
	panel.refresh()
	await frames()
	for sk in Data.skills_for_class(cls):
		if not ch.unlocked_skills.has(sk.id):
			row = skill_row(panel, sk.id)
			await reveal(panel.scroll, row)
			var locked_before: Array = ch.loadout.duplicate()
			await click(row.get_child(0))
			check(ch.loadout == locked_before and row.get_child(0).dim, cls + " locked skill input refused")
			break
	row = skill_row(panel, first)
	check(buttons(row)[1].disabled and buttons(row)[2].disabled, cls + " level-gated rune sockets")
	if cls == "mage":
		panel.scroll.scroll_vertical = 0
		await layout(panel, "skills_locked_1280x720")
	ch.level = 60
	ch.refresh_unlocks(false)
	panel.refresh()
	main.ui.close_all()

func verify_specs(cls: String) -> void:
	var ch = Game.ch
	main.ui.toggle("spec")
	var panel = main.ui.panels.spec
	await frames()
	await layout(panel, "choices_" + cls + "_1280x720")
	var specs: Array = Data.specs_for_class(cls)
	check(panel.area.get_child_count() == specs.size(), cls + " every specialisation offered")
	for sp in specs:
		ch.spec_id = ""
		ch.spec_nodes.clear()
		panel.refresh()
		await frames()
		var choose: Button
		for button in buttons(panel.area):
			if button.tooltip_text == "Choose " + sp.name:
				choose = button
		await reveal(panel.chooser_scroll, choose)
		await click(choose)
		await confirm_choice(false)
		check(ch.spec_id == "", sp.id + " choice cancellation")
		await click(choose)
		await confirm_choice(true)
		check(ch.spec_id == sp.id and panel.graph_frame.visible, sp.id + " choose input")
		await frames()
		for node in sp.nodes:
			if ch.can_alloc_spec(node.id) == "":
				await click_at(panel.graph.global_position + panel.graph._pos(node))
				check(ch.spec_nodes.has(node.id), sp.id + " graph allocation input " + node.id)
		var allocation_before: Array = ch.spec_nodes.duplicate()
		await click_at(panel.graph.global_position + panel.graph._pos(sp.nodes[0]))
		check(ch.spec_nodes == allocation_before, sp.id + " duplicate allocation refused")
		var nodes: Array = ch.spec_nodes.duplicate()
		var gold: int = ch.gold
		await click(panel.reset_btn)
		await confirm_choice(false)
		check(ch.spec_nodes == nodes and ch.gold == gold, sp.id + " reset cancellation")
		if sp == specs[0]:
			ch.gold = 0
			await click(panel.reset_btn)
			await confirm_choice(true)
			check(ch.spec_id == sp.id and ch.spec_nodes == nodes and ch.gold == 0, sp.id + " unaffordable reset refused")
			ch.gold = gold
		var cost: int = ch.spec_reset_cost()
		await click(panel.reset_btn)
		await confirm_choice(true)
		check(ch.spec_id == "" and ch.spec_nodes.is_empty() and ch.gold == gold - cost, sp.id + " reset refunds points at existing cost")
	# Locked choices still show every archetype, with disabled native actions.
	ch.level = 1
	panel.refresh()
	await frames()
	for button in buttons(panel.area):
		check(button.disabled, cls + " locked Choose disabled")
	if cls == "mage":
		await layout(panel, "choices_locked_1280x720")
	ch.level = 60
	panel.refresh()
	main.ui.close_all()

func _ready() -> void:
	Game.testing = true
	capture = OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name() != "headless"
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		get_window().borderless = true
	get_window().size = Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute(OUT)
	main = load("res://scripts/main.gd").new()
	add_child(main)
	await frames(3)
	for cls in ["warrior", "ranger", "mage"]:
		Game.new_character(cls)
		var ch = Game.ch
		ch.level = 60
		ch.gold = 500000
		ch.char_name = "A long character name for the cabinet heading"
		ch.refresh_unlocks(false)
		ch.recalc()
		main.start_game()
		await frames(10)
		Game.level.process_mode = Node.PROCESS_MODE_DISABLED
		await verify_skills(cls)
		await verify_specs(cls)
	var ch = Game.ch
	var character = main.ui.panels.character
	var skills = main.ui.panels.skills
	var spec = main.ui.panels.spec
	check(character.theme != main.ui.root.theme and skills.theme != null and spec.theme != null and main.ui.panels.options.theme == null, "scoped opt-in themes")
	for id in Data.skill_runes:
		ch.runes[id] = 999
	for dims in [Vector2i(1280,720), Vector2i(1920,1080), Vector2i(2560,1440), Vector2i(1920,1200), Vector2i(2560,1080)]:
		get_window().size = dims
		await frames(12)
		for name in ["character", "skills", "spec"]:
			main.ui.close_all()
			main.ui.open(name)
			var panel = main.ui.panels[name]
			await frames()
			await layout(panel, "%s_%dx%d" % [name, dims.x, dims.y])
			var before := JSON.stringify(ch.to_dict())
			var rng_state = Combat.rng.state
			for i in 4:
				panel.refresh()
				panel.reposition()
			check(before == JSON.stringify(ch.to_dict()) and rng_state == Combat.rng.state, name + " presentation preserves serialization and RNG")
			await click(panel.title_label.get_parent().get_child(1))
			check(not main.ui.is_open(name), name + " close input")
		main.ui.open("spec")
		ch.choose_spec(Data.specs_for_class("mage")[0].id)
		await frames()
		await layout(spec, "graph_%dx%d" % [dims.x, dims.y])
		ch.spec_id = ""
		ch.spec_nodes.clear()
		ch.recalc()
		main.ui.close_all()
	get_window().size = Vector2i(1280,720)
	await frames(12)
	main.ui.open("character")
	await frames()
	var row = character.list.get_child(1)
	var motion := InputEventMouseMotion.new()
	motion.position = row.get_global_rect().get_center()
	get_viewport().push_input(motion, true)
	await frames()
	check(main.ui.tooltip.visible and main.ui.tooltip_text.text.contains("Class base"), "stat row source tooltip input")
	for i in 30:
		await click_at(character.scroll.get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_DOWN)
	check(character.scroll.scroll_vertical > 0, "character wheel input")
	await reveal(character.scroll, character.list.get_child(character.list.get_child_count() - 1))
	check(character.list.get_child(character.list.get_child_count() - 1).get_global_rect().end.y <= character.scroll.get_global_rect().end.y + 1, "last character row reachable")
	main.ui.close_all()
	main.ui.open("skills")
	skills.rune_scroll.scroll_vertical = 0
	await frames()
	for i in 12:
		await click_at(skills.rune_scroll.get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_DOWN)
	check(skills.rune_scroll.scroll_vertical > 0, "large rune pouch scrolls independently")
	var focus_button: Button = buttons(skills.list)[0]
	focus_button.grab_focus()
	check(focus_button.has_focus() and focus_button.get_theme_stylebox("focus") is StyleBoxFlat, "native action keyboard focus")
	var key := InputEventKey.new()
	key.keycode = KEY_ENTER
	key.pressed = true
	get_viewport().push_input(key, true)
	key = key.duplicate()
	key.pressed = false
	get_viewport().push_input(key, true)
	await frames()
	check(main.ui.context.visible, "native focused rune action keyboard activation")
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
	print("Character chrome: %d passed, %d failed" % [checks - failures, failures])
	get_tree().quit(1 if failures else 0)
