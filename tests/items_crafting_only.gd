extends Node
## Quick runner for items and crafting only (existing item tests plus corruption) (full run: tests/test_runner.tscn).
##   godot --headless --fixed-fps 60 --path . res://tests/items_crafting_only.tscn

func _ready() -> void:
	Game.testing = true
	Loot.set_seed(12345)
	await get_tree().process_frame
	var T = load("res://tests/test_runner.gd").new()
	T.set_meta("no_auto", true)
	add_child(T)
	T.main = load("res://scripts/main.gd").new()
	T.add_child(T.main)
	await T.frames(2)
	T.test_item_generation()
	await T.test_crafting()
	await T.test_corruption()
	await T.test_corruption_crafting()
	await T.test_corruption_ui()
	await T.test_item_lock()
	await T.test_destroy_by_rarity()
	await T.test_stash_ui()
	await T.test_dev_tools()
	var f := FileAccess.open("res://tests/items_crafting_only_results.txt", FileAccess.WRITE)
	f.store_line("==== %d passed, %d failed ====" % [T.passes, T.fails])
	for l in T.log_lines:
		f.store_line(l)
	f.close()
	print("==== %d passed, %d failed ====" % [T.passes, T.fails])
	get_tree().quit(1 if T.fails > 0 else 0)
