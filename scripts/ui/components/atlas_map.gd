extends Control
## Draws the Atlas of Ruin hex map (Endgame Phase 1A) and reports clicks.
## Hidden hexes next to a revealed one are drawn as faint fog outlines; the rest stay dark.
## Rot (Phase 1C): green stain + level number, a heart mark at Heart levels, a gold inner frame on
## Restored hexes and a dashed green ring on the hexes the next completion will spread to.

const AtlasRules = preload("res://scripts/core/atlas_rules.gd")
const UIKit = preload("res://scripts/ui/ui_kit.gd")

signal hex_clicked(h: Vector2i)

var state := {}
var selected := Vector2i(9999, 9999)
var hover := Vector2i(9999, 9999)
var hex_size := 30.0
var forecast := []   # keys the next spread will raise (set_state)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(400, 360)

func set_state(st: Dictionary, sel: Vector2i) -> void:
	state = st
	selected = sel
	forecast = AtlasRules.forecast(st) if not st.is_empty() else []
	queue_redraw()

func _fit() -> void:
	var rad := AtlasRules.radius()
	var by_w := size.x / (sqrt(3.0) * (2 * rad + 1) + 0.6)
	var by_h := size.y / (3.0 * rad + 2.4)
	hex_size = maxf(8.0, minf(by_w, by_h))

func hex_center(h: Vector2i) -> Vector2:
	return size / 2 + AtlasRules.to_pixel(h, hex_size)

func hex_at(p: Vector2) -> Vector2i:
	_fit()
	return AtlasRules.from_pixel(p - size / 2, hex_size)

func _corners(c: Vector2, s: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var a := deg_to_rad(60.0 * i - 30.0)
		pts.append(c + Vector2(cos(a), sin(a)) * s)
	return pts

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var h := hex_at(e.position)
		if h != hover:
			hover = h
			queue_redraw()
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var h2 := hex_at(e.position)
		if AtlasRules.in_atlas(h2):
			hex_clicked.emit(h2)
			accept_event()

func _fog(h: Vector2i) -> bool:
	for n in AtlasRules.neighbours(h):
		if AtlasRules.ring_of(n) == 0 or AtlasRules.is_revealed(state, n):
			return true
	return false

func _draw() -> void:
	_fit()
	draw_rect(Rect2(Vector2.ZERO, size), Color("#0c0b0e"))
	if state.is_empty():
		return
	var s0 := int(state.get("seed", 0))
	var font := get_theme_default_font()
	for h in AtlasRules.within(Vector2i.ZERO, AtlasRules.radius()):
		var c := hex_center(h)
		var pts := _corners(c, hex_size - 1.5)
		var ring := AtlasRules.ring_of(h)
		if ring == 0:
			draw_colored_polygon(pts, Color("#3a3428"))
			draw_polyline(pts + PackedVector2Array([pts[0]]), UIKit.GOLD, 2.0)
			draw_string(font, c + Vector2(-14, 4), "Hub", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIKit.GOLD)
			continue
		var rc := AtlasRules.ring_cfg(ring)
		var layer_col := Color(str(rc.get("color", "#808080")))
		if not AtlasRules.is_revealed(state, h):
			if _fog(h):
				draw_colored_polygon(pts, Color("#16141a"))
				draw_polyline(pts + PackedVector2Array([pts[0]]), Color(layer_col, 0.25), 1.0)
			continue
		var info := AtlasRules.hex_info(s0, h)
		var col := Color(str(info.get("biome_color", "#606060")))
		var n := AtlasRules.clears(state, h)
		draw_colored_polygon(pts, col.darkened(0.15) if n > 0 else col.darkened(0.55))
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color(layer_col, 0.9), 1.5)
		if info.get("vantage", false):
			var d := hex_size * 0.22
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0)]), Color("#ffe8a0"))
		if n > 0:
			draw_circle(c + Vector2(hex_size * 0.42, -hex_size * 0.35), hex_size * 0.12, UIKit.GOOD)
		var mech := AtlasRules.mechanic_info(AtlasRules.natural_mechanic(s0, h, n, float(AtlasRules.varnish_fx(state)["natural_mult"])))
		if not mech.is_empty():   # Phase 1D: a small square in the mechanic's colour (top left)
			var mq := hex_size * 0.11
			var mc := c + Vector2(-hex_size * 0.42, -hex_size * 0.35)
			draw_rect(Rect2(mc - Vector2(mq, mq), Vector2(mq, mq) * 2.0), Color(str(mech.get("color", "#ffffff"))))
			draw_rect(Rect2(mc - Vector2(mq, mq), Vector2(mq, mq) * 2.0), Color(0, 0, 0, 0.8), false, 1.0)
		var mi := 0
		for mm in AtlasRules.minor_mechanics(s0, h, n, float(AtlasRules.varnish_fx(state)["natural_mult"])):   # Phase 2D: minor mechanics as small dots below
			mi += 1
			var md := AtlasRules.mechanic_info(mm)
			draw_circle(c + Vector2(-hex_size * 0.42 + (mi - 1) * hex_size * 0.2, -hex_size * 0.1), hex_size * 0.07, Color(str(md.get("color", "#ffffff"))))
		_draw_rot(h, c, font)
		if AtlasRules.warden_at(state, h) > 0:   # Phase 2A: a gold crown on a summoned Warden
			var wq := hex_size * 0.16
			var wcen := c + Vector2(hex_size * 0.42, hex_size * 0.32)
			var crown := PackedVector2Array([wcen + Vector2(-wq, wq * 0.6), wcen + Vector2(-wq, -wq * 0.5), wcen + Vector2(-wq * 0.5, 0), wcen + Vector2(0, -wq * 0.8), wcen + Vector2(wq * 0.5, 0), wcen + Vector2(wq, -wq * 0.5), wcen + Vector2(wq, wq * 0.6)])
			draw_colored_polygon(crown, Color(str(AtlasRules.ward_cfg().get("colors", {}).get("summon", "#ffe070"))))
			draw_polyline(crown + PackedVector2Array([crown[0]]), Color(0, 0, 0, 0.8), 1.0)
		if h == hover:
			draw_polyline(pts + PackedVector2Array([pts[0]]), Color(1, 1, 1, 0.5), 2.0)
	if AtlasRules.in_atlas(selected) and AtlasRules.ring_of(selected) > 0:
		var sp := _corners(hex_center(selected), hex_size - 1.0)
		draw_polyline(sp + PackedVector2Array([sp[0]]), UIKit.GOLD, 3.0)

func _draw_rot(h: Vector2i, c: Vector2, font: Font) -> void:
	var cols: Dictionary = AtlasRules.rot_cfg().get("colors", {})
	var rot := AtlasRules.rot_of(state, h)
	if AtlasRules.is_restored(state, h):
		var ip := _corners(c, hex_size * 0.78)
		draw_polyline(ip + PackedVector2Array([ip[0]]), Color(str(cols.get("restored", "#e8c060"))), 2.0)
	if rot > 0:
		# foxing: umber blotches that grow with Rot, plus a level badge
		var stain := Color(str(cols.get("stain", "#4a2a12")))
		var hc := Color(str(cols.get("heart", "#d8e070")))
		var rng := RandomNumberGenerator.new()
		rng.seed = (h.x + 50) * 977 + (h.y + 50) * 31
		for i in 2 + rot:
			var off := Vector2(rng.randf_range(-0.42, 0.42), rng.randf_range(-0.36, 0.36)) * hex_size
			draw_circle(c + off, hex_size * rng.randf_range(0.1, 0.16 + 0.025 * rot), Color(stain, 0.55 + 0.07 * rot))
		var bp := c + Vector2(-hex_size * 0.5, hex_size * 0.38)
		draw_circle(bp, hex_size * 0.2, Color("#141008"))
		draw_arc(bp, hex_size * 0.2, 0, TAU, 14, hc, 1.2)
		draw_string(font, bp + Vector2(-4, 5), str(rot), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, hc)
		if AtlasRules.is_heart(rot, AtlasRules.heart_at_for(state)):
			var hp := c + Vector2(0, hex_size * 0.48)
			var hpts := PackedVector2Array([hp + Vector2(0, hex_size * 0.16), hp + Vector2(-hex_size * 0.16, -hex_size * 0.02), hp + Vector2(-hex_size * 0.08, -hex_size * 0.12), hp + Vector2(0, -hex_size * 0.05), hp + Vector2(hex_size * 0.08, -hex_size * 0.12), hp + Vector2(hex_size * 0.16, -hex_size * 0.02)])
			draw_colored_polygon(hpts, Color("#b03020"))
			draw_polyline(hpts + PackedVector2Array([hpts[0]]), hc, 1.2)
	var fc := forecast.count(AtlasRules.key(h))
	if fc > 0:
		var fp := _corners(c, hex_size * 0.62)
		var col := Color(str(cols.get("forecast", "#9ab84a")), 0.85)
		for i in 6:
			if i % 2 == 0:
				draw_line(fp[i], fp[(i + 1) % 6], col, 1.5)
		draw_string(font, c + Vector2(hex_size * 0.3, hex_size * 0.5), "+%d" % fc, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
