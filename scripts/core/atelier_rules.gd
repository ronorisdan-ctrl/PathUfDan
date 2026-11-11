extends RefCounted
## Endgame Phase 3B: the Atelier (docs/ENDGAME_PHASE3.md, data/atlas.json "atelier"), the
## choice-based board that replaced the Varnish slots. Pure rules on the atlas state; no scene access.
## State: atlas["atelier"] = {"taken": [node ids], "choices": {choice node id: option id}, "bonus": dev points}.
## Points are never stored: they are counted from the atlas (first clears of ring 2+ regions and
## Layer Warden first kills), so existing characters get what their saves already earned.
## The effects of the taken nodes are AtlasRules.atelier_fx(st) (zone parameters only).

const AtlasRules = preload("res://scripts/core/atlas_rules.gd")

static func cfg() -> Dictionary:
	return AtlasRules.atelier_cfg()

static func state(st: Dictionary) -> Dictionary:
	if typeof(st.get("atelier")) != TYPE_DICTIONARY:
		st["atelier"] = {"taken": [], "choices": {}, "bonus": 0}
	var a: Dictionary = st["atelier"]
	if typeof(a.get("taken")) != TYPE_ARRAY:
		a["taken"] = []
	if typeof(a.get("choices")) != TYPE_DICTIONARY:
		a["choices"] = {}
	return a

static func taken(st: Dictionary) -> Array:
	return state(st)["taken"]

static func is_taken(st: Dictionary, id: String) -> bool:
	return taken(st).has(id)

static func choice_of(st: Dictionary, id: String) -> String:
	return str(state(st)["choices"].get(id, ""))

static func wedges() -> Array:
	return cfg().get("wedges", [])

static func cost_of(node: Dictionary) -> int:
	return int(cfg().get("costs", {}).get(str(node.get("kind", "small")), 1))

# ------------------------------------------------------------------ points
## Points from first clears: points.region per cleared region in ring >= region_min_ring, max region_cap.
static func region_points(st: Dictionary) -> int:
	var pc: Dictionary = cfg().get("points", {})
	var n := 0
	for k in st.get("clears", {}):
		if AtlasRules.ring_of(AtlasRules.parse(str(k))) >= int(pc.get("region_min_ring", 2)) and int(st["clears"][k]) > 0:
			n += 1
	return mini(n * int(pc.get("region", 1)), int(pc.get("region_cap", 18)))

## Points from Layer Warden first kills: points.warden each (+ warden_points from the given node set).
static func warden_points(st: Dictionary, ids: Array = [], choices: Dictionary = {}) -> int:
	var per := int(cfg().get("points", {}).get("warden", 2)) + int(AtlasRules.fx_of(ids, choices)["warden_points"])
	var n := 0
	for r in AtlasRules.warden_rings():
		if AtlasRules.warden_kills(st, r) > 0:
			n += 1
	return n * per

## Points available with a node set (default: the taken one).
static func points_total(st: Dictionary, ids = null, choices = null) -> int:
	var a := state(st)
	var t: Array = a["taken"] if ids == null else ids
	var c: Dictionary = a["choices"] if choices == null else choices
	return region_points(st) + warden_points(st, t, c) + int(a.get("bonus", 0))

static func points_spent(st: Dictionary, ids = null) -> int:
	var t: Array = taken(st) if ids == null else ids
	var n := 0
	for id in t:
		var node := AtlasRules.atelier_node(str(id))
		if not node.is_empty():
			n += cost_of(node)
	return n

static func points_free(st: Dictionary) -> int:
	return points_total(st) - points_spent(st)

## The most points a character can earn (region cap + every Warden; Master's Lesson raises it).
static func points_max(st: Dictionary = {}) -> int:
	var pc: Dictionary = cfg().get("points", {})
	var per := int(pc.get("warden", 2))
	if not st.is_empty():
		per += int(AtlasRules.atelier_fx(st)["warden_points"])
	return int(pc.get("region_cap", 18)) + per * AtlasRules.warden_rings().size()

# ------------------------------------------------------------------ paths
## Why node `id` cannot be in the set `ids` given the rest of the set ("" = its path is fine).
## Smalls are open from the hub; the choice needs choice_needs smalls of its wedge; the notable the
## choice; the tip the notable.
static func path_refusal(ids: Array, id: String) -> String:
	var node := AtlasRules.atelier_node(id)
	if node.is_empty():
		return "Unknown node"
	var w := str(node.get("wedge", ""))
	var kind := str(node.get("kind", ""))
	match kind:
		"choice":
			var need := int(cfg().get("choice_needs", 2))
			if _count_kind(ids, w, "small") < need:
				return "Needs %d small nodes of this wedge" % need
		"notable":
			if _count_kind(ids, w, "choice") < 1:
				return "Needs the wedge's choice node"
		"tip":
			if _count_kind(ids, w, "notable") < 1:
				return "Needs the wedge's notable"
	return ""

static func _count_kind(ids: Array, wedge: String, kind: String) -> int:
	var n := 0
	for id in ids:
		var node := AtlasRules.atelier_node(str(id))
		if str(node.get("wedge", "")) == wedge and str(node.get("kind", "")) == kind:
			n += 1
	return n

## True when every node of the set has its path.
static func paths_ok(ids: Array) -> bool:
	for id in ids:
		if path_refusal(ids, str(id)) != "":
			return false
	return true

# ------------------------------------------------------------------ actions
## Why node `id` (with option `opt` for a choice node) cannot be taken ("" = it can).
static func take_refusal(st: Dictionary, id: String, opt: String = "") -> String:
	var node := AtlasRules.atelier_node(id)
	if node.is_empty():
		return "Unknown node"
	if node.get("needs_3c", false):
		return "Arrives with the Burning Canvas and the Pigment Wells (Phase 3C)"
	if is_taken(st, id):
		return "Already taken"
	if str(node.get("kind", "")) == "choice":
		var o := AtlasRules.atelier_option(node, opt)
		if o.is_empty():
			return "Pick one of the three"
		if o.get("needs_3c", false):
			return "Arrives with the Burning Canvas and the Pigment Wells (Phase 3C)"
	var ids: Array = taken(st).duplicate()
	ids.append(id)
	var why := path_refusal(ids, id)
	if why != "":
		return why
	var ch: Dictionary = state(st)["choices"].duplicate()
	if opt != "":
		ch[id] = opt
	if points_spent(st, ids) > points_total(st, ids, ch):
		return "Needs %d point%s (%d free)" % [cost_of(node), "" if cost_of(node) == 1 else "s", points_free(st)]
	return ""

static func take(st: Dictionary, id: String, opt: String = "") -> bool:
	if take_refusal(st, id, opt) != "":
		return false
	var a := state(st)
	a["taken"].append(id)
	if str(AtlasRules.atelier_node(id).get("kind", "")) == "choice":
		a["choices"][id] = opt
	return true

## Why a taken node cannot be refunded on its own ("" = it can): nothing taken may need it and the
## points must still cover the rest (Master's Lesson's points can be spent).
static func refund_refusal(st: Dictionary, id: String) -> String:
	if not is_taken(st, id):
		return "Not taken"
	var ids: Array = taken(st).duplicate()
	ids.erase(id)
	if not paths_ok(ids):
		return "Other nodes of this wedge need it: refund them first"
	var ch: Dictionary = state(st)["choices"].duplicate()
	ch.erase(id)
	if points_spent(st, ids) > points_total(st, ids, ch):
		return "Its points are spent elsewhere: refund other nodes first"
	return ""

static func refund(st: Dictionary, id: String) -> bool:
	if refund_refusal(st, id) != "":
		return false
	var a := state(st)
	a["taken"].erase(id)
	a["choices"].erase(id)
	_trim_easel(st)
	return true

## Free respec: every node back. Returns the points refunded.
static func respec(st: Dictionary) -> int:
	var n := points_spent(st)
	var a := state(st)
	a["taken"] = []
	a["choices"] = {}
	_trim_easel(st)
	return n

## Pigments slotted beyond the Easel's slots (The Third Colour refunded) go back to the stock.
static func _trim_easel(st: Dictionary) -> void:
	var easel: Array = st.get("easel", [])
	while easel.size() > AtlasRules.easel_slots(st):
		st["pigments"].append(easel.pop_back())

## Sets nodes directly, without paths or points (smartbot / dev / tests). Each spec is "id" or
## "id:option"; an old Varnish id maps to its node (varnish_map). Unknown specs are skipped.
## Returns the ids set.
static func set_nodes(st: Dictionary, specs: Array, keep: bool = false) -> Array:
	var a := state(st)
	if not keep:
		a["taken"] = []
		a["choices"] = {}
	var vmap: Dictionary = cfg().get("varnish_map", {})
	var out := []
	for sp in specs:
		var parts := str(sp).strip_edges().split(":")
		var id := str(vmap.get(parts[0], parts[0]))
		var node := AtlasRules.atelier_node(id)
		if node.is_empty() or node.get("needs_3c", false):
			continue
		if str(node.get("kind", "")) == "choice":
			var opt := parts[1] if parts.size() > 1 else "a"
			var o := AtlasRules.atelier_option(node, opt)
			if o.is_empty() or o.get("needs_3c", false):
				continue
			a["choices"][id] = opt
		if not a["taken"].has(id):
			a["taken"].append(id)
		out.append(id)
	return out

## Makes a loaded set legal: nodes whose path broke are dropped (outermost first); if the points no
## longer cover the rest, everything is refunded (free respec) and atlas.atelier_reset is set.
static func fix(st: Dictionary) -> void:
	var a := state(st)
	var guard := 0
	while not paths_ok(a["taken"]) and guard < 50:
		guard += 1
		for id in a["taken"].duplicate():
			if path_refusal(a["taken"], str(id)) != "":
				a["taken"].erase(id)
				a["choices"].erase(id)
				break
	for id in a["choices"].keys():
		if not a["taken"].has(id):
			a["choices"].erase(id)
	if points_spent(st) > points_total(st):
		respec(st)
		st["atelier_reset"] = true

## "taken", "open" (can be taken now), "locked" (path), "poor" (path fine, not enough points) or
## "3c" (arrives in Phase 3C). For a choice node "open" means at least one option can be taken.
static func node_status(st: Dictionary, id: String) -> String:
	var node := AtlasRules.atelier_node(id)
	if node.get("needs_3c", false):
		return "3c"
	if is_taken(st, id):
		return "taken"
	var ids: Array = taken(st).duplicate()
	ids.append(id)
	if path_refusal(ids, id) != "":
		return "locked"
	var opt := ""
	if str(node.get("kind", "")) == "choice":
		for o in node.get("options", []):
			if not o.get("needs_3c", false):
				opt = str(o["id"])
				if take_refusal(st, id, opt) == "":
					return "open"
		return "poor"
	return "open" if take_refusal(st, id, opt) == "" else "poor"

## Short summary for the Atlas panel: "Atelier: 7 / 12 points".
static func summary_text(st: Dictionary) -> String:
	return "Atelier: %d / %d points spent" % [points_spent(st), points_total(st)]
