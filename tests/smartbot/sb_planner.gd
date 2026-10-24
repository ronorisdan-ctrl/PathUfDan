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
	return TARGETS.get(cls, {}).get(build, [])

func _cost(id: String) -> int:
	return int(Data.passives.get(id, {}).get("cost", 1))

func _frontier(ch) -> Array:
	var out := []
	for n in Data.passive_list:
		var id: String = n["id"]
		if n.get("type") in ["start", "keystone"]:
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
			if ch.allocate(first):
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
				if ch.allocated.has(l) or ln.is_empty() or ln.get("type") in ["start", "keystone"]:
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
