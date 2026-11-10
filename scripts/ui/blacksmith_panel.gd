extends "res://scripts/ui/base_panel.gd"
## Blacksmith crafting: upgrade, reroll / add / remove affixes, raise rarity
## and salvage. Every operation shows cost, availability and a preview,
## and permanent changes require confirmation.

var selected = null
const Chrome = preload("res://scripts/ui/components/station_chrome.gd")
var affix_index := -1
var op := "upgrade"
var item_text: RichTextLabel
var corr_bar: Control
var affix_box: VBoxContainer
var op_box: VBoxContainer
var preview: RichTextLabel
var confirm_btn: Button
var mats: RichTextLabel
var scroll: ScrollContainer
var corruption_result: RichTextLabel
const CorruptionRules = preload("res://scripts/core/corruption_rules.gd")
## Own random stream for corruption rolls. Never the global, Combat or Loot RNG,
## so crafting corruption cannot change drops or combat. Tests may replace it.
var corr_rng := RandomNumberGenerator.new()

func _init() -> void:
	corr_rng.randomize()
	place = "left"
	build("Blacksmith Oren", Vector2(440, 0))
	Chrome.apply(self)
	# Everything except the Craft button and the materials line lives in one
	# scroll area, so a long affix / operation list can never push Craft off
	# the screen. The scroll expands inside the viewport-bounded cabinet.
	scroll = ScrollContainer.new()
	scroll.custom_minimum_size.y = 180
	Chrome.scroll_inset(scroll)
	body.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6)
	scroll.add_child(content)
	content.add_child(Chrome.caption("Select an item in your inventory or equipment."))
	item_text = UIKit.rich()
	content.add_child(item_text)
	corr_bar = preload("res://scripts/ui/corruption_bar.gd").new()
	corr_bar.visible = false
	content.add_child(corr_bar)
	content.add_child(UIKit.label("Affixes (choose one for reroll / remove)", 13, UIKit.GOLD))
	affix_box = VBoxContainer.new()
	content.add_child(affix_box)
	content.add_child(UIKit.label("Operation", 13, UIKit.GOLD))
	op_box = VBoxContainer.new()
	content.add_child(op_box)
	preview = UIKit.rich()
	content.add_child(preview)
	corruption_result = UIKit.rich()
	content.add_child(corruption_result)
	# Pinned below the scroll area: always visible.
	confirm_btn = UIKit.button("Craft", _craft)
	body.add_child(confirm_btn)
	mats = UIKit.rich()
	Chrome.inset(body, mats)
	Events.currency_changed.connect(refresh)
	Events.inventory_changed.connect(refresh)

## Keep the reading area flexible while Craft and the wallet stay pinned.
func reposition() -> void:
	Chrome.place_panel(self, Vector2(480, 660))

func _show_preview() -> void:
	await get_tree().process_frame
	if visible and is_instance_valid(scroll) and is_instance_valid(preview):
		scroll.ensure_control_visible(preview)

func on_close() -> void:
	selected = null
	affix_index = -1

func select(it) -> void:
	selected = it if (it != null and not it.is_empty()) else null
	corruption_result.text = ""
	affix_index = -1
	scroll.scroll_vertical = 0
	refresh()
	ui.panels["inventory"].refresh()

func refresh() -> void:
	var ch = Game.ch
	if ch == null or not visible:
		return
	confirm_btn.text = "Corrupt Item" if op == "corrupt" else "Craft"
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
		corr_bar.visible = false
		preview.text = ""
		confirm_btn.disabled = true
		return
	item_text.text = Loot.tooltip(selected, ch, false)   # the readout below replaces the tooltip line
	corr_bar.set_item(selected)
	corr_bar.visible = true
	var affs: Array = selected.get("affixes", [])
	for i in affs.size():
		var b := UIKit.button(("> " if i == affix_index else "   ") + Loot.affix_text(affs[i]), _pick_affix.bind(i))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		affix_box.add_child(b)
		Chrome.wrap_button(b)
	if affs.is_empty():
		affix_box.add_child(UIKit.label("(none)", 12, UIKit.MUTED))
	for o in Loot.craft_ops() + ["corrupt"]:
		var cost: Dictionary = Loot.craft_cost(o, selected)
		var why: String = Loot.craft_check(o, selected, affix_index)
		var afford: bool = ch.has_materials(cost)
		var label2 := "%s%s   -   %s" % ["> " if o == op else "   ", Loot.craft_name(o), Loot.cost_text(cost)]
		if CorruptionRules.rolls_for(o):
			label2 += "\n      Risk: %s" % CorruptionRules.risk_text()
		var b2 := UIKit.button(label2, _pick_op.bind(o))
		b2.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var cwhy: String = CorruptionRules.craft_refusal(selected, o)
		if cwhy != "":
			b2.disabled = true            # fully corrupted: every craft is sealed
			b2.tooltip_text = cwhy
		if why != "" and why != "Choose an affix":
			b2.modulate = Color(1, 1, 1, 0.5)
		elif not afford:
			b2.modulate = Color(1, 0.7, 0.7)
		op_box.add_child(b2)
		Chrome.wrap_button(b2)
	var why2: String = Loot.craft_check(op, selected, affix_index)
	var cost2: Dictionary = Loot.craft_cost(op, selected)
	var lines := ["[color=#c8a060]%s[/color]" % Loot.craft_name(op)]
	if why2 != "":
		lines.append("[color=#ff8080]%s[/color]" % why2)
	else:
		lines.append(Loot.craft_preview(op, selected, affix_index))
		if CorruptionRules.rolls_for(op):
			lines.append("[color=#e0a030]Risk: %s  (%s)[/color]" % [CorruptionRules.risk_text(), CorruptionRules.events_text(selected)])
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
	if ui.confirm.visible:
		return
	if op == "corrupt":
		_corrupt()
		return
	if Loot.craft_check(op, selected, affix_index) != "":
		return
	var cost: Dictionary = Loot.craft_cost(op, selected)
	var it: Dictionary = selected
	var o := op
	var ai := affix_index
	var risk_note: String = CorruptionRules.confirm_text(it, o)
	ui.ask("%s on [color=#%s]%s[/color]?\n%s\nCost: %s%s" % [Loot.craft_name(o), Data.rarity_color(it["rarity"]).to_html(false), it["name"], Loot.craft_preview(o, it, ai), Loot.cost_text(cost), ("\n" + risk_note) if risk_note != "" else ""], func():
		if Game.ch != ch or Loot.craft_check(o, it, ai) != "":
			ui.toast("Item is no longer available for this craft", UIKit.BAD)
			return
		if not ch.pay(cost):
			ui.toast("Not enough materials", UIKit.BAD)
			return
		var cr := apply_craft(o, it, ai)
		affix_index = -1
		ch.recalc()
		Events.inventory_changed.emit()
		var extra := CorruptionRules.result_text(cr)
		ui.toast("%s complete%s" % [Loot.craft_name(o), ("  -  " + extra) if extra != "" else ""], Color("#ffd080") if not cr.get("hit", false) else UIKit.BAD)
		refresh())

## Applies a craft in full, THEN rolls for corruption (add / reroll / raise rarity).
## The craft is never weakened or wasted by corruption, including the one that
## takes the item to 100%. Payment and confirmation happen before this is called.
## Returns the roll result {rolled, hit, before, after}.
func apply_craft(o: String, it: Dictionary, ai: int) -> Dictionary:
	if Loot.craft_check(o, it, ai) != "":
		return {"rolled": false, "hit": false}
	Loot.craft_apply(o, it, ai)
	return CorruptionRules.roll(it, o, corr_rng)

func _corrupt() -> void:
	var ch = Game.ch
	var uid: int = int(selected.get("uid", 0))
	var why: String = ch.corruption_refusal(uid)
	if why != "":
		ui.toast(why, UIKit.BAD)
		return
	var action: String = ch.new_corruption_action_id()
	ui.ask(Loot.corruption_warning() + "\n\nPermanently corrupt [color=#db79e8]%s[/color]?" % selected.get("name", "item"), func():
		if Game.ch != ch:
			return
		confirm_btn.disabled = true
		var result: Dictionary = ch.corrupt_item(uid, action, corr_rng)
		if result["err"] != "":
			ui.toast(result["err"], UIKit.BAD)
			refresh()
			return
		selected = result["item"]
		var text := "[color=#db79e8]CORRUPTION RESULT[/color]\n"
		if result["outcome"] == "destroyed":
			text += "Item destroyed. Socketed gems recovered."
		else:
			text += "Corrupted (100%) — FINAL\n"
			text += "No new modifier." if result["outcome"] == "no_modifier" else Loot.corrupted_implicit_text(selected)
		corruption_result.text = text
		corruption_result.modulate = Color("#db79e8")
		corruption_result.create_tween().tween_property(corruption_result, "modulate", Color.WHITE, 0.6)
		ui.toast("Corruption: " + result["outcome"].replace("_", " "), Color("#db79e8"))
		refresh()
		_show_corruption_result())

func _show_corruption_result() -> void:
	await get_tree().process_frame
	if visible and is_instance_valid(scroll) and is_instance_valid(corruption_result):
		scroll.ensure_control_visible(corruption_result)
