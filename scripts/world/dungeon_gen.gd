extends RefCounted
## Builds a dungeon layout from handcrafted room templates (data/rooms.json)
## arranged on a macro grid as a random tree, joined by corridors.
## A tree guarantees every room is reachable; a flood fill verifies it.

const CW := 26   # macro cell width (tiles)
const CH := 22   # macro cell height
const MW := 5
const MH := 4

var rng := RandomNumberGenerator.new()

func generate(def: Dictionary, seed_value: int) -> Dictionary:
	rng.seed = seed_value
	for attempt in 8:
		var r := _try_generate(def)
		if not r.is_empty():
			return r
	push_error("Dungeon generation failed repeatedly")
	return {}

func _try_generate(def: Dictionary) -> Dictionary:
	var w := MW * CW + 4
	var h := MH * CH + 4
	var grid := PackedByteArray()
	grid.resize(w * h)
	grid.fill(0)
	var nr: Array = def.get("rooms", [7, 9])
	var n := rng.randi_range(int(nr[0]), int(nr[1]))
	# --- grow a random tree over the macro grid
	var start := Vector2i(0, rng.randi_range(0, MH - 1))
	var cells := {start: 0}
	var order := [start]
	var edges := []
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var guard := 0
	while order.size() < n and guard < 500:
		guard += 1
		var from: Vector2i = order[rng.randi() % order.size()]
		# bias growth to the right so the boss ends up far from the entrance
		var d: Vector2i = dirs[rng.randi() % 4] if rng.randf() < 0.6 else Vector2i(1, 0)
		var to: Vector2i = from + d
		if to.x < 0 or to.y < 0 or to.x >= MW or to.y >= MH or cells.has(to):
			continue
		cells[to] = int(cells[from]) + 1
		order.append(to)
		edges.append([from, to])
	if order.size() < 4:
		return {}
	# deepest room becomes the boss arena
	var boss: Vector2i = order[order.size() - 1]
	for c in order:
		if int(cells[c]) > int(cells[boss]) or (int(cells[c]) == int(cells[boss]) and c.x > boss.x):
			boss = c
	if boss == start:
		return {}
	var templates: Dictionary = Data.rooms.get("templates", {})
	var tkeys: Array = templates.keys()
	var rooms := []
	var index := {}
	for c in order:
		var kind := "normal"
		var tpl: Array
		if c == start:
			kind = "start"
			tpl = Data.rooms["start"]
		elif c == boss:
			kind = "boss"
			tpl = Data.rooms["arena"]
		else:
			tpl = templates[tkeys[rng.randi() % tkeys.size()]]
		tpl = _variant(tpl, kind == "normal")
		var th := tpl.size()
		var tw: int = tpl[0].length()
		var ox: int = 2 + c.x * CW + int((CW - tw) / 2.0) + rng.randi_range(-1, 1)
		var oy: int = 2 + c.y * CH + int((CH - th) / 2.0) + rng.randi_range(-1, 1)
		ox = clampi(ox, 1, w - tw - 1)
		oy = clampi(oy, 1, h - th - 1)
		var spawns := []
		var floor_cells := []
		for ty in th:
			var row: String = tpl[ty]
			for tx in tw:
				var chr := row[tx]
				if chr == "." or chr == "S":
					grid[(oy + ty) * w + ox + tx] = 1
					floor_cells.append(Vector2i(ox + tx, oy + ty))
				if chr == "S":
					spawns.append(Vector2i(ox + tx, oy + ty))
		var rect := Rect2i(ox, oy, tw, th)
		var center := Vector2i(ox + int(tw / 2.0), oy + int(th / 2.0))
		var anchor := _nearest_floor(floor_cells, center)
		var room := {"id": rooms.size(), "macro": c, "rect": rect, "kind": kind, "spawns": spawns,
					"anchor": anchor, "depth": int(cells[c]), "visited": kind == "start", "cleared": kind == "start"}
		index[c] = room["id"]
		rooms.append(room)
	# --- corridors
	for e in edges:
		var a: Dictionary = rooms[index[e[0]]]
		var b: Dictionary = rooms[index[e[1]]]
		_corridor(grid, w, a["anchor"], b["anchor"])
	# --- verify reachability
	var reach := _flood(grid, w, h, rooms[0]["anchor"])
	for r in rooms:
		if not reach.has(r["anchor"]):
			return {}
	return {"w": w, "h": h, "grid": grid, "rooms": rooms, "start": index[start], "boss": index[boss]}

func _variant(tpl: Array, allow: bool) -> Array:
	var out := tpl.duplicate()
	if not allow:
		return out
	if rng.randf() < 0.5:
		out.reverse()
	if rng.randf() < 0.5:
		var flipped := []
		for row in out:
			var s := ""
			for i in range(row.length() - 1, -1, -1):
				s += row[i]
			flipped.append(s)
		out = flipped
	return out

func _nearest_floor(cells: Array, c: Vector2i) -> Vector2i:
	var best := c
	var bd := 1 << 30
	for f in cells:
		var d: int = (f - c).length_squared()
		if d < bd:
			bd = d
			best = f
	return best

func _corridor(grid: PackedByteArray, w: int, a: Vector2i, b: Vector2i) -> void:
	var horizontal_first := rng.randf() < 0.5
	var mid := Vector2i(b.x, a.y) if horizontal_first else Vector2i(a.x, b.y)
	_line(grid, w, a, mid)
	_line(grid, w, mid, b)

func _line(grid: PackedByteArray, w: int, a: Vector2i, b: Vector2i) -> void:
	var x := a.x
	var y := a.y
	var steps := absi(b.x - a.x) + absi(b.y - a.y)
	for i in steps + 1:
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				var idx := (y + oy) * w + x + ox
				if idx >= 0 and idx < grid.size():
					grid[idx] = 1
		if x != b.x:
			x += signi(b.x - x)
		elif y != b.y:
			y += signi(b.y - y)

func _flood(grid: PackedByteArray, w: int, h: int, from: Vector2i) -> Dictionary:
	var seen := {from: true}
	var q := [from]
	var head := 0
	while head < q.size():
		var c: Vector2i = q[head]
		head += 1
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + o
			if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h or seen.has(n):
				continue
			if grid[n.y * w + n.x] == 1:
				seen[n] = true
				q.append(n)
	return seen
