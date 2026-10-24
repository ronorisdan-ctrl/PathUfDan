extends Control
## In-game HUD: life/mana orbs, XP bar, skill hotbar with cooldowns, flasks,
## buffs, minimap, zone/objective text, boss bar and interaction prompts.

const UIKit = preload("res://scripts/ui/ui_kit.gd")

var ui = null
var boss = null
var objective := ""
var big_map := false
var slot_rects := []
var flask_rects := []
var hover_slot := -1

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Events.boss_spawned.connect(func(b): boss = b)
	Events.objective_changed.connect(func(t): objective = t)

func _process(_delta: float) -> void:
	queue_redraw()
	_update_hover()

func _player():
	var lv = Game.level
	if lv == null or lv.player == null or not is_instance_valid(lv.player):
		return null
	return lv.player

func _update_hover() -> void:
	var m := get_local_mouse_position()
	var h := -1
	for i in slot_rects.size():
		if (slot_rects[i] as Rect2).has_point(m):
			h = i
	if h != hover_slot:
		hover_slot = h
		var p = _player()
		if h >= 0 and p != null:
			var sk: Dictionary = p.skill_in_slot(h)
			if not sk.is_empty():
				ui.show_tooltip(UIKit.skill_tooltip(sk, Game.ch))
			else:
				ui.show_tooltip("Empty skill slot\n[color=#8a8494]Press K to assign skills[/color]")
		else:
			ui.hide_tooltip()

func _draw() -> void:
	var p = _player()
	if p == null or Game.ch == null:
		return
	var ch = Game.ch
	var vs := size
	var f := ThemeDB.fallback_font
	# ---------------- orbs
	_orb(Vector2(78, vs.y - 78), 58, p.life / maxf(1.0, p.max_life), Color("#b02020"), Color("#3a0808"), "%d / %d" % [int(ceil(p.life)), int(p.max_life)])
	var mm: float = ch.final.get("max_mana", 1)
	_orb(Vector2(vs.x - 78, vs.y - 78), 58, p.mana / maxf(1.0, mm), Color("#2848c0"), Color("#080c30"), "%d / %d" % [int(p.mana), int(mm)])
	# ---------------- xp bar
	var xr := Rect2(150, vs.y - 12, vs.x - 300, 8)
	draw_rect(xr.grow(1), Color(0, 0, 0, 0.8))
	draw_rect(Rect2(xr.position, Vector2(xr.size.x * clampf(float(ch.xp) / ch.xp_to_next(), 0, 1), xr.size.y)), Color("#c8a040"))
	for i in range(1, 10):
		draw_line(xr.position + Vector2(xr.size.x * i / 10.0, 0), xr.position + Vector2(xr.size.x * i / 10.0, xr.size.y), Color(0, 0, 0, 0.5))
	draw_string_outline(f, Vector2(xr.position.x, xr.position.y - 4), "Level %d" % ch.level, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 3, Color.BLACK)
	draw_string(f, Vector2(xr.position.x, xr.position.y - 4), "Level %d" % ch.level, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#e8d8a0"))
	var xpt: String = "%d / %d XP" % [ch.xp, ch.xp_to_next()]
	var xw := f.get_string_size(xpt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string_outline(f, Vector2(xr.end.x - xw, xr.position.y - 4), xpt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color.BLACK)
	draw_string(f, Vector2(xr.end.x - xw, xr.position.y - 4), xpt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIKit.MUTED)
	# ---------------- hotbar
	var keys := ["LMB", "RMB", "Q", "E", "R", "T", "G"]
	var sz := 50.0
	var gap := 6.0
	var total := 7 * sz + 6 * gap
	var x0 := vs.x / 2 - total / 2 + 40
	var y0 := vs.y - sz - 26
	slot_rects.clear()
	for i in keys.size():
		var r := Rect2(x0 + i * (sz + gap), y0, sz, sz)
		slot_rects.append(r)
		draw_rect(r.grow(2), Color(0, 0, 0, 0.85))
		var sk: Dictionary = p.skill_in_slot(i)
		if sk.is_empty():
			draw_rect(r, Color(0.1, 0.09, 0.1))
		else:
			var blocked: String = p.use_block_reason(sk)
			UIKit.draw_skill_icon(self, r, sk, blocked != "" and blocked != "On cooldown")
			var cd: float = p.cooldowns.get(sk["id"], 0.0)
			if cd > 0:
				var full: float = maxf(0.01, float(sk.get("cooldown", 1)) * ch.final.get("cdr_mult", 1.0))
				var k := clampf(cd / full, 0, 1)
				draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * k)), Color(0, 0, 0, 0.65))
				var ct := "%.1f" % cd
				var cw := f.get_string_size(ct, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
				draw_string_outline(f, r.get_center() + Vector2(-cw / 2, 6), ct, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 3, Color.BLACK)
				draw_string(f, r.get_center() + Vector2(-cw / 2, 6), ct, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
			elif p.mana < p.mana_cost(sk) and not ch.stats.has_flag("blood_magic"):
				draw_rect(r, Color(0.1, 0.15, 0.6, 0.45))
		draw_rect(r, UIKit.GOLD_DIM if hover_slot != i else UIKit.GOLD, false, 1.5)
		draw_string_outline(f, r.position + Vector2(3, 12), keys[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color.BLACK)
		draw_string(f, r.position + Vector2(3, 12), keys[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#f0e0b0"))
	# flasks
	flask_rects.clear()
	for i in 2:
		var fr := Rect2(x0 - 2 * 40 - 16 + i * 40, y0 + 6, 34, 44)
		flask_rects.append(fr)
		draw_rect(fr.grow(2), Color(0, 0, 0, 0.85))
		draw_rect(fr, Color(0.1, 0.09, 0.1))
		var charges: float = ch.flask_charges[i]
		var fc := Color("#b02020") if i == 0 else Color("#2848c0")
		draw_rect(Rect2(fr.position.x + 3, fr.end.y - 3 - (fr.size.y - 6) * clampf(charges / 3.0, 0, 1), fr.size.x - 6, (fr.size.y - 6) * clampf(charges / 3.0, 0, 1)), Color(fc.r, fc.g, fc.b, 0.5))
		draw_texture_rect(Art.icon("flask_life" if i == 0 else "flask_mana"), Rect2(fr.position + Vector2(3, 6), Vector2(28, 28)), false)
		draw_rect(fr, UIKit.GOLD_DIM, false, 1.0)
		draw_string(f, fr.position + Vector2(3, 12), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#f0e0b0"))
		draw_string(f, Vector2(fr.position.x + 3, fr.end.y - 3), "%d" % int(charges), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
	# dodge
	var dr := Rect2(x0 + 7 * (sz + gap) + 4, y0 + 14, 36, 36)
	draw_rect(dr.grow(2), Color(0, 0, 0, 0.85))
	draw_rect(dr, Color(0.12, 0.11, 0.1))
	draw_polyline(PackedVector2Array([dr.get_center() + Vector2(-10, 6), dr.get_center() + Vector2(0, -8), dr.get_center() + Vector2(10, 6)]), Color("#d0c0a0"), 2.5)
	if p.dodge_cd > 0:
		draw_rect(Rect2(dr.position, Vector2(dr.size.x, dr.size.y * clampf(p.dodge_cd / p.DODGE_CD, 0, 1))), Color(0, 0, 0, 0.6))
	draw_string(f, dr.position + Vector2(2, 11), "Spc", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#f0e0b0"))
	# buffs
	var bx := x0
	for b in p.buffs:
		if b["t"] > 10000:
			continue
		var br := Rect2(bx, y0 - 28, 22, 22)
		var bsk: Dictionary = Data.skills.get(b["id"], {"fx": "#c0c0ff", "behavior": "buff"})
		UIKit.draw_skill_icon(self, br, bsk)
		draw_string(f, br.position + Vector2(0, -2), "%d" % int(ceil(b["t"])), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
		bx += 26
	# ---------------- top-left info
	var lv = Game.level
	var tl := Vector2(16, 26)
	draw_string_outline(f, tl, lv.level_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 4, Color.BLACK)
	draw_string(f, tl, lv.level_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#e8c890"))
	var oy := tl.y + 20
	var obj := objective
	if lv.has_method("objective_text"):
		obj = lv.objective_text()
	for line in obj.split("\n"):
		if line == "":
			continue
		draw_string_outline(f, Vector2(tl.x, oy), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 3, Color.BLACK)
		draw_string(f, Vector2(tl.x, oy), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#c8c0b0"))
		oy += 16
	var gold_t: String = "Gold: %d" % ch.gold
	draw_string_outline(f, Vector2(tl.x, oy + 4), gold_t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 3, Color.BLACK)
	draw_string(f, Vector2(tl.x, oy + 4), gold_t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#e8c050"))
	var spts: int = ch.spec_points_available() if ch.level >= ch.SPEC_LEVELS[0] else 0
	if ch.spec_id == "" and ch.level >= ch.SPEC_LEVELS[0]:
		spts = 1
	if spts > 0:
		var st: String = "Choose a specialisation - press J" if ch.spec_id == "" else "%d specialisation point%s - press J" % [spts, "s" if spts > 1 else ""]
		draw_string_outline(f, Vector2(tl.x, oy + 40), st, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 3, Color.BLACK)
		draw_string(f, Vector2(tl.x, oy + 40), st, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#ffb060"))
	var pts: int = ch.available_passive_points()
	if pts > 0:
		var pt: String = "%d unspent passive point%s - press P" % [pts, "s" if pts > 1 else ""]
		draw_string_outline(f, Vector2(tl.x, oy + 22), pt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 3, Color.BLACK)
		draw_string(f, Vector2(tl.x, oy + 22), pt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#80ff80"))
	# ---------------- interaction prompt
	var it = lv.nearest_interactable(p.global_position)
	if it != null:
		var tx: String = "[F] %s" % it["name"]
		var tw := f.get_string_size(tx, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		draw_string_outline(f, Vector2(vs.x / 2 - tw / 2, vs.y - 150), tx, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color.BLACK)
		draw_string(f, Vector2(vs.x / 2 - tw / 2, vs.y - 150), tx, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#ffe0a0"))
	# ---------------- minimap
	if "minimap_tex" in lv and lv.minimap_tex != null:
		_minimap(lv, p, vs)
	# ---------------- boss bar
	if boss != null and is_instance_valid(boss) and boss.alive:
		var bw := 520.0
		var br2 := Rect2(vs.x / 2 - bw / 2, 22, bw, 16)
		draw_rect(br2.grow(2), Color(0, 0, 0, 0.9))
		draw_rect(br2, Color("#2a0808"))
		draw_rect(Rect2(br2.position, Vector2(bw * clampf(boss.life / boss.max_life, 0, 1), br2.size.y)), Color("#a01818") if boss.get("phase") != 2 else Color("#d03030"))
		draw_rect(br2, UIKit.GOLD_DIM, false, 1.0)
		var bn: String = boss.display_name
		var bnw := f.get_string_size(bn, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_string_outline(f, Vector2(vs.x / 2 - bnw / 2, 18), bn, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color.BLACK)
		draw_string(f, Vector2(vs.x / 2 - bnw / 2, 18), bn, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#ffb090"))

func _orb(c: Vector2, r: float, k: float, col: Color, dark: Color, text: String) -> void:
	draw_circle(c, r + 4, Color(0, 0, 0, 0.9))
	draw_circle(c, r, dark)
	k = clampf(k, 0, 1)
	# fill from the bottom using horizontal slices
	var top := c.y + r - 2 * r * k
	var y := c.y - r
	while y < c.y + r:
		if y >= top:
			var dy := absf(y + 1 - c.y)
			var hw := sqrt(maxf(0.0, r * r - dy * dy))
			draw_line(Vector2(c.x - hw, y + 1), Vector2(c.x + hw, y + 1), col, 2.0)
		y += 2
	draw_arc(c, r, 0, TAU, 48, UIKit.GOLD_DIM, 3.0)
	draw_arc(c + Vector2(-r * 0.3, -r * 0.35), r * 0.45, PI * 1.1, PI * 1.6, 8, Color(1, 1, 1, 0.25), 3.0)
	var f := ThemeDB.fallback_font
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string_outline(f, c + Vector2(-w / 2, 5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 3, Color.BLACK)
	draw_string(f, c + Vector2(-w / 2, 5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)

func _minimap(lv, p, vs: Vector2) -> void:
	var mscale := 2.0 if not big_map else 4.0
	var mr := Rect2(vs.x - 210, 14, 196, 150) if not big_map else Rect2(vs.x / 2 - 360, vs.y / 2 - 260, 720, 480)
	draw_rect(mr.grow(2), Color(0, 0, 0, 0.6 if not big_map else 0.4))
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
	if lv.get("rooms") != null:
		for r in lv.rooms:
			if r["kind"] == "boss" and r["visited"]:
				var bp: Vector2 = origin + Vector2(r["anchor"]) * mscale
				if mr.has_point(bp):
					draw_string(ThemeDB.fallback_font, bp + Vector2(-4, 4), "X", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#ff6060"))
	draw_circle(mr.get_center(), 2.5, Color("#60ff60"))
	draw_rect(mr, UIKit.GOLD_DIM, false, 1.0)
