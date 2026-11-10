extends Node
## Screenshots for passive tree Phase 4b: gem sockets, radius ring, tooltip and gem menu.
##   godot --path . res://tests/screens_tree_p4b.tscn -- <outdir>

const MainScript = preload("res://scripts/main.gd")
var main = null
var outdir := "res://tests/screens_out_tree_p4b"

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
	ch.level = 60
	ch.gold = 50000
	ch.refresh_unlocks(false)
	ch.recalc()
	for id in ["p4_s_w_in", "w_mel2", "w_2h", "w_1h"]:
		ch.allocate_path(id)
	ch.add_gem("onyx:2")
	ch.add_gem("ruby:0")
	ch.add_gem("diamond:3")
	ch.socket_tree_gem("p4_s_w_in", "onyx:2")
	main.start_game()
	await frames(20)
	main.ui.open("passives")
	await frames(3)
	var view = main.ui.panels["passives"].view
	view.zoom = 1.1
	view.offset = -Vector2(-448, 358) * 1.1
	await shot("socket_area")
	view.hover = "p4_s_w_in"
	main.ui.show_tooltip(view.node_tooltip("p4_s_w_in"))
	await shot("socket_tooltip")
	main.ui.hide_tooltip()
	view.hover = ""
	view._click_socket("p4_s_w_in")
	await shot("socket_menu")
	main.ui.hide_context()
	view.fit()
	await shot("tree_fit")
	get_tree().quit()
