extends Node
## Screenshots for the stash tabs: personal stash, bought tab, shared stash, max tabs.
## Run with a display: godot --path . res://tests/screens_stash.tscn -- <outdir>

const MainScript = preload("res://scripts/main.gd")
var main = null
var outdir := "user://screens_stash"

func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func shot(tag: String) -> void:
	await frames(3)
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [outdir, tag])
	print("shot ", tag)

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
	ch.gold = 350
	var bases := []
	for b in Data.item_base_list:
		bases.append(b["id"])
	var rars := ["common", "uncommon", "rare", "epic", "legendary"]
	for i in 14:
		ch.stash[i] = Loot.make_item(bases[i % bases.size()], rars[i % rars.size()], 5 + i)
	main.start_game()
	await frames(20)
	main.ui.open_station("stash")
	await frames(5)
	await shot("stash_personal")
	var p = main.ui.panels["stash"]
	ch.gold = 1000
	p._do_buy()
	ch.stash[60] = Loot.make_item(bases[3], "epic", 20)
	Events.inventory_changed.emit()
	await shot("stash_tab2")
	p._set_mode("shared")
	for i in 6:
		SharedStash.slots[i] = Loot.make_item(bases[(i * 3) % bases.size()], rars[i % rars.size()], 10 + i)
	SharedStash.changed.emit()
	await shot("shared_stash")
	ch.gold = 5000000
	for i in 10:
		SharedStash.buy_tab(ch)
	p.tab["shared"] = 4
	SharedStash.changed.emit()
	await shot("shared_max_tabs")
	get_tree().quit(0)
