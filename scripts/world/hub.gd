extends "res://scripts/world/level.gd"
## Ashfall Sanctuary - the safe hub: merchant, blacksmith, jeweller, stash,
## skill altar, pet keeper, training dummy and the dungeon gate.

const Portal = preload("res://scripts/world/portal.gd")

const LAYOUT := [
	"##################################",
	"##################################",
	"#########.................########",
	"######.......................#####",
	"####..........................####",
	"###............................###",
	"###............................###",
	"##..............................##",
	"##.......##..........##.........##",
	"##.......##..........##.........##",
	"##..............................##",
	"##..............................##",
	"##..............................##",
	"##..............................##",
	"##.......##..........##.........##",
	"##.......##..........##.........##",
	"###............................###",
	"###............................###",
	"####..........................####",
	"######......................######",
	"#########................#########",
	"##################################",
	"##################################",
]

func setup(ch) -> void:
	palette = "hub"
	is_town = true
	level_name = "Ashfall Sanctuary"
	allow_combat = false
	ambient = Color(0.62, 0.56, 0.52)
	init_grid(LAYOUT[0].length(), LAYOUT.size())
	for y in LAYOUT.size():
		for x in LAYOUT[y].length():
			if LAYOUT[y][x] == ".":
				set_cell(x, y, FLOOR)
	build_world()
	for c in [Vector2i(9, 7), Vector2i(22, 7), Vector2i(9, 13), Vector2i(22, 13), Vector2i(14, 1), Vector2i(19, 1)]:
		add_torch(c)
	var mid := cell_center(Vector2i(17, 11))
	spawn_player(ch, mid + Vector2(0, 40))
	_station(cell_center(Vector2i(17, 4)), "Dungeon Gate", "dungeon", "", Color("#c060ff"))
	_station(cell_center(Vector2i(6, 11)), "Merchant", "merchant", "npc_merchant", Color("#ffd070"))
	_station(cell_center(Vector2i(28, 11)), "Blacksmith", "blacksmith", "npc_smith", Color("#ff9050"))
	_station(cell_center(Vector2i(10, 17)), "Stash", "stash", "chest", Color("#e0c080"))
	_station(cell_center(Vector2i(24, 17)), "Skill Altar", "altar", "shrine", Color("#a080ff"))
	_station(cell_center(Vector2i(26, 5)), "Jeweller", "jeweller", "npc_jeweller", Color("#c080ff"))
	_station(cell_center(Vector2i(8, 5)), "Pet Keeper", "pets", "npc_petkeeper", Color("#90e070"))
	var dummy: Dictionary = Data.enemies.get("training_dummy", {})
	if not dummy.is_empty():
		spawn_enemy(dummy, ch.level, [], cell_center(Vector2i(17, 15)))
	add_ambient_particles(Color(0.9, 0.8, 0.7, 0.25))

func _station(pos: Vector2, nm: String, kind: String, spr: String, col: Color) -> void:
	var p = Portal.new()
	p.position = pos
	p.color = col
	p.label = nm + "  [F]"
	p.sprite_name = spr
	floor_layer.add_child(p)
	add_interactable(pos, nm, kind, 34.0)

func on_interact(it: Dictionary) -> void:
	if Game.main != null:
		Game.main.open_station(it["kind"])

func loot_bonus() -> float:
	return 0.0
