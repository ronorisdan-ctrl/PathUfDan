extends Node
## Acceptance tests for the loot filter engine. No autoload or scene needed.
## Standalone use: make a scene with this script on the root node; it prints a
## summary and quits. To fold into tests/test_runner.gd, call run() and add
## result["passed"] / result["failed"] to its counters.

const LF := preload("res://scripts/core/loot_filter.gd")

var passed := 0
var failed := 0
var fails: Array = []


func _ready() -> void:
	var r := run()
	print("loot filter tests: %d passed, %d failed" % [r["passed"], r["failed"]])
	for l in r["log"]:
		print("  FAIL: ", l)
	get_tree().quit(1 if r["failed"] > 0 else 0)


func run() -> Dictionary:
	passed = 0
	failed = 0
	fails = []
	_t_presets()
	_t_rarity()
	_t_order_and_continue()
	_t_disabled_and_empty()
	_t_safety()
	_t_hide_and_reveal()
	_t_minimal()
	_t_level_delta()
	_t_affixes_and_upgrade()
	_t_normalize_garbage()
	_t_roundtrip()
	_t_per_character()
	return {"passed": passed, "failed": failed, "log": fails}


func _check(ok: bool, msg: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		fails.append(msg)


func _mk(data: Dictionary) -> Node:
	var f = LF.new()
	f.set_filter(data)
	return f


func _item(rarity: String, extra: Dictionary = {}) -> Dictionary:
	var it := {"name": "Test", "rarity": rarity, "kind": "gear", "slot": "ring", "ilvl": 10, "sockets": 1}
	it.merge(extra, true)
	return it


func _rule(name: String, cond: Dictionary, act: Dictionary) -> Dictionary:
	return {"name": name, "enabled": true, "conditions": cond, "actions": act}


func _t_presets() -> void:
	for n in LF.PRESET_NAMES:
		var f = LF.new()
		var text := FileAccess.get_file_as_string(LF.PRESET_DIR + n + ".json")
		var res: Dictionary = f.import_text(text)
		_check(res["ok"], "preset %s imports without errors: %s" % [n, str(res["errors"])])
		f.set_filter(res["data"])
		for it in LF.SAMPLE_ITEMS:
			var ev: Dictionary = f.evaluate(it)
			_check(ev["visibility"] in LF.VISIBILITY, "preset %s gives a valid visibility" % n)
		var leg: Dictionary = f.evaluate(_item("legendary"))
		_check(leg["visibility"] == "show", "preset %s never hides a legendary" % n)


func _t_rarity() -> void:
	var f = _mk({"default": "hide", "rules": [_rule("rare+", {"rarity_min": "rare"}, {"visibility": "show"})]})
	_check(f.evaluate(_item("rare"))["visibility"] == "show", "rarity_min matches equal rarity")
	_check(f.evaluate(_item("epic"))["visibility"] == "show", "rarity_min matches higher rarity")
	_check(f.evaluate(_item("uncommon"))["visibility"] == "hide", "rarity_min rejects lower; default applies")
	var g = _mk({"rules": [_rule("max", {"rarity_max": "uncommon"}, {"visibility": "hide"})]})
	_check(g.evaluate(_item("common"))["visibility"] == "hide", "rarity_max matches lower")
	_check(g.evaluate(_item("rare"))["visibility"] == "show", "rarity_max rejects higher")
	_check(g.evaluate({"rarity": 2})["visibility"] == "show", "integer rarity is accepted")


func _t_order_and_continue() -> void:
	var f = _mk({"rules": [
		_rule("first", {"rarity_min": "rare"}, {"color": "#ff0000"}),
		_rule("second", {"rarity_min": "rare"}, {"color": "#00ff00"})]})
	_check(f.evaluate(_item("rare"))["color"] == Color.html("#ff0000"), "first match wins without continue")
	var g = _mk({"rules": [
		_rule("sock", {"sockets_min": 1}, {"beam": "#ffffff", "continue": true}),
		_rule("rare", {"rarity_min": "rare"}, {"color": "#ffd84a"})]})
	var r: Dictionary = g.evaluate(_item("rare"))
	_check(r["beam"] == Color.html("#ffffff") and r["color"] == Color.html("#ffd84a"), "continue accumulates actions")
	_check(r["rule"] == "rare", "last matching rule is reported")
	var h = _mk({"rules": [
		_rule("a", {}, {"color": "#ff0000", "continue": true}),
		_rule("b", {}, {"color": "#0000ff"})]})
	_check(h.evaluate(_item("common"))["color"] == Color.html("#0000ff"), "later rule overrides earlier field")


func _t_disabled_and_empty() -> void:
	var f = _mk({"default": "show", "rules": [
		{"name": "off", "enabled": false, "conditions": {}, "actions": {"visibility": "hide"}}]})
	_check(f.evaluate(_item("common"))["visibility"] == "show", "disabled rule is skipped")
	var g = _mk({"rules": [_rule("all", {}, {"visibility": "hide"})]})
	_check(g.evaluate(_item("common"))["visibility"] == "hide", "empty conditions match everything")


func _t_safety() -> void:
	var f = _mk({"rules": [_rule("all", {}, {"visibility": "hide"})]})
	var r: Dictionary = f.evaluate(_item("legendary"))
	_check(r["visibility"] == "show" and r["safety_override"], "safety net overrides hide on legendary")
	var g = _mk({"safety": {"never_hide_min_rarity": "none"}, "rules": [_rule("all", {}, {"visibility": "hide"})]})
	_check(g.evaluate(_item("legendary"))["visibility"] == "hide", "safety net can be turned off")


func _t_hide_and_reveal() -> void:
	var f = _mk({"rules": [_rule("all", {}, {"visibility": "hide"})]})
	_check(not f.evaluate(_item("common"))["visible"], "hidden item is not visible")
	var hid: Dictionary = f.evaluate(_item("common"))
	_check(not hid["drawn"] and not hid["clickable"], "hidden item is not drawn and not clickable")
	_check(hid["beam"] == null and hid["sound"] == "" and hid["minimap"].is_empty(), "hidden item has no beam, sound or minimap icon")
	_check(f.allow_reveal_key, "Alt reveal is on by default")
	f.reveal_hidden = true
	var shown: Dictionary = f.evaluate(_item("common"))
	_check(shown["drawn"] and shown["clickable"] and shown["visibility"] == "hide", "Alt reveal draws hidden items and makes them clickable")
	f.reveal_hidden = false
	_check(not f.evaluate(_item("common"))["drawn"], "hidden again when Alt is released")


func _t_minimal() -> void:
	var f = _mk({"rules": [_rule("m", {}, {"visibility": "minimal", "beam": "#ffffff", "sound": "x", "size": "huge"})]})
	var r: Dictionary = f.evaluate(_item("common"))
	_check(r["beam"] == null and r["sound"] == "" and r["font_px"] == LF.SIZES["small"], "minimal strips beam, sound and size")


func _t_level_delta() -> void:
	var f = _mk({"rules": [_rule("old", {"ilvl_vs_player_max": -6}, {"visibility": "hide"})]})
	_check(f.evaluate(_item("common", {"ilvl": 4}), {"player_level": 12})["visibility"] == "hide", "old item hidden by level delta")
	_check(f.evaluate(_item("common", {"ilvl": 10}), {"player_level": 12})["visibility"] == "show", "recent item not hidden")


func _t_affixes_and_upgrade() -> void:
	var f = _mk({"rules": [
		_rule("aff", {"affix_any": ["life", "crit"], "affix_min_matches": 2}, {"color": "#ff0000"})]})
	var two := _item("rare", {"affixes": [{"id": "life"}, {"id": "crit"}, {"id": "armour"}]})
	var one := _item("rare", {"affixes": [{"id": "life"}]})
	_check(f.evaluate(two)["color"] != null, "affix_min_matches satisfied")
	_check(f.evaluate(one)["color"] == null, "affix_min_matches not satisfied")
	var g = _mk({"rules": [_rule("up", {"is_upgrade": true}, {"color": "#00ff00"})]})
	_check(g.evaluate(_item("rare"))["color"] == null, "no upgrade checker means not an upgrade")
	g.upgrade_checker = func(_it): return true
	_check(g.evaluate(_item("rare"))["color"] != null, "upgrade checker is used")


func _t_normalize_garbage() -> void:
	var f = LF.new()
	var n: Dictionary = f.normalize({"rules": [5, {"conditions": {"kind": "gem, rune", "x": null}, "actions": {"color": null}}], "default": "bogus"})
	_check(n["default"] == "show", "bad default falls back to show")
	_check(n["rules"].size() == 1, "non-dictionary rules are dropped")
	_check(n["rules"][0]["conditions"]["kind"] == ["gem", "rune"], "comma string becomes list")
	var bad: Dictionary = f.import_text("not json")
	_check(not bad["ok"], "garbage import is rejected")
	var many := []
	for i in 150:
		many.append(_rule("r", {"ilvl_min": 1}, {}))
	_check(f.normalize({"rules": many})["rules"].size() == LF.MAX_RULES, "rule count is capped")


func _t_roundtrip() -> void:
	var f = LF.new()
	var src := FileAccess.get_file_as_string(LF.PRESET_DIR + "default.json")
	var a: Dictionary = f.import_text(src)["data"]
	var b: Dictionary = f.import_text(f.export_text(a))["data"]
	_check(JSON.stringify(a) == JSON.stringify(b), "export then import is lossless")


func _t_per_character() -> void:
	var f = LF.new()
	f.set_character("test_char_a")
	var err: int = f.save_filter("mine", {"name": "A", "rules": [_rule("hide all", {}, {"visibility": "hide"})]})
	_check(err == OK, "save_filter succeeds for character A")
	f.set_character("test_char_b")
	_check(f.active_name == "default", "new character starts on the default preset")
	_check(not ("mine" in f.list_filters()), "character B does not see character A's filters")
	f.set_character("test_char_a")
	_check("mine" in f.list_filters(), "character A still has its saved filter")
	_check(f.load_filter("mine") and f.evaluate(_item("common"))["visibility"] == "hide", "character A filter loads")
	f.set_character("test_char_a")
	_check(f.active_name == "mine", "character A's active filter is remembered")
	for n in ["test_char_a", "test_char_b"]:
		var dir: String = LF.USER_ROOT + n + "/"
		for file in ["mine.json", "mine.json.bak", "_active.txt"]:
			DirAccess.remove_absolute(dir + file)
		DirAccess.remove_absolute(dir)
