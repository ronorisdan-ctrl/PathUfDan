extends Node
## Godot 4.0: --headless --fixed-fps 60 --path . res://tests/corruption_system.tscn
const C = preload("res://scripts/core/corruption_system.gd")
const Character = preload("res://scripts/core/character_data.gd")
const Rules = preload("res://scripts/core/corruption_rules.gd")

class SequenceRng:
	extends RefCounted
	var values := []
	var calls := 0
	var upper := false
	func _init(v: Array = [], high: bool = false):
		values = v.duplicate()
		upper = high
	func randi_range(low: int, high: int) -> int:
		calls += 1
		var n: int = values.pop_front() if not values.is_empty() else high if upper else low
		assert(n >= low and n <= high, "Forced roll outside requested interval")
		return n

class DoubleRng:
	extends RefCounted
	var first := true
	var rng := RandomNumberGenerator.new()
	func _init():
		rng.seed = 49533
	func randi_range(low: int, high: int) -> int:
		if first:
			first = false
			assert(low == 0 and high == 9999)
			return 9600
		return rng.randi_range(low,high)

var passes := 0
var fails := 0

func check(ok: bool, label: String) -> void:
	if ok:
		passes += 1
	else:
		fails += 1
		push_error("FAIL " + label)

func fixture(base: String = "rusted_sword", rarity: String = "rare", level: int = 42):
	var ch = Character.new()
	ch.setup_new("warrior")
	ch.level = 60
	ch.inventory.fill(null)
	ch.materials = {"abyssal_brand": 5}
	ch.gold = 1000
	var it: Dictionary = Loot.roll_item_of(base, rarity, level)
	it["uid"] = ch.take_uid()
	ch.inventory[0] = it
	return ch

func _ready() -> void:
	if has_meta("no_auto"):
		return
	Game.testing = true
	await get_tree().process_frame
	check(Data.corruption_errors.is_empty(), "registry/startup slot coverage: " + str(Data.corruption_errors))
	foundation()
	print("Corruption foundation: %d passed, %d failed" % [passes, fails])
	if not "foundation" in OS.get_cmdline_user_args():
		modifiers()
		await load("res://tests/test_corruption_mechanics.gd").new().run(self)
		probabilities()
	print("CORRUPTION SYSTEM: %d passed, %d failed" % [passes, fails])
	get_tree().quit(1 if fails else 0)

func run(tester) -> void:
	set_meta("no_auto",true)
	tester.add_child(self)
	foundation()
	modifiers()
	await load("res://tests/test_corruption_mechanics.gd").new().run(self,tester.main)
	probabilities()
	tester.passes += passes
	tester.fails += fails
	tester.check(fails == 0,"corruption spec v1 acceptance: %d passed / %d failed" % [passes,fails])
	queue_free()

func foundation() -> void:
	for pair in [[0,"destroyed"], [1499,"destroyed"], [1500,"no_modifier"], [3999,"no_modifier"], [4000,"single"], [9599,"single"], [9600,"double"], [9999,"double"]]:
		for before in [0,37,99]:
			var ch = fixture()
			var it: Dictionary = ch.inventory[0]
			it["corruption"] = before
			it["sockets"] = 1
			it["gems"] = ["ruby:0"]
			var original := it.duplicate(true)
			var uid: int = it["uid"]
			var action: String = ch.new_corruption_action_id()
			var result: Dictionary = ch.corrupt_item(uid, action, SequenceRng.new([pair[0]]))
			check(result.get("outcome") == pair[1] and result["err"] == "", "C01-06 outcome boundary %s at %d%%" % [str(pair),before])
			check(ch.materials["abyssal_brand"] == 4 and ch.gold == 1000, "exact cost once")
			if pair[1] == "destroyed":
				check(ch.inventory[0] == null and ch.gems.get("ruby:0",0) == 1, "C12 destruction recovers gems once")
			else:
				var survivor: Dictionary = ch.inventory[0]
				check(survivor["uid"] == uid and survivor["corruption"] == 100 and survivor["gems"] == ["ruby:0"], "survivor identity/gems/seal")
				check(survivor["affixes"] == original["affixes"] and survivor["implicit"] == original["implicit"], "normal modifiers unchanged")
				var n := int(survivor.get("corrupted_prefix") != null) + int(survivor.get("corrupted_suffix") != null)
				check(n == {"no_modifier":0,"single":1,"double":2}[pair[1]], "dedicated side count")
				for op in Loot.craft_ops():
					var snap := survivor.duplicate(true)
					check(Loot.craft_check(op,survivor,0) != "", "C14 sealed check " + op)
					Loot.craft_apply(op,survivor,0)
					check(survivor == snap, "sealed direct apply " + op)
				var snap := survivor.duplicate(true)
				Loot.add_socket(survivor)
				Loot.roll_sockets(survivor)
				check(not Loot.add_random_affix(survivor), "sealed direct normal-affix insertion refused")
				check(ch.socket_gem(survivor,0,"ruby:0") != "" and ch.unsocket_gem(survivor,0) != "" and survivor == snap, "C14 Jeweller/direct socket seal")
			var snap := JSON.stringify(ch.to_dict())
			check(ch.corrupt_item(uid,action,SequenceRng.new())["err"] != "" and JSON.stringify(ch.to_dict()) == snap, "C09 duplicate ID/replay no mutation")
			var loaded = Character.new()
			loaded.from_dict(JSON.parse_string(snap))
			check(JSON.stringify(loaded.inventory) == JSON.stringify(ch.inventory) and loaded.corruption_actions == ch.corruption_actions, "C15 save/load identity/values/receipts")
			check(loaded.corrupt_item(uid,action,SequenceRng.new())["err"] != "", "C09 replay after reload refused")
	for side in [0,1]:
		var ch = fixture()
		var r: Dictionary = ch.corrupt_item(ch.inventory[0]["uid"],"side",SequenceRng.new([4000,side]))
		check(r["item"].get("corrupted_prefix" if side == 0 else "corrupted_suffix") != null, "C05 single side extreme")
	for mutation in ["no_brand", "equipped", "missing", "locked", "quest_only", "destroyed", "trade_locked", "transaction_locked", "sealed", "invalid", "nan", "negative", "unknown_base", "busy", "duplicate_uid"]:
		var ch = fixture()
		var it: Dictionary = ch.inventory[0]
		var uid: int = it["uid"]
		match mutation:
			"no_brand": ch.materials.clear()
			"equipped":
				ch.inventory[0] = null
				ch.equipment["main_hand"] = it
			"missing": ch.inventory[0] = null
			"sealed": it["corruption"] = 100
			"invalid": it["corruption"] = "bad"
			"nan": it["corruption"] = NAN
			"negative": it["corruption"] = -5
			"unknown_base": it["base"] = "missing"
			"busy": ch._corruption_busy = true
			"duplicate_uid": ch.inventory[1] = it.duplicate(true)
			_: it[mutation] = true
		var snap := JSON.stringify(ch.to_dict())
		var rng := SequenceRng.new()
		check(ch.corrupt_item(uid,"refused",rng)["err"] != "" and rng.calls == 0 and JSON.stringify(ch.to_dict()) == snap, "C07/08 invalid request atomic: " + mutation)
	var ch = fixture()
	var saved: Array = Data.corruption_affixes
	var snap := JSON.stringify(ch.to_dict())
	Data.corruption_affixes = []
	check(ch.corrupt_item(ch.inventory[0]["uid"],"bad_data",SequenceRng.new([0]))["err"] != "" and JSON.stringify(ch.to_dict()) == snap, "C10 empty data cannot destroy/charge")
	Data.corruption_affixes = saved
	var it: Dictionary = Loot.make_unique("widowmaker",42)
	it["uid"] = ch.take_uid()
	it["sockets"] = 1
	it["gems"] = ["ruby:0"]
	ch.inventory[0] = it
	var original := it.duplicate(true)
	var result: Dictionary = ch.corrupt_item(it["uid"],"legendary",SequenceRng.new([9600]))
	for key in original:
		if not key in ["corruption", "corrupted_prefix", "corrupted_suffix", "corruption_roll_version"]:
			check(result["item"][key] == original[key], "C11 retained Legendary " + key)
	var legacy = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/corruption_legacy.json"))
	var old = Character.new()
	old.from_dict(legacy)
	check(old.inventory[0]["corruption"] == 37 and old.inventory[0]["corrupted_prefix"] == null and old.inventory[0]["corruption_roll_version"] == 0, "C16 legacy defaults without reroll")
	check(old.inventory[1]["corruption"] == 100 and old.inventory[1]["gems"] == ["ruby:0"] and old.inventory[1]["legendary_effect"] == "worldsplitter", "C16 obsolete sealed Legendary retained")
	for op in Loot.craft_ops():
		check(Loot.craft_check(op,old.inventory[1],0) != "", "legacy 100 seal " + op)
	check(ch.equip_restriction(result["item"]) != "Corrupted", "C14 equip allowed")
	check(not Loot.salvage_yield(result["item"]).has("abyssal_brand"), "salvage never refunds brand")
	# Existing two-hand swap logic still removes an incompatible off-hand and adds no phantom slot.
	ch = fixture()
	for base in Data.item_base_list:
		if base.get("two_handed",false) and "melee_weapon" in base.get("tags",[]):
			var two: Dictionary = Loot.make_item(base["id"],"common",42)
			two["uid"] = ch.take_uid()
			ch.inventory[0] = two
			break
	for base in Data.item_base_list:
		if base.get("category") == "shield":
			ch.equipment["off_hand"] = Loot.make_item(base["id"],"common",42)
			ch.equipment["off_hand"]["uid"] = ch.take_uid()
			break
	var two_uid: int = ch.inventory[0]["uid"]
	check(ch.corrupt_item(two_uid,"two-hand",SequenceRng.new([9600]))["err"] == "" and ch.equip_from_bag(0) == "" and ch.equipment["off_hand"] == null and ch.equipment["main_hand"]["uid"] == two_uid,"C17 corrupted two-hand weapon respects existing off-hand restriction")
	var current = Character.new()
	current.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/corruption_current.json")))
	check(current.inventory[0]["corrupted_prefix"]["tier"] == 2 and current.inventory[0]["corrupted_suffix"]["value"] == 8 and current.inventory[0]["uid"] == 201,"current-save fixture loads both dedicated slots unchanged")
	current.stash[0] = current.inventory[0]
	current.inventory[0] = null
	var stashed = Character.new()
	stashed.from_dict(JSON.parse_string(JSON.stringify(current.to_dict())))
	check(stashed.stash[0]["corrupted_prefix"]["value"] == 12 and stashed.stash[0]["uid"] == 201,"personal stash preserves exact corrupted rolls and identity")
	current.inventory[0] = current.stash[0]
	current.stash[0] = null
	var saved_shared_path: String = SharedStash.path
	var saved_shared_slots: Array = SharedStash.slots
	var saved_shared_tabs: int = SharedStash.extra_tabs
	SharedStash.path = "res://tests/.corruption_shared_test.json"
	SharedStash.reset()
	check(SharedStash.deposit(current,0)["err"] == "","shared stash accepts sealed equipment")
	SharedStash.load_file()
	check(SharedStash.slots[0]["corrupted_prefix"]["value"] == 12 and SharedStash.slots[0]["corrupted_suffix"]["value"] == 8,"shared stash disk reload retains both implicit slots")
	check(SharedStash.withdraw(current,0) == "" and current.inventory[0]["corruption"] == 100 and current.inventory[0]["corrupted_prefix"]["value"] == 12,"shared withdrawal preserves seal/effects under existing per-character UID reassignment")
	DirAccess.remove_absolute(SharedStash.path)
	DirAccess.remove_absolute(SharedStash.path + ".bak")
	SharedStash.path = saved_shared_path
	SharedStash.slots = saved_shared_slots
	SharedStash.extra_tabs = saved_shared_tabs

func modifiers() -> void:
	var cfg: Dictionary = Data.corruption_cfg
	var registry: Array = Data.corruption_affixes
	var index := C.registry_index(registry)
	check(registry.size() == 82, "82 authoritative families")
	var phases := {2:0,3:0,4:0}
	var pools := {"weapon":0,"amulet":0,"equipment":0}
	for f in registry:
		phases[int(f["phase"])] += 1
		pools[f["pool"]] += 1
		if int(f["phase"]) == 4:
			var disabled := cfg.duplicate(true)
			disabled["features"][f["requires_feature"]] = false
			check(not C.enabled(f,disabled) and C.enabled(f,cfg), "M14 per-family tested feature gate: " + f["id"])
		if f["fixed_tier"]:
			var random := SequenceRng.new()
			var record := C.roll_affix(f,42,cfg,random)
			check(random.calls == 0 and record["tier"] == null and record["value"] == f["fixed_value"], "M06 fixed effect no tier/value RNG: " + f["id"])
		else:
			for band in f["tiers"]:
				for high in [false,true]:
					var tier_roll: int = {3:0,2:60,1:90}[int(band["tier"])]
					var value: int = int(band["max"] if high else band["min"])
					var record := C.roll_affix(f,42,cfg,SequenceRng.new([tier_roll,value]))
					check(record["tier"] == band["tier"] and record["value"] == value, "M05 inclusive band %s tier %d" % [f["id"],band["tier"]])
					for m in record["effects"]:
						check(m["value"] == value, "M13 shared compound roll")
		# Every delivered effect is attached through the same item-modifier/stat path.
		if int(f["phase"]) <= 3:
			var selected := ""
			for base in Data.item_base_list:
				var it := {"base":base["id"],"ilvl":42}
				if C.eligible(it,f["side"],cfg,registry).has(f):
					selected = base["id"]
					break
			check(selected != "", "live base exists for " + f["id"])
			var ch = fixture(selected,"common")
			ch.class_id = "mage" if "caster_weapon" in C.tags_for(ch.inventory[0],cfg) or "caster_offhand" in C.tags_for(ch.inventory[0],cfg) else "ranger" if "ranged_weapon" in C.tags_for(ch.inventory[0],cfg) or "quiver" in C.tags_for(ch.inventory[0],cfg) else "warrior"
			var it: Dictionary = ch.inventory[0]
			var record := C.roll_affix(f,42,cfg,SequenceRng.new())
			it["corrupted_" + f["side"]] = record
			it["corruption"] = 100
			var slot: String = "ring1" if it["slot"] == "ring" else it["slot"]
			ch.equipment[slot] = it
			ch.inventory[0] = null
			var with_stats = ch.build_stats([])
			var corrupted_mods := C.item_mods(it,cfg,registry)
			check(corrupted_mods.size() == f["effects"].size(), "all effects resolve: " + f["id"])
			for m in corrupted_mods:
				var source: Dictionary = with_stats.source_breakdown(m["stat"]).get(m["source"],{})
				check(is_equal_approx(float(source.get(m["type"],-999)),float(record["value"])), "source-tagged effective stat " + f["id"])
			ch.equipment[slot] = null
			var without = ch.build_stats([])
			for m in corrupted_mods:
				check(not without.source_breakdown(m["stat"]).has(m["source"]), "C18 unequip removes source " + f["id"])
			ch.equipment[slot] = it
			var again = ch.build_stats([])
			check(again.mods == with_stats.mods, "C18 re-equip no duplicate stats " + f["id"])
	check(phases == {2:62,3:6,4:14} and pools == {"weapon":27,"amulet":20,"equipment":35}, "exact phase/pool record counts")
	for level in [1,27,28,29,30,39,40,42]:
		for base in Data.item_base_list:
			var it := {"base":base["id"],"ilvl":level,"tags":["amulet","weapon"]}
			for side in ["prefix","suffix"]:
				var candidates := C.eligible(it,side,cfg,registry)
				check(not candidates.is_empty(), "M09 slot/level coverage")
				for f in candidates:
					check(int(f["min_item_level"]) <= level and C.enabled(f,cfg), "M01-04 min level/feature gate")
					check(f["pool"] == C.pool_for(it,cfg), "M07/08 exclusive runtime-base pool")
					var record := C.roll_affix(f,level,cfg,SequenceRng.new([],true))
					if not f["fixed_tier"]:
						check(record["tier"] == (3 if level < 28 else 2 if level < 40 else 1), "M01-04 tier level gating")
			check(not C.paired_prefixes(C.eligible(it,"prefix",cfg,registry),C.eligible(it,"suffix",cfg,registry),cfg).is_empty(), "M09 compatible double pair")
	for pair in [["cw_splintered_fate","cw_of_fracturing"],["cw_splintered_fate","cw_of_second_echo"],["ce_of_relentless","ce_grasping_shadows"]]:
		check(not C.compatible(index[pair[0]],index[pair[1]],cfg), "M11 forbidden projectile pair")
	check(C.compatible(index["cw_ruinous"],index["cw_of_frenzy"],cfg), "ordinary complementary double permitted")
	var random := RandomNumberGenerator.new()
	random.seed = 2112
	for base in Data.item_base_list:
		var it := {"base":base["id"],"ilvl":42}
		var p: Dictionary = C.plan(it,cfg,registry,SequenceRng.new([9600]))
		check(p["outcome"] == "double" and p["item"]["corrupted_prefix"] != null and p["item"]["corrupted_suffix"] != null, "M10 guaranteed real double per base")
	# A deliberately incompatible prefix is removed before category selection, never rerolled.
	var candidates := [index["cw_splintered_fate"], index["cw_ruinous"]]
	var suffixes := [index["cw_of_fracturing"]]
	check(C.paired_prefixes(candidates,suffixes,cfg) == [index["cw_ruinous"]], "M11 filter impossible prefix before draw")
	var bad_cfg := cfg.duplicate(true)
	bad_cfg["outcome_weights_basis_points"]["double"] = 0
	check(not C.validate(bad_cfg,registry).is_empty(), "invalid lottery fail closed")
	var bad_registry := registry.duplicate(true)
	bad_registry[0]["tiers"][0]["tier"] = 4
	check(not C.validate(cfg,bad_registry).is_empty(), "T4 registry rejected")
	bad_registry = registry.duplicate(true)
	bad_registry.append(registry[0])
	check(not C.validate(cfg,bad_registry).is_empty(), "duplicate registry ID rejected")
	for invalid in ["band","effects","tags","weight"]:
		bad_registry = registry.duplicate(true)
		match invalid:
			"band": bad_registry[0]["tiers"] = ["malformed"]
			"effects": bad_registry[0]["effects"] = "malformed"
			"tags": bad_registry[0]["eligible_any_tags"] = 37
			"weight": bad_registry[0]["family_weight"] = NAN
		check(not C.validate(cfg,bad_registry).is_empty(),"malformed registry fails closed without exception: " + invalid)
	for corruption in ["unknown", "wrong_side", "out_of_range", "injected_effect", "wrong_tags", "same_group"]:
		var it: Dictionary = Loot.make_item("rusted_sword","rare",42)
		var record := C.roll_affix(index["cw_ruinous"],42,cfg,SequenceRng.new())
		match corruption:
			"unknown": record["id"] = "no_such_modifier"
			"wrong_side": record = C.roll_affix(index["cw_of_frenzy"],42,cfg,SequenceRng.new())
			"out_of_range": record["value"] = 999999
			"injected_effect": record["effects"][0]["value"] = 999999
			"wrong_tags": record = C.roll_affix(index["cw_bonebound"],42,cfg,SequenceRng.new())
			"same_group":
				# An identical ID on the wrong side is rejected rather than becoming a normal affix.
				it["corrupted_suffix"] = record.duplicate(true)
		it["corrupted_prefix"] = record
		C.normalize_item(it,cfg,registry)
		check(it.has("corruption_invalid_prefix") or it.has("corruption_invalid_suffix"), "M20 malformed record quarantined: " + corruption)
		check(it["affixes"].is_empty() and it["corruption"] == 100, "quarantine preserves item/seal/normal slots")
	combat_stats()
	economy()

func combat_stats() -> void:
	var ch = fixture()
	ch.equipment["main_hand"] = ch.inventory[0]
	ch.inventory[0] = null
	ch.allocated.clear()
	ch.equipment["main_hand"]["affixes"] = []
	ch.recalc()
	var skill: Dictionary = Data.skills["cleave"]
	var before: Dictionary = Combat.player_packet(ch,skill)
	var index := C.registry_index(Data.corruption_affixes)
	ch.equipment["main_hand"]["corrupted_prefix"] = C.roll_affix(index["cw_ruinous"],42,Data.corruption_cfg,SequenceRng.new([90,16]))
	ch.recalc()
	var after: Dictionary = Combat.player_packet(ch,skill)
	var base_bucket: float = ch.stats.inc_sum(["damage","attack_damage","melee_damage","area_damage","physical_damage","one_handed_damage"])
	check(after["dmg"]["physical"][0] > before["dmg"]["physical"][0] and is_equal_approx(after["increased_by_type"]["physical"],base_bucket), "ordinary attack bonus reaches actual additive combat bucket")
	var atk_before: float = ch.final["attack_speed_mult"]
	ch.equipment["main_hand"]["corrupted_suffix"] = C.roll_affix(index["cw_of_frenzy"],42,Data.corruption_cfg,SequenceRng.new([90,8]))
	ch.recalc()
	check(is_equal_approx(ch.final["attack_speed_mult"] - atk_before,0.08), "attack speed reaches use-time multiplier")
	ch.equipment["main_hand"]["corrupted_suffix"] = C.roll_affix(index["cw_of_ruin"],42,Data.corruption_cfg,SequenceRng.new([90,15]))
	ch.recalc()
	check(is_equal_approx(Combat.player_packet(ch,skill)["crit_mult"] - before["crit_mult"],0.15), "crit multi is percentage points")
	ch.equipment["main_hand"]["corrupted_prefix"] = C.roll_affix(index["cw_executioners"],42,Data.corruption_cfg,SequenceRng.new([90,12]))
	ch.recalc()
	var pk: Dictionary = Combat.player_packet(ch,skill)
	var elite = load("res://scripts/entities/enemy.gd").new()
	elite.is_elite = true
	var bucket: float = 1.0 + pk["increased_by_type"]["physical"] / 100.0
	check(is_equal_approx(Combat.corruption_damage_range(pk,elite,"physical")[0]/pk["dmg"]["physical"][0],(bucket+0.12)/bucket) and pk["elite_inc"] == 0, "elite corruption is additive without changing historical elite bonus")
	elite.is_elite = false
	check(Combat.corruption_damage_range(pk,elite,"physical") == pk["dmg"]["physical"], "elite corruption inactive on normal enemies")
	elite.free()
	var sb = ch.stats
	for stat in ["block_chance","damage_reduction","res_fire","res_cold","res_lightning"]:
		sb.add(stat,"flat",999,"test")
	var final: Dictionary = ch.resolve(sb)
	check(final["block_chance"] == 75 and final["damage_reduction"] == 60 and final["res_fire"] == 75 and Combat.evade_chance(999999,42) == 0.6, "corruption preserves defence caps")
	# Compound rolls add their full amount to EACH named resistance.
	var amulet := ""
	for b in Data.item_base_list:
		if b["slot"] == "amulet":
			amulet = b["id"]
			break
	var it: Dictionary = Loot.make_item(amulet,"common",42)
	it["corrupted_prefix"] = C.roll_affix(index["ca_threefold"],42,Data.corruption_cfg,SequenceRng.new([90,5]))
	var mods := C.item_mods(it,Data.corruption_cfg,Data.corruption_affixes)
	check(mods.size() == 3 and mods[0]["value"] == 5 and mods[1]["value"] == 5 and mods[2]["value"] == 5, "Threefold gives +5 each, not divided")

func economy() -> void:
	var cfg: Dictionary = Data.corruption_cfg
	check(C.brand_chance(4,1,false,true,true,cfg) == 0 and C.brand_chance(1,1,false,false,true,cfg) == 0, "no guaranteed/low-tier brand source")
	check(is_equal_approx(C.brand_chance(5,1,false,true,true,cfg),0.1), "T5 boss single brand chance")
	check(is_equal_approx(C.brand_chance(6,1,false,true,true,cfg),0.15) and is_equal_approx(C.brand_chance(6,20,true,true,true,cfg),0.2), "T6/endless uses one capped boss chance")
	check(is_equal_approx(C.brand_chance(6,1,false,false,true,cfg),0.001), "endgame elite very rare chance")
	var saved_state: int = Loot.rng.state
	for i in 10000:
		check(Loot._roll_material() != "abyssal_brand", "routine crafting material pool excludes brand")
	Loot.rng.state = saved_state
	Loot.set_seed(391)
	seed(1421)
	var without: Array = Loot.roll_drops(42,1,false,true,"warrior",0)
	var loot_state: int = Loot.rng.state
	Loot.set_seed(391)
	seed(1421)
	var with_brand: Array = Loot.roll_drops(42,1,false,true,"warrior",0,{"tier":6,"depth":1})
	var filtered := []
	for drop in with_brand:
		if drop.get("id", "") != "abyssal_brand":
			filtered.append(drop)
	check(JSON.stringify(filtered) == JSON.stringify(without) and Loot.rng.state == loot_state, "brand draw leaves all ordinary drop rolls and Loot RNG state unchanged")

func probabilities() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 20261104
	var cfg: Dictionary = Data.corruption_cfg
	var counts := {"destroyed":0,"no_modifier":0,"single":0,"double":0}
	var sides := {"prefix":0,"suffix":0}
	var n := 1000000
	for i in n:
		var outcome := C.outcome_for_roll(random.randi_range(0,9999),cfg)
		counts[outcome] += 1
		if outcome == "single":
			sides[C.weighted_key(cfg["single_side_weights"],random)] += 1
	for key in counts:
		check(absf(float(counts[key])/n - float(cfg["outcome_weights_basis_points"][key])/10000) < 0.003, "million-trial outcome tolerance " + key)
	check(absf(float(sides["prefix"])/counts["single"] - 0.5) < 0.005, "million-trial single prefix/suffix 50/50")
	print("N=1000000 outcome counts: ",counts,"; single sides: ",sides)
	var f: Dictionary = Data.corruption_affixes[0]
	for level in [27,28,39,40,42]:
		var tiers := {3:0,2:0,1:0}
		for i in 100000:
			var record := C.roll_affix(f,level,cfg,random)
			tiers[int(record["tier"])] += 1
		var expected: Array = [1,0,0] if level < 28 else [2.0/3,1.0/3,0] if level < 40 else [0.6,0.3,0.1]
		for j in 3:
			check(absf(float(tiers[3-j])/100000 - expected[j]) < 0.01, "100k tier distribution level %d tier %d" % [level,3-j])
		print("N=100000 level ",level," tiers: ",tiers)
	var index := C.registry_index(Data.corruption_affixes)
	# Pure category sampler fixture includes all four categories without enabling any P4 gameplay.
	var pool := [index["cw_ruinous"],index["cw_grave_hewn"],index["cw_executioners"],index["cw_shepherds"],index["cw_war_saints"]]
	var cats := {"common":0,"specialized":0,"signature":0,"mythic":0}
	var family_counts := {}
	for i in 200000:
		var family := C.draw_family(pool,cfg,random)
		cats[family["rarity_class"]] += 1
		family_counts[family["id"]] = int(family_counts.get(family["id"],0)) + 1
	for cat in cats:
		check(absf(float(cats[cat])/200000 - float(cfg["rarity_category_weights"][cat])/10000) < (0.0015 if cat == "mythic" else 0.005), "200k conditional category frequency " + cat)
	check(absf(float(family_counts["cw_ruinous"])/cats["common"] - 0.5) < 0.01, "within-category equal family weights")
	pool[0] = pool[0].duplicate(true)
	pool[0]["family_weight"] = 300
	var selected := {"cw_ruinous":0,"cw_grave_hewn":0}
	for i in 100000:
		selected[C.draw_family(pool.slice(0,2),cfg,random)["id"]] += 1
	check(absf(float(selected["cw_ruinous"])/100000 - 0.75) < 0.01, "100k within-category unequal 3:1 family weights")
	print("N=200000 conditional rarity categories: ",cats)
	var double_rng := DoubleRng.new()
	var pairs := {"prefix_t1":0,"suffix_t1":0,"both_t1":0}
	var ordinary_pool := [index["cw_ruinous"],index["cw_of_frenzy"]]
	for i in 100000:
		double_rng.first = true
		var plan := C.plan({"base":"rusted_sword","ilvl":42},cfg,ordinary_pool,double_rng)
		var p1: bool = plan["item"]["corrupted_prefix"]["tier"] == 1
		var s1: bool = plan["item"]["corrupted_suffix"]["tier"] == 1
		pairs["prefix_t1"] += int(p1)
		pairs["suffix_t1"] += int(s1)
		pairs["both_t1"] += int(p1 and s1)
	check(absf(pairs["prefix_t1"]/100000.0-0.1)<0.01 and absf(pairs["suffix_t1"]/100000.0-0.1)<0.01 and absf(pairs["both_t1"]/100000.0-0.01)<0.0015,"100k real double plans have independent tiers, no second-affix boost")
	print("N=100000 ordinary double plans: ",pairs)
