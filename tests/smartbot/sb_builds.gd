extends RefCounted
## Phase B keystone build library (docs/BOT_GEAR_PROFILES.md section 4).
## Each build is what a player commits to: one keystone, the masteries and tree gem
## socket on the way, a specialisation, preferred skill tags and (optionally) hotbar roles.
## The bot follows a build with --plan=<id>; --plan=auto takes the analyser's pick for the
## class and stage from build_picks.json (tests/smartbot/build_analyser.py writes it).
##
## Fields
##   keystone  node id;  ks_at: level from which points walk towards it
##   masteries [node, ...] (option chosen by the power score when allocated)
##   sockets   [node, ...] tree gem sockets (best pouch gem by score)
##   spec      specialisation id, "" = element of the main skill (re-picked when it changes)
##   tags      skill tags / damage types the hotbar prefers (score x PREFER)
##   roles     hotbar role order override (sb_hub ROLE_ORDER format), [] = class default
##   prefer    optional multiplier for tagged skills (default PREFER); Glacial Heart uses a
##             stronger one because its keystone punishes hits on enemies that are not chilled
##   standoff  optional [lo, hi] range band for ranged kiting (Phase C, Perfect Aim)
##   buff_roll optional buff id: roll in combat whenever it is down (Phase C, Wind Dancer)

const PREFER := 1.6

const BUILDS := {
	# ------------------------------------------------------------------ warrior
	"w_earthbreaker": {"class": "warrior", "name": "Earthbreaker slams", "keystone": "p3b_eb_cap", "ks_at": 16,
		"masteries": ["p4_m_melee"], "sockets": ["p4_s_w_in"], "spec": "earthbreaker", "tags": ["slam"], "roles": []},
	"w_momentum": {"class": "warrior", "name": "Overwhelming Momentum", "keystone": "ks_momentum", "ks_at": 8,
		"masteries": ["p4_m_melee", "p4_m_bulwark"], "sockets": ["p4_s_w_in"], "spec": "weapon_master", "tags": ["melee"], "roles": []},
	"w_riposte": {"class": "warrior", "name": "Iron Riposte (block)", "keystone": "p2_ks_riposte", "ks_at": 8,
		"masteries": ["p4_m_bulwark", "p4_m_melee"], "sockets": ["p4_s_w_in"], "spec": "juggernaut", "tags": ["melee"], "roles": []},
	"w_executioner": {"class": "warrior", "name": "Executioner's Creed", "keystone": "xe_ks", "ks_at": 14,
		"masteries": ["p4_m_melee"], "sockets": ["p4_s_w_in"], "spec": "berserker", "tags": ["melee"], "roles": []},
	# ------------------------------------------------------------------ ranger
	"r_perfect_aim": {"class": "ranger", "name": "Perfect Aim", "keystone": "ks_perfect_aim", "ks_at": 8,
		"masteries": ["p4_m_proj_r"], "sockets": ["p4_s_r_in"], "spec": "deadeye", "tags": ["projectile"], "roles": []},
	"r_machinist": {"class": "ranger", "name": "Automaton turrets", "keystone": "ks_automaton", "ks_at": 8,
		"masteries": ["p4_m_deploy"], "sockets": ["p4_s_r_in"], "spec": "machinist", "tags": ["turret"],
		"roles": ["st", "turret", "turret", "aoe", "buff_off", "buff_def", "trap", "damage"]},
	"r_trapper": {"class": "ranger", "name": "Master Trapper", "keystone": "p3b_tr_cap", "ks_at": 16,
		"masteries": ["p4_m_deploy"], "sockets": ["p4_s_r_in"], "spec": "trapper", "tags": ["trap"],
		"roles": ["st", "trap", "trap", "aoe", "buff_off", "buff_def", "curse", "damage"]},
	"r_wind": {"class": "ranger", "name": "Wind Dancer", "keystone": "xw_ks", "ks_at": 12,
		"masteries": ["p4_m_proj_r"], "sockets": ["p4_s_r_in"], "spec": "wraith_hunter", "tags": ["projectile"], "roles": []},
	# Phase C reworks: play the keystone the way a player would (range band, rolls), and a
	# cheap unconditional keystone (Glass Cannon, 6 points from the ranger start)
	"r_far_aim": {"class": "ranger", "name": "Perfect Aim at range", "keystone": "ks_perfect_aim", "ks_at": 8,
		"masteries": ["p4_m_proj_r"], "sockets": ["p4_s_r_in"], "spec": "deadeye", "tags": ["projectile"], "roles": [],
		"standoff": [190.0, 290.0]},
	"r_wind_roll": {"class": "ranger", "name": "Wind Dancer, rolling", "keystone": "xw_ks", "ks_at": 16,
		"masteries": ["p4_m_proj_r"], "sockets": ["p4_s_r_in"], "spec": "wraith_hunter", "tags": ["projectile"], "roles": [],
		"buff_roll": "wind_dance"},
	"r_glass": {"class": "ranger", "name": "Glass Cannon", "keystone": "ks_glass", "ks_at": 12,
		"masteries": ["p4_m_proj_r"], "sockets": ["p4_s_r_in"], "spec": "deadeye", "tags": ["projectile"], "roles": []},
	# ------------------------------------------------------------------ mage
	"m_glacial": {"class": "mage", "name": "Glacial Heart (cold)", "keystone": "p3b_fw_cap", "ks_at": 16,
		"masteries": ["p4_m_elem_m"], "sockets": ["p4_s_m_in"], "spec": "cryomancer", "tags": ["cold"], "prefer": 3.0, "roles": []},
	"m_embers": {"class": "mage", "name": "Avatar of Embers (fire)", "keystone": "p2_ks_embers", "ks_at": 8,
		"masteries": ["p4_m_elem_m"], "sockets": ["p4_s_m_in"], "spec": "pyromancer", "tags": ["fire"], "roles": []},
	"m_convergence": {"class": "mage", "name": "Elemental Convergence", "keystone": "ks_convergence", "ks_at": 8,
		"masteries": ["p4_m_elem_m"], "sockets": ["p4_s_m_in"], "spec": "", "tags": [], "roles": []},
	"m_legion": {"class": "mage", "name": "Legion of Bone (minions)", "keystone": "p2_ks_legion", "ks_at": 8,
		"masteries": ["p4_m_minion"], "sockets": ["p4_s_m_in"], "spec": "summoner", "tags": ["minion"],
		"roles": ["st", "summon", "summon", "summon", "aoe", "buff_off", "mobility", "damage"]},
}

static func ids_for(cls: String) -> Array:
	var out := []
	for id in BUILDS:
		if BUILDS[id]["class"] == cls:
			out.append(id)
	return out

static func get_build(id: String) -> Dictionary:
	return BUILDS.get(id, {})

## Stage key used by build_picks.json: "T3", "T6", "R1"... from the kit tier / Atlas ring.
static func stage_key(tier: int, ring: int) -> String:
	return ("R%d" % ring) if ring > 0 else ("T%d" % tier)

## The analyser's pick for a class and stage ("" when none). Stages the analyser did not
## play use the class pick, then the nearest earlier stage of the same class.
static func pick(cls: String, tier: int, ring: int) -> String:
	var path := "res://tests/smartbot/build_picks.json"
	if not FileAccess.file_exists(path):
		return ""
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(d) != TYPE_DICTIONARY:
		return ""
	var c: Dictionary = d.get("picks", {}).get(cls, {})
	var key := stage_key(tier, ring)
	if c.has(key):
		return str(c[key])
	var cp = d.get("class_pick", {}).get(cls, {})
	if typeof(cp) == TYPE_DICTIONARY and cp.has("build"):
		return str(cp["build"])
	var order := ["T2", "T3", "T4", "T5", "T6", "R1", "R2", "R3"]
	var i := order.find(key)
	while i > 0:
		i -= 1
		if c.has(order[i]):
			return str(c[order[i]])
	return ""
