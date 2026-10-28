extends PanelContainer
## In-game loot filter editor, built entirely in code (no scene needed).
##   var p = preload("res://scripts/ui/loot_filter_panel.gd").new()
##   some_ui_layer.add_child(p); p.open()
## Edits a working copy. "Apply" pushes it to the live LootFilter autoload,
## "Save" also writes it to user://loot_filters/<name>.json.

signal closed

const LF := preload("res://scripts/core/loot_filter.gd")

var COND_FIELDS := [
	{"k": "rarity_min", "l": "Rarity at least", "t": "enum", "o": [""] + LF.RARITIES},
	{"k": "rarity_max", "l": "Rarity at most", "t": "enum", "o": [""] + LF.RARITIES},
	{"k": "kind", "l": "Item kind", "t": "multi", "o": LF.KINDS},
	{"k": "slot", "l": "Slot", "t": "multi", "o": LF.SLOTS},
	{"k": "name_contains", "l": "Name/base contains (comma list)", "t": "list"},
	{"k": "ilvl_min", "l": "Item level at least", "t": "int"},
	{"k": "ilvl_max", "l": "Item level at most", "t": "int"},
	{"k": "ilvl_vs_player_min", "l": "Item lvl minus your lvl, min", "t": "int"},
	{"k": "ilvl_vs_player_max", "l": "Item lvl minus your lvl, max", "t": "int"},
	{"k": "sockets_min", "l": "Sockets at least", "t": "int"},
	{"k": "affix_any", "l": "Has affix ids (comma list)", "t": "list"},
	{"k": "affix_min_matches", "l": "...at least this many of them", "t": "int"},
	{"k": "affix_count_min", "l": "Total affixes at least", "t": "int"},
	{"k": "is_upgrade", "l": "Is an upgrade for me", "t": "tri"},
	{"k": "tier_min", "l": "Dungeon tier at least", "t": "int"},
	{"k": "tier_max", "l": "Dungeon tier at most", "t": "int"},
]

var engine: Node
var _filter: Dictionary = {}
var _sel := -1
var _loading := false
var _w := {}
var _rule_list: ItemList
var _pick: OptionButton
var _save_name: LineEdit
var _status: Label
var _preview: Label
var _dry: Label
var _form: VBoxContainer


func _ready() -> void:
	engine = get_node_or_null("/root/LootFilter")
	custom_minimum_size = Vector2(980, 600)
	_build()
	visible = false


func open() -> void:
	if engine == null:
		return
	_filter = engine.filter.duplicate(true)
	_save_name.text = "" if engine.active_name in LF.PRESET_NAMES else engine.active_name
	_refresh_picker()
	_refresh_list()
	_select(0 if _filter["rules"].size() > 0 else -1)
	_dry_run()
	_say("Character: %s. Filters are saved per character." % engine.character_id)
	visible = true


func close() -> void:
	visible = false
	emit_signal("closed")


# ---------------------------------------------------------------------- build

func _build() -> void:
	var root := VBoxContainer.new()
	add_child(root)
	var top := HBoxContainer.new()
	root.add_child(top)
	_pick = OptionButton.new()
	top.add_child(_pick)
	_btn(top, "Load", _on_load)
	_save_name = LineEdit.new()
	_save_name.placeholder_text = "save as..."
	_save_name.custom_minimum_size = Vector2(160, 0)
	top.add_child(_save_name)
	_btn(top, "Apply", _on_apply)
	_btn(top, "Save + Apply", _on_save)
	_btn(top, "Export (copy)", _on_export)
	_btn(top, "Import (paste)", _on_import)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	_btn(top, "Close", close)

	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(mid)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(260, 0)
	mid.add_child(left)
	_rule_list = ItemList.new()
	_rule_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rule_list.item_selected.connect(_select)
	left.add_child(_rule_list)
	var lb := HBoxContainer.new()
	left.add_child(lb)
	_btn(lb, "+", _on_add)
	_btn(lb, "Copy", _on_dup)
	_btn(lb, "Del", _on_del)
	_btn(lb, "Up", _on_up)
	_btn(lb, "Down", _on_down)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(scroll)
	_form = VBoxContainer.new()
	_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_form)
	_build_form()

	_preview = Label.new()
	_preview.text = "Preview"
	root.add_child(_preview)
	_dry = Label.new()
	root.add_child(_dry)
	_status = Label.new()
	root.add_child(_status)


func _btn(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _row(label: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(230, 0)
	h.add_child(l)
	_form.add_child(h)
	return h


func _header(text: String) -> void:
	var l := Label.new()
	l.text = "-- " + text + " --"
	_form.add_child(l)


func _build_form() -> void:
	_header("Rule")
	var h := _row("Name")
	var ne := LineEdit.new()
	ne.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ne.text_changed.connect(_on_any)
	h.add_child(ne)
	_w["name"] = ne
	h = _row("Enabled")
	var en := CheckBox.new()
	en.toggled.connect(_on_any)
	h.add_child(en)
	_w["enabled"] = en

	_header("Conditions (all must match; leave blank to ignore)")
	for f in COND_FIELDS:
		h = _row(f["l"])
		var key: String = "c_" + f["k"]
		match f["t"]:
			"enum":
				var ob := OptionButton.new()
				for o in f["o"]:
					ob.add_item(o if o != "" else "(any)")
				ob.item_selected.connect(_on_any)
				h.add_child(ob)
				_w[key] = ob
			"multi":
				var flow := HFlowContainer.new()
				flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				var boxes: Array = []
				for o in f["o"]:
					var cb := CheckBox.new()
					cb.text = o
					cb.toggled.connect(_on_any)
					flow.add_child(cb)
					boxes.append(cb)
				h.add_child(flow)
				_w[key] = boxes
			"list", "int":
				var le := LineEdit.new()
				le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				le.text_changed.connect(_on_any)
				h.add_child(le)
				_w[key] = le
			"tri":
				var tb := OptionButton.new()
				tb.add_item("(any)")
				tb.add_item("yes")
				tb.add_item("no")
				tb.item_selected.connect(_on_any)
				h.add_child(tb)
				_w[key] = tb

	_header("Actions (blank / inherit = leave unchanged)")
	h = _row("Visibility")
	_w["a_visibility"] = _opt(h, ["(inherit)"] + LF.VISIBILITY)
	h = _row("Label colour")
	_w["a_color_on"] = _chk(h)
	_w["a_color"] = _pick_color(h, Color(1, 1, 1))
	h = _row("Label size")
	_w["a_size"] = _opt(h, ["(inherit)"] + LF.SIZES.keys())
	h = _row("Beam")
	_w["a_beam_mode"] = _opt(h, ["(inherit)", "none", "colour"])
	_w["a_beam"] = _pick_color(h, Color(1, 1, 1))
	h = _row("Sound id (blank = inherit, none = silent)")
	var se := LineEdit.new()
	se.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	se.text_changed.connect(_on_any)
	h.add_child(se)
	_w["a_sound"] = se
	h = _row("Minimap icon")
	_w["a_mm_mode"] = _opt(h, ["(inherit)", "none"] + LF.MINIMAP_SHAPES)
	_w["a_mm"] = _pick_color(h, Color(1, 1, 1))
	h = _row("Continue to later rules")
	_w["a_continue"] = _chk(h)


func _opt(parent: Node, items: Array) -> OptionButton:
	var ob := OptionButton.new()
	for i in items:
		ob.add_item(str(i))
	ob.item_selected.connect(_on_any)
	parent.add_child(ob)
	return ob


func _chk(parent: Node) -> CheckBox:
	var cb := CheckBox.new()
	cb.toggled.connect(_on_any)
	parent.add_child(cb)
	return cb


func _pick_color(parent: Node, c: Color) -> ColorPickerButton:
	var cp := ColorPickerButton.new()
	cp.color = c
	cp.custom_minimum_size = Vector2(60, 24)
	cp.color_changed.connect(_on_any)
	parent.add_child(cp)
	return cp


# ------------------------------------------------------------ form <-> rule

func _fill(idx: int) -> void:
	_loading = true
	var r: Dictionary = _filter["rules"][idx]
	_w["name"].text = str(r["name"])
	_w["enabled"].button_pressed = bool(r["enabled"])
	var c: Dictionary = r["conditions"]
	for f in COND_FIELDS:
		var k: String = f["k"]
		var wd = _w["c_" + k]
		match f["t"]:
			"enum":
				wd.select(maxi(f["o"].find(str(c.get(k, ""))), 0))
			"multi":
				for cb in wd:
					cb.button_pressed = cb.text in c.get(k, [])
			"list":
				wd.text = ", ".join(PackedStringArray(c.get(k, [])))
			"int":
				wd.text = str(c[k]) if c.has(k) else ""
			"tri":
				wd.select(0 if not c.has(k) else (1 if c[k] else 2))
	var a: Dictionary = r["actions"]
	_w["a_visibility"].select(maxi(LF.VISIBILITY.find(str(a.get("visibility", ""))) + 1, 0))
	_w["a_color_on"].button_pressed = a.has("color")
	if a.has("color") and Color.html_is_valid(str(a["color"])):
		_w["a_color"].color = Color.html(str(a["color"]))
	_w["a_size"].select(maxi(LF.SIZES.keys().find(str(a.get("size", ""))) + 1, 0))
	var bm := 0
	if a.has("beam"):
		bm = 1 if str(a["beam"]) == "none" else 2
		if bm == 2 and Color.html_is_valid(str(a["beam"])):
			_w["a_beam"].color = Color.html(str(a["beam"]))
	_w["a_beam_mode"].select(bm)
	_w["a_sound"].text = str(a.get("sound", ""))
	var mm := 0
	var m = a.get("minimap", null)
	if typeof(m) == TYPE_DICTIONARY:
		mm = 2 + maxi(LF.MINIMAP_SHAPES.find(str(m.get("shape", "circle"))), 0)
		if Color.html_is_valid(str(m.get("color", ""))):
			_w["a_mm"].color = Color.html(str(m["color"]))
	elif m != null:
		mm = 1
	_w["a_mm_mode"].select(mm)
	_w["a_continue"].button_pressed = bool(a.get("continue", false))
	_loading = false


func _collect() -> Dictionary:
	var c := {}
	for f in COND_FIELDS:
		var k: String = f["k"]
		var wd = _w["c_" + k]
		match f["t"]:
			"enum":
				if wd.selected > 0:
					c[k] = f["o"][wd.selected]
			"multi":
				var sel: Array = []
				for cb in wd:
					if cb.button_pressed:
						sel.append(cb.text)
				if sel.size() > 0:
					c[k] = sel
			"list":
				var parts: Array = []
				for p in wd.text.split(","):
					if p.strip_edges() != "":
						parts.append(p.strip_edges())
				if parts.size() > 0:
					c[k] = parts
			"int":
				var t: String = wd.text.strip_edges()
				if t.is_valid_int():
					c[k] = t.to_int()
			"tri":
				if wd.selected > 0:
					c[k] = (wd.selected == 1)
	var a := {}
	if _w["a_visibility"].selected > 0:
		a["visibility"] = LF.VISIBILITY[_w["a_visibility"].selected - 1]
	if _w["a_color_on"].button_pressed:
		a["color"] = "#" + _w["a_color"].color.to_html(false)
	if _w["a_size"].selected > 0:
		a["size"] = LF.SIZES.keys()[_w["a_size"].selected - 1]
	match _w["a_beam_mode"].selected:
		1: a["beam"] = "none"
		2: a["beam"] = "#" + _w["a_beam"].color.to_html(false)
	var snd: String = _w["a_sound"].text.strip_edges()
	if snd != "":
		a["sound"] = snd
	var mi: int = _w["a_mm_mode"].selected
	if mi == 1:
		a["minimap"] = "none"
	elif mi >= 2:
		a["minimap"] = {"shape": LF.MINIMAP_SHAPES[mi - 2], "color": "#" + _w["a_mm"].color.to_html(false)}
	if _w["a_continue"].button_pressed:
		a["continue"] = true
	return {"name": _w["name"].text, "enabled": _w["enabled"].button_pressed,
		"conditions": c, "actions": a}


func _on_any(_a = null, _b = null) -> void:
	if _loading or _sel < 0:
		return
	_filter["rules"][_sel] = _collect()
	_rule_list.set_item_text(_sel, _rule_text(_filter["rules"][_sel]))
	_update_preview()
	_dry_run()


# ---------------------------------------------------------------- rule list

func _rule_text(r: Dictionary) -> String:
	var v: String = str(r["actions"].get("visibility", ""))
	var tag := "" if v == "" else (" [" + v + "]")
	return ("" if r["enabled"] else "(off) ") + str(r["name"]) + tag


func _refresh_list() -> void:
	_rule_list.clear()
	for r in _filter["rules"]:
		_rule_list.add_item(_rule_text(r))


func _select(i: int) -> void:
	_sel = i
	_form.visible = i >= 0
	if i >= 0:
		_rule_list.select(i)
		_fill(i)
	_update_preview()


func _swap(i: int, j: int) -> void:
	var rules: Array = _filter["rules"]
	if i < 0 or j < 0 or i >= rules.size() or j >= rules.size():
		return
	var t = rules[i]
	rules[i] = rules[j]
	rules[j] = t
	_refresh_list()
	_select(j)
	_dry_run()


func _on_add() -> void:
	var at := _sel + 1
	_filter["rules"].insert(at, {"name": "New rule", "enabled": true, "conditions": {}, "actions": {"visibility": "show"}})
	_refresh_list()
	_select(at)
	_dry_run()


func _on_dup() -> void:
	if _sel < 0:
		return
	var copy: Dictionary = _filter["rules"][_sel].duplicate(true)
	copy["name"] = str(copy["name"]) + " copy"
	_filter["rules"].insert(_sel + 1, copy)
	_refresh_list()
	_select(_sel + 1)
	_dry_run()


func _on_del() -> void:
	if _sel < 0:
		return
	_filter["rules"].remove_at(_sel)
	_refresh_list()
	_select(mini(_sel, _filter["rules"].size() - 1))
	_dry_run()


func _on_up() -> void:
	_swap(_sel, _sel - 1)


func _on_down() -> void:
	_swap(_sel, _sel + 1)


# ------------------------------------------------------------ top bar actions

func _refresh_picker() -> void:
	_pick.clear()
	for n in engine.list_filters():
		_pick.add_item(str(n))
		if str(n) == engine.active_name:
			_pick.select(_pick.item_count - 1)


func _on_load() -> void:
	if _pick.item_count == 0:
		return
	if engine.load_filter(_pick.get_item_text(_pick.selected)):
		open()
		_say("Loaded " + engine.active_name)
	else:
		_say("Could not load that filter")


func _on_apply() -> void:
	engine.set_filter(_filter)
	_say("Applied. " + _problems())


func _on_save() -> void:
	var n := _save_name.text.strip_edges()
	if n == "":
		_say("Type a name in the 'save as' box first")
		return
	var err: int = engine.save_filter(n, _filter)
	if err != OK:
		_say("Save failed (names of built-in presets are reserved). Error %d" % err)
		return
	engine.set_filter(_filter)
	engine.active_name = n
	engine._write_active()
	_refresh_picker()
	_say("Saved to " + engine.user_dir_os_path() + n + ".json  " + _problems())


func _on_export() -> void:
	DisplayServer.clipboard_set(engine.export_text(_filter))
	_say("Filter JSON copied to clipboard")


func _on_import() -> void:
	var res: Dictionary = engine.import_text(DisplayServer.clipboard_get())
	if not res["ok"]:
		_say("Import failed: " + "; ".join(PackedStringArray(res["errors"])))
		return
	_filter = res["data"]
	_refresh_list()
	_select(0 if _filter["rules"].size() > 0 else -1)
	_dry_run()
	_say("Imported. Press Apply or Save to use it.")


func _problems() -> String:
	var msgs: Array = engine.validate(_filter)
	return "No problems found." if msgs.is_empty() else "; ".join(PackedStringArray(msgs))


func _say(t: String) -> void:
	_status.text = t


# ------------------------------------------------------------------ previews

func _update_preview() -> void:
	if _sel < 0 or _sel >= _filter["rules"].size():
		_preview.text = "Preview"
		return
	var a: Dictionary = _filter["rules"][_sel]["actions"]
	var col := Color(1, 1, 1)
	if a.has("color") and Color.html_is_valid(str(a["color"])):
		col = Color.html(str(a["color"]))
	var px: int = LF.SIZES.get(str(a.get("size", "normal")), 16)
	_preview.text = "Preview: Sample Item Name"
	_preview.add_theme_color_override("font_color", col)
	_preview.add_theme_font_size_override("font_size", px)


## Runs the working copy against the sample items so you see its effect at once.
func _dry_run() -> void:
	var saved: Dictionary = engine.filter
	engine.filter = engine.normalize(_filter)
	var lines: Array = []
	for it in LF.SAMPLE_ITEMS:
		var r: Dictionary = engine.evaluate(it)
		lines.append("%s: %s%s" % [it["name"], str(r["visibility"]).to_upper(),
			(" (" + str(r["rule"]) + ")") if r["rule"] != "" else ""])
	engine.filter = saved
	_dry.text = "Dry run: " + " | ".join(PackedStringArray(lines))
	_dry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
