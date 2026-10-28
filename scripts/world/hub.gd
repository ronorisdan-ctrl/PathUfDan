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
	# Training Grounds: Drillmaster Rook spawns the test dummies (replaces the old fixed dummy)
	var npc: Dictionary = Data.training_cfg.get("npc", {})
	var npc_cell: Array = npc.get("cell", [14, 18])
	_station(cell_center(Vector2i(int(npc_cell[0]), int(npc_cell[1]))), str(npc.get("name", "Drillmaster Rook")), "training", str(npc.get("sprite", "drillmaster")), Color(str(npc.get("color", "#e0a050"))))
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

# ------------------------------------------------------------------ Training Grounds
## The dummies are plain actors in `enemies`, so every skill, projectile, minion, turret and mine
## finds them without any change to the targeting code. They exist only in the hub (never in a
## dungeon), they cannot die, and Dev "kill all" has no effect on them.
const TrainingDummy = preload("res://scripts/entities/training_dummy.gd")
const TrainingRules = preload("res://scripts/core/training_rules.gd")

var training_dummies := []

## Spawn button: replaces any existing dummies with the chosen set. Returns "" or the reason it was refused.
func training_spawn() -> String:
	if not TrainingLog.available():
		return "Training is switched off while the game is under test."
	var cfg: Dictionary = TrainingLog.cfg()
	var s: Dictionary = TrainingLog.settings
	var cell: Array = cfg.get("spawn_cell", [18, 18])
	var base := cell_center(Vector2i(int(cell[0]), int(cell[1])))
	var pts := []
	if s.get("type", "single") == "aoe":
		var side := float(cfg.get("cluster_spacing", {}).get(s.get("spacing", "tight"), 24))
		var r := side / sqrt(3.0)   # equilateral triangle around the spawn point, dummy 1 in front (north)
		for i in 3:
			pts.append(base + Vector2.RIGHT.rotated(deg_to_rad(-90.0 + 120.0 * i)) * r)
	else:
		pts.append(base)
	var npc_cell: Array = cfg.get("npc", {}).get("cell", [14, 18])
	var rook := cell_center(Vector2i(int(npc_cell[0]), int(npc_cell[1])))
	for p in pts:
		var open := true
		for o in [Vector2.ZERO, Vector2(8, 8), Vector2(-8, 8), Vector2(8, -8), Vector2(-8, -8)]:
			if is_solid(p + o):
				open = false
		if not open or not has_los(rook, p):
			return "No open floor for the dummies here (the cluster does not fit)."
	training_remove()
	var prof: Dictionary = cfg.get("profiles", {}).get(s.get("profile", "none"), {})
	var defence := TrainingRules.profile_defence(prof, Data.dungeon_list, Data.enemies, Game.ch.level if Game.ch != null else 1)
	TrainingLog.begin(pts.size())
	for i in pts.size():
		var d = TrainingDummy.new()
		d.level = self
		d.setup_dummy(i + 1, pts.size(), defence)
		d.position = pts[i]
		enemies.append(d)
		entity_layer.add_child(d)
		training_dummies.append(d)
	training_active = true
	return ""

## Reset button: clears the result and returns the dummies to idle, without moving them.
func training_reset() -> void:
	TrainingLog.reset_run()
	for d in training_dummies:
		if is_instance_valid(d):
			d.statuses.clear()

## Remove button: despawns the dummies; a running test is discarded (never added to history).
func training_remove() -> void:
	for d in training_dummies:
		enemies.erase(d)
		if is_instance_valid(d):
			d.queue_free()
	training_dummies.clear()
	training_active = false
	TrainingLog.discard()

func _exit_tree() -> void:
	TrainingLog.discard()   # leaving the hub discards a running test
