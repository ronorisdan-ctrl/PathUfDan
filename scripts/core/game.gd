extends Node
## Global game state: current character, settings, input map, save/load,
## and the bridge to the main scene that swaps menus, hub and dungeons.

const CharacterData = preload("res://scripts/core/character_data.gd")
const LEGACY_SAVE_PATH := "user://pathofdan_save.json"
const SAVE_DIR := "user://saves"
const SLOT_COUNT := 10
const AUTOSAVE_SLOT := 0
const SETTINGS_PATH := "user://pathofdan_settings.json"

var ch = null
var main = null
var level = null
var settings := {"loot_filter": 0, "screen_shake": 1.0, "volume": 0.7, "fullscreen": false, "hit_stop": true}
var carried_minions := 0
var vendor_stock := []
var testing := false
var save_dir := SAVE_DIR   # tests point this at a scratch folder
var current_slot := 1

const ACTIONS := {
	"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
	"skill_1": ["MB_LEFT"], "skill_2": ["MB_RIGHT"], "skill_3": [KEY_Q], "skill_4": [KEY_E], "skill_5": [KEY_R], "skill_6": [KEY_T], "skill_7": [KEY_G], "toggle_spec": [KEY_J],
	"dodge": [KEY_SPACE], "flask_1": [KEY_1], "flask_2": [KEY_2], "interact": [KEY_F],
	"toggle_inventory": [KEY_I, KEY_B], "toggle_character": [KEY_C], "toggle_passives": [KEY_P],
	"toggle_skills": [KEY_K], "toggle_map": [KEY_TAB], "toggle_loot_filter": [KEY_Z], "pause": [KEY_ESCAPE],
}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fixed_fps = OS.get_cmdline_args().has("--fixed-fps") or OS.get_cmdline_user_args().has("--fixed-fps")
	_setup_input()
	load_settings()

# ------------------------------------------------------------------ hit-stop
# A brief slow-motion freeze on impactful hits (crits, heavy hits, elite/boss kills).
# Timing uses real clock ticks, because Engine.time_scale also scales our own delta.
# Always off under tests, headless runs and --fixed-fps bot runs, so results stay deterministic.
const HITSTOP_SCALE := 0.03
const HITSTOP_MAX := 0.1
const HITSTOP_GAP_MS := 150    # minimum real time between freezes, so combos never feel sticky
var _fixed_fps := false
var _hs_end_ms := 0
var _hs_next_ms := 0

func hitstop_allowed() -> bool:
	return not testing and not _fixed_fps and bool(settings.get("hit_stop", true)) \
		and DisplayServer.get_name() != "headless"

## Freeze the game for about `sec` seconds of real time (clamped to HITSTOP_MAX).
func hitstop(sec: float) -> void:
	if sec <= 0.0 or not hitstop_allowed() or get_tree().paused:
		return
	var now := Time.get_ticks_msec()
	if _hs_end_ms == 0 and now < _hs_next_ms:
		return
	var end := now + int(minf(sec, HITSTOP_MAX) * 1000.0)
	if end <= _hs_end_ms:
		return
	_hs_end_ms = end
	_hs_next_ms = end + HITSTOP_GAP_MS
	Engine.time_scale = HITSTOP_SCALE

func end_hitstop() -> void:
	_hs_end_ms = 0
	Engine.time_scale = 1.0

func _process(_delta: float) -> void:
	if _hs_end_ms > 0 and (Time.get_ticks_msec() >= _hs_end_ms or get_tree().paused or not hitstop_allowed()):
		end_hitstop()

func _exit_tree() -> void:
	Engine.time_scale = 1.0

func _setup_input() -> void:
	for a in ACTIONS:
		if InputMap.has_action(a):
			InputMap.erase_action(a)
		InputMap.add_action(a)
		for k in ACTIONS[a]:
			if typeof(k) == TYPE_STRING:
				var mb := InputEventMouseButton.new()
				mb.button_index = MOUSE_BUTTON_LEFT if k == "MB_LEFT" else MOUSE_BUTTON_RIGHT
				InputMap.action_add_event(a, mb)
			else:
				var ev := InputEventKey.new()
				ev.physical_keycode = k
				InputMap.action_add_event(a, ev)

# ------------------------------------------------------------------ character
func new_character(cls: String) -> void:
	ch = CharacterData.new()
	ch.setup_new(cls, "Dan")
	carried_minions = 0
	vendor_stock.clear()

# ------------------------------------------------------------------ save slots
# 10 manual slots (1..10) plus one autosave (slot 0), each its own JSON file.
# The save dict format is unchanged (version 1); files add "saved_at" and
# "slot" metadata, which older code simply ignores.
func slot_path(slot: int) -> String:
	if slot == AUTOSAVE_SLOT:
		return save_dir + "/autosave.json"
	return save_dir + "/slot_%02d.json" % slot

func valid_slot(slot: int) -> bool:
	return slot >= 1 and slot <= SLOT_COUNT

func has_slot(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot))

## True if any slot or the autosave holds a file (used by the Continue button).
func has_save() -> bool:
	for s in range(0, SLOT_COUNT + 1):
		if has_slot(s):
			return true
	return false

func first_empty_slot() -> int:
	for s in range(1, SLOT_COUNT + 1):
		if not has_slot(s):
			return s
	return 0

func _ensure_dir() -> bool:
	if DirAccess.dir_exists_absolute(save_dir):
		return true
	return DirAccess.make_dir_recursive_absolute(save_dir) == OK

## Writes text to path via a .tmp file then a rename, so a crash mid-write
## cannot leave a half-written save behind.
func _write_atomic(path: String, text: String) -> bool:
	if not _ensure_dir():
		push_error("Could not create save folder %s" % save_dir)
		return false
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("Could not write save: %s" % FileAccess.get_open_error())
		return false
	f.store_string(text)
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	if DirAccess.rename_absolute(tmp, path) != OK:
		push_error("Could not finalise save %s" % path)
		return false
	return true

func _save_text() -> String:
	var d: Dictionary = ch.to_dict()
	d["vendor_stock"] = vendor_stock
	d["saved_at"] = int(Time.get_unix_time_from_system())
	d["slot"] = current_slot
	return JSON.stringify(d, "\t")

## Saves the current character to a manual slot (default: the current slot).
func save_game(slot: int = -1) -> bool:
	if ch == null or testing:
		return false
	if slot < 0:
		slot = current_slot
	if not valid_slot(slot):
		return false
	current_slot = slot
	return _write_atomic(slot_path(slot), _save_text())

## Rolling autosave into its own file; never touches the manual slots.
func autosave() -> bool:
	if ch == null or testing or not valid_slot(current_slot):
		return false
	return _write_atomic(slot_path(AUTOSAVE_SLOT), _save_text())

func read_slot(slot: int) -> Dictionary:
	if not has_slot(slot):
		return {}
	var f := FileAccess.open(slot_path(slot), FileAccess.READ)
	if f == null:
		return {"corrupt": true}
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		return {"corrupt": true}
	return d

func load_game(slot: int = -1) -> bool:
	if slot < 0:
		slot = current_slot
	var d := read_slot(slot)
	if d.is_empty() or d.has("corrupt"):
		if d.has("corrupt"):
			push_error("Save file is corrupted")
		return false
	if not load_from_dict(d):
		return false
	if slot == AUTOSAVE_SLOT:
		# continue in the manual slot the autosave came from (or any free one)
		var origin := int(d.get("slot", 0))
		current_slot = origin if valid_slot(origin) else maxi(first_empty_slot(), 1)
	else:
		current_slot = slot
	return true

func load_from_dict(d: Dictionary) -> bool:
	ch = CharacterData.new()
	ch.from_dict(d)
	vendor_stock = []
	for it in d.get("vendor_stock", []):
		var fixed = ch._fix_item(it)
		if fixed != null:
			vendor_stock.append(fixed)
	carried_minions = 0
	return true

## Display info for a slot: {exists, corrupt, summary, saved_at, date}.
func slot_info(slot: int) -> Dictionary:
	var info := {"exists": false, "corrupt": false, "summary": "", "saved_at": 0, "date": ""}
	if not has_slot(slot):
		return info
	info["exists"] = true
	var d := read_slot(slot)
	if d.is_empty() or d.has("corrupt"):
		info["corrupt"] = true
		info["summary"] = "Corrupted save"
		return info
	var cd: Dictionary = Data.classes.get(d.get("class", ""), {})
	info["summary"] = "%s - Level %d %s" % [d.get("name", "Dan"), int(d.get("level", 1)), cd.get("name", "?")]
	info["saved_at"] = int(d.get("saved_at", 0))
	if info["saved_at"] > 0:
		info["date"] = Time.get_datetime_string_from_unix_time(info["saved_at"], true)
	return info

## Summary of the most recently written save (for the main menu).
func latest_summary() -> String:
	var best := -1
	var best_t := -1
	for s in range(0, SLOT_COUNT + 1):
		if has_slot(s):
			var t := int(slot_info(s)["saved_at"])
			if t > best_t:
				best_t = t
				best = s
	if best < 0:
		return ""
	var label := "Autosave" if best == AUTOSAVE_SLOT else "Slot %d" % best
	return "%s: %s" % [label, slot_info(best)["summary"]]

func save_summary() -> String:
	return latest_summary()

func delete_slot(slot: int) -> void:
	if has_slot(slot):
		DirAccess.remove_absolute(slot_path(slot))

func delete_save() -> void:
	delete_slot(current_slot)

## One-time import of the old single-file save into the first free slot. The
## old file is left untouched, and a marker file stops it running twice.
func migrate_legacy_save() -> void:
	if testing or not FileAccess.file_exists(LEGACY_SAVE_PATH):
		return
	var marker := save_dir + "/.migrated"
	if FileAccess.file_exists(marker):
		return
	var f := FileAccess.open(LEGACY_SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()
	if typeof(JSON.parse_string(text)) != TYPE_DICTIONARY:
		return
	var slot := first_empty_slot()
	if slot == 0:
		return
	if _write_atomic(slot_path(slot), text) and has_slot(slot):
		_write_atomic(marker, "legacy save imported into slot %d" % slot)

# ------------------------------------------------------------------ settings
func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) == TYPE_DICTIONARY:
		for k in d:
			settings[k] = d[k]
	apply_settings()

func save_settings() -> void:
	if testing:
		return
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings))

func apply_settings() -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(0.001, float(settings.get("volume", 0.7)))))
	if not testing and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if settings.get("fullscreen", false) else DisplayServer.WINDOW_MODE_WINDOWED)

# ------------------------------------------------------------------ dungeon runs
## Each dungeon keeps a pre-rolled set of run modifiers so the Dungeon Gate can
## show them before you commit. They are re-rolled after every run.
func roll_run_mods(def: Dictionary) -> Array:
	var mc: Array = def.get("mod_count", [0, 0])
	var n := randi_range(int(mc[0]), int(mc[1]))
	var ids := []
	for m in Data.dungeon_mod_list:
		ids.append(m["id"])
	ids.shuffle()
	return ids.slice(0, n)

func prepared_run(def: Dictionary) -> Dictionary:
	if ch == null:
		return {}
	var pr: Dictionary = ch.progress.get("prepared", {})
	if not pr.has(def["id"]):
		pr[def["id"]] = {"mods": roll_run_mods(def), "depth": 1}
		ch.progress["prepared"] = pr
	return pr[def["id"]]

func reroll_prepared(def: Dictionary) -> void:
	var pr: Dictionary = ch.progress.get("prepared", {})
	pr[def["id"]] = {"mods": roll_run_mods(def), "depth": 1}
	ch.progress["prepared"] = pr

func take_prepared_run(def: Dictionary) -> Dictionary:
	if ch == null:
		return {}
	var r: Dictionary = prepared_run(def).duplicate(true)
	reroll_prepared(def)
	return r

# ------------------------------------------------------------------ vendor
func refresh_vendor() -> void:
	vendor_stock.clear()
	if ch == null:
		return
	for i in 8:
		var it := Loot.roll_item(maxi(1, ch.level), 60.0, ch.class_id)
		it["uid"] = ch.take_uid()
		vendor_stock.append(it)
