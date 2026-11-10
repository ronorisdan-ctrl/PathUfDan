extends RefCounted
## Passive tree Phase 1 checks: schema + validator, generator, save migration
## (SAVE_VERSION 4, full refund policy) and one behavioural test per registered flag.
## Called from tests/test_runner.gd; quick run on its own:
##   godot --headless --fixed-fps 60 --path . res://tests/tree_only.tscn
## Every flag in data/passive_flags.json needs a func flag_<id>(p, e) below: the node is
## really allocated through CharacterData.allocate_path, the trigger is performed on a
## live player/enemy in a dungeon, and the outcome is compared with the node unallocated.

const TreeRules = preload("res://scripts/core/tree_rules.gd")

var T = null          # the test runner (check, frames, main)
var lv = null
var p = null
var e = null
var cur_class := ""

func run(runner) -> void:
	T = runner
	T._log("--- passive tree (Phase 1)")
	print("\n--- passive tree (Phase 1)")
	test_validator_real()
	test_validator_catches()
	test_migrate_id()
	test_generator_check()
	test_flag_registry()
	test_exclusive()
	test_save_migration()
	test_phase3_data()
	test_phase3b_data()
	test_masteries()
	test_tree_sockets()
	test_tree_ui_5a()
	test_tree_ui_5b()
	await test_flag_behaviours()
	Game.new_character("warrior")

# ------------------------------------------------------------------ validator
func _validate(nodes: Array, reg: Dictionary = Data.passive_flags, mig: Dictionary = Data.passive_migrations) -> Dictionary:
	return TreeRules.validate(nodes, reg, mig, Data.classes)

func test_validator_real() -> void:
	var r := _validate(Data.passive_list)
	T.check(r["errors"].is_empty(), "tree: validator passes on data/passive_tree.json", str(r["errors"].slice(0, 8)))
	for w in r["warnings"]:
		T._log("WARN  tree: " + str(w))
	var kc: Dictionary = r["report"]["keystone_cost"]
	for cls in kc:
		var worst := 0
		for k in kc[cls]:
			worst = maxi(worst, int(kc[cls][k]))
		T._log("INFO  tree: %s reaches all %d keystones, dearest costs %d points" % [cls, kc[cls].size(), worst])
	T._log("INFO  tree: status coverage %s" % str(r["report"]["status_coverage"]))
	T.check(TreeRules.tree_version(Data.passive_migrations) >= 1, "tree: tree_version is set")
	var tagged := true
	for n in Data.passive_list:
		tagged = tagged and n.get("tags", []).size() > 0
	T.check(tagged, "tree: all %d nodes carry tags" % Data.passive_list.size())

func _copy(nodes: Array) -> Array:
	return JSON.parse_string(JSON.stringify(nodes))

func _find(nodes: Array, id: String) -> Dictionary:
	for n in nodes:
		if n["id"] == id:
			return n
	return {}

func _expect(nodes: Array, needle: String, what: String, reg: Dictionary = Data.passive_flags, mig: Dictionary = Data.passive_migrations) -> void:
	var errs: Array = _validate(nodes, reg, mig)["errors"]
	var hit := false
	for er in errs:
		hit = hit or str(er).contains(needle)
	T.check(hit, "tree validator catches: " + what, str(errs.slice(0, 4)))

func test_validator_catches() -> void:
	var t := _copy(Data.passive_list)
	_find(t, "w_mel1")["links"].erase("w_start")
	_expect(t, "not symmetric", "a one-way link")
	t = _copy(Data.passive_list)
	_find(t, "w_mel1")["flags"] = ["no_such_flag"]
	_expect(t, "not in data/passive_flags.json", "an unregistered flag")
	t = _copy(Data.passive_list)
	_find(t, "w_mel1")["mods"].append({"stat": "damage", "type": "more", "value": 5})
	_expect(t, "only allowed on keystones", "a 'more' mod on a small node")
	t = _copy(Data.passive_list)
	_find(t, "ks_glass").erase("drawback")
	_expect(t, "keystone without a drawback", "a keystone with no drawback")
	t = _copy(Data.passive_list)
	_find(t, "w_mel1")["tags"] = ["shiny"]
	_expect(t, "not in the vocabulary", "an unknown tag")
	t = _copy(Data.passive_list)
	_find(t, "w_mel1")["tags"] = []
	_expect(t, "needs at least one tag", "a node without tags")
	t = _copy(Data.passive_list)
	_find(t, "w_mel1")["exclusive_with"] = ["r_prj1"]
	_expect(t, "is not mutual", "a one-sided exclusive_with")
	t = _copy(Data.passive_list)
	t.append({"id": "zz_island", "name": "Island", "type": "minor", "mods": [], "x": 0, "y": 0, "cost": 1, "links": [], "cluster": "X", "tags": ["generic"]})
	_expect(t, "not reachable", "an unreachable node")
	t = _copy(Data.passive_list)
	t.append(_copy([_find(t, "w_mel1")])[0])
	_expect(t, "duplicate id", "a duplicate id")
	t = _copy(Data.passive_list)
	_find(t, "w_mel1")["colour"] = "red"
	_expect(t, "unknown key", "an unknown key")
	t = _copy(Data.passive_list)
	_find(t, "w_mel1")["cost"] = 0
	_expect(t, "only start nodes cost 0", "a free non-start node")
	var reg: Dictionary = Data.passive_flags.duplicate(true)
	reg["budget_l60"] = 5
	_expect(Data.passive_list, "> budget", "a keystone beyond the point budget", reg)
	_expect(Data.passive_list, "target missing", "a migration to a missing id", Data.passive_flags,
		{"tree_version": 2, "history": {"2": {"old_gone": "nope"}}})
	_expect(Data.passive_list, "ids are never reused", "a removed id that still exists", Data.passive_flags,
		{"tree_version": 2, "history": {"2": {"w_mel1": null}}})
	_expect(Data.passive_list, "must be 2..tree_version", "a migration newer than tree_version", Data.passive_flags,
		{"tree_version": 1, "history": {"2": {}}})

func test_migrate_id() -> void:
	var mig := {"tree_version": 3, "history": {"2": {"a": "b", "x": null}, "3": {"b": "c"}}}
	T.check(TreeRules.migrate_id("a", 1, mig) == "c", "tree: migrate_id follows renames across versions")
	T.check(TreeRules.migrate_id("x", 1, mig) == "", "tree: migrate_id drops removed ids")
	T.check(TreeRules.migrate_id("b", 2, mig) == "c" and TreeRules.migrate_id("k", 1, mig) == "k", "tree: migrate_id starts at the save's version")

func test_generator_check() -> void:
	var tool := ProjectSettings.globalize_path("res://tools/gen_clusters.py")
	for py in ["python3", "python", "py"]:
		var out := []
		var code := OS.execute(py, [tool, "--check"], out, true)
		if code == -1 or (code != 0 and str(out).contains("not found")) or (code == 9009):
			continue
		T.check(code == 0, "tree: tools/gen_clusters.py --check reproduces passive_tree.json", str(out).left(400))
		return
	T._log("SKIP  tree: gen_clusters --check (no python on this machine)")
	print("SKIP  tree: gen_clusters --check (no python)")

func test_flag_registry() -> void:
	var reg: Dictionary = Data.passive_flags.get("flags", {})
	T.check(reg.size() >= 15, "tree: flag registry lists the tree's flags", str(reg.size()))
	for f in reg:
		T.check(has_method("flag_" + f), "tree: flag %s has a behavioural test" % f)
		if reg[f].get("kind") == "behaviour":
			T.check(T._script_mentions(f), "tree: behaviour flag %s is read by game code" % f)

# ------------------------------------------------------------------ exclusive_with
func test_exclusive() -> void:
	Game.new_character("warrior")
	var ch = Game.ch
	ch.level = 60
	ch.recalc()
	var a: Dictionary = Data.passives["w_mel1"]
	var b: Dictionary = Data.passives["w_arm1"]
	a["exclusive_with"] = ["w_arm1"]
	b["exclusive_with"] = ["w_mel1"]
	T.check(ch.allocate("w_mel1"), "exclusive: first node of a pair allocates")
	T.check(ch.can_allocate("w_arm1").begins_with("Cannot be taken with"), "exclusive: second node is refused", ch.can_allocate("w_arm1"))
	T.check(ch.path_to("w_arm1").is_empty(), "exclusive: no route to the excluded node")
	var far_ok := true
	for id in (ch.path_to("w_arm2") if Data.passives.has("w_arm2") else []):
		far_ok = far_ok and id != "w_arm1"
	T.check(far_ok, "exclusive: routes avoid the excluded node")
	var d: Dictionary = ch.to_dict()
	d["allocated"] = [ch.class_def()["start_passive"], "w_mel1", "w_arm1"]
	Game.load_from_dict(JSON.parse_string(JSON.stringify(d)))
	T.check(Game.ch.allocated.size() == 1 and Game.ch.tree_refund.get("reason", "").contains("mutually exclusive"),
		"exclusive: a save holding both nodes is refunded", str(Game.ch.tree_refund))
	a.erase("exclusive_with")
	b.erase("exclusive_with")
	T.check(_validate(Data.passive_list)["errors"].is_empty(), "exclusive: test pair removed again")

# ------------------------------------------------------------------ saves
const SHAPES := [   # [class, level, keystone to route to ("" = a few minors), bonus points]
	["warrior", 1, "", 0], ["warrior", 20, "ks_glass", 0], ["warrior", 60, "xe_ks", 6],
	["ranger", 5, "", 0], ["ranger", 35, "ks_perfect_aim", 2], ["ranger", 60, "xw_ks", 6],
	["mage", 12, "", 0], ["mage", 40, "ks_one_mind", 3], ["mage", 60, "xa_ks", 6],
	["ranger", 60, "xs_ks", 0], ["mage", 28, "", 1],
]

func _shape_save(shape: Array) -> Dictionary:
	Game.new_character(shape[0])
	var ch = Game.ch
	ch.level = shape[1]
	ch.bonus_passive_points = shape[3]
	ch.recalc()
	if shape[2] != "" and ch.path_cost(ch.path_to(shape[2])) <= ch.available_passive_points():
		ch.allocate_path(shape[2])
	var guard := 0
	while ch.available_passive_points() > 0 and guard < 200:
		guard += 1
		var done := false
		for id in ch.allocated.duplicate():
			for l in Data.passives[id]["links"]:
				if ch.can_allocate(l) == "" and not ch.is_mastery(l):
					ch.allocate(l)
					done = true
					break
			if done:
				break
		if not done:
			break
	return JSON.parse_string(JSON.stringify(ch.to_dict()))

func _as_v3(d: Dictionary) -> Dictionary:
	var o: Dictionary = d.duplicate(true)
	o["version"] = 3
	o.erase("tree_version")
	return o

func test_save_migration() -> void:
	var old_dir: String = Game.save_dir
	var old_slot: int = Game.current_slot
	Game.save_dir = "user://test_tree_saves"
	for s in range(0, Game.SLOT_COUNT + 1):
		Game.delete_slot(s)
		for v in [1, 2, 3]:
			if FileAccess.file_exists(Game.slot_path(s) + ".tree%d.bak" % v):
				DirAccess.remove_absolute(Game.slot_path(s) + ".tree%d.bak" % v)
	var cur := TreeRules.tree_version(Data.passive_migrations)
	var d0 := _shape_save(SHAPES[2])
	T.check(int(d0["version"]) >= 4 and int(d0["tree_version"]) == cur, "save v4+ writes tree_version", "%s/%s" % [d0["version"], d0.get("tree_version")])
	# a version-3 file (= tree 1) in every slot shape (10 manual slots + autosave): unchanged while the
	# tree is still version 1; from Phase 2 (tree 2) every spent point is refunded and a .tree1.bak kept
	for s in range(0, Game.SLOT_COUNT + 1):
		var d := _as_v3(_shape_save(SHAPES[s]))
		var want: Array = d["allocated"]
		Game._write_atomic(Game.slot_path(s), JSON.stringify(d, "\t"))
		var ok: bool = Game.load_game(s)
		var ch = Game.ch
		var label := "%s (%s L%d, %d nodes)" % ["autosave" if s == 0 else "slot %d" % s, SHAPES[s][0], SHAPES[s][1], want.size()]
		if cur == 1 or want.size() <= 1:
			T.check(ok and ch.allocated == want and ch.tree_refund.is_empty() and Game.tree_notice == "",
				"v3 save in %s keeps its passives" % label, "%s vs %s %s" % [ch.allocated.size(), want.size(), ch.tree_refund])
			T.check(not FileAccess.file_exists(Game.slot_path(s) + ".tree1.bak"), "v3 save in slot %d: no backup needed" % s)
		else:
			T.check(ok and ch.allocated == [ch.class_def()["start_passive"]] and int(ch.tree_refund.get("from_version", 0)) == 1
				and ch.available_passive_points() == ch.total_passive_points(),
				"v3 save in %s: full refund to tree %d" % [label, cur], "%s %s" % [ch.allocated.size(), ch.tree_refund])
			T.check(FileAccess.file_exists(Game.slot_path(s) + ".tree1.bak"), "v3 save in slot %d: .tree1.bak kept" % s)
		T.check(ch.available_passive_points() >= 0 and ch.class_id == SHAPES[s][0], "v3 save in slot %d: class and points sane" % s)
	# a missing node -> full refund, message once, backup once
	var dm := _as_v3(_shape_save(SHAPES[2]))
	var spent := 0
	for id in dm["allocated"]:
		spent += int(Data.passives[id]["cost"])
	dm["allocated"].append("zz_removed_node")
	Game._write_atomic(Game.slot_path(4), JSON.stringify(dm))
	Game.load_game(4)
	var ch2 = Game.ch
	T.check(ch2.allocated == [ch2.class_def()["start_passive"]], "removed node in a save -> full refund to the class start")
	T.check(ch2.available_passive_points() == ch2.total_passive_points(), "full refund gives every point back", "%d/%d" % [ch2.available_passive_points(), ch2.total_passive_points()])
	T.check(int(ch2.tree_refund.get("points", 0)) == spent, "refund records the points given back", str(ch2.tree_refund))
	var want_ids := []
	for id in dm["allocated"]:
		if id != ch2.class_def()["start_passive"] and Data.passives.has(id) and not want_ids.has(id):
			want_ids.append(id)
	T.check(Array(ch2.tree_refund.get("ids", [])) == want_ids, "refund records the refunded node ids (still in the tree)", str(ch2.tree_refund.get("ids", [])))
	T.check(FileAccess.file_exists(Game.slot_path(4) + ".tree1.bak"), "refund keeps a .bak of the original file")
	var msgs := []
	var cb := func(text, _c): msgs.append(text)
	Events.message.connect(cb)
	Game._show_tree_notice(null)
	Game._show_tree_notice(null)
	Events.message.disconnect(cb)
	T.check(msgs.size() == 1 and str(msgs[0]).contains("refunded"), "refund message is shown exactly once", str(msgs))
	# the refunded character saves with the current tree and loads cleanly
	var again: Dictionary = JSON.parse_string(JSON.stringify(ch2.to_dict()))
	Game.load_from_dict(again)
	T.check(Game.ch.tree_refund.is_empty() and Game.tree_notice == "", "after a refund the next load is clean")
	# a tree_version bump refunds everyone, even valid allocations
	var dv := _shape_save(SHAPES[5])
	Data.passive_migrations["tree_version"] = cur + 1
	Game._write_atomic(Game.slot_path(5), JSON.stringify(dv))
	Game.load_game(5)
	T.check(Game.ch.allocated.size() == 1 and not Game.ch.tree_refund.is_empty(), "tree_version bump -> full refund of a legal tree", str(Game.ch.tree_refund))
	T.check(FileAccess.file_exists(Game.slot_path(5) + ".tree%d.bak" % cur), "tree_version bump keeps a .bak named after the old version")
	T.check(int(Game.ch.to_dict()["tree_version"]) == cur + 1, "refunded save is written with the new tree_version")
	var fresh := _shape_save(SHAPES[0])   # level 1, nothing spent: no message needed
	fresh["tree_version"] = cur
	Game.load_from_dict(fresh)
	T.check(Game.ch.tree_refund.is_empty() and Game.tree_notice == "", "tree_version bump with nothing spent stays silent")
	Data.passive_migrations["tree_version"] = cur
	# illegal allocations are refunded too
	var dd := _shape_save(SHAPES[0])
	dd["allocated"] = [Data.classes["warrior"]["start_passive"], "xe_ks"]
	dd["level"] = 60
	Game.load_from_dict(dd)
	T.check(Game.ch.allocated.size() == 1 and Game.ch.tree_refund.get("reason", "").contains("not connected"), "disconnected allocation -> full refund", str(Game.ch.tree_refund))
	var dp := _shape_save(SHAPES[2])
	dp["level"] = 3
	dp["bonus_passive_points"] = 0
	Game.load_from_dict(dp)
	T.check(Game.ch.allocated.size() == 1 and Game.ch.tree_refund.get("reason", "").contains("points spent"), "over-spent allocation -> full refund", str(Game.ch.tree_refund))
	var dn := _shape_save(SHAPES[0])
	dn["allocated"] = []
	Game.load_from_dict(dn)
	T.check(Game.ch.allocated == [Data.classes["warrior"]["start_passive"]] and Game.ch.tree_refund.is_empty(), "save without its start node gets it back silently")
	var dnew := _shape_save(SHAPES[1])
	var want2: Array = dnew["allocated"]
	dnew["tree_version"] = cur + 5
	Game.load_from_dict(dnew)
	T.check(Game.ch.allocated == want2, "a save from a newer tree keeps a legal allocation")
	for s in range(0, Game.SLOT_COUNT + 1):
		Game.delete_slot(s)
		for v in [1, cur, cur + 1]:
			if FileAccess.file_exists(Game.slot_path(s) + ".tree%d.bak" % v):
				DirAccess.remove_absolute(Game.slot_path(s) + ".tree%d.bak" % v)
	Game.save_dir = old_dir
	Game.current_slot = old_slot
	Game.tree_notice = ""

# ------------------------------------------------------------------ behavioural flag tests
func _class_for(node_id: String) -> String:
	var best := ""
	var bc := 1 << 30
	for cls in ["warrior", "ranger", "mage"]:
		var c: Dictionary = TreeRules.cheapest_costs(Data.passives, Data.classes[cls]["start_passive"])
		if c.has(node_id) and int(c[node_id]) < bc:
			bc = int(c[node_id])
			best = cls
	return best

func _node_with_flag(f: String) -> String:
	for n in Data.passive_list:
		if n.get("flags", []).has(f):
			return n["id"]
	return ""

## Puts the player in a dungeon as the class nearest to node_id, with only the start allocated.
func _enter_for(cls: String) -> void:
	if cls == cur_class and lv != null and is_instance_valid(lv) and Game.level == lv:
		return
	Game.new_character(cls)
	Game.ch.level = 60
	Game.ch.recalc()
	T.main.start_game()
	await T.frames(2)
	T.main.enter_dungeon("forgotten_depths", 77)
	await T.frames(3)
	lv = Game.level
	p = lv.player
	cur_class = cls
	for x in lv.enemies:
		x.set_physics_process(false)
	e = T._nearest_enemy(lv, p)
	e.max_life = 100000.0
	e.life = 90000.0

func _alloc(node_id: String) -> bool:
	var ch = Game.ch
	ch.allocated = [ch.class_def()["start_passive"]]
	var ok: bool = node_id == "" or ch.allocate_path(node_id)
	ch.recalc()
	p.refresh_stats()
	p.buffs.clear()
	p.ch.active_buffs = []
	ch.recalc()
	p.refresh_stats()
	p.momentum = 0
	p.invuln_t = 0
	p.dodge_t = 0
	p.dodge_cd = 0
	p.busy = 0
	p.life = p.max_life
	p.mana = p.ch.final.get("max_mana", 100.0)
	p.statuses.clear()
	e.statuses.clear()
	e.life = 90000.0
	return ok

func test_flag_behaviours() -> void:
	var reg: Dictionary = Data.passive_flags.get("flags", {})
	var order := {}
	for f in reg:
		var nid := _node_with_flag(f)
		T.check(nid != "", "tree flag %s is used by a node" % f)
		if nid == "":
			continue
		var cls := _class_for(nid)
		if not order.has(cls):
			order[cls] = []
		order[cls].append([f, nid])
	for cls in order:
		await _enter_for(cls)
		for pair in order[cls]:
			var f: String = pair[0]
			var nid: String = pair[1]
			T.check(_alloc(nid), "tree flag %s: %s routes and allocates for a L60 %s" % [f, nid, cls])
			T.check(Game.ch.stats.has_flag(f), "tree flag %s: active after allocation" % f)
			if has_method("flag_" + f):
				await call("flag_" + f, nid)

func _pk(dmg: Dictionary, tags: Array = []) -> Dictionary:
	return {"dmg": dmg, "crit_chance": 0.0, "crit_mult": 2.0, "faction": "player", "status": [], "tags": tags, "flags": Game.ch.stats.flags.duplicate()}

func _hit_taken(rolled: Dictionary, is_attack: bool) -> float:
	p.invuln_t = 0
	p.dodge_t = 0
	p.life = p.max_life
	var l0: float = p.life
	p.receive_hit(rolled, {"is_attack": is_attack}, null, false)
	return l0 - p.life

func _no_avoid() -> void:
	p.ch.final["evasion"] = 0
	p.ch.final["block_chance"] = 0
	p.ch.final["damage_reduction"] = 0
	p.ch.final["armour"] = 0

func flag_momentum(nid: String) -> void:
	var cold: float = p.damage_more({"kind": "attack"})
	for i in 5:
		p.register_hit()
	var hot: float = p.damage_more({"kind": "attack"})
	T.check(absf(cold - 0.9) < 0.001 and absf(hot - 1.15) < 0.001, "behaviour momentum: first hit 10% less, 5 hits = 15% more", "%.3f %.3f" % [cold, hot])
	_alloc("")
	p.register_hit()
	T.check(absf(p.damage_more({"kind": "attack"}) - 1.0) < 0.001, "behaviour momentum: no effect without the node")

func flag_bulwark(nid: String) -> void:
	_no_avoid()
	p.ch.final["block_chance"] = 100
	p.receive_hit({"physical": 20.0}, {"is_attack": true}, null, false)
	T.check(p.has_buff("bulwark"), "behaviour bulwark: blocking grants the buff")
	_alloc("")
	_no_avoid()
	p.ch.final["block_chance"] = 100
	p.receive_hit({"physical": 20.0}, {"is_attack": true}, null, false)
	T.check(not p.has_buff("bulwark"), "behaviour bulwark: no buff without the node")

func flag_fortress(nid: String) -> void:
	_no_avoid()
	p.still_t = 0.0
	var moving := _hit_taken({"fire": 100.0}, false)
	p.still_t = 2.0
	var still := _hit_taken({"fire": 100.0}, false)
	T.check(moving > 0 and absf(still / moving - 0.7) < 0.02, "behaviour fortress: standing still takes 30% less", "%.1f vs %.1f" % [still, moving])

func flag_perfect_aim(nid: String) -> void:
	var pk := _pk({"physical": [100.0, 100.0]}, ["projectile"])
	var at: Vector2 = e.global_position
	var far: float = Combat._conditional(pk, e, at + Vector2(250, 0))
	var mid: float = Combat._conditional(pk, e, at + Vector2(140, 0))
	var near: float = Combat._conditional(pk, e, at + Vector2(50, 0))
	T.check(absf(far / mid - 1.3) < 0.01 and absf(near / mid - 0.75) < 0.01, "behaviour perfect_aim: far +30%, near (< 70 units) -25%", "%.2f %.2f %.2f" % [far, mid, near])

func flag_convergence(nid: String) -> void:
	var pk := _pk({"fire": [100.0, 100.0]})
	var bare: float = Combat._conditional(pk, e, Vector2.INF)
	e.add_status("chill", 3.0, {})
	var combo: float = Combat._conditional(pk, e, Vector2.INF)
	e.statuses.clear()
	T.check(absf(combo / bare - 1.35 / 0.9) < 0.01, "behaviour convergence: fire vs chilled 35% more, vs clean 10% less", "%.2f %.2f" % [bare, combo])

func flag_void_pact(nid: String) -> void:
	var pk := _pk({"void": [100.0, 100.0]})
	var bare: float = Combat._conditional(pk, e, Vector2.INF)
	e.add_status("shock", 3.0, {"mag": 1.2})
	var ail: float = Combat._conditional(pk, e, Vector2.INF)
	e.statuses.clear()
	T.check(absf(ail / bare - 1.25) < 0.01, "behaviour void_pact: 25% more vs ailing enemies", "%.2f" % (ail / bare))

func flag_executioner(nid: String) -> void:
	e.life = 20000.0   # 20% of 100000
	var crits := 0
	var base := -1.0
	for i in 10:
		var pk := _pk({"fire": [1000.0, 1000.0]})
		pk["flags"] = {}
		if base < 0:
			var b0: float = e.life
			Combat.deal(pk, p, e)
			base = b0 - e.life
		pk["flags"] = Game.ch.stats.flags.duplicate()
		e.life = 20000.0
		var l0: float = e.life
		Combat.deal(pk, p, e)
		if l0 - e.life > base * 1.5:
			crits += 1
	T.check(crits == 10, "behaviour executioner: hits below 35% life always crit", str(crits))

func flag_vampiric(nid: String) -> void:
	p.life = p.max_life * 0.5
	var l0: float = p.life
	Combat.deal(_pk({"physical": [500.0, 500.0]}), p, e)
	T.check(p.life > l0, "behaviour vampiric: hits leech life", "%.1f -> %.1f" % [l0, p.life])

func flag_crimson_dance(nid: String) -> void:
	Combat.apply_status(e, {"type": "bleed"}, {"physical": 100.0}, _pk({}))
	var with_dps: float = float(e.statuses["bleed"]["dps"])
	e.statuses.clear()
	Combat.apply_status(e, {"type": "bleed"}, {"physical": 100.0}, {"flags": {}})
	var base: float = float(e.statuses["bleed"]["dps"])
	e.statuses.clear()
	T.check(absf(with_dps / base - 1.6) < 0.01, "behaviour crimson_dance: bleeds deal 60% more")

func flag_wind_dancer(nid: String) -> void:
	var before: float = p.damage_more({"kind": "attack"})
	p.start_dodge()
	T.check(absf(before - 0.9) < 0.001 and p.has_buff("wind_dance"), "behaviour wind_dancer: 10% less until a dodge grants Wind Dance", "%.3f" % before)

func flag_mind_over_matter(nid: String) -> void:
	_no_avoid()
	var m0: float = p.mana
	var lost := _hit_taken({"fire": 50.0}, false)
	T.check(p.mana < m0 and lost < 50.0 * 0.75, "behaviour mind_over_matter: 30% of the hit comes from mana", "mana %.1f->%.1f life lost %.1f" % [m0, p.mana, lost])

func _costly_slot() -> int:
	for i in p.ch.loadout.size():
		var sk: Dictionary = p.skill_in_slot(i)
		if not sk.is_empty() and p.mana_cost(sk) > 0 and p.use_block_reason(sk) == "":
			return i
	return -1

func flag_blood_magic(nid: String) -> void:
	var i := _costly_slot()
	if i < 0:
		T.check(false, "behaviour blood_magic: found a skill with a cost")
		return
	var cost: float = p.mana_cost(p.skill_in_slot(i))
	var l0: float = p.life
	var m0: float = p.mana
	var used: bool = p.try_use_slot(i)
	T.check(used and absf(l0 - p.life - cost) < 0.01 and p.mana == m0, "behaviour blood_magic: the skill is paid with life", "cost %.1f life %.1f->%.1f mana %.1f->%.1f" % [cost, l0, p.life, m0, p.mana])
	_alloc("")
	p.cooldowns.clear()
	m0 = p.mana
	l0 = p.life
	T.check(p.try_use_slot(i) and p.mana < m0 and p.life == l0, "behaviour blood_magic: paid with mana without the node")

## [value with the node, value with the same route minus the node]
func _final_without(nid: String, key: String) -> Array:
	var ch = Game.ch
	var with_v: float = float(ch.final.get(key, 0))
	ch.allocated.erase(nid)
	ch.recalc()
	var without: float = float(ch.final.get(key, 0))
	ch.allocated.append(nid)
	ch.recalc()
	return [with_v, without]

func flag_automaton(nid: String) -> void:
	var v := _final_without(nid, "turret_limit")
	T.check(int(v[0]) == maxi(1, int(v[1]) - 1) or int(v[0]) == int(v[1]) - 1, "behaviour automaton: one fewer turret", str(v))
	T.check(absf(Game.ch.stats.more("turret_damage") - 1.7) < 0.001, "behaviour automaton: turrets deal 70% more", str(Game.ch.stats.more("turret_damage")))

func flag_one_mind(nid: String) -> void:
	var sb = Game.ch.stats
	T.check(absf(sb.more("minion_damage") - 1.6) < 0.001 and absf(sb.more("damage") - 0.7) < 0.001,
		"behaviour one_mind: minions 60% more, you 30% less", "%.2f %.2f" % [sb.more("minion_damage"), sb.more("damage")])

func flag_glass_cannon(nid: String) -> void:
	var v := _final_without(nid, "max_life")
	T.check(absf(v[0] / v[1] - 0.6) < 0.02 and absf(Game.ch.stats.more("damage") - 1.4) < 0.001, "behaviour glass_cannon: 40% less life, 40% more damage", str(v))

# ------------------------------------------------------------------ Phase 2 flags (24 behaviour nodes)
const AoEScript = preload("res://scripts/entities/aoe.gd")
const TurretScript = preload("res://scripts/entities/turret.gd")
const MineScript = preload("res://scripts/entities/mine.gd")

## Puts an enemy at an offset from the player (enemy physics is off in these tests).
func _place(x, off: Vector2) -> void:
	x.global_position = p.global_position + off

## A second live enemy for spread/chain tests, cleaned and placed near e.
func _other_enemy(off: Vector2):
	for x in lv.enemies:
		if is_instance_valid(x) and x.alive and x != e:
			x.statuses.clear()
			x.max_life = 100000.0
			x.life = 90000.0
			x.global_position = e.global_position + off
			return x
	return null

func _aoe_count() -> int:
	var n := 0
	for c in lv.floor_layer.get_children():
		if c.get_script() == AoEScript and not c.is_queued_for_deletion():
			n += 1
	return n

func _crit_pk(dmg: Dictionary, tags: Array) -> Dictionary:
	var pk := _pk(dmg, tags)
	pk["crit_chance"] = 100.0
	return pk

func flag_opened_veins(nid: String) -> void:
	Combat.deal(_crit_pk({"physical": [100.0, 100.0]}, ["melee", "attack"]), p, e)
	T.check(e.has_status("bleed"), "behaviour opened_veins: melee crit inflicts bleed")
	_alloc("")
	Combat.deal(_crit_pk({"physical": [100.0, 100.0]}, ["melee", "attack"]), p, e)
	T.check(not e.has_status("bleed"), "behaviour opened_veins: no bleed without the node")

func flag_blood_scent(nid: String) -> void:
	p.life = p.max_life * 0.5
	e.add_status("bleed", 3.0, {"dps": 1.0, "dtype": "physical"})
	var l0: float = p.life
	p.on_kill(e)
	var gain: float = p.life - l0
	_alloc("")
	p.life = p.max_life * 0.5
	e.add_status("bleed", 3.0, {"dps": 1.0, "dtype": "physical"})
	l0 = p.life
	p.on_kill(e)
	var base: float = p.life - l0
	T.check(absf(gain - base - p.max_life * 0.04) < 1.0, "behaviour blood_scent: killing a bleeding enemy heals 4% life", "%.1f vs %.1f" % [gain, base])

func flag_blood_frenzy(nid: String) -> void:
	_place(e, Vector2(40, 0))
	var sk := {"id": "x", "kind": "attack"}
	var t0: float = p.use_time_for(sk)
	e.add_status("bleed", 5.0, {"dps": 1.0, "dtype": "physical"})
	var t1: float = p.use_time_for(sk)
	T.check(p.frenzy_count() >= 1 and absf(t0 / t1 - (1.0 + 0.04 * p.frenzy_count()) / (1.0 + 0.04 * (p.frenzy_count() - 1))) < 0.01, "behaviour blood_frenzy: bleeding enemy nearby = 4% faster attacks", "%.3f %.3f" % [t0, t1])
	_no_avoid()
	var phys := _hit_taken({"physical": 100.0}, false)
	p.ch.final["life_regen"] = 10.0
	p.life = p.max_life * 0.9
	p._regen(1.0)
	var no_regen: bool = absf(p.life - p.max_life * 0.9) < 0.001
	p.life = p.max_life * 0.3
	p._regen(1.0)
	var low_regen: bool = p.life > p.max_life * 0.3
	_alloc("")
	_no_avoid()
	var phys0 := _hit_taken({"physical": 100.0}, false)
	T.check(absf(phys / phys0 - 1.1) < 0.01, "behaviour blood_frenzy: 10% more physical taken", "%.1f vs %.1f" % [phys, phys0])
	T.check(no_regen and low_regen, "behaviour blood_frenzy: no regeneration above 50% life only")

func _block_from(src) -> void:
	_no_avoid()
	p.ch.final["block_chance"] = 100
	p.receive_hit({"physical": 20.0}, {"is_attack": true}, src, false)

func flag_counterweight(nid: String) -> void:
	_block_from(null)
	T.check(p.has_buff("counterweight") and Game.ch.stats.inc("melee_damage") >= 40.0, "behaviour counterweight: block grants 40% inc melee damage")

func flag_staggering_guard(nid: String) -> void:
	_place(e, Vector2(30, 0))
	_block_from(e)
	T.check(e.has_status("stun"), "behaviour staggering_guard: block stuns the attacker")
	_alloc("")
	_block_from(e)
	T.check(not e.has_status("stun"), "behaviour staggering_guard: no stun without the node")

func flag_iron_riposte(nid: String) -> void:
	_place(e, Vector2(30, 0))
	var l0: float = e.life
	_block_from(e)
	T.check(e.life < l0 and p.riposte_t > 0.0, "behaviour iron_riposte: block triggers a counterattack", "%.0f -> %.0f" % [l0, e.life])
	l0 = e.life
	_block_from(e)
	T.check(e.life == l0, "behaviour iron_riposte: 0.5s internal cooldown")
	p.start_dodge()
	T.check(p.dodge_t <= 0.0, "behaviour iron_riposte: cannot dodge roll")
	var c1: float = p.mana_cost(Data.skills["shield_charge"])
	_alloc("")
	var c0: float = p.mana_cost(Data.skills["shield_charge"])
	T.check(c0 > 0 and absf(c1 / c0 - 1.5) < 0.01, "behaviour iron_riposte: movement skills cost 50% more", "%.1f vs %.1f" % [c1, c0])

func flag_rallying_cry(nid: String) -> void:
	p.cooldowns = {"slow": 5.0, "fast": 1.0}
	e.add_status("stun", 3.0, {})
	p.on_kill(e)
	T.check(not p.cooldowns.has("fast") and p.cooldowns.has("slow"), "behaviour rallying_cry: stunned kill resets the shortest cooldown", str(p.cooldowns))
	p.cooldowns.clear()

func flag_war_herald(nid: String) -> void:
	_place(e, Vector2(30, 0))
	var sk: Dictionary = Data.skills["iron_guard"]
	p.exec.execute(p, sk, p.global_position)
	var t := 0.0
	for b in p.buffs:
		if b["id"] == sk["id"]:
			t = b["t"]
	T.check(absf(t - float(sk.get("duration", 5)) * 1.5) < 0.01 and e.has_status("stun"), "behaviour war_herald: buff lasts 50% longer and stuns nearby", "%.2f" % t)

func flag_volatile_mechanisms(nid: String) -> void:
	var a0 := _aoe_count()
	var tu = TurretScript.new()
	tu.level = lv
	tu.setup(p, Data.skills["ballista_turret"])
	tu.position = p.global_position
	lv.entity_layer.add_child(tu)
	tu.retire()
	var mi = MineScript.new()
	mi.level = lv
	mi.setup(p, Data.skills["explosive_mine"])
	mi.position = p.global_position + Vector2(400, 400)
	lv.floor_layer.add_child(mi)
	mi.retire()
	T.check(_aoe_count() == a0 + 2, "behaviour volatile_mechanisms: retiring turret and trap explode", "%d -> %d" % [a0, _aoe_count()])
	await T.frames(2)
	_alloc("")
	a0 = _aoe_count()
	var tu2 = TurretScript.new()
	tu2.level = lv
	tu2.setup(p, Data.skills["ballista_turret"])
	lv.entity_layer.add_child(tu2)
	tu2.retire()
	T.check(_aoe_count() == a0, "behaviour volatile_mechanisms: no explosion without the node")

func flag_overclock(nid: String) -> void:
	var tu = TurretScript.new()
	tu.level = lv
	tu.setup(p, Data.skills["ballista_turret"])
	lv.entity_layer.add_child(tu)
	tu.global_position = p.global_position + Vector2(50, 0)
	var near: bool = tu.overclocked()
	tu.global_position = p.global_position + Vector2(300, 0)
	var far: bool = tu.overclocked()
	_alloc("")
	tu.global_position = p.global_position + Vector2(50, 0)
	var off: bool = tu.overclocked()
	tu.expire()
	T.check(near and not far and not off, "behaviour overclock: faster only near the owner and with the node")

func flag_clockwork_mind(nid: String) -> void:
	var v := _final_without(nid, "turret_limit")
	T.check(int(v[0]) == int(v[1]) + 2, "behaviour clockwork_mind: +2 turrets", str(v))
	var own: float = Combat._conditional(_pk({"physical": [1.0, 1.0]}), e, Vector2.INF)
	var tp := _pk({"physical": [1.0, 1.0]})
	tp["kind"] = "turret"
	var tur: float = Combat._conditional(tp, e, Vector2.INF)
	T.check(absf(own / tur - 0.7) < 0.01, "behaviour clockwork_mind: own hits 30% less, turrets unaffected", "%.2f %.2f" % [own, tur])
	Game.ch.final["weapon_crit"] = 12.0
	var sk := {"id": "ballista_turret", "kind": "turret", "crit": 0, "base_damage": [5, 5], "tags": []}
	var c1: float = Combat.player_packet(Game.ch, sk)["crit_chance"]
	T.check(c1 >= 12.0, "behaviour clockwork_mind: turrets use weapon crit", "%.1f" % c1)

func flag_agonising_toxins(nid: String) -> void:
	for i in 3:
		Combat.apply_status(e, {"type": "poison"}, {"physical": 100.0}, _pk({}))
	T.check(e.poison_stacks() == 3 and e.has_status("agony"), "behaviour agonising_toxins: poison stacks to 3 and inflicts agony", str(e.poison_stacks()))
	var dps3: float = float(e.statuses["poison"]["dps"])
	Combat.apply_status(e, {"type": "poison"}, {"physical": 100.0}, _pk({}))
	T.check(e.poison_stacks() == 3 and absf(float(e.statuses["poison"]["dps"]) - dps3) < 0.01, "behaviour agonising_toxins: capped at 3 stacks")
	e.tick_statuses(0.1)
	T.check(e.poison_stacks() == 3, "behaviour agonising_toxins: stacks tick")
	var stats := []
	for s in Combat.player_packet(Game.ch, {"id": "x", "kind": "spell", "base_damage": [1, 2], "tags": []})["status"]:
		stats.append(s["type"])
	T.check(stats.has("poison"), "behaviour agonising_toxins: hits can poison")
	_alloc("")
	for i in 3:
		Combat.apply_status(e, {"type": "poison"}, {"physical": 100.0}, _pk({}))
	T.check(e.poison_stacks() == 1 and not e.has_status("agony"), "behaviour agonising_toxins: no stacking without the node")

func flag_virulence(nid: String) -> void:
	var o = _other_enemy(Vector2(6, 0))
	if o == null:
		T.check(false, "behaviour virulence: a second enemy exists")
		return
	e.add_status("poison", 3.0, {"dps": 50.0, "dtype": "void"})
	p.on_kill(e)
	T.check(o.has_status("poison"), "behaviour virulence: poison spreads on death",
		"d=%.1f near=%s o=%s alive=%s st=%s" % [o.global_position.distance_to(e.global_position), str(lv.nearest_hostile(e.global_position, "player", 90.0, {e.get_instance_id(): true})), str(o), o.alive, str(o.statuses.keys())])
	o.statuses.clear()

func flag_venom_pact(nid: String) -> void:
	for i in 5:
		Combat.apply_status(e, {"type": "poison"}, {"physical": 100.0}, _pk({}))
	T.check(e.poison_stacks() == 5 and float(e.statuses["poison"]["t"]) > 5.0, "behaviour venom_pact: poisons stack and last 40% longer", "%d %.2f" % [e.poison_stacks(), float(e.statuses["poison"]["t"])])
	var pk: Dictionary = Combat.player_packet(Game.ch, {"id": "x", "kind": "spell", "base_damage": [1, 2], "crit": 50, "tags": []})
	var has_p := false
	for s in pk["status"]:
		has_p = has_p or s["type"] == "poison"
	T.check(pk["crit_chance"] == 0.0 and has_p, "behaviour venom_pact: hits cannot crit and can poison")

func flag_marked_for_death(nid: String) -> void:
	var o = _other_enemy(Vector2(6, 0))
	Combat.deal(_crit_pk({"physical": [100.0, 100.0]}, ["projectile"]), p, e)
	T.check(e.has_status("marked"), "behaviour marked_for_death: projectile crit marks")
	if o != null:
		var l0: float = o.life
		Combat.deal(_crit_pk({"physical": [100.0, 100.0]}, ["projectile"]), p, e)
		T.check(o.life < l0, "behaviour marked_for_death: crit vs marked hits a nearby enemy", "%.0f %.0f marked=%s" % [l0, o.life, e.has_status("marked")])

func flag_shadowstep(nid: String) -> void:
	_place(e, Vector2(30, 0))
	p.start_dodge()
	T.check(e.has_status("chill"), "behaviour shadowstep: dodge chills nearby enemies")
	p.dodge_t = 0
	_alloc("")
	_place(e, Vector2(30, 0))
	p.start_dodge()
	T.check(not e.has_status("chill"), "behaviour shadowstep: no chill without the node")
	p.dodge_t = 0

func flag_funeral_pyre(nid: String) -> void:
	e.add_status("ignite", 3.0, {"dps": 1.0, "dtype": "fire"})
	p.on_kill(e)
	T.check(p.has_buff("funeral_pyre"), "behaviour funeral_pyre: ignited kill grants the buff")

func flag_searing_insight(nid: String) -> void:
	e.add_status("ignite", 30.0, {"dps": 0.0, "dtype": "fire"})
	var pk := _pk({"physical": [100.0, 100.0]})
	pk["crit_chance"] = 1.0
	var hits := []
	for i in 200:
		e.life = 90000.0
		var l0: float = e.life
		Combat.deal(pk, p, e)
		hits.append(l0 - e.life)
	var lo: float = hits.min()
	var crits := 0
	for h in hits:
		if h > lo * 1.5:
			crits += 1
	T.check(crits > 25, "behaviour searing_insight: +25% crit chance vs ignited", str(crits))

func flag_avatar_of_embers(nid: String) -> void:
	var sk := {"id": "x", "kind": "spell", "dmg_type": "cold", "base_damage": [10, 10], "tags": ["spell", "cold"], "status": {"type": "chill", "chance": 50}}
	var pk: Dictionary = Combat.player_packet(Game.ch, sk)
	var types := []
	for s in pk["status"]:
		types.append(s["type"])
	T.check(pk["dmg"].has("fire") and not pk["dmg"].has("cold") and not types.has("chill"), "behaviour avatar_of_embers: cold converts to fire, chill becomes ignite", str(types))
	Combat.apply_status(e, {"type": "shock"}, {"fire": 100.0}, pk)
	T.check(not e.has_status("shock") and e.has_status("ignite"), "behaviour avatar_of_embers: cannot shock")

func _test_minion():
	var m = p.spawn_minion("skeleton_warrior", 10, p.global_position + Vector2(20, 0))
	m.set_physics_process(false)
	return m

func flag_marrow_feast(nid: String) -> void:
	var m = _test_minion()
	m.life = m.max_life * 0.5
	p.on_kill(e, m)
	T.check(m.life > m.max_life * 0.69, "behaviour marrow_feast: killing minion recovers 20% life", "%.1f/%.1f" % [m.life, m.max_life])
	m.queue_free()
	p.minions.erase(m)

func flag_necrotic_orders(nid: String) -> void:
	var pk: Dictionary = Combat.minion_packet(Game.ch, Data.summons["skeleton_warrior"], 10)
	var ok := false
	for s in pk["status"]:
		ok = ok or s["type"] == "frailty"
	T.check(ok, "behaviour necrotic_orders: minion hits can inflict frailty")

func flag_legion_of_bone(nid: String) -> void:
	var v := _final_without(nid, "minion_limit")
	T.check(int(v[0]) == int(v[1]) + 2, "behaviour legion_of_bone: +2 minions", str(v))
	T.check(absf(Game.ch.stats.more("minion_life") - 0.7) < 0.001 and absf(Game.ch.stats.more("damage") - 0.8) < 0.001, "behaviour legion_of_bone: drawbacks applied")
	var m = _test_minion()
	var a0 := _aoe_count()
	m.die(null)
	T.check(_aoe_count() == a0 + 1, "behaviour legion_of_bone: minion explodes on death")

func flag_frailty_bloom(nid: String) -> void:
	var o = _other_enemy(Vector2(6, 0))
	e.add_status("frailty", 3.0, {})
	p.on_kill(e)
	T.check(o != null and o.has_status("frailty"), "behaviour frailty_bloom: frailty spreads on death")
	if o != null:
		o.statuses.clear()

func flag_hexblight(nid: String) -> void:
	e.add_status("frailty", 30.0, {})
	for i in 40:
		Combat.deal(_pk({"physical": [10.0, 10.0]}), p, e)
	T.check(e.has_status("agony"), "behaviour hexblight: hits vs frail enemies inflict agony")
	_alloc("")
	e.add_status("frailty", 30.0, {})
	for i in 40:
		Combat.deal(_pk({"physical": [10.0, 10.0]}), p, e)
	T.check(not e.has_status("agony"), "behaviour hexblight: no agony without the node")

# ------------------------------------------------------------------ Phase 3 (bridges, conversions, cuts, Abyss points)
func test_phase3_data() -> void:
	var mig: Dictionary = Data.passive_migrations
	T.check(TreeRules.tree_version(mig) >= 3, "tree: tree_version >= 3 after the Phase 3 restructure")
	var gone := true
	for old in mig.get("history", {}).get("3", {}):
		gone = gone and not Data.passives.has(old)
	T.check(gone and mig["history"]["3"].size() == 14, "tree: the 14 Phase 0 cuts are gone and listed in history[3]")
	var cov: Dictionary = _validate(Data.passive_list)["report"]["status_coverage"]
	var thin := []
	for st in cov:
		if int(cov[st]) < 2:
			thin.append(st)
	T.check(thin.is_empty(), "tree: every status appears on at least 2 nodes", str(cov))
	var beh := 0
	var fixed := 0   # Phase 4 choice nodes (masteries, sockets) are a separate layer, not counted
	for n in Data.passive_list:
		if n["type"] in ["mastery", "socket"]:
			continue
		fixed += 1
		if not n.get("flags", []).is_empty():
			beh += 1
	T.check(beh * 4 >= fixed, "tree: at least 25% of fixed nodes change behaviour", "%d/%d" % [beh, fixed])
	for b in [["h_wr3", "p3_hk_ks"], ["h_rm3", "p3_hs_ks"], ["h_mw3", "p3_sb_ks"]]:
		T.check(Data.passives.has(b[1]) and Data.passives[b[0]].get("flags", []).size() > 0, "tree: bridge %s has a behaviour centre and keystone %s" % b)
	T.check(Data.passives["xp_ks"].get("exclusive_with", []).has("p2_ks_embers"), "tree: Prismatic Soul excludes Avatar of Embers")
	# Abyss milestone points: 59 levels + 6 bosses + 7 Abyss depths = the L60 budget
	var ch = Game.ch
	var best0: int = int(ch.progress.get("abyss_best", 0))
	var depths: Array = Data.passive_flags.get("abyss_point_depths", [])
	T.check(59 + 6 + depths.size() == int(Data.passive_flags.get("budget_l60", 0)), "tree: 59 + 6 boss + %d Abyss points = budget_l60" % depths.size())
	ch.progress["abyss_best"] = 0
	var t0: int = ch.total_passive_points()
	ch.progress["abyss_best"] = 9
	T.check(ch.total_passive_points() == t0, "abyss points: none below depth 10")
	ch.progress["abyss_best"] = 35
	T.check(ch.total_passive_points() == t0 + 3, "abyss points: depth 35 gives 3")
	ch.progress["abyss_best"] = 99
	T.check(ch.total_passive_points() == t0 + depths.size(), "abyss points: all %d past the last depth" % depths.size())
	var d: Dictionary = ch.to_dict()
	var ch2 = ch.get_script().new()
	ch2.from_dict(d)
	T.check(ch2.total_passive_points() == ch.total_passive_points(), "abyss points survive save/load (derived from abyss_best)")
	ch.progress["abyss_best"] = best0
	# Phase D2 fix: a tree that spends the Abyss points is kept on load (progress loads after
	# the passives, so the check used to see 0 Abyss points and refunded the whole tree)
	var ca = ch.get_script().new()
	ca.class_id = ch.class_id
	ca.level = 10
	ca.progress["abyss_best"] = 99
	ca.allocated = [ca.class_def()["start_passive"]]
	var grew := true
	while grew and ca.available_passive_points() > 0:
		grew = false
		for n in Data.passive_list:
			if ca.available_passive_points() <= 0:
				break
			var nid: String = n["id"]
			if n.get("type", "") in ["minor", "greater"] and int(n.get("cost", 1)) == 1 and not ca.allocated.has(nid) and ca.can_allocate(nid) == "" and ca.allocate(nid):
				grew = true
	var spent_a: int = ca.allocated.size() - 1
	var ca2 = ch.get_script().new()
	ca2.from_dict(JSON.parse_string(JSON.stringify(ca.to_dict())))
	T.check(spent_a > ca.level - 1 + ca.bonus_passive_points and ca2.allocated.size() == ca.allocated.size() and ca2.tree_refund.is_empty(),
		"abyss points: a tree spending them is kept on load", "spent %d, loaded %d, refund %s" % [spent_a, ca2.allocated.size() - 1, str(ca2.tree_refund)])

func _crit_count(pk: Dictionary, n: int = 200) -> int:
	var hits := []
	for i in n:
		e.life = 90000.0
		var l0: float = e.life
		Combat.deal(pk, p, e)
		hits.append(l0 - e.life)
	var lo: float = hits.min()
	var c := 0
	for h in hits:
		if h > lo * 1.5:
			c += 1
	return c

func _status_types(pk: Dictionary) -> Array:
	var out := []
	for s in pk.get("status", []):
		out.append(s["type"])
	return out

func flag_hunter_knight(nid: String) -> void:
	var marks := 0
	for i in 100:
		e.statuses.clear()
		Combat.deal(_pk({"physical": [10.0, 10.0]}, ["melee", "attack"]), p, e)
		if e.has_status("marked"):
			marks += 1
	T.check(marks >= 5 and marks <= 40, "behaviour hunter_knight: melee hits Mark about 20% of the time", str(marks))
	e.statuses.clear()
	e.add_status("marked", 60.0, {})
	var pk := _pk({"physical": [100.0, 100.0]}, ["projectile"])
	pk["crit_chance"] = 1.0
	var c := _crit_count(pk)
	T.check(c > 15, "behaviour hunter_knight: +15% crit chance for projectiles vs Marked", str(c))

func flag_pinning_shot(nid: String) -> void:
	e.add_status("marked", 5.0, {})
	Combat.deal(_pk({"physical": [10.0, 10.0]}, ["projectile"]), p, e)
	T.check(e.has_status("snare"), "behaviour pinning_shot: projectile hit vs Marked snares")
	e.statuses.clear()
	Combat.deal(_pk({"physical": [10.0, 10.0]}, ["projectile"]), p, e)
	T.check(not e.has_status("snare"), "behaviour pinning_shot: no snare vs unmarked")

func flag_run_them_down(nid: String) -> void:
	e.add_status("snare", 60.0, {})
	var pk := _pk({"physical": [100.0, 100.0]}, ["melee"])
	pk["crit_chance"] = 1.0
	var c := _crit_count(pk)
	T.check(c > 20, "behaviour run_them_down: +20% melee crit chance vs Snared", str(c))

func flag_twin_disciplines(nid: String) -> void:
	var mel := {"id": "m", "kind": "attack", "tags": ["melee"]}
	var prj := {"id": "r", "kind": "attack", "tags": ["projectile"]}
	p.last_style = ""
	p._before_skill(mel)
	var first: float = p.damage_more(mel)
	p._before_skill(prj)
	var alt: float = p.damage_more(prj)
	p._before_skill(prj)
	var rep: float = p.damage_more(prj)
	T.check(absf(alt / first - 1.25) < 0.01 and absf(rep / first - 0.9) < 0.01, "behaviour twin_disciplines: 25% more after switching, 10% less repeating", "%.3f %.3f %.3f" % [first, alt, rep])
	p.last_style = ""
	p.twin_mult = 1.0

func flag_hexshot(nid: String) -> void:
	p.last_curse = []
	p.exec.execute(p, Data.skills["curse_of_frailty"], e.global_position)
	T.check(p.last_curse.size() > 0, "behaviour hexshot: casting a curse remembers it")
	p.last_curse = [{"type": "frailty", "chance": 100, "duration": 8}]
	e.statuses.clear()
	var pk := _pk({"physical": [10.0, 10.0]}, ["projectile"])
	pk["cast"] = 9001
	Combat.deal(pk, p, e)
	T.check(e.has_status("frailty"), "behaviour hexshot: projectile hit applies the last curse")
	e.statuses.clear()
	Combat.deal(pk, p, e)
	T.check(not e.has_status("frailty"), "behaviour hexshot: only the first hit of a skill use")
	pk["cast"] = 9002
	Combat.deal(pk, p, e)
	T.check(e.has_status("frailty"), "behaviour hexshot: next skill use applies it again")
	p.last_curse = []

func flag_charged_quiver(nid: String) -> void:
	var pk: Dictionary = Combat.player_packet(Game.ch, {"id": "x", "kind": "attack", "tags": ["attack", "projectile"], "weapon_eff": 100})
	T.check(_status_types(pk).has("shock"), "behaviour charged_quiver: projectile packets can shock")
	var pk2: Dictionary = Combat.player_packet(Game.ch, {"id": "y", "kind": "spell", "tags": ["spell", "area"], "base_damage": [5, 5], "dmg_type": "fire"})
	T.check(not _status_types(pk2).has("shock"), "behaviour charged_quiver: not on non-projectiles")

func flag_overload(nid: String) -> void:
	var o = _other_enemy(Vector2(20, 0))
	e.add_status("shock", 3.0, {"mag": 1.2})
	var l0: float = o.life if o != null else 0.0
	p.on_kill(e)
	T.check(o != null and o.life < l0 and o.has_status("shock"), "behaviour overload: shocked kill shocks and damages nearby enemies")
	if o != null:
		o.statuses.clear()

func _buffed_avg(sk: Dictionary, stat: String) -> Array:
	var a0 := Combat.packet_average(Combat.player_packet(Game.ch, sk))
	p.add_buff("t_" + stat, [{"stat": stat, "type": "inc", "value": 100}], 5.0)
	var a1 := Combat.packet_average(Combat.player_packet(Game.ch, sk))
	p.buffs.clear()
	p.refresh_stats()
	return [a0, a1]

func flag_spell_archer(nid: String) -> void:
	var v := _buffed_avg({"id": "x", "kind": "attack", "tags": ["attack", "projectile"], "weapon_eff": 100}, "spell_damage")
	T.check(v[1] > v[0] * 1.3, "behaviour spell_archer: spell damage increases reach projectile attacks", "%.1f -> %.1f" % v)
	T.check(absf(Game.ch.stats.more("attack_speed") - 0.85) < 0.001, "behaviour spell_archer: 15% less attack speed")

func flag_battlemage(nid: String) -> void:
	var v := _buffed_avg({"id": "x", "kind": "attack", "tags": ["attack", "melee"], "weapon_eff": 100}, "spell_damage")
	T.check(v[1] > v[0] * 1.3, "behaviour battlemage: spell damage increases reach melee attacks", "%.1f -> %.1f" % v)
	var w := _buffed_avg({"id": "y", "kind": "spell", "tags": ["spell"], "base_damage": [10, 10], "dmg_type": "fire"}, "melee_damage")
	T.check(w[1] > w[0] * 1.3, "behaviour battlemage: melee damage increases reach spells", "%.1f -> %.1f" % w)
	T.check(absf(Game.ch.stats.more("max_life") - 0.85) < 0.001, "behaviour battlemage: 15% less maximum life")

func flag_spellblade(nid: String) -> void:
	var o = _other_enemy(Vector2(20, 0))
	p.last_spell_type = "cold"
	p.spellblade_t = 0.0
	var l0: float = o.life if o != null else 0.0
	Combat.deal(_pk({"physical": [100.0, 100.0]}, ["melee", "attack"]), p, e)
	T.check(o != null and o.life < l0 and o.has_status("chill") and p.spellblade_t > 0.0, "behaviour spellblade: melee hit bursts the last spell's element (cold chills)")
	if o != null:
		o.statuses.clear()
		Combat.deal(_pk({"physical": [100.0, 100.0]}, ["melee", "attack"]), p, e)
		T.check(not o.has_status("chill"), "behaviour spellblade: 0.6s internal cooldown")
		o.statuses.clear()
	p.last_spell_type = ""

func flag_rime_edge(nid: String) -> void:
	e.add_status("chill", 60.0, {})
	for i in 40:
		Combat.deal(_pk({"physical": [10.0, 10.0]}, ["melee"]), p, e)
	T.check(e.has_status("freeze"), "behaviour rime_edge: melee hits vs chilled enemies freeze")
	e.statuses.clear()
	for i in 40:
		Combat.deal(_pk({"physical": [10.0, 10.0]}, ["melee"]), p, e)
	T.check(not e.has_status("freeze"), "behaviour rime_edge: no freeze vs unchilled enemies")

func flag_shatter(nid: String) -> void:
	var o = _other_enemy(Vector2(20, 0))
	e.add_status("freeze", 3.0, {"mag": 1.1})
	var l0: float = o.life if o != null else 0.0
	p.on_kill(e)
	T.check(o != null and o.life < l0 and o.has_status("chill"), "behaviour shatter: frozen kill chills and damages nearby enemies")
	if o != null:
		o.statuses.clear()

func flag_brutal_force(nid: String) -> void:
	e.add_status("stun", 60.0, {})
	var pk := _pk({"physical": [1000.0, 1000.0]}, ["melee"])
	var fl: Dictionary = pk["flags"]
	pk["flags"] = {}
	var l0: float = e.life
	Combat.deal(pk, p, e)
	var base: float = l0 - e.life
	pk["flags"] = fl
	var crits := 0
	for i in 10:
		e.life = 90000.0
		l0 = e.life
		Combat.deal(pk, p, e)
		if l0 - e.life > base * 1.5:
			crits += 1
	T.check(crits == 10, "behaviour brutal_force: melee hits vs stunned enemies always crit", str(crits))

func flag_second_wind(nid: String) -> void:
	_no_avoid()
	p.second_wind_cd = 0.0
	p.life = p.max_life * 0.5
	p.receive_hit({"physical": p.max_life * 0.3}, {"is_attack": false}, null, false)
	T.check(p.has_buff("second_wind") and p.second_wind_cd > 19.0, "behaviour second_wind: dropping below 35% starts the regeneration")
	p.buffs.clear()
	p.refresh_stats()
	p.life = p.max_life * 0.3
	p.invuln_t = 0
	p.receive_hit({"physical": 1.0}, {"is_attack": false}, null, false)
	T.check(not p.has_buff("second_wind"), "behaviour second_wind: 20s cooldown")
	p.life = p.max_life

func flag_deadeye_mastery(nid: String) -> void:
	Combat.deal(_pk({"physical": [10.0, 10.0]}, ["projectile"]), p, e, e.global_position + Vector2(200, 0))
	T.check(e.has_status("snare"), "behaviour deadeye_mastery: long-range projectile hits snare")
	e.statuses.clear()
	Combat.deal(_pk({"physical": [10.0, 10.0]}, ["projectile"]), p, e, e.global_position + Vector2(60, 0))
	T.check(not e.has_status("snare"), "behaviour deadeye_mastery: no snare up close")

func flag_engineers_doctrine(nid: String) -> void:
	var pk: Dictionary = Combat.player_packet(Game.ch, Data.skills["ballista_turret"])
	T.check(_status_types(pk).has("shock"), "behaviour engineers_doctrine: turret hits can shock")

func flag_killer_instinct(nid: String) -> void:
	e.add_status("chill", 60.0, {})
	Combat.deal(_crit_pk({"physical": [10.0, 10.0]}, []), p, e)
	T.check(e.has_status("freeze"), "behaviour killer_instinct: crit vs chilled freezes")
	e.statuses.clear()
	e.add_status("chill", 60.0, {})
	Combat.deal(_pk({"physical": [10.0, 10.0]}, []), p, e)
	T.check(not e.has_status("freeze"), "behaviour killer_instinct: non-crits do not freeze")

func flag_pyroclasm(nid: String) -> void:
	var o = _other_enemy(Vector2(20, 0))
	e.add_status("ignite", 3.0, {"dps": 1.0, "dtype": "fire"})
	var l0: float = o.life if o != null else 0.0
	p.on_kill(e)
	T.check(o != null and o.life < l0, "behaviour pyroclasm: ignited kill explodes")

func flag_commanders_edge(nid: String) -> void:
	p.add_buff("t_crit", [{"stat": "crit_chance", "type": "inc", "value": 100}, {"stat": "crit_multi", "type": "flat", "value": 50}], 5.0)
	var pk: Dictionary = Combat.minion_packet(Game.ch, Data.summons["skeleton_warrior"], 10)
	T.check(pk["crit_chance"] >= 9.9 and pk["crit_mult"] >= 1.99, "behaviour commanders_edge: minions use your crit", "%.1f x%.2f" % [pk["crit_chance"], pk["crit_mult"]])
	p.buffs.clear()
	p.refresh_stats()

func flag_rift_step(nid: String) -> void:
	_place(e, Vector2(30, 0))
	p.exec.execute(p, Data.skills["blink"], p.global_position + Vector2(-140, 0))
	T.check(e.has_status("snare"), "behaviour rift_step: blink snares enemies where you left")

func flag_festering_wounds(nid: String) -> void:
	e.add_status("snare", 60.0, {})
	Combat.apply_status(e, {"type": "bleed"}, {"physical": 100.0}, _pk({}))
	var t1: float = float(e.statuses["bleed"]["t"])
	e.statuses.clear()
	Combat.apply_status(e, {"type": "bleed"}, {"physical": 100.0}, _pk({}))
	var t0: float = float(e.statuses["bleed"]["t"])
	T.check(absf(t1 / t0 - 1.5) < 0.01, "behaviour festering_wounds: ailments last 50% longer on snared enemies", "%.2f / %.2f" % [t1, t0])

func flag_elemental_warding(nid: String) -> void:
	p.statuses.clear()
	p.add_status("chill", 2.0, {})
	T.check(p.statuses.has("chill") and absf(float(p.statuses["chill"]["t"]) - 1.0) < 0.01, "behaviour elemental_warding: elemental ailments on you last half as long")
	p.statuses.clear()

func flag_prismatic_soul(nid: String) -> void:
	p.statuses.clear()
	p.add_status("shock", 2.0, {"mag": 1.2})
	T.check(not p.statuses.has("shock"), "behaviour prismatic_soul: you cannot be shocked")
	var pk: Dictionary = Combat.player_packet(Game.ch, {"id": "x", "kind": "spell", "tags": ["spell", "fire"], "base_damage": [5, 5], "dmg_type": "fire", "status": {"type": "ignite", "chance": 100}})
	T.check(not _status_types(pk).has("ignite"), "behaviour prismatic_soul: your hits cannot ignite")
	Combat.apply_status(e, {"type": "chill"}, {"cold": 10.0}, _pk({}))
	T.check(not e.has_status("chill"), "behaviour prismatic_soul: you cannot chill")

func flag_tailwind(nid: String) -> void:
	p.dodge_cd = 5.0
	p._on_skill_used(Data.skills["blink"])
	T.check(p.dodge_cd <= 0.0, "behaviour tailwind: movement skills reset the dodge roll")

func flag_deathblow(nid: String) -> void:
	var o = _other_enemy(Vector2(40, 0))
	if o == null:
		T.check(false, "behaviour deathblow: needs a second enemy")
		return
	o.life = 5.0
	Combat.deal(_crit_pk({"physical": [1000.0, 1000.0]}, []), p, o)
	T.check(not o.alive and p.has_buff("deathblow"), "behaviour deathblow: crit kill grants the buff")
	p.buffs.clear()
	p.refresh_stats()

func flag_arcane_shell(nid: String) -> void:
	_no_avoid()
	p.arcane_shell_cd = 0.0
	p.life = p.max_life
	p.receive_hit({"physical": p.max_life * 0.2}, {"is_attack": false}, null, false)
	T.check(p.has_buff("arcane_shell"), "behaviour arcane_shell: a heavy hit grants the shell")
	p.buffs.clear()
	p.refresh_stats()
	p.life = p.max_life

func flag_abyssal_gaze(nid: String) -> void:
	var pk: Dictionary = Combat.player_packet(Game.ch, {"id": "x", "kind": "spell", "tags": ["spell", "void"], "base_damage": [5, 5], "dmg_type": "void"})
	T.check(_status_types(pk).has("frailty"), "behaviour abyssal_gaze: void hits can inflict frailty")

# ------------------------------------------------------------------ Phase 3b (archetype spurs)
const P3B := {"Earthbreaker": ["warrior", "p3b_eb_cap"], "Duelist": ["warrior", "p3b_du_cap"], "Trapper": ["ranger", "p3b_tr_cap"],
		"Barrage": ["ranger", "p3b_ba_cap"], "Tempest": ["mage", "p3b_ts_cap"], "Frostweaver": ["mage", "p3b_fw_cap"]}

func test_phase3b_data() -> void:
	T.check(TreeRules.tree_version(Data.passive_migrations) >= 4, "tree: tree_version >= 4 after Phase 3b")
	T.check(Data.passive_list.size() >= 310, "tree: Phase 3b grows the tree to ~320 nodes", str(Data.passive_list.size()))
	var budget := int(Data.passive_flags.get("budget_l60", 72))
	var costs := {}
	for cls in ["warrior", "ranger", "mage"]:
		costs[cls] = TreeRules.cheapest_costs(Data.passives, Data.classes[cls]["start_passive"])
	for cl in P3B:
		var n := 0
		var beh := 0
		for nd in Data.passive_list:
			if nd["cluster"] == cl and not (nd["type"] in ["mastery", "socket"]):   # Phase 4a/4b hang choice nodes off some spurs
				n += 1
				if not nd.get("flags", []).is_empty():
					beh += 1
		T.check(n == 14 and beh == 3, "tree: archetype spur %s has 14 nodes, 3 of them behaviour" % cl, "%d/%d" % [n, beh])
		var cap: String = P3B[cl][1]
		var home: String = P3B[cl][0]
		var reach := true
		for cls in costs:
			reach = reach and costs[cls].has(cap) and int(costs[cls][cap]) <= budget
		T.check(reach, "tree: every class reaches the %s capstone within budget" % cl)
		T.check(int(costs[home][cap]) <= 30, "tree: %s capstone is close to its own class (%s)" % [cl, home], str(costs[home][cap]))
	for k in ["p3b_eb_cap", "p3b_tr_cap", "p3b_fw_cap"]:
		T.check(Data.passives[k]["type"] == "keystone" and Data.passives[k].has("drawback"), "tree: %s is a keystone with a drawback" % k)
	T.check(Data.passives["p2_ks_clockwork"].get("exclusive_with", []).has("p3b_tr_cap"), "tree: Master Trapper excludes Clockwork Mind")
	T.check(Data.passives["p2_ks_embers"].get("exclusive_with", []).has("p3b_fw_cap") and Data.passives["xp_ks"].get("exclusive_with", []).has("p3b_fw_cap"),
		"tree: Glacial Heart excludes Avatar of Embers and Prismatic Soul")
	Game.new_character("ranger")
	Game.ch.level = 60
	Game.ch.recalc()
	Game.ch.allocate_path("p2_ks_clockwork")
	T.check(Game.ch.path_to("p3b_tr_cap").is_empty(), "exclusive: Clockwork Mind blocks the route to Master Trapper")

func _flag_off(f: String) -> void:
	Game.ch.stats.flags.erase(f)

func _flag_on(f: String) -> void:
	Game.ch.stats.flags[f] = 1

func _avg(sk: Dictionary) -> float:
	return Combat.packet_average(Combat.player_packet(Game.ch, sk))

func _far_others() -> void:
	for x in lv.enemies:
		if is_instance_valid(x) and x != e:
			x.global_position = e.global_position + Vector2(4000, 0)

func flag_tremor_lines(nid: String) -> void:
	T.check(_status_types(Combat.player_packet(Game.ch, Data.skills["ground_slam"])).has("snare"), "behaviour tremor_lines: slam hits snare")
	T.check(not _status_types(Combat.player_packet(Game.ch, Data.skills["cleave"])).has("snare"), "behaviour tremor_lines: other attacks do not")
	e.add_status("snare", 60.0, {})
	Combat.apply_status(e, {"type": "stun"}, {}, _pk({}))
	var t1: float = float(e.statuses["stun"]["t"])
	e.statuses.clear()
	Combat.apply_status(e, {"type": "stun"}, {}, _pk({}))
	var t0: float = float(e.statuses["stun"]["t"])
	T.check(absf(t1 / t0 - 1.5) < 0.01, "behaviour tremor_lines: stuns on snared enemies last 50% longer", "%.2f / %.2f" % [t1, t0])

func flag_shockwave(nid: String) -> void:
	var o = _other_enemy(Vector2(20, 0))
	e.add_status("stun", 3.0, {})
	var l0: float = o.life if o != null else 0.0
	p.on_kill(e)
	T.check(o != null and o.life < l0 and o.has_status("stun"), "behaviour shockwave: stunned kill damages and stuns nearby enemies")
	if o != null:
		o.statuses.clear()
	_alloc("")
	o = _other_enemy(Vector2(20, 0))
	e.add_status("stun", 3.0, {})
	l0 = o.life if o != null else 0.0
	p.on_kill(e)
	T.check(o != null and o.life == l0, "behaviour shockwave: nothing without the node")

func flag_earthbreaker(nid: String) -> void:
	var slam: Dictionary = Data.skills["ground_slam"]
	var a1 := _avg(slam)
	var st_on: Array = Combat.player_packet(Game.ch, slam)["status"]
	_flag_off("earthbreaker")
	var a0 := _avg(slam)
	_flag_on("earthbreaker")
	T.check(absf(a1 / a0 - 1.35) < 0.01, "behaviour earthbreaker: slams deal 35% more damage", "%.1f / %.1f" % [a1, a0])
	var always := false
	for s in st_on:
		always = always or (s["type"] == "stun" and float(s["chance"]) >= 100.0)
	T.check(always, "behaviour earthbreaker: slams always stun")
	T.check(absf(Game.ch.stats.more("attack_speed") - 0.8) < 0.001, "behaviour earthbreaker: 20% less attack speed")

func flag_feint(nid: String) -> void:
	p.feint_t = 0.0
	p.dodge_cd = 0.0
	p.dodge_t = 0.0
	p.start_dodge()
	p.dodge_t = 0.0
	T.check(p.feint_t > 0.0, "behaviour feint: dodge roll readies Feint")
	var pk := _pk({"physical": [100.0, 100.0]}, ["melee", "attack"])
	var l0: float = e.life
	Combat.deal(pk, p, e)
	var h1: float = l0 - e.life
	l0 = e.life
	Combat.deal(pk, p, e)
	var h2: float = l0 - e.life
	T.check(h1 > h2 * 1.5 and p.feint_t <= 0.0, "behaviour feint: the next melee hit crits, once", "%.1f vs %.1f" % [h1, h2])
	_alloc("")
	p.feint_t = 0.0
	p.start_dodge()
	p.dodge_t = 0.0
	T.check(p.feint_t <= 0.0, "behaviour feint: nothing without the node")

func flag_single_combat(nid: String) -> void:
	_far_others()
	Combat.deal(_pk({"physical": [10.0, 10.0]}, ["melee", "attack"]), p, e)
	T.check(e.has_status("marked"), "behaviour single_combat: melee hit on an isolated enemy Marks it")
	e.statuses.clear()
	var o = _other_enemy(Vector2(40, 0))
	Combat.deal(_pk({"physical": [10.0, 10.0]}, ["melee", "attack"]), p, e)
	T.check(o != null and not e.has_status("marked"), "behaviour single_combat: no Mark with another enemy close")

func flag_blade_dance(nid: String) -> void:
	p.buffs.clear()
	p.refresh_stats()
	var as0: float = Game.ch.final.get("attack_speed_mult", 1.0)
	for i in 3:
		Combat.deal(_crit_pk({"physical": [10.0, 10.0]}, ["melee", "attack"]), p, e)
	var stacks := 0
	for b in p.buffs:
		if b["id"] == "blade_dance":
			stacks = int(b.get("stacks", 0))
	T.check(stacks == 3 and Game.ch.final.get("attack_speed_mult", 1.0) > as0, "behaviour blade_dance: melee crits stack attack speed", str(stacks))
	for i in 3:
		Combat.deal(_crit_pk({"physical": [10.0, 10.0]}, ["melee", "attack"]), p, e)
	for b in p.buffs:
		if b["id"] == "blade_dance":
			stacks = int(b.get("stacks", 0))
	T.check(stacks == 4, "behaviour blade_dance: up to 4 stacks", str(stacks))
	p.buffs.clear()
	p.refresh_stats()

func flag_barbed_snares(nid: String) -> void:
	var st := _status_types(Combat.player_packet(Game.ch, Data.skills["bear_trap"]))
	T.check(st.has("snare") and st.has("bleed"), "behaviour barbed_snares: trap hits snare and can bleed", str(st))
	T.check(not _status_types(Combat.player_packet(Game.ch, Data.skills["quick_shot"])).has("snare"), "behaviour barbed_snares: not on attacks")

func flag_noxious_payload(nid: String) -> void:
	var pk := _pk({"physical": [10.0, 10.0]})
	pk["kind"] = "trap"
	e.add_status("snare", 60.0, {})
	for i in 6:
		Combat.deal(pk, p, e)
	T.check(e.poison_stacks() == 5 and e.has_status("agony"), "behaviour noxious_payload: trap hits stack poison to 5 on snared enemies, then Agony", str(e.poison_stacks()))
	e.statuses.clear()
	for i in 3:
		Combat.deal(pk, p, e)
	T.check(not e.has_status("poison"), "behaviour noxious_payload: no poison on unsnared enemies")

func flag_master_trapper(nid: String) -> void:
	T.check(p.use_block_reason(Data.skills["ballista_turret"]).begins_with("Master Trapper"), "behaviour master_trapper: turrets are blocked")
	var trap: Dictionary = Data.skills["bear_trap"]
	var a1 := _avg(trap)
	_flag_off("master_trapper")
	var a0 := _avg(trap)
	_flag_on("master_trapper")
	T.check(absf(a1 / a0 - 1.3) < 0.01, "behaviour master_trapper: traps deal 30% more damage", "%.1f / %.1f" % [a1, a0])
	var m = MineScript.new()
	m.level = lv
	m.setup(p, trap)
	T.check(m.arm_t <= 0.0, "behaviour master_trapper: traps arm instantly")
	m.free()
	var away: Vector2 = p.global_position - (e.global_position - p.global_position).normalized() * 60.0
	for i in 5:
		p.exec.execute(p, trap, away)
	var n := 0
	for d in p.deployables:
		if is_instance_valid(d) and d.get_meta("group", "") == "bear_trap":
			n += 1
	T.check(n == int(trap.get("max", 3)) + 1, "behaviour master_trapper: +1 trap of each kind", str(n))
	for d in p.deployables.duplicate():
		if is_instance_valid(d):
			d.expire()

func flag_volley_fire(nid: String) -> void:
	var ms: Dictionary = Data.skills["multishot"]
	var qs: Dictionary = Data.skills["quick_shot"]
	var c1: int = p.exec.proj_count(p, ms)
	var r1: int = p.exec.proj_pierce(p, qs)
	_flag_off("volley_fire")
	var c0: int = p.exec.proj_count(p, ms)
	var r0: int = p.exec.proj_pierce(p, qs)
	_flag_on("volley_fire")
	T.check(c1 == c0 + 2, "behaviour volley_fire: multi-projectile attacks fire 2 more", "%d vs %d" % [c1, c0])
	T.check(r1 == r0 + 1 and p.exec.proj_count(p, qs) == int(qs.get("count", 1)) + int(Game.ch.final.get("projectile_count", 0)),
		"behaviour volley_fire: single-projectile attacks pierce 1 more instead")

func flag_arrowstorm(nid: String) -> void:
	p.arrowstorm_n = 0
	var pk := _pk({"physical": [10.0, 10.0]}, ["projectile", "attack"])
	pk["is_attack"] = true
	var n0 := _aoe_count()
	for i in 9:
		Combat.deal(pk, p, e)
	T.check(_aoe_count() == n0, "behaviour arrowstorm: nothing before the 10th hit")
	Combat.deal(pk, p, e)
	T.check(_aoe_count() == n0 + 3, "behaviour arrowstorm: the 10th projectile attack hit calls 3 volleys", str(_aoe_count() - n0))
	for c in lv.floor_layer.get_children():
		if c.get_script() == AoEScript:
			c.queue_free()

func flag_endless_quiver(nid: String) -> void:
	p.pending.clear()
	for i in 200:
		p._on_skill_used(Data.skills["quick_shot"])
	var n: int = p.pending.size()
	p.pending.clear()
	for i in 100:
		p._on_skill_used(Data.skills["cleave"])
	var m: int = p.pending.size()
	p.pending.clear()
	T.check(n >= 12 and n <= 55 and m == 0, "behaviour endless_quiver: projectile attacks fire again ~15% of the time", "%d/200, melee %d" % [n, m])

func flag_conductive_web(nid: String) -> void:
	var o = _other_enemy(Vector2(30, 0))
	Combat.apply_status(e, {"type": "shock"}, {"lightning": 10.0}, _pk({}))
	T.check(o != null and o.has_status("shock"), "behaviour conductive_web: shock spreads to the nearest enemy")
	if o != null:
		o.statuses.clear()
	_alloc("")
	o = _other_enemy(Vector2(30, 0))
	Combat.apply_status(e, {"type": "shock"}, {"lightning": 10.0}, _pk({}))
	T.check(o != null and not o.has_status("shock"), "behaviour conductive_web: no spread without the node")

func flag_thunderhead(nid: String) -> void:
	_far_others()
	p.thunder_n = 0
	p.aim_pos = e.global_position
	var l0: float = e.life
	for i in 3:
		p._on_skill_used(Data.skills["spark"])
	T.check(e.life == l0 and not e.has_status("shock"), "behaviour thunderhead: nothing on the first 3 casts")
	p._on_skill_used(Data.skills["spark"])
	T.check(e.life < l0 and e.has_status("shock"), "behaviour thunderhead: the 4th lightning spell strikes and shocks")
	p.thunder_n = 0
	p.pending.clear()

func flag_static_cascade(nid: String) -> void:
	var o = _other_enemy(Vector2(40, 0))
	e.add_status("shock", 60.0, {"mag": 1.2})
	var l0: float = o.life if o != null else 0.0
	Combat.deal(_pk({"lightning": [100.0, 100.0]}, ["spell"]), p, e)
	T.check(o != null and o.life < l0, "behaviour static_cascade: lightning hit on a shocked enemy arcs")
	e.statuses.clear()
	if o != null:
		o.life = 90000.0
		Combat.deal(_pk({"lightning": [100.0, 100.0]}, ["spell"]), p, e)
		T.check(o.life == 90000.0, "behaviour static_cascade: no arc from an unshocked enemy")

func flag_cold_snap(nid: String) -> void:
	var o = _other_enemy(Vector2(30, 0))
	Combat.apply_status(e, {"type": "freeze"}, {"cold": 10.0}, _pk({}))
	T.check(o != null and o.has_status("chill"), "behaviour cold_snap: freezing chills nearby enemies")
	if o != null:
		o.statuses.clear()
	_alloc("")
	o = _other_enemy(Vector2(30, 0))
	Combat.apply_status(e, {"type": "freeze"}, {"cold": 10.0}, _pk({}))
	T.check(o != null and not o.has_status("chill"), "behaviour cold_snap: nothing without the node")

func flag_brittle(nid: String) -> void:
	e.add_status("freeze", 600.0, {"mag": 1.1})
	var pk := _pk({"physical": [100.0, 100.0]})
	pk["crit_chance"] = 1.0
	var c := _crit_count(pk)
	T.check(c > 30, "behaviour brittle: +30% crit chance against frozen enemies", str(c))
	e.statuses.clear()
	Combat.apply_status(e, {"type": "freeze"}, {"cold": 10.0}, _pk({}))
	var t1: float = float(e.statuses["freeze"]["t"])
	e.statuses.clear()
	var pk0 := _pk({})
	pk0["flags"].erase("brittle")
	Combat.apply_status(e, {"type": "freeze"}, {"cold": 10.0}, pk0)
	var t0: float = float(e.statuses["freeze"]["t"])
	T.check(absf(t1 / t0 - 1.3) < 0.01, "behaviour brittle: freezes last 30% longer", "%.2f / %.2f" % [t1, t0])

func flag_glacial_heart(nid: String) -> void:
	var pk := _pk({"cold": [100.0, 100.0]})
	e.add_status("chill", 60.0, {})
	var mc: float = Combat._conditional(pk, e, Vector2.INF)
	e.statuses.clear()
	e.add_status("freeze", 60.0, {"mag": 1.1})
	var mf: float = Combat._conditional(pk, e, Vector2.INF)
	e.statuses.clear()
	var mn: float = Combat._conditional(pk, e, Vector2.INF)
	T.check(absf(mf / mc - 1.4) < 0.01 and absf(mn / mc - 0.8) < 0.01, "behaviour glacial_heart: 40% more vs frozen, 20% less vs neither", "%.2f %.2f %.2f" % [mf, mc, mn])
	var chill := false
	for s in Combat.player_packet(Game.ch, Data.skills["frostbolt"])["status"]:
		chill = chill or (s["type"] == "chill" and float(s["chance"]) >= 100.0)
	T.check(chill, "behaviour glacial_heart: cold hits always chill")

# ------------------------------------------------------------------ Phase 4a masteries
func _mastery_nodes() -> Array:
	var out := []
	for n in Data.passive_list:
		if n["type"] == "mastery":
			out.append(n["id"])
	return out

func test_masteries() -> void:
	var reg: Dictionary = Data.passive_flags.get("masteries", {})
	var ms := _mastery_nodes()
	T.check(TreeRules.tree_version(Data.passive_migrations) >= 5, "mastery: tree_version >= 5 after Phase 4a")
	T.check(ms.size() == 12 and reg.size() == 9, "mastery: 12 mastery nodes over 9 groups", "%d/%d" % [ms.size(), reg.size()])
	var per_group := {}
	var budget := int(Data.passive_flags.get("budget_l60", 72))
	var reach_ok := true
	for id in ms:
		var n: Dictionary = Data.passives[id]
		per_group[n["mastery"]] = int(per_group.get(n["mastery"], 0)) + 1
		T.check(n["links"].size() == 1 and Data.passives[n["links"][0]]["type"] in ["notable", "greater"], "mastery: %s hangs off one notable" % id, str(n["links"]))
		T.check(reg[n["mastery"]]["options"].size() == 4, "mastery: %s offers 4 effects" % id)
		for cls in ["warrior", "ranger", "mage"]:
			var c := TreeRules.cheapest_costs(Data.passives, Data.classes[cls]["start_passive"])
			reach_ok = reach_ok and c.has(id) and int(c[id]) <= budget
	T.check(reach_ok, "mastery: every class reaches every mastery within budget")
	var twice := 0
	for g in per_group:
		if per_group[g] == 2:
			twice += 1
	T.check(twice == 3, "mastery: 3 groups appear twice (once-only rule matters)", str(per_group))
	# validator mutations
	var t := _copy(Data.passive_list)
	_find(t, ms[0])["mastery"] = "nope"
	_expect(t, "is not in passive_flags.json masteries", "a mastery with an unknown group")
	t = _copy(Data.passive_list)
	_find(t, ms[0])["mods"] = [{"stat": "str", "type": "flat", "value": 1}]
	_expect(t, "not mods/flags", "a mastery with its own mods")
	t = _copy(Data.passive_list)
	_find(t, "w_mel1")["mastery"] = "melee"
	_expect(t, "only mastery nodes carry", "a 'mastery' key on a minor node")
	var reg2: Dictionary = Data.passive_flags.duplicate(true)
	reg2["masteries"]["melee"]["options"][0]["mods"][0]["type"] = "more"
	_expect(Data.passive_list, "only flat/inc", "a 'more' mod in a mastery option", reg2)
	reg2 = Data.passive_flags.duplicate(true)
	reg2["masteries"]["bulwark"]["options"][0]["id"] = reg2["masteries"]["melee"]["options"][0]["id"]
	_expect(Data.passive_list, "is used twice", "a duplicated option id", reg2)
	Game.new_character("warrior")
	var ch = Game.ch
	ch.level = 60
	ch.gold = 100000
	ch.recalc()
	var mid := "p4_m_melee"
	var opts: Array = ch.mastery_options(mid)
	T.check(not ch.allocate_path(mid), "mastery: cannot be allocated without choosing an effect")
	T.check(not ch.allocate_path(mid, "bw_block"), "mastery: an effect of another group is refused")
	T.check(ch.allocate_path(mid, "melee_fury") and ch.mastery_choices.get(mid) == "melee_fury", "mastery: allocate with an effect")
	var before: float = ch.build_stats(ch.allocated, ch.active_buffs, null, {}).inc("melee_damage")
	T.check(absf(ch.stats.inc("melee_damage") - before - 20.0) < 0.01, "mastery: the chosen effect applies its mods", "%s -> %s" % [before, ch.stats.inc("melee_damage")])
	var g0: int = ch.gold
	T.check(ch.change_mastery(mid, "melee_tempo") == "" and ch.gold == g0 - ch.mastery_change_cost(), "mastery: changing the effect costs one refund")
	T.check(absf(ch.stats.inc("melee_damage") - before) < 0.01 and ch.stats.inc("attack_speed") > 0, "mastery: the old effect is removed on change")
	T.check(ch.change_mastery(mid, "melee_tempo") == "Already chosen", "mastery: re-choosing the same effect is refused")
	# once-only across two nodes of one group
	var a := "p4_m_bleed_w"
	var b := "p4_m_bleed_x"
	T.check(ch.allocate_path(a, "bl_chance"), "mastery: bleed mastery 1 allocated")
	T.check(not ch.allocate_path(b, "bl_chance"), "mastery: the same effect cannot be taken twice")
	T.check(ch.can_choose_mastery(b, "bl_chance").begins_with("Already chosen at"), "mastery: the refusal names the other node")
	T.check(ch.allocate_path(b, "bl_rend"), "mastery: a different effect of the same group is fine")
	T.check(ch.change_mastery(a, "bl_rend") != "", "mastery: cannot change into an effect held elsewhere")
	# never a route through a mastery
	var via := false
	for nid in Data.passives:
		var pth: Array = ch.path_to(nid)
		for i in range(0, pth.size() - 1):
			if ch.is_mastery(pth[i]):
				via = true
	T.check(not via, "mastery: no route passes through a mastery")
	# save round-trip
	var d: Dictionary = JSON.parse_string(JSON.stringify(ch.to_dict()))
	T.check(d.get("mastery_choices", {}).size() == 3, "mastery: choices are saved", str(d.get("mastery_choices")))
	var c2 = load("res://scripts/core/character_data.gd").new()
	c2.from_dict(d)
	T.check(c2.tree_refund.is_empty() and c2.mastery_choices.get(mid) == "melee_tempo" and c2.allocated.has(b), "mastery: choices load back")
	# bad choices -> full refund (policy: illegal allocation refunds everything)
	var bad: Dictionary = d.duplicate(true)
	bad["mastery_choices"].erase(mid)
	c2 = load("res://scripts/core/character_data.gd").new()
	c2.from_dict(bad)
	T.check(c2.allocated.size() == 1 and c2.tree_refund.get("reason", "").contains("no chosen effect"), "mastery: missing choice -> full refund", str(c2.tree_refund))
	bad = d.duplicate(true)
	bad["mastery_choices"][b] = "bl_chance"
	c2 = load("res://scripts/core/character_data.gd").new()
	c2.from_dict(bad)
	T.check(c2.allocated.size() == 1 and c2.tree_refund.get("reason", "").contains("chosen on both"), "mastery: duplicated effect in a save -> full refund", str(c2.tree_refund))
	bad = d.duplicate(true)
	bad["mastery_choices"][mid] = "pj_pierce"
	c2 = load("res://scripts/core/character_data.gd").new()
	c2.from_dict(bad)
	T.check(c2.allocated.size() == 1 and c2.tree_refund.get("reason", "").contains("not one of its options"), "mastery: wrong-group effect in a save -> full refund", str(c2.tree_refund))
	# refund clears the choice; preview with hypothetical choices
	T.check(ch.refund(a) and not ch.mastery_choices.has(a), "mastery: refund clears the choice")
	var ids: Array = ch.allocated.duplicate()
	ids.append(a)
	var pv: Dictionary = ch.preview_final(ids, null, {mid: "melee_tempo", b: "bl_rend", a: "bl_chance"})
	T.check(pv.size() > 0, "mastery: preview_final takes hypothetical choices")
	# no 'more' anywhere in options; every option mod stat exists
	var stats_ok := true
	for g in reg:
		for o in reg[g]["options"]:
			for m in o["mods"]:
				stats_ok = stats_ok and Data.stat_info.has(m["stat"]) and m["type"] != "more"
	T.check(stats_ok, "mastery: every option uses known stats and no 'more' mods")
	# the four mechanical options really reach the resolved sheet
	Game.new_character("ranger")
	ch = Game.ch
	ch.level = 60
	ch.recalc()
	var pc0: int = int(ch.final.get("projectile_count", 0))
	ch.allocate_path("p4_m_proj_r", "pj_split")
	T.check(int(ch.final.get("projectile_count", 0)) == pc0 + 1, "mastery: Split Shot adds a projectile")
	var tl0: int = int(ch.final.get("turret_limit", 0))
	ch.allocate_path("p4_m_deploy", "dp_turret")
	T.check(int(ch.final.get("turret_limit", 0)) == tl0 + 1, "mastery: Battery adds a turret")
	Game.new_character("warrior")

# ------------------------------------------------------------------ Phase 4b tree sockets
const SOCKETS := ["p4_s_w_in", "p4_s_w_out", "p4_s_r_in", "p4_s_r_out", "p4_s_m_in", "p4_s_m_out", "p4_s_wr", "p4_s_rm", "p4_s_mw"]

func _gem_total(c) -> int:
	var n := 0
	for k in c.gems:
		n += int(c.gems[k])
	return n + c.tree_gems.size()

func test_tree_sockets() -> void:
	var cfg: Dictionary = Data.passive_flags.get("tree_sockets", {})
	T.check(TreeRules.tree_version(Data.passive_migrations) >= 6, "socket: tree_version >= 6 after Phase 4b")
	var found := []
	for n in Data.passive_list:
		if n["type"] == "socket":
			found.append(n["id"])
	found.sort()
	var want := SOCKETS.duplicate()
	want.sort()
	T.check(found == want, "socket: 9 tree sockets (2 per class + 1 per bridge)", str(found))
	var budget := int(Data.passive_flags.get("budget_l60", 72))
	var reach_ok := true
	var shape_ok := true
	for id in SOCKETS:
		var n: Dictionary = Data.passives.get(id, {})
		shape_ok = shape_ok and int(n.get("cost", 0)) == 1 and n.get("mods", [1]).is_empty() and n["links"].size() in [1, 2]
		for l in n.get("links", []):
			shape_ok = shape_ok and Data.passives[l]["type"] in ["notable", "greater"]
	# a class reaches its own 2 sockets and its 2 bridge sockets (the far bridge sits behind
	# that bridge's keystone, like the bridge notables themselves)
	var own := {"warrior": ["p4_s_w_in", "p4_s_w_out", "p4_s_wr", "p4_s_mw"], "ranger": ["p4_s_r_in", "p4_s_r_out", "p4_s_wr", "p4_s_rm"],
		"mage": ["p4_s_m_in", "p4_s_m_out", "p4_s_rm", "p4_s_mw"]}
	var far := []
	for cls in own:
		var c := TreeRules.cheapest_costs(Data.passives, Data.classes[cls]["start_passive"])
		for id in own[cls]:
			if not (c.has(id) and int(c[id]) <= budget):
				reach_ok = false
				far.append("%s:%s" % [cls, id])
	T.check(shape_ok, "socket: each costs 1, has no mods and hangs off notables/greaters")
	T.check(reach_ok, "socket: each class reaches its own and its bridge sockets within budget", str(far))
	T.check(float(cfg.get("radius", 0)) > 0 and cfg.get("boost_pct", []).size() == Data.gem_cfg["tiers"].size(), "socket: radius set, one boost value per gem tier", str(cfg))
	var gems_ok := true
	for g in Data.gem_list:
		gems_ok = gems_ok and g.get("tree", []).size() > 0 and g.get("tree_tags", []).size() > 0
		for m in g.get("tree", []):
			gems_ok = gems_ok and Data.stat_info.has(m["stat"]) and m["type"] in ["flat", "inc"]
		for tg in g.get("tree_tags", []):
			gems_ok = gems_ok and Data.passive_flags["tags"].has(tg)
	T.check(gems_ok, "socket: every gem has a tree table (known stats, flat/inc) and known tree_tags")
	T.check(Loot.gem_summary("ruby:0").contains("Passive tree:"), "socket: gem summary shows the tree stats")
	for id in SOCKETS:
		T.check(TreeRules.nodes_in_radius(Data.passives, id, cfg).size() >= 6, "socket: %s has at least 6 boostable nodes in its ring" % id)
	# validator mutations
	var t := _copy(Data.passive_list)
	_find(t, "p4_s_w_in")["mods"] = [{"stat": "str", "type": "flat", "value": 1}]
	_expect(t, "come from its gem", "a socket with its own mods")
	t = _copy(Data.passive_list)
	_find(t, "p4_s_w_in")["cost"] = 2
	_expect(t, "sockets cost 1 point", "a socket costing 2")
	var reg2: Dictionary = Data.passive_flags.duplicate(true)
	reg2["tree_sockets"]["radius"] = 0
	_expect(Data.passive_list, "radius must be > 0", "a zero socket radius", reg2)
	# pure boost rule: max of overlapping sockets, tag match, radius, node types
	var by := {
		"s1": {"id": "s1", "type": "socket", "x": 0, "y": 0, "tags": ["generic"]},
		"s2": {"id": "s2", "type": "socket", "x": 50, "y": 0, "tags": ["generic"]},
		"a": {"id": "a", "type": "minor", "x": 30, "y": 0, "tags": ["fire"]},
		"b": {"id": "b", "type": "minor", "x": 30, "y": 0, "tags": ["cold"]},
		"c": {"id": "c", "type": "minor", "x": 500, "y": 0, "tags": ["fire"]},
		"k": {"id": "k", "type": "keystone", "x": 10, "y": 0, "tags": ["fire"]}}
	var bo := TreeRules.socket_boosts(by, ["s1", "s2", "a", "b", "c", "k"], {"s1": "ruby:0", "s2": "ruby:3"}, cfg, Data.gems)
	T.check(bo.get("a", 0.0) == float(cfg["boost_pct"][3]), "socket: overlapping sockets give the largest boost, no stacking", str(bo))
	T.check(not bo.has("b") and not bo.has("c") and not bo.has("k"), "socket: no boost without a shared tag, outside the radius or on keystones", str(bo))
	bo = TreeRules.socket_boosts(by, ["s1", "a"], {"s1": "ruby:0", "s2": "ruby:3"}, cfg, Data.gems)
	T.check(bo.get("a", 0.0) == float(cfg["boost_pct"][0]), "socket: an unallocated socket gives nothing", str(bo))
	# live character
	Game.new_character("warrior")
	var ch = Game.ch
	ch.level = 60
	ch.gold = 100000
	ch.recalc()
	var sid := "p4_s_w_in"
	T.check(ch.can_socket_tree_gem(sid, "onyx:0") == "Allocate the socket first", "socket: a gem needs the socket allocated")
	T.check(ch.allocate_path(sid), "socket: allocate by route (no choice needed)")
	T.check(ch.can_socket_tree_gem(sid, "onyx:0") == "You have no such gem", "socket: a gem must be in the pouch")
	# allocate every boostable node in the ring that the route allows
	for nid in TreeRules.nodes_in_radius(Data.passives, sid, cfg):
		if not ch.allocated.has(nid):
			ch.allocate_path(nid)
	var phys0: float = ch.stats.inc("physical_damage")
	var sb0 = ch.build_stats(ch.allocated, ch.active_buffs)
	ch.add_gem("onyx:0")
	ch.add_gem("onyx:3")
	var tot0 := _gem_total(ch)
	T.check(ch.socket_tree_gem(sid, "onyx:0") == "" and ch.tree_gems.get(sid) == "onyx:0" and not ch.gems.has("onyx:0"), "socket: socketing takes the gem from the pouch")
	var bo2: Dictionary = ch.socket_boosts(ch.allocated)
	T.check(bo2.size() > 0, "socket: Onyx boosts allocated melee/physical nodes in the ring", str(bo2))
	# expected change of melee_damage: only node mods (Onyx's tree table has no melee_damage)
	var exp_melee := 0.0
	var out_ok := true
	var sp := Vector2(Data.passives[sid]["x"], Data.passives[sid]["y"])
	for nid in bo2:
		out_ok = out_ok and sp.distance_to(Vector2(Data.passives[nid]["x"], Data.passives[nid]["y"])) <= float(cfg["radius"])
		for m in Data.passives[nid].get("mods", []):
			var add := float(m["value"]) * float(bo2[nid]) / 100.0
			if m["stat"] == "melee_damage" and m["type"] == "inc":
				exp_melee += add
			for ae in Data.attributes.get("effects", {}).get(m["stat"], []):   # e.g. str -> melee_damage
				if ae["stat"] == "melee_damage" and m["type"] == "flat":
					exp_melee += add * float(ae["per"])
	T.check(out_ok, "socket: every boosted node lies inside the radius")
	T.check(absf(ch.stats.inc("melee_damage") - sb0.inc("melee_damage") - exp_melee) < 0.01, "socket: the radius boost scales node values", "%.2f -> %.2f (exp +%.2f)" % [sb0.inc("melee_damage"), ch.stats.inc("melee_damage"), exp_melee])
	var exp_phys := 0.0
	for nid in bo2:
		for m in Data.passives[nid].get("mods", []):
			if m["stat"] == "physical_damage" and m["type"] == "inc":
				exp_phys += float(m["value"]) * float(bo2[nid]) / 100.0
	T.check(absf(ch.stats.inc("physical_damage") - phys0 - 4.0 - exp_phys) < 0.01, "socket: the gem's tree table applies (Chipped Onyx +4% physical)", "%.2f -> %.2f" % [phys0, ch.stats.inc("physical_damage")])
	# swap to a better grade: old gem back to the pouch, bigger boost
	T.check(ch.socket_tree_gem(sid, "onyx:3") == "" and ch.gems.get("onyx:0", 0) == 1 and ch.tree_gems[sid] == "onyx:3", "socket: swapping is free and returns the old gem")
	var bo3: Dictionary = ch.socket_boosts(ch.allocated)
	T.check(float(bo3.values()[0]) == float(cfg["boost_pct"][3]), "socket: a Flawless gem gives the top boost", str(bo3))
	T.check(_gem_total(ch) == tot0, "socket: no gem is created or lost by swapping")
	T.check(ch.can_socket_tree_gem(sid, "onyx:3") == "Already socketed", "socket: re-socketing the same gem is refused")
	# preview without the socket drops the gem
	var ids: Array = ch.allocated.duplicate()
	ids.erase(sid)
	T.check(ch.preview_final(ids).get("armour", 0) <= ch.final.get("armour", 0), "socket: preview without the socket drops its gem")
	# level requirement
	ch.add_gem("ruby:1")
	ch.level = 10
	T.check(ch.can_socket_tree_gem(sid, "ruby:1") == "Requires level %d" % Loot.gem_req("ruby:1"), "socket: gem level requirement applies")
	ch.level = 60
	ch.recalc()
	# save round-trip
	var d: Dictionary = JSON.parse_string(JSON.stringify(ch.to_dict()))
	T.check(d.get("tree_gems", {}).get(sid) == "onyx:3", "socket: tree gems are saved", str(d.get("tree_gems")))
	var c2 = load("res://scripts/core/character_data.gd").new()
	c2.from_dict(d)
	T.check(c2.tree_refund.is_empty() and c2.tree_gems.get(sid) == "onyx:3" and absf(c2.stats.inc("melee_damage") - ch.stats.inc("melee_damage")) < 0.01, "socket: tree gems load back with the same stats")
	var bad: Dictionary = d.duplicate(true)
	bad["tree_gems"]["p4_s_r_in"] = "topaz:0"   # socket not allocated -> gem goes to the pouch
	bad["tree_gems"]["p4_s_m_in"] = "nonsense:9"
	c2 = load("res://scripts/core/character_data.gd").new()
	c2.from_dict(bad)
	T.check(not c2.tree_gems.has("p4_s_r_in") and c2.gems.get("topaz:0", 0) == 1 and not c2.tree_gems.has("p4_s_m_in"), "socket: a gem in an unallocated socket returns to the pouch; unknown gems are dropped")
	bad = d.duplicate(true)
	bad["tree_version"] = int(d["tree_version"]) - 1   # full refund keeps every gem
	c2 = load("res://scripts/core/character_data.gd").new()
	c2.from_dict(bad)
	T.check(c2.allocated.size() == 1 and c2.tree_gems.is_empty() and c2.gems.get("onyx:3", 0) == 1 and _gem_total(c2) == _gem_total(ch), "socket: a full tree refund returns socketed gems to the pouch", str(c2.gems))
	# unsocket and refund
	T.check(ch.unsocket_tree_gem(sid) == "" and ch.gems.get("onyx:3", 0) == 1 and ch.tree_gems.is_empty(), "socket: removing is free and returns the gem")
	T.check(ch.unsocket_tree_gem(sid) == "The socket is empty", "socket: removing from an empty socket is refused")
	ch.socket_tree_gem(sid, "onyx:3")
	T.check(ch.refund(sid) and ch.gems.get("onyx:3", 0) == 1 and ch.tree_gems.is_empty(), "socket: refunding the socket returns its gem")
	T.check(ch.socket_boosts(ch.allocated).is_empty(), "socket: no boost once the socket is gone")
	ch.allocate_path(sid)
	ch.socket_tree_gem(sid, "onyx:3")
	ch.clear_tree_gems()
	T.check(ch.tree_gems.is_empty() and ch.gems.get("onyx:3", 0) == 1, "socket: clear_tree_gems (full respec) returns every gem")
	# never a route through a socket
	var via := false
	for nid in Data.passives:
		var pth: Array = ch.path_to(nid)
		for i in range(0, pth.size() - 1):
			if ch.is_socket(pth[i]):
				via = true
	T.check(not via, "socket: no route passes through a socket")
	Game.new_character("warrior")

# ------------------------------------------------------------------ Phase 5a: tree UI functions
const ViewScript = preload("res://scripts/ui/passive_tree_view.gd")
const PanelScript = preload("res://scripts/ui/passive_tree_panel.gd")

func _ui_char():
	Game.new_character("warrior")
	var ch = Game.ch
	ch.level = 60
	ch.gold = 50000
	ch.refresh_unlocks(false)
	ch.recalc()
	return ch

func test_tree_ui_5a() -> void:
	var ch = _ui_char()
	var v = ViewScript.new()
	v.size = Vector2(1000, 600)
	var start: String = ch.class_def()["start_passive"]
	# --- theme / sum helpers
	var th_ok := true
	for pr in [["res_fire", "Defence"], ["fire_damage", "Fire"], ["str", "Attributes"], ["attack_speed", "Attacks"], ["move_speed", "Speed"],
			["minion_life", "Minions"], ["damage", "General"], ["crit_multi", "Critical"], ["bleed_chance", "Ailments"], ["turret_limit", "Traps & turrets"],
			["max_life", "Life & mana"], ["cast_speed", "Spells"], ["projectile_speed", "Projectiles"], ["dot_damage", "Ailments"]]:
		if TreeRules.stat_theme(pr[0]) != pr[1]:
			th_ok = false
			T._log("     stat_theme(%s) = %s, want %s" % [pr[0], TreeRules.stat_theme(pr[0]), pr[1]])
	T.check(th_ok, "ui5a: stat themes group stats as intended")
	var sums := {}
	TreeRules.sum_mod(sums, {"stat": "damage", "type": "inc", "value": 10})
	TreeRules.sum_mod(sums, {"stat": "damage", "type": "inc", "value": 5}, 2.0)
	TreeRules.sum_mod(sums, {"stat": "damage", "type": "more", "value": 20})
	TreeRules.sum_mod(sums, {"stat": "damage", "type": "more", "value": 10}, 3.0)
	T.check(absf(float(sums["damage|inc"]["value"]) - 20.0) < 0.001 and absf(float(sums["damage|more"]["value"]) - 32.0) < 0.001,
		"ui5a: inc mods add (with boost), more mods multiply (no boost)", str(sums))
	var nb := 0
	var fixed := 0
	for n in Data.passive_list:
		if TreeRules.is_behaviour_node(n):
			nb += 1
			if not (n["type"] in ["mastery", "socket"]):
				fixed += 1
	T.check(fixed >= 84 and nb == fixed + 21, "ui5a: behaviour filter covers flagged nodes, keystones, masteries and sockets", "%d (%d fixed)" % [nb, fixed])
	# --- LOD
	v.zoom = 0.2
	var l0: int = v.lod()
	v.zoom = 0.5
	var l1: int = v.lod()
	v.zoom = 1.0
	var l2: int = v.lod()
	T.check(l0 == 0 and l1 == 1 and l2 == 2, "ui5a: three zoom levels of detail", "%d %d %d" % [l0, l1, l2])
	var a_minor := ""
	var a_notable := ""
	for n in Data.passive_list:
		if n["type"] == "minor" and a_minor == "" and not ch.allocated.has(n["id"]):
			a_minor = n["id"]
		if n["type"] == "notable" and a_notable == "":
			a_notable = n["id"]
	v.zoom = 0.2
	T.check(v.node_visible(Data.passives["ks_momentum"], false) and v.node_visible(Data.passives[start], true) and not v.node_visible(Data.passives[a_minor], false)
		and not v.node_visible(Data.passives[a_notable], false) and v.node_visible(Data.passives[a_minor], true),
		"ui5a: far view shows starts, keystones and allocated nodes only")
	T.check(v.node_overlays(a_minor).has("lod_hidden"), "ui5a: hidden nodes carry the lod_hidden overlay")
	v.zoom = 0.5
	T.check(v.node_visible(Data.passives[a_minor], false) and v.node_visible(Data.passives[a_notable], false), "ui5a: mid view shows notables and minor dots")
	# --- node states (Codex V5 contract)
	var nbr: String = Data.passives[start]["links"][0]
	T.check(v.node_state(start) == ViewScript.NodeState.ALLOCATED and v.node_state(nbr) == ViewScript.NodeState.AVAILABLE
		and v.node_state("ks_momentum") == ViewScript.NodeState.LOCKED, "ui5a: allocated / available / locked states")
	var keep: int = ch.bonus_passive_points
	ch.bonus_passive_points = -ch.total_passive_points() + keep
	T.check(v.node_state(nbr) == ViewScript.NodeState.UNAVAILABLE, "ui5a: connected but no points -> unavailable")
	ch.bonus_passive_points = keep
	v.planned[nbr] = true
	T.check(v.node_state(nbr) == ViewScript.NodeState.PLANNED, "ui5a: planned state (reserved for 5b)")
	v.planned = {}
	ch.tree_refund = {"from_version": 1, "reason": "test", "points": 1, "ids": ["ks_momentum"]}
	T.check(v.node_state("ks_momentum") == ViewScript.NodeState.MIGRATED_REFUNDED and v.node_tooltip("ks_momentum").contains("refunded"),
		"ui5a: nodes from before a tree refund show as migrated_refunded")
	ch.tree_refund = {}
	T.check(ViewScript.STATE_NAMES.size() == ViewScript.NodeState.size(), "ui5a: every state has a contract name")
	# exclusive pair -> unavailable
	var ex_ok := true
	for n in Data.passive_list:
		if not n.get("exclusive_with", []).is_empty():
			var c2 = _ui_char()
			if c2.allocate_path(n["id"]):
				var other: String = n["exclusive_with"][0]
				var pth: Array = c2.path_to(other)
				# allocate the route up to (not including) the other node, if one exists
				var reach := false
				for l in Data.passives[other]["links"]:
					reach = reach or c2.allocated.has(l)
				if reach:
					ex_ok = v.node_state(other) == ViewScript.NodeState.UNAVAILABLE
			break
	T.check(ex_ok, "ui5a: an exclusive node next to the web is unavailable")
	ch = _ui_char()
	# --- filters
	v.set_tag("fire", true)
	var fire_ok := true
	for n in Data.passive_list:
		if v.passes_filter(n) != n.get("tags", []).has("fire"):
			fire_ok = false
	T.check(fire_ok and v.filter_active(), "ui5a: a tag chip keeps exactly the nodes with that tag")
	v.set_tag("bleed", true)
	var or_ok := true
	for n in Data.passive_list:
		var tg: Array = n.get("tags", [])
		if v.passes_filter(n) != (tg.has("fire") or tg.has("bleed")):
			or_ok = false
	T.check(or_ok, "ui5a: several chips match any of their tags")
	T.check(v.node_overlays(a_minor).has("filtered_out") == not v.passes_filter(Data.passives[a_minor]), "ui5a: filtered_out overlay follows the filter")
	v.clear_filters()
	v.behaviour_only = true
	T.check(v.passes_filter(Data.passives["ks_momentum"]) and not v.passes_filter(Data.passives[a_minor]), "ui5a: behaviour-only toggle")
	v.clear_filters()
	T.check(not v.filter_active() and v.passes_filter(Data.passives[a_minor]), "ui5a: clear removes every filter")
	# --- search + jump
	v.search = "momentum"
	var hits: Array = v.search_hits()
	var hid: String = v.next_hit(1)
	var on_centre: bool = hid != "" and v.to_screen(v.node_pos(Data.passives[hid])).distance_to(v.size / 2) < 0.5
	T.check(hits.has("ks_momentum") and on_centre and v.zoom >= ViewScript.LOD_NEAR, "ui5a: next search hit centres the node at near zoom", str(hits))
	var all_seen := {}
	for i in hits.size():
		all_seen[v.next_hit(1)] = true
	T.check(all_seen.size() == hits.size(), "ui5a: next hit cycles through every hit")
	v.search = "zzzz_nothing"
	T.check(v.next_hit(1) == "" and v.search_hits().is_empty(), "ui5a: no hits -> no jump")
	v.search = ""
	# --- minimap
	var mr: Rect2 = v.minimap_rect()
	var mm_ok := true
	for n in Data.passive_list:
		var q: Vector2 = v.world_to_mini(v.node_pos(n))
		mm_ok = mm_ok and mr.grow(0.5).has_point(q) and v.mini_to_world(q).distance_to(v.node_pos(n)) < 0.5
	T.check(mm_ok, "ui5a: minimap holds every node and maps back to the tree")
	var target := Vector2(-300, 400)
	v.center_on(v.mini_to_world(v.world_to_mini(target)), 0.8)
	T.check(v.view_world_rect().get_center().distance_to(target) < 0.5, "ui5a: minimap jump centres the view there")
	T.check(v._node_at(mr.get_center()) == "" and v.in_minimap(mr.get_center()), "ui5a: clicks on the minimap never hit a node")
	# --- tooltip: drawback in red + tags
	var tip: String = v.node_tooltip("ks_momentum")
	T.check(tip.contains("[color=#ff6060]Drawback: " + Data.passives["ks_momentum"]["drawback"]) and tip.contains("Tags: attack, melee"),
		"ui5a: keystone tooltip shows the drawback in red and the tags")
	var no_db := true
	for n in Data.passive_list:
		if n["type"] == "keystone" and str(n.get("drawback", "")) == "":
			no_db = false
	T.check(no_db, "ui5a: every keystone has a drawback to show")
	# --- summary
	for id in ["p4_s_w_in", "w_mel2", "w_2h", "w_1h", "ks_momentum"]:
		ch.allocate_path(id)
	ch.allocate_path("p4_m_melee", "melee_fury")
	ch.add_gem("onyx:2")
	ch.socket_tree_gem("p4_s_w_in", "onyx:2")
	var sm: Dictionary = ch.tree_summary()
	var pts := 0
	for id in ch.allocated:
		if id != start:
			pts += int(Data.passives[id]["cost"])
	T.check(int(sm["nodes"]) == ch.allocated.size() - 1 and int(sm["points"]) == pts and int(sm["points"]) == ch.spent_passive_points(),
		"ui5a: summary counts nodes and points", "%d %d" % [sm["nodes"], sm["points"]])
	T.check(sm["keystones"] == ["ks_momentum"] and sm["masteries"] == [["p4_m_melee", "melee_fury"]] and sm["gems"] == [["p4_s_w_in", "onyx:2"]],
		"ui5a: summary lists keystones, masteries and gems", str([sm["keystones"], sm["masteries"], sm["gems"]]))
	# every summed value equals the hand-made total (socket boosts and mastery/gem stats included)
	var want := {}
	var bo: Dictionary = ch.socket_boosts(ch.allocated)
	for id in ch.allocated:
		var n: Dictionary = Data.passives[id]
		for m in n.get("mods", []):
			TreeRules.sum_mod(want, m, 1.0 + float(bo.get(id, 0.0)) / 100.0)
	for m in ch.mastery_option("p4_m_melee", "melee_fury").get("mods", []):
		TreeRules.sum_mod(want, m)
	for m in Loot.gem_mods("onyx:2", "tree"):
		TreeRules.sum_mod(want, m)
	var got := {}
	var placed_ok := true
	for th in sm["order"]:
		for m in sm["themes"][th]:
			got[str(m["stat"]) + "|" + str(m["type"])] = float(m["value"])
			placed_ok = placed_ok and TreeRules.stat_theme(str(m["stat"])) == th
	var sum_ok := true
	for k in want:
		if absf(float(want[k]["value"])) >= 0.01 and absf(float(got.get(k, -999.0)) - float(want[k]["value"])) > 0.001:
			sum_ok = false
			T._log("     summary %s = %s, want %s" % [k, got.get(k, "missing"), want[k]["value"]])
	T.check(sum_ok and got.size() > 3, "ui5a: summary totals match every allocated mod", str(got.size()))
	T.check(placed_ok, "ui5a: each total sits under its theme")
	T.check(bo.size() > 0 and float(got.get("melee_damage|inc", 0.0)) > 0.0, "ui5a: socket boost included in the summary")
	var pn = PanelScript.new()
	var txt: String = pn.summary_text()
	T.check(txt.contains("Overwhelming Momentum") and txt.contains(Data.passives["ks_momentum"]["drawback"]) and txt.contains("Masteries")
		and txt.contains(Loot.gem_name("onyx:2")) and txt.contains("Tags:"), "ui5a: summary panel text lists keystone + drawback, masteries, gems, tags")
	T.check(PanelScript.used_tags().size() >= ViewScript.FILTER_CHIPS.size() and PanelScript.used_tags().has("fire"), "ui5a: tag list for the More menu")
	var chips_ok := true
	for tg in ViewScript.FILTER_CHIPS:
		chips_ok = chips_ok and Data.passive_flags["tags"].has(tg) and PanelScript.used_tags().has(tg)
	T.check(chips_ok, "ui5a: every chip is a used vocabulary tag")
	ch = _ui_char()
	T.check(pn.summary_text().contains("Nothing allocated"), "ui5a: empty tree summary")
	pn.free()
	v.free()

# ------------------------------------------------------------------ Phase 5b: presets, planner, build codes
func _set_of(a: Array) -> Dictionary:
	var d := {}
	for x in a:
		d[str(x)] = true
	return d

func _same_set(a: Array, b: Array) -> bool:
	var sa := _set_of(a)
	var sb := _set_of(b)
	return sa.size() == sb.size() and sa.keys().all(func(k): return sb.has(k))

func test_tree_ui_5b() -> void:
	var ch = _ui_char()
	var start: String = ch.class_def()["start_passive"]
	var masteries: Dictionary = Data.passive_flags.get("masteries", {})
	# --- codec
	var src := {"v": 1, "c": "warrior", "t": 3, "n": ["a", "b", "c"], "m": {"m1": "o1"}, "g": {"s1": "ruby"}}
	var code: String = TreeRules.encode_build(src)
	var dec: Dictionary = TreeRules.decode_build(code)
	var safe := true
	for c in code.substr(5):
		safe = safe and TreeRules.B64_CHARS.contains(c)
	T.check(code.begins_with("POD1-") and safe and dec["error"] == "" and JSON.stringify(dec["data"], "", true) == JSON.stringify(src, "", true),
		"ui5b: build code round-trips (POD1-, URL-safe base64 of DEFLATE JSON)", code)
	var spaced := code.substr(0, 10) + " \n" + code.substr(10)
	T.check(TreeRules.decode_build(spaced)["error"] == "", "ui5b: whitespace in a pasted code is ignored")
	var bad_ok := true
	var bad_codes := ["", "hello", "POD2-" + code.substr(5), "POD1-!!!!????", "POD1-AAAA", "POD1-" + code.substr(5, code.length() / 2),
		"POD1-" + Marshalls.raw_to_base64(PackedByteArray([0, 0, 9, 1, 2, 3, 4, 5, 6])).replace("=", ""),
		TreeRules.encode_build({"v": 2, "c": "warrior", "n": []}), TreeRules.encode_build({"v": 1, "c": 5, "n": []}), TreeRules.encode_build({"v": 1, "c": "warrior", "n": "x"})]
	for bc in bad_codes:
		var r: Dictionary = TreeRules.decode_build(bc)
		if r["error"] == "":
			bad_ok = false
			T._log("     accepted bad code: %s" % bc)
	T.check(bad_ok, "ui5b: damaged, foreign or malformed codes are rejected", str(bad_codes.size()))
	# --- export / import round trip (nodes, mastery, gem suggestion)
	for id in ["p4_s_w_in", "w_mel2", "w_2h", "w_1h", "ks_momentum"]:
		ch.allocate_path(id)
	ch.allocate_path("p4_m_melee", "melee_fury")
	ch.add_gem("onyx:2")
	ch.socket_tree_gem("p4_s_w_in", "onyx:2")
	var want: Array = ch.allocated.duplicate()
	var exp_code: String = ch.export_build_code(false)
	var c2 = _ui_char()
	var imp: Dictionary = c2.import_build_code(exp_code)
	var want_plan := want.duplicate()
	want_plan.erase(start)
	T.check(imp["error"] == "" and imp["dropped"] == 0 and _same_set(c2.plan, want_plan) and c2.allocated == [start] and c2.plan_choices.get("p4_m_melee", "") == "melee_fury"
		and c2.plan_gems == {"p4_s_w_in": "onyx"} and imp["gems"] == ["onyx"], "ui5b: import puts the build into the plan (mastery choice + gem suggestion)", str(imp))
	var spent0: int = c2.available_passive_points()
	var nap: int = c2.apply_plan()
	T.check(nap == want_plan.size() and _same_set(c2.allocated, want) and c2.mastery_choices.get("p4_m_melee", "") == "melee_fury" and c2.plan.is_empty()
		and c2.tree_gems.is_empty() and c2.available_passive_points() == spent0 - c2.spent_passive_points(),
		"ui5b: apply plan allocates the imported build (gems stay suggestions)")
	var r2 = load("res://scripts/core/character_data.gd").new()
	r2.setup_new("ranger")
	r2.level = 60
	T.check(r2.import_build_code(exp_code)["error"].contains("Warrior") and r2.plan.is_empty(), "ui5b: a code for another class is refused")
	# --- illegal nodes are dropped, the rest stays legal
	var c3 = _ui_char()
	var fr: Array = c3.path_to("p2_ks_frenzy")
	var rp: Array = c3.path_to("p2_ks_riposte")
	var far: String = Data.passives[Data.classes["ranger"]["start_passive"]]["links"][0]
	var ids := fr.duplicate()
	ids.append_array(rp)
	ids.append_array(["no_such_node", Data.classes["mage"]["start_passive"], far, start])
	var ill := TreeRules.encode_build({"v": 1, "c": "warrior", "t": TreeRules.tree_version(Data.passive_migrations), "n": ids, "m": {"p4_m_melee": "not_an_option"}, "g": {"no_socket": "ruby"}})
	var ri: Dictionary = c3.import_build_code(ill)
	var legal: String = TreeRules.allocation_problem(c3.allocated + c3.plan, start, 9999, Data.passives, c3.plan_choices, masteries)
	T.check(ri["error"] == "" and legal == "" and c3.plan.has("p2_ks_frenzy") and not c3.plan.has("p2_ks_riposte") and not c3.plan.has(far)
		and not c3.plan.has("no_such_node") and ri["dropped"] >= 4 and ri["gems"].is_empty(), "ui5b: import drops unknown, start, disconnected and exclusive nodes", "%s / %s" % [legal, str(ri)])
	# --- planner
	var c4 = _ui_char()
	var v = ViewScript.new()
	v.size = Vector2(1000, 600)
	var pts: int = c4.available_passive_points()
	var route: Array = c4.plan_route("ks_momentum")
	T.check(c4.plan_add("ks_momentum") == "" and c4.plan == route and c4.allocated == [start] and c4.available_passive_points() == pts
		and v.node_state("ks_momentum") == ViewScript.NodeState.PLANNED and c4.plan_points() == c4.path_cost(route), "ui5b: planning a node adds its route as ghost nodes for free")
	T.check(c4.can_plan("ks_momentum") == "Already planned" and c4.can_plan(start) != "", "ui5b: cannot plan twice or plan the start")
	T.check(c4.can_plan("p4_m_melee") == "Choose an effect" or c4.can_plan("p4_m_melee") == "No route to that node", "ui5b: a planned mastery needs an effect")
	var mid: String = route[0]
	c4.plan_remove(mid)
	T.check(c4.plan.is_empty(), "ui5b: removing a planned node drops what it cut off", str(c4.plan))
	c4.plan_add("p2_ks_frenzy")
	T.check(c4.can_plan("p2_ks_riposte") != "", "ui5b: cannot plan a node exclusive with the plan")
	c4.clear_plan()
	c4.plan_add("ks_momentum")
	c4.bonus_passive_points = -c4.total_passive_points() + c4.bonus_passive_points + 2
	var napp: int = c4.apply_plan()
	T.check(napp == 2 and c4.available_passive_points() == 0 and c4.plan.size() == route.size() - 2 and c4.plan[0] == route[2], "ui5b: apply plan stops when points run out", "%d %s" % [napp, str(c4.plan)])
	# --- presets
	var c5 = _ui_char()
	for id in ["w_mel2", "w_2h"]:
		c5.allocate_path(id)
	c5.allocate_path("p4_s_w_in")
	c5.add_gem("onyx:2")
	c5.socket_tree_gem("p4_s_w_in", "onyx:2")
	var tree_a: Array = c5.allocated.duplicate()
	var g0: int = c5.gold
	T.check(c5.preset_empty(1) and c5.switch_preset(1) == "" and c5.active_preset == 1 and c5.allocated == tree_a and c5.gold == g0, "ui5b: switching to an empty preset copies the tree for free")
	# build tree B: refund back to start, take another route
	var start_only := [start]
	c5.clear_tree_gems()
	c5.allocated = start_only.duplicate()
	c5.recalc()
	c5.allocate_path("ks_momentum")
	var tree_b: Array = c5.allocated.duplicate()
	var removed := 0
	for id in tree_b:
		if not tree_a.has(id):
			removed += 1
	g0 = c5.gold
	var cost: int = c5.preset_switch_cost(0)
	T.check(cost == removed * c5.refund_cost() and cost > 0, "ui5b: switch cost = refund price per removed node", "%d %d" % [cost, removed])
	T.check(c5.switch_preset(0) == "" and c5.allocated == tree_a and c5.gold == g0 - cost and c5.tree_gems.get("p4_s_w_in", "") == "onyx:2" and int(c5.gems.get("onyx:2", 0)) == 0,
		"ui5b: switching back restores the tree and re-sockets its gem")
	T.check(_same_set(c5.preset_slot(1).get("allocated", []), tree_b) and c5.preset_slot(0).is_empty(), "ui5b: the left tree is kept in its slot")
	c5.level = 10
	T.check(c5.preset_switch_cost(1) == 0, "ui5b: switching is free below level 20")
	c5.level = 60
	var gk: int = c5.gold
	c5.gold = 0
	T.check(c5.can_switch_preset(1).contains("gold"), "ui5b: not enough gold to switch")
	c5.gold = gk
	T.check(c5.can_switch_preset(0) != "" and c5.can_switch_preset(3) != "", "ui5b: cannot switch to the active or a missing slot")
	# save round trip
	c5.plan_add("p4_m_melee", "melee_fury")
	var d: Dictionary = c5.to_dict()
	var c6 = load("res://scripts/core/character_data.gd").new()
	c6.from_dict(d)
	T.check(c6.active_preset == 0 and _same_set(c6.preset_slot(1).get("allocated", []), tree_b) and c6.plan == c5.plan and c6.plan_choices == c5.plan_choices,
		"ui5b: presets and the plan survive save/load", str(d.get("passive_presets", {})))
	var d2: Dictionary = d.duplicate(true)
	d2["passive_presets"]["slots"][1]["allocated"].append("no_such_node")
	var c7 = load("res://scripts/core/character_data.gd").new()
	c7.from_dict(d2)
	T.check(c7.preset_empty(1) and c7.presets_dropped == 1, "ui5b: an illegal preset is emptied on load")
	var d3: Dictionary = d.duplicate(true)
	d3["tree_version"] = 1
	var c8 = load("res://scripts/core/character_data.gd").new()
	c8.from_dict(d3)
	T.check((TreeRules.tree_version(Data.passive_migrations) == 1) or (c8.preset_empty(1) and c8.plan.is_empty()), "ui5b: a tree update empties presets and the plan")
	var fresh = _ui_char()
	T.check(not fresh.to_dict().has("passive_presets") and not fresh.to_dict().has("tree_plan"), "ui5b: unused presets/plan add nothing to the save")
	# panel text
	var pn = PanelScript.new()
	T.check(pn.preset_text(0).begins_with("> 1") and pn.preset_text(1) == "2: empty", "ui5b: preset buttons", pn.preset_text(0))
	pn.free()
	v.free()
