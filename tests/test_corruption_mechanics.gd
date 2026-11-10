extends RefCounted
## Gameplay acceptance for P3 and each individually gated P4 family.
const C = preload("res://scripts/core/corruption_system.gd")
const Effects = preload("res://scripts/core/corruption_effects.gd")
const Character = preload("res://scripts/core/character_data.gd")
const Exec = preload("res://scripts/combat/skill_exec.gd")
var t
var main
var p
var ch
var index := {}
var exec = Exec.new()

func check(ok: bool, label: String) -> void:
	t.check(ok,label)

func reset(cls: String) -> void:
	p.clear_summons()
	ch.class_id = cls
	ch.level = 42
	ch.allocated.clear()
	ch.spec_nodes.clear()
	ch.active_buffs.clear()
	p.buffs.clear()
	ch.corruption_cooldowns.clear()
	for slot in ch.equipment:
		ch.equipment[slot] = null
	ch.recalc()
	p.life = p.max_life
	p.mana = ch.final["max_mana"]
	p.statuses.clear()
	p.invuln_t = 0
	p.dodge_t = 0
	p.dodge_cd = 0
	p.dash_t = 0
	p.alive = true
	p.input_enabled = true
	ch.refresh_unlocks(false)

func equip(id: String) -> Dictionary:
	var f: Dictionary = index[id]
	for base in Data.item_base_list:
		var it: Dictionary = Loot.make_item(base["id"],"common",42)
		if Loot.base_usable_by(base,ch.class_id) and C.eligible(it,f["side"],Data.corruption_cfg,Data.corruption_affixes).has(f):
			it["uid"] = ch.take_uid()
			it["corruption"] = 100
			it["corruption_roll_version"] = 1
			it["corrupted_" + f["side"]] = C.roll_affix(f,42,Data.corruption_cfg,t.SequenceRng.new([],true))
			var slot: String = "ring1" if it["slot"] == "ring" else it["slot"]
			ch.equipment[slot] = it
			ch.recalc()
			check(true,"mechanic fixture " + id)
			return it
	check(false,"no valid mechanic fixture " + id)
	return {}

func clear_projectiles() -> void:
	for node in p.level.projectile_layer.get_children():
		p.level.projectile_layer.remove_child(node)
		node.queue_free()

func run(tester, existing_main = null) -> void:
	t = tester
	var saved_cfg: Dictionary = Data.corruption_cfg
	var cfg := saved_cfg.duplicate(true)
	for f in Data.corruption_affixes:
		if int(f["phase"]) == 4:
			cfg["features"][f["requires_feature"]] = true
			if not f["requires_feature"] in cfg["implemented_features"]:
				cfg["implemented_features"].append(f["requires_feature"])
	Data.corruption_cfg = cfg
	check(C.validate(cfg,Data.corruption_affixes).is_empty(),"P4 enabled registry validates supported typed operations")
	index = C.registry_index(Data.corruption_affixes)
	main = existing_main
	var owns_main: bool = main == null
	if owns_main:
		main = load("res://scripts/main.gd").new()
		t.add_child(main)
		await t.get_tree().process_frame
	Game.new_character("mage")
	main.start_game()
	await t.get_tree().process_frame
	await t.get_tree().process_frame
	p = Game.level.player
	ch = Game.ch
	Game.training_in_tests = true
	Game.level.training_spawn()
	var dummy = Game.level.training_dummies[0]
	p.set_physics_process(false)
	signatures(dummy)
	skill_levels()
	projectiles()
	conditionals(dummy)
	resources()
	mitigation()
	traps()
	persistence()
	balance_matrix(dummy)
	await user_interface()
	Data.corruption_cfg = saved_cfg
	Game.training_in_tests = false
	if owns_main:
		main.queue_free()
		await t.get_tree().process_frame

func signatures(dummy) -> void:
	for id in ["cw_shepherds","ca_soul_shepherd","ce_deathless"]:
		reset("mage")
		equip(id)
		var sk: Dictionary = ch.resolved_skill("summon_skeletons")
		for i in int(sk.get("max",3)) + 2:
			exec._summon(p,sk)
		check(p.minions.size() == int(sk.get("max",3)) + 1,"P3 active minion capacity: " + id)
	reset("ranger")
	equip("ca_master_constructs")
	var sk: Dictionary = ch.resolved_skill("ballista_turret")
	for i in int(sk.get("max",2)) + 2:
		exec._deploy(p,sk,p.global_position)
	check(p.deployables.size() == int(sk.get("max",2)) + 1,"P3 active turret capacity")
	reset("ranger")
	equip("cw_of_fracturing")
	clear_projectiles()
	exec._projectiles(p,ch.resolved_skill("quick_shot"),p.global_position,Vector2.RIGHT,Color.WHITE)
	check(p.level.projectile_layer.get_child(0).pierce == 1,"P3 actual projectile gains pierce")
	reset("warrior")
	equip("cw_of_reclamation")
	var pk: Dictionary = Combat.player_packet(ch,ch.resolved_skill("cleave"))
	pk["crit_chance"] = 0
	pk["dmg"] = {"physical":[10,10],"fire":[10,10],"cold":[10,10]}
	pk["status"] = []
	p.life = p.max_life - 20
	var life_before: float = p.life
	Combat.deal(pk,p,dummy)
	check(is_equal_approx(p.life-life_before,3),"P3 life on hit pays once for three damage components")
	pk["dmg"] = {"physical":[0,0]}
	life_before = p.life
	Combat.deal(pk,p,dummy)
	check(p.life == life_before,"life on hit ignores zero-damage hits")

func skill_levels() -> void:
	reset("warrior")
	ch.level = 10
	ch.recalc()
	var before: int = ch.skill_level("cleave")
	equip("cw_war_saints")
	check(ch.skill_level("cleave") == before+1 and Effects.skill_levels(ch.stats,Data.skills["firebolt"]) == 0,"War-Saint only active melee skills")
	var boosted: float = Combat.packet_average(Combat.player_packet(ch,ch.resolved_skill("cleave")))
	ch.equipment["main_hand"]["corrupted_prefix"] = null
	ch.recalc()
	check(boosted > Combat.packet_average(Combat.player_packet(ch,ch.resolved_skill("cleave"))),"tagged melee level increases actual damage")
	reset("mage")
	ch.level = 10
	ch.recalc()
	before = ch.skill_level("firebolt")
	var summons_before: int = ch.skill_level("summon_skeletons")
	equip("cw_apostates")
	check(ch.skill_level("firebolt") == before+1 and ch.skill_level("summon_skeletons") == summons_before,"Apostate only tagged active spells, not summons")
	equip("ca_forbidden_knowledge")
	check(ch.skill_level("firebolt") == before+2 and ch.skill_level("summon_skeletons") == summons_before+1,"Forbidden Knowledge stacks for active spells/summons")
	ch.stats.add("skill_level","flat",1,"existing charm/Legendary")
	check(ch.skill_level("firebolt") == before+3,"existing global skill-level source stacks")
	ch.level = 60
	ch.recalc()
	check(ch.skill_level("firebolt") == Character.MAX_SKILL_LEVEL,"corruption respects existing skill-level hard cap")

func projectiles() -> void:
	reset("ranger")
	equip("cw_splintered_fate")
	equip("ce_of_relentless")
	var sk: Dictionary = ch.resolved_skill("quick_shot")
	var base: int = int(sk.get("count",1)) + int(ch.final.get("projectile_count",0))
	check(exec.proj_count(p,sk) == base+2,"bow plus quiver gives +2 projectiles")
	ch.stats.add_flag("volley_fire")
	check(exec.proj_count(p,sk) == base+4 and exec.proj_pierce(p,sk) == int(sk.get("pierce",0)),"Volley Fire reads actual shot count; corruption cannot claim its single-shot pierce too")
	ch.stats.flags.erase("volley_fire")
	ch.stats.add_mod({"op":"tagged_projectile_count:weapon_attack","value":1},"future corruption source")
	check(exec.proj_count(p,sk) == base+2 and "1 suppressed" in Effects.projectile_summary(ch.stats),"M12 third corruption projectile suppressed, stored sources retained")
	ch.stats.add("projectile_count","flat",4,"non-corruption projectiles")
	ch.final = ch.resolve(ch.stats)
	check(exec.proj_count(p,sk) == base+6,"non-corruption projectiles remain outside +2 cap")
	for id in ["firebolt","ballista_turret","explosive_mine","rain_of_arrows"]:
		var other: Dictionary = Data.skills[id]
		check(Effects.projectiles(ch,other) == 0,"projectile filter excludes " + id)
	var orbit := sk.duplicate(true)
	orbit["behavior"] = "nova"
	check(Effects.projectiles(ch,orbit) == 0,"orbit/nova effects cannot receive extra shots")
	clear_projectiles()
	exec._projectiles(p,sk,p.global_position,Vector2.RIGHT,Color.WHITE)
	check(p.level.projectile_layer.get_child_count() == base+6,"actual simultaneous projectile count respects cap")
	var saved_roll: Dictionary = ch.equipment["off_hand"]["corrupted_suffix"].duplicate(true)
	check(saved_roll["value"] == 1,"suppression never mutates stored quiver roll")
	# Test Firearm alias and existing rune/non-corruption count without a bow-only bonus.
	for b in Data.item_base_list:
		if "firearm" in b.get("tags",[]):
			var weapon: Dictionary = Loot.make_item(b["id"],"common",42)
			weapon["corrupted_prefix"] = C.roll_affix(index["cw_splintered_fate"],42,Data.corruption_cfg,t.SequenceRng.new())
			ch.equipment["main_hand"] = weapon
			ch.equipment["off_hand"] = null
			break
	ch.recalc()
	check(Effects.projectiles(ch,Data.skills["quickdraw"]) == 1,"firearm gets weapon projectile source")
	var rune_tested := false
	for rune in Data.skill_rune_list:
		var adds_count := false
		for mod in rune.get("mods",[]):
			adds_count = adds_count or mod[0] == "count"
		if adds_count and ch.rune_fits(rune["id"],"quickdraw") == "":
			ch.skill_runes["quickdraw"] = [rune["id"]]
			var resolved: Dictionary = ch.resolved_skill("quickdraw")
			check(exec.proj_count(p,resolved) == int(resolved.get("count",1)) + ch.final.get("projectile_count",0) + 1,"rune projectile count stacks once")
			rune_tested = true
	check(rune_tested,"projectile skill-rune fixture exists")
	reset("ranger")
	equip("ce_grasping_shadows")
	check(exec.proj_pierce(p,Data.skills["quick_shot"]) == 1 and exec.proj_pierce(p,Data.skills["firebolt"]) == 0,"tagged pierce attacks only")
	reset("mage")
	equip("cw_of_second_echo")
	clear_projectiles()
	exec._projectiles(p,ch.resolved_skill("firebolt"),p.global_position,Vector2.RIGHT,Color.WHITE)
	check(p.level.projectile_layer.get_child(0).chain == 1 and Effects.chains(ch.stats,Data.skills["chain_lightning"]) == 1,"Second Echo reaches projectiles and chaining spells")
	check(Effects.chains(ch.stats,Data.skills["lightning_trap"]) == 0 and Effects.chains(ch.stats,Data.skills["tesla_turret"]) == 0,"Second Echo does not duplicate deployable chains")

func conditionals(dummy) -> void:
	reset("mage")
	equip("ca_of_final_blow")
	var pk: Dictionary = Combat.player_packet(ch,ch.resolved_skill("firebolt"))
	dummy.life = dummy.max_life * 0.35
	check(Combat.corruption_damage_range(pk,dummy,"fire") == pk["dmg"]["fire"],"Final Blow strictly excludes exactly 35% life")
	dummy.life = dummy.max_life * 0.349
	var increased: float = float(pk["increased_by_type"]["fire"])
	var expect: float = pk["pre_increased"]["fire"][0] * (1.0 + (increased+13)/100.0)
	check(is_equal_approx(Combat.corruption_damage_range(pk,dummy,"fire")[0],expect),"Final Blow adds to increased bucket at combat time")
	dummy.life = dummy.max_life
	check(Combat.corruption_damage_range(pk,dummy,"fire") == pk["dmg"]["fire"],"Final Blow clears when target recovers")
	reset("mage")
	equip("ce_of_deathless")
	var def: Dictionary = Data.summons["skeleton_warrior"]
	var high: Dictionary = Combat.minion_packet(ch,def,10,0.35)
	var low: Dictionary = Combat.minion_packet(ch,def,10,0.349)
	var bucket: float = 1.0 + ch.stats.inc("minion_damage") / 100.0
	check(is_equal_approx(low["dmg"]["physical"][0]/high["dmg"]["physical"][0],(bucket+0.15)/bucket),"Deathless live minion damage strictly below 35%")
	ch.equipment["helmet"] = null
	ch.recalc()
	check(Combat.minion_packet(ch,def,10,0.1)["dmg"] == high["dmg"],"conditional minion effect removed immediately on unequip")

func resources() -> void:
	reset("mage")
	equip("ca_of_stolen_moments")
	var enemy = load("res://scripts/entities/enemy.gd").new()
	enemy.is_elite = true
	p.mana = 0
	p.on_kill(enemy,p)
	var granted: float = ch.final["max_mana"] * 0.03
	check(is_equal_approx(p.mana,granted),"credited elite kill restores 3% Mana")
	p.on_kill(enemy,p)
	check(is_equal_approx(p.mana,granted),"duplicate elite kill pays once")
	enemy.free()
	enemy = load("res://scripts/entities/enemy.gd").new()
	enemy.is_boss = true
	p.mana = ch.final["max_mana"]-1
	p.on_kill(enemy,p)
	check(p.mana == ch.final["max_mana"],"boss counted by existing elite classifier; Mana clamps to missing")
	enemy.free()
	enemy = load("res://scripts/entities/enemy.gd").new()
	enemy.is_elite = true
	p.mana = 0
	p.on_kill(enemy,null)
	check(p.mana == 0,"uncredited kill grants no corruption Mana")
	enemy.free()
	reset("mage")
	equip("ce_of_second_wind")
	p.mana = 0
	p.dodge_cd = 0
	p.dodge_t = 0
	p.dash_t = 0
	p.start_dodge()
	check(is_equal_approx(p.mana,ch.final["max_mana"]*0.10) and ch.corruption_cooldowns.get("dodge_mana") == 8.0,"dodge restores 10% and starts game-time ICD")
	ch.tick_corruption_cooldowns(7.9)
	p.dodge_cd = 0
	p.dodge_t = 0
	p.mana = 0
	p.start_dodge()
	check(p.mana == 0,"dodge ICD refuses early proc")
	var loaded = Character.new()
	loaded.from_dict(JSON.parse_string(JSON.stringify(ch.to_dict())))
	check(is_equal_approx(loaded.corruption_cooldowns.get("dodge_mana",0),0.1),"dodge ICD survives save/reload")
	ch.tick_corruption_cooldowns(0.11)
	p.dodge_cd = 0
	p.dodge_t = 0
	p.start_dodge()
	check(p.mana > 0,"dodge proc returns after eight game-time seconds")
	ch.corruption_cooldowns.clear()
	p.dodge_cd = 0
	p.dodge_t = 0
	p.mana = 0
	p.statuses["stun"] = {"t":2.0,"dur":2.0}
	p.start_dodge()
	check(p.mana == 0,"stunned dodge never grants corruption Mana")
	p.statuses.clear()
	p.input_enabled = false
	p.dodge_cd = 0
	p.dodge_t = 0
	p.start_dodge()
	check(p.mana == 0,"disabled input never grants corruption Mana")

func mitigation() -> void:
	reset("warrior")
	equip("ce_sovereigns")
	for r in ["fire","cold","lightning","arcane","void"]:
		ch.stats.add("res_" + r,"flat",100,"test resistance")
	ch.final = ch.resolve(ch.stats)
	check(ch.final["res_fire"] == 76 and ch.final["res_cold"] == 76 and ch.final["res_lightning"] == 76 and ch.final["res_arcane"] == 75 and Combat.RES_CAP == 75,"Sovereign derived elemental caps only; global cap unchanged")
	ch.final["block_chance"] = 0
	ch.final["damage_reduction"] = 0
	var hit: float = p.receive_hit({"fire":100},{"is_attack":false},null,false)
	check(is_equal_approx(hit,24) and is_equal_approx(p.dot_resist("fire"),0.24),"raised resistance cap reaches actual hits and DoT")
	ch.stats.add_mod({"op":"maximum_elemental_resistance","value":999},"future source")
	check(ch.resolve(ch.stats)["res_cap_fire"] == 78,"absolute maximum resistance safety cap")
	ch.stats.add("res_fire","flat",-150,"debuff")
	check(ch.resolve(ch.stats)["res_fire"] == -50,"max resistance never grants missing resistance or cancels debuff")
	reset("warrior")
	equip("ce_bastions")
	ch.final["armour"] = 0
	ch.final["block_chance"] = 0
	hit = p.receive_hit({"physical":100},{"is_attack":false},null,false)
	check(is_equal_approx(hit,98) and p.dot_resist("physical") == 1,"Bastion mitigates hits only")
	p.statuses.clear()
	ch.final["damage_reduction"] = 59
	hit = p.receive_hit({"physical":100},{"is_attack":false},null,false)
	check(is_equal_approx(hit,40),"Bastion contribution clamps at 60% global base DR")

func traps() -> void:
	reset("ranger")
	equip("ce_of_endless_preparation")
	var sk: Dictionary = ch.resolved_skill("explosive_mine")
	for i in int(sk.get("max",2)) + 2:
		exec._deploy(p,sk,p.global_position)
	check(p.deployables.size() == int(sk.get("max",2))+1,"Endless Preparation raises enforced per-type trap cap")
	ch.equipment["belt"] = null
	ch.recalc()
	exec._deploy(p,sk,p.global_position)
	check(p.deployables.size() == int(sk.get("max",2)),"removing trap-limit gear restores capacity on next deployment")

func user_interface() -> void:
	reset("ranger")
	equip("cw_splintered_fate")
	equip("ce_of_relentless")
	var tooltip: String = Loot.tooltip(ch.equipment["main_hand"],ch)
	check("Mythic — fixed" in tooltip and "CORRUPTED IMPLICITS" in tooltip and "limit +2" in tooltip and "FINAL" in tooltip,"Mythic fixed and projectile cap visible in real tooltip")
	var ui = main.ui
	ui.open_station("blacksmith")
	var bs = ui.panels["blacksmith"]
	var it: Dictionary = Loot.make_item("rusted_sword","rare",42)
	it["uid"] = ch.take_uid()
	ch.inventory[0] = it
	ch.materials["abyssal_brand"] = 3
	bs.select(it)
	bs.op = "corrupt"
	bs.refresh()
	var rng_before: int = bs.corr_rng.state
	bs.refresh()
	Loot.tooltip(it,ch)
	check(bs.corr_rng.state == rng_before,"preview/tooltip consumes no corruption RNG")
	bs._craft()
	check(ui.confirm.visible and "15%" in ui.confirm_text.text and "25%" in ui.confirm_text.text and "56%" in ui.confirm_text.text and "4%" in ui.confirm_text.text and "Irreversible" in ui.confirm_text.text,"Blacksmith warns exact consequences before action")
	var action_before: int = ch.corruption_action_serial
	bs._craft()
	check(ch.corruption_action_serial == action_before,"duplicate click cannot dispatch another confirmation")
	ui._on_cancel()
	check(ch.materials["abyssal_brand"] == 3 and ch.inventory[0]["corruption_roll_version"] == 0,"cancel has no cost/mutation")
	# Consume the same real confirmation callback twice: service receipts/seal permit only once.
	bs._craft()
	ui._on_confirm()
	ui._on_confirm()
	check(ch.materials["abyssal_brand"] == 2 and not bs.corruption_result.text.is_empty(),"real confirm commits once and reveals result")
	ui.close("blacksmith")
	await t.get_tree().process_frame

func balance_matrix(dummy) -> void:
	var rows := []
	var cases: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/corruption_benchmarks.json"))
	dummy.set_physics_process(false)
	for case in cases:
		reset(case["class"])
		var weapon: Dictionary = equip(case["prefix"]).duplicate(true)
		weapon["corrupted_prefix"] = null
		var base_dps := 0.0
		var previous_dps := 0.0
		for tier in [0,3,2,1]:
			reset(case["class"])
			var it := weapon.duplicate(true)
			if tier > 0:
				var roll: int = {3:0,2:60,1:90}[tier]
				for side in ["prefix","suffix"]:
					if case.get(side) != null:
						var f: Dictionary = index[case[side]]
						var max_value := 0
						for band in f["tiers"]:
							if int(band["tier"]) == tier:
								max_value = int(band["max"])
						it["corrupted_" + side] = C.roll_affix(f,42,Data.corruption_cfg,t.SequenceRng.new([roll,max_value]))
			ch.equipment["main_hand"] = it
			ch.recalc()
			var sk: Dictionary = ch.resolved_skill(case["skill"])
			var interval := 0.6
			var units := 1
			var packet := {}
			if case["mode"] == "minion":
				var def: Dictionary = Data.summons[sk.get("minion","skeleton_warrior")]
				interval = float(def.get("attack_time",1.0)) / (1.0 + ch.stats.inc("minion_speed")/100.0)
				units = int(sk.get("max",3)) + int(ch.final.get("minion_limit",0))
				packet = Combat.minion_packet(ch,def,ch.skill_level(sk["id"]))
				packet["src_skill"] = sk["id"]
			elif case["mode"] == "turret":
				var turret = load("res://scripts/entities/turret.gd").new()
				turret.setup(p,sk)
				interval = turret.fire_interval
				units = int(sk.get("max",2)) + int(ch.final.get("turret_limit",0))
				turret.free()
				packet = Combat.player_packet(ch,sk)
			else:
				interval = (1.0/ch.final["weapon_aps"]) * float(sk.get("speed_mult",1)) / ch.final["attack_speed_mult"] if case["mode"] == "attack" else float(sk.get("use_time",0.6)) / ch.final["cast_speed_mult"]
				packet = Combat.player_packet(ch,sk)
			Combat.rng.seed = 28177
			TrainingLog.reset_settings()
			TrainingLog.begin(1)
			dummy.statuses.clear()
			var next_hit := 0.0
			var started := Time.get_ticks_usec()
			for frame in 600:
				var now: float = frame / 60.0
				if now + 0.00001 >= next_hit:
					next_hit += interval
					Combat.cast_serial += 1
					packet["cast"] = Combat.cast_serial
					for unit in units:
						Combat.deal(packet,p,dummy)
				dummy.tick_statuses(1.0/60.0)
				TrainingLog.tick(1.0/60.0)
			var elapsed_ms: float = (Time.get_ticks_usec()-started)/1000.0
			var events: Array = TrainingLog.run["events"]
			var damage: float = TrainingLog.Rules.total_damage(events)
			var hits := 0
			for event in events:
				if event.get("status_id","") == "":
					hits += 1
			var dps: float = damage / 10.0
			if tier == 0:
				base_dps = dps
			check(dps >= previous_dps and hits > 0,"Training Grounds monotonic tier gain: %s T%d" % [case["name"],tier])
			previous_dps = dps
			rows.append({"archetype":case["name"],"tier":"baseline" if tier == 0 else "T%d" % tier,"dps":dps,"hits":hits,"delta_dps_pct":(dps/base_dps-1)*100,"use_or_fire_seconds":interval,"cast_speed_multiplier":ch.final["cast_speed_mult"],"target_10000_life_seconds_proxy":10000.0/maxf(0.0001,dps),"max_life":ch.final["max_life"],"armour":ch.final["armour"],"block_chance":ch.final["block_chance"],"simulation_cpu_ms":elapsed_ms})
	var out := FileAccess.open("res://docs/corruption_training_matrix.json",FileAccess.WRITE)
	out.store_string(JSON.stringify({"level":42,"duration_seconds":10,"seed":28177,"notes":"Matched common gear/passives/runes, maximum roll of each tier; real Combat.deal and TrainingLog/status paths with scripted attack cadence and predeployed unit counts. No resource starvation or movement. Target-clear column is a 10,000-life DPS proxy, not a measured dungeon clear. Survivability stats should remain unchanged for these offensive families.","rows":rows},"\t"))
	out.close()
	dummy.set_physics_process(true)
	TrainingLog.discard()
	print("Training Grounds: 5 archetypes x baseline/T3/T2/T1 report generated")

func persistence() -> void:
	reset("ranger")
	var saved_dir: String = Game.save_dir
	var saved_slot: int = Game.current_slot
	var saved_testing: bool = Game.testing
	# Invalid slot forces a persistence failure without touching any user save file.
	Game.current_slot = 0
	Game.testing = false
	var it: Dictionary = Loot.make_item("rusted_sword","rare",42)
	it["uid"] = ch.take_uid()
	it["sockets"] = 1
	it["gems"] = ["ruby:0"]
	ch.inventory[0] = it
	ch.materials["abyssal_brand"] = 2
	var before: String = JSON.stringify(ch.to_dict())
	var result: Dictionary = ch.corrupt_item(it["uid"],"failed-save",t.SequenceRng.new([0]))
	check(result["err"] != "" and JSON.stringify(ch.to_dict()) == before and not ch._corruption_busy,"C10 failed persistence restores item/gems/resources/receipt and releases lock")
	Game.save_dir = "res://tests/.corruption_save_test"
	Game.current_slot = 1
	result = ch.corrupt_item(it["uid"],"actual-save",t.SequenceRng.new([9600]))
	check(result["err"] == "" and FileAccess.file_exists(Game.slot_path(1)),"actual atomic save commits corruption")
	var loaded = Character.new()
	loaded.from_dict(Game.read_slot(1))
	check(JSON.stringify(loaded.inventory) == JSON.stringify(ch.inventory) and loaded.corruption_actions.has("actual-save") and loaded.materials["abyssal_brand"] == 1,"current-save fixture disk roundtrip keeps double/gems/cost/receipt")
	for slot in [1,Game.AUTOSAVE_SLOT]:
		DirAccess.remove_absolute(Game.slot_path(slot))
	DirAccess.remove_absolute(Game.save_dir)
	Game.save_dir = saved_dir
	Game.current_slot = saved_slot
	Game.testing = saved_testing
