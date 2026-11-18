extends RefCounted
## Endgame 3D: the Bare Ground, the Overpainter's round studio (data/atlas.json pinnacle).
## A fixed layout: one round arena of `arena_radius` tiles. Room 0 is the start (a small rect at
## the south edge, inside the arena); room 1 is the arena itself, kind "arena" (not "boss": the
## dungeon never wakes the boss by walking in; the pinnacle arena wakes it after a short delay).

const PAD := 3

func generate(def: Dictionary, _seed_value: int) -> Dictionary:
	var r := maxi(6, int(def.get("arena_radius", 12)))
	var w := 2 * (r + PAD) + 1
	var h := w
	var c := Vector2i(r + PAD, r + PAD)
	var grid := PackedByteArray()
	grid.resize(w * h)
	grid.fill(0)
	for y in h:
		for x in w:
			if Vector2(x - c.x, y - c.y).length() <= float(r) + 0.5:
				grid[y * w + x] = 1
	var south := Vector2i(c.x, c.y + r - 2)
	var start := {"id": 0, "macro": Vector2i(0, 1), "rect": Rect2i(c.x - 2, c.y + r - 4, 5, 4), "kind": "start", "spawns": [],
		"anchor": south, "depth": 0, "visited": true, "cleared": true}
	var arena := {"id": 1, "macro": Vector2i(0, 0), "rect": Rect2i(c.x - r, c.y - r, 2 * r + 1, 2 * r + 1), "kind": "arena", "spawns": [],
		"anchor": c, "depth": 1, "visited": false, "cleared": false}
	return {"w": w, "h": h, "grid": grid, "rooms": [start, arena], "start": 0, "boss": 1, "centre": c, "radius": r}
