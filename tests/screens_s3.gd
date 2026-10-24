extends Node
## Screenshots for stage 3: new skills, runes and specialisations.

const MainScript = preload("res://scripts/main.gd")
var main = null
var outdir := "/tmp/s3"

func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func shot(tag: String) -> void:
	await frames(3)
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [outdir, tag])
	print("shot ", tag)

func use(p, sid: String, at: Vector2) -> void:
	Game.ch.loadout[0] = sid
	p.busy = 0
	p.mana = 9999
	p.cooldowns.clear()
	p.auto_aim_override = at
	p.try_use_slot(0)

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		outdir = args[0]
	DirAccess.make_dir_recursive_absolute(outdir)
	Game.testing = true
	main = MainScript.new()
	add_child(main)
	await frames(5)
	for cls in ["mage", "ranger", "warrior"]:
		Game.new_character(cls)
		var ch = Game.ch
		ch.level = 30
		ch.refresh_unlocks(false)
		ch.recalc()
		for r in Data.skill_rune_list:
			ch.add_rune(r["id"], 1)
		main.start_game()
		await frames(5)
		main.enter_dungeon("abyssal_warrens", 12)
		await frames(10)
		var lv = Game.level
		var p = lv.player
		p.max_life = 1e6
		p.life = 1e6
		var e = null
		var bd := INF
		for x in lv.enemies:
			var d: float = x.global_position.distance_to(p.global_position)
			if d < bd:
				bd = d
				e = x
		p.global_position = lv.clamp_to_floor(e.global_position, e.global_position + Vector2(-90, 0))
		await frames(30)
		var seq: Array = {"mage": ["inferno", "blizzard", "summon_skeleton_archers", "arcane_missiles", "curse_of_frailty", "disintegration_beam"],
			"ranger": ["frost_snare", "cannon_turret", "repeater_turret", "explosive_arrow", "barrage", "death_from_above"],
			"warrior": ["earthquake", "whirlwind", "battle_leap", "titans_fall", "chain_hook", "berserker_rage"]}[cls]
		for sid in seq:
			var tgt: Vector2 = e.global_position if is_instance_valid(e) else p.global_position + Vector2(60, 0)
			use(p, sid, tgt)
			await frames(14)
		await shot("%s_skills" % cls)
		if ch.rune_fits("split", seq[3]) == "":
			ch.socket_rune(seq[3], "split")
		else:
			ch.socket_rune(seq[3], "efficiency")
		main.ui.open("skills")
		await frames(4)
		await shot("%s_skills_panel" % cls)
		main.ui.close_all()
		ch.level = 44
		ch.recalc()
		var sp: Dictionary = Data.specs_for_class(cls)[0]
		main.ui.open("spec")
		await frames(3)
		await shot("%s_spec_choose" % cls)
		ch.choose_spec(sp["id"])
		for n in sp["nodes"].slice(0, 5):
			ch.alloc_spec(n["id"])
		main.ui.panels["spec"].refresh()
		await frames(3)
		await shot("%s_spec_tree" % cls)
		main.ui.close_all()
	get_tree().quit()
