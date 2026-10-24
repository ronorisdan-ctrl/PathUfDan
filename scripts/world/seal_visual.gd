extends Node2D
## Glowing runic barrier drawn over the sealed boss-arena entrances.

var cells := []
var level = null
var t := 0.0

func _process(delta: float) -> void:
	t += delta
	queue_redraw()

func _draw() -> void:
	if level == null:
		return
	var T: int = level.T
	for c in cells:
		var r := Rect2(Vector2(c.x * T, c.y * T), Vector2(T, T))
		var a := 0.45 + 0.2 * sin(t * 3.0 + c.x * 0.7 + c.y * 0.5)
		draw_rect(r, Color(0.6, 0.3, 1.0, a * 0.5))
		draw_rect(r, Color(0.8, 0.6, 1.0, a), false, 1.0)
		draw_line(r.position + Vector2(4, 8), r.position + Vector2(12, 8), Color(1, 0.9, 1.0, a), 1.0)
