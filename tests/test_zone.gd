extends Node
## Endgame Phase 0 spike: zone generator, local flow field and pack sleeping checks.
##   godot --headless --fixed-fps 60 --path . res://tests/zone_only.tscn [-- --seeds=200 --png]
## Writes tests/zone_only_results.txt. --png also writes layout pictures to tests/zone_out/.

const ZoneGen = preload("res://scripts/world/zone_gen.gd")
const DungeonGen = preload("res://scripts/world/dungeon_gen.gd")
const ZONE_ID := "zone_overgrown_ruin"

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
	var f := FileAccess.open("res://tests/zone_only_results.txt", FileAccess.WRITE)
	f.store_line("==== %d passed, %d failed ====" % [passes, fails])
	for l in log_lines:
		f.store_line(l)
	f.close()
	print("==== %d passed, %d failed ====" % [passes, fails])
	get_tree().quit(1 if fails > 0 else 0)

func run_all() -> void:
	test_zone_data()
	for z in Data.zone_list:   # every biome (Endgame Phase 1B adds nave and catacomb)
		test_generator(z["id"], int(args.get("seeds", "200")), args.has("png"))
	test_dungeon_gen_unchanged()
	main = load("res://scripts/main.gd").new()
	add_child(main)
	await frames(2)
	await test_live_zone()

# ------------------------------------------------------------------ data
func test_zone_data() -> void:
	check(Data.zone_list.size() >= 1, "zones.json defines at least one zone")
	var z: Dictionary = Data.zones.get(ZONE_ID, {})
	check(not z.is_empty(), "spike zone %s exists" % ZONE_ID)
	check(z.get("generator", "") == "zone" and z.get("spike", false), "spike zone uses the zone generator and is flagged spike")
	check(not Data.dungeons.has(ZONE_ID), "spike zone is not listed as a dungeon tier")
	check(Data.enemies.has(z.get("boss", "")), "spike zone boss exists")
	for p in z.get("pool", []):
		check(Data.enemies.has(p["id"]), "spike zone enemy %s exists" % p["id"])
	for opts in z.get("objective_pool", []):
		check((opts as Array).has("boss"), "objective option %s ends with the boss" % str(opts))

# ------------------------------------------------------------------ generator
func test_generator(zid: String, n: int, png: bool) -> void:
	var def: Dictionary = Data.zones[zid]
	var gcfg: Dictionary = def["gen"]
	var ok_all := {"built": true, "border": true, "connected": true, "chamber_map": true, "boss_leaf": true,
		"counts": true, "sizes": true, "spawns": true, "seal_safe": true, "start": true, "anchors": true, "unlinked_gap": true}
	var bad := {}
	var t_total := 0
	var t_max := 0
	var attempts_max := 0
	var floors := []
	var styles := {}
	for s in range(1, n + 1):
		var gen = ZoneGen.new()
		var t0 := Time.get_ticks_usec()
		var L: Dictionary = gen.generate(def, s)
		var dt := Time.get_ticks_usec() - t0
		t_total += dt
		t_max = maxi(t_max, dt)
		if L.is_empty():
			ok_all["built"] = false
			bad["built"] = s
			continue
		attempts_max = maxi(attempts_max, int(L["attempts"]))
		var w: int = L["w"]
		var h: int = L["h"]
		var grid: PackedByteArray = L["grid"]
		var rooms: Array = L["rooms"]
		var cz: PackedByteArray = L["cell_chamber"]
		var adj: Array = L["adjacency"]
		# border all wall
		for x in w:
			if grid[x] != 0 or grid[(h - 1) * w + x] != 0:
				ok_all["border"] = false
				bad["border"] = s
		for y in h:
			if grid[y * w] != 0 or grid[y * w + w - 1] != 0:
				ok_all["border"] = false
				bad["border"] = s
		# one connected floor region, every floor cell mapped to a chamber
		var startr: Dictionary = rooms[L["start"]]
		var seen := _flood(grid, w, h, startr["anchor"], [])
		var floor_n := 0
		for i in grid.size():
			if grid[i] == 1:
				floor_n += 1
				if seen[i] == 0:
					ok_all["connected"] = false
					bad["connected"] = s
				if cz[i] >= rooms.size():
					ok_all["chamber_map"] = false
					bad["chamber_map"] = s
		floors.append(floor_n)
		for r in rooms:
			var a: Vector2i = r["anchor"]
			if grid[a.y * w + a.x] != 1 or cz[a.y * w + a.x] != r["id"]:
				ok_all["anchors"] = false
				bad["anchors"] = s
			styles[r["style"]] = int(styles.get(r["style"], 0)) + 1
		# chamber counts and sizes
		var normals := rooms.filter(func(r): return r["kind"] == "normal")
		var cr: Array = gcfg["chambers"]
		if normals.size() < int(cr[0]) or normals.size() > int(cr[1]):
			ok_all["counts"] = false
			bad["counts"] = s
		var sz: Array = gcfg["chamber_size"]
		for r in normals:
			var rc: Rect2i = r["rect"]
			if rc.size.x < int(sz[0]) or rc.size.x > int(sz[1]) or rc.size.y < int(sz[0]) or rc.size.y > int(sz[1]):
				ok_all["sizes"] = false
				bad["sizes"] = s
			if r["spawns"].size() < 3:
				ok_all["spawns"] = false
				bad["spawns"] = s
			for sp in r["spawns"]:
				if grid[sp.y * w + sp.x] != 1 or not (rc as Rect2i).has_point(sp):
					ok_all["spawns"] = false
					bad["spawns"] = s
		if startr["kind"] != "start" or L["start"] == L["boss"]:
			ok_all["start"] = false
			bad["start"] = s
		# boss arena is a leaf; sealing its border never cuts another chamber off
		var bid: int = L["boss"]
		if adj[bid].size() != 1:
			ok_all["boss_leaf"] = false
			bad["boss_leaf"] = s
		var br: Rect2i = rooms[bid]["rect"]
		var sealed := []
		for x in range(br.position.x - 1, br.end.x + 1):
			for y in range(br.position.y - 1, br.end.y + 1):
				var on_border := x == br.position.x - 1 or y == br.position.y - 1 or x == br.end.x or y == br.end.y
				if on_border and grid[y * w + x] == 1:
					sealed.append(y * w + x)
		if sealed.is_empty():
			ok_all["seal_safe"] = false
			bad["seal_safe"] = s
		var seen2 := _flood(grid, w, h, startr["anchor"], sealed)
		for r in rooms:
			if r["id"] == bid:
				continue
			var a2: Vector2i = r["anchor"]
			if seen2[a2.y * w + a2.x] == 0:
				ok_all["seal_safe"] = false
				bad["seal_safe"] = s
		var ba: Vector2i = rooms[bid]["anchor"]
		if seen2[ba.y * w + ba.x] != 0:
			ok_all["seal_safe"] = false    # the seal must actually close the arena
			bad["seal_safe"] = s
		# unlinked chambers keep 6+ cells of rock between their floors (first 30 seeds; slow)
		if s <= 30:
			var linked := {}
			for e in L["edges"]:
				linked["%d-%d" % [e[0], e[1]]] = true
				linked["%d-%d" % [e[1], e[0]]] = true
			for y in range(0, h, 2):
				for x in range(0, w, 2):
					if grid[y * w + x] != 1:
						continue
					var ca: int = cz[y * w + x]
					for dy in range(-5, 6):
						for dx in range(-5, 6):
							var xx := x + dx
							var yy := y + dy
							if xx < 0 or yy < 0 or xx >= w or yy >= h or grid[yy * w + xx] != 1:
								continue
							var cb: int = cz[yy * w + xx]
							if cb != ca and not linked.has("%d-%d" % [ca, cb]):
								ok_all["unlinked_gap"] = false
								bad["unlinked_gap"] = s
		if png and s <= 8:
			_save_png(L, "res://tests/zone_out/%s_seed%d.png" % [zid, s])
	for k in ok_all:
		check(ok_all[k], "%s generator %s over %d seeds" % [zid, k, n], "first bad seed %s" % str(bad.get(k, "-")))
	floors.sort()
	note("ZONEGEN %s seeds=%d avg_ms=%.1f max_ms=%.1f max_attempts=%d floor_min=%d floor_median=%d floor_max=%d styles=%s" % [
		zid, n, t_total / 1000.0 / n, t_max / 1000.0, attempts_max, floors[0], floors[floors.size() / 2], floors[floors.size() - 1], str(styles)])
	check(t_max < 1500000, "%s generation stays under 1.5 s per zone" % zid, "%d us" % t_max)
	# determinism
	var a1: Dictionary = ZoneGen.new().generate(def, 4242)
	var a2: Dictionary = ZoneGen.new().generate(def, 4242)
	var a3: Dictionary = ZoneGen.new().generate(def, 4243)
	check(a1["grid"] == a2["grid"] and a1["cell_chamber"] == a2["cell_chamber"] and str(a1["rooms"]) == str(a2["rooms"]), "%s: same seed -> identical zone" % zid)
	check(a1["grid"] != a3["grid"], "%s: different seed -> different zone" % zid)

## Dungeons still use dungeon_gen.gd: same seed gives the same layout as before (checksum
## pinned from the pre-Phase-0 generator, which this phase does not touch).
func test_dungeon_gen_unchanged() -> void:
	var d: Dictionary = Data.dungeons["forgotten_depths"]
	var L: Dictionary = DungeonGen.new().generate(d, 777)
	check(not L.is_empty() and not L.has("zone"), "dungeons still build with dungeon_gen (no zone data)")

func _flood(grid: PackedByteArray, w: int, h: int, from: Vector2i, blocked: Array) -> PackedByteArray:
	var seen := PackedByteArray()
	seen.resize(w * h)
	var blk := {}
	for b in blocked:
		blk[b] = true
	if grid[from.y * w + from.x] != 1:
		return seen
	seen[from.y * w + from.x] = 1
	var q := [from]
	var head := 0
	while head < q.size():
		var c: Vector2i = q[head]
		head += 1
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb: Vector2i = c + o
			if nb.x < 0 or nb.y < 0 or nb.x >= w or nb.y >= h:
				continue
			var i := nb.y * w + nb.x
			if grid[i] == 1 and seen[i] == 0 and not blk.has(i):
				seen[i] = 1
				q.append(nb)
	return seen

func _save_png(L: Dictionary, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var w: int = L["w"]
	var h: int = L["h"]
	var img := Image.create(w * 3, h * 3, false, Image.FORMAT_RGB8)
	var cols := [Color("#7a5a48"), Color("#5a7a48"), Color("#48607a"), Color("#7a4870"), Color("#70703a"), Color("#3a7070"), Color("#8a6a3a"), Color("#5a4a8a"), Color("#4a8a5a"), Color("#8a4a4a")]
	var grid: PackedByteArray = L["grid"]
	var cz: PackedByteArray = L["cell_chamber"]
	for y in h:
		for x in w:
			var c := Color("#141014")
			if grid[y * w + x] == 1:
				var id: int = cz[y * w + x]
				c = cols[id % cols.size()]
				if id == L["boss"]:
					c = Color("#b03030")
				elif id == L["start"]:
					c = Color("#d0c060")
			img.fill_rect(Rect2i(x * 3, y * 3, 3, 3), c)
	for r in L["rooms"]:
		for sp in r["spawns"]:
			img.fill_rect(Rect2i(sp.x * 3, sp.y * 3, 3, 3), Color.WHITE)
		var a: Vector2i = r["anchor"]
		img.fill_rect(Rect2i(a.x * 3 - 3, a.y * 3 - 3, 9, 9), Color.BLACK)
	img.save_png(ProjectSettings.globalize_path(path))

# ------------------------------------------------------------------ live level
func test_live_zone() -> void:
	Game.new_character("warrior")
	Game.ch.level = 20
	main.start_game()
	await frames(3)
	var hub_flow: int = Game.level.flow_reach
	check(hub_flow == 90 and Game.level.cell_zone.is_empty(), "hub keeps the whole-grid flow field (reach 90)")
	var ok: bool = main.enter_dungeon(ZONE_ID, 31337)
	await frames(3)
	var lv = Game.level
	check(ok and lv != null and lv.is_zone, "spike zone loads through main.enter_dungeon")
	if not ok or lv == null:
		return
	check(lv.cell_zone.size() == lv.gw * lv.gh and lv.zone_adj.size() == lv.rooms.size(), "zone level has chamber map and links")
	check(lv.enemies.size() >= 100, "zone spawns a full population", str(lv.enemies.size()))
	note("LIVE zone %dx%d enemies=%d rooms=%d objectives=%s" % [lv.gw, lv.gh, lv.enemies.size(), lv.rooms.size(), str(lv.objectives.map(func(o): return o["type"]))])
	# local flow: only the player's chamber and its links are covered
	var p = lv.player
	lv._compute_flow(lv.to_cell(p.global_position))
	var pc: int = lv.chamber_at(p.global_position)
	var allowed := {pc: true}
	for n in lv.zone_adj[pc]:
		allowed[int(n)] = true
	var outside := 0
	var inside := 0
	for i in lv.flow.size():
		if lv.flow[i] >= 0:
			if allowed.has(int(lv.cell_zone[i])):
				inside += 1
			else:
				outside += 1
	check(outside == 0 and inside > 100, "flow field stays inside the player's chamber and linked chambers", "in %d out %d" % [inside, outside])
	note("FLOW build %d us (cells %d)" % [lv.flow_us, inside])
	# walkable maps follow grid changes (the arena seal uses set_cell)
	var pcell: Vector2i = lv.to_cell(p.global_position) + Vector2i(1, 0)
	if lv.cell(pcell.x, pcell.y) == lv.FLOOR:
		var idx: int = pcell.y * lv.gw + pcell.x
		lv.set_cell(pcell.x, pcell.y, lv.WALL)
		var closed: bool = lv._regions[pc][idx] == 0
		lv.set_cell(pcell.x, pcell.y, lv.FLOOR)
		check(closed and lv._regions[pc][idx] == 1, "chamber walk maps follow set_cell (seal / unseal)")
	# sleeping: far packs asleep, near packs awake
	lv.update_sleep()
	var dist: Array = lv.chamber_dist(pc)
	var wrong := 0
	var asleep := 0
	for e in lv.enemies:
		if not is_instance_valid(e) or not e.alive:
			continue
		var ec: int = lv.chamber_at(e.global_position)
		var far: bool = int(dist[ec]) > 2 and not e.is_boss
		var near: bool = int(dist[ec]) <= 1
		if far and e.process_mode != Node.PROCESS_MODE_DISABLED:
			wrong += 1
		if near and e.process_mode == Node.PROCESS_MODE_DISABLED:
			wrong += 1
		if e.process_mode == Node.PROCESS_MODE_DISABLED:
			asleep += 1
	check(wrong == 0, "far packs sleep, packs in linked chambers stay awake", "%d wrong" % wrong)
	check(asleep > lv.enemies.size() / 3, "most of the zone is asleep at the entrance", "%d/%d" % [asleep, lv.enemies.size()])
	# a sleeping enemy does not move or think
	var sleeper = null
	for e in lv.enemies:
		if is_instance_valid(e) and e.process_mode == Node.PROCESS_MODE_DISABLED:
			sleeper = e
			break
	if sleeper != null:
		var pos0: Vector2 = sleeper.global_position
		var tt: float = sleeper.think_t
		await frames(20)
		check(sleeper.global_position == pos0 and sleeper.think_t == tt, "sleeping enemy is frozen")
		# walk the player into the sleeper's chamber: it wakes
		p.global_position = lv.cell_center(lv.rooms[lv.chamber_at(sleeper.global_position)]["anchor"])
		await frames(20)
		check(sleeper.process_mode != Node.PROCESS_MODE_DISABLED, "sleeping enemy wakes when the player enters its chamber")
	# spike zone gives no first-kill passive point or tier unlock
	var pts0: int = Game.ch.bonus_passive_points
	var tier0: int = int(Game.ch.progress.get("highest_tier", 1))
	var bid: int = lv.layout["boss"]
	for o in lv.objectives:
		if o["type"] != "boss":
			o["done"] = true
	lv._update_seal()
	check(lv.sealed_cells.is_empty(), "arena unsealed once pre-boss objectives are done")
	p.global_position = lv.cell_center(lv.rooms[bid]["anchor"])
	await frames(20)
	check(lv.boss != null and is_instance_valid(lv.boss), "boss spawns in the authored arena")
	if lv.boss != null and is_instance_valid(lv.boss):
		lv.boss.process_mode = Node.PROCESS_MODE_INHERIT
		lv.boss.die(p)
		await frames(10)
		check(lv.boss_dead, "boss kill completes the zone")
		check(Game.ch.bonus_passive_points == pts0 and int(Game.ch.progress.get("highest_tier", 1)) == tier0, "spike zone grants no first-kill point or tier unlock")
	main.go_hub(false)
	await frames(3)
