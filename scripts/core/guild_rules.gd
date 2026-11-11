extends RefCounted
## Endgame Phase 2C: the Commission Board and the Restorers' Guild (docs/ENDGAME_PHASE2.md,
## data/atlas.json "guild"). Pure rules; the only side effects are on the state dictionary and,
## for caches / the Pigment vendor, on the character passed in.
## State: atlas["guild"] (per character, like the rest of the Atlas):
##   {"rep": int, "seals": int, "board": [contract], "draws": int, "zones": int, "rerolls": int,
##    "bought": int, "caches": int, "done": int}
##   contract = {"tpl": id, "need": int, "have": int, "rep": int, "seals": int, "done": bool}
## Contracts progress only from completed Atlas zones (the run report built when the zone boss
## dies) and from the Heart choice made after it. Completed contracts pay at once (reputation +
## Seals) and their slot shows "done" until the board refreshes (every `refresh_every` zones).

const AtlasRules = preload("res://scripts/core/atlas_rules.gd")

const STATS := ["zones", "hearts", "restore", "harvest", "peels", "painted", "elites", "pigment_zones", "wardens",
	"kills", "bosses", "wagers_won", "wager_3x", "vaults", "trap_vaults", "riddle_vaults"]   # Phase 2D adds the second row

static func cfg() -> Dictionary:
	return Data.atlas_cfg.get("guild", {})

# ------------------------------------------------------------------ state
static func new_guild() -> Dictionary:
	return {"rep": 0, "seals": 0, "board": [], "draws": 0, "zones": 0, "rerolls": 0, "bought": 0, "caches": 0, "done": 0}

## The Guild state of an Atlas state, created (and its board filled) on first use.
static func ensure(st: Dictionary) -> Dictionary:
	if st.is_empty():
		return {}
	if typeof(st.get("guild")) != TYPE_DICTIONARY or st["guild"].is_empty():
		st["guild"] = new_guild()
	var g: Dictionary = st["guild"]
	fill_board(st)
	return g

## Cleans a loaded Guild block. Unknown templates and bad numbers are dropped.
static func sanitize(raw) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY or raw.is_empty():
		return {}
	var g := new_guild()
	for k in ["rep", "seals", "draws", "zones", "rerolls", "bought", "caches", "done"]:
		var v = raw.get(k, 0)
		g[k] = maxi(0, int(v)) if (v is int or v is float) else 0
	g["seals"] = mini(int(g["seals"]), int(cfg().get("seal_cap", 99)))
	var b = raw.get("board", [])
	if typeof(b) == TYPE_ARRAY:
		for c in b:
			if typeof(c) != TYPE_DICTIONARY or template(str(c.get("tpl", ""))).is_empty():
				continue
			if g["board"].size() >= int(cfg().get("max_slots", 4)):
				break
			var need := maxi(1, int(c.get("need", 1)))
			g["board"].append({"tpl": str(c["tpl"]), "need": need, "have": clampi(int(c.get("have", 0)), 0, need),
				"rep": maxi(0, int(c.get("rep", 0))), "seals": maxi(0, int(c.get("seals", 0))), "done": bool(c.get("done", false))})
	return g

# ------------------------------------------------------------------ ranks
static func ranks() -> Array:
	return cfg().get("ranks", [])

## 1-based rank for a reputation total.
static func rank_for(rep: int) -> int:
	var r := 1
	for i in ranks().size():
		if rep >= int(ranks()[i].get("rep", 0)):
			r = i + 1
	return r

static func rank(st: Dictionary) -> int:
	if st.is_empty() or typeof(st.get("guild")) != TYPE_DICTIONARY:
		return 1 if not st.is_empty() else 0
	return rank_for(int(st["guild"].get("rep", 0)))

static func rank_info(r: int) -> Dictionary:
	if r < 1 or r > ranks().size():
		return {}
	return ranks()[r - 1]

## Reputation needed for the next rank (-1 at the top rank).
static func next_rep(st: Dictionary) -> int:
	var r := rank(st)
	if r >= ranks().size():
		return -1
	return int(ranks()[r].get("rep", 0))

## The rank that unlocks a feature ("board", "vendor", "fixative", "slot4", "cache4").
static func unlock_rank(feature: String) -> int:
	for i in ranks().size():
		if ranks()[i].get("unlocks", []).has(feature):
			return i + 1
	return 99

static func has_unlock(st: Dictionary, feature: String) -> bool:
	return rank(st) >= unlock_rank(feature)

static func rank_name(r: int) -> String:
	return str(rank_info(r).get("name", "Rank %d" % r))

## Fixative gate (Phase 2B decision): "" when allowed, otherwise the reason. ch may be null
## (tests and tools without a character: allowed, so pure item checks stay unchanged).
static func fixative_refusal(ch) -> String:
	if ch == null:
		return ""
	var need := unlock_rank("fixative")
	var st: Dictionary = ch.atlas if typeof(ch.atlas) == TYPE_DICTIONARY else {}
	if st.is_empty() or rank(st) < need:
		return "Fixative needs %s rank %d (%s)" % [str(cfg().get("name", "Restorers' Guild")), need, rank_name(need)]
	return ""

# ------------------------------------------------------------------ board
static func slot_count(st: Dictionary) -> int:
	var n := int(cfg().get("slots", 3))
	if has_unlock(st, "slot4"):
		n += 1
	return mini(n, int(cfg().get("max_slots", 4)))

static func templates() -> Array:
	return cfg().get("contracts", [])

static func template(id: String) -> Dictionary:
	for t in templates():
		if str(t.get("id", "")) == id:
			return t
	return {}

## True when the template can be offered on this atlas now (its "req" block).
static func eligible(st: Dictionary, t: Dictionary) -> bool:
	var req: Dictionary = t.get("req", {})
	if req.has("rank") and rank(st) < int(req["rank"]):
		return false
	if req.has("ring"):
		var ok := false
		for k in st.get("revealed", []):
			if AtlasRules.ring_of(AtlasRules.parse(str(k))) >= int(req["ring"]):
				ok = true
				break
		if not ok:
			return false
	if req.has("rot"):
		var best := 0
		var rd: Dictionary = st.get("rot", {})
		for k in rd:
			if st.get("revealed", []).has(k):
				best = maxi(best, int(rd[k]))
		if best < int(req["rot"]):
			return false
	if req.get("wardens", false):
		var any := false
		for ring in AtlasRules.warden_rings():
			if AtlasRules.shards(st, int(ring)) > 0 or AtlasRules.warden_kills(st, int(ring)) > 0:
				any = true
		if not any:
			return false
	if req.has("clears"):
		var n := 0
		for k in st.get("clears", {}):
			n += int(st["clears"][k])
		if n < int(req["clears"]):
			return false
	return true

## Draws one contract, seeded by (atlas seed, draw count); avoids templates already on the board.
static func draw(st: Dictionary, g: Dictionary) -> Dictionary:
	var on := []
	for c in g.get("board", []):
		if not c.get("done", false):
			on.append(str(c["tpl"]))
	var pool := []
	var total := 0.0
	for t in templates():
		if eligible(st, t) and not on.has(str(t.get("id", ""))):
			pool.append(t)
			total += float(t.get("w", 1))
	if pool.is_empty():
		for t in templates():
			if eligible(st, t):
				pool.append(t)
				total += float(t.get("w", 1))
	if pool.is_empty():
		return {}
	var rng := AtlasRules._rng(int(st.get("seed", 1)), Vector2i(int(g.get("draws", 0)), 11), 700)
	g["draws"] = int(g.get("draws", 0)) + 1
	var roll := rng.randf() * total
	var t: Dictionary = pool[pool.size() - 1]
	for p in pool:
		roll -= float(p.get("w", 1))
		if roll <= 0.0:
			t = p
			break
	var nr: Array = t.get("need", [1, 1])
	var need := rng.randi_range(int(nr[0]), int(nr[nr.size() - 1]))
	return {"tpl": str(t["id"]), "need": need, "have": 0,
		"rep": int(round(float(t.get("rep", 1)) * need + float(t.get("rep_base", 0)))),
		"seals": maxi(1, int(round(float(t.get("seals", 0.3)) * need + float(t.get("seals_base", 0))))),
		"done": false}

## Fills empty slots up to slot_count. Done contracts stay until the next refresh.
static func fill_board(st: Dictionary) -> void:
	var g: Dictionary = st["guild"]
	if typeof(g.get("board")) != TYPE_ARRAY:
		g["board"] = []
	while g["board"].size() < slot_count(st):
		var c := draw(st, g)
		if c.is_empty():
			break
		g["board"].append(c)

## Refresh: done contracts are replaced, the free reroll and the vendor limit reset.
static func refresh(st: Dictionary) -> void:
	var g: Dictionary = st["guild"]
	var b: Array = g["board"]
	for i in b.size():
		if b[i].get("done", false):
			var c := draw(st, g)
			if not c.is_empty():
				b[i] = c
	g["zones"] = 0
	g["rerolls"] = 0
	g["bought"] = 0
	fill_board(st)

static func rerolls_left(st: Dictionary) -> int:
	return maxi(0, int(cfg().get("rerolls", 1)) - int(ensure(st).get("rerolls", 0)))

## Free reroll of an unfinished contract (once per refresh). "" or the reason it was refused.
static func reroll(st: Dictionary, i: int) -> String:
	var g := ensure(st)
	var b: Array = g["board"]
	if i < 0 or i >= b.size():
		return "No such contract"
	if b[i].get("done", false):
		return "That contract is already complete"
	if rerolls_left(st) <= 0:
		return "No free reroll left until the board refreshes"
	var c := draw(st, g)
	if c.is_empty():
		return "No other contract is available"
	b[i] = c
	g["rerolls"] = int(g.get("rerolls", 0)) + 1
	return ""

static func zones_to_refresh(st: Dictionary) -> int:
	return maxi(0, int(cfg().get("refresh_every", 5)) - int(ensure(st).get("zones", 0)))

## How much a run report advances contract c.
static func progress_of(c: Dictionary, report: Dictionary) -> int:
	var t := template(str(c.get("tpl", "")))
	if t.is_empty():
		return 0
	if int(report.get("ring", 0)) < int(t.get("min_ring", 0)):
		return 0
	if int(report.get("rot", 0)) < int(t.get("min_rot", 0)):
		return 0
	# Phase 2D filters: zone time, boss fight time, Pigments slotted
	if t.has("max_time") and (not report.has("time") or float(report["time"]) > float(t["max_time"])):
		return 0
	if t.has("max_boss_time"):
		# Phase 3B Last Light: boss_times holds one fight time per Lantern-bearer; each fast one counts
		if typeof(report.get("boss_times")) == TYPE_ARRAY and str(t.get("stat", "")) == "bosses":
			var fast := 0
			for bt in report["boss_times"]:
				if float(bt) <= float(t["max_boss_time"]):
					fast += 1
			return fast
		if not report.has("boss_time") or float(report["boss_time"]) > float(t["max_boss_time"]):
			return 0
	if int(report.get("pigments", 0)) < int(t.get("min_pigments", 0)):
		return 0
	return maxi(0, int(report.get(str(t.get("stat", "zones")), 0)))

## Phase 2D: a death in an Atlas zone breaks every unfinished "in a row" (streak) contract.
## Returns how many contracts lost progress.
static func on_death(st: Dictionary) -> int:
	if st.is_empty() or typeof(st.get("guild")) != TYPE_DICTIONARY:
		return 0
	var n := 0
	for c in st["guild"].get("board", []):
		if c.get("done", false) or not template(str(c.get("tpl", ""))).get("streak", false):
			continue
		if int(c.get("have", 0)) > 0:
			n += 1
		c["have"] = 0
	return n

## Credits a run report: {zones, ring, rot, hearts, restore, harvest, peels, painted, elites,
## pigment_zones, wardens; Phase 2D: kills, bosses, wagers_won, wager_3x, vaults, trap_vaults,
## riddle_vaults, time (s in the zone), boss_time (s from the boss waking to its death), pigments;
## Phase 3B: boss_times [s] per Last Light Lantern-bearer}. Returns {completed: [labels], rep, seals, rank_up (new rank or 0), refreshed}.
static func credit(st: Dictionary, report: Dictionary) -> Dictionary:
	var out := {"completed": [], "rep": 0, "seals": 0, "rank_up": 0, "refreshed": false}
	if st.is_empty():
		return out
	var g := ensure(st)
	var r0 := rank(st)
	for c in g["board"]:
		if c.get("done", false):
			continue
		var n := progress_of(c, report)
		if n <= 0:
			continue
		c["have"] = mini(int(c["need"]), int(c.get("have", 0)) + n)
		if int(c["have"]) >= int(c["need"]):
			c["done"] = true
			g["rep"] = int(g["rep"]) + int(c["rep"])
			g["seals"] = mini(int(cfg().get("seal_cap", 99)), int(g["seals"]) + int(c["seals"]))
			g["done"] = int(g.get("done", 0)) + 1
			out["rep"] += int(c["rep"])
			out["seals"] += int(c["seals"])
			out["completed"].append(label(c))
	var r1 := rank(st)
	if r1 > r0:
		out["rank_up"] = r1
		fill_board(st)   # rank 4 adds a slot
	if int(report.get("zones", 0)) > 0:
		g["zones"] = int(g.get("zones", 0)) + int(report["zones"])
		if int(g["zones"]) >= int(cfg().get("refresh_every", 5)):
			refresh(st)
			out["refreshed"] = true
	return out

static func label(c: Dictionary) -> String:
	var t := template(str(c.get("tpl", "")))
	var n := int(c.get("need", 1))
	var s := str(t.get("text", "%d")).replace("%d", str(n))
	if n == 1:
		for pl in [[" zones", " zone"], [" Hearts", " Heart"], [" layers", " layer"], [" sketches", " sketch"], [" elites", " elite"],
				[" Wagers", " Wager"], [" Vaults", " Vault"], [" bosses", " boss"], [" monsters", " monster"]]:
			s = s.replace(pl[0], pl[1])
	return s

static func adds_rep(st: Dictionary, n: int) -> int:
	var g := ensure(st)
	var r0 := rank(st)
	g["rep"] = maxi(0, int(g["rep"]) + n)
	fill_board(st)
	return rank(st) if rank(st) != r0 else 0

# ------------------------------------------------------------------ Seal caches
static func cache_cost() -> int:
	return maxi(1, int(cfg().get("cache_cost", 10)))

static func cache_kinds() -> Array:
	return cfg().get("caches", [])

static func cache_info(id: String) -> Dictionary:
	for k in cache_kinds():
		if str(k.get("id", "")) == id:
			return k
	return {}

static func offer_count(st: Dictionary) -> int:
	return int(cfg().get("cache_offer", 3)) + (1 if has_unlock(st, "cache4") else 0)

## The caches on offer now (distinct ids), seeded by (atlas seed, caches opened).
static func cache_offers(st: Dictionary) -> Array:
	var g := ensure(st)
	var rng := AtlasRules._rng(int(st.get("seed", 1)), Vector2i(int(g.get("caches", 0)), 13), 710)
	var pool := cache_kinds().duplicate()
	var out := []
	while out.size() < offer_count(st) and not pool.is_empty():
		var total := 0.0
		for k in pool:
			total += float(k.get("w", 1))
		var roll := rng.randf() * total
		var pick: int = pool.size() - 1
		for i in pool.size():
			roll -= float(pool[i].get("w", 1))
			if roll <= 0.0:
				pick = i
				break
		out.append(str(pool[pick]["id"]))
		pool.remove_at(pick)
	return out

## Item level of Guild rewards: the deepest revealed ring's monster level + 1.
static func reward_level(st: Dictionary) -> int:
	var best := 1
	for k in st.get("revealed", []):
		best = maxi(best, AtlasRules.ring_of(AtlasRules.parse(str(k))))
	return int(AtlasRules.ring_cfg(best).get("level", 40)) + 1

## Picks a base of one of `slots` usable by the class, near the level (Loot's own rng).
static func _base_for(slots: Array, ilvl: int, class_id: String) -> String:
	var pool := []
	var near := []
	for b in Data.item_base_list:
		if not slots.has(str(b.get("slot", ""))) or int(b.get("req_level", 1)) > ilvl + 1:
			continue
		if class_id != "" and not Loot.base_usable_by(b, class_id):
			continue
		pool.append(b["id"])
		if int(b.get("req_level", 1)) >= ilvl - 18 or str(b.get("slot", "")) in ["ring", "amulet", "belt", "charm"]:
			near.append(b["id"])
	if not near.is_empty():
		pool = near
	if pool.is_empty():
		return ""
	return str(pool[Loot.rng.randi() % pool.size()])

## Opens a cache of kind id (must be on offer): pays the Seals and gives the contents to ch.
## {ok, msg, items: [item dicts], text: [lines]}
static func open_cache(st: Dictionary, ch, id: String) -> Dictionary:
	var g := ensure(st)
	var info := cache_info(id)
	if info.is_empty() or not cache_offers(st).has(id):
		return {"ok": false, "msg": "That cache is not on offer"}
	if int(g["seals"]) < cache_cost():
		return {"ok": false, "msg": "Needs %d Seals" % cache_cost()}
	var n_items := int(info.get("items", 0))
	if n_items > 0 and ch.bag_free_count() < n_items:
		return {"ok": false, "msg": "Make room: %d free bag slots needed" % n_items}
	g["seals"] = int(g["seals"]) - cache_cost()
	g["caches"] = int(g.get("caches", 0)) + 1
	var lv := reward_level(st)
	var items := []
	var text := []
	var slots: Array = info.get("slots", [])
	for i in n_items:
		var bonus := float(info.get("rarity", 300)) if i == n_items - 1 else 0.0
		var rar := Loot.roll_rarity(bonus) if bonus > 0.0 else "rare"
		if Data.rarity_index(rar) < Data.rarity_index("rare"):
			rar = "rare"
		var it: Dictionary = {}
		if rar == "legendary":
			var u: Dictionary = Loot.roll_unique(lv, ch.class_id)
			if not u.is_empty() and slots.has(str(u.get("slot", ""))):
				it = u
			else:
				rar = "epic"
		if it.is_empty():
			var bid := _base_for(slots, lv, ch.class_id)
			if bid == "":
				continue
			it = Loot.roll_item_of(bid, rar, lv)
		if ch.add_to_bag(it):
			items.append(it)
			text.append(str(it.get("name", "item")))
	var mats: Dictionary = info.get("materials", {})
	for m in mats:
		ch.add_material(str(m), int(mats[m]))
		text.append("%d %s" % [int(mats[m]), str(Data.materials.get(m, {}).get("name", m))])
	for i in int(info.get("random_materials", 0)):
		var mid: String = Loot._roll_material()
		ch.add_material(mid, 1)
		text.append("1 %s" % str(Data.materials.get(mid, {}).get("name", mid)))
	for i in int(info.get("gems", 0)):
		var gid: String = Loot.random_gem(lv)
		if gid != "":
			ch.add_gem(gid, 1)
			text.append(Loot.gem_name(gid))
	var gold := int(info.get("gold_per_level", 0)) * lv
	if gold > 0:
		ch.gold += gold
		text.append("%d gold" % gold)
	Events.currency_changed.emit()
	return {"ok": true, "msg": "Opened the %s" % str(info.get("name", id)), "items": items, "text": text}

# ------------------------------------------------------------------ Pigment vendor (rank 2)
static func vendor_list() -> Array:
	return cfg().get("vendor", {}).get("list", [])

static func vendor_left(st: Dictionary) -> int:
	var per := int(cfg().get("vendor", {}).get("per_refresh", 2)) + int(AtlasRules.atelier_fx(st)["vendor_extra"])   # Atelier Guild Supplier
	return maxi(0, per - int(ensure(st).get("bought", 0)))

static func vendor_price(id: String) -> int:
	for v in vendor_list():
		if str(v.get("id", "")) == id:
			return int(v.get("gold", 1000))
	return -1

## "" when the purchase is allowed.
static func buy_refusal(st: Dictionary, ch, id: String) -> String:
	if not has_unlock(st, "vendor"):
		return "Needs Guild rank %d" % unlock_rank("vendor")
	var price := vendor_price(id)
	if price < 0:
		return "Not sold here"
	if vendor_left(st) <= 0:
		return "Sold out until the board refreshes"
	if AtlasRules.pigment_count(st) >= int(AtlasRules.pig_cfg().get("stock_cap", 12)):
		return "The Easel is full"
	if ch == null or int(ch.gold) < price:
		return "Needs %d gold" % price
	return ""

## {ok, msg, pigment}
static func buy_pigment(st: Dictionary, ch, id: String) -> Dictionary:
	var why := buy_refusal(st, ch, id)
	if why != "":
		return {"ok": false, "msg": why}
	ch.gold -= vendor_price(id)
	ensure(st)["bought"] = int(st["guild"].get("bought", 0)) + 1
	Events.currency_changed.emit()
	return {"ok": true, "msg": "Bought", "pigment": AtlasRules.add_pigment(st, id)}
