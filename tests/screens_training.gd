extends Node
## Screenshots for the Training Grounds: a single test running, a single result, the Result
## tab, an AoE result, the History tab (expanded row) and the Setup tab.
## Run with a display (not headless):
##   godot --path . res://tests/screens_training.tscn -- <outdir>
## The damage is simulated with real combat packets (Combat.deal on the dummies) at a steady
## cadence, so the numbers, breakdown and head labels are the real thing.

const MainScript = preload("res://scripts/main.gd")
var main = null
var outdir := "user://screens_training"

func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func shot(tag: String) -> void:
	await frames(3)
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [outdir, tag])
	print("shot ", tag, "  viewport ", get_viewport().get_visible_rect().size)

func pk(skill: String, kind: String, dmg: float, extra: Dictionary = {}) -> Dictionary:
	var p := {"dmg": {"fire": [dmg * 0.8, dmg * 1.2]}, "crit_chance": 25.0, "crit_mult": 2.0, "faction": "player", "status": [], "tags": [], "flags": {}, "skill": skill, "kind": kind, "cast": Combat.cast_serial}
	for k in extra:
		p[k] = extra[k]
	return p

## Plays `secs` of game time of steady damage on the dummies.
func play(secs: float, targets: Array, aoe: bool, p) -> void:
	var n := int(secs * 60.0)
	for f in n:
		await get_tree().physics_frame
		if f % 8 == 0:
			Combat.cast_serial += 1
			for t in (targets if aoe else [targets[0]]):
				Combat.deal(pk("fireball", "spell", 80.0, {"status": [{"type": "ignite", "chance": 100.0}]}), p, t)
		if f % 45 == 20:
			Combat.cast_serial += 1
			for t in (targets if aoe else [targets[0]]):
				Combat.deal(pk("frost_nova", "spell", 140.0), p, t)
		if f % 30 == 10:
			Combat.deal(pk("summon_skeletons", "minion", 35.0, {"src_skill": "summon_skeletons"}), p, targets[0])

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		outdir = args[0]
	DirAccess.make_dir_recursive_absolute(outdir)
	Game.testing = true
	Game.training_in_tests = true
	main = MainScript.new()
	add_child(main)
	await frames(5)
	Game.new_character("mage")
	var ch = Game.ch
	ch.loadout[0] = "fireball"
	ch.loadout[1] = "frost_nova"
	ch.loadout[2] = "summon_skeletons"
	main.start_game()
	await frames(20)
	var hub = Game.level
	var p = hub.player
	p.global_position = hub.cell_center(Vector2i(16, 19))
	await frames(20)
	var ui = main.ui
	ui.open_station("training")
	await frames(3)
	var tp = ui.panels["training"]
	await shot("training_setup")

	# ---- single target
	tp._spawn()
	await frames(10)
	var d = hub.training_dummies[0]
	await shot("training_single_idle")
	await play(3.0, hub.training_dummies, false, p)
	await shot("training_single_running")
	await play(7.4, hub.training_dummies, false, p)
	await frames(10)
	ui.close_all()
	await shot("training_single_result")
	ui.open_station("training")
	tp._show_tab("result")
	await frames(3)
	await shot("training_result_tab")

	# ---- a second single test with a different hotbar, so History has a change to show
	ch.loadout[3] = "meteor"
	await play(2.1, hub.training_dummies, false, p)       # past the restart grace
	await play(10.4, hub.training_dummies, false, p)
	await frames(5)

	# ---- AoE
	TrainingLog.set_option("type", "aoe")
	TrainingLog.set_option("spacing", "tight")
	tp._spawn()
	await frames(10)
	await play(10.4, hub.training_dummies, true, p)
	await frames(10)
	ui.close_all()
	await shot("training_aoe_result")
	ui.open_station("training")
	tp._show_tab("result")
	await frames(3)
	await shot("training_aoe_result_tab")

	# ---- History
	tp._show_tab("history")
	tp.open_row = 0
	tp.refresh()
	await frames(3)
	await shot("training_history")
	tp.open_row = -1
	tp.refresh()
	await frames(3)
	await shot("training_history_collapsed")
	get_tree().quit(0)
