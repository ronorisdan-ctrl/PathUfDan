extends Control
## Renders and handles input for the passive tree.

const UIKit = preload("res://scripts/ui/ui_kit.gd")
const TreeRules = preload("res://scripts/core/tree_rules.gd")
const RADIUS := {"start": 18.0, "minor": 9.0, "notable": 13.0, "greater": 15.0, "keystone": 21.0, "mastery": 15.0, "socket": 14.0}
const TYPE_NAMES := {"start": "Class Start", "minor": "Minor Node", "notable": "Specialised Node", "greater": "Greater Node", "keystone": "Keystone", "mastery": "Mastery", "socket": "Gem Socket"}
const MASTERY_COL := Color("#60d0c0")
const SOCKET_COL := Color("#c080ff")
const REFUND_COL := Color("#60b8e0")
const BG := Color(0.03, 0.03, 0.04)

## ---- Codex V5 contract (Phase 5a, docs/TREE_UI_CONTRACT.md) ----
## Base state of a node: exactly one per node. V5 replaces how each state is drawn, not
## how it is decided. PLANNED is reserved for the Phase 5b planner.
enum NodeState {LOCKED, AVAILABLE, UNAVAILABLE, ALLOCATED, PLANNED, MIGRATED_REFUNDED}
const STATE_NAMES := ["locked", "available", "unavailable", "allocated", "planned", "migrated_refunded"]
## Overlays stack on top of the base state (node_overlays): search_hit, filtered_out,
## boosted (gem socket ring), route (hover route preview), hover, lod_hidden.

## Zoom levels of detail: below LOD_FAR only cluster labels, class starts, keystones and
## allocated nodes; below LOD_NEAR notables/greater/masteries/sockets join and minors are
## small dots; from LOD_NEAR up, everything with labels.
const LOD_FAR := 0.35
const LOD_NEAR := 0.7
const ZOOM_MIN := 0.15
const ZOOM_MAX := 1.8
## Tag chips shown in the panel's filter row; every other used tag is in its "More" list.
const FILTER_CHIPS := ["fire", "cold", "lightning", "physical", "void", "crit", "ailment", "melee", "projectile", "spell", "minion", "trap"]
const MINIMAP_SIZE := Vector2(190, 140)

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
var tag_filter := {}          # tag -> true; a node matches if it has any of them
var behaviour_only := false   # also require TreeRules.is_behaviour_node
var show_minimap := true
var planned := {}             # extra ghost ids (tests/tools); the planner itself uses Game.ch.plan
var planner := false          # Phase 5b: clicks plan ghost nodes instead of spending points
const PLAN_COL := Color(0.55, 0.65, 1.0)
var hit_index := -1
var _bounds := Rect2()

func lod() -> int:
	## 0 far, 1 mid, 2 near
	return 0 if zoom < LOD_FAR else (1 if zoom < LOD_NEAR else 2)

func filter_active() -> bool:
	return not tag_filter.is_empty() or behaviour_only

func passes_filter(n: Dictionary) -> bool:
	if behaviour_only and not TreeRules.is_behaviour_node(n):
		return false
	if tag_filter.is_empty():
		return true
	for tg in n.get("tags", []):
		if tag_filter.has(tg):
			return true
	return false

func set_tag(tag: String, on: bool) -> void:
	if on:
		tag_filter[tag] = true
	else:
		tag_filter.erase(tag)
	queue_redraw()

func clear_filters() -> void:
	tag_filter = {}
	behaviour_only = false
	queue_redraw()

func refunded_ids() -> Dictionary:
	var out := {}
	if Game.ch != null:
		for id in Game.ch.tree_refund.get("ids", []):
			out[str(id)] = true
	return out

func _alloc_set() -> Dictionary:
	var a := {}
	for id in Game.ch.allocated:
		a[id] = true
	return a

## Base state of node id (NodeState). The Codex V5 art keys off this.
func node_state(id: String) -> int:
	return _state(Data.passives[id], _alloc_set(), Game.ch.available_passive_points(), refunded_ids())

func _state(n: Dictionary, alloc: Dictionary, pts: int, refunded: Dictionary) -> int:
	var id: String = n["id"]
	if alloc.has(id):
		return NodeState.ALLOCATED
	if planned.has(id) or Game.ch.plan_has(id):
		return NodeState.PLANNED
	if refunded.has(id):
		return NodeState.MIGRATED_REFUNDED
	if n["type"] == "start":
		return NodeState.LOCKED
	for l in n.get("links", []):
		if alloc.has(l):
			if int(n.get("cost", 1)) <= pts and Game.ch.excluded_by(id) == "":
				return NodeState.AVAILABLE
			return NodeState.UNAVAILABLE
	return NodeState.LOCKED

## Whether node n is drawn (and clickable) at the current zoom level.
func node_visible(n: Dictionary, is_alloc: bool) -> bool:
	var lv := lod()
	if lv == 2 or is_alloc or n["id"] == hover or matches_search(n) or (Game.ch != null and Game.ch.plan_has(n["id"])):
		return true
	if n["type"] in ["start", "keystone"]:
		return true
	if lv == 1:
		return true   # minors are drawn as small dots
	return false

func node_overlays(id: String) -> Array:
	var n: Dictionary = Data.passives[id]
	var out := []
	var alloc := _alloc_set()
	if matches_search(n):
		out.append("search_hit")
	if filter_active() and not passes_filter(n):
		out.append("filtered_out")
	if alloc.has(id) and Game.ch.socket_boosts(Game.ch.allocated).has(id):
		out.append("boosted")
	if hover != "" and not alloc.has(hover) and hover_route(hover).has(id) and id != hover:
		out.append("route")
	if id == hover:
		out.append("hover")
	if not node_visible(n, alloc.has(id)):
		out.append("lod_hidden")
	return out

## ---- search hits and jumping
func search_hits() -> Array:
	var out := []
	for n in Data.passive_list:
		if matches_search(n):
			out.append(n["id"])
	return out

func next_hit(dir: int = 1) -> String:
	var hits := search_hits()
	if hits.is_empty():
		hit_index = -1
		return ""
	hit_index = posmod(hit_index + dir, hits.size())
	var id: String = hits[hit_index]
	center_on(node_pos(Data.passives[id]), maxf(zoom, LOD_NEAR + 0.1))
	return id

func center_on(world: Vector2, z: float = -1.0) -> void:
	if z > 0:
		zoom = clampf(z, ZOOM_MIN, ZOOM_MAX)
	offset = -world * zoom
	queue_redraw()

## ---- minimap (top-right corner of the view)
func tree_bounds() -> Rect2:
	if _bounds.size == Vector2.ZERO:
		var mn := Vector2(INF, INF)
		var mx := Vector2(-INF, -INF)
		for n in Data.passive_list:
			var p := node_pos(n)
			mn = Vector2(minf(mn.x, p.x), minf(mn.y, p.y))
			mx = Vector2(maxf(mx.x, p.x), maxf(mx.y, p.y))
		_bounds = Rect2(mn, mx - mn).grow(60)
	return _bounds

func minimap_rect() -> Rect2:
	return Rect2(Vector2(size.x - MINIMAP_SIZE.x - 8, 8), MINIMAP_SIZE)

func _mini_scale() -> float:
	var b := tree_bounds()
	return minf(MINIMAP_SIZE.x / b.size.x, MINIMAP_SIZE.y / b.size.y)

func world_to_mini(p: Vector2) -> Vector2:
	var mr := minimap_rect()
	return mr.get_center() + (p - tree_bounds().get_center()) * _mini_scale()

func mini_to_world(m: Vector2) -> Vector2:
	return tree_bounds().get_center() + (m - minimap_rect().get_center()) / _mini_scale()

## World-space rectangle the view currently shows.
func view_world_rect() -> Rect2:
	var a := (-size / 2 - offset) / zoom
	return Rect2(a, size / zoom)

func in_minimap(m: Vector2) -> bool:
	return show_minimap and minimap_rect().has_point(m)

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
	if not sn.is_empty():
		center_on(node_pos(sn) * 0.85, 0.8)
	else:
		zoom = 0.8
		queue_redraw()

func fit() -> void:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for n in Data.passive_list:
		var p := node_pos(n)
		mn = Vector2(minf(mn.x, p.x), minf(mn.y, p.y))
		mx = Vector2(maxf(mx.x, p.x), maxf(mx.y, p.y))
	var span := mx - mn + Vector2(120, 120)
	zoom = clampf(minf(size.x / span.x, size.y / span.y), ZOOM_MIN, 1.6)
	offset = -(mn + mx) / 2 * zoom
	queue_redraw()

func _node_at(m: Vector2) -> String:
	if in_minimap(m):
		return ""
	var alloc := _alloc_set()
	for n in Data.passive_list:
		if not node_visible(n, alloc.has(n["id"])):
			continue
		var r: float = RADIUS.get(n["type"], 10.0) * maxf(zoom, 0.5) + 3
		if to_screen(node_pos(n)).distance_to(m) <= r:
			return n["id"]
	return ""

## The route the hovered node would add: allocation route, or the plan route in planner mode.
func hover_route(id: String) -> Array:
	return Game.ch.plan_route(id) if planner else Game.ch.path_to(id)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(event.position, 1.12)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(event.position, 1.0 / 1.12)
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed and in_minimap(event.position):
			center_on(mini_to_world(event.position))
			dragging = false
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
	var nz := clampf(zoom * f, ZOOM_MIN, ZOOM_MAX)
	var world := (p - size / 2 - offset) / zoom
	zoom = nz
	offset = p - size / 2 - world * zoom

func _click(button: int, pos: Vector2) -> void:
	var id := _node_at(pos)
	if id == "":
		return
	var ch = Game.ch
	var n: Dictionary = Data.passives[id]
	if planner:
		_click_plan(button, id)
		return
	if button == MOUSE_BUTTON_LEFT and n["type"] == "mastery":
		_click_mastery(id)
		return
	if button == MOUSE_BUTTON_LEFT and n["type"] == "socket" and ch.allocated.has(id):
		_click_socket(id)
		return
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
		var gem_note := ""
		if ch.tree_gems.has(id):
			gem_note = "\nThe %s goes back to your gem pouch." % Loot.gem_name(str(ch.tree_gems[id]))
		panel.ui.ask("Refund [color=#e8c890]%s[/color] for %d gold?%s" % [n["name"], ch.refund_cost(), gem_note], func(): ch.refund(id))

## Phase 5b planner: LMB plans the node (and its route), RMB removes it (and whatever
## planned nodes it cut off). Masteries ask for the planned effect first.
func _click_plan(button: int, id: String) -> void:
	var ch = Game.ch
	if button == MOUSE_BUTTON_RIGHT:
		if not ch.plan_remove(id):
			panel.ui.toast("Not planned" if not ch.allocated.has(id) else "Allocated nodes are refunded outside the planner", UIKit.BAD)
		return
	if button != MOUSE_BUTTON_LEFT:
		return
	if ch.is_mastery(id) and ch.can_plan(id, "x") in ["Choose an effect", "That effect is already taken"]:
		var used: Dictionary = ch._plan_options_used()
		var opts := []
		for o in ch.mastery_options(id):
			var oid := str(o["id"])
			opts.append([option_text(o) + ("  (taken)" if used.has(oid) else ""), _plan_pick.bind(id, oid), not used.has(oid)])
		panel.ui.show_context(opts)
		return
	var why: String = ch.plan_add(id)
	if why != "":
		panel.ui.toast(why, UIKit.BAD)

func _plan_pick(id: String, oid: String) -> void:
	var why: String = Game.ch.plan_add(id, oid)
	if why != "":
		panel.ui.toast(why, UIKit.BAD)

## Phase 4b: an allocated socket takes a gem from the pouch (free to socket, swap or remove).
func gem_tree_text(gid: String) -> String:
	var parts := []
	for m in Loot.gem_mods(gid, "tree"):
		parts.append(Loot.mod_text(m))
	return ", ".join(parts)

func gem_boost_pct(gid: String) -> float:
	var pcts: Array = Game.ch.tree_socket_cfg().get("boost_pct", [0])
	return float(pcts[clampi(Loot.gem_tier(gid), 0, pcts.size() - 1)])

func gem_tags_text(gid: String) -> String:
	return ", ".join(Loot.gem_base(gid).get("tree_tags", []))

func _click_socket(id: String) -> void:
	var ch = Game.ch
	var opts := []
	var cur := str(ch.tree_gems.get(id, ""))
	if cur != "":
		opts.append(["Remove %s" % Loot.gem_name(cur), _socket_remove.bind(id), true])
	var held: Array = ch.gems.keys()
	held.sort_custom(func(a, b): return a.get_slice(":", 0) < b.get_slice(":", 0) or (a.get_slice(":", 0) == b.get_slice(":", 0) and Loot.gem_tier(a) > Loot.gem_tier(b)))
	for gid in held:
		var why: String = ch.can_socket_tree_gem(id, gid)
		opts.append(["%s x%d  (+%d%% %s)%s" % [Loot.gem_name(gid), int(ch.gems[gid]), int(gem_boost_pct(gid)), "/".join(Loot.gem_base(gid).get("tree_tags", []).slice(0, 3)), "" if why == "" else "  - %s" % why], _socket_put.bind(id, gid), why == ""])
	if opts.is_empty():
		panel.ui.toast("Your gem pouch is empty", UIKit.BAD)
		return
	panel.ui.show_context(opts)

func _socket_put(id: String, gid: String) -> void:
	var r: String = Game.ch.socket_tree_gem(id, gid)
	if r != "":
		panel.ui.toast(r, UIKit.BAD)

func _socket_remove(id: String) -> void:
	var r: String = Game.ch.unsocket_tree_gem(id)
	if r != "":
		panel.ui.toast(r, UIKit.BAD)

## Phase 4a: a mastery is allocated (or changed) by picking one of its effects.
func option_text(o: Dictionary) -> String:
	var parts := []
	for m in o.get("mods", []):
		parts.append(Loot.mod_text(m))
	return "%s: %s" % [o.get("name", o.get("id", "")), ", ".join(parts)]

func _click_mastery(id: String) -> void:
	var ch = Game.ch
	var opts := []
	if ch.allocated.has(id):
		var cur := str(ch.mastery_choices.get(id, ""))
		for o in ch.mastery_options(id):
			var oid := str(o["id"])
			var txt := option_text(o)
			if oid == cur:
				opts.append(["> " + txt + "  (current)", _noop, false])
			else:
				var why: String = ch.can_choose_mastery(id, oid)
				opts.append([txt + ("  (%d gold)" % ch.mastery_change_cost() if why == "" else "  (%s)" % why), _mastery_change.bind(id, oid), why == ""])
		panel.ui.show_context(opts)
		return
	var why0: String = ch.can_allocate(id)
	var via_path := false
	if why0 == "Must connect to an allocated node":
		var path: Array = ch.path_to(id)
		if path.is_empty():
			panel.ui.toast("No route to that node", UIKit.BAD)
			return
		if ch.path_cost(path) > ch.available_passive_points():
			panel.ui.toast("That route needs %d points (you have %d)" % [ch.path_cost(path), ch.available_passive_points()], UIKit.BAD)
			return
		via_path = true
	elif why0 != "":
		panel.ui.toast(why0, UIKit.BAD)
		return
	for o in ch.mastery_options(id):
		var oid := str(o["id"])
		var why: String = ch.can_choose_mastery(id, oid)
		opts.append([option_text(o) + ("" if why == "" else "  (%s)" % why), _mastery_pick.bind(id, oid, via_path), why == ""])
	panel.ui.show_context(opts)

func _noop() -> void:
	pass

func _mastery_change(id: String, oid: String) -> void:
	var r: String = Game.ch.change_mastery(id, oid)
	if r != "":
		panel.ui.toast(r, UIKit.BAD)

func _mastery_pick(id: String, oid: String, via_path: bool) -> void:
	var ok: bool = Game.ch.allocate_path(id, oid) if via_path else Game.ch.allocate(id, oid)
	if ok:
		hover = ""
		panel.ui.hide_tooltip()

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
	if str(n.get("drawback", "")) != "":
		lines.append("[color=#ff6060]Drawback: %s[/color]" % n["drawback"])
	if not n.get("tags", []).is_empty() and n["type"] != "start":
		lines.append("[color=#8a8494]Tags: %s[/color]" % ", ".join(n["tags"]))
	if ch.plan_has(id):
		var pm := str(ch.plan_choices.get(id, ""))
		lines.append("[color=#8ca6ff]Planned%s[/color]" % ((": " + str(ch.mastery_option(id, pm).get("name", pm))) if pm != "" else ""))
	if ch.plan_gems.has(id):
		lines.append("[color=#c080ff]Build suggests a %s gem here[/color]" % Data.gems.get(ch.plan_gems[id], {}).get("name", ch.plan_gems[id]))
	if refunded_ids().has(id) and not ch.allocated.has(id):
		lines.append("[color=#60b8e0]You had this node before the tree update refunded your points[/color]")
	if n["type"] == "mastery":
		var cur := str(ch.mastery_choices.get(id, "")) if ch.allocated.has(id) else ""
		for o in ch.mastery_options(id):
			var oid := str(o["id"])
			var other: String = ch.option_taken_by(oid, id)
			if oid == cur:
				lines.append("[color=#80e080]> %s[/color]" % option_text(o))
			elif other != "":
				lines.append("[color=#6a6474]%s (taken at %s)[/color]" % [option_text(o), Data.passives[other]["name"]])
			else:
				lines.append("[color=#8ab8ff]%s[/color]" % option_text(o))
	if n["type"] == "socket":
		var gid := str(ch.tree_gems.get(id, "")) if ch.allocated.has(id) else ""
		if gid != "":
			lines.append("[color=#%s]%s[/color]" % [Loot.gem_color(gid).to_html(false), Loot.gem_name(gid)])
			lines.append("[color=#8ab8ff]%s[/color]" % gem_tree_text(gid))
			var nb := 0
			var bo: Dictionary = ch.socket_boosts(ch.allocated)
			for nid in TreeRules.nodes_in_radius(Data.passives, id, ch.tree_socket_cfg()):
				if bo.has(nid):
					nb += 1
			lines.append("[color=#c080ff]+%d%% to the values of allocated %s nodes in the ring (%d boosted)[/color]" % [int(gem_boost_pct(gid)), gem_tags_text(gid), nb])
		else:
			lines.append("[color=#8a8494]Empty. A gem adds its passive tree stats and boosts allocated nodes in the ring that share its tags.[/color]")
	else:
		var bp := float(ch.socket_boosts(ch.allocated).get(id, 0.0)) if ch.allocated.has(id) else 0.0
		if bp > 0:
			lines.append("[color=#c080ff]Gem socket: values +%d%%[/color]" % int(bp))
	if n.has("class"):
		lines.append("[color=#8a8494]Starting point of the %s[/color]" % Data.classes[n["class"]]["name"])
	var allocated: bool = ch.allocated.has(id)
	var ids: Array = ch.allocated.duplicate()
	if allocated:
		ids.erase(id)
	else:
		ids.append(id)
	if not (n["type"] in ["start", "mastery"]):
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
	if planner:
		if allocated:
			lines.append("[color=#80e080]Allocated[/color]")
		elif ch.plan_has(id):
			lines.append("[color=#8ca6ff]Right-click to remove from the plan[/color]")
		else:
			var pr: Array = ch.plan_route(id)
			lines.append(("[color=#8ca6ff]Click to plan the route: %d points[/color]" % ch.path_cost(pr)) if not pr.is_empty() else "[color=#ff8080]%s[/color]" % ch.can_plan(id, "x" if ch.is_mastery(id) else ""))
		return "\n".join(lines)
	if allocated:
		var r: String = ch.can_refund(id) if n["type"] != "start" else "Starting point"
		lines.append("[color=#80e080]Allocated[/color]" + ("" if r == "" else "  [color=#8a8494](%s)[/color]" % r))
		if n["type"] == "mastery":
			lines.append("[color=#80c8ff]Click to change the effect: %d gold[/color]" % ch.mastery_change_cost())
		elif n["type"] == "socket":
			lines.append("[color=#80c8ff]Click to socket, swap or remove a gem (free)[/color]")
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
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	var lv := lod()
	# faint concentric guides
	for r in [200, 420, 640, 860, 1130]:
		draw_arc(to_screen(Vector2.ZERO), r * zoom, 0, TAU, 64, Color(1, 1, 1, 0.03), 1.0)
	var f0 := ThemeDB.fallback_font
	var cc := cluster_centres()
	# far zoom: cluster labels become the main landmarks
	var fs := int(clampf(30.0 * zoom, 11.0, 22.0)) if lv > 0 else 13
	var la := 0.16 if lv > 0 else 0.6
	for c in cc:
		var cp := to_screen(cc[c])
		var cw := f0.get_string_size(c, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if lv == 0:
			draw_string_outline(f0, cp + Vector2(-cw / 2, fs * 0.35), c, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.8))
		draw_string(f0, cp + Vector2(-cw / 2, fs * 0.35), c, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.85, 0.75, 0.55, la))
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
			if lv == 0 and not one:
				col = Color(col, 0.5)
			draw_line(a, b, col, ((4.0 if both else 2.0) * maxf(zoom, 0.5)) if lv > 0 else (2.5 if both else 1.0))
	# route preview for the hovered node
	# planned links (Phase 5b): both ends allocated or planned, at least one planned
	if not ch.plan.is_empty():
		for pid in ch.plan:
			var pn: Dictionary = Data.passives.get(pid, {})
			if pn.is_empty():
				continue
			for l in pn.get("links", []):
				if alloc.has(l) or (ch.plan_has(l) and l > pid):
					draw_line(to_screen(node_pos(pn)), to_screen(node_pos(Data.passives[l])), Color(PLAN_COL, 0.75), (3.0 * maxf(zoom, 0.5)) if lv > 0 else 1.5)
	var route := {}
	if hover != "" and not alloc.has(hover):
		var rp: Array = hover_route(hover)
		if rp.size() > 1:
			for i in rp.size():
				route[rp[i]] = true
			var prevp := Vector2.INF
			for l in Data.passives[rp[0]]["links"]:
				if alloc.has(l) or (planner and ch.plan_has(l)):
					prevp = to_screen(node_pos(Data.passives[l]))
					break
			for id2 in rp:
				var q := to_screen(node_pos(Data.passives[id2]))
				if prevp != Vector2.INF:
					draw_line(prevp, q, Color(0.5, 0.8, 1.0, 0.7), 3.0 * maxf(zoom, 0.5))
				prevp = q
	# gem socket rings (Phase 4b): hovered socket always, filled sockets faintly
	var sock_r := float(ch.tree_socket_cfg().get("radius", 0)) * zoom
	var boosts: Dictionary = ch.socket_boosts(ch.allocated)
	for sid in Data.passives:
		if Data.passives[sid]["type"] != "socket":
			continue
		var filled: bool = alloc.has(sid) and ch.tree_gems.has(sid)
		if sid == hover or filled:
			var rc := Loot.gem_color(str(ch.tree_gems[sid])) if filled else SOCKET_COL
			draw_arc(to_screen(node_pos(Data.passives[sid])), sock_r, 0, TAU, 64, Color(rc, 0.55 if sid == hover else 0.18), 1.5)
	# nodes
	var f := ThemeDB.fallback_font
	var refunded := refunded_ids()
	var filt := filter_active()
	for n in Data.passive_list:
		var p := to_screen(node_pos(n))
		if p.x < -40 or p.y < -40 or p.x > size.x + 40 or p.y > size.y + 40:
			continue
		var id: String = n["id"]
		var is_alloc: bool = alloc.has(id)
		if not node_visible(n, is_alloc or route.has(id)):
			continue
		var r: float = RADIUS.get(n["type"], 10.0) * maxf(zoom, 0.5)
		var st := _state(n, alloc, pts, refunded)
		var fill := Color(0.12, 0.11, 0.12)
		var ring := Color(0.35, 0.32, 0.3)
		match st:
			NodeState.ALLOCATED:
				fill = Color("#8a6a30")
				ring = Color("#ffd070")
			NodeState.AVAILABLE:
				var pulse := 0.6 + 0.4 * sin(t * 4.0)
				ring = Color(0.4, 1.0, 0.4).lerp(Color.WHITE, 0.2 * pulse)
				fill = Color(0.12, 0.2, 0.12)
			NodeState.UNAVAILABLE:
				ring = Color(0.8, 0.35, 0.3)
			NodeState.PLANNED:
				ring = Color(0.55, 0.65, 1.0)
				fill = Color(0.12, 0.13, 0.22)
			NodeState.MIGRATED_REFUNDED:
				ring = REFUND_COL
		var dimmed: bool = filt and not passes_filter(n)
		if lv == 1 and n["type"] == "minor" and not is_alloc and not route.has(id) and id != hover and not matches_search(n):
			# mid zoom: minors are plain dots
			draw_circle(p, r * 0.55, Color(ring, 0.55 if not dimmed else 0.15))
			continue
		is_alloc = st == NodeState.ALLOCATED
		if n["type"] == "mastery":
			var hx := PackedVector2Array()
			for i in 6:
				hx.append(p + Vector2.RIGHT.rotated(TAU * i / 6.0) * r)
			draw_colored_polygon(hx, fill if not is_alloc else Color("#2a6a62"))
			hx.append(hx[0])
			draw_polyline(hx, ring if not is_alloc else MASTERY_COL, 2.5)
			draw_circle(p, r * 0.3, MASTERY_COL if is_alloc else Color(MASTERY_COL, 0.35))
		elif n["type"] == "socket":
			draw_circle(p, r, fill)
			draw_arc(p, r, 0, TAU, 24, ring if not is_alloc else SOCKET_COL, 2.5)
			draw_arc(p, r - 4, 0, TAU, 20, Color(SOCKET_COL, 0.5), 1.0)
			if is_alloc and ch.tree_gems.has(id):
				var gp := PackedVector2Array()
				for i in 4:
					gp.append(p + Vector2.RIGHT.rotated(TAU * i / 4.0) * r * 0.55)
				draw_colored_polygon(gp, Loot.gem_color(str(ch.tree_gems[id])))
		elif n["type"] == "keystone":
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
		if dimmed:
			draw_circle(p, r + 2.0, Color(BG, 0.55 if is_alloc else 0.8))
		if boosts.has(id):
			draw_arc(p, r + 2.5, 0, TAU, 20, Color(SOCKET_COL, 0.9), 1.5)
		if id == hover:
			draw_arc(p, r + 4, 0, TAU, 24, Color.WHITE, 1.5)
		elif route.has(id):
			draw_arc(p, r + 3, 0, TAU, 20, Color(0.5, 0.8, 1.0, 0.8), 1.5)
		if matches_search(n):
			draw_arc(p, r + 7, 0, TAU, 24, Color(1.0, 0.85, 0.2, 0.6 + 0.4 * sin(t * 6.0)), 2.5)
		if lv == 2 and not dimmed and n["type"] == "mastery":
			var lbl: String = n["name"]
			if is_alloc:
				lbl = str(ch.mastery_option(id, str(ch.mastery_choices.get(id, ""))).get("name", lbl))
			var w3 := f.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			draw_string_outline(f, p + Vector2(-w3 / 2, -r - 6), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color.BLACK)
			draw_string(f, p + Vector2(-w3 / 2, -r - 6), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, MASTERY_COL)
		if lv == 2 and not dimmed and n["type"] in ["greater", "keystone"]:
			var w2 := f.get_string_size(n["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			draw_string_outline(f, p + Vector2(-w2 / 2, -r - 6), n["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color.BLACK)
			draw_string(f, p + Vector2(-w2 / 2, -r - 6), n["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#e8c890") if n["type"] == "greater" else Color("#ffb060"))
	# legend
	var items := [[Color("#ffd070"), "Allocated"], [Color(0.4, 1.0, 0.4), "Available"], [Color(0.8, 0.35, 0.3), "Connected, cannot take (points / exclusive)"], [Color(0.35, 0.32, 0.3), "Locked"]]
	if not ch.plan.is_empty() or planner:
		items.append([PLAN_COL, "Planned (%d points)" % ch.plan_points()])
	if not refunded.is_empty():
		items.append([REFUND_COL, "Refunded by a tree update"])
	if filt:
		items.append([Color(0.3, 0.3, 0.3), "Dimmed: filtered out"])
	var ly := size.y - 8 - items.size() * 16
	for i in items.size():
		draw_arc(Vector2(20, ly + i * 16), 5, 0, TAU, 12, items[i][0], 2.0)
		draw_string(f, Vector2(32, ly + i * 16 + 5), items[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIKit.MUTED)
	draw_string(f, Vector2(12, 18), ["Far view: clusters and keystones", "Mid view: notables", "Near view: all nodes"][lv], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIKit.MUTED)
	if planner:
		draw_string(f, Vector2(12, 36), "PLANNER: clicks plan nodes for free (right-click removes)", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, PLAN_COL)
	if show_minimap:
		_draw_minimap(alloc, filt)

func _draw_minimap(alloc: Dictionary, filt: bool) -> void:
	var mr := minimap_rect()
	draw_rect(mr, Color(0, 0, 0, 0.72))
	draw_rect(mr, Color(0.55, 0.5, 0.4, 0.8), false, 1.0)
	for n in Data.passive_list:
		var q := world_to_mini(node_pos(n))
		var id: String = n["id"]
		var col := Color(0.45, 0.42, 0.4, 0.6)
		var rr := 0.9
		if alloc.has(id):
			col = Color("#ffd070")
			rr = 1.6
		elif Game.ch.plan_has(id):
			col = PLAN_COL
			rr = 1.6
		elif n["type"] == "keystone":
			col = Color("#ffb060", 0.8)
			rr = 1.4
		elif n["type"] == "start":
			col = Color(Data.classes.get(n.get("class", ""), {}).get("color", "#888888"))
			rr = 2.2
		if filt and not passes_filter(n):
			col = Color(col, col.a * 0.25)
		draw_circle(q, rr, col)
		if matches_search(n):
			draw_arc(q, 3.0, 0, TAU, 8, Color(1.0, 0.85, 0.2), 1.0)
	var vr := view_world_rect()
	var a := world_to_mini(vr.position)
	var b := world_to_mini(vr.end)
	var rect := Rect2(a, b - a).intersection(mr)
	if rect.size.x > 0 and rect.size.y > 0:
		draw_rect(rect, Color(1, 1, 1, 0.85), false, 1.0)
