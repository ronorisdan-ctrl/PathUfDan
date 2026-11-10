extends RefCounted
## Inventory-local native materials; never mutate the HUD/root Theme.

const HUDStyle = preload("res://scripts/ui/components/hud_style.gd")
const IVORY := Color("#e2dcc7")
const MUTED := Color("#aaa594")
const BRONZE := Color("#66583b")

static func box(fill: Color, edge: Color, padding: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_content_margin_all(padding)
	return style

static func make_theme() -> Theme:
	var result: Theme = HUDStyle.THEME.duplicate(true)
	result.default_font_size = 14
	var window := box(Color("#191815"), BRONZE, 12)
	window.set_border_width_all(2)
	window.shadow_color = Color(0, 0, 0, 0.7)
	window.shadow_size = 8
	result.set_stylebox("panel", "PanelContainer", window)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var button: StyleBoxFlat = result.get_stylebox(state, "Button").duplicate()
		button.content_margin_left = 8
		button.content_margin_right = 8
		button.content_margin_top = 5
		button.content_margin_bottom = 5
		result.set_stylebox(state, "Button", button)
	return result

static func inset() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_theme_stylebox_override("panel", box(Color("#101310"), Color("#3e392d"), 6))
	return panel

static func caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", MUTED)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

static func draw_frame(view: Control) -> void:
	var rect := Rect2(Vector2.ZERO, view.size)
	view.draw_rect(rect.grow(-3), Color("#080d0b"), false, 2)
	view.draw_rect(rect.grow(-5), BRONZE.darkened(0.2), false)
	for corner in [Vector2(6, 6), Vector2(view.size.x - 6, 6), view.size - Vector2(6, 6), Vector2(6, view.size.y - 6)]:
		view.draw_circle(corner, 1.5, HUDStyle.color("gold"))
	for x in range(18, int(view.size.x) - 18, 29):
		view.draw_line(Vector2(x, 3), Vector2(x + 5, 3), Color(0.7, 0.6, 0.4, 0.18))
