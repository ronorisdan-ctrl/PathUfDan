extends RefCounted
## Threat perception for the smart bot.
## Reads ONLY what a player can see on screen: ground telegraphs (aoe.gd), enemy and
## boss wind-ups (state/attack_dir/state_t, drawn as arcs/lines), charges and dashes in
## progress, projectiles in flight and hazard warnings. Nothing hidden (future pattern
## choice, RNG) is read. Each threat gets ONE perception roll when it first appears on
## screen (awareness, mistake rate) and becomes actionable after the reaction delay.
##
## Geometry kinds:
##   circle {c, r, t0}           hit if |pos - c| <= r at time t0
##   arc    {c, r, dir, cos, t0} hit if inside radius and the attack cone at t0
##   line   {a, dir, len, hw, t0, t1} hit if within hw of the segment during [t0, t1]
##   proj   {q, v, hitr, rem}     moving projectile, hit if it passes within hitr
##   soft   {c, r, w}             lingering damage area (miasma) / visible trap: avoid when cheap

const AoEScript = preload("res://scripts/entities/aoe.gd")
const HazardScript = preload("res://scripts/entities/hazard.gd")
const ProjScript = preload("res://scripts/entities/projectile.gd")

const PR := 5.0                  # player collision radius
const VIEW := Vector2(330, 190)  # half screen at zoom 2 (1280x720) plus a little
const HORIZON := 1.6             # seconds of look-ahead for hard threats

var prof := {}
var rng: RandomNumberGenerator
var now := 0.0
var reg := {}            # key -> threat dict (all threats, perceived or not)
var active := []         # threats the bot will act on this tick
var serial := {}         # enemy id -> windup serial
var last_state := {}     # enemy id -> last state
var counters := {"seen": 0, "perceived": 0, "ignored_mistake": 0}

func setup(profile: Dictionary, r: RandomNumberGenerator) -> void:
	prof = profile
	rng = r

func reset() -> void:
	reg.clear()
	active.clear()
	serial.clear()
	last_state.clear()

# ------------------------------------------------------------------ scanning
func _in_view(pp: Vector2, q: Vector2) -> bool:
	var d := q - pp
	return absf(d.x) <= VIEW.x and absf(d.y) <= VIEW.y

func _register(key, th: Dictionary, pp: Vector2, anchor: Vector2) -> void:
	var old = reg.get(key)
	if old == null:
		th["first"] = now
		th["rolled"] = false
		th["perceived"] = false
		reg[key] = th
		old = th
	else:
		# keep perception state, refresh geometry
		for k in th:
			old[k] = th[k]
	old["last"] = now
	if not old["rolled"] and _in_view(pp, anchor):
		old["rolled"] = true
		old["seen_at"] = now
		counters["seen"] += 1
		var aw := float(prof.get("awareness", 1.0))
		if old.get("kind", "") == "proj":
			aw = aw * aw          # projectiles are harder to track than ground telegraphs
		var perceived := rng.randf() < aw
		if perceived and rng.randf() < float(prof.get("mistake_rate", 0.0)):
			perceived = false
			counters["ignored_mistake"] += 1
		old["perceived"] = perceived
		if perceived:
			counters["perceived"] += 1

func scan(lv, p, t_now: float) -> void:
	now = t_now
	var pp: Vector2 = p.global_position
	# ground telegraphs and hazards
	for c in lv.floor_layer.get_children():
		var s = c.get_script()
		if s == AoEScript:
			if c.faction != "enemy" or c.done:
				continue
			var t0: float = now + maxf(0.0, c.delay - c.t)
			_register(c.get_instance_id(), {"kind": "circle", "c": c.global_position, "r": c.radius, "t0": t0, "t1": t0,
				"w": _weight(c.source), "label": _label_for(c.source, "aoe"), "node": c}, pp, c.global_position)
		elif s == HazardScript:
			_scan_hazard(c, pp)
	# enemy and boss wind-ups / charges / dashes
	for e in lv.enemies:
		if not is_instance_valid(e) or not e.alive:
			continue
		_scan_enemy(e, pp)
	# projectiles
	for c in lv.projectile_layer.get_children():
		if c.get_script() != ProjScript or c.faction != "enemy":
			continue
		var q: Vector2 = c.global_position
		if q.distance_to(pp) > 320:
			continue
		_register(c.get_instance_id(), {"kind": "proj", "q": q, "v": c.vel, "hitr": c.radius + PR + 2.0,
			"rem": maxf(0.0, c.max_dist - c.traveled), "t0": now, "t1": now + 1.5, "w": _weight(c.source),
			"label": _label_for(c.source, "projectile"), "node": c}, pp, q)
	# drop stale entries and build the actionable list
	var react: float = float(prof.get("reaction_ms", 300.0)) / 1000.0
	active.clear()
	for k in reg.keys():
		var th: Dictionary = reg[k]
		if now - float(th.get("last", now)) > 0.05 and now > float(th.get("t1", 0.0)) + 1.0:
			reg.erase(k)
			continue
		if float(th.get("last", -1.0)) < now - 0.001:
			continue    # not present this tick (resolved)
		if th["perceived"] and now - float(th.get("seen_at", now)) >= react:
			active.append(th)

func _scan_hazard(h, pp: Vector2) -> void:
	var key = h.get_instance_id()
	var c: Vector2 = h.global_position
	match h.kind:
		"miasma":
			_register(key, {"kind": "soft", "c": c, "r": h.radius + PR, "w": 0.6, "t0": now, "t1": now + 10.0, "label": "hazard:miasma", "node": h}, pp, c)
		_:
			if h.phase == "warn":
				var t0: float = now + maxf(0.0, h.warn - h.t)
				_register(key, {"kind": "circle", "c": c, "r": h.radius + PR, "t0": t0, "t1": t0, "w": 1.0, "label": "hazard:" + h.kind, "node": h}, pp, c)
			elif h.kind == "spikes":
				# visible spike plate: soft avoid while idle
				_register(key, {"kind": "soft", "c": c, "r": h.radius + PR, "w": 0.15, "t0": now, "t1": now + 10.0, "label": "hazard:spikes", "node": h}, pp, c)

func _scan_enemy(e, pp: Vector2) -> void:
	var id: int = e.get_instance_id()
	var st: String = e.state
	if st == "windup" and last_state.get(id, "") != "windup":
		serial[id] = int(serial.get(id, 0)) + 1
	last_state[id] = st
	var key := "e%d_%d" % [id, int(serial.get(id, 0))]
	var pos: Vector2 = e.global_position
	var asm: float = maxf(0.05, e.attack_speed_mult)
	var w := _weight(e)
	if e.is_boss:
		if e.charge_t > 0:
			var spd := float(e.current.get("speed", 420))
			_register(key, {"kind": "line", "a": pos, "dir": e.attack_dir, "len": spd * e.charge_t + 8.0, "hw": e.radius + PR + 4.0,
				"t0": now, "t1": now + e.charge_t, "w": w, "label": _label_for(e, "charge")}, pp, pos)
			return
		if st != "windup" or e.attack_kind != "pattern":
			return
		var t0: float = now + maxf(0.0, e.state_t) / asm
		match e.current.get("type", ""):
			"cleave":
				var arc := deg_to_rad(float(e.current.get("arc", 140))) / 2.0 + 0.15
				_register(key, {"kind": "arc", "c": pos, "r": float(e.current.get("radius", 46)) + PR, "dir": e.attack_dir, "cos": cos(arc),
					"t0": t0, "t1": t0, "w": w, "label": _label_for(e, "cleave")}, pp, pos)
			"charge":
				var spd2 := float(e.current.get("speed", 420))
				_register(key, {"kind": "line", "a": pos, "dir": e.attack_dir, "len": spd2 * 0.45, "hw": e.radius + PR + 4.0,
					"t0": t0, "t1": t0 + 0.45, "w": w, "label": _label_for(e, "charge")}, pp, pos)
		return
	# normal enemies
	if e.dash_t > 0:
		var ds := float(e.def.get("dash_speed", 350))
		_register(key, {"kind": "line", "a": pos, "dir": e.attack_dir, "len": ds * e.dash_t + 6.0, "hw": e.radius + PR + 5.0,
			"t0": now, "t1": now + e.dash_t, "w": w, "label": _label_for(e, "dash")}, pp, pos)
		return
	if st != "windup":
		return
	var t1: float = now + maxf(0.0, e.state_t) / asm
	match e.attack_kind:
		"melee":
			_register(key, {"kind": "arc", "c": pos, "r": float(e.def.get("attack_range", 16)) + PR + 6.0, "dir": e.attack_dir, "cos": 0.2,
				"t0": t1, "t1": t1, "w": w, "label": _label_for(e, "melee")}, pp, pos)
		"dash":
			var rng_d := float(e.def.get("attack_range", 100))
			var ds2 := float(e.def.get("dash_speed", 350))
			_register(key, {"kind": "line", "a": pos, "dir": e.attack_dir, "len": rng_d, "hw": e.radius + PR + 5.0,
				"t0": t1, "t1": t1 + rng_d / ds2, "w": w, "label": _label_for(e, "dash")}, pp, pos)

func _weight(src) -> float:
	if src == null or not is_instance_valid(src):
		return 1.0
	if "is_boss" in src and src.is_boss:
		return 2.0
	if "is_elite" in src and src.is_elite:
		return 1.5
	return 1.0

func pattern_name(b) -> String:
	if b == null or not is_instance_valid(b) or not ("patterns" in b):
		return ""
	for n in b.patterns:
		if b.patterns[n] == b.current:
			return n
	return ""

func _label_for(src, what: String) -> String:
	if src == null:
		return "hazard:" + what
	if not is_instance_valid(src):
		return "death_explosion"
	var nm: String = src.display_name if "display_name" in src else "?"
	if "is_boss" in src and src.is_boss:
		var pn := pattern_name(src)
		return "%s:%s" % [nm, pn if pn != "" else what]
	if "is_elite" in src and src.is_elite and not src.is_miniboss:
		nm = "%s (elite)" % nm
	return "%s:%s" % [nm, what]

# ------------------------------------------------------------------ evaluation
## A plan: {start, dir, reach, speed, roll, busy, mm, inv}
## Returns {hard, soft, keys}
func plan_pos(pl: Dictionary, tau: float) -> Vector2:
	var s := 0.0
	if pl["roll"]:
		s = minf(85.0, tau / 0.24 * 85.0)
		if tau > 0.24:
			s += (tau - 0.24) * float(pl["speed"])
	else:
		var b: float = pl["busy"]
		var spd: float = pl["speed"]
		if tau <= b:
			s = tau * spd * float(pl["mm"])
		else:
			s = b * spd * float(pl["mm"]) + (tau - b) * spd
	return pl["start"] + pl["dir"] * minf(s, float(pl["reach"]))

func _invuln(pl: Dictionary, tau: float) -> bool:
	if tau < float(pl["inv"]):
		return true
	return pl["roll"] and tau < 0.24

func _inside(th: Dictionary, pos: Vector2, margin: float) -> bool:
	match th["kind"]:
		"circle", "soft":
			return pos.distance_to(th["c"]) <= float(th["r"]) + margin
		"arc":
			var to: Vector2 = pos - th["c"]
			var l := to.length()
			if l > float(th["r"]) + margin:
				return false
			if l < 6.0:
				return true
			return to.normalized().dot(th["dir"]) > float(th["cos"]) - margin * 0.01
		"line":
			var a: Vector2 = th["a"]
			var b: Vector2 = a + th["dir"] * float(th["len"])
			var seg := b - a
			var tt := clampf((pos - a).dot(seg) / maxf(seg.length_squared(), 0.01), 0.0, 1.0)
			return pos.distance_to(a + seg * tt) <= float(th["hw"]) + margin
	return false

func evaluate(pl: Dictionary, margin: float, list: Array = []) -> Dictionary:
	var hard := 0.0
	var soft := 0.0
	var keys := []
	var src: Array = active if list.is_empty() else list
	for th in src:
		var k: String = th["kind"]
		if k == "soft":
			if _inside(th, plan_pos(pl, 0.25), 0.0) or _inside(th, plan_pos(pl, 0.6), 0.0):
				soft += float(th["w"])
			continue
		if k == "proj":
			var q: Vector2 = th["q"]
			var v: Vector2 = th["v"]
			var sp := v.length()
			var rem: float = th["rem"]
			var tau := 0.0
			while tau <= 1.0 and tau * sp <= rem:
				if not _invuln(pl, tau):
					var pp := plan_pos(pl, tau) + Vector2(0, -4)
					if pp.distance_to(q + v * tau) <= float(th["hitr"]) + margin * 0.5:
						hard += float(th["w"]) * 0.7
						keys.append(th)
						break
				tau += 0.05
			continue
		var t0: float = float(th["t0"]) - now
		var t1: float = float(th["t1"]) - now
		if t1 < -0.02 or t0 > HORIZON:
			continue
		var samples := [maxf(t0, 0.0)]
		if k == "line":
			samples = [maxf(t0, 0.0), maxf((t0 + t1) * 0.5, 0.0), maxf(t1, 0.0)]
		for tau in samples:
			if _invuln(pl, tau):
				continue
			if _inside(th, plan_pos(pl, tau), margin):
				hard += float(th["w"])
				keys.append(th)
				break
	return {"hard": hard, "soft": soft, "keys": keys}

# ------------------------------------------------------------------ attribution
## Called from Events.player_damaged: which visible attack just hit the player?
func attribute(p, t_now: float) -> Dictionary:
	var pp: Vector2 = p.global_position
	var best = null
	var best_s := INF
	for key in reg:
		var th: Dictionary = reg[key]
		var s := INF
		match th["kind"]:
			"proj":
				var n = th.get("node")
				if n != null and is_instance_valid(n):
					var d: float = n.global_position.distance_to(pp + Vector2(0, -4))
					if d <= float(th["hitr"]) + 8.0:
						s = d * 0.01
			"circle":
				if absf(float(th["t0"]) - t_now) <= 0.12 and _inside(th, pp, 3.0):
					s = 0.5 + absf(float(th["t0"]) - t_now)
			"arc":
				if absf(float(th["t0"]) - t_now) <= 0.12 and _inside(th, pp, 4.0):
					s = 0.6 + absf(float(th["t0"]) - t_now)
			"line":
				if t_now >= float(th["t0"]) - 0.12 and t_now <= float(th["t1"]) + 0.12 and _inside(th, pp, 6.0):
					s = 0.7
		if s < best_s:
			best_s = s
			best = th
	if best == null:
		return {}
	return best
