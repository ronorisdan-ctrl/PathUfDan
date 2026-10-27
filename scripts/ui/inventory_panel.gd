extends "res://scripts/ui/base_panel.gd"
## Equipment paper-doll, 40-slot bag, materials, sorting and item actions
## (equip, compare, sell, salvage, stash, craft-select, destroy).

const ItemSlot = preload("res://scripts/ui/item_slot.gd")

const EQUIP_LAYOUT := {
	"charm": Vector2(0, 0), "helmet": Vector2(150, 0), "amulet": Vector2(210, 0),
	"main_hand": Vector2(80, 60), "chest": Vector2(150, 60), "off_hand": Vector2(220, 60),
	"gloves": Vector2(80, 120), "belt": Vector2(150, 120), "boots": Vector2(220, 120),
	"ring1": Vector2(90, 180), "ring2": Vector2(210, 180),
}
const PLACEHOLDERS := {"charm": "charm", "helmet": "helm", "amulet": "amulet", "main_hand": "sword", "chest": "plate", "off_hand": "shield",
	"gloves": "glove", "belt": "belt", "boots": "boot", "ring1": "ring", "ring2": "ring"}

var equip_slots := {}
var bag_slots := []
var mats_label: RichTextLabel
var filter_btn: Button
var info_label: Label

func _init() -> void:
	place = "right"
	build("Inventory", Vector2(430, 560))
	var eqbox := Control.new()
	eqbox.custom_minimum_size = Vector2(400, 200)
	body.add_child(eqbox)
	for s in EQUIP_LAYOUT:
		var sl = ItemSlot.new()
		sl.key = s
		sl.placeholder = PLACEHOLDERS[s]
		sl.position = EQUIP_LAYOUT[s] * 0.88 + Vector2(50, 0)
		sl.size = Vector2(46, 46)
		sl.custom_minimum_size = Vector2(46, 46)
		sl.clicked.connect(_on_equip_click)
		sl.hovered.connect(_on_hover)
		sl.unhovered.connect(_on_unhover)
		eqbox.add_child(sl)
		equip_slots[s] = sl
	body.add_child(HSeparator.new())
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	body.add_child(grid)
	for i in 40:
		var sl2 = ItemSlot.new()
		sl2.key = i
		sl2.clicked.connect(_on_bag_click)
		sl2.hovered.connect(_on_hover)
		sl2.unhovered.connect(_on_unhover)
		grid.add_child(sl2)
		bag_slots.append(sl2)
	mats_label = UIKit.rich("", 400)
	body.add_child(mats_label)
	var h := HBoxContainer.new()
	h.add_child(UIKit.button("Sort", func(): Game.ch.sort_bag()))
	filter_btn = UIKit.button("Filter", func(): ui.cycle_loot_filter())
	h.add_child(filter_btn)
	body.add_child(h)
	info_label = UIKit.label("", 11, UIKit.MUTED)
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	info_label.custom_minimum_size.x = 400
	body.add_child(info_label)
	Events.inventory_changed.connect(refresh)
	Events.currency_changed.connect(refresh)

func refresh() -> void:
	var ch = Game.ch
	if ch == null or not visible:
		return
	for s in equip_slots:
		equip_slots[s].set_item(ch.equipment.get(s))
		equip_slots[s].selected = _is_selected(ch.equipment.get(s))
	for i in bag_slots.size():
		bag_slots[i].set_item(ch.inventory[i])
		bag_slots[i].selected = _is_selected(ch.inventory[i])
		bag_slots[i].price = Loot.sell_value(ch.inventory[i]) if ui.is_open("vendor") and ch.inventory[i] != null else -1
	var parts := ["[color=#e8c050]Gold: %d[/color]" % ch.gold]
	for k in Data.materials:
		var md: Dictionary = Data.materials[k]
		parts.append("[color=%s]%s: %d[/color]" % [md.get("color", "#fff"), md["name"], int(ch.materials.get(k, 0))])
	mats_label.text = "   ".join(parts)
	filter_btn.text = "Loot filter: " + ui.loot_filter_name()
	var hint := "LMB: equip   RMB: actions   "
	if ui.is_open("vendor"):
		hint += "Shift+LMB: sell"
	elif ui.is_open("blacksmith"):
		hint = "LMB: select for crafting   Shift+LMB: salvage   RMB: actions"
	elif ui.is_open("jeweller"):
		hint = "LMB: select for socketing   RMB: actions"
	elif ui.is_open("stash"):
		hint = "LMB: move to %s   RMB: actions" % ui.panels["stash"].target_name()
	info_label.text = hint

func _is_selected(it) -> bool:
	if it == null:
		return false
	if ui.is_open("jeweller"):
		return ui.panels["jeweller"].selected == it
	if not ui.is_open("blacksmith"):
		return false
	return ui.panels["blacksmith"].selected == it

func _on_hover(sl) -> void:
	if sl.item != null:
		ui.item_tooltip(sl.item, typeof(sl.key) == TYPE_INT)

func _on_unhover(_sl) -> void:
	ui.hide_tooltip()

func _on_bag_click(sl, button: int, shift: bool) -> void:
	var ch = Game.ch
	var idx: int = sl.key
	var it = ch.inventory[idx]
	if it == null:
		return
	if button == MOUSE_BUTTON_RIGHT:
		_context_bag(idx, it)
		return
	if button != MOUSE_BUTTON_LEFT:
		return
	if ui.is_open("jeweller"):
		ui.panels["jeweller"].select(it)
		refresh()
		return
	if ui.is_open("blacksmith"):
		if shift:
			salvage(idx)
		else:
			ui.panels["blacksmith"].select(it)
		refresh()
		return
	if ui.is_open("stash"):
		ui.panels["stash"].deposit(idx)
		return
	if shift and ui.is_open("vendor"):
		sell(idx)
		return
	var err: String = ch.equip_from_bag(idx)
	if err != "":
		ui.toast(err, UIKit.BAD)
	ui.hide_tooltip()

func _context_bag(idx: int, it: Dictionary) -> void:
	var ch = Game.ch
	var opts := []
	opts.append(["Equip", _equip_idx.bind(idx, ""), ch.equip_restriction(it) == ""])
	if it.get("slot") == "ring":
		opts.append(["Equip in Ring 2", _equip_idx.bind(idx, "ring2"), ch.equip_restriction(it) == ""])
	if ui.is_open("vendor"):
		opts.append(["Sell for %d gold" % Loot.sell_value(it), func(): sell(idx)])
	if ui.is_open("blacksmith"):
		opts.append(["Select for crafting", func(): ui.panels["blacksmith"].select(it)])
		opts.append(["Salvage", func(): salvage(idx)])
	if ui.is_open("stash"):
		opts.append(["Move to " + ui.panels["stash"].target_name(), func(): ui.panels["stash"].deposit(idx)])
	opts.append(["Destroy", func(): _destroy(idx)])
	ui.show_context(opts)

func _equip_idx(idx: int, slot: String) -> void:
	var e: String = Game.ch.equip_from_bag(idx, slot)
	if e != "":
		ui.toast(e, UIKit.BAD)

func _on_equip_click(sl, button: int, _shift: bool) -> void:
	var ch = Game.ch
	var slot: String = sl.key
	var it = ch.equipment.get(slot)
	if it == null:
		return
	if ui.is_open("blacksmith") and button == MOUSE_BUTTON_LEFT:
		ui.panels["blacksmith"].select(it)
		refresh()
		return
	if ui.is_open("jeweller") and button == MOUSE_BUTTON_LEFT:
		ui.panels["jeweller"].select(it)
		refresh()
		return
	if button == MOUSE_BUTTON_RIGHT:
		var opts := [["Unequip", func(): _unequip(slot)]]
		if ui.is_open("blacksmith"):
			opts.append(["Select for crafting", func(): ui.panels["blacksmith"].select(it)])
		ui.show_context(opts)
		return
	_unequip(slot)

func _unequip(slot: String) -> void:
	if not Game.ch.unequip(slot):
		ui.toast("Not enough bag space", UIKit.BAD)
	ui.hide_tooltip()

func _valuable(it: Dictionary) -> bool:
	return Data.rarity_index(it.get("rarity", "common")) >= 2 or int(it.get("upgrade", 0)) > 0

func sell(idx: int) -> void:
	var ch = Game.ch
	var it = ch.inventory[idx]
	if it == null:
		return
	var do_sell := func():
		if ch.inventory[idx] != it:
			return
		ch.reclaim_gems(ch.inventory[idx])
		ch.inventory[idx] = null
		ch.gold += Loot.sell_value(it)
		Game.vendor_stock.append(it)
		while Game.vendor_stock.size() > 16:
			Game.vendor_stock.pop_front()
		Events.inventory_changed.emit()
		Events.currency_changed.emit()
		ui.refresh_open()
	if it.get("rarity") == "legendary":
		ui.ask("Sell [color=#%s]%s[/color] for %d gold?" % [Data.rarity_color(it["rarity"]).to_html(false), it["name"], Loot.sell_value(it)], do_sell)
	else:
		do_sell.call()

func salvage(idx: int) -> void:
	var ch = Game.ch
	var it = ch.inventory[idx]
	if it == null:
		return
	var y: Dictionary = Loot.salvage_yield(it)
	var do_salvage := func():
		if ch.inventory[idx] != it:
			return
		ch.reclaim_gems(ch.inventory[idx])
		ch.inventory[idx] = null
		for k in y:
			ch.add_material(k, int(y[k]))
		if ui.panels["blacksmith"].selected == it:
			ui.panels["blacksmith"].select({})
		if ui.panels["jeweller"].selected == it:
			ui.panels["jeweller"].select({})
		Events.inventory_changed.emit()
		ui.toast("Salvaged: " + Loot.cost_text(y), Color("#c0a080"))
		ui.refresh_open()
	if _valuable(it):
		ui.ask("Salvage [color=#%s]%s[/color]?\nYou will receive: %s\n[color=#ff8080]The item will be destroyed.[/color]" % [Data.rarity_color(it["rarity"]).to_html(false), it["name"], Loot.cost_text(y)], do_salvage)
	else:
		do_salvage.call()

func _destroy(idx: int) -> void:
	var ch = Game.ch
	var it = ch.inventory[idx]
	if it == null:
		return
	ui.ask("Destroy [color=#%s]%s[/color]? This cannot be undone." % [Data.rarity_color(it["rarity"]).to_html(false), it["name"]], func():
		if ch.inventory[idx] == it:
			ch.reclaim_gems(ch.inventory[idx])
			ch.inventory[idx] = null
			Events.inventory_changed.emit())
