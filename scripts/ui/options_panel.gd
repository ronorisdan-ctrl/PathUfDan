extends "res://scripts/ui/base_panel.gd"
## Options, opened from the pause menu. Settings are saved when the panel closes.

const LOOT_PICKUP_MODES := [
	["keybind", "Keybind (F)"],
	["mouse", "Mouse Click"],
	["both", "Both"],
]

var loot_pick: OptionButton
var loot_hint: Label
var dev: CheckBox
var dev_btn: Button

func _init() -> void:
	place = "center"
	build("Options", Vector2(380, 330))
	body.add_child(UIKit.label("Loot Pickup", 13))
	loot_pick = OptionButton.new()
	loot_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in LOOT_PICKUP_MODES.size():
		loot_pick.add_item(LOOT_PICKUP_MODES[i][1], i)
	loot_pick.item_selected.connect(func(idx):
		Game.settings["loot_pickup"] = LOOT_PICKUP_MODES[idx][0]
		_update_hint())
	body.add_child(loot_pick)
	loot_hint = UIKit.label("", 12, UIKit.GOOD)
	loot_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(loot_hint)
	body.add_child(HSeparator.new())
	body.add_child(UIKit.button("Loot filter editor", func():
		ui.close("options")
		ui.open_filter_editor()))
	dev = CheckBox.new()
	dev.text = "Developer tools"
	dev.tooltip_text = "Testing cheats: F1 opens the Developer panel. Characters that use them are marked (dev)."
	dev.toggled.connect(func(on):
		if on != bool(Game.settings.get("dev_tools", false)):
			Dev.set_enabled(on)
		dev_btn.visible = Dev.enabled())
	body.add_child(dev)
	dev_btn = UIKit.button("Developer tools (F1)", func():
		ui.close("options")
		ui.open("dev"))
	dev_btn.tooltip_text = "Open the Developer panel"
	body.add_child(dev_btn)
	body.add_child(HSeparator.new())
	body.add_child(UIKit.button("Back", func():
		ui.close("options")
		ui.open("pause")))

func on_open() -> void:
	var mode := str(Game.settings.get("loot_pickup", "keybind"))
	for i in LOOT_PICKUP_MODES.size():
		if LOOT_PICKUP_MODES[i][0] == mode:
			loot_pick.select(i)
	_update_hint()
	dev.button_pressed = bool(Game.settings.get("dev_tools", false))
	dev_btn.visible = Dev.enabled()

func on_close() -> void:
	Game.save_settings()

func _update_hint() -> void:
	match str(Game.settings.get("loot_pickup", "keybind")):
		"mouse":
			loot_hint.text = "Click an item's nameplate to pick it up. F no longer picks up items."
		"both":
			loot_hint.text = "Click an item's nameplate or press F to pick it up."
		_:
			loot_hint.text = "Press F to pick up items. Clicking a nameplate does nothing."
