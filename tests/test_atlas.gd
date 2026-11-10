extends Node
## Endgame Phase 1A: Atlas of Ruin rules, save v5, zone summon cap and a live atlas run.
## Phase 1C: Rot rules (sources, spread, forecast, cap, safety ring, death, restore/fester),
## Heart boss mutations and live Rot / Heart runs.
## Phase 1D: zone mechanics (natural roll, Glazed Elites, The Unfinished) rules and live runs.
## Phase 2B: Fixative crafting and Rot-touched implicits (rules, Blacksmith, live Rot drops).
## Phase 2C: Commission Board + Restorers' Guild (rules, pace sim, Fixative gate, live credit, panel).
## Phase 2D: Collector's Wager + Pentimento Vaults (rules, live bets, live vaults) and the new contracts.
## Phase 1E: Pigments (craft, slots, charges, modifiers), Varnish slots, Heart Varnish drops, the Easel.
##   godot --headless --fixed-fps 60 --path . res://tests/atlas_only.tscn [-- --shot]
## Writes tests/atlas_only_results.txt. --shot (windowed) saves tests/screens_out_atlas/*.png.

const AR = preload("res://scripts/core/atlas_rules.gd")
const AC = preload("res://scripts/core/atlas_craft_rules.gd")
const GR = preload("res://scripts/core/guild_rules.gd")
const WV = preload("res://scripts/core/wager_vault_rules.gd")
const CharacterData = preload("res://scripts/core/character_data.gd")

var fails := 0
var passes := 0
var log_lines := []
var main = null
var args := {}

func check(cond: bool, what: String, detail: String = "") -> void:
	if cond:
		passes += 1
		log_lines.append("PASS  " + what)
	else:
		fails += 1
		print("FAIL  ", what, "  ", detail)
		log_lines.append("FAIL  %s  %s" % [what, detail])

func note(line: String) -> void:
	print(line)
	log_lines.append(line)

func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := String(a).trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	Game.testing = true
	Loot.set_seed(12345)
	await get_tree().process_frame
	await run_all()
	var f := FileAccess.open("res://tests/atlas_only_results.txt", FileAccess.WRITE)
	f.store_line("==== %d passed, %d failed ====" % [passes, fails])
	for l in log_lines:
		f.store_line(l)
	f.close()
	print("==== %d passed, %d failed ====" % [passes, fails])
	get_tree().quit(1 if fails > 0 else 0)

func run_all() -> void:
	test_data()
	test_hex_maths()
	test_derivation()
	test_state()
	test_save()
	test_rot()
	test_heart_defs()
	test_mechanic_rules()
	test_pigment_rules()
	test_varnish_rules()
	test_warden_rules()
	test_fixative()
	test_rot_touched_rules()
	test_guild_rules()
	test_guild_pace()
	test_wager_vault_rules()
	test_contracts_2d()
	main = load("res://scripts/main.gd").new()
	add_child(main)
	await frames(2)
	Game.atlas_force_mechanic = "none"   # the 1A-1C live checks run without zone mechanics
	await test_live()
	await test_live_rot()
	await test_live_mechanics()
	await test_live_pigments()
	await test_live_wardens()
	await test_live_rot_touched()
	await test_live_guild()
	await test_live_wager()
	await test_live_vaults()
	await test_live_contracts_2d()
	Game.atlas_force_mechanic = ""

# ------------------------------------------------------------------ data
func test_data() -> void:
	var c: Dictionary = Data.atlas_cfg
	check(not c.is_empty(), "data/atlas.json loads")
	check(int(c.get("radius", 0)) == 3 and c.get("rings", []).size() == 3, "MVP atlas: radius 3, 3 ring definitions")
	var lv := []
	for rc in c.get("rings", []):
		lv.append(int(rc["level"]))
	check(lv == [40, 45, 50], "ring monster levels 40 / 45 / 50", str(lv))
	check(Data.dungeons.has(str(c.get("unlock_dungeon", ""))), "unlock dungeon exists")
	check(c.get("biomes", []).size() == 3, "three biomes")
	for b in c.get("biomes", []):
		var z: Dictionary = Data.zones.get(b["zone"], {})
		check(z.get("generator", "") == "zone", "biome %s is a zone def" % b["zone"])
		check(Data.enemies.has(z.get("boss", "")), "biome %s boss exists" % b["zone"])
		for p in z.get("pool", []):
			check(Data.enemies.has(p["id"]), "biome %s enemy %s exists" % [b["zone"], p["id"]])
		check(int(z.get("summon_lifetime", 0)) > 0, "biome %s caps summons" % b["zone"])
	for bid in c.get("bosses", []):
		check(Data.enemies.has(bid), "atlas boss %s exists" % bid)

# ------------------------------------------------------------------ hex maths
func test_hex_maths() -> void:
	var all := AR.within(Vector2i.ZERO, 3)
	check(all.size() == 37, "radius 3 holds 37 hexes", str(all.size()))
	var per := {}
	for h in all:
		per[AR.ring_of(h)] = int(per.get(AR.ring_of(h), 0)) + 1
	check(per == {0: 1, 1: 6, 2: 12, 3: 18}, "ring sizes 1/6/12/18", str(per))
	var ok_nb := true
	var ok_px := true
	for h in all:
		for n in AR.neighbours(h):
			if absi(AR.ring_of(n) - AR.ring_of(h)) > 1:
				ok_nb = false
		for sz in [10.0, 30.0]:
			if AR.from_pixel(AR.to_pixel(h, sz), sz) != h or AR.from_pixel(AR.to_pixel(h, sz) + Vector2(sz * 0.4, -sz * 0.3), sz) != h:
				ok_px = false
		if AR.parse(AR.key(h)) != h:
			ok_px = false
	check(ok_nb, "neighbours differ by at most one ring")
	check(ok_px, "pixel <-> hex and key <-> hex round trips")
	check(AR.parse("x,1") == Vector2i(9999, 9999) and not AR.in_atlas(AR.parse("bad")), "bad keys parse outside the atlas")

# ------------------------------------------------------------------ derivation
func test_derivation() -> void:
	var biomes := {}
	var bosses := {}
	var vant_bad := 0
	var vant := 0
	var same := true
	var differs := false
	for s in range(1, 61):
		for h in AR.within(Vector2i.ZERO, 3):
			if AR.ring_of(h) == 0:
				if s == 1:
					check(AR.hex_info(s, h).is_empty(), "hub has no zone")
				continue
			var a := AR.hex_info(s, h)
			var b := AR.hex_info(s, h)
			if str(a) != str(b):
				same = false
			if str(a) != str(AR.hex_info(s + 1000, h)):
				differs = true
			biomes[a["zone"]] = true
			bosses[a["boss"]] = true
			if a["vantage"]:
				vant += 1
				if a["ring"] < 2:
					vant_bad += 1
	check(same, "hex info is deterministic for a seed")
	check(differs, "different atlas seeds give different atlases")
	check(biomes.size() == 3, "all three biomes appear", str(biomes.keys()))
	check(bosses.size() == 6, "all six bosses appear", str(bosses.keys()))
	check(vant_bad == 0 and vant > 0, "vantage hexes appear only from ring 2", "%d bad / %d" % [vant_bad, vant])
	note("DERIV 60 seeds: vantage %.1f per atlas" % (vant / 60.0))
	for h in AR.within(Vector2i.ZERO, 3):   # the smartbot's atlas (seed 1), for picking bot hexes
		var i1 := AR.hex_info(1, h)
		if not i1.is_empty():
			note("SEED1 %s ring %d %s boss=%s vantage=%s" % [i1["key"], i1["ring"], i1["zone"], i1["boss"], i1["vantage"]])
	# biome clustering: neighbours share a biome more often than chance (1/3)
	var pairs := 0
	var same_b := 0
	for s in range(1, 21):
		for h in AR.within(Vector2i.ZERO, 3):
			if AR.ring_of(h) == 0:
				continue
			for n in AR.neighbours(h):
				if AR.ring_of(n) >= 1 and AR.in_atlas(n):
					pairs += 1
					if AR.hex_info(s, h)["zone"] == AR.hex_info(s, n)["zone"]:
						same_b += 1
	check(float(same_b) / pairs > 0.45, "biomes form regions (neighbours share a biome)", "%.2f" % (float(same_b) / pairs))
	for ring in [1, 2, 3]:
		var h := Vector2i(ring, 0)
		var d := AR.zone_def(77, h)
		var rc := AR.ring_cfg(ring)
		check(d["id"] == "atlas:%d,0" % ring and d["atlas"] and not d["spike"] and int(d["tier"]) == 6, "ring %d zone def is an atlas zone (tier 6)" % ring)
		check(int(d["min_level"]) == int(rc["level"]) and int(d["max_level"]) == int(rc["level"]), "ring %d fixes monster level %d" % [ring, int(rc["level"])])
		check(float(d["life_mult"]) == float(rc["life_mult"]) and d["mod_count"] == rc["mod_count"], "ring %d scaling applied" % ring)
		check(d["boss"] == AR.hex_info(77, h)["boss"] and d["generator"] == "zone", "ring %d boss and generator" % ring)
		var m1 := AR.run_mods(77, h, 0, d)
		check(m1 == AR.run_mods(77, h, 0, d) and m1.size() >= int(rc["mod_count"][0]) and m1.size() <= int(rc["mod_count"][1]), "ring %d base modifiers are seeded and in range" % ring, str(m1))
	check(AR.layout_seed(5, Vector2i(1, 0), 0) == AR.layout_seed(5, Vector2i(1, 0), 0) and AR.layout_seed(5, Vector2i(1, 0), 0) != AR.layout_seed(5, Vector2i(1, 0), 1), "layout seed is fixed per clear count and changes after a clear")
	check(Data.zones.get("zone_overgrown_ruin", {}).get("min_level") == 15, "atlas zone defs never modify the biome template")

# ------------------------------------------------------------------ state
func test_state() -> void:
	var st := AR.new_state(4242)
	check(st["revealed"].size() == 6 and st["clears"].is_empty(), "new atlas reveals ring 1 only")
	check(not AR.can_enter(st, Vector2i.ZERO) and not AR.can_enter(st, Vector2i(2, 0)) and AR.can_enter(st, Vector2i(1, 0)), "hub and hidden hexes cannot be entered")
	check(AR.complete(st, Vector2i(2, 0)).is_empty() and AR.clears(st, Vector2i(2, 0)) == 0, "completing a hidden hex does nothing")
	var fresh := AR.complete(st, Vector2i(1, 0))
	var expect := []
	for n in AR.neighbours(Vector2i(1, 0)):
		if AR.ring_of(n) == 2:
			expect.append(AR.key(n))
	fresh.sort()
	expect.sort()
	check(fresh == expect and AR.clears(st, Vector2i(1, 0)) == 1, "clearing a ring-1 hex reveals its ring-2 neighbours", str(fresh))
	check(AR.complete(st, Vector2i(1, 0)).is_empty() and AR.clears(st, Vector2i(1, 0)) == 2, "re-clearing counts but reveals nothing new")
	# vantage reveals radius 2
	var vs := -1
	var vh := Vector2i.ZERO
	for s in range(1, 200):
		for h in AR.within(Vector2i.ZERO, 3):
			if AR.ring_of(h) == 2 and AR.hex_info(s, h).get("vantage", false):
				vs = s
				vh = h
				break
		if vs > 0:
			break
	if vs > 0:
		var st2 := AR.new_state(vs)
		st2["revealed"].append(AR.key(vh))
		AR.complete(st2, vh)
		var all_in := true
		for n in AR.within(vh, 2):
			if AR.ring_of(n) >= 1 and AR.in_atlas(n) and not AR.is_revealed(st2, n):
				all_in = false
		check(all_in, "a vantage hex reveals everything within 2")
	# exploring everything reveals all 36 regions
	var st3 := AR.new_state(99)
	var steps := 0
	var progress := true
	while progress and steps < 100:
		progress = false
		for k in st3["revealed"].duplicate():
			var h := AR.parse(k)
			if AR.clears(st3, h) == 0:
				AR.complete(st3, h)
				steps += 1
				progress = true
	var sm := AR.summary(st3)
	check(sm["revealed"] == 36 and sm["cleared"] == 36 and sm["total"] == 36, "clearing outward reveals the whole atlas", str(sm))
	check(sm["rings"] == {1: [6, 6], 2: [12, 12], 3: [18, 18]}, "summary per ring", str(sm["rings"]))
	# sanitize
	var raw := {"seed": 5, "revealed": ["1,0", "9,9", "0,0", "nope", "2,0"], "clears": {"2,-1": 3, "7,0": 2, "1,0": -1}}
	var cl := AR.sanitize(raw)
	check(cl["seed"] == 5 and cl["revealed"].has("2,0") and cl["revealed"].has("2,-1") and not cl["revealed"].has("9,9") and not cl["revealed"].has("0,0"), "sanitize keeps valid revealed hexes", str(cl["revealed"]))
	check(cl["clears"] == {"2,-1": 3}, "sanitize keeps only valid positive clear counts", str(cl["clears"]))
	check(AR.sanitize({}).is_empty() and AR.sanitize({"seed": 0}).is_empty() and AR.sanitize("x").is_empty(), "sanitize rejects empty / seedless / malformed")

# ------------------------------------------------------------------ save v5
func test_save() -> void:
	check(CharacterData.SAVE_VERSION == 5, "SAVE_VERSION is 5")
	var ch = CharacterData.new()
	ch.setup_new("mage", "Dan")
	var d0: Dictionary = ch.to_dict()
	check(not d0.has("atlas") and int(d0["version"]) == 5, "a character without an atlas writes no atlas key")
	check(not AR.unlocked(ch), "atlas locked for a new character")
	ch.progress["bosses_killed"]["nightmare_vaults"] = 1
	check(AR.unlocked(ch), "atlas unlocks after Malgrath")
	AR.ensure(ch, 31337)
	AR.ensure(ch, 1)
	check(int(ch.atlas["seed"]) == 31337, "ensure creates the atlas once")
	AR.complete(ch.atlas, Vector2i(0, 1))
	var d1: Dictionary = ch.to_dict()
	var ch2 = CharacterData.new()
	ch2.from_dict(JSON.parse_string(JSON.stringify(d1)))
	check(str(ch2.atlas) == str(ch.atlas), "atlas survives a JSON save round trip", str(ch2.atlas))
	var d4 := d0.duplicate(true)
	d4["version"] = 4
	var ch3 = CharacterData.new()
	ch3.from_dict(d4)
	check(ch3.atlas.is_empty() and int(ch3.to_dict()["version"]) == 5, "v4 save loads with no atlas and re-saves as v5")

# ------------------------------------------------------------------ live
func test_live() -> void:
	Game.new_character("warrior")
	Game.ch.level = 40
	main.start_game()
	await frames(3)
	var ui = main.ui
	ui.toggle("dungeon")
	await frames(2)
	var dp = ui.panels["dungeon"]
	check(dp.atlas_btn.disabled, "Dungeon Gate: Atlas button locked before Malgrath")
	ui.close_all()
	Game.ch.progress["bosses_killed"]["nightmare_vaults"] = 1
	ui.toggle("dungeon")
	await frames(2)
	check(not dp.atlas_btn.disabled, "Dungeon Gate: Atlas button open after Malgrath")
	dp._open_atlas()
	await frames(3)
	var ap = ui.panels["atlas"]
	check(ui.is_open("atlas") and not ui.is_open("dungeon"), "Atlas panel opens from the Gate")
	check(not Game.ch.atlas.is_empty(), "opening the Atlas creates the character's atlas")
	Game.ch.atlas = AR.new_state(20261105)
	ap.select(Vector2i(2, 0))
	check(ap.enter_btn.disabled, "hidden hex cannot be entered from the panel")
	var h := Vector2i(1, 0)
	ap.select(h)
	check(not ap.enter_btn.disabled and ap.detail.text.find("Ring 1") >= 0, "revealed ring-1 hex can be entered")
	if args.has("shot"):
		await _shot("atlas_fresh")
	var info := AR.hex_info(20261105, h)
	ap._enter()
	await frames(4)
	var lv = Game.level
	check(lv != null and lv.is_zone and lv.atlas_hex == "1,0", "Enter Zone loads an atlas zone")
	if lv == null or not lv.is_zone:
		return
	check(lv.monster_level == 40 and lv.def["boss"] == info["boss"] and lv.def["palette"] == Data.zones[info["zone"]]["palette"], "atlas zone uses the ring level, hex boss and biome", "%d %s" % [lv.monster_level, lv.def["boss"]])
	check(lv.run_seed == AR.layout_seed(20261105, h, 0), "atlas zone uses the hex layout seed")
	check(lv.mods.size() == AR.run_mods(20261105, h, 0, lv.def).size(), "atlas zone applies the hex modifiers")
	check(lv.summon_lifetime == 8, "zones cap summons (8 per summoner)")
	# summon cap
	var summoner = null
	for e in lv.enemies:
		if is_instance_valid(e) and e.alive and not e.is_boss:
			summoner = e
			break
	if summoner != null:
		for i in 10:
			summoner._summon_adds("plague_rat", 3)
		check(summoner.summoned_total == 8 and summoner._summon_room() == 0, "a summoner stops at the lifetime cap", str(summoner.summoned_total))
	# kill the boss
	var p = lv.player
	var pts0: int = Game.ch.bonus_passive_points
	var tier0: int = int(Game.ch.progress.get("highest_tier", 1))
	for o in lv.objectives:
		if o["type"] != "boss":
			o["done"] = true
	lv._update_seal()
	p.global_position = lv.cell_center(lv.rooms[lv.layout["boss"]]["anchor"])
	await frames(20)
	check(lv.boss != null and is_instance_valid(lv.boss), "atlas boss spawns")
	if lv.boss != null and is_instance_valid(lv.boss):
		check(lv.boss.def["id"] == info["boss"], "the hex's boss is the one that spawns")
		lv.boss.process_mode = Node.PROCESS_MODE_INHERIT
		lv.boss.die(p)
		await frames(10)
		check(lv.boss_dead and AR.clears(Game.ch.atlas, h) == 1, "boss kill clears the hex")
		check(lv.atlas_revealed.size() >= 3 and AR.is_revealed(Game.ch.atlas, Vector2i(2, 0)), "clear reveals the outer neighbours", str(lv.atlas_revealed))
		check(Game.ch.bonus_passive_points == pts0 and int(Game.ch.progress.get("highest_tier", 1)) == tier0 and not Game.ch.progress["bosses_killed"].has("atlas:1,0"), "atlas clears give no dungeon first-kill point or tier change")
		check(Game.ch.to_dict().has("atlas"), "atlas is saved with the character")
	main.go_hub(true)
	await frames(3)
	check(main.enter_dungeon("atlas:1,0"), "enter_dungeon accepts atlas:q,r ids (smartbot)")
	await frames(3)
	check(Game.level.run_seed == AR.layout_seed(20261105, h, 1), "a re-run of a cleared hex uses a new layout")
	check(not main.enter_dungeon("atlas:3,0"), "a hidden hex cannot be entered by id")
	main.go_hub(false)
	await frames(3)
	# a dungeon keeps no summon cap
	main.enter_dungeon("forgotten_depths", 777)
	await frames(3)
	check(Game.level.summon_lifetime == 0 and not Game.level.is_zone, "dungeons keep uncapped summons")
	main.go_hub(false)
	await frames(3)
	if args.has("shot"):
		ui.toggle("atlas")
		ui.panels["atlas"].select(Vector2i(2, 0))
		await _shot("atlas_after_clear")
		ui.close_all()

# ------------------------------------------------------------------ Rot (Phase 1C)
func _min_ring_ok(st: Dictionary) -> bool:
	for k in st["rot"]:
		if AR.ring_of(AR.parse(k)) < 2 or AR.is_restored(st, AR.parse(k)):
			return false
	return true

func test_rot() -> void:
	var rc: Dictionary = AR.rot_cfg()
	check(not rc.is_empty() and rc.get("levels", []).size() == 5 and int(rc.get("max", 0)) == 5, "atlas.json has a Rot block with 5 levels")
	var mono := true
	for i in range(1, 5):
		var a: Dictionary = rc["levels"][i - 1]
		var b: Dictionary = rc["levels"][i]
		for k in ["density", "life_mult", "damage_mult", "reward"]:
			if float(b[k]) < float(a[k]):
				mono = false
	check(mono, "Rot levels never get easier as Rot rises")
	# sources
	var src_ok := true
	var src_n := true
	var src_same := true
	for sd in range(1, 41):
		var st := AR.new_state(sd)
		if st["rot"].size() != int(rc["sources"]) or AR.rot_total(st) != int(rc["sources"]) * int(rc["source_level"]):
			src_n = false
		if not _min_ring_ok(st):
			src_ok = false
		if str(AR.new_state(sd)["rot"]) != str(st["rot"]):
			src_same = false
	check(src_n, "a new atlas plants %d Rot sources" % int(rc["sources"]))
	check(src_ok, "Rot sources sit in ring 2+")
	check(src_same, "Rot sources are seeded (same seed, same sources)")
	# spread
	var st := AR.new_state(7)
	_open_atlas_all(st)
	var fc := AR.forecast(st)
	var before := str(st)
	check(str(st) == before, "forecast does not change the state")
	var sp := AR.spread(st)
	check(sp == fc and sp.size() == int(rc["fronts"]), "a spread advances %d fronts and matches the forecast" % int(rc["fronts"]), "%s vs %s" % [str(sp), str(fc)])
	check(AR.rot_total(st) == int(rc["sources"]) + sp.size() and int(st["spreads"]) == 1, "each front adds 1 Rot")
	var adj_ok := true
	var st2 := AR.new_state(11)
	for i in 30:
		var prev: Dictionary = st2["rot"].duplicate()
		for k in AR.spread(st2):
			var hx := AR.parse(k)
			var near: bool = prev.has(k)
			for n in AR.neighbours(hx):
				if prev.has(AR.key(n)):
					near = true
			if not near and not prev.is_empty():
				adj_ok = false
			prev[k] = 1
		# open the whole atlas so the cap is not the limit
		if i == 0:
			for h in AR.within(Vector2i.ZERO, 3):
				if AR.ring_of(h) > 0 and not st2["revealed"].has(AR.key(h)):
					st2["revealed"].append(AR.key(h))
	check(adj_ok, "Rot only spreads from Rot hexes to themselves or their neighbours")
	check(_min_ring_ok(st2), "Rot never enters the safety ring (ring 1)")
	var mx_ok := true
	for k in st2["rot"]:
		if int(st2["rot"][k]) > 5 or int(st2["rot"][k]) < 1:
			mx_ok = false
	check(mx_ok, "Rot stays within 1-5 per hex")
	check(AR.rot_total(st2) <= AR.rot_cap(st2) and AR.rot_cap(st2) == 3 * int(rc["cap_per_ring"]), "global cap: 3 x rings revealed", "%d / %d" % [AR.rot_total(st2), AR.rot_cap(st2)])
	# cap with only ring 1 revealed
	var st3 := AR.new_state(3)
	for i in 10:
		AR.spread(st3)
	check(AR.rot_total(st3) == int(rc["cap_per_ring"]) * 1, "with only ring 1 revealed Rot stops at the ring-1 cap", str(AR.rot_total(st3)))
	# determinism
	var a1 := AR.new_state(99)
	var a2 := AR.new_state(99)
	for i in 6:
		AR.spread(a1)
		AR.spread(a2)
	check(str(a1["rot"]) == str(a2["rot"]), "spreads are deterministic for a seed")
	# restore / fester / death
	var st4 := AR.new_state(5)
	for h in AR.within(Vector2i.ZERO, 3):
		if AR.ring_of(h) > 0 and not st4["revealed"].has(AR.key(h)):
			st4["revealed"].append(AR.key(h))
	var hx := Vector2i(2, 0)
	st4["rot"][AR.key(hx)] = 3
	AR.restore(st4, hx)
	check(AR.rot_of(st4, hx) == 0 and AR.is_restored(st4, hx), "Restore sets Rot 0 and marks the hex Restored")
	var never := true
	for i in 40:
		AR.spread(st4)
		if AR.rot_of(st4, hx) > 0:
			never = false
	check(never, "a Restored hex never takes Rot again")
	check(AR.add_death_rot(st4, hx) == -1 and AR.add_death_rot(st4, Vector2i(1, 0)) == -1, "death adds no Rot on Restored or ring-1 hexes")
	var hy := Vector2i(-2, 0)
	if AR.is_restored(st4, hy):
		hy = Vector2i(0, 2)
	var r0 := AR.rot_of(st4, hy)
	check(AR.add_death_rot(st4, hy) == mini(5, r0 + 1), "death adds +1 Rot to the hex")
	st4["rot"][AR.key(hy)] = 5
	check(AR.add_death_rot(st4, hy) == -1 and AR.rot_of(st4, hy) == 5, "death never pushes Rot past 5")
	var st5 := AR.new_state(8)
	for h in AR.within(Vector2i.ZERO, 3):
		if AR.ring_of(h) > 0 and not st5["revealed"].has(AR.key(h)):
			st5["revealed"].append(AR.key(h))
	AR.fester(st5, Vector2i(2, 0))
	check(AR.fronts_next(st5) == int(rc["fronts"]) + 1, "Harvest (fester) adds a front to the next spread")
	check(AR.spread(st5).size() == int(rc["fronts"]) + 1 and AR.fronts_next(st5) == int(rc["fronts"]), "the extra front is spent by one spread")
	# no Rot left -> a new source appears
	var st6 := AR.new_state(4)
	for k in st6["rot"].keys():
		AR.restore(st6, AR.parse(k))
	for h in AR.within(Vector2i.ZERO, 3):
		if AR.ring_of(h) > 0 and not st6["revealed"].has(AR.key(h)):
			st6["revealed"].append(AR.key(h))
	check(AR.rot_total(st6) == 0 and AR.spread(st6).size() > 0 and _min_ring_ok(st6), "with no Rot left the next spread plants a new source")
	# complete_run
	var st7 := AR.new_state(12)
	var res := AR.complete_run(st7, Vector2i(1, 0))
	check(res["revealed"].size() >= 2 and res["spread"].size() == int(rc["fronts"]) - maxi(0, AR.rot_total(st7) - AR.rot_cap(st7)), "complete_run reveals then spreads", str(res))
	# sanitize
	var raw := {"seed": 5, "revealed": ["1,0"], "clears": {}, "rot": {"2,0": 9, "1,0": 2, "3,0": 2, "9,9": 1, "-2,0": 0}, "restored": ["3,-1", "bad"], "spreads": 4, "fester": 1}
	var cl := AR.sanitize(raw)
	check(cl["rot"] == {"2,0": 5, "3,0": 2}, "sanitize clamps Rot to 5 and drops ring-1, zero and outside entries", str(cl["rot"]))
	check(cl["restored"] == ["3,-1"] and int(cl["spreads"]) == 4 and int(cl["fester"]) == 1, "sanitize keeps restored, spreads and fester")
	var old := AR.sanitize({"seed": 5, "revealed": ["1,0"], "clears": {}})
	check(old["rot"].size() == int(rc["sources"]) and str(old["rot"]) == str(AR.new_state(5)["rot"]), "a pre-1C atlas gets its seeded Rot sources on load")
	var ch = CharacterData.new()
	ch.atlas = AR.new_state(42)
	AR.spread(ch.atlas)
	AR.restore(ch.atlas, Vector2i(2, -1))
	var ch2 = CharacterData.new()
	ch2.from_dict(JSON.parse_string(JSON.stringify(ch.to_dict())))
	check(ch2.atlas["rot"] == ch.atlas["rot"] and ch2.atlas["restored"] == ch.atlas["restored"] and int(ch2.atlas["spreads"]) == 1, "Rot survives a JSON save round trip", "%s | %s" % [str(ch2.atlas), str(ch.atlas)])
	# zone def scaling
	var d := AR.zone_def(77, Vector2i(2, 0))
	var d0 := AR.apply_rot(d, 0, 77, Vector2i(2, 0))
	check(float(d0["life_mult"]) == float(d["life_mult"]) and not d0.has("heart") and int(d0["rot"]) == 0, "Rot 0 leaves the zone def unchanged")
	var d2 := AR.apply_rot(d, 2, 77, Vector2i(2, 0))
	check(is_equal_approx(float(d2["life_mult"]), float(d["life_mult"]) * 1.3) and is_equal_approx(float(d2["damage_mult"]), float(d["damage_mult"]) * 1.2) and float(d2["rot_density"]) == 1.2 and float(d2["rot_reward"]) == 35.0, "Rot 2 scales life, damage, density and rewards")
	var em0: Array = d.get("elite_mods", [1, 2])
	check(d2["elite_mods"] == [int(em0[0]) + 1, int(em0[1]) + 1] and not d2.get("heart", false), "Rot 2 elites gain a modifier; no Heart yet", str(d2.get("elite_mods")))
	var d3 := AR.apply_rot(d, 3, 77, Vector2i(2, 0))
	var d5 := AR.apply_rot(d, 5, 77, Vector2i(2, 0))
	check(d3["heart"] and d3["heart_mutations"].size() == 1 and d5["heart_mutations"].size() == 3, "Rot 3 makes a Heart with 1 mutation, Rot 5 with 3")
	check(d5["heart_mutations"].slice(0, 1) == d3["heart_mutations"], "higher Rot keeps the lower Rot's mutations")
	check(d.get("rot") == null and float(d["life_mult"]) == float(AR.zone_def(77, Vector2i(2, 0))["life_mult"]), "apply_rot returns a copy")

func test_heart_defs() -> void:
	for bid in Data.atlas_cfg.get("bosses", []):
		var bd: Dictionary = Data.enemies.get(bid, {})
		var ms: Array = bd.get("rot_mutations", [])
		check(ms.size() >= 3, "boss %s has 3+ rot_mutations" % bid)
		var ids := []
		for m in ms:
			ids.append(m["id"])
		var hd := AR.heart_def(bd, ids)
		var ok := true
		var why := ""
		var pats: Dictionary = hd["patterns"]
		for ph in hd["phases"]:
			for pid in ph["patterns"]:
				if not pats.has(pid):
					ok = false
					why = pid
		for m in ms:
			for pid in m.get("add", {}):
				if not hd["phases"][int(m.get("phase", 0))]["patterns"].has(pid):
					ok = false
					why = "add " + pid
			for pid in m.get("unlock", []):
				if not hd["phases"][int(m.get("phase", 0))]["patterns"].has(pid):
					ok = false
					why = "unlock " + pid
			for pid in m.get("tune", {}):
				if not pats.has(pid):
					ok = false
					why = "tune " + pid
				else:
					for f in m["tune"][pid]:
						if pats[pid][f] != m["tune"][pid][f]:
							ok = false
							why = "tune %s.%s" % [pid, f]
		check(ok, "boss %s Heart def: every mutation applies and every phase pattern exists" % bid, why)
		var shifted := true
		for i in range(1, hd["phases"].size()):
			if float(hd["phases"][i]["at"]) <= float(bd["phases"][i]["at"]):
				shifted = false
		check(shifted and float(hd["life"]) > float(bd["life"]) and hd["name"].find("Heart of Rot") >= 0, "boss %s Heart: earlier phases, more life, new name" % bid)
		check(str(Data.enemies[bid]["phases"]) == str(bd["phases"]) and not Data.enemies[bid].has("heart"), "boss %s base def untouched by heart_def" % bid)

func _open_atlas_all(st: Dictionary) -> void:
	for h in AR.within(Vector2i.ZERO, 3):
		if AR.ring_of(h) > 0 and not st["revealed"].has(AR.key(h)):
			st["revealed"].append(AR.key(h))

var killed := {}   # the last boss _kill_boss killed: {def, name}

func _kill_boss(lv) -> void:
	killed = {}
	var p = lv.player
	for o in lv.objectives:
		if o["type"] != "boss":
			o["done"] = true
	lv._update_seal()
	p.global_position = lv.cell_center(lv.rooms[lv.layout["boss"]]["anchor"])
	await frames(20)
	if lv.boss != null and is_instance_valid(lv.boss):
		killed = {"def": lv.boss.def, "name": lv.boss.display_name}
		lv.boss.process_mode = Node.PROCESS_MODE_INHERIT
		lv.boss.die(p)
		await frames(10)

func test_live_rot() -> void:
	var st: Dictionary = AR.ensure(Game.ch)
	_open_atlas_all(st)
	var h := Vector2i(2, 0)
	var hk := AR.key(h)
	st["restored"].erase(hk)
	# Rot 0 vs Rot 2 on the same layout: density and rewards
	st["rot"].erase(hk)
	var n := AR.clears(st, h)
	main.enter_atlas(h, 4242)
	await frames(3)
	var lv0 = Game.level
	var dens0: float = lv0.density
	var rew0: float = lv0.reward_bonus
	var life0: float = float(lv0.enemy_run["life"])
	var total0: int = lv0.total_enemies
	main.go_hub(false)
	await frames(3)
	st["rot"][hk] = 2
	main.enter_atlas(h, 4242)
	await frames(3)
	var lv = Game.level
	check(lv.rot == 2 and lv.level_name.find("Rot 2") >= 0, "a Rot 2 hex runs at Rot 2 (shown in the level name)", lv.level_name)
	check(is_equal_approx(lv.density, dens0 * 1.2) and is_equal_approx(lv.reward_bonus, rew0 + 35.0), "Rot 2 zone: 20% denser, +35% rewards", "%.2f/%.2f %.0f/%.0f" % [lv.density, dens0, lv.reward_bonus, rew0])
	check(is_equal_approx(float(lv.enemy_run["life"]), life0 * 1.3), "Rot 2 zone: monsters have 30% more life")
	check(lv.total_enemies > total0, "Rot 2 zone spawns more enemies on the same layout", "%d vs %d" % [lv.total_enemies, total0])
	# death adds Rot once
	check(lv.apply_death_rot() == 3 and lv.apply_death_rot() == 3 and AR.rot_of(st, h) == 3, "death in the zone adds +1 Rot, once per run")
	main.go_hub(false)
	await frames(3)
	# Heart run (Rot 3): mutated boss, choice portals, Restore
	st["rot"][hk] = 3
	main.enter_atlas(h)
	await frames(3)
	lv = Game.level
	check(lv.def.get("heart", false) and lv.def["heart_mutations"].size() == 1, "a Rot 3 hex has a Heart with 1 mutation")
	await _kill_boss(lv)
	check(not killed.is_empty() and killed["def"].get("heart", false) and str(killed["name"]).find("Heart of Rot") >= 0, "the zone boss spawns as the Heart of Rot", str(killed.get("name", "")))
	check(not killed.is_empty() and killed["def"]["patterns"].size() >= Data.enemies[lv.def["boss"]]["patterns"].size(), "the Heart carries its mutation")
	check(lv.boss_dead and AR.clears(st, h) == n + 1, "killing the Heart clears the hex")
	check(lv.markers.has("rot_restore") and lv.markers.has("rot_harvest"), "Restore / Harvest choices appear after the Heart dies")
	var spread_n: int = lv.rot_spread.size()
	check(spread_n >= 0 and int(st["spreads"]) >= 1, "the completion spread the Rot", str(lv.rot_spread))
	check(lv.apply_death_rot() == -1, "dying after the boss adds no Rot")
	check(lv.choose_heart("restore") and AR.rot_of(st, h) == 0 and AR.is_restored(st, h), "Restore: the hex goes to Rot 0 and is Restored")
	check(not lv.choose_heart("harvest") and not lv.markers.has("rot_harvest"), "only one Heart choice per run")
	main.go_hub(true)
	await frames(3)
	# Harvest on another hex
	var h2 := Vector2i(-2, 0)
	var hk2 := AR.key(h2)
	st["restored"].erase(hk2)
	st["rot"][hk2] = 4
	var fronts0 := AR.fronts_next(st)
	main.enter_atlas(h2)
	await frames(3)
	lv = Game.level
	check(lv.def["heart_mutations"].size() == 2, "a Rot 4 Heart has 2 mutations")
	await _kill_boss(lv)
	var before_items := _drop_count(lv)
	var fronts_after_kill := AR.fronts_next(st)
	check(lv.choose_heart("harvest"), "Harvest can be chosen")
	await frames(2)
	var after_items := _drop_count(lv)
	check(AR.rot_of(st, h2) >= 4 and not AR.is_restored(st, h2), "Harvest: the hex keeps its Rot", str(AR.rot_of(st, h2)))
	check(AR.fronts_next(st) == fronts_after_kill + 1 and fronts0 >= 2, "Harvest: the next spread gets an extra front")
	check(after_items >= before_items + 14, "Harvest drops a legendary, gold, materials, gems and rares", "%d -> %d" % [before_items, after_items])
	check(_has_legendary(lv), "Harvest payout includes a legendary")
	main.go_hub(true)
	await frames(3)
	# the safety ring: a ring-1 hex never shows Rot
	main.enter_atlas(Vector2i(1, 0))
	await frames(3)
	check(Game.level.rot == 0 and not Game.level.def.get("heart", false), "ring-1 hexes never run with Rot")
	check(Game.level.apply_death_rot() == -1 and AR.rot_of(st, Vector2i(1, 0)) == 0, "death on ring 1 adds no Rot")
	main.go_hub(false)
	await frames(3)
	# Atlas panel shows Rot
	var ui = main.ui
	if ui != null:
		st["rot"]["3,0"] = 3
		st["restored"].erase("3,0")
		ui.toggle("atlas")
		var ap = ui.panels["atlas"]
		ap.select(Vector2i(3, 0))
		check(ap.detail.text.find("Rot 3") >= 0 and ap.detail.text.find("Heart of Rot") >= 0, "Atlas panel shows Rot level and the Heart's mutations")
		check(ap.progress_label.text.find("Rot ") >= 0 and ap.map.forecast.size() == AR.forecast(st).size(), "Atlas panel shows Rot total and the forecast")
		ap.select(h)
		check(ap.detail.text.find("Restored") >= 0, "Atlas panel marks Restored regions")
		if args.has("shot"):
			await _shot("atlas_rot")
			# a natural-looking atlas: everything revealed, six spreads, one Heart, forecast visible
			var keep: Dictionary = Game.ch.atlas
			var demo := AR.new_state(20261105)
			_open_atlas_all(demo)
			for i in 6:
				AR.spread(demo)
			Game.ch.atlas = demo
			var best := Vector2i(2, 0)
			for k in demo["rot"]:
				if int(demo["rot"][k]) > AR.rot_of(demo, best):
					best = AR.parse(k)
			ap.select(best)
			await _shot("atlas_rot_forecast")
			Game.ch.atlas = keep
		ui.close_all()

func _drop_count(lv) -> int:
	var c := 0
	for ch in lv.get_children():
		c += _count_drops(ch)
	return c

func _count_drops(n) -> int:
	var c := 1 if n.get_script() != null and str(n.get_script().resource_path).ends_with("loot_drop.gd") else 0
	for k in n.get_children():
		c += _count_drops(k)
	return c

func _has_legendary(lv) -> bool:
	return _find_leg(lv)

func _find_leg(n) -> bool:
	if n.get_script() != null and str(n.get_script().resource_path).ends_with("loot_drop.gd"):
		var it = n.get("item")
		if typeof(it) == TYPE_DICTIONARY and str(it.get("rarity", "")) == "legendary":
			return true
	for k in n.get_children():
		if _find_leg(k):
			return true
	return false

func _shot(nm: String) -> void:
	await frames(6)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var dir := "res://tests/screens_out_atlas"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	img.save_png(ProjectSettings.globalize_path("%s/%s.png" % [dir, nm]))
	note("shot %s" % nm)

# ------------------------------------------------------------------ Phase 1D: zone mechanics
func test_mechanic_rules() -> void:
	var mc := AR.mech_cfg()
	check(mc.get("list", []).size() == 4 and not AR.mechanic_info("glazed").is_empty() and not AR.mechanic_info("unfinished").is_empty(), "mechanics: Glazed Elites and The Unfinished are defined (plus the 2D minor mechanics)")
	check(Data.materials.has("glaze_flake") and Data.materials.has("pigment_dust"), "mechanics: Glaze Flake and Pigment Dust materials exist")
	check(float(Data.materials["glaze_flake"].get("weight", 1)) == 0.0 and float(Data.materials["pigment_dust"].get("weight", 1)) == 0.0, "mechanics: the new materials never drop at random (weight 0)")
	var seen := {}
	for i in 3000:
		seen[Loot._roll_material()] = true
	check(not seen.has("glaze_flake") and not seen.has("pigment_dust"), "mechanics: random material rolls never give Flakes or Dust", str(seen.keys()))
	var hits := 0
	var tot := 0
	var kinds := {}
	var stable := true
	for sd in [1, 7, 99]:
		for h in AR.within(Vector2i.ZERO, 3):
			if AR.ring_of(h) == 0:
				continue
			for n in 4:
				var m := AR.natural_mechanic(sd, h, n)
				stable = stable and m == AR.natural_mechanic(sd, h, n)
				tot += 1
				if m != "":
					hits += 1
					kinds[m] = int(kinds.get(m, 0)) + 1
	var rate := float(hits) / float(tot)
	check(stable, "mechanics: the natural roll is deterministic per (seed, hex, clears)")
	check(rate > 0.22 and rate < 0.38, "mechanics: about 30% of runs roll a natural mechanic", "%.3f" % rate)
	check(int(kinds.get("glazed", 0)) > hits * 0.3 and int(kinds.get("unfinished", 0)) > hits * 0.3, "mechanics: both mechanics come up", str(kinds))
	check(AR.natural_mechanic(1, Vector2i.ZERO, 0) == "", "mechanics: the hub has no mechanic")
	check(AR.sketch_colours(1, 0) == 1 and AR.sketch_colours(2, 2) == 1 and AR.sketch_colours(2, 3) == 2 and AR.sketch_colours(3, 0) == 2 and AR.sketch_colours(3, 5) == 2, "mechanics: sketches need 1 colour, 2 at Rot 3+ or ring 3")
	check(AR.colour_for_status("ignite").get("id", "") == "vermilion" and AR.colour_for_status("freeze").get("id", "") == "ultramarine" and AR.colour_for_status("chill").get("id", "") == "ultramarine", "mechanics: ignite = vermilion, chill/freeze = ultramarine")
	check(AR.colour_for_status("poison").get("id", "") == "verdigris" and AR.colour_for_status("shock").get("id", "") == "lead_white" and AR.colour_for_status("bleed").get("id", "") == "madder" and AR.colour_for_status("stun").get("id", "") == "madder", "mechanics: poison = verdigris, shock = lead white, bleed/stun = madder")
	check(AR.colour_for_status("snare").is_empty(), "mechanics: other statuses paint nothing")
	check(AR.glaze_layers(1) == 2 and AR.glaze_layers(3) == 3 and AR.glaze_layers(6) == 4, "mechanics: glaze layers = modifiers, at least 2, at most 4")

func _find(lv, pred: Callable):
	for e in lv.enemies:
		if is_instance_valid(e) and e.alive and pred.call(e):
			return e
	return null

func _fresh_enemy(lv, mods: Array):
	var e = lv.spawn_enemy(Data.enemies["ghoul"], lv.monster_level, mods, lv.player.global_position + Vector2(400, 0))
	e.process_mode = Node.PROCESS_MODE_DISABLED
	return e

func test_live_mechanics() -> void:
	var st: Dictionary = AR.ensure(Game.ch)
	_open_atlas_all(st)
	var h := Vector2i(2, 0)
	var hk := AR.key(h)
	st["rot"].erase(hk)
	st["restored"].erase(hk)
	# no mechanic vs The Unfinished on the same seed: same layout and packs (own RNG)
	Game.atlas_force_mechanic = "none"
	seed(5151)   # _populate shuffles with the global RNG, which also decides the objectives (and the arena seal in the grid)
	main.enter_atlas(h, 5151)
	await frames(3)
	var grid0: int = hash(Game.level.layout["grid"])
	var cells0: int = Game.level.layout["rooms"].size()
	check(Game.level.mechanic == "", "mechanics: 'none' runs without a mechanic")
	main.go_hub(false)
	await frames(3)
	Game.atlas_force_mechanic = "unfinished"
	seed(5151)
	main.enter_atlas(h, 5151)
	await frames(3)
	var lv = Game.level
	check(lv.mechanic == "unfinished" and lv.level_name.find("The Unfinished") >= 0, "mechanics: The Unfinished shows in the level name", lv.level_name)
	check(hash(lv.layout["grid"]) == grid0 and lv.layout["rooms"].size() == cells0, "The Unfinished: same layout as the run without it (own RNG)", "rooms %d vs %d, seeds %d" % [lv.layout["rooms"].size(), cells0, lv.run_seed])
	check(int(lv.mech_stats["sketch_packs"]) >= 3 and int(lv.mech_stats["sketches"]) > 0, "The Unfinished: at least 3 packs are sketched", str(lv.mech_stats))
	var sk = _find(lv, func(e): return e.sketched)
	check(sk != null and sk.sketch_need.size() == 1, "The Unfinished: ring 2 / Rot 0 sketches need 1 colour")
	check(lv.objective_text().find("The Unfinished") >= 0, "The Unfinished: the objective panel tracks sketches")
	var u: Dictionary = AR.mech_cfg()["unfinished"]
	var pal: Array = u["palette"]
	var ver: Dictionary = AR.colour_for_status("ignite")
	var ult: Dictionary = AR.colour_for_status("chill")
	var ver_id: String = ver["id"]
	# immunity: hits and DoTs leave life untouched but fill the raw paint
	var e1 = _fresh_enemy(lv, [])
	e1.make_sketch([AR.colour_for_status("poison")], u)
	var dealt: float = e1.receive_hit({"physical": e1.max_life * 0.2}, {"flags": {}}, lv.player, false)
	check(dealt == 0.0 and e1.life == e1.max_life and e1.sketch_raw > 0.0 and e1.sketched, "The Unfinished: a sketch takes no damage from hits", "dealt %.1f raw %.3f" % [dealt, e1.sketch_raw])
	var raw1: float = e1.sketch_raw
	e1.take_dot(e1.max_life * 0.1, "fire")
	check(e1.life == e1.max_life and e1.sketch_raw > raw1, "The Unfinished: DoTs deal no damage to a sketch but add raw paint")
	e1._sketch_raw(e1.max_life * 0.7)
	check(not e1.sketched and e1.painted_by == "raw" and e1.loot_rank_up, "The Unfinished: enough raw paint fills the sketch in (no colour needed)")
	var d2: float = e1.receive_hit({"physical": e1.max_life * 0.05}, {"flags": {}}, lv.player, false)
	check(d2 > 0.0 and e1.life < e1.max_life, "The Unfinished: a filled-in sketch takes damage again")
	# colour: the right status paints it, the wrong one does not
	var e2 = _fresh_enemy(lv, [])
	e2.make_sketch([ver], u)
	e2.add_status("chill", 1.0, {})
	check(e2.sketched, "The Unfinished: the wrong colour does not paint")
	e2.add_status("ignite", 1.0, {"dps": 1.0, "dtype": "fire"})
	check(not e2.sketched and e2.painted_by == "colour" and e2.loot_rank_up and e2.sketch_have.has(ver_id), "The Unfinished: ignite paints a vermilion sketch")
	var dust0 := int(lv.mech_stats["dust"])
	var drops0 := _drop_count(lv)
	e2.die(lv.player)
	await frames(2)
	check(int(lv.mech_stats["dust"]) == dust0 + int(u.get("dust", 1)) and int(lv.mech_stats["painted"]) >= 1, "The Unfinished: a painted sketch drops Pigment Dust", str(lv.mech_stats))
	check(_drop_count(lv) >= drops0 + 2, "The Unfinished: a painted normal monster drops as an elite (guaranteed gold) plus Dust", "%d -> %d" % [drops0, _drop_count(lv)])
	# two colours
	var e3 = _fresh_enemy(lv, [])
	e3.make_sketch([ver, ult], u)
	e3.add_status("ignite", 1.0, {"dps": 1.0, "dtype": "fire"})
	check(e3.sketched and e3.sketch_have.size() == 1, "The Unfinished: a 2-colour sketch stays sketched after one colour")
	e3.add_status("freeze", 0.5, {})
	check(not e3.sketched and e3.painted_by == "colour", "The Unfinished: the second colour (freeze counts as ultramarine) paints it")
	# a real hit through Combat.deal applies its status to the sketch
	var e4 = _fresh_enemy(lv, [])
	e4.make_sketch([ver], u)
	var pk := {"dmg": {"fire": [50.0, 50.0]}, "crit_chance": 0.0, "crit_mult": 1.5, "faction": "player", "kind": "skill", "tags": [], "flags": {},
		"status": [{"type": "ignite", "chance": 100.0}], "dot_mult": 1.0, "status_dur": 1.0, "elite_inc": 0.0}
	var dd: float = Combat.deal(pk, lv.player, e4)
	check(dd == 0.0 and not e4.sketched and e4.painted_by == "colour", "The Unfinished: a fire hit with ignite paints the sketch (no damage on that hit)", "dealt %.1f sketched %s" % [dd, str(e4.sketched)])
	# a painted elite gets the elite rarity bonus
	var e5 = _fresh_enemy(lv, ["mighty"])
	e5.make_sketch([AR.colour_for_status("stun")], u)
	e5.add_status("stun", 0.3, {})
	check(not e5.sketched and is_equal_approx(e5.loot_rarity_extra, float(u.get("elite_rarity_bonus", 150))), "The Unfinished: stun paints madder; a painted elite gets extra rarity")
	# Rot 3 / ring 3: two colours
	main.go_hub(false)
	await frames(3)
	st["rot"][hk] = 3
	main.enter_atlas(h, 5151)
	await frames(3)
	lv = Game.level
	sk = _find(lv, func(e): return e.sketched)
	check(sk != null and sk.sketch_need.size() == 2, "The Unfinished: Rot 3 sketches need 2 colours")
	main.go_hub(false)
	await frames(3)
	st["rot"].erase(hk)
	# Glazed Elites
	Game.atlas_force_mechanic = "glazed"
	var glz = null
	for sd in [5151, 5252, 5353, 5454, 5555]:
		main.enter_atlas(h, sd)
		await frames(3)
		lv = Game.level
		glz = _find(lv, func(e): return e.glaze_total > 0)
		if glz != null:
			break
		main.go_hub(false)
		await frames(3)
	check(lv.mechanic == "glazed" and lv.level_name.find("Glazed Elites") >= 0, "mechanics: Glazed Elites shows in the level name", lv.level_name)
	check(glz != null and int(lv.mech_stats["glazed"]) > 0, "Glazed Elites: the zone has glazed elites", str(lv.mech_stats))
	var all_ok := true
	for e in lv.enemies:
		if is_instance_valid(e) and e.is_elite and not e.is_miniboss and not e.is_boss:
			all_ok = all_ok and e.glaze_total >= 2 and e.glaze_total <= 4 and e.glaze_total == e.elite_mods.size()
	check(all_ok, "Glazed Elites: every elite is glazed with 2-4 layers, one per modifier")
	check(lv.objective_text().find("Glazed Elites") >= 0, "Glazed Elites: the objective panel tracks peels")
	# peeling: burst poise fills, the outer modifier goes, a Flake drops, then a short immunity
	var gd: Dictionary = AR.mech_cfg()["glazed"]
	var g = _fresh_enemy(lv, ["mighty", "armoured"])
	g.make_glazed(gd)
	check(g.glaze_layers == 2 and is_equal_approx(g.elite_taken, 0.65), "Glazed Elites: a 2-modifier elite has 2 layers")
	var dm0: float = g.damage_mult
	var fl0 := int(lv.mech_stats["flakes"])
	check(not g.glaze_hit(g.max_life * 0.1), "Glazed Elites: one 10% hit does not peel")
	check(g.glaze_fight_t == 0.0, "Glazed Elites: the first hit starts the kill timer")
	check(g.glaze_hit(g.max_life * 0.1), "Glazed Elites: a second 10% hit right after fills the poise and peels")
	check(g.glaze_layers == 1 and g.elite_mods.size() == 1 and is_equal_approx(g.elite_taken, 1.0) and is_equal_approx(g.damage_mult, dm0), "Glazed Elites: the outer layer (Armoured) is peeled off; Mighty stays")
	check(int(lv.mech_stats["flakes"]) == fl0 + 1 and int(lv.mech_stats["peels"]) >= 1, "Glazed Elites: a peel drops a Glaze Flake")
	check(not g.glaze_hit(g.max_life * 0.5) and g.glaze_layers == 1, "Glazed Elites: poise is immune right after a peel")
	# burst: the bar drains all the time, so slow damage never peels
	var gb = _fresh_enemy(lv, ["mighty", "armoured"])
	gb.make_glazed(gd)
	for i in 20:
		gb.glaze_hit(gb.max_life * 0.03)
		gb.glaze_tick(1.0)
	check(gb.glaze_layers == 2 and float(gb.glaze_poise["poise"]) < 100.0, "Glazed Elites: 3% of life per second never peels (the bar drains)", "%.0f" % float(gb.glaze_poise["poise"]))
	check(is_equal_approx(gb.glaze_fight_t, 20.0) and gb.glaze_shatter_count() == 0, "Glazed Elites: a 20 s kill shatters nothing")
	# stuns and freezes add stun poise (hit-stuns and skill stuns both go through add_status)
	var gs = _fresh_enemy(lv, ["mighty", "armoured"])
	gs.make_glazed(gd)
	gs.add_status("stun", 0.3, {})
	check(is_equal_approx(float(gs.glaze_poise["poise"]), float(gd.get("stun_poise", 60))) and gs.glaze_layers == 2, "Glazed Elites: a stun adds stun poise")
	gs.add_status("freeze", 0.3, {})
	check(gs.glaze_layers == 1, "Glazed Elites: a stun then a freeze peel a layer")
	# kill speed: remaining layers shatter on death
	var gk = _fresh_enemy(lv, ["frenzied", "mighty", "armoured"])
	gk.make_glazed(gd)
	gk.glaze_fight_t = 2.0
	check(gk.glaze_shatter_count() == 3, "Glazed Elites: a kill within shatter_fast shatters every layer")
	gk.glaze_fight_t = (float(gd["shatter_fast"]) + float(gd["shatter_slow"])) / 2.0
	check(gk.glaze_shatter_count() == 2, "Glazed Elites: a mid-speed kill shatters about half", str(gk.glaze_shatter_count()))
	gk.glaze_fight_t = 1.0
	var fl1 := int(lv.mech_stats["flakes"])
	var full0 := int(lv.mech_stats["full_peels"])
	gk.die(lv.player)
	var gk_extra: float = gk.loot_rarity_extra
	await frames(2)
	check(int(lv.mech_stats["flakes"]) == fl1 + 3 + int(gd.get("full_bonus", 1)) and int(lv.mech_stats["full_peels"]) == full0 + 1, "Glazed Elites: a fast kill shatters 3 Flakes + the full-glaze bonus", str(lv.mech_stats))
	check(is_equal_approx(gk_extra, float(gd.get("full_rarity_bonus", 150))), "Glazed Elites: a fully removed glaze adds rarity before the drops roll")
	# peel the last layer, then a slow kill: still a full glaze (all layers peeled)
	g.glaze_poise["immune"] = 0.0
	g.glaze_poise["stagger"] = 0.0
	check(g.glaze_hit(g.max_life * 0.5) and g.glaze_layers == 0 and is_equal_approx(g.damage_mult, dm0 / 1.4), "Glazed Elites: the last layer (Mighty) peels")
	check(g.is_elite and g.elite_title() == "Peeled", "Glazed Elites: a fully peeled elite is still an elite")
	g.glaze_fight_t = 30.0
	var fl2 := int(lv.mech_stats["flakes"])
	g.die(lv.player)
	await frames(2)
	check(int(lv.mech_stats["flakes"]) == fl2 + int(gd.get("full_bonus", 1)), "Glazed Elites: peeling every layer earns the full bonus even on a slow kill")
	# other modifiers come off cleanly
	var g2 = _fresh_enemy(lv, ["frenzied", "vampiric", "shielded", "frostbound"])
	g2.make_glazed(gd)
	var sp0: float = g2.speed / 1.35
	for i in 4:
		g2.glaze_poise["immune"] = 0.0
		g2.glaze_poise["stagger"] = 0.0
		g2.glaze_hit(g2.max_life * 0.5)
	check(g2.glaze_layers == 0 and g2.convert_type == "" and g2.on_hit_status == "" and g2.shield_max == 0.0 and g2.leech == 0.0 and is_equal_approx(g2.speed, sp0), "Glazed Elites: peeling removes conversion, shield, leech and speed")
	# a real hit through receive_hit builds glaze poise
	var g3 = _fresh_enemy(lv, ["regenerating", "blinking"])
	g3.make_glazed(gd)
	g3.receive_hit({"void": g3.max_life * 0.12}, {"flags": {}}, lv.player, false)
	check(float(g3.glaze_poise["poise"]) > 0.0 or g3.glaze_layers < 2, "Glazed Elites: hits fill the glaze poise bar")
	main.go_hub(false)
	await frames(3)
	# Atlas panel: the next run's mechanic
	Game.atlas_force_mechanic = "none"
	var ui = main.ui
	if ui != null:
		var target := Vector2i.ZERO
		var tid := ""
		for hx in AR.within(Vector2i.ZERO, 3):
			var mm := AR.natural_mechanic(int(st["seed"]), hx, AR.clears(st, hx))
			if mm != "":
				target = hx
				tid = mm
				break
		ui.toggle("atlas")
		var ap = ui.panels["atlas"]
		if tid != "":
			ap.select(target)
			check(ap.detail.text.find("Mechanic: " + str(AR.mechanic_info(tid)["name"])) >= 0, "Atlas panel shows the next run's mechanic", tid)
			if args.has("shot"):
				await _shot("atlas_mechanic")
		ap.select(Vector2i(1, 0))
		check(ap.detail.text.find("Mechanic") >= 0, "Atlas panel always lists the mechanic line")
		ui.close_all()
	if args.has("shot"):
		for mid in ["unfinished", "glazed"]:
			Game.atlas_force_mechanic = mid
			main.enter_atlas(h, 5151)
			await frames(3)
			lv = Game.level
			var tgt = _find(lv, func(e): return e.sketched or e.glaze_total > 0)
			if tgt != null:
				lv.player.global_position = tgt.global_position + Vector2(-60, 0)
				await frames(30)
				await _shot("mech_" + mid)
			main.go_hub(false)
			await frames(3)

# ------------------------------------------------------------------ Pigments & Varnish (Phase 1E)
func _bare_state(sd: int) -> Dictionary:
	var st := AR.new_state(sd)
	_open_atlas_all(st)
	return st

func test_pigment_rules() -> void:
	var pc := AR.pig_cfg()
	check(pc.get("list", []).size() == 2 and pc["mods"]["glazed"].size() == 4 and pc["mods"]["unfinished"].size() == 4, "pigments: 2 Pigments with 4 modifiers each")
	for p in pc["list"]:
		check(Data.materials.has(str(p["material"])), "pigments: %s costs a real material" % p["id"])
	var st := _bare_state(4242)
	var a := AR.add_pigment(st, "glazed")
	var st2 := _bare_state(4242)
	var b := AR.add_pigment(st2, "glazed")
	check(a["mod"] == b["mod"] and int(a["charges"]) == int(pc["charges"]) and int(a["uid"]) == 0 and int(st["crafted"]) == 1, "pigments: the modifier is seeded by (atlas seed, craft count)", str(a))
	var seen := {}
	for i in 40:
		seen[AR.add_pigment(_bare_state(100 + i), "unfinished")["mod"]] = true
	check(seen.size() == 4, "pigments: every modifier can roll", str(seen.keys()))
	check(AR.add_pigment(st, "glazed", "thick_glaze")["mod"] == "thick_glaze" and AR.add_pigment(st, "nope").is_empty(), "pigments: a forced modifier; unknown Pigments refused")
	# crafting pays the material
	var ch = CharacterData.new()
	ch.setup_new("warrior", "Dan")
	var st3 := _bare_state(7)
	var gcost := int(AR.pigment_info("glazed")["cost"])
	var ucost := int(AR.pigment_info("unfinished")["cost"])
	ch.materials["glaze_flake"] = gcost - 1
	check(not AR.craft_pigment(st3, ch, "glazed")["ok"] and int(ch.materials["glaze_flake"]) == gcost - 1, "pigments: crafting without enough Flakes fails and costs nothing")
	ch.materials["glaze_flake"] = gcost + 30
	var r := AR.craft_pigment(st3, ch, "glazed")
	check(r["ok"] and int(ch.materials["glaze_flake"]) == 30 and st3["pigments"].size() == 1, "pigments: a Glazed Pigment costs its Glaze Flakes (%d)" % gcost)
	ch.materials["pigment_dust"] = ucost
	check(AR.craft_pigment(st3, ch, "unfinished")["ok"] and int(ch.materials["pigment_dust"]) == 0, "pigments: an Unfinished Pigment costs its Pigment Dust (%d)" % ucost)
	ch.materials["pigment_dust"] = 9999
	for i in 20:
		AR.craft_pigment(st3, ch, "unfinished")
	check(AR.pigment_count(st3) == int(pc["stock_cap"]), "pigments: the Easel holds at most stock_cap Pigments", str(AR.pigment_count(st3)))
	# slots
	var st4 := _bare_state(9)
	AR.add_pigment(st4, "glazed", "thick_glaze")
	AR.add_pigment(st4, "unfinished", "two_tone")
	AR.add_pigment(st4, "glazed", "crowded_glaze")
	check(AR.slot_pigment(st4, 0) and AR.slot_pigment(st4, 0) and not AR.slot_pigment(st4, 0), "pigments: at most 2 slotted")
	check(st4["easel"][0]["mod"] == "thick_glaze" and st4["easel"][1]["mod"] == "two_tone" and st4["pigments"].size() == 1, "pigments: slot order is kept")
	check(AR.pigment_slots(st4, Vector2i(1, 0)) == 1 and AR.pigment_slots(st4, Vector2i(2, 0)) == 1 and AR.pigment_slots(st4, Vector2i(3, 0)) == 2, "pigments: 1 slot in rings 1-2, 2 in ring 3")
	AR.restore(st4, Vector2i(2, 0))
	check(AR.pigment_slots(st4, Vector2i(2, 0)) == 2, "pigments: a Restored region has 2 slots")
	check(AR.run_pigments(st4, Vector2i(1, 0)).size() == 1 and AR.run_pigments(st4, Vector2i(3, 0)).size() == 2, "pigments: a run uses the first N slotted Pigments")
	var ms := AR.run_mechanics(st4, Vector2i(3, 0), AR.run_pigments(st4, Vector2i(3, 0)))
	check(ms.size() == 2 and ms[0] == "glazed" and ms[1] == "unfinished", "pigments: both mechanics in one zone, in slot order", str(ms))
	var nat_found := false
	for hx in AR.within(Vector2i.ZERO, 3):
		var nat := AR.natural_mechanic(9, hx, 0)
		if nat == "unfinished" and AR.ring_of(hx) > 0:
			var one := AR.run_mechanics(st4, hx, [st4["easel"][0]])
			nat_found = one.size() == 2 and one[0] == "glazed" and one[1] == "unfinished"
			break
	check(nat_found, "pigments: the natural roll still adds a different mechanic")
	check(AR.unslot_pigment(st4, 0) and st4["easel"].size() == 1 and st4["pigments"].size() == 2, "pigments: unslot returns it to the stock")
	# charges
	var st5 := _bare_state(11)
	var p5 := AR.add_pigment(st5, "glazed", "thick_glaze")
	AR.slot_pigment(st5, 0)
	var gone := AR.spend_pigments(st5, [int(p5["uid"])], 1)
	check(gone.is_empty() and int(st5["easel"][0]["charges"]) == int(pc["charges"]) - 1, "pigments: a run spends 1 charge")
	AR.spend_pigments(st5, [999], 5)
	check(int(st5["easel"][0]["charges"]) == int(pc["charges"]) - 1, "pigments: other uids are untouched")
	gone = AR.spend_pigments(st5, [int(p5["uid"])], 10)
	check(gone.size() == 1 and st5["easel"].is_empty(), "pigments: an empty Pigment is used up", str(gone))
	# tuning
	var g0: Dictionary = AR.mech_cfg()["glazed"]
	var g1 := AR.mech_tuning("glazed", ["thick_glaze"])
	var g2 := AR.mech_tuning("glazed", ["thick_glaze", "thick_glaze"])
	check(int(g1["min_layers"]) == int(g0["min_layers"]) + 1 and int(g1["max_layers"]) == int(g0["max_layers"]) + 1 and int(g2["max_layers"]) == int(g0["max_layers"]) + 2, "pigments: Thick adds a layer; the same modifier twice stacks")
	check(is_equal_approx(float(AR.mech_tuning("glazed", ["crowded_glaze"])["elite_chance_mult"]), float(g0["elite_chance_mult"]) * 1.25), "pigments: Crowded multiplies the elite chance")
	check(int(AR.mech_cfg()["glazed"]["min_layers"]) == int(g0["min_layers"]), "pigments: tuning copies, the data is untouched")
	var u2 := AR.mech_tuning("unfinished", ["two_tone"])
	check(AR.sketch_colours(1, 0, u2) == 2 and AR.sketch_colours(3, 0, u2) == 3, "pigments: Two-Tone needs one more colour (up to 3)")
	check(is_equal_approx(float(AR.mech_tuning("unfinished", ["stubborn_sketch"])["filled_dust_chance"]), 1.0), "pigments: Stubborn makes filled-in sketches always drop Dust (capped at 100%)")
	# save round trip
	var ch6 = CharacterData.new()
	ch6.setup_new("mage", "Dan")
	ch6.atlas = _bare_state(13)
	AR.add_pigment(ch6.atlas, "glazed", "biting_glaze")
	AR.add_pigment(ch6.atlas, "unfinished", "vivid_sketch")
	AR.slot_pigment(ch6.atlas, 1)
	AR.add_varnish(ch6.atlas, "thin_varnish", 2)
	AR.slot_varnish(ch6.atlas, "thin_varnish")
	var ch7 = CharacterData.new()
	ch7.from_dict(JSON.parse_string(JSON.stringify(ch6.to_dict())))
	check(str(ch7.atlas) == str(ch6.atlas), "pigments: Pigments, Easel and Varnish survive a JSON save", str(ch7.atlas))
	var raw: Dictionary = ch6.to_dict()["atlas"].duplicate(true)
	raw["pigments"].append({"id": "glazed", "mod": "nope", "charges": 3})
	raw["pigments"].append({"id": "glazed", "mod": "thick_glaze", "charges": 0})
	raw["varnish"]["bogus"] = 3
	raw["varnish_slots"].append("bogus")
	var cl := AR.sanitize(raw)
	check(cl["pigments"].size() == 1 and not cl["varnish"].has("bogus") and cl["varnish_slots"] == ["thin_varnish"], "pigments: bad Pigments / Varnishes are dropped on load")
	var old := {"seed": 5, "revealed": [], "clears": {}}
	var cl2 := AR.sanitize(old)
	check(cl2["pigments"].is_empty() and cl2["easel"].is_empty() and cl2["varnish"].is_empty() and cl2["varnish_slots"].is_empty(), "pigments: a 1D atlas loads with an empty Easel")

func test_varnish_rules() -> void:
	var vc := AR.varn_cfg()
	check(vc.get("list", []).size() == 6, "varnish: 6 rule-changers")
	var st := _bare_state(21)
	check(AR.varnish_slot_count(st) == 1, "varnish: 1 slot at the start")
	check(not AR.slot_varnish(st, "thin_varnish"), "varnish: an unowned Varnish cannot be slotted")
	AR.add_varnish(st, "thin_varnish")
	AR.add_varnish(st, "greed_varnish")
	check(AR.slot_varnish(st, "thin_varnish") and not AR.slot_varnish(st, "thin_varnish") and not AR.slot_varnish(st, "greed_varnish"), "varnish: one of each, slot limit holds")
	for hx in AR.within(Vector2i.ZERO, 1):
		if AR.ring_of(hx) == 1:
			st["clears"][AR.key(hx)] = 1
	check(AR.varnish_slot_count(st) == 2 and AR.slot_varnish(st, "greed_varnish"), "varnish: clearing a whole ring adds a slot")
	for hx in AR.within(Vector2i.ZERO, 3):
		if AR.ring_of(hx) > 0:
			st["clears"][AR.key(hx)] = 1
	check(AR.varnish_slot_count(st) == 3, "varnish: at most 3 slots in the MVP")
	# effects
	var base := _bare_state(22)
	var thin := _bare_state(22)
	AR.add_varnish(thin, "thin_varnish")
	AR.slot_varnish(thin, "thin_varnish")
	check(AR.fronts_next(thin) == AR.fronts_next(base) - 1, "varnish: Thin spreads one fewer front")
	check(AR.heart_at_for(thin) == AR.heart_at_for(base) + 1, "varnish: Thin moves the Heart to Rot 4")
	var d: Dictionary = AR.zone_def(22, Vector2i(2, 0))
	check(AR.apply_rot(d, 3, 22, Vector2i(2, 0), base).get("heart", false) and not AR.apply_rot(d, 3, 22, Vector2i(2, 0), thin).get("heart", false) and AR.apply_rot(d, 4, 22, Vector2i(2, 0), thin).get("heart", false), "varnish: with Thin, Rot 3 has no Heart, Rot 4 has")
	var greed := _bare_state(22)
	AR.add_varnish(greed, "greed_varnish")
	AR.slot_varnish(greed, "greed_varnish")
	check(is_equal_approx(float(AR.apply_rot(d, 2, 22, Vector2i(2, 0), greed)["rot_reward"]), float(AR.apply_rot(d, 2, 22, Vector2i(2, 0), base)["rot_reward"]) * 1.5), "varnish: Greedy raises Rot rewards 50%")
	var gh := Vector2i(2, 0)
	greed["rot"].erase(AR.key(gh))
	check(AR.add_death_rot(greed, gh) == 2, "varnish: Greedy makes a death add +2 Rot")
	var binder := _bare_state(23)
	AR.add_varnish(binder, "binder_varnish")
	AR.slot_varnish(binder, "binder_varnish")
	check(AR.pigment_slots(binder, Vector2i(3, 0)) == 1 and int(AR.add_pigment(binder, "glazed")["charges"]) == int(AR.pig_cfg()["charges"]) + 2, "varnish: Binding gives +2 charges but 1 Pigment slot")
	var bloom := _bare_state(24)
	AR.add_varnish(bloom, "bloom_varnish")
	AR.slot_varnish(bloom, "bloom_varnish")
	var n0 := 0
	var n1 := 0
	for hx in AR.within(Vector2i.ZERO, 3):
		for c in 6:
			if AR.ring_of(hx) > 0:
				n0 += 1 if AR.natural_mechanic(24, hx, c) != "" else 0
				n1 += 1 if AR.natural_mechanic(24, hx, c, float(AR.varnish_fx(bloom)["natural_mult"])) != "" else 0
	check(n1 > n0 * 1.6, "varnish: Blooming roughly doubles natural mechanics", "%d -> %d" % [n0, n1])
	# Heart drops
	var harvest_all := true
	var restores := 0
	var n := 0
	for i in 200:
		var s2 := _bare_state(300 + i)
		var hx := Vector2i(2, -1)
		harvest_all = harvest_all and AR.heart_varnish(s2, hx, "harvest") != ""
		if AR.heart_varnish(s2, hx, "restore") != "":
			restores += 1
		n += 1
	check(harvest_all, "varnish: Harvest always drops a Varnish")
	check(restores > 40 and restores < 100, "varnish: Restore drops one about a third of the time", "%d / %d" % [restores, n])
	var s3 := _bare_state(77)
	check(AR.heart_varnish(s3, Vector2i(2, 0), "harvest") == AR.heart_varnish(s3, Vector2i(2, 0), "harvest"), "varnish: the drop is seeded")
	check(AR.unslot_varnish(st, "thin_varnish") and not st["varnish_slots"].has("thin_varnish"), "varnish: unslot")

func test_live_pigments() -> void:
	var st: Dictionary = AR.ensure(Game.ch)
	_open_atlas_all(st)
	Game.atlas_force_mechanic = "none"
	st["pigments"] = []
	st["easel"] = []
	st["varnish_slots"] = []
	var h3 := Vector2i(3, 0)
	st["rot"].erase(AR.key(h3))
	st["restored"].erase(AR.key(h3))
	main.enter_atlas(h3, 6161)
	await frames(3)
	var reward0: float = Game.level.reward_bonus
	var dens0: float = Game.level.density
	main.go_hub(false)
	await frames(3)
	var pa := AR.add_pigment(st, "glazed", "thick_glaze")
	var pb := AR.add_pigment(st, "unfinished", "two_tone")
	AR.slot_pigment(st, 0)
	AR.slot_pigment(st, 0)
	var charges0 := int(AR.pig_cfg()["charges"])
	main.enter_atlas(h3, 6161)
	await frames(3)
	var lv = Game.level
	check(lv.mechanics == ["glazed", "unfinished"] and lv.level_name.find("Glazed Elites") >= 0 and lv.level_name.find("The Unfinished") >= 0, "live pigments: two Pigments give both mechanics in a ring-3 zone", lv.level_name)
	check(int(st["easel"][0]["charges"]) == charges0 - 1 and int(st["easel"][1]["charges"]) == charges0 - 1, "live pigments: entering spends 1 charge of each used Pigment")
	check(is_equal_approx(lv.reward_bonus, reward0 + 2.0 * float(AR.pig_cfg()["reward"])), "live pigments: each Pigment adds its reward bonus", "%.1f vs %.1f" % [lv.reward_bonus, reward0])
	check(int(lv.glaze_tune["min_layers"]) == int(AR.mech_cfg()["glazed"]["min_layers"]) + 1, "live pigments: Thick reaches the zone's glaze tuning")
	var g = _find(lv, func(e): return e.glaze_total > 0)
	check(g == null or g.glaze_total >= 3, "live pigments: glazed elites wear at least 3 layers with Thick")
	var sk = _find(lv, func(e): return e.sketched)
	check(sk != null and sk.sketch_need.size() == 3, "live pigments: ring 3 + Two-Tone sketches need 3 colours", str(sk.sketch_need.size() if sk != null else -1))
	check(lv.objective_text().find("Glazed Elites") >= 0 and lv.objective_text().find("The Unfinished") >= 0, "live pigments: the objective panel tracks both mechanics")
	check(lv.apply_death_rot() >= -1 and int(st["easel"][0]["charges"]) == charges0 - 2, "live pigments: a death spends 1 more charge")
	lv.apply_death_rot()
	check(int(st["easel"][0]["charges"]) == charges0 - 2, "live pigments: only once per run")
	main.go_hub(false)
	await frames(3)
	# ring 2: one slot, only the first Pigment is used
	var h2 := Vector2i(2, 0)
	st["rot"].erase(AR.key(h2))
	st["restored"].erase(AR.key(h2))
	var c1 := int(st["easel"][1]["charges"])
	main.enter_atlas(h2, 6161)
	await frames(3)
	check(Game.level.has_mech("glazed") and int(st["easel"][1]["charges"]) == c1, "live pigments: a ring-2 zone uses only the first slotted Pigment")
	main.go_hub(false)
	await frames(3)
	# Stubborn: a filled-in sketch always drops Dust
	st["easel"] = []
	st["pigments"] = []
	AR.add_pigment(st, "unfinished", "stubborn_sketch")
	AR.slot_pigment(st, 0)
	main.enter_atlas(h2, 6161)
	await frames(3)
	lv = Game.level
	check(is_equal_approx(float(lv.sketch_tune["raw_fill"]), float(AR.mech_cfg()["unfinished"]["raw_fill"]) + 0.25), "live pigments: Stubborn raises the raw fill")
	var e = _fresh_enemy(lv, [])
	e.make_sketch([AR.colour_for_status("poison")], lv.sketch_tune)
	e._sketch_raw(e.max_life * 0.9)
	var d0 := int(lv.mech_stats["dust"])
	var pby: String = e.painted_by
	e.die(lv.player)
	await frames(2)
	check(pby == "raw" and int(lv.mech_stats["dust"]) == d0 + 1, "live pigments: a filled-in sketch drops Dust (Stubborn)", str(lv.mech_stats))
	main.go_hub(false)
	await frames(3)
	# Vivid: a colour also adds raw fill
	var vt := AR.mech_tuning("unfinished", ["vivid_sketch"])
	main.enter_atlas(h2, 6161)
	await frames(3)
	lv = Game.level
	var e2 = _fresh_enemy(lv, [])
	e2.make_sketch([AR.colour_for_status("ignite"), AR.colour_for_status("poison")], vt)
	e2.add_status("ignite", 1.0, {"dps": 1.0, "dtype": "fire"})
	check(e2.sketched and is_equal_approx(e2.sketch_raw, 0.15), "live pigments: Vivid adds 15% raw fill per colour")
	main.go_hub(false)
	await frames(3)
	st["easel"] = []
	st["rot"].erase(AR.key(h3))
	# Varnish in a run: Dense = bigger packs, more rewards
	AR.add_varnish(st, "dense_varnish")
	st["varnish_slots"] = ["dense_varnish"]
	main.enter_atlas(h3, 6161)
	await frames(3)
	lv = Game.level
	check(is_equal_approx(lv.density, dens0 * 1.25) and is_equal_approx(lv.reward_bonus, reward0 + 20.0), "live varnish: Dense raises pack size and rewards", "%.2f/%.1f" % [lv.density, lv.reward_bonus])
	main.go_hub(false)
	await frames(3)
	st["varnish_slots"] = []
	# Heart drops: Harvest always leaves a Varnish
	var hh := Vector2i(-3, 0)
	st["restored"].erase(AR.key(hh))
	st["rot"][AR.key(hh)] = 3
	var owned0 := 0
	for k in st["varnish"]:
		owned0 += int(st["varnish"][k])
	main.enter_atlas(hh)
	await frames(3)
	lv = Game.level
	await _kill_boss(lv)
	check(lv.choose_heart("harvest") and lv.varnish_drop != "", "live varnish: Harvesting a Heart drops a Varnish", lv.varnish_drop)
	var owned1 := 0
	for k in st["varnish"]:
		owned1 += int(st["varnish"][k])
	check(owned1 == owned0 + 1, "live varnish: the Varnish is banked on the atlas")
	main.go_hub(true)
	await frames(3)
	# the Easel panel
	var ui = main.ui
	if ui != null:
		Game.ch.materials["glaze_flake"] = int(AR.pigment_info("glazed")["cost"]) + 150
		st["pigments"] = []
		st["easel"] = []
		ui.toggle("easel")
		var ep = ui.panels["easel"]
		check(ui.is_open("easel") and ep.info.text.find("Glaze Flake") >= 0, "Easel panel opens and shows materials", ep.info.text.substr(0, 120))
		ep._craft("glazed")
		check(st["pigments"].size() == 1 and int(Game.ch.materials["glaze_flake"]) == 150, "Easel panel crafts a Pigment")
		check(AR.slot_pigment(st, 0), "Easel: slot")
		ep.refresh()
		check(ep.easel_box.get_child_count() == 1, "Easel panel lists the slotted Pigment")
		if args.has("shot"):
			await _shot("easel")
		ui.toggle("atlas")
		var ap = ui.panels["atlas"]
		ap.select(Vector2i(2, 0))
		check(ap.detail.text.find("Pigments (1 slot") >= 0, "Atlas panel lists the run's Pigments", ap.detail.text.substr(0, 0))
		ui.close_all()
	st["easel"] = []
	st["pigments"] = []

# ------------------------------------------------------------------ Layer Wardens (Phase 2A)
func test_warden_rules() -> void:
	var wc := AR.ward_cfg()
	check(not wc.is_empty() and AR.warden_rings() == [1, 2, 3], "wardens: rings 1-3 each have a Warden", str(AR.warden_rings()))
	for r in AR.warden_rings():
		var w := AR.warden_cfg(r)
		var bd: Dictionary = Data.enemies[str(w["boss"])]
		var wd := AR.warden_def(bd, r)
		check(wd.get("warden", 0) == r and str(wd["name"]).find(str(w["title"])) >= 0, "warden %d: named %s" % [r, str(wd["name"])])
		check(wd["phases"].size() == bd["phases"].size() + 1, "warden %d: gains a final phase" % r)
		check(float(wd["life"]) > float(bd["life"]) * 2.0 and int(wd["damage"][1]) > int(bd["damage"][1]), "warden %d: more life and damage" % r)
		var ok := true
		for pid in w.get("add", {}):
			var used := false
			for ph in wd["phases"]:
				used = used or ph["patterns"].has(pid)
			ok = ok and wd["patterns"].has(pid) and used
		check(ok, "warden %d: every new pattern is used by a phase" % r)
		check(wd["patterns"].has(str(w["signature"])) and wd["phases"][0]["patterns"].has(str(w["signature"])), "warden %d: signature pattern from phase 1" % r)
		var types_ok := true
		for pid in wd["patterns"]:
			types_ok = types_ok and str(wd["patterns"][pid].get("type", "")) in ["cleave", "charge", "ring", "eruption", "summon", "burrow", "fan", "spiral", "teleport", "mortar", "vent", "ward"]
		check(types_ok, "warden %d: built only from existing pattern types" % r)
		var last: Dictionary = wd["phases"][wd["phases"].size() - 1]
		var prev: Dictionary = wd["phases"][wd["phases"].size() - 2]
		check(float(last["at"]) < float(prev["at"]), "warden %d: final phase starts below the previous one" % r)
		check(Data.enemies[str(w["boss"])]["phases"].size() == bd["phases"].size() and not Data.enemies[str(w["boss"])]["patterns"].has(str(w["signature"])), "warden %d: base boss data untouched" % r)
	# shards: seeded, pity, cap, Heart
	var st := _bare_state(777)
	var h := Vector2i(1, 0)
	st["clears"][AR.key(h)] = 1
	var a := AR.roll_shard(st.duplicate(true), h)
	var b := AR.roll_shard(st.duplicate(true), h)
	check(a == b, "shards: the roll is seeded")
	var got := 0
	var dry_max := 0
	var dry := 0
	for i in 60:
		st["clears"][AR.key(h)] = i + 1
		st["shards"] = {}
		var g := AR.roll_shard(st, h)
		got += g
		dry = 0 if g > 0 else dry + 1
		dry_max = maxi(dry_max, dry)
	check(dry_max <= int(wc["shard_pity"]), "shards: never more than %d dry clears in a row" % int(wc["shard_pity"]), str(dry_max))
	check(got >= 25 and got <= 45, "shards: about half of clears drop one", "%d/60" % got)
	var st2 := _bare_state(778)
	st2["clears"]["2,0"] = 1
	check(AR.roll_shard(st2, Vector2i(2, 0), 3, true) == 1, "shards: a Heart always drops one")
	AR.add_shards(st2, 2, 99)
	check(AR.shards(st2, 2) == int(wc["shard_cap"]) and AR.roll_shard(st2, Vector2i(2, 0)) == 0, "shards: capped at %d" % int(wc["shard_cap"]))
	check(AR.add_shards(st2, 5, 1) == 0, "shards: no Warden ring, no shard")
	# summoning
	var st3 := _bare_state(779)
	var hx := Vector2i(1, -1)
	check(AR.summon_refusal(st3, hx).find("Clear") >= 0, "summon: refused before the region is cleared")
	st3["clears"][AR.key(hx)] = 1
	check(AR.summon_refusal(st3, hx).find("Needs") >= 0 and not AR.summon(st3, hx), "summon: refused without enough shards")
	AR.add_shards(st3, 1, 3)
	check(AR.summon(st3, hx) and AR.warden_at(st3, hx) == 1 and AR.shards(st3, 1) == 3, "summon: marks the hex, spends nothing yet")
	var hy := Vector2i(0, 1)
	st3["clears"][AR.key(hy)] = 1
	check(AR.summon(st3, hy) and AR.warden_at(st3, hx) == 0 and AR.warden_at(st3, hy) == 1, "summon: moving the Warden to another cleared hex")
	var zd := AR.apply_warden(AR.apply_rot(AR.zone_def(779, hy), 3, 779, hy, st3), 1)
	check(zd["boss"] == "warden" and not zd.get("heart", false) and int(zd["warden"]) == 1, "apply_warden: Warden boss, no Heart")
	# victory + Ground Pigment pity
	var v1 := AR.warden_victory(st3, 1)
	check(v1["ground"] and v1["first"] and AR.ground_count(st3, 1) == 1 and AR.shards(st3, 1) == 0 and AR.summoned_hex(st3, 1) == "", "victory: first kill always drops the Ground Pigment and spends the shards")
	var dry2 := 0
	var dmax := 0
	var grounds := 0
	for i in 40:
		var v := AR.warden_victory(st3, 1)
		grounds += 1 if v["ground"] else 0
		dry2 = 0 if v["ground"] else dry2 + 1
		dmax = maxi(dmax, dry2)
	check(dmax <= int(wc["ground_pity"]), "ground: at most %d dry kills in a row" % int(wc["ground_pity"]), str(dmax))
	check(grounds >= 10 and grounds <= 25, "ground: about 1 in 3 after the first", "%d/40" % grounds)
	check(AR.ground_kinds(st3) == 1 and not AR.pinnacle_ready(st3), "ground: one layer is not enough for the pinnacle")
	st3["ground"] = {"1": 1, "2": 2, "3": 1}
	check(AR.ground_kinds(st3) == 3 and not AR.pinnacle_ready(st3), "ground: 3 layers still short of %d" % int(wc["pinnacle_need"]))
	# sanitize
	st3["shards"] = {"1": 2, "7": 4, "2": -3}
	st3["summons"] = {"1": AR.key(hy), "2": "1,0", "3": "9,9"}
	var san := AR.sanitize(st3)
	check(san["shards"] == {"1": 2} and san["summons"] == {"1": AR.key(hy)} and san["ground"].size() == 3, "sanitize: keeps valid warden state, drops bad rings and summons", str(san["shards"]) + str(san["summons"]))
	var old := AR.sanitize({"seed": 55, "revealed": [], "clears": {}})
	check(old["shards"].is_empty() and old["summons"].is_empty() and old["ground"].is_empty(), "sanitize: a 1E atlas loads with no warden state")

func test_live_wardens() -> void:
	var st: Dictionary = AR.ensure(Game.ch)
	_open_atlas_all(st)
	Game.atlas_force_mechanic = "none"
	st["easel"] = []
	st["varnish_slots"] = []
	for k in ["shards", "shard_dry", "summons", "ground", "ground_dry", "warden_kills"]:
		st[k] = {}
	Game.ch.progress["bosses_killed"].erase("atlas_warden_1")
	# a normal ring-1 clear rolls a shard (pity guarantees one by the third)
	var h := Vector2i(1, 0)
	var shards := 0
	for i in 3:
		main.enter_atlas(h)
		await frames(3)
		await _kill_boss(Game.level)
		shards += int(Game.level.shard_drop)
		main.go_hub(true)
		await frames(3)
	check(shards >= 1 and AR.shards(st, 1) == shards, "live wardens: ring-1 clears drop Varnish Shards", str(shards))
	# summon and fight
	AR.add_shards(st, 1, 3)
	var have := AR.shards(st, 1)
	check(AR.summon(st, h), "live wardens: summon at a cleared ring-1 hex")
	var pts0: int = Game.ch.bonus_passive_points
	main.enter_atlas(h)
	await frames(3)
	var lv = Game.level
	check(lv.warden == 1 and lv.level_name.find("Warden") >= 0 and lv.objective_text().find("Varnish Warden") >= 0, "live wardens: the run fights the Varnish Warden", lv.level_name)
	# a death before the Warden falls keeps the shards and the summon
	lv.apply_death_rot()
	check(AR.shards(st, 1) == have and AR.warden_at(st, h) == 1, "live wardens: dying costs no shards")
	await _kill_boss(lv)
	check(not killed.is_empty() and int(killed["def"].get("warden", 0)) == 1 and str(killed["name"]).find("Varnish Warden") >= 0, "live wardens: the boss spawns as the Warden", str(killed.get("name", "")))
	check(lv.warden_result.get("ground", false) and AR.ground_count(st, 1) == 1, "live wardens: first kill drops Ground Varnish")
	check(Game.ch.bonus_passive_points == pts0 + 1, "live wardens: first kill gives +1 passive point")
	check(AR.shards(st, 1) == have - AR.summon_cost() and AR.summoned_hex(st, 1) == "", "live wardens: victory spends the shards and ends the summon")
	check(_has_legendary(lv), "live wardens: the Warden drops a legendary")
	check(not lv.markers.has("rot_harvest") and lv.shard_drop == 0, "live wardens: no Heart choice and no shard roll on a Warden run")
	main.go_hub(true)
	await frames(3)
	# second kill: no second passive point
	AR.add_shards(st, 1, 3)
	AR.summon(st, h)
	pts0 = Game.ch.bonus_passive_points
	main.enter_atlas(h)
	await frames(3)
	await _kill_boss(Game.level)
	check(Game.ch.bonus_passive_points == pts0 and AR.warden_kills(st, 1) == 2, "live wardens: only the first kill gives a passive point")
	main.go_hub(true)
	await frames(3)
	# a Warden on a Rot 3 hex replaces the Heart
	var h2 := Vector2i(2, 0)
	st["restored"].erase(AR.key(h2))
	st["rot"][AR.key(h2)] = 3
	st["clears"][AR.key(h2)] = maxi(1, AR.clears(st, h2))
	AR.add_shards(st, 2, 3)
	AR.summon(st, h2)
	main.enter_atlas(h2)
	await frames(3)
	lv = Game.level
	check(lv.warden == 2 and lv.rot == 3 and not lv.def.get("heart", false), "live wardens: a Warden replaces the Heart in a Rot 3 region")
	await _kill_boss(lv)
	check(str(killed.get("name", "")).find("Craquelure Warden") >= 0 and AR.ground_count(st, 2) == 1, "live wardens: the Craquelure Warden drops Ground Craquelure", str(killed.get("name", "")))
	main.go_hub(true)
	await frames(3)
	# save round trip
	var saved = JSON.parse_string(JSON.stringify(Game.ch.atlas))
	var back := AR.sanitize(saved)
	check(back["ground"] == st["ground"] and back["warden_kills"] == st["warden_kills"] and back["shards"] == st["shards"], "live wardens: warden state survives a save round trip")
	# Atlas panel
	var ui = main.ui
	if ui != null:
		AR.add_shards(st, 1, 3)
		ui.toggle("atlas")
		var ap = ui.panels["atlas"]
		ap.select(h)
		check(ap.progress_label.text.find("Ground Pigments: 2 of 6") >= 0, "Atlas panel shows Ground Pigments", ap.progress_label.text.substr(0, 120))
		check(not ap.summon_btn.disabled and ap.detail.text.find("Layer Warden") >= 0, "Atlas panel offers the summon")
		ap._summon()
		check(AR.warden_at(st, h) == 1 and ap.detail.text.find("Warden summoned") >= 0 and ap.summon_btn.disabled, "Atlas panel summons the Warden")
		ap.select(Vector2i(3, 0))
		check(ap.summon_btn.disabled, "Atlas panel: no summon without shards / clears")
		if args.has("shot"):
			ap.select(h)
			await _shot("atlas_warden")
		ui.close_all()
	AR.unsummon(st, 1)
	AR.unsummon(st, 2)
	Game.atlas_force_mechanic = ""

# ------------------------------------------------------------------ Phase 2B
func _test_item(rarity: String = "rare", ilvl: int = 45, rolled: bool = false) -> Dictionary:
	var base := ""
	for b in Data.item_base_list:
		if b.get("category", "") == "chest" or b.has("armour"):
			base = b["id"]
			break
	var it: Dictionary = Loot.roll_item_of(base, rarity, ilvl) if rolled else Loot.make_item(base, rarity, ilvl)
	it["uid"] = 900000 + randi() % 99999
	return it

func test_fixative() -> void:
	var CR = preload("res://scripts/core/corruption_rules.gd")
	var f: Dictionary = Data.atlas_cfg.get("fixative", {})
	check(int(f.get("reduce", 0)) == 25 and int(f.get("max_uses", 0)) == 2 and int(f.get("flakes", 0)) > 0, "fixative: data is -25, max 2 uses, costs Flakes")
	check("fixative" in Loot.craft_ops() and CR.is_exempt("fixative") and not CR.rolls_for("fixative"), "fixative: a Blacksmith craft, exempt from the corruption roll")
	var it := _test_item()
	check(Loot.craft_check("fixative", it) == "This item has no crafting corruption to fix", "fixative: refused at 0%", Loot.craft_check("fixative", it))
	CR.set_level(it, 75)
	var cost: Dictionary = Loot.craft_cost("fixative", it)
	check(int(cost.get("glaze_flake", 0)) == int(f["flakes"]) and int(cost.get("gold", 0)) == int(f["gold_base"]) + int(f["gold_per_ilvl"]) * 45, "fixative: cost is Flakes + gold by item level", str(cost))
	var affs: Array = it["affixes"].duplicate(true)
	check(Loot.craft_check("fixative", it) == "", "fixative: allowed at 75%")
	Loot.craft_apply("fixative", it)
	check(CR.get_level(it) == 50 and int(it.get("fixative", 0)) == 1 and it["affixes"] == affs, "fixative: 75% -> 50%, one use counted, affixes untouched")
	check(Loot.craft_preview("fixative", it).find("50% -> 25%") >= 0, "fixative: preview shows the new level", Loot.craft_preview("fixative", it))
	Loot.craft_apply("fixative", it)
	check(CR.get_level(it) == 25 and int(it["fixative"]) == 2, "fixative: second use 50% -> 25%")
	check(Loot.craft_check("fixative", it).find("most this item can take") >= 0, "fixative: a third use is refused", Loot.craft_check("fixative", it))
	Loot.craft_apply("fixative", it)
	check(CR.get_level(it) == 25 and int(it["fixative"]) == 2, "fixative: a refused direct apply changes nothing")
	check(Loot.tooltip(it).find("Fixative applied: 2 of 2") >= 0, "fixative: tooltip shows the uses")
	var low := _test_item()
	CR.set_level(low, 10)
	AC.apply_fix(low)
	check(CR.get_level(low) == 0 and not low.has("corruption") and int(low["fixative"]) == 1, "fixative: never below 0 (key erased at 0)")
	var sealed := _test_item()
	CR.set_level(sealed, 100)
	check(Loot.craft_check("fixative", sealed) != "" and AC.apply_fix(sealed).is_empty() and CR.get_level(sealed) == 100, "fixative: refused at 100% (the seal holds)")
	var branded := _test_item()
	CR.set_level(branded, 75)
	branded["corruption_roll_version"] = 1
	check(AC.fix_refusal(branded).find("fully corrupted") >= 0, "fixative: refused on a Brand-corrupted item")
	# load normalisation
	var j = JSON.parse_string(JSON.stringify(it))
	var ch = CharacterData.new()
	var back = ch._fix_item(j)
	check(back != null and back["fixative"] is int and int(back["fixative"]) == 2 and Loot.craft_check("fixative", back) != "", "fixative: uses survive a save round trip as an int")
	# Blacksmith panel path: no corruption roll, Flakes paid through the normal cost
	var bp = load("res://scripts/ui/blacksmith_panel.gd").new()
	var it2 := _test_item()
	CR.set_level(it2, 50)
	var r: Dictionary = bp.apply_craft("fixative", it2, -1)
	check(not r.get("rolled", true) and CR.get_level(it2) == 25, "fixative: Blacksmith apply_craft lowers it without a corruption roll", str(r))
	bp.free()

func test_rot_touched_rules() -> void:
	var rc: Dictionary = Data.atlas_cfg.get("rot_touched", {})
	var pool: Array = rc.get("pool", [])
	check(pool.size() >= 5, "rot-touched: a small pool", str(pool.size()))
	var ok := true
	for e in pool:
		for side in ["bonus", "drawback"]:
			if not Data.stat_info.has(str(e.get(side, {}).get("stat", ""))):
				ok = false
		if e.get("tiers", []).size() != 2:
			ok = false
	check(ok, "rot-touched: every entry has a known bonus and drawback stat and 2 tiers")
	check(is_equal_approx(AC.chance(3), 0.0) and is_equal_approx(AC.chance(4), 0.10) and is_equal_approx(AC.chance(5), 0.25), "rot-touched: chance 0 / 10% / 25% at Rot 3 / 4 / 5")
	check(AC.tier_for(4) == 1 and AC.tier_for(5) == 2, "rot-touched: tier 1 at Rot 4, tier 2 at Rot 5")
	var rng := RandomNumberGenerator.new()
	for rot in [4, 5]:
		rng.seed = 77 + rot
		var n := 0
		var good := true
		var ids := {}
		for i in 4000:
			var it := {"base": "x", "name": "x"}
			if AC.roll(it, rot, rng):
				n += 1
				var rec: Dictionary = it["rot_implicit"]
				ids[rec["id"]] = true
				var e: Dictionary = AC.entry(rec["id"])
				var row: Array = e["tiers"][AC.tier_for(rot) - 1]
				var ms := AC.mods(it)
				if int(rec["tier"]) != AC.tier_for(rot) or ms.size() != 2 or ms[0]["value"] < row[0] or ms[0]["value"] > row[1] or int(ms[1]["value"]) != int(row[2]):
					good = false
		var rate := float(n) / 4000.0
		check(absf(rate - AC.chance(rot)) < 0.025, "rot-touched: Rot %d hit rate near %d%%" % [rot, int(AC.chance(rot) * 100)], "%.3f" % rate)
		check(good and ids.size() == pool.size(), "rot-touched: Rot %d records are in range and every entry appears" % rot, str(ids.keys()))
	var it0 := {"base": "x"}
	rng.seed = 1
	var st0 := rng.state
	check(not AC.roll(it0, 3, rng) and rng.state == st0 and not it0.has("rot_implicit"), "rot-touched: nothing rolled (or drawn) below Rot 4")
	# item mods, tooltip, normalisation, Brand corruption
	var it := _test_item()
	var e0: Dictionary = pool[0]
	it["rot_implicit"] = AC.make_record(e0, 2, rng)
	var found := 0
	for m in Loot.item_mods(it):
		for rm in it["rot_implicit"]["mods"]:
			if m.get("stat") == rm["stat"] and m.get("type") == rm["type"] and is_equal_approx(float(m.get("value", 0)), float(rm["value"])):
				found += 1
	check(found == 2, "rot-touched: both modifiers reach item_mods", str(found))
	var tt := Loot.tooltip(it)
	check(tt.find("Rot-touched: %s (T2)" % e0["name"]) >= 0, "rot-touched: tooltip names the implicit")
	check(not AC.roll(it, 5, rng) or false, "rot-touched: an item never gets a second one")
	check(LootFilter.describe(it)["rot"] == str(e0["id"]) and LootFilter.describe(_test_item())["rot"] == "", "rot-touched: the loot filter sees the implicit on a real item")
	var back = CharacterData.new()._fix_item(JSON.parse_string(JSON.stringify(it)))
	check(back != null and back["rot_implicit"]["tier"] is int and AC.mods(back).size() == 2 and int(AC.mods(back)[1]["value"]) == int(e0["tiers"][1][2]), "rot-touched: survives a save round trip")
	var bad := _test_item()
	bad["rot_implicit"] = "junk"
	back = CharacterData.new()._fix_item(JSON.parse_string(JSON.stringify(bad)))
	check(back != null and not back.has("rot_implicit"), "rot-touched: a malformed record is dropped on load")
	var unk := _test_item()
	unk["rot_implicit"] = {"id": "nope", "tier": 1, "mods": [{"stat": "damage", "type": "inc", "value": 99}]}
	check(AC.mods(unk).is_empty() and Loot.rot_implicit_text(unk) == "", "rot-touched: an unknown id stays inactive")
	# crafting keeps it (it is an implicit, not an affix)
	var cr_it := _test_item("rare", 45, true)
	cr_it["rot_implicit"] = AC.make_record(e0, 1, rng)
	var keep: Dictionary = cr_it["rot_implicit"].duplicate(true)
	if not cr_it["affixes"].is_empty():
		Loot.craft_apply("reroll", cr_it, 0)
		Loot.craft_apply("remove", cr_it, 0)
	Loot.craft_apply("upgrade", cr_it)
	check(cr_it["rot_implicit"] == keep, "rot-touched: reroll / remove / upgrade keep the implicit")

func test_live_rot_touched() -> void:
	var st: Dictionary = AR.ensure(Game.ch)
	_open_atlas_all(st)
	Game.atlas_force_mechanic = "none"
	for k in ["summons"]:
		st[k] = {}
	var h := Vector2i(2, -1)
	var key := AR.key(h)
	st["restored"].erase(key)
	var counts := {}
	var base: String = _test_item()["base"]
	for rot in [0, 5]:
		st["rot"][key] = rot
		main.enter_atlas(h)
		await frames(3)
		var lv = Game.level
		check(lv.rot == rot, "live rot-touched: entered the Rot %d region" % rot, str(lv.rot))
		var lr1 = Loot.rng.state
		var n := 0
		for i in 200:
			var item: Dictionary = Loot.make_item(base, "rare", 50)
			lv.spawn_drop({"kind": "item", "item": item}, lv.player.global_position)
			if item.has("rot_implicit"):
				n += 1
		counts[rot] = n
		check(Loot.rng.state == lr1, "live rot-touched: Rot %d rolls never touch the Loot stream" % rot)
		check(lv.rot_touched == n, "live rot-touched: the run counts its touched drops")
		main.go_hub(true)
		await frames(3)
	check(counts[0] == 0, "live rot-touched: no Rot-touched drops at Rot 0")
	check(counts[5] >= 30 and counts[5] <= 70, "live rot-touched: about 25% of drops at Rot 5", str(counts[5]))
	st["rot"][key] = 0
	Game.atlas_force_mechanic = ""

# ------------------------------------------------------------------ Phase 2C
func _contract(tpl: String, need: int) -> Dictionary:
	return {"tpl": tpl, "need": need, "have": 0, "rep": 10, "seals": 2, "done": false}

func test_guild_rules() -> void:
	var gc := GR.cfg()
	check(GR.ranks().size() == 4 and GR.unlock_rank("fixative") == 3 and GR.unlock_rank("vendor") == 2 and GR.unlock_rank("slot4") == 4, "guild: 4 ranks; vendor 2, Fixative 3, 4th slot 4")
	var stats_ok := true
	for t in GR.templates():
		stats_ok = stats_ok and GR.STATS.has(str(t.get("stat", ""))) and t.get("need", []).size() == 2
	check(stats_ok and GR.templates().size() >= 10, "guild: every contract template counts a known run stat", str(GR.templates().size()))
	# fresh atlas: only ring 1 revealed, no Rot visible -> only basic contracts
	var fresh := AR.new_state(4321)
	var g := GR.ensure(fresh)
	check(g["board"].size() == 3 and int(g["rep"]) == 0 and GR.rank(fresh) == 1, "guild: a new board has 3 contracts at rank 1")
	var basic := true
	for c in g["board"]:
		var t := GR.template(str(c["tpl"]))
		basic = basic and t.get("req", {}).is_empty()
	check(basic, "guild: a fresh atlas only offers contracts without requirements", str(g["board"]))
	var tpls := []
	for c in g["board"]:
		tpls.append(c["tpl"])
	var distinct := true
	for t in tpls:
		distinct = distinct and tpls.count(t) == 1
	check(distinct, "guild: the board never shows the same contract twice", str(tpls))
	var again := GR.ensure(AR.new_state(4321))
	check(again["board"] == g["board"], "guild: the board is seeded by the atlas seed")
	# eligibility on an opened atlas
	var st := _bare_state(999)
	st["rot"]["2,0"] = 3
	check(GR.eligible(st, GR.template("ring3")) and GR.eligible(st, GR.template("hearts")) and not GR.eligible(st, GR.template("warden")), "guild: ring/Rot contracts unlock with the atlas; Warden contracts need shards")
	AR.add_shards(st, 1, 1)
	check(GR.eligible(st, GR.template("warden")), "guild: a Ground Shard makes Warden contracts eligible")
	# credit
	var gg := GR.ensure(st)
	gg["board"] = [_contract("zones", 2), _contract("ring2", 1), _contract("hearts", 1)]
	var r1 := GR.credit(st, {"zones": 1, "ring": 1, "rot": 0})
	check(int(gg["board"][0]["have"]) == 1 and int(gg["board"][1]["have"]) == 0 and r1["completed"].is_empty(), "guild: a ring-1 clear advances 'zones' but not 'ring 2+'")
	var r2 := GR.credit(st, {"zones": 1, "ring": 2, "rot": 3, "hearts": 1})
	check(r2["completed"].size() == 3 and int(gg["rep"]) == 30 and int(gg["seals"]) == 6 and gg["board"][0]["done"], "guild: completed contracts pay reputation and Seals at once", str(r2))
	check(int(gg["zones"]) == 2 and GR.zones_to_refresh(st) == 3, "guild: the refresh counts completed zones")
	var r3 := GR.credit(st, {"zones": 0, "ring": 2, "rot": 3, "restore": 1})
	check(int(gg["zones"]) == 2 and r3["rep"] == 0, "guild: a Heart choice report is not a zone")
	for i in 3:
		GR.credit(st, {"zones": 1, "ring": 1, "rot": 0})
	var all_new := true
	for c in gg["board"]:
		all_new = all_new and not c["done"]
	check(all_new and int(gg["zones"]) == 0 and gg["board"].size() == 3, "guild: after 5 zones the done contracts are replaced")
	# reroll
	var before: Dictionary = gg["board"][0].duplicate()
	check(GR.reroll(st, 0) == "" and gg["board"][0] != before, "guild: a free reroll replaces a contract")
	check(GR.reroll(st, 1).find("No free reroll") >= 0, "guild: one free reroll per refresh")
	gg["rerolls"] = 0
	gg["board"][2]["done"] = true
	check(GR.reroll(st, 2).find("already complete") >= 0, "guild: a done contract cannot be rerolled")
	# ranks
	check(GR.rank_for(0) == 1 and GR.rank_for(int(GR.ranks()[1]["rep"])) == 2 and GR.rank_for(int(GR.ranks()[2]["rep"]) - 1) == 2 and GR.rank_for(99999) == 4, "guild: ranks by total reputation")
	gg["rep"] = int(GR.ranks()[3]["rep"])
	GR.fill_board(st)
	check(GR.slot_count(st) == 4 and gg["board"].size() == 4 and GR.offer_count(st) == 4, "guild: rank 4 adds a 4th contract and a 4th cache choice")
	# Fixative gate
	var ch = CharacterData.new()
	ch.setup_new("warrior", "GuildGate")
	check(GR.fixative_refusal(null) == "", "fixative gate: no character = allowed (pure item checks)")
	check(GR.fixative_refusal(ch).find("rank 3") >= 0, "fixative gate: refused without an Atlas")
	ch.atlas = AR.new_state(55)
	GR.ensure(ch.atlas)["rep"] = int(GR.ranks()[2]["rep"]) - 1
	check(GR.fixative_refusal(ch).find("rank 3") >= 0, "fixative gate: refused at rank 2")
	ch.atlas["guild"]["rep"] = int(GR.ranks()[2]["rep"])
	check(GR.fixative_refusal(ch) == "", "fixative gate: open at rank 3")
	# caches
	var cst := _bare_state(31337)
	var cg := GR.ensure(cst)
	var offers := GR.cache_offers(cst)
	check(offers.size() == 3 and offers == GR.cache_offers(cst) and offers[0] != offers[1] and offers[1] != offers[2] and offers[0] != offers[2], "caches: 3 distinct seeded offers", str(offers))
	var cch = CharacterData.new()
	cch.setup_new("ranger", "Cache")
	check(not GR.open_cache(cst, cch, str(offers[0]))["ok"], "caches: refused without 10 Seals")
	cg["seals"] = 25
	var item_kind := ""
	for o in offers:
		if int(GR.cache_info(str(o)).get("items", 0)) > 0:
			item_kind = str(o)
	if item_kind == "":
		item_kind = str(offers[0])
	var free0: int = cch.bag_free_count()
	var res := GR.open_cache(cst, cch, item_kind)
	var want := int(GR.cache_info(item_kind).get("items", 0))
	check(res["ok"] and int(cg["seals"]) == 15 and free0 - cch.bag_free_count() == want, "caches: opening one spends 10 Seals and gives its contents", "%s %s" % [item_kind, str(res.get("text", []))])
	var slots_ok := true
	for it in res.get("items", []):
		slots_ok = slots_ok and GR.cache_info(item_kind)["slots"].has(str(it.get("slot", ""))) and Data.rarity_index(str(it.get("rarity", ""))) >= Data.rarity_index("rare")
	check(slots_ok, "caches: items match the cache's slots and are rare or better")
	check(GR.cache_offers(cst) != offers or int(cg["caches"]) == 1, "caches: the offer re-rolls after each cache")
	check(not GR.open_cache(cst, cch, "not_a_cache")["ok"], "caches: unknown cache refused")
	var mat := GR.cache_info("crafting")
	cg["seals"] = 10
	var flakes0 := int(cch.materials.get("glaze_flake", 0))
	var tries := 0
	while not GR.cache_offers(cst).has("crafting") and tries < 20:
		cg["caches"] = int(cg["caches"]) + 1
		tries += 1
	check(GR.open_cache(cst, cch, "crafting")["ok"] and int(cch.materials.get("glaze_flake", 0)) == flakes0 + int(mat["materials"]["glaze_flake"]), "caches: the Restorer's Satchel gives Glaze Flakes")
	# vendor
	cch.gold = 5000
	cg["rep"] = 0
	check(GR.buy_refusal(cst, cch, "glazed").find("rank 2") >= 0, "vendor: closed at rank 1")
	cg["rep"] = int(GR.ranks()[1]["rep"])
	var pc0 := AR.pigment_count(cst)
	var b1 := GR.buy_pigment(cst, cch, "glazed")
	check(b1["ok"] and cch.gold == 5000 - GR.vendor_price("glazed") and AR.pigment_count(cst) == pc0 + 1, "vendor: rank 2 buys a Pigment for gold")
	GR.buy_pigment(cst, cch, "unfinished")
	check(GR.buy_refusal(cst, cch, "glazed").find("Sold out") >= 0, "vendor: 2 per board refresh")
	cg["bought"] = 0
	cch.gold = 10
	check(GR.buy_refusal(cst, cch, "glazed").find("gold") >= 0, "vendor: needs the gold")
	# save
	var saved = JSON.parse_string(JSON.stringify(cst))
	var back := AR.sanitize(saved)
	check(back.has("guild") and back["guild"]["board"] == cg["board"] and int(back["guild"]["rep"]) == int(cg["rep"]) and int(back["guild"]["seals"]) == int(cg["seals"]), "guild: state survives a save round trip")
	var junk := GR.sanitize({"rep": "x", "seals": 500, "board": [{"tpl": "nope"}, 5, {"tpl": "zones", "need": 3, "have": 9}]})
	check(int(junk["rep"]) == 0 and int(junk["seals"]) == int(gc.get("seal_cap", 99)) and junk["board"].size() == 1 and int(junk["board"][0]["have"]) == 3, "guild: bad saved data is cleaned", str(junk))
	check(not AR.sanitize({"seed": 5}).has("guild"), "guild: an older atlas loads without a Guild block")

## Monte Carlo of the rank pace (Dan, 2026-11-05: rank 3 after about 40-50 zones). Synthetic
## zone reports for a player working through rings 1-3 (no rerolls used).
func test_guild_pace() -> void:
	var results := []
	var r2s := []
	var seals := []
	for sd in 20:
		var st := _bare_state(9000 + sd)
		st["rot"] = {"2,0": 3, "-2,1": 2, "0,3": 4}
		AR.add_shards(st, 1, 1)
		var rng := RandomNumberGenerator.new()
		rng.seed = 77 + sd
		var zones := 0
		var r2 := -1
		while GR.rank(st) < 3 and zones < 200:
			zones += 1
			var ring: int = 1 if zones <= 8 else (2 if zones <= 20 else rng.randi_range(2, 3))
			var rotv: int = 0 if ring == 1 else [0, 0, 1, 2, 3, 4][rng.randi_range(0, 5)]
			var heart: bool = rotv >= 3
			var mech := rng.randf() < 0.45
			var glaze := mech and rng.randf() < 0.5
			var rep := {"zones": 1, "ring": ring, "rot": rotv, "hearts": 1 if heart else 0,
				"peels": rng.randi_range(4, 8) if glaze else 0, "painted": rng.randi_range(6, 10) if mech and not glaze else 0,
				"elites": rng.randi_range(5, 11), "pigment_zones": 1 if rng.randf() < 0.35 else 0,
				"wardens": 1 if zones % 10 == 0 else 0}
			# Phase 2D fields: kills, boss/zone times, Pigments, Wager (20% of zones, ~55% won, 1 in 3 at 3x), Vaults (20%)
			var vn: int = rng.randi_range(1, 2) if rng.randf() < 0.2 else 0
			var vt := 0
			var vr := 0
			for vi in vn:
				var tr := rng.randf()
				vt += 1 if tr < 0.35 else 0
				vr += 1 if tr >= 0.8 else 0
			var won: bool = rng.randf() < 0.2 and rng.randf() < 0.55
			rep.merge({"kills": rng.randi_range(140, 220), "bosses": 1, "time": rng.randf_range(150.0, 330.0), "boss_time": rng.randf_range(8.0, 40.0),
				"pigments": 2 if ring == 3 and rng.randf() < 0.3 else (1 if int(rep["pigment_zones"]) > 0 else 0),
				"wagers_won": 1 if won else 0, "wager_3x": 1 if won and rng.randf() < 0.33 else 0,
				"vaults": vn, "trap_vaults": vt, "riddle_vaults": vr})
			GR.credit(st, rep)
			if heart:
				var hr := {"zones": 0, "ring": ring, "rot": rotv}
				hr["restore" if rng.randf() < 0.5 else "harvest"] = 1
				GR.credit(st, hr)
			if r2 < 0 and GR.rank(st) >= 2:
				r2 = zones
		results.append(zones)
		r2s.append(r2)
		seals.append(int(st["guild"]["seals"]))
	results.sort()
	r2s.sort()
	var med: int = results[results.size() / 2]
	seals.sort()
	note("guild pace: zones to rank 2 median %d, rank 3 median %d (range %d-%d); Seals earned by then median %d" % [r2s[r2s.size() / 2], med, results[0], results[results.size() - 1], seals[seals.size() / 2]])
	check(med >= 38 and med <= 52, "guild pace: rank 3 (Fixative) after about 40-50 zones", str(results))
	check(results[0] >= 30, "guild pace: even a lucky streak needs 30+ zones", str(results[0]))

func test_live_guild() -> void:
	var st: Dictionary = AR.ensure(Game.ch)
	_open_atlas_all(st)
	Game.atlas_force_mechanic = "none"
	st["easel"] = []
	st["varnish_slots"] = []
	st["summons"] = {}
	var g := GR.ensure(st)
	g["rep"] = 0
	g["zones"] = 0
	g["board"] = [_contract("zones", 1), _contract("ring2", 1), _contract("elites", 999)]
	main.go_hub(false)
	await frames(3)
	var has_npc := false
	for it in Game.level.interactables:
		has_npc = has_npc or it["kind"] == "guild"
	check(has_npc, "live guild: Restorer Ottilie stands in the Sanctuary once the Atlas is open")
	main.enter_atlas(Vector2i(1, 0))
	await frames(3)
	var lv = Game.level
	await _kill_boss(lv)
	check(int(lv.guild_report.get("zones", 0)) == 1 and int(lv.guild_report["ring"]) == 1, "live guild: the zone clear builds a run report", str(lv.guild_report))
	check(g["board"][0]["done"] and not g["board"][1]["done"] and int(g["rep"]) == 10, "live guild: completing the zone completes the 'zones' contract only", str(g["board"]))
	check(int(g["board"][2]["have"]) == int(lv.elite_kills), "live guild: elite kills before the boss count", "%d %d" % [int(g["board"][2]["have"]), lv.elite_kills])
	main.go_hub(true)
	await frames(3)
	# a death run credits nothing
	main.enter_atlas(Vector2i(2, -1))
	await frames(3)
	var rep0 := int(g["rep"])
	var z0 := int(g["zones"])
	main.go_hub(false)
	await frames(3)
	check(int(g["rep"]) == rep0 and int(g["zones"]) == z0 and int(g["board"][1]["have"]) == 0, "live guild: leaving a zone unfinished credits nothing")
	# Heart choice: Restore credits a restore contract
	var h2 := Vector2i(2, 0)
	st["restored"].erase(AR.key(h2))
	st["rot"][AR.key(h2)] = 3
	g["board"][1] = _contract("restore", 1)
	main.enter_atlas(h2)
	await frames(3)
	lv = Game.level
	await _kill_boss(lv)
	check(int(g["board"][1]["have"]) == 0, "live guild: the Heart choice is not credited before it is made")
	lv.choose_heart("restore")
	check(g["board"][1]["done"], "live guild: Restore completes a 'Restore a region' contract")
	main.go_hub(true)
	await frames(3)
	# Fixative gate at the Blacksmith with the live character
	var CR = preload("res://scripts/core/corruption_rules.gd")
	var it := _test_item("rare", 45)
	CR.set_level(it, 75)
	g["rep"] = 0
	check(Loot.craft_check("fixative", it).find("rank 3") >= 0, "live guild: Fixative is refused below Guild rank 3", Loot.craft_check("fixative", it))
	g["rep"] = int(GR.ranks()[2]["rep"])
	check(Loot.craft_check("fixative", it) == "", "live guild: Fixative opens at rank 3")
	# panel
	var ui = main.ui
	if ui != null:
		g["seals"] = 12
		ui.open_station("guild")
		var gp = ui.panels["guild"]
		check(ui.is_open("guild") and gp.info.text.find("Rank 3") >= 0 and gp.board_box.get_child_count() == g["board"].size(), "Guild panel shows the rank and the board", gp.info.text.substr(0, 100))
		check(gp.cache_box.get_child_count() == 1 + GR.offer_count(st) and gp.vendor_box.get_child_count() == 1 + GR.vendor_list().size(), "Guild panel lists the caches and the vendor")
		if args.has("shot"):
			await _shot("guild_panel")
		ui.close_all()
	g["seals"] = 0
	Game.atlas_force_mechanic = ""


# ------------------------------------------------------------------ Phase 2D: Wager + Vaults
func test_wager_vault_rules() -> void:
	check(AR.mechanic_info("wager").get("minor", false) and AR.mechanic_info("vault").get("minor", false), "2D: the Wager and Vaults are minor mechanics")
	# the main natural roll never gives a minor mechanic; the minor roll is ~20% each, deterministic
	var minor_main := false
	var nw := 0
	var nv := 0
	var tot := 0
	var stable := true
	for sd in [1, 7, 99, 123]:
		for h in AR.within(Vector2i.ZERO, 3):
			if AR.ring_of(h) == 0:
				continue
			for n in 4:
				var m := AR.natural_mechanic(sd, h, n)
				minor_main = minor_main or m == "wager" or m == "vault"
				var mm := AR.minor_mechanics(sd, h, n)
				stable = stable and mm == AR.minor_mechanics(sd, h, n)
				tot += 1
				nw += 1 if mm.has("wager") else 0
				nv += 1 if mm.has("vault") else 0
	check(not minor_main, "2D: the main natural roll is still Glazed / Unfinished only")
	check(stable and AR.minor_mechanics(1, Vector2i.ZERO, 0).is_empty(), "2D: minor mechanic rolls are deterministic and never in the hub")
	check(float(nw) / tot > 0.14 and float(nw) / tot < 0.26 and float(nv) / tot > 0.14 and float(nv) / tot < 0.26, "2D: each minor mechanic comes up in about 20% of runs", "wager %d vault %d of %d" % [nw, nv, tot])
	var nb := 0
	for sd in [1, 7, 99, 123]:
		for h in AR.within(Vector2i.ZERO, 3):
			if AR.ring_of(h) > 0 and AR.minor_mechanics(sd, h, 0, 2.0).size() > AR.minor_mechanics(sd, h, 0).size():
				nb += 1
	check(nb > 0, "2D: the Blooming Varnish multiplier also raises minor mechanics")
	var st := _bare_state(4040)
	var found := false
	for h in AR.within(Vector2i.ZERO, 3):
		if AR.ring_of(h) > 0 and not AR.minor_mechanics(4040, h, 0).is_empty():
			found = AR.run_mechanics(st, h).has(AR.minor_mechanics(4040, h, 0)[0])
			break
	check(found, "2D: run_mechanics includes the hex's minor mechanics")
	# bets
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var o1 := WV.offers(rng, [], 3)
	rng.seed = 5
	var o2 := WV.offers(rng, [], 3)
	var distinct := true
	for i in o1.size():
		distinct = distinct and o1.find(o1[i]) == i
	check(o1.size() == 3 and o1 == o2 and distinct, "2D wager: 3 distinct seeded offers", str(o1))
	var bad := false
	for sd in 200:
		rng.seed = sd
		for id in WV.offers(rng, [], 0):
			bad = bad or id in ["flaking", "colourist", "archaeology", "unscathed"]
	check(not bad, "2D wager: mechanic bets need their mechanic, 'Unscathed' needs a living elite")
	var seen := {}
	for sd in 200:
		rng.seed = sd
		for id in WV.offers(rng, ["glazed", "unfinished", "vault"], 4):
			seen[id] = true
	check(seen.size() == WV.bets().size(), "2D wager: every bet can be offered", str(seen.keys()))
	check(WV.stake(45, 1) == 900 and WV.stake(45, 3) == 2700, "2D wager: stake = 20 gold x level x multiplier")
	var p1 := WV.payout("boss_rush", 45, 1, 0)
	var p3 := WV.payout("boss_rush", 45, 3, 2)
	var br_odds := float(WV.bet_info("boss_rush")["odds"])
	check(int(p1["gold"]) == int(round(900 * (1.0 + br_odds))) and not p1["rare"] and int(p1["materials"]) == 2, "2D wager: a 1x win pays the stake x (1 + odds) and 2 materials", str(p1))
	check(int(p3["gold"]) == int(round(2700 * (1.0 + br_odds) * 1.2)) and p3["rare"] and int(p3["flakes"]) == 24 and int(p3["dust"]) == 6, "2D wager: 3x pays more materials, a rare, and Rot adds 10% gold per level", str(p3))
	check(WV.stake_refusal(899, 45, 1) != "" and WV.stake_refusal(900, 45, 1) == "", "2D wager: the stake must be affordable")
	var brb := WV.bet_info("boss_rush")
	var br_t := int(brb["base_time"]) + 3 * int(brb["per_chamber"])
	check(int(WV.limits("boss_rush", 3)["time"]) == br_t and WV.text("boss_rush", WV.limits("boss_rush", 3)) == "Slay the zone boss within %d seconds" % br_t, "2D wager: boss rush time = base + per chamber x chambers", WV.text("boss_rush", WV.limits("boss_rush", 3)))
	var fz := WV.bet_info("frenzy")
	check(WV.text("frenzy", WV.limits("frenzy")) == "Slay %d monsters within %d seconds" % [int(fz["count"]), int(fz["time"])] and WV.text("iron_will", WV.limits("iron_will")).find("%d%%" % int(WV.bet_info("iron_will")["life_pct"])) >= 0, "2D wager: bet texts fill their numbers")
	# Phase 2E: Unscathed has a hit allowance; Frenzy needs monsters ahead of the Collector
	check(WV.text("unscathed", WV.limits("unscathed")).find(str(int(WV.bet_info("unscathed").get("max_hits", 0)))) >= 0, "2E wager: Unscathed shows its hit allowance", WV.text("unscathed", WV.limits("unscathed")))
	var fz_min := int(fz.get("min_monsters", 0))
	check(fz_min > 0 and not WV.bet_ok(fz, [], 1, fz_min - 1) and WV.bet_ok(fz, [], 1, fz_min) and WV.bet_ok(fz, [], 1, -1), "2E wager: Frenzy is offered only with %d+ monsters ahead" % fz_min)
	var few_ok := true
	for sd in 100:
		rng.seed = sd
		few_ok = few_ok and not WV.offers(rng, [], 2, -1, 0).has("frenzy")
	check(few_ok, "2E wager: no Frenzy offer with no monsters ahead")
	check(WV.ends_at_boss("boss_rush") and WV.ends_at_boss("abstinence") and not WV.ends_at_boss("frenzy") and not WV.ends_at_boss("unscathed"), "2D wager: which bets settle at the boss")
	# vaults
	check(WV.vault_count(1, 0) == 1 and WV.vault_count(3, 0) == 2 and WV.vault_count(2, 3) == 2 and WV.vault_count(3, 5) == 2, "2D vaults: 1 per zone, 2 in ring 3 or at Rot 3+")
	var kinds := {}
	for sd in 600:
		rng.seed = sd
		var k := WV.roll_type(rng)
		kinds[k] = int(kinds.get(k, 0)) + 1
	check(int(kinds.get("treasure", 0)) > int(kinds.get("trap", 0)) and int(kinds.get("trap", 0)) > int(kinds.get("riddle", 0)) and int(kinds.get("riddle", 0)) > 60, "2D vaults: Treasure 45 / Trap 35 / Riddle 20", str(kinds))
	rng.seed = 3
	var ord := WV.riddle_order(rng)
	var sorted_o := ord.duplicate()
	sorted_o.sort()
	check(ord.size() == 3 and sorted_o == [0, 1, 2], "2D vaults: a riddle order is a permutation of the 3 sigils", str(ord))
	var c0 := WV.cache(45, 0, "treasure")
	var c4 := WV.cache(45, 4, "riddle")
	check(int(c0["rares"]) == 2 and int(c4["rares"]) == 5 and int(c0["gold"]) == 675, "2D vaults: cache 2 rares (+1 per 2 Rot, +1 for a riddle), 15 gold x level", "%s %s" % [str(c0), str(c4)])
	check(is_equal_approx(WV.shard_chance(0), 0.08) and is_equal_approx(WV.shard_chance(5), 0.18), "2D vaults: Ground Shard chance 8% + 2% per Rot")

func test_contracts_2d() -> void:
	for id in ["wager_win", "wager_3x", "vaults", "vault_trap", "vault_riddle", "kills", "rot_elites", "bosses", "boss_fast", "streak", "fast_zone", "two_pigments", "rot4"]:
		check(not GR.template(id).is_empty(), "2D contracts: template %s exists" % id)
	var c := _contract("fast_zone", 2)
	check(GR.progress_of(c, {"zones": 1, "time": 200.0}) == 1 and GR.progress_of(c, {"zones": 1, "time": 260.0}) == 0 and GR.progress_of(c, {"zones": 1}) == 0, "2D contracts: 'under 4 minutes' needs time <= 240 s")
	c = _contract("boss_fast", 2)
	check(GR.progress_of(c, {"bosses": 1, "boss_time": 15.0}) == 1 and GR.progress_of(c, {"bosses": 1, "boss_time": 25.0}) == 0, "2D contracts: fast boss kill needs <= 20 s")
	c = _contract("two_pigments", 1)
	check(GR.progress_of(c, {"zones": 1, "pigments": 2}) == 1 and GR.progress_of(c, {"zones": 1, "pigments": 1}) == 0, "2D contracts: 2 Pigments slotted")
	c = _contract("rot_elites", 10)
	check(GR.progress_of(c, {"elites": 6, "rot": 2}) == 6 and GR.progress_of(c, {"elites": 6, "rot": 1}) == 0, "2D contracts: Rot 2+ elites")
	check(GR.progress_of(_contract("kills", 300), {"kills": 180}) == 180 and GR.progress_of(_contract("wager_3x", 1), {"wager_3x": 1, "wagers_won": 1}) == 1, "2D contracts: kills and wager stats count")
	# streak: a death resets the progress, not the other contracts
	var st := _bare_state(5150)
	var g := GR.ensure(st)
	g["board"] = [_contract("streak", 3), _contract("zones", 5), _contract("streak", 3)]
	g["board"][2]["done"] = true
	GR.credit(st, {"zones": 1, "ring": 1, "rot": 0})
	GR.credit(st, {"zones": 1, "ring": 1, "rot": 0})
	check(int(g["board"][0]["have"]) == 2, "2D contracts: zones in a row add up")
	check(GR.on_death(st) == 1 and int(g["board"][0]["have"]) == 0 and int(g["board"][1]["have"]) == 2 and g["board"][2]["done"], "2D contracts: a death resets the streak only (done ones stay done)")
	check(GR.label({"tpl": "wager_win", "need": 1}) == "Win 1 Collector's Wager" and GR.label({"tpl": "bosses", "need": 1}) == "Defeat 1 zone boss" and GR.label({"tpl": "vault_trap", "need": 1}) == "Clear 1 Trap Vault", "2D contracts: singular labels", GR.label({"tpl": "wager_win", "need": 1}))
	# requirements: a fresh atlas offers none of the gated 2D contracts
	var fresh := AR.new_state(77)
	var gated := false
	for t in GR.templates():
		if str(t["id"]) in ["wager_3x", "vault_trap", "vault_riddle", "two_pigments", "rot4", "rot_elites"]:
			gated = gated or GR.eligible(fresh, t)
	check(not gated, "2D contracts: gated templates need clears / ring 3 / Rot")

func _wager_run(h: Vector2i, seed_v: int, bet: String):
	Game.atlas_force_mechanic = "wager"
	main.enter_atlas(h, seed_v)
	await frames(3)
	var lv = Game.level
	if not lv.wager["offers"].has(bet):
		lv.wager["offers"][0] = bet
		lv.wager["lim"][bet] = WV.limits(bet, lv._boss_chamber_links(lv.collector_pos))
	return lv

func test_live_wager() -> void:
	var st: Dictionary = AR.ensure(Game.ch)
	_open_atlas_all(st)
	st["easel"] = []
	st["varnish_slots"] = []
	st["summons"] = {}
	var h := Vector2i(2, 0)
	st["rot"].erase(AR.key(h))
	st["restored"].erase(AR.key(h))
	# same seed with / without the Collector: same layout, packs and main stream
	Game.atlas_force_mechanic = "none"
	seed(4242)   # _populate shuffles spawns with the global RNG
	main.enter_atlas(h, 6262)
	var grid0: int = hash(Game.level.layout["grid"])
	var en0: int = Game.level.total_enemies
	var rs0: int = Game.level.rng.state   # right after setup, before any frame runs
	var dbg0 := "%s ml%d mods%s el%.2f den%.2f" % [Game.level.level_name, Game.level.monster_level, str(Game.level.mods.map(func(m): return m.get("id", ""))), Game.level.elite_mult, Game.level.density]
	await frames(3)
	main.go_hub(false)
	await frames(3)
	Game.atlas_force_mechanic = "wager"
	seed(4242)
	main.enter_atlas(h, 6262)
	var rs1: int = Game.level.rng.state
	var en1: int = Game.level.total_enemies
	var dbg1 := "%s ml%d mods%s el%.2f den%.2f" % [Game.level.level_name, Game.level.monster_level, str(Game.level.mods.map(func(m): return m.get("id", ""))), Game.level.elite_mult, Game.level.density]
	var gh1: int = hash(Game.level.layout["grid"])
	await frames(3)
	main.go_hub(false)
	await frames(3)
	var lv = await _wager_run(h, 6262, "frenzy")
	check(lv.has_mech("wager") and lv.markers.has("collector") and lv.level_name.find("Collector") >= 0, "live wager: the Collector stands in the zone", lv.level_name)
	check(gh1 == grid0 and rs1 == rs0 and en1 == en0, "live wager: same layout, packs and main RNG as without it", "enemies %d/%d rng %d/%d grid %s | %s | %s" % [en1, en0, rs1, rs0, str(gh1 == grid0), dbg0, dbg1])
	check(lv.wager["state"] == "offer" and lv.wager["offers"].size() == 3, "live wager: 3 bets on offer", str(lv.wager["offers"]))
	check(lv.objective_text().find("Collector's Wager") >= 0, "live wager: the objective panel shows the Collector")
	var ch = Game.ch
	ch.gold = 10
	check(lv.accept_wager("frenzy", 1).find("gold") >= 0 and lv.wager["state"] == "offer", "live wager: no gold, no bet")
	ch.gold = 100000
	var g0 := int(ch.gold)
	check(lv.accept_wager("frenzy", 2) == "" and int(ch.gold) == g0 - WV.stake(lv.monster_level, 2) and lv.wager["state"] == "active", "live wager: accepting takes the stake")
	check(lv.accept_wager("frenzy", 1) != "", "live wager: one bet per zone")
	var need := int(lv.wager["lim"]["frenzy"]["count"])
	var g1 := int(ch.gold)
	for i in need:
		_fresh_enemy(lv, []).die(lv.player)
	await frames(2)
	check(lv.wager["state"] == "won" and int(lv.wv_stats["wagers_won"]) == 1 and int(ch.gold) == g1 + int(WV.payout("frenzy", lv.monster_level, 2, 0)["gold"]), "live wager: Frenzy won after %d kills, gold paid" % need, str(lv.wager.get("state")))
	check(not lv.markers.has("collector"), "live wager: the Collector leaves after the bet")
	main.go_hub(false)
	await frames(3)
	# Unscathed: a hit loses the stake
	lv = await _wager_run(h, 6263, "unscathed")
	g0 = int(ch.gold)
	lv.accept_wager("unscathed", 1)
	var allow := int(WV.limits("unscathed")["hits"])   # Phase 2E: a small hit allowance
	for i in allow:
		Events.player_damaged.emit(5.0)
	check(lv.wager["state"] == "active", "live wager: Unscathed allows %d hits" % allow, str(lv.wager.get("state")))
	Events.player_damaged.emit(5.0)
	check(lv.wager["state"] == "lost" and int(ch.gold) == g0 - WV.stake(lv.monster_level, 1) and int(lv.wv_stats["wagers_lost"]) == 1, "live wager: Unscathed is lost on hit %d, the stake is gone" % (allow + 1))
	main.go_hub(false)
	await frames(3)
	# Phase 2E: a bet that can no longer be won is refused (no sealed vault left)
	lv = await _wager_run(h, 6265, "abstinence")
	check(lv.wager_refusal("archaeology") != "" and lv.accept_wager("archaeology", 1) != "" and lv.wager["state"] == "offer", "2E wager: Archaeology is refused with no sealed vault left", lv.wager_refusal("archaeology"))
	check(lv.wager_refusal("abstinence") == "", "2E wager: other bets are not refused")
	main.go_hub(false)
	await frames(3)
	# Phase 2E: a timed count bet (Colourist) is lost when its time runs out
	lv = await _wager_run(h, 6266, "colourist")
	lv.accept_wager("colourist", 1)
	var col_t := float(WV.limits("colourist")["time"])
	lv._tick_wager(col_t - 1.0)
	var col_mid: String = str(lv.wager.get("state"))
	lv._tick_wager(2.0)
	check(col_t > 0.0 and col_mid == "active" and lv.wager["state"] == "lost" and str(lv.wager.get("why", "")) == "out of time", "2E wager: Colourist is lost after %d s" % int(col_t), "%s / %s" % [col_mid, str(lv.wager.get("state"))])
	main.go_hub(false)
	await frames(3)
	# Economy of Means: a third skill loses
	lv = await _wager_run(h, 6264, "few_skills")
	lv.accept_wager("few_skills", 1)
	var fs_max := int(WV.limits("few_skills")["skills"])
	for i in fs_max:
		Events.player_skill_used.emit("s%d" % i)
		Events.player_skill_used.emit("s0")
	check(lv.wager["state"] == "active", "live wager: %d different skill(s) allowed" % fs_max)
	Events.player_skill_used.emit("extra")
	check(lv.wager["state"] == "lost", "live wager: one more different skill loses Economy of Means")
	main.go_hub(false)
	await frames(3)
	# Against the Clock at 3x: the boss dies in time -> won, credited to a 3x contract
	var g := GR.ensure(st)
	g["board"] = [_contract("wager_3x", 1), _contract("wager_win", 2), _contract("zones", 99)]
	g["zones"] = 0   # no board refresh during the check
	lv = await _wager_run(h, 6265, "boss_rush")
	lv.accept_wager("boss_rush", 3)
	await _kill_boss(lv)
	check(lv.wager["state"] == "won" and int(lv.wv_stats["wager_3x"]) == 1, "live wager: Against the Clock won at 3x when the boss dies in time", str(lv.wager.get("why")))
	check(int(lv.guild_report.get("wagers_won", 0)) == 1 and int(lv.guild_report.get("wager_3x", 0)) == 1 and g["board"][0]["done"] and int(g["board"][1]["have"]) == 1, "live wager: wins are credited to the Commission Board", str(lv.guild_report))
	main.go_hub(true)
	await frames(3)
	# a count bet still running when the boss dies is lost; so is any bet on death
	lv = await _wager_run(h, 6266, "frenzy")
	lv.accept_wager("frenzy", 1)
	await _kill_boss(lv)
	check(lv.wager["state"] == "lost" and int(lv.guild_report.get("wagers_won", 0)) == 0, "live wager: Frenzy is lost if the boss dies first")
	main.go_hub(true)
	await frames(3)
	lv = await _wager_run(h, 6267, "abstinence")
	lv.accept_wager("abstinence", 1)
	lv.player.flasks_used += 1
	await frames(2)
	check(lv.wager["state"] == "lost", "live wager: Abstinence is lost on a flask")
	main.go_hub(false)
	await frames(3)
	lv = await _wager_run(h, 6268, "iron_will")
	lv.accept_wager("iron_will", 1)
	lv.apply_death_rot()
	check(lv.wager["state"] == "lost", "live wager: a death loses the bet")
	# panel
	var ui = main.ui
	if ui != null:
		main.go_hub(false)
		await frames(3)
		lv = await _wager_run(h, 6269, "frenzy")
		ui.open("wager")
		var wp = ui.panels["wager"]
		check(ui.is_open("wager") and wp.box.get_child_count() == 3 and wp.info.text.find("Gold") >= 0, "Wager panel lists the 3 bets with stakes", wp.info.text.substr(0, 80))
		if args.has("shot"):
			await _shot("wager_panel")
		ui.close_all()
	main.go_hub(false)
	await frames(3)

func test_live_vaults() -> void:
	var st: Dictionary = AR.ensure(Game.ch)
	_open_atlas_all(st)
	st["easel"] = []
	st["summons"] = {}
	var h := Vector2i(3, 0)
	st["restored"].erase(AR.key(h))
	st["rot"][AR.key(h)] = 0
	Game.atlas_force_mechanic = "vault"
	main.enter_atlas(h, 7171)
	await frames(3)
	var lv = Game.level
	var sites0 := []
	for v in lv.vaults:
		sites0.append(v["f"])
	check(lv.has_mech("vault") and lv.vaults.size() == 2, "live vaults: ring 3 zones hide 2 vaults", "%d" % lv.vaults.size())
	if lv.vaults.is_empty():
		main.go_hub(false)
		await frames(3)
		return
	var v: Dictionary = lv.vaults[0]
	var sealed := true
	for c in v["mouth"]:
		sealed = sealed and lv.cell(c.x, c.y) == 0
	var pocket := true
	for c in v["cells"]:
		pocket = pocket and lv.cell(c.x, c.y) == 1
	check(sealed and pocket and v["seal"] != null, "live vaults: a floor pocket behind a sealed mouth")
	check(v["wall"] != null and is_instance_valid(v["wall"]) and lv.enemies.has(v["wall"]) and v["wall"].def.get("object", false), "live vaults: the shimmering wall is a damageable object")
	var mons: int = lv.enemies.filter(func(e): return not e.def.get("object", false)).size()
	check(lv.objective_text().find("Monsters remaining: %d" % mons) >= 0 and lv.objective_text().find("Pentimento Vaults: 0 / 2") >= 0, "live vaults: walls are not monsters; the panel counts vaults")
	if args.has("shot"):
		lv.player.global_position = lv.cell_center(v["f"]) - Vector2(v["dir"]) * lv.T * 3
		lv.update_sleep()
		await frames(40)
		await _shot("vault_closed")
	# the wall takes damage like a monster and never moves
	var w = v["wall"]
	w.process_mode = Node.PROCESS_MODE_INHERIT
	var p0: Vector2 = w.global_position
	var dealt: float = w.receive_hit({"physical": w.max_life * 0.3}, {"flags": {}}, lv.player, false)
	await frames(10)
	check(dealt > 0.0 and w.life < w.max_life and w.global_position.distance_to(p0) < 0.5, "live vaults: the wall takes hits and stays put", "dealt %.1f" % dealt)
	# Treasure
	v["type"] = "treasure"
	var k0: int = lv.kills
	var xp0: int = Game.ch.xp
	var d0 := _drop_count(lv)
	w.die(lv.player)
	await frames(3)
	var mouth_open := true
	for c in v["mouth"]:
		mouth_open = mouth_open and lv.cell(c.x, c.y) == 1
	check(v["open"] and v["done"] and mouth_open and int(lv.wv_stats["vaults"]) == 1 and int(lv.wv_stats["treasure_vaults"]) == 1, "live vaults: breaking the wall opens a Treasure vault")
	check(lv.kills == k0 and Game.ch.xp == xp0, "live vaults: the wall gives no kill or XP")
	check(_drop_count(lv) >= d0 + 4, "live vaults: the Treasure cache drops", "%d -> %d" % [d0, _drop_count(lv)])
	# Trap
	var v2: Dictionary = lv.vaults[1]
	v2["type"] = "trap"
	lv.open_vault(v2)
	await frames(2)
	var trap: Array = v2["trap"].duplicate()
	var aggro := true
	for a in trap:
		aggro = aggro and a.aggro and a.loot_mult >= float(a.def.get("loot_mult", 1.0)) * 2.0 - 0.001
	check(trap.size() >= 4 and aggro and not v2["done"], "live vaults: a Trap vault wakes an ambush with double loot", "%d" % trap.size())
	for a in trap:
		if is_instance_valid(a) and a.alive:
			a.die(lv.player)
	await frames(2)
	check(v2["done"] and int(lv.wv_stats["trap_vaults"]) == 1, "live vaults: clearing the ambush pays the cache")
	# Riddle (re-use the first vault's record on a fresh run with the same seed: deterministic sites)
	main.go_hub(false)
	await frames(3)
	main.enter_atlas(h, 7171)
	await frames(3)
	lv = Game.level
	var sites1 := []
	for vv in lv.vaults:
		sites1.append(vv["f"])
	check(sites1 == sites0, "live vaults: vault sites are seeded by the run", "%s vs %s" % [str(sites1), str(sites0)])
	var v3: Dictionary = lv.vaults[0]
	v3["type"] = "riddle"
	lv.open_vault(v3)
	await frames(2)
	check(v3["sigils"].size() == 3 and v3["order"].size() == 3, "live vaults: a Riddle vault shows 3 sigils")
	if args.has("shot"):
		lv.player.global_position = lv.cell_center(v3["f"]) + Vector2(v3["dir"]) * lv.T * 2
		await frames(40)
		await _shot("vault_riddle")
	var ord: Array = v3["order"]
	var vi: int = lv.vaults.find(v3)
	var wrong := "vault_sigil_%d_%d" % [vi, int(ord[1])]
	var en0: int = lv.enemies.size()
	lv.strike_sigil("vault_sigil_%d_%d" % [vi, int(ord[0])])
	check(int(v3["next"]) == 1, "live vaults: the right sigil lights")
	lv.strike_sigil("vault_sigil_%d_%d" % [vi, int(ord[2])])
	check(int(v3["next"]) == 0 and lv.enemies.size() > en0, "live vaults: a wrong sigil resets the order and wakes guardians")
	for i in ord:
		lv.strike_sigil("vault_sigil_%d_%d" % [vi, int(i)])
	check(v3["done"] and int(lv.wv_stats["riddle_vaults"]) == 1 and not lv.markers.has(wrong), "live vaults: the right order solves the riddle")
	# the zone report counts vaults opened before the boss
	var g := GR.ensure(st)
	g["board"] = [_contract("vaults", 1), _contract("vault_riddle", 1), _contract("kills", 9999)]
	g["zones"] = 0   # no board refresh during the check
	await _kill_boss(lv)
	check(int(lv.guild_report.get("vaults", 0)) == 1 and int(lv.guild_report.get("riddle_vaults", 0)) == 1 and g["board"][0]["done"] and g["board"][1]["done"], "live vaults: vaults are credited to the Commission Board", str(lv.guild_report))
	main.go_hub(true)
	await frames(3)

func test_live_contracts_2d() -> void:
	var st: Dictionary = AR.ensure(Game.ch)
	Game.atlas_force_mechanic = "none"
	var g := GR.ensure(st)
	g["board"] = [_contract("kills", 9999), _contract("bosses", 2), _contract("streak", 3)]
	g["zones"] = 0   # no board refresh during the check
	var h := Vector2i(1, 0)
	main.enter_atlas(h)
	await frames(3)
	var lv = Game.level
	for i in 3:
		_fresh_enemy(lv, []).die(lv.player)
	await frames(2)
	await _kill_boss(lv)
	var r: Dictionary = lv.guild_report
	check(int(r.get("kills", 0)) >= 4 and int(r.get("bosses", 0)) == 1 and float(r.get("time", 0)) > 0.0 and float(r.get("boss_time", -1)) >= 0.0 and r.has("pigments"), "live 2D: the run report has kills, bosses, zone and boss times", str(r))
	check(int(g["board"][0]["have"]) == int(r["kills"]) and int(g["board"][1]["have"]) == 1 and int(g["board"][2]["have"]) == 1, "live 2D: kill, boss and streak contracts progress", str(g["board"]))
	main.go_hub(true)
	await frames(3)
	main.enter_atlas(h)
	await frames(3)
	Game.level.apply_death_rot()
	check(int(g["board"][2]["have"]) == 0 and int(g["board"][1]["have"]) == 1, "live 2D: dying in a zone breaks the streak")
	main.go_hub(false)
	await frames(3)
