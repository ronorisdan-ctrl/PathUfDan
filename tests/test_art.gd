extends RefCounted
## Phase V0 art-pipeline checks (sprite manifest, sheet animation, fallback, sync,
## gameplay neutrality). Called from tests/test_runner.gd; quick run on its own:
##   godot --headless --fixed-fps 60 --path . res://tests/art_only.tscn

const Rules = preload("res://scripts/gfx/anim_rules.gd")
const V0_SET := ["warrior", "ranger", "mage", "ghoul"]

var T = null   # the test runner (check, frames, main)

func run(runner) -> void:
	T = runner
	T._log("--- art pipeline (V0)")
	test_render_and_manifest()
	test_direction_rules()
	test_sync_rules()
	test_texture_imports()
	test_validate_tool()
	await test_fallback_in_dungeon()
	await test_placeholders_in_dungeon()
	await test_player_attack_sync()
	await test_enemy_windup_sync()
	await test_rng_isolation()
	await test_gallery()
	_restore()

func _restore() -> void:
	Art.force_fallback = false
	Art.placeholders_in_game = bool(Art.render.get("placeholders_in_game", false))
	Art.load_manifest()

func _set_art(placeholders: bool, fallback: bool) -> void:
	Art.placeholders_in_game = placeholders
	Art.force_fallback = fallback
	Art.clear_sheet_cache()

# ------------------------------------------------------------------ data
func _data_sprite_ids() -> Dictionary:
	# every "sprite" id referenced by data/*.json -> where it was found
	var ids := {}
	for c in Data.class_list:
		ids[str(c.get("sprite", ""))] = "classes:" + str(c["id"])
	for id in Data.enemies:
		ids[str(Data.enemies[id].get("sprite", "ghoul"))] = "enemies:" + id
	for id in Data.summons:
		ids[str(Data.summons[id].get("sprite", "skeleton"))] = "summons:" + id
	for p in Data.pet_list:
		ids[str(p.get("sprite", "pet_dog"))] = "pets:" + str(p.get("id", ""))
	ids.erase("")
	return ids

func test_render_and_manifest() -> void:
	T.check(not Art.render.is_empty(), "art: data/render.json loads")
	T.check(is_equal_approx(Art.ART_SCALE, 0.5) and is_equal_approx(Art.camera_zoom(), 2.0),
		"art: art scale 0.5 at camera zoom 2 (1 art px = 1 screen px)", "%s %s" % [Art.ART_SCALE, Art.camera_zoom()])
	T.check(int(Art.render.get("tile_px", 0)) == 2 * int(Art.render.get("world_cell", 0)),
		"art: tile_px is 2x the world cell (32 px art per 16-unit cell)")
	var sprites: Dictionary = Art.manifest.get("sprites", {})
	T.check(sprites.size() >= 30, "art: manifest lists the characters", str(sprites.size()))
	var bad := []
	for id in sprites:
		var e := Art.sprite_entry(id)
		var dirs := int(e.get("directions", 8))
		if not dirs in [1, 2, 4, 8]:
			bad.append("%s directions %d" % [id, dirs])
		if not e["anims"].has("idle"):
			bad.append(id + " has no idle")
		var fb := str(e.get("fallback", ""))
		if fb == "" or not Art.SPRITES.has(fb):
			bad.append("%s fallback '%s' is not an Art.sprite id" % [id, fb])
		var fr: Array = e["frame"]
		var pv: Array = e["pivot"]
		if pv[0] < 0 or pv[0] >= fr[0] or pv[1] < 0 or pv[1] >= fr[1]:
			bad.append(id + " pivot outside the frame")
		for n in e["anims"]:
			var a: Dictionary = e["anims"][n]
			var nf := int(a.get("frames", 0))
			if nf < 1:
				bad.append("%s/%s frames" % [id, n])
			if a.has("impact_frame") and (int(a["impact_frame"]) < 0 or int(a["impact_frame"]) >= nf):
				bad.append("%s/%s impact_frame out of range" % [id, n])
			if a.has("corpse_frame") and int(a["corpse_frame"]) >= nf:
				bad.append("%s/%s corpse_frame out of range" % [id, n])
			if a.has("sync") and not str(a["sync"]) in ["skill", "windup", "dodge"]:
				bad.append("%s/%s unknown sync %s" % [id, n, a["sync"]])
	T.check(bad.is_empty(), "art: every manifest entry is well formed", str(bad))
	# every enemy, class and summon id has a manifest entry or keeps its old sprite
	var missing := []
	var used := _data_sprite_ids()
	for sid in used:
		if not Art.SPRITES.has(sid) and not sprites.has(sid):
			missing.append("%s (%s)" % [sid, used[sid]])
	T.check(missing.is_empty(), "art: every sprite id in data/*.json resolves to art or a fallback", str(missing))
	for id in Data.enemies:
		if id == "training_dummy":
			continue
		T.check(sprites.has(id), "art: manifest entry for enemy %s" % id)
	for c in Data.class_list:
		T.check(sprites.has(c["id"]), "art: manifest entry for class %s" % c["id"])
	# placeholder sheets resolve with the right grid
	Art.art_errors.clear()
	for id in V0_SET:
		var d := Art.sprite_def_any(id)
		T.check(not d.is_empty() and d.get("placeholder", false), "art: placeholder sheets for %s load" % id)
		if not d.is_empty():
			T.check(d["anims"].size() == Art.sprite_entry(id)["anims"].size(), "art: every %s animation has a sheet" % id)
			var sf: SpriteFrames = Art.sprite_frames_for(d)
			var rows := int(d["rows"])
			T.check(rows == Rules.rows_needed(int(d["directions"]), bool(d["mirror"])), "art: %s row count matches its directions" % id)
			T.check(sf.get_frame_count("idle_0") == int(d["anims"]["idle"]["frames"]) and sf.has_animation("idle_%d" % (rows - 1)),
				"art: %s SpriteFrames built per direction row" % id)
	T.check(Art.art_errors.is_empty(), "art: no sheet size errors", str(Art.art_errors))

# ------------------------------------------------------------------ rules
func test_direction_rules() -> void:
	var exp := {Vector2(0, 1): 0, Vector2(1, 1): 1, Vector2(1, 0): 2, Vector2(1, -1): 3,
		Vector2(0, -1): 4, Vector2(-1, -1): 5, Vector2(-1, 0): 6, Vector2(-1, 1): 7}
	var ok := true
	for v in exp:
		if Rules.dir8(v) != exp[v]:
			ok = false
	T.check(ok, "art: 8-way direction from vectors (S, SE, E, NE, N, NW, W, SW)")
	# hysteresis around the E/SE boundary (22.5 degrees below east)
	var just_over := Vector2.RIGHT.rotated(deg_to_rad(22.5 + 5.0))
	var well_over := Vector2.RIGHT.rotated(deg_to_rad(22.5 + 12.0))
	T.check(Rules.dir8(just_over) == 1, "art: raw pick crosses into SE past 22.5 degrees")
	T.check(Rules.pick(just_over, 2, 8) == 2, "art: hysteresis keeps E just past the boundary")
	T.check(Rules.pick(well_over, 2, 8) == 1, "art: hysteresis lets go once clearly past it")
	T.check(Rules.pick(Vector2.ZERO, 5, 8) == 5, "art: zero vector keeps the current facing")
	T.check(Rules.pick(Vector2(-1, 0.2), 2, 4) == 6 and Rules.pick(Vector2(0, -1), 6, 4) == 4, "art: 4-way picks W and N")
	# mirroring
	T.check(Rules.row_for(5, 8, true) == [3, true] and Rules.row_for(6, 8, true) == [2, true] and Rules.row_for(7, 8, true) == [1, true],
		"art: NW/W/SW mirror NE/E/SE rows")
	T.check(Rules.row_for(4, 8, true) == [4, false] and Rules.row_for(6, 8, false) == [6, false], "art: unmirrored 8-row sheets map one row per direction")
	T.check(Rules.row_for(6, 4, true) == [1, true] and Rules.row_for(4, 4, true) == [2, false] and Rules.row_for(0, 4, true) == [0, false],
		"art: 4-way sheets: S, E, N rows, W mirrors E")
	T.check(Rules.rows_needed(8, true) == 5 and Rules.rows_needed(4, true) == 3 and Rules.rows_needed(8, false) == 8, "art: rows needed per layout")

func test_sync_rules() -> void:
	var ok := true
	for c in [[0.3, 6, 3], [0.0, 6, 3], [0.55, 7, 4], [0.9, 6, 5], [1.0, 6, 5]]:
		if Rules.synced_frame(c[0], c[0], c[1], c[2]) != c[2]:
			ok = false
			T._log("   synced_frame impact mismatch %s" % str(c))
	T.check(ok, "art: the impact frame shows exactly when gameplay applies the hit")
	T.check(Rules.synced_frame(0.0, 0.3, 6, 3) == 0 and Rules.synced_frame(0.29, 0.3, 6, 3) == 2, "art: wind-up frames fill the time before the hit")
	T.check(Rules.synced_frame(0.999, 0.3, 6, 3) == 5 and Rules.synced_frame(1.0, 0.3, 6, 3) == 5, "art: the action ends on its last frame")
	T.check(Rules.synced_frame(0.05, 0.0, 6, 3) == 3, "art: instant skills start on the impact frame")
	T.check(Rules.looped_frame(0.35, 10, 4, true) == 3 and Rules.looped_frame(0.45, 10, 4, true) == 0 and Rules.looped_frame(5.0, 10, 4, false) == 3,
		"art: looped and one-shot frame clocks")

func test_texture_imports() -> void:
	var bad := []
	var n := [0]
	_scan_imports("res://assets", bad, n)
	T.check(n[0] > 0 and bad.is_empty(), "art: every PNG in assets/ imports lossless without mipmaps", "%d files, bad: %s" % [n[0], str(bad)])

func _scan_imports(dir: String, bad: Array, n: Array) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	for sub in da.get_directories():
		_scan_imports(dir + "/" + sub, bad, n)
	for f in da.get_files():
		if not f.ends_with(".png"):
			continue
		n[0] += 1
		var imp := dir + "/" + f + ".import"
		if not FileAccess.file_exists(imp):
			bad.append(f + " (not imported)")
			continue
		var txt := FileAccess.get_file_as_string(imp)
		if txt.find("mipmaps/generate=false") < 0 or txt.find("compress/mode=0") < 0:
			bad.append(f)

func test_validate_tool() -> void:
	var tool := ProjectSettings.globalize_path("res://tools/validate_art.py")
	for py in ["python3", "python"]:
		var out := []
		var code := OS.execute(py, [tool, "--quiet"], out, true)
		if code == -1 or (out.size() > 0 and str(out[0]).find("Pillow") >= 0 and code != 0 and str(out[0]).find("ERROR") < 0):
			continue
		T.check(code == 0, "art: tools/validate_art.py is clean", str(out))
		return
	T._log("SKIP  art: tools/validate_art.py (no python with Pillow on this machine)")
	print("SKIP  art: tools/validate_art.py (no python with Pillow)")

# ------------------------------------------------------------------ in a real dungeon
func _enter(seed_value: int) -> Object:
	Game.new_character("warrior")
	T.main.start_game()
	await T.frames(3)
	T.main.enter_dungeon("forgotten_depths", seed_value)
	await T.frames(3)
	return Game.level

func test_fallback_in_dungeon() -> void:
	# 1) default: no real art and placeholders off -> everyone keeps the old sprite
	_set_art(false, false)
	var lv = await _enter(4242)
	var any_anim := lv.player.anim != null
	for e in lv.enemies:
		any_anim = any_anim or e.anim != null
	T.check(not any_anim and lv.player.sprite.texture != null and lv.player.sprite.self_modulate.a > 0.5,
		"art: with no sheet art every actor uses the old sprite")
	# 2) the manifest pointing at missing files behaves the same, without errors
	_set_art(true, false)
	var saved: Dictionary = Art.manifest.duplicate(true)
	for id in Art.manifest["sprites"]:
		for n in Art.manifest["sprites"][id].get("anims", {}):
			Art.manifest["sprites"][id]["anims"][n]["file"] = "missing/%s_%s.png" % [id, n]
	Art.clear_sheet_cache()
	lv = await _enter(4243)
	any_anim = lv.player.anim != null
	for e in lv.enemies:
		any_anim = any_anim or e.anim != null
	await T.frames(20)
	T.check(not any_anim and is_instance_valid(lv.player) and lv.enemies.size() > 5, "art: missing sheet files fall back to the old art and the dungeon runs")
	Art.manifest = saved
	Art.clear_sheet_cache()

func test_placeholders_in_dungeon() -> void:
	_set_art(true, false)
	var lv = await _enter(4242)
	var p = lv.player
	T.check(p.anim != null and p.anim.def.get("id") == "warrior", "art: placeholders: the warrior animates from sheets")
	if p.anim == null:
		return
	T.check(p.sprite.self_modulate.a == 0.0 and p.anim.scale == Vector2(0.5, 0.5), "art: old sprite hidden, sheet drawn at art scale 0.5")
	var ghouls := []
	for e in lv.enemies:
		if e.def.get("id") == "ghoul":
			ghouls.append(e)
	T.check(ghouls.size() > 0 and ghouls[0].anim != null and int(ghouls[0].anim.def["directions"]) == 4, "art: placeholders: ghouls animate with 4 directions")
	var others_fallback := true
	for e in lv.enemies:
		if e.def.get("id") != "ghoul" and e.anim != null:
			others_fallback = false
	T.check(others_fallback, "art: enemies without sheets keep their old sprite next to animated ones")
	# idle -> run, and 8 directions reached by moving
	await T.frames(4)
	T.check(p.anim.cur == "idle", "art: standing still plays idle", p.anim.cur)
	var seen := {}
	for d in 8:
		var v := Vector2.RIGHT.rotated(Rules.dir_angle(d)) * 40.0
		p.velocity = v
		for i in 3:
			p.anim._process(1.0 / 60.0)
		seen[p.anim.dir] = true
		T.check(p.anim.cur == "run", "art: moving plays run (%s)" % Rules.NAMES[d], p.anim.cur)
	T.check(seen.size() == 8, "art: the player reaches all 8 directions", str(seen.keys()))
	p.velocity = Vector2.ZERO
	# hit flash still shows on the animated sprite
	p.flash = 0.12
	p.update_visual(0.0, false)
	p.anim._process(0.0)
	T.check(p.anim.modulate.r > 2.0, "art: hit flash carries over to the sheet sprite")
	T.check(p.visual_height() > 20.0, "art: bars sit above the taller sheet figure", str(p.visual_height()))

func test_player_attack_sync() -> void:
	_set_art(true, false)
	for case in [["fast", 2.5], ["slow", 0.5]]:
		var lv = await _enter(4242)
		var p = lv.player
		var e = T._nearest_enemy(lv, p)
		if e == null or p.anim == null:
			T.check(false, "art: sync test setup (%s)" % case[0])
			continue
		e.set_physics_process(false)
		e.max_life = 1.0e6
		e.life = 1.0e6
		p.global_position = lv.clamp_to_floor(e.global_position, e.global_position + Vector2(-14, 0))
		await T.frames(2)
		p.auto_aim_override = e.global_position
		p.ch.final["attack_speed_mult"] = case[1]
		var slot := -1
		for i in p.ch.loadout.size():
			var sk = Data.skills.get(p.ch.loadout[i], {})
			if sk.get("behavior", "") == "melee_arc" and sk.get("kind", "") == "attack":
				slot = i
				break
		if slot < 0:
			T.check(false, "art: warrior has a melee attack for the sync test")
			continue
		var life0: float = e.life
		T.check(p.try_use_slot(slot), "art: %s melee attack used" % case[0])
		var imp := int(p.anim.def["anims"]["attack"].get("impact_frame", 0))
		T.check(is_equal_approx(p.swing_impact, p.current_use_time * 0.3), "art: the melee hit time is known to the animation (%s)" % case[0])
		var hit_frame := -1
		var pre_ok := true
		for i in 240:
			await T.get_tree().process_frame
			if e.life < life0:
				hit_frame = p.anim.cur_frame
				break
			if p.anim.cur == "attack" and p.anim.cur_frame > imp:
				pre_ok = false
		T.check(hit_frame >= 0 and absi(hit_frame - imp) <= 1, "art: %s attack: impact frame lands with the hit (frame %d, impact %d, use %.2fs)" % [case[0], hit_frame, imp, p.current_use_time])
		T.check(pre_ok, "art: %s attack: no post-impact frame before the hit" % case[0])
		p.ch.recalc()

func test_enemy_windup_sync() -> void:
	_set_art(true, false)
	var lv = await _enter(4244)
	var p = lv.player
	p.max_life = 1.0e6
	p.life = 1.0e6
	var g = null
	for e in lv.enemies:
		if e.def.get("id") == "ghoul" and e.anim != null:
			g = e
			break
	T.check(g != null, "art: a ghoul for the wind-up test")
	if g == null:
		return
	for e in lv.enemies:
		if e != g:
			e.set_physics_process(false)
	p.input_enabled = false
	p.global_position = lv.clamp_to_floor(g.global_position, g.global_position + Vector2(-12, 0))
	g.aggro = true
	var imp := int(g.anim.def["anims"]["attack"].get("impact_frame", 0))
	var saw_windup := false
	var windup_off := 0   # samples in wind-up not showing the attack (1 allowed: render lags physics by a frame)
	var windup_pre_impact := true
	var at_hit := -1
	var prev_state := ""
	for i in 600:
		await T.get_tree().process_frame
		if g.state == "windup":
			saw_windup = true
			if g.anim.cur != "attack":
				windup_off += 1
			if g.anim.cur_frame > imp:
				windup_pre_impact = false
		if prev_state == "windup" and g.state == "recover":
			at_hit = g.anim.cur_frame
			break
		prev_state = g.state
	T.check(saw_windup, "art: the ghoul winds up an attack")
	T.check(windup_off <= 1, "art: the attack animation covers the whole wind-up", "%d off" % windup_off)
	T.check(windup_pre_impact, "art: no frame past the impact frame during the wind-up")
	T.check(at_hit >= 0 and absi(at_hit - imp) <= 1, "art: the ghoul's impact frame lands when its hit is performed", "frame %d impact %d" % [at_hit, imp])
	p.input_enabled = true

func test_rng_isolation() -> void:
	# Sheet sprites must never advance the global, Combat or Loot RNGs.
	_set_art(true, false)
	var lv = await _enter(4245)
	seed(98765)
	Combat.rng.seed = 555
	var c0: int = Combat.rng.state
	var l0 = Loot.rng.state if "rng" in Loot else 0
	var anims := []
	for e in lv.enemies:
		if e.anim != null:
			anims.append(e.anim)
	anims.append(lv.player.anim)
	var made := 0
	for i in 20:
		var a = load("res://scripts/gfx/sprite_anim.gd").new()
		a.setup(Art.sprite_def_any("ghoul"))
		a.forced_anim = "attack"
		lv.add_child(a)
		anims.append(a)
		made += 1
	for i in 120:
		for a in anims:
			if a != null and is_instance_valid(a):
				a._process(1.0 / 60.0)
	var g_next := randi()
	seed(98765)
	T.check(g_next == randi(), "art: sheet sprites don't use the global RNG")
	T.check(Combat.rng.state == c0, "art: sheet sprites don't use the Combat RNG")
	T.check(("rng" not in Loot) or Loot.rng.state == l0, "art: sheet sprites don't use the Loot RNG")
	T.check(not Game.hitstop_allowed(), "art: hit-stop is off under Game.testing")
	for a in anims.slice(anims.size() - made):
		a.queue_free()

func test_gallery() -> void:
	var g = load("res://tests/art_gallery.gd").new()
	T.add_child(g)
	await T.frames(3)
	T.check(g.anims.size() >= 29 * 3 and g.shown.size() >= V0_SET.size(), "art: the gallery shows every sheet in every direction", "%d cells" % g.anims.size())
	T.check(g.missing.size() + g.shown.size() == Art.manifest["sprites"].size(), "art: the gallery lists entries without sheets")
	g.queue_free()
	await T.frames(1)
