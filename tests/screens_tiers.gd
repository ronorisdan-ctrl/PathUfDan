extends Node
## Screenshots of every dungeon tier and its boss (needs a display).
##   xvfb-run godot --rendering-driver opengl3 --path . res://tests/screens_tiers.tscn -- <outdir>

const MainScript = preload("res://scripts/main.gd")

var main = null
var outdir := "/tmp/tiers"

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
	Game.new_character("mage")
	Game.ch.progress["highest_tier"] = 6
	Game.ch.level = 20
	Game.ch.refresh_unlocks(false)
	Game.ch.recalc()
	main.start_game()
	await frames(5)
	main.ui.open("dungeon")
	main.ui.panels["dungeon"]._choose("dread_sanctums")
	await shot("00_gate")
	main.ui.close_all()
	for d in Data.dungeon_list:
		main.enter_dungeon(d["id"], 77 + int(d["tier"]))
		await frames(10)
		var lv = Game.level
		var p = lv.player
		p.max_life = 1.0e6
		p.life = 1.0e6
		# walk into the first normal room
		for r in lv.rooms:
			if r["kind"] == "normal":
				p.global_position = lv.cell_center(r["anchor"]) + Vector2(-60, 0)
				p.global_position = lv.clamp_to_floor(lv.cell_center(r["anchor"]), p.global_position)
				break
		await frames(40)
		await shot("t%d_room" % int(d["tier"]))
		for o in lv.objectives:
			if o["type"] != "boss":
				o["done"] = true
		lv._update_seal()
		var br: Dictionary = lv.rooms[lv.layout["boss"]]
		p.global_position = lv.cell_center(br["anchor"]) + Vector2(0, 80)
		await frames(10)
		p.global_position = lv.cell_center(br["anchor"]) + Vector2(0, 80)
		await frames(70)
		await shot("t%d_boss" % int(d["tier"]))
		if lv.boss != null and is_instance_valid(lv.boss):
			lv.boss.life = lv.boss.max_life * 0.2
		await frames(90)
		await shot("t%d_boss_late" % int(d["tier"]))
	get_tree().quit()
