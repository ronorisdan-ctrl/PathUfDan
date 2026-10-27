extends "res://scripts/ui/base_panel.gd"
## Blacksmith crafting: upgrade, reroll / add / remove affixes, raise rarity
## and salvage. Every operation shows cost, availability and a preview,
## and permanent changes require confirmation.

var selected = null
var affix_index := -1
var op := "upgrade"
var item_text: RichTextLabel
var affix_box: VBoxContainer
var op_box: VBoxContainer
var preview: RichTextLabel
var confirm_btn: Button
var mats: RichTextLabel
var scroll: ScrollContainer

func _init() -> void:
	place = "left"
	build("Blacksmith Oren", Vector2(440, 0))
	# Everything except the Craft button and the materials line lives in one
	# scroll area, so a long affix / operation list can never push Craft off
	# the screen. The scroll height is set in reposition() from the viewport.
	scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6)
	scroll.add_child(content)
	content.add_child(UIKit.label("Select an item in your inventory or equipment.", 12, UIKit.MUTED))
	item_text = UIKit.rich("", 390)
	content.add_child(item_text)
	content.add_child(UIKit.label("Affixes (choose one for reroll / remove)", 13, UIKit.GOLD))
	affix_box = VBoxContainer.new()
	content.add_child(affix_box)
	content.add_child(UIKit.label("Operation", 13, UIKit.GOLD))
	op_box = VBoxContainer.new()
	content.add_child(op_box)
	preview = UIKit.rich("", 390)
	content.add_child(preview)
	# Pinned below the scroll area: always visible.
	confirm_btn = UIKit.button("Craft", _craft)
	body.add_child(confirm_btn)
	mats = UIKit.rich("", 420)
	body.add_child(mats)
	Events.currency_changed.connect(refresh)

## Fit the scroll area to the window: viewport height minus the title bar,
## Craft button, materials line and the panel's own padding.
func reposition() -> void:
	var vh := get_viewport_rect().size.y
	scroll.custom_minimum_size.y = clampf(vh - 240.0, 200.0, 620.0)
	super.reposition()

func _show_preview() -> void:
	await get_tree().process_frame
	if visible and is_instance_valid(scroll) and is_instance_valid(preview):
		scroll.ensure_control_visible(preview)

func on_close() -> void:
	selected = null
	affix_index = -1

func select(it) -> void:
	selected = it if (it != null and not it.is_empty()) else null
	affix_index = -1
	scroll.scroll_vertical = 0
	refresh()
	ui.panels["inventory"].refresh()

func refresh() -> void:
	var ch = Game.ch
	if ch == null or not visible:
		return
	for c in affix_box.get_children():
		c.queue_free()
	for c in op_box.get_children():
		c.queue_free()
	var parts := []
	for k in Data.materials:
		parts.append("[color=%s]%s %d[/color]" % [Data.materials[k]["color"], Data.materials[k]["name"], int(ch.materials.get(k, 0))])
	mats.text = "[color=#e8c050]Gold %d[/color]   " % ch.gold + "   ".join(parts)
	if selected == null:
		item_text.text = "[color=#8a8494]No item selected.[/color]"
		preview.text = ""
		confirm_btn.disabled = true
		return
	item_text.text = Loot.tooltip(selected, ch)
	var affs: Array = selected.get("affixes", [])
	for i in affs.size():
		var b := UIKit.button(("> " if i == affix_index else "   ") + Loot.affix_text(affs[i]), _pick_affix.bind(i))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		affix_box.add_child(b)
	if affs.is_empty():
		affix_box.add_child(UIKit.label("(none)", 12, UIKit.MUTED))
	for o in Loot.craft_ops():
		var cost: Dictionary = Loot.craft_cost(o, selected)
		var why: String = Loot.craft_check(o, selected, affix_index)
		var afford: bool = ch.has_materials(cost)
		var b2 := UIKit.button("%s%s   -   %s" % ["> " if o == op else "   ", Loot.craft_name(o), Loot.cost_text(cost)], _pick_op.bind(o))
		b2.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if why != "" and why != "Choose an affix":
			b2.modulate = Color(1, 1, 1, 0.5)
		elif not afford:
			b2.modulate = Color(1, 0.7, 0.7)
		op_box.add_child(b2)
	var why2: String = Loot.craft_check(op, selected, affix_index)
	var cost2: Dictionary = Loot.craft_cost(op, selected)
	var lines := ["[color=#c8a060]%s[/color]" % Loot.craft_name(op)]
	if why2 != "":
		lines.append("[color=#ff8080]%s[/color]" % why2)
	else:
		lines.append(Loot.craft_preview(op, selected, affix_index))
		lines.append("Cost: %s" % Loot.cost_text(cost2))
		if not ch.has_materials(cost2):
			lines.append("[color=#ff8080]You do not have enough materials[/color]")
	preview.text = "\n".join(lines)
	confirm_btn.disabled = why2 != "" or not ch.has_materials(cost2)

func _pick_affix(i: int) -> void:
	affix_index = i
	if op not in ["reroll", "remove"]:
		op = "reroll"
	refresh()

func _pick_op(o: String) -> void:
	op = o
	refresh()
	_show_preview()

func _craft() -> void:
	var ch = Game.ch
	if selected == null:
		return
	if Loot.craft_check(op, selected, affix_index) != "":
		return
	var cost: Dictionary = Loot.craft_cost(op, selected)
	var it: Dictionary = selected
	var o := op
	var ai := affix_index
	ui.ask("%s on [color=#%s]%s[/color]?\n%s\nCost: %s" % [Loot.craft_name(o), Data.rarity_color(it["rarity"]).to_html(false), it["name"], Loot.craft_preview(o, it, ai), Loot.cost_text(cost)], func():
		if not ch.pay(cost):
			ui.toast("Not enough materials", UIKit.BAD)
			return
		Loot.craft_apply(o, it, ai)
		affix_index = -1
		ch.recalc()
		Events.inventory_changed.emit()
		ui.toast("%s complete" % Loot.craft_name(o), Color("#ffd080"))
		refresh())
