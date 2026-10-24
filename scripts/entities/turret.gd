extends Node2D
## Deployed turret: fires bolts at the nearest visible enemy until it expires.

const Projectile = preload("res://scripts/entities/projectile.gd")

var level = null
var owner_player = null
var skill := {}
var life_t := 15.0
var fire_t := 0.3
var fire_interval := 0.7
var rng_dist := 240.0
var bolts := 1
var alive := true
var faction := "player"
var radius := 6.0
var sprite: Sprite2D
var aim := 0.0

func setup(player, sk: Dictionary) -> void:
	owner_player = player
	skill = sk
	var sb = player.ch.stats
	life_t = float(sk.get("duration", 15))
	var spd: float = (1.0 + sb.inc("turret_speed") / 100.0) * sb.more("turret_speed")
	fire_interval = 1.0 / maxf(0.2, float(sk.get("fire_rate", 1.2)) * spd)
	rng_dist = float(sk.get("range", 240))
	bolts = int(sk.get("bolts", 1)) + (1 if sb.has_flag("clockwork_choir") else 0)

func _ready() -> void:
	sprite = Sprite2D.new()
	sprite.texture = Art.sprite("turret")
	if skill.has("tint"):
		sprite.texture = Art.tinted("turret", Color(skill["tint"]))
	sprite.offset = Vector2(0, -6)
	add_child(sprite)
	var l := PointLight2D.new()
	l.texture = Art.light_tex
	l.color = Color("#ffd080")
	l.energy = 0.4
	l.texture_scale = 0.3
	add_child(l)

func _physics_process(delta: float) -> void:
	if level == null or owner_player == null or not is_instance_valid(owner_player):
		expire()
		return
	life_t -= delta
	if life_t <= 0:
		expire()
		return
	fire_t -= delta
	if fire_t <= 0:
		var t = level.nearest_hostile(global_position, "player", rng_dist, {}, true)
		if t != null:
			fire_t = fire_interval
			_fire(t)
		else:
			fire_t = 0.15
	modulate.a = 1.0 if life_t > 2.0 else (0.5 + 0.5 * sin(life_t * 20.0))

func _fire(t) -> void:
	var dir: Vector2 = (t.global_position - global_position).normalized()
	aim = dir.angle()
	sprite.flip_h = dir.x < 0
	var pk: Dictionary = Combat.player_packet(owner_player.ch, skill)
	for i in bolts:
		var p = Projectile.new()
		p.level = level
		p.source = owner_player
		p.faction = "player"
		p.packet = pk
		p.kind = skill.get("proj", "bolt")
		p.color = Color(skill.get("fx", "#ffffff"))
		p.radius = float(skill.get("size", 4))
		p.explode_radius = float(skill.get("explode_radius", 0))
		p.chain = int(skill.get("chain", 0)) + (1 if owner_player.ch.stats.has_flag("tesla_coils") else 0)
		p.vel = dir.rotated((i - (bolts - 1) * 0.5) * 0.12 + randf_range(-1, 1) * deg_to_rad(float(skill.get("jitter", 0)))) * float(skill.get("speed", 420))
		p.max_dist = rng_dist * 1.2
		p.position = global_position + Vector2(0, -6)
		p.pierce = owner_player.ch.final.get("pierce", 0)
		level.projectile_layer.add_child(p)

func expire() -> void:
	if not alive:
		return
	alive = false
	if owner_player != null and is_instance_valid(owner_player):
		owner_player.deployables.erase(self)
	queue_free()
