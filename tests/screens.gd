extends Node
## Captures screenshots of key screens for visual review (needs a display).
##   xvfb-run godot --path . res://tests/screens.tscn -- <class> <outdir>

const MainScript = preload("res://scripts/main.gd")

var main = null
var outdir := "/tmp/shots"
var cls := "warrior"

func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func shot(tag: String) -> void:
	await frames(3)
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s_%s.png" % [outdir, cls, tag])
	print("shot ", tag)

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		cls = args[0]
	if args.size() > 1:
		outdir = args[1]
	DirAccess.make_dir_recursive_absolute(outdir)
	Game.testing = true
	Loot.set_seed(99)
	main = MainScript.new()
	add_child(main)
	await frames(10)
	await shot("01_menu")
	main.menus.show_class_select()
	await frames(5)
	await shot("02_class_select")
	Game.new_character(cls)
	main.start_game()
	await frames(20)
	await shot("03_hub")
	main.enter_dungeon("forgotten_depths", 31337)
	await frames(20)
	var lv = Game.level
	var p = lv.player
	# find a pack and fight it
	var e = null
	var bd := INF
	for x in lv.enemies:
		var d: float = x.global_position.distance_to(p.global_position)
		if d < bd:
			bd = d
			e = x
	if e != null:
		p.global_position = lv.clamp_to_floor(e.global_position, e.global_position + Vector2(-70, 10))
		for i in 6:
			await frames(4)
		await shot("04_dungeon_approach")
		for i in 40:
			if not is_instance_valid(e) or not e.alive:
				for x in lv.enemies:
					if is_instance_valid(x) and x.alive and x.global_position.distance_to(p.global_position) < 200:
						e = x
						break
			if is_instance_valid(e):
				p.auto_aim_override = e.global_position + Vector2(0, -4)
				p.mana = 999
				p.life = p.max_life
				p.try_use_slot(i % 2)
			await frames(6)
			if i == 8:
				await shot("05_combat")
		await shot("06_after_combat")
	p.auto_aim_override = null
	# give some loot and open panels
	for i in 8:
		var it: Dictionary = Loot.roll_item(8, 300, cls)
		it["uid"] = Game.ch.take_uid()
		Game.ch.add_to_bag(it)
		lv.spawn_drop({"kind": "item", "item": Loot.roll_item(8, 300, cls)}, p.global_position + Vector2(randf_range(-40, 40), randf_range(-30, 30)))
	await frames(20)
	await shot("07_loot_on_floor")
	var ui = main.ui
	ui.open("inventory")
	await frames(3)
	ui.item_tooltip(Game.ch.inventory[1], true)
	await shot("08_inventory")
	ui.close_all()
	ui.open("character")
	await shot("09_character")
	ui.close_all()
	Game.ch.level = 8
	Game.ch.refresh_unlocks(false)
	Game.ch.recalc()
	ui.open("passives")
	await frames(5)
	await shot("10_passives")
	ui.close_all()
	ui.open("skills")
	await shot("11_skills")
	ui.close_all()
	# boss
	var br: Dictionary = lv.rooms[lv.layout["boss"]]
	p.global_position = lv.cell_center(br["anchor"]) + Vector2(0, 70)
	await frames(30)
	await shot("12_boss")
	main.go_hub(false)
	await frames(10)
	ui.open_station("blacksmith")
	ui.panels["blacksmith"].select(Game.ch.inventory[1])
	await shot("13_blacksmith")
	ui.close_all()
	ui.open("dungeon")
	await shot("14_dungeon_select")
	get_tree().quit()
