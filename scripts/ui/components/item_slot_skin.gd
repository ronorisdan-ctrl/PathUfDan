extends RefCounted
## Native cabinet wells. Pure presentation: no item rules, input or child Controls.

const HUDStyle = preload("res://scripts/ui/components/hud_style.gd")
const GOLD := Color("#ffd060")
const BRONZE := Color("#66583b")
const SEAL := Color("#ed6660")

static func frame(view: Control, rarity: Color, occupied: bool, hover: bool) -> void:
	var rect := Rect2(Vector2.ZERO, view.size)
	view.draw_rect(rect, Color("#070b09"))
	view.draw_rect(rect.grow(-1), BRONZE.darkened(0.3), false)
	view.draw_rect(rect.grow(-3), Color("#131813"))
	view.draw_line(Vector2(3, 3), Vector2(view.size.x - 3, 3), Color("#020604"))
	view.draw_line(Vector2(3, 3), Vector2(3, view.size.y - 3), Color("#020604"))
	view.draw_line(Vector2(3, view.size.y - 3), view.size - Vector2(3, 3), Color("#454131"))
	if occupied:
		view.draw_rect(rect.grow(-4), Color(rarity.r, rarity.g, rarity.b, 0.12))
		view.draw_rect(rect.grow(-2), rarity.darkened(0.15), false)
	if hover:
		view.draw_rect(rect.grow(-1), Color("#ded8bb"), false)
		view.draw_rect(rect.grow(-4), Color(0.9, 0.85, 0.65, 0.06))

static func selection(view: Control) -> void:
	# Broken inner brackets leave the rarity rim and all marker corners visible.
	for point in [Vector2(5, 17), Vector2(view.size.x - 5, 17)]:
		view.draw_line(point, point + Vector2(0, view.size.y - 34), GOLD, 2)
		var dx := 3 if point.x < view.size.x / 2 else -3
		view.draw_line(point, point + Vector2(dx, 0), GOLD)
		view.draw_line(point + Vector2(0, view.size.y - 34), point + Vector2(dx, view.size.y - 34), GOLD)

static func badge(view: Control, rect: Rect2, text: String, color: Color) -> void:
	view.draw_rect(rect, Color(0.025, 0.035, 0.025, 0.96))
	HUDStyle.text(view, rect.position + Vector2(1, 9), text, 10, color)

static func price_text(value: int) -> String:
	# Keep the bottom-right seal clear even for expensive high-level vendor stock.
	if value < 10000:
		return str(value)
	for unit in [[1000000000, "b"], [1000000, "m"], [1000, "k"]]:
		if value >= unit[0]:
			var amount := float(value) / float(unit[0])
			return ("%.1f" % (floor(amount * 10) / 10) if amount < 10 else str(int(amount))) + unit[1]
	return str(value)
