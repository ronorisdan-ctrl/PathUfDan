extends Node
## Damage model shared by every attacker and defender.
##
## Hit damage = base (weapon x effectiveness, or skill base) x level scaling
##            x (1 + sum of all applicable "increased" %) x product of "more" multipliers
##            x crit multiplier (if crit) x conditional multipliers (elites, keystones, legendaries)
## Mitigation (defender): evasion (attacks only) -> block -> armour (physical) / resistances (elemental)
##                        -> generic damage reduction. All caps are defined here.

const DamageNumber = preload("res://scripts/fx/damage_number.gd")

const DAMAGE_TYPES := ["physical", "fire", "cold", "lightning", "arcane", "void"]
const ELEMENTAL := ["fire", "cold", "lightning"]
const TYPE_COLORS := {
	"physical": Color("#f0e8d8"), "fire": Color("#ff8a3a"), "cold": Color("#8ad8ff"),
	"lightning": Color("#fff27a"), "arcane": Color("#d090ff"), "void": Color("#a060c0"),
}
const ARMOUR_FACTOR := 12.0
const ARMOUR_CAP := 0.8
const RES_CAP := 75.0
const DR_CAP := 60.0
const EVADE_CAP := 0.6
const MAX_NUMBERS := 60

var rng := RandomNumberGenerator.new()
var _numbers := 0
var cast_serial := 0   # +1 per player skill use (player.try_use_slot); packets carry it as "cast" (Training Grounds only reads it)

func _ready() -> void:
	rng.randomize()

# ---------------------------------------------------------------- packet building
func level_mult(lvl: int) -> float:
	return 1.0 + 0.12 * (lvl - 1)

## Damage packet for a player skill. extra_more multiplies everything (momentum etc.)
func player_packet(ch, skill: Dictionary, extra_more: float = 1.0) -> Dictionary:
	extra_more *= float(skill.get("damage_mult", 1.0))
	if skill.has("shield_bonus") and ch.has_shield():
		extra_more *= 1.0 + float(skill["shield_bonus"]) / 100.0
	var sb = ch.stats
	var f: Dictionary = ch.final
	var lvl: int = ch.skill_level(skill["id"])
	var kind: String = skill.get("kind", "spell")
	var tags: Array = skill.get("tags", [])
	var base := {}
	var crit_base := float(skill.get("crit", 5))
	if kind == "attack":
		var eff := float(skill.get("weapon_eff", 100)) / 100.0 * (1.0 + 0.04 * (lvl - 1))
		base["physical"] = [f["weapon_min"] * eff, f["weapon_max"] * eff]
		for t in ["physical", "fire", "cold", "lightning"]:
			var added: float = sb.value("added_" + t)
			if added > 0:
				var cur: Array = base.get(t, [0.0, 0.0])
				base[t] = [cur[0] + added * 0.7 * eff, cur[1] + added * 1.3 * eff]
		crit_base = f["weapon_crit"]
		var conv: String = skill.get("dmg_type", "physical")
		if conv != "physical" and skill.get("convert", false):
			base[conv] = base["physical"]
			base.erase("physical")
	else:
		var bd: Array = skill.get("base_damage", [1, 2])
		var lm := level_mult(lvl)
		base[skill.get("dmg_type", "physical")] = [float(bd[0]) * lm, float(bd[1]) * lm]
	var common := ["damage"]
	for t in tags:
		if DAMAGE_TYPES.has(t):
			continue
		var st: String = t + "_damage"
		if Data.stat_info.has(st):
			common.append(st)
	if kind == "attack":
		var w = ch.weapon()
		if w != null:
			var wt: Array = w.get("tags", [])
			if wt.has("bow"):
				common.append("bow_damage")
			if wt.has("firearm"):
				common.append("firearm_damage")
			if wt.has("two_handed"):
				common.append("two_handed_damage")
			if wt.has("one_handed"):
				common.append("one_handed_damage")
	elif kind == "trap":
		if not common.has("trap_damage"):
			common.append("trap_damage")
	elif kind == "turret":
		if not common.has("turret_damage"):
			common.append("turret_damage")
	var dmg := {}
	for t in base:
		var stats := common.duplicate()
		stats.append(t + "_damage")
		if ELEMENTAL.has(t):
			stats.append("elemental_damage")
		var mult: float = maxf(0.0, 1.0 + sb.inc_sum(stats) / 100.0) * sb.more_prod(stats) * extra_more
		dmg[t] = [base[t][0] * mult, base[t][1] * mult]
	var crit_chance: float = clampf((crit_base + sb.value("crit_chance_flat")) * maxf(0.0, 1.0 + sb.inc("crit_chance") / 100.0), 0, 95)
	var crit_mult: float = 1.5 + sb.value("crit_multi") / 100.0
	var statuses := []
	if sb.has_flag("warlord") and tags.has("melee"):
		statuses.append({"type": "intimidate", "chance": 30.0, "duration": 4.0})
	if sb.has_flag("warlords_grip") and tags.has("melee"):
		statuses.append({"type": "stun", "chance": 15.0})
	if sb.has_flag("toxic_traps") and kind == "trap":
		statuses.append({"type": "poison", "chance": 60.0})
	var st: Dictionary = skill.get("status", {})
	if not st.is_empty():
		var ch2: float = float(st.get("chance", 0)) + sb.value("status_chance")
		if st.get("type") == "chill" and sb.has_flag("deep_freeze"):
			ch2 += 30.0
		if st.get("type") == "ignite":
			ch2 += sb.value("ignite_chance")
		statuses.append({"type": st["type"], "chance": ch2, "duration": float(st.get("duration", 0))})
	if dmg.has("fire") and (st.is_empty() or st.get("type") != "ignite"):
		var ic: float = sb.value("ignite_chance")
		if ic > 0:
			statuses.append({"type": "ignite", "chance": ic})
	if kind == "attack" and dmg.has("physical"):
		var bc: float = sb.value("bleed_chance")
		if bc > 0:
			statuses.append({"type": "bleed", "chance": bc})
	return {
		"dmg": dmg, "crit_chance": crit_chance, "crit_mult": crit_mult, "kind": kind, "tags": tags,
		"status": statuses, "is_attack": kind == "attack", "faction": "player", "skill": skill["id"], "cast": cast_serial,
		"elite_inc": sb.inc("damage_vs_elite"), "flags": sb.flags.duplicate(),
		"dot_mult": maxf(0.0, 1.0 + sb.inc("dot_damage") / 100.0) * sb.more("dot_damage"),
		"status_dur": maxf(0.1, 1.0 + sb.inc("status_duration") / 100.0),
		"knockback": float(skill.get("knockback", 0)), "life_on_hit": f.get("life_on_hit", 0.0),
		"execute": float(skill.get("execute", 0)),
		"leech": float(skill.get("leech", 0)), "elite_bonus": float(skill.get("elite_bonus", 0)),
	}

func minion_packet(ch, mdef: Dictionary, lvl: int) -> Dictionary:
	var sb = ch.stats
	var d: Array = mdef.get("damage", [2, 4])
	var lm := 1.0 + float(mdef.get("damage_per_level", 0.12)) * (lvl - 1)
	var mult: float = maxf(0.0, 1.0 + sb.inc("minion_damage") / 100.0) * sb.more("minion_damage")
	if sb.has_flag("pack_leader"):
		mult *= 1.0 + clampf(sb.inc("move_speed"), 0.0, 40.0) / 100.0
	var t: String = mdef.get("dmg_type", "physical")
	var st := []
	if mdef.has("status"):
		st.append(mdef["status"])
	return {"dmg": {t: [float(d[0]) * lm * mult, float(d[1]) * lm * mult]}, "crit_chance": 5.0, "crit_mult": 1.5,
			"kind": "minion", "tags": ["minion"], "status": st, "is_attack": true, "faction": "player", "skill": "minion",
			"elite_inc": 0.0, "flags": {}, "dot_mult": 1.0, "status_dur": 1.0, "knockback": 4.0, "life_on_hit": 0.0}

func enemy_packet(e, mult: float = 1.0) -> Dictionary:
	var d: Array = e.def.get("damage", [2, 4])
	var lm: float = 1.0 + 0.13 * (e.mlevel - 1)
	var m: float = lm * mult * e.damage_mult
	var t: String = e.def.get("dmg_type", "physical")
	if e.convert_type != "":
		t = e.convert_type
	var statuses := []
	if e.on_hit_status != "":
		statuses.append({"type": e.on_hit_status, "chance": 100.0})
	var st: Dictionary = e.def.get("status", {})
	if not st.is_empty():
		statuses.append({"type": st["type"], "chance": float(st.get("chance", 0))})
	var dmg := {t: [float(d[0]) * m, float(d[1]) * m]}
	var af: float = e.added_fire
	if af > 0:
		var cur: Array = dmg.get("fire", [0.0, 0.0])
		dmg["fire"] = [cur[0] + float(d[0]) * m * af, cur[1] + float(d[1]) * m * af]
	return {"dmg": dmg, "crit_chance": 5.0, "crit_mult": 1.5, "kind": "enemy",
			"tags": [], "status": statuses, "is_attack": e.def.get("attack", "") in ["melee", "slam", "boss", "dash"] or e.def.get("proj", "") == "arrow",
			"faction": "enemy", "skill": "", "elite_inc": 0.0, "flags": {}, "dot_mult": 1.0, "status_dur": 1.0,
			"knockback": 0.0, "life_on_hit": 0.0, "leech": e.leech}

## Average hit for UI display (skills panel, tooltips)
func packet_average(p: Dictionary) -> float:
	var t := 0.0
	for k in p.get("dmg", {}):
		t += (p["dmg"][k][0] + p["dmg"][k][1]) * 0.5
	var c: float = p.get("crit_chance", 0.0) / 100.0
	return t * (1.0 + c * (p.get("crit_mult", 1.5) - 1.0))

# ---------------------------------------------------------------- hit resolution
func deal(p: Dictionary, source, target, origin: Vector2 = Vector2.INF) -> float:
	if target == null or not is_instance_valid(target) or not target.alive:
		return 0.0
	var crit: bool = rng.randf() * 100.0 < float(p.get("crit_chance", 0))
	if not crit and p.get("faction") == "player" and p.get("flags", {}).has("executioner") and target.life < target.max_life * 0.35:
		crit = true
	var rolled := {}
	var m := 1.0
	if crit:
		m *= float(p.get("crit_mult", 1.5))
	if p.get("faction") == "player":
		m *= _conditional(p, target, origin)
		m *= Dev.hit_mult()   # developer damage multiplier / one-hit kills (1.0 unless dev tools are on)
	for t in p["dmg"]:
		var r: Array = p["dmg"][t]
		rolled[t] = rng.randf_range(r[0], r[1]) * m
	var dealt: float = target.receive_hit(rolled, p, source, crit)
	if dealt > 0 and target.faction == "enemy":
		Sfx.play("crit" if crit else "hit")
		if p.get("faction") == "player" and p.get("kind") != "minion":
			_impact_freeze(target, dealt, crit)
	if dealt > 0 and target.alive:
		for s in p.get("status", []):
			if rng.randf() * 100.0 < float(s.get("chance", 0)):
				apply_status(target, s, rolled, p)
	if dealt > 0 and is_instance_valid(source) and source.alive:
		var loh: float = p.get("life_on_hit", 0.0)
		if loh > 0:
			source.heal(loh)
		var leech: float = p.get("leech", 0.0)
		if p.get("flags", {}).has("vampiric") and "ch" in source:
			leech += 0.02
		if leech > 0:
			source.heal(dealt * leech)
	return dealt

## Hit-stop tiers: boss kill > elite kill > crit > heavy hit. Ordinary kills and hits never freeze.
func _impact_freeze(target, dealt: float, crit: bool) -> void:
	var sec := 0.0
	if not target.alive:
		if target.is_boss:
			sec = 0.07
		elif target.is_elite:
			sec = 0.06
	if crit:
		sec = maxf(sec, 0.045)
	if dealt >= 0.2 * target.max_life:
		sec = maxf(sec, 0.04)
	if sec > 0.0:
		Game.hitstop(sec)

func _conditional(p: Dictionary, target, origin: Vector2) -> float:
	var m := 1.0
	var fl: Dictionary = p.get("flags", {})
	if target.is_elite or target.is_boss:
		m *= 1.0 + float(p.get("elite_inc", 0.0)) / 100.0
		m *= 1.0 + float(p.get("elite_bonus", 0.0)) / 100.0
	var ex := float(p.get("execute", 0.0))
	if ex > 0 and target.life < target.max_life * 0.35:
		m *= 1.0 + ex / 100.0
	if fl.has("far_shot") and p.get("tags", []).has("projectile") and origin != Vector2.INF:
		m *= 1.0 + 0.3 * clampf((origin.distance_to(target.global_position) - 60.0) / 190.0, 0.0, 1.0)
	if fl.has("widowmaker") and target.level != null and target.level.is_isolated(target, 110.0):
		m *= 1.5
	if fl.has("perfect_aim") and p.get("tags", []).has("projectile") and origin != Vector2.INF:
		var d := origin.distance_to(target.global_position)
		if d > 180:
			m *= 1.3
		elif d < 100:
			m *= 0.7
	if fl.has("void_pact") and not target.statuses.is_empty():
		m *= 1.25
	if fl.has("convergence"):
		var types: Dictionary = p.get("dmg", {})
		var st: Dictionary = target.statuses
		if st.is_empty():
			m *= 0.9
		elif (types.has("fire") and (st.has("chill") or st.has("shock"))) or ((types.has("cold") or types.has("lightning")) and st.has("ignite")):
			m *= 1.35
	return m

func apply_status(target, s: Dictionary, rolled: Dictionary, p: Dictionary) -> void:
	var dur_mult: float = p.get("status_dur", 1.0)
	var dot_mult: float = p.get("dot_mult", 1.0)
	var typ: String = s["type"]
	match typ:
		"ignite":
			var base: float = rolled.get("fire", 0.0)
			if base <= 0:
				base = _sum(rolled) * 0.5
			target.add_status("ignite", 3.0 * dur_mult, {"dps": base * 0.5 * dot_mult, "dtype": "fire"})
			if p.get("flags", {}).has("ember_heart") and not s.get("spread", false) and target.level != null:
				var best = null
				var bd := 90.0
				for o in target.level.hostiles_in_radius(target.global_position, 90.0, "player"):
					if o != target and not o.has_status("ignite"):
						var dd: float = o.global_position.distance_to(target.global_position)
						if dd < bd:
							bd = dd
							best = o
				if best != null:
					best.add_status("ignite", 3.0 * dur_mult, {"dps": base * 0.5 * dot_mult, "dtype": "fire"})
					_tag_source(best, "ignite", p)
		"bleed":
			var base2: float = rolled.get("physical", _sum(rolled))
			var cd_m := 1.6 if p.get("flags", {}).has("crimson_dance") else 1.0
			target.add_status("bleed", 4.0 * dur_mult * (1.5 if cd_m > 1.0 else 1.0), {"dps": base2 * 0.35 * dot_mult * cd_m, "dtype": "physical"})
		"chill":
			var fl: Dictionary = p.get("flags", {})
			if fl.has("deep_freeze") and target.has_status("chill"):
				target.statuses.erase("chill")
				target.add_status("freeze", (0.3 if target.is_boss else 1.0) * dur_mult, {"mag": 1.25})
			else:
				target.add_status("chill", 2.0 * dur_mult, {})
		"freeze":
			target.add_status("freeze", (0.3 if target.is_boss else 1.0) * dur_mult, {"mag": 1.1})
		"shock":
			var mag := 1.35 if p.get("flags", {}).has("overcharge") else 1.2
			target.add_status("shock", 3.0 * dur_mult, {"mag": mag})
		"poison":
			target.add_status("poison", 4.0 * dur_mult, {"dps": _sum(rolled) * 0.3 * dot_mult, "dtype": "void"})
		"agony":
			target.add_status("agony", float(s.get("duration", 6.0)) * dur_mult, {"dps": maxf(float(s.get("dps", 0.0)), _sum(rolled) * 0.4) * dot_mult, "dtype": "void"})
		"frailty", "marked", "snare":
			target.add_status(typ, float(s.get("duration", 5.0)) * dur_mult, {})
		"stun":
			target.add_status("stun", (0.2 if target.is_boss else 0.6) * dur_mult, {})
		"intimidate":
			var d := float(s.get("duration", 4.0))
			target.add_status("intimidate", (d if d > 0 else 4.0) * dur_mult, {})
		_:
			target.add_status(typ, 2.0 * dur_mult, {})
	_tag_source(target, typ, p)

## Remembers who applied a status (skill id + skill kind) so the Training Grounds can credit
## its DoT ticks. Data only: nothing in the game reads these two keys.
func _tag_source(target, typ: String, p: Dictionary) -> void:
	if p.get("faction") != "player":
		return
	var st = target.statuses.get(typ)
	if st == null:
		return
	var sk: String = str(p.get("src_skill", ""))
	if sk == "":
		sk = str(p.get("skill", ""))
	st["src_skill"] = sk
	st["src_kind"] = str(p.get("kind", ""))

func _sum(d: Dictionary) -> float:
	var t := 0.0
	for k in d:
		t += d[k]
	return t

func armour_reduction(armour: float, hit: float) -> float:
	if armour <= 0 or hit <= 0:
		return 0.0
	return minf(ARMOUR_CAP, armour / (armour + ARMOUR_FACTOR * hit))

func evade_chance(evasion: float, attacker_level: int) -> float:
	if evasion <= 0:
		return 0.0
	return minf(EVADE_CAP, evasion / (evasion + 150.0 + 25.0 * attacker_level))

# ---------------------------------------------------------------- feedback
func number(level, pos: Vector2, text: String, color: Color, big: bool = false) -> void:
	if level == null or _numbers >= MAX_NUMBERS:
		return
	var n = DamageNumber.new()
	n.setup(text, color, big)
	n.position = pos + Vector2(rng.randf_range(-6, 6), -14)
	n.tree_exited.connect(func(): _numbers -= 1)
	_numbers += 1
	level.fx_layer.add_child(n)

func dominant_type(rolled: Dictionary) -> String:
	var best := "physical"
	var bv := -1.0
	for k in rolled:
		if rolled[k] > bv:
			bv = rolled[k]
			best = k
	return best
