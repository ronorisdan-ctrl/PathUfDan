extends Control
## Isolated Phase 0 review harness. No character, world, fixture actions or saves.

const Meter = preload("res://scenes/ui/components/resource_meter.tscn")
var meter
var sample_button: Button
var sample := 0
var failures := 0
var checks := 0

func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	get_window().size = Vector2i(1280, 720)
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Theme is explicit because CanvasLayer interrupts Control inheritance.
	center.theme = theme
	layer.add_child(center)
	var stack := VBoxContainer.new()
	stack.custom_minimum_size.x = 520
	stack.add_theme_constant_override("separation", 22)
	center.add_child(stack)
	var title := Label.new()
	title.text = "The Dying Canvas"
	title.theme_type_variation = &"Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "PHASE 0  /  HUD MATERIAL STUDY"
	subtitle.theme_type_variation = &"Muted"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(subtitle)
	stack.add_child(HSeparator.new())
	meter = Meter.instantiate()
	stack.add_child(meter)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	stack.add_child(row)
	sample_button = Button.new()
	sample_button.text = "Cycle sample"
	sample_button.tooltip_text = "Life, depleted life, empty life, full life, mana"
	sample_button.pressed.connect(_cycle)
	row.add_child(sample_button)
	var disabled_button := Button.new()
	disabled_button.text = "Preview only"
	disabled_button.disabled = true
	row.add_child(disabled_button)
	var note := Label.new()
	note.text = "Tab to focus / Enter to cycle / Hover for tooltip\nTemporary native materials and fonts"
	note.theme_type_variation = &"Muted"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(note)
	meter.present(740, 1000)
	if OS.get_cmdline_user_args().has("--verify"):
		await _verify()
		get_tree().quit(1 if failures else 0)

func _cycle() -> void:
	sample = (sample + 1) % 5
	if sample == 4:
		meter.present(65, 120, "Mana", true)
	else:
		meter.present([740, 120, 0, 1000][sample], 1000)

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("Phase 0: " + message)

func _verify() -> void:
	var original_character = Game.ch
	var original_level = Game.level
	var original_rng = Combat.rng.state
	for i in 3:
		await get_tree().process_frame
	for case in [[740.0, 1000.0, 74.0, "740 / 1000"], [-2.0, 1000.0, 0.0, "0 / 1000"], [1500.0, 1000.0, 100.0, "1000 / 1000"], [5.0, 0.0, 0.0, "0 / 0"], [5.0, -1.0, 0.0, "0 / 0"], [NAN, INF, 0.0, "0 / 0"]]:
		meter.present(case[0], case[1])
		_check(is_equal_approx(meter.bar.value, case[2]) and meter.readout.text == case[3], "bounded resource presentation")
	sample_button.grab_focus()
	await get_tree().process_frame
	var event := InputEventKey.new()
	event.keycode = KEY_ENTER
	event.pressed = true
	get_viewport().push_input(event)
	await get_tree().process_frame
	event = InputEventKey.new()
	event.keycode = KEY_ENTER
	get_viewport().push_input(event)
	await get_tree().process_frame
	_check(sample == 1 and meter.bar.value == 12.0, "keyboard activation cycles sample")
	for i in 3:
		sample_button.pressed.emit()
	_check(meter.bar.theme_type_variation == &"ManaMeter" and meter.caption.text == "MANA", "shared component accepts mana presentation")
	_check(meter.tooltip_text == "Mana: 65 / 120", "tooltip matches readout")
	meter.present(740, 1000)
	for resolution in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(1920, 1200), Vector2i(2560, 1080)]:
		get_window().size = resolution
		for i in 4:
			await get_tree().process_frame
		var visible_rect := get_viewport_rect()
		_check(visible_rect.encloses(meter.get_global_rect()), "meter fits at " + str(resolution))
		_check(meter.size.x >= 320 and meter.size.y >= 96, "minimum size at " + str(resolution))
		_check(meter.readout.size.x >= meter.readout.get_minimum_size().x, "readout fits at " + str(resolution))
		if OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute("res://tests/screens_out_phase0")
			var path := "res://tests/screens_out_phase0/meter_%dx%d.png" % [resolution.x, resolution.y]
			_check(get_viewport().get_texture().get_image().save_png(path) == OK, "capture " + path)
	_check(Game.ch == original_character and Game.level == original_level and Combat.rng.state == original_rng, "character/world/combat RNG isolation")
	print("Phase 0 UI: %d passed, %d failed" % [checks - failures, failures])
