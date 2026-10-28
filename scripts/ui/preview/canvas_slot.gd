extends Button
## A real focusable Button with separately visible hover, focus and selection.

const CanvasStyle = preload("res://scripts/ui/preview/canvas_skin.gd")
var item: Dictionary = {}
var placeholder := ""
var selected := false
var unavailable := false
var hidden_by_filter := false
var slot_key := ""

func _init() -> void:
	custom_minimum_size = Vector2(44, 44)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var edge := Color("#4a4b3b")
	var hovered := is_hovered() and not hidden_by_filter
	draw_rect(r, Color("#090e0d"))
	draw_rect(Rect2(Vector2(2, 2), size - Vector2(4, 4)), Color("#1e251f") if hovered else Color("#141a16"))
	if not item.is_empty() and not hidden_by_filter:
		edge = Data.rarity_color(item.get("rarity", "common")).darkened(0.28)
		var tex: Texture2D = Art.icon(item.get("icon", "charm"))
		# Existing 12px icons at an exact 3x, never fractionally resampled.
		draw_texture_rect(tex, Rect2((size - Vector2(36, 36)) / 2, Vector2(36, 36)), false, Color(0.7, 0.65, 0.59) if unavailable else Color.WHITE)
		draw_rect(Rect2(Vector2(3, 3), Vector2(3, 3)), edge.lightened(0.2))
		if unavailable:
			draw_line(Vector2(size.x - 9, 5), Vector2(size.x - 9, 12), CanvasStyle.BAD, 2)
			draw_rect(Rect2(Vector2(size.x - 10, 15), Vector2(2, 2)), CanvasStyle.BAD)
	elif placeholder != "":
		draw_texture_rect(Art.icon(placeholder), Rect2((size - Vector2(24, 24)) / 2, Vector2(24, 24)), false, Color(0.6, 0.6, 0.5, 0.23))
	draw_rect(r.grow(-0.5), edge, false)
	draw_line(Vector2(2, size.y - 2), size - Vector2(2, 2), Color("#303a2b"))
	if hovered:
		draw_rect(r.grow(-1.5), CanvasStyle.GOLD, false, 2)
	if selected:
		draw_rect(r.grow(-3), CanvasStyle.TEXT, false, 2)
		var p := Vector2(size.x - 11, size.y - 11)
		draw_line(p, p + Vector2(3, 3), CanvasStyle.GOLD, 2)
		draw_line(p + Vector2(3, 3), p + Vector2(8, -4), CanvasStyle.GOLD, 2)
	if has_focus():
		for i in range(4, int(size.x) - 4, 6):
			draw_rect(Rect2(Vector2(i, 0), Vector2(3, 1)), CanvasStyle.TEXT)
			draw_rect(Rect2(Vector2(i, size.y - 1), Vector2(3, 1)), CanvasStyle.TEXT)
