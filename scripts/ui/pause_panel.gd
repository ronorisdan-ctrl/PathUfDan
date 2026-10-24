extends "res://scripts/ui/base_panel.gd"
## Pause menu and settings.

var vol: HSlider
var shake: HSlider
var fs: CheckBox
var hs: CheckBox
var saved: Label
var slot_pick: OptionButton

func _init() -> void:
	place = "center"
	build("Paused", Vector2(380, 510))
	body.add_child(UIKit.button("Resume", func(): ui.close("pause")))
	body.add_child(UIKit.button("Save Game", _save))
	var sa := HBoxContainer.new()
	slot_pick = OptionButton.new()
	slot_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sa.add_child(slot_pick)
	sa.add_child(UIKit.button("Save to slot", _save_to_selected))
	body.add_child(sa)
	saved = UIKit.label("", 12, UIKit.GOOD)
	body.add_child(saved)
	body.add_child(HSeparator.new())
	body.add_child(UIKit.label("Volume", 13))
	vol = HSlider.new()
	vol.min_value = 0
	vol.max_value = 1
	vol.step = 0.05
	vol.value_changed.connect(func(v):
		Game.settings["volume"] = v
		Game.apply_settings())
	body.add_child(vol)
	body.add_child(UIKit.label("Screen shake", 13))
	shake = HSlider.new()
	shake.min_value = 0
	shake.max_value = 1.5
	shake.step = 0.1
	shake.value_changed.connect(func(v): Game.settings["screen_shake"] = v)
	body.add_child(shake)
	hs = CheckBox.new()
	hs.text = "Hit-stop (impact freeze)"
	hs.toggled.connect(func(on): Game.settings["hit_stop"] = on)
	body.add_child(hs)
	fs = CheckBox.new()
	fs.text = "Fullscreen"
	fs.toggled.connect(func(on):
		Game.settings["fullscreen"] = on
		Game.apply_settings())
	body.add_child(fs)
	body.add_child(UIKit.button("Cycle loot filter (Z)", func(): ui.cycle_loot_filter()))
	body.add_child(HSeparator.new())
	body.add_child(UIKit.button("Save and return to Main Menu", _menu))
	body.add_child(UIKit.button("Save and Quit", _quit))

func on_open() -> void:
	vol.value = float(Game.settings.get("volume", 0.7))
	shake.value = float(Game.settings.get("screen_shake", 1.0))
	fs.button_pressed = bool(Game.settings.get("fullscreen", false))
	hs.button_pressed = bool(Game.settings.get("hit_stop", true))
	saved.text = ""
	_fill_slots()

func on_close() -> void:
	Game.save_settings()

func _fill_slots() -> void:
	slot_pick.clear()
	for i in range(1, Game.SLOT_COUNT + 1):
		var info: Dictionary = Game.slot_info(i)
		var t := "Slot %d: %s" % [i, info["summary"] if info["exists"] else "Empty"]
		if i == Game.current_slot:
			t += " (current)"
		slot_pick.add_item(t, i)
	slot_pick.select(Game.current_slot - 1)

func _save() -> void:
	saved.text = "Saved to slot %d." % Game.current_slot if Game.save_game() else "Could not save."

func _save_to_selected() -> void:
	var slot: int = slot_pick.get_selected_id()
	if slot == Game.current_slot or not Game.has_slot(slot):
		_do_save_to(slot)
		return
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = "Overwrite slot %d?\n%s" % [slot, Game.slot_info(slot)["summary"]]
	dlg.process_mode = Node.PROCESS_MODE_ALWAYS
	dlg.confirmed.connect(func():
		_do_save_to(slot)
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()

func _do_save_to(slot: int) -> void:
	saved.text = "Saved to slot %d." % slot if Game.save_game(slot) else "Could not save."
	_fill_slots()

func _menu() -> void:
	Game.save_game()
	Game.save_settings()
	ui.close_all()
	Game.main.show_main_menu()

func _quit() -> void:
	Game.save_game()
	Game.save_settings()
	get_tree().quit()
