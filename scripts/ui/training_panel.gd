extends "res://scripts/ui/base_panel.gd"
## Training Grounds: Drillmaster Rook spawns DPS test dummies. Tabs: Setup (choose the test and
## spawn), Result (the latest result in full). Maths in training_rules.gd, session in TrainingLog,
## the dummies are spawned by the hub (Game.level.training_spawn). The History tab arrives later.

const TrainingRules = preload("res://scripts/core/training_rules.gd")

var tab := "setup"
var tab_btns := {}
var setup_box: VBoxContainer
var result_box: VBoxContainer
var result_label: RichTextLabel
var note_label: Label
var msg_label: Label
var spacing_row: Control
var choice_btns := {}     # option key -> {value: Button}
var spawn_btn: Button
var reset_btn: Button
var remove_btn: Button

func _init() -> void:
	place = "left"
	build("Drillmaster Rook", Vector2(500, 470))
	body.add_child(UIKit.label("\"Hit the dummy. The clock starts on your first blow.\"", 12, UIKit.MUTED))
	var tabs := HBoxContainer.new()
	body.add_child(tabs)
	for t in [["setup", "Setup"], ["result", "Result"]]:
		var b := UIKit.button(t[1], _show_tab.bind(t[0]), 90)
		tabs.add_child(b)
		tab_btns[t[0]] = b
	body.add_child(HSeparator.new())
	# ---- Setup tab
	setup_box = VBoxContainer.new()
	setup_box.add_theme_constant_override("separation", 8)
	body.add_child(setup_box)
	var cfg: Dictionary = Data.training_cfg
	var lab: Dictionary = cfg.get("labels", {})
	var type_choices := []
	for k in ["single", "aoe"]:
		type_choices.append([k, str(lab.get("types", {}).get(k, k))])
	_choice_row("Test type", "type", type_choices)
	var dur_choices := []
	for d in cfg.get("durations", [10, 30]):
		dur_choices.append([int(d), "%d s" % int(d)])
	_choice_row("Duration", "duration", dur_choices)
	var cnt_choices := []
	for k in ["all", "player"]:
		cnt_choices.append([k, str(lab.get("counting", {}).get(k, k))])
	_choice_row("Counting", "counting", cnt_choices)
	var prof_choices := []
	for k in cfg.get("profiles", {}):
		prof_choices.append([k, str(cfg["profiles"][k].get("label", k))])
	_choice_row("Defence profile", "profile", prof_choices)
	spacing_row = _choice_row("Cluster spacing", "spacing", [["tight", "Tight"], ["spread", "Spread"]])
	var actions := HBoxContainer.new()
	spawn_btn = UIKit.button("Spawn", _spawn, 90)
	reset_btn = UIKit.button("Reset", _reset, 90)
	remove_btn = UIKit.button("Remove", _remove, 90)
	actions.add_child(spawn_btn)
	actions.add_child(reset_btn)
	actions.add_child(remove_btn)
	setup_box.add_child(actions)
	note_label = UIKit.label("", 12, UIKit.MUTED)
	note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_label.custom_minimum_size = Vector2(470, 0)
	setup_box.add_child(note_label)
	msg_label = UIKit.label("", 12, UIKit.GOLD)
	msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_label.custom_minimum_size = Vector2(470, 0)
	setup_box.add_child(msg_label)
	# ---- Result tab
	result_box = VBoxContainer.new()
	body.add_child(result_box)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(470, 340)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	result_box.add_child(sc)
	result_label = UIKit.rich("", 450)
	sc.add_child(result_label)
	TrainingLog.result_ready.connect(func(_r): refresh())

func _choice_row(title: String, key: String, choices: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := UIKit.label(title, 13, UIKit.MUTED)
	l.custom_minimum_size = Vector2(120, 0)
	row.add_child(l)
	var grp := ButtonGroup.new()
	choice_btns[key] = {}
	for c in choices:
		var b := Button.new()
		b.text = str(c[1])
		b.toggle_mode = true
		b.button_group = grp
		b.pressed.connect(_pick.bind(key, c[0]))
		b.pressed.connect(func(): Sfx.play("ui", 0.0))
		row.add_child(b)
		choice_btns[key][c[0]] = b
	setup_box.add_child(row)
	return row

func _pick(key: String, value) -> void:
	TrainingLog.set_option(key, value)
	refresh()

func _show_tab(t: String) -> void:
	tab = t
	refresh()

func on_open() -> void:
	msg_label.text = ""
	refresh()

static func hub():
	var lv = Game.level
	if lv != null and is_instance_valid(lv) and lv.has_method("training_spawn"):
		return lv
	return null

func refresh() -> void:
	if not visible:
		return
	setup_box.visible = tab == "setup"
	result_box.visible = tab == "result"
	for t in tab_btns:
		tab_btns[t].disabled = t == tab
	var s: Dictionary = TrainingLog.settings
	for key in choice_btns:
		for v in choice_btns[key]:
			choice_btns[key][v].button_pressed = (s.get(key) == v)
	spacing_row.visible = s.get("type", "single") == "aoe"
	var has_dummies := TrainingLog.has_run()
	reset_btn.disabled = not has_dummies
	remove_btn.disabled = not has_dummies
	note_label.text = ("Changing an option applies to the next Spawn." if has_dummies else "Pick a test, then Spawn. Hit a dummy to start the timer.")
	if not TrainingLog.available():
		note_label.text = "Training is switched off while the game is under test."
	_refresh_result()
	reposition()

func _refresh_result() -> void:
	var cfg: Dictionary = Data.training_cfg
	if TrainingLog.is_running():
		var left := float(TrainingLog.run["duration"]) - float(TrainingLog.run["elapsed"])
		result_label.text = "[color=#e8c050]Test running: %.1f s left.[/color]\n[color=#8a8494]The result appears here and above the dummy when the timer ends.[/color]" % maxf(0.0, left)
		return
	var res: Dictionary = TrainingLog.last_result
	var delta := {}
	if not res.is_empty():
		delta = TrainingLog.delta_for(res)
	result_label.text = TrainingRules.result_text(res, cfg, delta)

func _spawn() -> void:
	var lv = hub()
	if lv == null:
		msg_label.text = "Dummies can only be spawned in the hub."
		return
	var why: String = lv.training_spawn()
	msg_label.text = why if why != "" else "Dummies spawned. Hit one to start the timer."
	if why != "":
		ui.toast(why, UIKit.BAD)
	refresh()

func _reset() -> void:
	var lv = hub()
	if lv != null:
		lv.training_reset()
		msg_label.text = "Reset. The dummies are idle again."
	refresh()

func _remove() -> void:
	var lv = hub()
	if lv != null:
		lv.training_remove()
		msg_label.text = "Dummies removed."
	refresh()
