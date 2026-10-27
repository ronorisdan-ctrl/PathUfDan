extends Node
## Screenshots for the developer tools: every panel tab, the HUD tag + overlay,
## and the pause menu. Run with a display: godot --path . res://tests/screens_dev.tscn -- <outdir>

const MainScript = preload("res://scripts/main.gd")
var main = null
var outdir := "user://screens_dev"

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
	Game.dev_in_tests = true
	Game.settings["dev_tools"] = true
	main = MainScript.new()
	add_child(main)
	await frames(5)
	main.menus.show_settings()
	await shot("dev_00_settings")
	Game.new_character("ranger")
	main.start_game()
	await frames(20)
	Dev.set_level(18)
	Dev.add_gold(25000)
	var ui = main.ui
	ui.open("dev")
	var p = ui.panels["dev"]
	for i in p.tabs.get_tab_count():
		p.tabs.current_tab = i
		await frames(2)
		await shot("dev_%02d_%s" % [i + 1, String(p.tabs.get_tab_title(i)).to_lower()])
	ui.close("dev")
	Dev.start_run("abyssal_warrens", ["hasted", "teeming"], 1)
	await frames(10)
	Dev.set_flag("overlay", true)
	Dev.set_flag("god", true)
	Dev.drop_random(6, "")
	await frames(20)
	await shot("dev_20_hud_overlay")
	ui.open("pause")
	await shot("dev_21_pause")
	get_tree().quit(0)
