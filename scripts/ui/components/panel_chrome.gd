extends RefCounted
## Scoped shared-panel materials. Consumers opt in without changing root/HUD themes.

const Cabinet = preload("res://scripts/ui/components/inventory_chrome.gd")

static func make_theme() -> Theme:
	var result := Cabinet.make_theme()
	var field := Cabinet.box(Color("#101310"), Cabinet.BRONZE, 6)
	result.set_stylebox("normal", "LineEdit", field)
	result.set_stylebox("read_only", "LineEdit", field)
	result.set_stylebox("focus", "LineEdit", result.get_stylebox("focus", "Button"))
	result.set_color("font_color", "LineEdit", Cabinet.IVORY)
	result.set_color("font_placeholder_color", "LineEdit", Cabinet.MUTED)
	result.set_color("caret_color", "LineEdit", Cabinet.IVORY)
	result.set_color("selection_color", "LineEdit", Color("#66583b"))
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var button: StyleBox = result.get_stylebox(state, "Button").duplicate()
		if state != "focus":
			button.content_margin_right = 24
		result.set_stylebox(state, "OptionButton", button)
	result.set_color("font_color", "OptionButton", Cabinet.IVORY)
	result.set_color("font_hover_color", "OptionButton", Color("#fff0d0"))
	result.set_stylebox("panel", "PopupMenu", Cabinet.box(Color("#191815"), Cabinet.BRONZE, 8))
	result.set_stylebox("hover", "PopupMenu", Cabinet.box(Color("#3b3021"), Cabinet.BRONZE, 2))
	result.set_color("font_color", "PopupMenu", Cabinet.IVORY)
	result.set_color("font_hover_color", "PopupMenu", Color("#fff0d0"))
	return result

static func heading(label: Label) -> void:
	label.add_theme_font_override("font", Cabinet.HUDStyle.THEME.get_font("font", "Title"))
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Cabinet.IVORY)

static func apply(panel: PanelContainer) -> void:
	panel.theme = make_theme()
	heading(panel.title_label)
	panel.title_label.get_parent().get_child(1).tooltip_text = "Close " + panel.title_label.text.to_lower()

static func scroll_inset(scroll: ScrollContainer) -> void:
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_theme_stylebox_override("panel", Cabinet.box(Color("#101310"), Color("#3e392d"), 8))

static func place_panel(panel: Control, preferred: Vector2) -> void:
	var viewport := panel.get_viewport_rect().size
	panel.custom_minimum_size = Vector2(minf(preferred.x, viewport.x - 32), minf(preferred.y, viewport.y - 32))
	panel.size = panel.get_combined_minimum_size()
	panel.position = (viewport - panel.size) / 2
	if panel.place == "left":
		panel.position.x = 16
