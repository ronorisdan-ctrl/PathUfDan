extends "res://scripts/entities/actor.gd"
## Player controller: WASD movement, mouse aiming, 5-slot skill hotbar
## (LMB, RMB, Q, E, R), dodge roll (Space), flasks (1, 2), interaction (F).

const SkillExec = preload("res://scripts/combat/skill_exec.gd")
const Minion = preload("res://scripts/entities/minion.gd")
const VFX = preload("res://scripts/fx/vfx.gd")

const SLOT_ACTIONS := ["skill_1", "skill_2", "skill_3", "skill_4", "skill_5", "skill_6", "skill_7"]
const DODGE_TIME := 0.24
const DODGE_DIST := 85.0
const DODGE_CD := 1.1

var ch = null
var mana := 0.0
var exec = SkillExec.new()
var cooldowns := {}
var busy := 0.0
var current_use_time := 0.0
var held := [false, false, false, false, false, false, false]
var current_move_mult := 0.45
var buffs := []
var minions := []
var deployables := []
var pending := []
var aim_pos := Vector2.ZERO
var weapon_sprite: Sprite2D
var swing_t := 0.0
var swing_dur := 0.0
var swing_kind := ""
var cam: Camera2D
var shake_amt := 0.0
var light: PointLight2D

var dodge_t := 0.0
var dodge_cd := 0.0
var dodge_dir := Vector2.ZERO
var dash_t := 0.0
var dash_vel := Vector2.ZERO
var dash_packet := {}
var dash_radius := 16.0
var dash_knock := 0.0
var dash_hit := {}

var momentum := 0
var momentum_t := 0.0
var still_t := 0.0
var msg_cd := 0.0
var input_enabled := true
var auto_aim_override = null   # tests can force an aim point
var last_hit_by := ""
var heal_mult := 1.0   # run modifiers can reduce recovery
var invuln_t := 0.0
var spell_count := 0
var aura_t := 0.0

func setup(character) -> void:
	ch = character
	faction = "player"
	display_name = ch.char_name
	setup_body(5.0, LAYER_PLAYER, LAYER_WALL | LAYER_ENEMY)
	setup_sprite(Art.sprite(ch.class_def().get("sprite", "warrior")))
	weapon_sprite = Sprite2D.new()
	weapon_sprite.z_index = 1
	add_child(weapon_sprite)
	light = PointLight2D.new()
	light.texture = Art.light_tex
	light.texture_scale = 3.2
	light.energy = 1.0
	light.color = Color("#ffe8c8")
	add_child(light)
	cam = Camera2D.new()
	cam.zoom = Vector2(2, 2)
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 9.0
	add_child(cam)
	refresh_stats()
	life = max_life
	mana = ch.final.get("max_mana", 0)
	_refresh_weapon()
	Events.inventory_changed.connect(_refresh_weapon)
	Events.stats_changed.connect(_on_stats_changed)

func _on_stats_changed() -> void:
	var old_max := max_life
	max_life = ch.final.get("max_life", 50)
	if old_max > 0 and max_life != old_max:
		life = clampf(life * max_life / old_max, 1, max_life) if alive else life

func refresh_stats() -> void:
	ch.recalc(buffs)
	max_life = ch.final.get("max_life", 50)
	life = minf(life, max_life)

func _refresh_weapon() -> void:
	if weapon_sprite == null or ch == null:
		return
	var w = ch.weapon()
	weapon_sprite.texture = Art.icon(w.get("icon", "sword")) if w != null else null

# ------------------------------------------------------------------ input
func _unhandled_input(event: InputEvent) -> void:
	if not alive or not input_enabled:
		return
	for i in SLOT_ACTIONS.size():
		if event.is_action_pressed(SLOT_ACTIONS[i]):
			if i == 0 and level != null and level.try_click_pickup(get_global_mouse_position(), self):
				get_viewport().set_input_as_handled()
				return
			held[i] = true
			try_use_slot(i)
		elif event.is_action_released(SLOT_ACTIONS[i]):
			held[i] = false
	if event.is_action_pressed("dodge"):
		start_dodge()
	elif event.is_action_pressed("flask_1"):
		use_flask(0)
	elif event.is_action_pressed("flask_2"):
		use_flask(1)
	elif event.is_action_pressed("interact"):
		if level != null:
			level.interact(self)

func release_all() -> void:
	for i in held.size():
		held[i] = false

# ------------------------------------------------------------------ main loop
func _physics_process(delta: float) -> void:
	if level == null:
		return
	if not alive:
		update_visual(delta, false)
		return
	aim_pos = auto_aim_override if auto_aim_override != null else get_global_mouse_position()
	tick_statuses(delta)
	if not alive:
		return
	_tick_timers(delta)
	_regen(delta)
	# held skills repeat as soon as they are ready
	if busy <= 0 and dash_t <= 0 and dodge_t <= 0:
		for i in held.size():
			if held[i]:
				try_use_slot(i)
				break
	var vel := Vector2.ZERO
	if dodge_t > 0:
		vel = dodge_dir * (DODGE_DIST / DODGE_TIME)
	elif dash_t > 0:
		vel = dash_vel
		_dash_hits()
	else:
		var inp := Vector2.ZERO
		if input_enabled:
			inp = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		var spd: float = ch.final.get("move_speed", 100)
		if busy > 0:
			spd *= current_move_mult
		vel = inp * spd * speed_mult()
	velocity = vel + knock
	knock = knock.move_toward(Vector2.ZERO, 500 * delta)
	var moving := vel.length() > 1
	if velocity.length() > 0.5:
		move_and_slide()
	still_t = 0.0 if moving else still_t + delta
	if busy > 0 or swing_t > 0:
		facing = signf(aim_pos.x - global_position.x) if absf(aim_pos.x - global_position.x) > 1 else facing
	elif absf(vel.x) > 1:
		facing = signf(vel.x)
	update_visual(delta, moving)
	_update_weapon(delta)
	if dodge_t > 0:
		sprite.modulate.a = 0.6
	_update_camera(delta)

func _tick_timers(delta: float) -> void:
	busy -= delta
	invuln_t -= delta
	msg_cd -= delta
	dodge_t -= delta
	dodge_cd -= delta
	if dash_t > 0:
		dash_t -= delta
		if dash_t <= 0:
			collision_mask = LAYER_WALL | LAYER_ENEMY
	for k in cooldowns.keys():
		cooldowns[k] -= delta
		if cooldowns[k] <= 0:
			cooldowns.erase(k)
	var changed := false
	for b in buffs.duplicate():
		b["t"] -= delta
		if b["t"] <= 0:
			buffs.erase(b)
			changed = true
	if changed:
		refresh_stats()
	aura_t -= delta
	if aura_t <= 0:
		aura_t = 0.5
		if ch.stats.has_flag("tyrant") and level != null and level.allow_combat:
			for e in level.hostiles_in_radius(global_position, 90.0, "player"):
				e.add_status("intimidate", 1.0, {})
	momentum_t -= delta
	if momentum_t <= 0:
		momentum = 0
	for pe in pending.duplicate():
		pe["t"] -= delta
		if pe["t"] <= 0:
			pending.erase(pe)
			pe["fn"].call()

func _regen(delta: float) -> void:
	heal(ch.final.get("life_regen", 0.0) * delta)
	var mm: float = ch.final.get("max_mana", 0)
	mana = minf(mm, mana + ch.final.get("mana_regen", 0.0) * delta)

func schedule(delay: float, fn: Callable) -> void:
	if delay <= 0.001:
		fn.call()
	else:
		pending.append({"t": delay, "fn": fn})

# ------------------------------------------------------------------ skills
func skill_in_slot(i: int) -> Dictionary:
	var sid: String = ch.loadout[i] if i < ch.loadout.size() else ""
	return ch.resolved_skill(sid)

func weapon_ok(sk: Dictionary) -> bool:
	var req: Array = sk.get("weapon_req", [])
	if req.is_empty():
		return true
	var groups: Array = ch.weapon_groups()
	for r in req:
		if groups.has(r):
			return true
	return false

func mana_cost(sk: Dictionary) -> float:
	var c: float = float(sk.get("cost", 0)) * ch.final.get("mana_cost_mult", 1.0)
	if ch.stats.has_flag("hollow_crown") and mana >= ch.final.get("max_mana", 0) * 0.9:
		c = 0.0
	return c

func use_time_for(sk: Dictionary) -> float:
	match sk.get("kind", "spell"):
		"attack":
			return (1.0 / maxf(0.2, ch.final.get("weapon_aps", 1.2))) * float(sk.get("speed_mult", 1.0)) / ch.final.get("attack_speed_mult", 1.0)
		"spell", "trap", "minion", "turret":
			return float(sk.get("use_time", 0.6)) / ch.final.get("cast_speed_mult", 1.0)
		_:
			return float(sk.get("use_time", 0.3))

func use_block_reason(sk: Dictionary) -> String:
	if sk.is_empty():
		return "empty"
	if cooldowns.get(sk["id"], 0.0) > 0:
		return "On cooldown"
	if not weapon_ok(sk):
		return "Requires a %s weapon" % "/".join(sk.get("weapon_req", []))
	var cost := mana_cost(sk)
	if ch.stats.has_flag("blood_magic"):
		if life <= cost + 1:
			return "Not enough life"
	elif mana < cost:
		return "Not enough mana"
	return ""

func try_use_slot(i: int) -> bool:
	if busy > 0 or dodge_t > 0 or dash_t > 0 or not alive or speed_mult() <= 0:
		return false
	var sk := skill_in_slot(i)
	if sk.is_empty():
		return false
	if auto_aim_override != null:
		aim_pos = auto_aim_override
	var why := use_block_reason(sk)
	if why != "":
		if msg_cd <= 0 and why != "On cooldown":
			msg_cd = 1.0
			Events.message.emit(why, Color("#ff8080"))
		return false
	if sk.get("behavior") in ["summon", "deploy", "buff"] and level != null and not level.allow_combat:
		if msg_cd <= 0:
			msg_cd = 1.0
			Events.message.emit("You cannot do that in town", Color("#ff8080"))
		return false
	var cost := mana_cost(sk)
	if ch.stats.has_flag("blood_magic"):
		life -= cost
	else:
		mana -= cost
	current_use_time = use_time_for(sk)
	current_move_mult = float(sk.get("move_mult", 0.45))
	busy = current_use_time
	var cd: float = float(sk.get("cooldown", 0)) * ch.final.get("cdr_mult", 1.0)
	if cd > 0:
		cooldowns[sk["id"]] = cd
	swing_t = current_use_time
	swing_dur = current_use_time
	swing_kind = sk.get("behavior", "")
	facing = signf(aim_pos.x - global_position.x) if absf(aim_pos.x - global_position.x) > 1 else facing
	exec.execute(self, sk, aim_pos)
	_on_skill_used(sk)
	var b: String = sk.get("behavior", "")
	if b in ["melee_arc", "dash"] or (b == "ground_aoe" and sk.get("at_self", false)):
		Sfx.play("swing")
	elif sk.get("kind") == "attack" or sk.get("kind") == "turret":
		Sfx.play("shoot")
	else:
		Sfx.play("spell")
	return true

const REPEATABLE := ["projectile", "ground_aoe", "nova", "chain", "beam", "melee_arc"]

## Legendary effects that trigger on skill use (echoes, double shots, starfall).
func _on_skill_used(sk: Dictionary) -> void:
	var sb = ch.stats
	var b: String = sk.get("behavior", "")
	if sk.get("kind") == "spell":
		spell_count += 1
		if sb.has_flag("echo") and b in REPEATABLE and randf() < 0.2:
			schedule(0.22, exec.execute.bind(self, sk, aim_pos))
		if sb.has_flag("starfall") and spell_count % 5 == 0 and level != null and level.allow_combat:
			var at := aim_pos
			level.add_fx(VFX.make("telegraph", at, Color("#ffe080"), 0.45, 46))
			schedule(0.45, _starfall.bind(at, sk))
	elif sk.get("kind") == "attack" and b == "projectile" and sb.has_flag("double_shot") and ch.weapon_groups().has("firearm") and randf() < 0.25:
		schedule(0.15, exec.execute.bind(self, sk, aim_pos))

func _starfall(at: Vector2, sk: Dictionary) -> void:
	if level == null or not alive:
		return
	var pk: Dictionary = Combat.player_packet(ch, sk, 2.5)
	var dm := {}
	var tot := 0.0
	for k in pk["dmg"]:
		tot += (pk["dmg"][k][0] + pk["dmg"][k][1]) * 0.5
	dm["fire"] = [tot * 0.4, tot * 0.6]
	dm["arcane"] = [tot * 0.4, tot * 0.6]
	pk["dmg"] = dm
	level.add_fx(VFX.make("explosion", at, Color("#ffe080"), 0.4, 46))
	shake(2.0)
	for e in level.hostiles_in_radius(at, 46.0, "player"):
		Combat.deal(pk, self, e, at)

func register_hit() -> void:
	## consecutive-hit mechanics (Overwhelming Momentum keystone, Bloodletter)
	momentum = mini(momentum + 1, 20)
	momentum_t = 2.0

func damage_more(sk: Dictionary) -> float:
	var m := 1.0
	var sb = ch.stats
	if sb.has_flag("rage"):
		m *= 1.0 + 0.02 * mini(momentum, 20)
	if sb.has_flag("arcane_flow") and sk.get("kind") == "spell":
		m *= 1.0 + 0.3 * (mana / maxf(1.0, ch.final.get("max_mana", 1.0)))
	if sb.has_flag("momentum"):
		m *= 0.9 if momentum == 0 else (1.0 + 0.03 * momentum)
	if sb.has_flag("wind_dancer") and not has_buff("wind_dance"):
		m *= 0.9
	if sb.has_flag("bloodletter") and sk.get("kind") == "attack":
		m *= 1.0 + 0.04 * mini(momentum, 10)
	return m

func add_buff(id: String, mods: Array, duration: float) -> void:
	for b in buffs:
		if b["id"] == id:
			b["t"] = duration
			return
	buffs.append({"id": id, "mods": mods, "t": duration})
	refresh_stats()

func has_buff(id: String) -> bool:
	for b in buffs:
		if b["id"] == id:
			return true
	return false

func spawn_minion(id: String, lvl: int, pos: Vector2, sk: Dictionary = {}):
	var m = Minion.new()
	m.level = level
	m.setup(id, self, lvl, sk)
	m.position = pos
	minions.append(m)
	level.allies.append(m)
	level.entity_layer.add_child(m)
	return m

func clear_summons() -> void:
	for m in minions.duplicate():
		if is_instance_valid(m):
			m.queue_free()
	minions.clear()
	for d in deployables.duplicate():
		if is_instance_valid(d):
			d.queue_free()
	deployables.clear()

# ------------------------------------------------------------------ movement skills
func start_dodge() -> void:
	if dodge_cd > 0 or dodge_t > 0 or dash_t > 0 or speed_mult() <= 0:
		return
	var inp := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	dodge_dir = inp.normalized() if inp.length() > 0.1 else (aim_pos - global_position).normalized()
	if dodge_dir == Vector2.ZERO:
		dodge_dir = Vector2.RIGHT * facing
	dodge_t = DODGE_TIME
	dodge_cd = DODGE_CD * (0.5 if ch.stats.has_flag("phantom_step") else 1.0) * (0.6 if ch.stats.has_flag("phantom_treads") else 1.0)
	if ch.stats.has_flag("phantom_treads"):
		add_buff("phantom_treads", [{"stat": "move_speed", "type": "inc", "value": 20}], 2.0)
	if ch.stats.has_flag("phantom_step"):
		add_buff("phantom_step", [{"stat": "damage", "type": "more", "value": 30}], 3.0)
	if ch.stats.has_flag("wind_dancer"):
		add_buff("wind_dance", [{"stat": "damage", "type": "more", "value": 40}, {"stat": "move_speed", "type": "inc", "value": 15}], 3.0)
	busy = 0.0
	pending.clear()
	level.add_fx(VFX.make("dust", global_position, Color("#a09080"), 0.3, 10))

func start_dash(dir: Vector2, dist: float, dur: float, pk: Dictionary, r: float, kb: float, col: Color) -> void:
	dash_t = dur
	dash_vel = dir * dist / dur
	dash_packet = pk
	dash_radius = r
	dash_knock = kb
	dash_hit.clear()
	collision_mask = LAYER_WALL
	busy = dur
	level.add_fx(VFX.make("dust", global_position, col, 0.3, 12))

func _dash_hits() -> void:
	if dash_packet.is_empty():
		return
	for e in level.enemies:
		if not is_instance_valid(e) or not e.alive or dash_hit.has(e.get_instance_id()):
			continue
		if e.global_position.distance_to(global_position) < dash_radius + e.radius:
			dash_hit[e.get_instance_id()] = true
			Combat.deal(dash_packet, self, e, global_position)
			if e.alive and not e.is_boss:
				e.knock += dash_vel.normalized() * dash_knock * 4.0
			register_hit()
			shake(1.5)

# ------------------------------------------------------------------ defence
func receive_hit(rolled: Dictionary, p: Dictionary, source, crit: bool) -> float:
	if not alive or dodge_t > 0 or invuln_t > 0:
		return 0.0
	var f: Dictionary = ch.final
	var att_lvl := 1
	if source != null and is_instance_valid(source) and "mlevel" in source:
		att_lvl = source.mlevel
	if p.get("is_attack", false) and randf() < Combat.evade_chance(f.get("evasion", 0), att_lvl):
		Combat.number(level, global_position, "Evade", Color("#a0e0a0"))
		return 0.0
	var block: float = f.get("block_chance", 0) / 100.0 * (1.0 if p.get("is_attack", false) else 0.5)
	if block > 0 and randf() < block:
		Combat.number(level, global_position, "Block", Color("#c0c8ff"))
		Sfx.play("block")
		_on_block()
		return 0.0
	var total := 0.0
	for t in rolled:
		var v: float = rolled[t]
		if t == "physical":
			v *= 1.0 - Combat.armour_reduction(f.get("armour", 0), v)
		else:
			v *= 1.0 - clampf(f.get("res_" + t, 0.0), -100, Combat.RES_CAP) / 100.0
		total += v
	var dr: float = f.get("damage_reduction", 0.0)
	if ch.stats.has_flag("fortress") and still_t >= 1.0:
		dr += 30.0
	if ch.stats.has_flag("minion_shield"):
		dr += minf(30.0, 5.0 * minions.size())
	dr = minf(dr, 75.0)
	total *= (1.0 - dr / 100.0) * taken_mult()
	if ch.stats.has_flag("thorns") and p.get("is_attack", false) and source != null and is_instance_valid(source) and source.alive and source.global_position.distance_to(global_position) < 48.0:
		var th: float = f.get("armour", 0) * 0.3
		if th > 0:
			Combat.deal({"dmg": {"physical": [th * 0.9, th * 1.1]}, "crit_chance": 0.0, "crit_mult": 1.0, "faction": "player", "status": [], "tags": [], "flags": {}}, self, source, global_position)
	if ch.stats.has_flag("mind_over_matter") and total > 0:
		var from_mana := minf(mana, total * 0.3)
		mana -= from_mana
		total -= from_mana
	if source != null and is_instance_valid(source) and "display_name" in source:
		last_hit_by = source.display_name + (" (elite)" if source.is_elite else "")
	apply_damage(total, source, crit, Combat.dominant_type(rolled))
	if total > 0:
		Sfx.play("hurt")
	Events.player_damaged.emit(total)
	if total > max_life * 0.1:
		shake(2.0)
	return total

func _on_block() -> void:
	if ch.stats.has_flag("retaliate"):
		var dmg: float = 10.0 + ch.final.get("armour", 0) * 0.25
		var pk := {"dmg": {"physical": [dmg * 0.8, dmg * 1.2]}, "crit_chance": 0.0, "crit_mult": 1.0, "faction": "player", "status": [{"type": "stun", "chance": 50.0}], "tags": [], "flags": {}}
		for e in level.hostiles_in_radius(global_position, 50.0, "player"):
			Combat.deal(pk, self, e, global_position)
		level.add_fx(VFX.make("nova", global_position, Color("#c0c8ff"), 0.3, 50))
	if ch.stats.has_flag("last_bastion"):
		add_buff("last_bastion", [{"stat": "damage_reduction", "type": "flat", "value": 25}], 3.0)
	if ch.stats.has_flag("bulwark"):
		add_buff("bulwark", [{"stat": "damage_reduction", "type": "flat", "value": 15}], 2.0)

func dot_resist(dtype: String) -> float:
	if dtype == "physical":
		return 1.0
	return 1.0 - clampf(ch.final.get("res_" + dtype, 0.0), -100, Combat.RES_CAP) / 100.0

func die(_killer) -> void:
	if not alive:
		return
	alive = false
	life = 0
	release_all()
	pending.clear()
	sprite.rotation = PI / 2
	sprite.modulate = Color(0.6, 0.3, 0.3)
	Sfx.play("death", 0.0)
	Events.player_died.emit()

func heal(amount: float) -> void:
	super.heal(amount * heal_mult)

func on_kill(e) -> void:
	heal(ch.final.get("life_on_kill", 0.0))
	mana = minf(ch.final.get("max_mana", 0), mana + ch.final.get("mana_on_kill", 0.0))
	for i in 2:
		ch.flask_charges[i] = minf(3.0, ch.flask_charges[i] + (1.0 if e.is_boss else 0.25))
	if ch.stats.has_flag("gravetender"):
		for m in minions:
			if is_instance_valid(m):
				m.heal(m.max_life * 0.1)

func use_flask(i: int) -> void:
	if ch.flask_charges[i] < 1.0:
		if msg_cd <= 0:
			msg_cd = 0.8
			Events.message.emit("Flask is empty", Color("#ff8080"))
		return
	ch.flask_charges[i] -= 1.0
	var fm: float = ch.final.get("flask_mult", 1.0)
	if i == 0:
		heal(max_life * 0.4 * fm)
		statuses.erase("bleed")
		statuses.erase("ignite")
		level.add_fx(VFX.make("ring", global_position, Color("#ff5050"), 0.4, 16))
	else:
		mana = minf(ch.final.get("max_mana", 0), mana + ch.final.get("max_mana", 0) * 0.5 * fm)
		level.add_fx(VFX.make("ring", global_position, Color("#5080ff"), 0.4, 16))

# ------------------------------------------------------------------ visuals
func shake(amount: float) -> void:
	shake_amt = maxf(shake_amt, amount * float(Game.settings.get("screen_shake", 1.0)))

func _update_camera(delta: float) -> void:
	if cam == null:
		return
	if shake_amt > 0.05:
		cam.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake_amt
		shake_amt = move_toward(shake_amt, 0, 14 * delta)
	else:
		cam.offset = Vector2.ZERO

func _update_weapon(delta: float) -> void:
	if weapon_sprite == null or weapon_sprite.texture == null:
		return
	var aim_dir := (aim_pos - global_position).normalized()
	var base_ang := aim_dir.angle()
	swing_t -= delta
	var w = ch.weapon()
	var cat: String = w.get("category", "") if w != null else ""
	var ranged: bool = w != null and w.get("tags", []).has("ranged_weapon")
	var caster: bool = w != null and w.get("tags", []).has("caster_weapon")
	var off := Vector2(4, -5)
	var ang := base_ang
	if swing_t > 0 and swing_dur > 0 and not ranged and not caster and swing_kind in ["melee_arc", "ground_aoe", "dash"]:
		var k := 1.0 - swing_t / swing_dur
		ang = base_ang + lerpf(-1.6, 1.4, clampf(k * 1.6, 0, 1))
	elif swing_t > 0 and caster:
		off += Vector2(0, -3) * sin(clampf(1.0 - swing_t / maxf(swing_dur, 0.01), 0, 1) * PI)
	elif swing_t > 0 and ranged:
		off -= aim_dir * 2.0 * clampf(swing_t / maxf(swing_dur, 0.01), 0, 1)
	weapon_sprite.position = off + aim_dir * 3.0
	# icons are drawn pointing up-right; bows are drawn vertically
	var icon_rot := PI / 4.0
	if cat in ["shortbow", "longbow", "crossbow"] or ranged and not cat in ["pistol", "rifle"]:
		icon_rot = 0.0
	if cat in ["pistol", "rifle", "crossbow"]:
		icon_rot = 0.0
	weapon_sprite.rotation = ang + icon_rot
	weapon_sprite.flip_v = false
	weapon_sprite.scale = Vector2(0.85, 0.85)
	weapon_sprite.z_index = 1 if aim_dir.y > -0.3 else -1
