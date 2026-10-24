extends PanelContainer
## Window chrome shared by all game panels: title, close button, placement.

const UIKit = preload("res://scripts/ui/ui_kit.gd")

var ui = null
var panel_name := ""
var title_label: Label
var body: VBoxContainer
var place := "center"   # left | right | center | full

func build(t: String, min_size: Vector2) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = min_size
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	add_child(outer)
	var head := HBoxContainer.new()
	outer.add_child(head)
	title_label = UIKit.label(t, 18, UIKit.GOLD)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_label)
	var x := UIKit.button("X", func(): ui.close(panel_name))
	x.custom_minimum_size = Vector2(28, 26)
	head.add_child(x)
	outer.add_child(HSeparator.new())
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(body)

func reposition() -> void:
	var vs := get_viewport_rect().size
	size = get_combined_minimum_size()
	var y := maxf(8.0, (vs.y - size.y) / 2.0 - 20.0)
	match place:
		"left":
			position = Vector2(16, y)
		"right":
			position = Vector2(vs.x - size.x - 16, y)
		"full":
			position = Vector2(20, 20)
			size = vs - Vector2(40, 40)
		_:
			position = (vs - size) / 2
	position.y = clampf(position.y, 0, maxf(0, vs.y - size.y))

func on_open() -> void:
	refresh()

func on_close() -> void:
	pass

func refresh() -> void:
	pass
