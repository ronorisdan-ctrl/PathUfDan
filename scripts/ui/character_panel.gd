extends "res://scripts/ui/base_panel.gd"
## Character sheet: attributes, offence (per equipped skill), defence,
## resistances, minions. Hover any row to see where the value comes from.

var scroll: ScrollContainer
var list: VBoxContainer
var header: RichTextLabel

const SOURCE_NAMES := {"base": "Class base", "level": "Level growth", "equipment": "Equipment", "passive": "Passive tree", "attribute": "Attributes", "buff": "Temporary buffs", "specialisation": "Specialisation"}

func _init() -> void:
	place = "left"
	build("Character", Vector2(400, 620))
	header = UIKit.rich("", 380)
	body.add_child(header)
	scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(380, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	Events.stats_changed.connect(_on_stats)

func _on_stats() -> void:
	if visible:
		refresh()

func refresh() -> void:
	var ch = Game.ch
	if ch == null:
		return
	var cd: Dictionary = ch.class_def()
	var spn: String = Data.specs.get(ch.spec_id, {}).get("name", "")
	header.text = "[font_size=16][color=#e8c890]%s[/color][/font_size]  Level %d %s%s\n[color=#8a8494]%s[/color]" % [ch.char_name, ch.level, cd.get("name", ""), (" - " + spn) if spn != "" else "", cd.get("identity", "")]
	for c in list.get_children():
		c.queue_free()
	var f: Dictionary = ch.final
	_section("Attributes")
	for a in Data.attributes.get("order", []):
		_row(Data.attributes["names"][a], UIKit.fmt(f[a]), a, Data.attributes.get("descriptions", {}).get(a, ""))
	_section("Offence")
	for i in ch.loadout.size():
		var sid: String = ch.loadout[i]
		if sid == "" or not Data.skills.has(sid):
			continue
		var sk: Dictionary = ch.resolved_skill(sid)
		if not (sk.has("weapon_eff") or sk.has("base_damage")):
			continue
		var pk: Dictionary = Combat.player_packet(ch, sk)
		var avg: float = Combat.packet_average(pk)
		var ut: float = _use_time(ch, sk)
		var dps := avg / maxf(ut, 0.05)
		_row(sk["name"], "%d avg  (%.0f/s)" % [int(avg), dps], "", "Average hit including crits: %d\nUse time: %.2fs\nCrit chance: %.1f%%  Multiplier: x%.2f\nSkill level %d" % [int(avg), ut, pk["crit_chance"], pk["crit_mult"], ch.skill_level(sid)])
	_row("Weapon damage", "%d-%d" % [int(f["weapon_min"]), int(f["weapon_max"])], "", "Base physical damage of your main hand (after upgrades)")
	_row("Attacks per second", "%.2f" % (f["weapon_aps"] * f["attack_speed_mult"]), "attack_speed", "")
	_row("Cast speed", "+%d%%" % int(round((f["cast_speed_mult"] - 1.0) * 100)), "cast_speed", "")
	_row("Critical chance (increased)", "+%d%%" % int(ch.stats.inc("crit_chance")), "crit_chance", "")
	_row("Critical multiplier", "x%.2f" % (1.5 + ch.stats.value("crit_multi") / 100.0), "crit_multi", "")
	for st in ["damage", "physical_damage", "fire_damage", "cold_damage", "lightning_damage", "elemental_damage", "melee_damage", "projectile_damage", "spell_damage", "attack_damage", "area_damage", "dot_damage"]:
		var v: float = ch.stats.inc(st)
		var m: float = ch.stats.more(st)
		if absf(v) > 0.01 or absf(m - 1.0) > 0.001:
			var txt := "+%d%%" % int(v)
			if absf(m - 1.0) > 0.001:
				txt += "  x%.2f" % m
			_row(Data.stat_name(st), txt, st, "")
	for st2 in ["added_physical", "added_fire", "added_cold", "added_lightning", "bleed_chance", "ignite_chance", "status_chance", "projectile_count", "pierce", "chain", "damage_vs_elite"]:
		var v2: float = ch.stats.value(st2)
		if st2 == "damage_vs_elite":
			v2 = ch.stats.inc(st2)
		if absf(v2) > 0.01:
			_row(Data.stat_name(st2), UIKit.fmt(v2, 0), st2, "")
	_section("Defence")
	_row("Maximum Life", UIKit.fmt(f["max_life"]), "max_life", "")
	_row("Life Regeneration", "%.1f /s" % f["life_regen"], "life_regen", "")
	_row("Maximum Mana", UIKit.fmt(f["max_mana"]), "max_mana", "")
	_row("Mana Regeneration", "%.1f /s" % f["mana_regen"], "mana_regen", "")
	_row("Armour", UIKit.fmt(f["armour"]), "armour", "Reduces physical hits: armour / (armour + 12 x hit). A %d hit is reduced by %d%%." % [10, int(Combat.armour_reduction(f["armour"], 10) * 100)])
	_row("Evasion", UIKit.fmt(f["evasion"]), "evasion", "Chance to evade attacks from a level %d monster: %d%%" % [ch.level, int(Combat.evade_chance(f["evasion"], ch.level) * 100)])
	_row("Block Chance", "%d%%" % int(f["block_chance"]), "block_chance", "Blocked attacks deal no damage. Spells are blocked at half this chance. Cap 75%.")
	_row("Damage Reduction", "%d%%" % int(f["damage_reduction"]), "damage_reduction", "Applied after armour and resistances. Cap 60% (75% with temporary effects).")
	_row("Movement Speed", UIKit.fmt(f["move_speed"]), "move_speed", "")
	_section("Resistances (cap 75%)")
	for r in [["fire", "Fire"], ["cold", "Ice"], ["lightning", "Lightning"], ["arcane", "Arcane"], ["void", "Void"]]:
		_row(r[1] + " Resistance", "%d%%" % int(f["res_" + r[0]]), "res_" + r[0], "")
	_section("Minions, Traps & Turrets")
	_row("Minion damage", "+%d%%" % int(ch.stats.inc("minion_damage")), "minion_damage", "")
	_row("Minion life", "+%d%%" % int(ch.stats.inc("minion_life")), "minion_life", "")
	_row("Trap damage", "+%d%%" % int(ch.stats.inc("trap_damage")), "trap_damage", "")
	_row("Turret damage", "+%d%%" % int(ch.stats.inc("turret_damage")), "turret_damage", "")
	_section("Special")
	var flags: Array = ch.stats.flags.keys()
	if flags.is_empty():
		_row("No keystones or legendary effects", "", "", "")
	for fl in flags:
		_row(_flag_name(fl), "active", "", _flag_desc(fl))

func _use_time(ch, sk: Dictionary) -> float:
	match sk.get("kind", "spell"):
		"attack":
			return (1.0 / maxf(0.2, ch.final["weapon_aps"])) * float(sk.get("speed_mult", 1.0)) / ch.final["attack_speed_mult"]
		_:
			return float(sk.get("use_time", 0.6)) / ch.final["cast_speed_mult"]

func _flag_name(fl: String) -> String:
	for n in Data.passive_list:
		if n.get("flags", []).has(fl):
			return n["name"]
	for u in Data.unique_list:
		if u.get("effect", "") == fl:
			return u["name"]
	return fl.capitalize()

func _flag_desc(fl: String) -> String:
	for n in Data.passive_list:
		if n.get("flags", []).has(fl):
			return n.get("desc", "")
	for u in Data.unique_list:
		if u.get("effect", "") == fl:
			return u.get("effect_text", "")
	return ""

func _section(t: String) -> void:
	var l := UIKit.label(t, 15, UIKit.GOLD)
	list.add_child(l)

func _row(title: String, value: String, stat: String, extra: String) -> void:
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_STOP
	var a := UIKit.label(title, 13)
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var b := UIKit.label(value, 13, Color("#ffffff"))
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(a)
	h.add_child(b)
	h.mouse_entered.connect(func(): ui.show_tooltip(_breakdown(title, stat, extra)))
	h.mouse_exited.connect(func(): ui.hide_tooltip())
	list.add_child(h)

func _breakdown(title: String, stat: String, extra: String) -> String:
	var lines := ["[color=#c8a060]%s[/color]" % title]
	if extra != "":
		lines.append(extra)
	if stat != "":
		var src: Dictionary = Game.ch.stats.source_breakdown(stat)
		if src.is_empty():
			lines.append("[color=#8a8494]No modifiers[/color]")
		for k in src:
			var s: Dictionary = src[k]
			var parts := []
			if absf(s["flat"]) > 0.001:
				parts.append("%s%s flat" % ["+" if s["flat"] >= 0 else "", UIKit.fmt(s["flat"], 1 if absf(s["flat"]) < 10 else 0)])
			if absf(s["inc"]) > 0.001:
				parts.append("%s%d%% increased" % ["+" if s["inc"] >= 0 else "", int(s["inc"])])
			if absf(s["more"]) > 0.001:
				parts.append("%s%d%% more" % ["+" if s["more"] >= 0 else "", int(s["more"])])
			if parts.size() > 0:
				lines.append("%s: %s" % [SOURCE_NAMES.get(k, k), ", ".join(parts)])
		lines.append("[color=#6a6474]Final = (base + flat) x (1 + increased) x more[/color]")
	return "\n".join(lines)
