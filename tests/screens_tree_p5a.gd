extends Node
## Screenshots for passive tree Phase 5a: zoom levels, filters, search jump, minimap,
## summary panel, drawback tooltip and refunded-node state.
##   godot --path . res://tests/screens_tree_p5a.tscn -- <outdir>

const MainScript = preload("res://scripts/main.gd")
var main = null
var outdir := "res://tests/screens_out_tree_p5a"

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
	for id in ["p4_s_w_in", "w_mel2", "w_2h", "w_1h", "ks_momentum"]:
		ch.allocate_path(id)
	ch.allocate_path("p4_m_melee", "melee_fury")
	ch.add_gem("onyx:2")
	ch.socket_tree_gem("p4_s_w_in", "onyx:2")
	main.start_game()
	await frames(20)
	main.ui.open("passives")
	await frames(3)
	var panel = main.ui.panels["passives"]
	var view = panel.view
	view.fit()
	await shot("lod_far")
	view.center_on(Vector2(-440, 520), 0.5)
	await shot("lod_mid")
	view.center_on(Vector2(-440, 520), 1.0)
	await shot("lod_near")
	panel.chips["melee"].button_pressed = true
	view.center_on(Vector2(-300, 300), 0.5)
	await shot("filter_melee")
	panel.behaviour_btn.button_pressed = true
	await shot("filter_melee_behaviour")
	panel.clear_filters()
	panel.search.text = "bleed"
	panel._on_search("bleed")
	panel.jump_hit(1)
	await shot("search_jump")
	panel.search.text = ""
	panel._on_search("")
	view.center_on(Vector2(-440, 560), 0.9)
	view.hover = "ks_momentum"
	main.ui.show_tooltip(view.node_tooltip("ks_momentum"))
	await shot("keystone_tooltip")
	main.ui.hide_tooltip()
	view.hover = ""
	panel.toggle_summary()
	await shot("summary")
	panel.toggle_summary()
	ch.tree_refund = {"from_version": 5, "reason": "test", "points": 4, "ids": ["m_ele", "w_blk1", "w_def1"]}
	view.center_on(Vector2(-300, 300), 0.8)
	await shot("refunded_state")
	get_tree().quit()
