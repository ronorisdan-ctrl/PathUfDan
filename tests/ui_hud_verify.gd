extends Node

const Dock = preload("res://scripts/ui/components/combat_dock.gd")
const HUDStyle = preload("res://scripts/ui/components/hud_style.gd")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("HUD: " + message)

func _ready() -> void:
	Game.testing = true
	get_window().size = Vector2i(1280, 720)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		get_window().borderless = true
		get_window().position = Vector2i.ZERO
		await get_tree().process_frame
	var dock = Dock.new()
	add_child(dock)
	for resolution in [Vector2(1280, 720), Vector2(1920, 1080), Vector2(2560, 1440), Vector2(1152, 720), Vector2(1707, 720), Vector2(800, 720)]:
		dock.fit_to(resolution)
		check(Rect2(Vector2.ZERO, resolution).encloses(dock.get_global_rect()), "dock fits " + str(resolution))
	check(dock.mouse_filter == Control.MOUSE_FILTER_IGNORE, "combat click through")
	check(HUDStyle.key_label("skill_1") == "LMB" and HUDStyle.key_label("skill_3") == "Q", "real action mappings")
	for case in [[74.0, 100.0, 0.74], [-1.0, 100.0, 0.0], [200.0, 100.0, 1.0], [5.0, 0.0, 0.0], [NAN, INF, 0.0]]:
		dock.life.present(case[0], case[1], true)
		check(is_equal_approx(dock.life.ratio, case[2]), "finite bounded resource")
	dock.life.present(100, 100, true)
	dock.life.present(20, 100)
	dock.life.advance(0.1)
	check(dock.life.displayed > 0.2 and dock.life.displayed < 1 and dock.life.delayed > dock.life.displayed, "damage smoothing and delayed damage")
	dock.life.present(80, 100)
	for i in 120: dock.life.advance(1.0 / 60)
	check(absf(dock.life.displayed - 0.8) < 0.001 and dock.life.readout() == "80 / 100", "interrupted damage recovers to latest value")
	dock.mana.present(0, 0, true)
	check(dock.mana.readout() == "0 / 0" and dock.mana.displayed == 0, "zero mana maximum")
	var slot = dock.slots[0]
	var skill := {"id": "test", "cooldown": 2.0}
	slot.present(skill, 2, 2, "On cooldown", false, "skill_1")
	slot.present(skill, 0, 2, "", true, "skill_1")
	check(slot.completion > 0 and slot.selected, "cooldown completion and selected state")
	slot.present(skill, 0, 2, "Not enough mana", false, "skill_1")
	check(slot.reason == "Not enough mana" and not slot.selected, "disabled resource state")
	dock.trigger_skill("test")
	check(slot.activation > 0, "skill activation feedback")
	var original_events := InputMap.action_get_events("skill_3")
	InputMap.action_erase_events("skill_3")
	var binding := InputEventKey.new()
	binding.physical_keycode = KEY_H
	InputMap.action_add_event("skill_3", binding)
	check(HUDStyle.key_label("skill_3") == "H", "labels follow remapped input")
	InputMap.action_erase_events("skill_3")
	for event in original_events: InputMap.action_add_event("skill_3", event)
	dock.free()
	await verify_live()
	if OS.get_cmdline_user_args().has("--capture"):
		await capture_live()
	# Godot 4.0's dummy audio driver can retain active WAV playback at fast exit.
	for audio_player in Sfx.players:
		audio_player.stop()
		audio_player.stream = null
	await get_tree().create_timer(0.1).timeout
	print("HUD: %d passed, %d failed" % [checks - failures, failures])
	get_tree().call_deferred("quit", 1 if failures else 0)

func verify_live() -> void:
	var main = load("res://scripts/main.gd").new()
	add_child(main)
	for cls in ["warrior", "ranger", "mage"]:
		Game.new_character(cls)
		main.start_game()
		for i in 3: await get_tree().process_frame
		var p = Game.level.player
		p.set_physics_process(false)
		var hud = main.ui.hud
		p.life = p.max_life * 0.4
		p.mana = Game.ch.final.get("max_mana", 0) * 0.5
		hud._process(1.0 / 60)
		check(hud.dock.life.current == p.life and hud.dock.mana.current == p.mana, cls + " live resource binding")
		check(hud.slot_rects.size() == 7 and hud.flask_rects.size() == 2, cls + " preserves all actions")
		check(hud.dock.slots[0].skill == p.skill_in_slot(0), cls + " resolved skill icons/data")
		var original_id: String = Game.ch.loadout[0]
		main.ui.panels["skills"].assign(0, "")
		hud._process(0)
		check(hud.dock.slots[0].skill.is_empty(), cls + " reassignment updates without recreating HUD")
		main.ui.panels["skills"].assign(0, original_id)
		p.mana = Game.ch.final.get("max_mana", 0)
		p.life = p.max_life
		hud._process(0)
		check(p.try_use_slot(0), cls + " existing activation works")
		check(hud.dock.slots[0].activation > 0, cls + " successful use emits visual feedback")
		p.buffs = [{"id": "test_buff", "t": 5.0, "mods": []}]
		p.statuses = {"chill": {"t": 2.0}}
		hud._process(0)
		check(hud.dock.statuses.entries.size() == 2 and hud.dock.statuses.entries[1]["harmful"], cls + " existing buffs/debuffs")
		check(hud.dock.statuses.description_at(Vector2(5, 5)).contains("5.0s remaining"), cls + " status tooltip duration")
		p.buffs.clear()
		p.statuses.clear()
		Game.ch.add_xp(Game.ch.xp_to_next() + 5)
		hud._process(0.1)
		check(hud.dock.progression.level == Game.ch.level and hud.dock.progression.celebration > 0 and hud.dock.progression.experience_text.begins_with("5 /"), cls + " actual XP rollover and level feedback")
		hud._process(0)
		check(hud.dock.statuses.entries.is_empty(), cls + " expired status removal")
		p.life = p.max_life * 0.1
		p.mana = 0
		p.use_flask(0)
		p.use_flask(1)
		hud._process(0)
		check(hud.dock.flasks[0].charges == Game.ch.flask_charges[0] and hud.dock.flasks[0].activation > 0 and hud.dock.life.current == p.life, cls + " flask use and health recovery")
		check(hud.dock.mana.current == p.mana, cls + " mana flask recovery")
		p.start_dodge()
		hud._process(0)
		check(hud.dock.evade.cooldown == p.dodge_cd and hud.dock.evade.selected, cls + " actual dodge cooldown")
		p.dodge_t = 0
		p.dodge_cd = 0
		p.busy = 0
		p.cooldowns.clear()
		p.mana = Game.ch.final.get("max_mana", 0)
		hud._process(0)
		await verify_input(main, p)
		p.busy = 0
		p.cooldowns.clear()
		p.mana = Game.ch.final.get("max_mana", 0)
		if float(p.skill_in_slot(1).get("cooldown", 0)) > 0:
			check(p.try_use_slot(1), cls + " cooldown skill activates")
			hud._process(0)
			var skill_id: String = p.skill_in_slot(1)["id"]
			var remaining: float = p.cooldowns[skill_id]
			check(hud.dock.slots[1].cooldown == remaining, cls + " actual skill cooldown binding")
			p._tick_timers(remaining + 0.01)
			hud._process(0)
			check(hud.dock.slots[1].cooldown == 0 and hud.dock.slots[1].completion > 0, cls + " actual cooldown completion")
		var before: float = hud.dock.life.displayed
		get_tree().paused = true
		p.life = 0
		hud._process(0.2)
		check(hud.dock.life.displayed == before and hud.dock.life.current == 0, cls + " pause freezes animation with exact readout")
		get_tree().paused = false
		p.alive = false
		hud._process(0.2)
		check(hud.dock.slots[0].reason == "Unavailable" and hud.dock.life.current == 0, cls + " death state")
		p.alive = true
		p.life = p.max_life
		var combat_rng = Combat.rng.state
		var data_before: String = JSON.stringify(Game.ch.to_dict())
		var began := Time.get_ticks_usec()
		for i in 120: hud._process(1.0 / 60)
		var elapsed := (Time.get_ticks_usec() - began) / 120.0
		check(Combat.rng.state == combat_rng and JSON.stringify(Game.ch.to_dict()) == data_before, cls + " presentation does not mutate character or combat RNG")
		print("HUD update average (%s): %.0f us" % [cls, elapsed])
		hud.big_map = true
		var map_rect: Rect2 = hud.minimap_rect(hud.size)
		check(map_rect.end.y < hud.dock.position.y and Rect2(Vector2.ZERO, hud.size).encloses(map_rect.grow(5)), cls + " expanded map clear of combat HUD")
		hud.big_map = false
		p.release_all()
		main.show_main_menu()
		for i in 2: await get_tree().process_frame
	main.queue_free()
	Game.ch = null
	for i in 4: await get_tree().process_frame

func verify_input(main, player) -> void:
	var hud = main.ui.hud
	var motion := InputEventMouseMotion.new()
	motion.position = hud.slot_rects[0].get_center()
	if DisplayServer.get_name() != "headless":
		get_viewport().warp_mouse(motion.position)
	get_viewport().push_input(motion, true)
	await get_tree().process_frame
	hud._update_hover()
	if DisplayServer.get_name() != "headless":
		check(hud.hover_slot == 0 and main.ui.tooltip.visible and main.ui.tooltip_text.text.contains(player.skill_in_slot(0)["name"]), "actual skill hover tooltip")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = motion.position
	press.pressed = true
	var casts := Combat.cast_serial
	get_viewport().push_input(press, true)
	if not get_viewport().is_input_handled(): get_viewport().push_unhandled_input(press, true)
	await get_tree().process_frame
	check(Combat.cast_serial > casts and player.held[0], "combat mouse input passes through HUD")
	press = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = motion.position
	get_viewport().push_input(press, true)
	if not get_viewport().is_input_handled(): get_viewport().push_unhandled_input(press, true)
	await get_tree().process_frame
	check(not player.held[0], "combat mouse release passes through HUD")
	main.ui.open("skills")
	main.ui.show_tooltip("Panel tooltip ownership")
	hud._update_hover()
	check(hud.hover_slot == -1 and main.ui.tooltip_text.text == "Panel tooltip ownership" and main.ui.tooltip.visible, "panel hover owns its tooltip")
	main.ui.close_all()
	player.busy = 0
	player.cooldowns.clear()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_SPACE
	key.pressed = true
	get_viewport().push_input(key, true)
	if not get_viewport().is_input_handled(): get_viewport().push_unhandled_input(key, true)
	await get_tree().process_frame
	check(player.dodge_cd > 0, "existing keyboard dodge input")
	key = InputEventKey.new()
	key.physical_keycode = KEY_SPACE
	get_viewport().push_input(key, true)
	if not get_viewport().is_input_handled(): get_viewport().push_unhandled_input(key, true)
	player.dodge_t = 0
	player.dodge_cd = 0
	motion = InputEventMouseMotion.new()
	motion.position = Vector2(640, 300)
	if DisplayServer.get_name() != "headless": get_viewport().warp_mouse(motion.position)
	get_viewport().push_input(motion, true)
	hud._update_hover()

func capture_live() -> void:
	var main = load("res://scripts/main.gd").new()
	add_child(main)
	Game.new_character("mage")
	main.start_game()
	main.enter_dungeon("forgotten_depths", 777)
	for i in 8: await get_tree().process_frame
	Game.level.process_mode = Node.PROCESS_MODE_DISABLED
	var hud = main.ui.hud
	DirAccess.make_dir_recursive_absolute("res://tests/screens_out_hud")
	for resolution in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(1920, 1200), Vector2i(2560, 1080), Vector2i(1024, 768)]:
		get_window().size = resolution
		for i in 5: await get_tree().process_frame
		check(get_viewport_rect_safe().encloses(hud.dock.get_global_rect()), "rendered dock fit " + str(resolution))
		for slot in hud.dock.slots:
			check(get_viewport_rect_safe().encloses(slot.get_global_rect()), "rendered slot fit " + str(resolution))
		await RenderingServer.frame_post_draw
		var shot := get_viewport().get_texture().get_image()
		check(shot.get_size() == resolution, "actual render resolution " + str(resolution))
		check(shot.save_png("res://tests/screens_out_hud/after_%dx%d.png" % [resolution.x, resolution.y]) == OK, "capture " + str(resolution))
		var hovered_frames := 0
		for attempt in 30:
			get_viewport().warp_mouse(hud.slot_rects[0].get_center())
			await get_tree().process_frame
			hud._update_hover()
			hovered_frames = hovered_frames + 1 if hud.hover_slot == 0 else 0
			if hovered_frames >= 4: break
		check(hud.hover_slot == 0 and main.ui.tooltip.visible, "resized pointer hit test " + str(resolution))
		check(get_viewport_rect_safe().encloses(main.ui.tooltip.get_global_rect()), "tooltip fit " + str(resolution))
		if resolution == Vector2i(1920, 1080):
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://tests/screens_out_hud/skill_tooltip_1920x1080.png")
		get_viewport().warp_mouse(Vector2(640, 300))
		main.ui.hide_tooltip()
		hud._hover_text = ""
	await capture_states(main)
	main.show_main_menu()
	main.queue_free()
	Game.ch = null
	await get_tree().process_frame

func capture_states(main) -> void:
	get_window().size = Vector2i(1920, 1080)
	var p = Game.level.player
	var hud = main.ui.hud
	Game.ch.level = 30
	Game.ch.refresh_unlocks(false)
	for i in mini(7, Game.ch.unlocked_skills.size()):
		Game.ch.loadout[i] = Game.ch.unlocked_skills[i]
	Game.ch.recalc()
	p.refresh_stats()
	p.life = p.max_life * 0.2
	p.mana = Game.ch.final.get("max_mana", 0) * 0.45
	Game.ch.xp = int(Game.ch.xp_to_next() * 0.42)
	p.add_status("chill", 4.2, {})
	p.add_status("ignite", 2.7, {})
	p.try_use_slot(1)
	for i in 5: await get_tree().process_frame
	p.cam.force_update_scroll()
	for i in 20: hud._process(0.1)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/screens_out_hud/combat_states_1920x1080.png")
	hud.big_map = true
	for i in 3: await get_tree().process_frame
	p.cam.force_update_scroll()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/screens_out_hud/expanded_map_1920x1080.png")
	hud.big_map = false
	# Show the real dungeon boss/poise API, without running a boss simulation.
	for room in Game.level.rooms:
		if room["kind"] == "boss":
			Game.level._spawn_boss(room)
			break
	for i in 3: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/screens_out_hud/boss_1920x1080.png")

func get_viewport_rect_safe() -> Rect2:
	return get_viewport().get_visible_rect()
