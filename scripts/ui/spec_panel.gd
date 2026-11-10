extends "res://scripts/ui/base_panel.gd"
## Class specialisation: pick one of your class's archetypes (from level 12),
## then spend specialisation points (levels 12/20/28/36/44) on its node path.

const Chrome = preload("res://scripts/ui/components/panel_chrome.gd")

var info: RichTextLabel
var area: GridContainer
var chooser_scroll: ScrollContainer
var graph_frame: PanelContainer
var reset_btn: Button

class SpecGraph extends Control:
	var spec := {}
	var panel = null
	var hover := ""
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
	func _pos(n: Dictionary) -> Vector2:
		return Vector2(size.x / 2 + float(n["x"]) * 1.4, 40 + float(n["y"]) * 1.25)
	func _node_at(m: Vector2) -> String:
		for n in spec.get("nodes", []):
			if _pos(n).distance_to(m) < 22:
				return n["id"]
		return ""
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			var h := _node_at(event.position)
			if h != hover:
				hover = h
				if h != "":
					panel.ui.show_tooltip(panel.node_tooltip(h))
				else:
					panel.ui.hide_tooltip()
				queue_redraw()
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var id := _node_at(event.position)
			if id != "":
				panel.try_alloc(id)
	func _draw() -> void:
		var ch = Game.ch
		var col := Color(spec.get("color", "#ffffff"))
		var nodes: Array = spec.get("nodes", [])
		for n in nodes:
			for r in n.get("req", []):
				var m: Dictionary = Data.spec_nodes.get(r, {})
				if m.is_empty():
					continue
				var both: bool = ch.spec_nodes.has(r) and ch.spec_nodes.has(n["id"])
				draw_line(_pos(m), _pos(n), col if both else Color(0.3, 0.28, 0.26), 4.0 if both else 2.0)
		var f := ThemeDB.fallback_font
		for n in nodes:
			var p := _pos(n)
			var alloc: bool = ch.spec_nodes.has(n["id"])
			var can: bool = ch.can_alloc_spec(n["id"]) == ""
			var r := 20.0 if n.get("capstone", false) else 15.0
			draw_circle(p, r, col.darkened(0.2) if alloc else Color(0.1, 0.1, 0.12))
			var ring := col.lightened(0.3) if alloc else (Color(0.4, 1.0, 0.4) if can else Color(0.35, 0.32, 0.3))
			draw_arc(p, r, 0, TAU, 28, ring, 3.0 if n["id"] == hover else 2.0)
			var w := f.get_string_size(n["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			draw_string_outline(f, p + Vector2(-w / 2, r + 15), n["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color.BLACK)
			draw_string(f, p + Vector2(-w / 2, r + 15), n["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#e8d8b0") if alloc else UIKit_text())
	func UIKit_text() -> Color:
		return Color("#a8a0b0")

var graph: SpecGraph

func _init() -> void:
	place = "center"
	build("Specialisation", Vector2(940, 620))
	Chrome.apply(self)
	info = UIKit.rich()
	body.add_child(info)
	chooser_scroll = ScrollContainer.new()
	Chrome.scroll_inset(chooser_scroll)
	chooser_scroll.custom_minimum_size.y = 200
	body.add_child(chooser_scroll)
	area = GridContainer.new()
	area.columns = 3
	area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	area.add_theme_constant_override("h_separation", 8)
	area.add_theme_constant_override("v_separation", 8)
	chooser_scroll.add_child(area)
	graph_frame = Chrome.Cabinet.inset()
	graph_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(graph_frame)
	graph = SpecGraph.new()
	graph.panel = self
	graph.custom_minimum_size = Vector2(600, 380)
	graph_frame.add_child(graph)
	reset_btn = UIKit.button("Reset specialisation", _reset)
	body.add_child(reset_btn)
	Events.passive_changed.connect(refresh)
	Events.player_leveled.connect(func(_l): refresh())

func reposition() -> void:
	Chrome.place_panel(self, Vector2(940, 620))

func refresh() -> void:
	var ch = Game.ch
	if ch == null or not visible:
		return
	for c in area.get_children():
		area.remove_child(c)
		c.queue_free()
	var specs: Array = Data.specs_for_class(ch.class_id)
	if ch.spec_id == "":
		graph_frame.visible = false
		reset_btn.visible = false
		chooser_scroll.visible = true
		var lock := "" if ch.level >= ch.SPEC_LEVELS[0] else "[color=#ff8080]Unlocks at level %d (you are level %d).[/color] " % [ch.SPEC_LEVELS[0], ch.level]
		info.text = "[font_size=15]Choose a specialisation for your %s.[/font_size]\n%sYou gain a specialisation point at levels 12, 20, 28, 36 and 44. Only one capstone can be taken." % [ch.class_def()["name"], lock]
		for sp in specs:
			var card := Chrome.Cabinet.inset()
			card.custom_minimum_size = Vector2(0, 190)
			card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var v := VBoxContainer.new()
			card.add_child(v)
			var title := UIKit.label(sp["name"], 17, Color(sp["color"]))
			title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_child(title)
			var d := UIKit.label(sp["desc"], 12, Chrome.Cabinet.MUTED)
			d.autowrap_mode = TextServer.AUTOWRAP_WORD
			d.size_flags_vertical = Control.SIZE_EXPAND_FILL
			v.add_child(d)
			var caps := []
			for n in sp["nodes"]:
				if n.get("capstone", false):
					caps.append(n["name"])
			var cl := UIKit.label("Capstones: " + ", ".join(caps), 12, UIKit.GOLD)
			cl.autowrap_mode = TextServer.AUTOWRAP_WORD
			v.add_child(cl)
			var b := UIKit.button("Choose", _choose.bind(sp["id"]))
			b.tooltip_text = "Choose " + sp["name"]
			b.disabled = ch.level < ch.SPEC_LEVELS[0]
			v.add_child(b)
			area.add_child(card)
	else:
		chooser_scroll.visible = false
		graph_frame.visible = true
		reset_btn.visible = true
		var sp: Dictionary = Data.specs[ch.spec_id]
		graph.spec = sp
		graph.queue_redraw()
		info.text = "[font_size=17][color=%s]%s[/color][/font_size]  -  %s\nPoints available: [color=#80ff80]%d[/color] of %d.  Click a highlighted node to allocate." % [sp["color"], sp["name"], sp["desc"], ch.spec_points_available(), ch.spec_points_total()]
		reset_btn.text = "Reset specialisation (%d gold)" % ch.spec_reset_cost()

func node_tooltip(id: String) -> String:
	var ch = Game.ch
	var n: Dictionary = Data.spec_nodes[id]
	var lines := ["[font_size=16][color=#e8c890]%s[/color][/font_size]%s" % [n["name"], "  [color=#ffb060](Capstone)[/color]" if n.get("capstone", false) else ""]]
	for m in n.get("mods", []):
		lines.append("[color=#8ab8ff]%s[/color]" % Loot.mod_text(m))
	if n.get("desc", "") != "":
		lines.append("[color=#ffb060]%s[/color]" % n["desc"])
	if ch.spec_nodes.has(id):
		lines.append("[color=#80e080]Allocated[/color]")
	else:
		var why: String = ch.can_alloc_spec(id)
		lines.append("[color=#80e080]Click to allocate[/color]" if why == "" else "[color=#ff8080]%s[/color]" % why)
	return "\n".join(lines)

func try_alloc(id: String) -> void:
	var why: String = Game.ch.can_alloc_spec(id)
	if why != "":
		ui.toast(why, UIKit.BAD)
		return
	Game.ch.alloc_spec(id)
	ui.hide_tooltip()

func _choose(id: String) -> void:
	var sp: Dictionary = Data.specs[id]
	ui.ask("Become a [color=%s]%s[/color]?\n%s\n(You can reset later for gold.)" % [sp["color"], sp["name"], sp["desc"]], func():
		var e: String = Game.ch.choose_spec(id)
		if e != "":
			ui.toast(e, UIKit.BAD))

func _reset() -> void:
	ui.ask("Reset your specialisation for %d gold? All specialisation points are refunded." % Game.ch.spec_reset_cost(), func():
		var e: String = Game.ch.reset_spec()
		if e != "":
			ui.toast(e, UIKit.BAD))
