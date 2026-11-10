extends Node2D
## Draws the level grid once: flagstone floors, brick wall faces and dark wall tops.

var level = null
# Zones (Endgame Phase 0): the grid is drawn in chunks so Godot can cull off-screen ones.
# area = this chunk's cells (empty = whole grid, as in dungeons and the hub); rvals = the
# per-cell variant rolls of the whole grid, precomputed in the same order as the full draw.
var area := Rect2i()
var rvals := PackedFloat32Array()
var chunked := false

func _ready() -> void:
	queue_redraw()

func _draw() -> void:
	if level == null or chunked:
		return
	var pal: String = level.palette
	var T: int = level.T
	var tops: Texture2D = Art.wall_tile(pal, true)
	var face: Texture2D = Art.wall_tile(pal, false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var void_col: Color = Art.TILE_PALETTES.get(pal, Art.TILE_PALETTES["crypt"])["void"]
	if area.size != Vector2i.ZERO:
		_draw_area(pal, T, tops, face, void_col)
		return
	for y in level.gh:
		for x in level.gw:
			var p := Vector2(x * T, y * T)
			var v: int = level.cell(x, y)
			var r := rng.randf()
			if v == level.FLOOR:
				var variant := 0
				if r < 0.10:
					variant = 1
				elif r < 0.16:
					variant = 2
				elif r < 0.19:
					variant = 3
				draw_texture(Art.floor_tile(pal, variant), p)
				# soft shadow under the wall above
				if level.cell(x, y - 1) != level.FLOOR:
					draw_rect(Rect2(p, Vector2(T, 4)), Color(0, 0, 0, 0.35))
			else:
				if level.cell(x, y + 1) == level.FLOOR:
					draw_texture(face, p)
				elif level._near_floor(x, y):
					draw_texture(tops, p)
				else:
					draw_rect(Rect2(p, Vector2(T, T)), void_col)

func _draw_area(pal: String, T: int, tops: Texture2D, face: Texture2D, void_col: Color) -> void:
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var p := Vector2(x * T, y * T)
			var v: int = level.cell(x, y)
			var r: float = rvals[y * level.gw + x]
			if v == level.FLOOR:
				var variant := 0
				if r < 0.10:
					variant = 1
				elif r < 0.16:
					variant = 2
				elif r < 0.19:
					variant = 3
				draw_texture(Art.floor_tile(pal, variant), p)
				if level.cell(x, y - 1) != level.FLOOR:
					draw_rect(Rect2(p, Vector2(T, 4)), Color(0, 0, 0, 0.35))
			else:
				if level.cell(x, y + 1) == level.FLOOR:
					draw_texture(face, p)
				elif level._near_floor(x, y):
					draw_texture(tops, p)
				else:
					draw_rect(Rect2(p, Vector2(T, T)), void_col)
