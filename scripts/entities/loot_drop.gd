extends Node2D
## An item, gold pile or crafting material lying on the floor.

var level = null
var kind := "item"       # item | gold | material
var item := {}
var amount := 0
var mat_id := ""
var color := Color.WHITE
var label := ""
var t := 0.0
var pop := Vector2.ZERO
var picked := false
var hidden_by_filter := false
var label_off := 0.0   # vertical offset so overlapping labels stack
var claimed_by = null  # the pet (or player) reaching for this drop; first claim wins
var magnet_by = null   # the pet whose magnet is pulling this drop
var fres := {}         # last LootFilter.evaluate() result (items only; empty = unfiltered)
var fs := 8            # label font size chosen by the filter
var label_color := Color.WHITE
var beam_color = null  # Color from the filter, or null for the default rarity beam

func setup_item(it: Dictionary) -> void:
	kind = "item"
	item = it
	color = Data.rarity_color(it.get("rarity", "common"))
	label = it.get("name", "Item")

func setup_gold(n: int) -> void:
	kind = "gold"
	amount = n
	color = Color("#e8c050")
	label = "%d Gold" % n

func setup_rune(id: String) -> void:
	kind = "rune"
	mat_id = id
	amount = 1
	var rd: Dictionary = Data.skill_runes.get(id, {})
	color = Color(rd.get("color", "#c080ff"))
	label = rd.get("name", "Rune")

func setup_gem(id: String) -> void:
	kind = "gem"
	mat_id = id
	amount = 1
	color = Loot.gem_color(id)
	label = Loot.gem_name(id)

func setup_material(id: String, n: int) -> void:
	kind = "material"
	mat_id = id
	amount = n
	var md: Dictionary = Data.materials.get(id, {})
	color = Color(md.get("color", "#ffffff"))
	label = md.get("name", id)

func _ready() -> void:
	z_index = 2
	pop = Vector2(randf_range(-14, 14), randf_range(-10, 10))
	refresh_filter()
	if kind == "item" and (not Game.testing or Game.filter_in_tests):
		LootFilter.filter_changed.connect(refresh_filter)
		LootFilter.reveal_changed.connect(_on_reveal)
	if kind == "item" and visible and str(fres.get("sound", "")) != "":
		Sfx.play(str(fres["sound"]))
	if kind == "item" and Data.rarity_index(item.get("rarity", "common")) >= 2:
		var l := PointLight2D.new()
		l.texture = Art.light_tex
		l.color = color
		l.energy = 0.6
		l.texture_scale = 0.35
		add_child(l)

## Claims the drop for a collector. Fails if someone else already holds it.
func claim(who) -> bool:
	if picked:
		return false
	if claimed_by != null and is_instance_valid(claimed_by) and claimed_by != who:
		return false
	claimed_by = who
	return true

func release(who) -> void:
	if claimed_by == who:
		claimed_by = null

func is_claimed_by_other(who) -> bool:
	return claimed_by != null and is_instance_valid(claimed_by) and claimed_by != who

## Rarity index for sorting/gating; non-items sort below commons.
func rarity_idx() -> int:
	return Data.rarity_index(item.get("rarity", "common")) if kind == "item" else -1

## True if the current loot filter hides this drop (re-read from settings every call).
func filtered_now() -> bool:
	if kind != "item":
		return false
	return not bool(_evaluate().get("drawn", true))

## Runs the loot filter for this item. Bots and tests bypass it (everything shows)
## unless Game.filter_in_tests is on, so balance data is unaffected.
func _evaluate() -> Dictionary:
	if Game.testing and not Game.filter_in_tests:
		return {}
	var tier := 0
	var d = level.get("def") if level != null else null
	if typeof(d) == TYPE_DICTIONARY:
		tier = int(d.get("tier", 0))
	var lvl: int = Game.ch.level if Game.ch != null else 1
	return LootFilter.evaluate(item, {"player_level": lvl, "tier": tier})

func _on_reveal(_on) -> void:
	refresh_filter()

func refresh_filter() -> void:
	hidden_by_filter = false
	fres = {}
	fs = 8
	label_color = color
	beam_color = null
	if kind == "item":
		fres = _evaluate()
		hidden_by_filter = not bool(fres.get("drawn", true))
		if not fres.is_empty():
			if fres.get("color") != null:
				label_color = fres["color"]
			if int(fres.get("font_px", -1)) > 0:
				fs = clampi(roundi(float(fres["font_px"]) * 0.5), 6, 14)
			beam_color = fres.get("beam")
	visible = not hidden_by_filter
	queue_redraw()

func _process(delta: float) -> void:
	if t < 0.3:
		t += delta
		position += pop * delta * 3.0
		queue_redraw()
	else:
		t += delta
		if kind == "item" and Data.rarity_index(item.get("rarity", "common")) >= 2:
			queue_redraw()

func label_rect() -> Rect2:
	var f := ThemeDB.fallback_font
	var w := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 6
	return Rect2(global_position + Vector2(-w / 2, -22 + label_off - (fs - 8)), Vector2(w, 11 + (fs - 8)))

func _draw() -> void:
	var tex: Texture2D
	match kind:
		"gold":
			tex = Art.icon("gold")
		"material", "rune", "gem":
			tex = Art.icon({"material": "material", "rune": "rune", "gem": "gem"}[kind])
		_:
			tex = Art.icon(item.get("icon", "charm"))
	var bob := -4.0 * maxf(0.0, sin(minf(t, 0.3) / 0.3 * PI))
	draw_texture(tex, Vector2(-6, -8 + bob), color if kind in ["material", "rune", "gem"] else Color.WHITE)
	if kind == "item":
		var r := Data.rarity_index(item.get("rarity", "common"))
		var minimal: bool = str(fres.get("visibility", "show")) == "minimal"
		if beam_color != null and not minimal:
			var bc: Color = beam_color
			var bh := 18.0 + 6.0 * sin(t * 3.0)
			draw_line(Vector2(0, -2), Vector2(0, -2 - bh * (1 + maxi(r, 2) * 0.4)), Color(bc.r, bc.g, bc.b, 0.45), 2.0)
		elif r >= 2 and not minimal:
			var h := 18.0 + 6.0 * sin(t * 3.0)
			draw_line(Vector2(0, -2), Vector2(0, -2 - h * (1 + r * 0.4)), Color(color.r, color.g, color.b, 0.35), 2.0)
	var f := ThemeDB.fallback_font
	var w := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var lc := label_color
	var rect := Rect2(Vector2(-w / 2 - 3, -22 + label_off - (fs - 8)), Vector2(w + 6, 11 + (fs - 8)))
	if label_off < -1:
		draw_line(Vector2(0, -9), Vector2(0, -11 + label_off), Color(lc.r, lc.g, lc.b, 0.4), 1.0)
	draw_rect(rect, Color(0, 0, 0, 0.8))
	draw_rect(rect, Color(lc.r, lc.g, lc.b, 0.6), false, 1.0)
	draw_string(f, Vector2(-w / 2, -14 + label_off), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, lc)
