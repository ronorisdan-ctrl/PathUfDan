extends RefCounted
## Endgame Phase 3C: the Burning Canvas (docs/ENDGAME_PHASE3.md Stage 3C, data/atlas.json
## mechanics.burning). Pure rules: the distance field the fire front follows, front speed, burn
## damage, Ash per kill, cistern placement. The dungeon (scripts/world/zone_fire.gd) owns the live
## state and passes its mech_rng stream in, so the main run stream is never touched.

const AtlasRules = preload("res://scripts/core/atlas_rules.gd")

static func cfg() -> Dictionary:
	return AtlasRules.mech_cfg().get("burning", {})

## Distance (4-way steps over floor cells, grid value 1) from `start` to every cell; -1 = unreachable.
static func dist_field(grid: PackedByteArray, w: int, h: int, start: Vector2i) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(w * h)
	dist.fill(-1)
	if start.x < 0 or start.y < 0 or start.x >= w or start.y >= h or grid[start.y * w + start.x] != 1:
		return dist
	var q := PackedInt32Array()
	q.resize(w * h)
	var head := 0
	var tail := 0
	var i0 := start.y * w + start.x
	dist[i0] = 0
	q[tail] = i0
	tail += 1
	while head < tail:
		var i: int = q[head]
		head += 1
		var x := i % w
		var y := int(i / w)
		var d := dist[i] + 1
		for n in [i - 1 if x > 0 else -1, i + 1 if x < w - 1 else -1, i - w if y > 0 else -1, i + w if y < h - 1 else -1]:
			if n >= 0 and dist[n] < 0 and grid[n] == 1:
				dist[n] = d
				q[tail] = n
				tail += 1
	return dist

## Speed multiplier from kills: 1 + min(kill_cap, kills x kill_speed), x the tuning's speed_mult.
static func kill_mult(kills: int, t: Dictionary) -> float:
	return (1.0 + minf(float(t.get("kill_cap", 0.5)), maxf(0, kills) * float(t.get("kill_speed", 0.005)))) * float(t.get("speed_mult", 1.0))

## Base front speed in cells per second: the arena distance in arena_time seconds.
static func base_speed(arena_d: int, t: Dictionary) -> float:
	return maxf(1.0, float(arena_d)) / maxf(1.0, float(t.get("arena_time", 170)))

## Fire damage per second on burnt floor at zone level `lvl` (before fire resistance).
static func dot_dps(lvl: int, t: Dictionary) -> float:
	var ref := float(t.get("ref_life_base", 0)) + float(t.get("ref_life_per_level", 30)) * lvl
	return maxf(0.0, float(t.get("dot_pct", 0.03)) * ref * float(t.get("dot_mult", 1.0)))

## Cisterns in a zone (base + Rot extra, at least 1 when the base is > 0 before modifiers).
static func cistern_count(rot: int, t: Dictionary) -> int:
	var n := int(t.get("cisterns", 2)) + (int(t.get("rot_cisterns", 1)) if rot > 0 else 0)
	return maxi(1, n)

## The depth fractions the cisterns sit at: cistern_at (trimmed or padded to the base count) plus
## rot_cistern_at for the Rot cistern, sorted.
static func cistern_fracs(rot: int, t: Dictionary) -> Array:
	var base := maxi(1, int(t.get("cisterns", 2)))
	var at: Array = t.get("cistern_at", [0.33, 0.67]).duplicate()
	var out := []
	if base == 1:
		out.append(0.5)
	else:
		for i in base:
			out.append(float(at[i]) if i < at.size() else float(i + 1) / float(base + 1))
	if rot > 0:
		for i in int(t.get("rot_cisterns", 1)):
			out.append(float(t.get("rot_cistern_at", 0.5)))
	out.sort()
	return out

## Where the front goes when a cistern is doused (never behind the entrance).
static func pushed(front: float, arena_d: int, t: Dictionary) -> float:
	return maxf(0.0, front - float(t.get("push_frac", 0.25)) * float(arena_d))

## Does this ground drop burn? kind: "item" (by rarity) or "gold"; everything else is safe.
static func burns(kind: String, rarity: String, t: Dictionary) -> bool:
	if kind == "gold":
		return bool(t.get("burn_gold", true))
	if kind == "item":
		return t.get("burn_rarities", ["common", "uncommon"]).has(rarity)
	return false

## Ash from one kill. ahead = the kill was within ahead_cells ahead of the front.
static func ash_for_kill(rng: RandomNumberGenerator, elite: bool, boss: bool, ahead: bool, t: Dictionary) -> int:
	var n := 0.0
	if boss:
		n = float(t.get("boss_ash", 3))
	elif elite:
		n = float(t.get("elite_ash", 1)) + (1.0 if rng.randf() < float(t.get("elite_ash_extra", 0.25)) else 0.0)
	else:
		n = 1.0 if rng.randf() < float(t.get("ash_chance", 0.25)) else 0.0
	if n <= 0.0:
		return 0
	if ahead:
		n *= float(t.get("ahead_mult", 2))
	var x := n * float(t.get("ash_mult", 1.0))
	return int(floor(x)) + (1 if rng.randf() < x - floor(x) else 0)
