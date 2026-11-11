extends Node2D
## Endgame Phase 3C: a Pigment Well in a zone (zone_wells.gd sets color / fill / label each tick).

var color := Color("#d84a3a")
var fill := 0.0
var label := "Well"
var t := 0.0
var light: PointLight2D

func _ready() -> void:
	z_index = 1
	light = PointLight2D.new()
	light.texture = Art.light_tex
	light.color = color
	light.energy = 0.5
	light.texture_scale = 1.0
	add_child(light)

func _process(delta: float) -> void:
	t += delta
	if light != null:
		light.energy = 0.4 + 0.9 * fill
		light.texture_scale = 0.8 + 0.8 * fill
	queue_redraw()

func _draw() -> void:
	draw_circle(Vector2.ZERO, 15.0, Color(0.16, 0.14, 0.13, 0.95))
	draw_arc(Vector2.ZERO, 15.0, 0.0, TAU, 28, Color(0.45, 0.4, 0.35), 2.0)
	var r := 3.0 + 9.0 * clampf(fill, 0.0, 1.0)
	draw_circle(Vector2.ZERO, r, Color(color.r, color.g, color.b, 0.55 + 0.35 * fill))
	if fill > 0.0:
		draw_arc(Vector2.ZERO, 19.0, -PI / 2, -PI / 2 + TAU * clampf(fill, 0.0, 1.0), 32, color.lightened(0.25), 2.5)
	if fill >= 1.0:
		draw_arc(Vector2.ZERO, 22.0 + sin(t * 4.0) * 1.5, 0.0, TAU, 32, Color(color.r, color.g, color.b, 0.6), 1.5)
	var f := ThemeDB.fallback_font
	var txt := "%s %d%%" % [label, int(round(fill * 100.0))]
	var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	draw_string_outline(f, Vector2(-w / 2, -26), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, 3, Color.BLACK)
	draw_string(f, Vector2(-w / 2, -26), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, color.lightened(0.3))
