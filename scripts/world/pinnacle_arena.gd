extends Node2D
## Endgame 3D: the live Overpainter fight in the Bare Ground (rules: scripts/core/pinnacle_rules.gd,
## numbers: data/atlas.json pinnacle). Owned by the dungeon (added to its floor layer at the world
## origin, so it draws in world coordinates). Wakes the boss after `wake_delay` s, paints the floor
## over in sections during phase 2 (Erasure), hurts the player on painted floor, restores the
## painted section nearest the player on a poise break, and keeps the run notes (phase reached,
## time per phase, sections painted / restored, poise breaks). Its own RNG stream: the main run
## stream is never touched.

const PinnacleRules = preload("res://scripts/core/pinnacle_rules.gd")

var dungeon = null
var centre := Vector2.ZERO
var tile := 16.0
var c := {}
var rng := RandomNumberGenerator.new()
var painted := []          # section indices painted over
var warn := -1             # section being painted (warning), -1 = none
var warn_t := 0.0
var paint_t := 0.0
var tick_t := 0.0
var wake_t := 1.5
var woke := false
var phase_idx := 0
var phase_t := [0.0, 0.0, 0.0]
var stats := {"painted": 0, "restored": 0, "breaks": 0, "paint_hits": 0, "phase": 1}

func setup(d, centre_world: Vector2, seed_value: int) -> void:
	dungeon = d
	centre = centre_world
	tile = 16.0   # level.gd T
	c = PinnacleRules.cfg()
	rng.seed = seed_value * 97 + 13
	wake_t = float(c.get("wake_delay", 1.5))
	paint_t = float(c.get("paint_every", 9.0)) * 0.5   # the first section comes sooner
	z_index = 0

func radius_px() -> float:
	return float(c.get("arena_radius", 12)) * tile

func safe_px() -> float:
	return float(c.get("safe_radius", 3)) * tile

func sections() -> int:
	return maxi(1, int(c.get("sections", 8)))

func section_at(p: Vector2) -> int:
	return PinnacleRules.section_at(p - centre, tile)

func painted_at(p: Vector2) -> bool:
	var s := section_at(p)
	return s >= 0 and painted.has(s)

func warned_at(p: Vector2) -> bool:
	var s := section_at(p)
	return s >= 0 and s == warn

## Nearest standing spot that is neither painted nor about to be: the centre disc or the middle of
## a clean section (smartbot / tests).
func safe_point(from: Vector2) -> Vector2:
	var best := centre
	var bd := from.distance_to(centre) - safe_px() * 0.6
	var n := sections()
	for s in n:
		if painted.has(s) or s == warn:
			continue
		var a := (s + 0.5) * TAU / n
		var p := centre + Vector2.RIGHT.rotated(a) * (safe_px() + radius_px()) * 0.5
		var dd := from.distance_to(p)
		if dd < bd:
			bd = dd
			best = p
	return best

func boss():
	return dungeon.boss if dungeon != null and dungeon.boss != null and is_instance_valid(dungeon.boss) else null

func tick(delta: float) -> void:
	if dungeon == null or dungeon.boss_dead:
		return
	if not woke:
		wake_t -= delta
		if wake_t <= 0.0:
			woke = true
			dungeon._spawn_boss(dungeon.rooms[dungeon.layout["boss"]])
		return
	var b = boss()
	if b == null or not b.alive:
		return
	phase_t[clampi(phase_idx, 0, 2)] += delta
	if phase_idx == 1:   # Erasure: paint a section over every paint_every s (after a warning)
		if warn >= 0:
			warn_t -= delta
			if warn_t <= 0.0:
				if not painted.has(warn):
					painted.append(warn)
					stats["painted"] += 1
				warn = -1
				queue_redraw()
		else:
			paint_t -= delta
			if paint_t <= 0.0:
				paint_t = float(c.get("paint_every", 9.0))
				var s := PinnacleRules.next_section(painted, rng)
				if s >= 0:
					warn = s
					warn_t = float(c.get("paint_warn", 2.0))
					Events.message.emit("The Overpainter paints over the floor - move!", Color(str(c.get("colors", {}).get("warn", "#ffffff"))))
					queue_redraw()
	if not painted.is_empty():   # painted floor hurts (phases 2 and 3)
		tick_t -= delta
		if tick_t <= 0.0:
			tick_t = float(c.get("paint_tick", 0.5))
			var pl = dungeon.player
			if pl != null and is_instance_valid(pl) and pl.alive and painted_at(pl.global_position):
				var pk: Dictionary = Combat.enemy_packet(b, float(c.get("paint_mult", 0.15)))
				pk["is_attack"] = false
				pk["crit_chance"] = 0.0
				var total := [0.0, 0.0]
				for k in pk["dmg"]:
					total[0] += float(pk["dmg"][k][0])
					total[1] += float(pk["dmg"][k][1])
				pk["dmg"] = {str(c.get("paint_dtype", "void")): total}
				pk["status"] = [{"type": str(c.get("paint_status", "chill")), "chance": 100.0}] if str(c.get("paint_status", "")) != "" else []
				Combat.deal(pk, b, pl)
				stats["paint_hits"] += 1
	if warn >= 0:
		queue_redraw()

## The boss entered phase i (0-based).
func on_phase(i: int) -> void:
	phase_idx = i
	stats["phase"] = i + 1
	if i == 1:
		paint_t = minf(paint_t, float(c.get("paint_every", 9.0)) * 0.5)
	if i >= 2 and warn >= 0:   # Bare Canvas: no new sections (the one being painted is dropped)
		warn = -1
	queue_redraw()

## Poise broken: the painted section nearest the player is restored.
func on_stagger() -> void:
	stats["breaks"] += 1
	if painted.is_empty() or dungeon.player == null:
		return
	var s := PinnacleRules.nearest_painted(painted, dungeon.player.global_position - centre)
	if s >= 0:
		painted.erase(s)
		stats["restored"] += 1
		Events.message.emit("The paint lifts: a section of the floor is restored", Color("#e8d8a0"))
		queue_redraw()

## Run notes for the smartbot report.
func notes() -> Dictionary:
	return {"phase": int(stats["phase"]), "t1": snapped(phase_t[0], 0.1), "t2": snapped(phase_t[1], 0.1), "t3": snapped(phase_t[2], 0.1),
		"painted": int(stats["painted"]), "restored": int(stats["restored"]), "breaks": int(stats["breaks"]), "paint_hits": int(stats["paint_hits"])}

func marks() -> Array:
	return [{"pos": centre, "color": Color(str(c.get("colors", {}).get("hex", "#f4efe0")))}]

func _wedge(s: int, r0: float, r1: float) -> PackedVector2Array:
	var n := sections()
	var a0 := s * TAU / n
	var a1 := (s + 1) * TAU / n
	var pts := PackedVector2Array()
	var steps := 10
	for i in steps + 1:
		pts.append(centre + Vector2.RIGHT.rotated(lerpf(a0, a1, float(i) / steps)) * r1)
	for i in steps + 1:
		pts.append(centre + Vector2.RIGHT.rotated(lerpf(a1, a0, float(i) / steps)) * r0)
	return pts

func _draw() -> void:
	var col := Color(str(c.get("colors", {}).get("painted", "#f2eee2")))
	draw_arc(centre, safe_px(), 0, TAU, 32, Color(col.r, col.g, col.b, 0.25), 1.5)
	for s in painted:
		draw_colored_polygon(_wedge(int(s), safe_px(), radius_px()), Color(col.r, col.g, col.b, 0.55))
	if warn >= 0:
		var k := 0.35 + 0.35 * sin(Time.get_ticks_msec() / 90.0)
		var wc := Color(str(c.get("colors", {}).get("warn", "#ffffff")))
		var pts := _wedge(warn, safe_px(), radius_px())
		pts.append(pts[0])
		draw_polyline(pts, Color(wc.r, wc.g, wc.b, 0.5 + k), 2.0)
		draw_colored_polygon(_wedge(warn, safe_px(), radius_px()), Color(wc.r, wc.g, wc.b, 0.12 + 0.1 * k))
