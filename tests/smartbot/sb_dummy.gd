extends RefCounted
## Phase D2 (docs/PHASE_D2_MEASUREMENTS.md): Training Grounds dummy pass for keystone builds.
## Separates keystone maths from bot play: the bot's own skill choice and aim (sb_controller
## _pick_skill) against an immortal Training Grounds dummy in the hub, with the player pinned at
## a fixed distance and nothing attacking it. The TrainingLog measures the window.
##   --dummy=<dist>[:<secs>]    stand <dist> units from the dummy (default window 30 s)
##   --dummy-profile=t6_boss|t3_normal|none   defence profile (default t6_boss)
##   --dummy-roll=<s>           dodge roll every <s> seconds (Wind Dancer upkeep), then step back
## Row: clear_time = window, dps_est = measured average DPS, notes = dummy:...
const TrainingDummy = preload("res://scripts/entities/training_dummy.gd")
const TrainingRules = preload("res://scripts/core/training_rules.gd")

func run(bot, ctrl, main, ch) -> Dictionary:
	var spec := str(bot.A["dummy"])
	var dist := float(spec.get_slice(":", 0))
	var secs := 30.0 if spec.get_slice_count(":") < 2 else float(spec.get_slice(":", 1))
	var roll_every := float(bot.A.get("dummy_roll", "0"))
	main.go_hub(false)
	await bot.get_tree().physics_frame
	var lv = Game.level
	var p = lv.player
	Game.training_in_tests = true
	var cfg: Dictionary = TrainingLog.cfg()
	var cell: Array = cfg.get("spawn_cell", [18, 18])
	var dpos: Vector2 = lv.cell_center(Vector2i(int(cell[0]), int(cell[1])))
	# a stand point at `dist` with open floor and line of sight (8 directions, first that fits)
	var stand := Vector2.INF
	for i in 8:
		var dir := Vector2.RIGHT.rotated(PI / 4.0 * i)
		var sp: Vector2 = dpos + dir * dist
		var ok: bool = not lv.is_solid(sp) and lv.has_los(sp, dpos)
		for k in range(1, 5):
			if lv.is_solid(dpos + dir * dist * k / 4.0 + Vector2(0, 6)) or lv.is_solid(dpos + dir * dist * k / 4.0 - Vector2(0, 6)):
				ok = false
		if ok:
			stand = sp
			break
	if stand == Vector2.INF:
		push_error("dummy: no open stand point at %.0f" % dist)
		return {"error": "no stand point"}
	var prof: Dictionary = cfg.get("profiles", {}).get(str(bot.A.get("dummy_profile", "t6_boss")), {})
	var defence := TrainingRules.profile_defence(prof, Data.dungeon_list, Data.enemies, ch.level)
	TrainingLog.settings = TrainingRules.sanitize_settings(cfg, {"type": "single", "duration": 30, "counting": "all", "profile": "none", "spacing": "tight"})
	TrainingLog.begin(1)
	TrainingLog.run["duration"] = secs
	var d = TrainingDummy.new()
	d.level = lv
	d.setup_dummy(1, 1, defence)
	d.position = dpos
	lv.enemies.append(d)
	lv.entity_layer.add_child(d)
	lv.training_active = true
	p.global_position = stand
	ctrl.begin(lv, p)
	var t := 0.0
	var next_roll := roll_every
	var rolls := 0
	var res := {}
	while t < secs + 20.0:
		await bot.get_tree().physics_frame
		var dt: float = bot.get_physics_process_delta_time()
		t += dt
		ctrl.t += dt
		if p.dodge_t <= 0.0 and p.dash_t <= 0.0:
			p.global_position = stand
			p.velocity = Vector2.ZERO
		ctrl.target = d
		ctrl.target_pick_t = ctrl.t + 10.0
		ctrl._set_move(Vector2.ZERO)
		p.life = p.max_life
		if roll_every > 0.0 and t >= next_roll and p.dodge_cd <= 0 and p.dodge_t <= 0 and p.busy <= 0:
			next_roll = t + roll_every
			p.aim_pos = stand + (stand - dpos).normalized().orthogonal() * 40.0
			p.start_dodge()
			rolls += 1
			continue
		if p.busy <= 0 and p.dash_t <= 0 and p.dodge_t <= 0:
			ctrl._pick_skill()
			if ctrl.want_skill >= 0:
				var sk: Dictionary = p.skill_in_slot(ctrl.want_skill)
				p.auto_aim_override = ctrl.want_aim
				if p.try_use_slot(ctrl.want_skill):
					var su: Dictionary = ctrl.st["skill_uses"]
					su[sk["id"]] = int(su.get(sk["id"], 0)) + 1
				ctrl.want_skill = -1
		if not TrainingLog.last_result.is_empty():
			res = TrainingLog.last_result
			break
	ctrl.end()
	lv.training_remove()
	Game.training_in_tests = false
	if res.is_empty():
		return {"error": "no result (no hit landed?)"}
	var su2 := []
	for k in ctrl.st["skill_uses"]:
		su2.append("%s:%d" % [k, ctrl.st["skill_uses"][k]])
	var bd := []
	for r in res.get("breakdown", []).slice(0, 4):
		bd.append("%s=%d%%" % [str(r.get("key", "?")).get_slice("|", 1), int(round(float(r.get("share", 0.0))))])
	return {"dps": float(res["avg_dps"]), "secs": secs, "dist": dist, "rolls": rolls, "hits": int(res["hits"]),
		"crit": float(res["crit_rate"]), "avg_hit": float(res["avg_hit"]), "skill_uses": "|".join(su2), "breakdown": "+".join(bd),
		"wind": p.has_buff("wind_dance")}
