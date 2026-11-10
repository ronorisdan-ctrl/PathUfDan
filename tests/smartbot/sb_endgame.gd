extends RefCounted
## Endgame Phase 2E: what the smart bot does with the Collector's Wager and Pentimento Vaults
## (docs/ENDGAME_PHASE2.md, stage 2E). The controller asks this module for a goal before it heads
## for the boss room, and asks it whether a flask / a skill / a loot detour would break the bet.
##
##   --wager=auto|<bet id>|none   walk to the Collector and take a bet (auto = the bot's own pick;
##                                a bet id is forced into the offer for win-rate measurements)
##   --stake=1|2|3                stake multiplier (default 1)
##   --vaults=0                   do not go out of the way for vaults (default: open them)
## A competent player obeys the bet he took: no flask under Abstinence, only the two kept skills
## under Economy of Means, more careful flasking under Iron Will, no loot detours against the clock.

const WV = preload("res://scripts/core/wager_vault_rules.gd")

## The bot's own pick (auto): estimated win chance per bet and class, from the 2E measurement runs
## (tests/smartbot/out/atlas_p2e_<bet>_*_c1/c2/c3_rot0.csv, final tuning). The bot takes the offered bet with the best expected
## return  p x (1 + odds) - 1.
const EST_WIN := {
	"unscathed": {"warrior": 0.4, "ranger": 0.67, "mage": 0.7},
	"boss_rush": {"warrior": 0.7, "ranger": 0.9, "mage": 0.4},
	"few_skills": {"warrior": 1.0, "ranger": 1.0, "mage": 0.8},
	"frenzy": {"warrior": 0.8, "ranger": 0.6, "mage": 0.3},
	"abstinence": {"warrior": 1.0, "ranger": 0.9, "mage": 0.7},
	"iron_will": {"warrior": 0.4, "ranger": 0.9, "mage": 0.5},
	"flaking": {"warrior": 0.6, "ranger": 0.6, "mage": 1.0},
	"colourist": {"warrior": 0.7, "ranger": 0.7, "mage": 0.7},
	"archaeology": {"warrior": 0.6, "ranger": 0.57, "mage": 0.67},
}

var c = null          # sb_controller
var plan := ""        # "" = ignore the Collector, "auto", or a bet id
var mult := 1
var seek_vaults := true
var keep := {}        # Economy of Means: the skill ids the bot keeps to
var log := {}

func setup(ctrl, wager_arg: String, stake: int, vaults_arg: String) -> void:
	c = ctrl
	plan = "" if wager_arg in ["", "none", "0"] else wager_arg
	mult = clampi(stake, 1, 3)
	seek_vaults = not (vaults_arg in ["0", "false", "no"])

func begin() -> void:
	keep = {}
	log = {"bet": "", "mult": 0, "stake": 0, "accept_t": -1.0, "end_t": -1.0, "offers": [], "vault_t": 0.0, "vault_seen": 0,
		"sigil_hits": 0, "trap_alive_at_death": 0}

func _has(name: String) -> bool:
	return c.lv != null and name in c.lv

func wager_state() -> String:
	return str(c.lv.wager.get("state", "")) if _has("wager") else ""

## The bet now running ("" if none).
func bet() -> String:
	return str(c.lv.wager.get("bet", "")) if wager_state() == "active" else ""

# ------------------------------------------------------------------ the bet's rules
func flask_ok() -> bool:
	return bet() != "abstinence"

func flask_threshold(base: float) -> float:
	return maxf(base, 0.68) if bet() == "iron_will" else base

func loot_ok() -> bool:
	return bet() != "boss_rush"

func skill_ok(id: String) -> bool:
	if bet() != "few_skills":
		return true
	return keep.has(id)

func tick(dt: float) -> void:
	if wager_state() == "active" and c.p != null:
		log["minlife"] = minf(float(log.get("minlife", 1.0)), c.p.life / maxf(1.0, c.p.max_life))
	if c.goal_kind.begins_with("vault") or (_valid_wall_target()):
		log["vault_t"] = float(log["vault_t"]) + dt
	if log["end_t"] < 0.0 and log["accept_t"] >= 0.0 and wager_state() in ["won", "lost"]:
		log["end_t"] = c.t

func _valid_wall_target() -> bool:
	return c._valid(c.target) and c.target.def.get("object", false)

# ------------------------------------------------------------------ choosing and taking the bet
func choose(offers: Array) -> String:
	if offers.is_empty():
		return ""
	offers = offers.filter(func(o): return c.lv.wager_refusal(o) == "")
	if plan != "auto":
		return plan if offers.has(plan) else ""
	var cls: String = c.ch.class_id
	var best := ""
	var bv := -INF
	for id in offers:
		var pw: float = float(EST_WIN.get(id, {}).get(cls, 0.5))
		var odds := float(WV.bet_info(id).get("odds", 1.0))
		var ev := pw * (1.0 + odds) - 1.0
		if ev > bv:
			bv = ev
			best = id
	return best

## Economy of Means: keep the main attack (slot 0) and, if the bet allows 2, the most used other skill so far.
func _pick_keep() -> void:
	keep = {}
	var s0: Dictionary = c.p.skill_in_slot(0)
	if not s0.is_empty():
		keep[s0["id"]] = true
	var allow := int(c.lv.wager.get("lim", {}).get("few_skills", {}).get("skills", 2))
	if keep.size() >= allow:
		return
	var su: Dictionary = c.st["skill_uses"]
	var best := ""
	var bn := -1
	for id in su:
		if not keep.has(id) and int(su[id]) > bn:
			bn = int(su[id])
			best = id
	if best == "":
		for i in range(1, c.ch.HOTBAR_SIZE):
			var sk: Dictionary = c.p.skill_in_slot(i)
			if not sk.is_empty():
				best = sk["id"]
				break
	if best != "":
		keep[best] = true

func _take_bet() -> void:
	var offers: Array = c.lv.wager.get("offers", [])
	log["offers"] = offers.duplicate()
	var id := choose(offers)
	if id == "":
		c.lv.wager["state"] = "declined"   # the bot walks on; the line says nothing to the game
		c.bot.trace("WAGER declined %s" % str(offers))
		return
	var why: String = c.lv.accept_wager(id, mult)
	if why != "":
		c.bot.trace("WAGER refused %s x%d: %s" % [id, mult, why])
		c.lv.wager["state"] = "declined"
		return
	log["bet"] = id
	log["mult"] = mult
	log["stake"] = int(c.lv.wager.get("stake", 0))
	log["accept_t"] = c.t
	if id == "few_skills":
		_pick_keep()
	c.bot.trace("WAGER took %s x%d (%s) offers=%s keep=%s" % [id, mult, c.lv.wager_text(id), str(offers), str(keep.keys())])

# ------------------------------------------------------------------ goals
## A goal before the boss room: the Collector, an unopened vault, the open vault's work. null = none.
func goal():
	if c.lv.boss_dead:
		return null
	var pp: Vector2 = c.p.global_position
	if plan != "" and wager_state() == "offer" and _has("collector_pos"):
		var cp: Vector2 = c.lv.collector_pos
		c.goal_kind = "collector"
		if pp.distance_to(cp) < 24.0:
			_take_bet()
			return null
		return cp
	var b := bet()
	if b in ["frenzy", "unscathed", "flaking", "colourist"]:
		# the bet's prey instead of walking on to the boss: Frenzy any pack, Unscathed an elite,
		# Flaking a glazed elite with layers left, Colourist a sketch
		var fe = null
		var fd := 700.0 if b == "frenzy" else 1100.0
		for e in c.lv.enemies:
			if not c._valid(e) or e.is_boss or e.def.get("object", false):
				continue
			var prey: bool = b == "frenzy" or (b == "unscathed" and e.is_elite) or (b == "flaking" and int(e.glaze_layers) > 0) or (b == "colourist" and e.sketched)
			if prey:
				var d0: float = pp.distance_to(e.global_position)
				if d0 < fd:
					fd = d0
					fe = e
		if fe != null:
			c.goal_kind = "hunt:" + b
			return fe.global_position
	if not _has("vaults") or c.lv.vaults.is_empty():
		return null
	# open vaults first: riddle sigils, trap monsters
	for vi in c.lv.vaults.size():
		var v: Dictionary = c.lv.vaults[vi]
		if not v["open"] or v["done"]:
			continue
		if v["type"] == "riddle":
			var key := "vault_sigil_%d_%d" % [vi, int(v["order"][int(v["next"])])]
			for it in c.lv.interactables:
				if it["kind"] == key:
					c.goal_kind = "vault:sigil"
					if pp.distance_to(it["pos"]) < 24.0:
						c.lv.on_interact(it)
						log["sigil_hits"] = int(log["sigil_hits"]) + 1
						c.bot.trace("VAULT sigil %s" % key)
					return it["pos"]
		elif v["type"] == "trap":
			for e in v["trap"]:
				if c._valid(e):
					c.goal_kind = "vault:trap"
					return e.global_position
	if (not seek_vaults and b != "archaeology") or b == "boss_rush":
		return null
	# the nearest sealed vault (a player sees the shimmer on the map once the chamber is revealed)
	var best = null
	var bd := INF
	for v in c.lv.vaults:
		if v["open"] or v["wall"] == null or not is_instance_valid(v["wall"]) or not v["wall"].alive:
			continue
		var wp: Vector2 = v["wall"].global_position
		if not _revealed(wp) and b != "archaeology":
			continue
		var d: float = pp.distance_to(wp)
		if d < bd:
			bd = d
			best = v["wall"]
	if best == null:
		return null
	c.goal_kind = "vault:wall"
	if bd < 300.0 and c.lv.has_los(pp, best.global_position):
		c.target = best
		c.target_pick_t = c.t + 0.5
	return best.global_position

func _revealed(pos: Vector2) -> bool:
	if not _has("reveal"):
		return true
	var cc: Vector2i = c.lv.to_cell(pos)
	var i: int = cc.y * c.lv.gw + cc.x
	return i >= 0 and i < c.lv.reveal.size() and c.lv.reveal[i] != 0

## Notes for the run row.
func notes(outcome: String) -> Array:
	var out := []
	if _has("wager") and not c.lv.wager.is_empty():
		var w: Dictionary = c.lv.wager
		var s := wager_state()
		var gold := 0
		if log["bet"] != "":
			if s == "won":
				gold = int(WV.payout(str(log["bet"]), int(c.lv.monster_level), int(log["mult"]), int(c.lv.rot) if "rot" in c.lv else 0)["gold"]) - int(log["stake"])
			else:
				gold = -int(log["stake"])
		out.append("wager:%s|x%d|%s|why=%s|offers=%s|t=%.0f|gold=%d|hits=%d|kills=%d|limt=%.0f|minlife=%d|peels=%d|painted=%d" % [str(log["bet"]) if log["bet"] != "" else "-", int(log["mult"]), s,
			str(w.get("why", "")).replace(",", ";").replace("|", "/"), "+".join(log["offers"]) if not log["offers"].is_empty() else "+".join(w.get("offers", [])),
			(float(log["end_t"]) if log["end_t"] >= 0.0 else c.t) - float(log["accept_t"]) if log["accept_t"] >= 0.0 else 0.0, gold, int(w.get("hits", 0)), int(w.get("kills", 0)), float(w.get("lim", {}).get(str(log["bet"]), {}).get("time", 0.0)), int(round(100.0 * float(log.get("minlife", 1.0)))),
			int(c.lv.mech_stats.get("peels", 0)) - int(w.get("peels0", 0)), int(c.lv.mech_stats.get("painted", 0)) + int(c.lv.mech_stats.get("filled", 0)) - int(w.get("painted0", 0))])
	if _has("vaults") and not c.lv.vaults.is_empty():
		var parts := []
		var trap_alive := 0
		for v in c.lv.vaults:
			parts.append("%s:%s" % [str(v["type"]), "done" if v["done"] else ("open" if v["open"] else "sealed")])
			if v["type"] == "trap" and v["open"] and not v["done"]:
				for e in v["trap"]:
					if is_instance_valid(e) and e.alive:
						trap_alive += 1
		out.append("vaults:%s|t=%.0f|sigils=%d|shards=%d%s" % ["+".join(parts), float(log["vault_t"]), int(log["sigil_hits"]),
			int(c.lv.wv_stats.get("vault_shards", 0)), ("|trap_alive=%d" % trap_alive) if outcome == "died" and trap_alive > 0 else ""])
	return out
