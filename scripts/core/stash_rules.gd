extends RefCounted
## Pure stash rules (no scene or autoload access, so they are easy to test).
## Both stashes are a flat slot array. Tab N is slots N*per_tab .. N*per_tab+per_tab-1,
## so buying a tab only appends empty slots and never moves an existing item.
## `cfg` is data/stash.json.

static func slots_per_tab(cfg: Dictionary) -> int:
	return maxi(1, int(cfg.get("columns", 8)) * int(cfg.get("rows", 7)))

static func columns(cfg: Dictionary) -> int:
	return maxi(1, int(cfg.get("columns", 8)))

static func free_tabs(cfg: Dictionary, shared: bool) -> int:
	return maxi(1, int(cfg.get("shared_free_tabs" if shared else "stash_free_tabs", 1)))

static func max_extra(cfg: Dictionary) -> int:
	return maxi(0, int(cfg.get("max_extra_tabs", 10)))

static func clamp_extra(cfg: Dictionary, n: int) -> int:
	return clampi(n, 0, max_extra(cfg))

static func tab_total(cfg: Dictionary, extra_bought: int, shared: bool) -> int:
	return free_tabs(cfg, shared) + extra_bought

static func total_slots(cfg: Dictionary, extra_bought: int, shared: bool) -> int:
	return tab_total(cfg, extra_bought, shared) * slots_per_tab(cfg)

## Gold price of the next extra tab when `extra_bought` have been bought already.
## base_cost * growth^extra_bought (100, 200, 400, ... with the default config).
static func tab_cost(cfg: Dictionary, extra_bought: int) -> int:
	return int(round(float(cfg.get("base_cost", 100)) * pow(float(cfg.get("growth", 2.0)), float(extra_bought))))

## Total gold for buying `n` extra tabs from scratch.
static func total_cost(cfg: Dictionary, n: int) -> int:
	var t := 0
	for i in n:
		t += tab_cost(cfg, i)
	return t

## "" = the purchase is allowed, otherwise the reason it is refused.
static func buy_refusal(cfg: Dictionary, extra_bought: int, gold: int) -> String:
	if extra_bought >= max_extra(cfg):
		return "Maximum tabs reached"
	if gold < tab_cost(cfg, extra_bought):
		return "Not enough gold"
	return ""

## Grows a flat slot array so it holds `tabs` tabs. Never shrinks, never moves items.
static func ensure_slots(cfg: Dictionary, slots: Array, tabs: int) -> void:
	var want := tabs * slots_per_tab(cfg)
	while slots.size() < want:
		slots.append(null)

## [from, to) index range of one tab inside the flat array.
static func tab_range(cfg: Dictionary, tab: int) -> Vector2i:
	var n := slots_per_tab(cfg)
	return Vector2i(tab * n, tab * n + n)

## Index of the first empty slot inside `tab`, or -1 when that tab is full.
static func free_slot_in_tab(cfg: Dictionary, slots: Array, tab: int) -> int:
	var r := tab_range(cfg, tab)
	for i in range(r.x, mini(r.y, slots.size())):
		if slots[i] == null:
			return i
	return -1

## Index of the first empty slot anywhere, or -1.
static func free_slot_any(slots: Array) -> int:
	for i in slots.size():
		if slots[i] == null:
			return i
	return -1

static func count_items(slots: Array) -> int:
	var c := 0
	for s in slots:
		if s != null:
			c += 1
	return c

## Stash saves before version 3 held 60 slots while only the first 56 (8x7) were ever
## shown. Anything stuck in the hidden slots moves into free slots; if there is no
## room it is kept by granting extra tabs. Returns {"slots": Array, "extra_added": int}.
static func migrate_legacy(cfg: Dictionary, slots: Array) -> Dictionary:
	var per := slots_per_tab(cfg)
	var keep := slots.slice(0, per)
	var hidden := []
	for i in range(per, slots.size()):
		if slots[i] != null:
			hidden.append(slots[i])
	while keep.size() < per:
		keep.append(null)
	var extra := 0
	for it in hidden:
		var f := free_slot_any(keep)
		if f < 0:
			extra += 1
			ensure_slots(cfg, keep, 1 + extra)
			f = free_slot_any(keep)
		keep[f] = it
	return {"slots": keep, "extra_added": extra}
