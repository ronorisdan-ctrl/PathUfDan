extends RefCounted
## Passive tree build planner. Each build variant is a list of keystone targets
## (with the level from which the player starts walking towards them). Points go,
## one at a time, to the next node of the game's own shortest route
## (CharacterData.path_to, the same logic the tree UI uses for click-to-route).
## Between targets, points go to the frontier node with the best gain per point,
## measured with the hub power score (class stats + gear + current skills),
## with a one-node look-ahead so cheap travel nodes towards strong clusters are taken.

var hub = null

const TARGETS := {
	"warrior": {
		"balanced": [],
		"glass": [{"node": "ks_momentum", "at": 8}, {"node": "ks_glass", "at": 16}],
		"defensive": [{"node": "ks_fortress", "at": 8}, {"node": "xp_ks", "at": 24}],
	},
	"ranger": {
		"balanced": [],
		"glass": [{"node": "ks_perfect_aim", "at": 8}, {"node": "ks_glass", "at": 16}],
		"defensive": [{"node": "xp_ks", "at": 12}, {"node": "xa_ks", "at": 26}],
	},
	"mage": {
		"balanced": [],
		"glass": [{"node": "ks_convergence", "at": 8}, {"node": "ks_glass", "at": 16}],
		"defensive": [{"node": "xa_ks", "at": 10}, {"node": "xp_ks", "at": 20}],
	},
}

static func builds() -> Array:
	return ["balanced", "glass", "defensive"]

func targets_for(cls: String, build: String) -> Array:
	## Phase B: a keystone build plan (sb_builds.gd) replaces the build's targets:
	## tree gem socket and first mastery early, the keystone from ks_at, other masteries after.
	if hub != null and not hub.plan.is_empty():
		var pl: Dictionary = hub.plan
		var out := []
		for s in pl.get("sockets", []):
			out.append({"node": s, "at": 1})
		var ms: Array = pl.get("masteries", [])
		if ms.size() > 0:
			out.append({"node": ms[0], "at": 1})
		out.append({"node": pl["keystone"], "at": int(pl.get("ks_at", 8))})
		for i in range(1, ms.size()):
			out.append({"node": ms[i], "at": int(pl.get("ks_at", 8))})
		return out
	return TARGETS.get(cls, {}).get(build, [])

## Best effect for a mastery node by the power score (Phase B plans).
func best_mastery_option(ch, id: String) -> String:
	var best := ""
	var bv := -INF
	var al: Array = ch.allocated.duplicate()
	al.append(id)
	for o in ch.mastery_options(id):
		if ch.can_choose_mastery(id, o["id"]) != "":
			continue
		var choices: Dictionary = ch.mastery_choices.duplicate()
		choices[id] = o["id"]
		var keep: Dictionary = ch.mastery_choices
		ch.mastery_choices = choices
		var v: float = hub.score(ch, null, al)
		ch.mastery_choices = keep
		if v > bv:
			bv = v
			best = o["id"]
	return best

func _cost(id: String) -> int:
	return int(Data.passives.get(id, {}).get("cost", 1))

func _frontier(ch) -> Array:
	var out := []
	for n in Data.passive_list:
		var id: String = n["id"]
		if n.get("type") in ["start", "keystone", "mastery", "socket"]:
			continue
		if ch.can_allocate(id) == "":
			out.append(id)
	return out

func _flag_bonus(id: String) -> float:
	var n: Dictionary = Data.passives.get(id, {})
	var b := 0.0
	for f in n.get("flags", []):
		b += 0.01
	return b

## Spend all available points. Returns log lines.
func spend(ch, build: String) -> Array:
	var lines := []
	var guard := 0
	while ch.available_passive_points() > 0 and guard < 200:
		guard += 1
		var acted := false
		var waiting := false
		for tg in targets_for(ch.class_id, build):
			var nid: String = tg["node"]
			if ch.allocated.has(nid) or ch.level < int(tg["at"]):
				continue
			var path: Array = ch.path_to(nid)
			if path.is_empty():
				continue
			var first: String = path[0]
			if _cost(first) > ch.available_passive_points():
				waiting = true     # save the point for the 2-point keystone
				break
			var opt := ""
			if ch.is_mastery(first):
				opt = best_mastery_option(ch, first)
			if ch.allocate(first, opt):
				if opt != "":
					lines.append("MASTERY %s = %s" % [first, opt])
				lines.append("PASSIVE %s (%s) towards %s, %d left on route" % [first, Data.passives[first].get("name", ""), nid, path.size() - 1])
				acted = true
				break
		if acted:
			continue
		if waiting:
			break
		var base: float = hub.score(ch)
		var best := ""
		var best_v := -INF
		for id in _frontier(ch):
			var al: Array = ch.allocated.duplicate()
			al.append(id)
			var g1: float = hub.score(ch, null, al) - base + _flag_bonus(id)
			var v := g1 / _cost(id)
			for l in Data.passives[id].get("links", []):
				var ln: Dictionary = Data.passives.get(l, {})
				if ch.allocated.has(l) or ln.is_empty() or ln.get("type") in ["start", "keystone", "mastery", "socket"]:
					continue
				var al2 := al.duplicate()
				al2.append(l)
				var g2: float = hub.score(ch, null, al2) - base + _flag_bonus(id) + _flag_bonus(l)
				v = maxf(v, g2 / (_cost(id) + _cost(l)) * 0.9)
			if v > best_v:
				best_v = v
				best = id
		if best == "" or not ch.allocate(best):
			break
		lines.append("PASSIVE %s (%s) value %.4f" % [best, Data.passives[best].get("name", ""), best_v])
	return lines

func keystones(ch) -> Array:
	var out := []
	for id in ch.allocated:
		if Data.passives.get(id, {}).get("type", "") == "keystone":
			out.append(id)
	return out
