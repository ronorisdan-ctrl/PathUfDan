extends Control
## One inventory / equipment / stash / vendor cell.

signal clicked(slot, button, shift)
## Emitted (after `clicked`) on the second press of a left double-click.
signal double_clicked(slot)
signal hovered(slot)
signal unhovered(slot)

var item = null
var placeholder := ""     # icon shown when empty (equipment slots)
var key = null            # index or slot name, set by owner
var selected := false
var price := -1
var dim := false

func _init() -> void:
	custom_minimum_size = Vector2(44, 44)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func(): hovered.emit(self))
	mouse_exited.connect(func(): unhovered.emit(self))

func set_item(it) -> void:
	item = it
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		clicked.emit(self, event.button_index, event.shift_pressed)
		if event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
			double_clicked.emit(self)
		accept_event()

## Small padlock in the corner of a locked item (top-left of `at`, about 9x11 px).
func _draw_padlock(at: Vector2) -> void:
	var gold := Color("#ffd060")
	draw_rect(Rect2(at + Vector2(-1, 3), Vector2(11, 8)), Color(0, 0, 0, 0.75))
	draw_arc(at + Vector2(4.5, 3), 3.0, PI, TAU, 10, gold, 1.5)
	draw_rect(Rect2(at + Vector2(0, 4), Vector2(9, 6)), gold)
	draw_rect(Rect2(at + Vector2(4, 6), Vector2(1, 2)), Color(0.1, 0.08, 0.05))

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.08, 0.07, 0.09))
	if item != null:
		var col := Data.rarity_color(item.get("rarity", "common"))
		draw_rect(Rect2(Vector2(1, 1), size - Vector2(2, 2)), Color(col.r, col.g, col.b, 0.12))
		var tex: Texture2D = Art.icon(item.get("icon", "charm"))
		var isz := minf(size.x, size.y) - 8
		draw_texture_rect(tex, Rect2((size - Vector2(isz, isz)) / 2, Vector2(isz, isz)), false, Color(1, 1, 1, 0.45) if dim else Color.WHITE)
		draw_rect(r, col.darkened(0.2), false, 1.0)
		if int(item.get("upgrade", 0)) > 0:
			draw_string(ThemeDB.fallback_font, Vector2(3, 12), "+%d" % int(item["upgrade"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#ffd060"))
		if Game.ch != null and Game.ch.equip_restriction(item) != "":
			draw_rect(Rect2(Vector2(1, 1), size - Vector2(2, 2)), Color(0.8, 0.1, 0.1, 0.18))
		if bool(item.get("locked", false)):
			_draw_padlock(Vector2(size.x - 12, 3))
		if price >= 0:
			draw_string(ThemeDB.fallback_font, Vector2(2, size.y - 3), str(price), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#e8c050"))
	else:
		draw_rect(r, Color(0.25, 0.22, 0.2), false, 1.0)
		if placeholder != "":
			var t2: Texture2D = Art.icon(placeholder)
			var isz2 := minf(size.x, size.y) - 12
			draw_texture_rect(t2, Rect2((size - Vector2(isz2, isz2)) / 2, Vector2(isz2, isz2)), false, Color(1, 1, 1, 0.12))
	if selected:
		draw_rect(r, Color("#ffd060"), false, 2.0)
