extends Control
## Reusable skill/flask/dodge well. Input and reassignment stay in their owners.

const HUDStyle = preload("res://scripts/ui/components/hud_style.gd")
const UIKit = preload("res://scripts/ui/ui_kit.gd")
var skill := {}
var icon: Texture2D
var key_text := ""
var reason := ""
var cooldown := 0.0
var duration := 1.0
var charges := -1.0
var selected := false
var hovered := false
var dodge := false
var activation := 0.0
var completion := 0.0
var hover_amount := 0.0
var initialized := false
var identity := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(52, 60)

func present(data: Dictionary, remaining: float, full: float, blocked: String, held: bool, action: String) -> void:
	var next_id: String = data.get("id", action)
	if identity != next_id:
		initialized = false
		activation = 0
		completion = 0
		identity = next_id
	if initialized and cooldown > 0 and remaining <= 0:
		completion = 0.35
	if not initialized or remaining > cooldown + 0.05:
		duration = maxf(0.01, maxf(full, remaining))
	cooldown = maxf(0, remaining)
	skill = data
	reason = blocked
	selected = held
	key_text = HUDStyle.key_label(action)
	initialized = true

func advance(delta: float) -> void:
	activation = move_toward(activation, 0, delta)
	completion = move_toward(completion, 0, delta)
	hover_amount = move_toward(hover_amount, 1.0 if hovered else 0.0, delta * 8)
	queue_redraw()

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var emphasis := maxf(hover_amount * 0.75, 1.0 if selected else 0.0)
	HUDStyle.frame(self, r, emphasis)
	var well := Rect2(6, 5, size.x - 12, size.y - 22)
	if not skill.is_empty():
		UIKit.draw_skill_icon(self, well, skill, reason != "" and reason != "On cooldown")
	elif icon != null:
		draw_texture_rect(icon, well, false, Color(0.55, 0.55, 0.55) if reason != "" else Color.WHITE)
	elif dodge:
		draw_polyline(PackedVector2Array([well.get_center() + Vector2(-12, 8), well.get_center() + Vector2(0, -9), well.get_center() + Vector2(12, 8)]), HUDStyle.color("ivory"), 2, true)
	else:
		draw_line(well.get_center() - Vector2(6, 0), well.get_center() + Vector2(6, 0), HUDStyle.color("bronze"))
	if charges >= 0:
		for i in 3:
			draw_rect(Rect2(7 + i * (size.x - 14) / 3.0, 36, (size.x - 20) / 3.0, 3), HUDStyle.color("gold") if charges >= i + 1 else Color("#34352f"))
	if cooldown > 0:
		var fraction := clampf(cooldown / duration, 0, 1)
		draw_rect(Rect2(well.position, Vector2(well.size.x, well.size.y * fraction)), Color(0.015, 0.015, 0.02, 0.78))
		draw_line(well.position + Vector2(0, well.size.y * fraction), well.position + Vector2(well.size.x, well.size.y * fraction), Color(0.8, 0.77, 0.65, 0.45))
		HUDStyle.centered(self, well.get_center() + Vector2(0, 5), "%.1f" % cooldown if cooldown < 10 else str(int(ceil(cooldown))), 14, HUDStyle.color("ivory"))
	elif reason != "" and reason != "empty":
		draw_rect(well, Color(0.04, 0.04, 0.06, 0.35))
		draw_line(well.position, well.end, Color(0.7, 0.47, 0.4, 0.55), 1, true)
	# Key plate is outside the icon/cooldown reading area.
	draw_rect(Rect2(5, size.y - 16, size.x - 10, 12), Color("#141511"))
	var label_size := 11
	while label_size > 7 and ThemeDB.fallback_font.get_string_size(key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size).x > size.x - 8:
		label_size -= 1
	HUDStyle.centered(self, Vector2(size.x * 0.5, size.y - 6), key_text, label_size, HUDStyle.color("gold"))
	if selected:
		draw_line(Vector2(12, size.y - 2), Vector2(size.x - 12, size.y - 2), HUDStyle.color("ivory"), 2, true)
	var glow := maxf(activation, completion)
	if glow > 0:
		draw_rect(r.grow(-1), Color(0.8, 0.7, 0.45, glow * 1.4), false, 2)
