extends "res://scripts/ui/base_panel.gd"
## Storage chest with numbered tabs. Two stashes share this window:
##   Stash   - belongs to the current character (saved in its save file)
##   Shared  - belongs to the account (user://shared_stash.json); every character sees it
## Both can have extra tabs bought with gold (price in data/stash.json).
## LMB on a stash item moves it to your bag; LMB on a bag item stores it in the open tab.

const ItemSlot = preload("res://scripts/ui/item_slot.gd")
const Rules = preload("res://scripts/core/stash_rules.gd")

var slots := []
var mode := "stash"                       # "stash" | "shared"
var tab := {"stash": 0, "shared": 0}      # open tab of each stash
var mode_btns := {}
var gold_label: Label
var tab_row: HFlowContainer
var info_label: Label
var grid: GridContainer

func _init() -> void:
	place = "left"
	build("Stash", Vector2(420, 560))
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 6)
	body.add_child(mrow)
	for m in ["stash", "shared"]:
		var b := UIKit.button("Stash" if m == "stash" else "Shared Stash", _set_mode.bind(m), 120)
		mrow.add_child(b)
		mode_btns[m] = b
	gold_label = UIKit.label("", 13, UIKit.GOLD)
	gold_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mrow.add_child(gold_label)
	tab_row = HFlowContainer.new()
	tab_row.add_theme_constant_override("h_separation", 4)
	tab_row.add_theme_constant_override("v_separation", 4)
	body.add_child(tab_row)
	info_label = UIKit.label("", 11, UIKit.MUTED)
	body.add_child(info_label)
	grid = GridContainer.new()
	grid.columns = Rules.columns(Data.stash_cfg)
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	body.add_child(grid)
	for i in Rules.slots_per_tab(Data.stash_cfg):
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
	body.add_child(UIKit.label("Shared Stash is visible to all your characters (items only).", 11, UIKit.MUTED))
	Events.inventory_changed.connect(refresh)
	Events.currency_changed.connect(refresh)
	SharedStash.changed.connect(refresh)

# ------------------------------------------------------------------ state helpers
func is_shared() -> bool:
	return mode == "shared"

## Name used in the bag's hint and context menu ("Move to stash" / "Move to shared stash").
func target_name() -> String:
	return "shared stash" if is_shared() else "stash"

func _array() -> Array:
	return SharedStash.slots if is_shared() else Game.ch.stash

func _extra_bought() -> int:
	return SharedStash.extra_tabs if is_shared() else Game.ch.stash_extra_tabs

func _tab_total() -> int:
	return Rules.tab_total(Data.stash_cfg, _extra_bought(), is_shared())

func _set_mode(m: String) -> void:
	mode = m
	ui.hide_tooltip()
	Events.inventory_changed.emit()   # refreshes this panel and the bag's "move to ..." hint

func _set_tab(t: int) -> void:
	tab[mode] = t
	ui.hide_tooltip()
	refresh()

# ------------------------------------------------------------------ drawing
func refresh() -> void:
	if Game.ch == null or not visible:
		return
	var ch = Game.ch
	var cfg: Dictionary = Data.stash_cfg
	var arr: Array = _array()
	var total := _tab_total()
	tab[mode] = clampi(int(tab[mode]), 0, total - 1)
	title_label.text = "Shared Stash" if is_shared() else "Stash"
	for m in mode_btns:
		mode_btns[m].modulate = Color("#ffd060") if m == mode else Color.WHITE
	gold_label.text = "Gold: %d" % ch.gold
	# tab strip: one button per tab, then the buy button
	for c in tab_row.get_children():
		tab_row.remove_child(c)
		c.queue_free()
	var per := Rules.slots_per_tab(cfg)
	for t in total:
		var r := Rules.tab_range(cfg, t)
		var used := Rules.count_items(arr.slice(r.x, mini(r.y, arr.size())))
		var b := UIKit.button(str(t + 1), _set_tab.bind(t), 34)
		b.tooltip_text = "Tab %d - %d / %d items" % [t + 1, used, per]
		b.modulate = Color("#ffd060") if t == tab[mode] else Color.WHITE
		tab_row.add_child(b)
	var bought := _extra_bought()
	var maxed := bought >= Rules.max_extra(cfg)
	var why := Rules.buy_refusal(cfg, bought, ch.gold)
	var buy := UIKit.button("Max tabs" if maxed else "+ Buy tab (%dg)" % Rules.tab_cost(cfg, bought), _on_buy_pressed)
	buy.disabled = why != ""
	buy.tooltip_text = why
	tab_row.add_child(buy)
	if maxed:
		info_label.text = "Extra tabs: %d / %d (maximum)" % [bought, Rules.max_extra(cfg)]
	else:
		info_label.text = "Extra tabs: %d / %d   Next tab: %d gold" % [bought, Rules.max_extra(cfg), Rules.tab_cost(cfg, bought)]
	# the open tab's grid
	var rng := Rules.tab_range(cfg, tab[mode])
	for i in slots.size():
		var idx: int = rng.x + i
		slots[i].set_item(arr[idx] if idx < arr.size() else null)

# ------------------------------------------------------------------ buying a tab
func _on_buy_pressed() -> void:
	var cost := Rules.tab_cost(Data.stash_cfg, _extra_bought())
	ui.ask("Buy an extra tab for the %s?\nCost: [color=#e8c050]%d gold[/color]" % ["Shared Stash" if is_shared() else "Stash", cost], _do_buy)

func _do_buy() -> void:
	var err: String = SharedStash.buy_tab(Game.ch) if is_shared() else Game.ch.buy_stash_tab()
	if err != "":
		ui.toast(err, UIKit.BAD)
	else:
		tab[mode] = _tab_total() - 1   # jump to the new tab
		ui.toast("New tab bought", UIKit.GOOD)
	refresh()

# ------------------------------------------------------------------ moving items
## Stores bag item `bag_idx` in the open tab (or the nearest tab with room).
func deposit(bag_idx: int) -> void:
	var ch = Game.ch
	var it = ch.inventory[bag_idx]
	if it == null:
		return
	var want: int = tab[mode]
	if is_shared():
		var res: Dictionary = SharedStash.deposit(ch, bag_idx, want)
		if res["err"] != "":
			ui.toast(res["err"], UIKit.BAD)
			return
		if int(res["tab"]) != want:
			ui.toast("Tab %d was full - stored in tab %d" % [want + 1, int(res["tab"]) + 1], UIKit.MUTED)
		return
	var cfg: Dictionary = Data.stash_cfg
	var idx := Rules.free_slot_in_tab(cfg, ch.stash, want)
	var used := want
	if idx < 0:
		for t in ch.stash_tab_count():
			idx = Rules.free_slot_in_tab(cfg, ch.stash, t)
			if idx >= 0:
				used = t
				break
	if idx < 0:
		ui.toast("Stash is full", UIKit.BAD)
		return
	ch.stash[idx] = it
	ch.inventory[bag_idx] = null
	Events.inventory_changed.emit()
	if used != want:
		ui.toast("Tab %d was full - stored in tab %d" % [want + 1, used + 1], UIKit.MUTED)

func _on_click(s, button: int, _shift: bool) -> void:
	if s.item == null or button != MOUSE_BUTTON_LEFT:
		return
	var ch = Game.ch
	var idx: int = Rules.tab_range(Data.stash_cfg, tab[mode]).x + int(s.key)
	if is_shared():
		var err: String = SharedStash.withdraw(ch, idx)
		if err != "":
			ui.toast(err, UIKit.BAD)
	elif ch.add_to_bag(ch.stash[idx]):
		ch.stash[idx] = null
		Events.inventory_changed.emit()
	else:
		ui.toast("Inventory full", UIKit.BAD)
	ui.hide_tooltip()
