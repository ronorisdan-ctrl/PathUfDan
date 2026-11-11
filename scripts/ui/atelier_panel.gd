extends "res://scripts/ui/base_panel.gd"
## The Atelier (Endgame Phase 3B): the board of zone rules that replaced the Varnish slots.
## Six wedges (one per painting layer), six nodes each from the hub outward: 3 small, a choice
## (pick 1 of 3), a notable and a rule-changer tip. Hover or click a node for its bonus (green) and
## cost (red); take or refund it on the right. Free respec. Opened from the Atlas and the Easel.

const Chrome = preload("res://scripts/ui/components/station_chrome.gd")
const AtlasRules = preload("res://scripts/core/atlas_rules.gd")
const AtelierRules = preload("res://scripts/core/atelier_rules.gd")

const KIND_LABEL := {"small": "Small", "choice": "Choice", "notable": "Notable", "tip": "Rule-changer"}
const STATUS_COLOR := {"taken": Color("#80e080"), "open": Color("#e8d8a0"), "poor": Color("#a89a7a"), "locked": Color("#6a6470"), "3c": Color("#5a5a62")}

var points_label: RichTextLabel
var grid: GridContainer
var detail: RichTextLabel
var actions: VBoxContainer
var node_buttons := {}   # node id -> Button
var focus := ""           # node shown in the detail column

func _init() -> void:
	place = "center"
	build("The Atelier", Vector2(1180, 560))
	Chrome.apply(self)
	points_label = UIKit.rich()
	points_label.fit_content = true
	body.add_child(points_label)
	var h := HBoxContainer.new()
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_theme_constant_override("separation", 12)
	body.add_child(h)
	grid = GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_stretch_ratio = 2.6
	h.add_child(grid)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.custom_minimum_size = Vector2(280, 0)
	h.add_child(right)
	var sc := Chrome.reading_scroll(right, 330)
	detail = UIKit.rich()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(detail)
	actions = VBoxContainer.new()
	right.add_child(actions)
	var hb := HBoxContainer.new()
	hb.add_child(UIKit.button("Respec all (free)", _respec))
	hb.add_child(UIKit.button("Easel", func(): ui.toggle("easel")))
	hb.add_child(UIKit.button("Back to the Atlas", func(): ui.toggle("atlas")))
	body.add_child(hb)
	_build_grid()

func reposition() -> void:
	Chrome.place_panel(self, Vector2(1240, 640))

func state() -> Dictionary:
	if Game.ch == null or not AtlasRules.unlocked(Game.ch):
		return {}
	return AtlasRules.ensure(Game.ch)

## One column per wedge: header, then its nodes from the hub outward.
func _build_grid() -> void:
	for w in AtelierRules.wedges():
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 4)
		# plain Labels: a fit_content RichTextLabel in a narrow column wraps per letter and grows very tall
		var head := UIKit.label(str(w.get("name", "")), 15, Color(str(w.get("color", "#e8d8a0"))))
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(head)
		var sub := UIKit.label(str(w.get("theme", "")), 11, UIKit.MUTED)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.clip_text = true
		col.add_child(sub)
		for n in w.get("nodes", []):
			var id := str(n.get("id", ""))
			var b := Button.new()
			b.text = str(n.get("name", id))
			b.clip_text = true
			b.custom_minimum_size = Vector2(140, 34 if str(n.get("kind", "")) in ["small", "choice"] else 42)
			b.add_theme_font_size_override("font_size", 13)
			b.tooltip_text = _plain_tooltip(n)
			b.pressed.connect(func(): _focus(id))
			b.mouse_entered.connect(func(): _show(id))
			col.add_child(b)
			node_buttons[id] = b
		grid.add_child(col)

## Plain-text tooltip (Godot tooltips have no colour; the detail column has the coloured version).
func _plain_tooltip(n: Dictionary) -> String:
	var t := "%s (%s, %d point%s)" % [str(n.get("name", "")), KIND_LABEL.get(str(n.get("kind", "")), ""), AtelierRules.cost_of(n), "" if AtelierRules.cost_of(n) == 1 else "s"]
	if n.has("bonus"):
		t += "\n+ " + str(n["bonus"])
	if n.has("cost"):
		t += "\n- " + str(n["cost"])
	for o in n.get("options", []):
		t += "\n(%s) %s: %s" % [str(o.get("id", "")), str(o.get("name", "")), str(o.get("bonus", ""))]
	if n.get("needs_3c", false):
		t += "\nArrives with the Burning Canvas and the Pigment Wells (Phase 3C)."
	return t

func on_open() -> void:
	refresh()

func refresh() -> void:
	var st := state()
	if st.is_empty():
		points_label.text = "[color=#ff8080]Locked - %s[/color]" % str(AtlasRules.cfg().get("unlock_text", ""))
		return
	var pc: Dictionary = AtelierRules.cfg().get("points", {})
	points_label.text = "[color=#e8d8a0]Points: %d spent of %d[/color]   [color=#80e080]%d free[/color]   [color=#8a8494](%d from first clears of ring %d+ regions, max %d; %d from Layer Wardens; up to %d in all)[/color]" % [
		AtelierRules.points_spent(st), AtelierRules.points_total(st), AtelierRules.points_free(st),
		AtelierRules.region_points(st), int(pc.get("region_min_ring", 2)), int(pc.get("region_cap", 18)),
		AtelierRules.warden_points(st, AtelierRules.taken(st), AtelierRules.state(st)["choices"]), AtelierRules.points_max(st)]
	for id in node_buttons:
		var b: Button = node_buttons[id]
		var status := AtelierRules.node_status(st, id)
		b.modulate = STATUS_COLOR.get(status, Color.WHITE)
		var n := AtlasRules.atelier_node(id)
		var label := str(n.get("name", id))
		if status == "taken" and str(n.get("kind", "")) == "choice":
			label += ": " + str(AtlasRules.atelier_option(n, AtelierRules.choice_of(st, id)).get("name", ""))
		b.text = ("* " if status == "taken" else "") + label
	if focus == "":
		_show_intro()
	else:
		_show(focus)

func _show_intro() -> void:
	detail.text = "[color=#e8d8a0]The Atelier[/color]\n[color=#8a8494]Each wedge edits one family of zone rules. Take its small nodes from the hub in any order; the choice node needs %d of them, the notable needs the choice, and the rule-changer at the tip needs the notable. Nodes change zones only, never your character. Respec is free.\n\nGreen: taken. Gold: can take. Dim: path or points missing. Grey: arrives in Phase 3C.\n\nHover a node to read it; click it to take or refund it.[/color]" % int(AtelierRules.cfg().get("choice_needs", 2))
	_clear_actions()

func _focus(id: String) -> void:
	focus = id
	_show(id)

## Detail column: bonus in green, cost in red, status and actions (actions only for the focused node).
func _show(id: String) -> void:
	var st := state()
	if st.is_empty():
		return
	var n := AtlasRules.atelier_node(id)
	if n.is_empty():
		return
	var status := AtelierRules.node_status(st, id)
	var lines := []
	lines.append("[font_size=17][color=#e8c890]%s[/color][/font_size]" % str(n.get("name", id)))
	lines.append("[color=#8a8494]%s - %s, %d point%s[/color]" % [str(_wedge_name(str(n.get("wedge", "")))), KIND_LABEL.get(str(n.get("kind", "")), ""), AtelierRules.cost_of(n), "" if AtelierRules.cost_of(n) == 1 else "s"])
	if n.has("bonus"):
		lines.append("[color=#80e080]+ %s[/color]" % str(n["bonus"]))
	if n.has("cost"):
		lines.append("[color=#ff7070]- %s[/color]" % str(n["cost"]))
	if str(n.get("kind", "")) == "choice":
		lines.append("[color=#8a8494]Pick one (change it with a refund or respec):[/color]")
		var cur := AtelierRules.choice_of(st, id)
		for o in n.get("options", []):
			var mark := "[color=#80e080](picked)[/color] " if status == "taken" and str(o.get("id", "")) == cur else ""
			var gate := "  [color=#6a6470](Phase 3C)[/color]" if o.get("needs_3c", false) else ""
			lines.append("%s[color=#e8d8a0]%s[/color]: [color=#80e080]%s[/color]%s" % [mark, str(o.get("name", "")), str(o.get("bonus", "")), gate])
	match status:
		"taken":
			lines.append("[color=#80e080]Taken.[/color]")
		"3c":
			lines.append("[color=#8a8494]Arrives with the Burning Canvas and the Pigment Wells (Phase 3C).[/color]")
		"locked":
			var ids: Array = AtelierRules.taken(st).duplicate()
			ids.append(id)
			lines.append("[color=#ff9070]%s.[/color]" % AtelierRules.path_refusal(ids, id))
		"poor":
			lines.append("[color=#ff9070]Not enough free points.[/color]")
	detail.text = "\n".join(lines)
	if id == focus:
		_build_actions(st, n, status)

func _wedge_name(wid: String) -> String:
	for w in AtelierRules.wedges():
		if str(w.get("id", "")) == wid:
			return str(w.get("name", wid))
	return wid

func _clear_actions() -> void:
	for c in actions.get_children():
		actions.remove_child(c)
		c.queue_free()

func _build_actions(st: Dictionary, n: Dictionary, status: String) -> void:
	_clear_actions()
	var id := str(n.get("id", ""))
	if status == "taken":
		var why := AtelierRules.refund_refusal(st, id)
		var b := UIKit.button("Refund", func(): _act(AtelierRules.refund(state(), id), "Refunded %s" % str(n.get("name", id))))
		b.disabled = why != ""
		b.tooltip_text = why
		actions.add_child(b)
		return
	if str(n.get("kind", "")) == "choice":
		for o in n.get("options", []):
			var opt := str(o.get("id", ""))
			var why := AtelierRules.take_refusal(st, id, opt)
			var b := UIKit.button("Take: %s" % str(o.get("name", opt)), func(): _act(AtelierRules.take(state(), id, opt), "Took %s: %s" % [str(n.get("name", id)), str(o.get("name", opt))]))
			b.disabled = why != ""
			b.tooltip_text = why
			actions.add_child(b)
		return
	var why2 := AtelierRules.take_refusal(st, id)
	var tb := UIKit.button("Take (%d point%s)" % [AtelierRules.cost_of(n), "" if AtelierRules.cost_of(n) == 1 else "s"], func(): _act(AtelierRules.take(state(), id), "Took %s" % str(n.get("name", id))))
	tb.disabled = why2 != ""
	tb.tooltip_text = why2
	actions.add_child(tb)

func _act(ok: bool, msg: String) -> void:
	if ui != null and ok and msg != "":
		ui.toast(msg, Color("#e8d8a0"))
	if ok:
		Game.save_game()
	refresh()
	if ui != null and ui.is_open("atlas"):
		ui.panels["atlas"].refresh()

func _respec() -> void:
	var st := state()
	if st.is_empty():
		return
	var n := AtelierRules.respec(st)
	focus = ""
	_act(true, "Respec: %d point%s back" % [n, "" if n == 1 else "s"])
