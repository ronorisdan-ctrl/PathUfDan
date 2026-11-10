extends RefCounted
## Endgame Phase 0 spike: chamber-stitched zone generator.
##
## A zone is a handful of large chambers on a macro grid (one chamber per macro cell),
## joined by wide drunkard's-walk connectors. Chambers are carved by cellular automata
## (organic caves / gardens) or BSP (ruined halls); the boss chamber is the authored arena
## template from data/rooms.json and is always a leaf of the chamber tree, so sealing it
## never cuts another chamber off. A flood fill from the start removes every pocket the
## player cannot reach.
##
## The result uses the same layout format as dungeon_gen.gd (w, h, grid, rooms, start, boss),
## so dungeon.gd runs it unchanged, plus zone data for local pathing and pack sleeping:
##   cell_chamber  PackedByteArray, chamber (room) id per cell, 255 = none
##   adjacency     Array, room id -> Array of linked room ids
##   macro_cell    int, macro cell size in cells
## Settings: the "gen" block of a zone def in data/zones.json. Same seed -> same zone.

const NONE := 255
const DIRS4 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var rng := RandomNumberGenerator.new()
var g := {}
var _room_fill := 0.6
var stats := {}     # diagnostics of the last successful generate() (tests / bench)

func generate(def: Dictionary, seed_value: int) -> Dictionary:
	rng.seed = seed_value
	g = def.get("gen", {})
	for attempt in 16:
		var r := _try_generate()
		if not r.is_empty():
			r["attempts"] = attempt + 1
			return r
	push_error("Zone generation failed repeatedly (seed %d)" % seed_value)
	return {}

func _gi(key: String, fallback: int) -> int:
	return int(g.get(key, fallback))

func _range(v, lo: int, hi: int) -> int:
	if typeof(v) == TYPE_ARRAY and v.size() >= 2:
		return rng.randi_range(int(v[0]), int(v[1]))
	return rng.randi_range(lo, hi)

# ------------------------------------------------------------------ main pass
func _try_generate() -> Dictionary:
	var mc := _gi("macro_cols", 4)
	var mr := _gi("macro_rows", 3)
	var cs := _gi("macro_cell", 44)
	var w := mc * cs + 2
	var h := mr * cs + 2
	var grid := PackedByteArray()
	grid.resize(w * h)
	grid.fill(0)
	var n_normal := _range(g.get("chambers"), 5, 7)
	var total := mini(n_normal + 2, mc * mr)
	# --- chamber tree over the macro grid (biased to the right, like dungeon_gen)
	var start := Vector2i(0, rng.randi_range(0, mr - 1))
	var depth := {start: 0}
	var order := [start]
	var edges := []
	var guard := 0
	while order.size() < total and guard < 800:
		guard += 1
		var from: Vector2i = order[rng.randi() % order.size()]
		var d: Vector2i = DIRS4[rng.randi() % 4] if rng.randf() < 0.6 else Vector2i(1, 0)
		var to: Vector2i = from + d
		if to.x < 0 or to.y < 0 or to.x >= mc or to.y >= mr or depth.has(to):
			continue
		depth[to] = int(depth[from]) + 1
		order.append(to)
		edges.append([from, to])
	if order.size() < total:
		return {}
	# the deepest cell is always a leaf: it becomes the boss arena
	var boss: Vector2i = order[order.size() - 1]
	for c in order:
		if int(depth[c]) > int(depth[boss]) or (int(depth[c]) == int(depth[boss]) and c.x > boss.x):
			boss = c
	if boss == start:
		return {}
	# --- extra links (loops make the zone feel open); never into the boss arena
	var linked := {}
	for e in edges:
		linked[_edge_key(e[0], e[1])] = true
	var loops := 0
	var want := _gi("extra_links", 1)
	var tries := 0
	while loops < want and tries < 60:
		tries += 1
		var a: Vector2i = order[rng.randi() % order.size()]
		var b: Vector2i = a + DIRS4[rng.randi() % 4]
		if not depth.has(b) or a == boss or b == boss or linked.has(_edge_key(a, b)):
			continue
		linked[_edge_key(a, b)] = true
		edges.append([a, b])
		loops += 1
	# --- carve chambers
	var rooms := []
	var index := {}
	var bsp_share := float(g.get("bsp_share", 0.4))
	for c in order:
		var kind := "normal"
		var style := ""
		var local := {}
		if c == start:
			kind = "start"
			style = "clearing"
			local = _clearing_room(_range(g.get("start_size"), 14, 16))
		elif c == boss:
			kind = "boss"
			style = "arena"
			local = _template_room(Data.rooms.get("arena", []))
		else:
			var lw := _range(g.get("chamber_size"), 30, 40)
			var lh := _range(g.get("chamber_size"), 30, 40)
			if rng.randf() < bsp_share:
				style = "bsp"
				local = _bsp_room(lw, lh, g.get("bsp", {}))
			else:
				style = "ca"
				local = _ca_room(lw, lh, g.get("ca", {}))
		if local.is_empty():
			return {}
		var lw2: int = local["w"]
		var lh2: int = local["h"]
		# keep `chamber_margin` cells of rock to the macro cell edge, so chambers that are not
		# linked never sit behind a wall thin enough for packs to notice the player through it
		var org := Vector2i(1 + c.x * cs, 1 + c.y * cs)
		var mg := _gi("chamber_margin", 3)
		var ox: int = org.x + rng.randi_range(mg, maxi(mg, cs - lw2 - mg))
		var oy: int = org.y + rng.randi_range(mg, maxi(mg, cs - lh2 - mg))
		var lg: PackedByteArray = local["grid"]
		var spawns := []
		for ty in lh2:
			for tx in lw2:
				var v := lg[ty * lw2 + tx]
				if v >= 1:
					grid[(oy + ty) * w + ox + tx] = 1
				if v == 2:
					spawns.append(Vector2i(ox + tx, oy + ty))
		var room := {"id": rooms.size(), "macro": c, "rect": Rect2i(ox, oy, lw2, lh2), "kind": kind, "style": style,
					"spawns": spawns, "anchor": Vector2i(ox + int(lw2 / 2.0), oy + int(lh2 / 2.0)), "depth": int(depth[c]),
					"visited": kind == "start", "cleared": kind == "start"}
		index[c] = room["id"]
		rooms.append(room)
	for r in rooms:
		r["anchor"] = _nearest_floor_in(grid, w, r["rect"], r["anchor"], true)
	# --- connectors
	var cw = g.get("connector", {})
	for e in edges:
		var ra: Dictionary = rooms[index[e[0]]]
		var rb: Dictionary = rooms[index[e[1]]]
		var pa := _nearest_floor_in(grid, w, ra["rect"], _rect_center(rb["rect"]), false)
		var pb := _nearest_floor_in(grid, w, rb["rect"], _rect_center(ra["rect"]), false)
		var ma := Rect2i(1 + e[0].x * cs, 1 + e[0].y * cs, cs, cs)
		var bound := ma.merge(Rect2i(1 + e[1].x * cs, 1 + e[1].y * cs, cs, cs)).grow(-1)
		_connector(grid, w, pa, pb, bound, _range(cw.get("width", [4, 6]), 4, 6), float(cw.get("bias", 0.72)), int(cw.get("max_steps", 900)))
	# --- flood fill from the start; remove unreachable pockets
	var reach := _flood(grid, w, h, rooms[index[start]]["anchor"])
	var removed := 0
	for i in grid.size():
		if grid[i] == 1 and reach[i] == 0:
			grid[i] = 0
			removed += 1
	for r in rooms:
		var a2: Vector2i = r["anchor"]
		if grid[a2.y * w + a2.x] != 1:
			return {}
		r["spawns"] = r["spawns"].filter(func(s): return grid[s.y * w + s.x] == 1)
	# --- chamber map, adjacency, spawn points
	var cell_chamber := PackedByteArray()
	cell_chamber.resize(w * h)
	cell_chamber.fill(NONE)
	for y in h:
		for x in w:
			var m := Vector2i(clampi(int((x - 1) / float(cs)), 0, mc - 1), clampi(int((y - 1) / float(cs)), 0, mr - 1))
			if index.has(m):
				cell_chamber[y * w + x] = index[m]
	var adjacency := []
	for r in rooms:
		adjacency.append([])
	var room_edges := []
	for e in edges:
		var ia: int = index[e[0]]
		var ib: int = index[e[1]]
		adjacency[ia].append(ib)
		adjacency[ib].append(ia)
		room_edges.append([ia, ib])
	var min_floor := _gi("min_chamber_floor", 260)
	for r in rooms:
		if r["kind"] != "normal":
			continue
		var fc := _floor_count(grid, w, r["rect"])
		r["floor"] = fc
		if fc < min_floor:
			return {}
		r["spawns"] = _pick_spawns(grid, w, r["rect"], _gi("spawn_spacing", 7), rooms[index[start]]["anchor"])
		if r["spawns"].size() < 3:
			return {}
	var floor_total := 0
	for v in grid:
		floor_total += v
	stats = {"chambers": rooms.size(), "normal": n_normal, "loops": loops, "removed_cells": removed, "floor": floor_total}
	return {"w": w, "h": h, "grid": grid, "rooms": rooms, "start": index[start], "boss": index[boss],
			"zone": true, "cell_chamber": cell_chamber, "adjacency": adjacency, "edges": room_edges,
			"macro_cell": cs, "stats": stats}

func _edge_key(a: Vector2i, b: Vector2i) -> String:
	if a.x > b.x or (a.x == b.x and a.y > b.y):
		var t := a
		a = b
		b = t
	return "%d,%d-%d,%d" % [a.x, a.y, b.x, b.y]

func _rect_center(r: Rect2i) -> Vector2i:
	return r.position + r.size / 2

# ------------------------------------------------------------------ chamber styles
## Local chamber grids: 0 wall, 1 floor, 2 floor + spawn mark. Border cells stay wall.

func _ca_room(lw: int, lh: int, cfg: Dictionary) -> Dictionary:
	var fill := float(cfg.get("fill", 0.53))
	var steps := int(cfg.get("steps", 5))
	var birth := int(cfg.get("birth", 5))
	var survive := int(cfg.get("survive", 4))
	var min_floor := float(cfg.get("min_floor", 0.38))
	for attempt in 8:
		var a := PackedByteArray()
		a.resize(lw * lh)
		var cx := (lw - 1) / 2.0
		var cy := (lh - 1) / 2.0
		for y in lh:
			for x in lw:
				var nx := (x - cx) / (lw / 2.0 - 1.0)
				var ny := (y - cy) / (lh / 2.0 - 1.0)
				var inside := nx * nx + ny * ny <= 1.0
				# open middle, rough edge: the ellipse keeps chambers from reading as rectangles
				var p := fill + (0.12 if nx * nx + ny * ny < 0.25 else 0.0)
				a[y * lw + x] = 1 if inside and rng.randf() < p else 0
		for s in steps:
			var b := PackedByteArray()
			b.resize(lw * lh)
			for y in lh:
				for x in lw:
					if x == 0 or y == 0 or x == lw - 1 or y == lh - 1:
						b[y * lw + x] = 0
						continue
					var walls := 0
					for dy in range(-1, 2):
						for dx in range(-1, 2):
							if (dx != 0 or dy != 0) and a[(y + dy) * lw + x + dx] == 0:
								walls += 1
					var wall_now := a[y * lw + x] == 0
					b[y * lw + x] = 0 if walls >= birth or (wall_now and walls >= survive) else 1
			a = b
		a = _largest_region(a, lw, lh)
		var cnt := 0
		for v in a:
			cnt += v
		if cnt >= min_floor * lw * lh * 0.785:
			return {"w": lw, "h": lh, "grid": a}
	return {}

func _bsp_room(lw: int, lh: int, cfg: Dictionary) -> Dictionary:
	var min_leaf := int(cfg.get("min_leaf", 10))
	var margin := int(cfg.get("margin", 1))
	var corr := int(cfg.get("corridor", 3))
	var erode := float(cfg.get("erode", 0.08))
	var pillars := float(cfg.get("pillars", 0.012))
	var min_floor := float(cfg.get("min_floor", 0.30))
	for attempt in 8:
		var a := PackedByteArray()
		a.resize(lw * lh)
		a.fill(0)
		_room_fill = float(cfg.get("room_fill", 0.6))
		_bsp_split(a, lw, Rect2i(1, 1, lw - 2, lh - 2), min_leaf, margin, corr)
		# ruin: breaches in thin walls, rubble pillars in open floor
		for y in range(2, lh - 2):
			for x in range(2, lw - 2):
				var i := y * lw + x
				if a[i] == 0:
					var hz := a[i - 1] == 1 and a[i + 1] == 1
					var vt := a[i - lw] == 1 and a[i + lw] == 1
					if (hz or vt) and rng.randf() < erode:
						a[i] = 1
				elif rng.randf() < pillars and _open8(a, lw, x, y):
					a[i] = 0
		a = _largest_region(a, lw, lh)
		var cnt := 0
		for v in a:
			cnt += v
		if cnt >= min_floor * lw * lh:
			return {"w": lw, "h": lh, "grid": a}
	return {}

## Splits r recursively; carves one room per leaf and joins sibling subtrees with a corridor.
## Returns the centres of the rooms carved under r.
func _bsp_split(a: PackedByteArray, lw: int, r: Rect2i, min_leaf: int, margin: int, corr: int) -> Array:
	var can_x := r.size.x >= 2 * min_leaf
	var can_y := r.size.y >= 2 * min_leaf
	if not can_x and not can_y:
		var rw := rng.randi_range(mini(maxi(5, int(r.size.x * _room_fill)), r.size.x - 2 * margin), maxi(5, r.size.x - 2 * margin))
		var rh := rng.randi_range(mini(maxi(5, int(r.size.y * _room_fill)), r.size.y - 2 * margin), maxi(5, r.size.y - 2 * margin))
		rw = mini(rw, r.size.x)
		rh = mini(rh, r.size.y)
		var rx := r.position.x + rng.randi_range(0, r.size.x - rw)
		var ry := r.position.y + rng.randi_range(0, r.size.y - rh)
		for y in range(ry, ry + rh):
			for x in range(rx, rx + rw):
				a[y * lw + x] = 1
		return [Vector2i(rx + rw / 2, ry + rh / 2)]
	var split_x := can_x and (not can_y or r.size.x > r.size.y or (r.size.x == r.size.y and rng.randf() < 0.5))
	var left: Rect2i
	var right: Rect2i
	if split_x:
		var sx := rng.randi_range(min_leaf, r.size.x - min_leaf)
		left = Rect2i(r.position, Vector2i(sx, r.size.y))
		right = Rect2i(r.position + Vector2i(sx, 0), Vector2i(r.size.x - sx, r.size.y))
	else:
		var sy := rng.randi_range(min_leaf, r.size.y - min_leaf)
		left = Rect2i(r.position, Vector2i(r.size.x, sy))
		right = Rect2i(r.position + Vector2i(0, sy), Vector2i(r.size.x, r.size.y - sy))
	var ca := _bsp_split(a, lw, left, min_leaf, margin, corr)
	var cb := _bsp_split(a, lw, right, min_leaf, margin, corr)
	var best := [ca[0], cb[0]]
	var bd := 1 << 30
	for p in ca:
		for q in cb:
			var d: int = (p - q).length_squared()
			if d < bd:
				bd = d
				best = [p, q]
	_l_corridor(a, lw, best[0], best[1], corr)
	return ca + cb

func _l_corridor(a: PackedByteArray, lw: int, p: Vector2i, q: Vector2i, width: int) -> void:
	var lh := a.size() / lw
	var mid := Vector2i(q.x, p.y) if rng.randf() < 0.5 else Vector2i(p.x, q.y)
	for seg in [[p, mid], [mid, q]]:
		var s: Vector2i = seg[0]
		var t: Vector2i = seg[1]
		var c := s
		while true:
			for oy in range(-(width / 2), width - width / 2):
				for ox in range(-(width / 2), width - width / 2):
					var x := c.x + ox
					var y := c.y + oy
					if x >= 1 and y >= 1 and x < lw - 1 and y < lh - 1:
						a[y * lw + x] = 1
			if c == t:
				break
			c += Vector2i(signi(t.x - c.x), 0) if c.x != t.x else Vector2i(0, signi(t.y - c.y))

func _clearing_room(sz: int) -> Dictionary:
	var a := PackedByteArray()
	a.resize(sz * sz)
	var c := (sz - 1) / 2.0
	var rad := sz / 2.0 - 1.2
	for y in sz:
		for x in sz:
			var d := Vector2(x - c, y - c).length()
			a[y * sz + x] = 1 if d <= rad - rng.randf() * 1.2 else 0
	return {"w": sz, "h": sz, "grid": _largest_region(a, sz, sz)}

func _template_room(tpl: Array) -> Dictionary:
	if tpl.is_empty():
		return {}
	var th := tpl.size()
	var tw: int = String(tpl[0]).length()
	var a := PackedByteArray()
	a.resize(tw * th)
	for y in th:
		var row: String = tpl[y]
		for x in tw:
			var ch := row[x]
			a[y * tw + x] = 2 if ch == "S" else (1 if ch == "." else 0)
	return {"w": tw, "h": th, "grid": a}

# ------------------------------------------------------------------ connectors
## Drunkard's walk from a to b, biased towards b and clamped to `bound`, carving a square
## brush `width` cells wide. If the walk runs out of steps, an L-shaped line finishes it.
func _connector(grid: PackedByteArray, w: int, a: Vector2i, b: Vector2i, bound: Rect2i, width: int, bias: float, max_steps: int) -> void:
	var c := a
	var steps := 0
	while c != b and steps < max_steps:
		steps += 1
		_brush(grid, w, c, width, bound)
		var dv := b - c
		var step: Vector2i
		if rng.randf() < bias:
			var ax := absi(dv.x)
			var ay := absi(dv.y)
			if ax > 0 and (ay == 0 or rng.randf() < float(ax) / float(ax + ay)):
				step = Vector2i(signi(dv.x), 0)
			else:
				step = Vector2i(0, signi(dv.y))
		else:
			step = DIRS4[rng.randi() % 4]
		var n := c + step
		if bound.has_point(n):
			c = n
	while c != b:
		_brush(grid, w, c, width, bound)
		c += Vector2i(signi(b.x - c.x), 0) if c.x != b.x else Vector2i(0, signi(b.y - c.y))
	_brush(grid, w, b, width, bound)

func _brush(grid: PackedByteArray, w: int, c: Vector2i, width: int, bound: Rect2i) -> void:
	var lo := -(width / 2)
	var hi := width - width / 2
	for oy in range(lo, hi):
		for ox in range(lo, hi):
			var p := c + Vector2i(ox, oy)
			if bound.has_point(p):
				grid[p.y * w + p.x] = 1

# ------------------------------------------------------------------ helpers
func _largest_region(a: PackedByteArray, lw: int, lh: int) -> PackedByteArray:
	var label := PackedInt32Array()
	label.resize(lw * lh)
	label.fill(-1)
	var best_id := -1
	var best_n := 0
	var next := 0
	for i in a.size():
		if a[i] == 0 or label[i] >= 0:
			continue
		var q := [i]
		label[i] = next
		var head := 0
		while head < q.size():
			var k: int = q[head]
			head += 1
			var x := k % lw
			var y := k / lw
			for o in DIRS4:
				var nx: int = x + o.x
				var ny: int = y + o.y
				if nx < 0 or ny < 0 or nx >= lw or ny >= lh:
					continue
				var j := ny * lw + nx
				if a[j] != 0 and label[j] < 0:
					label[j] = next
					q.append(j)
		if q.size() > best_n:
			best_n = q.size()
			best_id = next
		next += 1
	var out := PackedByteArray()
	out.resize(lw * lh)
	for i in a.size():
		out[i] = a[i] if label[i] == best_id else 0
	return out

func _open8(a: PackedByteArray, lw: int, x: int, y: int) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if a[(y + dy) * lw + x + dx] == 0:
				return false
	return true

func _flood(grid: PackedByteArray, w: int, h: int, from: Vector2i) -> PackedByteArray:
	var seen := PackedByteArray()
	seen.resize(w * h)
	seen.fill(0)
	if grid[from.y * w + from.x] != 1:
		return seen
	seen[from.y * w + from.x] = 1
	var q := [from]
	var head := 0
	while head < q.size():
		var c: Vector2i = q[head]
		head += 1
		for o in DIRS4:
			var n: Vector2i = c + o
			if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
				continue
			var i := n.y * w + n.x
			if grid[i] == 1 and seen[i] == 0:
				seen[i] = 1
				q.append(n)
	return seen

func _nearest_floor_in(grid: PackedByteArray, w: int, r: Rect2i, target: Vector2i, clear: bool) -> Vector2i:
	var best := Vector2i(-1, -1)
	var bd := 1 << 30
	for pass_i in 2:
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				if grid[y * w + x] != 1:
					continue
				if clear and pass_i == 0 and not _open8(grid, w, x, y):
					continue
				var d := (x - target.x) * (x - target.x) + (y - target.y) * (y - target.y)
				if d < bd:
					bd = d
					best = Vector2i(x, y)
		if best.x >= 0:
			return best
	return _rect_center(r)

func _floor_count(grid: PackedByteArray, w: int, r: Rect2i) -> int:
	var n := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			n += grid[y * w + x]
	return n

## Pack spawn points: floor cells with a clear 5x5 around them, at least `spacing` apart.
func _pick_spawns(grid: PackedByteArray, w: int, r: Rect2i, spacing: int, avoid: Vector2i) -> Array:
	var cands := []
	for y in range(r.position.y + 2, r.end.y - 2):
		for x in range(r.position.x + 2, r.end.x - 2):
			var ok := true
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					if grid[(y + dy) * w + x + dx] != 1:
						ok = false
						break
				if not ok:
					break
			if ok:
				cands.append(Vector2i(x, y))
	# seeded shuffle (Array.shuffle uses the global RNG)
	for i in range(cands.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = cands[i]
		cands[i] = cands[j]
		cands[j] = t
	var out := []
	for c in cands:
		if (c - avoid).length_squared() < 144:
			continue
		var far := true
		for o in out:
			if (c - o).length_squared() < spacing * spacing:
				far = false
				break
		if far:
			out.append(c)
		if out.size() >= 16:
			break
	return out
