extends CharacterBody2D
## Shared base for the player, enemies and minions: life, status effects,
## hit flash, death handling. Subclasses override receive_hit/die.

const LAYER_WALL := 1
const LAYER_PLAYER := 2
const LAYER_ENEMY := 4
const LAYER_MINION := 8
const Stun = preload("res://scripts/combat/stun.gd")

var level = null            # the Level node this actor lives in
var faction := "enemy"
var display_name := ""
var mlevel := 1
var max_life := 10.0
var life := 10.0
var alive := true
var radius := 6.0
var is_elite := false
var is_boss := false
var statuses := {}          # type -> {"t": remaining, ...}
var sprite: Sprite2D
var shadow: Sprite2D
var flash := 0.0
var facing := 1.0
var anim_t := 0.0
var knock := Vector2.ZERO
var recently_hit := 0.0
var stun_immune_t := 0.0     # no new armour/health stun while > 0 (data/stun.json)

func setup_body(r: float, layer: int, mask: int) -> void:
	radius = r
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = layer
	collision_mask = mask
	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = r
	cs.shape = sh
	add_child(cs)

func setup_sprite(tex: Texture2D, y_off: float = 0.0, sprite_scale: float = 1.0) -> void:
	shadow = Sprite2D.new()
	shadow.texture = Art.soft_tex
	shadow.modulate = Color(0, 0, 0, 0.55)
	shadow.scale = Vector2(radius / 20.0, radius / 40.0) * 1.4
	shadow.position = Vector2(0, 1)
	add_child(shadow)
	sprite = Sprite2D.new()
	sprite.texture = tex
	sprite.scale = Vector2(sprite_scale, sprite_scale)
	sprite.offset = Vector2(0, -tex.get_height() / 2.0 + 2 + y_off)
	add_child(sprite)

# ------------------------------------------------------------- status effects
func add_status(type: String, duration: float, data: Dictionary) -> void:
	if not alive:
		return
	var cur = statuses.get(type)
	if cur == null:
		var d := data.duplicate()
		d["t"] = duration
		d["tick"] = 0.0
		statuses[type] = d
	else:
		cur["t"] = maxf(cur["t"], duration)
		if data.has("dps"):
			cur["dps"] = maxf(cur.get("dps", 0.0), data["dps"])

func has_status(type: String) -> bool:
	return statuses.has(type)

func taken_mult() -> float:
	var m := 1.0
	if statuses.has("shock"):
		m *= float(statuses["shock"].get("mag", 1.2))
	if statuses.has("intimidate"):
		m *= 1.15
	if statuses.has("frailty"):
		m *= 1.2
	if statuses.has("marked"):
		m *= 1.4
	if statuses.has("freeze"):
		m *= float(statuses["freeze"].get("mag", 1.1))
	return m

func speed_mult() -> float:
	if statuses.has("stun") or statuses.has("freeze"):
		return 0.0
	if statuses.has("snare"):
		return 0.45
	if statuses.has("chill"):
		return 0.65
	return 1.0

func tick_statuses(delta: float) -> void:
	stun_immune_t = maxf(0.0, stun_immune_t - delta)
	var expired := []
	for k in statuses:
		var s: Dictionary = statuses[k]
		s["t"] -= delta
		if s.has("dps"):
			s["tick"] += delta
			if s["tick"] >= 0.5:
				s["tick"] -= 0.5
				take_dot(s["dps"] * 0.5, s.get("dtype", "physical"))
				if not alive:
					return
		if s["t"] <= 0:
			expired.append(k)
	for k in expired:
		statuses.erase(k)

func take_dot(amount: float, dtype: String) -> void:
	var dealt := amount * dot_resist(dtype)
	if dealt <= 0:
		return
	life -= dealt
	if level != null and randf() < 0.5:
		Combat.number(level, global_position, str(int(ceil(dealt))), Combat.TYPE_COLORS.get(dtype, Color.WHITE) * Color(1, 1, 1, 0.8))
	if life <= 0:
		die(null)

func dot_resist(_dtype: String) -> float:
	return 1.0

# ------------------------------------------------------------- hit stun (data/stun.json)
## Rolls the armour/health stun for a hit. `dmg` is the life actually lost (after
## armour, resistances, DR and shields), so armour reduces stuns without double dipping.
## kind: "player", "normal" or "elite". Returns the stun duration (0 = no stun).
func try_hit_stun(dmg: float, kind: String, thr_mult: float = 1.0) -> float:
	var cfg: Dictionary = Data.stun_cfg
	if not alive or stun_immune_t > 0.0 or cfg.is_empty() or not cfg.get("enabled", false):
		return 0.0
	var chance: float = Stun.stun_chance(cfg, kind, dmg, max_life, thr_mult)
	if chance <= 0.0:
		return 0.0
	if chance < 1.0 and Combat.rng.randf() > chance:   # seeded RNG keeps the smartbot deterministic
		return 0.0
	var dur: float = Stun.stun_duration(cfg, kind, dmg, max_life, thr_mult)
	stun_immune_t = dur + float(cfg.get("immunity_after_stun", 0.0))
	add_status("stun", dur, {})
	statuses["stun"]["dur"] = statuses["stun"]["t"]
	if level != null:
		Combat.number(level, global_position + Vector2(0, -10), "Stunned", Color("#ffe070"))
	return dur

## Seconds since the current stun started (0 when not stunned).
func stun_elapsed() -> float:
	var s = statuses.get("stun")
	if s == null:
		return 0.0
	return float(s.get("dur", s["t"])) - float(s["t"])

# ------------------------------------------------------------- damage hooks
## Override in subclasses. rolled = {type: amount}. Returns damage actually dealt.
func receive_hit(rolled: Dictionary, _p: Dictionary, source, crit: bool) -> float:
	var total := 0.0
	for t in rolled:
		total += rolled[t]
	apply_damage(total, source, crit, Combat.dominant_type(rolled))
	return total

func apply_damage(total: float, source, crit: bool, dtype: String) -> void:
	if not alive:
		return
	life -= total
	flash = 0.12
	recently_hit = 2.0
	if level != null:
		var col: Color = Combat.TYPE_COLORS.get(dtype, Color.WHITE)
		if faction != "enemy":
			col = Color("#ff5050")
		if crit:
			col = Color("#ffe040")
		Combat.number(level, global_position, str(int(ceil(total))) + ("!" if crit else ""), col, crit)
	if life <= 0:
		die(source)

func heal(amount: float) -> void:
	if not alive or amount <= 0:
		return
	life = minf(max_life, life + amount)

func die(_killer) -> void:
	if not alive:
		return
	alive = false
	queue_free()

# ------------------------------------------------------------- visuals
func update_visual(delta: float, moving: bool) -> void:
	anim_t += delta
	if sprite == null:
		return
	if flash > 0:
		flash -= delta
		sprite.modulate = Color(3, 3, 3, 1)
	else:
		var c := Color(1, 1, 1, 1)
		if statuses.has("freeze"):
			c = Color(0.5, 0.8, 1.6)
		elif statuses.has("poison"):
			c = Color(0.7, 1.2, 0.6)
		elif statuses.has("frailty") or statuses.has("marked"):
			c = Color(1.2, 0.7, 1.2)
		if statuses.has("stun"):
			c = Color(1.35, 1.3, 0.75) if int(anim_t * 10.0) % 2 == 0 else Color(1.0, 1.0, 0.85)
		if statuses.has("chill"):
			c = Color(0.6, 0.85, 1.3)
		if statuses.has("ignite"):
			c = c * Color(1.3, 0.85, 0.6)
		if statuses.has("shock"):
			c = c * Color(1.2, 1.2, 0.7)
		sprite.modulate = c
	sprite.flip_h = facing < 0
	if moving:
		sprite.position.y = -absf(sin(anim_t * 12.0)) * 1.5
		sprite.rotation = sin(anim_t * 12.0) * 0.06
	else:
		sprite.position.y = sin(anim_t * 2.5) * 0.4
		sprite.rotation = 0
