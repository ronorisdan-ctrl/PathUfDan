extends RefCounted
## Typed exceptional effects, kept separate from ordinary stat names.
## The registry controls which item/side/level can provide an operation.
const OPS := ["tagged_skill_level:melee", "tagged_skill_level:spell", "skill_level:active",
	"tagged_projectile_count:weapon_attack", "tagged_projectile_count:bow_attack",
	"tagged_pierce:projectile_attack", "chain", "maximum_elemental_resistance",
	"damage_reduction_vs_hit", "trap_limit", "conditional_inc_damage:target_below_35pct_life",
	"conditional_minion_damage:player_below_35pct_life", "on_elite_kill_mana_pct", "on_dodge_mana_pct_icd8s"]

static func supports(op: String) -> bool:
	return op in OPS

static func total(sb, op: String) -> float:
	var amount := 0.0
	for effect in sb.operations:
		if effect.get("op") == op:
			amount += float(effect.get("value", 0))
	return amount

static func skill_levels(sb, skill: Dictionary) -> int:
	var bonus := total(sb,"skill_level:active")
	if skill.get("tags", []).has("melee"):
		bonus += total(sb,"tagged_skill_level:melee")
	if skill.get("tags", []).has("spell"):
		bonus += total(sb,"tagged_skill_level:spell")
	return int(bonus)

static func offensive_projectile(skill: Dictionary) -> bool:
	return skill.get("behavior") == "projectile" and skill.get("tags", []).has("projectile") and skill.get("kind") in ["attack", "spell"]

static func projectile_total(sb) -> int:
	return int(total(sb,"tagged_projectile_count:weapon_attack") + total(sb,"tagged_projectile_count:bow_attack"))

static func projectiles(ch, skill: Dictionary) -> int:
	if not offensive_projectile(skill) or skill.get("kind") != "attack":
		return 0
	var groups: Array = ch.weapon_groups()
	if not ("bow" in groups or "firearm" in groups):
		return 0
	var amount := int(total(ch.stats,"tagged_projectile_count:weapon_attack"))
	if "bow" in groups:
		amount += int(total(ch.stats,"tagged_projectile_count:bow_attack"))
	return mini(int(Data.corruption_cfg.get("corrupted_projectile_bonus_character_cap", 2)), amount)

static func pierce(ch, skill: Dictionary) -> int:
	return int(total(ch.stats,"tagged_pierce:projectile_attack")) if offensive_projectile(skill) and skill.get("kind") == "attack" else 0

static func chains(sb, skill: Dictionary) -> int:
	return int(total(sb,"chain")) if offensive_projectile(skill) or (skill.get("behavior") == "chain" and skill.get("kind") == "spell") else 0

static func describe(effect: Dictionary) -> String:
	var text: String = Data.corruption_cfg.get("effect_text", {}).get(effect.get("op", ""), "Unsupported corruption effect")
	return text.replace("{v}", str(int(effect.get("value", 0))))

static func projectile_summary(sb) -> String:
	var amount := projectile_total(sb)
	var cap := int(Data.corruption_cfg.get("corrupted_projectile_bonus_character_cap", 2))
	return "Corruption projectiles: equipped +%d / limit +%d; %d suppressed. Applies to matching offensive weapon skills only." % [amount,cap,maxi(0,amount-cap)]
