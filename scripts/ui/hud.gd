extends Control
## In-game HUD: life/mana orbs, XP bar, skill hotbar with cooldowns, flasks,
## buffs, minimap, zone/objective text, boss bar and interaction prompts.

const UIKit = preload("res://scripts/ui/ui_kit.gd")
const DevRules = preload("res://scripts/core/dev_rules.gd")
const CombatDock = preload("res://scripts/ui/components/combat_dock.gd")
const HUDStyle = preload("res://scripts/ui/components/hud_style.gd")

var ui = null
var boss = null
var objective := ""
var big_map := false
var slot_rects := []
var flask_rects := []
var hover_slot := -1
var dock
var _hover_text := ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	dock = CombatDock.new()
	add_child(dock)
	Events.player_skill_used.connect(dock.trigger_skill)
	Events.boss_spawned.connect(func(b): boss = b)
	Events.objective_changed.connect(func(t): objective = t)

func _process(delta: float) -> void:
	var p = _player()
	dock.visible = p != null and Game.ch != null
	if dock.visible:
		dock.fit_to(size)
		dock.present(p, Game.ch, 0.0 if get_tree().paused else delta)
		slot_rects.clear()
		flask_rects.clear()
		for slot in dock.slots:
			slot_rects.append(Rect2(dock.position + slot.position * dock.scale, slot.size * dock.scale))
		for flask in dock.flasks:
			flask_rects.append(Rect2(dock.position + flask.position * dock.scale, flask.size * dock.scale))
	else:
		dock.source = null
		slot_rects.clear()
		flask_rects.clear()
	queue_redraw()
	_update_hover()

func _player():
	var lv = Game.level
	if lv == null or lv.player == null or not is_instance_valid(lv.player):
		return null
	return lv.player

func _update_hover() -> void:
	if ui == null:
		return
	var m := get_local_mouse_position()
	var h := -1
	var description := ""
	var p = _player()
	var blocked: bool = ui.any_blocking_open() or ui.context.visible or ui.confirm.visible
	if not blocked and p != null and dock.visible:
		for i in slot_rects.size():
			if (slot_rects[i] as Rect2).has_point(m):
				h = i
		if h >= 0:
			var slot = dock.slots[h]
			description = UIKit.skill_tooltip(slot.skill, Game.ch) if not slot.skill.is_empty() else "Empty skill slot"
			if slot.reason != "" and slot.reason != "empty":
				description += "\n[color=#c69e8c]%s[/color]" % slot.reason
			description += "\n[color=#aaa38b]Assign skills: %s[/color]" % HUDStyle.key_label("toggle_skills")
		else:
			for i in flask_rects.size():
				if (flask_rects[i] as Rect2).has_point(m):
					description = "%s flask\n%d / 3 charges\n[%s] Restore %s" % ["Life" if i == 0 else "Mana", int(Game.ch.flask_charges[i]), HUDStyle.key_label("flask_%d" % (i + 1)), "life" if i == 0 else "mana"]
			var dodge_rect := Rect2(dock.position + dock.evade.position * dock.scale, dock.evade.size * dock.scale)
			if dodge_rect.has_point(m):
				description = "Dodge  [%s]\n%.1fs cooldown remaining" % [HUDStyle.key_label("dodge"), maxf(0, p.dodge_cd)]
			if description == "":
				description = dock.statuses.description_at(dock.statuses.get_local_mouse_position())
			if description == "" and dock.life.get_global_rect().has_point(get_global_mouse_position()):
				description = "Life: " + dock.life.readout()
			if description == "" and dock.mana.get_global_rect().has_point(get_global_mouse_position()):
				description = "Mana: " + dock.mana.readout()
			if description == "" and dock.progression.get_global_rect().has_point(get_global_mouse_position()):
				description = dock.progression.character_text + "\n" + dock.progression.experience_text
	hover_slot = h
	for i in dock.slots.size():
		dock.slots[i].hovered = i == h
	for flask in dock.flasks:
		flask.hovered = not blocked and flask.get_global_rect().has_point(get_global_mouse_position())
	dock.evade.hovered = not blocked and dock.evade.get_global_rect().has_point(get_global_mouse_position())
	if description != _hover_text:
		if description != "":
			ui.show_tooltip(description)
		elif _hover_text != "" and ui.tooltip_text.text == _hover_text:
			ui.hide_tooltip()
		_hover_text = description

func _draw() -> void:
	var p = _player()
	if p == null or Game.ch == null:
		return
	var ch = Game.ch
	var vs := size
	var f := ThemeDB.fallback_font
	var lv = Game.level
	_draw_zone(lv, ch, vs)
	# ---------------- interaction prompt
	var it = lv.nearest_interactable(p.global_position)
	if it != null:
		var tx: String = "[%s] %s" % [HUDStyle.key_label("interact"), it["name"]]
		var tw := f.get_string_size(tx, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		var prompt_y := minf(dock.position.y, dock.position.y + dock.statuses.position.y * dock.scale.y) - 14
		HUDStyle.text(self, Vector2(vs.x / 2 - tw / 2, prompt_y), tx, 16, HUDStyle.color("ivory"))
	# ---------------- minimap
	if "minimap_tex" in lv and lv.minimap_tex != null:
		_minimap(lv, p, vs)
	# ---------------- boss bar
	if boss != null and is_instance_valid(boss) and boss.alive:
		var bw := minf(520, maxf(280, vs.x - 2 * (minf(400, vs.x * 0.29) + 32)))
		var br2 := Rect2(vs.x / 2 - bw / 2, 32, bw, 14)
		HUDStyle.frame(self, br2.grow(5))
		draw_rect(br2, HUDStyle.color("life").darkened(0.75))
		draw_rect(Rect2(br2.position, Vector2(bw * clampf(boss.life / maxf(1, boss.max_life), 0, 1), br2.size.y)), HUDStyle.color("life") if boss.get("phase") != 2 else HUDStyle.color("life").lightened(0.15))
		var ps = boss.get("poise_state")
		if ps is Dictionary and not ps.is_empty():
			# poise bar: gold fills toward a stagger; grey shows the immunity that follows
			var pr := Rect2(br2.position + Vector2(0, br2.size.y + 4), Vector2(bw, 4))
			draw_rect(pr.grow(1), Color(0, 0, 0, 0.9))
			var pcfg: Dictionary = Data.stun_cfg.get("poise", {})
			if ps["stagger"] > 0.0:
				draw_rect(pr, Color("#fff0a0"))
			elif ps["immune"] > 0.0:
				var full := float(pcfg.get("immunity_after_stagger", 8.0)) + float(pcfg.get("stagger_duration", 1.0))
				draw_rect(Rect2(pr.position, Vector2(bw * clampf(ps["immune"] / full, 0, 1), pr.size.y)), Color("#606060"))
			else:
				draw_rect(Rect2(pr.position, Vector2(bw * clampf(ps["poise"] / 100.0, 0, 1), pr.size.y)), Color("#e0b040"))
		var bn: String = boss.display_name
		var bnw := f.get_string_size(bn, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_string_outline(f, Vector2(vs.x / 2 - bnw / 2, 18), bn, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color.BLACK)
		draw_string(f, Vector2(vs.x / 2 - bnw / 2, 18), bn, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#ffb090"))
	# ---------------- developer tools
	if Dev.enabled():
		_dev_tag(f, vs)
		if Dev.flags.get("overlay", false):
			_dev_overlay(f, vs)

func _wrapped(value: String, width: float, font_size: int = 13) -> Array:
	var result := []
	var font := ThemeDB.fallback_font
	for paragraph in value.split("\n"):
		var line := ""
		for word in paragraph.split(" "):
			var next := word if line == "" else line + " " + word
			if line != "" and font.get_string_size(next, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
				result.append(line)
				line = word
			else:
				line = next
		if line != "": result.append(line)
	return result

func _draw_zone(lv, ch, vs: Vector2) -> void:
	var width := minf(400, vs.x * 0.29)
	var obj: String = lv.objective_text() if lv.has_method("objective_text") else objective
	var lines := _wrapped(obj, width - 28)
	var prompts := []
	var points: int = ch.available_passive_points()
	if points > 0:
		prompts.append("%d passive point%s  [%s]" % [points, "s" if points > 1 else "", HUDStyle.key_label("toggle_passives")])
	var spec_points: int = ch.spec_points_available() if ch.level >= ch.SPEC_LEVELS[0] else 0
	if ch.spec_id == "" and ch.level >= ch.SPEC_LEVELS[0]: spec_points = 1
	if spec_points > 0:
		prompts.append(("Choose a specialisation" if ch.spec_id == "" else "%d specialisation point%s" % [spec_points, "s" if spec_points > 1 else ""]) + "  [%s]" % HUDStyle.key_label("toggle_spec"))
	var height := 62.0 + (lines.size() + prompts.size()) * 17
	HUDStyle.frame(self, Rect2(12, 12, width, height))
	var title_size := 20
	var title_font: Font = HUDStyle.THEME.get_font("font", "Title")
	while title_size > 13 and title_font.get_string_size(lv.level_name, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x > width - 28:
		title_size -= 1
	HUDStyle.text(self, Vector2(26, 38), lv.level_name, title_size, HUDStyle.color("gold"), true)
	draw_line(Vector2(26, 47), Vector2(width - 2, 47), HUDStyle.color("bronze").darkened(0.35))
	var y := 65.0
	for line in lines:
		HUDStyle.text(self, Vector2(26, y), line, 13, HUDStyle.color("ivory"))
		y += 17
	HUDStyle.text(self, Vector2(26, y + 3), "Gold  %d" % ch.gold, 13, HUDStyle.color("gold"))
	y += 21
	for prompt in prompts:
		HUDStyle.text(self, Vector2(26, y), prompt, 12, HUDStyle.color("ivory"))
		y += 17

func minimap_rect(vs: Vector2) -> Rect2:
	if not big_map:
		return Rect2(vs.x - 210, 14, 196, 150)
	var available := Rect2(24, 80, vs.x - 48, maxf(80, dock.position.y - 126))
	var dimensions := Vector2(minf(720, available.size.x), minf(480, available.size.y))
	return Rect2(available.position + (available.size - dimensions) * 0.5, dimensions)

## Small "DEV" tag above the life orb so the tools are never on by accident.
func _dev_tag(f: Font, vs: Vector2) -> void:
	var r := Rect2(14, vs.y - 160, 44, 18)
	draw_rect(r, Color(0.5, 0.05, 0.4, 0.85))
	draw_rect(r, Color("#ff80e0"), false, 1.0)
	draw_string(f, r.position + Vector2(7, 14), "DEV", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
	var active: Array = DevRules.active_flags(Dev.flags)
	if not active.is_empty():
		var t := "  ".join(active)
		draw_string_outline(f, r.position + Vector2(52, 14), t, HORIZONTAL_ALIGNMENT_LEFT, vs.x - 260, 11, 3, Color.BLACK)
		draw_string(f, r.position + Vector2(52, 14), t, HORIZONTAL_ALIGNMENT_LEFT, vs.x - 260, 11, Color("#ffb0f0"))

func _dev_overlay(f: Font, vs: Vector2) -> void:
	var lines: Array = Dev.overlay_lines()
	var x := vs.x - 300.0
	var y := 186.0
	draw_rect(Rect2(x - 6, y - 14, 292, 16 * lines.size() + 8), Color(0, 0, 0, 0.6))
	for l in lines:
		draw_string(f, Vector2(x, y), l, HORIZONTAL_ALIGNMENT_LEFT, 286, 12, Color("#c0ffc0"))
		y += 16

func _minimap(lv, p, vs: Vector2) -> void:
	var mscale := 2.0 if not big_map else 4.0
	var mr := minimap_rect(vs)
	HUDStyle.frame(self, mr.grow(5))
	var pc: Vector2 = p.global_position / float(lv.T)
	var origin := mr.get_center() - pc * mscale
	# clip by drawing only the texture region that fits
	var src_size := mr.size / mscale
	var src := Rect2(pc - src_size / 2, src_size)
	draw_texture_rect_region(lv.minimap_tex, mr, src)
	# markers
	for e in lv.enemies:
		if is_instance_valid(e) and e.alive:
			var c: Vector2 = e.global_position / float(lv.T)
			var ep := origin + c * mscale
			if mr.has_point(ep) and lv.reveal[int(c.y) * lv.gw + int(c.x)] == 1:
				draw_rect(Rect2(ep - Vector2(1, 1), Vector2(2, 2) * (1.5 if e.is_elite or e.is_boss else 1.0)), Color("#ff4040") if not e.is_elite else e.elite_color)
	for it in lv.interactables:
		var ip: Vector2 = origin + it["pos"] / float(lv.T) * mscale
		if mr.has_point(ip):
			draw_circle(ip, 3, Color("#ffd060") if it["kind"] == "exit_portal" else Color("#6080ff"))
	# loot filter minimap icons
	for n in lv.loot:
		if is_instance_valid(n) and not n.picked and n.visible and n.kind == "item":
			var mm: Dictionary = n.fres.get("minimap", {})
			if mm.is_empty():
				continue
			var lp: Vector2 = origin + n.global_position / float(lv.T) * mscale
			if not mr.has_point(lp):
				continue
			var mc: Color = mm.get("color", Color.WHITE)
			match str(mm.get("shape", "circle")):
				"diamond":
					draw_colored_polygon(PackedVector2Array([lp + Vector2(0, -4), lp + Vector2(3, 0), lp + Vector2(0, 4), lp + Vector2(-3, 0)]), mc)
				"square":
					draw_rect(Rect2(lp - Vector2(2.5, 2.5), Vector2(5, 5)), mc)
				"star":
					draw_string(ThemeDB.fallback_font, lp + Vector2(-4, 4), "*", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, mc)
				_:
					draw_circle(lp, 2.5, mc)
	if lv.get("rooms") != null:
		for r in lv.rooms:
			if r["kind"] == "boss" and r["visited"]:
				var bp: Vector2 = origin + Vector2(r["anchor"]) * mscale
				if mr.has_point(bp):
					draw_string(ThemeDB.fallback_font, bp + Vector2(-4, 4), "X", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#ff6060"))
	draw_circle(mr.get_center(), 2.5, Color("#60ff60"))
	draw_rect(mr, HUDStyle.color("bronze"), false, 1.0)
