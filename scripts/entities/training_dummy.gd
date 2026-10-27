extends "res://scripts/entities/actor.gd"
## Training Grounds dummy (hub only). An immortal, immovable target that takes damage through
## the normal combat path (Combat.deal -> receive_hit) and reports every damage event to the
## TrainingLog. It never changes how combat works: the same mitigation as enemy.gd, statuses
## apply normally, nothing moves it, nothing stuns it. The maths lives in training_rules.gd,
## the session in the TrainingLog autoload; this node only displays and forwards.
## No randomness here: no global randf()/randi(), no Combat/Loot RNG calls of its own.

const TrainingRules = preload("res://scripts/core/training_rules.gd")

var idx := 1                 # 1..3 (shown small under the dummy in AoE tests)
var count := 1               # dummies in this test
var armour := 0.0
var resist := {}
var poise_on := false        # T6 boss profile: gold poise bar, breaks are counted
var poise_state := {}
var poise_life := 1.0        # the reference boss's life, so poise fills like it would on the real boss
var aggro := false           # enemy-shaped fields other systems read from level.enemies
var elite_color := Color.WHITE
var _tick_n := 0
var _poise_flash := 0.0

func setup_dummy(i: int, n: int, defence: Dictionary) -> void:
	idx = i
	count = n
	faction = "enemy"
	display_name = "Training Dummy"
	var d: Dictionary = TrainingLog.cfg().get("dummy", {})
	max_life = float(d.get("max_life", 1000000000.0))
	life = max_life
	armour = float(defence.get("armour", 0.0))
	resist = defence.get("resist", {}).duplicate()
	poise_on = bool(defence.get("poise", false))
	if poise_on:
		poise_state = Stun.new_poise()
		poise_life = maxf(1.0, float(defence.get("life", 1.0)))
		is_boss = true     # bosses take boss-only bonuses and shorter freezes, like the real thing
	setup_body(7.0, LAYER_ENEMY, 0)   # blocks the player and minions; never moves itself
	setup_sprite(Art.sprite(str(d.get("sprite", "training_dummy"))), 0.0, 1.0)
	add_to_group("training_dummy")
	TrainingLog.result_ready.connect(_on_result)

## The window ended: statuses are cleared so nothing keeps ticking into the result.
func _on_result(_res) -> void:
	statuses.clear()

func _physics_process(delta: float) -> void:
	if not alive or level == null:
		return
	if idx == 1:
		TrainingLog.tick(delta)       # one clock per test, scaled delta (pause, hit-stop, Dev time scale)
	life = max_life
	knock = Vector2.ZERO
	recently_hit -= delta
	_poise_flash = maxf(0.0, _poise_flash - delta)
	if poise_on:
		Stun.poise_tick(Data.stun_cfg, poise_state, delta)
	tick_statuses(delta)
	update_visual(delta, false)
	queue_redraw()

# ------------------------------------------------------------- damage
func receive_hit(rolled: Dictionary, p: Dictionary, source, crit: bool) -> float:
	if not alive:
		return 0.0
	var arm := armour * (0.5 if p.get("flags", {}).has("armour_pen") else 1.0)
	var total: float = TrainingRules.mitigate(rolled, arm, resist, statuses.has("frailty"), taken_mult(), Callable(Combat, "armour_reduction"))
	apply_damage(total, source, crit, Combat.dominant_type(rolled))   # number + flash; life is refilled below
	life = max_life
	if p.get("faction", "") == "player" and total > 0.0:
		TrainingLog.report(_hit_event(p, source, total, crit))
		if poise_on and Stun.poise_hit(Data.stun_cfg, poise_state, total, poise_life):
			TrainingLog.report_poise_break()
			_poise_flash = 0.25
			flash = 0.25
	return total

func _hit_event(p: Dictionary, source, amount: float, crit: bool) -> Dictionary:
	var skill: String = str(p.get("src_skill", ""))
	if skill == "":
		skill = str(p.get("skill", ""))
	var pk: String = str(p.get("kind", ""))
	var kind := "hit"
	if pk == "minion":
		kind = "minion"
	elif pk == "trap" or pk == "turret":
		kind = "deployable"
	if skill == "":
		TrainingLog.note_unattributed("kind=%s source=%s" % [pk, str(source.get("display_name")) if source != null and is_instance_valid(source) else "?"])
	return {"kind": kind, "amount": amount, "skill_id": skill, "status_id": "", "crit": crit,
		"dummy": idx, "cast_id": int(p.get("cast", -1)) if kind == "hit" else -1}

## Status ticks (ignite, bleed, poison, agony...). Same 0.5 s cadence and maths as actor.gd /
## enemy.gd, but each tick is reported with the status and the skill that applied it.
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
				_status_tick(k, s)
		if s["t"] <= 0:
			expired.append(k)
	for k in expired:
		statuses.erase(k)

func _status_tick(status_id: String, s: Dictionary) -> void:
	var dtype: String = s.get("dtype", "physical")
	var dealt: float = float(s["dps"]) * 0.5 * dot_resist(dtype)
	if dealt <= 0.0:
		return
	_show_tick(dealt, dtype)
	var sk_kind: String = str(s.get("src_kind", ""))
	var kind := "dot"
	if sk_kind == "minion":
		kind = "minion"
	elif sk_kind == "trap" or sk_kind == "turret":
		kind = "deployable"
	var skill: String = str(s.get("src_skill", ""))
	if skill == "":
		TrainingLog.note_unattributed("status=%s (no source recorded)" % status_id)
	TrainingLog.report({"kind": kind, "amount": dealt, "skill_id": skill, "status_id": status_id,
		"crit": false, "dummy": idx, "cast_id": -1})

## Same as enemy.gd: resistance of the damage type and the taken-damage multiplier.
func dot_resist(dtype: String) -> float:
	return (1.0 - clampf(float(resist.get(dtype, 0)), -100, 90) / 100.0) * taken_mult()

## Something outside the status system dealt damage over time (not used today): counted as "Other".
func take_dot(amount: float, dtype: String) -> void:
	var dealt := amount * dot_resist(dtype)
	if dealt <= 0.0:
		return
	_show_tick(dealt, dtype)
	TrainingLog.note_unattributed("take_dot(%s)" % dtype)
	TrainingLog.report({"kind": "dot", "amount": dealt, "skill_id": "", "status_id": "dot", "crit": false, "dummy": idx, "cast_id": -1})

func _show_tick(dealt: float, dtype: String) -> void:
	_tick_n += 1
	if level != null and _tick_n % 2 == 0:   # every other tick, no random numbers
		Combat.number(level, global_position, str(int(ceil(dealt))), Combat.TYPE_COLORS.get(dtype, Color.WHITE) * Color(1, 1, 1, 0.8))

func die(_killer) -> void:
	pass   # immortal: Dev "kill all" and anything else that calls die() has no effect

# ------------------------------------------------------------- label above the head
func _draw() -> void:
	var f := ThemeDB.fallback_font
	if poise_on:
		var w := 22.0
		draw_rect(Rect2(-w / 2.0, 5.0, w, 3.0), Color(0, 0, 0, 0.7))
		var frac: float = clampf(float(poise_state.get("poise", 0.0)) / 100.0, 0.0, 1.0)
		draw_rect(Rect2(-w / 2.0 + 0.5, 5.5, (w - 1.0) * frac, 2.0), Color("#fff0a0") if _poise_flash > 0.0 else Color("#e8c050"))
	if count > 1:
		var nt := str(idx)
		draw_string(f, Vector2(-2.0, 17.0), nt, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(1, 1, 1, 0.55))
	var lines: Array = TrainingLog.head_lines(idx)
	var y := -24.0
	for i in range(lines.size() - 1, -1, -1):
		var fs := 8
		var col := Color("#e0d8c8")
		if lines.size() == 1:
			col = Color("#ffe080")
		elif i == 0:
			col = Color("#ffe080")
		elif i == 1:
			col = Color("#c8c0b0")
		var t: String = lines[i]
		var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string_outline(f, Vector2(-tw / 2.0, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.9))
		draw_string(f, Vector2(-tw / 2.0, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		y -= 10.0
