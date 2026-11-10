extends Control
## One inventory / equipment / stash / vendor cell.

signal clicked(slot, button, shift)
## Emitted (after `clicked`) on the second press of a left double-click.
signal double_clicked(slot)
signal hovered(slot)
signal unhovered(slot)

const CorruptionRules = preload("res://scripts/core/corruption_rules.gd")
const SlotStyle = preload("res://scripts/ui/components/item_slot_skin.gd")

var item = null
var placeholder := ""     # icon shown when empty (equipment slots)
var key = null            # index or slot name, set by owner
var selected := false:
	set(value):
		selected = value
		queue_redraw()
var price := -1:
	set(value):
		price = value
		queue_redraw()
var dim := false:
	set(value):
		dim = value
		queue_redraw()
var pointer_over := false

func _init() -> void:
	custom_minimum_size = Vector2(44, 44)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func():
		pointer_over = true
		queue_redraw()
		hovered.emit(self))
	mouse_exited.connect(func():
		pointer_over = false
		queue_redraw()
		unhovered.emit(self))
	visibility_changed.connect(func():
		if not is_visible_in_tree():
			pointer_over = false
			queue_redraw())
	resized.connect(queue_redraw)

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
	var gold := SlotStyle.GOLD
	draw_rect(Rect2(at + Vector2(-1, 3), Vector2(11, 8)), Color(0, 0, 0, 0.75))
	draw_arc(at + Vector2(4.5, 3), 3.0, PI, TAU, 10, gold, 1.5)
	draw_rect(Rect2(at + Vector2(0, 4), Vector2(9, 6)), gold)
	draw_rect(Rect2(at + Vector2(4, 6), Vector2(1, 2)), Color(0.1, 0.08, 0.05))

## Corner marker rectangles (also used by the tests to prove they never overlap).
static func padlock_rect(slot_size: Vector2) -> Rect2:
	return Rect2(Vector2(slot_size.x - 12, 3) + Vector2(-1, 0), Vector2(11, 11))

static func corrupted_rect(slot_size: Vector2) -> Rect2:
	return Rect2(Vector2(slot_size.x - 12, slot_size.y - 12), Vector2(10, 10))

static func upgrade_rect(_slot_size: Vector2) -> Rect2:
	return Rect2(Vector2(3, 3), Vector2(23, 11))

static func price_rect(slot_size: Vector2) -> Rect2:
	return Rect2(Vector2(2, slot_size.y - 13), Vector2(slot_size.x - 15, 11))

## Small red "dead base" marker in the bottom-right corner of a 100% corrupted item
## (the padlock is top-right, the upgrade level top-left, a vendor price bottom-left).
func _draw_corrupted(at: Vector2) -> void:
	var red := SlotStyle.SEAL
	draw_rect(Rect2(at, Vector2(10, 10)), Color(0, 0, 0, 0.8))
	draw_rect(Rect2(at, Vector2(10, 10)), red, false, 1.0)
	draw_line(at + Vector2(2, 2), at + Vector2(8, 8), red, 1.5)
	draw_line(at + Vector2(8, 2), at + Vector2(2, 8), red, 1.5)

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var col := Data.rarity_color(item.get("rarity", "common")) if item != null else SlotStyle.BRONZE
	SlotStyle.frame(self, col, item != null, pointer_over)
	if item != null:
		var tex: Texture2D = Art.icon(item.get("icon", "charm"))
		var isz := minf(size.x, size.y) - 8
		draw_texture_rect(tex, Rect2((size - Vector2(isz, isz)) / 2, Vector2(isz, isz)), false, Color(1, 1, 1, 0.45) if dim else Color.WHITE)
		if Game.ch != null and Game.ch.equip_restriction(item) != "":
			draw_rect(r.grow(-4), Color(0.8, 0.1, 0.1, 0.2))
			# A non-colour cue, away from the four status corners.
			SlotStyle.badge(self, Rect2(Vector2(size.x / 2 - 3, size.y / 2 - 5), Vector2(7, 11)), "!", Color("#ff9690"))
		if int(item.get("upgrade", 0)) > 0:
			SlotStyle.badge(self, upgrade_rect(size), "+%d" % int(item["upgrade"]), SlotStyle.GOLD)
		if bool(item.get("locked", false)):
			_draw_padlock(Vector2(size.x - 12, 3))
		if CorruptionRules.is_maxed(item):
			_draw_corrupted(corrupted_rect(size).position)
		if price >= 0:
			SlotStyle.badge(self, price_rect(size), SlotStyle.price_text(price), SlotStyle.GOLD)
	else:
		if placeholder != "":
			var t2: Texture2D = Art.icon(placeholder)
			var isz2 := minf(size.x, size.y) - 12
			draw_texture_rect(t2, Rect2((size - Vector2(isz2, isz2)) / 2, Vector2(isz2, isz2)), false, Color(0.85, 0.81, 0.68, 0.22))
	if selected:
		SlotStyle.selection(self)
