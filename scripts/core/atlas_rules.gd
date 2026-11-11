extends RefCounted
## Endgame Phase 1A: the Atlas of Ruin (docs/ENDGAME_PHASE1.md, data/atlas.json).
## Pure rules, no scene access. Hexes use axial coordinates (q, r); the hub is (0, 0).
## Saved state (CharacterData.atlas, save key "atlas"):
##   {"seed": int, "revealed": ["q,r", ...], "clears": {"q,r": int},
##    "rot": {"q,r": 1-5}, "restored": ["q,r", ...], "spreads": int, "fester": int}   (Rot: Phase 1C)
## Everything else about a hex (biome, boss, vantage, base modifiers, layout seed) is derived
## from hash(seed, q, r), so the save stays tiny and any hex can be replayed by seed.

const DIRS := [Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)]

static func cfg() -> Dictionary:
	return Data.atlas_cfg

static func radius(c: Dictionary = {}) -> int:
	if c.is_empty():
		c = cfg()
	return int(c.get("radius", 3))

# ------------------------------------------------------------------ hex maths
static func key(h: Vector2i) -> String:
	return "%d,%d" % [h.x, h.y]

static func parse(k: String) -> Vector2i:
	var p := k.split(",")
	if p.size() != 2 or not p[0].is_valid_int() or not p[1].is_valid_int():
		return Vector2i(9999, 9999)
	return Vector2i(int(p[0]), int(p[1]))

static func ring_of(h: Vector2i) -> int:
	return (absi(h.x) + absi(h.y) + absi(h.x + h.y)) / 2

static func neighbours(h: Vector2i) -> Array:
	var out := []
	for d in DIRS:
		out.append(h + d)
	return out

## Every hex within `rad` of `c` (including c), in a stable order.
static func within(c: Vector2i, rad: int) -> Array:
	var out := []
	for q in range(-rad, rad + 1):
		for r in range(maxi(-rad, -q - rad), mini(rad, -q + rad) + 1):
			out.append(c + Vector2i(q, r))
	return out

static func in_atlas(h: Vector2i, c: Dictionary = {}) -> bool:
	return ring_of(h) <= radius(c)

## Pixel centre of a hex (pointy-top), size = corner radius.
static func to_pixel(h: Vector2i, size: float) -> Vector2:
	return Vector2(size * sqrt(3.0) * (h.x + h.y / 2.0), size * 1.5 * h.y)

static func from_pixel(p: Vector2, size: float) -> Vector2i:
	var q := (sqrt(3.0) / 3.0 * p.x - p.y / 3.0) / size
	var r := (2.0 / 3.0 * p.y) / size
	return _round(q, r)

static func _round(qf: float, rf: float) -> Vector2i:
	var sf := -qf - rf
	var q := roundi(qf)
	var r := roundi(rf)
	var s := roundi(sf)
	var dq := absf(q - qf)
	var dr := absf(r - rf)
	var ds := absf(s - sf)
	if dq > dr and dq > ds:
		q = -r - s
	elif dr > ds:
		r = -q - s
	return Vector2i(q, r)

# ------------------------------------------------------------------ seeded derivation
## Deterministic RNG for (seed, hex, salt). Same inputs -> same stream on every run.
static func _rng(seed_value: int, h: Vector2i, salt: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 1000003 + (h.x + 64) * 7919 + (h.y + 64) * 104729 + salt * 15485863
	rng.randi()
	return rng

static func ring_cfg(ring: int, c: Dictionary = {}) -> Dictionary:
	if c.is_empty():
		c = cfg()
	var rings: Array = c.get("rings", [])
	if rings.is_empty():
		return {}
	return rings[clampi(ring - 1, 0, rings.size() - 1)]

## Which sixth of the map (0-5) a hex sits in, by angle from the hub.
static func sector(h: Vector2i) -> int:
	var p := to_pixel(h, 1.0)
	var a := fposmod(atan2(p.y, p.x) + PI / 6.0, TAU)
	return int(a / (TAU / 6.0)) % 6

static func _weighted(rng: RandomNumberGenerator, items: Array) -> Dictionary:
	var total := 0.0
	for it in items:
		total += float(it.get("w", 1))
	var roll := rng.randf() * total
	for it in items:
		roll -= float(it.get("w", 1))
		if roll < 0:
			return it
	return items[items.size() - 1] if not items.is_empty() else {}

## Biome: each sixth of the map gets one biome; `biome_stray` of hexes pick another at random.
static func biome_of(seed_value: int, h: Vector2i, c: Dictionary = {}) -> Dictionary:
	if c.is_empty():
		c = cfg()
	var biomes: Array = c.get("biomes", []).filter(func(b): return Data.zones.has(str(b.get("zone", ""))))
	if biomes.is_empty():
		return {}
	var srng := _rng(seed_value, Vector2i(sector(h), 99), 1)
	var b := _weighted(srng, biomes)
	var hrng := _rng(seed_value, h, 2)
	if hrng.randf() < float(c.get("biome_stray", 0.25)):
		b = _weighted(hrng, biomes)
	return b

## Display/derived info for one hex. Empty for the hub and hexes outside the atlas.
static func hex_info(seed_value: int, h: Vector2i, c: Dictionary = {}) -> Dictionary:
	if c.is_empty():
		c = cfg()
	var ring := ring_of(h)
	if ring < 1 or ring > radius(c):
		return {}
	var rc := ring_cfg(ring, c)
	var b := biome_of(seed_value, h, c)
	if b.is_empty():
		return {}
	var bosses: Array = c.get("bosses", []).filter(func(x): return Data.enemies.has(x))
	var boss: String = Data.zones[b["zone"]].get("boss", "")
	if not bosses.is_empty():
		boss = bosses[_rng(seed_value, h, 3).randi_range(0, bosses.size() - 1)]
	var vc: Dictionary = c.get("vantage", {})
	var vantage := ring >= int(vc.get("min_ring", 2)) and _rng(seed_value, h, 4).randf() < float(vc.get("chance", 0.15))
	return {"hex": h, "key": key(h), "ring": ring, "layer": str(rc.get("layer", "")), "level": int(rc.get("level", 40)),
		"zone": str(b["zone"]), "biome": str(b.get("short", b["zone"])), "biome_color": str(b.get("color", "#808080")),
		"boss": boss, "boss_name": str(Data.enemies.get(boss, {}).get("name", boss)), "vantage": vantage,
		"name": "%s of the %s" % [str(b.get("short", "Zone")), str(rc.get("layer", "Atlas"))]}

## The dungeon def that dungeon.gd runs for a hex: the biome zone def with ring scaling.
static func zone_def(seed_value: int, h: Vector2i, c: Dictionary = {}) -> Dictionary:
	if c.is_empty():
		c = cfg()
	var info := hex_info(seed_value, h, c)
	if info.is_empty():
		return {}
	var rc := ring_cfg(info["ring"], c)
	var d: Dictionary = Data.zones[info["zone"]].duplicate(true)
	d["id"] = "atlas:" + info["key"]
	d["name"] = info["name"]
	d["spike"] = false
	d["atlas"] = true
	d["atlas_hex"] = info["key"]
	d["atlas_ring"] = info["ring"]
	d["tier"] = int(c.get("tier", 6))
	d["min_level"] = info["level"]
	d["max_level"] = info["level"]
	d["boss"] = info["boss"]
	for k in ["life_mult", "damage_mult", "resist_bonus", "rarity_bonus", "mod_count", "elite_chance"]:
		if rc.has(k):
			d[k] = rc[k]
	if rc.has("ambient_tint"):   # Phase 3A: rings 4-6 tint the biome's light by painting layer
		d["ambient"] = "#" + Color(str(d.get("ambient", "#585060"))).lerp(Color(str(rc["ambient_tint"])), clampf(float(rc.get("ambient_tint_w", 0.35)), 0.0, 1.0)).to_html(false)
	return d

## Layout seed for the n-th run of a hex (a cleared hex plays a new layout each time).
static func layout_seed(seed_value: int, h: Vector2i, clears: int) -> int:
	return maxi(1, _rng(seed_value, h, 100 + clears).randi())

## Base modifiers for the n-th run of a hex, drawn from dungeon_mods.json.
## extra: more modifiers (the Atelier's base_mods); the first ones match the roll without it.
static func run_mods(seed_value: int, h: Vector2i, clears: int, d: Dictionary, extra: int = 0) -> Array:
	var mc: Array = d.get("mod_count", [0, 0])
	var rng := _rng(seed_value, h, 200 + clears)
	var n := rng.randi_range(int(mc[0]), int(mc[1])) + maxi(0, extra)
	var ids := []
	for m in Data.dungeon_mod_list:
		ids.append(m["id"])
	var out := []
	while out.size() < n and not ids.is_empty():
		out.append(ids.pop_at(rng.randi_range(0, ids.size() - 1)))
	return out

# ------------------------------------------------------------------ state
static func unlocked(ch) -> bool:
	if ch == null:
		return false
	var need: String = str(cfg().get("unlock_dungeon", "nightmare_vaults"))
	return ch.progress.get("bosses_killed", {}).has(need) or not ch.atlas.is_empty()

## A fresh atlas: ring 1 (around the hub) is revealed.
static func new_state(seed_value: int) -> Dictionary:
	var rev := []
	for h in within(Vector2i.ZERO, 1):
		if ring_of(h) == 1:
			rev.append(key(h))
	var st := {"seed": seed_value, "revealed": rev, "clears": {}, "rot": {}, "restored": [], "spreads": 0, "fester": 0,
		"pigments": [], "easel": [], "crafted": 0, "atelier": {"taken": [], "choices": {}, "bonus": 0}, "ring_sources": [],
		"shards": {}, "shard_dry": {}, "summons": {}, "ground": {}, "ground_dry": {}, "warden_kills": {}, "seen": []}
	seed_rot(st)
	return st

## Creates the character's atlas on first use. Returns the state.
static func ensure(ch, seed_value: int = 0) -> Dictionary:
	if ch.atlas.is_empty():
		var s := seed_value
		while s == 0:
			s = randi() & 0x7fffffff
		ch.atlas = new_state(s)
	return ch.atlas

## Cleans a loaded state: unknown/outside keys dropped, ring 1 always revealed.
static func sanitize(raw) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY or raw.is_empty():
		return {}
	var s := int(raw.get("seed", 0))
	if s == 0:
		return {}
	var st := new_state(s)
	var rev: Array = st["revealed"]
	var src_rev = raw.get("revealed", [])
	if typeof(src_rev) == TYPE_ARRAY:
		for k in src_rev:
			var h := parse(str(k))
			if ring_of(h) >= 1 and in_atlas(h) and not rev.has(key(h)):
				rev.append(key(h))
	var src_cl = raw.get("clears", {})
	if typeof(src_cl) == TYPE_DICTIONARY:
		for k in src_cl:
			var h := parse(str(k))
			var n := int(src_cl[k])
			if ring_of(h) >= 1 and in_atlas(h) and n > 0:
				st["clears"][key(h)] = n
				if not rev.has(key(h)):
					rev.append(key(h))
	# Rot (Phase 1C). An atlas saved before 1C has no "rot" key and gets its seeded sources.
	var rc := rot_cfg()
	var src_res = raw.get("restored", [])
	if typeof(src_res) == TYPE_ARRAY:
		for k in src_res:
			var h := parse(str(k))
			if ring_of(h) >= 1 and in_atlas(h) and not st["restored"].has(key(h)):
				st["restored"].append(key(h))
	var src_rot = raw.get("rot", null)
	if typeof(src_rot) == TYPE_DICTIONARY:
		st["rot"] = {}
		for k in src_rot:
			var h := parse(str(k))
			var n := clampi(int(src_rot[k]), 0, int(rc.get("max", 5)))
			if n > 0 and _rot_eligible(st, h):
				st["rot"][key(h)] = n
	st["spreads"] = maxi(0, int(raw.get("spreads", 0)))
	st["fester"] = clampi(int(raw.get("fester", 0)), 0, 20)
	# Pigments and Varnish (Phase 1E). Older saves have none.
	st["crafted"] = maxi(0, int(raw.get("crafted", 0)))
	var pc := pig_cfg()
	for k in ["pigments", "easel"]:
		var src = raw.get(k, [])
		if typeof(src) != TYPE_ARRAY:
			continue
		for p in src:
			var cp := _clean_pigment(p)
			if cp.is_empty():
				continue
			if k == "easel" and st["easel"].size() < int(pc.get("max_slots", 2)):
				st["easel"].append(cp)
			elif st["pigments"].size() + st["easel"].size() < int(pc.get("stock_cap", 12)) + int(pc.get("max_slots", 2)):
				st["pigments"].append(cp)
			st["crafted"] = maxi(int(st["crafted"]), int(cp["uid"]) + 1)
	_sanitize_wardens(st, raw)   # Layer Wardens (Phase 2A)
	# Phase 3B: ring 4-6 Rot sources already planted (never twice)
	var src_rs = raw.get("ring_sources", [])
	if typeof(src_rs) == TYPE_ARRAY:
		for r in src_rs:
			var ri := int(r) if (r is int or r is float or str(r).is_valid_int()) else 0
			if ri > int(rot_cfg().get("reach_ring", 3)) and ri <= radius() and not st["ring_sources"].has(ri):
				st["ring_sources"].append(ri)
	# Phase 3A (save v6): the atlas grew from radius 3 to 6. Every cleared hex reveals what its clear
	# would reveal now, so cleared ring 3 regions open their ring 4 neighbours on load.
	for k in st["clears"].keys():
		_reveal_from(st, parse(str(k)))
	plant_ring_sources(st)   # Phase 3B: saves that revealed ring 4+ before 3B get their source once
	# Phase 3C (save v8): the zone mechanics this character has met (Guild contracts need them). Older saves: none.
	var src_seen = raw.get("seen", [])
	if typeof(src_seen) == TYPE_ARRAY:
		for m in src_seen:
			if not mechanic_info(str(m)).is_empty() and not st["seen"].has(str(m)):
				st["seen"].append(str(m))
	# Restorers' Guild (Phase 2C); loaded at runtime because guild_rules.gd preloads this script
	var gs: Dictionary = load("res://scripts/core/guild_rules.gd").sanitize(raw.get("guild", {}))
	if not gs.is_empty():
		st["guild"] = gs
	# The Atelier (Phase 3B). Save v7: Varnishes (owned and slotted) become varnish_seals Guild Seals
	# each; atlas.varnish_converted keeps the count for a one-time message.
	_migrate_varnish(st, raw)
	st["atelier"] = _clean_atelier(raw.get("atelier", {}))
	load("res://scripts/core/atelier_rules.gd").fix(st)   # path and budget (runtime load: it preloads this script)
	return st

## Save v7: each owned Varnish (slotted ones are owned too) becomes varnish_seals Guild Seals, up to
## the Seal cap. The number converted and the Seals given are kept in atlas.varnish_converted
## {varnish, seals} until the player has seen the message (ack_varnish_message).
static func _migrate_varnish(st: Dictionary, raw: Dictionary) -> void:
	var conv = raw.get("varnish_converted", {})
	if typeof(conv) == TYPE_DICTIONARY and not conv.is_empty():
		st["varnish_converted"] = {"varnish": maxi(0, int(conv.get("varnish", 0))), "seals": maxi(0, int(conv.get("seals", 0)))}
	var src_v = raw.get("varnish", {})
	if typeof(src_v) != TYPE_DICTIONARY:
		return
	var vmap: Dictionary = atelier_cfg().get("varnish_map", {})
	var n := 0
	for id in src_v:
		if vmap.has(str(id)):
			n += clampi(int(src_v[id]), 0, 99)
	if n <= 0:
		return
	var gr = load("res://scripts/core/guild_rules.gd")
	var g: Dictionary = st["guild"] if typeof(st.get("guild")) == TYPE_DICTIONARY and not st["guild"].is_empty() else gr.new_guild()
	var cap := int(gr.cfg().get("seal_cap", 99))
	var before := int(g.get("seals", 0))
	g["seals"] = mini(cap, before + n * int(atelier_cfg().get("varnish_seals", 2)))
	st["guild"] = g
	var prev: Dictionary = st.get("varnish_converted", {"varnish": 0, "seals": 0})
	st["varnish_converted"] = {"varnish": int(prev.get("varnish", 0)) + n, "seals": int(prev.get("seals", 0)) + int(g["seals"]) - before}

## The one-time Varnish conversion message ("" when there is none); ack_varnish_message clears it.
static func varnish_message(st: Dictionary) -> String:
	var c: Dictionary = st.get("varnish_converted", {})
	if c.is_empty() or int(c.get("varnish", 0)) <= 0:
		return ""
	var t := "The Varnish slots are gone: the Atelier replaces them. Your %d Varnish%s became %d Guild Seal%s." % [
		int(c["varnish"]), "" if int(c["varnish"]) == 1 else "es", int(c.get("seals", 0)), "" if int(c.get("seals", 0)) == 1 else "s"]
	if int(c.get("seals", 0)) < int(c["varnish"]) * int(atelier_cfg().get("varnish_seals", 2)):
		t += " (The Seal cap kept the rest.)"
	return t

static func ack_varnish_message(st: Dictionary) -> void:
	st.erase("varnish_converted")

static func is_revealed(st: Dictionary, h: Vector2i) -> bool:
	return st.get("revealed", []).has(key(h))

static func clears(st: Dictionary, h: Vector2i) -> int:
	return int(st.get("clears", {}).get(key(h), 0))

static func can_enter(st: Dictionary, h: Vector2i) -> bool:
	return ring_of(h) >= 1 and in_atlas(h) and is_revealed(st, h)

## Records a completed run of hex h. Reveals its neighbours (radius 2 for a vantage hex)
## on every clear. Returns the keys that were newly revealed.
static func complete(st: Dictionary, h: Vector2i) -> Array:
	if not can_enter(st, h):
		return []
	st["clears"][key(h)] = clears(st, h) + 1
	return _reveal_from(st, h)

## Reveals what a clear of h reveals (its neighbours; radius 2 for a vantage hex). Returns new keys.
static func _reveal_from(st: Dictionary, h: Vector2i) -> Array:
	var info := hex_info(int(st["seed"]), h)
	var rad := int(cfg().get("vantage", {}).get("reveal", 2)) if info.get("vantage", false) else 1
	var fresh := []
	for n in within(h, rad):
		if ring_of(n) >= 1 and in_atlas(n) and not is_revealed(st, n):
			st["revealed"].append(key(n))
			fresh.append(key(n))
	if not fresh.is_empty():
		plant_ring_sources(st)
	return fresh

## Counts for the UI and tests: {revealed, cleared, total, rings: {ring: [cleared, total]}}.
static func summary(st: Dictionary) -> Dictionary:
	var rings := {}
	var total := 0
	var cleared := 0
	for h in within(Vector2i.ZERO, radius()):
		var rg := ring_of(h)
		if rg == 0:
			continue
		total += 1
		if not rings.has(rg):
			rings[rg] = [0, 0]
		rings[rg][1] += 1
		if clears(st, h) > 0:
			cleared += 1
			rings[rg][0] += 1
	return {"revealed": st.get("revealed", []).size(), "cleared": cleared, "total": total, "rings": rings}

# ------------------------------------------------------------------ Rot (Endgame Phase 1C)
## Rot is a per-hex level 0-5 that spreads one step per front after each completed zone (never
## in real time). Ring 1 and the hub are a safety ring; Restored hexes never take Rot again.
static func rot_cfg() -> Dictionary:
	return cfg().get("rot", {})

static func rot_of(st: Dictionary, h: Vector2i) -> int:
	return int(st.get("rot", {}).get(key(h), 0))

static func is_restored(st: Dictionary, h: Vector2i) -> bool:
	return st.get("restored", []).has(key(h))

static func _rot_eligible(st: Dictionary, h: Vector2i) -> bool:
	return in_atlas(h) and ring_of(h) >= int(rot_cfg().get("min_ring", 2)) and ring_of(h) <= rot_reach(st) and not is_restored(st, h)

## Phase 3A: the outermost ring Rot can be in: max(reach_ring, highest revealed ring). An atlas whose
## player is still in rings 1-3 behaves exactly like the radius-3 atlas.
static func rot_reach(st: Dictionary) -> int:
	return maxi(int(rot_cfg().get("reach_ring", 3)), rings_open(st))

static func rot_total(st: Dictionary) -> int:
	var t := 0
	for k in st.get("rot", {}):
		t += int(st["rot"][k])
	return t

## Highest ring with a revealed hex (at least 1).
static func rings_open(st: Dictionary) -> int:
	var m := 1
	for k in st.get("revealed", []):
		m = maxi(m, ring_of(parse(str(k))))
	return m

## Global Rot cap: cap_per_ring x the highest revealed ring.
static func rot_cap(st: Dictionary) -> int:
	return int(rot_cfg().get("cap_per_ring", 3)) * rings_open(st)

## Zone scaling at Rot n (n >= 1); {} at Rot 0.
static func rot_level(n: int) -> Dictionary:
	var lv: Array = rot_cfg().get("levels", [])
	if n <= 0 or lv.is_empty():
		return {}
	return lv[clampi(n - 1, 0, lv.size() - 1)]

## Seeded score for a hex in a given draw; the lowest score wins. Scoring every candidate
## (instead of picking by index) keeps the forecast stable when one candidate drops out.
static func _score(seed_value: int, h: Vector2i, draw: int) -> float:
	return _rng(seed_value, h, 1000 + draw).randf()

## Phase 3B (Dan, 2026-11-11): when a ring beyond reach_ring (4-6) is first revealed it gets
## ring_sources extra Rot source(s) at source_level, seeded by (atlas seed, ring). Recorded in
## atlas.ring_sources so a ring is never planted twice. Nothing happens while only rings <= reach_ring
## are revealed. Returns the keys planted.
static func plant_ring_sources(st: Dictionary) -> Array:
	var out := []
	var rc := rot_cfg()
	if not st.has("ring_sources"):
		st["ring_sources"] = []
	if not st.has("rot") or typeof(st["rot"]) != TYPE_DICTIONARY:
		st["rot"] = {}
	var open := rings_open(st)
	var sd := int(st.get("seed", 1))
	for rg in range(int(rc.get("reach_ring", 3)) + 1, mini(open, radius()) + 1):
		if st["ring_sources"].has(rg):
			continue
		st["ring_sources"].append(rg)
		var cands := []
		for h in within(Vector2i.ZERO, rg):
			if ring_of(h) == rg and _rot_eligible(st, h) and rot_of(st, h) == 0:
				cands.append(h)
		cands.sort_custom(func(a, b): return _score(sd + rg * 7919, a, 7000 + rg) < _score(sd + rg * 7919, b, 7000 + rg))
		for h in cands.slice(0, int(rc.get("ring_sources", 1))):
			st["rot"][key(h)] = int(rc.get("source_level", 1))
			out.append(key(h))
	return out

## Plants the seeded Rot sources of a new atlas (rings >= min_ring, lowest scores).
static func seed_rot(st: Dictionary) -> Array:
	var rc := rot_cfg()
	var n := int(rc.get("sources", 2))
	var lvl := int(rc.get("source_level", 1))
	var cands := []
	for h in within(Vector2i.ZERO, radius()):
		if _rot_eligible(st, h) and rot_of(st, h) == 0:
			cands.append(h)
	var sd := int(st["seed"])
	cands.sort_custom(func(a, b): return _score(sd, a, 0) < _score(sd, b, 0))
	var out := []
	for h in cands.slice(0, n):
		st["rot"][key(h)] = lvl
		out.append(key(h))
	return out

## Hexes a front can raise: eligible, below max, and a Rot hex or next to one.
## With no Rot left anywhere, every eligible hex is a candidate (a new source appears).
static func spread_candidates(st: Dictionary) -> Array:
	var mx := int(rot_cfg().get("max", 5))
	var any := rot_total(st) > 0
	var out := []
	for h in within(Vector2i.ZERO, radius()):
		if not _rot_eligible(st, h):
			continue
		var r := rot_of(st, h)
		if r >= mx:
			continue
		if not any or r > 0:
			out.append(h)
			continue
		for n in neighbours(h):
			if rot_of(st, n) > 0:
				out.append(h)
				break
	return out

static func fronts_next(st: Dictionary) -> int:
	return maxi(1, int(rot_cfg().get("fronts", 2)) + int(atelier_fx(st)["fronts"])) + int(st.get("fester", 0))

## One spread step (call once per completed zone). Returns the keys raised, in order.
## `from` = the hex just completed: with the Atelier's spread_local, a front only raises revealed
## hexes that are `from` or next to it; with none of those, any revealed hex (the front isn't lost).
static func spread(st: Dictionary, from: Vector2i = Vector2i(9999, 9999)) -> Array:
	if not st.has("rot"):
		st["rot"] = {}
	var sd := int(st["seed"])
	var fronts := fronts_next(st)
	var local: bool = atelier_fx(st)["spread_local"] and in_atlas(from)
	var draw := int(st.get("spreads", 0))
	st["fester"] = 0
	st["spreads"] = draw + 1
	var out := []
	for f in fronts:
		if rot_total(st) >= rot_cap(st):
			break
		var cands := spread_candidates(st)
		if local:
			cands = _local_candidates(st, cands, from)
		if cands.is_empty():
			break
		var best: Vector2i = cands[0]
		var bs := 2.0
		for h in cands:
			var sc := _score(sd, h, 1 + draw * 16 + f)
			if sc < bs:
				bs = sc
				best = h
		st["rot"][key(best)] = rot_of(st, best) + 1
		out.append(key(best))
	return out

## Atelier spread_local: the candidates limited to revealed hexes at or next to `from`, else to
## revealed hexes.
static func _local_candidates(st: Dictionary, cands: Array, from: Vector2i) -> Array:
	var near := []
	var rev := []
	for h in cands:
		if not is_revealed(st, h):
			continue
		rev.append(h)
		if h == from or neighbours(from).has(h):
			near.append(h)
	return near if not near.is_empty() else rev

## What the next completion will spread to, from the current state (shown on the map).
## Restoring or harvesting the zone you finish can still change it. `from` = the hex you would
## complete (only matters with the Atelier's spread_local; forecast_depends_on_hex says so).
static func forecast(st: Dictionary, from: Vector2i = Vector2i(9999, 9999)) -> Array:
	if st.is_empty():
		return []
	return spread(st.duplicate(true), from)

static func forecast_depends_on_hex(st: Dictionary) -> bool:
	return bool(atelier_fx(st)["spread_local"])

## A finished run: reveal (complete) then one Rot spread. {revealed: [keys], spread: [keys]}
static func complete_run(st: Dictionary, h: Vector2i) -> Dictionary:
	if not can_enter(st, h):
		return {"revealed": [], "spread": []}
	var rev := complete(st, h)
	return {"revealed": rev, "spread": spread(st, h)}

## Death in a zone: the hex gains death_rot (not on the safety ring or a Restored hex; the
## spread cap does not apply). Returns the hex's new Rot, or -1 when nothing changed.
static func add_death_rot(st: Dictionary, h: Vector2i) -> int:
	if not _rot_eligible(st, h):
		return -1
	var rc := rot_cfg()
	var fx := atelier_fx(st)
	var extra := int(fx["death_rot"]) + (int(fx["death_rot_on_rot"]) if rot_of(st, h) >= 1 else 0)
	var n := mini(int(rc.get("max", 5)), rot_of(st, h) + int(rc.get("death_rot", 1)) + extra)
	if n == rot_of(st, h):
		return -1
	st["rot"][key(h)] = n
	return n

## Cleanse: the hex drops to Rot 0 and becomes Restored (a permanent firebreak). With the Atelier's
## restore_neighbours, each neighbour also loses that much Rot. Returns the neighbour keys lowered.
static func restore(st: Dictionary, h: Vector2i) -> Array:
	st.get("rot", {}).erase(key(h))
	if not st["restored"].has(key(h)):
		st["restored"].append(key(h))
	var out := []
	var nr := int(atelier_fx(st)["restore_neighbours"])
	if nr > 0:
		for n in neighbours(h):
			var r := rot_of(st, n)
			if r <= 0:
				continue
			if r - nr <= 0:
				st["rot"].erase(key(n))
			else:
				st["rot"][key(n)] = r - nr
			out.append(key(n))
	return out

## Fester: the hex keeps its Rot and the next spread gets extra fronts.
static func fester(st: Dictionary, _h: Vector2i) -> void:
	st["fester"] = int(st.get("fester", 0)) + int(rot_cfg().get("harvest", {}).get("extra_front", 1))

## heart_at: the Rot level a Heart appears at (-1 = the data's; heart_at_for(st) adds the Atelier).
static func is_heart(rot: int, heart_at: int = -1) -> bool:
	return rot >= (heart_at if heart_at > 0 else int(rot_cfg().get("heart_at", 3)))

static func heart_at_for(st: Dictionary) -> int:
	return int(rot_cfg().get("heart_at", 3)) + int(atelier_fx(st)["heart_at"])

## Scales an Atlas zone def for Rot n (returns a copy). Keys read by dungeon.gd:
## rot, rot_density, rot_reward, heart, heart_mutations.
static func apply_rot(d: Dictionary, rot: int, seed_value: int, h: Vector2i, st: Dictionary = {}) -> Dictionary:
	var out := d.duplicate(true)
	var fx := atelier_fx(st)
	out["rot"] = rot
	var lv := rot_level(rot)
	if lv.is_empty():
		return out
	out["life_mult"] = float(out.get("life_mult", 1.0)) * float(lv.get("life_mult", 1.0))
	out["damage_mult"] = float(out.get("damage_mult", 1.0)) * float(lv.get("damage_mult", 1.0))
	out["rot_density"] = float(lv.get("density", 1.0))
	out["rot_reward"] = float(lv.get("reward", 0)) * rot_reward_mult(st)
	out["rot_heal"] = float(lv.get("heal", 1.0))             # Phase 1E: the Rot saps life recovery
	out["rot_attack_speed"] = float(lv.get("attack_speed", 1.0))
	out["rot_move_speed"] = float(lv.get("move_speed", 1.0))   # Phase D2: levers that reach kiting builds
	out["rot_proj_speed"] = float(lv.get("proj_speed", 1.0))
	var eb := int(lv.get("elite_mods", 0))
	if eb > 0:
		var em: Array = out.get("elite_mods", [1, 2])
		out["elite_mods"] = [int(em[0]) + eb, int(em[1]) + eb]
	if is_heart(rot, heart_at_for(st)):
		out["heart"] = true
		var ms := []
		for m in heart_mutations(seed_value, h, str(out.get("boss", "")), int(lv.get("mutations", 1))):
			ms.append(str(m.get("id", "")))
		out["heart_mutations"] = ms
		out["heart_life"] = float(fx["heart_life"])   # Atelier (Phase 3B): x the Heart's life
	return out

## The first n rot_mutations of a boss in this hex's seeded order (so Rot 4 keeps Rot 3's).
static func heart_mutations(seed_value: int, h: Vector2i, boss_id: String, n: int) -> Array:
	var all: Array = Data.enemies.get(boss_id, {}).get("rot_mutations", []).duplicate()
	var rng := _rng(seed_value, h, 400)
	for i in range(all.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = all[i]
		all[i] = all[j]
		all[j] = t
	return all.slice(0, clampi(n, 0, all.size()))

## A boss def turned into a Heart of Rot: mutations applied (add / tune / unlock patterns from
## a phase on), later phases start earlier, extra life, new name and light.
static func heart_def(bd: Dictionary, mutation_ids: Array) -> Dictionary:
	var hc: Dictionary = rot_cfg().get("heart", {})
	var d := bd.duplicate(true)
	var pats: Dictionary = d.get("patterns", {})
	var phases: Array = d.get("phases", [])
	var by_id := {}
	for m in bd.get("rot_mutations", []):
		by_id[str(m.get("id", ""))] = m
	var applied := []
	for mid in mutation_ids:
		var m: Dictionary = by_id.get(str(mid), {})
		if m.is_empty():
			continue
		applied.append(m)
		var from := int(m.get("phase", 0))
		var unlock: Array = m.get("unlock", []).duplicate()
		var add: Dictionary = m.get("add", {})
		for pid in add:
			pats[pid] = add[pid].duplicate(true)
			unlock.append(pid)
		var tune: Dictionary = m.get("tune", {})
		for pid in tune:
			if pats.has(pid):
				for f in tune[pid]:
					pats[pid][f] = tune[pid][f]
		for i in range(from, phases.size()):
			var pl: Array = phases[i].get("patterns", [])
			for pid in unlock:
				if pats.has(pid) and not pl.has(pid):
					pl.append(pid)
			phases[i]["patterns"] = pl
	var sh := float(hc.get("phase_shift", 0.06))
	for i in range(1, phases.size()):
		phases[i]["at"] = minf(0.95, float(phases[i].get("at", 0.5)) + sh)
	d["patterns"] = pats
	d["phases"] = phases
	d["life"] = float(d.get("life", 100)) * float(hc.get("life_mult", 1.0))
	d["name"] = "%s, %s" % [str(bd.get("name", "")), str(hc.get("suffix", "Heart of Rot"))]
	d["light"] = str(hc.get("light", d.get("light", "#9ad04a")))
	d["heart"] = true
	d["heart_applied"] = applied
	return d

# ------------------------------------------------------------------ zone mechanics (Phase 1D)
static func mech_cfg() -> Dictionary:
	return cfg().get("mechanics", {})

static func mechanic_info(id: String) -> Dictionary:
	for m in mech_cfg().get("list", []):
		if str(m.get("id", "")) == id:
			return m
	return {}

## The natural mechanic of the n-th run of a hex ("" = none): rolls natural_chance, then a weighted
## pick, from (seed, hex, clear count), so the Atlas panel can show the next run's mechanic.
## Atelier (Phase 3B): chance_add is added to natural_chance before chance_mult; force (a non-minor
## mechanic id) replaces the pick; roll > 0 is an extra roll on its own seed (Double Study).
static func natural_mechanic(seed_value: int, h: Vector2i, clears: int, chance_mult: float = 1.0, chance_add: float = 0.0, force: String = "", roll: int = 0) -> String:
	var mc := mech_cfg()
	var lst: Array = mc.get("list", [])
	if lst.is_empty() or ring_of(h) < 1:
		return ""
	var rng := _rng(seed_value, h, 300 + clears + roll * 5000)
	if rng.randf() >= (float(mc.get("natural_chance", 0.3)) + chance_add) * chance_mult:
		return ""
	if force.contains("|"):   # Phase 3C Study in Fire: "burning|wells" picks one, seeded on the same roll
		var opts := []
		for f in force.split("|", false):
			var fo := mechanic_info(f)
			if not fo.is_empty() and not fo.get("minor", false):
				opts.append(f)
		if not opts.is_empty():
			return str(opts[rng.randi_range(0, opts.size() - 1)])
	var fm := mechanic_info(force)
	if not fm.is_empty() and not fm.get("minor", false):
		return force
	var items := []
	for m in lst:
		if not m.get("minor", false):   # Phase 2D: minor mechanics roll on their own
			items.append({"id": str(m.get("id", "")), "w": float(m.get("weight", 1))})
	if items.is_empty():
		return ""
	return str(_weighted(rng, items).get("id", ""))

## Endgame Phase 2D: the minor mechanics (Collector's Wager, Pentimento Vaults) of the n-th run of
## a hex. Each rolls on its own at its `chance` (x chance_mult x mults[id]), seeded by (seed, hex,
## clear count). one_of (the Atelier's vault_or_collector): exactly one of them - if none hits, the
## one closest to hitting is added; if several hit, the most decisive hit (lowest roll / chance) stays.
static func minor_mechanics(seed_value: int, h: Vector2i, clears: int, chance_mult: float = 1.0, mults: Dictionary = {}, one_of: bool = false) -> Array:
	var out := []
	if ring_of(h) < 1:
		return out
	var i := 0
	var best := ""
	var best_q := INF
	for m in mech_cfg().get("list", []):
		if not m.get("minor", false):
			continue
		i += 1
		var id := str(m.get("id", ""))
		var rng := _rng(seed_value, h, 2000 * i + clears)
		var ch := float(m.get("chance", 0.2)) * chance_mult * float(mults.get(id, 1.0))
		var r := rng.randf()
		if r < ch:
			out.append(id)
		var q := r / maxf(ch, 0.0001)
		if q < best_q:
			best_q = q
			best = id
	if one_of and best != "":
		out = [best]
	return out

## How many status colours a sketch needs in a zone of this ring / Rot.
static func sketch_colours(ring: int, rot: int, u: Dictionary = {}) -> int:
	if u.is_empty():
		u = mech_cfg().get("unfinished", {})
	var n := int(u.get("colours", 1))
	if rot >= int(u.get("extra_colour_rot", 3)) or ring >= int(u.get("extra_colour_ring", 3)):
		n += 1
	return clampi(n, 1, mini(int(u.get("max_colours", 2)), u.get("palette", []).size()))

## Palette entry whose statuses include `status` ({} if none).
static func colour_for_status(status: String) -> Dictionary:
	for c in mech_cfg().get("unfinished", {}).get("palette", []):
		if c.get("statuses", []).has(status):
			return c
	return {}

## Glaze layer count for an elite with n modifiers.
static func glaze_layers(n: int) -> int:
	var g: Dictionary = mech_cfg().get("glazed", {})
	return clampi(maxi(n, int(g.get("min_layers", 2))), 1, int(g.get("max_layers", 4)))

# ------------------------------------------------------------------ The Atelier (Phase 3B): zone-rule effects
## The Atelier's taken nodes edit zone parameters only. atelier_fx(st) is the single source of
## zone-rule effects (it replaced the Phase 1E varnish_fx). Points, paths and respec live in
## atelier_rules.gd. Combine modes (data/atlas.json atelier.fx_doc): ints/floats add, _FX_MULT
## multiply, _FX_MIN / _FX_MAX keep the lowest / highest, bools are true if any node sets them,
## strings: the last node wins.
const _FX_NEUTRAL := {
	"fronts": 0, "heart_at": 0, "death_rot": 0, "death_rot_on_rot": 0, "rot_reward": 0.0, "reward": 0.0,
	"elite_mods": 0, "boss_elite_mods": 0, "boss_rares": 0, "last_chamber_packs": 0, "trap_elites": 0,
	"treasure_rares": 0, "riddle_mistakes": 0, "pigment_charges": 0, "pigment_reward": 0.0, "pigment_damage": 0.0,
	"pigment_slots": 0, "vendor_extra": 0, "glaze_layers": 0, "glaze_flakes": 0, "sketch_colours": 0,
	"natural_chance": 0.0, "natural_rolls": 0, "base_mods": 0, "shard_chance": 0.0, "warden_rares": 0,
	"summon_cost": 0, "warden_rot_shard": 0, "warden_points": 0, "heart_material_rolls": 0, "harvest_gems": 0,
	"restore_neighbours": 0,
	"density": 1.0, "elite_mult": 1.0, "damage_mult": 1.0, "life_mult": 1.0, "natural_mult": 1.0,
	"major_natural_mult": 1.0, "vault_mult": 1.0, "wager_mult": 1.0, "vault_wall_life": 1.0, "craft_cost_mult": 1.0,
	"glazed_cost_mult": 1.0, "unfinished_cost_mult": 1.0, "dust_mult": 1.0, "warden_life": 1.0, "heart_life": 1.0,
	"harvest_gold_mult": 1.0,
	"pigment_slots_max": 99, "ground_pity": 99, "shard_cap": 0, "wager_max_mult": 0, "restore_shard_chance": 0.0,
	"spread_local": false, "restore_no_slot": false, "elite_preview": false, "first_elite_rare": false,
	"vault_or_collector": false, "pigment_danger_roll": false, "death_no_charge": false, "umber_well": false,
	"last_light": false, "natural_force": ""}
const _FX_MULT := ["density", "elite_mult", "damage_mult", "life_mult", "natural_mult", "major_natural_mult", "vault_mult",
	"wager_mult", "vault_wall_life", "craft_cost_mult", "glazed_cost_mult", "unfinished_cost_mult", "dust_mult",
	"warden_life", "heart_life", "harvest_gold_mult"]
const _FX_MIN := ["pigment_slots_max", "ground_pity"]
const _FX_MAX := ["shard_cap", "wager_max_mult", "restore_shard_chance"]

static func atelier_cfg() -> Dictionary:
	return cfg().get("atelier", {})

## Every node of the board, in wedge order (each with its "wedge" id added).
static func atelier_nodes() -> Array:
	var out := []
	for w in atelier_cfg().get("wedges", []):
		for n in w.get("nodes", []):
			var c: Dictionary = n.duplicate()
			c["wedge"] = str(w.get("id", ""))
			out.append(c)
	return out

static func atelier_node(id: String) -> Dictionary:
	for n in atelier_nodes():
		if str(n.get("id", "")) == id:
			return n
	return {}

## A choice node's option ({} if none).
static func atelier_option(node: Dictionary, opt: String) -> Dictionary:
	for o in node.get("options", []):
		if str(o.get("id", "")) == opt:
			return o
	return {}

## Cleans a loaded atelier block: known ids, no 3C-gated nodes or options, choices only for taken
## choice nodes. Path and budget are checked by AtelierRules.fix.
static func _clean_atelier(raw) -> Dictionary:
	var out := {"taken": [], "choices": {}, "bonus": 0}
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	out["bonus"] = clampi(int(raw.get("bonus", 0)) if (raw.get("bonus", 0) is int or raw.get("bonus", 0) is float) else 0, 0, 99)   # dev-granted points
	var src_t = raw.get("taken", [])
	var src_c = raw.get("choices", {})
	if typeof(src_c) != TYPE_DICTIONARY:
		src_c = {}
	if typeof(src_t) == TYPE_ARRAY:
		for id in src_t:
			var n := atelier_node(str(id))
			if n.is_empty() or n.get("needs_3c", false) or out["taken"].has(str(id)):
				continue
			if str(n.get("kind", "")) == "choice":
				var o := atelier_option(n, str(src_c.get(str(id), "")))
				if o.is_empty() or o.get("needs_3c", false):
					continue
				out["choices"][str(id)] = str(o["id"])
			out["taken"].append(str(id))
	return out

## The effects of a list of node ids (choices: {choice node id: option id}). Ids that are unknown,
## 3C-gated or a choice without a valid pick are ignored.
static func fx_of(ids: Array, choices: Dictionary = {}) -> Dictionary:
	var fx := _FX_NEUTRAL.duplicate()
	for id in ids:
		var n := atelier_node(str(id))
		if n.is_empty() or n.get("needs_3c", false):
			continue
		var src: Dictionary = n.get("fx", {})
		if str(n.get("kind", "")) == "choice":
			var o := atelier_option(n, str(choices.get(str(id), "")))
			if o.is_empty() or o.get("needs_3c", false):
				continue
			src = o.get("fx", {})
		for k in src:
			if not fx.has(k):
				continue
			var v = src[k]
			if k in _FX_MULT:
				fx[k] = float(fx[k]) * float(v)
			elif k in _FX_MIN:
				fx[k] = mini(int(fx[k]), int(v))
			elif k in _FX_MAX:
				fx[k] = maxf(float(fx[k]), float(v)) if typeof(_FX_NEUTRAL[k]) == TYPE_FLOAT else maxi(int(fx[k]), int(v))
			elif typeof(_FX_NEUTRAL[k]) == TYPE_BOOL:
				fx[k] = bool(fx[k]) or bool(v)
			elif typeof(_FX_NEUTRAL[k]) == TYPE_STRING:
				fx[k] = str(v)
			elif typeof(_FX_NEUTRAL[k]) == TYPE_FLOAT:
				fx[k] = float(fx[k]) + float(v)
			else:
				fx[k] = int(fx[k]) + int(v)
	return fx

## Combined effect of the character's taken Atelier nodes (neutral values with none).
static func atelier_fx(st: Dictionary) -> Dictionary:
	var a: Dictionary = st.get("atelier", {}) if typeof(st.get("atelier", {})) == TYPE_DICTIONARY else {}
	return fx_of(a.get("taken", []), a.get("choices", {}))

## Connoisseur's Eye: the elite modifier ids the n-th run of h can roll (atelier.preview_pool of
## them, seeded by seed, hex and clear count). The zone's elites draw only from this pool.
static func elite_preview(seed_value: int, h: Vector2i, clears: int) -> Array:
	var ids := []
	for m in Data.elite_mod_list:
		ids.append(str(m["id"]))
	var rng := _rng(seed_value, h, 900 + clears)
	var out := []
	while out.size() < int(atelier_cfg().get("preview_pool", 4)) and not ids.is_empty():
		out.append(ids.pop_at(rng.randi_range(0, ids.size() - 1)))
	return out

## Multiplier on Rot rewards: 1 + the summed rot_reward percent (never below 0).
static func rot_reward_mult(st: Dictionary) -> float:
	return maxf(0.0, 1.0 + float(atelier_fx(st)["rot_reward"]) / 100.0)

# ------------------------------------------------------------------ Pigments (Phase 1E)
## Pigments are crafted at the Easel from their mechanic's material. Slotted ones (atlas.easel, in
## order) guarantee their mechanic in the zones they fit, add a seeded modifier and spend charges.
static func pig_cfg() -> Dictionary:
	return cfg().get("pigments", {})

static func pigment_info(id: String) -> Dictionary:
	for p in pig_cfg().get("list", []):
		if str(p.get("id", "")) == id:
			return p
	return {}

static func pigment_mod(mech: String, mod_id: String) -> Dictionary:
	for m in pig_cfg().get("mods", {}).get(mech, []):
		if str(m.get("id", "")) == mod_id:
			return m
	return {}

## "Thick Glazed Pigment (3 charges)".
static func pigment_label(p: Dictionary, with_charges: bool = true) -> String:
	var m := pigment_mod(str(p.get("id", "")), str(p.get("mod", "")))
	var t := "%s %s" % [str(m.get("name", "")), str(pigment_info(str(p.get("id", ""))).get("name", "Pigment"))]
	if with_charges:
		t += " (%d charge%s)" % [int(p.get("charges", 0)), "" if int(p.get("charges", 0)) == 1 else "s"]
	return t.strip_edges()

static func _clean_pigment(p) -> Dictionary:
	if typeof(p) != TYPE_DICTIONARY:
		return {}
	var id := str(p.get("id", ""))
	var mod := str(p.get("mod", ""))
	if pigment_info(id).is_empty() or pigment_mod(id, mod).is_empty():
		return {}
	var c := clampi(int(p.get("charges", 0)), 0, 20)
	if c <= 0:
		return {}
	return {"id": id, "mod": mod, "charges": c, "uid": maxi(0, int(p.get("uid", 0)))}

# ---- Pigments
static func pigment_count(st: Dictionary) -> int:
	return st.get("pigments", []).size() + st.get("easel", []).size()

## Pigment slots for a run of hex h: base, +1 in ring extra_slot_ring+ or a Restored region (not
## with the Atelier's restore_no_slot), + the Atelier's pigment_slots; at most pigment_slots_max
## (Binding Varnish) and max_slots.
static func pigment_slots(st: Dictionary, h: Vector2i) -> int:
	var pc := pig_cfg()
	var fx := atelier_fx(st)
	var n := int(pc.get("slots", 1))
	if ring_of(h) >= int(pc.get("extra_slot_ring", 3)) or (is_restored(st, h) and not fx["restore_no_slot"]):
		n += 1
	n += int(fx["pigment_slots"])
	return clampi(mini(n, int(fx["pigment_slots_max"])), 0, int(pc.get("max_slots", 3)))

## How many Pigments the Easel holds: easel_slots (2), + the Atelier's pigment_slots, at most max_slots.
static func easel_slots(st: Dictionary) -> int:
	var pc := pig_cfg()
	return clampi(int(pc.get("easel_slots", 2)) + int(atelier_fx(st)["pigment_slots"]), 1, int(pc.get("max_slots", 3)))

## Material cost of crafting Pigment `id` (Atelier: craft_cost_mult x glazed/unfinished_cost_mult).
## Phase 3C: a Pigment with a `materials` block (the Wells Pigment) costs several; this is their sum.
static func pigment_cost(st: Dictionary, id: String) -> int:
	var n := 0
	var c := pigment_costs(st, id)
	for k in c:
		n += int(c[k])
	return n

## Phase 3C: {material id: amount} to craft Pigment `id` (`material` + `cost`, or a `materials` block),
## each x the Atelier's craft_cost_mult x <id>_cost_mult, rounded, at least 1.
static func pigment_costs(st: Dictionary, id: String) -> Dictionary:
	var info := pigment_info(id)
	var fx := atelier_fx(st)
	var m := float(fx["craft_cost_mult"]) * float(fx.get(id + "_cost_mult", 1.0))
	var src: Dictionary = info.get("materials", {}) if typeof(info.get("materials", {})) == TYPE_DICTIONARY else {}
	if src.is_empty() and str(info.get("material", "")) != "":
		src = {str(info["material"]): info.get("cost", 1)}
	var out := {}
	for k in src:
		out[str(k)] = maxi(1, int(round(float(src[k]) * m)))
	return out

## Phase 3C: "120 Glaze Flake, 30 Pigment Dust, 20 Ash".
static func cost_text(cost: Dictionary) -> String:
	var parts := []
	for k in cost:
		parts.append("%d %s" % [int(cost[k]), str(Data.materials.get(k, {}).get("name", k))])
	return ", ".join(parts)

## Phase 3C: the materials the Easel shows (every Pigment's, in list order, no repeats).
static func pigment_materials() -> Array:
	var out := []
	for p in pig_cfg().get("list", []):
		var src: Dictionary = p.get("materials", {}) if typeof(p.get("materials", {})) == TYPE_DICTIONARY else {}
		var ids: Array = src.keys() if not src.is_empty() else [str(p.get("material", ""))]
		for k in ids:
			if str(k) != "" and not out.has(str(k)):
				out.append(str(k))
	return out

## Crafts a Pigment of mechanic `id` into the stock, paying its material from ch. The modifier is
## seeded by (atlas seed, craft count). {ok, msg, pigment}
static func craft_pigment(st: Dictionary, ch, id: String) -> Dictionary:
	var info := pigment_info(id)
	if info.is_empty() or ch == null:
		return {"ok": false, "msg": "Unknown Pigment"}
	var pc := pig_cfg()
	if pigment_count(st) >= int(pc.get("stock_cap", 12)):
		return {"ok": false, "msg": "The Easel holds at most %d Pigments" % int(pc.get("stock_cap", 12))}
	var cost := pigment_costs(st, id)
	if not ch.pay(cost):
		return {"ok": false, "msg": "Needs " + cost_text(cost)}
	return {"ok": true, "msg": "Crafted", "pigment": add_pigment(st, id)}

## Adds a Pigment (seeded modifier unless mod_id is given) to the stock without a cost (crafting, dev, bots).
static func add_pigment(st: Dictionary, id: String, mod_id: String = "") -> Dictionary:
	var mods: Array = pig_cfg().get("mods", {}).get(id, [])
	if pigment_info(id).is_empty() or mods.is_empty():
		return {}
	var uid := int(st.get("crafted", 0))
	var fx := atelier_fx(st)
	if pigment_mod(id, mod_id).is_empty():
		var rng := _rng(int(st.get("seed", 1)), Vector2i(uid, 7), 500)
		mod_id = str(mods[rng.randi_range(0, mods.size() - 1)].get("id", ""))
		if fx["pigment_danger_roll"]:   # Atelier: roll twice, keep the more dangerous (atelier.pigment_danger)
			var other := str(mods[rng.randi_range(0, mods.size() - 1)].get("id", ""))
			var order: Array = atelier_cfg().get("pigment_danger", {}).get(id, [])
			if order.find(other) > order.find(mod_id):
				mod_id = other
	var p := {"id": id, "mod": mod_id, "charges": int(pig_cfg().get("charges", 4)) + int(fx["pigment_charges"]), "uid": uid}
	st["crafted"] = uid + 1
	if not st.has("pigments"):
		st["pigments"] = []
	st["pigments"].append(p)
	return p

## Moves stock[i] onto the Easel (the end of the slot order). False when the Easel is full.
static func slot_pigment(st: Dictionary, i: int) -> bool:
	var stock: Array = st.get("pigments", [])
	if not st.has("easel"):
		st["easel"] = []
	if i < 0 or i >= stock.size() or st["easel"].size() >= easel_slots(st):
		return false
	st["easel"].append(stock.pop_at(i))
	return true

static func unslot_pigment(st: Dictionary, i: int) -> bool:
	var easel: Array = st.get("easel", [])
	if i < 0 or i >= easel.size():
		return false
	st["pigments"].append(easel.pop_at(i))
	return true

## Phase 3C: records the mechanics of a run as met (atlas.seen; the Guild's cistern / well contracts need them).
static func mark_seen(st: Dictionary, mechs: Array) -> void:
	if st.is_empty():
		return
	if typeof(st.get("seen")) != TYPE_ARRAY:
		st["seen"] = []
	for m in mechs:
		if not mechanic_info(str(m)).is_empty() and not st["seen"].has(str(m)):
			st["seen"].append(str(m))

static func has_seen(st: Dictionary, mech: String) -> bool:
	return typeof(st.get("seen")) == TYPE_ARRAY and st["seen"].has(mech)

## The slotted Pigments a run of hex h uses (the first pigment_slots of the Easel).
static func run_pigments(st: Dictionary, h: Vector2i) -> Array:
	return st.get("easel", []).slice(0, pigment_slots(st, h)).duplicate(true)

## Zone mechanics of the next run of h: the Pigments' mechanics (in slot order), then the natural roll
## if it is a different one.
static func run_mechanics(st: Dictionary, h: Vector2i, pigs: Array = []) -> Array:
	var out := []
	for p in pigs:
		if not out.has(str(p.get("id", ""))):
			out.append(str(p.get("id", "")))
	var nx := next_mechanics(st, h)
	for m in nx["natural"] + nx["minor"]:   # minor: Phase 2D
		if not out.has(m):
			out.append(m)
	return out

## The natural and minor mechanics the next run of h rolls (before Pigments), with the Atelier:
## {natural: [ids], minor: [ids]}. Without Atelier nodes this is exactly the Phase 2D roll.
static func next_mechanics(st: Dictionary, h: Vector2i) -> Dictionary:
	var fx := atelier_fx(st)
	var sd := int(st.get("seed", 1))
	var n := clears(st, h)
	var nm := float(fx["natural_mult"])
	var nat := []
	for roll in 1 + int(fx["natural_rolls"]):
		var m := natural_mechanic(sd, h, n, nm * float(fx["major_natural_mult"]), float(fx["natural_chance"]), str(fx["natural_force"]), roll)
		if m != "" and not nat.has(m):
			nat.append(m)
	var mults := {"vault": float(fx["vault_mult"]), "wager": float(fx["wager_mult"])}
	return {"natural": nat, "minor": minor_mechanics(sd, h, n, nm, mults, bool(fx["vault_or_collector"]))}

## {mechanic: [modifier ids]} for a list of Pigments (the same modifier twice stacks).
static func pigment_mods(pigs: Array) -> Dictionary:
	var out := {}
	for p in pigs:
		var id := str(p.get("id", ""))
		if not out.has(id):
			out[id] = []
		out[id].append(str(p.get("mod", "")))
	return out

## Spends n charges of the Easel Pigments with these uids; empty ones are used up. Returns the
## labels of the Pigments that ran out.
static func spend_pigments(st: Dictionary, uids: Array, n: int = 1) -> Array:
	var gone := []
	var keep := []
	for p in st.get("easel", []):
		if uids.has(int(p.get("uid", -1))):
			p["charges"] = int(p.get("charges", 0)) - n
			if int(p["charges"]) <= 0:
				gone.append(pigment_label(p, false))
				continue
		keep.append(p)
	st["easel"] = keep
	return gone

const _MECH_MULT := ["elite_chance_mult", "fill_fraction", "elite_damage", "sketch_damage",
	"speed_mult", "dot_mult", "ash_mult", "kill_fill_mult", "time_fill_mult", "fill_mult", "danger_mult"]   # Phase 3C

## The mechanic's tuning block with Pigment modifiers applied (multipliers for _MECH_MULT keys,
## otherwise added). Extra keys a modifier introduces start from 0 (or 1 for multipliers).
static func mech_tuning(mech: String, mod_ids: Array = []) -> Dictionary:
	var out: Dictionary = mech_cfg().get(mech, {}).duplicate(true)
	for mid in mod_ids:
		var m := pigment_mod(mech, str(mid))
		for k in m:
			if k in ["id", "name", "desc"]:
				continue
			if k in _MECH_MULT:
				out[k] = float(out.get(k, 1.0)) * float(m[k])
			else:
				out[k] = out.get(k, 0) + m[k]
	if out.has("filled_dust_chance"):
		out["filled_dust_chance"] = clampf(float(out["filled_dust_chance"]), 0.0, 1.0)
	if out.has("max_colours"):
		out["max_colours"] = mini(int(out["max_colours"]), out.get("palette", []).size())
	return out

# ------------------------------------------------------------------ Layer Wardens (Endgame Phase 2A)
## Each ring has a Warden (an upgraded existing boss). Clears in a ring drop Ground Shards of that
## layer; summon_cost shards summon the Warden at a cleared region of the ring, and the next run
## there fights it. Shards are spent only on victory. A Warden drops a Ground Pigment (always on
## the first kill, then ground_chance with pity). State keys (ring numbers as strings):
## shards, shard_dry, summons ({ring: hex key}), ground, ground_dry, warden_kills.
const _WARDEN_KEYS := ["shards", "shard_dry", "ground", "ground_dry", "warden_kills"]

static func ward_cfg() -> Dictionary:
	return cfg().get("wardens", {})

static func warden_cfg(ring: int) -> Dictionary:
	for w in ward_cfg().get("rings", []):
		if int(w.get("ring", 0)) == ring and Data.enemies.has(str(w.get("boss", ""))):
			return w
	return {}

static func warden_rings() -> Array:
	var out := []
	for w in ward_cfg().get("rings", []):
		if not warden_cfg(int(w.get("ring", 0))).is_empty():
			out.append(int(w["ring"]))
	return out

static func _wget(st: Dictionary, k: String, ring: int) -> int:
	return int(st.get(k, {}).get(str(ring), 0))

static func _wset(st: Dictionary, k: String, ring: int, n: int) -> void:
	if not st.has(k) or typeof(st[k]) != TYPE_DICTIONARY:
		st[k] = {}
	if n <= 0:
		st[k].erase(str(ring))
	else:
		st[k][str(ring)] = n

static func shards(st: Dictionary, ring: int) -> int:
	return _wget(st, "shards", ring)

## Shards a Warden summon needs (+ the Atelier's summon_cost when st is given).
static func summon_cost(st: Dictionary = {}) -> int:
	return int(ward_cfg().get("summon_cost", 3)) + (int(atelier_fx(st)["summon_cost"]) if not st.is_empty() else 0)

## Shards held per layer at most (the Atelier's shard_cap can raise it).
static func shard_cap(st: Dictionary = {}) -> int:
	var c := int(ward_cfg().get("shard_cap", 9))
	return maxi(c, int(atelier_fx(st)["shard_cap"])) if not st.is_empty() else c

## The highest shard cap any Atelier pick can give (loading never cuts shards below it).
static func shard_cap_max() -> int:
	var c := int(ward_cfg().get("shard_cap", 9))
	for n in atelier_nodes():
		c = maxi(c, int(n.get("fx", {}).get("shard_cap", 0)))
		for o in n.get("options", []):
			c = maxi(c, int(o.get("fx", {}).get("shard_cap", 0)))
	return c

## Adds n shards of a ring (capped; shards above the cap, e.g. after a respec, are kept). Returns
## how many were really added.
static func add_shards(st: Dictionary, ring: int, n: int = 1) -> int:
	if warden_cfg(ring).is_empty():
		return 0
	var have := shards(st, ring)
	var nv := maxi(0, mini(have + n, maxi(have, shard_cap(st))))
	_wset(st, "shards", ring, nv)
	return nv - have

## The shard roll after a normal (non-Warden) clear of hex h. Seeded by the atlas seed, hex and
## clear count (call after complete()). Chance + Rot bonus; a Heart always drops one; after
## shard_pity dry clears in that ring the next one is guaranteed. Returns shards gained (0/1).
static func roll_shard(st: Dictionary, h: Vector2i, rot: int = 0, heart: bool = false) -> int:
	var ring := ring_of(h)
	var wc := ward_cfg()
	if warden_cfg(ring).is_empty():
		return 0
	if shards(st, ring) >= shard_cap(st):
		return 0
	var chance := float(wc.get("shard_chance", 0.45)) + float(wc.get("shard_rot_bonus", 0.1)) * rot + float(atelier_fx(st)["shard_chance"])
	var hit := _rng(int(st.get("seed", 0)), h, 500 + clears(st, h)).randf() < chance
	if heart and wc.get("heart_shard", true):
		hit = true
	if _wget(st, "shard_dry", ring) >= int(wc.get("shard_pity", 2)):
		hit = true
	if not hit:
		_wset(st, "shard_dry", ring, _wget(st, "shard_dry", ring) + 1)
		return 0
	_wset(st, "shard_dry", ring, 0)
	return add_shards(st, ring, 1)

## Ring whose Warden is summoned at h (0 = none).
static func warden_at(st: Dictionary, h: Vector2i) -> int:
	var ring := ring_of(h)
	if str(st.get("summons", {}).get(str(ring), "")) == key(h) and not warden_cfg(ring).is_empty():
		return ring
	return 0

static func summoned_hex(st: Dictionary, ring: int) -> String:
	return str(st.get("summons", {}).get(str(ring), ""))

## Why h cannot take a Warden summon ("" = it can).
static func summon_refusal(st: Dictionary, h: Vector2i) -> String:
	var ring := ring_of(h)
	var wc := warden_cfg(ring)
	if wc.is_empty():
		return "No Warden guards this layer yet"
	if not can_enter(st, h) or clears(st, h) <= 0:
		return "Clear this region first"
	if warden_at(st, h) > 0:
		return "The Warden is already summoned here"
	if shards(st, ring) < summon_cost(st):
		return "Needs %d %ss (you have %d)" % [summon_cost(st), str(wc.get("shard", "Shard")), shards(st, ring)]
	return ""

## Summons (or moves) the ring's Warden to cleared hex h. Shards are not spent yet.
static func summon(st: Dictionary, h: Vector2i) -> bool:
	if summon_refusal(st, h) != "":
		return false
	if not st.has("summons") or typeof(st["summons"]) != TYPE_DICTIONARY:
		st["summons"] = {}
	st["summons"][str(ring_of(h))] = key(h)
	return true

static func unsummon(st: Dictionary, ring: int) -> void:
	if st.has("summons"):
		st["summons"].erase(str(ring))

## An Atlas zone def turned into a Warden run (copy): the ring's Warden boss, no Heart.
static func apply_warden(d: Dictionary, ring: int) -> Dictionary:
	var wc := warden_cfg(ring)
	if wc.is_empty():
		return d
	var out := d.duplicate(true)
	out["warden"] = ring
	out["boss"] = str(wc["boss"])
	out["heart"] = false
	out.erase("heart_mutations")
	out["name"] = "%s - %s" % [str(d.get("name", "")), str(wc.get("title", "Warden")).capitalize()]
	return out

## A boss def turned into the ring's Layer Warden: new patterns (added from a phase on), tuning,
## a final phase, more life and damage, new name and light.
static func warden_def(bd: Dictionary, ring: int) -> Dictionary:
	var wc := warden_cfg(ring)
	if wc.is_empty():
		return bd
	var d := bd.duplicate(true)
	var pats: Dictionary = d.get("patterns", {})
	var phases: Array = d.get("phases", [])
	var add: Dictionary = wc.get("add", {})
	for pid in add:
		pats[pid] = add[pid].duplicate(true)
	var tune: Dictionary = wc.get("tune", {})
	for pid in tune:
		if pats.has(pid):
			for f in tune[pid]:
				pats[pid][f] = tune[pid][f]
	var fp: Dictionary = wc.get("final_phase", {})
	if not fp.is_empty() and not phases.is_empty():
		var last: Dictionary = phases[phases.size() - 1]
		var np := {"at": minf(float(fp.get("at", 0.3)), float(last.get("at", 1.0)) - 0.05), "patterns": last.get("patterns", []).duplicate()}
		for pid in fp.get("add", []):
			if pats.has(pid) and not np["patterns"].has(pid):
				np["patterns"].append(pid)
		for k in ["speed", "attack_speed", "tint", "message"]:
			if fp.has(k):
				np[k] = fp[k]
			elif last.has(k) and k in ["speed", "attack_speed"]:
				np[k] = last[k]
		phases.append(np)
	for u in wc.get("unlock", []):
		var pid := str(u[0]) if typeof(u) == TYPE_ARRAY else str(u)
		var from := int(u[1]) if typeof(u) == TYPE_ARRAY and u.size() > 1 else 0
		for i in range(clampi(from, 0, phases.size()), phases.size()):
			var pl: Array = phases[i].get("patterns", [])
			if pats.has(pid) and not pl.has(pid):
				pl.append(pid)
			phases[i]["patterns"] = pl
	d["patterns"] = pats
	d["phases"] = phases
	d["life"] = float(d.get("life", 100)) * float(wc.get("life_mult", 1.0))
	var dm := float(wc.get("damage_mult", 1.0))
	var dmg: Array = d.get("damage", [1, 1])
	d["damage"] = [int(round(float(dmg[0]) * dm)), int(round(float(dmg[1]) * dm))]
	var base_name := str(bd.get("name", "")).split(",")[0]
	d["name"] = "%s, %s" % [base_name, str(wc.get("title", "the Warden"))]
	d["light"] = str(wc.get("light", d.get("light", "#ffe070")))
	d["warden"] = ring
	return d

## A Warden victory: spends the summon's shards, clears the summon, counts the kill and rolls the
## Ground Pigment (first kill always; then ground_chance; guaranteed after ground_pity dry kills).
## rot = the hex's Rot (the Atelier's warden_rot_shard gives shards back at Rot 3+).
## Returns {ground: bool, first: bool, kills: n, rot_shards: n}.
static func warden_victory(st: Dictionary, ring: int, rot: int = 0) -> Dictionary:
	var wc := ward_cfg()
	if warden_cfg(ring).is_empty():
		return {"ground": false, "first": false, "kills": 0, "rot_shards": 0}
	var fx := atelier_fx(st)
	_wset(st, "shards", ring, shards(st, ring) - summon_cost(st))
	unsummon(st, ring)
	var kills := _wget(st, "warden_kills", ring) + 1
	_wset(st, "warden_kills", ring, kills)
	var got := kills == 1
	if not got:
		got = _rng(int(st.get("seed", 0)), Vector2i(ring, 0), 600 + kills).randf() < float(wc.get("ground_chance", 0.34))
	if _wget(st, "ground_dry", ring) >= mini(int(wc.get("ground_pity", 3)), int(fx["ground_pity"])):
		got = true
	if got:
		_wset(st, "ground", ring, _wget(st, "ground", ring) + 1)
		_wset(st, "ground_dry", ring, 0)
	else:
		_wset(st, "ground_dry", ring, _wget(st, "ground_dry", ring) + 1)
	var rs := 0
	if rot >= 3 and int(fx["warden_rot_shard"]) > 0:
		rs = add_shards(st, ring, int(fx["warden_rot_shard"]))
	return {"ground": got, "first": kills == 1, "kills": kills, "rot_shards": rs}

static func warden_kills(st: Dictionary, ring: int) -> int:
	return _wget(st, "warden_kills", ring)

static func ground_count(st: Dictionary, ring: int) -> int:
	return _wget(st, "ground", ring)

## Distinct Ground Pigment layers owned (the pinnacle needs pinnacle_need of layers_total).
static func ground_kinds(st: Dictionary) -> int:
	var n := 0
	for k in st.get("ground", {}):
		if int(st["ground"][k]) > 0:
			n += 1
	return n

static func pinnacle_ready(st: Dictionary) -> bool:
	return ground_kinds(st) >= int(ward_cfg().get("pinnacle_need", 4))

## Cleans the Warden keys of a loaded state into st (Phase 2A; older saves have none).
static func _sanitize_wardens(st: Dictionary, raw: Dictionary) -> void:
	var rings := warden_rings()
	for k in _WARDEN_KEYS:
		st[k] = {}
		var src = raw.get(k, {})
		if typeof(src) != TYPE_DICTIONARY:
			continue
		for rk in src:
			var r := int(str(rk))
			var n := int(src[rk])
			if rings.has(r) and n > 0:
				st[k][str(r)] = mini(n, shard_cap_max() if k == "shards" else 9999)
	st["summons"] = {}
	var ss = raw.get("summons", {})
	if typeof(ss) == TYPE_DICTIONARY:
		for rk in ss:
			var h := parse(str(ss[rk]))
			if rings.has(int(str(rk))) and ring_of(h) == int(str(rk)) and in_atlas(h) and clears(st, h) > 0:
				st["summons"][str(int(str(rk)))] = key(h)
