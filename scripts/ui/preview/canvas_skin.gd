extends RefCounted
## Local preview skin. No change to the live game's theme or resource settings.

const INK := Color("#101310")
const PANEL := Color("#191815")
const GOLD := Color("#b29a65")
const EDGE := Color("#66583b")
const TEXT := Color("#e2dcc7")
const MUTED := Color("#969784")
const GOOD := Color("#a9c5a0")
const BAD := Color("#d18a78")

static func box(bg: Color, border: Color, width: int = 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_content_margin_all(8)
	return s

static func theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 14
	t.set_color("font_color", "Label", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	for kind in ["Button", "CheckButton"]:
		t.set_stylebox("normal", kind, box(Color("#24281f"), EDGE))
		t.set_stylebox("hover", kind, box(Color("#343a2b"), GOLD))
		t.set_stylebox("pressed", kind, box(Color("#414330"), GOLD))
		t.set_stylebox("disabled", kind, box(Color("#181c18"), Color("#3b4034")))
		var focus := box(Color(0, 0, 0, 0), TEXT, 2)
		t.set_stylebox("focus", kind, focus)
		t.set_color("font_color", kind, TEXT)
		t.set_color("font_hover_color", kind, Color("#fff1cf"))
		t.set_color("font_disabled_color", kind, Color("#77796d"))
	return t

static func label(parent: Node, text: String, at: Vector2, extent: Vector2, font_size: int = 14, colour: Color = TEXT) -> Label:
	var l := Label.new()
	l.clip_text = true
	l.text = text
	l.position = at
	l.size = extent
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", colour)
	if font_size >= 17:
		var title_font := SystemFont.new()
		title_font.font_names = PackedStringArray(["Georgia", "Times New Roman"])
		l.add_theme_font_override("font", title_font)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

static func rule(parent: Node, at: Vector2, width: float) -> ColorRect:
	var r := ColorRect.new()
	r.position = at
	r.size = Vector2(width, 1)
	r.color = EDGE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r
