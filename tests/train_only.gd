extends Node
## Quick runner for the Training Grounds checks only (full run: tests/test_runner.tscn).
##   godot --headless --path . res://tests/train_only.tscn

func _ready() -> void:
	Game.testing = true
	await get_tree().process_frame
	var T = load("res://tests/test_runner.gd").new()
	T.test_training()
	var f := FileAccess.open("res://tests/train_only_results.txt", FileAccess.WRITE)
	f.store_line("==== %d passed, %d failed ====" % [T.passes, T.fails])
	for l in T.log_lines:
		f.store_line(l)
	f.close()
	print("==== %d passed, %d failed ====" % [T.passes, T.fails])
	get_tree().quit(1 if T.fails > 0 else 0)
