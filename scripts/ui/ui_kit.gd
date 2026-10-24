extends RefCounted
## Shared UI helpers: theme, colours, skill icon drawing, small widget builders.

const GOLD := Color("#c8a060")
const GOLD_DIM := Color("#6a5432")
const BG := Color(0.06, 0.05, 0.07, 0.96)
const BG2 := Color(0.10, 0.09, 0.12, 1.0)
const TEXT := Color("#e0d8c8")
const MUTED := Color("#8a8494")
const GOOD := Color("#80e080")
const BAD := Color("#ff6060")

static func make_theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 14
	var panel := StyleBoxFlat.new()
	panel.bg_color = BG
	panel.border_color = GOLD_DIM
	panel.set_border_width_all(2)
	panel.set_content_margin_all(10)
	panel.shadow_color = Color(0, 0, 0, 0.6)
	panel.shadow_size = 6
	th.set_stylebox("panel", "PanelContainer", panel)
	th.set_stylebox("panel", "Panel", panel)
	var b := StyleBoxFlat.new()
	b.bg_color = Color(0.16, 0.13, 0.12)
	b.border_color = GOLD_DIM
	b.set_border_width_all(1)
	b.set_content_margin_all(6)
	var bh := b.duplicate()
	bh.bg_color = Color(0.26, 0.20, 0.15)
	bh.border_color = GOLD
	var bp := b.duplicate()
	bp.bg_color = Color(0.36, 0.26, 0.16)
	var bd := b.duplicate()
	bd.bg_color = Color(0.09, 0.08, 0.08)
	bd.border_color = Color(0.25, 0.22, 0.2)
	th.set_stylebox("normal", "Button", b)
	th.set_stylebox("hover", "Button", bh)
	th.set_stylebox("pressed", "Button", bp)
	th.set_stylebox("disabled", "Button", bd)
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", TEXT)
	th.set_color("font_hover_color", "Button", Color("#fff0d0"))
	th.set_color("font_disabled_color", "Button", Color(0.45, 0.42, 0.4))
	th.set_color("font_color", "Label", TEXT)
	th.set_color("default_color", "RichTextLabel", TEXT)
	var sep := StyleBoxLine.new()
	sep.color = GOLD_DIM
	sep.thickness = 1
	th.set_stylebox("separator", "HSeparator", sep)
	var sl := StyleBoxFlat.new()
	sl.bg_color = Color(0.2, 0.17, 0.15)
	sl.set_content_margin_all(3)
	th.set_stylebox("slider", "HSlider", sl)
	var tt := StyleBoxFlat.new()
	tt.bg_color = Color(0.03, 0.03, 0.04, 0.97)
	tt.border_color = GOLD_DIM
	tt.set_border_width_all(1)
	tt.set_content_margin_all(8)
	th.set_stylebox("panel", "TooltipPanel", tt)
	return th

static func label(text: String, size: int = 14, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

static func button(text: String, cb: Callable, min_w: int = 0) -> Button:
	var b := Button.new()
	b.text = text
	if min_w > 0:
		b.custom_minimum_size.x = min_w
	b.pressed.connect(cb)
	b.pressed.connect(func(): Sfx.play("ui", 0.0))
	return b

static func rich(text: String = "", min_w: int = 0) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.text = text
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if min_w > 0:
		r.custom_minimum_size.x = min_w
	return r

static func fmt(v: float, decimals: int = 0) -> String:
	if decimals <= 0:
		return str(int(round(v)))
	return ("%." + str(decimals) + "f") % v

## Procedural skill icon: background tinted by the skill colour plus a glyph
## chosen by behaviour, so new data-defined skills get an icon automatically.
static func draw_skill_icon(ci: CanvasItem, r: Rect2, sk: Dictionary, dim: bool = false) -> void:
	var col := Color(sk.get("fx", "#ffffff"))
	var bg := col.darkened(0.75)
	if dim:
		bg = bg.darkened(0.5)
		col = col.darkened(0.5)
	ci.draw_rect(r, bg)
	ci.draw_rect(Rect2(r.position + Vector2(2, 2), r.size - Vector2(4, 4)), bg.lightened(0.08))
	var c := r.get_center()
	var s := r.size.x * 0.32
	var w := maxf(2.0, r.size.x / 14.0)
	match sk.get("behavior", ""):
		"melee_arc":
			ci.draw_arc(c + Vector2(-s * 0.4, s * 0.3), s * 1.2, -1.4, 0.2, 10, col, w * 1.4)
			ci.draw_line(c + Vector2(-s, s), c + Vector2(s * 0.9, -s * 0.9), Color.WHITE.lerp(col, 0.4), w)
		"projectile":
			var n := int(sk.get("count", 1))
			for i in mini(n, 5):
				var off := (i - (mini(n, 5) - 1) / 2.0) * s * 0.35
				ci.draw_line(c + Vector2(-s, s * 0.6 + off), c + Vector2(s, -s * 0.6 + off), col, w)
			ci.draw_circle(c + Vector2(s, -s * 0.6), w * 1.3, Color.WHITE)
		"ground_aoe":
			ci.draw_arc(c + Vector2(0, s * 0.3), s, 0, TAU, 20, col, w)
			ci.draw_circle(c + Vector2(0, s * 0.3), s * 0.35, col)
			ci.draw_line(c + Vector2(-s * 0.5, -s * 1.1), c + Vector2(0, s * 0.1), Color.WHITE, w * 0.8)
		"nova":
			ci.draw_arc(c, s * 1.1, 0, TAU, 24, col, w)
			ci.draw_arc(c, s * 0.6, 0, TAU, 18, col.lightened(0.3), w * 0.8)
			ci.draw_circle(c, s * 0.2, Color.WHITE)
		"chain":
			var pts := PackedVector2Array([c + Vector2(-s, -s), c + Vector2(-s * 0.1, -s * 0.1), c + Vector2(-s * 0.4, s * 0.2), c + Vector2(s, s)])
			ci.draw_polyline(pts, col, w * 1.3)
			ci.draw_polyline(pts, Color.WHITE, w * 0.5)
		"dash":
			for i in 3:
				var x := -s + i * s * 0.7
				ci.draw_polyline(PackedVector2Array([c + Vector2(x, -s * 0.7), c + Vector2(x + s * 0.5, 0), c + Vector2(x, s * 0.7)]), col, w)
		"blink":
			for i in 4:
				var a := TAU * i / 4.0 + PI / 4
				ci.draw_line(c, c + Vector2.RIGHT.rotated(a) * s * 1.1, col, w)
			ci.draw_circle(c, s * 0.35, Color.WHITE)
		"summon":
			var t: Texture2D = Art.icon("charm")
			ci.draw_texture_rect(t, Rect2(c - Vector2(s, s) * 1.2, Vector2(s, s) * 2.4), false, col.lightened(0.4))
		"deploy":
			var t2: Texture2D = Art.sprite("turret" if sk.get("deployable", "") == "turret" else "mine")
			ci.draw_texture_rect(t2, Rect2(c - Vector2(s, s) * 1.3, Vector2(s, s) * 2.6), false)
		"beam":
			ci.draw_line(c + Vector2(-s * 1.2, s * 0.8), c + Vector2(s * 1.2, -s * 0.8), col, w * 2.5)
			ci.draw_line(c + Vector2(-s * 1.2, s * 0.8), c + Vector2(s * 1.2, -s * 0.8), Color.WHITE, w * 0.8)
		"leap":
			ci.draw_arc(c + Vector2(0, s * 0.6), s, PI, TAU, 12, col, w)
			ci.draw_line(c + Vector2(-s * 1.1, s * 0.9), c + Vector2(s * 1.1, s * 0.9), Color.WHITE.lerp(col, 0.4), w)
		"zone":
			ci.draw_circle(c + Vector2(0, s * 0.3), s, Color(col.r, col.g, col.b, 0.45))
			for i in 4:
				var xx := -s * 0.6 + i * s * 0.4
				ci.draw_line(c + Vector2(xx, s * 0.5), c + Vector2(xx, -s * 0.4), col.lightened(0.3), w * 0.8)
		"curse":
			ci.draw_arc(c, s, 0, TAU, 20, col, w)
			ci.draw_line(c + Vector2(-s * 0.6, -s * 0.6), c + Vector2(s * 0.6, s * 0.6), col, w)
			ci.draw_line(c + Vector2(s * 0.6, -s * 0.6), c + Vector2(-s * 0.6, s * 0.6), col, w)
		"buff":
			ci.draw_polyline(PackedVector2Array([c + Vector2(-s, s * 0.2), c + Vector2(0, -s), c + Vector2(s, s * 0.2)]), col, w * 1.3)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-s, s), c + Vector2(0, 0), c + Vector2(s, s)]), col.lightened(0.3), w)
		_:
			ci.draw_circle(c, s, col)
	ci.draw_rect(r, col.darkened(0.2), false, 1.0)

static func skill_tooltip(sk: Dictionary, ch) -> String:
	var lines := []
	var col := Color(sk.get("fx", "#ffffff")).lightened(0.2).to_html(false)
	lines.append("[font_size=17][color=#%s]%s[/color][/font_size]" % [col, sk["name"]])
	var lvl: int = ch.skill_level(sk["id"]) if ch.unlocked_skills.has(sk["id"]) else 1
	lines.append("[color=#8a8494]%s - Level %d - %s[/color]" % [sk.get("kind", "").capitalize(), lvl, ", ".join(sk.get("tags", []))])
	lines.append(sk.get("desc", ""))
	if sk.has("rune_names"):
		lines.append("[color=#c080ff]Runes: %s[/color]" % ", ".join(sk["rune_names"]))
	var info := []
	if float(sk.get("cost", 0)) > 0:
		info.append("Cost: %d %s" % [int(round(float(sk["cost"]) * ch.final.get("mana_cost_mult", 1.0))), "Life" if ch.stats.has_flag("blood_magic") else "Mana"])
	if float(sk.get("cooldown", 0)) > 0:
		info.append("Cooldown: %.1fs" % (float(sk["cooldown"]) * ch.final.get("cdr_mult", 1.0)))
	if sk.get("kind") == "attack":
		info.append("Weapon effectiveness: %d%%" % int(sk.get("weapon_eff", 100)))
	if info.size() > 0:
		lines.append("[color=#c8c0d8]%s[/color]" % "   ".join(info))
	if sk.has("weapon_eff") or sk.has("base_damage"):
		var pk: Dictionary = Combat.player_packet(ch, sk)
		var parts := []
		for t in pk["dmg"]:
			parts.append("[color=#%s]%d-%d %s[/color]" % [Combat.TYPE_COLORS.get(t, Color.WHITE).to_html(false), int(pk["dmg"][t][0]), int(pk["dmg"][t][1]), t])
		lines.append("Damage per hit: " + ", ".join(parts))
		lines.append("[color=#8a8494]Crit %.1f%%  x%.2f   Avg hit %d[/color]" % [pk["crit_chance"], pk["crit_mult"], int(Combat.packet_average(pk))])
	if sk.has("weapon_req"):
		lines.append("[color=#8a8494]Requires: %s weapon[/color]" % "/".join(sk["weapon_req"]))
	if not ch.unlocked_skills.has(sk["id"]):
		lines.append("[color=#ff6060]Unlocks at level %d[/color]" % int(sk.get("unlock_level", 1)))
	return "\n".join(lines)
