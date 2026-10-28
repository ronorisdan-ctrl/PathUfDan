extends "res://scripts/entities/actor.gd"
## Summoned creature: follows its owner (flow-field pathing around walls),
## acquires nearby enemies, attacks them, and is removed on death.

const VFX = preload("res://scripts/fx/vfx.gd")

var owner_player = null
var def := {}
var def_id := ""
var armour := 0.0
var speed := 100.0
var attack_range := 18.0
var attack_time := 1.0
var cd := 0.0
var target = null
var think_t := 0.0
var moving := false
var dmg_mult := 1.0
var life_t := -1.0   # >0 for temporary minions
var skill_id := ""   # the summoning skill (Training Grounds credits minion damage to it)

func setup(id: String, player, lvl: int, sk: Dictionary = {}) -> void:
	def_id = id
	skill_id = str(sk.get("id", ""))
	def = Data.summons.get(id, {})
	owner_player = player
	faction = "player"
	mlevel = lvl
	display_name = def.get("name", "Minion")
	var sb = player.ch.stats
	var life_mult: float = maxf(0.1, 1.0 + sb.inc("minion_life") / 100.0) * sb.more("minion_life")
	max_life = (float(def.get("life", 30)) + float(def.get("life_per_level", 6)) * (lvl - 1)) * life_mult * float(sk.get("minion_life_mult", 1.0))
	life = max_life
	dmg_mult = float(sk.get("damage_mult", 1.0)) * float(sk.get("minion_damage_mult", 1.0))
	life_t = float(sk.get("minion_duration", -1.0))
	var spd_mult: float = (1.0 + sb.inc("minion_speed") / 100.0) * float(sk.get("minion_speed_mult", 1.0))
	speed = float(def.get("speed", 100)) * spd_mult
	attack_time = float(def.get("attack_time", 1.0)) / spd_mult
	attack_range = float(def.get("attack_range", 18))
	armour = float(def.get("armour", 0))
	setup_body(float(def.get("radius", 6)), LAYER_MINION, LAYER_WALL | LAYER_ENEMY | LAYER_MINION)
	var tex: Texture2D = Art.sprite(def.get("sprite", "skeleton"))
	if def.has("tint"):
		tex = Art.tinted(def.get("sprite", "skeleton"), Color(def["tint"]))
	setup_sprite(tex, 0.0, float(def.get("sprite_scale", 1.0)))

func _physics_process(delta: float) -> void:
	if not alive or level == null:
		return
	tick_statuses(delta)
	if not alive:
		return
	if life_t > 0:
		life_t -= delta
		if life_t <= 0:
			die(null)
			return
	cd -= delta
	think_t -= delta
	if think_t <= 0:
		think_t = 0.25
		_pick_target()
	var vel := Vector2.ZERO
	var op = owner_player
	if target != null and is_instance_valid(target) and target.alive:
		var to: Vector2 = target.global_position - global_position
		if to.length() <= attack_range + target.radius and (not def.get("ranged", false) or level.has_los(global_position, target.global_position)):
			if cd <= 0:
				cd = attack_time
				_attack()
		else:
			vel = to.normalized() * speed
			if not level.has_los(global_position, target.global_position):
				var fd: Vector2 = level.flow_dir(global_position)
				if fd != Vector2.ZERO:
					vel = fd * speed
	elif op != null and is_instance_valid(op):
		var d: float = global_position.distance_to(op.global_position)
		if d > 260:
			# teleport back if hopelessly separated
			global_position = op.global_position + Vector2(randf_range(-16, 16), randf_range(-16, 16))
		elif d > 45:
			var fd2: Vector2 = level.flow_dir(global_position)
			if fd2 == Vector2.ZERO or level.has_los(global_position, op.global_position):
				fd2 = (op.global_position - global_position).normalized()
			vel = fd2 * speed * (1.0 if d > 80 else 0.6)
	velocity = vel * speed_mult() + knock
	knock = knock.move_toward(Vector2.ZERO, 400 * delta)
	moving = vel.length() > 1
	if velocity.length() > 1:
		move_and_slide()
		if absf(vel.x) > 1:
			facing = signf(vel.x)
	update_visual(delta, moving)

func _pick_target() -> void:
	var op = owner_player
	var center: Vector2 = op.global_position if op != null and is_instance_valid(op) else global_position
	var best = null
	var bd := INF
	for e in level.enemies:
		if not is_instance_valid(e) or not e.alive:
			continue
		if e.global_position.distance_to(center) > 230:
			continue
		var d: float = e.global_position.distance_to(global_position)
		if d < bd:
			bd = d
			best = e
	target = best

func _attack() -> void:
	if target == null or owner_player == null or not is_instance_valid(owner_player):
		return
	facing = signf(target.global_position.x - global_position.x)
	var pk: Dictionary = Combat.minion_packet(owner_player.ch, def, mlevel)
	pk["src_skill"] = skill_id
	if dmg_mult != 1.0:
		for k in pk["dmg"]:
			pk["dmg"][k] = [pk["dmg"][k][0] * dmg_mult, pk["dmg"][k][1] * dmg_mult]
	if def.get("ranged", false):
		var P = load("res://scripts/entities/projectile.gd")
		var pr = P.new()
		pr.level = level
		pr.source = self
		pr.faction = "player"
		pr.packet = pk
		pr.kind = def.get("proj", "arrow")
		pr.color = Combat.TYPE_COLORS.get(def.get("dmg_type", "physical"), Color.WHITE)
		pr.radius = 4.0
		pr.vel = (target.global_position - global_position).normalized() * float(def.get("proj_speed", 320))
		pr.max_dist = attack_range * 1.4
		pr.position = global_position + Vector2(0, -6)
		level.projectile_layer.add_child(pr)
		return
	var v = VFX.make("slash", global_position + Vector2(0, -5), Color("#d0d8c0"), 0.18, attack_range + 4)
	v.angle = (target.global_position - global_position).angle()
	v.arc = 90
	level.add_fx(v)
	Combat.deal(pk, self, target)

func receive_hit(rolled: Dictionary, _p: Dictionary, source, crit: bool) -> float:
	var total := 0.0
	for t in rolled:
		var v: float = rolled[t]
		if t == "physical":
			v *= 1.0 - Combat.armour_reduction(armour, v)
		total += v
	apply_damage(total, source, crit, Combat.dominant_type(rolled))
	return total

func die(_killer) -> void:
	if not alive:
		return
	alive = false
	if level != null:
		level.allies.erase(self)
		level.add_fx(VFX.make("dust", global_position, Color("#d0d8c0"), 0.4, 12))
	if owner_player != null and is_instance_valid(owner_player):
		owner_player.minions.erase(self)
	queue_free()
