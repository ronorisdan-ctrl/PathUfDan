extends "res://scripts/ui/base_panel.gd"
## Jeweller: socket gems into gear, remove them for a small fee and
## combine three gems of a grade into one of the next grade.

var selected = null
var item_text: RichTextLabel
var socket_box: VBoxContainer
var pouch_box: VBoxContainer
var gold_label: RichTextLabel
var buy_btn: Button

func _init() -> void:
	place = "left"
	build("Jeweller Mira", Vector2(440, 560))
	body.add_child(UIKit.label("Select an item in your inventory or equipment.", 12, UIKit.MUTED))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(420, 120)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(sc)
	item_text = UIKit.rich("", 400)
	sc.add_child(item_text)
	body.add_child(UIKit.label("Sockets", 13, UIKit.GOLD))
	socket_box = VBoxContainer.new()
	body.add_child(socket_box)
	body.add_child(UIKit.label("Gem pouch", 13, UIKit.GOLD))
	var sc2 := ScrollContainer.new()
	sc2.custom_minimum_size = Vector2(420, 190)
	sc2.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(sc2)
	pouch_box = VBoxContainer.new()
	pouch_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc2.add_child(pouch_box)
	gold_label = UIKit.rich("", 420)
	body.add_child(gold_label)
	buy_btn = UIKit.button("Buy a random gem", _buy_gem)
	body.add_child(buy_btn)
	Events.currency_changed.connect(refresh)
	Events.inventory_changed.connect(refresh)

func on_close() -> void:
	selected = null

func select(it) -> void:
	selected = it if (it != null and not it.is_empty()) else null
	refresh()
	if ui.panels.has("inventory"):
		ui.panels["inventory"].refresh()

func refresh() -> void:
	var ch = Game.ch
	if ch == null or not visible:
		return
	for c in socket_box.get_children():
		c.queue_free()
	for c in pouch_box.get_children():
		c.queue_free()
	gold_label.text = "[color=#e8c050]Gold %d[/color]   [color=#8a8494]Add sockets at the Blacksmith.[/color]" % ch.gold
	buy_btn.text = "Buy a random gem (%d gold)" % gem_price()
	buy_btn.disabled = ch.gold < gem_price()
	# sockets of the selected item
	if selected == null:
		item_text.text = "[color=#8a8494]No item selected.[/color]"
	else:
		item_text.text = Loot.tooltip(selected, ch)
		var ns: int = Loot.item_sockets(selected)
		if ns == 0:
			var why := "This item cannot hold sockets." if Loot.max_sockets(selected) == 0 else "No sockets - the Blacksmith can add up to %d." % Loot.max_sockets(selected)
			socket_box.add_child(UIKit.label(why, 12, UIKit.MUTED))
		var gl: Array = selected.get("gems", [])
		for i in ns:
			var g: String = gl[i] if i < gl.size() else ""
			var b: Button
			if g == "":
				b = UIKit.button("Socket %d: empty - choose a gem" % (i + 1), _socket_menu.bind(i))
			else:
				b = UIKit.button("Socket %d: %s - remove (%d gold)" % [i + 1, Loot.gem_name(g), ch.unsocket_cost(g)], _unsocket.bind(i))
				b.modulate = Loot.gem_color(g).lerp(Color.WHITE, 0.5)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			socket_box.add_child(b)
	# gem pouch
	var ids: Array = ch.gems.keys()
	ids.sort_custom(func(a, b):
		if Loot.gem_tier(a) != Loot.gem_tier(b):
			return Loot.gem_tier(a) > Loot.gem_tier(b)
		return a < b)
	if ids.is_empty():
		pouch_box.add_child(UIKit.label("No gems yet - they drop from monsters (more from elites and bosses).", 12, UIKit.MUTED))
	for gid in ids:
		var row := HBoxContainer.new()
		var l := UIKit.rich("[color=#%s]%s[/color] x%d" % [Loot.gem_color(gid).to_html(false), Loot.gem_name(gid), int(ch.gems[gid])], 200)
		l.tooltip_text = Loot.gem_summary(gid) + "\nRequires level %d" % Loot.gem_req(gid)
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var cc: int = ch.combine_cost(gid)
		if cc >= 0:
			var cb := UIKit.button("Combine 3 (%d g)" % cc, _combine.bind(gid))
			cb.disabled = ch.can_combine(gid) != ""
			cb.tooltip_text = ch.can_combine(gid) if cb.disabled else "Turn 3 into one %s" % Loot.gem_name(Loot.gem_id(gid.get_slice(":", 0), Loot.gem_tier(gid) + 1))
			row.add_child(cb)
		pouch_box.add_child(row)

func _socket_menu(idx: int) -> void:
	var ch = Game.ch
	if selected == null:
		return
	var cat: String = Loot.socket_category(selected)
	var opts := []
	for gid in ch.gems:
		var ms := []
		for m in Loot.gem_mods(gid, cat):
			ms.append(Loot.mod_text(m))
		var ok: bool = ch.level >= Loot.gem_req(gid)
		opts.append(["%s (x%d): %s%s" % [Loot.gem_name(gid), int(ch.gems[gid]), ", ".join(ms), "" if ok else "  [needs lv %d]" % Loot.gem_req(gid)], _do_socket.bind(idx, gid), ok])
	if opts.is_empty():
		ui.toast("You have no gems", UIKit.BAD)
		return
	ui.show_context(opts)

func _do_socket(idx: int, gid: String) -> void:
	var e: String = Game.ch.socket_gem(selected, idx, gid)
	if e != "":
		ui.toast(e, UIKit.BAD)
	else:
		Sfx.play("pickup")
	refresh()

func _unsocket(idx: int) -> void:
	var e: String = Game.ch.unsocket_gem(selected, idx)
	if e != "":
		ui.toast(e, UIKit.BAD)
	refresh()

func _combine(gid: String) -> void:
	var e: String = Game.ch.combine_gems(gid)
	if e != "":
		ui.toast(e, UIKit.BAD)
	else:
		ui.toast("Created %s" % Loot.gem_name(Loot.gem_id(gid.get_slice(":", 0), Loot.gem_tier(gid) + 1)), Color("#ffd080"))
		Sfx.play("levelup", 0.0)
	refresh()

func gem_price() -> int:
	return 30 + 10 * Game.ch.level

func _buy_gem() -> void:
	var ch = Game.ch
	var price := gem_price()
	if ch.gold < price:
		ui.toast("Not enough gold", UIKit.BAD)
		return
	ch.gold -= price
	var gid: String = Loot.random_gem(ch.level)
	ch.add_gem(gid)
	ui.toast("Bought %s" % Loot.gem_name(gid), Loot.gem_color(gid))
	refresh()
