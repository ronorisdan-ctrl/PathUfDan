extends Node
## Account-wide stash shared by every character. Register as autoload "SharedStash".
## Lives in user://shared_stash.json (not in a save slot), written atomically with a
## .bak copy of the previous version. Holds equipment and charms only: gems, runes and
## materials are counters on the character, not item dictionaries, so they cannot be
## stored here.
##
## Duplication safety. The character and the shared file are saved separately, so every
## transfer orders its two writes such that a crash can only LOSE an item, never copy it:
##   deposit:  remove from the character -> save the character -> write the shared file
##   withdraw: write the shared file (item removed) -> add to the character -> save it

const Rules = preload("res://scripts/core/stash_rules.gd")
const CharacterData = preload("res://scripts/core/character_data.gd")

const REAL_PATH := "user://shared_stash.json"
const VERSION := 1

signal changed

## Tests point this at a scratch file. While Game.testing is on, the real file is never written.
var path := REAL_PATH
var extra_tabs := 0
var slots: Array = []
var loaded_from_backup := false
var _fixer = null   # a CharacterData, used only for its item validation (_fix_item)

func _ready() -> void:
	load_file()

func cfg() -> Dictionary:
	return Data.stash_cfg

func tab_total() -> int:
	return Rules.tab_total(cfg(), extra_tabs, true)

func next_cost() -> int:
	return Rules.tab_cost(cfg(), extra_tabs)

func item_count() -> int:
	return Rules.count_items(slots)

## True for anything the shared stash accepts: a real item dictionary (known base).
func can_store(item) -> bool:
	return typeof(item) == TYPE_DICTIONARY and Data.item_bases.has(item.get("base", ""))

# ------------------------------------------------------------------ file
func load_file() -> void:
	extra_tabs = 0
	slots = []
	loaded_from_backup = false
	for p in [path, path + ".bak"]:
		if not FileAccess.file_exists(p):
			continue
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null:
			continue
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		_apply(parsed)
		loaded_from_backup = (p != path)
		return
	Rules.ensure_slots(cfg(), slots, tab_total())

func _apply(d: Dictionary) -> void:
	if _fixer == null:
		_fixer = CharacterData.new()
	var c := cfg()
	extra_tabs = Rules.clamp_extra(c, int(d.get("extra_tabs", 0)))
	var raw: Array = Array(d.get("slots", []))
	slots = []
	var last := -1
	for i in raw.size():
		var it = _fixer._fix_item(raw[i])
		slots.append(it)
		if it != null:
			last = i
	if last >= 0:   # never drop an item because the config shrank
		var need := int(ceil(float(last + 1) / float(Rules.slots_per_tab(c))))
		extra_tabs = maxi(extra_tabs, need - Rules.free_tabs(c, true))
	Rules.ensure_slots(c, slots, tab_total())
	slots.resize(tab_total() * Rules.slots_per_tab(c))

## Atomic write: temp file, previous version kept as .bak, then rename.
## Returns true on success (and true without writing when tests would hit the real file).
func save_file() -> bool:
	if Game.testing and path == REAL_PATH:
		return true
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("Could not write shared stash: %s" % FileAccess.get_open_error())
		return false
	f.store_string(JSON.stringify({"version": VERSION, "extra_tabs": extra_tabs, "slots": slots}))
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(path, path + ".bak")
		DirAccess.remove_absolute(path)
	if DirAccess.rename_absolute(tmp, path) != OK:
		push_error("Could not finalise shared stash")
		return false
	return true

## Empties the in-memory stash (tests).
func reset() -> void:
	extra_tabs = 0
	slots = []
	Rules.ensure_slots(cfg(), slots, tab_total())
	changed.emit()

# ------------------------------------------------------------------ buying tabs
## Charges the active character. Returns "" on success or the refusal reason.
## Order: character saved first, then the shared file, so a crash costs gold, never a free tab.
func buy_tab(ch) -> String:
	var why := Rules.buy_refusal(cfg(), extra_tabs, int(ch.gold))
	if why != "":
		return why
	var cost := next_cost()
	ch.gold -= cost
	extra_tabs += 1
	Rules.ensure_slots(cfg(), slots, tab_total())
	Events.currency_changed.emit()
	Game.save_now()
	if not save_file():
		ch.gold += cost   # nothing was recorded, so give the gold back
		extra_tabs -= 1
		slots.resize(tab_total() * Rules.slots_per_tab(cfg()))
		Events.currency_changed.emit()
		return "Could not save the shared stash"
	changed.emit()
	return ""

# ------------------------------------------------------------------ transfers
## Moves bag item `bag_idx` into the shared stash, preferring `prefer_tab` and falling back
## to any tab with room. Returns {"err": "" or reason, "tab": tab used}.
func deposit(ch, bag_idx: int, prefer_tab: int = 0) -> Dictionary:
	var it = ch.inventory[bag_idx] if bag_idx >= 0 and bag_idx < ch.inventory.size() else null
	if it == null:
		return {"err": "Nothing to store", "tab": prefer_tab}
	if not can_store(it):
		return {"err": "Shared stash holds items only", "tab": prefer_tab}
	var tab := -1
	var idx := Rules.free_slot_in_tab(cfg(), slots, prefer_tab)
	if idx >= 0:
		tab = prefer_tab
	else:
		for t in tab_total():
			idx = Rules.free_slot_in_tab(cfg(), slots, t)
			if idx >= 0:
				tab = t
				break
	if idx < 0:
		return {"err": "Shared stash is full", "tab": prefer_tab}
	ch.inventory[bag_idx] = null
	Game.save_now()                 # the character no longer owns it before the file does
	slots[idx] = it
	if not save_file():
		slots[idx] = null           # keep it in the bag; the next save will record that
		ch.inventory[bag_idx] = it
		return {"err": "Could not save the shared stash", "tab": prefer_tab}
	Events.inventory_changed.emit()
	changed.emit()
	return {"err": "", "tab": tab}

## Moves shared slot `slot_idx` into the character's bag. Returns "" or the reason.
func withdraw(ch, slot_idx: int) -> String:
	if slot_idx < 0 or slot_idx >= slots.size() or slots[slot_idx] == null:
		return "Nothing to take"
	if ch.free_bag_slot() < 0:
		return "Inventory full"
	var it = slots[slot_idx]
	slots[slot_idx] = null
	if not save_file():
		slots[slot_idx] = it
		return "Could not save the shared stash"
	it["uid"] = ch.take_uid()       # uids are per character; give it a fresh one
	ch.add_to_bag(it)
	Game.save_now()
	changed.emit()
	return ""
