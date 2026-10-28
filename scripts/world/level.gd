extends Node2D
## Base world: tile grid, rendering, wall collision, flow-field pathing,
## line of sight, spatial queries, loot and the entity layers.
## The hub and dungeons extend this.

const Player = preload("res://scripts/entities/player.gd")
const Enemy = preload("res://scripts/entities/enemy.gd")
const Boss = preload("res://scripts/entities/boss.gd")
const LootDrop = preload("res://scripts/entities/loot_drop.gd")
const Pet = preload("res://scripts/entities/pet.gd")
const PetRules = preload("res://scripts/core/pet_rules.gd")
const AoE = preload("res://scripts/entities/aoe.gd")
const VFX = preload("res://scripts/fx/vfx.gd")

const T := 16
const FLOOR := 1
const WALL := 0

var gw := 0
var gh := 0
var grid := PackedByteArray()
var palette := "crypt"
var level_name := ""
var allow_combat := true
var is_town := false
var ambient := Color(0.42, 0.40, 0.50)

var floor_layer: Node2D
var entity_layer: Node2D
var projectile_layer: Node2D
var fx_layer: Node2D
var tile_drawer: Node2D
var walls: StaticBody2D

var player = null
var pet = null          # cosmetic loot pet; never a target, never collides, never takes damage
var enemies := []
var training_active := false   # hub only: true while Training Grounds dummies exist (summon/deploy/buff skills work)
var allies := []
var loot := []
var interactables := []   # {pos, name, kind, radius}
var flow := PackedInt32Array()
var flow_origin := Vector2i(-999, -999)
var flow_timer := 0.0
var _unstick_t := 0.0
var kills := 0
var rng := RandomNumberGenerator.new()

func _init() -> void:
	floor_layer = Node2D.new()
	floor_layer.name = "Floor"
	entity_layer = Node2D.new()
	entity_layer.name = "Entities"
	entity_layer.y_sort_enabled = true
	projectile_layer = Node2D.new()
	projectile_layer.name = "Projectiles"
	fx_layer = Node2D.new()
	fx_layer.name = "FX"

func _ready() -> void:
	Events.enemy_killed.connect(_on_enemy_killed)

func init_grid(w: int, h: int) -> void:
	gw = w
	gh = h
	grid = PackedByteArray()
	grid.resize(w * h)
	grid.fill(WALL)

func set_cell(x: int, y: int, v: int) -> void:
	if x >= 0 and y >= 0 and x < gw and y < gh:
		grid[y * gw + x] = v

func cell(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= gw or y >= gh:
		return WALL
	return grid[y * gw + x]

func carve_rect(r: Rect2i) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			set_cell(x, y, FLOOR)

func to_cell(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / T)), int(floor(p.y / T)))

func cell_center(c: Vector2i) -> Vector2:
	return Vector2(c.x * T + T / 2.0, c.y * T + T / 2.0)

func is_solid(p: Vector2) -> bool:
	var c := to_cell(p)
	return cell(c.x, c.y) != FLOOR

# ------------------------------------------------------------------ build
func build_world() -> void:
	tile_drawer = load("res://scripts/world/tile_drawer.gd").new()
	tile_drawer.name = "Tiles"
	tile_drawer.z_index = -10
	tile_drawer.level = self
	add_child(tile_drawer)
	add_child(floor_layer)
	add_child(entity_layer)
	add_child(projectile_layer)
	add_child(fx_layer)
	floor_layer.z_index = -5
	projectile_layer.z_index = 5
	fx_layer.z_index = 10
	_build_walls()
	var cm := CanvasModulate.new()
	cm.color = ambient
	add_child(cm)

func _near_floor(x: int, y: int) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if cell(x + dx, y + dy) == FLOOR:
				return true
	return false

func _build_walls() -> void:
	walls = StaticBody2D.new()
	walls.collision_layer = 1
	walls.collision_mask = 0
	add_child(walls)
	for y in gh:
		var x := 0
		while x < gw:
			if cell(x, y) == WALL and _near_floor(x, y):
				var x0 := x
				while x < gw and cell(x, y) == WALL and _near_floor(x, y):
					x += 1
				var cs := CollisionShape2D.new()
				var sh := RectangleShape2D.new()
				sh.size = Vector2((x - x0) * T, T)
				cs.shape = sh
				cs.position = Vector2(x0 * T + (x - x0) * T / 2.0, y * T + T / 2.0)
				walls.add_child(cs)
			else:
				x += 1

func add_torch(c: Vector2i) -> void:
	var l := PointLight2D.new()
	l.texture = Art.light_tex
	l.color = Color("#ffa050")
	l.energy = 1.0
	l.texture_scale = 1.4
	l.position = cell_center(c) + Vector2(0, 4)
	add_child(l)
	var fl = load("res://scripts/world/flicker.gd").new()
	fl.light = l
	add_child(fl)
	var s := Sprite2D.new()
	s.texture = Art.sprite("torch")
	s.position = cell_center(c) + Vector2(0, 2)
	s.z_index = -4
	add_child(s)

func add_ambient_particles(col: Color) -> void:
	var p := CPUParticles2D.new()
	p.amount = 40
	p.lifetime = 6.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(360, 220)
	p.gravity = Vector2(0, -6)
	p.initial_velocity_min = 2
	p.initial_velocity_max = 8
	p.direction = Vector2(0.3, -1)
	p.spread = 60
	p.scale_amount_min = 1.0
	p.scale_amount_max = 1.5
	p.color = col
	p.local_coords = false
	p.z_index = 15
	if player != null:
		player.add_child(p)

# ------------------------------------------------------------------ player & spawns
func spawn_player(ch, pos: Vector2):
	player = Player.new()
	player.level = self
	player.setup(ch)
	player.position = pos
	allies.append(player)
	entity_layer.add_child(player)
	if not Events.pet_changed.is_connected(respawn_pet):
		Events.pet_changed.connect(respawn_pet)
	respawn_pet()
	return player

# ------------------------------------------------------------------ pet
## Pets are off in tests and bot runs (Game.testing) so results stay deterministic;
## pet tests switch them on with Game.pets_in_tests.
func pets_allowed() -> bool:
	return not Game.testing or Game.pets_in_tests

## (Re)creates the active pet next to the player. Called on spawn and whenever the
## active pet is swapped, upgraded or renamed. Any in-flight fetch is cancelled.
func respawn_pet() -> void:
	if pet != null and is_instance_valid(pet):
		pet.despawn()
	pet = null
	if player == null or not is_instance_valid(player) or not pets_allowed():
		return
	var id: String = player.ch.active_pet
	if id == "" or not player.ch.owns_pet(id):
		return
	pet = Pet.new()
	pet.setup(self, player, id)
	pet.position = player.global_position + Vector2(-14, 6)
	entity_layer.add_child(pet)

## enemy_run holds the tier / run-modifier multipliers applied to every spawn
var enemy_run := {}

func spawn_enemy(def: Dictionary, lvl: int, mods: Array, pos: Vector2, run = null):
	var e
	if def.get("boss", false):
		e = Boss.new()
	else:
		e = Enemy.new()
	e.level = self
	e.setup(def, lvl, mods, enemy_run if run == null else run)
	e.position = pos
	enemies.append(e)
	entity_layer.add_child(e)
	return e

func add_fx(n: Node) -> void:
	fx_layer.add_child(n)

func shake(a: float) -> void:
	if player != null and is_instance_valid(player):
		player.shake(a)

# ------------------------------------------------------------------ queries
func hostiles_of(faction: String) -> Array:
	return enemies if faction == "player" else allies

func hostiles_in_radius(pos: Vector2, r: float, faction: String) -> Array:
	var out := []
	for e in hostiles_of(faction):
		if is_instance_valid(e) and e.alive and e.global_position.distance_to(pos) <= r + e.radius:
			out.append(e)
	return out

func enemies_in_cone(pos: Vector2, dir: Vector2, rng_d: float, arc_deg: float) -> Array:
	var out := []
	var half := deg_to_rad(arc_deg) / 2.0
	for e in enemies:
		if not is_instance_valid(e) or not e.alive:
			continue
		var to: Vector2 = e.global_position + Vector2(0, -4) - pos
		var d := to.length()
		if d > rng_d + e.radius:
			continue
		if d < e.radius + 4 or absf(dir.angle_to(to)) <= half:
			out.append(e)
	return out

func nearest_hostile(pos: Vector2, faction: String, maxd: float, exclude: Dictionary = {}, need_los: bool = false):
	var best = null
	var bd := maxd
	for e in hostiles_of(faction):
		if not is_instance_valid(e) or not e.alive or exclude.has(e.get_instance_id()):
			continue
		var d: float = e.global_position.distance_to(pos)
		if d < bd:
			if need_los and not has_los(pos, e.global_position):
				continue
			bd = d
			best = e
	return best

func is_isolated(e, r: float) -> bool:
	for o in enemies:
		if o != e and is_instance_valid(o) and o.alive and o.global_position.distance_to(e.global_position) < r:
			return false
	return true

func has_los(a: Vector2, b: Vector2) -> bool:
	var d := a.distance_to(b)
	var steps := int(d / 6.0)
	for i in range(1, steps):
		if is_solid(a.lerp(b, float(i) / steps)):
			return false
	return true

func clamp_to_floor(from: Vector2, to: Vector2) -> Vector2:
	var d := from.distance_to(to)
	var steps := maxi(1, int(d / 4.0))
	var last := from
	for i in range(1, steps + 1):
		var p := from.lerp(to, float(i) / steps)
		if is_solid(p) or is_solid(p + Vector2(4, 0)) or is_solid(p - Vector2(4, 0)) or is_solid(p + Vector2(0, 4)):
			return last
		last = p
	return last

## Pushes an actor that physics recovery shoved into a wall back onto the nearest floor.
func unstick(a) -> void:
	if not is_solid(a.global_position):
		return
	var c := to_cell(a.global_position)
	var best := Vector2i(-1, -1)
	var bd := 1 << 30
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var n := c + Vector2i(dx, dy)
			if cell(n.x, n.y) == FLOOR:
				var d := dx * dx + dy * dy
				if d < bd:
					bd = d
					best = n
	if best.x < 0:
		best = nearest_floor(c)   # deep in rock or outside the grid: search wider
	if best.x >= 0:
		# small spread so that two actors stuck together are not dropped on the same point
		# (overlapping bodies push each other back through the wall strip, over and over)
		_unstick_n += 1
		a.global_position = cell_center(best) + Vector2.RIGHT.rotated(_unstick_n * 2.39996) * 4.0

var _unstick_n := 0

## Nearest FLOOR cell to c by expanding square rings (c may lie outside the grid).
## Returns (-1, -1) only if the map has no floor at all.
func nearest_floor(c: Vector2i) -> Vector2i:
	var cx := clampi(c.x, 0, gw - 1)
	var cy := clampi(c.y, 0, gh - 1)
	for r in range(0, maxi(gw, gh)):
		var best := Vector2i(-1, -1)
		var bd := 1 << 30
		for y in range(cy - r, cy + r + 1):
			for x in range(cx - r, cx + r + 1):
				if maxi(absi(x - cx), absi(y - cy)) != r:
					continue
				if cell(x, y) == FLOOR:
					var d := (x - c.x) * (x - c.x) + (y - c.y) * (y - c.y)
					if d < bd:
						bd = d
						best = Vector2i(x, y)
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)

var _used_spawn := {}

func random_floor_near(c: Vector2i, rad: int) -> Vector2:
	var anchor_ok := cell(c.x, c.y) == FLOOR
	for i in 40:
		var x := c.x + rng.randi_range(-rad, rad)
		var y := c.y + rng.randi_range(-rad, rad)
		var key := Vector2i(x, y)
		if _used_spawn.has(key) and i < 30:
			continue
		# a straight floor line from the anchor keeps spawns on the anchor's side of thin walls
		if anchor_ok and key != c and not has_los(cell_center(c), cell_center(key)):
			continue
		if cell(x, y) == FLOOR and cell(x + 1, y) == FLOOR and cell(x, y + 1) == FLOOR and cell(x - 1, y) == FLOOR and cell(x, y - 1) == FLOOR:
			_used_spawn[key] = true
			return cell_center(key)
	return cell_center(c)

# ------------------------------------------------------------------ flow field
func _physics_process(delta: float) -> void:
	flow_timer -= delta
	if player != null and is_instance_valid(player) and player.alive:
		var pc := to_cell(player.global_position)
		if (pc != flow_origin and flow_timer <= 0) or flow_timer <= -1.0:
			_compute_flow(pc)
			flow_timer = 0.2
	_unstick_t -= delta
	if _unstick_t <= 0:
		_unstick_t = 0.25
		for e in enemies:
			if is_instance_valid(e) and e.alive:
				unstick(e)
		for a in allies:
			if is_instance_valid(a) and a.alive:
				unstick(a)

func _compute_flow(origin: Vector2i) -> void:
	flow_origin = origin
	if flow.size() != gw * gh:
		flow.resize(gw * gh)
	flow.fill(-1)
	if cell(origin.x, origin.y) != FLOOR:
		return
	var queue := [origin]
	flow[origin.y * gw + origin.x] = 0
	var head := 0
	var maxd := 90
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		var d: int = flow[c.y * gw + c.x]
		if d >= maxd:
			continue
		for o in dirs:
			var n: Vector2i = c + o
			if n.x < 0 or n.y < 0 or n.x >= gw or n.y >= gh:
				continue
			var idx := n.y * gw + n.x
			if grid[idx] == FLOOR and flow[idx] < 0:
				flow[idx] = d + 1
				queue.append(n)

func flow_dir(pos: Vector2) -> Vector2:
	if flow.size() != gw * gh:
		return Vector2.ZERO
	var c := to_cell(pos)
	var here := flow_value(c)
	if here < 0:
		return Vector2.ZERO
	var best := here
	var bestc := c
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var n := c + Vector2i(dx, dy)
			var v := flow_value(n)
			if v < 0:
				continue
			if dx != 0 and dy != 0 and (cell(c.x + dx, c.y) != FLOOR or cell(c.x, c.y + dy) != FLOOR):
				continue  # no corner cutting
			if v < best:
				best = v
				bestc = n
	if bestc == c:
		return (player.global_position - pos).normalized() if player != null else Vector2.ZERO
	return (cell_center(bestc) - pos).normalized()

func flow_value(c: Vector2i) -> int:
	if c.x < 0 or c.y < 0 or c.x >= gw or c.y >= gh:
		return -1
	return flow[c.y * gw + c.x]

# ------------------------------------------------------------------ loot
func _on_enemy_killed(e, killer) -> void:
	if e.level != self or player == null:
		return
	kills += 1
	var ch = player.ch
	ch.add_xp(int(e.xp_value * xp_bonus()))
	player.on_kill(e)
	var drops: Array = Loot.roll_drops(e.mlevel, e.loot_mult * loot_bonus(), e.is_elite or e.is_miniboss, e.is_boss, ch.class_id, ch.final.get("item_rarity", 0.0) + rarity_bonus())
	for d in drops:
		spawn_drop(d, e.global_position)
	# legendary on-kill effects
	if ch.stats.has_flag("ashheart") and e.has_status("ignite"):
		_effect_burst(e.global_position, {"fire": [e.max_life * 0.15, e.max_life * 0.2]}, Color("#ff7030"), 46)
	if ch.stats.has_flag("spreading_flames") and e.has_status("ignite"):
		var ig: Dictionary = e.statuses["ignite"]
		for o in hostiles_in_radius(e.global_position, 60.0, "player"):
			o.add_status("ignite", 3.0, {"dps": float(ig.get("dps", 1.0)), "dtype": "fire"})
		add_fx(VFX.make("ring", e.global_position, Color("#ff7030"), 0.4, 60))
	if ch.stats.has_flag("shatter") and (e.has_status("chill") or e.has_status("freeze")):
		for o in hostiles_in_radius(e.global_position, 70.0, "player"):
			o.add_status("chill", 2.0, {})
		add_fx(VFX.make("nova", e.global_position, Color("#a0e0ff"), 0.35, 70))
	if ch.stats.has_flag("corpse_blast") and killer != null and is_instance_valid(killer) and "owner_player" in killer:
		_effect_burst(e.global_position, {"void": [e.max_life * 0.15, e.max_life * 0.15]}, Color("#a0c080"), 48)
	if ch.stats.has_flag("dead_mans_promise") and killer == player and e.last_overkill > 1:
		_effect_burst(e.global_position, {"physical": [e.last_overkill, e.last_overkill]}, Color("#ffd060"), 50)
	on_enemy_killed(e)

func loot_bonus() -> float:
	return 1.0

func rarity_bonus() -> float:
	return 0.0

func xp_bonus() -> float:
	return 1.0

func on_enemy_killed(_e) -> void:
	pass

func _effect_burst(pos: Vector2, dmg: Dictionary, col: Color, r: float) -> void:
	var a = AoE.new()
	a.level = self
	a.source = player
	a.packet = {"dmg": dmg, "crit_chance": 0.0, "crit_mult": 1.0, "faction": "player", "status": [], "tags": [], "flags": {}}
	a.faction = "player"
	a.radius = r
	a.delay = 0.05
	a.style = "explosion"
	a.color = col
	a.show_telegraph = false
	a.position = pos
	floor_layer.add_child(a)

func spawn_drop(d: Dictionary, pos: Vector2) -> void:
	var n = LootDrop.new()
	n.level = self
	match d.get("kind", ""):
		"item":
			if d["item"].is_empty():
				return
			d["item"]["uid"] = player.ch.take_uid()
			n.setup_item(d["item"])
		"gold":
			n.setup_gold(int(d["amount"]))
		"material":
			n.setup_material(d["id"], int(d.get("amount", 1)))
		"rune":
			if d.get("id", "") == "":
				return
			n.setup_rune(d["id"])
		"gem":
			if d.get("id", "") == "":
				return
			n.setup_gem(d["id"])
	n.position = pos
	loot.append(n)
	floor_layer.add_child(n)

var _label_t := 0.0

func _layout_labels() -> void:
	var items := []
	for n in loot:
		if is_instance_valid(n) and n.visible:
			items.append(n)
	items.sort_custom(func(a, b): return a.global_position.y > b.global_position.y)
	var placed := []
	for n in items:
		n.label_off = 0.0
		var r: Rect2 = n.label_rect().grow(1)
		var guard := 0
		var moved := true
		while moved and guard < 30:
			moved = false
			guard += 1
			for q in placed:
				if r.intersects(q):
					n.label_off -= 12.0
					r = n.label_rect().grow(1)
					moved = true
					break
		placed.append(r)
		n.queue_redraw()

func _process(delta: float) -> void:
	_label_t -= delta
	if _label_t <= 0:
		_label_t = 0.3
		_layout_labels()
	if player == null or not is_instance_valid(player) or not player.alive:
		return
	# walk over gold and materials to collect them
	for n in loot.duplicate():
		if not is_instance_valid(n):
			loot.erase(n)
			continue
		if n.kind != "item" and n.t > 0.3 and n.global_position.distance_to(player.global_position) < 18:
			pickup(n)

## Why `collector` may not collect drop `n` right now ("" = it may). This is the
## single gate for manual pickup, walk-over, pet fetch and pet magnet, and it is
## re-checked at the moment of collection.
func collect_block(n, collector = null) -> String:
	if n == null or not is_instance_valid(n) or n.picked:
		return "gone"
	if n.is_claimed_by_other(collector if collector != null else player):
		return "claimed"
	if collector != null and collector != player and "is_pet" in collector:
		if n.filtered_now():
			return "hidden"
		if collector.tier < PetRules.required_tier(n.kind, n.item.get("rarity", "common") if n.kind == "item" else "common"):
			return "too_heavy"
	return ""

## The one pickup path: manual F/click, walking over gold, and the pet all call this.
## Only a successful collection frees the drop, so nothing can be duplicated or lost.
func pickup(n, collector = null) -> bool:
	if collect_block(n, collector) != "":
		return false
	var ch = player.ch
	match n.kind:
		"gold":
			ch.gold += n.amount
			Sfx.play("gold")
			Events.currency_changed.emit()
		"material":
			ch.add_material(n.mat_id, n.amount)
			Sfx.play("pickup")
		"gem":
			ch.add_gem(n.mat_id, 1)
			Sfx.play("pickup")
			Events.message.emit("Found %s - socket it at the Jeweller" % n.label, n.color)
		"rune":
			ch.add_rune(n.mat_id, 1)
			Sfx.play("levelup", 0.0)
			Events.message.emit("Found %s - socket it in the Skills panel (K)" % n.label, n.color)
			Events.message.emit("+%d %s" % [n.amount, n.label], n.color)
		"item":
			if not ch.add_to_bag(n.item):
				Events.message.emit("Inventory full", Color("#ff8080"))
				n.release(collector if collector != null else player)
				return false
			Sfx.play("pickup")
			Events.item_picked.emit(n.item)
	n.picked = true
	loot.erase(n)
	if collector != null and collector != player and is_instance_valid(collector) and collector.has_method("on_collected"):
		collector.on_collected(n)
	n.queue_free()
	return true

func nearest_item(pos: Vector2, maxd: float):
	var best = null
	var bd := maxd
	for n in loot:
		if is_instance_valid(n) and n.kind == "item" and not n.hidden_by_filter:
			var d: float = n.global_position.distance_to(pos)
			if d < bd:
				bd = d
				best = n
	return best

## Settings > Options > Loot Pickup: "keybind" (F only, default), "mouse" or "both".
func loot_pickup_mode() -> String:
	var m := str(Game.settings.get("loot_pickup", "keybind"))
	return m if m in ["keybind", "mouse", "both"] else "keybind"

func try_click_pickup(mouse: Vector2, p) -> bool:
	if loot_pickup_mode() == "keybind":
		return false
	for n in loot:
		if is_instance_valid(n) and not n.hidden_by_filter and n.label_rect().has_point(mouse):
			if n.global_position.distance_to(p.global_position) < float(PetRules.setting("manual_pickup_reach", 70)):
				pickup(n)
			else:
				Events.message.emit("Too far away", Color("#ff8080"))
			return true
	return false

func refresh_loot_filter() -> void:
	for n in loot:
		if is_instance_valid(n):
			n.refresh_filter()

# ------------------------------------------------------------------ interaction
func add_interactable(pos: Vector2, nm: String, kind: String, r: float = 26.0) -> void:
	interactables.append({"pos": pos, "name": nm, "kind": kind, "radius": r})

func nearest_interactable(pos: Vector2):
	var best = null
	var bd := INF
	for it in interactables:
		var d: float = pos.distance_to(it["pos"])
		if d < it["radius"] and d < bd:
			bd = d
			best = it
	return best

## The drop whose label is under the cursor, else the nearest label within
## label_pick_radius of it. Overlaps resolve to the higher rarity. Hidden drops
## have no label, so they can never be targeted.
func drop_at_cursor(mouse: Vector2):
	var best = null
	var best_d := INF
	var best_r := -99
	var radius := float(PetRules.setting("label_pick_radius", 40))
	for n in loot:
		if not is_instance_valid(n) or n.picked or n.hidden_by_filter or not n.visible:
			continue
		var r: Rect2 = n.label_rect()
		var d := 0.0
		if not r.has_point(mouse):
			var cp := Vector2(clampf(mouse.x, r.position.x, r.end.x), clampf(mouse.y, r.position.y, r.end.y))
			d = cp.distance_to(mouse)
			if d > radius:
				continue
		var ri: int = n.rarity_idx()
		if d < best_d - 0.01 or (absf(d - best_d) <= 0.01 and ri > best_r):
			best = n
			best_d = d
			best_r = ri
	return best

## F: the drop at the cursor is collected by you if it is within reach, otherwise
## your pet is sent for it. With nothing near the cursor, F works as before
## (nearest interactable, then the nearest item at your feet).
func interact(p, mouse = null) -> void:
	var f_loots := loot_pickup_mode() != "mouse"
	if mouse != null and f_loots:
		var target = drop_at_cursor(mouse)
		if target != null:
			if target.global_position.distance_to(p.global_position) <= float(PetRules.setting("manual_pickup_reach", 70)):
				pickup(target)
			elif pet != null and is_instance_valid(pet):
				pet.request_fetch(target)
			else:
				Events.message.emit("Too far away", Color("#ff8080"))
			return
	var it = nearest_interactable(p.global_position)
	if it != null:
		on_interact(it)
		return
	if not f_loots:
		return
	var n = nearest_item(p.global_position, 34.0)
	if n != null:
		pickup(n)

func on_interact(_it: Dictionary) -> void:
	pass

func cleanup() -> void:
	if Events.pet_changed.is_connected(respawn_pet):
		Events.pet_changed.disconnect(respawn_pet)
	if pet != null and is_instance_valid(pet):
		pet.despawn()
	pet = null
	if Events.enemy_killed.is_connected(_on_enemy_killed):
		Events.enemy_killed.disconnect(_on_enemy_killed)
