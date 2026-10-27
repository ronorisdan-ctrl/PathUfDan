extends Node
## Training Grounds session state (autoload "TrainingLog", added last in project.godot).
## Holds the Setup choices, the running test and the last results per save slot.
## It lives here, not on the dummy or the hub, because the hub is rebuilt every time the
## player returns from a dungeon. Session only: nothing is written to disk and the save
## format is untouched (history is lost when the game quits, by design).
## All maths is in scripts/core/training_rules.gd; numbers come from data/training.json.

const Rules = preload("res://scripts/core/training_rules.gd")
const DevRules = preload("res://scripts/core/dev_rules.gd")

signal result_ready(result)

var settings := {}          # Setup tab choices, remembered for the session
var run := {}               # the running (or finished) test; {} when no dummies exist
var last_result := {}       # latest finished result, shown on the Result tab
var history_by_slot := {}   # save slot (int) -> Array of entries, newest first
var _names := {}            # skill id -> display name (built lazily)

func _ready() -> void:
	reset_settings()

func cfg() -> Dictionary:
	return Data.training_cfg

func reset_settings() -> void:
	settings = Rules.default_settings(cfg())

## Training is off under Game.testing unless a test opts in (same pattern as pets).
func available() -> bool:
	return not Game.testing or Game.training_in_tests

# ------------------------------------------------------------------ setup
func set_option(key: String, value) -> void:
	var s := settings.duplicate()
	s[key] = value
	var clean := Rules.sanitize_settings(cfg(), s)
	if clean.get(key) != value:
		return   # not a valid choice: keep what was set before
	settings = clean

## Called by Spawn: a fresh idle test with the current Setup choices.
func begin(dummies: int) -> void:
	run = Rules.new_run(settings, dummies)
	last_result = {}

## Reset button: clears the result and returns to idle without touching the dummies.
func reset_run() -> void:
	if run.is_empty():
		return
	run = Rules.new_run(run["settings"], int(run["dummies"]))
	last_result = {}

## Remove button / leaving the hub: any running test is discarded (never added to history).
func discard() -> void:
	run = {}
	last_result = {}

func has_run() -> bool:
	return not run.is_empty()

func is_running() -> bool:
	return not run.is_empty() and Rules.is_running(run)

# ------------------------------------------------------------------ events from dummies
## Called by a dummy for every damage event. Returns what happened to it (see
## TrainingRules.record, plus "no_run" and "ignored_grace").
func report(ev: Dictionary) -> String:
	if run.is_empty():
		return "no_run"
	var counting: String = run["settings"].get("counting", "all")
	var kind: String = ev.get("kind", "hit")
	if run.get("finished", false):
		if not Rules.starts_window(kind, counting, Rules.is_tick(ev)):
			return "ignored_ended"
		if not Rules.can_start(run):
			return "ignored_grace"
		# grace is over and a counted direct hit arrived: a new test starts with the same settings
		run = Rules.new_run(run["settings"], int(run["dummies"]))
		last_result = {}
	return Rules.record(run, ev)

func report_poise_break() -> void:
	if not run.is_empty():
		Rules.add_poise_break(run)

## Called every physics frame with the SCALED delta (pauses with the pause menu, follows
## hit-stop and the Dev time scale). Finishes the test and stores the result once.
func tick(delta: float) -> void:
	if run.is_empty():
		return
	check_dev()
	Rules.tick(run, delta, float(cfg().get("restart_grace", 2.0)))
	if run.get("finished", false) and not run.get("recorded", false):
		run["recorded"] = true
		var res := Rules.build_result(run, skill_names(), cfg())
		res["when"] = session_time()
		res["snapshot"] = {}
		last_result = res
		_add_to_history(res)
		emit_signal("result_ready", res)

## Marks the running test DEV when a damage-affecting developer flag is active.
func check_dev() -> void:
	if not Dev.enabled() or not Rules.is_running(run):
		return
	var active := Rules.marking_flags(Dev.flags, DevRules.default_flags(),
			cfg().get("dev_flags_that_mark", []), int(Dev.attr_bonus))
	if not active.is_empty():
		run["dev"] = true

## Result fields can be refreshed after the fact (the build snapshot is attached by the
## caller, which can see the character).
func attach_snapshot(snapshot: Dictionary) -> void:
	if last_result.is_empty():
		return
	last_result["snapshot"] = snapshot
	var h := history()
	if not h.is_empty() and h[0].get("when") == last_result.get("when"):
		h[0]["snapshot"] = snapshot

# ------------------------------------------------------------------ history (per save slot)
func _slot_key() -> int:
	return int(Game.current_slot)

func history() -> Array:
	var k := _slot_key()
	if not history_by_slot.has(k):
		history_by_slot[k] = []
	return history_by_slot[k]

func _add_to_history(res: Dictionary) -> void:
	history_by_slot[_slot_key()] = Rules.push_history(history(), res, int(cfg().get("history_size", 5)))

## "Clear history" clears only the current character's list.
func clear_history() -> void:
	history_by_slot[_slot_key()] = []

## Change of a result against the most recent comparable one before it.
func delta_for(result: Dictionary) -> Dictionary:
	var h := history()
	# a result that is already in the list compares with the entries after it
	var skip := 0
	for i in h.size():
		if h[i] == result:
			skip = i + 1
			break
	return Rules.delta_vs_history(result, h, skip)

func session_time() -> float:
	return Time.get_ticks_msec() / 1000.0

func skill_names() -> Dictionary:
	if _names.is_empty():
		for id in Data.skills:
			_names[id] = str(Data.skills[id].get("name", id))
	return _names
