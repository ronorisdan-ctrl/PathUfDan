extends Control
## Only existing player buffs/status dictionaries supply these badges.

const HUDStyle = preload("res://scripts/ui/components/hud_style.gd")
const UIKit = preload("res://scripts/ui/ui_kit.gd")
const COLUMNS := 12
var entries := []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func present(player) -> void:
	entries.clear()
	for buff in player.buffs:
		if float(buff.get("t", 0)) <= 0: continue
		var data: Dictionary = Data.skills.get(buff["id"], {})
		entries.append({"name": data.get("name", str(buff["id"]).capitalize()), "t": buff["t"], "skill": data, "harmful": false})
	for id in player.statuses:
		var status: Dictionary = player.statuses[id]
		if float(status.get("t", 0)) <= 0: continue
		entries.append({"name": str(id).capitalize(), "t": status["t"], "skill": {}, "harmful": true})
	size = Vector2(COLUMNS * 34, maxf(0, ceil(entries.size() / float(COLUMNS)) * 36))
	position.y = 42 - size.y
	queue_redraw()

func badge_rect(index: int) -> Rect2:
	return Rect2((index % COLUMNS) * 34, (index / COLUMNS) * 36, 30, 30)

func description_at(point: Vector2) -> String:
	for i in entries.size():
		if badge_rect(i).has_point(point):
			var entry: Dictionary = entries[i]
			return "%s\n%s" % [entry["name"], "Active" if entry["t"] > 10000 else "%.1fs remaining" % entry["t"]]
	return ""

func _draw() -> void:
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var rect := badge_rect(i)
		HUDStyle.frame(self, rect)
		var skill: Dictionary = entry["skill"]
		if not skill.is_empty():
			UIKit.draw_skill_icon(self, Rect2(rect.position + Vector2(4, 3), Vector2(22, 18)), skill)
		else:
			HUDStyle.centered(self, rect.position + Vector2(15, 17), str(entry["name"]).substr(0, 1), 13, HUDStyle.color("ivory"))
		if entry["harmful"]:
			draw_rect(rect.grow(-1), HUDStyle.color("life").lightened(0.15), false, 1)
		var timer := "∞" if entry["t"] > 10000 else str(int(ceil(entry["t"])))
		HUDStyle.centered(self, rect.position + Vector2(15, 27), timer, 10, HUDStyle.color("ivory"))
