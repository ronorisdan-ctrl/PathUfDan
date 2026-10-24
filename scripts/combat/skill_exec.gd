extends RefCounted
## Executes data-defined skills. Each "behavior" is a reusable template; a new
## skill is a new JSON entry that picks a behavior and sets its parameters.

const Projectile = preload("res://scripts/entities/projectile.gd")
const AoE = preload("res://scripts/entities/aoe.gd")
const VFX = preload("res://scripts/fx/vfx.gd")
const Minion = preload("res://scripts/entities/minion.gd")
const Turret = preload("res://scripts/entities/turret.gd")
const Mine = preload("res://scripts/entities/mine.gd")
const Zone = preload("res://scripts/entities/zone.gd")

const BEHAVIORS := ["melee_arc", "projectile", "ground_aoe", "nova", "chain", "dash", "blink", "summon", "deploy", "buff", "beam", "leap", "zone", "curse"]

func execute(p, sk: Dictionary, aim: Vector2) -> void:
	var lv = p.level
	if lv == null:
		return
	var origin: Vector2 = p.global_position + Vector2(0, -5)
	var dir: Vector2 = (aim - origin)
	if dir.length() < 0.01:
		dir = Vector2.RIGHT * p.facing
	dir = dir.normalized()
	var col := Color(sk.get("fx", "#ffffff"))
	match sk.get("behavior", ""):
		"melee_arc":
			var delay: float = p.current_use_time * 0.3
			p.schedule(delay, func(): _melee(p, sk, dir, col))
		"projectile":
			_projectiles(p, sk, origin, dir, col)
		"ground_aoe":
			var delay2: float = p.current_use_time * 0.3 if sk.get("at_self", false) else 0.0
			p.schedule(delay2, func(): _ground(p, sk, origin, aim, dir, col))
		"nova":
			_nova(p, sk, col)
		"chain":
			_chain(p, sk, origin, aim, dir, col)
		"dash":
			var pk: Dictionary = Combat.player_packet(p.ch, sk, p.damage_more(sk))
			p.start_dash(dir, float(sk.get("distance", 100)), float(sk.get("duration", 0.25)), pk if sk.get("damage", false) else {}, float(sk.get("radius", 16)), float(sk.get("knockback", 0)), col)
		"blink":
			var to: Vector2 = lv.clamp_to_floor(p.global_position, p.global_position + (aim - p.global_position).limit_length(float(sk.get("max_range", 150))))
			lv.add_fx(VFX.make("nova", p.global_position, col, 0.3, 18))
			p.global_position = to
			lv.add_fx(VFX.make("nova", to, col, 0.3, 22))
		"summon":
			_summon(p, sk)
		"deploy":
			_deploy(p, sk, aim)
		"buff":
			p.add_buff(sk["id"], sk.get("mods", []), float(sk.get("duration", 5)))
			lv.add_fx(VFX.make("nova", p.global_position, col, 0.4, 26))
			if sk.has("heal_pct"):
				p.heal(p.max_life * float(sk["heal_pct"]) / 100.0)
		"beam":
			_beam(p, sk, origin, dir, col)
		"leap":
			var to2: Vector2 = lv.clamp_to_floor(p.global_position, p.global_position + (aim - p.global_position).limit_length(float(sk.get("max_range", 160))))
			var dist: float = p.global_position.distance_to(to2)
			var dur := float(sk.get("duration", 0.35))
			p.start_dash((to2 - p.global_position).normalized() if dist > 1 else dir, maxf(dist, 1.0), dur, {}, 0.0, 0.0, col)
			p.invuln_t = dur
			p.schedule(dur, func(): _land(p, sk, col))
		"zone":
			_zone(p, sk, aim, col)
		"curse":
			_curse(p, sk, aim, col)
		_:
			push_warning("Unknown skill behavior: " + str(sk.get("behavior")))

func _melee(p, sk: Dictionary, dir: Vector2, col: Color) -> void:
	if not is_instance_valid(p) or not p.alive:
		return
	var lv = p.level
	var area: float = sqrt(p.ch.final.get("area_mult", 1.0)) if sk.get("tags", []).has("area") else 1.0
	var rng: float = float(sk.get("range", 30)) * area
	var arc := float(sk.get("arc", 120))
	var center: Vector2 = p.global_position + Vector2(0, -4)
	var v = VFX.make("slash", center, col, 0.22, rng)
	v.angle = dir.angle()
	v.arc = arc
	lv.add_fx(v)
	var pk: Dictionary = Combat.player_packet(p.ch, sk, p.damage_more(sk))
	var hits: Array = lv.enemies_in_cone(center, dir, rng, arc)
	for e in hits:
		Combat.deal(pk, p, e, center)
		if pk.get("knockback", 0.0) > 0 and is_instance_valid(e) and e.alive and not e.is_boss:
			e.knock += dir * pk["knockback"] * 4.0
	if hits.size() > 0:
		p.register_hit()
		lv.shake(1.0 if sk.get("weapon_eff", 100) < 200 else 2.5)
	if (p.ch.stats.has_flag("worldsplitter") or p.ch.stats.has_flag("earth_aftershock")) and sk.get("tags", []).has("slam"):
		_aftershock(p, center + dir * rng * 0.6, pk, col)

func _aftershock(p, at: Vector2, pk: Dictionary, col: Color, rad: float = 42.0, delay: float = 0.45) -> void:
	var a = AoE.new()
	a.level = p.level
	a.source = p
	var pk2 := pk.duplicate(true)
	for t in pk2["dmg"]:
		pk2["dmg"][t] = [pk2["dmg"][t][0] * 0.7, pk2["dmg"][t][1] * 0.7]
	a.packet = pk2
	a.faction = "player"
	a.radius = rad
	a.delay = delay
	a.style = "slam"
	a.color = col
	a.position = at
	p.level.floor_layer.add_child(a)

func _projectiles(p, sk: Dictionary, origin: Vector2, dir: Vector2, col: Color) -> void:
	var f: Dictionary = p.ch.final
	var sb = p.ch.stats
	var count: int = int(sk.get("count", 1)) + int(f.get("projectile_count", 0))
	var spread := deg_to_rad(float(sk.get("spread", 0)) + (10.0 * (count - 1) if int(sk.get("count", 1)) == 1 and count > 1 else 0.0))
	var spd: float = float(sk.get("speed", 300)) * maxf(0.2, 1.0 + sb.inc("projectile_speed") / 100.0)
	var pk: Dictionary = Combat.player_packet(p.ch, sk, p.damage_more(sk))
	var chain := int(sk.get("chain", 0)) + int(f.get("chain", 0))
	if sk.get("tags", []).has("lightning") and sb.has_flag("stormglass"):
		chain += 2
	if sb.has_flag("ricochet") and p.ch.weapon_groups().has("firearm") and sk.get("kind") == "attack":
		chain += 1
	for i in count:
		var a := 0.0
		if count > 1:
			a = -spread / 2.0 + spread * float(i) / float(count - 1)
		var pr = Projectile.new()
		pr.level = p.level
		pr.source = p
		pr.faction = "player"
		pr.packet = pk
		pr.kind = sk.get("proj", "arrow")
		pr.color = col
		pr.radius = float(sk.get("size", 4))
		pr.vel = dir.rotated(a) * spd
		pr.max_dist = float(sk.get("max_range", 300))
		pr.pierce = int(sk.get("pierce", 0)) + int(f.get("pierce", 0))
		pr.chain = chain
		pr.explode_radius = float(sk.get("explode_radius", 0)) * sqrt(f.get("area_mult", 1.0))
		pr.homing = float(sk.get("homing", 0.0))
		pr.pull = sk.get("pull", false)
		var jit := deg_to_rad(float(sk.get("jitter", 0.0)))
		if jit > 0:
			pr.vel = pr.vel.rotated(randf_range(-jit, jit))
		pr.position = origin + dir * 6
		p.level.projectile_layer.add_child(pr)
	p.register_hit()

func _ground(p, sk: Dictionary, origin: Vector2, aim: Vector2, dir: Vector2, col: Color) -> void:
	if not is_instance_valid(p) or not p.alive:
		return
	var lv = p.level
	var f: Dictionary = p.ch.final
	var center: Vector2
	if sk.get("at_self", false):
		center = p.global_position + dir * float(sk.get("forward", 0))
	else:
		center = lv.clamp_to_floor(p.global_position, p.global_position + (aim - p.global_position).limit_length(float(sk.get("max_range", 300))))
	var radius: float = float(sk.get("radius", 40)) * sqrt(f.get("area_mult", 1.0))
	var pk: Dictionary = Combat.player_packet(p.ch, sk, p.damage_more(sk))
	var repeats := int(sk.get("repeats", 1))
	var style := "slam"
	if sk["id"] == "meteor":
		style = "meteor"
	elif sk.get("tags", []).has("projectile"):
		style = "rain"
	for i in repeats:
		var a = AoE.new()
		a.level = lv
		a.source = p
		a.packet = pk
		a.faction = "player"
		a.radius = radius
		a.delay = float(sk.get("delay", 0)) + float(sk.get("interval", 0)) * i
		a.style = style
		a.color = col
		a.show_telegraph = a.delay > 0.05
		a.origin = p.global_position
		var sc := float(sk.get("scatter", 0))
		a.position = center + (Vector2(randf_range(-sc, sc), randf_range(-sc, sc)) if i > 0 else Vector2.ZERO)
		lv.floor_layer.add_child(a)
	if sk.get("aftershock", false):
		_aftershock(p, center, pk, col, radius, float(sk.get("delay", 0)) + 0.6)
	if sk.get("at_self", false):
		p.register_hit()
		if (p.ch.stats.has_flag("worldsplitter") or p.ch.stats.has_flag("earth_aftershock")) and sk.get("tags", []).has("slam"):
			_aftershock(p, center + dir * radius * 0.8, pk, col)

func _nova(p, sk: Dictionary, col: Color) -> void:
	var lv = p.level
	var radius: float = float(sk.get("radius", 80)) * sqrt(p.ch.final.get("area_mult", 1.0))
	lv.add_fx(VFX.make("nova", p.global_position, col, 0.4, radius))
	var targets: Array = lv.hostiles_in_radius(p.global_position, radius, "player")
	if sk.get("damage", true):
		var pk: Dictionary = Combat.player_packet(p.ch, sk, p.damage_more(sk))
		for e in targets:
			Combat.deal(pk, p, e, p.global_position)
		if targets.size() > 0:
			p.register_hit()
	else:
		var st: Dictionary = sk.get("status", {})
		if not st.is_empty():
			for e in targets:
				Combat.apply_status(e, st, {}, {"status_dur": 1.0, "dot_mult": 1.0})
	var sbuf: Dictionary = sk.get("self_buff", {})
	if not sbuf.is_empty():
		p.add_buff(sk["id"], sbuf.get("mods", []), float(sbuf.get("duration", 5)))

func _chain(p, sk: Dictionary, origin: Vector2, aim: Vector2, dir: Vector2, col: Color) -> void:
	var lv = p.level
	var maxr := float(sk.get("max_range", 240))
	var first = lv.nearest_hostile(aim, "player", 70.0, {}, false)
	if first != null and first.global_position.distance_to(p.global_position) > maxr * 1.2:
		first = null
	if first == null:
		var best = null
		var bd := INF
		for e in lv.enemies:
			if not is_instance_valid(e) or not e.alive:
				continue
			var to: Vector2 = e.global_position - p.global_position
			if to.length() < maxr and to.normalized().dot(dir) > 0.5 and lv.has_los(origin, e.global_position):
				if to.length() < bd:
					bd = to.length()
					best = e
		first = best
	if first == null:
		var v0 = VFX.make("bolt", Vector2.ZERO, col, 0.18, 10)
		v0.points = PackedVector2Array([origin, origin + dir * maxr * 0.6])
		lv.add_fx(v0)
		return
	var chains: int = int(sk.get("chains", 3)) + int(p.ch.final.get("chain", 0))
	if p.ch.stats.has_flag("stormglass"):
		chains += 2
	var pk: Dictionary = Combat.player_packet(p.ch, sk, p.damage_more(sk))
	var hit := {}
	var cur = first
	var prev_pos := origin
	var n := 0
	while cur != null and n <= chains:
		hit[cur.get_instance_id()] = true
		var v = VFX.make("bolt", Vector2.ZERO, col, 0.22, 10)
		v.points = PackedVector2Array([prev_pos, cur.global_position + Vector2(0, -6)])
		lv.add_fx(v)
		prev_pos = cur.global_position + Vector2(0, -6)
		var cpos: Vector2 = cur.global_position
		Combat.deal(pk, p, cur, origin)
		n += 1
		cur = lv.nearest_hostile(cpos, "player", float(sk.get("chain_range", 110)), hit, true)
	p.register_hit()

func _summon(p, sk: Dictionary) -> void:
	var lv = p.level
	var limit: int = int(sk.get("max", 3)) + int(p.ch.final.get("minion_limit", 0))
	if p.ch.stats.has_flag("gravetender"):
		limit += 2
	var lvl: int = p.ch.skill_level(sk["id"])
	for i in int(sk.get("count", 1)):
		while p.minions.size() >= limit and p.minions.size() > 0:
			var old = p.minions.pop_front()
			if is_instance_valid(old):
				old.die(null)
		var pos: Vector2 = lv.clamp_to_floor(p.global_position, p.global_position + Vector2.RIGHT.rotated(randf() * TAU) * 20)
		p.spawn_minion(sk.get("minion", "skeleton_warrior"), lvl, pos, sk)
		lv.add_fx(VFX.make("ring", pos, Color(sk.get("fx", "#d0d8c0")), 0.4, 14))

func _deploy(p, sk: Dictionary, aim: Vector2) -> void:
	var lv = p.level
	var kind: String = sk.get("deployable", "turret")
	var limit := int(sk.get("max", 2))
	if kind == "turret":
		limit += int(p.ch.final.get("turret_limit", 0))
		if p.ch.stats.has_flag("clockwork_choir"):
			limit += 1
		limit = maxi(1, limit)
	var group: String = kind if kind == "turret" else sk["id"]
	var mine: Array = p.deployables.filter(func(d): return is_instance_valid(d) and d.get_meta("group", "") == group)
	while mine.size() >= limit:
		var old = mine.pop_front()
		old.expire()
	var pos: Vector2 = lv.clamp_to_floor(p.global_position, p.global_position + (aim - p.global_position).limit_length(float(sk.get("max_range", 120))))
	var d
	if kind == "turret":
		d = Turret.new()
	else:
		d = Mine.new()
	d.level = lv
	d.setup(p, sk)
	d.set_meta("kind", kind)
	d.set_meta("group", group)
	d.position = pos
	p.deployables.append(d)
	if kind == "mine":
		lv.floor_layer.add_child(d)
	else:
		lv.entity_layer.add_child(d)
	lv.add_fx(VFX.make("ring", pos, Color(sk.get("fx", "#ffffff")), 0.3, 12))

func _beam(p, sk: Dictionary, origin: Vector2, dir: Vector2, col: Color) -> void:
	## instant line that hits every enemy along it (Disintegration Beam, Piercing Thrust)
	var lv = p.level
	var length := float(sk.get("max_range", 220))
	var end: Vector2 = origin
	var steps := int(length / 6.0)
	for i in range(1, steps + 1):
		var q: Vector2 = origin + dir * (i * 6.0)
		if lv.is_solid(q + Vector2(0, 5)):
			break
		end = q
	var width := float(sk.get("width", 10))
	var pk: Dictionary = Combat.player_packet(p.ch, sk, p.damage_more(sk))
	var seg := end - origin
	var hits := 0
	for e in lv.enemies.duplicate():
		if not is_instance_valid(e) or not e.alive:
			continue
		var ep: Vector2 = e.global_position + Vector2(0, -4)
		var t := clampf((ep - origin).dot(seg) / maxf(seg.length_squared(), 0.01), 0, 1)
		if ep.distance_to(origin + seg * t) <= width + e.radius:
			Combat.deal(pk, p, e, origin)
			hits += 1
	var v = VFX.make("beam", Vector2.ZERO, col, float(sk.get("fx_life", 0.12)), 10)
	v.points = PackedVector2Array([origin, end])
	v.width = width * 0.5
	lv.add_fx(v)
	if hits > 0:
		p.register_hit()

func _land(p, sk: Dictionary, col: Color) -> void:
	if not is_instance_valid(p) or not p.alive:
		return
	var lv = p.level
	var radius: float = float(sk.get("radius", 55)) * sqrt(p.ch.final.get("area_mult", 1.0))
	var pk: Dictionary = Combat.player_packet(p.ch, sk, p.damage_more(sk))
	lv.add_fx(VFX.make("nova", p.global_position, col, 0.35, radius))
	lv.shake(2.5)
	Sfx.play("explode")
	var targets: Array = lv.hostiles_in_radius(p.global_position, radius, "player")
	for e in targets:
		Combat.deal(pk, p, e, p.global_position)
		if is_instance_valid(e) and e.alive and not e.is_boss:
			e.knock += (e.global_position - p.global_position).normalized() * float(sk.get("knockback", 0)) * 4.0
	if targets.size() > 0:
		p.register_hit()
	if p.ch.stats.has_flag("earth_aftershock"):
		_aftershock(p, p.global_position, pk, col, radius * 0.8)

func _zone(p, sk: Dictionary, aim: Vector2, col: Color) -> void:
	var lv = p.level
	var center: Vector2 = p.global_position
	if not sk.get("at_self", false):
		center = lv.clamp_to_floor(p.global_position, p.global_position + (aim - p.global_position).limit_length(float(sk.get("max_range", 260))))
	var group: String = "zone_" + sk["id"]
	var mine: Array = p.deployables.filter(func(d): return is_instance_valid(d) and d.get_meta("group", "") == group)
	while mine.size() >= int(sk.get("max", 2)):
		var old = mine.pop_front()
		old.queue_free()
		p.deployables.erase(old)
	var z = Zone.new()
	z.level = lv
	z.source = p
	z.faction = "player"
	z.radius = float(sk.get("radius", 50)) * sqrt(p.ch.final.get("area_mult", 1.0))
	z.duration = float(sk.get("duration", 4.0))
	z.tick = float(sk.get("tick", 0.5))
	z.color = col
	z.style = sk.get("zone_style", "burning")
	z.owner_skill = sk["id"]
	if sk.has("base_damage") or sk.has("weapon_eff"):
		z.packet = Combat.player_packet(p.ch, sk, p.damage_more(sk))
		z.damage_per_tick = float(sk.get("tick_fraction", 0.35))
	else:
		z.damage_per_tick = 0.0
		z.packet = {"flags": p.ch.stats.flags.duplicate()}
	z.statuses = sk.get("zone_status", [])
	z.position = center
	z.set_meta("group", group)
	p.deployables.append(z)
	z.tree_exited.connect(func():
		if is_instance_valid(p):
			p.deployables.erase(z))
	lv.floor_layer.add_child(z)

func _curse(p, sk: Dictionary, aim: Vector2, col: Color) -> void:
	var lv = p.level
	var center: Vector2 = lv.clamp_to_floor(p.global_position, p.global_position + (aim - p.global_position).limit_length(float(sk.get("max_range", 260))))
	var radius: float = float(sk.get("radius", 50)) * sqrt(p.ch.final.get("area_mult", 1.0))
	lv.add_fx(VFX.make("ring", center, col, 0.5, radius))
	lv.add_fx(VFX.make("nova", center, col, 0.4, radius))
	var pk: Dictionary = Combat.player_packet(p.ch, sk, p.damage_more(sk)) if sk.has("base_damage") else {"dmg": {}, "flags": p.ch.stats.flags.duplicate()}
	var dps := Combat.packet_average(pk) if sk.has("base_damage") else 0.0
	var dur_mult: float = maxf(0.1, 1.0 + p.ch.stats.inc("status_duration") / 100.0)
	var targets: Array = lv.hostiles_in_radius(center, radius, "player")
	if sk.get("single", false):
		var best = lv.nearest_hostile(aim, "player", radius + 30.0)
		targets = [best] if best != null else []
	for e in targets:
		for st in sk.get("curse", []):
			var s2: Dictionary = st.duplicate()
			s2["dps"] = dps
			Combat.apply_status(e, s2, {}, {"status_dur": dur_mult, "dot_mult": pk.get("dot_mult", 1.0), "flags": pk.get("flags", {})})
		e.flash = 0.1
	if targets.size() > 0:
		p.register_hit()
