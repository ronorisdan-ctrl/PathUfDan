extends RefCounted
## Endgame Phase 3D: the Overpainter, the pinnacle boss (Apprentice). docs/ENDGAME_PHASE3.md
## Stage 3D, data/atlas.json `pinnacle`. Pure rules: the set of Ground Pigments, the lock and its
## tries, the study order, the boss def, the arena def, the Erasure sections, the brush rewards and
## the Atlas centre hex state. The live fight is in scripts/world/pinnacle_arena.gd (owned by the
## dungeon); it passes its own RNG stream in, so the main run stream is never touched.
##
## State: atlas.pinnacle = {set: [rings], tries, attempts, wins, in_fight, first, owned: [unique ids]}
## and atlas.warden_order = [rings in first-kill order] (kept by AtlasRules.warden_victory).

const AtlasRules = preload("res://scripts/core/atlas_rules.gd")

static func cfg() -> Dictionary:
	return AtlasRules.cfg().get("pinnacle", {})

static func need() -> int:
	return int(cfg().get("need", AtlasRules.ward_cfg().get("pinnacle_need", 4)))

static func max_tries() -> int:
	return maxi(1, int(cfg().get("tries", 3)))

static func new_pin() -> Dictionary:
	return {"set": [], "tries": 0, "attempts": 0, "wins": 0, "in_fight": false, "first": false, "owned": []}

## The pinnacle block of an atlas state (created when missing).
static func pin(st: Dictionary) -> Dictionary:
	if typeof(st.get("pinnacle")) != TYPE_DICTIONARY:
		st["pinnacle"] = new_pin()
	return st["pinnacle"]

static func wins(st: Dictionary) -> int:
	return int(st.get("pinnacle", {}).get("wins", 0)) if typeof(st.get("pinnacle")) == TYPE_DICTIONARY else 0

## Rings whose Ground Pigment the character owns (ring order).
static func owned_layers(st: Dictionary) -> Array:
	var out := []
	for r in AtlasRules.warden_rings():
		if AtlasRules.ground_count(st, int(r)) > 0:
			out.append(int(r))
	return out

## Warden rings in first-kill order. Kills recorded before Phase 3D (no atlas.warden_order entry)
## follow in ring order, then the rings never beaten.
static func kill_order(st: Dictionary) -> Array:
	var out := []
	var rings := AtlasRules.warden_rings()
	var src = st.get("warden_order", [])
	if typeof(src) == TYPE_ARRAY:
		for r in src:
			var ri := int(r)
			if rings.has(ri) and not out.has(ri):
				out.append(ri)
	for r in rings:
		if not out.has(int(r)) and AtlasRules.warden_kills(st, int(r)) > 0:
			out.append(int(r))
	for r in rings:
		if not out.has(int(r)):
			out.append(int(r))
	return out

## The set's rings in study order (phase 1 casts their signatures in this order).
static func study_order(st: Dictionary, rings: Array) -> Array:
	var ko := kill_order(st)
	var out := []
	for r in ko:
		if rings.has(int(r)):
			out.append(int(r))
	return out

static func locked(st: Dictionary) -> bool:
	return pin(st).get("set", []).size() == need()

static func locked_set(st: Dictionary) -> Array:
	return pin(st).get("set", []).duplicate() if locked(st) else []

static func tries_left(st: Dictionary) -> int:
	return int(pin(st).get("tries", 0)) if locked(st) else max_tries()

static func is_ready(st: Dictionary) -> bool:
	return locked(st) or owned_layers(st).size() >= need()

## Cleans a picked set: distinct Warden rings, sorted.
static func _clean_set(rings) -> Array:
	var out := []
	if typeof(rings) != TYPE_ARRAY:
		return out
	var valid := AtlasRules.warden_rings()
	for r in rings:
		var ri := int(r) if (r is int or r is float or str(r).is_valid_int()) else 0
		if valid.has(ri) and not out.has(ri):
			out.append(ri)
	out.sort()
	return out

## Why this set cannot enter ("" = it can). A locked set can only enter with itself.
static func set_refusal(st: Dictionary, rings: Array) -> String:
	var s := _clean_set(rings)
	if locked(st):
		var ls: Array = locked_set(st)
		if s != ls:
			return "The set is locked in until it is spent"
		if tries_left(st) <= 0:
			return "No tries left"
		return ""
	if owned_layers(st).size() < need():
		return "Needs Ground Pigments of %d layers (you have %d)" % [need(), owned_layers(st).size()]
	if s.size() != need() or s.size() != rings.size():
		return "Pick exactly %d different layers" % need()
	for r in s:
		if AtlasRules.ground_count(st, int(r)) <= 0:
			return "You have no %s" % str(AtlasRules.warden_cfg(int(r)).get("ground", "Ground Pigment"))
	return ""

## Starts a fight with this set: locks it (first time) and uses a try. Returns "" or the refusal.
static func enter(st: Dictionary, rings: Array) -> String:
	var why := set_refusal(st, rings)
	if why != "":
		return why
	var p := pin(st)
	if not locked(st):
		p["set"] = _clean_set(rings)
		p["tries"] = max_tries()
	p["tries"] = int(p["tries"]) - 1
	p["attempts"] = int(p.get("attempts", 0)) + 1
	p["in_fight"] = true
	return ""

## Spends 1 Ground Pigment of each layer in the locked set and unlocks it.
static func _spend(st: Dictionary) -> Array:
	var p := pin(st)
	var spent := []
	for r in p.get("set", []):
		var n := AtlasRules.ground_count(st, int(r))
		if n > 0:
			AtlasRules._wset(st, "ground", int(r), n - 1)
			spent.append(int(r))
	p["set"] = []
	p["tries"] = 0
	return spent

## Ends the fight in progress (idempotent: nothing happens when no fight is in progress).
## won: spends the set, counts the win, picks the brush (class_id; "" = no brush).
## lost: the try is already used; the last try spends the set.
## Returns {} or {won, spent: [rings], first, brush, tries_left}.
static func finish(st: Dictionary, won: bool, class_id: String = "") -> Dictionary:
	var p := pin(st)
	if not p.get("in_fight", false):
		return {}
	p["in_fight"] = false
	var out := {"won": won, "spent": [], "first": false, "brush": "", "tries_left": int(p.get("tries", 0))}
	if won:
		out["first"] = not p.get("first", false)
		out["brush"] = pick_brush(st, class_id) if class_id != "" else ""
		p["first"] = true
		p["wins"] = int(p.get("wins", 0)) + 1
		if out["brush"] != "" and not p["owned"].has(out["brush"]):
			p["owned"].append(out["brush"])
		out["spent"] = _spend(st)
		out["tries_left"] = 0
	elif int(p.get("tries", 0)) <= 0:
		out["spent"] = _spend(st)
	return out

# ------------------------------------------------------------------ brushes
static func brush_map() -> Dictionary:
	return cfg().get("brushes", {})

static func brush_ids() -> Array:
	var out := []
	for k in brush_map():
		var id := str(brush_map()[k])
		if Data.uniques.has(id) and not out.has(id):
			out.append(id)
	return out

static func is_brush_item(it: Dictionary) -> bool:
	return str(it.get("slot", "")) == "brush" or brush_ids().has(str(it.get("unique", "")))

## The brush a win gives (call before the win is counted). First kill: the class's brush.
## Later: a brush not owned yet (class-weighted), then any (class-weighted). Seeded by the atlas
## seed and the win count.
static func pick_brush(st: Dictionary, class_id: String) -> String:
	var p := pin(st)
	var bm := brush_map()
	var mine := str(bm.get(class_id, ""))
	var all := brush_ids()
	if all.is_empty():
		return ""
	if not p.get("first", false) and all.has(mine):
		return mine
	var pool := []
	for id in all:
		if not p.get("owned", []).has(id):
			pool.append(id)
	if pool.is_empty():
		pool = all.duplicate()
	var cw := float(cfg().get("class_weight", 60))
	var ow := float(cfg().get("other_weight", 20))
	var total := 0.0
	for id in pool:
		total += cw if id == mine else ow
	var rng := AtlasRules._rng(int(st.get("seed", 1)), Vector2i(int(p.get("wins", 0)), 3), 950)
	var roll := rng.randf() * total
	for id in pool:
		roll -= cw if id == mine else ow
		if roll <= 0.0:
			return id
	return pool[pool.size() - 1]

## Effect parameters of a brush unique (data/uniques.json effect_params).
static func brush_params(effect: String) -> Dictionary:
	for u in Data.uniques.values():
		if str(u.get("effect", "")) == effect:
			return u.get("effect_params", {})
	return {}

# ------------------------------------------------------------------ the fight
## The Overpainter's def for this study order: the Warden signatures become phase 1, phase
## thresholds, life and damage come from the pinnacle block, phase 3 drains poise faster.
static func boss_def(bd: Dictionary, studies: Array) -> Dictionary:
	var c := cfg()
	var d := bd.duplicate(true)
	var pats: Dictionary = d.get("patterns", {})
	var seq := []
	var i := 0
	for r in studies:
		var wc := AtlasRules.warden_cfg(int(r))
		var sig := str(wc.get("signature", ""))
		var src: Dictionary = wc.get("add", {}).get(sig, {})
		if src.is_empty():
			continue
		var pd: Dictionary = src.duplicate(true)
		pd["mult"] = float(pd.get("mult", 1.0)) * float(c.get("study_mult", 1.0))
		pd["study"] = int(r)
		var pid := "study_%d_%s" % [i, sig]
		pats[pid] = pd
		seq.append(pid)
		i += 1
	var phases: Array = d.get("phases", [])
	if phases.size() >= 3:
		var filler := str(c.get("filler", "study_fan"))
		var p0: Dictionary = phases[0]
		var pl: Array = [filler] if pats.has(filler) else []
		pl.append_array(seq)
		p0["patterns"] = pl
		p0["sequence"] = seq
		phases[1]["at"] = float(c.get("phase2_at", 0.7))
		phases[1]["erasure"] = true
		phases[2]["at"] = float(c.get("phase3_at", 0.35))
		phases[2]["poise"] = c.get("phase3_poise", {}).duplicate()
		phases[2]["bare"] = true
	d["patterns"] = pats
	d["phases"] = phases
	d["life"] = float(d.get("life", 100)) * float(c.get("life_mult", 1.0))
	var dm := float(c.get("damage_mult", 1.0))
	var dmg: Array = d.get("damage", [1, 1])
	d["damage"] = [int(round(float(dmg[0]) * dm)), int(round(float(dmg[1]) * dm))]
	d["studies"] = studies.duplicate()
	d["pinnacle"] = true
	return d

## The run def of the Bare Ground arena (not an Atlas zone: no hex, Rot, mechanics, Pigments,
## run modifiers or Atelier rules).
static func arena_def(st: Dictionary) -> Dictionary:
	var c := cfg()
	var lvl := int(c.get("level", 68))
	return {"id": "pinnacle:overpainter", "name": "The Bare Ground", "generator": "pinnacle", "pinnacle": true,
		"spike": true, "atlas": false, "tier": 1, "min_level": lvl, "max_level": lvl, "boss": "overpainter",
		"palette": str(c.get("palette", "sanctum")), "ambient": str(c.get("ambient", "#8a8478")),
		"life_mult": 1.0, "damage_mult": 1.0, "resist_bonus": float(c.get("resist_bonus", 45)),
		"rarity_bonus": float(c.get("rarity_bonus", 320)), "objectives": ["boss"], "pool": [], "hazards": [],
		"packs_per_room": [0, 0], "elite_chance": 0.0, "mod_count": [0, 0],
		"studies": study_order(st, locked_set(st)), "arena_radius": int(c.get("arena_radius", 12))}

## Erasure section of a point relative to the arena centre (px): -1 inside the safe disc or
## outside the arena, else 0 .. sections-1 (section 0 starts at angle 0, clockwise in screen space).
static func section_at(rel: Vector2, tile: float = 16.0) -> int:
	var c := cfg()
	var d := rel.length()
	if d < float(c.get("safe_radius", 3)) * tile or d > (float(c.get("arena_radius", 12)) + 0.5) * tile:
		return -1
	var n := maxi(1, int(c.get("sections", 8)))
	var a := fposmod(rel.angle(), TAU)
	return clampi(int(a / (TAU / n)), 0, n - 1)

## The painted section nearest to rel (by angle; -1 when none is painted).
static func nearest_painted(painted: Array, rel: Vector2) -> int:
	if painted.is_empty():
		return -1
	var n := maxi(1, int(cfg().get("sections", 8)))
	var a := fposmod(rel.angle(), TAU)
	var best := -1
	var bd := 99.0
	for s in painted:
		var mid := (int(s) + 0.5) * TAU / n
		var dd := absf(wrapf(a - mid, -PI, PI))
		if dd < bd:
			bd = dd
			best = int(s)
	return best

## The next section to paint over: a random unpainted one (rng = the arena's own stream);
## -1 when max_painted are painted already.
static func next_section(painted: Array, rng: RandomNumberGenerator) -> int:
	var n := maxi(1, int(cfg().get("sections", 8)))
	if painted.size() >= mini(n, int(cfg().get("max_painted", 6))):
		return -1
	var free := []
	for s in n:
		if not painted.has(s):
			free.append(s)
	if free.is_empty():
		return -1
	return int(free[rng.randi_range(0, free.size() - 1)])

# ------------------------------------------------------------------ the Atlas centre hex
static func layer_name(ring: int) -> String:
	return str(AtlasRules.ring_cfg(ring).get("layer", "Layer %d" % ring))

## {state: locked | ready | set | beaten, text, short, wins, tries, set}
static func hex_state(st: Dictionary) -> Dictionary:
	var p := pin(st)
	var w := int(p.get("wins", 0))
	var out := {"wins": w, "tries": tries_left(st), "set": locked_set(st)}
	var beaten := " Beaten %d time%s." % [w, "" if w == 1 else "s"] if w > 0 else ""
	if locked(st):
		var names := []
		for r in locked_set(st):
			names.append(layer_name(int(r)))
		out["state"] = "set"
		out["short"] = "%d tr%s left" % [tries_left(st), "y" if tries_left(st) == 1 else "ies"]
		out["text"] = "The Bare Ground: set locked (%s), %d tr%s left. A win or the last try spends the set.%s" % [", ".join(names), tries_left(st), "y" if tries_left(st) == 1 else "ies", beaten]
	elif owned_layers(st).size() >= need():
		out["state"] = "ready"
		out["short"] = "Ready"
		out["text"] = "The Bare Ground is open: pick %d Ground Pigments to face the Overpainter (%d tries per set).%s" % [need(), max_tries(), beaten]
	elif w > 0:
		out["state"] = "beaten"
		out["short"] = "Beaten x%d" % w
		out["text"] = "The Overpainter is beaten (%d time%s). Ground Pigments: %d of %d layers." % [w, "" if w == 1 else "s", owned_layers(st).size(), need()]
	else:
		out["state"] = "locked"
		out["short"] = "%d/%d" % [owned_layers(st).size(), need()]
		out["text"] = "The Bare Ground opens with Ground Pigments of %d layers (you have %d). Layer Wardens drop them." % [need(), owned_layers(st).size()]
	return out

# ------------------------------------------------------------------ saving
## Cleans a loaded pinnacle block into st (call after the Warden keys are loaded). A fight that
## was in progress when the game closed counts as a used try (the last try spends the set).
static func sanitize(st: Dictionary, raw) -> void:
	var p := new_pin()
	if typeof(raw) == TYPE_DICTIONARY:
		var s := _clean_set(raw.get("set", []))
		if s.size() == need():
			p["set"] = s
			p["tries"] = clampi(int(raw.get("tries", 0)), 0, max_tries())
		p["attempts"] = maxi(0, int(raw.get("attempts", 0)))
		p["wins"] = maxi(0, int(raw.get("wins", 0)))
		p["first"] = bool(raw.get("first", false)) or int(p["wins"]) > 0
		var ow = raw.get("owned", [])
		if typeof(ow) == TYPE_ARRAY:
			for id in ow:
				if brush_ids().has(str(id)) and not p["owned"].has(str(id)):
					p["owned"].append(str(id))
		p["in_fight"] = bool(raw.get("in_fight", false)) and not p["set"].is_empty()
	st["pinnacle"] = p
	if p["in_fight"]:
		finish(st, false)
	elif not p["set"].is_empty() and int(p["tries"]) <= 0:
		_spend(st)
