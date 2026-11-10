extends Node
## Damage model shared by every attacker and defender.
##
## Hit damage = base (weapon x effectiveness, or skill base) x level scaling
##            x (1 + sum of all applicable "increased" %) x product of "more" multipliers
##            x crit multiplier (if crit) x conditional multipliers (elites, keystones, legendaries)
## Mitigation (defender): evasion (attacks only) -> block -> armour (physical) / resistances (elemental)
##                        -> generic damage reduction. All caps are defined here.

const DamageNumber = preload("res://scripts/fx/damage_number.gd")
const VFX = preload("res://scripts/fx/vfx.gd")
const CorruptionEffects = preload("res://scripts/core/corruption_effects.gd")

const DAMAGE_TYPES := ["physical", "fire", "cold", "lightning", "arcane", "void"]
const ELEMENTAL := ["fire", "cold", "lightning"]
const ELEMENTAL_AILMENTS := ["ignite", "chill", "freeze", "shock"]
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
var _was_shocked := false   # Phase 3b Static Cascade: target was Shocked before the current hit
const AoEScript = preload("res://scripts/entities/aoe.gd")

func _ready() -> void:
	rng.randomize()

# ---------------------------------------------------------------- packet building
func level_mult(lvl: int) -> float:
	return 1.0 + 0.12 * (lvl - 1)

## Damage packet for a player skill. extra_more multiplies everything (momentum etc.)
## Caster itemisation (docs/CASTER_ITEMISATION.md): spells gain flat "added damage to spells"
## (the caster base implicit added_spell as the spell's own type, plus the elemental
## added_spell_<type> affixes), scaled like attack added damage: x 0.7..1.3 x effectiveness.
## Effectiveness = the spell's own base-damage average / caster.added_ref (clamped to
## eff_min..eff_max; override per skill with "added_eff") x (1 + 4% per skill level).
func spell_added_eff(skill: Dictionary, bd: Array, lvl: int) -> float:
	var cc: Dictionary = Data.loot.get("caster", {})
	var e: float = float(skill.get("added_eff", -1.0))
	if e < 0.0:
		e = clampf((float(bd[0]) + float(bd[1])) * 0.5 / float(cc.get("added_ref", 16.0)), float(cc.get("eff_min", 0.4)), float(cc.get("eff_max", 1.5)))
	return e * (1.0 + 0.04 * (lvl - 1))

func _caster_added(sb, skill: Dictionary, bd: Array, lvl: int, own: String, base: Dictionary) -> void:
	var eff := spell_added_eff(skill, bd, lvl)
	var own_added: float = sb.value("added_spell")
	if own_added > 0:
		base[own] = [base[own][0] + own_added * 0.7 * eff, base[own][1] + own_added * 1.3 * eff]
	for t in ["fire", "cold", "lightning"]:
		var added: float = sb.value("added_spell_" + t)
		if added > 0:
			var cur: Array = base.get(t, [0.0, 0.0])
			base[t] = [cur[0] + added * 0.7 * eff, cur[1] + added * 1.3 * eff]

func player_packet(ch, skill: Dictionary, extra_more: float = 1.0) -> Dictionary:
	extra_more *= float(skill.get("damage_mult", 1.0))
	if skill.has("shield_bonus") and ch.has_shield():
		extra_more *= 1.0 + float(skill["shield_bonus"]) / 100.0
	var sb = ch.stats
	var f: Dictionary = ch.final
	var lvl: int = ch.skill_level(skill["id"])
	var kind: String = skill.get("kind", "spell")
	var tags: Array = skill.get("tags", [])
	if sb.has_flag("earthbreaker") and tags.has("slam"):   # Phase 3b keystones: more damage for one skill family
		extra_more *= 1.35
	if sb.has_flag("master_trapper") and kind == "trap":
		extra_more *= 1.3
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
		var own: String = skill.get("dmg_type", "physical")
		base[own] = [float(bd[0]) * lm, float(bd[1]) * lm]
		if kind == "spell":
			_caster_added(sb, skill, bd, lvl, own, base)
	if sb.has_flag("avatar_of_embers"):   # Phase 2 keystone: cold and lightning become fire
		for ct in ["cold", "lightning"]:
			if base.has(ct):
				var fr: Array = base.get("fire", [0.0, 0.0])
				base["fire"] = [fr[0] + base[ct][0], fr[1] + base[ct][1]]
				base.erase(ct)
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
	# Phase 3 bridge keystones: spell increases reach attacks (and melee increases reach spells)
	if sb.has_flag("spell_archer") and kind == "attack" and tags.has("projectile") and not common.has("spell_damage"):
		common.append("spell_damage")
	if sb.has_flag("battlemage"):
		if kind == "attack" and tags.has("melee") and not common.has("spell_damage"):
			common.append("spell_damage")
		elif kind == "spell" and not common.has("melee_damage"):
			common.append("melee_damage")
	var dmg := {}
	var increased_by_type := {}
	var pre_increased := {}
	for t in base:
		var stats := common.duplicate()
		stats.append(t + "_damage")
		if ELEMENTAL.has(t):
			stats.append("elemental_damage")
		var mult: float = maxf(0.0, 1.0 + sb.inc_sum(stats) / 100.0) * sb.more_prod(stats) * extra_more
		increased_by_type[t] = sb.inc_sum(stats)
		var other_mult: float = sb.more_prod(stats) * extra_more
		pre_increased[t] = [base[t][0] * other_mult, base[t][1] * other_mult]
		dmg[t] = [base[t][0] * mult, base[t][1] * mult]
	if sb.has_flag("clockwork_mind") and kind in ["turret", "trap"]:
		crit_base = maxf(crit_base, float(f.get("weapon_crit", crit_base)))
	var crit_chance: float = clampf((crit_base + sb.value("crit_chance_flat")) * maxf(0.0, 1.0 + sb.inc("crit_chance") / 100.0), 0, 95)
	if sb.has_flag("venom_pact"):
		crit_chance = 0.0
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
	var pc := (20.0 if sb.has_flag("venom_pact") else 0.0) + (10.0 if sb.has_flag("agonising_toxins") else 0.0)
	if pc > 0:
		statuses.append({"type": "poison", "chance": pc})
	# Phase 3 status enablers
	if sb.has_flag("charged_quiver") and tags.has("projectile"):
		statuses.append({"type": "shock", "chance": 15.0})
	if sb.has_flag("engineers_doctrine") and kind in ["turret", "trap"]:
		statuses.append({"type": "shock", "chance": 15.0})
	if sb.has_flag("abyssal_gaze") and (dmg.has("void") or dmg.has("arcane")):
		statuses.append({"type": "frailty", "chance": 15.0, "duration": 4.0})
	# Phase 3b status enablers
	if tags.has("slam"):
		if sb.has_flag("tremor_lines"):
			statuses.append({"type": "snare", "chance": 100.0, "duration": 1.5})
		if sb.has_flag("earthbreaker"):
			statuses.append({"type": "stun", "chance": 100.0})
	if kind == "trap" and sb.has_flag("barbed_snares"):
		statuses.append({"type": "snare", "chance": 100.0, "duration": 2.0})
		statuses.append({"type": "bleed", "chance": 30.0})
	if sb.has_flag("glacial_heart") and dmg.has("cold"):
		statuses.append({"type": "chill", "chance": 100.0})
	if sb.has_flag("avatar_of_embers"):   # cannot chill, freeze or shock: those chances become ignite
		for s in statuses:
			if s["type"] in ["chill", "freeze", "shock"]:
				s["type"] = "ignite"
	if sb.has_flag("prismatic_soul"):   # Phase 3 keystone drawback: cannot inflict elemental ailments
		var kept := []
		for s in statuses:
			if not s["type"] in ELEMENTAL_AILMENTS:
				kept.append(s)
		statuses = kept
	return {
		"dmg": dmg, "crit_chance": crit_chance, "crit_mult": crit_mult, "kind": kind, "tags": tags,
		"status": statuses, "is_attack": kind == "attack", "faction": "player", "skill": skill["id"], "cast": cast_serial,
		# Historical elite bonuses remain multiplicative. Corruption explicitly uses increased%.
		"elite_inc": sb.inc("damage_vs_elite") - corruption_increased(sb, "damage_vs_elite"), "flags": sb.flags.duplicate(),
		"corruption_elite_inc": corruption_increased(sb, "damage_vs_elite"), "increased_by_type": increased_by_type,
		"pre_increased": pre_increased, "corruption_low_life_inc": CorruptionEffects.total(sb,"conditional_inc_damage:target_below_35pct_life"),
		"dot_mult": maxf(0.0, 1.0 + sb.inc("dot_damage") / 100.0) * sb.more("dot_damage"),
		"status_dur": maxf(0.1, 1.0 + sb.inc("status_duration") / 100.0),
		"knockback": float(skill.get("knockback", 0)), "life_on_hit": f.get("life_on_hit", 0.0),
		"execute": float(skill.get("execute", 0)),
		"leech": float(skill.get("leech", 0)), "elite_bonus": float(skill.get("elite_bonus", 0)),
		# caster itemisation: spells ignore this many points of fire/cold/lightning resistance
		"ele_pen": maxf(0.0, sb.value("spell_penetration")) if kind == "spell" else 0.0,
	}

func minion_packet(ch, mdef: Dictionary, lvl: int, owner_life_ratio: float = 1.0) -> Dictionary:
	var sb = ch.stats
	var d: Array = mdef.get("damage", [2, 4])
	var lm := 1.0 + float(mdef.get("damage_per_level", 0.12)) * (lvl - 1)
	var conditional := CorruptionEffects.total(sb,"conditional_minion_damage:player_below_35pct_life") if owner_life_ratio < 0.35 else 0.0
	var mult: float = maxf(0.0, 1.0 + (sb.inc("minion_damage") + conditional) / 100.0) * sb.more("minion_damage")
	if sb.has_flag("pack_leader"):
		mult *= 1.0 + clampf(sb.inc("move_speed"), 0.0, 40.0) / 100.0
	var t: String = mdef.get("dmg_type", "physical")
	var st := []
	if mdef.has("status"):
		st.append(mdef["status"])
	if sb.has_flag("necrotic_orders"):
		st.append({"type": "frailty", "chance": 20.0, "duration": 4.0})
	var mcc := 5.0
	var mcm := 1.5
	if sb.has_flag("commanders_edge"):   # Phase 3: minions use your crit chance increases and multiplier
		mcc = clampf((5.0 + sb.value("crit_chance_flat")) * maxf(0.0, 1.0 + sb.inc("crit_chance") / 100.0), 0, 95)
		mcm = 1.5 + sb.value("crit_multi") / 100.0
	return {"dmg": {t: [float(d[0]) * lm * mult, float(d[1]) * lm * mult]}, "crit_chance": mcc, "crit_mult": mcm,
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
	var fl: Dictionary = p.get("flags", {})
	var cc := float(p.get("crit_chance", 0))
	if fl.has("searing_insight") and p.get("faction") == "player" and target.has_status("ignite") and cc > 0:
		cc = minf(95.0, cc + 25.0)
	var ptags: Array = p.get("tags", [])
	if p.get("faction") == "player" and cc > 0:   # Phase 3 conditional crit chance
		if fl.has("run_them_down") and ptags.has("melee") and (target.has_status("snare") or target.has_status("chill")):
			cc = minf(95.0, cc + 20.0)
		if fl.has("hunter_knight") and ptags.has("projectile") and target.has_status("marked"):
			cc = minf(95.0, cc + 15.0)
		if fl.has("brittle") and target.has_status("freeze"):   # Phase 3b
			cc = minf(95.0, cc + 30.0)
	var crit: bool = rng.randf() * 100.0 < cc
	if not crit and p.get("faction") == "player" and fl.has("executioner") and not fl.has("venom_pact") and target.life < target.max_life * 0.35:
		crit = true
	if not crit and p.get("faction") == "player" and fl.has("brutal_force") and not fl.has("venom_pact") and ptags.has("melee") \
			and (target.has_status("stun") or target.has_status("freeze")):
		crit = true
	if p.get("faction") == "player" and fl.has("feint") and ptags.has("melee") and source != null and is_instance_valid(source) \
			and "feint_t" in source and source.feint_t > 0.0:   # Phase 3b Feint: the first melee hit after a dodge roll crits
		source.feint_t = 0.0
		if not fl.has("venom_pact"):
			crit = true
	var was_shocked: bool = target.has_status("shock")
	var was_marked: bool = target.has_status("marked")
	var rolled := {}
	var m := 1.0
	if crit:
		m *= float(p.get("crit_mult", 1.5))
	if p.get("faction") == "player":
		m *= _conditional(p, target, origin)
		m *= Dev.hit_mult()   # developer damage multiplier / one-hit kills (1.0 unless dev tools are on)
	for t in p["dmg"]:
		var r: Array = corruption_damage_range(p,target,t)
		rolled[t] = rng.randf_range(r[0], r[1]) * m
	var dealt: float = target.receive_hit(rolled, p, source, crit)
	if dealt > 0 and target.faction == "enemy":
		Sfx.play("crit" if crit else "hit")
		if p.get("faction") == "player" and p.get("kind") != "minion":
			_impact_freeze(target, dealt, crit)
	# The Unfinished (Endgame Phase 1D): a hit on a sketch deals no damage but still applies statuses (to paint it)
	var on_sketch: bool = dealt <= 0 and "sketch_hit" in target and target.sketch_hit
	if (dealt > 0 or on_sketch) and target.alive:
		for s in p.get("status", []):
			if rng.randf() * 100.0 < float(s.get("chance", 0)):
				apply_status(target, s, rolled, p)
	if dealt > 0 and p.get("faction") == "player" and not fl.is_empty():
		_was_shocked = was_shocked
		_on_hit_passives(p, fl, source, target, rolled, crit, was_marked, origin)
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

func corruption_increased(sb, stat: String) -> float:
	var total := 0.0
	for source in sb.source_breakdown(stat):
		if str(source).begins_with("Corruption: "):
			total += float(sb.source_breakdown(stat)[source].get("inc", 0))
	return total

func corruption_damage_range(p: Dictionary, target, damage_type: String) -> Array:
	var extra := float(p.get("corruption_elite_inc",0)) if target.is_elite or target.is_boss else 0.0
	if target.life < target.max_life * 0.35:
		extra += float(p.get("corruption_low_life_inc",0))
	if extra == 0 or not p.get("pre_increased",{}).has(damage_type):
		return p["dmg"][damage_type]
	var base: Array = p["pre_increased"][damage_type]
	var factor := maxf(0.0,1.0 + (float(p.get("increased_by_type",{}).get(damage_type,0)) + extra) / 100.0)
	return [base[0]*factor,base[1]*factor]

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
		elif d < 70:
			m *= 0.75   # Phase D2 (Dan): was 30% less within 100 units
	if fl.has("void_pact") and not target.statuses.is_empty():
		m *= 1.25
	if fl.has("clockwork_mind") and not p.get("kind", "") in ["turret", "trap", "minion"]:
		m *= 0.7
	if fl.has("glacial_heart"):   # Phase 3b keystone
		if target.has_status("freeze"):
			m *= 1.4
		elif not target.has_status("chill"):
			m *= 0.8
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
	var pfl: Dictionary = p.get("flags", {})
	if pfl.has("avatar_of_embers") and typ in ["chill", "freeze", "shock"]:
		if _sum(rolled) <= 0.0:
			return
		typ = "ignite"
	if pfl.has("prismatic_soul") and typ in ELEMENTAL_AILMENTS:
		return
	if pfl.has("festering_wounds") and typ in ["bleed", "ignite", "poison"] and (target.has_status("snare") or target.has_status("marked")):
		dur_mult *= 1.5
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
				_freeze(target, p, dur_mult, 1.25)
			else:
				target.add_status("chill", 2.0 * dur_mult, {})
		"freeze":
			_freeze(target, p, dur_mult, 1.1)
		"shock":
			var mag := 1.35 if p.get("flags", {}).has("overcharge") else 1.2
			target.add_status("shock", 3.0 * dur_mult, {"mag": mag})
			if pfl.has("conductive_web") and not s.get("spread", false) and target.level != null:   # Phase 3b
				var best = null
				var bd := 90.0
				for o in target.level.hostiles_in_radius(target.global_position, 90.0, "player"):
					if o != target and o.alive and not o.has_status("shock"):
						var dd: float = o.global_position.distance_to(target.global_position)
						if dd < bd:
							bd = dd
							best = o
				if best != null:
					best.add_status("shock", 3.0 * dur_mult, {"mag": mag})
					_tag_source(best, "shock", p)
		"poison":
			var stacks := 20 if pfl.has("venom_pact") else (3 if pfl.has("agonising_toxins") else 1)
			if pfl.has("noxious_payload") and target.has_status("snare"):   # Phase 3b
				stacks = maxi(stacks, 5)
			var pdur := 4.0 * dur_mult * (1.4 if pfl.has("venom_pact") else 1.0)
			var pdata := {"dps": _sum(rolled) * 0.3 * dot_mult, "dtype": "void"}
			if stacks > 1:
				pdata["max_stacks"] = stacks
			target.add_status("poison", pdur, pdata)
			if pfl.has("agonising_toxins") and target.poison_stacks() >= 3 and not target.has_status("agony"):
				apply_status(target, {"type": "agony", "duration": 4.0}, rolled, p)
			elif pfl.has("noxious_payload") and target.poison_stacks() >= 5 and not target.has_status("agony"):
				apply_status(target, {"type": "agony", "duration": 4.0}, rolled, p)
		"agony":
			target.add_status("agony", float(s.get("duration", 6.0)) * dur_mult, {"dps": maxf(float(s.get("dps", 0.0)), _sum(rolled) * 0.4) * dot_mult, "dtype": "void"})
		"frailty", "marked", "snare":
			target.add_status(typ, float(s.get("duration", 5.0)) * dur_mult, {})
		"stun":
			if pfl.has("tremor_lines") and target.has_status("snare"):   # Phase 3b
				dur_mult *= 1.5
			target.add_status("stun", (0.2 if target.is_boss else 0.6) * dur_mult, {})
		"intimidate":
			var d := float(s.get("duration", 4.0))
			target.add_status("intimidate", (d if d > 0 else 4.0) * dur_mult, {})
		_:
			target.add_status(typ, 2.0 * dur_mult, {})
	_tag_source(target, typ, p)

## Freeze (also Deep Freeze's chill-to-freeze). Phase 3b: Brittle lengthens it, Cold Snap chills nearby enemies.
func _freeze(target, p: Dictionary, dur_mult: float, mag: float) -> void:
	var pfl: Dictionary = p.get("flags", {})
	if pfl.has("brittle"):
		dur_mult *= 1.3
	target.add_status("freeze", (0.3 if target.is_boss else 1.0) * dur_mult, {"mag": mag})
	if pfl.has("cold_snap") and target.level != null:
		for o in target.level.hostiles_in_radius(target.global_position, 70.0, "player"):
			if o != target and o.alive and not o.has_status("freeze"):
				o.add_status("chill", 2.0 * float(p.get("status_dur", 1.0)), {})
				_tag_source(o, "chill", p)
		if target.level.has_method("add_fx"):
			target.level.add_fx(VFX.make("nova", target.global_position, TYPE_COLORS["cold"], 0.3, 70))

## Phase 2/3 on-hit notables (Opened Veins, Marked for Death, Hexblight; Phase 3 bridges and conversions).
func _on_hit_passives(p: Dictionary, fl: Dictionary, source, target, rolled: Dictionary, crit: bool, was_marked: bool, origin: Vector2 = Vector2.INF) -> void:
	var tags: Array = p.get("tags", [])
	if not is_instance_valid(target):
		return
	_on_hit_phase3(p, fl, source, target, rolled, crit, was_marked, origin, tags)
	if crit and fl.has("opened_veins") and tags.has("melee") and target.alive:
		apply_status(target, {"type": "bleed"}, rolled, p)
	if crit and fl.has("marked_for_death") and tags.has("projectile"):
		if was_marked and target.level != null:
			var o = target.level.nearest_hostile(target.global_position, "player", 110.0, {target.get_instance_id(): true})
			if o != null:
				var p2 := p.duplicate()
				var f2: Dictionary = fl.duplicate()
				f2.erase("marked_for_death")   # the extra hit does not chain again
				p2["flags"] = f2
				deal(p2, source, o, target.global_position)
		if target.alive:
			apply_status(target, {"type": "marked", "duration": 2.0}, rolled, p)
	if fl.has("hexblight") and target.alive and (target.has_status("frailty") or target.has_status("snare")) and rng.randf() < 0.25:
		apply_status(target, {"type": "agony", "duration": 6.0}, rolled, p)

func _on_hit_phase3(p: Dictionary, fl: Dictionary, source, target, rolled: Dictionary, crit: bool, was_marked: bool, origin: Vector2, tags: Array) -> void:
	var melee: bool = tags.has("melee")
	var proj: bool = tags.has("projectile")
	var src_ok: bool = source != null and is_instance_valid(source)
	var pre_shock := _was_shocked
	_on_hit_phase3b(p, fl, source, target, rolled, crit, origin, tags, src_ok, pre_shock)
	if crit and not target.alive and fl.has("deathblow") and src_ok and source.has_method("add_buff"):
		source.add_buff("deathblow", [{"stat": "crit_chance", "type": "inc", "value": 20}, {"stat": "attack_speed", "type": "inc", "value": 10},
				{"stat": "cast_speed", "type": "inc", "value": 10}], 3.0)
	if not target.alive:
		return
	if melee and fl.has("hunter_knight") and not target.has_status("marked") and rng.randf() < 0.2:
		apply_status(target, {"type": "marked", "duration": 2.0}, rolled, p)
	if proj and fl.has("pinning_shot") and was_marked:
		apply_status(target, {"type": "snare", "duration": 1.5}, rolled, p)
	if proj and fl.has("deadeye_mastery") and origin != Vector2.INF and origin.distance_to(target.global_position) > 160.0:
		apply_status(target, {"type": "snare", "duration": 1.5}, rolled, p)
	if target.has_status("chill") and ((crit and fl.has("killer_instinct")) or (melee and fl.has("rime_edge") and rng.randf() < 0.25)):
		apply_status(target, {"type": "freeze"}, rolled, p)
	if proj and fl.has("hexshot") and src_ok and "last_curse" in source and not source.last_curse.is_empty():
		var cast: int = int(p.get("cast", -1))
		if cast != source.hexshot_cast:
			source.hexshot_cast = cast
			for st in source.last_curse:
				apply_status(target, st, rolled, p)
	if melee and fl.has("spellblade") and src_ok and "spellblade_t" in source and source.spellblade_t <= 0.0 \
			and SPELLBLADE_STATUS.has(source.last_spell_type) and target.level != null:
		source.spellblade_t = 0.6
		var et: String = source.last_spell_type
		death_burst(source, target.level, target.global_position, 50.0, et, _sum(rolled) * 0.3, SPELLBLADE_STATUS[et], null, fl)

## Phase 3b archetype notables (Duelist, Trapper, Barrage, Tempest).
func _on_hit_phase3b(p: Dictionary, fl: Dictionary, source, target, rolled: Dictionary, crit: bool, origin: Vector2, tags: Array, src_ok: bool, pre_shock: bool) -> void:
	var melee: bool = tags.has("melee")
	if crit and melee and fl.has("blade_dance") and src_ok and source.has_method("blade_dance_stack"):
		source.blade_dance_stack()
	if tags.has("projectile") and p.get("is_attack", false) and fl.has("arrowstorm") and src_ok and "arrowstorm_n" in source and target.level != null:
		source.arrowstorm_n += 1
		if source.arrowstorm_n >= 10:
			source.arrowstorm_n = 0
			arrow_rain(source, target.level, target.global_position, rolled, fl)
	if pre_shock and fl.has("static_cascade") and float(rolled.get("lightning", 0.0)) > 0.0 and target.level != null:
		var o = target.level.nearest_hostile(target.global_position, "player", 100.0, {target.get_instance_id(): true})
		if o != null:
			var p2 := p.duplicate()
			var f2: Dictionary = fl.duplicate()
			f2.erase("static_cascade")   # the arc does not arc again
			p2["flags"] = f2
			var d2 := {}
			for t in p["dmg"]:
				d2[t] = [p["dmg"][t][0] * 0.5, p["dmg"][t][1] * 0.5]
			p2["dmg"] = d2
			if target.level.has_method("add_fx"):
				var v = VFX.make("bolt", Vector2.ZERO, TYPE_COLORS["lightning"], 0.2, 8)
				v.points = PackedVector2Array([target.global_position + Vector2(0, -6), o.global_position + Vector2(0, -6)])
				target.level.add_fx(v)
			deal(p2, source, o, target.global_position)
	if not is_instance_valid(target) or not target.alive:
		return
	if melee and fl.has("single_combat") and target.level != null and target.level.is_isolated(target, 110.0):
		apply_status(target, {"type": "marked", "duration": 3.0}, rolled, p)
	if p.get("kind", "") == "trap" and fl.has("noxious_payload") and target.has_status("snare"):
		apply_status(target, {"type": "poison"}, rolled, p)

## Arrowstorm: 3 delayed arrow volleys at a point, each 40% of the triggering hit (no on-hit flags).
func arrow_rain(source, level, at: Vector2, rolled: Dictionary, owner_flags: Dictionary) -> void:
	if level == null or not "floor_layer" in level:
		return
	var d := {}
	for t in rolled:
		d[t] = [rolled[t] * 0.4, rolled[t] * 0.4]
	var fl := {}
	for k in ["prismatic_soul", "avatar_of_embers"]:
		if owner_flags.has(k):
			fl[k] = true
	var pk := {"dmg": d, "crit_chance": 0.0, "crit_mult": 1.0, "faction": "player", "status": [], "tags": ["area"], "flags": fl, "kind": "burst"}
	for i in 3:
		var a = AoEScript.new()
		a.level = level
		a.source = source
		a.packet = pk
		a.faction = "player"
		a.radius = 40.0
		a.delay = 0.2 + 0.15 * i
		a.style = "rain"
		a.color = Color("#e0d8b0")
		a.origin = at
		a.position = at + (Vector2(rng.randf_range(-14, 14), rng.randf_range(-14, 14)) if i > 0 else Vector2.ZERO)
		level.floor_layer.add_child(a)

const SPELLBLADE_STATUS := {"fire": "ignite", "cold": "chill", "lightning": "shock"}

## Area hit around a point (Overload, Shatter, Pyroclasm, Spellblade). Flat damage of one type plus a
## guaranteed status. The packet carries no on-hit flags (no chains of bursts), only the ones that
## restrict statuses (Prismatic Soul, Avatar of Embers).
func death_burst(source, level, at: Vector2, radius: float, dtype: String, amount: float, status: String, exclude, owner_flags: Dictionary) -> int:
	if level == null or amount <= 0.0:
		return 0
	var fl := {}
	for k in ["prismatic_soul", "avatar_of_embers"]:
		if owner_flags.has(k):
			fl[k] = true
	var pk := {"dmg": {dtype: [amount * 0.9, amount * 1.1]}, "crit_chance": 0.0, "crit_mult": 1.0, "faction": "player",
			"status": [{"type": status, "chance": 100.0}] if status != "" else [], "tags": ["area"], "flags": fl, "kind": "burst"}
	var n := 0
	for o in level.hostiles_in_radius(at, radius, "player"):
		if o != exclude and is_instance_valid(o) and o.alive:
			deal(pk, source, o, at)
			n += 1
	if level.has_method("add_fx"):
		level.add_fx(VFX.make("nova", at, TYPE_COLORS.get(dtype, Color.WHITE), 0.3, radius))
	return n

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
