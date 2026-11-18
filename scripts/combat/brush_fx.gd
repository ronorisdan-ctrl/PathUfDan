extends RefCounted
## Endgame 3D: the Overpainter's brushes (data/uniques.json, effect_params). Called from
## Combat._on_hit_passives (The Broad Stroke, The Rigger) and from the player after a skill is
## used (The Glazier). Extra hits made here carry `brush_extra` so they never trigger a brush again.

const WetPaint = preload("res://scripts/entities/wet_paint.gd")
const VFX = preload("res://scripts/fx/vfx.gd")

static func params(uid: String) -> Dictionary:
	return Data.uniques.get(uid, {}).get("effect_params", {})

## A copy of packet p dealing mult x its damage, without brush flags.
static func _scaled(p: Dictionary, mult: float) -> Dictionary:
	var p2 := p.duplicate()
	var f2: Dictionary = p.get("flags", {}).duplicate()
	for f in ["broad_stroke", "the_rigger", "the_glazier"]:
		f2.erase(f)
	p2["flags"] = f2
	var d2 := {}
	for t in p.get("dmg", {}):
		d2[t] = [float(p["dmg"][t][0]) * mult, float(p["dmg"][t][1]) * mult]
	p2["dmg"] = d2
	p2["brush_extra"] = true
	return p2

static func on_hit(p: Dictionary, fl: Dictionary, source, target, tags: Array) -> void:
	if p.get("brush_extra", false) or source == null or not is_instance_valid(source) or target == null or not is_instance_valid(target):
		return
	if fl.has("broad_stroke") and tags.has("melee"):
		_broad_stroke(p, source, target)
	if fl.has("the_rigger") and tags.has("projectile"):
		_rigger(p, source, target)

# ------------------------------------------------------------------ The Broad Stroke
static func _broad_stroke(p: Dictionary, source, target) -> void:
	var bp := params("broad_stroke")
	var n := int(source.get_meta("brush_stroke_n", 0)) + 1
	if n < maxi(1, int(bp.get("every", 4))):
		source.set_meta("brush_stroke_n", n)
		return
	source.set_meta("brush_stroke_n", 0)
	var lv = target.level
	if lv == null:
		return
	var from: Vector2 = source.global_position
	var dir: Vector2 = (target.global_position - from)
	dir = dir.normalized() if dir.length() > 1.0 else Vector2.RIGHT
	var length := float(bp.get("length", 180))
	var width := float(bp.get("width", 50))
	var to: Vector2 = lv.clamp_to_floor(from, from + dir * length)
	var p2 := _scaled(p, float(bp.get("mult", 1.2)))
	for e in lv.hostiles_in_radius(from + (to - from) * 0.5, from.distance_to(to) * 0.5 + width, "player"):
		if is_instance_valid(e) and e.alive and WetPaint.seg_dist(e.global_position, from, to) <= width * 0.5 + float(e.radius):
			Combat.deal(p2, source, e, from)
	var wp = WetPaint.new()
	wp.setup(lv, source, from, to, bp)
	lv.floor_layer.add_child(wp)
	source.set_meta("brush_strokes", int(source.get_meta("brush_strokes", 0)) + 1)   # tests / telemetry

# ------------------------------------------------------------------ The Rigger
static func _rigger(p: Dictionary, source, target) -> void:
	var bp := params("the_rigger")
	var lv = target.level
	if lv == null:
		return
	var was_painted := float(target.get_meta("rigger_until", -1.0)) > lv_time(lv)
	target.set_meta("rigger_until", lv_time(lv) + float(bp.get("paint_life", 4.0)))
	if not was_painted or float(target.get_meta("rigger_cd", -1.0)) > lv_time(lv):
		return
	target.set_meta("rigger_cd", lv_time(lv) + float(bp.get("cooldown", 0.5)))
	var reach := float(bp.get("reach", 240))
	var others := []
	for e in lv.hostiles_in_radius(target.global_position, reach, "player"):
		if e != target and is_instance_valid(e) and e.alive and float(e.get_meta("rigger_until", -1.0)) > lv_time(lv):
			others.append(e)
	others.sort_custom(func(x, y): return x.global_position.distance_squared_to(target.global_position) < y.global_position.distance_squared_to(target.global_position))
	var links := mini(others.size(), int(bp.get("links", 3)))
	if links <= 0:
		return
	var p2 := _scaled(p, float(bp.get("mult", 0.6)))
	var lw := float(bp.get("line_width", 10))
	var a: Vector2 = target.global_position
	for i in links:
		var b: Vector2 = others[i].global_position
		for e in lv.hostiles_in_radius(a + (b - a) * 0.5, a.distance_to(b) * 0.5 + lw + 20.0, "player"):
			if is_instance_valid(e) and e.alive and e != target and WetPaint.seg_dist(e.global_position, a, b) <= lw + float(e.radius):
				Combat.deal(p2, source, e, a)
		var v = VFX.make("bolt", Vector2.ZERO, Color("#e8e0c8"), 0.25, 6)
		v.points = PackedVector2Array([a + Vector2(0, -6), b + Vector2(0, -6)])
		lv.add_fx(v)
	source.set_meta("brush_lines", int(source.get_meta("brush_lines", 0)) + links)   # tests / telemetry

## Game time of a level in seconds (physics frames; tests run at a fixed 60 fps).
static func lv_time(lv) -> float:
	return float(Engine.get_physics_frames()) / float(Engine.physics_ticks_per_second)

# ------------------------------------------------------------------ The Glazier
## After a skill is used. Spells add a Glaze layer (+per_layer% spell damage, refreshed); a spell
## cast at max_layers spends them and casts again (the echo deals echo_mult damage).
static func on_cast(pl, sk: Dictionary, aim: Vector2) -> void:
	if pl == null or not pl.ch.stats.has_flag("the_glazier") or sk.get("kind", "") != "spell" or sk.get("_echo_mult", 0.0) > 0.0:
		return
	var bp := params("the_glazier")
	var mx := maxi(1, int(bp.get("max_layers", 5)))
	var now := lv_time(pl.level)
	var n := int(pl.get_meta("glaze_layers", 0)) if float(pl.get_meta("glaze_until", -1.0)) > now else 0
	if n >= mx:
		pl.set_meta("glaze_layers", 0)
		pl.set_meta("glaze_until", -1.0)
		pl.buffs = pl.buffs.filter(func(x): return x["id"] != "glaze")
		pl.refresh_stats()
		var sk2: Dictionary = sk.duplicate()
		sk2["_echo_mult"] = float(bp.get("echo_mult", 0.7))
		pl.set_meta("glaze_echoes", int(pl.get_meta("glaze_echoes", 0)) + 1)   # tests / telemetry
		pl.schedule(float(bp.get("echo_delay", 0.2)), func():
			if is_instance_valid(pl) and pl.alive and pl.level != null:
				pl.exec.execute(pl, sk2, aim))
		return
	n += 1
	pl.set_meta("glaze_layers", n)
	pl.set_meta("glaze_until", now + float(bp.get("layer_life", 6.0)))
	pl.buffs = pl.buffs.filter(func(x): return x["id"] != "glaze")
	pl.add_buff("glaze", [{"stat": "spell_damage", "type": "inc", "value": float(bp.get("per_layer", 4)) * n}], float(bp.get("layer_life", 6.0)))
