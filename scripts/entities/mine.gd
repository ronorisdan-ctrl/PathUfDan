extends Node2D
## Explosive mine: arms, waits for an enemy to come close, then detonates.

const AoE = preload("res://scripts/entities/aoe.gd")

var level = null
var owner_player = null
var skill := {}
var arm_t := 0.6
var life_t := 20.0
var radius := 56.0
var trigger := 36.0
var alive := true
var blink := 0.0

func setup(player, sk: Dictionary) -> void:
	owner_player = player
	skill = sk
	life_t = float(sk.get("duration", 20))
	radius = float(sk.get("radius", 56)) * float(player.ch.final.get("area_mult", 1.0))
	trigger = float(sk.get("trigger_radius", 36))
	z_index = -1

func _process(delta: float) -> void:
	if level == null or owner_player == null or not is_instance_valid(owner_player):
		expire()
		return
	blink += delta
	life_t -= delta
	if life_t <= 0:
		expire()
		return
	if arm_t > 0:
		arm_t -= delta
	else:
		for e in level.enemies:
			if is_instance_valid(e) and e.alive and e.global_position.distance_to(global_position) < trigger + e.radius:
				detonate()
				return
	queue_redraw()

func detonate() -> void:
	if not alive:
		return
	var eff: String = skill.get("trap_effect", "explode")
	var col := Color(skill.get("fx", "#ff8a3a"))
	if eff == "bear":
		var t = level.nearest_hostile(global_position, "player", trigger + 12.0)
		if t != null:
			Combat.deal(Combat.player_packet(owner_player.ch, skill), owner_player, t, global_position)
			if t.alive:
				t.add_status("snare" if t.is_boss else "stun", 0.6 if t.is_boss else float(skill.get("hold", 2.0)), {})
		level.add_fx(load("res://scripts/fx/vfx.gd").make("spark", global_position, col, 0.3, 14))
		Sfx.play("block")
		expire()
		return
	if eff == "lightning":
		var VFX = load("res://scripts/fx/vfx.gd")
		var hit := {}
		var prev := global_position
		var pk: Dictionary = Combat.player_packet(owner_player.ch, skill)
		for i in int(skill.get("chains", 4)):
			var t2 = level.nearest_hostile(prev, "player", float(skill.get("radius", 90)), hit)
			if t2 == null:
				break
			hit[t2.get_instance_id()] = true
			var b = VFX.make("bolt", Vector2.ZERO, col, 0.2, 8)
			b.points = PackedVector2Array([prev, t2.global_position + Vector2(0, -5)])
			level.add_fx(b)
			Combat.deal(pk, owner_player, t2, global_position)
			prev = t2.global_position
		Sfx.play("crit")
		expire()
		return
	if eff == "snare" or eff == "poison":
		var Z = load("res://scripts/entities/zone.gd")
		var z = Z.new()
		z.level = level
		z.source = owner_player
		z.radius = radius
		z.duration = float(skill.get("zone_duration", 4.0))
		z.color = col
		z.style = "frost" if eff == "snare" else "toxic"
		z.packet = Combat.player_packet(owner_player.ch, skill)
		z.damage_per_tick = float(skill.get("tick_fraction", 0.2))
		z.statuses = skill.get("zone_status", [])
		z.position = global_position
		level.floor_layer.add_child(z)
		expire()
		return
	var a = AoE.new()
	a.level = level
	a.source = owner_player
	a.packet = Combat.player_packet(owner_player.ch, skill)
	a.faction = "player"
	a.radius = radius
	a.delay = 0.08
	a.style = "explosion"
	a.color = col
	a.show_telegraph = false
	a.position = global_position
	level.floor_layer.add_child(a)
	expire()

func expire() -> void:
	if not alive:
		return
	alive = false
	if owner_player != null and is_instance_valid(owner_player):
		owner_player.deployables.erase(self)
	queue_free()

func _draw() -> void:
	if skill.get("trap_effect", "explode") == "bear":
		draw_arc(Vector2.ZERO, 5, PI, TAU, 8, Color("#9aa0a8"), 2.0)
		draw_arc(Vector2.ZERO, 5, 0, PI, 8, Color("#6a7078"), 2.0)
	else:
		draw_texture(Art.sprite("mine"), Vector2(-5, -5), Color(skill.get("fx", "#ffffff")).lerp(Color.WHITE, 0.5))
	if arm_t <= 0 and fmod(blink, 0.8) < 0.15:
		draw_circle(Vector2.ZERO, 2, Color(1, 0.3, 0.2))
	if arm_t <= 0:
		draw_arc(Vector2.ZERO, trigger, 0, TAU, 24, Color(1, 0.5, 0.2, 0.12), 1.0)
