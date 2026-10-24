extends Node2D
## Environmental hazards placed in dungeon rooms. They hurt the player and
## minions (never monsters) and always telegraph before dealing burst damage.
##   spikes   - periodic floor spikes (physical)
##   vent     - periodic fire column (fire, ignites)
##   miasma   - lingering toxic pool (void damage over time, no burst)
##   lightning- run modifier strike that follows the player (lightning)

var level = null
var kind := "spikes"
var mlevel := 1
var radius := 18.0
var period := 3.0
var warn := 0.8
var t := 0.0
var phase := "idle"
var base_damage := 7.0
var one_shot := false

func setup(k: String, lvl: int) -> void:
	kind = k
	mlevel = lvl
	match k:
		"spikes":
			radius = 16.0
			period = 2.6
			base_damage = 8.0
		"vent":
			radius = 22.0
			period = 3.4
			base_damage = 9.0
		"miasma":
			radius = 26.0
			period = 0.5
			warn = 0.0
			base_damage = 2.2
		"lightning":
			radius = 30.0
			period = 0.0
			warn = 0.9
			base_damage = 11.0
			one_shot = true
	t = randf() * period
	z_index = -2

func _packet(mult: float) -> Dictionary:
	var dmg := base_damage * (1.0 + 0.13 * (mlevel - 1)) * mult
	var dtype: String = {"spikes": "physical", "vent": "fire", "miasma": "void", "lightning": "lightning"}.get(kind, "physical")
	var st := []
	if kind == "vent":
		st.append({"type": "ignite", "chance": 40.0})
	if kind == "lightning":
		st.append({"type": "shock", "chance": 50.0})
	return {"dmg": {dtype: [dmg * 0.85, dmg * 1.15]}, "crit_chance": 0.0, "crit_mult": 1.0, "kind": "hazard", "tags": [], "status": st,
			"is_attack": false, "faction": "enemy", "flags": {}, "dot_mult": 1.0, "status_dur": 1.0, "knockback": 0.0, "life_on_hit": 0.0, "leech": 0.0}

func _process(delta: float) -> void:
	if level == null:
		return
	t += delta
	match phase:
		"idle":
			if t >= period:
				t = 0.0
				phase = "warn" if warn > 0 else "fire"
		"warn":
			if t >= warn:
				t = 0.0
				phase = "fire"
		"fire":
			_trigger()
			t = 0.0
			phase = "active"
		"active":
			if t >= 0.25:
				t = 0.0
				phase = "idle"
				if one_shot:
					queue_free()
	queue_redraw()

func _trigger() -> void:
	for a in level.allies:
		if is_instance_valid(a) and a.alive and a.global_position.distance_to(global_position) <= radius + a.radius:
			Combat.deal(_packet(1.0), null, a)
	if kind in ["vent", "lightning"]:
		var VFX = load("res://scripts/fx/vfx.gd")
		level.add_fx(VFX.make("explosion" if kind == "vent" else "nova", global_position, _color(), 0.3, radius))
		if kind == "lightning":
			var b = VFX.make("bolt", Vector2.ZERO, _color(), 0.25, 10)
			b.points = PackedVector2Array([global_position + Vector2(randf_range(-20, 20), -160), global_position])
			level.add_fx(b)
			Sfx.play("crit")

func _color() -> Color:
	return {"spikes": Color("#c8c0b0"), "vent": Color("#ff7030"), "miasma": Color("#80c040"), "lightning": Color("#c0e8ff")}.get(kind, Color.WHITE)

func _draw() -> void:
	var c := _color()
	match kind:
		"miasma":
			var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 400.0)
			draw_circle(Vector2.ZERO, radius, Color(c.r * 0.5, c.g * 0.6, c.b * 0.3, 0.35 + 0.1 * pulse))
			for i in 5:
				var a := float(i) * 1.3 + Time.get_ticks_msec() / 900.0
				draw_circle(Vector2.RIGHT.rotated(a) * radius * 0.55, 2.5, Color(c.r, c.g, c.b, 0.4))
		"spikes":
			draw_rect(Rect2(-radius, -radius * 0.6, radius * 2, radius * 1.2), Color(0.12, 0.11, 0.13, 0.8))
			var up := phase in ["fire", "active"]
			for x in range(-2, 3):
				for y in range(-1, 2):
					var p := Vector2(x * radius * 0.4, y * radius * 0.4)
					if up:
						draw_colored_polygon(PackedVector2Array([p + Vector2(-2, 2), p + Vector2(2, 2), p + Vector2(0, -6)]), c)
					else:
						draw_circle(p, 1.2, Color(0.05, 0.05, 0.05))
			if phase == "warn":
				draw_rect(Rect2(-radius, -radius * 0.6, radius * 2, radius * 1.2), Color(1, 0.2, 0.1, 0.25 + 0.25 * t / warn), false, 1.5)
		"vent", "lightning":
			if kind == "vent":
				draw_circle(Vector2.ZERO, 7, Color(0.15, 0.08, 0.06))
				draw_circle(Vector2.ZERO, 4, Color(0.6, 0.2, 0.05, 0.8))
			if phase == "warn":
				var k := t / maxf(warn, 0.01)
				draw_circle(Vector2.ZERO, radius, Color(c.r, c.g, c.b, 0.10))
				draw_arc(Vector2.ZERO, radius, 0, TAU, 32, Color(c.r, c.g, c.b, 0.6), 1.5)
				draw_circle(Vector2.ZERO, radius * k, Color(c.r, c.g, c.b, 0.2))
