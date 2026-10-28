extends Node
## Screenshots for item corruption: tooltips, Blacksmith readout, confirm dialog,
## 100% state, inventory markers and the dev tools. Needs a display.
##   godot --path . res://tests/screens_corruption.tscn -- <outdir>
## Without an argument the PNGs go to res://tests/screens_out_corruption.

const MainScript = preload("res://scripts/main.gd")
const R = preload("res://scripts/core/corruption_rules.gd")
var main = null
var outdir := "res://tests/screens_out_corruption"

func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func shot(tag: String) -> void:
	await frames(4)
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [outdir, tag])
	print("shot ", tag)

func tip(ui, it: Dictionary, tag: String, compare: bool = false) -> void:
	# The real tooltip follows the mouse and the HUD may hide it, so show it at a fixed
	# spot and take the picture straight away.
	ui.set_process(false)
	ui.item_tooltip(it, compare)
	ui.tooltip.position = Vector2(560, 120)
	if ui.tooltip2.visible:
		ui.tooltip2.position = Vector2(560 + ui.tooltip.size.x + 8, 120)
	await get_tree().process_frame
	ui.tooltip.visible = true
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [outdir, tag])
	print("shot ", tag)
	ui.hide_tooltip()
	ui.set_process(true)

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		outdir = args[0]
	DirAccess.make_dir_recursive_absolute(outdir)
	Game.testing = true
	SharedStash.path = "user://screens_shared_stash.json"
	main = MainScript.new()
	add_child(main)
	await frames(5)
	Game.new_character("warrior")
	var ch = Game.ch
	ch.gold = 5000
	for k in Data.materials:
		ch.materials[k] = 30
	var base: String = "rusty_sword" if Data.item_bases.has("rusty_sword") else Data.item_base_list[0]["id"]
	var levels := [0, 20, 40, 60, 80, 100]
	var items := []
	for i in levels.size():
		var it: Dictionary = Loot.roll_item_of(base, "rare", 14)
		it["uid"] = ch.take_uid()
		R.set_level(it, levels[i])
		items.append(it)
		ch.add_to_bag(it)
	var locked: Dictionary = Loot.roll_item_of(base, "epic", 14)
	locked["uid"] = ch.take_uid()
	R.set_level(locked, 100)
	ch.add_to_bag(locked)
	ch.set_item_locked(locked, true)
	main.start_game()
	await frames(20)
	var ui = main.ui
	# inventory with markers, tooltip at 40%
	ui.open("inventory")
	await frames(5)
	await tip(ui, items[2], "inventory_tooltip_40")
	await tip(ui, items[5], "inventory_tooltip_100")
	await tip(ui, items[0], "inventory_tooltip_0")
	await tip(ui, items[3], "inventory_tooltip_compare", true)
	ui.hide_tooltip()
	await shot("inventory_markers")
	# blacksmith at 40%
	ui.open_station("blacksmith")
	await frames(3)
	var bs = ui.panels["blacksmith"]
	bs.select(items[2])
	bs.op = "add"
	bs.refresh()
	await shot("blacksmith_40")
	bs.scroll.scroll_vertical = 100000
	await shot("blacksmith_40_buttons")
	# confirm dialog at 80% (warning)
	bs.select(items[4])
	bs.op = "reroll"
	bs.affix_index = 0
	bs.refresh()
	if Loot.craft_check("reroll", items[4], 0) == "":
		bs._craft()
		await shot("blacksmith_confirm_80")
		ui.confirm.visible = false
	# blacksmith at 100%
	bs.select(items[5])
	bs.op = "add"
	bs.refresh()
	await shot("blacksmith_100")
	bs.scroll.scroll_vertical = 100000
	await shot("blacksmith_100_buttons")
	ui.close("blacksmith")
	# dev panel
	Game.dev_in_tests = true
	Game.settings["dev_tools"] = true
	ui.open("dev")
	await frames(4)
	var dp = ui.panels["dev"]
	for i in dp.tabs.get_tab_count():
		if "Item" in dp.tabs.get_tab_title(i):
			dp.tabs.current_tab = i
	await shot("dev_items_tab")
	get_tree().quit(0)
