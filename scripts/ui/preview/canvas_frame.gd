extends Panel
## Crisp cabinet moulding, chipped gilding and localized pigment wear.

const CanvasStyle = preload("res://scripts/ui/preview/canvas_skin.gd")
var accent := CanvasStyle.GOLD

func _ready() -> void:
	add_theme_stylebox_override("panel", CanvasStyle.box(CanvasStyle.PANEL, CanvasStyle.EDGE))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	# Broad warm-black moulding reads as wood/gesso without noise behind text.
	draw_rect(Rect2(Vector2(1, 1), size - Vector2(2, 2)), Color("#29271f"), false, 2)
	draw_line(Vector2(11, 11), Vector2(11, size.y - 11), Color("#49412f"), 2)
	draw_line(Vector2(size.x - 11, 11), size - Vector2(11, 11), Color("#080d0b"), 2)
	draw_rect(Rect2(Vector2(3, 3), size - Vector2(6, 6)), Color("#080d0b"), false, 2)
	draw_rect(Rect2(Vector2(6, 6), size - Vector2(12, 12)), accent.darkened(0.45), false)
	draw_line(Vector2(7, 7), Vector2(size.x - 7, 7), accent.lightened(0.1))
	for corner in [Vector2(9, 9), Vector2(size.x - 10, 9), Vector2(9, size.y - 10), Vector2(size.x - 10, size.y - 10)]:
		var sx := 1.0 if corner.x < size.x / 2 else -1.0
		var sy := 1.0 if corner.y < size.y / 2 else -1.0
		draw_line(corner, corner + Vector2(21 * sx, 0), accent, 2)
		draw_line(corner, corner + Vector2(0, 21 * sy), accent, 2)
		draw_rect(Rect2(corner + Vector2(3 * sx, 3 * sy), Vector2(3, 3)), accent)
		for i in 13:
			var p: Vector2 = corner + Vector2(((i * 7) % 23) * sx, ((i * 11) % 19) * sy)
			draw_rect(Rect2(p, Vector2(1 + i % 3, 1 + i % 2)), Color("#725b3d") if i % 3 else Color("#353e2c"))
	# Grain stays at the border; the reading surface is intentionally quiet.
	for i in 55:
		var x := 12 + (i * 71) % maxi(1, int(size.x) - 24)
		var y: float = 10 if i % 2 else size.y - 12
		draw_rect(Rect2(Vector2(x, y), Vector2(2, 1)), accent.darkened(0.4))
