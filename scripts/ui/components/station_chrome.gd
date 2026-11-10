extends "res://scripts/ui/components/panel_chrome.gd"
## Station-local layout helpers. Controllers and transaction callbacks stay in panels.

static func caption(text: String) -> Label:
	var label := Cabinet.caption(text)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

static func inset(parent: Node, child: Control) -> void:
	var frame := Cabinet.inset()
	parent.add_child(frame)
	frame.add_child(child)

static func reading_scroll(parent: Node, height: float) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = height
	scroll_inset(scroll)
	parent.add_child(scroll)
	return scroll

## Godot 4.0 Buttons have no native word wrap. Preserve explicit line breaks,
## labels and callbacks while keeping data-driven choices within the station.
static func wrap_button(button: Button, width: float = 400.0) -> void:
	var font := button.get_theme_font("font")
	var font_size := button.get_theme_font_size("font_size")
	var lines := PackedStringArray()
	for paragraph in button.text.split("\n"):
		var line := ""
		for word in paragraph.split(" ", false):
			var next := word if line == "" else line + " " + word
			if line != "" and font.get_string_size(next, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
				lines.append(line)
				line = word
			else:
				line = next
		lines.append(line)
	button.text = "\n".join(lines)
