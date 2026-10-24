extends Node
## Screenshots for stage 4: expanded passive web, jeweller and gems, charms.

const MainScript = preload("res://scripts/main.gd")
var main = null
var outdir := "/tmp/s4"

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
	main = MainScript.new()
	add_child(main)
	await frames(5)
	Game.new_character("ranger")
	var ch = Game.ch
	ch.level = 40
	ch.gold = 50000
	ch.refresh_unlocks(false)
	ch.recalc()
	ch.allocate_path("xw_ks")
	ch.allocate_path("xp_r0")
	for g in Data.gem_list:
		ch.add_gem(Loot.gem_id(g["id"], 0), 3)
		ch.add_gem(Loot.gem_id(g["id"], 2), 1)
	var bow: Dictionary = Loot.roll_item(40, 300.0, "ranger", "rare")
	ch.inventory[0] = Loot.make_item("hunting_bow" if Data.item_bases.has("hunting_bow") else "longbow", "rare", 40)
	var chest: Dictionary = Loot.make_item("leather_jerkin" if Data.item_bases.has("leather_jerkin") else "plate_cuirass", "rare", 40)
	for i in 3:
		Loot.add_random_affix(chest)
		Loot.add_socket(chest)
	chest["gems"] = ["ruby:2", "topaz:2", ""]
	chest["name"] = "Socketed Jerkin"
	ch.inventory[1] = chest
	ch.inventory[2] = Loot.make_unique("wolfmother", 40)
	ch.inventory[3] = Loot.make_unique("starfall_staff", 40)
	ch.inventory[4] = bow
	var charm: Dictionary = Loot.make_item("relic_charm", "epic", 42)
	for i in 4:
		Loot.add_random_affix(charm)
	Loot._rename(charm)
	ch.inventory[5] = charm
	main.start_game()
	await frames(20)
	await shot("hub")
	main.ui.open_station("jeweller")
	main.ui.panels["jeweller"].select(chest)
	await frames(5)
	await shot("jeweller")
	main.ui.item_tooltip(chest, true)
	await shot("jeweller_tooltip")
	main.ui.close_all()
	main.ui.open("passives")
	await frames(3)
	main.ui.panels["passives"].view.fit()
	await shot("tree_fit")
	main.ui.panels["passives"].view.zoom = 0.75
	main.ui.panels["passives"].view.offset = -Vector2(1000, 600) * 0.75
	await shot("tree_windwalker")
	main.ui.panels["passives"].view.search = "resist"
	main.ui.panels["passives"].view.fit()
	await shot("tree_search")
	main.ui.close_all()
	main.ui.open("inventory")
	main.ui.item_tooltip(charm, true)
	await shot("charm")
	main.ui.item_tooltip(ch.inventory[3], true)
	await shot("starfall")
	get_tree().quit()
