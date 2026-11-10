extends Node
## Screenshots for passive tree Phase 5b: preset row, planner ghost nodes + route,
## build code box, after apply plan.
##   godot --path . res://tests/screens_tree_p5b.tscn -- <outdir>

const MainScript = preload("res://scripts/main.gd")
var main = null
var outdir := "res://tests/screens_out_tree_p5b"

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
	ch.level = 30
	ch.gold = 50000
	ch.refresh_unlocks(false)
	ch.recalc()
	for id in ["w_mel2", "w_2h"]:
		ch.allocate_path(id)
	ch.switch_preset(1)
	ch.allocated = [ch.class_def()["start_passive"]]
	ch.recalc()
	ch.allocate_path("p4_s_w_in")
	main.start_game()
	await frames(20)
	main.ui.open("passives")
	await frames(3)
	var panel = main.ui.panels["passives"]
	var view = panel.view
	panel.refresh()
	panel.planner_btn.button_pressed = true
	ch.plan_add("ks_momentum")
	ch.plan_add("p4_m_melee", "melee_fury")
	view.center_on(Vector2(-440, 520), 0.8)
	view.hover = "w_1h"
	main.ui.show_tooltip(view.node_tooltip("w_1h"))
	await shot("planner")
	main.ui.hide_tooltip()
	view.hover = ""
	panel.toggle_code()
	panel.export_code()
	await shot("build_code")
	panel.apply_plan()
	await shot("plan_applied")
	view.fit()
	await shot("plan_far")
	get_tree().quit()
