extends Node2D
## Generic short-lived vector/pixel effect: slash arcs, rings, explosions,
## lightning bolts, beams and telegraphs. One script, many styles, auto-freed.

var style := "ring"
var color := Color.WHITE
var life := 0.3
var t := 0.0
var radius := 30.0
var arc := 120.0
var angle := 0.0
var points := PackedVector2Array()
var width := 2.0
var follow = null

static func make(st: String, pos: Vector2, col: Color, lf: float, rad: float = 30.0):
	var v = load("res://scripts/fx/vfx.gd").new()
	v.style = st
	v.position = pos
	v.color = col
	v.life = lf
	v.radius = rad
	return v

func _ready() -> void:
	z_index = 20
	if style in ["explosion", "nova", "slash", "bolt", "beam", "spark"]:
		var light := PointLight2D.new()
		light.texture = Art.light_tex
		light.color = color
		light.energy = 0.9
		light.texture_scale = maxf(0.5, radius / 40.0)
		add_child(light)
	if style == "bolt":
		_jitter()

func _jitter() -> void:
	# rebuild the zig-zag between endpoints for a crackling look
	if points.size() < 2:
		return
	var a: Vector2 = points[0]
	var b: Vector2 = points[points.size() - 1]
	var pts := PackedVector2Array([a])
	var segs := maxi(3, int(a.distance_to(b) / 10.0))
	var n := (b - a).orthogonal().normalized()
	for i in range(1, segs):
		var p := a.lerp(b, float(i) / segs) + n * randf_range(-5, 5)
		pts.append(p)
	pts.append(b)
	points = pts

func _process(delta: float) -> void:
	t += delta
	if follow != null and is_instance_valid(follow):
		global_position = follow.global_position
	if t >= life:
		queue_free()
		return
	if style == "bolt" and fmod(t, 0.05) < delta:
		_jitter()
	queue_redraw()

func _draw() -> void:
	var k := t / life
	var a := 1.0 - k
	var c := Color(color.r, color.g, color.b, a)
	match style:
		"ring":
			draw_arc(Vector2.ZERO, radius * (0.3 + 0.7 * k), 0, TAU, 32, c, 2.0)
		"nova":
			var r := radius * (0.2 + 0.8 * minf(1.0, k * 1.6))
			draw_arc(Vector2.ZERO, r, 0, TAU, 40, c, 3.0)
			draw_circle(Vector2.ZERO, r, Color(color.r, color.g, color.b, a * 0.18))
		"explosion":
			var r2 := radius * (0.35 + 0.65 * minf(1.0, k * 2.5))
			draw_circle(Vector2.ZERO, r2, Color(color.r, color.g, color.b, a * 0.35))
			draw_circle(Vector2.ZERO, r2 * 0.6 * (1.0 - k), Color(1, 1, 0.85, a * 0.6))
			draw_arc(Vector2.ZERO, r2, 0, TAU, 32, c, 2.0)
		"slash":
			var sweep := deg_to_rad(arc)
			var start := angle - sweep / 2.0
			var prog := minf(1.0, k * 2.2)
			var steps := 10
			for i in steps:
				var f0 := float(i) / steps
				if f0 > prog:
					break
				var a0 := start + sweep * f0
				var a1 := start + sweep * minf(prog, float(i + 1) / steps)
				var fade := a * (0.4 + 0.6 * f0)
				draw_arc(Vector2.ZERO, radius * 0.85, a0, a1, 3, Color(color.r, color.g, color.b, fade), 5.0)
				draw_arc(Vector2.ZERO, radius, a0, a1, 3, Color(1, 1, 1, fade * 0.7), 1.5)
		"bolt", "beam":
			if points.size() >= 2:
				draw_polyline(points, Color(color.r, color.g, color.b, a * 0.5), width + 3.0)
				draw_polyline(points, Color(1, 1, 1, a), width)
		"spark":
			for i in 6:
				var ang := float(i) / 6.0 * TAU + float(get_instance_id() % 7)
				var p0 := Vector2.RIGHT.rotated(ang) * radius * k * 0.3
				var p1 := Vector2.RIGHT.rotated(ang) * radius * (0.3 + k)
				draw_line(p0, p1, c, 1.5)
		"telegraph":
			draw_circle(Vector2.ZERO, radius, Color(color.r, color.g, color.b, 0.12))
			draw_arc(Vector2.ZERO, radius, 0, TAU, 40, Color(color.r, color.g, color.b, 0.6), 1.5)
			draw_circle(Vector2.ZERO, radius * k, Color(color.r, color.g, color.b, 0.22))
		"dust":
			for i in 5:
				var ang2 := float(i) / 5.0 * TAU
				draw_circle(Vector2.RIGHT.rotated(ang2) * radius * k, 2.5 * a + 0.5, Color(color.r, color.g, color.b, a * 0.6))
