extends RefCounted
## Skill profiles for the smart bot. Profiles are defined ONLY by human-like
## behaviour parameters (reaction time, mistakes, awareness, ...). They are never
## tuned towards a target success rate. See README.md for the parameter table.
##
##   reaction_ms        delay between a telegraph appearing and the bot acting on it
##   mistake_rate       chance that a perceived telegraph is still not acted on
##   awareness          chance to notice a telegraph at all (rolled once, when it enters the screen)
##   avoid_threats      move out of / around telegraphs (false = never dodges)
##   use_roll           allowed to use the dodge roll (Space) to escape
##   safety_margin      extra pixels kept from telegraph edges when judging safety
##   positioning        0..1 quality of spacing (ranged keep-away distance, melee reach use)
##   target_quality     chance to pick the best-priority target instead of the nearest one
##   skill_quality      chance to use the best skill for the situation instead of a random usable one
##   potion_discipline  0..1; drink threshold = 0.30 + 0.20 * discipline of max life, cleanses DoTs if >= 0.9
##   decision_ms        how often targets / skills / movement goals are re-evaluated (APM)
##   lead_targets       aim projectiles ahead of moving targets

const BASE := {
	"reaction_ms": 350.0,
	"mistake_rate": 0.20,
	"awareness": 0.75,
	"avoid_threats": true,
	"use_roll": true,
	"safety_margin": 4.0,
	"positioning": 0.6,
	"target_quality": 0.7,
	"skill_quality": 0.75,
	"potion_discipline": 0.7,
	"decision_ms": 120.0,
	"lead_targets": false,
}

const PRESETS := {
	# competent player who simply never dodges (same values as Competent otherwise)
	"NoDodge": {"avoid_threats": false, "use_roll": false},
	"Competent": {},
	"Expert": {
		"reaction_ms": 180.0,
		"mistake_rate": 0.05,
		"awareness": 0.95,
		"safety_margin": 6.0,
		"positioning": 0.9,
		"target_quality": 0.95,
		"skill_quality": 0.95,
		"potion_discipline": 0.95,
		"decision_ms": 60.0,
		"lead_targets": true,
	},
}

static func names() -> Array:
	return ["NoDodge", "Competent", "Expert"]

static func get_profile(name: String, overrides: Dictionary = {}) -> Dictionary:
	var p: Dictionary = BASE.duplicate()
	var pre: Dictionary = PRESETS.get(name, {})
	for k in pre:
		p[k] = pre[k]
	for k in overrides:
		if p.has(k):
			p[k] = overrides[k]
	p["name"] = name
	return p
