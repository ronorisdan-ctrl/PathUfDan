extends "res://scripts/entities/enemy.gd"
## Data-driven boss. Each boss in data/enemies.json lists named attack patterns
## (built from a reusable library below) and phases that unlock patterns at life
## thresholds. Every attack has a visible telegraph during its windup.
##
## Pattern library: cleave, charge, ring, eruption, mortar, fan, spiral, summon,
## teleport, burrow, ward, vent.

var phase := 1
var phase_idx := 0
var patterns := {}
var cds := {}
var current := {}
var decide_t := 0.6
var roar_t := 0.0
var charge_t := 0.0
var charge_hit := {}
var burrowed := false
var burrow_t := 0.0
var burrow_marked := false
var warded := false
var ward_t := 0.0
var ward_adds := []
var vent_t := 0.0
var vent_tick := 0.0
var spiral_waves := 0
var spiral_t := 0.0
var extra_summons := 0
var patterns_used := {}   # for tests / telemetry
var poise_state := {}     # boss poise (data/stun.json): poise, since_hit, immune, stagger

func _ready() -> void:
	super._ready()
	is_boss = true
	aggro = true
	patterns = def.get("patterns", {})
	poise_state = Stun.new_poise()
	extra_summons = 2 if level != null and level.enemy_run.get("boss_summons", false) else 0

func active_patterns() -> Array:
	var ph: Array = def.get("phases", [])
	if ph.is_empty():
		return patterns.keys()
	return ph[phase_idx].get("patterns", [])

func _physics_process(delta: float) -> void:
	if not alive or level == null:
		return
	if Dev.freeze_ai():
		super._physics_process(delta)   # the enemy freeze path: no patterns, charges or phases
		return
	if not Data.stun_cfg.is_empty() and not poise_state.is_empty():
		Stun.poise_tick(Data.stun_cfg, poise_state, delta)
	_check_phase()
	for k in cds.keys():
		cds[k] -= delta
	if warded:
		ward_t -= delta
		ward_adds = ward_adds.filter(func(a): return is_instance_valid(a) and a.alive)
		if ward_adds.is_empty() or ward_t <= 0:
			warded = false
			Events.message.emit("%s's ward shatters!" % display_name, Color("#ffd060"))
	if spiral_waves > 0:
		spiral_t -= delta
		if spiral_t <= 0:
			spiral_t = 0.3
			spiral_waves -= 1
			_spiral_wave(spiral_waves)
	if roar_t > 0:
		roar_t -= delta
		update_visual(delta, false)
		queue_redraw()
		return
	if charge_t > 0:
		_do_charge(delta)
		return
	if burrow_t > 0:
		_do_burrow(delta)
		return
	if vent_t > 0:
		_do_vent(delta)
		return
	super._physics_process(delta)

func _check_phase() -> void:
	var ph: Array = def.get("phases", [])
	var frac := life / max_life
	while phase_idx + 1 < ph.size() and frac <= float(ph[phase_idx + 1].get("at", 0)):
		phase_idx += 1
		phase = phase_idx + 1
		var p: Dictionary = ph[phase_idx]
		speed *= float(p.get("speed", 1.0))
		attack_speed_mult *= float(p.get("attack_speed", 1.0))
		if p.has("tint"):
			sprite.texture = Art.tinted(def.get("sprite", "warden"), Color(p["tint"]))
		roar_t = 1.0
		state = "recover"
		state_t = 0.4
		statuses.erase("stun")
		Events.message.emit(p.get("message", "%s grows enraged!" % display_name), Color("#ff6060"))
		level.add_fx(VFX.make("nova", global_position, Color(def.get("light", "#60d0c0")), 0.8, 90))
		level.shake(4.0)
		Sfx.play("boss", 0.0)
		if extra_summons > 0 or patterns.has("summon"):
			_summon_adds(def.get("summon", "ghoul"), 2 + extra_summons)

# ------------------------------------------------------------------ decision
func _chase() -> Vector2:
	if target == null or not is_instance_valid(target) or not target.alive:
		target = level.player
		if target == null or not target.alive:
			return Vector2.ZERO
	var to: Vector2 = target.global_position - global_position
	var dist := to.length()
	if dist > 0.1:
		attack_dir = to.normalized()
	decide_t -= get_physics_process_delta_time()
	if decide_t <= 0:
		decide_t = 0.35
		var pick := _choose(dist)
		if pick != "":
			_start_pattern(pick)
			return Vector2.ZERO
	if dist < 36:
		return Vector2.ZERO
	var dir := to.normalized()
	if not level.has_los(global_position, target.global_position):
		var fd: Vector2 = level.flow_dir(global_position)
		if fd != Vector2.ZERO:
			dir = fd
	return dir * speed

func _choose(dist: float) -> String:
	var total := 0.0
	var opts := []
	for n in active_patterns():
		var pd: Dictionary = patterns.get(n, {})
		if pd.is_empty() or cds.get(n, 0.0) > 0:
			continue
		var r: Array = pd.get("range", [0, 999])
		if dist < float(r[0]) or dist > float(r[1]):
			continue
		if pd.get("type") in ["summon", "ward"]:
			summons = summons.filter(func(s): return is_instance_valid(s) and s.alive)
			if summons.size() >= 6:
				continue
		opts.append(n)
		total += float(pd.get("w", 1))
	if opts.is_empty():
		return ""
	var roll := randf() * total
	for n in opts:
		roll -= float(patterns[n].get("w", 1))
		if roll <= 0:
			return n
	return opts[0]

func _start_pattern(n: String) -> void:
	current = patterns[n]
	patterns_used[n] = int(patterns_used.get(n, 0)) + 1
	attack_kind = "pattern"
	state = "windup"
	var wu := float(current.get("windup", 0.7))
	state_t = wu
	cds[n] = float(current.get("cooldown", 0.0))
	facing = signf(attack_dir.x) if absf(attack_dir.x) > 0.1 else facing
	var delay := wu / attack_speed_mult
	var mult := float(current.get("mult", 1.0))
	var col := Color(current.get("color", "#ff5030"))
	windup_aoes.clear()
	match current.get("type", ""):
		"ring":
			windup_aoes.append(_spawn_aoe(global_position, float(current.get("radius", 80)), delay, "slam", col, mult))
		"eruption":
			if _target_ok():
				for i in int(current.get("count", 3)):
					var off := Vector2(randf_range(-36, 36), randf_range(-36, 36)) if i > 0 else Vector2.ZERO
					windup_aoes.append(_spawn_aoe(level.clamp_to_floor(global_position, target.global_position + off), float(current.get("radius", 34)), delay + 0.35 * i, "slam", col, mult))
		"mortar":
			if _target_ok():
				for i in int(current.get("count", 6)):
					var c: Vector2 = target.global_position
					var off2 := Vector2(randf_range(-90, 90), randf_range(-90, 90))
					if current.get("on_player", false) and i % 3 == 0:
						off2 = Vector2(randf_range(-10, 10), randf_range(-10, 10))
					var at: Vector2 = c + off2
					if level.is_solid(at):
						at = c
					windup_aoes.append(_spawn_aoe(at, float(current.get("radius", 36)), delay + float(current.get("interval", 0.25)) * i + 0.5, "explosion", col, mult))

func _target_ok() -> bool:
	return target != null and is_instance_valid(target) and target.alive

func _perform_attack() -> void:
	if attack_kind != "pattern":
		super._perform_attack()
		return
	var mult := float(current.get("mult", 1.0))
	match current.get("type", ""):
		"cleave":
			var rad := float(current.get("radius", 46))
			var arc := deg_to_rad(float(current.get("arc", 140)))
			var v = VFX.make("slash", global_position + Vector2(0, -8), Color(def.get("light", "#80e0d0")), 0.3, rad)
			v.angle = attack_dir.angle()
			v.arc = rad2deg_safe(arc)
			level.add_fx(v)
			level.shake(1.5)
			Sfx.play("swing")
			for a in level.allies:
				if not is_instance_valid(a) or not a.alive:
					continue
				var to: Vector2 = a.global_position - global_position
				if to.length() <= rad + a.radius and absf(attack_dir.angle_to(to)) <= arc / 2.0 + 0.15:
					Combat.deal(Combat.enemy_packet(self, mult), self, a)
		"charge":
			charge_t = 0.45
			charge_hit.clear()
		"fan":
			var n := int(current.get("count", 5))
			var spread := deg_to_rad(float(current.get("spread", 50)))
			for i in n:
				var a2 := -spread / 2.0 + spread * float(i) / maxf(1.0, n - 1.0) if n > 1 else 0.0
				_shoot(attack_dir.rotated(a2), mult)
			Sfx.play("spell")
		"spiral":
			spiral_waves = int(current.get("waves", 2))
			spiral_t = 0.0
		"summon":
			_summon_adds(def.get("summon", "ghoul"), int(current.get("count", 3)) + extra_summons)
		"ward":
			_summon_adds(def.get("summon", "ghoul"), int(current.get("count", 4)) + extra_summons)
			ward_adds = summons.duplicate()
			warded = true
			ward_t = float(current.get("duration", 10))
			Events.message.emit("%s is shielded by its minions - kill them!" % display_name, Color("#ff9060"))
		"teleport":
			if _target_ok():
				level.add_fx(VFX.make("nova", global_position, Color("#c080ff"), 0.4, 24))
				var dirr := Vector2.RIGHT.rotated(randf() * TAU)
				global_position = level.clamp_to_floor(target.global_position, target.global_position + dirr * 130.0)
				level.add_fx(VFX.make("nova", global_position, Color("#c080ff"), 0.4, 30))
				attack_dir = (target.global_position - global_position).normalized()
				for i in 5:
					_shoot(attack_dir.rotated(-0.4 + 0.2 * i), 0.6)
		"burrow":
			burrowed = true
			burrow_marked = false
			burrow_t = float(current.get("duration", 2.0))
			collision_layer = 0
			collision_mask = LAYER_WALL
			sprite.visible = false
			level.add_fx(VFX.make("dust", global_position, Color("#a08060"), 0.5, 30))
			Sfx.play("explode")
		"vent":
			vent_t = float(current.get("duration", 3.0))
			vent_tick = 0.0
			Events.message.emit("%s overheats - strike now!" % display_name, Color("#ffd060"))

func rad2deg_safe(r: float) -> float:
	return r * 180.0 / PI

func _shoot(dir: Vector2, mult: float) -> void:
	var p = Projectile.new()
	p.level = level
	p.source = self
	p.faction = "enemy"
	var pk: Dictionary = Combat.enemy_packet(self, mult)
	var dt: String = current.get("dtype", def.get("dmg_type", "physical"))
	var vals: Array = pk["dmg"].values()[0]
	pk["dmg"] = {dt: vals}
	p.packet = pk
	p.kind = current.get("proj", "orb")
	p.color = Combat.TYPE_COLORS.get(dt, Color.WHITE)
	p.radius = 4.0
	p.vel = dir * float(current.get("proj_speed", 180))
	p.max_dist = 420.0
	p.position = global_position + Vector2(0, -10) + dir * (radius + 2)
	level.projectile_layer.add_child(p)

func _spiral_wave(i: int) -> void:
	var n := int(current.get("count", 16))
	var off := (PI / n) * (i % 2)
	for k in n:
		_shoot(Vector2.RIGHT.rotated(TAU * k / n + off), float(current.get("mult", 0.7)))
	Sfx.play("spell")

# ------------------------------------------------------------------ special states
func _do_charge(delta: float) -> void:
	charge_t -= delta
	velocity = attack_dir * float(current.get("speed", 420))
	move_and_slide()
	update_visual(delta, true)
	for a in level.allies:
		if not is_instance_valid(a) or not a.alive or charge_hit.has(a.get_instance_id()):
			continue
		if a.global_position.distance_to(global_position) < radius + a.radius + 4:
			charge_hit[a.get_instance_id()] = true
			Combat.deal(Combat.enemy_packet(self, float(current.get("mult", 1.4))), self, a)
			if not a.is_boss:
				a.knock += attack_dir * 160.0
	if get_slide_collision_count() > 0 and charge_t < 0.35:
		charge_t = 0.0
		level.shake(2.0)
	if charge_t <= 0:
		state = "recover"
		state_t = 0.9
	queue_redraw()

func _do_burrow(delta: float) -> void:
	burrow_t -= delta
	if _target_ok():
		if burrow_t > 0.7:
			global_position = global_position.move_toward(target.global_position, speed * 2.2 * delta)
			if randf() < 0.15:
				level.add_fx(VFX.make("dust", global_position, Color("#806040"), 0.4, 10))
		elif not burrow_marked:
			burrow_marked = true
			global_position = level.clamp_to_floor(global_position, target.global_position)
			_spawn_aoe(global_position, float(current.get("radius", 46)), 0.7, "slam", Color("#c08040"), float(current.get("mult", 1.5)))
	if burrow_t <= 0:
		burrowed = false
		sprite.visible = true
		collision_layer = LAYER_ENEMY
		collision_mask = LAYER_WALL | LAYER_PLAYER | LAYER_ENEMY | LAYER_MINION
		state = "recover"
		state_t = 0.8
	queue_redraw()

func _do_vent(delta: float) -> void:
	vent_t -= delta
	vent_tick -= delta
	if vent_tick <= 0:
		vent_tick = 0.8
		_spawn_aoe(global_position, 46.0, 0.45, "explosion", Color("#ff7030"), 0.5)
	update_visual(delta, false)
	if vent_t <= 0:
		state = "recover"
		state_t = 0.5
	queue_redraw()

# ------------------------------------------------------------------ damage
func receive_hit(rolled: Dictionary, p: Dictionary, source, crit: bool) -> float:
	if burrowed:
		if randf() < 0.3:
			Combat.number(level, global_position, "Immune", Color("#a0a0a0"))
		return 0.0
	if warded:
		for k in rolled:
			rolled[k] *= 0.1
	if vent_t > 0:
		for k in rolled:
			rolled[k] *= 1.5
	var dealt: float = super.receive_hit(rolled, p, source, crit)
	if alive and dealt > 0 and not Data.stun_cfg.is_empty() and not poise_state.is_empty():
		if Stun.poise_hit(Data.stun_cfg, poise_state, dealt, max_life):
			_stagger()
	return dealt

## Poise broken: a short stagger that interrupts the current telegraph (and a charge).
func _stagger() -> void:
	var pc: Dictionary = Data.stun_cfg["poise"]
	var dur := float(pc.get("stagger_duration", 1.0))
	add_status("stun", dur, {})
	statuses["stun"]["dur"] = statuses["stun"]["t"]
	if pc.get("interrupts_windup", true):
		interrupt_windup()
		if charge_t > 0:
			charge_t = 0.0
			state = "recover"
			state_t = 0.5
	Combat.number(level, global_position + Vector2(0, -14), "Staggered!", Color("#ffe070"), true)
	Events.message.emit("%s is staggered!" % display_name, Color("#ffe070"))
	level.shake(2.5)

func _draw() -> void:
	if not alive:
		return
	if burrowed:
		draw_circle(Vector2.ZERO, 8, Color(0.4, 0.3, 0.2, 0.5))
		return
	if warded:
		draw_arc(Vector2(0, -12), radius + 10, 0, TAU, 32, Color(1, 0.6, 0.3, 0.7), 2.0)
		draw_circle(Vector2(0, -12), radius + 10, Color(1, 0.6, 0.3, 0.08))
	if vent_t > 0:
		draw_circle(Vector2(0, -10), radius + 6, Color(1, 0.5, 0.2, 0.2 + 0.1 * sin(Time.get_ticks_msec() / 60.0)))
	if roar_t > 0:
		draw_arc(Vector2(0, -12), 20 + (1.0 - roar_t) * 50, 0, TAU, 24, Color(0.9, 0.5, 0.4, roar_t), 2.0)
	if state != "windup" or attack_kind != "pattern":
		return
	var wu := float(current.get("windup", 0.7))
	var k := 1.0 - clampf(state_t / wu, 0, 1)
	var red := Color(1, 0.2, 0.15, 0.25 + 0.5 * k)
	match current.get("type", ""):
		"cleave":
			var arc := deg_to_rad(float(current.get("arc", 140)))
			var a0 := attack_dir.angle() - arc / 2.0
			draw_arc(Vector2(0, -8), float(current.get("radius", 46)), a0, a0 + arc, 16, red, 3.0 + 6.0 * k)
		"charge":
			draw_line(Vector2.ZERO, attack_dir * 190.0, Color(1, 0.25, 0.2, 0.2 + 0.4 * k), 2.0 * radius)
		"fan":
			var spread := deg_to_rad(float(current.get("spread", 50)))
			for s in [-0.5, 0.0, 0.5]:
				draw_line(Vector2(0, -10), Vector2(0, -10) + attack_dir.rotated(spread * s) * 60.0, Color(1, 0.6, 0.3, 0.3 + 0.4 * k), 2.0)
		"spiral", "summon", "ward", "teleport", "vent", "burrow":
			draw_arc(Vector2(0, -12), radius + 6 + 10 * k, 0, TAU, 24, Color(def.get("light", "#ffffff")) * Color(1, 1, 1, 0.3 + 0.5 * k), 2.0)
