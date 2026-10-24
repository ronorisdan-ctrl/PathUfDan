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
	if kind == "item" and Data.rarity_index(item.get("rarity", "common")) >= 2:
		var l := PointLight2D.new()
		l.texture = Art.light_tex
		l.color = color
		l.energy = 0.6
		l.texture_scale = 0.35
		add_child(l)

func refresh_filter() -> void:
	hidden_by_filter = false
	if kind == "item":
		var lvl := int(Game.settings.get("loot_filter", 0))
		hidden_by_filter = Data.rarity_index(item.get("rarity", "common")) < lvl
	visible = not hidden_by_filter

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
	var w := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x + 6
	return Rect2(global_position + Vector2(-w / 2, -22 + label_off), Vector2(w, 11))

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
		if r >= 2:
			var h := 18.0 + 6.0 * sin(t * 3.0)
			draw_line(Vector2(0, -2), Vector2(0, -2 - h * (1 + r * 0.4)), Color(color.r, color.g, color.b, 0.35), 2.0)
	var f := ThemeDB.fallback_font
	var w := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	var rect := Rect2(Vector2(-w / 2 - 3, -22 + label_off), Vector2(w + 6, 11))
	if label_off < -1:
		draw_line(Vector2(0, -9), Vector2(0, -11 + label_off), Color(color.r, color.g, color.b, 0.4), 1.0)
	draw_rect(rect, Color(0, 0, 0, 0.8))
	draw_rect(rect, Color(color.r, color.g, color.b, 0.6), false, 1.0)
	draw_string(f, Vector2(-w / 2, -14 + label_off), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, color)
