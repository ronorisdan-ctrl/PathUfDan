extends RefCounted
## Native, replaceable HUD materials. No random generation or gameplay access.

const THEME = preload("res://assets/ui/themes/decaying_oil.tres")

static func color(token: String) -> Color:
	return THEME.get_color(token, "GameplayHUD")

static func frame(view: Control, rect: Rect2, emphasis: float = 0.0) -> void:
	view.draw_style_box(THEME.get_stylebox("panel", "HUDFrame"), rect)
	var edge := color("bronze").lerp(color("gold"), clampf(emphasis, 0, 1))
	view.draw_rect(rect.grow(-3), edge, false, 1.0)
	# Restrained edge wear, deterministic and clear of the reading area.
	for i in range(12, int(rect.size.x) - 12, 23):
		view.draw_line(rect.position + Vector2(i, 2), rect.position + Vector2(i + 5, 2), Color(0.65, 0.57, 0.4, 0.16))
	for corner in [rect.position + Vector2(5, 5), Vector2(rect.end.x - 5, rect.position.y + 5), rect.end - Vector2(5, 5), Vector2(rect.position.x + 5, rect.end.y - 5)]:
		view.draw_circle(corner, 1.3, edge)

static func text(view: Control, at: Vector2, value: String, font_size: int = 14, tint: Color = Color.WHITE, heading: bool = false) -> void:
	var font: Font = THEME.get_font("font", "Title") if heading else ThemeDB.fallback_font
	view.draw_string_outline(font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color(0.02, 0.02, 0.02, 0.9))
	view.draw_string(font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, tint)

static func centered(view: Control, at: Vector2, value: String, font_size: int = 14, tint: Color = Color.WHITE) -> void:
	var width := ThemeDB.fallback_font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	text(view, at - Vector2(width * 0.5, 0), value, font_size, tint)

static func key_label(action: String) -> String:
	if not InputMap.has_action(action):
		return "—"
	for event in InputMap.action_get_events(action):
		if event is InputEventMouseButton:
			match event.button_index:
				MOUSE_BUTTON_LEFT: return "LMB"
				MOUSE_BUTTON_RIGHT: return "RMB"
				MOUSE_BUTTON_MIDDLE: return "MMB"
			return "M%d" % event.button_index
		if event is InputEventKey:
			var code: int = event.physical_keycode if event.physical_keycode else event.keycode
			var label := OS.get_keycode_string(code)
			if event.ctrl_pressed: label = "Ctrl+" + label
			if event.alt_pressed: label = "Alt+" + label
			if event.shift_pressed: label = "Shift+" + label
			return label
	return "—"
