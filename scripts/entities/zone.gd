extends Node2D
## Persistent ground effect from a skill: burning ground, blizzards, static
## fields, toxic clouds, time snares. Ticks damage and/or statuses on hostiles
## inside its radius until it expires.

var level = null
var source = null
var packet := {}
var faction := "player"
var radius := 50.0
var duration := 4.0
var tick := 0.5
var t := 0.0
var tick_t := 0.0
var color := Color(1, 0.5, 0.2)
var style := "burning"      # burning | frost | storm | toxic | void | time
var statuses := []          # [{type, chance, duration}]
var damage_per_tick := 1.0  # fraction of the packet dealt each tick
var owner_skill := ""

func _ready() -> void:
	z_index = -3
	var l := PointLight2D.new()
	l.texture = Art.light_tex
	l.color = color
	l.energy = 0.55
	l.texture_scale = radius / 55.0
	add_child(l)

func _process(delta: float) -> void:
	if level == null:
		queue_free()
		return
	t += delta
	tick_t -= delta
	if tick_t <= 0:
		tick_t = tick
		_tick()
	if t >= duration:
		queue_free()
	queue_redraw()

func _tick() -> void:
	for e in level.hostiles_in_radius(global_position, radius, faction):
		if not packet.is_empty() and damage_per_tick > 0:
			var pk := packet.duplicate()
			var dm := {}
			for k in packet["dmg"]:
				dm[k] = [packet["dmg"][k][0] * damage_per_tick, packet["dmg"][k][1] * damage_per_tick]
			pk["dmg"] = dm
			pk["status"] = []
			Combat.deal(pk, source, e, global_position)
		for s in statuses:
			if randf() * 100.0 < float(s.get("chance", 100)):
				Combat.apply_status(e, s, {}, {"status_dur": 1.0, "dot_mult": 1.0, "flags": packet.get("flags", {})})
	if style == "storm" and randf() < 0.6:
		var VFX = load("res://scripts/fx/vfx.gd")
		var a := randf() * TAU
		var p := global_position + Vector2.RIGHT.rotated(a) * randf() * radius
		var b = VFX.make("bolt", Vector2.ZERO, color, 0.15, 8)
		b.points = PackedVector2Array([p + Vector2(0, -40), p])
		level.add_fx(b)

func _draw() -> void:
	var fade := clampf(minf(t * 4.0, (duration - t) * 2.0), 0, 1)
	var c := Color(color.r, color.g, color.b, 0.16 * fade)
	draw_circle(Vector2.ZERO, radius, c)
	draw_arc(Vector2.ZERO, radius, 0, TAU, 40, Color(color.r, color.g, color.b, 0.5 * fade), 1.5)
	var n := int(radius / 6.0)
	for i in n:
		var seed_v := float(i) * 12.9898
		var ang := seed_v + t * (0.6 if style != "frost" else 2.2)
		var r := radius * (0.15 + 0.8 * fmod(seed_v * 0.37, 1.0))
		var p := Vector2.RIGHT.rotated(ang) * r
		match style:
			"burning":
				var h := 3.0 + 2.0 * sin(t * 9.0 + seed_v)
				draw_line(p, p + Vector2(0, -h), Color(1, 0.6, 0.2, 0.7 * fade), 2.0)
			"frost":
				draw_line(p, p + Vector2(2, 6), Color(0.85, 0.95, 1.0, 0.8 * fade), 1.0)
			"toxic":
				draw_circle(p, 2.5 + sin(t * 3.0 + seed_v), Color(0.5, 0.9, 0.3, 0.35 * fade))
			"time":
				draw_arc(Vector2.ZERO, radius * (0.3 + 0.7 * fmod(t * 0.5 + i * 0.1, 1.0)), 0, TAU, 24, Color(color.r, color.g, color.b, 0.15 * fade), 1.0)
			_:
				draw_circle(p, 1.5, Color(color.r, color.g, color.b, 0.6 * fade))
