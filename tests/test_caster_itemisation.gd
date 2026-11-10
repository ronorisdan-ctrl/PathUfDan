extends RefCounted
## Caster itemisation checks (docs/CASTER_ITEMISATION.md): flat added damage to spells,
## caster base implicits, +spell skill levels past the cap, glove cast speed / spell damage,
## spell elemental penetration. Called from tests/test_runner.gd; quick run on its own:
##   godot --headless --fixed-fps 60 --path . res://tests/caster_only.tscn

const TR = preload("res://scripts/core/training_rules.gd")

var T = null

func run(runner) -> void:
	T = runner
	T._log("--- caster itemisation")
	print("\n--- caster itemisation")
	test_data()
	test_rolls()
	test_spell_packet()
	test_skill_levels()
	test_penetration_rules()
	await test_penetration_enemy()
	Game.new_character("warrior")

# ------------------------------------------------------------------ data
func test_data() -> void:
	for id in ["searing", "frigid", "crackling"]:
		var a: Dictionary = Data.affixes.get(id, {})
		T.check(not a.is_empty() and a["kind"] == "prefix" and a["type"] == "flat", "caster: %s exists as a flat prefix" % id)
		T.check(a.get("slots", []) == ["caster_weapon", "caster_offhand"], "caster: %s rolls only on caster weapons and off-hands" % id, str(a.get("slots", [])))
		T.check(Data.stat_info.has(a.get("stat", "")), "caster: %s stat has a name" % id)
	T.check(Data.affixes.get("sorcerous", {}).get("slots", []) == ["gloves"] and Data.affixes["sorcerous"]["stat"] == "spell_damage", "caster: % spell damage rolls on gloves")
	T.check(Data.affixes.get("of_haste", {}).get("slots", []).has("gloves"), "caster: cast speed rolls on gloves")
	T.check(Data.affixes.get("of_sorcery", {}).get("stat", "") == "spell_skill_level", "caster: +spell skill level suffix exists")
	T.check(Data.affixes.get("of_penetration", {}).get("stat", "") == "spell_penetration", "caster: spell penetration suffix exists")
	for s in ["added_spell", "added_spell_fire", "added_spell_cold", "added_spell_lightning", "spell_skill_level", "spell_penetration"]:
		T.check(Data.stat_info.has(s), "caster: stat %s is named" % s)
	var want := {"apprentice_wand_t2": 2, "apprentice_wand_t3": 11, "bone_wand_t2": 3, "bone_wand_t3": 12, "oak_staff_t2": 4, "oak_staff_t3": 18}
	for bid in want:
		var v := 0.0
		for m in Data.item_bases.get(bid, {}).get("implicit", []):
			if m["stat"] == "added_spell":
				v = float(m["value"])
		T.check(v == want[bid], "caster: %s has +%d Added Spell Damage" % [bid, want[bid]], str(v))
	for bid in ["apprentice_wand", "bone_wand", "oak_staff"]:
		var has := false
		for m in Data.item_bases.get(bid, {}).get("implicit", []):
			has = has or m["stat"] == "added_spell"
		T.check(not has, "caster: tier 1 %s has no added spell damage" % bid)
	var cc: Dictionary = Data.loot.get("caster", {})
	T.check(float(cc.get("added_ref", 0)) > 0 and int(cc.get("overcap", -1)) >= 0, "caster: loot.json caster config present", str(cc))
	T.check(Loot.affix_text({"id": "searing", "value": 31}) == "Adds 31 Fire Damage to Spells", "caster: affix text", Loot.affix_text({"id": "searing", "value": 31}))
	T.check(Loot.mod_text({"stat": "added_spell", "type": "flat", "value": 18}) == "+18 Added Spell Damage", "caster: implicit text", Loot.mod_text({"stat": "added_spell", "type": "flat", "value": 18}))

# ------------------------------------------------------------------ rolls stay on legal slots
func test_rolls() -> void:
	var spell_flat := ["searing", "frigid", "crackling"]
	var bad := []
	var seen := {}
	for i in 3000:
		var bid: String = ["oak_staff_t3", "bone_wand_t3", "cracked_focus_t3", "tome_t3", "greataxe_t3", "longbow_t3"][i % 6]
		var it: Dictionary = Loot.roll_item_of(bid, "epic", 50)
		var caster: bool = it.get("tags", []).has("caster_weapon") or it.get("tags", []).has("caster_offhand")
		for a in it["affixes"]:
			seen[a["id"]] = true
			if a["id"] in spell_flat and not caster:
				bad.append("%s on %s" % [a["id"], bid])
	for i in 2000:
		var g: Dictionary = Loot.roll_item_of("leather_gloves" if Data.item_bases.has("leather_gloves") else _a_gloves_base(), "epic", 50)
		for a in g["affixes"]:
			seen["gloves:" + a["id"]] = true
			if a["id"] in spell_flat:
				bad.append("%s on gloves" % a["id"])
	T.check(bad.is_empty(), "caster: flat spell damage never rolls off caster weapons/off-hands", str(bad.slice(0, 5)))
	T.check(seen.has("searing") and seen.has("frigid") and seen.has("crackling") and seen.has("of_sorcery") and seen.has("of_penetration"), "caster: new caster affixes roll", str(seen.keys()))
	T.check(seen.has("gloves:sorcerous") and seen.has("gloves:of_haste"), "caster: gloves roll spell damage and cast speed")

func _a_gloves_base(cls: String = "") -> String:
	for b in Data.item_base_list:
		if b.get("slot", "") == "gloves" and (cls == "" or Loot.base_usable_by(b, cls)) and int(b.get("req_level", 1)) <= 10:
			return b["id"]
	return ""

# ------------------------------------------------------------------ spell packet
func _mage(lvl: int):
	Game.new_character("mage")
	var ch = Game.ch
	ch.level = lvl
	ch.refresh_unlocks(false)
	for s in ch.equipment.keys():
		ch.equipment[s] = null
	ch.recalc()
	return ch

func _avg(ch, sid: String) -> float:
	return Combat.packet_average(Combat.player_packet(ch, ch.resolved_skill(sid)))

func _dmg(ch, sid: String) -> Dictionary:
	return Combat.player_packet(ch, ch.resolved_skill(sid))["dmg"]

func test_spell_packet() -> void:
	var ch = _mage(50)
	var a0 := _avg(ch, "fireball")
	var wand: Dictionary = Loot.make_item("apprentice_wand", "rare", 50)
	ch.equipment["main_hand"] = wand
	ch.recalc()
	var a1 := _avg(ch, "fireball")
	var w3: Dictionary = Loot.make_item("bone_wand_t3", "rare", 50)
	ch.equipment["main_hand"] = w3
	ch.recalc()
	var a3 := _avg(ch, "fireball")
	T.check(a3 > a1 * 1.3, "caster: a Runeforged wand raises spell hits (implicit added spell damage)", "%.1f -> %.1f (no wand %.1f)" % [a1, a3, a0])
	T.check(_dmg(ch, "fireball").keys() == ["fire"], "caster: the implicit adds the spell's own damage type", str(_dmg(ch, "fireball").keys()))
	var b0 := _avg(ch, "fireball")
	w3["affixes"].append({"id": "crackling", "kind": "prefix", "stat": "added_spell_lightning", "type": "flat", "value": 40.0, "tier": 6, "tier_ilvl": 42})
	ch.recalc()
	var d := _dmg(ch, "fireball")
	T.check(d.has("lightning") and d.has("fire") and _avg(ch, "fireball") > b0, "caster: Adds Lightning Damage to Spells adds lightning to a fire spell", str(d.keys()))
	# the added amount: value x 0.7..1.3 x effectiveness, before increases
	var sk: Dictionary = ch.resolved_skill("fireball")
	var eff: float = Combat.spell_added_eff(sk, sk["base_damage"], ch.skill_level("fireball"))
	var pre: Array = Combat.player_packet(ch, sk)["pre_increased"]["lightning"]
	T.check(absf(pre[0] - 40.0 * 0.7 * eff) < 0.01 and absf(pre[1] - 40.0 * 1.3 * eff) < 0.01, "caster: added spell damage = value x 0.7..1.3 x effectiveness", "%s eff %.3f" % [str(pre), eff])
	# effectiveness follows the spell's base damage, clamped
	var cc: Dictionary = Data.loot["caster"]
	var fb: Dictionary = Data.skills["fireball"]
	var exp_fb: float = clampf((fb["base_damage"][0] + fb["base_damage"][1]) * 0.5 / float(cc["added_ref"]), float(cc["eff_min"]), float(cc["eff_max"]))
	T.check(absf(Combat.spell_added_eff(fb, fb["base_damage"], 1) - exp_fb) < 0.001, "caster: effectiveness = base average / added_ref at skill level 1")
	T.check(absf(Combat.spell_added_eff(fb, fb["base_damage"], 11) - exp_fb * 1.4) < 0.001, "caster: effectiveness +4% per skill level")
	var spk: Dictionary = Data.skills["spark"]
	T.check(absf(Combat.spell_added_eff(spk, spk["base_damage"], 1) - float(cc["eff_min"])) < 0.001, "caster: weak spells are clamped to eff_min")
	var ov: Dictionary = fb.duplicate(true)
	ov["added_eff"] = 0.5
	T.check(absf(Combat.spell_added_eff(ov, ov["base_damage"], 1) - 0.5) < 0.001, "caster: added_eff overrides the derived effectiveness")
	# attacks are untouched by spell stats, spells untouched by attack stats
	Game.new_character("warrior")
	var wc = Game.ch
	wc.level = 30
	wc.refresh_unlocks(false)
	wc.recalc()
	var c0 := _avg(wc, "cleave")
	var gl: Dictionary = Loot.make_item(_a_gloves_base("warrior"), "rare", 30)
	gl["affixes"].append({"id": "searing", "kind": "prefix", "stat": "added_spell_fire", "type": "flat", "value": 30.0, "tier": 5, "tier_ilvl": 32})
	wc.equipment["gloves"] = gl
	wc.recalc()
	T.check(absf(_avg(wc, "cleave") - c0) < 0.001, "caster: added spell damage does not reach attacks")
	ch = _mage(30)
	var f0 := _avg(ch, "fireball")
	var g2: Dictionary = Loot.make_item(_a_gloves_base("mage"), "rare", 30)
	g2["affixes"].append({"id": "emberforged", "kind": "prefix", "stat": "added_fire", "type": "flat", "value": 30.0, "tier": 5, "tier_ilvl": 32})
	ch.equipment["gloves"] = g2
	ch.recalc()
	T.check(absf(_avg(ch, "fireball") - f0) < 0.001, "caster: added attack damage does not reach spells")

# ------------------------------------------------------------------ skill levels past the cap
func test_skill_levels() -> void:
	var ch = _mage(50)
	var cap: int = ch.MAX_SKILL_LEVEL
	var over := int(Data.loot["caster"]["overcap"])
	T.check(ch.skill_level("fireball") == cap, "caster: fireball is at the natural cap at level 50", str(ch.skill_level("fireball")))
	var am: Dictionary = Loot.make_item(_base_for("amulet"), "rare", 50)
	am["affixes"].append({"id": "of_sorcery", "kind": "suffix", "stat": "spell_skill_level", "type": "flat", "value": 2.0, "tier": 2, "tier_ilvl": 42})
	ch.equipment["amulet"] = am
	ch.recalc()
	T.check(ch.skill_level("fireball") == cap + 2, "caster: +2 spell skill levels go past the cap", str(ch.skill_level("fireball")))
	var a_spell := _avg(ch, "fireball")
	am["affixes"][-1]["value"] = 0.0
	ch.recalc()
	T.check(a_spell > _avg(ch, "fireball"), "caster: levels past the cap raise spell damage")
	am["affixes"][-1]["value"] = 50.0
	ch.recalc()
	T.check(ch.skill_level("fireball") == cap + over, "caster: item levels stop at cap + overcap", str(ch.skill_level("fireball")))
	am["affixes"][-1]["value"] = 2.0
	ch.recalc()
	var nonspell := ""
	for s in ch.unlocked_skills:
		if not Data.skills[s].get("tags", []).has("spell"):
			nonspell = s
			break
	if nonspell != "":
		T.check(ch.skill_level(nonspell) <= cap, "caster: spell levels do not reach non-spell skills (%s)" % nonspell, str(ch.skill_level(nonspell)))
	var low = _mage(12)
	var n0: int = low.skill_level("fireball")
	var am2: Dictionary = Loot.make_item(_base_for("amulet"), "rare", 12)
	am2["affixes"].append({"id": "of_sorcery", "kind": "suffix", "stat": "spell_skill_level", "type": "flat", "value": 1.0, "tier": 1, "tier_ilvl": 24})
	low.equipment["amulet"] = am2
	low.recalc()
	T.check(low.skill_level("fireball") == n0 + 1, "caster: +1 spell level below the cap", "%d -> %d" % [n0, low.skill_level("fireball")])

func _base_for(slot: String) -> String:
	for b in Data.item_base_list:
		if b.get("slot", "") == slot:
			return b["id"]
	return ""

# ------------------------------------------------------------------ penetration
func test_penetration_rules() -> void:
	var rolled := {"fire": 100.0, "void": 100.0, "physical": 100.0}
	var res := {"fire": 70.0, "void": 70.0}
	var red := Callable(Combat, "armour_reduction")
	var m0: float = TR.mitigate(rolled, 0.0, res, false, 1.0, red)
	var m1: float = TR.mitigate(rolled, 0.0, res, false, 1.0, red, 15.0)
	T.check(absf((m1 - m0) - 15.0) < 0.01, "caster: 15% penetration turns 70% fire resistance into 55% (void and physical unchanged)", "%.2f -> %.2f" % [m0, m1])
	var cap: float = TR.mitigate({"lightning": 100.0}, 0.0, {"lightning": 100.0}, false, 1.0, red, 15.0)
	T.check(absf(cap - 15.0) < 0.01, "caster: penetration applies before the 90% resistance clamp", str(cap))
	var ch = _mage(50)
	var am: Dictionary = Loot.make_item(_base_for("amulet"), "rare", 50)
	am["affixes"].append({"id": "of_penetration", "kind": "suffix", "stat": "spell_penetration", "type": "flat", "value": 12.0, "tier": 3, "tier_ilvl": 32})
	ch.equipment["amulet"] = am
	ch.recalc()
	T.check(float(Combat.player_packet(ch, ch.resolved_skill("fireball")).get("ele_pen", 0)) == 12.0, "caster: spells carry their penetration")
	Game.new_character("warrior")
	var wc = Game.ch
	wc.level = 50
	wc.refresh_unlocks(false)
	wc.equipment["amulet"] = am.duplicate(true)
	wc.recalc()
	T.check(float(Combat.player_packet(wc, wc.resolved_skill("cleave")).get("ele_pen", 0)) == 0.0, "caster: attacks carry no spell penetration")

func test_penetration_enemy() -> void:
	Game.new_character("mage")
	T.main.enter_dungeon("forgotten_depths", 4242)
	await T.frames(3)
	var lv = Game.level
	var e = null
	for x in lv.enemies:
		if is_instance_valid(x) and x.alive and not x.is_in_group("training_dummy"):
			e = x
			break
	T.check(e != null, "caster: an enemy for the penetration test")
	if e == null:
		return
	e.resist = {"fire": 60.0}
	if "shield" in e:
		e.shield = 0.0
	e.max_life = 1.0e9
	e.life = 1.0e9
	var p0 := {"faction": "player", "flags": {}}
	var p1 := {"faction": "player", "flags": {}, "ele_pen": 20.0}
	var d0: float = e.receive_hit({"fire": 100.0}, p0, null, false)
	var d1: float = e.receive_hit({"fire": 100.0}, p1, null, false)
	T.check(d1 > d0 * 1.45 and d1 < d0 * 1.55, "caster: an enemy with 60% fire resistance takes 50% more from 20% penetration", "%.2f -> %.2f" % [d0, d1])
	T.main.go_hub(false)
	await T.frames(2)
