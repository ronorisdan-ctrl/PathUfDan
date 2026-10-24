extends "res://scripts/ui/base_panel.gd"
## Passive skill tree: pannable, zoomable node web with class starts,
## allocation validation, stat previews and gold-cost refunds.

var view: Control
var info: RichTextLabel

func _init() -> void:
	place = "full"
	build("Passive Skill Tree", Vector2(900, 600))
	var top := HBoxContainer.new()
	info = UIKit.rich("", 700)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(info)
	var search := LineEdit.new()
	search.placeholder_text = "Search nodes..."
	search.custom_minimum_size = Vector2(150, 0)
	search.text_changed.connect(_on_search)
	top.add_child(search)
	top.add_child(UIKit.button("Centre on my class", func(): view.center_on_class()))
	top.add_child(UIKit.button("Fit tree", func(): view.fit()))
	top.add_child(UIKit.button("Specialisation (J)", func(): ui.toggle("spec")))
	body.add_child(top)
	view = load("res://scripts/ui/passive_tree_view.gd").new()
	view.panel = self
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.custom_minimum_size = Vector2(600, 400)
	body.add_child(view)
	Events.passive_changed.connect(refresh)
	Events.currency_changed.connect(refresh)

func _on_search(txt: String) -> void:
	view.search = txt
	view.queue_redraw()

func on_open() -> void:
	refresh()
	view.center_on_class()

func refresh() -> void:
	var ch = Game.ch
	if ch == null:
		return
	info.text = "[font_size=15]Points available: [color=#80ff80]%d[/color]   Allocated: %d   Refund cost: [color=#e8c050]%d gold[/color] per node[/font_size]\n[color=#8a8494]LMB: allocate a highlighted node   RMB: refund   Drag: pan   Wheel: zoom   Keystones ask for confirmation[/color]" % [ch.available_passive_points(), ch.allocated.size() - 1, ch.refund_cost()]
	view.queue_redraw()
