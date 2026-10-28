extends Node
## Loot filter engine. Register as autoload "LootFilter".
## Pure logic: item dictionary in -> display decision out. No scene dependencies,
## so it can be unit tested without a running game.
## Rule model: ordered rules, top to bottom. A matching rule applies its actions.
## If the rule has "continue": true, evaluation goes on and later rules override
## the fields they set (same idea as Path of Exile's Continue). Otherwise it stops.

signal filter_changed
signal reveal_changed(revealed)

const PRESET_NAMES := ["default", "show_all", "rare_plus", "strict"]
const PRESET_DIR := "res://data/loot_filters/"
const USER_ROOT := "user://loot_filters/"
const SCHEMA_VERSION := 1
const MAX_RULES := 100

const RARITIES := ["common", "uncommon", "rare", "epic", "legendary"]
const KINDS := ["gear", "charm", "gem", "rune", "material", "other"]
const SLOTS := ["weapon_1h", "weapon_2h", "offhand", "helm", "chest", "gloves",
	"boots", "belt", "ring", "amulet", "charm"]
const VISIBILITY := ["show", "minimal", "hide"]
const SIZES := {"small": 13, "normal": 16, "large": 20, "huge": 26}
const MINIMAP_SHAPES := ["circle", "diamond", "square", "star"]
const LIST_COND_KEYS := ["kind", "slot", "name_contains", "affix_any"]
const COND_KEYS := ["rarity_min", "rarity_max", "kind", "slot", "name_contains",
	"ilvl_min", "ilvl_max", "ilvl_vs_player_min", "ilvl_vs_player_max",
	"sockets_min", "affix_any", "affix_min_matches", "affix_count_min",
	"is_upgrade", "tier_min", "tier_max"]
const ACTION_KEYS := ["visibility", "color", "size", "beam", "sound", "minimap", "continue"]

## Items used by the editor's dry run and by tests. Keys follow describe().
const SAMPLE_ITEMS := [
	{"name": "Emberheart", "rarity": "legendary", "kind": "gear", "slot": "chest", "ilvl": 40, "sockets": 3},
	{"name": "Runic Greatsword", "rarity": "epic", "kind": "gear", "slot": "weapon_2h", "ilvl": 32, "sockets": 3},
	{"name": "Iron Ring", "rarity": "rare", "kind": "gear", "slot": "ring", "ilvl": 20, "sockets": 1},
	{"name": "Leather Boots", "rarity": "uncommon", "kind": "gear", "slot": "boots", "ilvl": 12, "sockets": 2},
	{"name": "Rusty Helm", "rarity": "common", "kind": "gear", "slot": "helm", "ilvl": 3, "sockets": 0},
	{"name": "Cracked Charm", "rarity": "common", "kind": "charm", "slot": "charm", "ilvl": 8, "sockets": 0},
	{"name": "Ruby (Grade 2)", "rarity": "uncommon", "kind": "gem", "ilvl": 1},
	{"name": "Rune of Echoes", "rarity": "rare", "kind": "rune", "ilvl": 1},
]

var filter: Dictionary = {}
var active_name := "default"
## Fill from Sfx at merge time. Empty = sound ids are not validated.
var known_sounds: Array = []
## Optional Callable(item: Dictionary) -> bool. Hook to the comparison-tooltip logic.
var upgrade_checker := Callable()
var player_level := 1
## Per-character storage: each character has its own folder and its own active filter.
var character_id := "default"
var user_dir := USER_ROOT + "default/"
## Hidden items are NOT drawn, except while Alt is held (set false to disable).
var allow_reveal_key := true
var reveal_hidden := false


## Call when a character is loaded or created (use a stable id, e.g. the save slot).
## Loads that character's last active filter, or the "default" preset for a new one.
func set_character(id: String) -> void:
	character_id = _safe_name(id) if _safe_name(id) != "" else "default"
	user_dir = USER_ROOT + character_id + "/"
	ensure_dirs()
	if not load_filter(_read_active()):
		if not load_filter("default"):
			set_filter({"name": "Fallback"})


func _ready() -> void:
	set_character(character_id)


func _process(_delta: float) -> void:
	var now := (allow_reveal_key and Input.is_key_pressed(KEY_ALT)) or Dev.reveal_hidden()
	if now != reveal_hidden:
		reveal_hidden = now
		emit_signal("reveal_changed", now)


# ---------------------------------------------------------------- evaluation

func evaluate(item: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var d := describe(item)
	var res := {
		"visibility": str(filter.get("default", "show")),
		"visible": true, "color": null, "font_px": -1, "beam": null,
		"sound": "", "minimap": {}, "rule": "", "safety_override": false,
		"drawn": true, "clickable": true, "filter_hidden": false,
	}
	for rule in filter.get("rules", []):
		if not rule.get("enabled", true):
			continue
		if not _match(rule.get("conditions", {}), d, item, ctx):
			continue
		var act: Dictionary = rule.get("actions", {})
		_apply(res, act)
		res["rule"] = str(rule.get("name", ""))
		if not act.get("continue", false):
			break
	if res["visibility"] == "minimal":
		res["beam"] = null
		res["sound"] = ""
		res["minimap"] = {}
		res["font_px"] = SIZES["small"]
		if res["color"] == null:
			res["color"] = Color(0.6, 0.6, 0.6)
	var safe_i := RARITIES.find(str(filter.get("safety", {}).get("never_hide_min_rarity", "")))
	if res["visibility"] == "hide" and safe_i >= 0 and d["rarity_i"] >= safe_i:
		res["visibility"] = "show"
		res["safety_override"] = true
	# The show/hide decision itself. It never looks at the Alt reveal: reveal only
	# changes what is drawn and what the player can target, never what a pet may take.
	res["filter_hidden"] = res["visibility"] == "hide"
	res["visible"] = not res["filter_hidden"] or reveal_hidden
	# A hidden item gets no sprite, label, beam, light, sound or minimap icon, and
	# cannot be clicked or picked up (including future auto-pickup).
	res["drawn"] = res["visible"]
	res["clickable"] = res["visible"]
	if not res["visible"]:
		res["beam"] = null
		res["sound"] = ""
		res["minimap"] = {}
	return res


## The one place that knows how items look. Adjust key names here at merge time.
func describe(item: Dictionary) -> Dictionary:
	var r = item.get("rarity", "common")
	var ri := 0
	if typeof(r) == TYPE_INT:
		ri = clampi(r, 0, RARITIES.size() - 1)
	else:
		ri = maxi(RARITIES.find(str(r).to_lower()), 0)
	var ids: Array = []
	for a in item.get("affixes", []):
		ids.append(str(a.get("id", "")) if typeof(a) == TYPE_DICTIONARY else str(a))
	var sk = item.get("sockets", 0)
	var sockets := 0
	if typeof(sk) == TYPE_ARRAY:
		sockets = sk.size()
	else:
		sockets = int(sk)
	# Path of Dan item slots -> filter slot ids
	var slot := str(item.get("slot", ""))
	match slot:
		"main_hand":
			slot = "weapon_2h" if bool(item.get("two_handed", false)) else "weapon_1h"
		"off_hand":
			slot = "offhand"
		"helmet":
			slot = "helm"
	var kind := str(item.get("kind", ""))
	if kind == "":
		kind = "charm" if slot == "charm" else ("gem" if item.has("gem_type") else "gear")
	return {
		"rarity_i": ri, "kind": kind, "slot": slot, "ilvl": int(item.get("ilvl", 0)),
		"sockets": sockets, "affixes": ids,
		"text": (str(item.get("base_name", item.get("base", ""))) + " " + str(item.get("name", ""))).to_lower(),
	}


func _match(c: Dictionary, d: Dictionary, item: Dictionary, ctx: Dictionary) -> bool:
	if c.has("rarity_min") and d["rarity_i"] < RARITIES.find(str(c["rarity_min"])):
		return false
	if c.has("rarity_max"):
		var mx := RARITIES.find(str(c["rarity_max"]))
		if mx >= 0 and d["rarity_i"] > mx:
			return false
	if c.has("kind") and not (d["kind"] in c["kind"]):
		return false
	if c.has("slot") and not (d["slot"] in c["slot"]):
		return false
	if c.has("name_contains"):
		var hit := false
		for s in c["name_contains"]:
			if str(s).to_lower() != "" and str(s).to_lower() in d["text"]:
				hit = true
		if not hit:
			return false
	if c.has("ilvl_min") and d["ilvl"] < int(c["ilvl_min"]):
		return false
	if c.has("ilvl_max") and d["ilvl"] > int(c["ilvl_max"]):
		return false
	var delta: int = d["ilvl"] - int(ctx.get("player_level", player_level))
	if c.has("ilvl_vs_player_min") and delta < int(c["ilvl_vs_player_min"]):
		return false
	if c.has("ilvl_vs_player_max") and delta > int(c["ilvl_vs_player_max"]):
		return false
	if c.has("sockets_min") and d["sockets"] < int(c["sockets_min"]):
		return false
	if c.has("affix_count_min") and d["affixes"].size() < int(c["affix_count_min"]):
		return false
	if c.has("affix_any"):
		var n := 0
		for a in d["affixes"]:
			if a in c["affix_any"]:
				n += 1
		if n < int(c.get("affix_min_matches", 1)):
			return false
	if c.has("tier_min") and int(ctx.get("tier", 0)) < int(c["tier_min"]):
		return false
	if c.has("tier_max") and int(ctx.get("tier", 0)) > int(c["tier_max"]):
		return false
	if c.has("is_upgrade"):
		var up := false
		if upgrade_checker.is_valid():
			up = bool(upgrade_checker.call(item))
		if up != bool(c["is_upgrade"]):
			return false
	return true


func _apply(res: Dictionary, a: Dictionary) -> void:
	if a.has("visibility") and str(a["visibility"]) in VISIBILITY:
		res["visibility"] = str(a["visibility"])
	if a.has("color") and _ok_color(a["color"]):
		res["color"] = Color.html(str(a["color"]))
	if a.has("size") and SIZES.has(str(a["size"])):
		res["font_px"] = SIZES[str(a["size"])]
	if a.has("beam"):
		if _ok_color(a["beam"]):
			res["beam"] = Color.html(str(a["beam"]))
		elif str(a["beam"]) == "none":
			res["beam"] = null
	if a.has("sound"):
		res["sound"] = "" if str(a["sound"]) == "none" else str(a["sound"])
	if a.has("minimap"):
		var m = a["minimap"]
		if typeof(m) == TYPE_DICTIONARY and _ok_color(m.get("color", "")):
			res["minimap"] = {"shape": str(m.get("shape", "circle")), "color": Color.html(str(m["color"]))}
		else:
			res["minimap"] = {}


func _ok_color(v) -> bool:
	return typeof(v) == TYPE_STRING and Color.html_is_valid(v)


# ------------------------------------------------------- normalise / validate

func normalize(data: Dictionary) -> Dictionary:
	var out := {
		"version": SCHEMA_VERSION, "name": str(data.get("name", "Unnamed")),
		"description": str(data.get("description", "")), "default": "show",
		"safety": {"never_hide_min_rarity": "legendary"}, "rules": [],
	}
	if str(data.get("default", "show")) in VISIBILITY:
		out["default"] = str(data.get("default", "show"))
	var s = data.get("safety", {})
	if typeof(s) == TYPE_DICTIONARY and s.has("never_hide_min_rarity"):
		out["safety"]["never_hide_min_rarity"] = str(s["never_hide_min_rarity"])
	var rules = data.get("rules", [])
	if typeof(rules) != TYPE_ARRAY:
		rules = []
	for r in rules:
		if typeof(r) != TYPE_DICTIONARY or out["rules"].size() >= MAX_RULES:
			continue
		var conds := {}
		var rc = r.get("conditions", {})
		if typeof(rc) == TYPE_DICTIONARY:
			for k in rc:
				if rc[k] == null:
					continue
				conds[k] = _to_list(rc[k]) if k in LIST_COND_KEYS else rc[k]
		var acts := {}
		var ra = r.get("actions", {})
		if typeof(ra) == TYPE_DICTIONARY:
			for k in ra:
				if ra[k] != null:
					acts[k] = ra[k]
		out["rules"].append({"name": str(r.get("name", "Rule")), "enabled": bool(r.get("enabled", true)),
			"conditions": conds, "actions": acts})
	return out


func _to_list(v) -> Array:
	var out: Array = []
	if typeof(v) == TYPE_STRING:
		for p in v.split(","):
			if p.strip_edges() != "":
				out.append(p.strip_edges())
	elif typeof(v) == TYPE_ARRAY:
		for p in v:
			out.append(str(p))
	return out


## Returns human-readable problems. "ERROR:" entries make a rule unreliable.
func validate(data: Dictionary) -> Array:
	var msgs: Array = []
	var i := 0
	var total: int = data.get("rules", []).size()
	for r in data.get("rules", []):
		i += 1
		var tag := "rule %d (%s): " % [i, str(r.get("name", "?"))]
		var c: Dictionary = r.get("conditions", {})
		var a: Dictionary = r.get("actions", {})
		for k in c:
			if not (k in COND_KEYS):
				msgs.append("WARN: " + tag + "unknown condition '%s'" % k)
		for k in a:
			if not (k in ACTION_KEYS):
				msgs.append("WARN: " + tag + "unknown action '%s'" % k)
		for k in ["rarity_min", "rarity_max"]:
			if c.has(k) and not (str(c[k]) in RARITIES):
				msgs.append("ERROR: " + tag + "bad rarity '%s'" % str(c[k]))
		for k in ["color", "beam"]:
			if a.has(k) and not _ok_color(a[k]) and str(a[k]) != "none":
				msgs.append("ERROR: " + tag + "bad colour for %s" % k)
		if a.has("visibility") and not (str(a["visibility"]) in VISIBILITY):
			msgs.append("ERROR: " + tag + "bad visibility")
		if a.has("size") and not SIZES.has(str(a["size"])):
			msgs.append("ERROR: " + tag + "bad size")
		if a.has("sound") and known_sounds.size() > 0 and str(a["sound"]) != "none" \
				and not (str(a["sound"]) in known_sounds):
			msgs.append("WARN: " + tag + "unknown sound '%s'" % str(a["sound"]))
		if c.is_empty() and not a.get("continue", false) and r.get("enabled", true) and i < total:
			msgs.append("WARN: " + tag + "matches everything, so rules below it never run")
	return msgs


# -------------------------------------------------------------- load / save

func set_filter(data: Dictionary) -> void:
	filter = normalize(data)
	emit_signal("filter_changed")


func list_filters() -> Array:
	var names: Array = PRESET_NAMES.duplicate()
	var d := DirAccess.open(user_dir)
	if d:
		for f in d.get_files():
			if f.ends_with(".json") and not f.begins_with("_"):
				var n := f.get_basename()
				if not (n in names):
					names.append(n)
	return names


func load_filter(fname: String) -> bool:
	var data = _read_json(user_dir + fname + ".json")
	if data == null and fname in PRESET_NAMES:
		data = _read_json(PRESET_DIR + fname + ".json")
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("LootFilter: could not load '%s'" % fname)
		return false
	set_filter(data)
	active_name = fname
	_write_active()
	return true


## Atomic write with a .bak of the previous file. Returns an Error code.
func save_filter(fname: String, data: Dictionary) -> int:
	ensure_dirs()
	var clean := _safe_name(fname)
	if clean == "" or clean in PRESET_NAMES:
		return ERR_INVALID_PARAMETER
	var path := user_dir + clean + ".json"
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return ERR_CANT_CREATE
	f.store_string(export_text(data))
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(path, path + ".bak")
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(tmp, path)


func export_text(data: Dictionary) -> String:
	return JSON.stringify(normalize(data), "\t")


func import_text(text: String) -> Dictionary:
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "errors": ["Not a valid filter (JSON object expected)"], "data": {}}
	var data := normalize(parsed)
	var errs: Array = []
	for m in validate(data):
		if m.begins_with("ERROR"):
			errs.append(m)
	return {"ok": errs.is_empty(), "errors": errs, "data": data}


func ensure_dirs() -> void:
	DirAccess.make_dir_recursive_absolute(user_dir)


func user_dir_os_path() -> String:
	return ProjectSettings.globalize_path(user_dir)


func _safe_name(s: String) -> String:
	var out := ""
	for ch in s.strip_edges():
		if ch.is_valid_identifier() or ch == " " or ch == "-" or (ch >= "0" and ch <= "9"):
			out += ch
	return out.strip_edges().substr(0, 40)


func _read_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


func _active_file() -> String:
	return user_dir + "_active.txt"


func _read_active() -> String:
	if not FileAccess.file_exists(_active_file()):
		return "default"
	var f := FileAccess.open(_active_file(), FileAccess.READ)
	return f.get_as_text().strip_edges() if f else "default"


func _write_active() -> void:
	ensure_dirs()
	var f := FileAccess.open(_active_file(), FileAccess.WRITE)
	if f:
		f.store_string(active_name)
