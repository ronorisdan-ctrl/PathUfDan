extends "res://scripts/ui/base_panel.gd"
## Shared storage chest. LMB moves items between stash and bag.

const ItemSlot = preload("res://scripts/ui/item_slot.gd")

var slots := []

func _init() -> void:
	place = "left"
	build("Stash", Vector2(420, 430))
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	body.add_child(grid)
	for i in 56:
		var s = ItemSlot.new()
		s.key = i
		s.clicked.connect(_on_click)
		s.hovered.connect(func(sl):
			if sl.item != null:
				ui.item_tooltip(sl.item, true))
		s.unhovered.connect(func(_s): ui.hide_tooltip())
		grid.add_child(s)
		slots.append(s)
	body.add_child(UIKit.label("LMB: take an item. LMB in your bag: store it.", 11, UIKit.MUTED))
	Events.inventory_changed.connect(refresh)

func refresh() -> void:
	if Game.ch == null or not visible:
		return
	for i in slots.size():
		slots[i].set_item(Game.ch.stash[i] if i < Game.ch.stash.size() else null)

func deposit(bag_idx: int) -> void:
	var ch = Game.ch
	var it = ch.inventory[bag_idx]
	if it == null:
		return
	for i in mini(ch.stash.size(), slots.size()):
		if ch.stash[i] == null:
			ch.stash[i] = it
			ch.inventory[bag_idx] = null
			Events.inventory_changed.emit()
			return
	ui.toast("Stash is full", UIKit.BAD)

func _on_click(s, button: int, _shift: bool) -> void:
	if s.item == null or button != MOUSE_BUTTON_LEFT:
		return
	var ch = Game.ch
	var i: int = s.key
	if ch.add_to_bag(ch.stash[i]):
		ch.stash[i] = null
		Events.inventory_changed.emit()
	else:
		ui.toast("Inventory full", UIKit.BAD)
	ui.hide_tooltip()
