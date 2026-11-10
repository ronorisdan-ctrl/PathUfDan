extends Control

const HUDStyle = preload("res://scripts/ui/components/hud_style.gd")
var ratio := 0.0
var displayed := 0.0
var character_text := ""
var experience_text := ""
var level := 0
var celebration := 0.0
var gain := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(624, 30)

func present(character, delta: float, snap: bool = false) -> void:
	var next := clampf(float(character.xp) / maxf(1, character.xp_to_next()), 0, 1)
	if character.level >= character.MAX_LEVEL:
		next = 1.0
	if snap or level == 0:
		displayed = next
		celebration = 0
		gain = 0
	elif character.level > level:
		celebration = 1.6
		displayed = 0
	elif next > ratio:
		gain = 0.35
	ratio = next
	level = character.level
	character_text = "%s  ·  LEVEL %d" % [str(character.class_def().get("name", character.class_id)).to_upper(), level]
	experience_text = "%d / %d XP" % [character.xp, character.xp_to_next()] if level < character.MAX_LEVEL else "MAX LEVEL"
	displayed = lerpf(displayed, ratio, 1.0 - exp(-delta * 10))
	celebration = maxf(0, celebration - delta)
	gain = maxf(0, gain - delta)
	queue_redraw()

func _draw() -> void:
	var r := Rect2(0, 2, size.x, 6)
	draw_rect(r.grow(1), Color("#080a09"))
	draw_rect(r, Color("#29271e"))
	draw_rect(Rect2(r.position, Vector2(r.size.x * displayed, r.size.y)), HUDStyle.color("gold").darkened(0.22))
	draw_line(r.position, Vector2(r.end.x, r.position.y), HUDStyle.color("bronze"))
	for i in range(1, 20):
		var at := r.position + Vector2(r.size.x * i / 20, 0)
		draw_line(at, at + Vector2(0, r.size.y), Color(0.03, 0.03, 0.02, 0.55))
	if celebration > 0 or gain > 0:
		draw_line(r.position + Vector2(0, 1), r.position + Vector2(r.size.x * displayed, 1), Color(0.85, 0.74, 0.5, minf(0.6, maxf(gain, celebration) * 0.5)), 2)
	HUDStyle.text(self, Vector2(0, 24), character_text, 11, HUDStyle.color("gold"))
	var info := "LEVEL GAINED" if celebration > 0 else experience_text
	var width := ThemeDB.fallback_font.get_string_size(info, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	HUDStyle.text(self, Vector2(size.x - width, 24), info, 11, HUDStyle.color("ivory") if celebration > 0 else HUDStyle.color("muted"))
