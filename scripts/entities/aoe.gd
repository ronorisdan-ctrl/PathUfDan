extends Node2D
## Delayed area hit with a readable telegraph. Used by player skills
## (meteor, rain of arrows, mines) and enemy attacks (slams, explosions).

const VFX = preload("res://scripts/fx/vfx.gd")

var level = null
var source = null
var packet := {}
var faction := "player"
var radius := 40.0
var delay := 0.5
var t := 0.0
var color := Color(1, 0.3, 0.2)
var style := "explosion"    # explosion | slam | rain | meteor | frost
var show_telegraph := true
var origin := Vector2.INF
var on_hit: Callable
var done := false

func _ready() -> void:
	z_index = -1 if style != "meteor" else 4
	if origin == Vector2.INF:
		origin = global_position

func _process(delta: float) -> void:
	t += delta
	if not done and t >= delay:
		done = true
		_trigger()
	if done and t >= delay + 0.05:
		queue_free()
	queue_redraw()

func _trigger() -> void:
	if level == null:
		return
	var fx_style := "explosion"
	if style == "slam":
		fx_style = "nova"
	elif style == "rain":
		fx_style = "dust"
	level.add_fx(VFX.make(fx_style, global_position, color, 0.35 if style != "rain" else 0.25, radius))
	if style in ["slam", "meteor", "explosion"]:
		level.shake(3.0 if style == "meteor" else 1.5)
		Sfx.play("explode")
	for target in level.hostiles_in_radius(global_position, radius, faction):
		Combat.deal(packet, source, target, origin)
		if on_hit.is_valid():
			on_hit.call(target)

func _draw() -> void:
	if done or not show_telegraph:
		return
	var k := clampf(t / maxf(delay, 0.01), 0, 1)
	draw_circle(Vector2.ZERO, radius, Color(color.r, color.g, color.b, 0.10))
	draw_arc(Vector2.ZERO, radius, 0, TAU, 40, Color(color.r, color.g, color.b, 0.65), 1.2)
	draw_circle(Vector2.ZERO, radius * k, Color(color.r, color.g, color.b, 0.20))
	if style == "meteor":
		var h := (1.0 - k) * 160.0
		var p := Vector2(-h * 0.5, -h)
		draw_line(p + Vector2(-10, -20), p, Color(1, 0.5, 0.1, 0.4), 6.0)
		draw_circle(p, 7.0, Color(1, 0.45, 0.1))
		draw_circle(p, 4.0, Color(1, 0.9, 0.5))
	elif style == "rain":
		for i in 3:
			var ox := sin(float(i) * 2.1 + t * 9.0) * radius * 0.6
			var oy := -(1.0 - k) * 80.0 - i * 10.0
			draw_line(Vector2(ox, oy), Vector2(ox + 2, oy + 8), Color(0.9, 0.85, 0.7, 0.8), 1.0)
