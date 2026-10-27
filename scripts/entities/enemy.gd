extends "res://scripts/entities/actor.gd"
## Data-driven enemy: detection, pursuit (via the level flow field), repositioning,
## telegraphed attacks, elite modifiers and death handling.

const Projectile = preload("res://scripts/entities/projectile.gd")
const AoE = preload("res://scripts/entities/aoe.gd")
const VFX = preload("res://scripts/fx/vfx.gd")

var def := {}
var armour := 0.0
var resist := {}
var speed := 50.0
var damage_mult := 1.0
var attack_speed_mult := 1.0
var elite_taken := 1.0
var leech := 0.0
var regen := 0.0
var death_explode := false
var convert_type := ""
var on_hit_status := ""
var elite_mods := []
var elite_color := Color.WHITE
var loot_mult := 1.0
var xp_value := 0
var room_id := -1
var last_overkill := 0.0
var added_fire := 0.0
var front_guard := 0.0
var is_miniboss := false
var summons := []
var dash_t := 0.0
var dash_hit := {}
var shield_max := 0.0
var shield := 0.0
var shield_regen_t := 0.0
var elite_summon := ""
var elite_summon_t := 6.0
var blink := false
var blink_t := 5.0

var state := "idle"
var state_t := 0.0
var target = null
var aggro := false
var home := Vector2.ZERO
var wander_to := Vector2.ZERO
var wander_t := 0.0
var attack_dir := Vector2.RIGHT
var attack_kind := ""
var think_t := 0.0
var moving := false
var windup_aoes := []     # telegraphs of the current windup; removed if the attack is interrupted

## run: multipliers from the dungeon tier and run modifiers
## (life, damage, speed, attack_speed, armour, resist, regen, explode, added_fire)
func setup(d: Dictionary, lvl: int, mods: Array, run: Dictionary = {}) -> void:
	def = d
	mlevel = lvl
	display_name = d["name"]
	faction = "enemy"
	is_boss = d.get("boss", false)
	max_life = float(d["life"]) * (1.0 + 0.28 * (lvl - 1))
	armour = float(d.get("armour", 0)) * (1.0 + 0.12 * (lvl - 1))
	resist = d.get("resist", {}).duplicate()
	speed = float(d.get("speed", 50))
	front_guard = float(d.get("front_guard", 0.0))
	is_miniboss = d.get("miniboss", false)
	max_life *= float(run.get("life", 1.0))
	damage_mult *= float(run.get("damage", 1.0))
	speed *= float(run.get("speed", 1.0))
	attack_speed_mult *= float(run.get("attack_speed", 1.0))
	armour *= float(run.get("armour", 1.0))
	regen = float(run.get("regen", 0.0))
	death_explode = run.get("explode", false) and not is_boss
	added_fire = float(run.get("added_fire", 0.0))
	var rb := float(run.get("resist", 0.0))
	if rb != 0.0:
		for el in ["fire", "cold", "lightning", "void"]:
			resist[el] = float(resist.get(el, 0)) + rb
	if is_miniboss:
		mods = d.get("fixed_mods", []) + mods
	xp_value = int(round(float(d.get("xp", 5)) * (1.0 + 0.18 * (lvl - 1))))
	loot_mult = float(d.get("loot_mult", 1.0))
	for mid in mods:
		var m: Dictionary = Data.elite_mods.get(mid, {})
		if m.is_empty():
			continue
		elite_mods.append(m)
		speed *= float(m.get("speed_mult", 1.0))
		attack_speed_mult *= float(m.get("attack_speed_mult", 1.0))
		elite_taken *= float(m.get("damage_taken_mult", 1.0))
		damage_mult *= float(m.get("damage_mult", 1.0))
		leech = maxf(leech, float(m.get("leech", 0.0)))
		regen = maxf(regen, float(m.get("regen", 0.0)))
		if m.get("death_explode", false):
			death_explode = true
		if m.has("convert"):
			convert_type = m["convert"]
		if m.has("on_hit_status"):
			on_hit_status = m["on_hit_status"]
		if m.has("summons"):
			elite_summon = m["summons"]
		if m.get("blink", false):
			blink = true
	if elite_mods.size() > 0:
		is_elite = true
		if not is_miniboss:
			max_life *= 2.6
		damage_mult *= 1.15
		xp_value *= 3
		elite_color = Color(elite_mods[0].get("color", "#ffffff"))
	life = max_life
	for m in elite_mods:
		if m.has("shield"):
			shield_max = max_life * float(m["shield"])
			shield = shield_max
	var r := float(d.get("radius", 6))
	setup_body(r, LAYER_ENEMY, LAYER_WALL | LAYER_PLAYER | LAYER_ENEMY | LAYER_MINION)
	var tex: Texture2D = Art.sprite(d.get("sprite", "ghoul"))
	if d.has("tint"):
		tex = Art.tinted(d.get("sprite", "ghoul"), Color(d["tint"]))
	if is_elite and not is_miniboss:
		tex = Art.tinted(d.get("sprite", "ghoul"), elite_color)
	setup_sprite(tex, 0.0, float(d.get("sprite_scale", 1.0)))
	if is_elite or is_boss:
		var l := PointLight2D.new()
		l.texture = Art.light_tex
		l.color = elite_color if is_elite else Color(d.get("light", "#60d0c0"))
		l.energy = 0.5
		l.texture_scale = 0.5
		add_child(l)

func elite_title() -> String:
	if is_miniboss:
		return display_name
	var names := []
	for m in elite_mods:
		names.append(m["name"])
	return " ".join(names)

func _ready() -> void:
	home = global_position
	wander_to = home

func _physics_process(delta: float) -> void:
	if not alive or level == null:
		return
	if Dev.freeze_ai():
		# developer tools: stand still, never think or attack (statuses and visuals still tick)
		tick_statuses(delta)
		update_visual(delta, false)
		queue_redraw()
		return
	if def.get("dummy", false):
		recently_hit -= delta
		statuses.clear()
		if recently_hit <= 0:
			life = max_life
		update_visual(delta, false)
		queue_redraw()
		return
	tick_statuses(delta)
	if not alive:
		return
	if dash_t > 0:
		_do_dash(delta)
		return
	if aggro and state != "idle":
		_tick_elite(delta)
	if regen > 0 and recently_hit <= 0:
		heal(max_life * regen * delta)
	recently_hit -= delta
	think_t -= delta
	if think_t <= 0:
		think_t = 0.2
		_think()
	state_t -= delta * (attack_speed_mult if state in ["windup", "recover"] else 1.0)
	moving = false
	var vel := Vector2.ZERO
	var sm := speed_mult()
	if sm <= 0.0:
		state_t = maxf(state_t, 0.05)  # stunned: freeze the current action
	else:
		match state:
			"idle":
				vel = _wander(delta)
			"chase":
				vel = _chase()
			"windup":
				if state_t <= 0:
					windup_aoes.clear()
					_perform_attack()
					state = "recover"
					state_t = float(def.get("recover", 0.8))
			"recover":
				if state_t <= 0:
					state = "chase"
	velocity = vel * sm + knock
	knock = knock.move_toward(Vector2.ZERO, 400 * delta)
	if velocity.length() > 1:
		move_and_slide()
		moving = vel.length() > 1
		if absf(vel.x) > 1:
			facing = signf(vel.x)
	update_visual(delta, moving)
	queue_redraw()

func _think() -> void:
	var detect := float(def.get("detect", 180)) * (1.8 if aggro else 1.0)
	var best = null
	var bd := INF
	for a in level.allies:
		if not is_instance_valid(a) or not a.alive:
			continue
		var d: float = global_position.distance_to(a.global_position)
		if a.faction == "player":
			d *= 0.8  # prefer the player
		if d < bd and d < detect:
			best = a
			bd = d
	if best == null:
		if aggro and level.player != null and level.player.alive and global_position.distance_to(level.player.global_position) < detect * 1.5:
			best = level.player
	if best != null and not aggro:
		if bd < 70 or level.has_los(global_position, best.global_position):
			_alert()
	if best != null and aggro:
		target = best
		if state == "idle":
			state = "chase"
	elif best == null and state == "chase":
		state = "idle"
		target = null

func _alert() -> void:
	aggro = true
	if state == "idle":
		state = "chase"
	for e in level.enemies:
		if is_instance_valid(e) and e != self and not e.aggro and e.global_position.distance_to(global_position) < 130:
			e.aggro = true

func _wander(delta: float) -> Vector2:
	wander_t -= delta
	if wander_t <= 0:
		wander_t = randf_range(1.5, 4.0)
		wander_to = home + Vector2(randf_range(-30, 30), randf_range(-30, 30))
		if level.is_solid(wander_to):
			wander_to = home
	var d := wander_to - global_position
	if d.length() < 4:
		return Vector2.ZERO
	return d.normalized() * speed * 0.35

func _chase() -> Vector2:
	if target == null or not is_instance_valid(target) or not target.alive:
		state = "idle"
		target = null
		return Vector2.ZERO
	var to: Vector2 = target.global_position - global_position
	var dist := to.length()
	if to.length() > 0.1:
		attack_dir = to.normalized()
	var rng_attack: float = float(def.get("attack_range", 16)) + target.radius
	var atk: String = def.get("attack", "melee")
	var los: bool = level.has_los(global_position, target.global_position)
	if dist <= rng_attack and (los or dist < 30):
		_start_attack(to.normalized())
		return Vector2.ZERO
	if atk == "dash" and dist < 40:
		_start_attack(to.normalized())
		return Vector2.ZERO
	if atk in ["ranged", "summoner"] and los and dist < float(def.get("preferred_range", 120)) * 0.6:
		return -to.normalized() * speed * 0.8
	var dir := to.normalized()
	if not los or dist > 90:
		var fd: Vector2 = level.flow_dir(global_position) if target == level.player else Vector2.ZERO
		if fd != Vector2.ZERO:
			dir = fd
	# light separation so packs spread around the target
	for e in level.enemies:
		if e != self and is_instance_valid(e):
			var off: Vector2 = global_position - e.global_position
			var l := off.length()
			if l < 14 and l > 0.1:
				dir += off / l * 0.35
	return dir.normalized() * speed

func _start_attack(dir: Vector2) -> void:
	attack_dir = dir
	facing = signf(dir.x) if absf(dir.x) > 0.1 else facing
	state = "windup"
	var wu := float(def.get("windup", 0.5))
	state_t = wu
	attack_kind = def.get("attack", "melee")
	windup_aoes.clear()
	match attack_kind:
		"slam":
			var at: Vector2 = global_position + dir * float(def.get("attack_range", 30)) * 0.7
			windup_aoes.append(_spawn_aoe(at, float(def.get("slam_radius", 36)), wu / attack_speed_mult, "slam", Color("#ff5030")))
		"explode":
			windup_aoes.append(_spawn_aoe(global_position, float(def.get("slam_radius", 40)), wu / attack_speed_mult, "explosion", Color("#a0e040")))
		"nova":
			windup_aoes.append(_spawn_aoe(global_position, float(def.get("slam_radius", 50)), wu / attack_speed_mult, "slam", Combat.TYPE_COLORS.get(def.get("dmg_type", "physical"), Color.WHITE)))

func _spawn_aoe(at: Vector2, r: float, delay: float, style: String, col: Color, mult: float = 1.0):
	var a = AoE.new()
	a.level = level
	a.source = self
	a.packet = Combat.enemy_packet(self, mult)
	a.packet["is_attack"] = style == "slam"
	a.faction = "enemy"
	a.radius = r
	a.delay = delay
	a.style = style
	a.color = col
	a.position = at
	level.floor_layer.add_child(a)
	return a

func _perform_attack() -> void:
	match attack_kind:
		"melee":
			level.add_fx(_slash_fx())
			for a in level.allies:
				if not is_instance_valid(a) or not a.alive:
					continue
				var to: Vector2 = a.global_position - global_position
				if to.length() <= float(def.get("attack_range", 16)) + a.radius + 6 and to.normalized().dot(attack_dir) > 0.2:
					Combat.deal(Combat.enemy_packet(self), self, a)
		"ranged":
			_fire_projectile(attack_dir)
		"dash":
			dash_t = float(def.get("attack_range", 100)) / float(def.get("dash_speed", 350))
			dash_hit.clear()
		"summoner":
			summons = summons.filter(func(s): return is_instance_valid(s) and s.alive)
			if summons.size() < int(def.get("summon_max", 4)):
				_summon_adds(def.get("summon", "plague_rat"), int(def.get("summon_count", 2)))
			else:
				_fire_projectile(attack_dir)
		"explode":
			alive = true
			die(null)

func _tick_elite(delta: float) -> void:
	if shield_max > 0 and shield < shield_max:
		shield_regen_t -= delta
		if shield_regen_t <= 0:
			shield = minf(shield_max, shield + shield_max * 0.25 * delta)
	if elite_summon != "":
		elite_summon_t -= delta
		if elite_summon_t <= 0:
			elite_summon_t = 8.0
			summons = summons.filter(func(s): return is_instance_valid(s) and s.alive)
			if summons.size() < 4:
				_summon_adds(elite_summon, 2)
	if blink and target != null and is_instance_valid(target) and state == "chase":
		blink_t -= delta
		if blink_t <= 0:
			blink_t = randf_range(5.0, 7.0)
			var to: Vector2 = level.clamp_to_floor(target.global_position, target.global_position + Vector2.RIGHT.rotated(randf() * TAU) * 36.0)
			if global_position.distance_to(target.global_position) > 60:
				level.add_fx(VFX.make("ring", global_position, Color("#d080ff"), 0.3, 14))
				global_position = to
				level.add_fx(VFX.make("ring", to, Color("#d080ff"), 0.3, 14))
				state = "recover"
				state_t = 0.35

func _summon_adds(id: String, n: int) -> void:
	var sd: Dictionary = Data.enemies.get(id, {})
	if sd.is_empty():
		return
	for i in n:
		var p: Vector2 = global_position + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(16, 30)
		if level.is_solid(p):
			p = global_position
		var e = level.spawn_enemy(sd, maxi(1, mlevel - 1), [], p)
		if e != null:
			e.aggro = true
			e.loot_mult = 0.15
			e.xp_value = int(e.xp_value * 0.3)
			summons.append(e)
			level.add_fx(VFX.make("ring", p, Color("#80ff80"), 0.4, 12))

func _do_dash(delta: float) -> void:
	dash_t -= delta
	velocity = attack_dir * float(def.get("dash_speed", 350))
	move_and_slide()
	update_visual(delta, true)
	for a in level.allies:
		if not is_instance_valid(a) or not a.alive or dash_hit.has(a.get_instance_id()):
			continue
		if a.global_position.distance_to(global_position) < radius + a.radius + 5:
			dash_hit[a.get_instance_id()] = true
			Combat.deal(Combat.enemy_packet(self), self, a)
	if get_slide_collision_count() > 0:
		dash_t = 0.0
	queue_redraw()

func _fire_projectile(dir: Vector2, mult: float = 1.0) -> void:
	if target != null and is_instance_valid(target):
		dir = (target.global_position - global_position).normalized()
	var p = Projectile.new()
	p.level = level
	p.source = self
	p.faction = "enemy"
	p.packet = Combat.enemy_packet(self, mult)
	p.kind = def.get("proj", "orb")
	p.color = Combat.TYPE_COLORS.get(convert_type if convert_type != "" else def.get("dmg_type", "physical"), Color.WHITE)
	if p.kind == "fire":
		p.radius = 4.0
	p.vel = dir * float(def.get("proj_speed", 200))
	p.max_dist = float(def.get("attack_range", 200)) * 1.5
	p.position = global_position + Vector2(0, -6) + dir * 6
	level.projectile_layer.add_child(p)

func _slash_fx():
	var v = VFX.make("slash", global_position + Vector2(0, -5), Color("#ff6050"), 0.22, float(def.get("attack_range", 16)) + 6)
	v.angle = attack_dir.angle()
	v.arc = 100
	return v

# ------------------------------------------------------------- damage
func receive_hit(rolled: Dictionary, p: Dictionary, source, crit: bool) -> float:
	if not alive:
		return 0.0
	var total := 0.0
	var arm := armour * (0.5 if p.get("flags", {}).has("armour_pen") else 1.0)
	var res_shift := -20.0 if statuses.has("frailty") else 0.0
	for t in rolled:
		var v: float = rolled[t]
		if t == "physical":
			v *= 1.0 - Combat.armour_reduction(arm, v)
		else:
			v *= 1.0 - clampf(float(resist.get(t, 0)) + res_shift, -100, 90) / 100.0
		total += v
	total *= taken_mult() * elite_taken
	if front_guard > 0 and source != null and is_instance_valid(source):
		var to_src: Vector2 = (source.global_position - global_position).normalized()
		if to_src.dot(attack_dir) > 0.35:
			total *= 1.0 - front_guard
			if randf() < 0.3:
				Combat.number(level, global_position, "Guard", Color("#c0c8d0"))
	if not aggro:
		_alert()
	if source != null and is_instance_valid(source) and source.faction != "enemy" and "alive" in source:
		if target == null or randf() < 0.3:
			target = source
	if state == "idle":
		state = "chase"
	if shield > 0 and total > 0:
		var absorbed := minf(shield, total)
		shield -= absorbed
		total -= absorbed
		shield_regen_t = 4.0
		if total <= 0:
			Combat.number(level, global_position, "Absorbed", Color("#80a0ff"))
			return 0.0
	last_overkill = maxf(0.0, total - life)
	if def.get("dummy", false):
		if total >= life:
			life = max_life + total
		apply_damage(total, source, crit, Combat.dominant_type(rolled))
		life = minf(life, max_life)
		return total
	apply_damage(total, source, crit, Combat.dominant_type(rolled))
	if alive and total > 0 and not is_boss:
		_try_hit_stun(total)
	return total

## Armour/health stun for normal and elite enemies (bosses use poise in boss.gd).
func _try_hit_stun(dmg: float) -> void:
	if Data.stun_cfg.is_empty():
		return
	var kind := "elite" if (is_elite or is_miniboss) else "normal"
	if try_hit_stun(dmg, kind) > 0.0 and Data.stun_cfg["kinds"][kind].get("interrupts_windup", true):
		interrupt_windup()

## Cancels a telegraphed attack: its warning circles are removed and the attack never lands.
func interrupt_windup() -> bool:
	if state != "windup":
		return false
	for a in windup_aoes:
		if is_instance_valid(a):
			a.queue_free()
	windup_aoes.clear()
	state = "recover"
	state_t = float(def.get("recover", 0.8)) * 0.5
	return true

func dot_resist(dtype: String) -> float:
	return (1.0 - clampf(float(resist.get(dtype, 0)), -100, 90) / 100.0) * taken_mult() * elite_taken

func die(killer) -> void:
	if not alive:
		return
	alive = false
	collision_layer = 0
	if level != null:
		level.enemies.erase(self)
		level.add_fx(VFX.make("dust", global_position, Color("#8a7a6a"), 0.4, radius * 2.5))
		Events.enemy_killed.emit(self, killer)
		if death_explode:
			_spawn_aoe(global_position, 42.0, 0.7, "explosion", Color("#ffa030"), 1.2)
	queue_free()

func _draw() -> void:
	if not alive:
		return
	if state == "windup" and attack_kind == "melee":
		var k := 1.0 - clampf(state_t / float(def.get("windup", 0.5)), 0, 1)
		var r := float(def.get("attack_range", 16)) + 8
		var a0 := attack_dir.angle() - 0.9
		draw_arc(Vector2(0, -4), r, a0, a0 + 1.8, 10, Color(1, 0.2, 0.15, 0.25 + 0.5 * k), 2.0 + 3.0 * k)
	if state == "windup" and attack_kind == "dash":
		var k3 := 1.0 - clampf(state_t / float(def.get("windup", 0.5)), 0, 1)
		draw_line(Vector2(0, -3), attack_dir * float(def.get("attack_range", 100)), Color(1, 0.2, 0.2, 0.15 + 0.35 * k3), 2.0 + radius)
	if front_guard > 0:
		draw_arc(Vector2(0, -6), radius + 4, attack_dir.angle() - 0.8, attack_dir.angle() + 0.8, 8, Color(0.75, 0.8, 0.9, 0.6), 2.0)
	if state == "windup" and attack_kind in ["ranged", "summoner"]:
		var k2 := 1.0 - clampf(state_t / float(def.get("windup", 0.5)), 0, 1)
		draw_circle(Vector2(0, -8) + attack_dir * 6, 1.5 + 2.0 * k2, Color(1, 0.6, 0.3, 0.8))
	if is_boss:
		return
	if life < max_life or is_elite:
		var w := 18.0 if not is_elite else (24.0 if not is_miniboss else 34.0)
		var y := -float(sprite.texture.get_height()) * sprite.scale.y - 2 if sprite else -20.0
		draw_rect(Rect2(-w / 2 - 1, y - 1, w + 2, 4), Color(0, 0, 0, 0.8))
		draw_rect(Rect2(-w / 2, y, w * clampf(life / max_life, 0, 1), 2), Color("#d03030") if not is_elite else elite_color)
		if shield_max > 0 and shield > 0:
			draw_rect(Rect2(-w / 2, y + 2, w * clampf(shield / shield_max, 0, 1), 1), Color("#80a0ff"))
		if is_elite:
			var f := ThemeDB.fallback_font
			var nm := elite_title()
			var tw := f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x
			draw_string_outline(f, Vector2(-tw / 2, y - 3), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, 2, Color.BLACK)
			draw_string(f, Vector2(-tw / 2, y - 3), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, elite_color)
	if shield > 0:
		draw_arc(Vector2(0, -6), radius + 3, 0, TAU, 16, Color(0.5, 0.65, 1.0, 0.45), 1.0)
