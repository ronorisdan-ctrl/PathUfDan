extends PanelContainer
## Bounded presentation only. UIRoot owns placement, lifecycle and reading input.

const Chrome = preload("res://scripts/ui/components/inventory_chrome.gd")
var text: RichTextLabel
var hint: Label
var reading := false
var overflowing := false
var _active := false
var _body: VBoxContainer

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", Chrome.box(Color("#101310"), Chrome.BRONZE, 10))
	_body = VBoxContainer.new()
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_theme_constant_override("separation", 6)
	add_child(_body)
	text = RichTextLabel.new()
	text.bbcode_enabled = true
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_theme_color_override("default_color", Chrome.IVORY)
	text.add_theme_font_size_override("normal_font_size", 14)
	text.add_theme_stylebox_override("focus", Chrome.box(Color(0, 0, 0, 0), Color("#dcc07c"), 0))
	_body.add_child(text)
	hint = Chrome.caption("")
	_body.add_child(hint)
	set_reading(false)
	z_index = 100
	visible = false

func present(value: String) -> void:
	text.text = value
	text.get_v_scroll_bar().value = 0

func set_reading(value: bool) -> void:
	reading = value
	mouse_filter = Control.MOUSE_FILTER_STOP if value else Control.MOUSE_FILTER_IGNORE
	text.mouse_filter = mouse_filter
	text.get_v_scroll_bar().mouse_filter = mouse_filter
	text.focus_mode = Control.FOCUS_ALL if value else Control.FOCUS_NONE
	text.scroll_active = true

func fit_card(width: float, max_height: float, allow_reading: bool) -> void:
	# Scrolling stays enabled with an inert scrollbar in passive mode, so
	# entering reading mode does not rewrap the item's text.
	text.custom_minimum_size.x = maxf(1, width - 36)
	var content_height := float(text.get_content_height())
	hint.text = "Wheel / PgUp / PgDn: scroll\nTab: other card   Esc: close" if reading else "More below — F4: read full cards"
	var padding := get_theme_stylebox("panel").get_minimum_size().y
	overflowing = content_height > max_height - padding
	hint.visible = reading or (overflowing and allow_reading)
	var hint_height := hint.get_combined_minimum_size().y + 6 if hint.visible else 0.0
	text.custom_minimum_size.y = minf(maxf(20, content_height), maxf(20, max_height - padding - hint_height))
	custom_minimum_size = Vector2(width, 0)
	size = Vector2(width, text.custom_minimum_size.y + padding + hint_height)

func mark_active(value: bool) -> void:
	if value == _active:
		return
	_active = value
	add_theme_stylebox_override("panel", Chrome.box(Color("#101310"), Color("#dcc07c") if value else Chrome.BRONZE, 10))

func scroll_page(direction: float) -> void:
	text.get_v_scroll_bar().value += direction * text.size.y * 0.85
