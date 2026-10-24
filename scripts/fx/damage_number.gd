extends Node2D
## Floating combat text. Frees itself.

var text := ""
var color := Color.WHITE
var big := false
var t := 0.0
const LIFE := 0.85

func setup(tx: String, c: Color, b: bool) -> void:
	text = tx
	color = c
	big = b
	z_index = 50

func _process(delta: float) -> void:
	t += delta
	position.y -= (34.0 if big else 24.0) * delta
	modulate.a = clampf(1.5 - t / LIFE * 1.5, 0, 1)
	if t >= LIFE:
		queue_free()
	queue_redraw()

func _draw() -> void:
	var f := ThemeDB.fallback_font
	var fs := 11 if big else 8
	var s := 1.0 + (0.4 * maxf(0.0, 1.0 - t * 6.0) if big else 0.0)
	draw_set_transform(Vector2.ZERO, 0, Vector2(s, s))
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string_outline(f, Vector2(-w / 2, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.9))
	draw_string(f, Vector2(-w / 2, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
