extends Node
## Endgame Phase 0 performance bench. Run WINDOWED (real rendering), vsync is switched off:
##   godot --path . res://tests/zone_bench.tscn [-- --seconds=75 --seed=31337 --modes=zone,nosleep,dungeon]
## An invulnerable player walks a fixed route through every chamber (scripted movement, no
## input) and kills everything within 70 units every 0.4 s, like a fast clear. Packs chase and
## attack, loot drops. Modes:
##   zone     shipping spike: local flow field + sleeping packs, Rot-5-like density (+50% packs)
##   nosleep  same zone and density, whole-grid flow field (reach 90), nobody sleeps
##   dungeon  Tier 3 dungeon (Abyssal Warrens) for comparison
## Writes tests/zone_bench_results.txt (one BENCH line per mode) and prints it.

const ZONE_ID := "zone_overgrown_ruin"

var args := {}
var lines := []
var main = null

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := String(a).trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	Game.testing = true
	Loot.set_seed(777)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await get_tree().process_frame
	main = load("res://scripts/main.gd").new()
	add_child(main)
	await get_tree().process_frame
	# mode[@packs_lo-packs_hi], e.g. zone@7-9 (Rot-5-like) or nosleep@12-14 (stress)
	var modes: PackedStringArray = String(args.get("modes", "zone@7-9,nosleep@7-9,zone@12-14,nosleep@12-14,dungeon")).split(",")
	for rep_i in int(args.get("reps", "1")):
		for m in modes:
			await bench(m)
	var f := FileAccess.open("res://tests/zone_bench_results.txt", FileAccess.WRITE)
	for l in lines:
		f.store_line(l)
	f.close()
	get_tree().quit(0)

func out(l: String) -> void:
	print(l)
	lines.append(l)

func bench(spec: String) -> void:
	var parts := spec.split("@")
	var mode: String = parts[0]
	var packs := [7, 9]
	if parts.size() > 1:
		var pr := parts[1].split("-")
		packs = [int(pr[0]), int(pr[1])]
	var seconds := float(args.get("seconds", "75"))
	var seed_v := int(args.get("seed", "31337"))
	seed(seed_v)
	Loot.set_seed(777)
	Game.new_character("warrior")
	Game.ch.level = 22
	main.start_game()
	for i in 3:
		await get_tree().physics_frame
	var zdef: Dictionary = Data.zones[ZONE_ID]
	var saved_ppr = zdef["packs_per_room"]
	var saved_ps = zdef["pack_size"]
	var id := ZONE_ID
	if mode == "dungeon":
		id = "abyssal_warrens"
	else:
		zdef["packs_per_room"] = packs     # 7-9 = Rot-5-like pack count (+~50%)
	var ok: bool = main.enter_dungeon(id, seed_v, {"mods": [], "depth": 1})
	zdef["packs_per_room"] = saved_ppr
	zdef["pack_size"] = saved_ps
	if not ok:
		out("BENCH %s FAILED to enter" % mode)
		return
	var lv = Game.level
	if mode == "zone_r90":
		lv.flow_reach = 90
	if mode == "nosleep":
		lv.cell_zone = PackedByteArray()
		lv.flow_reach = 90
		lv.is_zone = false
		for e in lv.enemies:
			if is_instance_valid(e):
				e.process_mode = Node.PROCESS_MODE_INHERIT
	var placed: int = lv.enemies.size()
	var p = lv.player
	p.set_physics_process(false)
	var route := _route(lv)
	var ri := 0
	var dist := PackedInt32Array()
	var dist_for := -1
	var frame_us := []
	var flow_samples := []
	var awake_sum := 0
	var awake_max := 0
	var samples := 0
	var kill_t := 0.0
	var spikes := 0
	var mon := {"phys": 0.0, "proc": 0.0, "draw": 0.0, "objs": 0.0, "chase": 0.0}
	var kills := 0
	var t := 0.0
	var last := Time.get_ticks_usec()
	var speed := 150.0
	lv.flow_us_max = 0
	while t < seconds and ri < route.size():
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var dt_us := now - last
		last = now
		var dt := minf(dt_us / 1000000.0, 0.05)
		t += dt
		if t > 1.0:
			frame_us.append(dt_us)
			if dt_us > 33333:
				spikes += 1
		p.invuln_t = 1.0
		p.life = p.max_life
		# walk along the BFS gradient towards the current route anchor
		var goal: Vector2i = route[ri]
		if dist_for != ri:
			dist = _bfs(lv, goal)
			dist_for = ri
		var c: Vector2i = lv.to_cell(p.global_position)
		var here: int = dist[c.y * lv.gw + c.x] if lv.cell(c.x, c.y) == 1 else -1
		if here <= 1:
			ri += 1
			continue
		var best := c
		var bv := here
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb: Vector2i = c + o
			var v: int = dist[nb.y * lv.gw + nb.x]
			if v >= 0 and v < bv:
				bv = v
				best = nb
		var to: Vector2 = lv.cell_center(best) - p.global_position
		p.global_position += to.normalized() * minf(speed * dt, to.length())
		# fast clear: kill what is next to the player
		kill_t -= dt
		if kill_t <= 0:
			kill_t = 0.4
			for e in lv.hostiles_in_radius(p.global_position, 70.0, "player"):
				if not e.is_boss:
					e.die(p)
					kills += 1
		flow_samples.append(lv.flow_us)
		var chasing := 0
		for e in lv.enemies:
			if is_instance_valid(e) and e.alive and e.state != "idle" and e.process_mode != Node.PROCESS_MODE_DISABLED:
				chasing += 1
		mon["chase"] += chasing
		var awake := 0
		for e in lv.enemies:
			if is_instance_valid(e) and e.alive and e.process_mode != Node.PROCESS_MODE_DISABLED:
				awake += 1
		awake_sum += awake
		if args.has("debug") and samples % 300 == 0:
			var alive_n := 0
			var dis := 0
			for e in lv.enemies:
				if is_instance_valid(e) and e.alive:
					alive_n += 1
					if e.process_mode == Node.PROCESS_MODE_DISABLED:
						dis += 1
			print("DBG %s t=%.1f enemies=%d alive=%d disabled=%d awake=%d" % [mode, t, lv.enemies.size(), alive_n, dis, awake])
		awake_max = maxi(awake_max, awake)
		samples += 1
	frame_us.sort()
	var n := frame_us.size()
	var tot := 0
	for v in frame_us:
		tot += v
	var fl_tot := 0
	for v in flow_samples:
		fl_tot += v
	var fps_avg: float = 1000000.0 * n / maxf(1.0, float(tot))
	var p95: float = frame_us[int(n * 0.95)] / 1000.0 if n > 0 else 0.0
	var p99: float = frame_us[int(n * 0.99)] / 1000.0 if n > 0 else 0.0
	var mx: float = frame_us[n - 1] / 1000.0 if n > 0 else 0.0
	var over := 0
	for v in frame_us:
		if v > 16667:
			over += 1
	out("BENCH mode=%s packs=%s over16ms=%.1f%% over33ms=%d grid=%dx%d placed=%d kills=%d route=%d/%d secs=%.0f frames=%d fps_avg=%.0f frame_avg_ms=%.2f p95_ms=%.2f p99_ms=%.2f max_ms=%.1f flow_last_avg_us=%d flow_max_us=%d awake_avg=%d awake_max=%d chasing_avg=%d" % [
		mode, "%d-%d" % packs if mode != "dungeon" else "-", 100.0 * over / maxf(1, n), spikes, lv.gw, lv.gh, placed, kills, ri, route.size(), t, n, fps_avg, tot / 1000.0 / maxf(1, n), p95, p99, mx,
		fl_tot / maxi(1, flow_samples.size()), lv.flow_us_max, awake_sum / maxi(1, samples), awake_max,
		mon["chase"] / maxi(1, samples)])
	main.go_hub(false)
	for i in 5:
		await get_tree().physics_frame

## Chamber anchors in depth-first order from the start (boss arena last; it stays sealed
## until objectives are done, so the route stops in front of it).
func _route(lv) -> Array:
	var out_r := []
	var rooms: Array = lv.rooms
	var adj: Array = lv.layout.get("adjacency", [])
	if adj.is_empty():
		var sorted := rooms.duplicate()
		sorted.sort_custom(func(a, b): return a["depth"] < b["depth"])
		for r in sorted:
			if r["kind"] != "boss":
				out_r.append(r["anchor"])
		return out_r
	var seen := {}
	var stack := [lv.layout["start"]]
	while stack.size() > 0:
		var i: int = stack.pop_back()
		if seen.has(i):
			continue
		seen[i] = true
		if rooms[i]["kind"] != "boss":
			out_r.append(rooms[i]["anchor"])
		for nb in adj[i]:
			if not seen.has(int(nb)):
				stack.append(int(nb))
	return out_r

func _bfs(lv, goal: Vector2i) -> PackedInt32Array:
	var d := PackedInt32Array()
	d.resize(lv.gw * lv.gh)
	d.fill(-1)
	var q := [goal]
	d[goal.y * lv.gw + goal.x] = 0
	var h := 0
	while h < q.size():
		var c: Vector2i = q[h]
		h += 1
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb: Vector2i = c + o
			if nb.x < 0 or nb.y < 0 or nb.x >= lv.gw or nb.y >= lv.gh:
				continue
			var i: int = nb.y * lv.gw + nb.x
			if lv.grid[i] == 1 and d[i] < 0:
				d[i] = d[c.y * lv.gw + c.x] + 1
				q.append(nb)
	return d
