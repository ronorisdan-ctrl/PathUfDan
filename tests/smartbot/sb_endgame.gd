extends RefCounted
## Endgame Phase 2E: what the smart bot does with the Collector's Wager and Pentimento Vaults
## (docs/ENDGAME_PHASE2.md, stage 2E). The controller asks this module for a goal before it heads
## for the boss room, and asks it whether a flask / a skill / a loot detour would break the bet.
##
##   --wager=auto|<bet id>|none   walk to the Collector and take a bet (auto = the bot's own pick;
##                                a bet id is forced into the offer for win-rate measurements)
##   --stake=1|2|3                stake multiplier (default 1)
##   --vaults=0                   do not go out of the way for vaults (default: open them)
## Endgame 3C: the Burning Canvas and the Pigment Wells.
##   --fire_flee=N        cells between the bot and the fire front at which it stops for loot / packs
##                        behind it and heads for the arena (default 8)
##   --fire_cistern=N     the front this close (cells) and a cistern within cistern_reach px: douse it (default 14)
##   --wells_linger=S     seconds the bot stands by each well it passes to fight there (default 12)
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
var fire_flee := 8.0
var fire_cistern := 14.0
var cistern_reach := 320.0
var wells_linger := 12.0

func setup(ctrl, wager_arg: String, stake: int, vaults_arg: String) -> void:
	c = ctrl
	plan = "" if wager_arg in ["", "none", "0"] else wager_arg
	mult = clampi(stake, 1, 3)
	seek_vaults = not (vaults_arg in ["0", "false", "no"])
	fire_flee = float(ctrl.bot.A.get("fire_flee", "8"))
	fire_cistern = float(ctrl.bot.A.get("fire_cistern", "14"))
	wells_linger = float(ctrl.bot.A.get("wells_linger", "12"))

func begin() -> void:
	keep = {}
	log = {"bet": "", "mult": 0, "stake": 0, "accept_t": -1.0, "end_t": -1.0, "offers": [], "vault_t": 0.0, "vault_seen": 0,
		"sigil_hits": 0, "trap_alive_at_death": 0, "flee_t": 0.0, "well_t": {}, "cistern_tries": 0, "min_gap": INF}

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
	return bet() != "boss_rush" and not fleeing()

# ------------------------------------------------------------------ Endgame 3C: the Burning Canvas
func _burn():
	return c.lv.burn if _has("burn") and c.lv.burn != null and c.lv.burn.active() else null

## Cells between the bot and the front (INF without a burning front).
func fire_gap() -> float:
	var b = _burn()
	return b.gap(c.p.global_position) if b != null else INF

## The front is close: no detours, packs behind are left to the fire.
func fleeing() -> bool:
	return fire_gap() < fire_flee and not c.lv.boss_dead

## Leave an enemy alone while fleeing when it is behind us (nearer the entrance) and not on top of us.
func skip_enemy(e) -> bool:
	if not fleeing() or e.is_boss:
		return false
	var b = _burn()
	var de: int = b.dist_at(e.global_position)
	var dp: int = b.dist_at(c.p.global_position)
	return de >= 0 and de <= dp and e.global_position.distance_to(c.p.global_position) > 40.0

## While channelling a cistern the bot stands still at it (it still fights from there).
func hold_goal():
	var b = _burn()
	if b != null and b.channeling():
		return b.cisterns[int(b.channel["i"])]["pos"]
	return null

func _cistern_goal():
	var b = _burn()
	if b == null or fire_gap() >= fire_cistern:
		return null
	var pp: Vector2 = c.p.global_position
	var best := -1
	var bd := cistern_reach
	for i in b.cisterns.size():
		var cs: Dictionary = b.cisterns[i]
		if cs["used"]:
			continue
		var d: float = pp.distance_to(cs["pos"])
		if d < bd and b.dist_at(cs["pos"]) > b.front + 2.0:
			bd = d
			best = i
	if best < 0:
		return null
	var cp: Vector2 = b.cisterns[best]["pos"]
	c.goal_kind = "fire:cistern"
	if bd < 24.0:
		for it in c.lv.interactables:
			if it["kind"] == b.cisterns[best]["key"]:
				c.lv.on_interact(it)
				log["cistern_tries"] = int(log["cistern_tries"]) + 1
				c.bot.trace("FIRE cistern %d (gap %.1f)" % [best, fire_gap()])
				break
	return cp

# ------------------------------------------------------------------ Endgame 3C: the Pigment Wells
func _wells():
	return c.lv.wells if _has("wells") and c.lv.wells != null else null

func _well_goal():
	var ws = _wells()
	if ws == null or ws.done or fleeing():
		return null
	var pp: Vector2 = c.p.global_position
	for w in ws.wells:
		if float(w["fill"]) >= 1.0:
			continue
		var key := str(w["id"])
		var spent: float = float(log["well_t"].get(key, 0.0))
		if spent >= wells_linger:
			continue
		var d: float = pp.distance_to(w["pos"])
		if d > 300.0 or not _revealed(w["pos"]):
			continue
		c.goal_kind = "well:" + key
		return w["pos"]
	return null

## After the boss: walk to the easel and mix (before looting).
func post_goal():
	var ws = _wells()
	if ws == null or not ws.pending():
		return null
	var pp: Vector2 = c.p.global_position
	c.goal_kind = "well:easel"
	if pp.distance_to(ws.easel_pos) < 24.0:
		for it in c.lv.interactables:
			if it["kind"] == "wells_easel":
				c.lv.on_interact(it)
				c.bot.trace("WELLS mixed: %s" % str(ws.result.get("kind", "")))
				break
		return null
	return ws.easel_pos

func post_pending() -> bool:
	var ws = _wells()
	return ws != null and ws.pending()

func skill_ok(id: String) -> bool:
	if bet() != "few_skills":
		return true
	return keep.has(id)

func tick(dt: float) -> void:
	if _burn() != null and c.p != null:
		var gp := fire_gap()
		log["min_gap"] = minf(float(log["min_gap"]), gp)
		if gp < fire_flee:
			log["flee_t"] = float(log["flee_t"]) + dt
	var ws = _wells()
	if ws != null and not ws.done and c.p != null:   # time spent by each well (bounds the linger)
		var near: float = float(ws.t.get("near_cells", 4)) * float(c.lv.T) + 8.0
		for w in ws.wells:
			if c.p.global_position.distance_to(w["pos"]) < near:
				log["well_t"][str(w["id"])] = float(log["well_t"].get(str(w["id"]), 0.0)) + dt
	if wager_state() == "active" and c.p != null:
		log["minlife"] = minf(float(log.get("minlife", 1.0)), c.p.life / maxf(1.0, c.p.max_life))
	if c.goal_kind.begins_with("vault") or (_valid_wall_target()):
		log["vault_t"] = float(log["vault_t"]) + dt
	if log["end_t"] < 0.0 and log["accept_t"] >= 0.0 and wager_state() in ["won", "lost"]:
		log["end_t"] = c.t

## Phase D2: with an Archaeology plan the bot leaves sealed vault walls alone until it has
## taken the bet (in D1 14/30 runs opened the vault on the way and the bet was refused).
func hold_wall(e) -> bool:
	return plan == "archaeology" and wager_state() in ["", "offer"] and e.def.get("object", false)

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
	var cg = _cistern_goal()   # Endgame 3C: the fire is close and a cistern is near
	if cg != null:
		return cg
	if fleeing():
		return null            # straight on to the arena
	var wg = _well_goal()
	if wg != null:
		return wg
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
	if _has("burn") and c.lv.burn != null:
		var b = c.lv.burn
		var s: Dictionary = b.stats
		out.append("burn:ash=%d|ahead_ash=%d|cist=%d/%d|tries=%d|fire_t=%.0f|burn_t=%.1f|ahead_pct=%d|caught=%d|burnt_items=%d|burnt_gold=%d|dmg=%d|arena_d=%d|reach_arena=%.0f|front_end=%.0f|kills=%d|flee_t=%.0f|min_gap=%.0f|speed=%.3f" % [
			int(s["ash"]), int(s["ash_ahead"]), int(s["cisterns"]), b.cisterns.size(), int(log["cistern_tries"]), float(s["fire_t"]), float(s["burn_t"]),
			int(round(100.0 * float(s["ahead_t"]) / maxf(0.01, float(s["fire_t"])))), int(s["caught"]), int(s["burnt_items"]), int(s["burnt_gold"]), int(s["burn_dmg"]),
			int(b.arena_d), float(s["reach_arena_t"]), float(s["front_end"]) if float(s["front_end"]) >= 0.0 else b.front, int(b.kills), float(log["flee_t"]), minf(999.0, float(log["min_gap"])), b.speed])
	if _has("wells") and c.lv.wells != null:
		var ws = c.lv.wells
		var parts := []
		for w in ws.wells:
			parts.append("%s=%.2f" % [str(w["id"]), float(w["fill"])])
		var r: Dictionary = ws.result
		out.append("wells:%s|full=%d|kind=%s|dom=%s|draws=%d|drops=%d|value=%d|leg=%d|uniq=%d|kill_fill=%.2f|time_fill=%.2f|near_t=%.0f" % ["+".join(parts), int(ws.stats["full"]),
			str(r.get("kind", "unmixed" if ws.easel else "none")), str(r.get("dominant", "-")), r.get("draws", []).size(), int(r.get("drops", 0)), int(r.get("value", 0)),
			1 if r.get("got_legendary", false) else 0, 1 if r.get("got_unique", false) else 0, float(ws.stats["kill_fill"]), float(ws.stats["time_fill"]), float(ws.stats["near_t"])])
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
