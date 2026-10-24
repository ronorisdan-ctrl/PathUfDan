extends Control
## Renders and handles input for the passive tree.

const UIKit = preload("res://scripts/ui/ui_kit.gd")
const RADIUS := {"start": 18.0, "minor": 9.0, "notable": 13.0, "greater": 15.0, "keystone": 21.0}
const TYPE_NAMES := {"start": "Class Start", "minor": "Minor Node", "notable": "Specialised Node", "greater": "Greater Node", "keystone": "Keystone"}

var panel = null
var zoom := 0.55
var offset := Vector2.ZERO
var dragging := false
var drag_from := Vector2.ZERO
var drag_moved := 0.0
var hover := ""
var t := 0.0
var search := ""
var _cluster_centres := {}

func cluster_centres() -> Dictionary:
	## centroid of every named cluster (labels drawn behind the web)
	if _cluster_centres.is_empty():
		var acc := {}
		for n in Data.passive_list:
			var c: String = n.get("cluster", "")
			if c == "" or c == "Origins" or c == "Wanderer's Road":
				continue
			if not acc.has(c):
				acc[c] = [Vector2.ZERO, 0]
			acc[c][0] += node_pos(n)
			acc[c][1] += 1
		for c in acc:
			_cluster_centres[c] = acc[c][0] / float(acc[c][1])
	return _cluster_centres

func matches_search(n: Dictionary) -> bool:
	if search.length() < 2:
		return false
	var q := search.to_lower()
	if String(n.get("name", "")).to_lower().contains(q) or String(n.get("desc", "")).to_lower().contains(q) or String(n.get("cluster", "")).to_lower().contains(q):
		return true
	for m in n.get("mods", []):
		if Loot.mod_text(m).to_lower().contains(q):
			return true
	return false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true

func _process(delta: float) -> void:
	if is_visible_in_tree():
		t += delta
		queue_redraw()

func to_screen(p: Vector2) -> Vector2:
	return size / 2 + offset + p * zoom

func node_pos(n: Dictionary) -> Vector2:
	return Vector2(float(n["x"]), float(n["y"]))

func center_on_class() -> void:
	var ch = Game.ch
	if ch == null:
		return
	var sn: Dictionary = Data.passives.get(ch.class_def().get("start_passive", ""), {})
	zoom = 0.8
	if not sn.is_empty():
		offset = -node_pos(sn) * zoom * 0.85
	queue_redraw()

func fit() -> void:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for n in Data.passive_list:
		var p := node_pos(n)
		mn = Vector2(minf(mn.x, p.x), minf(mn.y, p.y))
		mx = Vector2(maxf(mx.x, p.x), maxf(mx.y, p.y))
	var span := mx - mn + Vector2(120, 120)
	zoom = clampf(minf(size.x / span.x, size.y / span.y), 0.15, 1.6)
	offset = -(mn + mx) / 2 * zoom
	queue_redraw()

func _node_at(m: Vector2) -> String:
	for n in Data.passive_list:
		var r: float = RADIUS.get(n["type"], 10.0) * maxf(zoom, 0.5) + 3
		if to_screen(node_pos(n)).distance_to(m) <= r:
			return n["id"]
	return ""

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(event.position, 1.12)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(event.position, 1.0 / 1.12)
		elif event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if event.pressed:
				dragging = true
				drag_from = event.position
				drag_moved = 0.0
			else:
				dragging = false
				if drag_moved < 6.0:
					_click(event.button_index, event.position)
		accept_event()
	elif event is InputEventMouseMotion:
		if dragging:
			offset += event.relative
			drag_moved += event.relative.length()
		var h := _node_at(event.position)
		if h != hover:
			hover = h
			if h != "":
				panel.ui.show_tooltip(node_tooltip(h))
			else:
				panel.ui.hide_tooltip()
		accept_event()

func _zoom_at(p: Vector2, f: float) -> void:
	var nz := clampf(zoom * f, 0.15, 1.8)
	var world := (p - size / 2 - offset) / zoom
	zoom = nz
	offset = p - size / 2 - world * zoom

func _click(button: int, pos: Vector2) -> void:
	var id := _node_at(pos)
	if id == "":
		return
	var ch = Game.ch
	var n: Dictionary = Data.passives[id]
	if button == MOUSE_BUTTON_LEFT:
		var why: String = ch.can_allocate(id)
		if why == "Must connect to an allocated node":
			var path: Array = ch.path_to(id)
			var cost: int = ch.path_cost(path)
			if path.is_empty():
				panel.ui.toast("No route to that node", UIKit.BAD)
			elif cost > ch.available_passive_points():
				panel.ui.toast("That route needs %d points (you have %d)" % [cost, ch.available_passive_points()], UIKit.BAD)
			else:
				panel.ui.ask("Allocate the %d-node route to [color=#e8c890]%s[/color]?%s" % [path.size(), n["name"], ("\n" + n.get("desc", "")) if n["type"] == "keystone" else ""], func():
					if ch.allocate_path(id):
						hover = ""
						panel.ui.hide_tooltip())
			return
		if why != "":
			panel.ui.toast(why, UIKit.BAD)
			return
		if n["type"] == "keystone":
			panel.ui.ask("Allocate keystone [color=#ffb060]%s[/color]?\n%s" % [n["name"], n.get("desc", "")], func(): _do_alloc(id))
		else:
			_do_alloc(id)
	elif button == MOUSE_BUTTON_RIGHT:
		var why2: String = ch.can_refund(id)
		if why2 != "":
			panel.ui.toast(why2, UIKit.BAD)
			return
		panel.ui.ask("Refund [color=#e8c890]%s[/color] for %d gold?" % [n["name"], ch.refund_cost()], func(): ch.refund(id))

func _do_alloc(id: String) -> void:
	if Game.ch.allocate(id):
		hover = ""
		panel.ui.hide_tooltip()

func node_tooltip(id: String) -> String:
	var ch = Game.ch
	var n: Dictionary = Data.passives[id]
	var lines := []
	var tcol := "ffb060" if n["type"] == "keystone" else ("e8c890" if n["type"] in ["greater", "notable"] else "d0d0d0")
	lines.append("[font_size=16][color=#%s]%s[/color][/font_size]" % [tcol, n["name"]])
	lines.append("[color=#8a8494]%s - Cost %d point%s%s[/color]" % [TYPE_NAMES.get(n["type"], ""), int(n.get("cost", 1)), "s" if int(n.get("cost", 1)) != 1 else "", ("  -  " + n["cluster"]) if n.get("cluster", "") not in ["", "Origins"] else ""])
	for m in n.get("mods", []):
		lines.append("[color=#8ab8ff]%s[/color]" % Loot.mod_text(m))
	if n.get("desc", "") != "" and n["type"] != "start":
		lines.append("[color=#ffb060]%s[/color]" % n["desc"])
	if n.has("class"):
		lines.append("[color=#8a8494]Starting point of the %s[/color]" % Data.classes[n["class"]]["name"])
	var allocated: bool = ch.allocated.has(id)
	var ids: Array = ch.allocated.duplicate()
	if allocated:
		ids.erase(id)
	else:
		ids.append(id)
	if n["type"] != "start":
		var a: Dictionary = ch.final
		var b: Dictionary = ch.preview_final(ids)
		var diff := []
		for k in [["max_life", "Life"], ["max_mana", "Mana"], ["armour", "Armour"], ["evasion", "Evasion"], ["block_chance", "Block %"], ["move_speed", "Move speed"], ["mana_regen", "Mana regen"], ["life_regen", "Life regen"]]:
			var d: float = float(b.get(k[0], 0)) - float(a.get(k[0], 0))
			if absf(d) >= 0.1:
				diff.append("[color=#%s]%s%s %s[/color]" % ["80e080" if d > 0 else "ff6060", "+" if d > 0 else "", UIKit.fmt(d, 1 if absf(d) < 10 else 0), k[1]])
		for i in 2:
			var sid: String = ch.loadout[i]
			if sid == "":
				continue
			var s0: float = ch.preview_skill_avg(sid, ch.allocated)
			var s1: float = ch.preview_skill_avg(sid, ids)
			if s0 > 0 and absf(s1 - s0) / s0 > 0.002:
				var pct := (s1 / s0 - 1.0) * 100.0
				diff.append("[color=#%s]%s%.1f%% %s damage[/color]" % ["80e080" if pct > 0 else "ff6060", "+" if pct > 0 else "", pct, Data.skills[sid]["name"]])
		if diff.size() > 0:
			lines.append("")
			lines.append("[color=#c8a060]%s:[/color]" % ("If refunded" if allocated else "If allocated"))
			lines.append_array(diff)
	lines.append("")
	if allocated:
		var r: String = ch.can_refund(id) if n["type"] != "start" else "Starting point"
		lines.append("[color=#80e080]Allocated[/color]" + ("" if r == "" else "  [color=#8a8494](%s)[/color]" % r))
	else:
		var why: String = ch.can_allocate(id)
		if why == "Must connect to an allocated node":
			var path: Array = ch.path_to(id)
			if not path.is_empty():
				var pc: int = ch.path_cost(path)
				lines.append(("[color=#80c8ff]Click to allocate the route: %d points[/color]" if pc <= ch.available_passive_points() else "[color=#ff8080]Route needs %d points[/color]") % pc)
			else:
				lines.append("[color=#ff8080]No route[/color]")
		else:
			lines.append("[color=#80e080]Click to allocate[/color]" if why == "" else "[color=#ff8080]%s[/color]" % why)
	return "\n".join(lines)

func _draw() -> void:
	var ch = Game.ch
	if ch == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.03, 0.04))
	# faint concentric guides
	for r in [200, 420, 640, 860, 1130]:
		draw_arc(to_screen(Vector2.ZERO), r * zoom, 0, TAU, 64, Color(1, 1, 1, 0.03), 1.0)
	var f0 := ThemeDB.fallback_font
	var cc := cluster_centres()
	var fs := int(clampf(30.0 * zoom, 11.0, 22.0))
	for c in cc:
		var cp := to_screen(cc[c])
		var cw := f0.get_string_size(c, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f0, cp + Vector2(-cw / 2, fs * 0.35), c, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.85, 0.75, 0.55, 0.16))
	var alloc := {}
	for id in ch.allocated:
		alloc[id] = true
	var pts: int = ch.available_passive_points()
	# links
	for n in Data.passive_list:
		var a := to_screen(node_pos(n))
		for l in n.get("links", []):
			if l < n["id"]:
				continue
			var m: Dictionary = Data.passives.get(l, {})
			if m.is_empty():
				continue
			var b := to_screen(node_pos(m))
			var both: bool = alloc.has(n["id"]) and alloc.has(l)
			var one: bool = alloc.has(n["id"]) or alloc.has(l)
			var col := Color(0.25, 0.22, 0.2) if not one else (Color("#c8a060") if both else Color(0.55, 0.5, 0.4))
			draw_line(a, b, col, (4.0 if both else 2.0) * maxf(zoom, 0.5))
	# route preview for the hovered node
	var route := {}
	if hover != "" and not alloc.has(hover):
		var rp: Array = ch.path_to(hover)
		if rp.size() > 1:
			for i in rp.size():
				route[rp[i]] = true
			var prevp := Vector2.INF
			for l in Data.passives[rp[0]]["links"]:
				if alloc.has(l):
					prevp = to_screen(node_pos(Data.passives[l]))
					break
			for id2 in rp:
				var q := to_screen(node_pos(Data.passives[id2]))
				if prevp != Vector2.INF:
					draw_line(prevp, q, Color(0.5, 0.8, 1.0, 0.7), 3.0 * maxf(zoom, 0.5))
				prevp = q
	# nodes
	var f := ThemeDB.fallback_font
	for n in Data.passive_list:
		var p := to_screen(node_pos(n))
		if p.x < -40 or p.y < -40 or p.x > size.x + 40 or p.y > size.y + 40:
			continue
		var r: float = RADIUS.get(n["type"], 10.0) * maxf(zoom, 0.5)
		var id: String = n["id"]
		var is_alloc: bool = alloc.has(id)
		var connected := false
		for l in n.get("links", []):
			if alloc.has(l):
				connected = true
		var can: bool = not is_alloc and connected and n["type"] != "start"
		var affordable: bool = int(n.get("cost", 1)) <= pts
		var fill := Color(0.12, 0.11, 0.12)
		var ring := Color(0.35, 0.32, 0.3)
		if is_alloc:
			fill = Color("#8a6a30")
			ring = Color("#ffd070")
		elif can and affordable:
			var pulse := 0.6 + 0.4 * sin(t * 4.0)
			ring = Color(0.4, 1.0, 0.4).lerp(Color.WHITE, 0.2 * pulse)
			fill = Color(0.12, 0.2, 0.12)
		elif can:
			ring = Color(0.8, 0.35, 0.3)
		if n["type"] == "keystone":
			var pts2 := PackedVector2Array()
			for i in 8:
				pts2.append(p + Vector2.RIGHT.rotated(TAU * i / 8.0 + PI / 8) * r)
			draw_colored_polygon(pts2, fill)
			pts2.append(pts2[0])
			draw_polyline(pts2, ring, 3.0)
		elif n["type"] == "start":
			var c := Color(Data.classes.get(n.get("class", ""), {}).get("color", "#888888"))
			draw_circle(p, r, c.darkened(0.4) if not is_alloc else c)
			draw_arc(p, r, 0, TAU, 32, ring, 3.0)
			var nm: String = Data.classes.get(n.get("class", ""), {}).get("name", "")
			var w := f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			draw_string_outline(f, p + Vector2(-w / 2, r + 16), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 3, Color.BLACK)
			draw_string(f, p + Vector2(-w / 2, r + 16), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, c.lightened(0.3))
		else:
			draw_circle(p, r, fill)
			draw_arc(p, r, 0, TAU, 24, ring, 2.5 if n["type"] != "minor" else 1.5)
			if n["type"] in ["greater", "notable"]:
				draw_arc(p, r - 4, 0, TAU, 20, Color(ring.r, ring.g, ring.b, 0.5), 1.0)
		if id == hover:
			draw_arc(p, r + 4, 0, TAU, 24, Color.WHITE, 1.5)
		elif route.has(id):
			draw_arc(p, r + 3, 0, TAU, 20, Color(0.5, 0.8, 1.0, 0.8), 1.5)
		if matches_search(n):
			draw_arc(p, r + 7, 0, TAU, 24, Color(1.0, 0.85, 0.2, 0.6 + 0.4 * sin(t * 6.0)), 2.5)
		if zoom > 0.7 and n["type"] in ["greater", "keystone"]:
			var w2 := f.get_string_size(n["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			draw_string_outline(f, p + Vector2(-w2 / 2, -r - 6), n["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color.BLACK)
			draw_string(f, p + Vector2(-w2 / 2, -r - 6), n["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#e8c890") if n["type"] == "greater" else Color("#ffb060"))
	# legend
	var ly := size.y - 70
	var items := [[Color("#ffd070"), "Allocated"], [Color(0.4, 1.0, 0.4), "Available"], [Color(0.8, 0.35, 0.3), "Connected, not enough points"], [Color(0.35, 0.32, 0.3), "Locked"]]
	for i in items.size():
		draw_arc(Vector2(20, ly + i * 16), 5, 0, TAU, 12, items[i][0], 2.0)
		draw_string(f, Vector2(32, ly + i * 16 + 5), items[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIKit.MUTED)
