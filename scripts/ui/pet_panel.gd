extends "res://scripts/ui/base_panel.gd"
## Pet Keeper: buy pets with gold, upgrade each pet with crafting materials,
## rename them and pick which one follows you. Buying and upgrading happen in
## town; switching (and dismissing) works anywhere from the pause menu.

const PetRules = preload("res://scripts/core/pet_rules.gd")

var selected := ""
var list_box: VBoxContainer
var info: RichTextLabel
var wallet: RichTextLabel
var where_label: Label
var upgrade_btn: Button
var follow_btn: Button
var name_edit: LineEdit
var rename_btn: Button

func _init() -> void:
	place = "left"
	build("Pet Keeper Pip", Vector2(470, 620))
	body.add_child(UIKit.label("\"Every adventurer needs a friend who carries things.\"", 12, UIKit.MUTED))
	wallet = UIKit.rich("", 450)
	body.add_child(wallet)
	where_label = UIKit.label("", 11, UIKit.MUTED)
	where_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	where_label.custom_minimum_size = Vector2(450, 0)
	body.add_child(where_label)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(450, 230)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(sc)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list_box)
	body.add_child(HSeparator.new())
	var sc2 := ScrollContainer.new()
	sc2.custom_minimum_size = Vector2(450, 170)
	sc2.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(sc2)
	info = UIKit.rich("", 430)
	sc2.add_child(info)
	var h := HBoxContainer.new()
	upgrade_btn = UIKit.button("Upgrade", _upgrade)
	h.add_child(upgrade_btn)
	follow_btn = UIKit.button("Follow me", _toggle_follow)
	h.add_child(follow_btn)
	body.add_child(h)
	var h2 := HBoxContainer.new()
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Pet name"
	name_edit.max_length = int(PetRules.setting("name_max_length", 16))
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_submitted.connect(func(_t): _rename())
	h2.add_child(name_edit)
	rename_btn = UIKit.button("Rename", _rename)
	h2.add_child(rename_btn)
	body.add_child(h2)
	Events.currency_changed.connect(refresh)
	Events.pet_changed.connect(refresh)

static func in_town() -> bool:
	return Game.level != null and is_instance_valid(Game.level) and bool(Game.level.get("is_town"))

func on_open() -> void:
	var ch = Game.ch
	if ch != null and selected == "":
		selected = ch.active_pet if ch.active_pet != "" else (Data.pet_list[0]["id"] if not Data.pet_list.is_empty() else "")
	refresh()

func select(id: String) -> void:
	selected = id
	refresh()

func refresh() -> void:
	var ch = Game.ch
	if ch == null or not visible:
		return
	var town := in_town()
	var mats := []
	for k in Data.materials:
		mats.append("[color=%s]%s %d[/color]" % [Data.materials[k]["color"], Data.materials[k]["name"], int(ch.materials.get(k, 0))])
	wallet.text = "[color=#e8c050]Gold %d[/color]   %s" % [ch.gold, "  ".join(mats)]
	where_label.text = "Press F on a far-away item label and your pet fetches it. Pets also collect gold and materials on their own. Switching is free and keeps every upgrade." \
		if town else "You are away from town: you can switch pets here, but buying and upgrading happen at the Pet Keeper."
	for c in list_box.get_children():
		c.queue_free()
	for pd in Data.pet_list:
		list_box.add_child(_row(pd, ch, town))
	_refresh_info(ch, town)

func _row(pd: Dictionary, ch, town: bool) -> Control:
	var id: String = pd["id"]
	var row := HBoxContainer.new()
	var icon := TextureRect.new()
	icon.texture = Art.sprite(pd.get("sprite", "pet_dog"))
	icon.custom_minimum_size = Vector2(26, 26)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	row.add_child(icon)
	var owned: bool = ch.owns_pet(id)
	var txt := ""
	if owned:
		txt = "[color=#e0d8c8]%s[/color] [color=#8a8494](%s, tier %d)[/color]%s" % [ch.pet_name(id), pd["name"], ch.pet_tier(id), "  [color=#80e080]following[/color]" if ch.active_pet == id else ""]
	else:
		txt = "[color=#c8c0b0]%s[/color] [color=#8a8494]%s - %d gold[/color]" % [pd["name"], pd.get("group", ""), int(pd.get("price", 0))]
	var l := UIKit.rich(txt, 250)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var info_b := UIKit.button(">" if selected == id else "Info", select.bind(id))
	info_b.custom_minimum_size = Vector2(44, 0)
	row.add_child(info_b)
	if owned:
		var fb := UIKit.button("Following" if ch.active_pet == id else "Switch", _switch.bind(id))
		fb.disabled = ch.active_pet == id
		row.add_child(fb)
	else:
		var bb := UIKit.button("Buy", _buy.bind(id))
		var why: String = ch.can_buy_pet(id)
		bb.disabled = not town or why != ""
		bb.tooltip_text = "Buy at the Pet Keeper in town" if not town else why
		row.add_child(bb)
	return row

func _cap_lines(id: String, tier: int) -> String:
	var s := PetRules.stats(id, tier)
	var fr := int(s["fetch_rarity"])
	var fetch_txt := "gold and materials only (gems and runes from tier %d)" % int(PetRules.setting("gem_rune_min_tier", 1))
	if fr >= 0 and fr < Data.rarity_list.size():
		fetch_txt = "%s items and below, gems, runes, gold, materials" % Data.rarity_list[fr]["name"]
	var lines := []
	lines.append("F fetch: %s" % fetch_txt)
	lines.append("Speed %d   F cooldown %.1f s   F range %s" % [int(s["speed"]), float(s["fetch_cd"]), "camera view" if float(s["fetch_range"]) < 0 else "%d px" % int(s["fetch_range"])])
	lines.append("Auto-loot every %.2f s within %s" % [float(s["auto_cd"]), "camera view" if float(s["auto_radius"]) < 0 else "%d px" % int(s["auto_radius"])])
	var extras := []
	if s["blink"]:
		extras.append("blink")
	if s["wall_pass"]:
		extras.append("passes walls")
	if float(s["magnet_radius"]) > 0:
		extras.append("magnet %d px" % int(s["magnet_radius"]))
	if not extras.is_empty():
		lines.append(", ".join(extras).capitalize())
	return "\n".join(lines)

func _refresh_info(ch, town: bool) -> void:
	var pd: Dictionary = Data.pets.get(selected, {})
	if pd.is_empty():
		info.text = "[color=#8a8494]Pick a pet.[/color]"
		upgrade_btn.visible = false
		follow_btn.visible = false
		name_edit.editable = false
		rename_btn.disabled = true
		return
	var owned: bool = ch.owns_pet(selected)
	var tier: int = ch.pet_tier(selected) if owned else 0
	var lines := []
	lines.append("[font_size=16][color=#c8a060]%s[/color][/font_size]  [color=#8a8494]%s pet%s[/color]" % [ch.pet_name(selected) if owned else pd["name"], pd.get("group", ""), "" if owned else " - %d gold" % int(pd.get("price", 0))])
	lines.append("[color=#a0a0b8]%s[/color]" % pd.get("quirk_text", ""))
	if pd.has("signature_text"):
		lines.append("[color=#ffd080]Signature: %s[/color]" % pd["signature_text"])
	lines.append("")
	lines.append("[color=#c8a060]Tier %d[/color] - %s\n%s" % [tier, PetRules.tier_def(tier).get("capability", ""), _cap_lines(selected, tier)])
	if tier < PetRules.max_tier():
		var cost := PetRules.upgrade_cost(selected, tier)
		var afford: bool = ch.has_materials(cost)
		var nd := PetRules.tier_def(tier + 1)
		lines.append("")
		lines.append("[color=#c8a060]Next: tier %d[/color] - fetches %s, %s" % [tier + 1, nd.get("label", ""), str(nd.get("capability", "")).to_lower()])
		lines.append("[color=%s]Cost: %s[/color]" % ["#80e080" if afford else "#ff8080", Loot.cost_text(cost)])
	else:
		lines.append("\n[color=#80e080]Fully upgraded.[/color]")
	info.text = "\n".join(lines)
	upgrade_btn.visible = owned
	upgrade_btn.disabled = not town or ch.can_upgrade_pet(selected) != ""
	upgrade_btn.text = "Upgrade" if tier < PetRules.max_tier() else "Max tier"
	upgrade_btn.tooltip_text = "Upgrade at the Pet Keeper in town" if not town else ch.can_upgrade_pet(selected)
	follow_btn.visible = owned
	follow_btn.text = "Send home" if ch.active_pet == selected else "Follow me"
	name_edit.editable = owned
	rename_btn.disabled = not owned
	if owned and not name_edit.has_focus():
		name_edit.text = ch.pet_name(selected)

func _buy(id: String) -> void:
	if not in_town():
		ui.toast("Buy pets at the Pet Keeper in town", UIKit.BAD)
		return
	var e: String = Game.ch.buy_pet(id)
	if e != "":
		ui.toast(e, UIKit.BAD)
		return
	selected = id
	Sfx.play_pitched("chirp", float(Data.pets[id].get("chirp", 1.0)))
	ui.toast("%s joins you!" % Data.pets[id]["name"], Color("#ffd080"))
	refresh()

func _switch(id: String) -> void:
	if Game.ch.set_active_pet(id):
		selected = id
		Sfx.play_pitched("chirp", float(Data.pets[id].get("chirp", 1.0)))
	refresh()

func _toggle_follow() -> void:
	var ch = Game.ch
	if ch.active_pet == selected:
		ch.set_active_pet("")
	else:
		ch.set_active_pet(selected)
	refresh()

func _upgrade() -> void:
	if not in_town():
		ui.toast("Upgrade pets at the Pet Keeper in town", UIKit.BAD)
		return
	var ch = Game.ch
	var cost := PetRules.upgrade_cost(selected, ch.pet_tier(selected))
	ui.ask("Upgrade %s to tier %d?\nCost: %s" % [ch.pet_name(selected), ch.pet_tier(selected) + 1, Loot.cost_text(cost)], func():
		var e: String = ch.upgrade_pet(selected)
		if e != "":
			ui.toast(e, UIKit.BAD)
		else:
			Sfx.play("levelup", 0.0)
			ui.toast("%s is now tier %d" % [ch.pet_name(selected), ch.pet_tier(selected)], Color("#ffd080"))
		refresh())

func _rename() -> void:
	var ch = Game.ch
	if ch.rename_pet(selected, name_edit.text):
		name_edit.release_focus()
		refresh()
