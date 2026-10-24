extends Node
## Smart player bot for Path of Dan (see tests/smartbot/README.md).
##
##   godot --headless --fixed-fps 60 --path . res://tests/smartbot/smartbot.tscn -- \
##         --class=warrior --tier=1 --runs=5 --seed=1 --profile=Competent --build=balanced
##
## One process plays one or more characters through dungeon runs, writes one CSV row per
## run (appended and flushed immediately, resumable by run id) and optionally a trace.

const MainScript = preload("res://scripts/main.gd")
const Profiles = preload("res://tests/smartbot/sb_profiles.gd")
const HubS = preload("res://tests/smartbot/sb_hub.gd")
const Ctrl = preload("res://tests/smartbot/sb_controller.gd")
const Kit = preload("res://tests/smartbot/sb_kit.gd")

const VERSION := "smartbot-1.0"
const COLUMNS := ["run_id", "version", "class", "build", "profile", "tier", "dungeon", "mode", "chain", "run", "seed", "run_seed",
	"start_level", "end_level", "outcome", "cause_of_death", "time_to_boss", "clear_time", "boss_hp_pct",
	"damage_taken", "hits_taken", "dodge_attempts", "dodge_rolls", "hits_avoided", "evade_failed", "threats_seen", "threats_perceived",
	"potions_used", "mana_potions_used", "kills", "deaths_total", "gear_power", "dps_est", "ehp_est", "max_life",
	"keystones", "passives", "spec", "gems", "hotbar", "runes", "skill_uses", "run_mods", "monster_level", "top_damage",
	"pickups", "midrun_equips", "flags", "ts", "tps", "notes"]

var A := {}
var main = null
var hub = HubS.new()
var ctrl = Ctrl.new()
var kit = Kit.new()
var prof := {}
var flags := {}
var rng := RandomNumberGenerator.new()
var out_path := ""
var trace_f: FileAccess = null
var done_ids := {}
var cur_run_id := ""
var t_run := 0.0

# ================================================================== args
func _parse_args() -> void:
	var defaults := {"class": "warrior", "tier": "1", "runs": "5", "seed": "1", "profile": "Competent", "build": "balanced",
		"mode": "fresh", "carry": "3", "level": "0", "ts": "1", "tps": "60", "timeout": "900", "dungeon": "",
		"out": "res://tests/smartbot/out/results.csv", "trace": "", "kit_only": ""}
	A = defaults.duplicate()
	for a in OS.get_cmdline_user_args():
		var s: String = a
		if not s.begins_with("--"):
			continue
		s = s.substr(2)
		var k := s
		var v := "1"
		if s.contains("="):
			k = s.get_slice("=", 0)
			v = s.substr(k.length() + 1)
		A[k.replace("-", "_")] = v
	flags = {}
	for f in ["no_gems", "no_passives", "no_dodge", "no_crafting"]:
		if A.has(f):
			flags[f] = true

func _flag_str() -> String:
	var parts := []
	for f in ["no_gems", "no_passives", "no_dodge", "no_crafting"]:
		if flags.get(f, false):
			parts.append(f.replace("_", "-"))
	return "|".join(parts) if not parts.is_empty() else "none"

# ================================================================== seeding
static func mix(parts: Array) -> int:
	var h: int = hash(parts) & 0x7fffffff
	return h if h != 0 else 1

func seed_all(s: int) -> void:
	seed(s)                         # global RNG: enemy AI, bosses, hazards, run mods, shuffles
	Loot.set_seed(mix([s, "loot"]))
	Combat.rng.seed = mix([s, "combat"])
	rng.seed = mix([s, "bot"])

# ================================================================== output
func trace(s: String) -> void:
	if trace_f != null:
		trace_f.store_line("[%s %7.2f] %s" % [cur_run_id, t_run if ctrl.lv != null else 0.0, s])
		trace_f.flush()

func _csv_escape(v) -> String:
	var s := str(v)
	if s.contains(",") or s.contains("\"") or s.contains("\n"):
		s = "\"" + s.replace("\"", "\"\"") + "\""
	return s

func _load_done() -> void:
	done_ids.clear()
	if not FileAccess.file_exists(out_path):
		return
	var f := FileAccess.open(out_path, FileAccess.READ)
	var first := true
	while not f.eof_reached():
		var line := f.get_line()
		if first:
			first = false
			continue
		if line.strip_edges() == "":
			continue
		done_ids[line.get_slice(",", 0)] = true

func _append_line(path: String, line: String, header: String) -> void:
	var f: FileAccess
	if FileAccess.file_exists(path):
		f = FileAccess.open(path, FileAccess.READ_WRITE)
		f.seek_end()
	else:
		f = FileAccess.open(path, FileAccess.WRITE)
		f.store_line(header)
	f.store_line(line)
	f.flush()
	f.close()

func _write_row(row: Dictionary) -> void:
	var vals := []
	for c in COLUMNS:
		vals.append(_csv_escape(row.get(c, "")))
	_append_line(out_path, ",".join(vals), ",".join(COLUMNS))
	done_ids[row["run_id"]] = true
	print("ROW ", ",".join(vals))

# ================================================================== setup
func _ready() -> void:
	_parse_args()
	Game.testing = true
	Engine.physics_ticks_per_second = int(A["tps"])
	Engine.max_physics_steps_per_frame = 8
	Engine.time_scale = float(A["ts"])
	out_path = A["out"]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_path.get_base_dir()))
	# keep the Godot editor from importing result CSVs as translations
	var gi := out_path.get_base_dir() + "/.gdignore"
	if not FileAccess.file_exists(gi):
		var gf := FileAccess.open(gi, FileAccess.WRITE)
		if gf != null:
			gf.store_string("results - not game assets\n")
			gf.close()
	if A["trace"] != "":
		var tp: String = A["trace"] if A["trace"] != "1" else out_path.get_basename() + "_trace.txt"
		if A.has("unit"):
			var c := int(A["unit"].get_slice(":", 0))
			var r := int(A["unit"].get_slice(":", 1))
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_path.get_base_dir() + "/trace"))
			tp = "%s/trace/%s.txt" % [out_path.get_base_dir(), _run_id(c, r, _level_for(int(A["tier"])))]
		if A.has("unit") or A.get("isolate", "1") == "0" or A["kit_only"] != "":
			trace_f = FileAccess.open(tp, FileAccess.WRITE)
	var ov := {}
	if A.has("set"):
		# --set=key:value,key:value overrides single profile parameters (sensitivity studies)
		for kv in String(A["set"]).split(","):
			var k: String = kv.get_slice(":", 0)
			var v: String = kv.get_slice(":", 1)
			if v in ["true", "false"]:
				ov[k] = v == "true"
			else:
				ov[k] = float(v)
	prof = Profiles.get_profile(A["profile"], ov)
	hub.setup(self, A["build"], flags)
	kit.hub = hub
	ctrl.setup(self, hub, prof, flags, rng)
	main = MainScript.new()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	if A.has("check"):
		# launcher pre-flight: all modules parsed and the game booted
		var cf := FileAccess.open(out_path.get_base_dir() + "/.check_ok", FileAccess.WRITE)
		cf.store_string(VERSION)
		cf.close()
		print("SMARTBOT OK")
	elif A["kit_only"] != "":
		await _kit_only()
	elif A.has("unit"):
		await _run_unit(int(A["unit"].get_slice(":", 0)), int(A["unit"].get_slice(":", 1)))
	else:
		await _run_all()
	print("SMARTBOT DONE")
	if trace_f != null:
		trace_f.close()
	get_tree().quit()

func _dungeon_id(tier: int) -> String:
	if A["dungeon"] != "":
		return A["dungeon"]
	for d in Data.dungeon_list:
		if int(d.get("tier", 1)) == tier:
			return d["id"]
	return "forgotten_depths"

func _level_for(tier: int) -> int:
	var l := int(A["level"])
	return l if l > 0 else kit.default_level(tier)

func _run_id(c: int, r: int, lvl: int) -> String:
	var m: String = A["mode"] + ("%d" % int(A["carry"]) if A["mode"] == "carry" else "")
	var pn: String = A["profile"] + (("[" + String(A["set"]).replace(",", ";").replace(":", "=") + "]") if A.has("set") else "")
	return "%s-%s-%s-T%d-L%d-s%s-%s-%s-ts%s-c%d-r%d" % [A["class"], A["build"], pn, int(A["tier"]), lvl, A["seed"], m, _flag_str(), A["ts"], c, r]

# ================================================================== kit-only
func _kit_only() -> void:
	var tier := int(A["tier"])
	var lvl := _level_for(tier)
	var path: String = out_path.get_basename() + "_kits.json"
	var kits := []
	for c in int(A["runs"]):
		seed_all(mix([int(A["seed"]), c, "kit"]))
		var info: Dictionary = kit.make(A["class"], tier, lvl, rng)
		var d: Dictionary = Game.ch.to_dict()
		d["kit_summary"] = _summary(Game.ch)
		kits.append(d)
		print("KIT %d %s L%d gear_power=%d %s" % [c, A["class"], info["level"], info["gear_power"], JSON.stringify(d["kit_summary"])])
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(kits, "  "))
	f.close()

func _summary(ch) -> Dictionary:
	var eq := {}
	for s in ch.equipment:
		var it = ch.equipment[s]
		if it != null:
			eq[s] = "%s %s ilvl%d sockets=%d gems=%s" % [it.get("rarity", ""), it.get("name", ""), int(it.get("ilvl", 0)), Loot.item_sockets(it), str(it.get("gems", []))]
	var pw: Dictionary = hub.power(ch)
	return {"level": ch.level, "life": ch.final.get("max_life", 0), "dps_est": int(pw["dps"]), "ehp_est": int(pw["ehp"]), "gold": ch.gold,
		"passives": ch.allocated.size(), "keystones": hub.planner.keystones(ch), "spec": ch.spec_id, "spec_nodes": ch.spec_nodes,
		"hotbar": ch.loadout, "runes": ch.skill_runes, "pouch": ch.gems, "equipment": eq}

# ================================================================== batch
func _ckpt_path(c: int, r: int) -> String:
	## character state after run r of chain c (after the town visit)
	return "%s_ckpt/%s.json" % [out_path.get_basename(), _run_id(c, r, _level_for(int(A["tier"])))]

func _row_path(rid: String) -> String:
	return "%s_rows/%s.json" % [out_path.get_basename(), rid]

func _snapshot() -> Dictionary:
	var d: Dictionary = Game.ch.to_dict()
	d["vendor_stock"] = Game.vendor_stock
	return d

func _restore(d: Dictionary) -> void:
	Game.load_from_dict(d)

## Normalise the character through the same JSON round trip a checkpoint uses.
func _roundtrip() -> void:
	var d = JSON.parse_string(JSON.stringify(_snapshot()))
	_restore(d)

## Rows written by finished child processes but not yet merged into the CSV (crash recovery).
func _merge_pending_rows() -> void:
	var dir := DirAccess.open(out_path.get_basename() + "_rows")
	if dir == null:
		return
	for fn in dir.get_files():
		if not fn.ends_with(".json"):
			continue
		var rid := fn.get_basename()
		if done_ids.has(rid):
			continue
		var d = JSON.parse_string(FileAccess.get_file_as_string(out_path.get_basename() + "_rows/" + fn))
		if typeof(d) == TYPE_DICTIONARY and d.get("csv_path", "") == out_path:
			_write_row(d["row"])
			if d.has("wall"):
				_append_line(out_path.get_basename() + "_perf.csv", "%s,%.2f,%s" % [rid, float(d["wall"]), str(d["row"].get("clear_time", ""))], "run_id,wall_s,game_s")

# ------------------------------------------------------------------ coordinator
## Every run is played in its own fresh process (`--unit=c:r`): results then do not depend
## on what ran before in the same process (Godot's physics broad-phase keeps history), so a
## batch can be split, resumed after a crash or run in parallel and still give identical rows.
var co_mutex := Mutex.new()

func _run_all() -> void:
	_load_done()
	_merge_pending_rows()
	var chains := int(A["runs"])
	var per_chain := int(A["carry"]) if A["mode"] == "carry" else 1
	var todo := []
	var lvl := _level_for(int(A["tier"]))
	for c in chains:
		if A.has("only") and c != int(A["only"]):
			continue
		var need := false
		for r in per_chain:
			if not done_ids.has(_run_id(c, r, lvl)):
				need = true
		if need:
			todo.append(c)
		else:
			print("SKIP chain %d (already in %s)" % [c, out_path])
	if A.get("isolate", "1") == "0":
		await _run_inline(todo, per_chain)
		return
	var jobs := maxi(1, int(A.get("jobs", "1")))
	var queue := todo.duplicate()
	var running := []
	while not queue.is_empty() or not running.is_empty():
		while running.size() < jobs and not queue.is_empty():
			var th := Thread.new()
			th.start(_chain_worker.bind(queue.pop_front(), per_chain, lvl))
			running.append(th)
		await get_tree().create_timer(0.25).timeout
		for th in running.duplicate():
			if not th.is_alive():
				th.wait_to_finish()
				running.erase(th)

func _child_args(c: int, r: int) -> Array:
	var user := []
	for a in OS.get_cmdline_user_args():
		if not (a.begins_with("--only") or a.begins_with("--unit") or a.begins_with("--jobs")):
			user.append(a)
	user.append("--unit=%d:%d" % [c, r])
	return ["--headless", "--fixed-fps", str(int(A["tps"])), "--path", ProjectSettings.globalize_path("res://"), "res://tests/smartbot/smartbot.tscn", "--"] + user

func _chain_worker(c: int, per_chain: int, lvl: int) -> void:
	for r in per_chain:
		var rid := _run_id(c, r, lvl)
		co_mutex.lock()
		var done: bool = done_ids.has(rid)
		co_mutex.unlock()
		if done:
			continue
		var t0 := Time.get_ticks_msec()
		var rp := _row_path(rid)
		# child with a wall-clock watchdog (a hung child is killed and logged)
		var pid := OS.create_process(OS.get_executable_path(), _child_args(c, r))
		var max_wall := float(A.get("max_wall", "1800"))
		var killed := false
		while OS.is_process_running(pid):
			OS.delay_msec(200)
			if (Time.get_ticks_msec() - t0) / 1000.0 > max_wall:
				OS.kill(pid)
				killed = true
				break
		var code := 0 if FileAccess.file_exists(rp) else 1
		var text := ""
		if killed:
			text = "killed after %.0f s wall (--max_wall)" % max_wall
		elif code != 0:
			# re-run once with output capture for the error log
			var out := []
			OS.execute(OS.get_executable_path(), _child_args(c, r), out, true)
			for o in out:
				text += str(o)
			code = 0 if FileAccess.file_exists(rp) else 1
		co_mutex.lock()
		if FileAccess.file_exists(rp):
			var d = JSON.parse_string(FileAccess.get_file_as_string(rp))
			if typeof(d) == TYPE_DICTIONARY:
				_write_row(d["row"])
				_append_line(out_path.get_basename() + "_perf.csv", "%s,%.2f,%s" % [rid, (Time.get_ticks_msec() - t0) / 1000.0, str(d["row"].get("clear_time", ""))], "run_id,wall_s,game_s")
			print("UNIT %s exit=%d" % [rid, code])
		else:
			print("UNIT %s FAILED exit=%d\n%s" % [rid, code, text.right(3000)])
			_append_line(out_path.get_basename() + "_errors.txt", "=== %s exit=%d\n%s" % [rid, code, text.right(6000)], "smartbot child failures")
		co_mutex.unlock()
		if not FileAccess.file_exists(rp):
			break     # later runs of this chain need this one's checkpoint

## One run in this process (child of the coordinator).
func _run_unit(c: int, r: int) -> void:
	var tier := int(A["tier"])
	var lvl := _level_for(tier)
	var per_chain := int(A["carry"]) if A["mode"] == "carry" else 1
	cur_run_id = _run_id(c, r, lvl)
	if r == 0:
		seed_all(mix([int(A["seed"]), c, "kit"]))
		kit.make(A["class"], tier, lvl, rng)
		_roundtrip()
		trace("KIT %s" % JSON.stringify(_summary(Game.ch)))
	else:
		var ck := _ckpt_path(c, r - 1)
		if not FileAccess.file_exists(ck):
			push_error("missing checkpoint " + ck)
			return
		_restore(JSON.parse_string(FileAccess.get_file_as_string(ck)))
	main.start_game()
	await _play_and_record(c, r, lvl, per_chain, true)

## Old single-process mode (--isolate=0): deterministic for the whole batch, but a chain's
## rows can depend on what ran before it in the same process.
func _run_inline(todo: Array, per_chain: int) -> void:
	var tier := int(A["tier"])
	var lvl := _level_for(tier)
	var started := false
	for c in todo:
		cur_run_id = _run_id(c, 0, lvl)
		seed_all(mix([int(A["seed"]), c, "kit"]))
		kit.make(A["class"], tier, lvl, rng)
		_roundtrip()
		trace("KIT %s" % JSON.stringify(_summary(Game.ch)))
		if not started:
			main.start_game()
			started = true
		else:
			main.go_hub(false)
		for r in per_chain:
			cur_run_id = _run_id(c, r, lvl)
			await _play_and_record(c, r, lvl, per_chain, false)

func _play_and_record(c: int, r: int, lvl: int, per_chain: int, as_unit: bool) -> void:
	var rid := _run_id(c, r, lvl)
	hub.choose_hotbar(Game.ch)
	var run_seed := mix([int(A["seed"]), c, r])
	seed_all(run_seed)
	var t0 := Time.get_ticks_msec()
	var row: Dictionary = await _one_run(c, r, run_seed, lvl)
	var wall := (Time.get_ticks_msec() - t0) / 1000.0
	# after the run: the game's own death / exit rules
	if row["outcome"] == "died":
		main.ui.panels["death"]._return()     # death_panel: lose 10% of level xp, back to town
	elif row["outcome"] == "boss_killed":
		main.go_hub(true)                     # exit portal
	else:
		main.go_hub(false)                    # town portal (timeout)
	await get_tree().physics_frame
	seed_all(mix([int(A["seed"]), c, r, "town"]))
	hub.town_visit(Game.ch)
	_roundtrip()
	main.go_hub(false)
	if per_chain > 1:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_path.get_basename() + "_ckpt"))
		var f := FileAccess.open(_ckpt_path(c, r), FileAccess.WRITE)
		f.store_string(JSON.stringify(_snapshot()))
		f.close()
	if as_unit:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_path.get_basename() + "_rows"))
		var f2 := FileAccess.open(_row_path(rid), FileAccess.WRITE)
		f2.store_string(JSON.stringify({"csv_path": out_path, "row": row, "wall": wall}))
		f2.close()
	else:
		if not done_ids.has(rid):
			_write_row(row)
		_append_line(out_path.get_basename() + "_perf.csv", "%s,%.2f,%s" % [rid, wall, str(row.get("clear_time", ""))], "run_id,wall_s,game_s")

## --debug: on a timeout, report whether the remaining objective targets can be reached at all
func _debug_reachability(lv) -> void:
	var gw: int = lv.gw
	var seen := PackedByteArray()
	seen.resize(gw * lv.gh)
	var start: Vector2i = lv.to_cell(lv.player.global_position)
	var q := [start]
	seen[start.y * gw + start.x] = 1
	var h := 0
	while h < q.size():
		var c: Vector2i = q[h]
		h += 1
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + o
			if lv.cell(n.x, n.y) == 1 and seen[n.y * gw + n.x] == 0:
				seen[n.y * gw + n.x] = 1
				q.append(n)
	for e in lv.wave_state.get("alive", []):
		if is_instance_valid(e) and e.alive:
			var ec: Vector2i = lv.to_cell(e.global_position)
			trace("REACH wave enemy %s at %s floor=%s reachable=%s state=%s" % [e.display_name, str(ec), lv.cell(ec.x, ec.y) == 1, seen[ec.y * gw + ec.x] == 1 if lv.cell(ec.x, ec.y) == 1 else false, e.state])
	for it in lv.interactables:
		var ic: Vector2i = lv.to_cell(it["pos"])
		trace("REACH interactable %s at %s floor=%s reachable=%s" % [it["kind"], str(ic), lv.cell(ic.x, ic.y) == 1, seen[ic.y * gw + ic.x] == 1])
	for k in lv.markers:
		var n2 = lv.markers[k]
		if is_instance_valid(n2):
			var mc: Vector2i = lv.to_cell(n2.global_position)
			trace("REACH marker %s at %s floor=%s reachable=%s" % [k, str(mc), lv.cell(mc.x, mc.y) == 1, seen[mc.y * gw + mc.x] == 1])

func _one_run(c: int, r: int, run_seed: int, lvl: int) -> Dictionary:
	var ch = Game.ch
	var tier := int(A["tier"])
	var did := _dungeon_id(tier)
	var start_level: int = ch.level
	var deaths0 := int(ch.progress.get("deaths", 0))
	hub.choose_hotbar(ch)
	hub.runes(ch)
	main.enter_dungeon(did, run_seed)
	await get_tree().physics_frame
	var lv = Game.level
	var p = lv.player
	ctrl.begin(lv, p)
	t_run = 0.0
	var timeout := float(A["timeout"])
	var boss_t := -1.0
	var clear_t := -1.0
	var outcome := "timeout"
	var kills0: int = lv.kills
	var boss_hp := -1.0
	trace("RUN start %s L%d mods=%s monster_level=%d hotbar=%s" % [did, ch.level, str(lv.mods.map(func(m): return m["id"])), lv.monster_level, str(ch.loadout)])
	while true:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t_run += dt
		if lv.boss_spawned and boss_t < 0:
			boss_t = t_run
			trace("BOSS spawned")
		if lv.boss != null and is_instance_valid(lv.boss):
			boss_hp = lv.boss.life / maxf(1.0, lv.boss.max_life) * 100.0
		if not p.alive:
			outcome = "died"
			break
		if lv.boss_dead:
			if clear_t < 0:
				clear_t = t_run
				boss_hp = 0.0
				ctrl.loot_mode = true
				trace("BOSS killed")
			if t_run - clear_t > 15.0 or not ctrl.loot_left():
				outcome = "boss_killed"
				break
		if t_run >= timeout:
			break
		ctrl.tick(dt)
	var notes := []
	if outcome == "timeout":
		for o in lv.objectives:
			if not o["done"]:
				notes.append("open:%s(%d/%d)" % [o["type"], int(o["have"]), int(o["need"])])
		if lv.sealed_cells.size() > 0:
			notes.append("arena_sealed")
		if lv.wave_state.get("active", false):
			notes.append("waves_active:%d_alive" % lv.wave_state.get("alive", []).size())
	if outcome == "timeout" and A.has("debug"):
		_debug_reachability(lv)
	if ctrl.st.get("unreachable", 0) > 0:
		notes.append("unreachable_targets:%d" % ctrl.st["unreachable"])
	var cause := ""
	if outcome == "died":
		cause = ctrl.death_cause()
		trace("DIED to %s" % cause)
	ctrl.end()
	var top := ""
	var db: Dictionary = ctrl.st["dmg_by"]
	var keys := db.keys()
	keys.sort_custom(func(a, b): return db[a] > db[b])
	var tops := []
	for k in keys.slice(0, 3):
		tops.append("%s=%d" % [k, int(db[k])])
	var gl := []
	for s in ch.EQUIP_SLOTS:
		var it = ch.equipment.get(s)
		if it != null:
			for g in it.get("gems", []):
				if g != "":
					gl.append(g)
	var su := []
	for k in ctrl.st["skill_uses"]:
		su.append("%s:%d" % [k, ctrl.st["skill_uses"][k]])
	var rl := []
	for k in ch.skill_runes:
		for rr in ch.skill_runes[k]:
			rl.append("%s>%s" % [rr, k])
	var pw: Dictionary = hub.power(ch)
	var row := {
		"run_id": _run_id(c, r, lvl), "version": VERSION, "class": A["class"], "build": A["build"], "profile": A["profile"] + (("[" + String(A["set"]).replace(",", ";") + "]") if A.has("set") else ""),
		"tier": tier, "dungeon": did, "mode": A["mode"], "chain": c, "run": r, "seed": A["seed"], "run_seed": run_seed,
		"start_level": start_level, "end_level": ch.level, "outcome": outcome, "cause_of_death": cause,
		"time_to_boss": "%.1f" % boss_t, "clear_time": "%.1f" % (clear_t if clear_t >= 0 else t_run),
		"boss_hp_pct": "%.1f" % boss_hp, "damage_taken": int(ctrl.st["damage_taken"]), "hits_taken": ctrl.st["hits_taken"],
		"dodge_attempts": ctrl.st["dodge_attempts"], "dodge_rolls": ctrl.st["dodge_rolls"], "hits_avoided": ctrl.st["hits_avoided"],
		"evade_failed": ctrl.st["evade_failed"], "threats_seen": ctrl.threat.counters["seen"], "threats_perceived": ctrl.threat.counters["perceived"],
		"potions_used": ctrl.st["potions"], "mana_potions_used": ctrl.st["mana_potions"], "kills": lv.kills - kills0,
		"deaths_total": deaths0 + (1 if outcome == "died" else 0),
		"gear_power": hub.gear_power(ch), "dps_est": int(pw["dps"]), "ehp_est": int(pw["ehp"]), "max_life": int(ch.final.get("max_life", 0)),
		"keystones": "|".join(hub.planner.keystones(ch)), "passives": ch.allocated.size() - 1, "spec": ch.spec_id + ("(%d)" % ch.spec_nodes.size() if ch.spec_id != "" else ""),
		"gems": "|".join(gl), "hotbar": "|".join(ch.loadout.filter(func(x): return x != "")), "runes": "|".join(rl), "skill_uses": "|".join(su),
		"run_mods": "|".join(lv.mods.map(func(m): return m["id"])), "monster_level": lv.monster_level, "top_damage": "|".join(tops),
		"pickups": ctrl.st["pickups"], "midrun_equips": ctrl.st["mid_equips"], "flags": _flag_str(), "ts": A["ts"], "tps": A["tps"], "notes": "|".join(notes),
	}
	trace("RUN end %s in %.1fs, damage taken %d, dodges %d (rolls %d), avoided %d, potions %d" % [outcome, t_run, int(ctrl.st["damage_taken"]), ctrl.st["dodge_attempts"], ctrl.st["dodge_rolls"], ctrl.st["hits_avoided"], ctrl.st["potions"]])
	return row
