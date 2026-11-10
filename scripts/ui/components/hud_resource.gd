extends Control
## Resource reliquary. Receives real values; animation never owns gameplay state.

const HUDStyle = preload("res://scripts/ui/components/hud_style.gd")
var resource_name := "LIFE"
var mana := false
var current := 0.0
var maximum := 0.0
var ratio := 0.0
var displayed := 0.0
var delayed := 0.0
var delay := 0.0
var feedback := 0.0
var warning_time := 0.0
var initialized := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(140, 140)

func present(value: float, limit: float, snap: bool = false) -> void:
	maximum = maxf(0, limit) if is_finite(limit) else 0.0
	current = clampf(value, 0, maximum) if is_finite(value) else 0.0
	var next := current / maximum if maximum > 0 else 0.0
	if not initialized or snap:
		displayed = next
		delayed = next
		feedback = 0
		delay = 0
		initialized = true
	elif next < ratio:
		delay = 0.35
		feedback = -0.25
	elif next > ratio + 0.008:
		feedback = 0.25
	ratio = next
	queue_redraw()

func advance(delta: float) -> void:
	displayed = lerpf(displayed, ratio, 1.0 - exp(-delta * 15.0))
	if absf(displayed - ratio) < 0.0005:
		displayed = ratio
	delay = maxf(0, delay - delta)
	if delay == 0:
		delayed = lerpf(delayed, ratio, 1.0 - exp(-delta * 5.0))
	delayed = maxf(delayed, displayed)
	feedback = move_toward(feedback, 0, delta)
	warning_time = fmod(warning_time + delta, TAU)
	queue_redraw()

func readout() -> String:
	return "%d / %d" % [int(ceil(current)), int(ceil(maximum))]

func _draw() -> void:
	var c := Vector2(70, 65)
	var radius := 49.0
	var pigment := HUDStyle.color("mana" if mana else "life")
	var bronze := HUDStyle.color("bronze")
	draw_circle(c, 61, Color(0.015, 0.017, 0.017, 0.95))
	draw_arc(c, 58, 0, TAU, 96, Color("#333633"), 6, true)
	draw_arc(c, 54, 0, TAU, 96, bronze, 2, true)
	draw_circle(c, radius, Color("#120f13") if mana else Color("#1c0b0e"))
	# Thin horizontal layers provide a curved, graduated fill at native UI resolution.
	for row in 98:
		var y := -radius + row + 0.5
		var half_width := sqrt(maxf(0, radius * radius - y * y))
		var fraction := (radius - y) / (2 * radius)
		var ink := Color.TRANSPARENT
		if fraction <= delayed and delayed > displayed + 0.01:
			ink = pigment.lightened(0.28).darkened(0.15)
		if fraction <= displayed:
			ink = pigment.darkened(0.05 + 0.5 * (y + radius) / (radius * 2))
		if ink.a > 0:
			draw_line(c + Vector2(-half_width, y), c + Vector2(half_width, y), ink, 1.2, true)
	if displayed > 0.01 and displayed < 0.99:
		var surface_y := radius - radius * 2 * displayed
		var surface_w := sqrt(maxf(0, radius * radius - surface_y * surface_y))
		draw_line(c + Vector2(-surface_w, surface_y), c + Vector2(surface_w, surface_y), pigment.lightened(0.22), 1.4, true)
	draw_arc(c, 50, 0, TAU, 96, Color("#090b0b"), 2, true)
	draw_arc(c, 57, PI * 1.05, PI * 1.85, 48, HUDStyle.color("gold"), 1.2, true)
	draw_arc(c + Vector2(-12, -13), 26, PI * 1.1, PI * 1.6, 28, Color(0.9, 0.85, 0.7, 0.09), 3, true)
	draw_arc(c, 47, -PI * 0.4, PI * 0.65, 64, Color(0.015, 0.01, 0.015, 0.22), 4, true)
	for side in [-1.0, 1.0]:
		var root := c + Vector2(side * 19, 57)
		draw_polyline(PackedVector2Array([root + Vector2(side * 14, -5), root, root + Vector2(side * 12, 8), root + Vector2(side * 28, 8)]), bronze.darkened(0.2), 2, true)
	# Iron clasps and small bronze studs; these can be replaced with texture art.
	for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
		var at := c + Vector2.from_angle(angle) * 57
		draw_colored_polygon(PackedVector2Array([at + Vector2(-5, 0), at + Vector2(0, -5), at + Vector2(5, 0), at + Vector2(0, 5)]), bronze)
	if not mana and ratio > 0 and ratio <= 0.25:
		draw_arc(c, 60, 0, TAU, 96, Color(0.66, 0.16, 0.16, 0.25 + sin(warning_time * 2) * 0.1), 2, true)
	if absf(feedback) > 0.01:
		draw_arc(c, 51, 0, TAU, 96, Color(0.65, 0.55, 0.4, absf(feedback) * 0.6), 1.5, true)
	HUDStyle.centered(self, c + Vector2(0, -4), resource_name, 11, HUDStyle.color("gold"))
	HUDStyle.centered(self, c + Vector2(0, 16), readout(), 15, HUDStyle.color("ivory"))
