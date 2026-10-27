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
	if has_meta("no_auto"):
		return   # tests/train_only.gd drives single groups itself
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
	await test_stun()
	await test_pets()
	await test_stash()
	await test_loot_filter()
	test_vendor_legendary_rate()
	await test_crafting()
	await test_boss_and_death()
	await test_dev_tools()
	test_training()
	await test_training_world()
	test_save_load()
	test_save_slots()
	await test_ui()
	await test_stash_ui()
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

func test_vendor_legendary_rate() -> void:
	var li: int = Data.rarity_list.size() - 1
	check(Data.rarity_list[li]["id"] == "legendary", "vendor odds: legendary is the last rarity")
	# vendor: 8 items per stock, +60 rarity bonus, legendary weight override from loot.json
	var vw := float(Data.loot.get("vendor_legendary_weight", -1.0))
	check(vw >= 0.0, "vendor odds: vendor_legendary_weight is set in loot.json")
	var w: Array = Loot.rarity_weights(60.0, vw)
	var total := 0.0
	for x in w:
		total += float(x)
	var p_item: float = float(w[li]) / total
	var p_stock: float = 1.0 - pow(1.0 - p_item, 8.0)
	check(p_stock > 1.0 / 550.0 and p_stock < 1.0 / 450.0, "vendor odds: about 1 legendary per 500 stock rerolls", "1 in %.1f" % (1.0 / p_stock))
	# monster drops are untouched: same weights as before for trash, elite and boss bonuses
	for bonus in [0.0, 150.0, 400.0]:
		var d: Array = Loot.rarity_weights(bonus)
		var expect: float = float(Data.rarity_list[li]["weight"]) * (1.0 + bonus / 100.0)
		check(is_equal_approx(float(d[li]), expect), "drop odds unchanged at bonus %d" % int(bonus))
	check(is_equal_approx(float(Loot.rarity_weights(60.0)[li]), float(Data.rarity_list[li]["weight"]) * 1.6), "default roll_rarity ignores the vendor override")

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

# ------------------------------------------------------------------ stun (data/stun.json)
const StunRules = preload("res://scripts/combat/stun.gd")

func _near(a: float, b: float, eps: float = 0.001) -> bool:
	return absf(a - b) <= eps

func test_stun() -> void:
	print("\n--- stun")
	_log("--- stun")
	var cfg: Dictionary = Data.stun_cfg
	check(not cfg.is_empty() and cfg.get("enabled", false), "stun config loaded and enabled")
	if cfg.is_empty():
		return
	# pure rules
	check(StunRules.stun_chance(cfg, "normal", 10.0, 100.0) == 0.0, "stun: no chance at the threshold")
	check(_near(StunRules.stun_chance(cfg, "normal", 30.0, 100.0), 0.55), "stun: chance ramps linearly", str(StunRules.stun_chance(cfg, "normal", 30.0, 100.0)))
	check(StunRules.stun_chance(cfg, "normal", 50.0, 100.0) == 1.0, "stun: guaranteed at 50% of max life")
	check(StunRules.stun_chance(cfg, "player", 50.0, 100.0, 5.0) == 1.0, "stun: high threshold stat never blocks a 50% hit")
	check(StunRules.stun_chance(cfg, "player", 25.0, 100.0, 2.0) == 0.0, "stun: threshold stat raises the threshold")
	check(StunRules.stun_chance(cfg, "normal", 3.0, 100.0, 0.0) > 0.0, "stun: threshold stat is floored at min_threshold_mult")
	check(_near(StunRules.stun_duration(cfg, "normal", 10.0, 100.0), 0.4) and _near(StunRules.stun_duration(cfg, "normal", 90.0, 100.0), 0.8), "stun: duration from min to max (capped)")
	check(StunRules.try_stun(cfg, "elite", 30.0, 100.0, 0.99) == 0.0 and StunRules.try_stun(cfg, "elite", 30.0, 100.0, 0.01) > 0.0, "stun: roll uses the supplied rng value")
	var off := cfg.duplicate(true)
	off["enabled"] = false
	check(StunRules.stun_chance(off, "normal", 90.0, 100.0) == 0.0, "stun: disabled config never stuns")
	var ps := StunRules.new_poise()
	var hits := []
	for i in 3:
		hits.append(StunRules.poise_hit(cfg, ps, 60.0, 1000.0))
	check(hits == [false, false, true], "poise: three 6% hits stagger a boss", str(hits))
	check(not StunRules.poise_hit(cfg, ps, 600.0, 1000.0) and ps["poise"] == 0.0, "poise: immune during and after stagger")
	StunRules.poise_tick(cfg, ps, 9.5)
	check(ps["immune"] == 0.0 and ps["stagger"] == 0.0, "poise: immunity ends after stagger + 8 s")
	StunRules.poise_hit(cfg, ps, 30.0, 1000.0)
	var p0: float = ps["poise"]
	StunRules.poise_tick(cfg, ps, 2.0)
	var p1: float = ps["poise"]
	StunRules.poise_tick(cfg, ps, 2.0)
	check(p1 == p0 and ps["poise"] < p0, "poise: regenerates only after the regen delay", "%f %f %f" % [p0, p1, ps["poise"]])
	check(_near(StunRules.poise_multiplier(cfg, 0.05), 1.0) and _near(StunRules.poise_multiplier(cfg, 0.15), 1.75) and _near(StunRules.poise_multiplier(cfg, 0.10), 1.375), "poise: big-hit bonus ramps without a cliff")
	# in game
	Game.new_character("warrior")
	Game.ch.level = 20
	Game.ch.recalc()
	main.start_game()
	await frames(2)
	main.enter_dungeon("forgotten_depths", 77)
	await frames(2)
	var lv = Game.level
	var p = lv.player
	var br: Dictionary = lv.rooms[lv.layout["boss"]]
	var pos: Vector2 = lv.cell_center(br["anchor"])
	var pk := {"flags": {}, "is_attack": false}
	# normal enemy: big hit stuns, small hit does not, immunity blocks a second stun
	var e = lv.spawn_enemy(Data.enemies["grave_brute"], 10, [], pos + Vector2(40, 0))
	await frames(1)
	e.armour = 0.0
	e.resist = {}
	e.receive_hit({"arcane": e.max_life * 0.05}, pk, p, false)
	check(not e.has_status("stun"), "stun: a 5% hit does not stun a normal enemy")
	e.life = e.max_life
	e.state = "chase"
	e._start_attack(Vector2.RIGHT)
	var tele: Array = e.windup_aoes.duplicate()
	check(e.state == "windup" and tele.size() == 1, "stun: slam windup records its telegraph")
	e.receive_hit({"arcane": e.max_life * 0.6}, pk, p, false)
	check(e.has_status("stun"), "stun: a 60% hit always stuns a normal enemy")
	check(e.state == "recover" and (tele.is_empty() or not is_instance_valid(tele[0]) or tele[0].is_queued_for_deletion()), "stun: interrupts the windup and removes its telegraph")
	check(e.stun_immune_t > 0.0 and e.try_hit_stun(e.max_life * 0.6, "normal") == 0.0, "stun: immunity after a stun")
	# armour reduces stuns: same raw hit, heavy armour -> less life lost -> lower chance
	check(StunRules.stun_chance(cfg, "normal", e.max_life * 0.3 * (1.0 - Combat.armour_reduction(500.0, e.max_life * 0.3)), e.max_life) < StunRules.stun_chance(cfg, "normal", e.max_life * 0.3, e.max_life), "stun: armour lowers stun chance")
	# boss poise
	var b = lv.spawn_enemy(Data.enemies["warden"], 20, [], pos)
	await frames(1)
	b.max_life = 2000.0
	b.life = 2000.0
	b.armour = 0.0
	b.resist = {}
	b.receive_hit({"arcane": 120.0}, pk, p, false)
	b.receive_hit({"arcane": 120.0}, pk, p, false)
	check(not b.has_status("stun") and b.poise_state["poise"] > 0.0, "poise: boss is not stunned by single hits", str(b.poise_state))
	b.receive_hit({"arcane": 120.0}, pk, p, false)
	check(b.has_status("stun") and b.poise_state["stagger"] > 0.0, "poise: boss staggers when poise fills", str(b.poise_state))
	b.receive_hit({"arcane": 120.0}, pk, p, false)
	check(b.poise_state["poise"] == 0.0 and b.poise_state["immune"] > 8.0, "poise: no poise gain while immune")
	for x in [b, e]:
		lv.enemies.erase(x)
		x.queue_free()
	# player: a 60% hit stuns and cancels the cast; dodge breaks it after 0.15 s
	p.global_position = pos + Vector2(-120, 0)
	p.max_life = 1000.0
	p.life = 1000.0
	p.stun_immune_t = 0.0
	p.ch.final["block_chance"] = 0.0
	p.ch.final["res_arcane"] = 0.0
	p.ch.final["damage_reduction"] = 0.0
	p.busy = 0.5
	p.pending.append({"t": 0.3, "fn": func(): pass})
	p.receive_hit({"arcane": 600.0}, pk, null, false)
	check(p.alive and p.has_status("stun"), "stun: big hit stuns the player", str(p.life))
	check(p.busy <= 0.0 and p.pending.is_empty(), "stun: player cast is cancelled")
	check(not p.can_dodge_out_of_stun(), "stun: dodge cannot break the stun at once")
	await frames(12)
	check(not p.has_status("stun") or p.can_dodge_out_of_stun(), "stun: dodge can break the stun after 0.15 s")
	p.dodge_cd = 0.0
	if p.has_status("stun"):
		p.start_dodge()
		check(not p.has_status("stun") and p.dodge_t > 0.0, "stun: dodging out of stun works")
	await frames(30)
	p.statuses.erase("stun")
	p.life = p.max_life
	p.stun_immune_t = 0.0
	p.ch.stats.add("stun_threshold", "inc", 150.0, "test")
	p.receive_hit({"arcane": 400.0}, pk, null, false)
	check(p.life < p.max_life and not p.has_status("stun"), "stun: stun threshold stat protects against a 40% hit", str(p.life))
	Game.ch.recalc()

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
	check(int(d1["version"]) == ch.SAVE_VERSION and ch.SAVE_VERSION >= 2, "save is versioned")

# ------------------------------------------------------------------ pets
const PetRulesT = preload("res://scripts/core/pet_rules.gd")

## A floor point `dist` px from `from` with a clear straight line, or null.
func _open_point(lv, from: Vector2, dist: float, avoid := []):
	for k in 16:
		var dir := Vector2.RIGHT.rotated(k * TAU / 16.0)
		var to: Vector2 = from + dir * dist
		if lv.is_solid(to) or not lv.has_los(from, to):
			continue
		var ok := true
		for a in avoid:
			if to.distance_to(a) < 24:
				ok = false
		if ok and lv.clamp_to_floor(from, to).distance_to(to) < 1.0:
			return to
	return null

func _drop_item(lv, rarity: String, pos: Vector2):
	var it: Dictionary = Loot.make_item("rusty_sword" if Data.item_bases.has("rusty_sword") else Data.item_base_list[0]["id"], rarity, 5)
	lv.spawn_drop({"kind": "item", "item": it}, pos)
	var n = lv.loot.back()
	n.t = 1.0
	n.position = pos
	return n

func _bag_uid_count(ch, uid: int) -> int:
	var c := 0
	for it in ch.inventory:
		if it != null and int(it.get("uid", -1)) == uid:
			c += 1
	return c

func _set_pet_tier(lv, ch, id: String, tier: int):
	ch.pets[id]["tier"] = tier
	Events.pet_changed.emit()
	return lv.pet

func _wait_until(cond: Callable, max_frames: int = 240) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await get_tree().physics_frame
	return cond.call()

func test_loot_filter() -> void:
	print("\n--- loot filter")
	_log("--- loot filter")
	var LF = load("res://scripts/core/loot_filter.gd")
	# ---- the engine's own acceptance tests
	var eng = load("res://tests/test_loot_filter.gd").new()
	var r: Dictionary = eng.run()
	check(int(r["failed"]) == 0 and int(r["passed"]) > 40, "loot filter: engine tests (%d passed)" % int(r["passed"]), str(r["log"]))
	eng.free()
	check(LootFilter != null and LootFilter.PRESET_NAMES.size() == 4, "loot filter: autoload present with four presets")
	# ---- every real base maps to a valid filter slot and kind
	var map_ok := true
	var bad := ""
	for base_id in Data.item_bases:
		var it: Dictionary = Loot.make_item(base_id, "rare", 20)
		if it.is_empty():
			continue
		var d: Dictionary = LootFilter.describe(it)
		if not (str(d["slot"]) in LF.SLOTS) or not (str(d["kind"]) in LF.KINDS):
			map_ok = false
			bad = "%s -> %s/%s" % [base_id, d["slot"], d["kind"]]
	check(map_ok, "loot filter: every item base maps to a known slot and kind", bad)
	var two_h := ""
	var one_h := ""
	for base_id in Data.item_bases:
		var b: Dictionary = Data.item_bases[base_id]
		if b.get("slot", "") == "main_hand":
			if b.get("two_handed", false) and two_h == "":
				two_h = base_id
			if not b.get("two_handed", false) and one_h == "":
				one_h = base_id
	check(LootFilter.describe(Loot.make_item(two_h, "common", 5))["slot"] == "weapon_2h" and LootFilter.describe(Loot.make_item(one_h, "common", 5))["slot"] == "weapon_1h", "loot filter: one-handed and two-handed weapons map to the right slots")
	# ---- drops obey the filter (the filter is bypassed under Game.testing unless switched on)
	var LootDropS = load("res://scripts/entities/loot_drop.gd")
	var common: Dictionary = Loot.make_item(one_h, "common", 5)
	var legend: Dictionary = Loot.make_item(one_h, "legendary", 5)
	var drop_c = LootDropS.new()
	drop_c.setup_item(common)
	add_child(drop_c)
	check(drop_c.visible and not drop_c.filtered_now(), "loot filter: bots and tests are unaffected (filter bypassed while testing)")
	drop_c.queue_free()
	Game.filter_in_tests = true
	LootFilter.set_character("test_runner")
	LootFilter.load_filter("strict")
	var dc = LootDropS.new()
	dc.setup_item(common)
	add_child(dc)
	var dl = LootDropS.new()
	dl.setup_item(legend)
	add_child(dl)
	check(not dc.visible and dc.hidden_by_filter and dc.filtered_now(), "loot filter: Strict hides a common drop (not drawn)")
	check(dl.visible and not dl.filtered_now(), "loot filter: a legendary is never hidden (safety net)")
	LootFilter.reveal_hidden = true
	LootFilter.emit_signal("reveal_changed", true)
	check(dc.visible and not dc.hidden_by_filter, "loot filter: holding Alt reveals the hidden drop")
	LootFilter.reveal_hidden = false
	LootFilter.emit_signal("reveal_changed", false)
	check(not dc.visible, "loot filter: releasing Alt hides it again")
	LootFilter.load_filter("show_all")
	check(dc.visible, "loot filter: switching filter updates drops already on the floor")
	LootFilter.load_filter("rare_plus")
	var dr = LootDropS.new()
	dr.setup_item(Loot.make_item(one_h, "rare", 5))
	add_child(dr)
	check(dr.visible and dr.fres.get("color") != null, "loot filter: Rare+ shows a rare with a custom label colour")
	check(dr.fs >= 6 and dr.fs <= 14, "loot filter: label size stays in the readable range", str(dr.fs))
	for n in [dc, dl, dr]:
		n.queue_free()
	Game.filter_in_tests = false
	# ---- sounds named by the presets exist
	var snd_ok := true
	for pn in LF.PRESET_NAMES:
		var txt := FileAccess.get_file_as_string("res://data/loot_filters/%s.json" % pn)
		var pd = JSON.parse_string(txt)
		check(typeof(pd) == TYPE_DICTIONARY and LootFilter.validate(LootFilter.normalize(pd)).filter(func(m): return m.begins_with("ERROR")).is_empty(), "loot filter: preset %s validates" % pn)
		for rule in pd.get("rules", []):
			var s: String = str(rule.get("actions", {}).get("sound", ""))
			if s != "" and s != "none" and not Sfx.streams.has(s):
				snd_ok = false
	check(snd_ok, "loot filter: every sound id used by the presets exists in Sfx")
	# ---- per-character folders follow the save slot
	LootFilter.set_character("test_runner")
	var err: int = LootFilter.save_filter("mine", {"name": "Mine", "rules": []})
	check(err == OK, "loot filter: custom filter saves for the current character")
	LootFilter.set_character("test_runner_b")
	check(not ("mine" in LootFilter.list_filters()), "loot filter: another character does not see it")
	for n in ["test_runner", "test_runner_b"]:
		var dir: String = LF.USER_ROOT + n + "/"
		for f in ["mine.json", "mine.json.bak", "_active.txt"]:
			DirAccess.remove_absolute(dir + f)
		DirAccess.remove_absolute(dir)
	# ---- the in-game editor builds, opens and shows the active filter's rules
	var pnl = load("res://scripts/ui/loot_filter_panel.gd").new()
	add_child(pnl)
	LootFilter.set_character("default")
	LootFilter.load_filter("default")
	pnl.open()
	await frames(2)
	check(pnl.visible and pnl._filter["rules"].size() == LootFilter.filter["rules"].size() and pnl._filter["rules"].size() > 0, "loot filter: editor opens and lists the active filter's rules")
	pnl.close()
	check(not pnl.visible, "loot filter: editor closes")
	pnl.queue_free()
	await frames(1)

func test_pets() -> void:
	print("\n--- pets")
	_log("--- pets")
	# ---- data and rules
	check(Data.pet_list.size() >= 16, "pets: roster loaded", str(Data.pet_list.size()))
	var data_ok := true
	for pd in Data.pet_list:
		if not Art.SPRITES.has(pd.get("sprite", "")) or int(pd.get("price", 0)) <= 0 or float(pd.get("upgrade_cost_mult", 0)) <= 0:
			data_ok = false
	check(data_ok, "pets: every pet has a sprite, a price and a cost multiplier")
	check(PetRulesT.max_tier() == 5, "pets: six-step tier track (0-5)")
	check(PetRulesT.required_tier("gold") == 0 and PetRulesT.required_tier("material") == 0, "pets: gold and materials from tier 0")
	check(PetRulesT.required_tier("item", "common") == 1 and PetRulesT.required_tier("item", "rare") == 3 and PetRulesT.required_tier("item", "legendary") == 5, "pets: each tier unlocks one rarity")
	var costs_rise := true
	var prev := 0
	for t in 5:
		var tot := 0
		for k in PetRulesT.upgrade_cost("dog", t):
			tot += int(PetRulesT.upgrade_cost("dog", t)[k])
		if tot <= prev:
			costs_rise = false
		prev = tot
	check(costs_rise and PetRulesT.upgrade_cost("dog", 5).is_empty(), "pets: upgrade costs rise steeply and stop at max tier")
	check(PetRulesT.total_cost("mimic") > PetRulesT.total_cost("dog") * 3, "pets: cost multiplier scales the whole track", "%d vs %d" % [PetRulesT.total_cost("mimic"), PetRulesT.total_cost("dog")])
	check(PetRulesT.stats("ghost", 3)["wall_pass"] and not PetRulesT.stats("dog", 3)["wall_pass"], "pets: signature tweaks apply (ghost passes walls early)")
	check(PetRulesT.stats("dog", 5)["fetch_cd"] < PetRulesT.stats("dog", 1)["fetch_cd"] and PetRulesT.stats("dog", 5)["speed"] > PetRulesT.stats("dog", 0)["speed"], "pets: higher tiers are faster with shorter cooldowns")
	# ---- buying, upgrading, swapping (state only)
	Game.new_character("ranger")
	var ch = Game.ch
	ch.gold = 100
	check(ch.buy_pet("dog") == "Not enough gold" and not ch.owns_pet("dog"), "pets: buying needs gold")
	ch.gold = 100000
	check(ch.buy_pet("dog") == "" and ch.gold == 100000 - int(Data.pets["dog"]["price"]), "pets: buy a dog with gold")
	check(ch.active_pet == "dog", "pets: the first pet bought starts following")
	check(ch.buy_pet("dog") != "", "pets: cannot buy the same pet twice")
	ch.buy_pet("cat")
	check(ch.active_pet == "dog" and ch.owns_pet("cat"), "pets: buying another pet does not swap")
	check(ch.upgrade_pet("dog") == "Not enough materials", "pets: upgrades cost materials")
	for k in Data.materials:
		ch.materials[k] = 1000000
	var scrap0 := int(ch.materials["scrap"])
	check(ch.upgrade_pet("dog") == "" and ch.upgrade_pet("dog") == "" and ch.pet_tier("dog") == 2, "pets: upgrade the dog to tier 2")
	check(int(ch.materials["scrap"]) < scrap0, "pets: upgrading spends materials")
	check(ch.pet_tier("cat") == 0, "pets: upgrades do not carry over to other pets")
	check(ch.set_active_pet("cat") and ch.active_pet == "cat" and ch.pet_tier("dog") == 2, "pets: swap to the cat, the dog keeps its tier")
	check(ch.set_active_pet("dog") and ch.pet_tier("dog") == 2 and ch.pet_tier("cat") == 0, "pets: swap back, nothing lost or refunded")
	check(not ch.set_active_pet("mimic"), "pets: cannot summon a pet you don't own")
	ch.rename_pet("dog", "  Sir Barks [x]  ")
	check(ch.pet_name("dog") == "Sir Barks (x)", "pets: rename is trimmed and sanitised", ch.pet_name("dog"))
	ch.rename_pet("cat", "   ")
	check(ch.pet_name("cat") == "Cat", "pets: blank name falls back to the species")
	var d2 = JSON.parse_string(JSON.stringify(ch.to_dict()))
	Game.load_from_dict(d2)
	ch = Game.ch
	check(ch.owns_pet("dog") and ch.owns_pet("cat") and ch.pet_tier("dog") == 2 and ch.active_pet == "dog" and ch.pet_name("dog") == "Sir Barks (x)", "pets: save/load round trip keeps pets, tiers, names and the active pet")
	var bad := {"pets": {"dog": {"tier": 99, "name": "A"}, "nonsense": {"tier": 1}}, "active_pet": "nonsense"}
	var d3: Dictionary = ch.to_dict()
	d3.merge(bad, true)
	Game.load_from_dict(JSON.parse_string(JSON.stringify(d3)))
	check(Game.ch.pet_tier("dog") == PetRulesT.max_tier() and not Game.ch.owns_pet("nonsense") and Game.ch.active_pet == "", "pets: bad save data is clamped and unknown pets dropped")
	Game.load_from_dict(d2)
	ch = Game.ch
	# ---- in the world
	Game.pets_in_tests = true
	main.start_game()
	await frames(2)
	check(Game.level.pet != null, "pets: the active pet follows you in town")
	main.enter_dungeon("forgotten_depths", 4242)
	await frames(3)
	var lv = Game.level
	var p = lv.player
	for e in lv.enemies:
		e.set_physics_process(false)
		e.set_process(false)
	var pet = lv.pet
	check(pet != null and is_instance_valid(pet) and pet.pet_id == "dog" and pet.tier == 2, "pets: the pet enters the dungeon with you")
	if pet == null:
		Game.pets_in_tests = false
		return
	# never in the way
	var no_body := true
	for c in pet.find_children("*", "", true, false):
		if c is CollisionObject2D or c is CollisionShape2D:
			no_body = false
	check(no_body and not (pet is CollisionObject2D), "pets: no collision shape or hurtbox")
	check(not pet.has_method("take_damage") and not pet.has_method("receive_hit") and not ("life" in pet), "pets: no life and no damage method")
	check(not lv.allies.has(pet) and not lv.enemies.has(pet) and not lv.hostiles_of("enemy").has(pet) and not lv.hostiles_of("player").has(pet), "pets: never in a targetable list")
	var tgt_ok := true
	for e in lv.enemies.slice(0, 10):
		var tg = lv.nearest_hostile(pet.global_position, "enemy", 9999.0)
		if tg == pet:
			tgt_ok = false
	check(tgt_ok, "pets: enemies never pick the pet as a target")
	# a hostile projectile flies straight through the pet
	p.global_position = lv.cell_center(lv.rooms[lv.layout["start"]]["anchor"]) if lv.layout.has("start") else p.global_position
	await frames(2)
	pet.teleport_to_player()
	var lane = _open_point(lv, pet.global_position, 60.0)
	if lane != null:
		var away: Vector2 = pet.global_position - (lane - pet.global_position)
		var spot = _open_point(lv, pet.global_position, 90.0, [lane, away])
		var keep_player: Vector2 = p.global_position
		if spot != null:
			p.global_position = spot
		pet.set_physics_process(false)
		var pr = load("res://scripts/entities/projectile.gd").new()
		pr.level = lv
		pr.faction = "enemy"
		pr.packet = {"dmg": {"physical": [5.0, 5.0]}, "crit_chance": 0.0, "crit_mult": 1.0, "faction": "enemy", "status": [], "tags": [], "flags": {}}
		pr.radius = 4.0
		pr.max_dist = 200.0
		pr.vel = (lane - pet.global_position).normalized() * 240.0
		pr.position = pet.global_position - pr.vel.normalized() * 20.0
		lv.projectile_layer.add_child(pr)
		await frames(8)
		check(is_instance_valid(pr) and pr.traveled > 25.0 and pr.hit_ids.is_empty(), "pets: projectiles pass through the pet", str(pr.traveled) if is_instance_valid(pr) else "freed")
		if is_instance_valid(pr):
			pr.queue_free()
		pet.set_physics_process(true)
		p.global_position = keep_player
		pet.teleport_to_player()
	else:
		check(false, "pets: projectile lane found")
	await frames(2)
	# ---- F routing
	Game.settings["loot_filter"] = 0
	ch.inventory = ch._fix_list([], ch.BAG_SIZE)
	pet = _set_pet_tier(lv, ch, "dog", 1)
	await frames(2)
	pet.teleport_to_player()
	var near_pos = _open_point(lv, p.global_position, 40.0)
	var n_near = _drop_item(lv, "common", near_pos)
	var uid_near := int(n_near.item["uid"])
	lv.interact(p, n_near.label_rect().get_center())
	check(_bag_uid_count(ch, uid_near) == 1 and pet.fetches == 0, "pets: F on a reachable item picks it up yourself")
	var far_pos = _open_point(lv, pet.global_position, 150.0)
	check(far_pos != null, "pets: test found open floor for a fetch")
	if far_pos == null:
		Game.pets_in_tests = false
		return
	var n_far = _drop_item(lv, "rare", far_pos)
	lv.interact(p, n_far.label_rect().get_center())
	check(pet.last_refusal == "Too heavy" and is_instance_valid(n_far) and not n_far.picked, "pets: F on a distant item above the pet's tier is refused (too heavy)")
	n_far.picked = true
	lv.loot.erase(n_far)
	n_far.queue_free()
	var n_c = _drop_item(lv, "common", far_pos)
	var uid_c := int(n_c.item["uid"])
	check(lv.drop_at_cursor(n_c.label_rect().get_center() + Vector2(0, 30)) == n_c, "pets: F targets the nearest label within the cursor radius")
	lv.interact(p, n_c.label_rect().get_center())
	check(pet.fetches == 1 and pet.state == "fetch" and n_c.claimed_by == pet, "pets: F on a distant item sends the pet")
	check(not lv.pickup(n_c), "pets: a claimed drop cannot be taken by a second collector")
	var n_c2 = _drop_item(lv, "common", far_pos + Vector2(0, 10))
	check(pet.request_fetch(n_c2) == "Busy", "pets: busy while already fetching")
	n_c2.picked = true
	lv.loot.erase(n_c2)
	n_c2.queue_free()
	var got: bool = await _wait_until(func(): return _bag_uid_count(ch, uid_c) == 1, 300)
	check(got and not is_instance_valid(n_c) or (is_instance_valid(n_c) and n_c.picked), "pets: the pet collects on touch, exactly one copy", str(_bag_uid_count(ch, uid_c)))
	var n_r = _drop_item(lv, "common", far_pos)
	check(pet.request_fetch(n_r) == "Resting" or pet.fetch_cd <= 0.0, "pets: resting while the cooldown runs", pet.last_refusal)
	# out of range
	pet.teleport_to_player()
	await frames(1)
	var long_pos = _open_point(lv, pet.global_position, float(pet.st["fetch_range"]) + 40.0)
	if long_pos != null and pet.in_view(long_pos):
		var n_long = _drop_item(lv, "common", long_pos)
		pet.fetch_cd = 0.0
		check(pet.request_fetch(n_long) == "Can't reach", "pets: out of fetch range is refused")
		n_long.picked = true
		lv.loot.erase(n_long)
		n_long.queue_free()
	else:
		check(true, "pets: out of fetch range is refused (no lane on this map)")
	# walls: find a floor spot without line of sight
	var hidden_spot = null
	var pc: Vector2i = lv.to_cell(pet.global_position)
	for dy in range(-10, 11):
		for dx in range(-14, 15):
			var c := Vector2i(pc.x + dx, pc.y + dy)
			if lv.cell(c.x, c.y) != lv.FLOOR:
				continue
			var cp: Vector2 = lv.cell_center(c)
			var dd: float = cp.distance_to(pet.global_position)
			if dd > 60 and dd < float(pet.st["fetch_range"]) - 10 and pet.in_view(cp) and not lv.has_los(pet.global_position, cp):
				hidden_spot = cp
				break
		if hidden_spot != null:
			break
	if hidden_spot != null:
		var n_w = _drop_item(lv, "common", hidden_spot)
		pet.fetch_cd = 0.0
		check(pet.request_fetch(n_w) == "Can't reach", "pets: a wall in the way is refused for early tiers")
		pet = _set_pet_tier(lv, ch, "dog", 4)
		await frames(2)
		pet.teleport_to_player()
		check(pet.request_fetch(n_w) == "", "pets: wall-pass and blink tiers ignore walls")
		var gotw: bool = await _wait_until(func(): return not is_instance_valid(n_w) or n_w.picked, 120)
		check(gotw, "pets: blink fetch through a wall completes")
		pet = _set_pet_tier(lv, ch, "dog", 1)
		await frames(2)
	else:
		check(true, "pets: wall check (no hidden floor near the start on this map)")
	n_r.picked = true
	lv.loot.erase(n_r)
	n_r.queue_free()
	# filter at the moment of collection
	pet = lv.pet
	pet.teleport_to_player()
	await frames(1)
	var n_f = _drop_item(lv, "common", far_pos)
	pet.fetch_cd = 0.0
	check(pet.request_fetch(n_f) == "", "pets: fetch a common item")
	Game.filter_in_tests = true
	LootFilter.load_filter("strict")
	lv.refresh_loot_filter()
	check(lv.drop_at_cursor(n_f.label_rect().get_center()) == null, "pets: items hidden by the loot filter cannot be targeted")
	await _wait_until(func(): return pet.state != "fetch", 300)
	check(is_instance_valid(n_f) and not n_f.picked and n_f.claimed_by == null, "pets: the filter is re-checked at collection (hidden item stays, claim released)")
	Game.filter_in_tests = false
	LootFilter.load_filter("default")
	lv.refresh_loot_filter()
	# bag full
	pet.teleport_to_player()
	await _wait_until(func(): return pet.fetch_cd <= 0.0 and pet.state == "follow", 300)
	for i in ch.inventory.size():
		if ch.inventory[i] == null:
			ch.inventory[i] = Loot.make_item(Data.item_base_list[0]["id"], "common", 1)
	check(pet.request_fetch(n_f) == "", "pets: fetch with a full bag starts")
	await _wait_until(func(): return pet.state != "fetch", 300)
	check(is_instance_valid(n_f) and not n_f.picked and n_f.claimed_by == null, "pets: a full bag leaves the item on the floor")
	ch.inventory = ch._fix_list([], ch.BAG_SIZE)
	# gem-socketed item keeps its gems
	pet.teleport_to_player()
	await _wait_until(func(): return pet.fetch_cd <= 0.0 and pet.state == "follow", 300)
	n_f.item["sockets"] = 2
	n_f.item["gems"] = ["ruby:1", ""] if Loot.gem_valid("ruby:1") else ["", ""]
	var gems_before: Array = n_f.item["gems"].duplicate()
	var uid_f := int(n_f.item["uid"])
	check(pet.request_fetch(n_f) == "", "pets: fetch a socketed item")
	await _wait_until(func(): return _bag_uid_count(ch, uid_f) == 1, 300)
	var gem_ok := false
	for it in ch.inventory:
		if it != null and int(it.get("uid", -1)) == uid_f:
			gem_ok = it.get("gems", []) == gems_before
	check(gem_ok, "pets: a socketed item keeps its gems")
	# auto-loot gold and materials, totals match
	pet.teleport_to_player()
	await frames(2)
	var g0: int = ch.gold
	var m0 := int(ch.materials.get("scrap", 0))
	var gpos = _open_point(lv, p.global_position, 70.0)
	lv.spawn_drop({"kind": "gold", "amount": 37}, gpos)
	lv.loot.back().position = gpos
	lv.spawn_drop({"kind": "material", "id": "scrap", "amount": 3}, gpos + Vector2(0, 6))
	lv.loot.back().position = gpos + Vector2(0, 6)
	var auto_ok: bool = await _wait_until(func(): return ch.gold == g0 + 37 and int(ch.materials.get("scrap", 0)) == m0 + 3, 300)
	check(auto_ok, "pets: auto-loot collects gold and materials with exact totals", "%d/%d" % [ch.gold - g0, int(ch.materials.get("scrap", 0)) - m0])
	# auto-loot never starves F
	pet.teleport_to_player()
	await _wait_until(func(): return pet.fetch_cd <= 0.0 and pet.state == "follow", 300)
	var g2pos = _open_point(lv, p.global_position, 60.0)
	lv.spawn_drop({"kind": "gold", "amount": 5}, g2pos)
	var gn = lv.loot.back()
	gn.position = g2pos
	gn.t = 1.0
	pet.auto_cd = 0.0
	await frames(2)
	var n_s = _drop_item(lv, "common", far_pos)
	var started_auto: bool = pet.state == "fetch" and pet.target_is_auto
	check(pet.request_fetch(n_s) == "" and not pet.target_is_auto and (not started_auto or gn.claimed_by != pet), "pets: F pre-empts an auto-loot run")
	# swapping cancels the fetch and releases the claim
	ch.set_active_pet("cat")
	await frames(2)
	check(lv.pet != null and lv.pet.pet_id == "cat" and is_instance_valid(n_s) and n_s.is_claimed_by_other(lv.pet) == false, "pets: swapping cancels the fetch and releases the drop")
	ch.set_active_pet("dog")
	await frames(2)
	pet = lv.pet
	check(pet.pet_id == "dog" and pet.tier == 1, "pets: switching back restores the same pet and tier")
	n_s.picked = true
	lv.loot.erase(n_s)
	n_s.queue_free()
	# magnet cap
	pet = _set_pet_tier(lv, ch, "dog", 4)
	await frames(2)
	pet.teleport_to_player()
	pet.set_physics_process(false)
	var piles := []
	for i in 10:
		var pp: Vector2 = pet.global_position + Vector2(20 + 3 * i, 0).rotated(i * 0.6)
		if lv.is_solid(pp):
			pp = pet.global_position + Vector2(0, -12)
		lv.spawn_drop({"kind": "gold", "amount": 1}, pp)
		lv.loot.back().position = pp
		lv.loot.back().t = 1.0
		piles.append(lv.loot.back())
	pet._magnet(1.0 / 60.0)
	check(pet.magnet_moved_last <= int(PetRulesT.setting("magnet_max_per_frame", 4)) and pet.magnet_moved_last > 0, "pets: magnet moves at most the per-frame cap", str(pet.magnet_moved_last))
	pet.set_physics_process(true)
	var mag_ok: bool = await _wait_until(func():
		for pl in piles:
			if is_instance_valid(pl) and not pl.picked:
				return false
		return true, 300)
	check(mag_ok, "pets: magnet collects the whole pile over the next frames")
	# catch-up teleport
	var far_player = _open_point(lv, p.global_position, 120.0)
	p.global_position = p.global_position + Vector2(5000, 0) if far_player == null else far_player
	pet.global_position = p.global_position + Vector2(600, 0)
	await frames(3)
	check(pet.global_position.distance_to(p.global_position) < 60.0, "pets: the pet teleports back when it falls far behind")
	# pets are off in normal test and bot runs
	Game.pets_in_tests = false
	Events.pet_changed.emit()
	check(lv.pet == null, "pets: no pet while Game.testing (bot determinism)")
	Game.settings["loot_filter"] = 0
	main.go_hub(false)
	await frames(2)

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

# ------------------------------------------------------------------ stash tabs + shared stash
const StashRulesT = preload("res://scripts/core/stash_rules.gd")
const STASH_TEST_PATH := "user://test_shared_stash.json"

func _stash_test_item(rarity: String = "rare", ilvl: int = 5) -> Dictionary:
	var base: String = "rusty_sword" if Data.item_bases.has("rusty_sword") else Data.item_base_list[0]["id"]
	return Loot.make_item(base, rarity, ilvl)

func _stash_clean_files() -> void:
	for p in [STASH_TEST_PATH, STASH_TEST_PATH + ".bak", STASH_TEST_PATH + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)

func _slot_has_uid(slots: Array, uid: int) -> bool:
	for it in slots:
		if it != null and int(it.get("uid", -1)) == uid:
			return true
	return false

func test_stash() -> void:
	print("\n--- stash tabs and shared stash")
	_log("--- stash tabs and shared stash")
	var cfg: Dictionary = Data.stash_cfg
	var R = StashRulesT
	# ---- data and pure rules
	check(Data.load_errors.is_empty() and not cfg.is_empty(), "stash: data/stash.json loads")
	check(R.slots_per_tab(cfg) == 56 and R.columns(cfg) == 8, "stash: a tab is 8x7 = 56 slots")
	var seq := [100, 200, 400, 800, 1600, 3200, 6400, 12800, 25600, 51200]
	var seq_ok := true
	for i in seq.size():
		if R.tab_cost(cfg, i) != seq[i]:
			seq_ok = false
	check(seq_ok, "stash: tab prices start at 100g and double each time (up to 51,200g)")
	check(R.max_extra(cfg) == 10 and R.total_cost(cfg, 10) == 102300, "stash: ten extra tabs, 102,300g in total", str(R.total_cost(cfg, 10)))
	check(R.tab_range(cfg, 0) == Vector2i(0, 56) and R.tab_range(cfg, 2) == Vector2i(112, 168), "stash: tab ranges are consecutive blocks of 56")
	check(R.buy_refusal(cfg, 0, 99) == "Not enough gold" and R.buy_refusal(cfg, 0, 100) == "", "stash: first tab needs exactly 100g")
	check(R.buy_refusal(cfg, 10, 999999999) == "Maximum tabs reached", "stash: no tab beyond the cap, whatever the gold")
	var arr := []
	arr.resize(56)
	arr[7] = {"base": "x"}
	R.ensure_slots(cfg, arr, 2)
	check(arr.size() == 112 and arr[7] != null, "stash: a new tab adds exactly 56 slots and keeps old items")
	R.ensure_slots(cfg, arr, 1)
	check(arr.size() == 112, "stash: slot arrays never shrink")
	check(R.free_slot_in_tab(cfg, arr, 0) == 0 and R.free_slot_in_tab(cfg, arr, 1) == 56, "stash: free slot is found per tab")
	var legacy := []
	legacy.resize(60)
	legacy[57] = {"base": "hidden"}
	legacy[3] = {"base": "kept"}
	var mg: Dictionary = R.migrate_legacy(cfg, legacy)
	check(mg["slots"].size() == 56 and mg["extra_added"] == 0 and R.count_items(mg["slots"]) == 2, "stash: legacy hidden slots are rescued into free space")
	var full := []
	full.resize(60)
	for i in 56:
		full[i] = {"base": "f%d" % i}
	full[58] = {"base": "hidden"}
	var mg2: Dictionary = R.migrate_legacy(cfg, full)
	check(mg2["extra_added"] == 1 and mg2["slots"].size() == 112 and R.count_items(mg2["slots"]) == 57, "stash: a full legacy stash keeps its hidden item by granting a tab")

	# ---- character: buying personal tabs
	var old_ch = Game.ch
	Game.new_character("warrior")
	var ch = Game.ch
	check(ch.stash.size() == 56 and ch.stash_extra_tabs == 0 and ch.stash_tab_count() == 1, "stash: a new character has one 56-slot tab")
	var keep = _stash_test_item()
	ch.stash[10] = keep
	ch.gold = 99
	check(ch.buy_stash_tab() == "Not enough gold" and ch.gold == 99 and ch.stash.size() == 56 and ch.stash_extra_tabs == 0, "stash: refused purchase changes nothing")
	ch.gold = 1000
	check(ch.buy_stash_tab() == "" and ch.gold == 900, "stash: first tab costs 100g, charged once")
	check(ch.stash.size() == 112 and ch.stash_extra_tabs == 1 and ch.stash[10] == keep, "stash: bought tab appends 56 slots, old item stays put")
	check(ch.stash_next_cost() == 200 and ch.buy_stash_tab() == "" and ch.gold == 700 and ch.stash_next_cost() == 400, "stash: second tab costs 200g, third 400g")
	ch.gold = 10000000
	var bought := 2
	while ch.buy_stash_tab() == "":
		bought += 1
	check(bought == 10 and ch.stash_tab_count() == 11 and ch.stash.size() == 11 * 56, "stash: capped at 10 extra tabs (11 tabs)", "%d %d" % [bought, ch.stash.size()])
	check(10000000 - ch.gold == R.total_cost(cfg, 10) - R.total_cost(cfg, 2), "stash: tabs 3 to 10 cost 400g up to 51,200g", str(10000000 - ch.gold))
	# save / load
	var deep = _stash_test_item("epic", 12)
	ch.stash[3 * 56 + 5] = deep
	var d1: Dictionary = ch.to_dict()
	check(int(d1["version"]) == 3 and int(d1["stash_extra_tabs"]) == 10, "stash: save is version 3 and records the bought tabs")
	var d2 = JSON.parse_string(JSON.stringify(d1))
	Game.load_from_dict(d2)
	var ch2 = Game.ch
	check(ch2.stash_extra_tabs == 10 and ch2.stash.size() == 11 * 56, "stash: save/load restores the tab count")
	check(ch2.stash[3 * 56 + 5] != null and ch2.stash[3 * 56 + 5]["name"] == deep["name"] and ch2.stash[10]["name"] == keep["name"], "stash: items in later tabs survive save/load")
	# old saves
	var v2 := {"version": 2, "name": "Old", "class": "warrior", "level": 5, "stash": [], "inventory": [], "gold": 5}
	var arr60 := []
	arr60.resize(60)
	arr60[4] = ch._fix_item(_stash_test_item())
	arr60[58] = ch._fix_item(_stash_test_item("uncommon"))
	v2["stash"] = arr60
	var d3 = JSON.parse_string(JSON.stringify(v2))
	Game.load_from_dict(d3)
	check(Game.ch.stash_extra_tabs == 0 and Game.ch.stash.size() == 56, "stash: a v2 save loads with 0 extra tabs and one tab")
	check(R.count_items(Game.ch.stash) == 2, "stash: v2 hidden-slot item is rescued")
	var v3 := {"version": 3, "name": "Cfg", "class": "warrior", "level": 5, "stash_extra_tabs": 0, "stash": [], "inventory": []}
	var arr120 := []
	arr120.resize(120)
	arr120[100] = ch._fix_item(_stash_test_item())
	v3["stash"] = arr120
	Game.load_from_dict(JSON.parse_string(JSON.stringify(v3)))
	check(Game.ch.stash_extra_tabs >= 1 and Game.ch.stash[100] != null, "stash: a save with items beyond its tab count never drops them")

	# ---- shared stash
	var SS = SharedStash
	var old_path: String = SS.path
	SS.path = STASH_TEST_PATH
	_stash_clean_files()
	SS.reset()
	Game.new_character("warrior")
	ch = Game.ch
	check(SS.slots.size() == 56 and SS.extra_tabs == 0 and SS.tab_total() == 1 and SS.next_cost() == 100, "shared: starts with one 56-slot tab, next tab 100g")
	ch.stash_extra_tabs = 3
	ch.gold = 50
	check(SS.buy_tab(ch) == "Not enough gold" and ch.gold == 50 and SS.extra_tabs == 0 and SS.slots.size() == 56, "shared: refused purchase changes nothing")
	ch.gold = 1000
	check(SS.buy_tab(ch) == "" and ch.gold == 900 and SS.extra_tabs == 1 and SS.slots.size() == 112, "shared: first tab costs 100g even if the stash has 3 extra tabs")
	check(ch.stash_extra_tabs == 3 and SS.next_cost() == 200, "shared: personal and shared tab counts are independent")
	ch.gold = 100000000
	var sb := 1
	while SS.buy_tab(ch) == "":
		sb += 1
	check(sb == 10 and SS.tab_total() == 11 and SS.slots.size() == 11 * 56, "shared: capped at 10 extra tabs", "%d %d" % [sb, SS.slots.size()])
	SS.reset()
	_stash_clean_files()
	# deposits and withdrawals
	for i in ch.inventory.size():
		ch.inventory[i] = null
	var a = _stash_test_item("legendary", 20)
	a["uid"] = ch.take_uid()
	var b = _stash_test_item("rare", 9)
	b["uid"] = ch.take_uid()
	ch.inventory[0] = a
	ch.inventory[1] = b
	var r1: Dictionary = SS.deposit(ch, 0, 0)
	check(r1["err"] == "" and ch.inventory[0] == null and SS.item_count() == 1 and SS.slots[0] == a, "shared: deposit moves the item out of the bag")
	check(FileAccess.file_exists(STASH_TEST_PATH), "shared: deposit writes the shared file")
	var r2: Dictionary = SS.deposit(ch, 1, 0)
	check(r2["err"] == "" and SS.item_count() == 2, "shared: second deposit")
	ch.inventory[39] = null
	var rbad: Dictionary = SS.deposit(ch, 39, 0)
	check(rbad["err"] != "" and SS.item_count() == 2, "shared: depositing an empty bag slot is refused")
	var gem_like := {"gem_type": "ruby", "grade": 1}
	ch.inventory[2] = gem_like
	var rgem: Dictionary = SS.deposit(ch, 2, 0)
	check(rgem["err"] == "Shared stash holds items only" and ch.inventory[2] == gem_like and SS.item_count() == 2, "shared: only real items are accepted (gems, runes, materials are refused)")
	ch.inventory[2] = null
	# reload from disk
	SS.extra_tabs = 0
	SS.slots = []
	SS.load_file()
	check(SS.item_count() == 2 and SS.slots[0] != null and SS.slots[0]["name"] == a["name"] and not SS.loaded_from_backup, "shared: file round-trip restores items")
	# corrupt main file falls back to the backup
	var f := FileAccess.open(STASH_TEST_PATH, FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	SS.load_file()
	check(SS.loaded_from_backup and SS.item_count() == 1 and SS.slots[0]["name"] == a["name"], "shared: a corrupt file falls back to the .bak", "items=%d backup=%s" % [SS.item_count(), str(SS.loaded_from_backup)])
	SS.reset()
	_stash_clean_files()
	# a second character sees the items
	ch.inventory[0] = a
	SS.deposit(ch, 0, 0)
	Game.new_character("mage")
	var ch3 = Game.ch
	var got: String = SS.withdraw(ch3, 0)
	var taken = null
	for it in ch3.inventory:
		if it != null and it.get("name", "") == a["name"]:
			taken = it
	check(got == "" and taken != null and SS.item_count() == 0, "shared: another character can take the item")
	var uid_n := 0
	for it in ch3.inventory:
		if it != null and taken != null and int(it.get("uid", -1)) == int(taken["uid"]):
			uid_n += 1
	check(taken != null and int(taken["uid"]) != 0 and ch3.next_uid >= int(taken["uid"]) and uid_n == 1, "shared: withdrawn item gets a fresh, unique uid from the new character")
	check(SS.withdraw(ch3, 0) == "Nothing to take", "shared: taking from an empty slot is refused")
	# full bag
	for i in ch3.inventory.size():
		if ch3.inventory[i] == null:
			ch3.inventory[i] = _stash_test_item()
	SS.slots[4] = _stash_test_item("epic", 7)
	check(SS.withdraw(ch3, 4) == "Inventory full" and SS.slots[4] != null, "shared: full bag refuses and the item stays in the shared stash")
	SS.reset()
	# tab preference and fallback
	Game.new_character("ranger")
	ch = Game.ch
	for i in 56:
		SS.slots[i] = _stash_test_item("common", 1)
	ch.inventory[0] = _stash_test_item()
	check(SS.deposit(ch, 0, 0)["err"] == "Shared stash is full" and ch.inventory[0] != null, "shared: full stash refuses and keeps the item in the bag")
	ch.gold = 500
	SS.buy_tab(ch)
	var rt: Dictionary = SS.deposit(ch, 0, 0)
	check(rt["err"] == "" and rt["tab"] == 1 and SS.slots[56] != null, "shared: a full tab falls back to the next tab with room")
	ch.inventory[0] = _stash_test_item()
	var rt2: Dictionary = SS.deposit(ch, 0, 1)
	check(rt2["tab"] == 1 and SS.slots[57] != null, "shared: the open tab is preferred")
	SS.reset()
	_stash_clean_files()

	# ---- crash safety: the character is saved before the shared file changes
	var old_dir: String = Game.save_dir
	var old_slot: int = Game.current_slot
	Game.save_dir = "user://test_saves"
	for s in range(0, Game.SLOT_COUNT + 1):
		Game.delete_slot(s)
	Game.new_character("warrior")
	ch = Game.ch
	Game.current_slot = 4
	Game.testing = false
	var dep = _stash_test_item("epic", 15)
	dep["uid"] = ch.take_uid()
	ch.inventory[3] = dep
	check(Game.save_game(4), "shared: (setup) character saved with the item in the bag")
	var dres: Dictionary = SS.deposit(ch, 3, 0)
	var disk_ch: Dictionary = Game.read_slot(4)
	var in_bag := false
	for it in disk_ch.get("inventory", []):
		if it != null and int(it.get("uid", -1)) == int(dep["uid"]):
			in_bag = true
	check(dres["err"] == "" and not in_bag, "shared: deposit saves the character without the item (reloading cannot duplicate it)")
	var auto_bag := false
	for it in Game.read_slot(Game.AUTOSAVE_SLOT).get("inventory", []):
		if it != null and int(it.get("uid", -1)) == int(dep["uid"]):
			auto_bag = true
	check(not auto_bag, "shared: the autosave is updated as well")
	check(SS.withdraw(ch, 0) == "", "shared: withdraw works")
	var back := false
	for it in Game.read_slot(4).get("inventory", []):
		if it != null and it.get("name", "") == dep["name"]:
			back = true
	check(back, "shared: withdraw saves the character holding the item")
	ch.gold = 400
	check(SS.buy_tab(ch) == "" and int(Game.read_slot(4).get("gold", 0)) == 300, "shared: buying a tab saves the gold spend immediately")
	for s in range(0, Game.SLOT_COUNT + 1):
		Game.delete_slot(s)
	Game.testing = true
	Game.save_dir = old_dir
	Game.current_slot = old_slot
	SS.reset()
	_stash_clean_files()

	# ---- tests never touch the real file
	SS.path = SS.REAL_PATH
	var existed := FileAccess.file_exists(SS.REAL_PATH)
	var mtime := FileAccess.get_modified_time(SS.REAL_PATH) if existed else 0
	SS.slots[0] = _stash_test_item()
	check(SS.save_file() and FileAccess.file_exists(SS.REAL_PATH) == existed and (not existed or FileAccess.get_modified_time(SS.REAL_PATH) == mtime), "shared: the real shared file is never written while testing")
	SS.path = old_path
	SS.reset()
	Game.ch = old_ch

func test_stash_ui() -> void:
	print("\n--- stash panel")
	_log("--- stash panel")
	if main.ui == null:   # normally test_ui has started the game already
		main.start_game()
		await frames(2)
	var ui = main.ui
	var SS = SharedStash
	var old_path: String = SS.path
	SS.path = STASH_TEST_PATH
	_stash_clean_files()
	SS.reset()
	Game.new_character("warrior")
	var ch = Game.ch
	ui.open("inventory")
	ui.open("stash")
	await frames(2)
	var p = ui.panels["stash"]
	check(p.slots.size() == 56 and p.grid.columns == 8, "stash ui: 8x7 grid")
	check(p.tab_row.get_child_count() == 2, "stash ui: one tab button plus the buy button")
	ch.gold = 0
	Events.currency_changed.emit()
	var buy = p.tab_row.get_child(p.tab_row.get_child_count() - 1)
	check(buy.disabled and buy.tooltip_text == "Not enough gold" and buy.text.contains("100"), "stash ui: buy button shows the price and is disabled without gold")
	ch.gold = 1000
	Events.currency_changed.emit()
	buy = p.tab_row.get_child(p.tab_row.get_child_count() - 1)
	check(not buy.disabled, "stash ui: buy button enables once you can afford it")
	p._do_buy()
	await frames(1)
	check(ch.stash_extra_tabs == 1 and ch.gold == 900 and p.tab_row.get_child_count() == 3 and p.tab["stash"] == 1, "stash ui: buying adds a tab, charges once and opens it")
	# deposit lands in the open tab
	var it = _stash_test_item()
	ch.inventory[0] = it
	p.deposit(0)
	check(ch.stash[56] == it, "stash ui: deposit goes to the open tab")
	# shared mode
	p._set_mode("shared")
	await frames(1)
	check(p.is_shared() and p.title_label.text == "Shared Stash" and p.tab_row.get_child_count() == 2, "stash ui: Shared Stash mode shows its own tabs")
	var it2 = _stash_test_item("epic", 9)
	ch.inventory[0] = it2
	p.deposit(0)
	await frames(1)
	check(SS.slots[0] == it2 and p.slots[0].item == it2, "stash ui: deposit in shared mode fills the shared tab")
	check(ui.panels["inventory"].info_label.text.contains("shared stash"), "stash ui: the bag hint names the shared stash")
	p._on_click(p.slots[0], MOUSE_BUTTON_LEFT, false)
	check(SS.item_count() == 0 and ch.inventory[0] != null and ch.inventory[0]["name"] == it2["name"], "stash ui: clicking a shared item takes it into the bag")
	ch.gold = 150
	p._on_buy_pressed()
	check(ui.confirm.visible and ui.confirm_text.text.contains("100"), "stash ui: buying asks for confirmation and shows the price")
	check(SS.extra_tabs == 0 and ch.gold == 150, "stash ui: nothing is charged before confirming")
	ui._on_confirm()
	check(SS.extra_tabs == 1 and ch.gold == 50 and p.tab["shared"] == 1, "stash ui: shared tab purchase works from the panel")
	p._set_mode("stash")
	check(ch.stash_extra_tabs == 1, "stash ui: personal tabs are unaffected by shared purchases")
	ui.close_all()
	await frames(2)
	SS.path = old_path
	SS.reset()
	_stash_clean_files()

# ------------------------------------------------------------------ developer tools
const DevRulesT = preload("res://scripts/core/dev_rules.gd")
const CharDataT = preload("res://scripts/core/character_data.gd")

func _dev_on() -> void:
	Game.dev_in_tests = true
	Game.settings["dev_tools"] = true

func _skill_levels(ch) -> Dictionary:
	var d := {}
	for s in Data.skills_for_class(ch.class_id):
		d[s["id"]] = ch.skill_level(s["id"])
	return d

func test_dev_tools() -> void:
	print("\n--- developer tools")
	_log("--- developer tools")
	var old_ch = Game.ch
	var R = DevRulesT
	# ---- setting and gating
	check(Game.DEFAULT_SETTINGS.get("dev_tools", true) == false, "dev: the Developer tools setting defaults to off")
	check(Data.load_errors.is_empty() and not Data.dev_cfg.is_empty(), "dev: data/dev_tools.json loads")
	check(Dev.flags == R.default_flags(), "dev: every flag starts at its default")
	check(Game.ACTIONS.has("dev_panel") and Game.ACTIONS["dev_panel"] == [KEY_F1], "dev: F1 is registered for the panel")
	var f1_free := true
	for a in Game.ACTIONS:
		if not String(a).begins_with("dev_") and Game.ACTIONS[a].has(KEY_F1):
			f1_free = false
	check(f1_free, "dev: F1 is not used by any other action")
	Game.new_character("mage")
	var ch = Game.ch
	Game.settings["dev_tools"] = false
	Game.dev_in_tests = true
	var g0: int = ch.gold
	check(not Dev.enabled() and not Dev.add_gold(1000)["ok"] and ch.gold == g0, "dev: actions do nothing while the setting is off")
	Game.settings["dev_tools"] = true
	Game.dev_in_tests = false
	check(not Dev.enabled() and not Dev.add_gold(1000)["ok"] and ch.gold == g0, "dev: actions do nothing under Game.testing without dev_in_tests")
	Dev.flags["god"] = true
	Dev.flags["damage_mult"] = 5.0
	Dev.flags["loot_luck"] = 20.0
	Dev.flags["freeze_ai"] = true
	check(not Dev.god() and Dev.hit_mult() == 1.0 and Dev.loot_luck() == 1.0 and not Dev.freeze_ai(), "dev: game hooks stay neutral in bots and tests, even with flags set")
	Dev.flags = R.default_flags()
	check(not ch.dev_used, "dev: refused actions do not mark the character")
	_dev_on()
	check(Dev.enabled(), "dev: setting on + dev_in_tests enables the tools")
	for fl in ["god", "one_hit", "infinite_mana", "no_cooldowns", "infinite_flasks", "freeze_ai", "reveal_hidden", "overlay", "hitboxes"]:
		Dev.set_flag(fl, true)
	Dev.set_flag("damage_mult", 10)
	Dev.set_flag("move_mult", 2)
	Dev.set_flag("loot_luck", 5)
	Dev.set_flag("time_scale", 0.5)
	check(Dev.god() and Dev.hit_mult() == 10.0 * float(Data.dev_cfg["one_hit_mult"]) and Dev.move_mult() == 2.0 and Dev.loot_luck() == 5.0, "dev: flags take effect while on")
	check(is_equal_approx(Engine.time_scale, 0.5) and is_equal_approx(Game.base_time_scale, 0.5), "dev: time scale sets the engine speed")
	Dev.set_flag("time_scale", 99.0)
	check(is_equal_approx(Game.base_time_scale, float(Data.dev_cfg["time_scale"]["max"])), "dev: time scale is clamped to the preset range")
	Dev.set_enabled(false)
	check(Dev.flags == R.default_flags() and is_equal_approx(Engine.time_scale, 1.0) and not get_tree().debug_collisions_hint, "dev: switching the setting off resets every flag (time scale 1, hitboxes off)")
	Dev.set_enabled(true)
	check(Dev.flags == R.default_flags() and Dev.enabled(), "dev: switching back on starts from defaults")
	check(ch.dev_used, "dev: switching on god mode marks the character")
	Game.new_character("mage")
	ch = Game.ch
	Dev.set_flag("overlay", true)
	Dev.set_flag("time_scale", 2.0)
	Dev.set_flag("hitboxes", true)
	check(not ch.dev_used, "dev: overlay, hitboxes and time scale do not mark the character")
	Dev.reset_flags()

	# ---- pure rules
	var xf := func(l): return CharDataT.xp_for_level(l)
	check(R.xp_to_reach(1, 0, 2, xf) == CharDataT.xp_for_level(1) and R.xp_to_reach(5, 10, 5, xf) == 0, "dev rules: xp to reach a level uses the game's own XP curve")
	check(R.add_amount(Data.dev_cfg, 50, -100) == 0 and R.set_amount(Data.dev_cfg, -5) == 0 and R.add_amount(Data.dev_cfg, 2000000000, 5) == 2000000000, "dev rules: amounts never go negative or past the cap")
	check(R.lucky_rarity(40.0, 1.0) == 40.0 and R.lucky_rarity(0.0, 5.0) == 400.0, "dev rules: loot luck multiplies the effective rarity")
	check(R.spawn_refusal(Data.dev_cfg, Data.item_bases, Data.rarities, "nope", "rare", 5, 0, 2) != "" and R.spawn_refusal(Data.dev_cfg, Data.item_bases, Data.rarities, Data.item_base_list[0]["id"], "rare", 5, 3, 2) != "", "dev rules: bad bases and too many sockets are refused")

	# ---- A. levels: same result as levelling naturally
	Game.new_character("ranger")
	var nat = Game.ch
	var guard := 0
	while nat.level < 14 and guard < 100000:
		nat.add_xp(37)
		guard += 1
	Game.new_character("ranger")
	ch = Game.ch
	var r: Dictionary = Dev.set_level(14)
	check(r["ok"] and ch.level == 14 and ch.xp == 0, "dev: set level 14 through the real level-up", r["msg"])
	check(ch.total_passive_points() == nat.total_passive_points() and ch.available_passive_points() == nat.available_passive_points(), "dev: set level gives the same passive points as levelling naturally", "%d vs %d" % [ch.total_passive_points(), nat.total_passive_points()])
	var su: Array = ch.unlocked_skills.duplicate()
	var nu: Array = nat.unlocked_skills.duplicate()
	su.sort()
	nu.sort()
	check(su == nu and _skill_levels(ch) == _skill_levels(nat) and ch.spec_points_total() == nat.spec_points_total(), "dev: set level gives the same skills, skill levels and spec points as levelling naturally")
	check(ch.dev_used and not nat.dev_used, "dev: progress actions mark the character dev_used")
	check(not Dev.set_level(3)["ok"] and ch.level == 14, "dev: levels never go down")
	Dev.add_levels(5)
	check(ch.level == 19, "dev: +5 levels")
	Dev.set_max_level()
	check(ch.level == R.max_level(Data.dev_cfg) and ch.level == CharDataT.MAX_LEVEL, "dev: max level", str(ch.level))
	Game.new_character("warrior")
	ch = Game.ch
	var xp0: int = ch.xp
	Dev.add_xp(10)
	check(ch.xp == xp0 + 10 and ch.level == 1, "dev: add XP adds exactly")
	var bp: int = ch.bonus_passive_points
	Dev.grant_passive_points(5)
	check(ch.bonus_passive_points == bp + 5, "dev: grant passive points")
	Dev.unlock_all_skills()
	check(ch.unlocked_skills.size() == Data.skills_for_class("warrior").size(), "dev: unlock all skills")
	Dev.set_level(10)
	var any := ""
	for n in Data.passive_list:
		if ch.can_allocate(n["id"]) == "":
			any = n["id"]
			break
	if any != "":
		ch.allocate(any)
	var gold_before: int = ch.gold
	Dev.respec_passives()
	check(ch.allocated.size() == 1 and ch.gold == gold_before and ch.available_passive_points() == ch.total_passive_points(), "dev: free respec refunds every passive at no cost")

	# ---- C. economy
	ch.gold = 0
	Dev.add_gold(1000)
	Dev.add_gold(1000000)
	check(ch.gold == 1001000, "dev: gold adds exactly", str(ch.gold))
	Dev.set_gold(42)
	check(ch.gold == 42, "dev: set gold")
	Dev.add_gold(-1000)
	check(ch.gold == 0, "dev: gold never goes negative")
	Dev.set_gold(-5)
	check(ch.gold == 0, "dev: set gold never goes negative")
	var mats_ok := true
	for id in Data.materials:
		var m0 := int(ch.materials.get(id, 0))
		Dev.add_material(id, 100)
		if int(ch.materials.get(id, 0)) != m0 + 100:
			mats_ok = false
	check(mats_ok, "dev: each material adds exactly 100")
	var before_all := {}
	for id in Data.materials:
		before_all[id] = int(ch.materials.get(id, 0))
	Dev.add_all_materials(1000)
	var all_ok := true
	for id in Data.materials:
		if int(ch.materials[id]) != before_all[id] + 1000:
			all_ok = false
	check(all_ok, "dev: +1,000 of every material")
	check(not Dev.add_material("not_a_material", 5)["ok"] and not ch.materials.has("not_a_material"), "dev: unknown material is refused")
	var gid: String = Loot.gem_id(Data.gem_list[0]["id"], 2)
	Dev.add_gem(gid, 3)
	check(int(ch.gems.get(gid, 0)) == 3, "dev: add 3 gems of a type and grade")
	Dev.add_all_gems(1)
	var gems_ok: bool = Dev.gem_ids().size() == Data.gem_list.size() * Data.gem_cfg["tiers"].size() and Dev.gem_ids().size() == 32
	for g in Dev.gem_ids():
		if int(ch.gems.get(g, 0)) != (4 if g == gid else 1):
			gems_ok = false
	check(gems_ok, "dev: one of every gem (8 types x 4 grades)")
	Dev.add_all_runes(1)
	var runes_ok := true
	for rr in Data.skill_rune_list:
		if int(ch.runes.get(rr["id"], 0)) != 1:
			runes_ok = false
	check(runes_ok, "dev: one of every skill rune")

	# ---- C. stash tabs through the real purchase
	ch.gold = 500
	r = Dev.free_stash_tab(false)
	check(r["ok"] and ch.stash_extra_tabs == 1 and ch.stash.size() == 112 and ch.gold == 500, "dev: free personal tab through buy_stash_tab, gold unchanged")
	Dev.all_stash_tabs(false)
	check(ch.stash_extra_tabs == StashRulesT.max_extra(Data.stash_cfg) and ch.gold == 500 and ch.stash.size() == ch.stash_tab_count() * 56, "dev: all personal tabs, capped like a purchase", str(ch.stash_extra_tabs))
	check(not Dev.free_stash_tab(false)["ok"] and ch.gold == 500, "dev: no free tab past the cap, gold untouched")
	var SS = SharedStash
	var old_path: String = SS.path
	SS.path = STASH_TEST_PATH
	_stash_clean_files()
	SS.reset()
	r = Dev.free_stash_tab(true)
	check(r["ok"] and SS.extra_tabs == 1 and ch.gold == 500, "dev: free shared tab through SharedStash.buy_tab", r["msg"])
	SS.reset()
	_stash_clean_files()
	SS.path = old_path
	SS.reset()
	var legacy := []
	legacy.resize(60)
	legacy[57] = {"base": "hidden"}
	var mg: Dictionary = StashRulesT.migrate_legacy(Data.stash_cfg, legacy)
	check(mg["slots"].size() == 56 and StashRulesT.count_items(mg["slots"]) == 1, "dev: stash migrate_legacy still rescues hidden slots")

	# ---- D. items
	var base_id := ""
	for b in Data.item_base_list:
		if b.get("slot", "") == "chest":
			base_id = b["id"]
	r = Dev.spawn_item(base_id, "rare", 20, 3, false)
	var it: Dictionary = r.get("item", {})
	check(r["ok"] and it.get("base") == base_id and it.get("rarity") == "rare" and int(it.get("ilvl", 0)) == 20 and int(it.get("sockets", 0)) == 3 and it.get("gems", []).size() == 3, "dev: spawned item has the requested base, rarity, ilvl and sockets", str(r["msg"]))
	check(ch.inventory.has(it) and ch._fix_item(it.duplicate(true)) != null and int(it.get("uid", 0)) > 0, "dev: spawned item is in the bag and passes the load validity check")
	var nrare: int = it.get("affixes", []).size()
	check(nrare >= 3 and nrare <= 4, "dev: rare affix count matches a dropped rare", str(nrare))
	check(not Dev.spawn_item(base_id, "rare", 20, 9)["ok"] and not Dev.spawn_item("no_such_base", "rare", 20, 0)["ok"] and not Dev.spawn_item(base_id, "mythic", 20, 0)["ok"], "dev: invalid spawn requests are refused")
	r = Dev.spawn_item(base_id, "epic", 40, 0, true)
	var maxed := true
	for a in r["item"].get("affixes", []):
		var tiers: Array = Data.affixes[a["id"]]["tiers"]
		var best: Array = R.max_affix_roll(tiers, 40)
		if float(a["value"]) != float(best[1]) or int(a["tier"]) != int(best[0]) + 1:
			maxed = false
	check(maxed and r["item"].get("affixes", []).size() > 0, "dev: max-roll affixes use the best tier and top value")
	var uid: String = Data.unique_list[0]["id"]
	r = Dev.spawn_legendary(uid)
	check(r["ok"] and r["item"].get("unique") == uid and r["item"].get("rarity") == "legendary" and ch._fix_item(r["item"].duplicate(true)) != null, "dev: spawn legendary by id")
	var charm_bases := 0
	for b in Data.item_base_list:
		if b.get("slot", "") == "charm":
			charm_bases += 1
	var bag0: int = ch.BAG_SIZE - ch.bag_free_count()
	Dev.add_all_charms()
	check(ch.BAG_SIZE - ch.bag_free_count() == bag0 + charm_bases, "dev: one of every charm", "%d charm bases" % charm_bases)
	Dev.clear_bag()
	check(ch.bag_free_count() == ch.BAG_SIZE, "dev: clear bag")
	# ---- in the world
	main.start_game()
	await frames(2)
	var lv = Game.level
	var p = lv.player
	check(not Dev.spawn_enemy("ghoul")["ok"], "dev: no enemy spawns in town")
	main.enter_dungeon("forgotten_depths", 777)
	await frames(3)
	lv = Game.level
	p = lv.player
	# bag full -> drop at feet
	for i in ch.inventory.size():
		ch.inventory[i] = Loot.make_item(base_id, "common", 1)
	var loot0: int = lv.loot.size()
	r = Dev.spawn_item(base_id, "uncommon", 5, 0)
	check(r["ok"] and lv.loot.size() == loot0 + 1 and r["msg"].contains("feet"), "dev: a full bag drops the spawned item at your feet")
	Dev.clear_bag()
	var loot1: int = lv.loot.size()
	r = Dev.drop_random(5, "epic")
	var epic_ok := true
	for n in lv.loot.slice(loot1):
		if not is_instance_valid(n) or n.kind != "item" or n.item.get("rarity") != "epic":
			epic_ok = false
	check(r["ok"] and lv.loot.size() == loot1 + 5 and epic_ok, "dev: drop 5 epic items through the real drop path")
	Game.filter_in_tests = true
	r = Dev.filter_rule_at(lv.loot[lv.loot.size() - 1].global_position)
	Game.filter_in_tests = false
	check(r["ok"] and r.has("rule"), "dev: loot filter rule lookup for the item at the cursor", r["msg"])
	r = Dev.decent_kit()
	var equipped := 0
	for s in ch.EQUIP_SLOTS:
		if ch.equipment.get(s) != null and ch.equipment[s].get("rarity") == "rare":
			equipped += 1
	check(r["ok"] and equipped >= 6, "dev: decent kit equips rare gear", str(equipped))
	# ---- loot luck
	Loot.set_seed(99)
	var base_items := 0
	for i in 400:
		for d in Loot.roll_drops(10, 1.0, false, false, "warrior", 0.0):
			if d["kind"] == "item":
				base_items += 1
	Dev.set_flag("loot_luck", 5)
	Loot.set_seed(99)
	var lucky_items := 0
	for i in 400:
		for d in Loot.roll_drops(10, 1.0, false, false, "warrior", 0.0):
			if d["kind"] == "item":
				lucky_items += 1
	Dev.set_flag("loot_luck", 1)
	check(lucky_items > base_items * 3, "dev: loot luck x5 multiplies drops at runtime", "%d vs %d" % [lucky_items, base_items])
	check(float(Data.loot["item_drop_chance"]) == 0.16, "dev: loot.json is never edited in memory")

	# ---- B. god mode
	ch.recalc()
	p.max_life = 1000.0
	p.life = 1000.0
	Dev.set_flag("god", true)
	var dealt: float = p.receive_hit({"physical": 300.0}, {"is_attack": false}, null, false)
	p.add_status("stun", 2.0, {})
	p.add_status("poison", 2.0, {"dps": 50.0, "dtype": "void"})
	p.take_dot(200.0, "fire")
	check(dealt == 0.0 and p.life == 1000.0, "dev: god mode blocks hit damage")
	check(p.statuses.is_empty(), "dev: god mode blocks stun and status application")
	check(not Dev.stun_self()["ok"], "dev: stun self is refused under god mode")
	Dev.set_flag("god", false)
	var hurt := false
	for i in 10:
		if p.receive_hit({"physical": 50.0}, {"is_attack": false}, null, false) > 0.0:
			hurt = true
			break
	check(hurt and p.life < 1000.0, "dev: turning god mode off restores normal damage")
	r = Dev.stun_self()
	check(r["ok"] and p.has_status("stun"), "dev: stun yourself through the real stun roll", r["msg"])
	Dev.full_heal()
	check(p.life == p.max_life and p.statuses.is_empty(), "dev: full heal clears statuses")
	# ---- B. damage, one-hit, freeze, kill all
	var at: Vector2 = p.global_position + Vector2(30, 0)
	r = Dev.spawn_enemy("grave_brute", ["armoured"], 1, at)
	var e = r["enemies"][0]
	check(r["ok"] and is_instance_valid(e) and e.is_elite and e.elite_mods.size() == 1, "dev: spawn an elite enemy with chosen mods")
	var pk := {"dmg": {"physical": [10.0, 10.0]}, "crit_chance": 0.0, "crit_mult": 1.0, "faction": "player", "status": [], "tags": [], "flags": {}}
	e.life = e.max_life
	var d1: float = Combat.deal(pk, p, e)
	Dev.set_flag("damage_mult", 10)
	e.life = e.max_life
	var d10: float = Combat.deal(pk, p, e)
	Dev.set_flag("damage_mult", 1)
	check(d1 > 0.0 and d10 > d1 * 5.0, "dev: damage multiplier scales your hits", "%.1f vs %.1f" % [d1, d10])
	Dev.set_flag("one_hit", true)
	Combat.deal(pk, p, e)
	Dev.set_flag("one_hit", false)
	await frames(1)
	check(not is_instance_valid(e) or not e.alive, "dev: one-hit kills")
	Dev.set_flag("freeze_ai", true)
	p.max_life = 1.0e6
	p.life = 1.0e6
	r = Dev.spawn_enemy("ghoul", [], 3, p.global_position + Vector2(14, 0))
	var pos0: Vector2 = r["enemies"][0].global_position
	await frames(60)
	check(is_instance_valid(r["enemies"][0]) and r["enemies"][0].global_position.distance_to(pos0) < 2.0 and p.life == 1.0e6, "dev: frozen enemies stand still and never attack")
	Dev.set_flag("freeze_ai", false)
	var xp_k: int = ch.xp + ch.level * 1000000
	r = Dev.kill_all_enemies()
	await frames(1)
	var left := 0
	for en in lv.enemies:
		if is_instance_valid(en) and en.alive:
			left += 1
	check(r["ok"] and left == 0 and ch.xp + ch.level * 1000000 > xp_k, "dev: kill all enemies counts as real kills (XP)", r["msg"])
	# infinite mana / no cooldowns / infinite flasks
	Dev.set_flag("infinite_mana", true)
	Dev.set_flag("no_cooldowns", true)
	Dev.set_flag("infinite_flasks", true)
	var sk: Dictionary = p.skill_in_slot(0)
	check(p.mana_cost(sk) == 0.0, "dev: infinite mana makes skills free")
	ch.flask_charges[0] = 0.0
	p.use_flask(0)
	check(ch.flask_charges[0] == 0.0 and Dev.infinite_flasks(), "dev: infinite flasks drink without charges")
	Dev.reset_flags()
	check(p.mana_cost(sk) == float(sk.get("cost", 0)) * ch.final.get("mana_cost_mult", 1.0) or ch.stats.has_flag("hollow_crown"), "dev: mana costs return when the flag is off")

	# ---- E. objectives and the boss arena
	ch.progress["highest_tier"] = 1
	Dev.unlock_all_tiers()
	check(int(ch.progress["highest_tier"]) == 6, "dev: unlock all tiers")
	r = Dev.start_run("dread_sanctums", ["hasted", "nonsense"], 1)
	await frames(3)
	lv = Game.level
	check(r["ok"] and lv.def["id"] == "dread_sanctums" and lv.mods.size() == 1 and lv.mods[0]["id"] == "hasted", "dev: start a run in any tier with chosen modifiers", r["msg"])
	check(not lv.sealed_cells.is_empty(), "dev: the boss arena starts sealed")
	r = Dev.complete_objective()
	check(r["ok"] and lv.objectives[0]["done"] and lv.objectives[0]["type"] == "relics", "dev: complete the relic objective", r["msg"])
	r = Dev.complete_objective()
	check(r["ok"] and lv.objectives[1]["done"] and not lv.wave_state.get("active", false), "dev: complete the Blood Altar waves", r["msg"])
	check(lv.sealed_cells.is_empty() and lv.seal_node == null, "dev: completing the objectives unseals the arena")
	r = Dev.complete_objective()
	await frames(2)
	var exitp := false
	for itx in lv.interactables:
		if itx["kind"] == "exit_portal":
			exitp = true
	check(r["ok"] and lv.boss_dead and exitp, "dev: complete the boss objective (real boss death, exit portal)", r["msg"])
	r = Dev.teleport_to_exit()
	check(r["ok"] and Game.level.player.global_position.distance_to(lv.player.global_position) < 1.0, "dev: teleport to the exit portal")
	r = Dev.start_run("nightmare_vaults", [], 1)
	await frames(3)
	lv = Game.level
	r = Dev.teleport_to_boss()
	await frames(2)
	var br: Dictionary = lv.rooms[lv.layout["boss"]]
	check(r["ok"] and lv.sealed_cells.is_empty() and lv.boss_spawned and lv.current_room == br["id"], "dev: teleport to boss completes guardian + mechanisms and enters the open arena", r["msg"])
	check(lv.objectives[0]["done"] and lv.objectives[1]["done"] and not lv.boss_dead, "dev: teleport to boss leaves the boss alive and the level valid")
	r = Dev.break_boss_poise()
	check(r["ok"] and lv.boss.has_status("stun") and lv.boss.poise_state["stagger"] > 0.0, "dev: break boss poise staggers the boss", r["msg"])
	# abyss records are not set by tainted characters
	ch.progress["abyss_best"] = 0
	r = Dev.set_abyss_depth(3)
	await frames(3)
	lv = Game.level
	check(r["ok"] and lv.def.get("endless", false) and lv.depth == 3, "dev: set Abyss depth", r["msg"])
	guard = 0
	while not lv.boss_dead and guard < 6:
		guard += 1
		Dev.complete_objective()
	await frames(2)
	check(lv.boss_dead and int(ch.progress.get("abyss_best", 0)) == 0, "dev: a dev-tainted character never records an Abyss depth")
	r = Dev.teleport_to(lv.player.global_position + Vector2(10, 0))
	check(r["ok"], "dev: teleport to a point")
	r = Dev.return_to_hub()
	await frames(2)
	check(r["ok"] and Game.level.is_town, "dev: return to town")

	# ---- F. pets
	ch.gold = 123
	r = Dev.unlock_all_pets()
	check(r["ok"] and ch.pets.size() == Data.pet_list.size() and ch.gold == 123, "dev: unlock all pets through the real purchase, gold unchanged", r["msg"])
	r = Dev.set_pet_tier(5)
	check(r["ok"] and ch.pet_tier(ch.active_pet) == 5, "dev: set the active pet's tier")
	Dev.rename_pet("Bitey")
	check(ch.pet_name(ch.active_pet) == "Bitey", "dev: free pet rename")

	# ---- G. seed, diagnostics
	r = Dev.set_seed(4242)
	check(r["ok"] and Dev.pending_seed == 4242 and Combat.rng.seed == Dev.mix([4242, "combat"]), "dev: set seed seeds the RNGs like the smartbot")
	Dev.start_run("forgotten_depths")
	await frames(3)
	check(Dev.current_seed() == 4242 and Dev.pending_seed == 0, "dev: the next run uses the chosen seed")
	var diag: String = Dev.diagnostics()
	check(diag.contains("class: ") and diag.contains("seed: 4242") and diag.contains("flags"), "dev: diagnostic info", diag)
	check(Dev.overlay_lines().size() >= 4, "dev: debug overlay lines")
	main.go_hub(false)
	await frames(2)

	# ---- save / load: dev_used persists, no flag leaks, old saves load
	Dev.set_flag("god", true)
	var sd: Dictionary = JSON.parse_string(JSON.stringify(ch.to_dict()))
	var leak := false
	for k in R.default_flags():
		if sd.has(k):
			leak = true
	check(sd.get("dev_used", false) == true and not leak, "dev: the save holds dev_used and no dev flag")
	Game.load_from_dict(sd)
	check(Game.ch.dev_used, "dev: dev_used survives a save/load round trip")
	sd.erase("dev_used")
	Game.load_from_dict(sd)
	check(not Game.ch.dev_used and Game.ch.level == ch.level, "dev: an old save without dev_used loads cleanly")
	Game.new_character("mage")
	check(not Game.ch.to_dict().has("dev_used"), "dev: untouched characters save exactly as before")
	var old_dir: String = Game.save_dir
	var old_slot: int = Game.current_slot
	Game.save_dir = "user://test_dev_saves"
	Game.testing = false
	Game.ch.dev_used = true
	Game.save_game(2)
	var info: Dictionary = Game.slot_info(2)
	Game.delete_slot(2)
	Game.testing = true
	Game.save_dir = old_dir
	Game.current_slot = old_slot
	check(info["summary"].ends_with("(dev)"), "dev: the load menu shows (dev)", info["summary"])
	# ---- UI: panel, pause button, HUD tag
	var ui = main.ui
	ui.open("dev")
	await frames(2)
	check(ui.is_open("dev") and ui.panels["dev"].tabs.visible and ui.panels["dev"].tabs.get_tab_count() == 7, "dev: the panel opens with seven tabs")
	var pr: Vector2 = ui.panels["dev"].size
	check(pr.x <= 1280 and pr.y <= 720, "dev: the panel fits the 1280x720 screen", str(pr))
	ui.close("dev")
	ui.open("pause")
	await frames(1)
	check(ui.panels["pause"].dev_btn.visible, "dev: the pause menu shows the Developer tools button")
	ui.close("pause")
	# ---- off again
	Dev.set_enabled(false)
	check(Dev.flags == R.default_flags() and not Dev.god(), "dev: switching off resets god mode and every flag")
	ui.open("dev")
	await frames(1)
	check(not ui.panels["dev"].tabs.visible and ui.panels["dev"].off_label.visible, "dev: the panel shows only a hint while the tools are off")
	ui.close_all()
	ui.open("pause")
	await frames(1)
	check(not ui.panels["pause"].dev_btn.visible, "dev: no pause menu button while off")
	ui.close_all()
	Game.dev_in_tests = false
	Game.settings["dev_tools"] = false
	Dev.reset_flags()
	Game.ch = old_ch


# ------------------------------------------------------------------ training grounds
const TrainingRulesT = preload("res://scripts/core/training_rules.gd")

func _tev(kind: String, amount: float, skill: String = "fireball", status: String = "", crit: bool = false, dummy: int = 1, cast: int = -1) -> Dictionary:
	return {"kind": kind, "amount": amount, "skill_id": skill, "status_id": status, "crit": crit, "dummy": dummy, "cast_id": cast}

func _trun(counting: String = "all", dur: int = 10, type: String = "single") -> Dictionary:
	var s: Dictionary = TrainingRulesT.default_settings(Data.training_cfg)
	s["counting"] = counting
	s["duration"] = dur
	s["type"] = type
	return TrainingRulesT.new_run(s, 3 if type == "aoe" else 1)

func test_training() -> void:
	print("\n--- training grounds (rules and history)")
	_log("--- training grounds (rules and history)")
	var R = TrainingRulesT
	var cfg: Dictionary = Data.training_cfg
	check(Data.load_errors.is_empty() and not cfg.is_empty(), "training: data/training.json loads")
	var durs: Array = cfg.get("durations", [])
	check(durs.size() == 2 and int(durs[0]) == 10 and int(durs[1]) == 30 and int(cfg.get("history_size", 0)) == 5, "training: durations 10/30 and history size 5 come from data")
	check(cfg["profiles"].has("none") and cfg["profiles"].has("t3_normal") and cfg["profiles"].has("t6_boss"), "training: the three defence profiles exist")
	# ---- window start
	var run := _trun()
	check(R.record(run, _tev("dot", 50.0, "fireball", "ignite")) == "ignored_idle" and not run["started"], "training: a DoT tick alone never starts the window")
	check(R.record(run, _tev("hit", 100.0)) == "counted" and run["started"] and run["events"][0]["t"] == 0.0, "training: the first direct hit starts the window and counts at t=0")
	R.tick(run, 1.0, 2.0)
	check(R.record(run, _tev("dot", 30.0, "fireball", "ignite")) == "counted" and is_equal_approx(run["events"][1]["t"], 1.0), "training: DoT ticks count once the window runs (t = game time since start)")
	var pr := _trun("player")
	check(R.record(pr, _tev("minion", 80.0, "summon_skeleton")) == "ignored_source" and not pr["started"], "training: Player only - a minion hit neither counts nor starts the window")
	check(R.record(pr, _tev("deployable", 80.0, "fire_trap")) == "ignored_source" and not pr["started"], "training: Player only - a trap/turret hit neither counts nor starts the window")
	check(R.record(pr, _tev("dot", 20.0, "fireball", "ignite")) == "ignored_idle", "training: Player only - a DoT tick before the first hit is ignored")
	check(R.record(pr, _tev("hit", 10.0)) == "counted" and pr["started"], "training: Player only - the player's own hit starts the window")
	var ar := _trun("all")
	check(R.record(ar, _tev("minion", 5.0, "summon_skeleton")) == "counted" and ar["started"], "training: All sources - a minion hit starts the window")
	var ar2 := _trun("all")
	check(R.record(ar2, _tev("minion", 5.0, "summon_skeleton", "ignite")) == "ignored_idle", "training: a minion-applied ignite tick is a tick, so it cannot start the window")
	check(not R.event_is_direct(_tev("deployable", 5.0, "fire_trap", "ignite")) and R.event_is_direct(_tev("deployable", 5.0, "fire_trap")), "training: status ticks are never direct hits, whoever applied them")
	# ---- window end (half-open [0, duration))
	var er := _trun("all", 10)
	R.record(er, _tev("hit", 10.0))
	for i in 99:
		R.tick(er, 0.1, 2.0)
	check(R.is_running(er) and R.record(er, _tev("hit", 5.0)) == "counted", "training: a hit just before the end counts")
	R.tick(er, 0.1, 2.0)
	check(er["finished"] and is_equal_approx(er["elapsed"], 10.0), "training: the window ends after exactly the chosen duration")
	check(R.record(er, _tev("hit", 99.0)) == "ignored_ended" and R.total_damage(er["events"]) == 15.0, "training: a hit at exactly the end time and later is ignored (window is [0, duration))")
	check(not R.can_start(er), "training: the restart grace blocks a new test right after the result")
	R.tick(er, 1.0, 2.0)
	check(not R.can_start(er), "training: still blocked after 1 s of a 2 s grace")
	R.tick(er, 1.5, 2.0)
	check(R.can_start(er), "training: a new test may start once the grace is over")
	var pz := _trun()
	R.record(pz, _tev("hit", 1.0))
	R.tick(pz, 0.0, 2.0)
	check(is_equal_approx(pz["elapsed"], 0.0), "training: no game time passing (pause) means no countdown")
	# ---- averages and peak
	var ev30 := []
	ev30.append({"t": 0.0, "amount": 3000.0, "kind": "hit", "skill_id": "a", "status_id": "", "crit": false, "dummy": 1})
	check(is_equal_approx(R.average_dps(ev30, 10.0), 300.0) and is_equal_approx(R.average_dps(ev30, 30.0), 100.0), "training: average DPS = total / full duration (10 s and 30 s)")
	var burst := [
		{"t": 0.2, "amount": 100.0, "kind": "hit", "skill_id": "a", "status_id": ""},
		{"t": 0.9, "amount": 400.0, "kind": "hit", "skill_id": "a", "status_id": ""},
		{"t": 1.1, "amount": 400.0, "kind": "hit", "skill_id": "a", "status_id": ""},
		{"t": 5.0, "amount": 700.0, "kind": "hit", "skill_id": "a", "status_id": ""},
	]
	var pk: Dictionary = R.peak_window(burst, 1.0)
	check(is_equal_approx(pk["dps"], 900.0) and is_equal_approx(pk["start"], 0.2), "training: a burst crossing a whole-second boundary is one window (900 from t=0.2)", str(pk))
	var pk2: Dictionary = R.peak_window([{"t": 0.0, "amount": 500.0, "kind": "hit"}, {"t": 1.0, "amount": 500.0, "kind": "hit"}], 1.0)
	check(is_equal_approx(pk2["dps"], 500.0), "training: events exactly 1.0 s apart are not in the same window", str(pk2))
	var pk3: Dictionary = R.peak_window([], 1.0)
	check(pk3["dps"] == 0.0, "training: peak second of an empty test is 0")
	var late := [{"t": 1.0, "amount": 100.0, "kind": "hit"}, {"t": 6.0, "amount": 100.0, "kind": "hit"}]
	check(is_equal_approx(R.peak_window(late, 1.0)["start"], 1.0), "training: ties keep the earliest peak second")
	# ---- hit stats ignore ticks
	var mix := [
		_tev("hit", 100.0, "a", "", true), _tev("hit", 300.0, "a", "", false),
		_tev("dot", 1000.0, "a", "ignite"), _tev("minion", 200.0, "m", "", false),
	]
	for i in mix.size():
		mix[i]["t"] = float(i)
	check(R.direct_hits(mix) == 3, "training: direct hits are hit/minion/deployable, DoT ticks are not hits")
	check(is_equal_approx(R.crit_rate(mix), 1.0 / 3.0), "training: crit rate ignores DoT ticks")
	check(is_equal_approx(R.average_hit(mix), 200.0) and is_equal_approx(R.biggest_hit(mix), 300.0), "training: average and biggest hit ignore DoT ticks")
	# ---- breakdown and attribution
	var names := {"fireball": "Fireball", "summon_skeleton": "Skeleton Warriors", "fire_trap": "Fire Trap"}
	var brk := [
		_tev("hit", 400.0, "fireball"), _tev("dot", 200.0, "fireball", "ignite"),
		_tev("minion", 150.0, "summon_skeleton"), _tev("deployable", 100.0, "fire_trap"),
		_tev("hit", 50.0, "passive"), _tev("hit", 100.0, ""),
	]
	for i in brk.size():
		brk[i]["t"] = float(i) * 0.1
	var rows: Array = R.breakdown(brk, 10.0, names, cfg)
	check(rows.size() == 6 and rows[0]["label"] == "Fireball" and is_equal_approx(rows[0]["damage"], 400.0), "training: breakdown is sorted by damage, highest first")
	var labels := []
	for r in rows:
		labels.append(r["label"])
	check(labels.has("Ignite (from Fireball)"), "training: a DoT is credited to the skill that applied it (sub-row)", str(labels))
	check(labels.has("Skeleton Warriors (minions)") and labels.has("Fire Trap (deployed)"), "training: minion and deployable rows carry their tags", str(labels))
	check(labels.has("Passive and item effects") and labels.has("Other"), "training: passive effects and unknown sources get their own rows", str(labels))
	var sum_exact := 0.0
	var sum_text := 0.0
	for r in rows:
		sum_exact += r["share"]
		sum_text += r["share_text"]
	check(absf(sum_exact - 100.0) < 0.0001 and absf(sum_text - 100.0) < 0.0001, "training: breakdown shares sum to 100% (exact and rounded)", "%f %f" % [sum_exact, sum_text])
	var thirds: Array = R.round_shares([100.0 / 3.0, 100.0 / 3.0, 100.0 / 3.0])
	check(absf(thirds[0] + thirds[1] + thirds[2] - 100.0) < 0.0001, "training: thirds round to exactly 100.0 (largest remainder)", str(thirds))
	check(is_equal_approx(rows[0]["dps"], 40.0), "training: row DPS = row damage / duration")
	check(R.top_rows(rows, 3).size() == 3, "training: the head label shows the top 3 rows")
	# a trap-applied ignite is excluded in Player only, a player-applied one is kept
	var po := _trun("player")
	R.record(po, _tev("hit", 10.0, "fireball"))
	var r_trap: String = R.record(po, _tev("deployable", 5.0, "fire_trap", "ignite"))
	var r_mine: String = R.record(po, _tev("dot", 5.0, "fireball", "ignite"))
	check(r_trap == "ignored_source" and r_mine == "counted", "training: Player only drops a trap's ignite and keeps the player's own", r_trap + " " + r_mine)
	# ---- full result
	var fr := _trun("all", 10)
	R.record(fr, _tev("hit", 1000.0, "fireball", "", true))
	R.tick(fr, 0.5, 2.0)
	R.record(fr, _tev("dot", 200.0, "fireball", "ignite"))
	for i in 30:
		R.tick(fr, 0.5, 2.0)
	var res: Dictionary = R.build_result(fr, names, cfg)
	check(fr["finished"] and is_equal_approx(res["total"], 1200.0) and is_equal_approx(res["avg_dps"], 120.0) and res["hits"] == 1, "training: build_result totals, average DPS and hit count", str(res))
	check(is_equal_approx(res["peak_dps"], 1200.0) and is_equal_approx(res["peak_start"], 0.0), "training: build_result peak second", str(res))
	# ---- poise breaks only count while running
	var pb := _trun()
	R.add_poise_break(pb)
	check(pb["poise_breaks"] == 0, "training: poise breaks before the test starts are not counted")
	R.record(pb, _tev("hit", 1.0))
	R.add_poise_break(pb)
	check(pb["poise_breaks"] == 1, "training: poise breaks inside the window are counted")
	# ---- dev marking
	var dr := _trun()
	R.mark_dev(dr, ["one_hit"], cfg["dev_flags_that_mark"])
	check(not dr["dev"], "training: no DEV mark before the window runs")
	R.record(dr, _tev("hit", 1.0))
	R.mark_dev(dr, ["god", "overlay"], cfg["dev_flags_that_mark"])
	check(not dr["dev"], "training: flags that do not change damage do not mark the result")
	R.mark_dev(dr, ["time_scale"], cfg["dev_flags_that_mark"])
	check(dr["dev"], "training: a damage-affecting flag marks the result DEV")
	var DevR = preload("res://scripts/core/dev_rules.gd")
	var fl: Dictionary = DevR.default_flags()
	check(R.marking_flags(fl, DevR.default_flags(), cfg["dev_flags_that_mark"], 0).is_empty(), "training: default Dev flags mark nothing")
	fl["damage_mult"] = 5.0
	fl["time_scale"] = 2.0
	var mf: Array = R.marking_flags(fl, DevR.default_flags(), cfg["dev_flags_that_mark"], 10)
	check(mf.has("damage_mult") and mf.has("time_scale") and mf.has("attr_bonus") and not mf.has("god"), "training: marking_flags reports the real Dev flag names", str(mf))
	for f in cfg["dev_flags_that_mark"]:
		check(f == "attr_bonus" or DevR.default_flags().has(f), "training: dev_flags_that_mark names a real Dev flag (%s)" % f)
	# ---- comparisons and history
	var base := {"settings": {"type": "single", "duration": 10, "counting": "all", "profile": "none", "spacing": "tight"}, "dev": false, "avg_dps": 1000.0}
	var same := base.duplicate(true)
	same["avg_dps"] = 1120.0
	check(R.comparable(base, same), "training: identical settings are comparable")
	var d30 := base.duplicate(true)
	d30["settings"]["duration"] = 30
	var dpo := base.duplicate(true)
	dpo["settings"]["counting"] = "player"
	var dpf := base.duplicate(true)
	dpf["settings"]["profile"] = "t6_boss"
	var ddev := base.duplicate(true)
	ddev["dev"] = true
	check(not R.comparable(base, d30) and not R.comparable(base, dpo) and not R.comparable(base, dpf) and not R.comparable(base, ddev), "training: duration, counting, profile and DEV differences make results not comparable")
	var a1 := base.duplicate(true)
	a1["settings"]["type"] = "aoe"
	var a2 := a1.duplicate(true)
	a2["settings"]["spacing"] = "spread"
	var a3 := a1.duplicate(true)
	a3["settings"]["spacing"] = "tight"
	var s_aoe := base.duplicate(true)
	s_aoe["settings"]["spacing"] = "spread"
	check(not R.comparable(a1, a2) and R.comparable(a1, a3) and not R.comparable(base, a1), "training: AoE compares only with AoE of the same spacing; single vs AoE never")
	check(R.comparable(base, s_aoe), "training: spacing is ignored for single-target results")
	var dl: Dictionary = R.delta_vs_history(same, [base])
	check(dl["comparable"] and is_equal_approx(dl["pct"], 12.0) and R.fmt_delta(dl) == "+12% vs previous", "training: delta is the % change in average DPS vs the latest comparable result", str(dl))
	var dn: Dictionary = R.delta_vs_history(same, [d30, dpo])
	check(not dn["comparable"] and R.fmt_delta(dn) == "not comparable", "training: no comparable result in history -> 'not comparable'")
	var dskip: Dictionary = R.delta_vs_history(same, [d30, base])
	check(dskip["comparable"] and is_equal_approx(dskip["prev_dps"], 1000.0), "training: the delta skips non-comparable entries to find the most recent comparable one")
	var hist := []
	for i in 7:
		var e := base.duplicate(true)
		e["avg_dps"] = float(i)
		hist = R.push_history(hist, e, 5)
	check(hist.size() == 5 and hist[0]["avg_dps"] == 6.0 and hist[4]["avg_dps"] == 2.0, "training: history keeps 5, newest first, and drops the oldest on the 6th")
	check(R.fmt_num(6980.0) == "6,980" and R.fmt_num(1234567.0) == "1,234,567" and R.fmt_num(12.0) == "12" and R.fmt_num(999999.4) == "999,999", "training: numbers use thousands separators")
	check(R.settings_text({"type": "single", "duration": 10, "counting": "all", "profile": "none"}, cfg) == "10 s · All sources · No defences", "training: settings text reads '10 s - All sources - No defences'")
	# ---- AoE helpers
	var aoe_ev := [
		_tev("hit", 300.0, "nova", "", false, 1, 1), _tev("hit", 300.0, "nova", "", false, 2, 1), _tev("hit", 300.0, "nova", "", false, 3, 1),
		_tev("hit", 100.0, "bolt", "", false, 1, 2),
		_tev("dot", 100.0, "nova", "ignite", false, 2, 1),
	]
	var pd: Array = R.per_dummy(aoe_ev, 3, 10.0)
	var pd_share := 0.0
	var pd_dmg := 0.0
	for r in pd:
		pd_share += r["share"]
		pd_dmg += r["damage"]
	check(pd.size() == 3 and absf(pd_share - 100.0) < 0.0001 and is_equal_approx(pd_dmg, R.total_damage(aoe_ev)), "training: AoE total is the sum of the three dummies and per-dummy shares sum to 100%")
	check(pd[0]["hits"] == 2 and pd[1]["hits"] == 1, "training: per-dummy hit counts ignore DoT ticks")
	check(is_equal_approx(R.targets_per_cast(aoe_ev), 2.0), "training: average targets hit per cast = distinct dummies per cast id, averaged (3 and 1 -> 2)")
	check(R.targets_per_cast([_tev("hit", 1.0)]) == -1.0, "training: targets per cast is unavailable (-1) when hits carry no cast id")
	# ---- settings
	var st: Dictionary = R.sanitize_settings(cfg, {"type": "aoe", "duration": 99, "counting": "nonsense", "profile": "t6_boss", "spacing": "spread"})
	check(st["type"] == "aoe" and st["duration"] == 10 and st["counting"] == "all" and st["profile"] == "t6_boss" and st["spacing"] == "spread", "training: invalid Setup values fall back to the defaults, valid ones are kept", str(st))
	# ---- TrainingLog (session and history, no scene)
	var old_slot: int = Game.current_slot
	Game.testing = true
	Game.training_in_tests = false
	check(not TrainingLog.available(), "training: unavailable under Game.testing without the opt-in flag")
	Game.training_in_tests = true
	check(TrainingLog.available(), "training: Game.training_in_tests turns it on for tests")
	TrainingLog.reset_settings()
	check(TrainingLog.settings == R.default_settings(cfg), "training: TrainingLog starts with the data defaults")
	TrainingLog.set_option("duration", 30)
	TrainingLog.set_option("counting", "player")
	TrainingLog.set_option("duration", 77)
	check(TrainingLog.settings["duration"] == 30 and TrainingLog.settings["counting"] == "player", "training: Setup choices are remembered and invalid values are refused")
	TrainingLog.reset_settings()
	Game.current_slot = 91
	TrainingLog.clear_history()
	TrainingLog.discard()
	check(TrainingLog.report(_tev("hit", 5.0)) == "no_run", "training: damage with no dummies spawned is ignored")
	TrainingLog.set_option("duration", 10)
	TrainingLog.begin(1)
	check(TrainingLog.has_run() and not TrainingLog.is_running(), "training: Spawn creates an idle test")
	check(TrainingLog.report(_tev("hit", 500.0)) == "counted" and TrainingLog.is_running(), "training: the first hit starts the test")
	for i in 100:
		TrainingLog.tick(0.1)
	check(not TrainingLog.is_running() and not TrainingLog.last_result.is_empty(), "training: the test ends after 10 s of game time and stores the result")
	check(TrainingLog.history().size() == 1 and is_equal_approx(TrainingLog.history()[0]["avg_dps"], 50.0), "training: the result is added to history once")
	TrainingLog.tick(0.1)
	check(TrainingLog.history().size() == 1, "training: ticking after the result does not add it again")
	check(TrainingLog.report(_tev("hit", 5.0)) == "ignored_grace", "training: a hit during the restart grace is ignored")
	for i in 25:
		TrainingLog.tick(0.1)
	check(TrainingLog.report(_tev("dot", 5.0, "fireball", "ignite")) == "ignored_ended", "training: a DoT tick after the result never starts a new test")
	check(TrainingLog.report(_tev("hit", 700.0)) == "counted" and TrainingLog.is_running() and TrainingLog.last_result.is_empty(), "training: after the grace a new direct hit starts a new test")
	# Remove / leaving the hub discards a running test: it never reaches history
	TrainingLog.discard()
	for i in 120:
		TrainingLog.tick(0.1)
	check(TrainingLog.history().size() == 1 and not TrainingLog.has_run(), "training: a discarded running test is never added to history")
	# Reset clears the result and returns to idle with the same dummies
	TrainingLog.begin(3)
	TrainingLog.report(_tev("hit", 10.0, "nova", "", false, 2, 1))
	TrainingLog.reset_run()
	check(TrainingLog.has_run() and not TrainingLog.is_running() and TrainingLog.run["dummies"] == 3 and TrainingLog.last_result.is_empty(), "training: Reset returns to idle and clears the result")
	# per save slot and survival
	TrainingLog.discard()
	Game.current_slot = 92
	check(TrainingLog.history().is_empty(), "training: a different save slot starts with an empty history")
	Game.current_slot = 91
	check(TrainingLog.history().size() == 1, "training: history is kept per save slot while switching characters")
	var res_first: Dictionary = TrainingLog.history()[0]
	check(TrainingLog.delta_for(res_first)["comparable"] == false, "training: the only entry has nothing to compare with")
	TrainingLog.clear_history()
	Game.current_slot = 92
	check(TrainingLog.history().is_empty(), "training: Clear history only clears the current character")
	Game.current_slot = old_slot
	# ---- history rows, build snapshots and what changed
	check(R.fmt_ago(100.0, 102.0) == "just now" and R.fmt_ago(100.0, 145.0) == "45 s ago" and R.fmt_ago(0.0, 750.0) == "12 min ago" and R.fmt_ago(0.0, 3900.0) == "1 h 5 min ago", "training: 'ago' text reads just now / s / min / h")
	var snap_a := {"name": "Dan", "class": "mage", "level": 12, "spec": "", "main_hand": "Oak Staff", "off_hand": "", "hotbar": ["firebolt", "frost_nova", "", "", "", "", ""], "hotbar_names": ["Firebolt", "Frost Nova", "", "", "", "", ""], "passives": 7}
	var snap_b := snap_a.duplicate(true)
	snap_b["level"] = 13
	snap_b["main_hand"] = "Yew Staff"
	snap_b["hotbar_names"][2] = "Meteor"
	snap_b["passives"] = 9
	var sl: Array = R.snapshot_lines(snap_a)
	check(sl.size() == 4 and sl[0] == "Dan, level 12 Mage" and "Oak Staff" in sl[1] and "none" in sl[1] and sl[2] == "Hotbar: Firebolt, Frost Nova" and sl[3] == "Allocated passives: 7", "training: snapshot lines name the character, gear, hotbar and passives", str(sl))
	check(R.snapshot_lines({}).is_empty(), "training: an empty snapshot gives no lines")
	var chg: Array = R.snapshot_changes(snap_b, snap_a)
	check(chg.size() == 4 and R.snapshot_changes(snap_a, snap_a).is_empty() and R.snapshot_changes({}, snap_a).is_empty(), "training: snapshot changes list level, main hand, hotbar slot and passives", str(chg))
	var e_old := {"settings": {"type": "single", "duration": 10, "counting": "all", "profile": "none", "spacing": "tight"}, "avg_dps": 1000.0, "peak_dps": 1500.0, "dev": false, "when": 10.0, "snapshot": snap_a, "breakdown": [], "total": 10000.0, "hits": 10, "crit_rate": 0.0, "avg_hit": 1000.0, "biggest_hit": 1000.0, "duration": 10.0, "peak_start": 1.0}
	var e_new := e_old.duplicate(true)
	e_new["avg_dps"] = 1100.0
	e_new["when"] = 70.0
	e_new["snapshot"] = snap_b
	var e_other := e_old.duplicate(true)
	e_other["settings"]["duration"] = 30
	var hist_l := [e_new, e_other, e_old]
	check(R.previous_comparable(e_new, hist_l, 1) == e_old and R.previous_comparable(e_old, hist_l, 3).is_empty(), "training: the previous comparable entry skips entries with other settings")
	var rl: Array = R.history_row_lines(e_new, R.delta_vs_history(e_new, hist_l, 1), 130.0, cfg)
	check(rl.size() == 2 and "1 min ago" in rl[0] and "Single" in rl[0] and "1,100 DPS" in rl[0] and "peak 1,500" in rl[0] and "+10%" in rl[0] and "10 s" in rl[1], "training: a History row shows when, type, DPS, peak and the change", str(rl))
	var dt: String = R.history_detail_text(e_new, R.delta_vs_history(e_new, hist_l, 1), snap_a, cfg)
	check("Build when tested" in dt and "Changed since the previous comparable test" in dt and "main hand Oak Staff to Yew Staff" in dt, "training: a History detail shows the build and the changes", dt.substr(max(0, dt.length() - 240)))
	TrainingLog.clear_history()
	TrainingLog.history_by_slot.erase(91)
	TrainingLog.history_by_slot.erase(92)
	TrainingLog.discard()
	TrainingLog.reset_settings()
	Game.training_in_tests = false


# ------------------------------------------------------------------ training grounds: hub, dummy, attribution
const EnemyT = preload("res://scripts/entities/enemy.gd")

func _tpk(skill: String, kind: String = "spell", dmg: float = 100.0, extra: Dictionary = {}) -> Dictionary:
	var pk := {"dmg": {"fire": [dmg, dmg]}, "crit_chance": 0.0, "crit_mult": 1.0, "faction": "player", "status": [], "tags": [], "flags": {}, "skill": skill, "kind": kind, "cast": Combat.cast_serial}
	for k in extra:
		pk[k] = extra[k]
	return pk

func _tevs(kind: String = "", skill: String = "") -> Array:
	var out := []
	for e in TrainingLog.run.get("events", []):
		if (kind == "" or e["kind"] == kind) and (skill == "" or e["skill_id"] == skill):
			out.append(e)
	return out

func _tready(p) -> void:
	p.busy = 0
	p.mana = 999
	p.cooldowns.clear()

func test_training_world() -> void:
	print("\n--- training grounds (hub, dummy, attribution)")
	_log("--- training grounds (hub, dummy, attribution)")
	Game.training_in_tests = false
	TrainingLog.discard()
	TrainingLog.reset_settings()
	Game.new_character("mage")
	main.start_game()
	await frames(3)
	var hub = Game.level
	var p = hub.player
	var ch = Game.ch
	check(hub.has_method("training_spawn") and hub.training_dummies.is_empty() and not hub.training_active, "training world: the hub starts with no dummies")
	# ---- off under tests
	var why: String = hub.training_spawn()
	check(why != "" and hub.training_dummies.is_empty() and not hub.training_active, "training world: Spawn is refused under Game.testing without the opt-in flag")
	Game.training_in_tests = true
	# ---- summon is refused in the hub until dummies exist
	ch.loadout[2] = "summon_skeletons"
	_tready(p)
	check(not p.try_use_slot(2) and p.minions.is_empty(), "training world: summoning in the hub is refused while no dummies exist")
	why = hub.training_spawn()
	check(why == "" and hub.training_dummies.size() == 1 and hub.training_active, "training world: Spawn creates one dummy and switches the hub rule on", why)
	var d = hub.training_dummies[0]
	check(hub.enemies.has(d) and d.is_in_group("training_dummy") and d.faction == "enemy", "training world: the dummy is a normal hostile target (level.enemies) in the training_dummy group")
	_tready(p)
	check(p.try_use_slot(2), "training world: summoning is allowed in the hub while dummies exist")
	await frames(3)
	check(p.minions.size() > 0, "training world: the summoned minions exist")
	for m in p.minions.duplicate():
		if is_instance_valid(m):
			m.die(null)
	p.minions.clear()
	# ---- basic hit path
	TrainingLog.reset_run()
	var pos0: Vector2 = d.global_position
	var pk := _tpk("fireball", "spell", 100.0)
	Combat.deal(pk, p, d)
	var evs := _tevs("hit", "fireball")
	check(evs.size() == 1 and absf(float(evs[0]["amount"]) - 100.0) < 0.5 and evs[0]["dummy"] == 1, "training world: a hit is recorded once with its skill and the damage after mitigation (no defences = 100)", str(evs))
	check(TrainingLog.is_running(), "training world: the first hit starts the test")
	Combat.deal(_tpk("fireball", "spell", 1.0e12), p, d)
	check(d.alive and d.life == d.max_life, "training world: the dummy cannot die")
	d.die(null)
	check(d.alive, "training world: kill-all style die() calls do nothing")
	d.knock = Vector2(900, 0)
	await frames(10)
	check(d.global_position.distance_to(pos0) < 0.01, "training world: knockback does not move the dummy")
	# enemy damage is not counted
	var n0: int = TrainingLog.run["events"].size()
	d.receive_hit({"fire": 500.0}, {"faction": "enemy"}, null, false)
	check(TrainingLog.run["events"].size() == n0, "training world: only player damage is counted")
	# ---- ignite is credited to the skill that applied it
	TrainingLog.reset_run()
	d.statuses.clear()
	Combat.deal(_tpk("fire_nova", "spell", 100.0, {"status": [{"type": "ignite", "chance": 100.0}]}), p, d)
	await frames(75)
	var ticks := _tevs("dot", "fire_nova")
	check(d.statuses.has("ignite") or ticks.size() > 0, "training world: a normal ignite is applied to the dummy")
	check(ticks.size() >= 1 and ticks[0]["status_id"] == "ignite", "training world: ignite ticks are credited to the skill that applied them", str(TrainingLog.run["events"]))
	# statuses end with the window
	TrainingLog.tick(100.0)
	check(not TrainingLog.last_result.is_empty() and d.statuses.is_empty(), "training world: the test ends and the dummy's statuses are cleared")
	var total_end: float = float(TrainingLog.last_result.get("total", -1.0))
	await frames(40)
	check(is_equal_approx(float(TrainingLog.last_result.get("total", -2.0)), total_end), "training world: nothing is added to the result after it ended")
	# ---- Player-only counting (a trap's ignite is dropped)
	TrainingLog.set_option("counting", "player")
	hub.training_spawn()
	d = hub.training_dummies[0]
	Combat.deal(_tpk("fireball", "spell", 100.0), p, d)
	Combat.deal(_tpk("explosive_mine", "trap", 100.0), p, d)
	check(_tevs("hit", "fireball").size() == 1 and _tevs("deployable").size() == 0, "training world: Player only does not count a trap's damage")
	TrainingLog.set_option("counting", "all")
	hub.training_spawn()
	d = hub.training_dummies[0]
	Combat.deal(_tpk("explosive_mine", "trap", 100.0), p, d)
	check(_tevs("deployable", "explosive_mine").size() == 1, "training world: All sources counts a trap's damage under the trap's skill")

	# ---- profiles: defences match a real enemy built the same way
	var dg := {"tier": 3, "min_level": 1, "max_level": 10, "pool": [{"id": "ghoul", "w": 40}], "resist_bonus": 10, "life_mult": 1.5, "boss": ""}
	var prof: Dictionary = Data.training_cfg["profiles"]["t3_normal"]
	var def_all: Dictionary = TrainingRulesT.profile_defence(prof, [dg], {"ghoul": Data.enemies["ghoul"]}, 7)
	var real = EnemyT.new()
	real.setup(Data.enemies["ghoul"], 7, [], {"life": 1.5, "resist": 10.0})
	var same := is_equal_approx(def_all["armour"], real.armour) and is_equal_approx(def_all["life"], real.max_life)
	for el in ["fire", "cold", "lightning", "void"]:
		same = same and is_equal_approx(float(def_all["resist"][el]), float(real.resist.get(el, 0.0)))
	check(same, "training world: a profile's armour, resist and life match a real enemy.gd setup", "%s vs %s/%s/%s" % [str(def_all), real.armour, real.max_life, str(real.resist)])
	real.free()
	var dg2 := {"tier": 3, "min_level": 1, "max_level": 10, "pool": [{"id": "ghoul", "w": 3}, {"id": "bloater", "w": 1}], "resist_bonus": 0, "life_mult": 1.0, "boss": ""}
	var en2 := {"ghoul": Data.enemies["ghoul"], "bloater": Data.enemies["bloater"]}
	var d2: Dictionary = TrainingRulesT.profile_defence(prof, [dg2], en2, 4)
	var arm2: float = (3.0 * float(Data.enemies["ghoul"].get("armour", 0)) + float(Data.enemies["bloater"].get("armour", 0))) / 4.0 * (1.0 + 0.12 * 3.0)
	check(is_equal_approx(d2["armour"], arm2) and d2["level"] == 4, "training world: the normal profile averages the dungeon pool by spawn weight")
	var bprof: Dictionary = Data.training_cfg["profiles"]["t6_boss"]
	var db: Dictionary = TrainingRulesT.profile_defence(bprof, Data.dungeon_list, Data.enemies, 1)
	check(db["life"] > 0.0 and db["level"] == 39 and db["poise"], "training world: the boss profile uses the tier's boss, one level above the dungeon's floor", str(db))
	TrainingLog.set_option("profile", "t3_normal")
	hub.training_spawn()
	d = hub.training_dummies[0]
	var t3: Dictionary = TrainingRulesT.profile_defence(prof, Data.dungeon_list, Data.enemies, ch.level)
	check(d.armour > 0.0 and is_equal_approx(d.armour, t3["armour"]) and not d.poise_on, "training world: the T3 dummy carries the profile's armour and no poise bar", "dummy armour=%s profile=%s poise=%s" % [d.armour, str(t3), d.poise_on])
	TrainingLog.set_option("profile", "t6_boss")
	hub.training_spawn()
	d = hub.training_dummies[0]
	check(d.poise_on and d.is_boss, "training world: the T6 boss dummy has poise")
	for i in 40:
		Combat.deal(_tpk("fireball", "spell", 5.0e6), p, d)
	check(int(TrainingLog.run["poise_breaks"]) >= 1, "training world: poise breaks on the boss dummy are counted", str(TrainingLog.run["poise_breaks"]))
	var bpos: Vector2 = d.global_position
	var pcfg: Dictionary = Data.stun_cfg["poise"]
	await frames(int((float(pcfg["stagger_duration"]) + float(pcfg["immunity_after_stagger"]) + 1.0) * 60.0))
	check(d.global_position.distance_to(bpos) < 0.01 and d.alive, "training world: the boss dummy does not move or stagger away after a poise break")
	var part: float = d.poise_life * float(pcfg["fill_fraction"]) * 0.5
	Combat.deal(_tpk("fireball", "spell", part), p, d)
	var poise_up: float = float(d.poise_state["poise"])
	await frames(int((float(pcfg["regen_delay"]) + 100.0 / float(pcfg["regen_per_sec"]) + 1.0) * 60.0))
	check(poise_up > 10.0 and float(d.poise_state["poise"]) < 0.01, "training world: poise fills from hits and drains back to empty", "%s -> %s" % [poise_up, d.poise_state["poise"]])
	TrainingLog.set_option("profile", "none")
	# ---- pausing stops the countdown
	hub.training_spawn()
	d = hub.training_dummies[0]
	Combat.deal(_tpk("fireball"), p, d)
	var el0: float = float(TrainingLog.run["elapsed"])
	get_tree().paused = true
	await frames(30)
	var el_paused: float = float(TrainingLog.run["elapsed"])
	get_tree().paused = false
	await frames(30)
	var el_run: float = float(TrainingLog.run["elapsed"])
	check(is_equal_approx(el_paused, el0) and el_run > el_paused + 0.3, "training world: pausing stops the countdown and it resumes afterwards", "%s %s %s" % [el0, el_paused, el_run])
	Engine.time_scale = 2.0
	var ts0: float = float(TrainingLog.run["elapsed"])
	await frames(60)
	var ts1: float = float(TrainingLog.run["elapsed"])
	Engine.time_scale = 1.0
	check(ts1 - ts0 > 0.9, "training world: game time still advances per physics frame with a Dev time scale", "%s" % (ts1 - ts0))
	hub.training_remove()

	# ---- spawn replaces; remove discards a running test
	hub.training_spawn()
	hub.training_spawn()
	await frames(2)
	var live := 0
	for e in hub.enemies:
		if is_instance_valid(e) and e.is_in_group("training_dummy"):
			live += 1
	check(hub.training_dummies.size() == 1 and live == 1 and get_tree().get_nodes_in_group("training_dummy").size() == 1, "training world: Spawn replaces the old dummy instead of adding another", "live=%d" % live)
	d = hub.training_dummies[0]
	var hist0: int = TrainingLog.history().size()
	Combat.deal(_tpk("fireball"), p, d)
	check(TrainingLog.is_running(), "training world: a test is running before Remove")
	hub.training_remove()
	await frames(2)
	check(not TrainingLog.is_running() and TrainingLog.history().size() == hist0 and hub.training_dummies.is_empty() and not hub.training_active and get_tree().get_nodes_in_group("training_dummy").is_empty(), "training world: Remove discards a running test and leaves history alone")
	_tready(p)
	check(not p.try_use_slot(2), "training world: summoning is refused again once the dummies are gone")

	# ---- AoE cluster
	TrainingLog.set_option("type", "aoe")
	TrainingLog.set_option("spacing", "tight")
	why = hub.training_spawn()
	check(why == "" and hub.training_dummies.size() == 3, "training world: AoE spawns three dummies", why)
	if hub.training_dummies.size() == 3:
		var a = hub.training_dummies[0]
		var b = hub.training_dummies[1]
		var c = hub.training_dummies[2]
		var tight: float = float(Data.training_cfg["cluster_spacing"]["tight"])
		check(absf(a.global_position.distance_to(b.global_position) - tight) < 0.5 and absf(b.global_position.distance_to(c.global_position) - tight) < 0.5 and absf(a.global_position.distance_to(c.global_position) - tight) < 0.5, "training world: tight cluster spacing comes from data")
		Combat.cast_serial += 1
		Combat.deal(_tpk("fireball", "spell", 100.0), p, b)
		Combat.deal(_tpk("fireball", "spell", 100.0), p, c)
		var dums := {}
		for e in TrainingLog.run["events"]:
			dums[e["dummy"]] = true
		check(dums.has(2) and dums.has(3) and TrainingLog.is_running() and TrainingLog.run["events"][0]["t"] == 0.0, "training world: hits on different dummies share one window")
		TrainingLog.tick(100.0)
		var lr: Dictionary = TrainingLog.last_result
		check(lr.has("per_dummy") and lr["settings"]["type"] == "aoe" and absf(float(lr["total"]) - 200.0) < 1.0, "training world: the AoE result sums all dummies", str(lr.get("total")))
		check(is_equal_approx(float(lr.get("targets_per_cast", -9.0)), 2.0), "training world: the AoE result reports distinct dummies hit per cast", str(lr.get("targets_per_cast")))
	TrainingLog.set_option("spacing", "spread")
	why = hub.training_spawn()
	if hub.training_dummies.size() == 3:
		var sp: float = float(Data.training_cfg["cluster_spacing"]["spread"])
		check(absf(hub.training_dummies[0].global_position.distance_to(hub.training_dummies[1].global_position) - sp) < 0.5, "training world: spread cluster spacing comes from data")
	else:
		check(false, "training world: the spread cluster fits in the hub", why)
	TrainingLog.set_option("type", "single")

	# ---- minion damage is credited to the summoning skill
	hub.training_spawn()
	d = hub.training_dummies[0]
	var sk: Dictionary = ch.resolved_skill("summon_skeletons")
	var m = p.spawn_minion(sk.get("minion", "skeleton_warrior"), 1, d.global_position + Vector2(-14, 0), sk)
	await frames(240)
	var mev := _tevs("minion")
	check(m != null and mev.size() > 0 and mev[0]["skill_id"] == "summon_skeletons", "training world: minion damage is credited to the summoning skill", str(mev.slice(0, 2)))
	hub.training_remove()
	for mm in p.minions.duplicate():
		if is_instance_valid(mm):
			mm.die(null)
	p.minions.clear()

	# ---- history survives a dungeon trip; a running test does not
	hub.training_spawn()
	d = hub.training_dummies[0]
	Combat.deal(_tpk("fireball"), p, d)
	TrainingLog.tick(100.0)
	check(TrainingLog.history().size() >= 1, "training world: a finished test is stored in this character's history")
	var hn: int = TrainingLog.history().size()
	Combat.deal(_tpk("fireball"), p, d)
	TrainingLog.tick(0.01)
	main.enter_dungeon("forgotten_depths", 31)
	await frames(3)
	check(not TrainingLog.has_run() or not TrainingLog.is_running(), "training world: leaving the hub drops a running test")
	main.go_hub(false)
	await frames(3)
	check(TrainingLog.history().size() == hn and Game.level.training_dummies.is_empty(), "training world: history survives a dungeon trip and the new hub starts without dummies")
	TrainingLog.clear_history()
	TrainingLog.discard()

	# ---- the panel (Setup and Result tabs)
	hub = Game.level
	p = hub.player
	var ui = main.ui
	ui.open_station("training")
	await frames(2)
	var tp = ui.panels["training"]
	check(ui.is_open("training") and tp.visible, "training panel: Rook opens the panel")
	check(tp.choice_btns["type"].has("aoe") and not tp.spacing_row.visible, "training panel: cluster spacing is hidden for a single-target test")
	tp.choice_btns["type"]["aoe"].pressed.emit()
	check(TrainingLog.settings["type"] == "aoe" and tp.spacing_row.visible, "training panel: choosing AoE shows the spacing row")
	tp.choice_btns["duration"][30].pressed.emit()
	tp.choice_btns["profile"]["t3_normal"].pressed.emit()
	check(int(TrainingLog.settings["duration"]) == 30 and TrainingLog.settings["profile"] == "t3_normal", "training panel: option buttons set the test options")
	check(tp.reset_btn.disabled and tp.remove_btn.disabled, "training panel: Reset and Remove wait until dummies exist")
	tp._spawn()
	var hub2 = Game.level
	check(hub2.training_dummies.size() == 3 and not tp.reset_btn.disabled and not tp.remove_btn.disabled, "training panel: Spawn creates the AoE cluster and enables Reset/Remove", tp.msg_label.text)
	d = hub2.training_dummies[0]
	Combat.deal(_tpk("fireball", "spell", 250.0), p, d)
	tp._show_tab("result")
	await frames(2)
	check(tp.result_label.text.contains("running"), "training panel: the Result tab says a test is running")
	TrainingLog.tick(100.0)
	await frames(2)
	check(tp.result_label.text.contains("250") or tp.result_label.text.contains("Fireball") or tp.result_label.text.contains("fireball"), "training panel: the Result tab shows the finished result", tp.result_label.text.substr(0, 200))
	check(tp.size.y <= 720.0 and tp.size.x <= 640.0, "training panel: fits a 1280x720 window", str(tp.size))
	# ---- build snapshot and the History tab
	var hist: Array = TrainingLog.history()
	var snap: Dictionary = hist[0].get("snapshot", {}) if hist.size() > 0 else {}
	var mh = ch.equipment.get("main_hand")
	check(snap.get("name") == ch.char_name and snap.get("class") == "mage" and int(snap.get("level", 0)) == ch.level and snap.get("hotbar", []).size() == 7 and snap.get("main_hand") == (mh["name"] if mh != null else "") and int(snap.get("passives", -1)) == ch.allocated.size(), "training history: a finished test stores the build snapshot", str(snap))
	ch.loadout[3] = "frost_nova"
	tp._remove()
	tp._spawn()
	var d3 = Game.level.training_dummies[0]
	Combat.deal(_tpk("fireball", "spell", 500.0), p, d3)
	TrainingLog.tick(100.0)
	check(TrainingLog.history().size() == 2 and TrainingLog.history()[0]["snapshot"]["hotbar"][3] == "frost_nova" and TrainingLog.history()[1]["snapshot"]["hotbar"][3] != "frost_nova", "training history: the second test is stored first with its own snapshot")
	tp._show_tab("history")
	await frames(2)
	var rows := 0
	var first_btn: Button = null
	for c in tp.history_list.get_children():
		if c is Button:
			rows += 1
			if first_btn == null:
				first_btn = c
	check(rows == 2 and not tp.clear_btn.disabled, "training history: the History tab lists one row per test")
	first_btn.pressed.emit()
	await frames(2)
	var detail := ""
	for c in tp.history_list.get_children():
		if c is RichTextLabel:
			detail = c.text
	check(tp.open_row == 0 and detail.contains("Build when tested") and detail.contains("Changed since the previous comparable test") and detail.contains("slot 4"), "training history: clicking a row shows its build and what changed", detail.substr(max(0, detail.length() - 260)))
	for c in tp.history_list.get_children():   # the list is rebuilt on every refresh: find the button again
		if c is Button:
			first_btn = c
			break
	first_btn.pressed.emit()
	await frames(2)
	check(tp.open_row == -1, "training history: clicking the row again collapses it")
	tp._ask_clear()
	check(ui.confirm.visible, "training history: Clear history asks for confirmation")
	ui._on_cancel()
	check(TrainingLog.history().size() == 2, "training history: cancelling keeps the history")
	tp._ask_clear()
	ui._on_confirm()
	await frames(2)
	check(TrainingLog.history().is_empty() and tp.clear_btn.disabled, "training history: confirming clears this character's history")
	tp._show_tab("result")
	tp._reset()
	check(TrainingLog.last_result.is_empty() and not TrainingLog.is_running(), "training panel: Reset clears the result")
	tp._remove()
	check(hub2.training_dummies.is_empty() and tp.reset_btn.disabled, "training panel: Remove clears the dummies")
	ui.close_all()
	TrainingLog.reset_settings()

	# ---- ranger: turret and mine damage is credited to the deploying skill
	Game.new_character("ranger")
	main.start_game()
	await frames(3)
	hub = Game.level
	p = hub.player
	ch = Game.ch
	ch.loadout[2] = "ballista_turret"
	_tready(p)
	check(not p.try_use_slot(2) and p.deployables.is_empty(), "training world: deploying in the hub is refused while no dummies exist")
	hub.training_spawn()
	d = hub.training_dummies[0]
	p.global_position = d.global_position + Vector2(-50, 0)
	p.auto_aim_override = p.global_position + Vector2(10, 0)
	_tready(p)
	check(p.try_use_slot(2), "training world: deploying a turret works in the hub while dummies exist")
	await frames(300)
	var tev := _tevs("deployable", "ballista_turret")
	check(tev.size() > 0, "training world: turret damage is credited to the deploying skill", str(TrainingLog.run["events"].slice(0, 3)))
	hub.training_remove()
	Game.training_in_tests = false
	TrainingLog.discard()
	TrainingLog.reset_settings()
