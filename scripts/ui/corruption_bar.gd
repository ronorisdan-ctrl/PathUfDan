extends Control
## Wide corruption readout for the Blacksmith: a bar with the number inside it,
## tick marks at every step (one per corruption event) and a line under it saying
## how many events remain. Drawn with _draw() like the other UI; no art files.

const CorruptionRules = preload("res://scripts/core/corruption_rules.gd")

var level := 0
var shown_item = null

func _init() -> void:
	custom_minimum_size = Vector2(390, 42)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

func set_item(it) -> void:
	shown_item = it
	level = CorruptionRules.get_level(it)
	queue_redraw()

## Text drawn on the bar, for tests.
func bar_label() -> String:
	return "Corruption %d%%" % level

func note_text() -> String:
	return CorruptionRules.events_text(shown_item)

func _draw() -> void:
	var w := size.x
	var bar := Rect2(0, 0, w, 20)
	var mx := CorruptionRules.max_level()
	draw_rect(bar, Color(0.1, 0.09, 0.12))
	var col := CorruptionRules.level_color(level)
	draw_rect(Rect2(0, 0, w * float(level) / float(mx), 20), col.darkened(0.15))
	draw_rect(bar, Color(0.35, 0.32, 0.38), false, 1.0)
	var st := CorruptionRules.step()
	var v := st
	while v < mx:
		var x := w * float(v) / float(mx)
		draw_line(Vector2(x, 2), Vector2(x, 18), Color(0, 0, 0, 0.7), 2.0)
		v += st
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(8, 15), bar_label(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1))
	var maxed := CorruptionRules.is_maxed(shown_item)
	draw_string(font, Vector2(2, 36), note_text(), HORIZONTAL_ALIGNMENT_LEFT, w - 4, 12, CorruptionRules.level_color(mx) if maxed else Color("#8a8494"))
