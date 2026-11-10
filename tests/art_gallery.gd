extends Node2D
## Art gallery: every sprite-sheet manifest entry playing every animation in every
## direction, for judging art. Open tests/art_gallery.tscn and press F6.
##
##   Mouse wheel / arrow keys / drag : scroll        + / - : zoom (whole pixels only)
##   P : palette check (off-palette pixels flash magenta)   Space : pause
## Real art and placeholder sheets are both shown (placeholders are labelled).
## Entries with no sheets yet are listed in the side panel with their old sprite.

const SpriteAnim = preload("res://scripts/gfx/sprite_anim.gd")
const Rules = preload("res://scripts/gfx/anim_rules.gd")
const PAL_SHADER := """
shader_type canvas_item;
uniform vec3 pal[64];
uniform int pal_n = 0;
uniform bool check = false;
uniform float blink = 1.0;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (check && c.a > 0.0) {
		float best = 10.0;
		for (int i = 0; i < 64; i++) {
			if (i >= pal_n) { break; }
			best = min(best, distance(c.rgb, pal[i]));
		}
		if (best > 0.002) { c = vec4(1.0, 0.0, 1.0, blink); } else { c.rgb = mix(c.rgb, vec3(0.15), 0.65); }
	}
	COLOR = c * COLOR;
}
"""
const GAP := 8
const LABEL_H := 18

var cam: Camera2D
var root: Node2D
var anims := []
var mat: ShaderMaterial
var ui: CanvasLayer
var speed_slider: HSlider
var pal_check: CheckBox
var filter: OptionButton
var info: Label
var zoom := 2
var paused := false
var content_h := 0.0
var content_w := 0.0
var only := ""            # filter: one manifest id, or "" for all
var missing := []
var shown := []
var _drag := false
var _t := 0.0

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("#1a1416"))
	mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = PAL_SHADER
	mat.shader = sh
	_load_palette()
	cam = Camera2D.new()
	cam.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	add_child(cam)
	cam.make_current()
	_build_ui()
	build()

func _load_palette() -> void:
	var cols := PackedVector3Array()
	var path := str(Art.render.get("palette", "res://assets/palette/dying_canvas.hex"))
	if FileAccess.file_exists(path):
		for line in FileAccess.get_file_as_string(path).split("\n"):
			var s := line.strip_edges().trim_prefix("#")
			if s.length() == 6:
				var c := Color("#" + s)
				cols.append(Vector3(c.r, c.g, c.b))
	mat.set_shader_parameter("pal", cols)
	mat.set_shader_parameter("pal_n", cols.size())

## (Re)builds the grid. Each row = one animation of one entry, one cell per direction.
func build() -> void:
	if root != null:
		root.queue_free()
	anims.clear()
	missing.clear()
	shown.clear()
	root = Node2D.new()
	add_child(root)
	var font := ThemeDB.fallback_font
	var y := 4.0
	var w_max := 0.0
	var ids: Array = Art.manifest.get("sprites", {}).keys()
	ids.sort()
	for id in ids:
		if only != "" and id != only:
			continue
		var d: Dictionary = Art.sprite_def_any(id)
		if d.is_empty():
			missing.append(id)
			continue
		shown.append(id)
		var fw := float(d["frame"][0])
		var fh := float(d["frame"][1])
		var dirs := int(d.get("directions", 8))
		var dlist := []
		for i in 8:
			if dirs == 8 or (dirs == 4 and i % 2 == 0) or (dirs <= 2 and i in [2, 6]) or dirs == 1 and i == 2:
				dlist.append(i)
		# entry header with the old sprite for size comparison (old art is 16 px = 32 art px)
		var head := _label("%s   [%s]   %dx%d, %d dirs%s, pivot %s%s" % [id, d.get("category", ""), fw, fh, dirs,
			" (mirrored)" if d.get("mirror", true) else "", str(d["pivot"]), "   PLACEHOLDER" if d.get("placeholder", false) else ""],
			Vector2(4, y), Color("#e0c890") if not d.get("placeholder", false) else Color("#c04a3a"))
		root.add_child(head)
		var old := Sprite2D.new()
		old.texture = Art.sprite(str(d.get("fallback", "ghoul")))
		old.centered = false
		old.scale = Vector2(2, 2)
		old.position = Vector2(4, y + LABEL_H)
		root.add_child(old)
		var old_l := _label("old", Vector2(4, y + LABEL_H + 34), Color("#968c7a"))
		root.add_child(old_l)
		y += LABEL_H
		var x0 := 48.0
		for n in d["anims"]:
			var a: Dictionary = d["anims"][n]
			var desc := "%s  %df @%sfps%s%s%s" % [n, int(a["frames"]), str(a.get("fps", 10)),
				"  loop" if a.get("loop", false) else "", ("  sync:%s impact %d" % [a["sync"], int(a.get("impact_frame", 0))]) if a.has("sync") else "",
				"  (placeholder)" if a.get("placeholder", false) else ""]
			root.add_child(_label(desc, Vector2(x0, y), Color("#bdb29a")))
			var cx := x0
			for di in dlist:
				var s = SpriteAnim.new()
				s.setup(d)
				s.scale = Vector2.ONE   # gallery shows art pixels 1:1 in its own space
				s.fixed_dir = di
				s.forced_anim = n
				s.material = mat
				s.position = Vector2(cx + float(d["pivot"][0]), y + LABEL_H + float(d["pivot"][1]))
				root.add_child(s)
				anims.append(s)
				var rf: Array = Rules.row_for(di, dirs, d.get("mirror", true))
				root.add_child(_label(Rules.NAMES[di] + (" (m)" if rf[1] else ""), Vector2(cx, y + LABEL_H + fh), Color("#968c7a")))
				# frame box
				var box := ReferenceRect.new()
				box.border_color = Color(1, 1, 1, 0.08)
				box.editor_only = false
				box.position = Vector2(cx, y + LABEL_H)
				box.size = Vector2(fw, fh)
				root.add_child(box)
				cx += fw + GAP
			w_max = maxf(w_max, cx)
			y += LABEL_H + fh + 14
		y += 10
	content_h = y
	content_w = w_max
	_update_info()
	_apply_zoom()

func _label(t: String, pos: Vector2, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.position = pos
	l.add_theme_font_size_override("font_size", 8)
	l.add_theme_color_override("font_color", col)
	return l

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	var panel := PanelContainer.new()
	panel.position = Vector2(1280 - 260, 0)
	panel.size = Vector2(260, 720)
	ui.add_child(panel)
	var v := VBoxContainer.new()
	panel.add_child(v)
	var title := Label.new()
	title.text = "Art gallery"
	v.add_child(title)
	filter = OptionButton.new()
	filter.add_item("All entries")
	var ids: Array = Art.manifest.get("sprites", {}).keys()
	ids.sort()
	for id in ids:
		filter.add_item(id)
	filter.item_selected.connect(func(i):
		only = "" if i == 0 else filter.get_item_text(i)
		cam.position = Vector2.ZERO
		build())
	v.add_child(filter)
	var sl := Label.new()
	sl.text = "Speed"
	v.add_child(sl)
	speed_slider = HSlider.new()
	speed_slider.min_value = 0.0
	speed_slider.max_value = 2.0
	speed_slider.step = 0.05
	speed_slider.value = 1.0
	v.add_child(speed_slider)
	pal_check = CheckBox.new()
	pal_check.text = "Palette check (P)"
	pal_check.toggled.connect(func(on): mat.set_shader_parameter("check", on))
	v.add_child(pal_check)
	info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(240, 0)
	v.add_child(info)

func _update_info() -> void:
	if info == null:
		return
	var t := "Showing %d entries.\nZoom %dx (+/-), wheel/arrows to scroll, Space pauses.\n\nNo sheets yet (%d):\n" % [shown.size(), zoom, missing.size()]
	t += ", ".join(missing)
	info.text = t

func _apply_zoom() -> void:
	cam.zoom = Vector2(zoom, zoom)
	_update_info()

func _process(delta: float) -> void:
	_t += delta
	mat.set_shader_parameter("blink", 0.55 + 0.45 * sin(_t * 8.0))
	var sp := 0.0 if paused else speed_slider.value
	for s in anims:
		s.speed = sp

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			scroll(Vector2(0, 60))
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			scroll(Vector2(0, -60))
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_drag = event.pressed
	if event is InputEventMouseMotion and _drag:
		scroll(-event.relative / zoom)
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_DOWN: scroll(Vector2(0, 60))
			KEY_UP: scroll(Vector2(0, -60))
			KEY_RIGHT: scroll(Vector2(60, 0))
			KEY_LEFT: scroll(Vector2(-60, 0))
			KEY_PAGEDOWN: scroll(Vector2(0, 600 / zoom))
			KEY_PAGEUP: scroll(Vector2(0, -600 / zoom))
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
				zoom = mini(zoom + 1, 8)
				_apply_zoom()
			KEY_MINUS, KEY_KP_SUBTRACT:
				zoom = maxi(zoom - 1, 1)
				_apply_zoom()
			KEY_P:
				pal_check.button_pressed = not pal_check.button_pressed
			KEY_SPACE:
				paused = not paused

func scroll(by: Vector2) -> void:
	cam.position.x = clampf(cam.position.x + by.x, 0.0, maxf(0.0, content_w - 1000.0 / zoom))
	cam.position.y = clampf(cam.position.y + by.y, 0.0, maxf(0.0, content_h - 600.0 / zoom))

## Screenshot helper: number of vertical pages at the current zoom.
func page_count() -> int:
	return maxi(1, int(ceil(content_h / (700.0 / zoom))))

func show_page(i: int) -> void:
	cam.position = Vector2(0, i * 700.0 / zoom)
