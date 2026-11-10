extends "res://scripts/ui/base_panel.gd"
## The Atlas of Ruin (Endgame Phase 1A): hex map, hex details and the enter button.
## Opened from the Dungeon Gate once Malgrath (Tier 5) is defeated.

const Chrome = preload("res://scripts/ui/components/station_chrome.gd")
const AtlasRules = preload("res://scripts/core/atlas_rules.gd")
const AtlasMap = preload("res://scripts/ui/components/atlas_map.gd")

var map
var detail: RichTextLabel
var progress_label: Label
var enter_btn: Button
var back_btn: Button
var easel_btn: Button
var summon_btn: Button
var chosen := Vector2i(1, 0)

func _init() -> void:
	place = "center"
	build("The Atlas of Ruin", Vector2(860, 560))
	Chrome.apply(self)
	var h := HBoxContainer.new()
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_theme_constant_override("separation", 12)
	body.add_child(h)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.3
	h.add_child(left)
	map = AtlasMap.new()
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map.hex_clicked.connect(select)
	left.add_child(map)
	progress_label = UIKit.label("", 13, UIKit.MUTED)
	left.add_child(progress_label)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var sc := Chrome.reading_scroll(v, 300)
	detail = UIKit.rich()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(detail)
	var hb := HBoxContainer.new()
	enter_btn = UIKit.button("Enter Zone", _enter)
	enter_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(enter_btn)
	easel_btn = UIKit.button("Easel", func(): ui.toggle("easel"))
	easel_btn.tooltip_text = "Craft and slot Pigments, slot Varnishes"
	hb.add_child(easel_btn)
	summon_btn = UIKit.button("Summon Warden", _summon)
	summon_btn.tooltip_text = "Spend nothing now: the next run of this region fights the layer's Warden. Shards are used only when you win."
	hb.add_child(summon_btn)
	back_btn = UIKit.button("Dungeon Gate", _back)
	hb.add_child(back_btn)
	v.add_child(hb)

func reposition() -> void:
	Chrome.place_panel(self, Vector2(960, 640))

func state() -> Dictionary:
	if Game.ch == null:
		return {}
	return AtlasRules.ensure(Game.ch) if AtlasRules.unlocked(Game.ch) else {}

func select(h: Vector2i) -> void:
	chosen = h
	refresh()

func refresh() -> void:
	var ch = Game.ch
	if ch == null:
		return
	if not AtlasRules.unlocked(ch):
		map.set_state({}, chosen)
		detail.text = "[color=#ff8080]Locked - %s[/color]" % str(AtlasRules.cfg().get("unlock_text", ""))
		progress_label.text = ""
		enter_btn.disabled = true
		easel_btn.disabled = true
		summon_btn.disabled = true
		return
	easel_btn.disabled = false
	var st := state()
	if not AtlasRules.in_atlas(chosen):
		chosen = Vector2i(1, 0)
	map.set_state(st, chosen)
	var sm := AtlasRules.summary(st)
	progress_label.text = "Cleared %d of %d regions   Revealed %d   Rot %d / %d   Next spread: %d front%s\nGreen dot: cleared   Diamond: vantage   Blotches + number: Rot   Red heart: Heart boss   Dashed: next spread   Gold frame: restored   Square: zone mechanic   Dots: Wager / Vaults   Crown: Warden summoned" % [sm["cleared"], sm["total"], sm["revealed"], AtlasRules.rot_total(st), AtlasRules.rot_cap(st), AtlasRules.fronts_next(st), "" if AtlasRules.fronts_next(st) == 1 else "s"]
	progress_label.text = _warden_summary(st) + "\n" + progress_label.text
	var lines := []
	var ring := AtlasRules.ring_of(chosen)
	if ring == 0:
		lines = ["[font_size=18][color=#e8c890]Ashfall Sanctuary[/color][/font_size]", "", "The hub sits at the heart of the painting. Each ring outward is an older, deeper layer."]
		enter_btn.disabled = true
	elif not AtlasRules.is_revealed(st, chosen):
		lines = ["[color=#8a8494]Unexplored %s region. Clear a neighbouring region to reveal it.[/color]" % str(AtlasRules.ring_cfg(ring).get("layer", ""))]
		enter_btn.disabled = true
	else:
		var info := AtlasRules.hex_info(int(st["seed"]), chosen)
		var rot := AtlasRules.rot_of(st, chosen)
		var d := AtlasRules.apply_rot(AtlasRules.zone_def(int(st["seed"]), chosen), rot, int(st["seed"]), chosen, st)
		var n := AtlasRules.clears(st, chosen)
		var mods := AtlasRules.run_mods(int(st["seed"]), chosen, n, d)
		lines = [
			"[font_size=18][color=#e8c890]%s[/color][/font_size]" % info["name"],
			"[color=#8a8494]Ring %d (%s layer)   Monster level %d[/color]" % [ring, info["layer"], info["level"]],
			"", str(Data.zones[info["zone"]].get("desc", "")).trim_prefix("Endgame biome: "), "",
			"[color=#c8a060]Monsters:[/color] %d%% more life, %d%% more damage, +%d%% resistances" % [int(round((float(d.get("life_mult", 1)) - 1) * 100)), int(round((float(d.get("damage_mult", 1)) - 1) * 100)), int(d.get("resist_bonus", 0))],
			"[color=#c8a060]Boss:[/color] %s" % (str(AtlasRules.warden_def(Data.enemies.get(str(AtlasRules.warden_cfg(ring).get("boss", "")), {}), ring).get("name", "")) + " (summoned)" if AtlasRules.warden_at(st, chosen) > 0 else info["boss_name"]),
			"[color=#c8a060]Rewards:[/color] +%d%% item rarity" % int(d.get("rarity_bonus", 0)),
		]
		lines.append_array(_warden_lines(st, chosen, ring))
		lines.append_array(_rot_lines(st, chosen, rot, d))
		lines.append_array(_mechanic_lines(st, chosen, ring, rot))
		if info["vantage"]:
			lines.append("[color=#ffe8a0]Vantage:[/color] clearing this region reveals everything within 2 regions.")
		if mods.is_empty():
			lines.append("[color=#c8a060]Modifiers:[/color] none")
		else:
			var total := 0
			lines.append("[color=#c8a060]Modifiers for your next run:[/color]")
			for id in mods:
				var m: Dictionary = Data.dungeon_mods.get(id, {})
				total += int(m.get("reward", 0))
				lines.append("  [color=#ff9070]%s[/color] - %s  [color=#80e080](+%d%% rewards)[/color]" % [m.get("name", id), m.get("desc", ""), int(m.get("reward", 0))])
			lines.append("  [color=#80e080]Total: +%d%% item quantity, rarity and experience[/color]" % total)
		lines.append("[color=#c8a060]Cleared:[/color] %d time%s" % [n, "" if n == 1 else "s"])
		if ch.level < int(info["level"]) - 4:
			lines.append("[color=#ff8080]Warning: you are well below this region's monster level.[/color]")
		enter_btn.disabled = false
	detail.text = "\n".join(lines)
	_refresh_summon(st)

# ------------------------------------------------------------------ Layer Wardens (Phase 2A)
func _warden_summary(st: Dictionary) -> String:
	var wc := AtlasRules.ward_cfg()
	var parts := []
	for r in AtlasRules.warden_rings():
		var w := AtlasRules.warden_cfg(r)
		parts.append("%s %d/%d" % [str(w.get("shard", "Shard")).replace(" Shard", ""), AtlasRules.shards(st, r), AtlasRules.summon_cost()])
	return "Ground Shards: %s   Ground Pigments: %d of %d layers (%d open the pinnacle)" % [", ".join(parts), AtlasRules.ground_kinds(st), int(wc.get("layers_total", 6)), int(wc.get("pinnacle_need", 4))]

func _warden_lines(st: Dictionary, h: Vector2i, ring: int) -> Array:
	var out := []
	var w := AtlasRules.warden_cfg(ring)
	if w.is_empty():
		return out
	var bname := str(Data.enemies.get(str(w["boss"]), {}).get("name", "")).split(",")[0]
	var title := "%s, %s" % [bname, str(w.get("title", ""))]
	if AtlasRules.warden_at(st, h) > 0:
		out.append("[color=#ffe070]Warden summoned:[/color] %s replaces this region's boss on your next run (no Heart of Rot). %s" % [title, str(w.get("desc", ""))])
		out.append("[color=#8a8494]Win to spend %d %ss and claim a chance at %s (always on the first kill, +1 passive point). Losing costs no shards.[/color]" % [AtlasRules.summon_cost(), str(w.get("shard", "")), str(w.get("ground", ""))])
	else:
		var where := AtlasRules.summoned_hex(st, ring)
		var kills := AtlasRules.warden_kills(st, ring)
		out.append("[color=#c8a060]Layer Warden:[/color] %s - %d/%d %ss%s%s" % [title, AtlasRules.shards(st, ring), AtlasRules.summon_cost(), str(w.get("shard", "")),
			("; summoned at %s" % where) if where != "" else "", ("; defeated %d time%s" % [kills, "" if kills == 1 else "s"]) if kills > 0 else ""])
	return out

func _refresh_summon(st: Dictionary) -> void:
	var ring := AtlasRules.ring_of(chosen)
	var why := AtlasRules.summon_refusal(st, chosen) if ring > 0 else "Pick a region"
	summon_btn.disabled = why != ""
	summon_btn.text = "Move Warden here" if why == "" and AtlasRules.summoned_hex(st, ring) != "" else "Summon Warden"
	summon_btn.tooltip_text = why if why != "" else "The next run of this region fights the layer's Warden. Shards are used only when you win."

func _summon() -> void:
	if Game.ch == null:
		return
	var st := state()
	if AtlasRules.summon(st, chosen):
		var w := AtlasRules.warden_cfg(AtlasRules.ring_of(chosen))
		ui.toast("%s awaits in %s" % [str(w.get("title", "The Warden")).capitalize(), AtlasRules.key(chosen)], Color("#ffe070"))
		Game.save_game()
	refresh()

## Zone mechanics of the next run: slotted Pigments (Phase 1E) plus the natural roll (Phase 1D).
func _mechanic_lines(st: Dictionary, h: Vector2i, ring: int, rot: int) -> Array:
	var out := []
	var pigs := AtlasRules.run_pigments(st, h)
	var mechs := AtlasRules.run_mechanics(st, h, pigs)
	var pm := AtlasRules.pigment_mods(pigs)
	var slots := AtlasRules.pigment_slots(st, h)
	if mechs.is_empty():
		out.append("[color=#8a8494]Mechanic: none on the next run (%d%% chance per run).[/color]" % int(round(float(AtlasRules.mech_cfg().get("natural_chance", 0.3)) * float(AtlasRules.varnish_fx(st)["natural_mult"]) * 100)))
	for id in mechs:
		var mech := AtlasRules.mechanic_info(id)
		var extra := ""
		if id == "unfinished":
			var nc := AtlasRules.sketch_colours(ring, rot, AtlasRules.mech_tuning("unfinished", pm.get("unfinished", [])))
			extra = " Sketches here need %d colour%s." % [nc, "" if nc == 1 else "s"]
		var src := " (Pigment)" if pm.has(id) else ""
		out.append("[color=%s]Mechanic: %s%s[/color] - %s%s" % [str(mech.get("color", "#ffffff")), str(mech.get("name", "")), src, str(mech.get("desc", "")), extra])
	if pigs.is_empty():
		out.append("[color=#8a8494]Pigments: %d slot%s here; none slotted at the Easel.[/color]" % [slots, "" if slots == 1 else "s"])
	else:
		var names := []
		for p in pigs:
			var m := AtlasRules.pigment_mod(str(p["id"]), str(p["mod"]))
			names.append("%s [color=#8a8494](%s)[/color]" % [AtlasRules.pigment_label(p), str(m.get("desc", ""))])
		out.append("[color=#e0c890]Pigments (%d slot%s, -1 charge per run, -%d more on death):[/color] %s  [color=#80e080](+%d%% rewards)[/color]" % [slots, "" if slots == 1 else "s", int(AtlasRules.pig_cfg().get("death_charges", 1)), "; ".join(names), int(float(AtlasRules.pig_cfg().get("reward", 10)) * pigs.size())])
	var vs: Array = st.get("varnish_slots", [])
	if not vs.is_empty():
		var vn := []
		for id in vs:
			vn.append(str(AtlasRules.varnish_info(str(id)).get("name", id)))
		out.append("[color=#e8d8a0]Varnish:[/color] %s" % ", ".join(vn))
	return out

func _rot_lines(st: Dictionary, h: Vector2i, rot: int, d: Dictionary) -> Array:
	var out := []
	if AtlasRules.is_restored(st, h):
		out.append("[color=#e8c060]Restored:[/color] the Rot can never return here.")
	elif AtlasRules.ring_of(h) < int(AtlasRules.rot_cfg().get("min_ring", 2)):
		out.append("[color=#8a8494]The Varnish layer is safe from the Rot.[/color]")
	if rot > 0:
		var lv := AtlasRules.rot_level(rot)
		out.append("[color=#b0e050]Rot %d:[/color] %d%% bigger packs, %d%% more monster life, %d%% more damage, +%d%% quantity, rarity and experience%s" % [rot,
			int(round((float(lv.get("density", 1)) - 1) * 100)), int(round((float(lv.get("life_mult", 1)) - 1) * 100)),
			int(round((float(lv.get("damage_mult", 1)) - 1) * 100)), int(lv.get("reward", 0)),
			", elites +%d modifier" % int(lv.get("elite_mods", 0)) if int(lv.get("elite_mods", 0)) > 0 else ""])
		if float(lv.get("heal", 1.0)) < 1.0 or float(lv.get("attack_speed", 1.0)) > 1.0:
			var sap := "[color=#b0e050]The Rot saps you:[/color] %d%% less life recovery, monsters attack %d%% faster" % [int(round((1.0 - float(lv.get("heal", 1.0))) * 100)), int(round((float(lv.get("attack_speed", 1.0)) - 1.0) * 100))]
			if float(lv.get("move_speed", 1.0)) > 1.0:
				sap += ", move %d%% faster" % int(round((float(lv.get("move_speed", 1.0)) - 1.0) * 100))
			if float(lv.get("proj_speed", 1.0)) > 1.0:
				sap += ", their projectiles fly %d%% faster" % int(round((float(lv.get("proj_speed", 1.0)) - 1.0) * 100))
			out.append(sap)
		if d.get("heart", false):
			var names := []
			for m in AtlasRules.heart_mutations(int(st["seed"]), h, str(d.get("boss", "")), int(lv.get("mutations", 1))):
				names.append("%s (%s)" % [m.get("name", ""), m.get("desc", "")])
			out.append("[color=#b0e050]Heart of Rot:[/color] the boss is mutated - %s. Kill it to Restore the region or Harvest the Heart." % "; ".join(names))
		elif rot < AtlasRules.heart_at_for(st):
			out.append("[color=#8a8494]At Rot %d the boss becomes a Heart of Rot.[/color]" % AtlasRules.heart_at_for(st))
	var fc := AtlasRules.forecast(st).count(AtlasRules.key(h))
	if fc > 0:
		out.append("[color=#9ab84a]The next completion spreads Rot here (+%d).[/color]" % fc)
	if not AtlasRules.is_restored(st, h) and AtlasRules.ring_of(h) >= int(AtlasRules.rot_cfg().get("min_ring", 2)):
		out.append("[color=#8a8494]Dying here adds +%d Rot.[/color]" % (int(AtlasRules.rot_cfg().get("death_rot", 1)) + int(AtlasRules.varnish_fx(st)["death_rot"])))
	return out

func _enter() -> void:
	if Game.ch == null or not AtlasRules.can_enter(state(), chosen):
		return
	ui.close_all()
	Game.main.enter_atlas(chosen)

func _back() -> void:
	ui.toggle("dungeon")
