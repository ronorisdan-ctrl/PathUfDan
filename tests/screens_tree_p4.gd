extends Node
## Screenshots for passive tree Phase 4a: mastery nodes, tooltip and effect menu.
##   godot --path . res://tests/screens_tree_p4.tscn -- <outdir>

const MainScript = preload("res://scripts/main.gd")
var main = null
var outdir := "user://screens_tree_p4"

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
	Game.new_character("warrior")
	var ch = Game.ch
	ch.level = 40
	ch.gold = 50000
	ch.refresh_unlocks(false)
	ch.recalc()
	ch.allocate_path("p4_m_melee", "melee_fury")
	ch.allocate_path("w_blk1")
	main.start_game()
	await frames(20)
	main.ui.open("passives")
	await frames(3)
	var view = main.ui.panels["passives"].view
	view.zoom = 1.1
	view.offset = -Vector2(-520, 380) * 1.1
	await shot("mastery_area")
	view.hover = "p4_m_melee"
	main.ui.show_tooltip(view.node_tooltip("p4_m_melee"))
	await shot("mastery_tooltip")
	main.ui.hide_tooltip()
	view.hover = ""
	view._click_mastery("p4_m_bulwark")
	await shot("mastery_menu")
	main.ui.hide_context()
	view.fit()
	await shot("tree_fit")
	get_tree().quit()
