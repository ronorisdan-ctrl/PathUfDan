extends "res://scripts/ui/base_panel.gd"
## Merchant: buy gear, refill flasks, sell from the inventory (Shift+LMB or RMB).

const ItemSlot = preload("res://scripts/ui/item_slot.gd")

var grid: GridContainer
var slots := []
var gold_label: Label

func _init() -> void:
	place = "left"
	build("Merchant Varga", Vector2(420, 460))
	body.add_child(UIKit.label("\"Coin for steel, steel for coin. The dead don't haggle.\"", 12, UIKit.MUTED))
	grid = GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	body.add_child(grid)
	for i in 16:
		var s = ItemSlot.new()
		s.key = i
		s.clicked.connect(_on_click)
		s.hovered.connect(_on_hover)
		s.unhovered.connect(func(_s): ui.hide_tooltip())
		grid.add_child(s)
		slots.append(s)
	gold_label = UIKit.label("", 14, Color("#e8c050"))
	body.add_child(gold_label)
	var h := HBoxContainer.new()
	h.add_child(UIKit.button("Refill flasks (free)", _refill))
	h.add_child(UIKit.button("New stock (%s)" % "25 gold", _reroll))
	h.add_child(UIKit.button("Buy random rune", _buy_rune))
	body.add_child(h)
	body.add_child(UIKit.label("LMB an item to buy it. Sell with Shift+LMB or RMB in your inventory.", 11, UIKit.MUTED))
	Events.currency_changed.connect(refresh)

func on_open() -> void:
	if Game.vendor_stock.is_empty():
		Game.refresh_vendor()
	refresh()

func refresh() -> void:
	if Game.ch == null or not visible:
		return
	for i in slots.size():
		var it = Game.vendor_stock[i] if i < Game.vendor_stock.size() else null
		slots[i].set_item(it)
		slots[i].price = Loot.buy_value(it) if it != null else -1
	gold_label.text = "Your gold: %d" % Game.ch.gold
	ui.panels["inventory"].refresh()

func _on_hover(s) -> void:
	if s.item != null:
		ui.item_tooltip(s.item, true)

func _on_click(s, button: int, _shift: bool) -> void:
	if s.item == null or button != MOUSE_BUTTON_LEFT:
		return
	var it: Dictionary = s.item
	var price := Loot.buy_value(it)
	var ch = Game.ch
	if ch.gold < price:
		ui.toast("Not enough gold (%d needed)" % price, UIKit.BAD)
		return
	if ch.free_bag_slot() < 0:
		ui.toast("Inventory full", UIKit.BAD)
		return
	ui.ask("Buy [color=#%s]%s[/color] for %d gold?" % [Data.rarity_color(it["rarity"]).to_html(false), it["name"], price], func():
		if ch.gold >= price and Game.vendor_stock.has(it):
			ch.gold -= price
			Game.vendor_stock.erase(it)
			ch.add_to_bag(it)
			Events.currency_changed.emit()
			refresh())

func _refill() -> void:
	Game.ch.flask_charges = [3.0, 3.0]
	if Game.level != null and Game.level.player != null:
		var p = Game.level.player
		p.life = p.max_life
		p.mana = Game.ch.final.get("max_mana", 0)
	ui.toast("Flasks refilled", Color("#a0d0ff"))

func rune_price() -> int:
	return 60 + 12 * Game.ch.level

func _buy_rune() -> void:
	var ch = Game.ch
	var price := rune_price()
	ui.ask("Buy a random skill rune for %d gold?" % price, func():
		if ch.gold < price:
			ui.toast("Not enough gold", UIKit.BAD)
			return
		ch.gold -= price
		var rid: String = Loot.random_rune()
		ch.add_rune(rid)
		ui.toast("Bought %s" % Data.skill_runes[rid]["name"], Color(Data.skill_runes[rid]["color"]))
		refresh())

func _reroll() -> void:
	if Game.ch.gold < 25:
		ui.toast("Not enough gold", UIKit.BAD)
		return
	Game.ch.gold -= 25
	Game.refresh_vendor()
	Events.currency_changed.emit()
	refresh()
