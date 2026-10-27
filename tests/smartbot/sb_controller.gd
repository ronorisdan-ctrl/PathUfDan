extends RefCounted
## In-dungeon controller of the smart bot. Layers (each can be switched off):
##   perception  sb_threat.gd: what is on screen, after reaction time / awareness / mistakes
##   avoidance   move out of telegraphs, dodge-roll when walking is not enough (--no-dodge)
##   combat      target priority, class spacing (melee closes in, ranged kites), skill choice
##   survival    flasks, retreat / re-engage
##   objectives  guardian, mechanisms, relics, blood altar waves, boss arena, loot
## Input goes through the real input actions (move_* with analog strength, start_dodge,
## try_use_slot, use_flask) exactly as the player's key handlers call them.

const Threat = preload("res://tests/smartbot/sb_threat.gd")
const Hub = preload("res://tests/smartbot/sb_hub.gd")

## Judgement shared by every avoiding profile: hits expected to cost less than TANK_FRAC of
## max life (after armour / resistances) are taken rather than giving up attack time, and
## the dodge roll (with its cooldown) is kept for hits worth at least ROLL_FRAC.
const TANK_FRAC := 0.05
const ROLL_FRAC := 0.08

var bot = null
var hub = null
var prof := {}
var flags := {}
var rng: RandomNumberGenerator
var threat = Threat.new()

var lv = null
var p = null
var ch = null
var ranged := false
var t := 0.0
var think_t := 0.0
var target = null
var target_pick_t := 0.0
var desired := Vector2.ZERO
var want_skill := -1
var want_aim := Vector2.ZERO
var dist_map := PackedInt32Array()
var dist_origin := Vector2i(-999, -999)
var bfs_t := 0.0
var retreat_until := -1.0
var retreat_cd := 0.0
var stuck_t := 0.0
var last_pos := Vector2.ZERO
var unstick_until := -1.0
var unstick_dir := Vector2.ZERO
var ignore := {}
var dmg_cache := {}
var dmg_cache_t := -10.0
var evaded := {}
var flask_t := -10.0
var pending_level := false
var loot_mode := false
var st := {}
var last_dmg_t := -10.0
var last_cause := ""
var last_cause_src := ""
var melee_reach := 26.0
var goal_kind := ""
var prog_target_id := 0
var prog_life := 0.0
var prog_t := 0.0
var approach_until := -1.0
var goal_loot_id := 0

func setup(b, h, profile: Dictionary, fl: Dictionary, r: RandomNumberGenerator) -> void:
	bot = b
	hub = h
	prof = profile
	flags = fl
	rng = r
	threat.setup(prof, rng)

func begin(level, player) -> void:
	lv = level
	p = player
	ch = player.ch
	ranged = ch.class_id != "warrior"
	t = 0.0
	think_t = 0.0
	target_pick_t = 0.0
	unstick_until = -1.0
	unstick_dir = Vector2.ZERO
	flask_t = -10.0
	dmg_cache_t = -10.0
	pending_level = false
	goal_kind = ""
	goal_loot_id = 0
	prog_target_id = 0
	approach_until = -1.0
	target = null
	desired = Vector2.ZERO
	want_skill = -1
	dist_origin = Vector2i(-999, -999)
	dist_map = PackedInt32Array()
	bfs_t = 0.0
	retreat_until = -1.0
	retreat_cd = 0.0
	stuck_t = 0.0
	last_pos = p.global_position
	ignore.clear()
	dmg_cache.clear()
	evaded.clear()
	loot_mode = false
	threat.reset()
	threat.counters = {"seen": 0, "perceived": 0, "ignored_mistake": 0}
	st = {"damage_taken": 0.0, "hits_taken": 0, "dodge_attempts": 0, "dodge_rolls": 0, "hits_avoided": 0, "evade_failed": 0,
		"potions": 0, "mana_potions": 0, "skill_uses": {}, "pickups": 0, "mid_equips": 0, "dmg_by": {}, "retreats": 0,
		"levelups": 0, "objectives": 0}
	last_dmg_t = -10.0
	last_cause = ""
	if not Events.player_damaged.is_connected(_on_damaged):
		Events.player_damaged.connect(_on_damaged)
	if not Events.player_leveled.is_connected(_on_level):
		Events.player_leveled.connect(_on_level)
	_update_reach()

func end() -> void:
	if Events.player_damaged.is_connected(_on_damaged):
		Events.player_damaged.disconnect(_on_damaged)
	if Events.player_leveled.is_connected(_on_level):
		Events.player_leveled.disconnect(_on_level)
	_set_move(Vector2.ZERO)
	_finish_evaded(true)

func _update_reach() -> void:
	melee_reach = 26.0
	if ranged:
		return
	var sk: Dictionary = ch.resolved_skill(ch.loadout[0])
	if sk.get("behavior", "") == "melee_arc":
		var area: float = sqrt(ch.final.get("area_mult", 1.0)) if sk.get("tags", []).has("area") else 1.0
		melee_reach = float(sk.get("range", 30)) * area

# ================================================================== events
func _on_damaged(amount: float) -> void:
	if p == null or not is_instance_valid(p):
		return
	st["damage_taken"] += amount
	if amount <= 0:
		return
	st["hits_taken"] += 1
	var th: Dictionary = threat.attribute(p, t)
	var label := ""
	if not th.is_empty():
		label = th.get("label", "")
		var key = th.get("key")
		if evaded.has(key):
			if not evaded[key]["hit"]:
				bot.trace("EVADE_FAIL %s dmg %.0f (life %.0f/%.0f)" % [th.get("label", "?"), amount, p.life, p.max_life])
			evaded[key]["hit"] = true
	if label == "":
		label = ("%s:contact" % p.last_hit_by) if p.last_hit_by != "" else "unknown"
		if bot.A.has("debug"):
			var info := ""
			for e in lv.enemies:
				if _valid(e) and e.is_boss:
					info = "boss %s st=%s t=%.2f kind=%s pat=%s charge=%.2f d=%.0f" % [e.display_name, e.state, e.state_t, e.attack_kind, str(e.current.get("type", "")), e.charge_t, e.global_position.distance_to(p.global_position)]
			bot.trace("CONTACT %s dmg %.0f | %s | threats %d" % [label, amount, info, threat.reg.size()])
	last_cause = label
	last_dmg_t = t
	var db: Dictionary = st["dmg_by"]
	db[label] = float(db.get(label, 0.0)) + amount

func _on_level(_l) -> void:
	pending_level = true

func death_cause() -> String:
	if t - last_dmg_t > 0.6 and p != null and is_instance_valid(p):
		for s in ["ignite", "bleed", "poison", "agony"]:
			if p.statuses.has(s):
				return "status:" + s
	return last_cause if last_cause != "" else "unknown"

func _finish_evaded(all: bool) -> void:
	for k in evaded.keys():
		var e: Dictionary = evaded[k]
		if all or t > float(e["exp"]):
			if e["hit"]:
				st["evade_failed"] += 1
			else:
				st["hits_avoided"] += 1
			evaded.erase(k)

# ================================================================== main tick
func tick(dt: float) -> void:
	t += dt
	if not p.alive:
		return
	if pending_level:
		pending_level = false
		st["levelups"] += 1
		hub.on_level_up(ch)
		if _can_change_skills():
			hub.choose_hotbar(ch)
			_update_reach()
	threat.scan(lv, p, t)
	_finish_evaded(false)
	think_t -= dt
	if think_t <= 0:
		think_t = float(prof["decision_ms"]) / 1000.0 * rng.randf_range(0.8, 1.2)
		_think()
	var mv := desired
	if t < unstick_until:
		mv = unstick_dir
	var roll := false
	var evading := false
	if prof["avoid_threats"] and not flags.get("no_dodge", false):
		var r := _evade(mv)
		mv = r["dir"]
		roll = r["roll"]
		evading = r["evading"]
	_set_move(mv)
	if roll:
		p.start_dodge()
		st["dodge_rolls"] += 1
		return
	var fleeing: bool = t < retreat_until and not ranged
	if not fleeing and p.busy <= 0 and p.dash_t <= 0 and p.dodge_t <= 0:
		_pick_skill()
		if want_skill >= 0:
			var sk: Dictionary = p.skill_in_slot(want_skill)
			# while stepping out of a telegraph, only cast if the slower walk (casting slows
			# movement) still gets clear in time - i.e. use the attack window between telegraphs
			if evading and not _safe_to_cast(sk, mv):
				want_skill = -1
		if want_skill >= 0:
			var sk: Dictionary = p.skill_in_slot(want_skill)
			p.auto_aim_override = want_aim
			if p.try_use_slot(want_skill):
				var su: Dictionary = st["skill_uses"]
				su[sk["id"]] = int(su.get(sk["id"], 0)) + 1
			want_skill = -1
	_stuck(dt)
	if bot.A.has("debug2"):
		var ee := ""
		for e in lv.enemies:
			if is_instance_valid(e) and e.alive and e.global_position.distance_to(p.global_position) < 200:
				ee += "%s@%.1f,%.1f;" % [e.display_name.substr(0, 4), e.global_position.x, e.global_position.y]
		bot.trace("D2 %s life=%.2f crng=%d lrng=%d %s" % [str(p.global_position), p.life, Combat.rng.state, Loot.rng.state, ee])
	if bot.A.has("debug") and int(t * 60.0) % 300 == 0:
		bot.trace("DBG t=%.1f pos=%s desired=%s goal=%s target=%s sealed=%d interactables=%s" % [t, str(lv.to_cell(p.global_position)), str(desired), goal_kind, target.display_name if _valid(target) else "-", lv.sealed_cells.size(), str(lv.interactables.map(func(i): return i["kind"]))])
		var ws = lv.get("wave_state")
		if typeof(ws) == TYPE_DICTIONARY and ws.get("active", false):
			var wl := ""
			var lost: Dictionary = ws.get("lost", {})
			for we in ws.get("alive", []):
				if is_instance_valid(we) and we.alive:
					var wc: Vector2i = lv.to_cell(we.global_position)
					wl += "%s@%s solid=%s flow=%d lost=%.1f st=%s; " % [we.display_name.substr(0, 6), str(wc), lv.is_solid(we.global_position), lv.flow_value(wc) if lv.has_method("flow_value") else -9, float(lost.get(we.get_instance_id(), 0.0)), we.state]
			bot.trace("   WAVES wave=%d/%d altar=%s d_altar=%.0f pflow=%d :: %s" % [int(ws.get("wave", 0)), int(ws.get("total", 0)), str(lv.to_cell(ws["pos"])), p.global_position.distance_to(ws["pos"]), lv.flow_value(lv.to_cell(p.global_position)) if lv.has_method("flow_value") else -9, wl])
		if _valid(target):
			var sk0: Dictionary = p.skill_in_slot(0)
			bot.trace("   d=%.0f los=%s tcell=%s solid=%s block0=%s val0=%s uses=%s busy=%.2f state=%s" % [target.global_position.distance_to(p.global_position), lv.has_los(p.global_position, target.global_position), str(lv.to_cell(target.global_position)), lv.is_solid(target.global_position), p.use_block_reason(sk0), str(_skill_value(sk0)), str(st["skill_uses"]), p.busy, target.state])

func _can_change_skills() -> bool:
	## skills_panel.can_change(): no aggressive enemy within 320 px
	for e in lv.enemies:
		if is_instance_valid(e) and e.alive and e.aggro and e.global_position.distance_to(p.global_position) < 320:
			return false
	return true

# ================================================================== thinking
func _think() -> void:
	_flasks()
	_choose_target()
	desired = _movement()

func _flasks() -> void:
	var lf: float = p.life / maxf(1.0, p.max_life)
	var disc: float = prof["potion_discipline"]
	var thr := 0.30 + 0.20 * disc
	if t - flask_t > 0.6 and ch.flask_charges[0] >= 1.0:
		var dots: bool = p.has_status("ignite") or p.has_status("bleed")
		if lf < thr or (disc >= 0.9 and dots and lf < 0.7):
			p.use_flask(0)
			flask_t = t
			st["potions"] += 1
	var mm: float = ch.final.get("max_mana", 0.0)
	if mm > 0 and p.mana < mm * 0.15 and ch.flask_charges[1] >= 1.0 and target != null and t - flask_t > 0.3:
		p.use_flask(1)
		flask_t = t
		st["mana_potions"] += 1
	# retreat when low and out of flasks
	if lf < 0.3 and ch.flask_charges[0] < 1.0 and t > retreat_cd:
		retreat_until = t + 5.0
		retreat_cd = t + 14.0
		st["retreats"] += 1
		bot.trace("RETREAT life %.0f%%" % (lf * 100))
	if t < retreat_until and lf > 0.6:
		retreat_until = t

func _valid(e) -> bool:
	return e != null and is_instance_valid(e) and e.alive and not (("burrowed" in e) and e.burrowed)

func _candidates() -> Array:
	var out := []
	var pp: Vector2 = p.global_position
	var wave: Array = lv.wave_state.get("alive", []) if "wave_state" in lv else []
	for e in lv.enemies:
		if not _valid(e) or ignore.get(e.get_instance_id(), -1.0) > t:
			continue
		var d: float = e.global_position.distance_to(pp)
		var seen: bool = d < 330 and lv.has_los(pp, e.global_position)
		if seen or (e.aggro and d < 460) or e.is_boss or wave.has(e) or (e == target and d < 520):
			out.append(e)
	return out

func _priority(e) -> float:
	## Higher is better. Melee: what is in reach first (walking costs time and draws the
	## pack), finish wounded enemies in reach, back-liners only when nothing is on us.
	## Ranged: distance matters less, casters / summoners / wounded first.
	var d: float = e.global_position.distance_to(p.global_position)
	var s := -d / (40.0 if not ranged else 120.0)
	var b = lv.boss if "boss" in lv else null
	if e.is_boss:
		s += 0.8
		if e.warded:
			s -= 3.0
	if b != null and is_instance_valid(b) and b.warded and b.ward_adds.has(e):
		s += 4.0
	var atk: String = e.def.get("attack", "")
	var bonus_ok := true
	if not ranged:
		bonus_ok = d < 160.0
		if bonus_ok:
			for o in lv.enemies:
				if _valid(o) and o != e and o.global_position.distance_to(p.global_position) < 70.0:
					bonus_ok = false
					break
	if bonus_ok and atk in ["ranged", "summoner", "nova"]:
		s += 0.8
	if bonus_ok and atk == "summoner":
		s += 0.4
	if e.is_elite and ranged:
		s += 0.2
	var wounded: float = 1.0 - e.life / maxf(1.0, e.max_life)
	if ranged or d < melee_reach + e.radius + 20.0:
		s += wounded * 0.8
	if "guardian" in lv and e == lv.guardian:
		s += 0.5
	if not lv.has_los(p.global_position, e.global_position):
		s -= 1.0
	return s

func _choose_target() -> void:
	if _valid(target) and t < target_pick_t:
		return
	target_pick_t = t + 0.5
	var c := _candidates()
	if c.is_empty():
		target = null
		return
	var best = null
	if rng.randf() < float(prof["target_quality"]):
		var bv := -INF
		for e in c:
			var v := _priority(e) + (0.5 if e == target else 0.0)
			if v > bv:
				bv = v
				best = e
	else:
		var bd := INF
		for e in c:
			var d: float = e.global_position.distance_to(p.global_position)
			if d < bd:
				bd = d
				best = e
	target = best

# ================================================================== movement
func _movement() -> Vector2:
	var pp: Vector2 = p.global_position
	goal_kind = "none"
	goal_loot_id = 0
	if t < retreat_until:
		return _away_dir(240.0)
	if loot_mode:
		var g0 = _loot_goal(400.0)
		return _path_dir(g0) if g0 != null else Vector2.ZERO
	if _valid(target):
		var tp: Vector2 = target.global_position
		var d := pp.distance_to(tp)
		var los: bool = lv.has_los(pp, tp)
		goal_kind = "target"
		# attacking but the target is not losing life (shots hit a wall corner, it out-heals us):
		# step in closer for a moment, give up on it after a while
		if target.get_instance_id() != prog_target_id or target.life < prog_life - 0.5:
			prog_target_id = target.get_instance_id()
			prog_life = target.life
			prog_t = t
		elif t - prog_t > 10.0 and not target.is_boss:
			ignore[prog_target_id] = t + 8.0
			prog_target_id = 0     # fresh progress clock when this target comes back
			bot.trace("NO PROGRESS on %s, switching target" % target.display_name)
			target = null
			return Vector2.ZERO
		elif t - prog_t > 4.0 and t > approach_until + 2.0:
			approach_until = t + 1.5
		if t < approach_until:
			return _path_dir(tp) if d > 30.0 else Vector2.ZERO
		if ranged:
			var pos: float = prof["positioning"]
			var lo := lerpf(70.0, 120.0, pos)
			var hi := 210.0
			var close := false
			var my_speed: float = ch.final.get("move_speed", 100.0) * p.speed_mult()
			for e in lv.enemies:
				if not _valid(e) or e.def.get("attack", "") in ["ranged", "summoner"]:
					continue
				if e.speed * e.speed_mult() >= my_speed * 0.95:
					continue     # cannot out-run it: stand and fight instead of backing off forever
				# keep out of the enemy's own reach (slams and explosions reach further than swings)
				var er := float(e.def.get("attack_range", 16)) + float(e.def.get("slam_radius", 0)) + 12.0
				if e.global_position.distance_to(pp) < maxf(lerpf(40.0, 60.0, pos), er):
					close = true
					break
			if not los or d > hi:
				return _path_dir(tp)
			var tgt_faster: bool = target.speed * target.speed_mult() >= ch.final.get("move_speed", 100.0) * p.speed_mult() * 0.95 and not target.def.get("attack", "") in ["ranged", "summoner"]
			if (d < lo and not tgt_faster) or close:
				return _away_dir(140.0)
			return Vector2.ZERO
		var reach: float = melee_reach * lerpf(0.75, 0.95, prof["positioning"]) + target.radius
		if d > reach or not los:
			return _path_dir(tp)
		# surrounded: work to the edge of the pack instead of fighting in its middle
		var close_n: int = lv.hostiles_in_radius(pp, 45.0, "player").size()
		if close_n >= 3 and p.life < p.max_life * lerpf(0.5, 0.8, prof["positioning"]):
			return _away_dir(90.0)
		return Vector2.ZERO
	var g = _goal()
	if g == null:
		return Vector2.ZERO
	return _path_dir(g)

func _away_dir(radius: float) -> Vector2:
	var pp: Vector2 = p.global_position
	var flee := Vector2.ZERO
	for e in lv.enemies:
		if not _valid(e):
			continue
		var off: Vector2 = pp - e.global_position
		var d := off.length()
		if d < radius and d > 0.1:
			flee += off / (d * d) * (3.0 if e.is_boss else 1.0)
	if flee.length() < 0.0001:
		return Vector2.ZERO
	var want := flee.normalized()
	var best := Vector2.ZERO
	var bs := -INF
	for i in 16:
		var dir := Vector2.RIGHT.rotated(TAU * i / 16.0)
		var reach: float = lv.clamp_to_floor(pp, pp + dir * 60.0).distance_to(pp)
		var s: float = dir.dot(want) + reach / 60.0 * 1.2
		if s > bs:
			bs = s
			best = dir
	return best

func _goal():
	var pp: Vector2 = p.global_position
	# objectives that unseal the boss arena
	if lv.sealed_cells.size() > 0 and not lv.wave_state.get("active", false):
		var og = _objective_goal()
		if og != null:
			return og
	# Blood Altar running: go back to the remaining wave enemies (the objective text shows
	# the wave is not over; the arena stays sealed until they are dead)
	if lv.sealed_cells.size() > 0 and lv.wave_state.get("active", false):
		var wbest = null
		var wd := INF
		for we in lv.wave_state.get("alive", []):
			if _valid(we):
				var dd: float = pp.distance_to(we.global_position)
				if dd < wd:
					wd = dd
					wbest = we
		if wbest != null:
			goal_kind = "waves"
			return wbest.global_position
	var lg = _loot_goal(160.0)
	if lg != null:
		return lg
	if lv.boss_dead:
		return null
	var br: Dictionary = lv.rooms[lv.layout["boss"]]
	goal_kind = "boss_room"
	return lv.cell_center(br["anchor"])

func _objective_goal():
	var pp: Vector2 = p.global_position
	var best = null
	var bd := INF
	for it in lv.interactables:
		var k: String = it["kind"]
		if k.begins_with("mechanism_") or k.begins_with("relic_") or k == "altar":
			var d: float = pp.distance_to(it["pos"])
			if d < bd:
				bd = d
				best = it
	if lv.guardian != null and is_instance_valid(lv.guardian) and lv.guardian.alive:
		var dg: float = pp.distance_to(lv.guardian.global_position)
		if dg < bd:
			target = lv.guardian
			return lv.guardian.global_position
	if best == null:
		return null
	goal_kind = "objective:" + best["kind"]
	if bd < 24.0 and not best["kind"].begins_with("relic_"):
		lv.on_interact(best)     # what pressing F (level.interact) does for the nearest interactable
		st["objectives"] += 1
		bot.trace("OBJECTIVE %s" % best["kind"])
	return best["pos"]

func _loot_goal(radius: float):
	var pp: Vector2 = p.global_position
	for e in lv.enemies:
		if _valid(e) and e.aggro and e.global_position.distance_to(pp) < 200 and lv.has_los(pp, e.global_position):
			return null
	var best = null
	var bd := radius
	for n in lv.loot:
		if not is_instance_valid(n) or n.picked:
			continue
		if n.kind == "item" and ch.free_bag_slot() < 0:
			continue
		if ignore.get(n.get_instance_id(), -1.0) > t:
			continue
		var d: float = n.global_position.distance_to(pp)
		if d < bd and not lv.is_solid(n.global_position):
			bd = d
			best = n
	if best == null:
		return null
	goal_kind = "loot:" + best.kind
	goal_loot_id = best.get_instance_id()
	if best.kind == "item" and bd < 28.0:
		if lv.pickup(best):     # level.interact() picks up the nearest item the same way
			st["pickups"] += 1
			var n: int = hub.equip_best(ch, 0.03, true)
			if n > 0:
				st["mid_equips"] += n
				bot.trace("MIDRUN equip %d item(s): %s" % [n, best.item.get("name", "")])
				_update_reach()
		return null
	return best.global_position

func loot_left() -> bool:
	return _loot_goal(400.0) != null

func _path_dir(goal: Vector2) -> Vector2:
	var pp: Vector2 = p.global_position
	if pp.distance_to(goal) < 56.0 and lv.has_los(pp, goal):
		return (goal - pp).normalized()
	var gc: Vector2i = lv.to_cell(goal)
	if gc != dist_origin and (t >= bfs_t or dist_map.size() != lv.gw * lv.gh):
		_bfs(gc)
		bfs_t = t + 0.25
	var c: Vector2i = lv.to_cell(pp)
	var best := _dist(c)
	if best < 0 and gc == dist_origin and goal_kind == "target" and _valid(target) and not target.is_boss:
		ignore[target.get_instance_id()] = t + 8.0     # unreachable from here
		prog_target_id = 0
		bot.trace("UNREACHABLE target %s at %s" % [target.display_name, str(gc)])
		st["unreachable"] = int(st.get("unreachable", 0)) + 1
		target = null
	var bestc := c
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var n := c + Vector2i(dx, dy)
			var v := _dist(n)
			if v < 0:
				continue
			if dx != 0 and dy != 0 and (lv.cell(c.x + dx, c.y) != 1 or lv.cell(c.x, c.y + dy) != 1):
				continue
			if v < best or best < 0:
				best = v
				bestc = n
	if bestc == c:
		if best != 0 and gc != dist_origin:
			_bfs(gc)       # stale map (goal moved): recompute now
			bfs_t = t + 0.25
			return _path_dir(goal)
		return (goal - pp).normalized()
	return (lv.cell_center(bestc) - pp).normalized()

func _dist(c: Vector2i) -> int:
	if c.x < 0 or c.y < 0 or c.x >= lv.gw or c.y >= lv.gh or dist_map.size() != lv.gw * lv.gh:
		return -1
	return dist_map[c.y * lv.gw + c.x]

func _bfs(origin: Vector2i) -> void:
	dist_origin = origin
	dist_map.resize(lv.gw * lv.gh)
	dist_map.fill(-1)
	if lv.cell(origin.x, origin.y) != 1:
		# goal stands in a wall cell (knocked back / large sprite): use the nearest floor cell
		var bestc := Vector2i(-1, -1)
		var bd := 1 << 30
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				if lv.cell(origin.x + dx, origin.y + dy) == 1 and dx * dx + dy * dy < bd:
					bd = dx * dx + dy * dy
					bestc = origin + Vector2i(dx, dy)
		if bestc.x < 0:
			return
		origin = bestc
	var q := [origin]
	dist_map[origin.y * lv.gw + origin.x] = 0
	var h := 0
	var gw: int = lv.gw
	var gh: int = lv.gh
	while h < q.size():
		var c: Vector2i = q[h]
		h += 1
		var d: int = dist_map[c.y * gw + c.x]
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + o
			if n.x < 0 or n.y < 0 or n.x >= gw or n.y >= gh:
				continue
			var i: int = n.y * gw + n.x
			if lv.grid[i] == 1 and dist_map[i] < 0:
				dist_map[i] = d + 1
				q.append(n)

func _stuck(dt: float) -> void:
	stuck_t += dt
	if stuck_t < 2.5:
		return
	stuck_t = 0.0
	var moved: float = p.global_position.distance_to(last_pos)
	last_pos = p.global_position
	var fighting: bool = _valid(target) and target.global_position.distance_to(p.global_position) < 110.0 and lv.has_los(p.global_position, target.global_position)
	if moved < 24.0 and desired.length() > 0.1 and t > unstick_until and not fighting:
		bot.trace("STUCK at %s, sidestepping (target %s, goal %s)" % [str(lv.to_cell(p.global_position)), target.display_name if _valid(target) else "-", goal_kind])
		if goal_loot_id != 0:
			ignore[goal_loot_id] = t + 30.0
		var ne = null
		var nd := INF
		for e in lv.enemies:
			if is_instance_valid(e) and e.alive and e.global_position.distance_to(p.global_position) < nd:
				nd = e.global_position.distance_to(p.global_position)
				ne = e
		if bot.A.has("debug"):
			var c0: Vector2i = lv.to_cell(p.global_position)
			bot.trace("   pos %s vel %s dodge_cd %.2f busy %.2f dist_here %d origin %s boss %s gw %d gh %d up_grid %d" % [str(p.global_position), str(p.velocity), p.dodge_cd, p.busy, _dist(c0), str(dist_origin), str(lv.rooms[lv.layout["boss"]]["anchor"]), lv.gw, lv.gh, lv.grid[(c0.y - 1) * lv.gw + c0.x]])
			for yy in range(-3, 4):
				var row := ""
				for xx in range(-4, 5):
					var v := _dist(c0 + Vector2i(xx, yy))
					row += ("  ##" if lv.cell(c0.x + xx, c0.y + yy) != 1 else "%4d" % v)
				bot.trace("   " + row)
		if ne != null:
			bot.trace("   nearest %s d=%.0f state=%s aggro=%s los=%s; active threats %d; desired %s" % [ne.display_name, nd, ne.state, ne.aggro, lv.has_los(p.global_position, ne.global_position), threat.active.size(), str(desired)])
		if _valid(target) and not target.is_boss:
			ignore[target.get_instance_id()] = t + 20.0
			prog_target_id = 0
			target = null
		dist_origin = Vector2i(-999, -999)
		unstick_dir = Vector2.RIGHT.rotated(rng.randf() * TAU)
		unstick_until = t + 0.6

func _set_move(v: Vector2) -> void:
	for a in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(a)
	if v.length() < 0.01:
		return
	v = v.normalized()
	if v.x < -0.001:
		Input.action_press("move_left", -v.x)
	elif v.x > 0.001:
		Input.action_press("move_right", v.x)
	if v.y < -0.001:
		Input.action_press("move_up", -v.y)
	elif v.y > 0.001:
		Input.action_press("move_down", v.y)

# ================================================================== avoidance
func _plan(base: Dictionary, dir: Vector2, roll: bool) -> Dictionary:
	var pl := base.duplicate()
	pl["dir"] = dir
	pl["roll"] = roll
	if dir == Vector2.ZERO:
		pl["reach"] = 0.0
	else:
		var maxd: float = (85.0 + float(base["speed"]) * 0.8) if roll else float(base["speed"]) * 1.2
		var start: Vector2 = base["start"]
		var reach: float = lv.clamp_to_floor(start, start + dir * maxd).distance_to(start)
		# enemy bodies block the player (CharacterBody2D collision): stop in front of them
		for b in base.get("bodies", []):
			var to: Vector2 = b[0] - start
			var proj := to.dot(dir)
			if proj <= 0.0:
				continue
			var perp2 := to.length_squared() - proj * proj
			var rr: float = b[1]
			if perp2 >= rr * rr:
				continue
			var enter := proj - sqrt(rr * rr - perp2)
			if enter < reach:
				reach = maxf(0.0, enter - 1.0)
		pl["reach"] = reach
	return pl

func _evade(want: Vector2) -> Dictionary:
	var none := {"dir": want, "roll": false, "evading": false}
	if threat.active.is_empty():
		return none
	var spd: float = ch.final.get("move_speed", 100.0) * p.speed_mult()
	if spd <= 1.0 or p.dash_t > 0:
		return none
	var margin: float = prof["safety_margin"]
	var base := {"start": p.global_position, "dir": Vector2.ZERO, "reach": 0.0, "speed": spd, "roll": false,
		"busy": maxf(0.0, p.busy), "mm": p.current_move_mult, "inv": maxf(maxf(p.dodge_t, p.invuln_t), 0.0),
		"bodies": _bodies()}
	var wn := want.normalized() if want.length() > 0.01 else Vector2.ZERO
	var pw := _plan(base, wn, false)
	var dw: Dictionary = threat.evaluate(pw, margin)
	if dw["hard"] <= 0.0 and dw["soft"] <= 0.0:
		return none
	if dw["soft"] <= 0.0 and dw["dmg"] < TANK_FRAC:
		return none      # a light hit (< 5% of life after mitigation): keep attacking and take it
	var best := pw
	var best_ev := dw
	var best_c := _cost(pw, dw, wn)
	var dirs := [Vector2.ZERO]
	for i in 16:
		dirs.append(Vector2.RIGHT.rotated(TAU * i / 16.0))
	var soft_only: bool = dw["hard"] <= 0.0
	for d in dirs:
		if soft_only and (wn == Vector2.ZERO or d.dot(wn) < 0.6):
			continue     # lingering ground effects: only small detours that keep making progress
		var pl := _plan(base, d, false)
		var ev: Dictionary = threat.evaluate(pl, margin)
		var c := _cost(pl, ev, wn)
		if c < best_c:
			best_c = c
			best = pl
			best_ev = ev
	if best_ev["hard"] > 0.0 and best_ev["dmg"] >= ROLL_FRAC and prof["use_roll"] and p.dodge_cd <= 0 and p.dodge_t <= 0 and p.speed_mult() > 0:
		for i in 16:
			var d2 := Vector2.RIGHT.rotated(TAU * i / 16.0)
			var pl2 := _plan(base, d2, true)
			var ev2: Dictionary = threat.evaluate(pl2, margin)
			var c2 := _cost(pl2, ev2, wn) + (3.0 if best_ev["hard"] <= 0.0 else 0.5)
			if c2 < best_c:
				best_c = c2
				best = pl2
				best_ev = ev2
	var hard: bool = dw["hard"] > 0.0
	if hard and float(dw["dmg"]) < 0.15 and best_ev["dmg"] > float(dw["dmg"]) * 0.6 and best_ev["soft"] <= dw["soft"]:
		return none      # no escape saves much: keep fighting instead of dancing in place
	if hard and (best["dir"] != wn or best["roll"]):
		for th in dw["keys"]:
			var k = th["key"]
			if not evaded.has(k):
				evaded[k] = {"exp": float(th.get("t1", t)) + 0.4, "hit": false}
				st["dodge_attempts"] += 1
				bot.trace("DODGE %s %s (hit in %.2fs) -> %s" % ["roll" if best["roll"] else "move", th.get("label", "?"), maxf(0.0, float(th.get("t0", t)) - t), "safe" if best_ev["hard"] <= 0.0 else "partial"])
	return {"dir": best["dir"], "roll": best["roll"], "evading": hard}

func _bodies() -> Array:
	var out := []
	var pp: Vector2 = p.global_position
	for e in lv.enemies:
		if is_instance_valid(e) and e.alive and e.collision_layer != 0 and e.global_position.distance_to(pp) < 140.0:
			out.append([e.global_position, float(e.radius) + 5.0 + 0.5])
	return out

func _safe_to_cast(sk: Dictionary, mv: Vector2) -> bool:
	if sk.get("behavior", "") in ["dash", "leap", "blink"]:
		return false
	var spd: float = ch.final.get("move_speed", 100.0) * p.speed_mult()
	var base := {"start": p.global_position, "dir": Vector2.ZERO, "reach": 0.0, "speed": spd, "roll": false,
		"busy": p.use_time_for(sk), "mm": float(sk.get("move_mult", 0.45)), "inv": maxf(maxf(p.dodge_t, p.invuln_t), 0.0),
		"bodies": _bodies()}
	var pl := _plan(base, mv.normalized() if mv.length() > 0.01 else Vector2.ZERO, false)
	return threat.evaluate(pl, float(prof["safety_margin"]))["hard"] <= 0.0

func _cost(pl: Dictionary, ev: Dictionary, wn: Vector2) -> float:
	var c: float = ev["hard"] * 100.0 + ev["soft"] * 1.5
	var d: Vector2 = pl["dir"]
	if wn == Vector2.ZERO:
		c += 0.0 if d == Vector2.ZERO else 0.25
	else:
		c += (1.0 - d.dot(wn)) * 0.6 if d != Vector2.ZERO else 0.7
	return c

# ================================================================== skills
func _avg(sk: Dictionary) -> float:
	if t - dmg_cache_t > 2.0:
		dmg_cache.clear()
		dmg_cache_t = t
	var id: String = sk["id"]
	if not dmg_cache.has(id):
		if sk.has("weapon_eff") or sk.has("base_damage"):
			dmg_cache[id] = Combat.packet_average(Combat.player_packet(ch, sk, p.damage_more(sk)))
		else:
			dmg_cache[id] = 0.0
	return dmg_cache[id]

func _group_count(group: String) -> int:
	var n := 0
	for d in p.deployables:
		if is_instance_valid(d) and d.get_meta("group", "") == group:
			n += 1
	return n

func _aim_at(e, sk: Dictionary) -> Vector2:
	var tp: Vector2 = e.global_position + Vector2(0, -4)
	if prof["lead_targets"] and sk.get("behavior", "") == "projectile":
		var spd := float(sk.get("speed", 300))
		var d: float = p.global_position.distance_to(tp)
		tp += e.velocity * (d / maxf(60.0, spd))
	return tp

func _pick_skill() -> void:
	want_skill = -1
	var opts := []
	for i in ch.HOTBAR_SIZE:
		var sk: Dictionary = p.skill_in_slot(i)
		if sk.is_empty() or p.use_block_reason(sk) != "":
			continue
		var r := _skill_value(sk)
		if r[0] > 0.0:
			opts.append([r[0], i, r[1]])
	if opts.is_empty():
		return
	var pick = null
	if rng.randf() < float(prof["skill_quality"]):
		for o in opts:
			if pick == null or o[0] > pick[0]:
				pick = o
	else:
		pick = opts[rng.randi() % opts.size()]
	want_skill = pick[1]
	want_aim = pick[2]

func _skill_value(sk: Dictionary) -> Array:
	var r := Hub.role(sk)
	var id: String = sk["id"]
	var pp: Vector2 = p.global_position
	var lf: float = p.life / maxf(1.0, p.max_life)
	var area: float = sqrt(ch.final.get("area_mult", 1.0))
	if not _valid(target):
		# out of combat: keep minions up
		if r == "summon":
			var lim := int(sk.get("max", 3)) + int(ch.final.get("minion_limit", 0))
			if p.minions.size() < lim:
				return [100.0, pp + Vector2(20, 0)]
		return [0.0, pp]
	var tp: Vector2 = target.global_position
	var d := pp.distance_to(tp)
	var los: bool = lv.has_los(pp + Vector2(0, -5), tp + Vector2(0, -4)) and lv.has_los(pp, tp)
	var near: int = lv.hostiles_in_radius(pp, 120.0, "player").size()
	var big: bool = target.is_boss or target.is_elite
	var engaged := d < 260.0
	var aim := _aim_at(target, sk)
	match r:
		"buff_off":
			if p.has_buff(id) or not engaged or not (big or near >= 3):
				return [0.0, aim]
			return [5000.0, aim]
		"buff_def":
			if p.has_buff(id):
				return [0.0, aim]
			if sk.has("heal_pct"):
				return [4600.0 if lf < 0.4 else 0.0, aim]
			# defensive cooldowns are used in real fights, not saved for emergencies only
			if engaged and (lf < 0.6 or big or near >= 2):
				return [4500.0, aim]
			return [0.0, aim]
		"warcry":
			var rad := float(sk.get("radius", 110)) * area
			if near >= 2 or (big and d < rad):
				return [4800.0, aim]
			return [0.0, aim]
		"summon":
			var lim2 := int(sk.get("max", 3)) + int(ch.final.get("minion_limit", 0))
			if p.minions.size() >= lim2:
				return [0.0, aim]
			# in combat a summon competes with damage skills: minion damage over an expected
			# lifetime per second of casting (fragile summons are not recast endlessly)
			var mdef: Dictionary = Data.summons.get(sk.get("minion", ""), {})
			var mavg: float = Combat.packet_average(Combat.minion_packet(ch, mdef, ch.skill_level(id)))
			var life_est := 6.0
			if float(sk.get("minion_duration", -1.0)) > 0:
				life_est = float(sk["minion_duration"])
			var cnt2 := mini(int(sk.get("count", 1)), lim2 - p.minions.size())
			var vs: float = mavg / maxf(0.3, float(mdef.get("attack_time", 1.0))) * life_est * cnt2 / maxf(0.1, p.use_time_for(sk))
			if p.minions.is_empty():
				vs *= 1.5     # something to soak hits
			return [vs, pp + Vector2(20, 0)]
		"turret":
			var lim3 := maxi(1, int(sk.get("max", 2)) + int(ch.final.get("turret_limit", 0)))
			if engaged and _group_count("turret") < lim3:
				return [3800.0, pp + (tp - pp).limit_length(60.0)]
			return [0.0, aim]
		"trap":
			if d <= float(sk.get("max_range", 160)) and _group_count(id) < int(sk.get("max", 3)):
				return [1500.0 + _avg(sk), tp]
			return [0.0, aim]
		"curse":
			var has: bool = target.has_status("frailty") or target.has_status("marked")
			if not has and d <= float(sk.get("max_range", 280)) and (big or near >= 3):
				return [3500.0, tp]
			return [0.0, aim]
		"zone_util":
			if d <= float(sk.get("max_range", 260)) and (big or near >= 3) and _group_count("zone_" + id) == 0:
				return [2500.0, tp]
			return [0.0, aim]
		"mobility":
			var b: String = sk.get("behavior", "")
			if ranged or b == "blink":
				return [0.0, aim]
			var mr := float(sk.get("max_range", sk.get("distance", 130)))
			if d > 110.0 and d <= mr and los and lf > 0.5:
				return [3000.0 + _avg(sk), tp]
			return [0.0, aim]
	# damage skills
	var avg := _avg(sk)
	if avg <= 0.0:
		return [0.0, aim]
	var b2: String = sk.get("behavior", "")
	var hits := 0.0
	match b2:
		"melee_arc":
			var rng_m := float(sk.get("range", 30)) * (area if sk.get("tags", []).has("area") else 1.0)
			if d > rng_m + target.radius:
				return [0.0, aim]
			hits = lv.enemies_in_cone(pp + Vector2(0, -4), (tp - pp).normalized(), rng_m, float(sk.get("arc", 120))).size()
		"projectile":
			if d > float(sk.get("max_range", 300)) * 0.9 or not los:
				return [0.0, aim]
			hits = 1.0
			var cnt := int(sk.get("count", 1)) + int(ch.final.get("projectile_count", 0))
			if cnt > 1:
				hits += minf(cnt - 1, lv.hostiles_in_radius(tp, 50.0, "player").size() - 1) * 0.6
			if float(sk.get("explode_radius", 0)) > 0:
				hits = maxf(hits, lv.hostiles_in_radius(tp, float(sk["explode_radius"]) * area, "player").size())
			if int(sk.get("pierce", 0)) + int(ch.final.get("pierce", 0)) > 0:
				hits += 0.3 * (lv.hostiles_in_radius(tp, 60.0, "player").size() - 1)
		"ground_aoe":
			var rad2 := float(sk.get("radius", 40)) * area
			if sk.get("at_self", false):
				if d > rad2 * 0.8 + target.radius:
					return [0.0, aim]
				hits = lv.hostiles_in_radius(pp, rad2, "player").size()
			else:
				if d > float(sk.get("max_range", 300)):
					return [0.0, aim]
				hits = lv.hostiles_in_radius(tp, rad2, "player").size()
				aim = tp
			hits *= float(sk.get("repeats", 1))
		"nova":
			var rad3 := float(sk.get("radius", 80)) * area
			hits = lv.hostiles_in_radius(pp, rad3 * 0.9, "player").size()
		"chain":
			if d > float(sk.get("max_range", 240)) or not los:
				return [0.0, aim]
			hits = minf(float(sk.get("chains", 3)) + 1.0, 1.0 + lv.hostiles_in_radius(tp, 110.0, "player").size() - 1)
		"beam":
			if d > float(sk.get("max_range", 220)):
				return [0.0, aim]
			hits = 1.0 + 0.3 * (lv.hostiles_in_radius(tp, 40.0, "player").size() - 1)
		"leap":
			if d > float(sk.get("max_range", 160)):
				return [0.0, aim]
			hits = lv.hostiles_in_radius(tp, float(sk.get("radius", 55)) * area, "player").size()
			aim = tp
		"zone":
			if d > float(sk.get("max_range", 260)) or _group_count("zone_" + id) >= int(sk.get("max", 2)):
				return [0.0, aim]
			for z in p.deployables:
				if is_instance_valid(z) and z.get_meta("group", "") == "zone_" + id and z.global_position.distance_to(tp) < float(sk.get("radius", 50)):
					return [0.0, aim]
			hits = lv.hostiles_in_radius(tp, float(sk.get("radius", 50)) * area, "player").size() * float(sk.get("duration", 4)) / float(sk.get("tick", 0.5)) * float(sk.get("tick_fraction", 0.35)) * 0.6
			aim = tp
		"curse":
			if d > float(sk.get("max_range", 280)) or target.has_status("agony"):
				return [0.0, aim]
			hits = lv.hostiles_in_radius(tp, float(sk.get("radius", 50)) * area, "player").size() * 2.0
			aim = tp
		_:
			hits = 1.0
	if hits <= 0.0:
		return [0.0, aim]
	var ut: float = p.use_time_for(sk)
	var v := avg * hits / maxf(0.1, ut)
	if float(sk.get("cooldown", 0)) > 0:
		v *= 1.3
	var mm: float = ch.final.get("max_mana", 0.0)
	var cost: float = p.mana_cost(sk)
	if cost > 0 and mm > 0 and p.mana - cost < mm * 0.15 and not big:
		v *= 0.3
	return [v, aim]
