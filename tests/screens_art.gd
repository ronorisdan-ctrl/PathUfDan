extends Node
## Phase-end art screenshots (needs a display): every art-gallery page, then one
## standard combat scene per dungeon tier with sheet art (placeholders allowed).
##   xvfb-run godot --rendering-driver opengl3 --path . res://tests/screens_art.tscn -- <outdir>
## Saves 1280x720 PNGs: gallery_<n>.png, t<tier>_combat.png, t1_combat_fallback.png.

const MainScript = preload("res://scripts/main.gd")
const Gallery = preload("res://tests/art_gallery.gd")

var outdir := "/tmp/art_shots"

func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func shot(tag: String) -> void:
	await frames(3)
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [outdir, tag])
	print("shot ", tag)

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if not a.begins_with("--"):
			outdir = a
	DirAccess.make_dir_recursive_absolute(outdir)
	Game.testing = true
	Art.placeholders_in_game = true
	Art.clear_sheet_cache()
	# 1) gallery pages
	var g = Gallery.new()
	add_child(g)
	await frames(30)
	for i in g.page_count():
		g.show_page(i)
		await frames(7)
		await shot("gallery_%02d" % i)
	g.queue_free()
	await frames(2)
	# 2) one combat scene per tier
	var main = MainScript.new()
	add_child(main)
	await frames(5)
	for pass_i in 2:
		if pass_i == 1:
			Art.force_fallback = true      # same T1 scene with the old art, for comparison
			Art.clear_sheet_cache()
		Game.new_character("warrior")
		Game.ch.progress["highest_tier"] = 6
		Game.ch.level = 4
		Game.ch.refresh_unlocks(false)
		Game.ch.recalc()
		main.start_game()
		await frames(5)
		for d in Data.dungeon_list:
			if pass_i == 1 and int(d["tier"]) != 1:
				continue
			main.enter_dungeon(d["id"], 77 + int(d["tier"]))
			await frames(10)
			var lv = Game.level
			var p = lv.player
			p.max_life = 1.0e6
			p.life = 1.0e6
			# stand next to a pack (T1: a ghoul pack, so both sheet actors are on screen)
			var c: Vector2 = p.global_position
			var target = null
			for e in lv.enemies:
				if e.def.get("id") == "ghoul" or target == null and not e.is_boss:
					target = e
					if e.def.get("id") == "ghoul":
						break
			if target != null:
				c = target.global_position
				p.global_position = lv.clamp_to_floor(c, c + Vector2(-40, 0))
				for e in lv.enemies:
					if e.global_position.distance_to(c) < 160:
						e.aggro = true
			# wait for a wind-up so the attack pose is on screen
			for i in 240:
				await frames(1)
				var winding := false
				for e in lv.enemies:
					if e.state == "windup" and e.global_position.distance_to(p.global_position) < 200:
						winding = true
				if winding and i > 20:
					break
			p.auto_aim_override = c
			await shot("t%d_combat%s" % [int(d["tier"]), "_fallback" if pass_i == 1 else ""])
	get_tree().quit()
