extends CanvasLayer
## Owns the HUD, all panels, tooltips, context menus, confirmation dialogs
## and toast messages. Panels are opened by hotkey or by hub stations.

const UIKit = preload("res://scripts/ui/ui_kit.gd")
const HUD = preload("res://scripts/ui/hud.gd")
const TooltipCard = preload("res://scripts/ui/components/tooltip_card.gd")
const Chrome = preload("res://scripts/ui/components/inventory_chrome.gd")
const PANELS := {
	"inventory": "res://scripts/ui/inventory_panel.gd",
	"character": "res://scripts/ui/character_panel.gd",
	"passives": "res://scripts/ui/passive_tree_panel.gd",
	"skills": "res://scripts/ui/skills_panel.gd",
	"spec": "res://scripts/ui/spec_panel.gd",
	"vendor": "res://scripts/ui/vendor_panel.gd",
	"blacksmith": "res://scripts/ui/blacksmith_panel.gd",
	"jeweller": "res://scripts/ui/jeweller_panel.gd",
	"pets": "res://scripts/ui/pet_panel.gd",
	"training": "res://scripts/ui/training_panel.gd",
	"stash": "res://scripts/ui/stash_panel.gd",
	"dungeon": "res://scripts/ui/dungeon_panel.gd",
	"atlas": "res://scripts/ui/atlas_panel.gd",
	"easel": "res://scripts/ui/easel_panel.gd",
	"guild": "res://scripts/ui/guild_panel.gd",
	"wager": "res://scripts/ui/wager_panel.gd",
	"pause": "res://scripts/ui/pause_panel.gd",
	"options": "res://scripts/ui/options_panel.gd",
	"death": "res://scripts/ui/death_panel.gd",
	"dev": "res://scripts/ui/dev_panel.gd",
}

var root: Control
var hud
var panels := {}
var open_set := {}
var tooltip: PanelContainer
var tooltip_text: RichTextLabel
var tooltip2: PanelContainer
var tooltip2_text: RichTextLabel
var toasts: VBoxContainer
var context: PanelContainer
var confirm: PanelContainer
var confirm_text: RichTextLabel
var confirm_cb: Callable
var tooltip_reading := false
var _reading_card := 0
var _reading_character = null
var _tooltip_anchor := Vector2.ZERO
var _context_anchor := Vector2.ZERO

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.theme = UIKit.make_theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	hud = HUD.new()
	hud.ui = self
	root.add_child(hud)
	for k in PANELS:
		var p = load(PANELS[k]).new()
		p.ui = self
		p.panel_name = k
		p.visible = false
		root.add_child(p)
		panels[k] = p
	LootFilter.upgrade_checker = Callable(self, "filter_is_upgrade")
	LootFilter.known_sounds = Sfx.streams.keys()
	toasts = VBoxContainer.new()
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toasts.position = Vector2(0, 90)
	toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	root.add_child(toasts)
	tooltip = _make_tooltip()
	tooltip_text = tooltip.text
	tooltip2 = _make_tooltip()
	tooltip2_text = tooltip2.text
	_build_context()
	_build_confirm()
	Events.message.connect(toast)
	Events.player_leveled.connect(func(_l): Sfx.play("levelup", 0.0))
	Events.player_leveled.connect(func(l): toast("Level up! You are now level %d (+1 passive point)" % l, Color("#ffe080")))
	Events.skill_unlocked.connect(func(s): toast("New skill unlocked: %s (press K)" % Data.skills[s]["name"], Color("#a0d0ff")))
	Events.item_picked.connect(func(it): toast("Picked up %s" % it["name"], Data.rarity_color(it.get("rarity", "common"))))
	Events.player_died.connect(func(): open("death"))
	get_viewport().size_changed.connect(_on_resize)
	Events.inventory_changed.connect(func(): hide_tooltip(true))
	Events.stats_changed.connect(func():
		if tooltip_reading:
			hide_tooltip(true))
	Events.level_ready.connect(func(_level): hide_tooltip(true))

func _make_tooltip() -> PanelContainer:
	var t := TooltipCard.new()
	root.add_child(t)
	return t

func _on_resize() -> void:
	for k in open_set:
		panels[k].reposition()

# ------------------------------------------------------------------ panels
func is_open(n: String) -> bool:
	return open_set.has(n)

func any_blocking_open() -> bool:
	return open_set.size() > 0

func open(n: String) -> void:
	if not panels.has(n):
		return
	hide_tooltip(true)
	if n == "death":
		close_all()
	var p = panels[n]
	open_set[n] = true
	p.visible = true
	p.reposition()
	p.on_open()
	_release_player()
	Events.ui_panel_toggled.emit(n, true)
	_update_pause()

func close(n: String) -> void:
	if not open_set.has(n):
		return
	open_set.erase(n)
	panels[n].visible = false
	panels[n].on_close()
	hide_tooltip(true)
	if n in ["vendor", "blacksmith", "stash", "jeweller"]:
		close("inventory")
	Events.ui_panel_toggled.emit(n, false)
	_update_pause()

func toggle(n: String) -> void:
	if is_open(n):
		close(n)
	else:
		# left-side panels share space
		if n in ["character", "vendor", "blacksmith", "stash", "jeweller", "pets", "training"]:
			for o in ["character", "vendor", "blacksmith", "stash", "jeweller", "pets", "training"]:
				if o != n and is_open(o):
					open_set.erase(o)
					panels[o].visible = false
					panels[o].on_close()
		if n in ["passives", "skills", "dungeon", "spec", "atlas", "easel", "guild"]:
			for o in ["passives", "skills", "dungeon", "spec", "atlas", "easel", "guild"]:
				if o != n:
					close(o)
		open(n)

func close_all() -> void:
	hide_tooltip(true)
	for k in open_set.keys():
		close(k)
	hide_context()
	confirm.visible = false

func refresh_open() -> void:
	for k in open_set:
		panels[k].refresh()

func _update_pause() -> void:
	# the game pauses only for the pause menu (and the developer frame pause); everything else is live
	get_tree().paused = is_open("pause") or Dev.frame_paused()

func _release_player() -> void:
	if Game.level != null and Game.level.player != null and is_instance_valid(Game.level.player):
		Game.level.player.release_all()

func open_station(kind: String) -> void:
	match kind:
		"merchant":
			toggle("vendor")
			open("inventory")
		"blacksmith":
			toggle("blacksmith")
			open("inventory")
		"stash":
			toggle("stash")
			open("inventory")
		"jeweller":
			toggle("jeweller")
			open("inventory")
		"pets":
			toggle("pets")
		"training":
			toggle("training")
		"guild":
			toggle("guild")
		"dungeon":
			toggle("dungeon")
		"altar":
			toggle("skills")

func _unhandled_input(event: InputEvent) -> void:
	if Game.ch == null or Game.level == null:
		return
	if is_open("death"):
		return
	if event.is_action_pressed("dev_panel") and Dev.enabled():
		close("pause")
		toggle("dev")
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause"):
		if confirm.visible:
			confirm.visible = false
		elif context.visible:
			hide_context()
		elif open_set.size() > 0 and not is_open("pause"):
			close_all()
		else:
			toggle("pause")
		get_viewport().set_input_as_handled()
		return
	if is_open("pause"):
		return
	var map := {"toggle_inventory": "inventory", "toggle_character": "character", "toggle_passives": "passives", "toggle_skills": "skills", "toggle_spec": "spec"}
	for a in map:
		if event.is_action_pressed(a):
			toggle(map[a])
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("toggle_map"):
		hud.big_map = not hud.big_map
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_loot_filter"):
		cycle_loot_filter()
		get_viewport().set_input_as_handled()

## Z cycles through the character's filters (presets first, then saved ones).
func cycle_loot_filter() -> void:
	var names: Array = LootFilter.list_filters()
	var i := names.find(LootFilter.active_name)
	LootFilter.load_filter(names[(i + 1) % names.size()])
	if Game.level != null:
		Game.level.refresh_loot_filter()
	toast("Loot filter: " + loot_filter_name(), Color("#c0c0ff"))
	refresh_open()

func loot_filter_name() -> String:
	return str(LootFilter.filter.get("name", LootFilter.active_name))

var filter_editor = null

## Opens the in-game loot filter editor (rules, colours, sounds, import/export).
func open_filter_editor() -> void:
	if filter_editor == null:
		filter_editor = load("res://scripts/ui/loot_filter_panel.gd").new()
		root.add_child(filter_editor)
		filter_editor.position = Vector2(150, 50)
	filter_editor.open()

## Hook for the filter's "is an upgrade for me" condition (same maths as the tooltip).
func filter_is_upgrade(it: Dictionary) -> bool:
	var ch = Game.ch
	if ch == null or ch.equip_restriction(it) != "":
		return false
	var eq: Dictionary = ch.equipment_with(it)
	var a: Dictionary = ch.final
	var b: Dictionary = ch.preview_final(ch.allocated, eq)
	var dmg_ok := true
	var gain := false
	var sid: String = ch.loadout[0]
	if sid != "":
		var before: float = ch.preview_skill_avg(sid, ch.allocated)
		var after: float = ch.preview_skill_avg(sid, ch.allocated, eq)
		if before > 0:
			dmg_ok = after >= before * 0.99
			gain = after > before * 1.01
	for k in ["max_life", "armour", "evasion", "block_chance", "res_fire", "res_cold", "res_lightning"]:
		if float(b.get(k, 0)) > float(a.get(k, 0)) + 0.5:
			gain = true
	return gain and dmg_ok

# ------------------------------------------------------------------ tooltip
func show_tooltip(text: String, text2: String = "") -> void:
	if tooltip_reading:
		return
	tooltip.present(text)
	tooltip2.present(text2)
	# Keep the public text API current even when a menu/modal owns visibility.
	if context.visible or confirm.visible:
		return
	tooltip.visible = true
	tooltip2.visible = text2 != ""
	_place_tooltips()

func hide_tooltip(force: bool = false) -> void:
	if tooltip_reading and not force:
		return
	tooltip_reading = false
	_reading_character = null
	for card in [tooltip, tooltip2]:
		card.set_reading(false)
		card.mark_active(false)
		if card.text.has_focus():
			card.text.release_focus()
	tooltip.visible = false
	tooltip2.visible = false

func _process(_delta: float) -> void:
	if tooltip_reading and (Game.ch != _reading_character or not any_blocking_open()):
		hide_tooltip(true)
	if tooltip.visible:
		_place_tooltips()
	if confirm.visible:
		_place_confirmation()
	if context.visible:
		_place_context()

func _place_tooltips() -> void:
	var m := _tooltip_anchor if tooltip_reading else root.get_local_mouse_position()
	var vs := root.size
	var paired := tooltip2.visible
	var width := minf(336, (vs.x - 16 - (6 if paired else 0)) / (2 if paired else 1))
	tooltip.fit_card(width, vs.y - 16, any_blocking_open())
	if paired:
		tooltip2.fit_card(width, vs.y - 16, any_blocking_open())
	var sz := Vector2(width * (2 if paired else 1) + (6 if paired else 0), maxf(tooltip.size.y, tooltip2.size.y if paired else 0))
	var pos := m + Vector2(18, 12)
	if pos.x + sz.x > vs.x:
		pos.x = m.x - sz.x - 18
	pos.y = clampf(pos.y, 8, maxf(8, vs.y - sz.y - 8))
	pos.x = clampf(pos.x, 8, maxf(8, vs.x - sz.x - 8))
	# Equipped comparison to the left, hovered candidate to the right.
	tooltip.position = pos + Vector2(width + 6 if paired else 0, 0)
	if paired:
		tooltip2.position = pos

func _read_tooltips() -> void:
	tooltip_reading = true
	_reading_character = Game.ch
	_tooltip_anchor = root.get_local_mouse_position()
	tooltip.set_reading(true)
	tooltip2.set_reading(true)
	_focus_tooltip(0)
	_place_tooltips()

func _focus_tooltip(index: int) -> void:
	_reading_card = index
	tooltip.mark_active(index == 0)
	tooltip2.mark_active(index == 1)
	var card = tooltip if index == 0 else tooltip2
	card.text.grab_focus()

func item_tooltip(it: Dictionary, compare: bool) -> void:
	var ch = Game.ch
	var main := Loot.tooltip(it, ch)
	if bool(it.get("locked", false)):
		main += "\n[color=#ffd060]Locked: cannot be sold, salvaged or destroyed[/color]"
	var other := ""
	if compare:
		var slot: String = ch.slot_for(it)
		if it.get("slot") == "ring":
			slot = "ring1"
		var eq = ch.equipment.get(slot)
		main += _compare_lines(it)
		if eq != null and eq != it:
			other = "[color=#8a8494]Currently equipped[/color]\n" + Loot.tooltip(eq, ch)
	show_tooltip(main, other)

func _compare_lines(it: Dictionary) -> String:
	var ch = Game.ch
	if ch.equip_restriction(it) != "":
		return ""
	var eq: Dictionary = ch.equipment_with(it)
	var a: Dictionary = ch.final
	var b: Dictionary = ch.preview_final(ch.allocated, eq)
	var lines := ["", "[color=#c8a060]If equipped:[/color]"]
	var keys := [["max_life", "Life"], ["max_mana", "Mana"], ["armour", "Armour"], ["evasion", "Evasion"], ["block_chance", "Block %"],
		["res_fire", "Fire Res"], ["res_cold", "Ice Res"], ["res_lightning", "Lightning Res"], ["move_speed", "Move Speed"]]
	var any := false
	for k in keys:
		var d: float = float(b.get(k[0], 0)) - float(a.get(k[0], 0))
		if absf(d) >= 0.5:
			any = true
			lines.append("[color=#%s]%s%d %s[/color]" % [("80e080" if d > 0 else "ff6060"), "+" if d > 0 else "", int(round(d)), k[1]])
	var sid: String = ch.loadout[0]
	if sid != "":
		var before: float = ch.preview_skill_avg(sid, ch.allocated)
		var after: float = ch.preview_skill_avg(sid, ch.allocated, eq)
		if before > 0 and absf(after - before) > 0.05:
			any = true
			var pct := (after / before - 1.0) * 100.0
			lines.append("[color=#%s]%s%.0f%% %s damage[/color]" % [("80e080" if pct > 0 else "ff6060"), "+" if pct > 0 else "", pct, Data.skills[sid]["name"]])
	if not any:
		lines.append("[color=#8a8494]No change to key stats[/color]")
	return "\n".join(lines)

# ------------------------------------------------------------------ toasts
func toast(text: String, color: Color = Color.WHITE) -> void:
	var l := UIKit.label(text, 16, color)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size.x = root.size.x
	toasts.add_child(l)
	while toasts.get_child_count() > 5:
		toasts.get_child(0).queue_free()
		toasts.remove_child(toasts.get_child(0))
	var tw := l.create_tween()
	tw.tween_interval(2.2)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)

# ------------------------------------------------------------------ context menu
func _build_context() -> void:
	context = PanelContainer.new()
	context.theme = Chrome.make_theme()
	context.visible = false
	context.z_index = 90
	var v := VBoxContainer.new()
	context.add_child(v)
	root.add_child(context)

func show_context(options: Array) -> void:
	## options: [[label, callable, enabled], ...]
	var v: VBoxContainer = context.get_child(0)
	for c in v.get_children():
		v.remove_child(c)
		c.queue_free()
	for o in options:
		var cb: Callable = o[1]
		var b := UIKit.button(o[0], func():
			hide_context()
			cb.call())
		b.disabled = o.size() > 2 and not o[2]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		v.add_child(b)
	context.visible = true
	_context_anchor = root.get_local_mouse_position() + Vector2(4, 4)
	_place_context()
	hide_tooltip(true)

func _place_context() -> void:
	context.size = context.get_combined_minimum_size()
	context.position.x = clampf(_context_anchor.x, 8, maxf(8, root.size.x - context.size.x - 8))
	context.position.y = clampf(_context_anchor.y, 8, maxf(8, root.size.y - context.size.y - 8))

func hide_context() -> void:
	context.visible = false

func _input(event: InputEvent) -> void:
	if tooltip_reading:
		if event is InputEventKey and event.pressed:
			if event.keycode in [KEY_ESCAPE, KEY_F4] and not event.alt_pressed:
				hide_tooltip(true)
				get_viewport().set_input_as_handled()
				return
			if event.keycode in [KEY_TAB, KEY_PAGEUP, KEY_PAGEDOWN, KEY_HOME, KEY_END]:
				get_viewport().set_input_as_handled()
				if event.keycode == KEY_TAB:
					_focus_tooltip(1 - _reading_card if tooltip2.visible else 0)
				else:
					var card = tooltip if _reading_card == 0 else tooltip2
					if event.keycode in [KEY_HOME, KEY_END]:
						card.text.get_v_scroll_bar().value = 0 if event.keycode == KEY_HOME else card.text.get_v_scroll_bar().max_value
					else:
						card.scroll_page(-1 if event.keycode == KEY_PAGEUP else 1)
				return
		if event is InputEventMouseButton and event.pressed:
			if tooltip.get_global_rect().has_point(event.position):
				_focus_tooltip(0)
			elif tooltip2.visible and tooltip2.get_global_rect().has_point(event.position):
				_focus_tooltip(1)
			elif event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
				# Dismiss only; never send the dismissing click to an item or combat.
				hide_tooltip(true)
				get_viewport().set_input_as_handled()
				return
	elif tooltip.visible and any_blocking_open() and not context.visible and not confirm.visible:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F4 and not event.alt_pressed and not event.ctrl_pressed and not event.meta_pressed:
			if tooltip.overflowing or (tooltip2.visible and tooltip2.overflowing):
				_read_tooltips()
				get_viewport().set_input_as_handled()
				return
	# While a confirmation is showing: Space = Confirm, Escape = Cancel.
	# Handled here so the game (dodge, pause menu) never sees these keys.
	if confirm.visible and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			get_viewport().set_input_as_handled()
			_on_confirm()
			return
		elif event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_on_cancel()
			return
	if context.visible and event is InputEventMouseButton and event.pressed:
		if not Rect2(context.global_position, context.size).has_point(event.position):
			hide_context()

# ------------------------------------------------------------------ confirmation
func _build_confirm() -> void:
	confirm = PanelContainer.new()
	confirm.theme = Chrome.make_theme()
	confirm.visible = false
	confirm.z_index = 95
	confirm.custom_minimum_size = Vector2(420, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	confirm.add_child(v)
	confirm_text = UIKit.rich("", 400)
	confirm_text.fit_content = false
	confirm_text.scroll_active = true
	confirm_text.mouse_filter = Control.MOUSE_FILTER_STOP
	v.add_child(confirm_text)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(UIKit.button("Confirm", _on_confirm, 120))
	h.add_child(UIKit.button("Cancel", _on_cancel, 120))
	v.add_child(h)
	root.add_child(confirm)

func _on_confirm() -> void:
	confirm.visible = false
	if confirm_cb.is_valid():
		confirm_cb.call()

func _on_cancel() -> void:
	confirm.visible = false

func ask(text: String, cb: Callable) -> void:
	confirm_text.text = text
	confirm_cb = cb
	confirm.visible = true
	confirm_text.get_v_scroll_bar().value = 0
	_place_confirmation()
	hide_tooltip(true)

func _place_confirmation() -> void:
	confirm_text.custom_minimum_size.y = minf(maxf(20, confirm_text.get_content_height()), maxf(20, root.size.y - 120))
	confirm.size = confirm.get_combined_minimum_size()
	confirm.position = (root.size - confirm.size) / 2
