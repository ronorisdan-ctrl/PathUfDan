extends RefCounted
## Pure Training Grounds rules (no scene or autoload access, Godot 4.0, no class_name).
## Usage: const TrainingRules = preload("res://scripts/core/training_rules.gd")
## Tuning lives in data/training.json (Data.training_cfg); every function here takes
## what it needs as arguments so it can be unit tested without a scene.
##
## A damage event is a Dictionary:
##   t          game seconds since the window started (set by record())
##   amount     damage applied after mitigation
##   kind       "hit" | "dot" | "minion" | "deployable"
##   skill_id   the skill that caused it ("" = unknown -> "Other", "passive" = passive/item effect)
##   status_id  for DoT ticks, the status ("ignite", "bleed", ...)
##   crit       bool, direct hits only
##   dummy      1..3
##   cast_id    int, -1 when unknown
##
## Window rule (documented): the window is the half-open interval [0, duration).
## The first counted direct hit is at t = 0 and counts. A hit that arrives when the
## elapsed time is exactly `duration` is ignored (the test is already over).

const KINDS := ["hit", "dot", "minion", "deployable"]
const DIRECT_KINDS := ["hit", "minion", "deployable"]
const PLAYER_ONLY_KINDS := ["hit", "dot"]

# ------------------------------------------------------------------ source filters
static func is_direct(kind: String) -> bool:
	return DIRECT_KINDS.has(kind)

## Does this kind of damage count towards the result under the counting mode?
## counting: "all" (every source) or "player" (player's hits and DoTs only).
static func counts(kind: String, counting: String) -> bool:
	if counting == "player":
		return PLAYER_ONLY_KINDS.has(kind)
	return KINDS.has(kind)

## A status tick: kind "dot", or any event that carries a status_id (a minion's or a
## trap's ignite has kind minion/deployable but is still a tick, not a hit).
static func is_tick(ev: Dictionary) -> bool:
	return ev.get("kind", "hit") == "dot" or str(ev.get("status_id", "")) != ""

## A direct hit: a hit/minion/deployable event that is not a status tick.
static func event_is_direct(ev: Dictionary) -> bool:
	return is_direct(ev.get("kind", "hit")) and not is_tick(ev)

## Only a counted direct hit can start the window; a DoT tick never does.
static func starts_window(kind: String, counting: String, tick: bool = false) -> bool:
	return is_direct(kind) and not tick and counts(kind, counting)

# ------------------------------------------------------------------ the running test
## Settings: {"type","duration","counting","profile","spacing"}.
static func default_settings(cfg: Dictionary) -> Dictionary:
	var d: Dictionary = cfg.get("defaults", {})
	return {
		"type": str(d.get("type", "single")),
		"duration": int(d.get("duration", cfg.get("default_duration", 10))),
		"counting": str(d.get("counting", "all")),
		"profile": str(d.get("profile", "none")),
		"spacing": str(d.get("spacing", "tight")),
	}

## Clamps unknown values back to something valid (duration must be one of cfg.durations).
static func sanitize_settings(cfg: Dictionary, s: Dictionary) -> Dictionary:
	var out := default_settings(cfg)
	if ["single", "aoe"].has(s.get("type", "")):
		out["type"] = s["type"]
	# JSON numbers load as floats, and Array.has(30) does not match 30.0, so compare as ints
	for d in cfg.get("durations", [10, 30]):
		if int(d) == int(s.get("duration", -1)):
			out["duration"] = int(d)
	if ["all", "player"].has(s.get("counting", "")):
		out["counting"] = s["counting"]
	if cfg.get("profiles", {}).has(s.get("profile", "")):
		out["profile"] = s["profile"]
	if cfg.get("cluster_spacing", {}).has(s.get("spacing", "")):
		out["spacing"] = s["spacing"]
	return out

## A fresh test. `dummies` is 1 (single) or 3 (AoE).
static func new_run(settings: Dictionary, dummies: int = 1) -> Dictionary:
	return {
		"settings": settings.duplicate(),
		"dummies": dummies,
		"duration": float(settings.get("duration", 10)),
		"started": false,
		"finished": false,
		"elapsed": 0.0,
		"grace_left": 0.0,
		"events": [],
		"poise_breaks": 0,
		"dev": false,
		"warnings": [],
	}

static func is_running(run: Dictionary) -> bool:
	return bool(run.get("started", false)) and not bool(run.get("finished", false))

## True when a new counted direct hit may start a fresh test (nothing running, and
## any previous result's restart grace is over).
static func can_start(run: Dictionary) -> bool:
	if run.is_empty():
		return true
	if not run.get("started", false):
		return true
	return bool(run.get("finished", false)) and float(run.get("grace_left", 0.0)) <= 0.0

## Advance game time. `delta` is the SCALED physics delta, so the timer pauses with the
## pause menu and follows hit-stop and the Dev time scale.
static func tick(run: Dictionary, delta: float, restart_grace: float) -> void:
	if run.is_empty():
		return
	if is_running(run):
		run["elapsed"] = float(run["elapsed"]) + delta
		# tiny epsilon: 100 ticks of 0.1 add up to 9.99999999999998, which must still end a 10 s test
		if float(run["elapsed"]) >= float(run["duration"]) - 0.000001:
			run["elapsed"] = float(run["duration"])
			run["finished"] = true
			run["grace_left"] = restart_grace
	elif run.get("finished", false):
		run["grace_left"] = maxf(0.0, float(run["grace_left"]) - delta)

## Offer one damage event. Returns "counted", "ignored_source" (excluded by the counting
## mode), "ignored_idle" (a DoT tick before the window started), "ignored_ended" (after the
## window ended) or "ignored_grace" is never returned here: the caller decides about
## starting a new test with can_start() before calling record on a new run.
static func record(run: Dictionary, ev: Dictionary) -> String:
	var counting: String = run["settings"].get("counting", "all")
	var kind: String = ev.get("kind", "hit")
	if not counts(kind, counting):
		return "ignored_source"
	if run.get("finished", false):
		return "ignored_ended"
	if not run.get("started", false):
		if not starts_window(kind, counting, is_tick(ev)):
			return "ignored_idle"
		run["started"] = true
		run["elapsed"] = 0.0
	var e := ev.duplicate()
	e["t"] = float(run["elapsed"])
	e["amount"] = float(ev.get("amount", 0.0))
	run["events"].append(e)
	return "counted"

static func add_poise_break(run: Dictionary) -> void:
	if is_running(run):
		run["poise_breaks"] = int(run["poise_breaks"]) + 1

## Marks the run DEV if any damage-affecting Dev flag is active right now.
## `active` is a list of flag names, `marking` is cfg.dev_flags_that_mark.
static func mark_dev(run: Dictionary, active: Array, marking: Array) -> void:
	if not is_running(run):
		return
	for f in active:
		if marking.has(f):
			run["dev"] = true
			return

## Which of the Dev flags (name -> value) differ from their defaults and mark results.
static func marking_flags(flags: Dictionary, defaults: Dictionary, marking: Array, attr_bonus: int = 0) -> Array:
	var out := []
	for f in marking:
		if f == "attr_bonus":
			if attr_bonus != 0:
				out.append(f)
		elif flags.has(f) and defaults.has(f) and flags[f] != defaults[f]:
			out.append(f)
	return out

# ------------------------------------------------------------------ result maths
static func total_damage(events: Array) -> float:
	var t := 0.0
	for e in events:
		t += float(e["amount"])
	return t

## Average DPS = total counted damage / the FULL test duration (not time to the last hit).
static func average_dps(events: Array, duration: float) -> float:
	if duration <= 0.0:
		return 0.0
	return total_damage(events) / duration

## Highest total damage in any sliding window of `window` seconds (default 1.0), with the
## time the window starts. Two-pointer pass over events sorted by t, windows anchored at
## each event, so a burst crossing a whole-second boundary is never split.
## Returns {"dps": damage per second over that window, "start": t}. Ties keep the earliest.
static func peak_window(events: Array, window: float = 1.0) -> Dictionary:
	if events.is_empty() or window <= 0.0:
		return {"dps": 0.0, "start": 0.0}
	var ev := events.duplicate()
	ev.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
	var best := 0.0
	var best_start := float(ev[0]["t"])
	var sum := 0.0
	var lo := 0
	for hi in ev.size():
		sum += float(ev[hi]["amount"])
		# window is [t_lo, t_lo + window): drop events that fell out of the back
		while float(ev[hi]["t"]) - float(ev[lo]["t"]) >= window:
			sum -= float(ev[lo]["amount"])
			lo += 1
		# the window ending at hi starts at the earliest event it still contains
		if sum > best + 1e-9:
			best = sum
			best_start = float(ev[lo]["t"])
	return {"dps": best / window, "start": best_start}

static func direct_events(events: Array) -> Array:
	var out := []
	for e in events:
		if event_is_direct(e):
			out.append(e)
	return out

static func direct_hits(events: Array) -> int:
	return direct_events(events).size()

static func crit_rate(events: Array) -> float:
	var d := direct_events(events)
	if d.is_empty():
		return 0.0
	var c := 0
	for e in d:
		if e.get("crit", false):
			c += 1
	return float(c) / float(d.size())

static func average_hit(events: Array) -> float:
	var d := direct_events(events)
	if d.is_empty():
		return 0.0
	return total_damage(d) / float(d.size())

static func biggest_hit(events: Array) -> float:
	var b := 0.0
	for e in direct_events(events):
		b = maxf(b, float(e["amount"]))
	return b

# ------------------------------------------------------------------ breakdown
## Row key + label for one event. `names` maps skill_id -> display name,
## cfg supplies labels/status names.
static func source_row(ev: Dictionary, names: Dictionary, cfg: Dictionary) -> Dictionary:
	var lab: Dictionary = cfg.get("labels", {})
	var sid: String = str(ev.get("skill_id", ""))
	var kind: String = ev.get("kind", "hit")
	var skill_name: String
	if sid == "":
		skill_name = str(lab.get("other", "Other"))
	elif sid == "passive":
		skill_name = str(lab.get("passive", "Passive and item effects"))
	else:
		skill_name = str(names.get(sid, sid.capitalize()))
	var tag := ""
	if kind == "minion":
		tag = " (%s)" % lab.get("minions_tag", "minions")
	elif kind == "deployable":
		tag = " (%s)" % lab.get("deployed_tag", "deployed")
	var st: String = str(ev.get("status_id", ""))
	if st != "":
		# a status tick: credited to the skill that applied the status (sub-row)
		var stn: String = str(cfg.get("status_names", {}).get(st, st.capitalize()))
		return {"key": "dot|%s|%s|%s" % [kind, st, sid], "label": "%s (from %s)%s" % [stn, skill_name, tag]}
	return {"key": "%s|%s" % [kind, sid], "label": skill_name + tag}

## Per-skill table: rows sorted by damage (highest first, label as tie-break), each
## {key, label, kind, damage, share (0..100, exact), share_text (1 decimal, sums to 100.0),
##  dps, hits}. Sources excluded by the counting mode never get here (record() drops them).
static func breakdown(events: Array, duration: float, names: Dictionary, cfg: Dictionary) -> Array:
	var rows := {}
	for e in events:
		var sr := source_row(e, names, cfg)
		var k: String = sr["key"]
		if not rows.has(k):
			rows[k] = {"key": k, "label": sr["label"], "kind": e["kind"], "damage": 0.0, "hits": 0}
		rows[k]["damage"] += float(e["amount"])
		rows[k]["hits"] += 1
	var out: Array = rows.values()
	out.sort_custom(func(a, b):
		if absf(a["damage"] - b["damage"]) > 1e-9:
			return a["damage"] > b["damage"]
		return str(a["label"]) < str(b["label"]))
	var total := total_damage(events)
	var raw := []
	for r in out:
		r["share"] = (float(r["damage"]) / total * 100.0) if total > 0.0 else 0.0
		r["dps"] = float(r["damage"]) / duration if duration > 0.0 else 0.0
		raw.append(r["share"])
	var rounded := round_shares(raw)
	for i in out.size():
		out[i]["share_text"] = rounded[i]
	return out

## Rounds percentages to one decimal with the largest-remainder method so they sum to
## exactly 100.0 (when the input sums to 100). Returns floats, same order.
static func round_shares(shares: Array) -> Array:
	var n := shares.size()
	var out := []
	if n == 0:
		return out
	var tot := 0.0
	for s in shares:
		tot += float(s)
	if tot <= 0.0:
		for i in n:
			out.append(0.0)
		return out
	var tenths := []
	var floors := []
	var used := 0
	for i in n:
		var v := float(shares[i]) / tot * 1000.0
		var f := int(floor(v))
		floors.append(f)
		tenths.append({"i": i, "rem": v - float(f)})
		used += f
	tenths.sort_custom(func(a, b): return a["rem"] > b["rem"])
	var extra := 1000 - used
	for j in extra:
		floors[tenths[j % n]["i"]] += 1
	for i in n:
		out.append(float(floors[i]) / 10.0)
	return out

## Top rows for the label above the head (cfg.breakdown_rows_above_head).
static func top_rows(rows: Array, n: int) -> Array:
	return rows.slice(0, mini(n, rows.size()))

# ------------------------------------------------------------------ AoE
## Per-dummy table: [{dummy, damage, share, dps, hits}] for dummies 1..count.
static func per_dummy(events: Array, count: int, duration: float) -> Array:
	var rows := []
	for d in range(1, count + 1):
		rows.append({"dummy": d, "damage": 0.0, "hits": 0, "share": 0.0, "dps": 0.0})
	for e in events:
		var d := int(e.get("dummy", 1))
		if d >= 1 and d <= count:
			rows[d - 1]["damage"] += float(e["amount"])
			if event_is_direct(e):
				rows[d - 1]["hits"] += 1
	var total := total_damage(events)
	for r in rows:
		r["share"] = (float(r["damage"]) / total * 100.0) if total > 0.0 else 0.0
		r["dps"] = float(r["damage"]) / duration if duration > 0.0 else 0.0
	return rows

## Average number of distinct dummies each cast damaged (direct hits only). Returns -1.0
## when no event carries a cast id (the stat is then shown as unavailable).
static func targets_per_cast(events: Array) -> float:
	var casts := {}
	for e in direct_events(events):
		var c := int(e.get("cast_id", -1))
		if c < 0:
			continue
		if not casts.has(c):
			casts[c] = {}
		casts[c][int(e.get("dummy", 1))] = true
	if casts.is_empty():
		return -1.0
	var sum := 0
	for c in casts:
		sum += casts[c].size()
	return float(sum) / float(casts.size())

# ------------------------------------------------------------------ full result
## Everything the panel and the head label need, computed from a finished (or running) run.
static func build_result(run: Dictionary, names: Dictionary, cfg: Dictionary) -> Dictionary:
	var ev: Array = run["events"]
	var dur := float(run["duration"])
	var pk := peak_window(ev, float(cfg.get("peak_window", 1.0)))
	var res := {
		"settings": run["settings"].duplicate(),
		"duration": dur,
		"dev": bool(run.get("dev", false)),
		"total": total_damage(ev),
		"avg_dps": average_dps(ev, dur),
		"peak_dps": pk["dps"],
		"peak_start": pk["start"],
		"hits": direct_hits(ev),
		"crit_rate": crit_rate(ev),
		"avg_hit": average_hit(ev),
		"biggest_hit": biggest_hit(ev),
		"poise_breaks": int(run.get("poise_breaks", 0)),
		"breakdown": breakdown(ev, dur, names, cfg),
	}
	if run["settings"].get("type", "single") == "aoe":
		res["per_dummy"] = per_dummy(ev, int(run.get("dummies", 3)), dur)
		res["targets_per_cast"] = targets_per_cast(ev)
	return res

# ------------------------------------------------------------------ comparisons and history
## Results are comparable only if type, duration, counting and profile match, plus the
## spacing for AoE, and both are DEV or both are not.
static func comparable(a: Dictionary, b: Dictionary) -> bool:
	var sa: Dictionary = a.get("settings", {})
	var sb: Dictionary = b.get("settings", {})
	for k in ["type", "duration", "counting", "profile"]:
		if sa.get(k) != sb.get(k):
			return false
	if sa.get("type") == "aoe" and sa.get("spacing") != sb.get("spacing"):
		return false
	return bool(a.get("dev", false)) == bool(b.get("dev", false))

## Percentage change in average DPS against the most recent comparable result in
## `history` (newest first). {"comparable": bool, "pct": float, "prev_dps": float}.
## `skip` leaves out the first N entries (use 1 to compare a history entry with the ones before it).
static func delta_vs_history(result: Dictionary, history: Array, skip: int = 0) -> Dictionary:
	for i in range(skip, history.size()):
		var h: Dictionary = history[i]
		if comparable(result, h):
			var prev := float(h.get("avg_dps", 0.0))
			if prev <= 0.0:
				return {"comparable": false, "pct": 0.0, "prev_dps": prev}
			return {"comparable": true, "pct": (float(result["avg_dps"]) - prev) / prev * 100.0, "prev_dps": prev}
	return {"comparable": false, "pct": 0.0, "prev_dps": 0.0}

## The most recent entry after `skip` that is comparable with `result`, or {}.
static func previous_comparable(result: Dictionary, history: Array, skip: int = 0) -> Dictionary:
	for i in range(skip, history.size()):
		if comparable(result, history[i]):
			return history[i]
	return {}

## New list with `entry` first, capped at `size`; the oldest entry drops off.
static func push_history(history: Array, entry: Dictionary, size: int) -> Array:
	var out := [entry]
	out.append_array(history)
	if out.size() > size:
		out.resize(size)
	return out

# ------------------------------------------------------------------ text
## 6980 -> "6,980"
static func fmt_num(v: float) -> String:
	var n := int(round(v))
	var neg := n < 0
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if neg else "") + out

static func fmt_delta(d: Dictionary) -> String:
	if not d.get("comparable", false):
		return "not comparable"
	return "%+d%% vs previous" % int(round(float(d["pct"])))

## One-line settings text, for example "10 s · All sources · No defences" (AoE adds the spacing).
static func settings_text(s: Dictionary, cfg: Dictionary, dev: bool = false) -> String:
	var lab: Dictionary = cfg.get("labels", {})
	var parts := ["%d s" % int(s.get("duration", 10)),
		str(lab.get("counting", {}).get(s.get("counting", "all"), "All sources")),
		str(cfg.get("profiles", {}).get(s.get("profile", "none"), {}).get("label", "No defences"))]
	if s.get("type", "single") == "aoe":
		parts.insert(0, "AoE x3 " + str(s.get("spacing", "tight")))
	if dev:
		parts.append(str(lab.get("dev", "DEV")))
	return " · ".join(parts)

# ------------------------------------------------------------------ defence profiles
## Armour, resistances and (for bosses) the life used for poise, computed with the same
## scaling as enemy.gd / dungeon.gd so balance changes carry over:
##   armour = def.armour * (1 + 0.12 * (lvl - 1)),  life = def.life * (1 + 0.28 * (lvl - 1)) * dungeon.life_mult
##   resist[el] = def.resist[el] + dungeon.resist_bonus   (fire, cold, lightning, void)
## The level is the dungeon's monster level for this character: clamp(max(char level, min), min, max),
## +1 for the boss. "normal" averages the dungeon's non-boss pool weighted by spawn weight, "boss" uses the dungeon's boss.
## Returns {armour, resist, life, level, poise}. A profile without "tier" has no defences.
static func profile_defence(profile: Dictionary, dungeons: Array, enemies: Dictionary, ch_level: int) -> Dictionary:
	var out := {"armour": 0.0, "resist": {}, "life": 0.0, "level": 0, "poise": bool(profile.get("poise", false))}
	if not profile.has("tier"):
		return out
	var dg := {}
	for d in dungeons:
		if int(d.get("tier", 0)) == int(profile["tier"]):
			dg = d
			break
	if dg.is_empty():
		return out
	var lo := int(dg.get("min_level", 1))
	var hi := int(dg.get("max_level", 10))
	var lvl := clampi(maxi(ch_level, lo), lo, hi)
	# (enemy definition, spawn weight). A pool entry is {"id": ..., "w": ...} in dungeons.json;
	# a bare id counts as weight 1. The normal profile averages the non-boss pool by spawn weight.
	var defs := []
	if profile.get("kind", "normal") == "boss":
		lvl += 1
		var bd: Dictionary = enemies.get(str(dg.get("boss", "")), {})
		if not bd.is_empty():
			defs.append([bd, 1.0])
	else:
		for entry in dg.get("pool", []):
			var id: String = str(entry.get("id", "")) if typeof(entry) == TYPE_DICTIONARY else str(entry)
			var w: float = float(entry.get("w", 1.0)) if typeof(entry) == TYPE_DICTIONARY else 1.0
			var e: Dictionary = enemies.get(id, {})
			if not e.is_empty() and w > 0.0 and not e.get("boss", false) and not e.get("miniboss", false):
				defs.append([e, w])
	if defs.is_empty():
		return out
	var arm := 0.0
	var life := 0.0
	var wsum := 0.0
	var res := {"fire": 0.0, "cold": 0.0, "lightning": 0.0, "void": 0.0}
	for pair in defs:
		var e: Dictionary = pair[0]
		var w: float = pair[1]
		wsum += w
		arm += float(e.get("armour", 0)) * w
		life += float(e.get("life", 1)) * w
		for el in res:
			res[el] += float(e.get("resist", {}).get(el, 0)) * w
	var rb := float(dg.get("resist_bonus", 0))
	out["level"] = lvl
	out["armour"] = arm / wsum * (1.0 + 0.12 * float(lvl - 1))
	out["life"] = life / wsum * (1.0 + 0.28 * float(lvl - 1)) * float(dg.get("life_mult", 1.0))
	for el in res:
		out["resist"][el] = res[el] / wsum + rb
	return out

## Damage a defender with `armour` and `resist` takes from rolled damage {type: amount}.
## Same maths as enemy.gd receive_hit (armour reduction for physical, clamped resistances,
## frailty -20 resist, taken multiplier). `reduction` is Combat.armour_reduction as a Callable.
static func mitigate(rolled: Dictionary, armour: float, resist: Dictionary, frailty: bool, taken_mult: float, reduction: Callable) -> float:
	var total := 0.0
	var shift := -20.0 if frailty else 0.0
	for t in rolled:
		var v: float = rolled[t]
		if t == "physical":
			v *= 1.0 - float(reduction.call(armour, v))
		else:
			v *= 1.0 - clampf(float(resist.get(t, 0)) + shift, -100.0, 90.0) / 100.0
		total += v
	return total * taken_mult

# ------------------------------------------------------------------ text for the head label and panel
static func _pct(v: float) -> String:
	return "%d%%" % int(round(v))

static func top_rows_text(rows: Array, n: int) -> String:
	var parts := []
	for r in top_rows(rows, n):
		parts.append("%s %s" % [r["label"], _pct(r["share"])])
	return " · ".join(parts)

## Lines drawn above dummy `idx` (1-based), top line first. `result` is the finished
## result ({} while idle or counting).
static func head_lines(run: Dictionary, result: Dictionary, idx: int, cfg: Dictionary) -> Array:
	if run.is_empty():
		return []
	if not run.get("started", false):
		return ["Hit me"]
	if not run.get("finished", false) or result.is_empty():
		return ["%.1f" % maxf(0.0, float(run["duration"]) - float(run["elapsed"]))]
	var st: Dictionary = result["settings"]
	var rows_n := int(cfg.get("breakdown_rows_above_head", 3))
	var line1 := "%s DPS   peak %s (%.1f s)" % [fmt_num(result["avg_dps"]), fmt_num(result["peak_dps"]), float(result["peak_start"])]
	var sett := settings_text(st, cfg, bool(result.get("dev", false)))
	var top := []   # one short line per breakdown row keeps the label narrow
	for r in top_rows(result["breakdown"], rows_n):
		top.append("%s %s" % [r["label"], _pct(r["share"])])
	if st.get("type", "single") != "aoe":
		return [line1, sett] + top
	var own := ""
	for r in result.get("per_dummy", []):
		if int(r["dummy"]) == idx:
			own = "%s DPS · %s" % [fmt_num(r["dps"]), _pct(r["share"])]
	if idx != 1:
		return [own]
	var total_line := "Total across %d targets: %s DPS · peak %s (%.1f s)" % [int(run.get("dummies", 3)), fmt_num(result["avg_dps"]), fmt_num(result["peak_dps"]), float(result["peak_start"])]
	return [total_line, sett] + top + [own]

## BBCode for the Result tab. `delta` comes from delta_vs_history (or {}).
static func result_text(res: Dictionary, cfg: Dictionary, delta: Dictionary) -> String:
	if res.is_empty():
		return "[color=#8a8494]No result yet. Spawn dummies, then hit one: the first hit starts the timer.[/color]"
	var st: Dictionary = res["settings"]
	var lines := []
	lines.append("[color=#c8a060]%s[/color]" % settings_text(st, cfg, bool(res.get("dev", false))))
	if st.get("type", "single") == "aoe":
		lines.append("[color=#ffd080]AoE results are not comparable with single-target results.[/color]")
	if res.get("dev", false):
		lines.append("[color=#ff8080]DEV: a damage-affecting developer flag was active during this test.[/color]")
	lines.append("")
	lines.append("[font_size=18]Average DPS  [color=#ffe080]%s[/color][/font_size]" % fmt_num(res["avg_dps"]))
	lines.append("Peak second  [color=#ffe080]%s[/color] DPS, starting at %.1f s" % [fmt_num(res["peak_dps"]), float(res["peak_start"])])
	if delta.size() > 0:
		lines.append("vs previous: [color=%s]%s[/color]" % ["#80e080" if delta.get("comparable", false) and float(delta["pct"]) >= 0.0 else "#ff9090" if delta.get("comparable", false) else "#8a8494", fmt_delta(delta)])
	lines.append("Total damage %s   Direct hits %s   Crit rate %s" % [fmt_num(res["total"]), fmt_num(res["hits"]), _pct(float(res["crit_rate"]) * 100.0)])
	lines.append("Average hit %s   Biggest hit %s" % [fmt_num(res["avg_hit"]), fmt_num(res["biggest_hit"])])
	if cfg.get("profiles", {}).get(st.get("profile", "none"), {}).get("poise", false):
		lines.append("Poise breaks %d" % int(res.get("poise_breaks", 0)))
	if st.get("type", "single") == "aoe":
		var tpc := float(res.get("targets_per_cast", -1.0))
		lines.append("Average targets hit per cast  %s" % ("%.2f" % tpc if tpc >= 0.0 else "[color=#8a8494]unavailable[/color]"))
		lines.append("")
		lines.append("[table=4][cell][b]Dummy[/b]  [/cell][cell][b]DPS[/b]  [/cell][cell][b]Share[/b]  [/cell][cell][b]Hits[/b][/cell]")
		for r in res.get("per_dummy", []):
			lines.append("[cell]%d  [/cell][cell]%s  [/cell][cell]%s  [/cell][cell]%d[/cell]" % [int(r["dummy"]), fmt_num(r["dps"]), _pct(r["share"]), int(r["hits"])])
		lines.append("[/table]")
	lines.append("")
	lines.append("[b]Damage by source[/b]")
	var tbl := ["[table=5][cell][b]Source[/b]  [/cell][cell][b]Damage[/b]  [/cell][cell][b]Share[/b]  [/cell][cell][b]DPS[/b]  [/cell][cell][b]Hits[/b][/cell]"]
	for r in res["breakdown"]:
		tbl.append("[cell]%s  [/cell][cell]%s  [/cell][cell]%.1f%%  [/cell][cell]%s  [/cell][cell]%s[/cell]" % [r["label"], fmt_num(r["damage"]), float(r["share_text"]), fmt_num(r["dps"]), fmt_num(r["hits"])])
	tbl.append("[/table]")
	lines.append("".join(tbl))
	return "\n".join(lines)

# ------------------------------------------------------------------ build snapshot and history rows
## "just now", "45 s ago", "12 min ago", "1 h 5 min ago" (game session time, not wall-clock dates).
static func fmt_ago(when: float, now: float) -> String:
	var s := int(maxf(0.0, now - when))
	if s < 5:
		return "just now"
	if s < 60:
		return "%d s ago" % s
	var mins := int(floor(float(s) / 60.0))
	if mins < 60:
		return "%d min ago" % mins
	return "%d h %d min ago" % [int(floor(float(mins) / 60.0)), mins % 60]

static func _or_none(v) -> String:
	var t := str(v)
	return t if t != "" else "none"

## Plain-text lines describing the build a result was made with. `snap` is what
## TrainingLog.build_snapshot() stored; an empty snapshot gives no lines.
static func snapshot_lines(snap: Dictionary) -> Array:
	if snap.is_empty():
		return []
	var who := "%s, level %d %s" % [str(snap.get("name", "?")), int(snap.get("level", 1)), str(snap.get("class", "")).capitalize()]
	if str(snap.get("spec", "")) != "":
		who += ", " + str(snap["spec"])
	var bar := []
	for n in snap.get("hotbar_names", []):
		if str(n) != "":
			bar.append(str(n))
	return [who,
		"Main hand: %s   Off hand: %s" % [_or_none(snap.get("main_hand", "")), _or_none(snap.get("off_hand", ""))],
		"Hotbar: " + (", ".join(bar) if not bar.is_empty() else "empty"),
		"Allocated passives: %d" % int(snap.get("passives", 0))]

## What differs between a newer snapshot `a` and an older one `b`, as short phrases.
## Empty when either has no snapshot or nothing changed.
static func snapshot_changes(a: Dictionary, b: Dictionary) -> Array:
	var out := []
	if a.is_empty() or b.is_empty():
		return out
	if int(a.get("level", 0)) != int(b.get("level", 0)):
		out.append("level %d to %d" % [int(b.get("level", 0)), int(a.get("level", 0))])
	if str(a.get("spec", "")) != str(b.get("spec", "")):
		out.append("specialisation %s to %s" % [_or_none(b.get("spec", "")), _or_none(a.get("spec", ""))])
	if str(a.get("main_hand", "")) != str(b.get("main_hand", "")):
		out.append("main hand %s to %s" % [_or_none(b.get("main_hand", "")), _or_none(a.get("main_hand", ""))])
	if str(a.get("off_hand", "")) != str(b.get("off_hand", "")):
		out.append("off hand %s to %s" % [_or_none(b.get("off_hand", "")), _or_none(a.get("off_hand", ""))])
	var ha: Array = a.get("hotbar_names", [])
	var hb: Array = b.get("hotbar_names", [])
	for i in maxi(ha.size(), hb.size()):
		var x := str(ha[i]) if i < ha.size() else ""
		var y := str(hb[i]) if i < hb.size() else ""
		if x != y:
			out.append("slot %d %s to %s" % [i + 1, _or_none(y), _or_none(x)])
	if int(a.get("passives", 0)) != int(b.get("passives", 0)):
		out.append("passives %d to %d" % [int(b.get("passives", 0)), int(a.get("passives", 0))])
	return out

## One History row, as two lines: [when, test type, average and peak DPS, change vs the
## previous comparable entry] and the settings text (duration, counting, profile, spacing, DEV).
static func history_row_lines(entry: Dictionary, delta: Dictionary, now: float, cfg: Dictionary) -> Array:
	var st: Dictionary = entry["settings"]
	var kind := "AoE" if st.get("type", "single") == "aoe" else "Single"
	var parts := [fmt_ago(float(entry.get("when", 0.0)), now), kind,
			"%s DPS" % fmt_num(entry["avg_dps"]), "peak %s" % fmt_num(entry["peak_dps"])]
	if delta.size() > 0:
		parts.append(fmt_delta(delta))
	return [" · ".join(parts), settings_text(st, cfg, bool(entry.get("dev", false)))]

## BBCode shown when a History row is expanded: the full result, the build it was made
## with and what changed since the previous comparable entry.
static func history_detail_text(entry: Dictionary, delta: Dictionary, prev_snapshot: Dictionary, cfg: Dictionary) -> String:
	var out := result_text(entry, cfg, delta)
	var snap: Dictionary = entry.get("snapshot", {})
	var lines := snapshot_lines(snap)
	if not lines.is_empty():
		out += "\n\n[b]Build when tested[/b]\n" + "\n".join(lines)
		var ch := snapshot_changes(snap, prev_snapshot)
		if not ch.is_empty():
			out += "\n[color=#ffd080]Changed since the previous comparable test: " + "; ".join(ch) + "[/color]"
	return out
