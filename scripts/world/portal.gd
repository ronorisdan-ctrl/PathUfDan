extends Node2D
## Swirling portal / station marker with a floating label.

var color := Color("#6080ff")
var label := "Portal"
var t := 0.0
var sprite_name := ""

func _ready() -> void:
	z_index = 1
	var l := PointLight2D.new()
	l.texture = Art.light_tex
	l.color = color
	l.energy = 1.1
	l.texture_scale = 1.2
	add_child(l)
	if sprite_name != "":
		var s := Sprite2D.new()
		s.texture = Art.sprite(sprite_name)
		s.offset = Vector2(0, -8)
		add_child(s)

func _process(delta: float) -> void:
	t += delta
	queue_redraw()

func _draw() -> void:
	if sprite_name == "":
		for i in 4:
			var r := 10.0 + i * 3.0 + sin(t * 3.0 + i) * 1.5
			draw_arc(Vector2(0, -10), r, t * (2.0 + i * 0.5), t * (2.0 + i * 0.5) + 4.0, 16, Color(color.r, color.g, color.b, 0.8 - i * 0.15), 2.0)
		draw_circle(Vector2(0, -10), 8, Color(color.r, color.g, color.b, 0.35))
	var f := ThemeDB.fallback_font
	var w := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	draw_string_outline(f, Vector2(-w / 2, -30), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, 3, Color.BLACK)
	draw_string(f, Vector2(-w / 2, -30), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, color.lightened(0.3))
