extends "res://scripts/ui/base_panel.gd"
## Passive skill tree: pannable, zoomable node web with class starts,
## allocation validation, stat previews and gold-cost refunds.
## Phase 5a: tag filter chips, "behaviour only" toggle, search-hit jumping, minimap
## (drawn by the view), zoom levels of detail and the "what my tree does" summary.
## Phase 5b: 3 presets per character, planner mode (ghost nodes, apply plan) and build codes.

const TreeRules = preload("res://scripts/core/tree_rules.gd")
const Chrome = preload("res://scripts/ui/components/panel_chrome.gd")

var view: Control
var info: RichTextLabel
var search: LineEdit
var hits_label: Label
var chips := {}            # tag -> Button
var more_tags: OptionButton
var behaviour_btn: Button
var summary_box: ScrollContainer
var summary: RichTextLabel
var preset_btns := []
var planner_btn: Button
var code_box: HBoxContainer
var code_edit: LineEdit
var help_label: Label

func _init() -> void:
	place = "full"
	build("Passive Skill Tree", Vector2(900, 600))
	theme = Chrome.make_theme()
	Chrome.heading(title_label)
	title_label.get_parent().get_child(1).tooltip_text = "Close passive tree"
	# row 1: points + navigation
	var top := HBoxContainer.new()
	info = UIKit.rich()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(info)
	top.add_child(UIKit.button("Jump to my start", func(): view.center_on_class()))
	top.add_child(UIKit.button("Fit tree", func(): view.fit()))
	top.add_child(UIKit.button("Minimap", toggle_minimap))
	top.add_child(UIKit.button("Summary", toggle_summary))
	top.add_child(UIKit.button("Specialisation (J)", func(): ui.toggle("spec")))
	body.add_child(top)
	# row 1b (Phase 5b): presets, planner, build codes
	var pr := HFlowContainer.new()
	pr.add_theme_constant_override("h_separation", 4)
	pr.add_theme_constant_override("v_separation", 4)
	pr.add_child(UIKit.label("Presets:", 13, UIKit.MUTED))
	for i in 3:
		var pb := Button.new()
		pb.add_theme_font_size_override("font_size", 12)
		pb.custom_minimum_size = Vector2(92, 0)
		pb.pressed.connect(click_preset.bind(i))
		preset_btns.append(pb)
		pr.add_child(pb)
	pr.add_child(VSeparator.new())
	planner_btn = Button.new()
	planner_btn.text = "Planner"
	planner_btn.toggle_mode = true
	planner_btn.add_theme_font_size_override("font_size", 12)
	planner_btn.tooltip_text = "Plan nodes for free (ghost nodes), then apply the plan as far as your points allow"
	planner_btn.toggled.connect(set_planner)
	pr.add_child(planner_btn)
	pr.add_child(UIKit.button("Apply plan", apply_plan))
	pr.add_child(UIKit.button("Clear plan", clear_plan))
	pr.add_child(VSeparator.new())
	pr.add_child(UIKit.button("Build code...", toggle_code))
	body.add_child(pr)
	code_box = HBoxContainer.new()
	code_box.visible = false
	code_edit = LineEdit.new()
	code_edit.placeholder_text = "Paste a build code (POD1-...) or press Export"
	code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_edit.text_submitted.connect(func(_t): import_code())
	code_box.add_child(code_edit)
	code_box.add_child(UIKit.button("Export + copy", export_code))
	code_box.add_child(UIKit.button("Import as plan", import_code))
	body.add_child(code_box)
	# row 2: search + filters
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	search = LineEdit.new()
	search.placeholder_text = "Search nodes..."
	search.custom_minimum_size = Vector2(140, 0)
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.text_changed.connect(_on_search)
	search.text_submitted.connect(func(_t): jump_hit(1))
	row.add_child(search)
	row.add_child(UIKit.button("<", func(): jump_hit(-1)))
	row.add_child(UIKit.button(">", func(): jump_hit(1)))
	hits_label = UIKit.label("", 12, UIKit.MUTED)
	hits_label.custom_minimum_size = Vector2(80, 0)
	row.add_child(hits_label)
	row.add_child(VSeparator.new())
	var filters := HFlowContainer.new()
	filters.add_theme_constant_override("h_separation", 4)
	filters.add_theme_constant_override("v_separation", 4)
	filters.add_child(Chrome.Cabinet.caption("TAGS"))
	for tg in load("res://scripts/ui/passive_tree_view.gd").FILTER_CHIPS:
		var b := Button.new()
		b.text = tag_label(tg)
		b.toggle_mode = true
		b.add_theme_font_size_override("font_size", 12)
		b.tooltip_text = "Show only %s nodes" % tg
		b.toggled.connect(func(on): set_tag(tg, on))
		chips[tg] = b
		filters.add_child(b)
	more_tags = OptionButton.new()
	more_tags.add_theme_font_size_override("font_size", 12)
	more_tags.custom_minimum_size.x = 150
	more_tags.add_item("More tags...")
	for tg in used_tags():
		if not chips.has(tg):
			more_tags.add_item(tag_label(tg))
			more_tags.set_item_metadata(more_tags.item_count - 1, tg)
	more_tags.item_selected.connect(_on_more_tag)
	row.add_child(more_tags)
	behaviour_btn = Button.new()
	behaviour_btn.text = "Behaviour only"
	behaviour_btn.toggle_mode = true
	behaviour_btn.add_theme_font_size_override("font_size", 12)
	behaviour_btn.tooltip_text = "Show only keystones, masteries, sockets and nodes that change how you play"
	behaviour_btn.toggled.connect(set_behaviour_only)
	row.add_child(behaviour_btn)
	row.add_child(UIKit.button("Clear", clear_filters))
	body.add_child(row)
	body.add_child(filters)
	# view + summary side panel
	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view = load("res://scripts/ui/passive_tree_view.gd").new()
	view.panel = self
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.custom_minimum_size = Vector2(480, 240)
	var tree_inset := Chrome.Cabinet.inset()
	tree_inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree_inset.add_child(view)
	mid.add_child(tree_inset)
	summary_box = ScrollContainer.new()
	summary_box.custom_minimum_size = Vector2(300, 0)
	summary_box.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	summary_box.visible = false
	summary_box.add_theme_stylebox_override("panel", Chrome.Cabinet.box(Color("#101310"), Color("#3e392d"), 8))
	summary = UIKit.rich()
	summary.fit_content = true
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary_box.add_child(summary)
	mid.add_child(summary_box)
	body.add_child(mid)
	help_label = UIKit.label("", 12, Chrome.Cabinet.MUTED)
	help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(help_label)
	Events.passive_changed.connect(refresh)
	Events.currency_changed.connect(refresh)
	resized.connect(queue_redraw)

func _draw() -> void:
	Chrome.Cabinet.draw_frame(self)

static func tag_label(tg: String) -> String:
	return tg.replace("_", " ").capitalize()

## Tags used by at least one node, in vocabulary order.
static func used_tags() -> Array:
	var used := {}
	for n in Data.passive_list:
		if n.get("type", "") == "start":
			continue
		for tg in n.get("tags", []):
			used[tg] = true
	var out := []
	for tg in Data.passive_flags.get("tags", []):
		if used.has(tg):
			out.append(tg)
	return out

func toggle_minimap() -> void:
	view.show_minimap = not view.show_minimap
	view.queue_redraw()

func set_behaviour_only(on: bool) -> void:
	view.behaviour_only = on
	view.queue_redraw()

func set_tag(tg: String, on: bool) -> void:
	view.set_tag(tg, on)

func _on_more_tag(i: int) -> void:
	# the drop-down holds one extra tag at a time
	for k in view.tag_filter.keys():
		if not chips.has(k):
			view.tag_filter.erase(k)
	if i > 0:
		view.set_tag(str(more_tags.get_item_metadata(i)), true)
	view.queue_redraw()

func clear_filters() -> void:
	for tg in chips:
		chips[tg].set_pressed_no_signal(false)
	behaviour_btn.set_pressed_no_signal(false)
	more_tags.select(0)
	view.clear_filters()

func _on_search(txt: String) -> void:
	view.search = txt
	view.hit_index = -1
	_update_hits()
	view.queue_redraw()

func _update_hits() -> void:
	if view.search.length() < 2:
		hits_label.text = ""
		return
	var n: int = view.search_hits().size()
	hits_label.text = ("%d/%d" % [view.hit_index + 1, n]) if view.hit_index >= 0 and n > 0 else ("%d hit%s" % [n, "" if n == 1 else "s"])

func jump_hit(dir: int) -> void:
	var id: String = view.next_hit(dir)
	_update_hits()
	if id == "" and view.search.length() >= 2:
		ui.toast("No nodes match the search", UIKit.BAD)

# ---------------------------------------------------------------- Phase 5b
func preset_text(i: int) -> String:
	var ch = Game.ch
	if ch.preset_empty(i):
		return "%d: empty" % (i + 1)
	return "%s%d: %d nodes" % ["> " if i == ch.active_preset else "", i + 1, ch.preset_nodes(i)]

func click_preset(i: int) -> void:
	var ch = Game.ch
	if i == ch.active_preset:
		ui.toast("Preset %d is your current tree" % (i + 1))
		return
	var why: String = ch.can_switch_preset(i)
	if why != "":
		ui.toast(why, UIKit.BAD)
		return
	var msg := ""
	if ch.preset_empty(i):
		msg = "Copy your current tree into preset %d and switch to it? (free)" % (i + 1)
	else:
		var cost: int = ch.preset_switch_cost(i)
		msg = "Switch to preset %d (%d nodes)?\nRemoves or changes %d of your nodes: %s.\nSocketed gems go back to your pouch; the preset's gems are socketed again if you still have them." % [
			i + 1, ch.preset_nodes(i), ch.preset_changes(i), ("[color=#e8c050]%d gold[/color]" % cost) if cost > 0 else ("free below level %d" % ch.PRESET_FREE_LEVEL if ch.level < ch.PRESET_FREE_LEVEL else "free")]
	ui.ask(msg, func(): _do_switch(i))

func _do_switch(i: int) -> void:
	var r: String = Game.ch.switch_preset(i)
	if r != "":
		ui.toast(r, UIKit.BAD)
	elif not Game.ch.last_preset_missing.is_empty():
		ui.toast("Missing gems not socketed: %s" % ", ".join(Game.ch.last_preset_missing.map(func(g): return Loot.gem_name(g))), UIKit.BAD)
	else:
		ui.toast("Switched to preset %d" % (i + 1), UIKit.GOOD)

func set_planner(on: bool) -> void:
	view.planner = on
	view.hover = ""
	ui.hide_tooltip()
	refresh()

func apply_plan() -> void:
	var ch = Game.ch
	if ch.plan.is_empty():
		ui.toast("Nothing planned", UIKit.BAD)
		return
	var n: int = ch.apply_plan()
	if n == 0:
		ui.toast("No planned node can be allocated yet (%d points available)" % ch.available_passive_points(), UIKit.BAD)
	else:
		ui.toast("Allocated %d planned node%s%s" % [n, "" if n == 1 else "s", ("; %d still planned" % ch.plan.size()) if not ch.plan.is_empty() else ""], UIKit.GOOD)

func clear_plan() -> void:
	Game.ch.clear_plan()

func toggle_code() -> void:
	code_box.visible = not code_box.visible
	if code_box.visible:
		code_edit.grab_focus()

func export_code() -> void:
	code_edit.text = Game.ch.export_build_code(true)
	DisplayServer.clipboard_set(code_edit.text)
	ui.toast("Build code copied to the clipboard%s" % (" (planned nodes included)" if not Game.ch.plan.is_empty() else ""), UIKit.GOOD)

## The code becomes the plan; illegal nodes are dropped and reported.
func import_code() -> void:
	var r: Dictionary = Game.ch.import_build_code(code_edit.text)
	if r["error"] != "":
		ui.toast(r["error"], UIKit.BAD)
		return
	planner_btn.button_pressed = true
	var g := ""
	if not r["gems"].is_empty():
		g = "; suggested gems: %s" % ", ".join(r["gems"].map(func(b): return Data.gems.get(b, {}).get("name", b)))
	ui.toast("Imported: %d nodes planned%s%s" % [r["planned"], (", %d illegal dropped" % r["dropped"]) if r["dropped"] > 0 else "", g], UIKit.GOOD)

func toggle_summary() -> void:
	summary_box.visible = not summary_box.visible
	refresh()

func on_open() -> void:
	refresh()
	view.center_on_class()

## "What my tree does": allocated stats summed and grouped by theme, then keystones,
## behaviour nodes, masteries and socketed gems.
func summary_text() -> String:
	var ch = Game.ch
	var sm: Dictionary = ch.tree_summary()
	var L := ["[font_size=16][color=#e8c890]What my tree does[/color][/font_size]", "[color=#8a8494]%d nodes, %d points[/color]" % [int(sm["nodes"]), int(sm["points"])]]
	if int(sm["nodes"]) == 0:
		L.append("")
		L.append("[color=#8a8494]Nothing allocated yet.[/color]")
		return "\n".join(L)
	if not sm["keystones"].is_empty():
		L.append("")
		L.append("[color=#ffb060]Keystones[/color]")
		for id in sm["keystones"]:
			var n: Dictionary = Data.passives[id]
			L.append("[color=#ffb060]%s[/color]" % n["name"])
			if str(n.get("drawback", "")) != "":
				L.append("  [color=#ff6060]%s[/color]" % n["drawback"])
	if not sm["behaviours"].is_empty():
		L.append("")
		L.append("[color=#e8c890]Behaviours[/color]")
		for id in sm["behaviours"]:
			var n2: Dictionary = Data.passives[id]
			L.append("[color=#e8c890]%s[/color]  [color=#b0a8b8]%s[/color]" % [n2["name"], n2.get("desc", "")])
	if not sm["masteries"].is_empty():
		L.append("")
		L.append("[color=#60d0c0]Masteries[/color]")
		for pr in sm["masteries"]:
			var o: Dictionary = ch.mastery_option(pr[0], pr[1])
			L.append("[color=#60d0c0]%s[/color]: %s" % [Data.passives[pr[0]]["name"], view.option_text(o) if not o.is_empty() else "?"])
	if not sm["gems"].is_empty():
		L.append("")
		L.append("[color=#c080ff]Socketed gems[/color]")
		for pr in sm["gems"]:
			L.append("[color=#%s]%s[/color] (+%d%% %s nearby)" % [Loot.gem_color(pr[1]).to_html(false), Loot.gem_name(pr[1]), int(view.gem_boost_pct(pr[1])), view.gem_tags_text(pr[1])])
	for th in sm["order"]:
		L.append("")
		L.append("[color=#c8a060]%s[/color]" % th)
		for m in sm["themes"][th]:
			L.append("[color=#8ab8ff]%s[/color]" % Loot.mod_text(m))
	var tags: Dictionary = sm["tags"]
	var tl: Array = tags.keys()
	tl.sort_custom(func(a, b): return tags[a] > tags[b] or (tags[a] == tags[b] and a < b))
	if not tl.is_empty():
		var parts := []
		for tg in tl.slice(0, 10):
			parts.append("%s %d" % [tg, int(tags[tg])])
		L.append("")
		L.append("[color=#8a8494]Tags: %s[/color]" % ", ".join(parts))
	return "\n".join(L)

func refresh() -> void:
	var ch = Game.ch
	if ch == null:
		return
	info.text = "[font_size=15]Points available: [color=#80ff80]%d[/color]   Allocated: %d   Refund cost: [color=#e8c050]%d gold[/color] per node%s[/font_size]" % [ch.available_passive_points(), ch.allocated.size() - 1, ch.refund_cost(),
		("   [color=#8ca6ff]Planned: %d (%d pts)[/color]" % [ch.plan.size(), ch.plan_points()]) if not ch.plan.is_empty() else ""]
	for i in preset_btns.size():
		preset_btns[i].text = preset_text(i)
		preset_btns[i].tooltip_text = "Current tree" if i == ch.active_preset else ("Empty: copies your current tree (free)" if ch.preset_empty(i) else "Switch: removes or changes %d nodes, %d gold" % [ch.preset_changes(i), ch.preset_switch_cost(i)])
		preset_btns[i].modulate = Color("#ffd070") if i == ch.active_preset else Color.WHITE
	help_label.text = ("PLANNER: LMB plans a route | RMB removes planned nodes" if view.planner else "LMB: allocate / route | RMB: refund") + "   •   Drag: pan | Wheel: zoom | Minimap: jump | Masteries: choose effect | Sockets: set gem"
	if summary_box.visible:
		summary.text = summary_text()
	view.queue_redraw()
