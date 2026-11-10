extends "res://scripts/ui/base_panel.gd"
## The Easel (Endgame Phase 1E): craft Pigments from Glaze Flakes / Pigment Dust, slot them for the
## next Atlas runs, and slot Varnishes (rule-changers dropped by Hearts of Rot). Opened from the Atlas.

const Chrome = preload("res://scripts/ui/components/station_chrome.gd")
const AtlasRules = preload("res://scripts/core/atlas_rules.gd")

var info: RichTextLabel
var craft_box: VBoxContainer
var easel_box: VBoxContainer
var stock_box: VBoxContainer
var varnish_box: VBoxContainer
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
	right.add_child(Chrome.caption("Varnish"))
	var sc2 := Chrome.reading_scroll(right, 360)
	varnish_box = VBoxContainer.new()
	varnish_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc2.add_child(varnish_box)
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
	for b in [craft_box, easel_box, stock_box, varnish_box]:
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
	info.text = "[color=#8a8494]Each slotted Pigment guarantees its mechanic in the zones it fits, adds one modifier and +%d%% rewards. Entering a zone spends 1 charge; dying there spends %d more. Zones have %d Pigment slot (%d in ring %d or a Restored region).[/color]\n%s   [color=#8a8494]Pigments %d / %d[/color]" % [
		int(pc.get("reward", 10)), int(pc.get("death_charges", 1)), int(pc.get("slots", 1)), int(pc.get("max_slots", 2)), int(pc.get("extra_slot_ring", 3)),
		"   ".join(mats), AtlasRules.pigment_count(st), int(pc.get("stock_cap", 12))]
	# craft
	for p in pc.get("list", []):
		var id := str(p.get("id", ""))
		var mech := AtlasRules.mechanic_info(id)
		var mid := str(p.get("material", ""))
		var r := _row(craft_box, "[color=%s]%s[/color]  [color=#8a8494]%d %s, %d charges, random modifier[/color]" % [str(mech.get("color", "#ffffff")), str(p.get("name", id)), int(p.get("cost", 1)), str(Data.materials.get(mid, {}).get("name", mid)), int(pc.get("charges", 4)) + int(AtlasRules.varnish_fx(st)["pigment_charges"])])
		var b := UIKit.button("Craft", func(): _craft(id))
		b.disabled = not ch.has_materials({mid: int(p.get("cost", 1))}) or AtlasRules.pigment_count(st) >= int(pc.get("stock_cap", 12))
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
		b.disabled = easel.size() >= int(pc.get("max_slots", 2))
		r.add_child(b)
	# varnish
	var slots: Array = st.get("varnish_slots", [])
	var nslots := AtlasRules.varnish_slot_count(st)
	_row(varnish_box, "[color=#8a8494]Varnishes drop from Hearts of Rot (always on Harvest, sometimes on Restore). Slotted ones stay until you unslot them. Slots: %d of %d used (+1 per ring fully cleared, up to %d).[/color]" % [slots.size(), nslots, int(AtlasRules.varn_cfg().get("max_slots", 3))])
	var owned: Dictionary = st.get("varnish", {})
	if owned.is_empty():
		_row(varnish_box, "[color=#8a8494]You own no Varnish yet.[/color]")
	for v in AtlasRules.varn_cfg().get("list", []):
		var id := str(v.get("id", ""))
		if int(owned.get(id, 0)) <= 0:
			continue
		var on: bool = slots.has(id)
		var r := _row(varnish_box, "[color=%s]%s[/color] x%d%s\n[color=#8a8494]%s[/color]" % ["#e8d8a0" if on else "#c8b890", str(v.get("name", id)), int(owned[id]), "  [color=#80e080](slotted)[/color]" if on else "", str(v.get("desc", ""))])
		if on:
			r.add_child(UIKit.button("Unslot", func(): _act(AtlasRules.unslot_varnish(state(), id), "")))
		else:
			var b := UIKit.button("Slot", func(): _act(AtlasRules.slot_varnish(state(), id), ""))
			b.disabled = slots.size() >= nslots
			r.add_child(b)
