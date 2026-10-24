extends Node
## Autoplay balance bot: plays full dungeon runs with a simple AI and reports
## clear time, deaths, levels and loot. Not a unit test - a balance probe.
##   godot --headless --path . res://tests/bot.tscn -- <class> <runs>

const MainScript = preload("res://scripts/main.gd")

var main = null
var cls := "warrior"
var runs := 2
var path_cache := {}
var target = null
var repath_t := 0.0
var dist_map := PackedInt32Array()
var dist_origin := Vector2i(-99, -99)
var dungeon := "forgotten_depths"
var start_level := 0

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		cls = a[0]
	if a.size() > 1:
		runs = int(a[1])
	if a.size() > 2:
		dungeon = a[2]
	if a.size() > 3:
		start_level = int(a[3])
	Game.testing = true
	Engine.physics_ticks_per_second = 240
	Engine.time_scale = 4.0
	main = MainScript.new()
	add_child(main)
	await get_tree().process_frame
	Game.new_character(cls)
	var ch = Game.ch
	if start_level > 0:
		_gear_up(ch, start_level)
	main.start_game()
	for r in runs:
		_auto_skills(ch)
		main.enter_dungeon(dungeon, 1000 + r)
		await get_tree().physics_frame
		var t0 := Time.get_ticks_msec()
		var res: Dictionary = await play_run()
		var secs := (Time.get_ticks_msec() - t0) / 1000.0 * Engine.time_scale
		print("RUN %d %s: result=%s  game_time=%.0fs  level=%d  kills=%d  deaths=%d  items_in_bag=%d  life=%d/%d" % [r, cls, res["result"], secs, ch.level, res["kills"], ch.progress.get("deaths", 0), 40 - ch.bag_free_count(), int(res["life"]), int(ch.final["max_life"])])
		# spend passive points along the class's first cluster and equip upgrades
		_spend_points(ch)
		_equip_best(ch)
		if res["result"] == "died":
			main.ui.panels["death"]._return()
		else:
			main.go_hub(true)
		await get_tree().physics_frame
	get_tree().quit()

func _gear_up(ch, lvl: int) -> void:
	ch.level = lvl
	ch.progress["highest_tier"] = 6
	ch.refresh_unlocks(false)
	for slot in ch.EQUIP_SLOTS:
		var want: String = "ring" if slot.begins_with("ring") else slot
		for i in 400:
			var it: Dictionary = Loot.roll_item(lvl, 0, cls, "rare")
			if it["slot"] != want or ch.equip_restriction(it) != "" or it.get("two_handed", false) and cls == "warrior":
				continue
			if slot == "off_hand" and ch.equipment.get("main_hand") != null and ch.equipment["main_hand"].get("two_handed", false) and it.get("category") != "quiver":
				break
			it["uid"] = ch.take_uid()
			ch.equipment[slot] = it
			break
	ch.recalc()
	_spend_points(ch)
	print("geared L%d: life %d, armour %d, evasion %d, skill avg %d" % [lvl, ch.final["max_life"], ch.final["armour"], ch.final["evasion"], int(Combat.packet_average(Combat.player_packet(ch, Data.skills[ch.loadout[0]])))])

func _objective_goal(lv, p):
	## returns [position, interactable or null] for the nearest unfinished objective
	var best = null
	var bd := INF
	for it in lv.interactables:
		var k: String = it["kind"]
		if k.begins_with("mechanism_") or k.begins_with("relic_") or k == "altar":
			var d: float = p.global_position.distance_to(it["pos"])
			if d < bd:
				bd = d
				best = it
	if lv.guardian != null and is_instance_valid(lv.guardian) and lv.guardian.alive:
		var dg: float = p.global_position.distance_to(lv.guardian.global_position)
		if dg < bd:
			return [lv.guardian.global_position, null]
	if best != null:
		return [best["pos"], best]
	return null

func _auto_skills(ch) -> void:
	# put unlocked damaging skills on the bar
	var i := 0
	for s in Data.skills_for_class(ch.class_id):
		if ch.unlocked_skills.has(s["id"]) and i < 5:
			ch.loadout[i] = s["id"]
			i += 1

func _spend_points(ch) -> void:
	var guard := 0
	while ch.available_passive_points() > 0 and guard < 50:
		guard += 1
		var best := ""
		for n in Data.passive_list:
			if ch.can_allocate(n["id"]) == "" and n["type"] != "keystone":
				best = n["id"]
				break
		if best == "":
			break
		ch.allocate(best)

func _equip_best(ch) -> void:
	for i in ch.inventory.size():
		var it = ch.inventory[i]
		if it == null or ch.equip_restriction(it) != "":
			continue
		var slot: String = ch.slot_for(it)
		var cur = ch.equipment.get(slot)
		if cur == null or Data.rarity_index(it["rarity"]) * 10 + int(it["ilvl"]) > Data.rarity_index(cur["rarity"]) * 10 + int(cur["ilvl"]):
			if it.get("two_handed", false) and ch.class_id == "warrior":
				continue
			ch.equip_from_bag(i)
	# sell the rest
	for i in ch.inventory.size():
		if ch.inventory[i] != null:
			ch.gold += Loot.sell_value(ch.inventory[i])
			ch.inventory[i] = null

func play_run() -> Dictionary:
	var lv = Game.level
	var p = lv.player
	var elapsed := 0.0
	var kills0: int = lv.kills
	var stuck_t := 0.0
	var last_pos: Vector2 = p.global_position
	while elapsed < 900.0:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		elapsed += dt
		if not p.alive:
			print("  died to %s, in boss room: %s, boss life %s" % [p.last_hit_by, lv.current_room == lv.layout["boss"], str(int(lv.boss.life)) + "/" + str(int(lv.boss.max_life)) if lv.boss != null and is_instance_valid(lv.boss) else "-"])
			return {"result": "died", "kills": lv.kills - kills0, "life": 0}
		if lv.boss_dead:
			return {"result": "cleared", "kills": lv.kills - kills0, "life": p.life}
		# pick up loot nearby
		for n in lv.loot.duplicate():
			if is_instance_valid(n) and n.kind == "item" and n.global_position.distance_to(p.global_position) < 40:
				lv.pickup(n)
		# flasks
		if p.life < p.max_life * 0.45 and Game.ch.flask_charges[0] >= 1:
			p.use_flask(0)
		if p.mana < 10 and Game.ch.flask_charges[1] >= 1:
			p.use_flask(1)
		repath_t -= dt
		if repath_t <= 0 or target == null or not is_instance_valid(target) or not target.alive:
			repath_t = 0.5
			target = _choose_target(lv, p)
		var goal: Vector2
		var near_enemy: bool = target != null and is_instance_valid(target) and target.global_position.distance_to(p.global_position) < 220
		var og = null
		if lv.sealed_cells.size() > 0 and not lv.wave_state.get("active", false):
			og = _objective_goal(lv, p)
		if og != null and not near_enemy:
			goal = og[0]
			target = null
			if og[1] != null and p.global_position.distance_to(goal) < 26:
				lv.on_interact(og[1])
			elif lv.guardian != null and is_instance_valid(lv.guardian) and goal == lv.guardian.global_position:
				target = lv.guardian
		elif target != null and is_instance_valid(target):
			goal = target.global_position
		else:
			var br: Dictionary = lv.rooms[lv.layout["boss"]]
			goal = lv.cell_center(br["anchor"])
		var d: float = p.global_position.distance_to(goal)
		var ranged: bool = cls != "warrior"
		var want := 110.0 if ranged else 18.0
		var los: bool = lv.has_los(p.global_position, goal)
		var move := Vector2.ZERO
		if target != null and los and d < want + 40:
			# fight
			p.auto_aim_override = goal + Vector2(0, -4)
			_use_best_skill(p)
			if ranged and d < 60:
				move = (p.global_position - goal).normalized()
		else:
			p.auto_aim_override = null
			move = _step_toward(lv, p.global_position, goal)
		_set_move(move)
		stuck_t += dt
		if stuck_t > 3.0:
			if p.global_position.distance_to(last_pos) < 8 and target != null:
				target = null
				repath_t = 0
				p.start_dodge()
			stuck_t = 0
			last_pos = p.global_position
	var alive := 0
	for e in lv.enemies:
		if is_instance_valid(e) and e.alive:
			alive += 1
	print("  objectives: ", lv.objective_text().replace("\n", " | "))
	print("  timeout: enemies left=%d target=%s dist=%s player_cell=%s boss_spawned=%s" % [alive, target.display_name if target != null and is_instance_valid(target) else "none", str(target.global_position.distance_to(p.global_position)) if target != null and is_instance_valid(target) else "-", str(lv.to_cell(p.global_position)), lv.boss_spawned])
	if target != null and is_instance_valid(target):
		print("  target cell=%s solid=%s los=%s state=%s" % [str(lv.to_cell(target.global_position)), lv.is_solid(target.global_position), lv.has_los(p.global_position, target.global_position), target.state])
	return {"result": "timeout", "kills": lv.kills - kills0, "life": p.life}

func _choose_target(lv, p):
	var best = null
	var bd := INF
	for e in lv.enemies:
		if is_instance_valid(e) and e.alive:
			var d: float = e.global_position.distance_to(p.global_position)
			if d > 330 and not e.is_boss and not lv.wave_state.get("alive", []).has(e):
				continue
			if e.is_boss:
				d *= 0.5
			if d < bd:
				bd = d
				best = e
	return best

func _use_best_skill(p) -> void:
	if p.busy > 0:
		return
	# try higher slots first (bigger skills), fall back to primary
	for i in [4, 3, 2, 1, 0]:
		var sk: Dictionary = p.skill_in_slot(i)
		if sk.is_empty():
			continue
		if sk.get("behavior") in ["blink", "dash"]:
			continue
		if sk.get("behavior") == "summon" and p.minions.size() >= 4:
			continue
		if sk.get("behavior") == "buff" and p.has_buff(sk["id"]):
			continue
		if sk.get("behavior") == "deploy" and p.deployables.size() >= 3 and sk.get("deployable") == "mine":
			continue
		if p.use_block_reason(sk) == "" and p.try_use_slot(i):
			return

func _set_move(v: Vector2) -> void:
	for a in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(a)
	if v.x < -0.3:
		Input.action_press("move_left")
	if v.x > 0.3:
		Input.action_press("move_right")
	if v.y < -0.3:
		Input.action_press("move_up")
	if v.y > 0.3:
		Input.action_press("move_down")

func _step_toward(lv, from: Vector2, goal: Vector2) -> Vector2:
	var gc: Vector2i = lv.to_cell(goal)
	if gc != dist_origin:
		_bfs(lv, gc)
	var c: Vector2i = lv.to_cell(from)
	var best := _dist(lv, c)
	var bestc := c
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var n := c + Vector2i(dx, dy)
			var v := _dist(lv, n)
			if v < 0:
				continue
			if dx != 0 and dy != 0 and (lv.cell(c.x + dx, c.y) != 1 or lv.cell(c.x, c.y + dy) != 1):
				continue
			if v < best or best < 0:
				best = v
				bestc = n
	if bestc == c:
		return (goal - from).normalized()
	return (lv.cell_center(bestc) - from).normalized()

func _dist(lv, c: Vector2i) -> int:
	if c.x < 0 or c.y < 0 or c.x >= lv.gw or c.y >= lv.gh:
		return -1
	return dist_map[c.y * lv.gw + c.x]

func _bfs(lv, origin: Vector2i) -> void:
	dist_origin = origin
	dist_map.resize(lv.gw * lv.gh)
	dist_map.fill(-1)
	if lv.cell(origin.x, origin.y) != 1:
		return
	var q := [origin]
	dist_map[origin.y * lv.gw + origin.x] = 0
	var h := 0
	while h < q.size():
		var c: Vector2i = q[h]
		h += 1
		var d: int = dist_map[c.y * lv.gw + c.x]
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + o
			if n.x < 0 or n.y < 0 or n.x >= lv.gw or n.y >= lv.gh:
				continue
			var i: int = n.y * lv.gw + n.x
			if lv.grid[i] == 1 and dist_map[i] < 0:
				dist_map[i] = d + 1
				q.append(n)
