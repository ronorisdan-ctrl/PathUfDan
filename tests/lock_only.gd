extends Node
## Quick runner for the item-lock checks only (full run: tests/test_runner.tscn).
##   godot --headless --fixed-fps 60 --path . res://tests/lock_only.tscn

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
	await T.test_item_lock()
	var f := FileAccess.open("res://tests/lock_only_results.txt", FileAccess.WRITE)
	f.store_line("==== %d passed, %d failed ====" % [T.passes, T.fails])
	for l in T.log_lines:
		f.store_line(l)
	f.close()
	print("==== %d passed, %d failed ====" % [T.passes, T.fails])
	get_tree().quit(1 if T.fails > 0 else 0)
