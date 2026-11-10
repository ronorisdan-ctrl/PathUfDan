extends Node2D
## Endgame 2D: the shimmering painted-over wall drawn over a Pentimento Vault's sealed mouth.

var cells := []
var level = null
var color := Color("#8fc4d8")
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
		var a := 0.5 + 0.25 * sin(t * 2.2 + c.x * 0.9 + c.y * 0.6)
		draw_rect(r, Color(color.r * 0.35, color.g * 0.35, color.b * 0.4, 0.95))
		draw_rect(r, Color(color.r, color.g, color.b, a * 0.45))
		for k in 3:
			var y := r.position.y + 3 + k * 5 + sin(t * 1.5 + k + c.x) * 1.5
			draw_line(Vector2(r.position.x + 2, y), Vector2(r.end.x - 2, y + 1), Color(1, 1, 1, a * 0.5), 1.0)
		draw_rect(r, Color(color.r, color.g, color.b, a), false, 1.0)
