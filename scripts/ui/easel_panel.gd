extends "res://scripts/ui/base_panel.gd"
## The Easel (Endgame Phase 1E): craft Pigments from Glaze Flakes / Pigment Dust and slot them for
## the next Atlas runs. Opened from the Atlas. Phase 3B: the Varnish slots are gone; the right column
## shows the Atelier (the board that replaced them) and opens it.

const Chrome = preload("res://scripts/ui/components/station_chrome.gd")
const AtlasRules = preload("res://scripts/core/atlas_rules.gd")
const AtelierRules = preload("res://scripts/core/atelier_rules.gd")

var info: RichTextLabel
var craft_box: VBoxContainer
var easel_box: VBoxContainer
var stock_box: VBoxContainer
var atelier_box: VBoxContainer
var last_msg := ""

func _init() -> void:
	place = "center"
	build("The Easel", Vector2(820, 540))
	Chrome.apply(self)
	info = UIKit.rich()
	info.fit_content = true
	body.add_child(info)
	var h := HBoxContainer.new()
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_theme_constant_override("separation", 14)
	body.add_child(h)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(left)
	left.add_child(Chrome.caption("Craft"))
	craft_box = VBoxContainer.new()
	left.add_child(craft_box)
	left.add_child(Chrome.caption("Slotted Pigments (used in this order)"))
	easel_box = VBoxContainer.new()
	left.add_child(easel_box)
	left.add_child(Chrome.caption("Pigment stock"))
	var sc := Chrome.reading_scroll(left, 170)
	stock_box = VBoxContainer.new()
	stock_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(stock_box)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(right)
	right.add_child(Chrome.caption("The Atelier"))
	var sc2 := Chrome.reading_scroll(right, 360)
	atelier_box = VBoxContainer.new()
	atelier_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc2.add_child(atelier_box)
	var hb := HBoxContainer.new()
	hb.add_child(UIKit.button("Back to the Atlas", func(): ui.toggle("atlas")))
	body.add_child(hb)

func reposition() -> void:
	Chrome.place_panel(self, Vector2(900, 620))

func state() -> Dictionary:
	if Game.ch == null or not AtlasRules.unlocked(Game.ch):
		return {}
	return AtlasRules.ensure(Game.ch)

func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()

func _row(box: Node, text: String) -> HBoxContainer:
	var r := HBoxContainer.new()
	var l := UIKit.rich(text)
	l.fit_content = true
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(l)
	box.add_child(r)
	return r

func _act(ok: bool, msg: String) -> void:
	last_msg = msg
	if ui != null and msg != "":
		ui.toast(msg, Color("#e0c890") if ok else Color("#ff8080"))
	Game.save_game()
	refresh()
	if ui != null and ui.is_open("atlas"):
		ui.panels["atlas"].refresh()

func _craft(id: String) -> void:
	var res := AtlasRules.craft_pigment(state(), Game.ch, id)
	if res.get("ok", false):
		_act(true, "Crafted %s" % AtlasRules.pigment_label(res["pigment"]))
	else:
		_act(false, str(res.get("msg", "")))

func refresh() -> void:
	for b in [craft_box, easel_box, stock_box, atelier_box]:
		_clear(b)
	var st := state()
	if st.is_empty():
		info.text = "[color=#ff8080]Locked - %s[/color]" % str(AtlasRules.cfg().get("unlock_text", ""))
		return
	var ch = Game.ch
	var pc := AtlasRules.pig_cfg()
	var mats := []
	for p in pc.get("list", []):
		var mid := str(p.get("material", ""))
		mats.append("%s: %d" % [str(Data.materials.get(mid, {}).get("name", mid)), int(ch.materials.get(mid, 0))])
	var fx := AtlasRules.atelier_fx(st)
	info.text = "[color=#8a8494]Each slotted Pigment guarantees its mechanic in the zones it fits, adds one modifier and +%d%% rewards. Entering a zone spends 1 charge; dying there spends %d more. Zones have %d Pigment slot (+1 in ring %d or a Restored region%s).[/color]\n%s   [color=#8a8494]Pigments %d / %d[/color]" % [
		int(float(pc.get("reward", 10)) + float(fx["pigment_reward"])), 0 if fx["death_no_charge"] else int(pc.get("death_charges", 1)), int(pc.get("slots", 1)) + int(fx["pigment_slots"]), int(pc.get("extra_slot_ring", 3)),
		"; at most %d with Binding Varnish" % int(fx["pigment_slots_max"]) if int(fx["pigment_slots_max"]) < 99 else "",
		"   ".join(mats), AtlasRules.pigment_count(st), int(pc.get("stock_cap", 12))]
	# craft
	for p in pc.get("list", []):
		var id := str(p.get("id", ""))
		var mech := AtlasRules.mechanic_info(id)
		var mid := str(p.get("material", ""))
		var price := AtlasRules.pigment_cost(st, id)
		var r := _row(craft_box, "[color=%s]%s[/color]  [color=#8a8494]%d %s, %d charges, random modifier[/color]" % [str(mech.get("color", "#ffffff")), str(p.get("name", id)), price, str(Data.materials.get(mid, {}).get("name", mid)), int(pc.get("charges", 4)) + int(fx["pigment_charges"])])
		var b := UIKit.button("Craft", func(): _craft(id))
		b.disabled = not ch.has_materials({mid: price}) or AtlasRules.pigment_count(st) >= int(pc.get("stock_cap", 12))
		r.add_child(b)
	# slotted
	var easel: Array = st.get("easel", [])
	if easel.is_empty():
		_row(easel_box, "[color=#8a8494]Empty. Slot a Pigment from your stock.[/color]")
	for i in easel.size():
		var p: Dictionary = easel[i]
		var r := _row(easel_box, "%d. %s  [color=#8a8494]%s[/color]" % [i + 1, AtlasRules.pigment_label(p), str(AtlasRules.pigment_mod(str(p["id"]), str(p["mod"])).get("desc", ""))])
		var idx := i
		r.add_child(UIKit.button("Unslot", func(): _act(AtlasRules.unslot_pigment(state(), idx), "")))
	# stock
	var stock: Array = st.get("pigments", [])
	if stock.is_empty():
		_row(stock_box, "[color=#8a8494]No Pigments. Craft one above.[/color]")
	for i in stock.size():
		var p: Dictionary = stock[i]
		var r := _row(stock_box, "%s  [color=#8a8494]%s[/color]" % [AtlasRules.pigment_label(p), str(AtlasRules.pigment_mod(str(p["id"]), str(p["mod"])).get("desc", ""))])
		var idx := i
		var b := UIKit.button("Slot", func(): _act(AtlasRules.slot_pigment(state(), idx), ""))
		b.disabled = easel.size() >= AtlasRules.easel_slots(st)
		r.add_child(b)
	# the Atelier (Phase 3B: replaced the Varnish slots)
	_row(atelier_box, "[color=#8a8494]The Varnish slots are gone. The Atelier is a board of zone rules: earn points by clearing ring 2+ regions for the first time and by defeating each Layer Warden, then spend them on nodes. Respec is free.[/color]")
	_row(atelier_box, "[color=#e8d8a0]%s[/color]   [color=#80e080]%d free[/color]" % [AtelierRules.summary_text(st), AtelierRules.points_free(st)])
	var names := []
	for id in AtelierRules.taken(st):
		names.append(str(AtlasRules.atelier_node(str(id)).get("name", id)))
	_row(atelier_box, "[color=#8a8494]Taken:[/color] %s" % (", ".join(names) if not names.is_empty() else "none yet"))
	var ob := _row(atelier_box, "")
	ob.add_child(UIKit.button("Open the Atelier", func(): ui.toggle("atelier")))
