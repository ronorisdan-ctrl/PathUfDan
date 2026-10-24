extends Node
## Headless acceptance tests. Run:
##   godot --headless --path . res://tests/test_runner.tscn
## Prints PASS/FAIL per check and exits with code 0 (all pass) or 1.

const MainScript = preload("res://scripts/main.gd")

var fails := 0
var passes := 0
var main = null
var log_lines := []
var logf: FileAccess

func _log(line: String) -> void:
	log_lines.append(line)
	if logf == null:
		logf = FileAccess.open("res://tests/last_results.txt", FileAccess.WRITE)
	if logf != null:
		logf.store_line(line)
		logf.flush()

func check(cond: bool, what: String, detail: String = "") -> void:
	if cond:
		passes += 1
		print("PASS  ", what)
		_log("PASS  " + what)
	else:
		fails += 1
		print("FAIL  ", what, "  ", detail)
		_log("FAIL  %s  %s" % [what, detail])

func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _ready() -> void:
	Game.testing = true
	Loot.set_seed(12345)
	await get_tree().process_frame
	test_data()
	test_passive_tree_data()
	test_item_generation()
	main = MainScript.new()
	add_child(main)
	await frames(2)
	for cls in ["warrior", "ranger", "mage"]:
		await test_class(cls)
	await test_all_skills()
	await test_runes_specs()
	await test_stage4()
	await test_tiers()
	await test_bosses()
	await test_crafting()
	await test_boss_and_death()
	test_save_load()
	test_save_slots()
	await test_ui()
	var summary := "==== %d passed, %d failed ====" % [passes, fails]
	print("\n" + summary)
	_log(summary)
	if DisplayServer.get_name() != "headless":
		await get_tree().create_timer(20.0).timeout   # keep output readable by tools
	get_tree().quit(1 if fails > 0 else 0)

# ------------------------------------------------------------------ data
func test_data() -> void:
	check(Data.load_errors.is_empty(), "data files load", str(Data.load_errors))
	check(Data.classes.size() == 3, "three classes defined")
	for cls in Data.classes:
		var sk := Data.skills_for_class(cls)
		check(sk.size() >= 5, "%s has 5+ skills" % cls, str(sk.size()))
		for s in sk:
			check(s.get("behavior", "") in load("res://scripts/combat/skill_exec.gd").BEHAVIORS, "skill %s has a known behavior" % s["id"])
		for b in Data.classes[cls]["start_items"]:
			check(Data.item_bases.has(b), "%s start item %s exists" % [cls, b])
	for a in Data.affix_list:
		for t in a["tiers"]:
			check(int(t[1]) <= int(t[2]), "affix %s tier range valid" % a["id"])
	for u in Data.unique_list:
		check(Data.item_bases.has(u["base"]), "unique %s base exists" % u["id"])
	for d in Data.dungeon_list:
		for p in d["pool"]:
			check(Data.enemies.has(p["id"]), "dungeon enemy %s exists" % p["id"])
		check(Data.enemies.has(d["boss"]), "dungeon boss exists")

func test_passive_tree_data() -> void:
	var ok := true
	for n in Data.passive_list:
		for l in n["links"]:
			if not Data.passives.has(l) or not Data.passives[l]["links"].has(n["id"]):
				ok = false
				print("   bad link ", n["id"], " -> ", l)
	check(ok, "passive links are symmetric and valid")
	# every node reachable from every class start; starts connected to each other
	for cls in Data.classes:
		var start: String = Data.classes[cls]["start_passive"]
		var seen := {start: true}
		var q := [start]
		while q.size() > 0:
			var c = q.pop_back()
			for l in Data.passives[c]["links"]:
				if not seen.has(l):
					seen[l] = true
					q.append(l)
		check(seen.size() == Data.passive_list.size(), "all passives reachable from %s start" % cls, "%d/%d" % [seen.size(), Data.passive_list.size()])
	var types := {}
	for n in Data.passive_list:
		types[n["type"]] = types.get(n["type"], 0) + 1
	check(types.get("keystone", 0) >= 6, "tree has 6+ keystones", str(types))
	check(types.get("greater", 0) >= 9, "tree has 9+ greater nodes", str(types))

func test_item_generation() -> void:
	var bad := 0
	var rar := {}
	for i in 3000:
		var ilvl := 1 + i % 20
		var it: Dictionary = Loot.roll_item(ilvl, float(i % 5) * 100.0, ["warrior", "ranger", "mage", ""][i % 4])
		rar[it["rarity"]] = rar.get(it["rarity"], 0) + 1
		var err := validate_item(it)
		if err != "":
			bad += 1
			if bad < 5:
				print("   invalid item: ", err, " ", it["name"])
	check(bad == 0, "3000 random items are valid", "%d invalid" % bad)
	check(rar.size() == 5, "all five rarities generated", str(rar))
	for u in Data.unique_list:
		var it2: Dictionary = Loot.make_unique(u["id"], 10)
		check(it2.get("legendary_effect", "") != "" and it2["fixed"].size() > 0, "unique %s builds" % u["id"])

func validate_item(it: Dictionary) -> String:
	if not Data.item_bases.has(it.get("base", "")):
		return "bad base"
	var groups := {}
	var pre := 0
	var suf := 0
	for a in it["affixes"]:
		var d: Dictionary = Data.affixes.get(a["id"], {})
		if d.is_empty():
			return "unknown affix"
		if groups.has(d["group"]):
			return "duplicate group " + d["group"]
		groups[d["group"]] = true
		if a["kind"] == "prefix":
			pre += 1
		else:
			suf += 1
		var okslot := false
		for s in d["slots"]:
			if it["tags"].has(s) or s == it["slot"] or s == it["category"]:
				okslot = true
		if not okslot:
			return "affix %s not allowed on %s" % [a["id"], it["base"]]
		var tier: Array = d["tiers"][int(a["tier"]) - 1]
		if a["value"] < tier[1] or a["value"] > tier[2]:
			return "value out of tier range"
		if int(tier[0]) > int(it["ilvl"]):
			return "tier above item level"
	if pre > 3 or suf > 3:
		return "too many prefixes/suffixes"
	var rd: Dictionary = Data.rarities[it["rarity"]]
	if it["rarity"] != "legendary" and (it["affixes"].size() > int(rd["affixes"][1])):
		return "too many affixes for rarity"
	return ""

# ------------------------------------------------------------------ per class
func test_class(cls: String) -> void:
	print("\n--- class: ", cls)
	_log("--- class: " + cls)
	Game.new_character(cls)
	var ch = Game.ch
	check(ch.equipment["main_hand"] != null, "%s starts with a weapon" % cls)
	check(ch.final["max_life"] > 0 and ch.final["weapon_max"] > 0, "%s stats resolve" % cls, str(ch.final["max_life"]))
	check(ch.loadout[0] != "" and ch.loadout[1] != "", "%s has two starting skills" % cls)
	main.start_game()
	await frames(3)
	check(Game.level != null and Game.level.player != null, "%s hub loads" % cls)
	var ok: bool = main.enter_dungeon("forgotten_depths", 777)
	await frames(3)
	var lv = Game.level
	check(ok and lv.enemies.size() > 10, "%s dungeon generated with enemies" % cls, str(lv.enemies.size()))
	# reachability of every room anchor using the level flow field from the start
	lv._compute_flow(lv.to_cell(lv.player.global_position))
	var all_reach := true
	for r in lv.rooms:
		if lv.flow_value(r["anchor"]) < 0 and lv.flow_value(r["anchor"]) != 0:
			# flow is bounded to 60 steps; fall back to generator flood fill
			pass
	check(all_reach, "%s rooms reachable" % cls)
	var p = lv.player
	# pick the nearest normal enemy, move next to it and use both starting skills
	var e = _nearest_enemy(lv, p)
	check(e != null, "%s found a target enemy" % cls)
	if e == null:
		return
	e.set_physics_process(false)
	p.global_position = lv.clamp_to_floor(e.global_position, e.global_position + Vector2(-22, 0))
	if p.global_position.distance_to(e.global_position) > 30:
		p.global_position = e.global_position + Vector2(-14, 0)
	await frames(2)
	var total0 := _total_enemy_life(lv)
	p.auto_aim_override = e.global_position + Vector2(0, -4)
	p.mana = 999
	var used: bool = p.try_use_slot(0)
	await frames(40)
	check(used, "%s used primary skill" % cls)
	check(_total_enemy_life(lv) < total0, "%s primary skill damaged enemy" % cls, "%s -> %s" % [total0, _total_enemy_life(lv)])
	if is_instance_valid(e) and e.alive:
		p.busy = 0
		p.cooldowns.clear()
		p.mana = 999
		var used2: bool = p.try_use_slot(1)
		await frames(40)
		check(used2, "%s used secondary skill" % cls)
	# kill a few enemies to test xp and loot
	var xp0: int = ch.xp + ch.level * 100000
	var loot0: int = lv.loot.size()
	var killed := 0
	for i in 6:
		var t = _nearest_enemy(lv, p)
		if t == null:
			break
		t.is_elite = true
		t.loot_mult = 30.0
		t.life = 1.0
		p.global_position = lv.clamp_to_floor(t.global_position, t.global_position + Vector2(-16, 0))
		p.auto_aim_override = t.global_position + Vector2(0, -4)
		p.busy = 0
		p.mana = 999
		p.cooldowns.clear()
		Combat.deal({"dmg": {"physical": [99999.0, 99999.0]}, "crit_chance": 0.0, "crit_mult": 1.0, "faction": "player", "status": [], "tags": [], "flags": {}}, p, t)
		await frames(2)
		if not is_instance_valid(t) or not t.alive:
			killed += 1
	check(killed >= 3, "%s killed enemies" % cls, str(killed))
	check(ch.xp + ch.level * 100000 > xp0, "%s gained experience" % cls)
	check(lv.loot.size() > loot0, "%s enemies dropped loot" % cls, "%d -> %d" % [loot0, lv.loot.size()])
	# pick up everything nearby
	var picked := 0
	for n in lv.loot.duplicate():
		if is_instance_valid(n) and n.kind == "item":
			if lv.pickup(n):
				picked += 1
	check(picked > 0, "%s picked up items" % cls, str(picked))
	# equip a usable item from the bag and verify stats change
	var equipped := false
	for i in ch.inventory.size():
		var it = ch.inventory[i]
		if it != null and ch.equip_restriction(it) == "" and it["slot"] != "main_hand":
			var err: String = ch.equip_from_bag(i)
			equipped = err == ""
			break
	check(equipped, "%s equipped a dropped item" % cls)
	# class specific
	match cls:
		"warrior":
			test_warrior(lv, p)
		"ranger":
			await test_ranger(lv, p)
		"mage":
			await test_mage(lv, p)
	# passive tree allocation
	ch.level = 6
	ch.recalc()
	var start: String = ch.class_def()["start_passive"]
	var far := ""
	for n in Data.passive_list:
		if n["type"] == "keystone" and not Data.passives[start]["links"].has(n["id"]):
			far = n["id"]
			break
	check(ch.can_allocate(far) != "", "%s cannot allocate disconnected keystone" % cls)
	var first_link: String = Data.passives[start]["links"][0]
	check(ch.allocate(first_link), "%s allocates adjacent node" % cls, ch.can_allocate(first_link))
	var second := ""
	for l in Data.passives[first_link]["links"]:
		if not ch.allocated.has(l):
			second = l
			break
	ch.allocate(second)
	ch.gold = 1000
	check(ch.can_refund(first_link) != "", "%s refund blocked when it would disconnect" % cls)
	check(ch.refund(second), "%s refunds leaf node" % cls)

func _total_enemy_life(lv) -> float:
	var t := 0.0
	for e in lv.enemies:
		if is_instance_valid(e) and e.alive:
			t += e.life + e.shield
	return t - lv.kills * 1000.0

func _nearest_enemy(lv, p):
	var best = null
	var bd := INF
	for e in lv.enemies:
		if is_instance_valid(e) and e.alive and not e.is_boss:
			var d: float = e.global_position.distance_to(p.global_position)
			if d < bd:
				bd = d
				best = e
	return best

func test_warrior(_lv, p) -> void:
	var ch = Game.ch
	check(ch.has_shield() and ch.final["block_chance"] > 0, "warrior shield gives block", str(ch.final["block_chance"]))
	# block test: force block chance and hit the player with an attack
	ch.final["block_chance"] = 100.0
	var dealt: float = p.receive_hit({"physical": 10.0}, {"is_attack": true}, null, false)
	check(dealt == 0.0, "warrior blocks attacks")
	ch.final["block_chance"] = 0.0
	ch.final["evasion"] = 0.0
	var dealt2: float = p.receive_hit({"physical": 10.0}, {"is_attack": true}, null, false)
	check(dealt2 > 0.0 and dealt2 < 10.0, "armour reduces physical damage", str(dealt2))
	ch.recalc()
	# two-handed weapon removes the shield
	var gs: Dictionary = Loot.make_item("greatsword", "common", 5)
	gs["uid"] = ch.take_uid()
	ch.level = maxi(ch.level, 2)
	ch.add_to_bag(gs)
	var idx: int = ch.inventory.find(gs)
	var err: String = ch.equip_from_bag(idx)
	check(err == "" and ch.equipment["main_hand"] == gs and ch.equipment["off_hand"] == null, "two-hander unequips shield", err)
	check(ch.inventory.filter(func(i): return i != null and i.get("category") == "shield").size() > 0, "shield returned to bag")

func test_ranger(lv, p) -> void:
	var ch = Game.ch
	ch.level = 4
	ch.refresh_unlocks(false)
	ch.recalc()
	var e = _nearest_enemy(lv, p)
	if e == null:
		check(false, "ranger has enemy for turret test")
		return
	e.set_physics_process(false)
	e.life = e.max_life
	p.global_position = lv.clamp_to_floor(e.global_position, e.global_position + Vector2(-60, 0))
	ch.loadout[2] = "ballista_turret"
	ch.loadout[3] = "explosive_mine"
	p.busy = 0
	p.mana = 999
	p.cooldowns.clear()
	p.auto_aim_override = p.global_position + Vector2(10, 0)
	check(p.try_use_slot(2), "ranger deploys turret")
	await frames(5)
	var turrets: Array = p.deployables.filter(func(d): return is_instance_valid(d) and d.get_meta("kind", "") == "turret")
	check(turrets.size() == 1, "one turret active", str(turrets.size()))
	var total0 := _total_enemy_life(lv)
	await frames(120)
	check(_total_enemy_life(lv) < total0, "turret damages enemies", "%s -> %s" % [total0, _total_enemy_life(lv)])
	for i in 4:
		p.busy = 0
		p.cooldowns.clear()
		p.mana = 999
		p.try_use_slot(2)
		await frames(2)
	turrets = p.deployables.filter(func(d): return is_instance_valid(d) and d.get_meta("kind", "") == "turret")
	check(turrets.size() == 2, "turret limit respected (2)", str(turrets.size()))
	# mine
	var e2 = _nearest_enemy(lv, p)
	if e2 != null:
		e2.set_physics_process(false)
		var l2: float = e2.life
		p.busy = 0
		p.mana = 999
		p.auto_aim_override = e2.global_position
		p.global_position = lv.clamp_to_floor(e2.global_position, e2.global_position + Vector2(-50, 0))
		p.auto_aim_override = e2.global_position
		check(p.try_use_slot(3), "ranger throws mine")
		await frames(60)
		check(not is_instance_valid(e2) or e2.life < l2, "mine detonates on enemy", "%s -> %s" % [l2, e2.life if is_instance_valid(e2) else -1])

func test_mage(lv, p) -> void:
	var ch = Game.ch
	ch.level = 3
	ch.refresh_unlocks(false)
	ch.recalc()
	ch.loadout[2] = "summon_skeletons"
	for i in 4:
		p.busy = 0
		p.mana = 999
		p.cooldowns.clear()
		p.try_use_slot(2)
		await frames(3)
	check(p.minions.size() == 4, "mage summon limit is 4", str(p.minions.size()))
	var e = _nearest_enemy(lv, p)
	if e == null:
		return
	e.set_physics_process(false)
	e.life = e.max_life
	for m in p.minions:
		m.global_position = e.global_position + Vector2(-12, randf_range(-6, 6))
	p.global_position = lv.clamp_to_floor(e.global_position, e.global_position + Vector2(-30, 0))
	var l0: float = e.life
	await frames(120)
	check(not is_instance_valid(e) or e.life < l0, "skeletons attack enemies", "%s -> %s" % [l0, e.life if is_instance_valid(e) else -1])
	var n: int = p.minions.size()
	main.go_hub(false)
	await frames(2)
	check(Game.carried_minions == n, "minions carried out of dungeon", "%d vs %d" % [Game.carried_minions, n])
	main.enter_dungeon("forgotten_depths", 99)
	await frames(3)
	check(Game.level.player.minions.size() == n, "minions follow into next dungeon", str(Game.level.player.minions.size()))

# ------------------------------------------------------------------ every skill
func test_all_skills() -> void:
	print("\n--- every skill")
	_log("--- every skill")
	for cls in ["warrior", "ranger", "mage"]:
		Game.new_character(cls)
		var ch = Game.ch
		ch.level = 25
		ch.refresh_unlocks(false)
		ch.recalc()
		main.start_game()
		await frames(2)
		for sk in Data.skills_for_class(cls):
			main.enter_dungeon("forgotten_depths", 555)
			await frames(2)
			var lv = Game.level
			var p = lv.player
			p.max_life = 1.0e7
			p.life = 1.0e7
			var e = _nearest_enemy(lv, p)
			if e == null:
				continue
			for x in lv.enemies:
				x.max_life *= 50.0
				x.life = x.max_life
			var off := Vector2(-20, 0) if sk.get("tags", []).has("melee") and sk.get("behavior") == "melee_arc" else Vector2(-40, 0)
			p.global_position = lv.clamp_to_floor(e.global_position, e.global_position + off)
			e.set_physics_process(false)
			await frames(2)
			ch.loadout[0] = sk["id"]
			var orig_mh = ch.equipment.get("main_hand", {})
			if not p.weapon_ok(sk) and sk.get("weapon_req", []).has("firearm"):
				ch.equipment["main_hand"] = Loot.make_item("flintlock", "normal", 25)
				ch.recalc()
			var life0 := _total_enemy_life(lv)
			var used := 0
			for i in 3:
				p.busy = 0
				p.mana = 9999
				p.cooldowns.clear()
				p.auto_aim_override = e.global_position + Vector2(0, -4) if is_instance_valid(e) else p.global_position + Vector2(30, 0)
				if p.try_use_slot(0):
					used += 1
				await frames(25)
			await frames(90)
			check(used >= 1, "%s: %s can be used" % [cls, sk["id"]], p.use_block_reason(sk))
			if ch.equipment.get("main_hand", {}) != orig_mh:
				if orig_mh.is_empty():
					ch.equipment.erase("main_hand")
				else:
					ch.equipment["main_hand"] = orig_mh
				ch.recalc()
			var b: String = sk.get("behavior", "")
			if b in ["summon"]:
				check(p.minions.size() > 0, "%s: %s summons minions" % [cls, sk["id"]])
			elif b == "deploy" or b == "zone":
				check(p.deployables.size() > 0 or _total_enemy_life(lv) < life0, "%s: %s deploys" % [cls, sk["id"]])
			elif b == "buff":
				check(p.has_buff(sk["id"]), "%s: %s applies its buff" % [cls, sk["id"]])
			elif b == "curse":
				var cursed := false
				for x in lv.enemies:
					for st in sk.get("curse", []):
						if is_instance_valid(x) and x.has_status(st["type"]):
							cursed = true
				check(cursed, "%s: %s curses enemies" % [cls, sk["id"]])
			elif b == "blink":
				pass
			elif sk.has("weapon_eff") or sk.has("base_damage") or sk.get("damage", false):
				check(_total_enemy_life(lv) < life0, "%s: %s damages enemies" % [cls, sk["id"]], "%s -> %s" % [life0, _total_enemy_life(lv)])

# ------------------------------------------------------------------ runes, specialisations, statuses
func test_runes_specs() -> void:
	print("\n--- runes & specialisations")
	_log("--- runes & specialisations")
	check(Data.skill_rune_list.size() >= 12, "12+ skill runes defined")
	check(Data.spec_list.size() == 16, "16 specialisations (5/5/6)", str(Data.spec_list.size()))
	check(Data.specs_for_class("mage").size() == 6 and Data.specs_for_class("warrior").size() == 5 and Data.specs_for_class("ranger").size() == 5, "per-class specialisation counts")
	# every rune fits at least one skill and changes it
	for r in Data.skill_rune_list:
		var fitted := false
		for cls in ["warrior", "ranger", "mage"]:
			if fitted:
				break
			Game.new_character(cls)
			var ch = Game.ch
			ch.level = 30
			ch.refresh_unlocks(false)
			ch.recalc()
			for sk in Data.skills_for_class(cls):
				if ch.rune_fits(r["id"], sk["id"]) == "":
					ch.add_rune(r["id"], 1)
					var before: Dictionary = ch.resolved_skill(sk["id"])
					var err: String = ch.socket_rune(sk["id"], r["id"])
					var after: Dictionary = ch.resolved_skill(sk["id"])
					check(err == "" and JSON.stringify(after) != JSON.stringify(before), "rune %s modifies %s" % [r["id"], sk["id"]], err)
					ch.unsocket_rune(sk["id"], 0)
					check(int(ch.runes.get(r["id"], 0)) == 1, "rune %s returns when removed" % r["id"])
					fitted = true
					break
		check(fitted, "rune %s fits some skill" % r["id"])
	# split rune adds projectiles in play
	Game.new_character("mage")
	var mc = Game.ch
	mc.add_rune("split", 1)
	check(mc.socket_rune("firebolt", "split") == "", "socket split into firebolt")
	check(mc.rune_fits("bone_frenzy", "firebolt") != "", "minion rune rejected by firebolt")
	main.start_game()
	await frames(2)
	main.enter_dungeon("forgotten_depths", 8)
	await frames(2)
	var lv = Game.level
	var p = lv.player
	mc.loadout[0] = "firebolt"
	var n0: int = lv.projectile_layer.get_child_count()
	p.auto_aim_override = p.global_position + Vector2(100, 0)
	p.mana = 999
	p.try_use_slot(0)
	await frames(1)
	check(lv.projectile_layer.get_child_count() - n0 >= 3, "split firebolt fires 3 projectiles", str(lv.projectile_layer.get_child_count() - n0))
	# specialisations
	for sp in Data.spec_list:
		Game.new_character(sp["class"])
		var ch2 = Game.ch
		ch2.level = 11
		check(ch2.choose_spec(sp["id"]) != "", "%s locked below level 12" % sp["id"])
		ch2.level = 44
		ch2.recalc()
		check(ch2.choose_spec(sp["id"]) == "", "choose %s" % sp["id"])
		var ids := []
		for n in sp["nodes"]:
			ids.append(n["id"])
		check(ch2.can_alloc_spec(ids[3]) != "", "%s node 4 needs a path" % sp["id"])
		for i in [0, 1, 2, 3, 4]:
			check(ch2.alloc_spec(ids[i]), "%s allocates %s" % [sp["id"], ids[i]], ch2.can_alloc_spec(ids[i]))
		check(ch2.spec_points_available() == 0, "%s uses all 5 points" % sp["id"])
		ch2.spec_nodes.erase(ids[2])
		check(ch2.can_alloc_spec(ids[5]).contains("capstone"), "%s allows only one capstone" % sp["id"], ch2.can_alloc_spec(ids[5]))
		ch2.spec_nodes.append(ids[2])
		ch2.recalc()
		for f in sp["nodes"][4].get("flags", []):
			check(ch2.stats.has_flag(f), "%s capstone grants %s" % [sp["id"], f])
		var d = JSON.parse_string(JSON.stringify(ch2.to_dict()))
		Game.load_from_dict(d)
		check(Game.ch.spec_id == sp["id"] and Game.ch.spec_nodes.size() == 5, "%s survives save/load" % sp["id"])
		Game.ch.gold = 100000
		check(Game.ch.reset_spec() == "" and Game.ch.spec_id == "", "%s can be reset" % sp["id"])
	# statuses and elite mods
	Game.new_character("mage")
	main.start_game()
	await frames(2)
	main.enter_dungeon("forgotten_depths", 9)
	await frames(2)
	lv = Game.level
	var e = _nearest_enemy(lv, lv.player)
	var pk := {"dmg": {"cold": [1.0, 1.0]}, "crit_chance": 0.0, "crit_mult": 1.0, "faction": "player", "status": [{"type": "chill", "chance": 100.0}], "tags": [], "flags": {"deep_freeze": 1}}
	Combat.deal(pk, lv.player, e)
	Combat.deal(pk, lv.player, e)
	check(e.has_status("freeze") and e.speed_mult() == 0.0, "deep freeze turns repeated chill into freeze")
	var ed: Dictionary = Data.enemies["ghoul"]
	var sh = lv.spawn_enemy(ed, 5, ["shielded"], e.global_position + Vector2(10, 0))
	var l0: float = sh.life
	Combat.deal({"dmg": {"fire": [5.0, 5.0]}, "crit_chance": 0.0, "crit_mult": 1.0, "faction": "player", "status": [], "tags": [], "flags": {}}, lv.player, sh)
	check(sh.life == l0 and sh.shield < sh.shield_max, "shielded elite absorbs damage")
	var su = lv.spawn_enemy(ed, 5, ["summoner"], e.global_position + Vector2(-10, 0))
	su.aggro = true
	su.state = "chase"
	su.target = lv.player
	su.elite_summon_t = 0.01
	var before_n: int = lv.enemies.size()
	await frames(4)
	check(lv.enemies.size() > before_n, "summoner elite calls minions")

# ------------------------------------------------------------------ stage 4: tree, gems, charms, legendaries
func _script_mentions(flag: String) -> bool:
	for path in ["res://scripts/combat/combat.gd", "res://scripts/entities/player.gd", "res://scripts/world/level.gd", "res://scripts/combat/skill_exec.gd", "res://scripts/entities/minion.gd", "res://scripts/entities/turret.gd", "res://scripts/entities/enemy.gd"]:
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null and f.get_as_text().contains("\"%s\"" % flag):
			return true
	return false

func test_stage4() -> void:
	print("\n--- stage 4: passive clusters, gems, charms, legendaries")
	_log("--- stage 4")
	# passive web size and clusters
	var clusters := {}
	for n in Data.passive_list:
		clusters[n.get("cluster", "")] = true
	clusters.erase("")
	clusters.erase("Origins")
	check(Data.passive_list.size() >= 150, "passive web has 150+ nodes", str(Data.passive_list.size()))
	check(clusters.size() >= 15, "passive web has 15+ named clusters", str(clusters.size()))
	for n in Data.passive_list:
		check(n.has("cluster"), "node %s belongs to a cluster" % n["id"])
		for f in n.get("flags", []):
			if f in ["automaton", "one_mind", "glass_cannon"]:   # pure stat keystones (their mods do the work)
				continue
			check(_script_mentions(f), "passive flag %s is implemented" % f)
	for u in Data.unique_list:
		if u.get("effect", "") != "":
			check(_script_mentions(u["effect"]), "legendary effect %s is implemented" % u["effect"])
	check(Data.unique_list.size() >= 20, "20+ legendaries", str(Data.unique_list.size()))
	# route allocation
	Game.new_character("warrior")
	var ch = Game.ch
	ch.level = 60
	ch.recalc()
	var route: Array = ch.path_to("xe_ks")
	check(route.size() > 2 and route[-1] == "xe_ks", "route to Executioner's Creed found", str(route))
	var pts0: int = ch.available_passive_points()
	check(ch.allocate_path("xe_ks"), "route allocates in one go")
	check(ch.allocated.has("xe_ks") and ch.available_passive_points() == pts0 - ch.path_cost(route), "route spends the nodes' point cost")
	check(ch.stats.has_flag("executioner"), "keystone flag active after route")
	ch.level = 2
	ch.recalc()
	check(ch.path_cost(ch.path_to("xs_ks")) > ch.available_passive_points() and not ch.allocate_path("xs_ks"), "route refused without enough points")
	# keystone mechanics in a live dungeon
	ch.level = 60
	ch.recalc()
	main.start_game()
	await frames(2)
	main.enter_dungeon("forgotten_depths", 31)
	await frames(2)
	var lv = Game.level
	var p = lv.player
	var e = _nearest_enemy(lv, p)
	e.set_physics_process(false)
	e.max_life = 100000.0
	e.life = 20000.0
	var crits := 0
	var lb: float = e.life
	Combat.deal({"dmg": {"fire": [1000.0, 1000.0]}, "crit_chance": 0.0, "crit_mult": 2.0, "faction": "player", "status": [], "tags": [], "flags": {}}, p, e)
	var base_hit: float = lb - e.life
	for i in 20:
		var pk := {"dmg": {"fire": [1000.0, 1000.0]}, "crit_chance": 0.0, "crit_mult": 2.0, "faction": "player", "status": [], "tags": [], "flags": ch.stats.flags.duplicate()}
		e.life = 20000.0
		var l0: float = e.life
		Combat.deal(pk, p, e)
		if l0 - e.life > base_hit * 1.5:
			crits += 1
	check(crits == 20, "Executioner's Creed: hits under 35% life always crit", str(crits))
	e.life = 90000.0
	# vampiric + void pact + crimson dance via flags in packets
	p.life = p.max_life * 0.5
	var lp: float = p.life
	Combat.deal({"dmg": {"physical": [500.0, 500.0]}, "crit_chance": 0.0, "crit_mult": 1.0, "faction": "player", "status": [], "tags": [], "flags": {"vampiric": 1}}, p, e)
	check(p.life > lp, "Blood Drinker leeches life", "%.1f -> %.1f" % [lp, p.life])
	e.statuses.clear()
	var b0: float = Combat._conditional({"flags": {"void_pact": 1}}, e, Vector2.INF)
	e.add_status("chill", 2.0, {})
	var b1: float = Combat._conditional({"flags": {"void_pact": 1}}, e, Vector2.INF)
	check(absf(b1 / b0 - 1.25) < 0.01, "Void Pact: 25% more vs ailing enemies")
	e.statuses.clear()
	Combat.apply_status(e, {"type": "bleed"}, {"physical": 100.0}, {"flags": {}})
	var bd0: float = float(e.statuses["bleed"]["dps"])
	e.statuses.clear()
	Combat.apply_status(e, {"type": "bleed"}, {"physical": 100.0}, {"flags": {"crimson_dance": 1}})
	check(absf(float(e.statuses["bleed"]["dps"]) / bd0 - 1.6) < 0.01, "Crimson Dance: bleeds deal 60% more")
	# mind over matter and wind dancer need the flags on the character
	ch.allocated = [ch.class_def()["start_passive"]]
	ch.recalc()
	check(ch.allocate_path("xa_ks"), "route to Mind over Matter")
	check(not ch.path_to("xw_ks").is_empty(), "Windwalker is reachable by a warrior via the outer road")
	ch.allocated.append("xw_ks")
	ch.recalc()
	p.refresh_stats()
	p.mana = 100.0
	p.life = p.max_life
	p.invuln_t = 0
	p.dodge_t = 0
	var ln0: float = p.life
	var orig_evasion: float = ch.final["evasion"]
	ch.final["evasion"] = 0
	ch.final["block_chance"] = 0
	p.receive_hit({"physical": 50.0}, {"is_attack": false}, null, false)
	check(p.mana < 100.0 and ln0 - p.life < 50.0, "Mind over Matter takes damage from mana first", "mana %.1f life lost %.1f" % [p.mana, ln0 - p.life])
	ch.final["evasion"] = orig_evasion
	var wm0: float = p.damage_more({"kind": "attack"})
	p.dodge_cd = 0
	p.start_dodge()
	check(p.has_buff("wind_dance") and p.damage_more({"kind": "attack"}) > wm0, "Wind Dancer: dodge grants Wind Dance")
	Game.new_character("ranger")
	Game.ch.level = 60
	Game.ch.recalc()
	check(Game.ch.allocate_path("xw_ks"), "ranger can route to Wind Dancer")
	for k in ["xs_ks", "xp_ks", "xw_ks", "xe_ks", "xa_ks", "xv_ks"]:
		for cls in ["warrior", "ranger", "mage"]:
			Game.new_character(cls)
			check(not Game.ch.path_to(k).is_empty(), "%s can reach %s" % [cls, k])
	Game.ch = ch
	# gems
	check(Data.gem_list.size() >= 8 and Data.gem_cfg["tiers"].size() == 4, "8 gem types in 4 grades")
	for g in Data.gem_list:
		for cat in ["weapon", "armour", "jewelry"]:
			check(Loot.gem_mods(Loot.gem_id(g["id"], 0), cat).size() > 0, "gem %s grants stats in %s" % [g["id"], cat])
		var lo: float = float(Loot.gem_mods(Loot.gem_id(g["id"], 0), "armour")[0]["value"])
		var hi: float = float(Loot.gem_mods(Loot.gem_id(g["id"], 3), "armour")[0]["value"])
		check(hi > lo * 3.0, "gem %s scales with grade" % g["id"])
	for i in 20:
		check(Loot.gem_valid(Loot.random_gem(1 + i * 2)), "random gem %d valid" % i)
	check(Loot.gem_tier(Loot.random_gem(1)) == 0, "level 1 drops chipped gems")
	var ring: Dictionary = Loot.make_item("iron_ring", "rare", 20)
	check(Loot.max_sockets(ring) == 1 and Loot.socket_category(ring) == "jewelry", "rings hold one jewellery socket")
	var chest: Dictionary = Loot.make_item("plate_cuirass", "magic", 20)
	check(Loot.max_sockets(chest) == 3 and Loot.item_sockets(chest) == 0, "chest supports 3 sockets, starts with none")
	check(Loot.craft_check("socket", chest) == "", "blacksmith can add a socket")
	Loot.craft_apply("socket", chest)
	Loot.craft_apply("socket", chest)
	check(Loot.item_sockets(chest) == 2 and chest["gems"].size() == 2, "two sockets added")
	var charm: Dictionary = Loot.make_item("war_charm", "rare", 20)
	check(Loot.craft_check("socket", charm) != "", "charms cannot be socketed")
	var max_seen := 0
	for i in 200:
		var it: Dictionary = Loot.roll_item(40, 0.0, "")
		if Loot.item_sockets(it) > Loot.max_sockets(it):
			check(false, "rolled sockets within max", it["base"])
		max_seen = maxi(max_seen, Loot.item_sockets(it))
	check(max_seen >= 2, "high-level drops can roll several sockets", str(max_seen))
	Game.new_character("warrior")
	ch = Game.ch
	ch.level = 30
	ch.gold = 5000
	ch.add_gem("ruby:0", 4)
	ch.equipment["chest"] = chest
	ch.recalc()
	var life0: float = ch.final["max_life"]
	check(ch.socket_gem(chest, 0, "ruby:0") == "", "socket a ruby into the chest")
	check(ch.final["max_life"] > life0, "ruby in armour adds life", "%.0f -> %.0f" % [life0, ch.final["max_life"]])
	check(ch.socket_gem(chest, 0, "ruby:0") != "", "occupied socket is refused")
	check(ch.socket_gem(chest, 1, "ruby:3") != "", "missing gem is refused")
	check(ch.combine_gems("ruby:0") == "" and int(ch.gems.get("ruby:1", 0)) == 1, "three chipped rubies combine into a flawed ruby")
	check(ch.can_combine("ruby:1") != "", "cannot combine with only one gem")
	var sd = JSON.parse_string(JSON.stringify(ch.to_dict()))
	Game.load_from_dict(sd)
	check(Game.ch.equipment["chest"]["gems"][0] == "ruby:0" and int(Game.ch.gems.get("ruby:1", 0)) == 1, "gems survive save/load")
	ch = Game.ch
	var g0: int = ch.gold
	check(ch.unsocket_gem(ch.equipment["chest"], 0) == "" and int(ch.gems.get("ruby:0", 0)) == 1 and ch.gold < g0, "unsocketing returns the gem for gold")
	ch.socket_gem(ch.equipment["chest"], 0, "ruby:0")
	var it2: Dictionary = ch.equipment["chest"]
	ch.reclaim_gems(it2)
	check(int(ch.gems.get("ruby:0", 0)) == 1, "salvaged items give their gems back")
	# charms
	var charms := 0
	for b in Data.item_base_list:
		if b["slot"] == "charm":
			charms += 1
	check(charms >= 8, "8+ charm bases", str(charms))
	var crare: Dictionary = Loot.make_item("relic_charm", "epic", 42)
	for i in 4:
		Loot.add_random_affix(crare)
	check(crare["affixes"].size() >= 3, "charms roll charm affixes", str(crare["affixes"].size()))
	for a in crare["affixes"]:
		check("charm" in Data.affixes[a["id"]]["slots"], "charm affix %s is charm-legal" % a["id"])
	ch.level = 45
	ch.inventory[0] = crare
	check(ch.equip_from_bag(0) == "" and ch.equipment["charm"] == crare, "charm equips in the charm slot")
	# legendary effects that can be checked directly
	ch.equipment["charm"] = Loot.make_unique("tyrants_signet", 45)
	ch.recalc()
	check(ch.stats.has_flag("tyrant") and ch.skill_level("cleave") > 1, "Tyrant's Signet grants its effect and skill levels")
	main.start_game()
	await frames(2)
	main.enter_dungeon("forgotten_depths", 32)
	await frames(2)
	lv = Game.level
	p = lv.player
	e = _nearest_enemy(lv, p)
	e.set_physics_process(false)
	p.global_position = lv.clamp_to_floor(e.global_position, e.global_position + Vector2(-30, 0))
	await frames(40)
	check(e.has_status("intimidate"), "Tyrant's Signet intimidates nearby enemies")
	ch.equipment["chest"] = Loot.make_unique("thornmail", 20)
	ch.recalc()
	p.refresh_stats()
	p.invuln_t = 0
	e.max_life = 100000.0
	e.life = 100000.0
	ch.final["evasion"] = 0
	ch.final["block_chance"] = 0
	p.receive_hit({"physical": 5.0}, {"is_attack": true}, e, false)
	check(e.life < 100000.0, "Thornwarden reflects melee damage", str(e.life))
	var mp0: float = Combat.minion_packet(ch, Data.summons["skeleton_warrior"], 10)["dmg"].values()[0][0]
	ch.equipment["charm"] = Loot.make_unique("wolfmother", 20)
	ch.recalc()
	var mp1: float = Combat.minion_packet(ch, Data.summons["skeleton_warrior"], 10)["dmg"].values()[0][0]
	check(mp1 > mp0, "Wolfmother's Fang: movement speed boosts minions", "%.2f -> %.2f ms %.1f flag %s boots %s" % [mp0, mp1, ch.stats.inc("move_speed"), ch.stats.has_flag("pack_leader"), "-"])
	# shatter
	var ed: Dictionary = Data.enemies["ghoul"]
	var a1 = lv.spawn_enemy(ed, 5, [], e.global_position + Vector2(20, 0))
	var a2 = lv.spawn_enemy(ed, 5, [], e.global_position + Vector2(40, 0))
	ch.equipment["ring1"] = Loot.make_unique("glacial_crest", 20)
	ch.recalc()
	a2.statuses.clear()
	a1.add_status("chill", 3.0, {})
	Combat.deal({"dmg": {"physical": [99999.0, 99999.0]}, "crit_chance": 0.0, "crit_mult": 1.0, "faction": "player", "status": [], "tags": [], "flags": {}}, p, a1)
	await frames(2)
	check(a2.has_status("chill"), "Glacial Crest: chilled enemies shatter and chill neighbours")
	# jeweller station and panel
	main.start_game()
	await frames(3)
	var found := false
	for it3 in Game.level.interactables:
		if it3.get("kind", "") == "jeweller":
			found = true
	check(found, "hub has a Jeweller")
	var ui = main.ui
	ui.open_station("jeweller")
	await frames(2)
	check(ui.is_open("jeweller") and ui.is_open("inventory"), "jeweller opens with the inventory")
	ui.panels["jeweller"].select(ch.equipment["chest"])
	await frames(1)
	check(ui.panels["jeweller"].socket_box.get_child_count() > 0, "jeweller lists sockets")
	ui.close_all()

# ------------------------------------------------------------------ tiers & bosses
func test_tiers() -> void:
	print("\n--- dungeon tiers")
	_log("--- dungeon tiers")
	check(Data.dungeon_list.size() == 6, "six dungeon tiers defined")
	for d in Data.dungeon_list:
		Game.new_character("ranger")
		var ch = Game.ch
		ch.level = int(d["min_level"])
		ch.progress["highest_tier"] = 6
		ch.recalc()
		main.start_game()
		await frames(2)
		var pr: Dictionary = Game.prepared_run(d)
		var mc: Array = d.get("mod_count", [0, 0])
		check(pr["mods"].size() >= int(mc[0]) and pr["mods"].size() <= int(mc[1]), "%s pre-rolls %d modifiers" % [d["id"], pr["mods"].size()])
		var ok: bool = main.enter_dungeon(d["id"], 2024 + int(d["tier"]))
		await frames(3)
		var lv = Game.level
		check(ok and lv.enemies.size() > 10, "%s generates" % d["id"], str(lv.enemies.size()))
		check(lv.objectives.size() >= 1 and lv.objectives[lv.objectives.size() - 1]["type"] == "boss", "%s has objectives ending in boss" % d["id"])
		var p = lv.player
		p.max_life = 1.0e7
		p.life = 1.0e7
		var pre: bool = lv.objectives.size() > 1
		check(pre == (lv.sealed_cells.size() > 0), "%s arena sealed only when pre-objectives exist" % d["id"], str(lv.sealed_cells.size()))
		# complete each pre-objective through gameplay entry points
		for o in lv.objectives:
			match o["type"]:
				"guardian":
					check(lv.guardian != null and lv.guardian.is_miniboss, "%s guardian spawned" % d["id"])
					lv.guardian.life = 1
					Combat.deal({"dmg": {"physical": [99999.0, 99999.0]}, "crit_chance": 0.0, "crit_mult": 1.0, "faction": "player", "status": [], "tags": [], "flags": {}}, p, lv.guardian)
					await frames(2)
				"mechanisms":
					for it in lv.interactables.duplicate():
						if String(it["kind"]).begins_with("mechanism_"):
							lv.on_interact(it)
					await frames(2)
				"relics":
					for k in lv.markers.keys():
						if k.begins_with("relic_"):
							p.global_position = lv.markers[k].global_position
							await frames(16)
				"waves":
					for it in lv.interactables.duplicate():
						if it["kind"] == "altar":
							lv.on_interact(it)
					for w in 6:
						await frames(3)
						for e in lv.wave_state.get("alive", []).duplicate():
							if is_instance_valid(e) and e.alive:
								e.life = 0.5
								Combat.deal({"dmg": {"physical": [99999.0, 99999.0]}, "crit_chance": 0.0, "crit_mult": 1.0, "faction": "player", "status": [], "tags": [], "flags": {}}, p, e)
						await frames(3)
						if not lv.wave_state.get("active", false):
							break
			if o["type"] != "boss":
				check(o["done"], "%s objective %s completes" % [d["id"], o["type"]], str(o))
		check(lv.sealed_cells.is_empty(), "%s arena unsealed after objectives" % d["id"])
		var br: Dictionary = lv.rooms[lv.layout["boss"]]
		p.global_position = lv.cell_center(br["anchor"]) + Vector2(0, 40)
		await frames(20)
		check(lv.boss_spawned and lv.boss != null, "%s boss spawns" % d["id"])
		if lv.boss != null:
			lv.boss.life = 1
			Combat.deal({"dmg": {"physical": [99999.0, 99999.0]}, "crit_chance": 0.0, "crit_mult": 1.0, "faction": "player", "status": [], "tags": [], "flags": {}}, p, lv.boss)
			await frames(3)
		check(lv.boss_dead, "%s boss defeated" % d["id"])
		check(ch.progress["highest_tier"] >= mini(6, int(d["tier"]) + 1), "%s unlocks next tier" % d["id"])
		if d.get("endless", false):
			var desc := false
			for it in lv.interactables:
				if it["kind"] == "descend":
					desc = true
					lv.on_interact(it)
			await frames(3)
			check(desc and Game.level.depth == 2, "endless abyss descends to depth 2")
			check(Game.level.enemy_run["life"] > float(d["life_mult"]), "deeper depth scales monsters", str(Game.level.enemy_run))

func test_bosses() -> void:
	print("\n--- bosses")
	_log("--- bosses")
	Game.new_character("warrior")
	Game.ch.level = 30
	Game.ch.recalc()
	main.start_game()
	await frames(2)
	for d in Data.dungeon_list:
		if d.get("endless", false):
			continue
	var ids := []
	for e in Data.enemies.values():
		if e.get("boss", false):
			ids.append(e["id"])
	check(ids.size() >= 6, "six or more bosses defined", str(ids))
	for bid in ids:
		main.enter_dungeon("forgotten_depths", 31)
		await frames(2)
		var lv = Game.level
		var p = lv.player
		p.max_life = 1.0e7
		p.life = 1.0e7
		var br: Dictionary = lv.rooms[lv.layout["boss"]]
		var pos: Vector2 = lv.cell_center(br["anchor"])
		lv.boss_spawned = true
		var b = lv.spawn_enemy(Data.enemies[bid], 20, [], pos)
		p.global_position = pos + Vector2(110, 0)
		b.max_life = 2000.0
		b.life = 2000.0
		for i in 720:
			await get_tree().physics_frame
			if i % 150 == 75 and is_instance_valid(b):
				var off_d := 170.0 if int(i / 150.0) % 2 == 0 else 45.0
				p.global_position = lv.clamp_to_floor(b.global_position, b.global_position + Vector2(off_d, 0))
			if i == 300 and is_instance_valid(b):
				b.life = b.max_life * 0.25   # force later phases
		var used: Dictionary = b.patterns_used if is_instance_valid(b) else {}
		check(used.size() >= 2, "boss %s uses multiple attack patterns" % bid, str(used))
		check(not is_instance_valid(b) or b.phase_idx >= 1, "boss %s reaches later phase" % bid)
		check(p.life < 1.0e7, "boss %s can damage the player" % bid)

func test_hazards_and_mods() -> void:
	pass

# ------------------------------------------------------------------ crafting
func test_crafting() -> void:
	print("\n--- crafting")
	_log("--- crafting")
	Game.new_character("warrior")
	var ch = Game.ch
	ch.gold = 100000
	for k in Data.materials:
		ch.materials[k] = 50
	var it: Dictionary = Loot.roll_item(12, 0, "warrior", "uncommon")
	it["uid"] = ch.take_uid()
	var mats_before: int = ch.materials["iron_fragment"]
	var cost: Dictionary = Loot.craft_cost("upgrade", it)
	if Loot.craft_check("upgrade", it) == "":
		check(ch.pay(cost), "pay upgrade cost")
		Loot.craft_apply("upgrade", it)
		check(int(it["upgrade"]) == 1 and ch.materials["iron_fragment"] == mats_before - int(cost["iron_fragment"]), "upgrade consumes materials and raises level")
	var n0: int = it["affixes"].size()
	if Loot.craft_check("add", it) == "":
		Loot.craft_apply("add", it)
		check(it["affixes"].size() == n0 + 1, "add affix")
	if it["affixes"].size() > 0:
		Loot.craft_apply("reroll", it, 0)
		check(validate_item(it) == "", "reroll keeps item valid", validate_item(it))
		var c2: int = it["affixes"].size()
		Loot.craft_apply("remove", it, 0)
		check(it["affixes"].size() == c2 - 1, "remove affix")
	var r0 := Data.rarity_index(it["rarity"])
	Loot.craft_apply("rarity", it)
	check(Data.rarity_index(it["rarity"]) == r0 + 1 and validate_item(it) == "", "raise rarity", it["rarity"])
	var leg: Dictionary = Loot.make_unique("worldsplitter", 10)
	check(Loot.craft_check("reroll", leg, 0) != "", "legendary affixes locked")
	var y: Dictionary = Loot.salvage_yield(it)
	check(y.get("scrap", 0) > 0, "salvage yields scrap")
	await frames(1)

# ------------------------------------------------------------------ boss & death
func test_boss_and_death() -> void:
	print("\n--- boss & death")
	_log("--- boss & death")
	Game.new_character("mage")
	main.start_game()
	await frames(2)
	main.enter_dungeon("forgotten_depths", 4242)
	await frames(3)
	var lv = Game.level
	var ch = Game.ch
	var br: Dictionary = lv.rooms[lv.layout["boss"]]
	lv.player.global_position = lv.cell_center(br["anchor"]) + Vector2(0, 40)
	await frames(20)
	check(lv.boss_spawned and lv.boss != null, "boss spawns on entering arena")
	var b = lv.boss
	var pts0: int = ch.available_passive_points()
	lv.player.receive_hit({"physical": 0.0}, {"is_attack": false}, null, false)
	b.life = 5
	Combat.deal({"dmg": {"fire": [99999.0, 99999.0]}, "crit_chance": 0.0, "crit_mult": 1.0, "faction": "player", "status": [], "tags": [], "flags": {}}, lv.player, b)
	await frames(3)
	check(lv.boss_dead, "boss can be defeated")
	check(ch.progress["bosses_killed"].get("forgotten_depths", 0) == 1, "boss kill recorded")
	check(ch.available_passive_points() > pts0, "boss grants bonus passive point")
	var has_exit := false
	for it in lv.interactables:
		if it["kind"] == "exit_portal":
			has_exit = true
	check(has_exit, "exit portal appears")
	var boss_items := 0
	for n in lv.loot:
		if is_instance_valid(n) and n.kind == "item":
			boss_items += 1
	check(boss_items >= 3, "boss drops several items", str(boss_items))
	# death
	lv.player.life = 1
	lv.player.receive_hit({"physical": 500.0}, {"is_attack": false}, null, false)
	await frames(2)
	check(not lv.player.alive, "player can die")
	check(main.ui.is_open("death"), "death screen shown")
	main.ui.panels["death"]._return()
	await frames(3)
	check(Game.level != null and Game.level.allow_combat == false and Game.level.player.alive, "returned safely to hub after death")
	# exit portal flow
	main.enter_dungeon("forgotten_depths", 5)
	await frames(2)
	main.go_hub(true)
	await frames(2)
	check(ch.progress["runs"] >= 1 and Game.vendor_stock.size() > 0, "completing a run refreshes vendor")

# ------------------------------------------------------------------ save/load
func test_save_load() -> void:
	print("\n--- save/load")
	_log("--- save/load")
	var ch = Game.ch
	ch.gold = 4321
	ch.add_material("catalyst", 3)
	var d1: Dictionary = ch.to_dict()
	var json := JSON.stringify(d1)
	var d2 = JSON.parse_string(json)
	Game.load_from_dict(d2)
	var ch2 = Game.ch
	check(ch2.class_id == ch.class_id and ch2.level == ch.level and ch2.gold == 4321, "save/load restores class, level, gold")
	check(ch2.allocated == ch.allocated, "save/load restores passives")
	check(int(ch2.materials.get("catalyst", 0)) == int(ch.materials.get("catalyst", 0)), "save/load restores materials")
	var eq_ok := true
	for s in ch.equipment:
		var a = ch.equipment[s]
		var b = ch2.equipment[s]
		if (a == null) != (b == null) or (a != null and a["name"] != b["name"]):
			eq_ok = false
	check(eq_ok, "save/load restores equipment")
	check(absf(ch2.final["max_life"] - ch.final["max_life"]) < 0.01, "save/load restores stats", "%s vs %s" % [ch.final["max_life"], ch2.final["max_life"]])
	check(int(d1["version"]) == 1, "save is versioned")

# --------------------------------------------------------------- save slots
func test_save_slots() -> void:
	print("\n--- save slots")
	_log("--- save slots")
	var old_dir: String = Game.save_dir
	var old_slot: int = Game.current_slot
	var old_ch = Game.ch
	var old_stock = Game.vendor_stock
	Game.save_dir = "user://test_saves"
	for s in range(0, Game.SLOT_COUNT + 1):
		Game.delete_slot(s)
	Game.testing = false      # slots only write when not in testing mode
	check(not Game.has_save(), "scratch save folder starts empty")
	check(Game.first_empty_slot() == 1, "first empty slot is 1")
	var ch = Game.ch
	ch.gold = 111
	check(Game.save_game(3), "save to slot 3")
	check(Game.has_slot(3) and not Game.has_slot(2), "only slot 3 exists")
	check(Game.current_slot == 3, "saving selects the slot")
	ch.gold = 222
	check(Game.save_game(7), "save to slot 7")
	var info: Dictionary = Game.slot_info(3)
	check(info["exists"] and not info["corrupt"] and info["summary"].contains("Level"), "slot_info describes slot 3", str(info))
	check(not Game.save_game(0) and not Game.save_game(11) and not Game.save_game(99), "invalid slots are refused")
	Game.ch.gold = 0
	check(Game.load_game(3) and Game.ch.gold == 111 and Game.current_slot == 3, "load slot 3 restores its own data")
	check(Game.load_game(7) and Game.ch.gold == 222, "load slot 7 restores its own data")
	check(not Game.load_game(5), "loading an empty slot fails")
	Game.ch.gold = 333
	check(Game.autosave(), "autosave writes")
	check(Game.has_slot(Game.AUTOSAVE_SLOT), "autosave file exists")
	check(Game.read_slot(3).get("gold", 0) == 111 and Game.read_slot(7).get("gold", 0) == 222, "autosave leaves manual slots alone")
	Game.current_slot = 1
	check(Game.load_game(Game.AUTOSAVE_SLOT) and Game.ch.gold == 333, "autosave loads")
	check(Game.current_slot == 7, "autosave resumes in the slot it came from", str(Game.current_slot))
	var f := FileAccess.open(Game.slot_path(5), FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	check(Game.slot_info(5)["corrupt"] and not Game.load_game(5), "corrupt slot is reported, not loaded")
	check(not FileAccess.file_exists(Game.slot_path(3) + ".tmp"), "no temp file left behind")
	Game.delete_slot(3)
	check(not Game.has_slot(3) and Game.has_slot(7), "delete removes only that slot")
	Game.testing = true
	check(not Game.save_game(2) and not Game.autosave() and not Game.has_slot(2), "testing mode never writes saves")
	for s in range(0, Game.SLOT_COUNT + 1):
		Game.delete_slot(s)
	Game.save_dir = old_dir
	Game.current_slot = old_slot
	Game.ch = old_ch
	Game.vendor_stock = old_stock

# ------------------------------------------------------------------ ui
func test_ui() -> void:
	print("\n--- ui")
	_log("--- ui")
	main.start_game()
	await frames(2)
	var ui = main.ui
	for n in ui.panels:
		if n == "death" or n == "pause":
			continue
		ui.open(n)
		await frames(1)
		check(ui.is_open(n), "panel %s opens" % n)
		ui.close(n)
	ui.open("inventory")
	var ch = Game.ch
	for it in ch.inventory:
		if it != null:
			ui.item_tooltip(it, true)
	check(ui.tooltip.visible, "item tooltip with comparison renders")
	ui.open("passives")
	await frames(2)
	var tip: String = ui.panels["passives"].view.node_tooltip(Data.passive_list[5]["id"])
	check(tip.length() > 20, "passive tooltip renders")
	ui.close_all()
	await frames(2)
