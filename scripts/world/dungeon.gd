extends "res://scripts/world/level.gd"
## A dungeon run: generated layout, tier scaling, run modifiers, monster packs
## with elites, hazards, objectives (guardian, mechanisms, relics, waves), a sealed
## boss arena, minimap reveal, exit / town / descend portals and endless depth.

const DungeonGen = preload("res://scripts/world/dungeon_gen.gd")
const Hazard = preload("res://scripts/entities/hazard.gd")
const Portal = preload("res://scripts/world/portal.gd")

var def := {}
var layout := {}
var rooms := []
var monster_level := 1
var boss = null
var boss_spawned := false
var boss_dead := false
var reveal := PackedByteArray()
var minimap_img: Image
var minimap_tex: ImageTexture
var reveal_t := 0.0
var run_seed := 0
var total_enemies := 0
var current_room := -1

var depth := 1
var mods := []                 # run modifier dictionaries
var reward_bonus := 0.0        # % more quantity / rarity / xp from modifiers and depth
var density := 1.0
var elite_mult := 1.0
var tempest := false
var tempest_t := 4.0
var objectives := []           # [{type, need, have, done}]
var sealed_cells := []
var seal_node: Node2D = null
var guardian = null
var wave_state := {}
var markers := {}              # interactable kind+index -> node

func setup(d: Dictionary, ch, seed_value: int = 0, run: Dictionary = {}) -> bool:
	def = d
	depth = int(run.get("depth", 1))
	palette = d.get("palette", "crypt")
	level_name = "%s  (Tier %d)" % [d["name"], int(d.get("tier", 1))]
	if d.get("endless", false):
		level_name = "%s  -  Depth %d" % [d["name"], depth]
	ambient = Color(d.get("ambient", "#56526a"))
	var lo := int(d.get("min_level", 1)) + 2 * (depth - 1)
	monster_level = clampi(maxi(ch.level, lo), int(d.get("min_level", 1)), int(d.get("max_level", 10)) + (depth - 1))
	run_seed = seed_value if seed_value != 0 else randi()
	rng.seed = run_seed
	_apply_modifiers(run.get("mods", []))
	var gen = DungeonGen.new()
	layout = gen.generate(d, run_seed)
	if layout.is_empty():
		return false
	rooms = layout["rooms"]
	init_grid(layout["w"], layout["h"])
	grid = layout["grid"]
	build_world()
	_place_torches()
	reveal.resize(gw * gh)
	reveal.fill(0)
	minimap_img = Image.create(gw, gh, false, Image.FORMAT_RGBA8)
	minimap_img.fill(Color(0, 0, 0, 0))
	minimap_tex = ImageTexture.create_from_image(minimap_img)
	var start: Dictionary = rooms[layout["start"]]
	spawn_player(ch, cell_center(start["anchor"]))
	_apply_player_mods()
	add_ambient_particles(Color(1.0, 0.6, 0.3, 0.35))
	var portal_pos := cell_center(start["anchor"]) + Vector2(0, -40)
	if is_solid(portal_pos):
		portal_pos = cell_center(start["anchor"]) + Vector2(32, 0)
	_add_portal(portal_pos, "Town Portal", "town_portal", Color("#6080ff"))
	_populate()
	_place_hazards()
	_setup_objectives()
	return true

# ------------------------------------------------------------------ modifiers & scaling
func _apply_modifiers(mod_ids: Array) -> void:
	var s := 1.0 + float(def.get("depth_scaling", 0.0)) * (depth - 1)
	enemy_run = {
		"life": float(def.get("life_mult", 1.0)) * s,
		"damage": float(def.get("damage_mult", 1.0)) * pow(s, 0.8),
		"resist": float(def.get("resist_bonus", 0)) + minf(20.0, 2.0 * (depth - 1)),
	}
	reward_bonus = 10.0 * (depth - 1)
	for id in mod_ids:
		var m: Dictionary = Data.dungeon_mods.get(id, {})
		if m.is_empty():
			continue
		mods.append(m)
		reward_bonus += float(m.get("reward", 0))
		var en: Dictionary = m.get("enemy", {})
		for k in en:
			var v = en[k]
			if typeof(v) == TYPE_BOOL:
				enemy_run[k] = v
			elif k in ["regen", "added_fire"]:
				enemy_run[k] = float(enemy_run.get(k, 0.0)) + float(v)
			else:
				enemy_run[k] = float(enemy_run.get(k, 1.0)) * float(v)
		density *= float(m.get("density", 1.0))
		elite_mult *= float(m.get("elite_mult", 1.0))
		if m.get("tempest", false):
			tempest = true

func _apply_player_mods() -> void:
	var pm := []
	var heal := 1.0
	for m in mods:
		pm.append_array(m.get("player_mods", []))
		heal *= float(m.get("player_heal", 1.0))
	player.heal_mult = heal
	if pm.size() > 0:
		player.add_buff("run_modifiers", pm, 1.0e9)

func loot_bonus() -> float:
	return 1.0 + reward_bonus / 100.0

func rarity_bonus() -> float:
	return float(def.get("rarity_bonus", 0)) + reward_bonus

func xp_bonus() -> float:
	return 1.0 + reward_bonus / 100.0

# ------------------------------------------------------------------ build helpers
func _place_torches() -> void:
	for r in rooms:
		var rect: Rect2i = r["rect"]
		var placed := 0
		for x in range(rect.position.x, rect.end.x):
			for y in range(rect.position.y, rect.end.y):
				if cell(x, y) == WALL and cell(x, y + 1) == FLOOR and (x + y) % 7 == 0 and placed < 4:
					if rng.randf() < 0.7:
						add_torch(Vector2i(x, y))
						placed += 1

func _add_portal(pos: Vector2, nm: String, kind: String, col: Color, spr: String = "") -> Node2D:
	var p = Portal.new()
	p.position = pos
	p.color = col
	p.label = nm
	p.sprite_name = spr
	floor_layer.add_child(p)
	add_interactable(pos, nm, kind, 30.0)
	return p

func _normal_rooms() -> Array:
	return rooms.filter(func(r): return r["kind"] == "normal")

func _room_floor(r: Dictionary) -> Vector2:
	var rect: Rect2i = r["rect"]
	for i in 60:
		var c := Vector2i(rng.randi_range(rect.position.x + 2, rect.end.x - 3), rng.randi_range(rect.position.y + 2, rect.end.y - 3))
		if cell(c.x, c.y) == FLOOR and cell(c.x + 1, c.y) == FLOOR and cell(c.x - 1, c.y) == FLOOR and cell(c.x, c.y + 1) == FLOOR and cell(c.x, c.y - 1) == FLOOR:
			return cell_center(c)
	return cell_center(r["anchor"])

# ------------------------------------------------------------------ population
func _populate() -> void:
	var pool: Array = def.get("pool", [])
	for r in rooms:
		if r["kind"] != "normal":
			continue
		var ppr: Array = def.get("packs_per_room", [1, 2])
		var packs := rng.randi_range(int(ppr[0]), int(ppr[1]))
		if r["depth"] >= 3:
			packs += 1
		if rng.randf() < density - 1.0:
			packs += 1
		var spawns: Array = r["spawns"].duplicate()
		spawns.shuffle()
		for p in packs:
			var anchor: Vector2i = spawns[p % spawns.size()] if spawns.size() > 0 else r["anchor"]
			_spawn_pack(pool, anchor, monster_level + int(r["depth"] / 3), rng.randf() < float(def.get("elite_chance", 0.15)) * elite_mult, r["id"])

func _spawn_pack(pool: Array, anchor: Vector2i, lvl: int, elite: bool, room_id: int) -> Array:
	var out := []
	var ed: Dictionary = Data.enemies.get(_weighted_enemy(pool), {})
	if ed.is_empty():
		return out
	var ps: Array = ed.get("pack", def.get("pack_size", [3, 5]))
	var count := int(round(rng.randi_range(int(ps[0]), int(ps[1])) * density))
	for i in count:
		var pos := random_floor_near(anchor, 2)
		var em_list := []
		if elite and i == 0:
			var em: Array = def.get("elite_mods", [1, 2])
			em_list = _roll_elite_mods(rng.randi_range(int(em[0]), int(em[1])))
		var d2 := ed
		if i > 0 and rng.randf() < 0.25:
			var alt: Dictionary = Data.enemies.get(_weighted_enemy(pool), {})
			if not alt.is_empty() and not alt.has("pack"):
				d2 = alt
		var e = spawn_enemy(d2, lvl, em_list, pos)
		e.room_id = room_id
		out.append(e)
		total_enemies += 1
	return out

func _weighted_enemy(pool: Array) -> String:
	var total := 0.0
	for p in pool:
		total += float(p.get("w", 10))
	var roll := rng.randf() * total
	for p in pool:
		roll -= float(p.get("w", 10))
		if roll <= 0:
			return p["id"]
	return pool[0]["id"] if pool.size() > 0 else "ghoul"

func _roll_elite_mods(n: int) -> Array:
	var ids := []
	for m in Data.elite_mod_list:
		ids.append(m["id"])
	var out := []
	for i in n:
		if ids.is_empty():
			break
		var id: String = ids[rng.randi() % ids.size()]
		ids.erase(id)
		out.append(id)
	return out

func _place_hazards() -> void:
	var kinds: Array = def.get("hazards", [])
	if kinds.is_empty():
		return
	for r in _normal_rooms():
		if rng.randf() > float(def.get("hazard_rooms", 0.3)):
			continue
		var kind: String = kinds[rng.randi() % kinds.size()]
		for i in rng.randi_range(1, 3):
			var h = Hazard.new()
			h.level = self
			h.setup(kind, monster_level)
			h.position = _room_floor(r)
			floor_layer.add_child(h)

# ------------------------------------------------------------------ objectives
func _setup_objectives() -> void:
	var list: Array = def.get("objectives", ["boss"]).duplicate()
	if def.get("endless", false):
		list = ["boss"]
		var extra := ["guardian", "mechanisms:3", "relics:3", "waves"]
		if depth % 3 == 0:
			list.push_front("waves")
		elif rng.randf() < 0.6:
			list.push_front(extra[rng.randi() % extra.size()])
	var normals := _normal_rooms()
	normals.sort_custom(func(a, b): return a["depth"] > b["depth"])
	var used := {}
	for o in list:
		var parts: PackedStringArray = String(o).split(":")
		var typ: String = parts[0]
		var need := int(parts[1]) if parts.size() > 1 else 1
		var ob := {"type": typ, "need": need, "have": 0, "done": false}
		objectives.append(ob)
		match typ:
			"guardian":
				var room: Dictionary = _pick_room(normals, used, true)
				var gid: String = def.get("guardian", ["guardian_knight", "guardian_witch"][rng.randi() % 2])
				var gd: Dictionary = Data.enemies.get(gid, {})
				if not gd.is_empty():
					guardian = spawn_enemy(gd, monster_level + 1, [], _room_floor(room))
					guardian.room_id = room["id"]
					_spawn_pack(def.get("pool", []), room["anchor"], monster_level, false, room["id"])
			"mechanisms":
				for i in need:
					var room2: Dictionary = _pick_room(normals, used, false)
					var pos := _room_floor(room2)
					markers["mechanism_%d" % i] = _add_portal(pos, "Ancient Mechanism", "mechanism_%d" % i, Color("#80c0ff"), "shrine")
			"relics":
				for i in need:
					var room3: Dictionary = _pick_room(normals, used, false)
					var pos2 := _room_floor(room3)
					markers["relic_%d" % i] = _add_portal(pos2, "Relic Fragment", "relic_%d" % i, Color("#ffd060"), "")
					_spawn_pack(def.get("pool", []), to_cell(pos2), monster_level + 1, true, room3["id"])
			"waves":
				var room4: Dictionary = _pick_room(normals, used, false)
				var pos3 := _room_floor(room4)
				markers["altar"] = _add_portal(pos3, "Blood Altar", "altar", Color("#ff4040"), "shrine")
				wave_state = {"pos": pos3, "wave": 0, "active": false, "alive": [], "total": 3 + (1 if depth >= 6 else 0)}
	_update_seal()
	Events.objective_changed.emit(objective_text())

func _pick_room(normals: Array, used: Dictionary, deepest: bool) -> Dictionary:
	var cands := normals.filter(func(r): return not used.has(r["id"]))
	if cands.is_empty():
		cands = normals.duplicate()
	if cands.is_empty():
		return rooms[layout["start"]]
	var r: Dictionary = cands[0] if deepest else cands[rng.randi() % cands.size()]
	used[r["id"]] = true
	return r

func _pre_boss_done() -> bool:
	for o in objectives:
		if o["type"] != "boss" and not o["done"]:
			return false
	return true

func _complete(o: Dictionary) -> void:
	if o["done"]:
		return
	o["done"] = true
	Sfx.play("levelup", 0.0)
	Events.message.emit("Objective complete: %s" % _obj_name(o), Color("#ffd060"))
	_update_seal()
	Events.objective_changed.emit(objective_text())

func _obj_name(o: Dictionary) -> String:
	match o["type"]:
		"guardian":
			return "Slay %s" % (guardian.display_name if guardian != null and is_instance_valid(guardian) else "the elite guardian")
		"mechanisms":
			return "Activate ancient mechanisms (%d/%d)" % [o["have"], o["need"]]
		"relics":
			return "Recover relic fragments (%d/%d)" % [o["have"], o["need"]]
		"waves":
			if wave_state.get("active", false):
				return "Survive the Blood Altar (wave %d/%d)" % [wave_state["wave"], wave_state["total"]]
			return "Survive the Blood Altar"
		"boss":
			var bd: Dictionary = Data.enemies.get(_boss_id(), {})
			return "Defeat %s" % bd.get("name", "the boss")
	return o["type"]

func objective_text() -> String:
	if boss_dead:
		return "Dungeon complete! Take the Exit Portal" + ("\nor Descend deeper" if def.get("endless", false) else "")
	var lines := []
	for o in objectives:
		lines.append(("[x] " if o["done"] else "[ ] ") + _obj_name(o))
	if sealed_cells.size() > 0:
		lines.append("The boss arena is sealed")
	lines.append("Monsters remaining: %d" % enemies.size())
	if mods.size() > 0:
		var names := []
		for m in mods:
			names.append(m["name"])
		lines.append("Modifiers: " + ", ".join(names) + "  (+%d%% rewards)" % int(reward_bonus))
	return "\n".join(lines)

# ------------------------------------------------------------------ boss arena seal
func _update_seal() -> void:
	var need_seal := not _pre_boss_done()
	if need_seal and sealed_cells.is_empty():
		_seal_arena()
	elif not need_seal and sealed_cells.size() > 0:
		_unseal_arena()

func _seal_arena() -> void:
	var br: Dictionary = rooms[layout["boss"]]
	var rect: Rect2i = br["rect"]
	for x in range(rect.position.x - 1, rect.end.x + 1):
		for y in range(rect.position.y - 1, rect.end.y + 1):
			var on_border := x == rect.position.x - 1 or y == rect.position.y - 1 or x == rect.end.x or y == rect.end.y
			if on_border and cell(x, y) == FLOOR:
				sealed_cells.append(Vector2i(x, y))
	seal_node = StaticBody2D.new()
	seal_node.collision_layer = 1
	seal_node.collision_mask = 0
	for c in sealed_cells:
		set_cell(c.x, c.y, WALL)
		var cs := CollisionShape2D.new()
		var sh := RectangleShape2D.new()
		sh.size = Vector2(T, T)
		cs.shape = sh
		cs.position = cell_center(c)
		seal_node.add_child(cs)
	add_child(seal_node)
	var vis = load("res://scripts/world/seal_visual.gd").new()
	vis.cells = sealed_cells
	vis.level = self
	seal_node.add_child(vis)

func _unseal_arena() -> void:
	for c in sealed_cells:
		set_cell(c.x, c.y, FLOOR)
	sealed_cells.clear()
	if seal_node != null:
		seal_node.queue_free()
		seal_node = null
	flow_timer = -2.0
	Events.message.emit("The seal on the boss arena breaks!", Color("#ffd060"))
	Sfx.play("portal", 0.0)

# ------------------------------------------------------------------ runtime
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if player == null or not is_instance_valid(player):
		return
	reveal_t -= delta
	if reveal_t <= 0:
		reveal_t = 0.2
		_reveal_around(player.global_position, 11)
		_track_room()
		_check_relics()
	if tempest and player.alive and not boss_dead:
		tempest_t -= delta
		if tempest_t <= 0:
			tempest_t = rng.randf_range(3.0, 5.0)
			var h = Hazard.new()
			h.level = self
			h.setup("lightning", monster_level)
			h.position = clamp_to_floor(player.global_position, player.global_position + Vector2(rng.randf_range(-50, 50), rng.randf_range(-50, 50)))
			floor_layer.add_child(h)
	if wave_state.get("active", false):
		_tick_waves()

func _track_room() -> void:
	var pc := to_cell(player.global_position)
	current_room = -1
	for r in rooms:
		if (r["rect"] as Rect2i).grow(-1).has_point(pc):
			current_room = r["id"]
			if not r["visited"]:
				r["visited"] = true
			if r["kind"] == "boss" and not boss_spawned and sealed_cells.is_empty():
				_spawn_boss(r)

func _boss_id() -> String:
	if def.get("endless", false) and depth > 1:
		var pool: Array = def.get("boss_pool", [def.get("boss", "warden")])
		return pool[(run_seed + depth) % pool.size()]
	return def.get("boss", "warden")

func _spawn_boss(r: Dictionary) -> void:
	boss_spawned = true
	var bd: Dictionary = Data.enemies.get(_boss_id(), {})
	if bd.is_empty():
		return
	var pos := cell_center(r["anchor"])
	boss = spawn_enemy(bd, monster_level + 1, [], pos)
	boss.aggro = true
	add_fx(VFX.make("nova", pos, Color(bd.get("light", "#60d0c0")), 0.9, 80))
	shake(3.0)
	Events.boss_spawned.emit(boss)
	Sfx.play("boss", 0.0)
	Events.message.emit("%s awakens!" % bd["name"], Color("#ff6060"))

func _check_relics() -> void:
	for k in markers.keys():
		if not k.begins_with("relic_"):
			continue
		var n = markers[k]
		if is_instance_valid(n) and n.global_position.distance_to(player.global_position) < 22:
			_take_interactable(k)
			for o in objectives:
				if o["type"] == "relics" and not o["done"]:
					o["have"] += 1
					Sfx.play("pickup", 0.0)
					Events.message.emit("Relic fragment recovered (%d/%d)" % [o["have"], o["need"]], Color("#ffd060"))
					if o["have"] >= o["need"]:
						_complete(o)
					Events.objective_changed.emit(objective_text())
					break

func _take_interactable(kind: String) -> void:
	var n = markers.get(kind)
	if n != null and is_instance_valid(n):
		n.queue_free()
	markers.erase(kind)
	interactables = interactables.filter(func(it): return it["kind"] != kind)

func on_enemy_killed(e) -> void:
	if e == guardian:
		for o in objectives:
			if o["type"] == "guardian":
				_complete(o)
		for i in 2:
			spawn_drop({"kind": "item", "item": Loot.roll_item(monster_level, 200.0 + rarity_bonus(), player.ch.class_id, "rare")}, e.global_position)
	if e == boss and not boss_dead:
		_on_boss_dead(e)
	else:
		Events.objective_changed.emit(objective_text())

func _on_boss_dead(e) -> void:
	boss_dead = true
	for o in objectives:
		if o["type"] == "boss":
			o["done"] = true
	var ch = player.ch
	var key: String = def["id"]
	var first: bool = not ch.progress["bosses_killed"].has(key)
	ch.progress["bosses_killed"][key] = int(ch.progress["bosses_killed"].get(key, 0)) + 1
	if first:
		ch.bonus_passive_points += 1
		Events.message.emit("First victory: +1 Passive Skill Point!", Color("#ffd040"))
	ch.add_xp(int(60 * monster_level * int(def.get("tier", 1)) * xp_bonus()))
	ch.progress["highest_tier"] = mini(6, maxi(int(ch.progress.get("highest_tier", 1)), int(def.get("tier", 1)) + 1))
	# tier rewards: extra loot, legendary chance at the highest tiers
	var tier := int(def.get("tier", 1))
	for i in tier - 1 + int(depth / 2.0):
		spawn_drop({"kind": "item", "item": Loot.roll_item(monster_level + 1, 300.0 + rarity_bonus(), ch.class_id)}, e.global_position)
	if tier >= 5 and rng.randf() < 0.25 + 0.03 * depth:
		spawn_drop({"kind": "item", "item": Loot.roll_item(monster_level + 1, 0.0, ch.class_id, "legendary")}, e.global_position)
	if def.get("endless", false):
		ch.progress["abyss_best"] = maxi(int(ch.progress.get("abyss_best", 0)), depth)
		_add_portal(e.global_position + Vector2(-40, 30), "Descend to depth %d" % (depth + 1), "descend", Color("#ff4060"))
	_add_portal(e.global_position + Vector2(0, 30), "Exit Portal", "exit_portal", Color("#ffd060"))
	Events.boss_died.emit(e)
	Events.objective_changed.emit(objective_text())
	Events.message.emit("%s has fallen!" % e.display_name, Color("#ffd060"))
	Game.save_game()

func on_interact(it: Dictionary) -> void:
	var k: String = it["kind"]
	if k == "town_portal":
		Game.main.go_hub(false)
	elif k == "exit_portal":
		Game.main.go_hub(true)
	elif k == "descend":
		Game.main.enter_dungeon(def["id"], 0, {"depth": depth + 1, "mods": Game.roll_run_mods(def)})
	elif k.begins_with("mechanism_"):
		var pos: Vector2 = it["pos"]
		_take_interactable(k)
		add_fx(VFX.make("nova", pos, Color("#80c0ff"), 0.6, 50))
		Sfx.play("portal", 0.0)
		for o in objectives:
			if o["type"] == "mechanisms" and not o["done"]:
				o["have"] += 1
				Events.message.emit("Mechanism activated (%d/%d)" % [o["have"], o["need"]], Color("#80c0ff"))
				if o["have"] >= o["need"]:
					_complete(o)
				break
		# activating the old machinery wakes guardians
		if rng.randf() < 0.6:
			var ambush := _spawn_pack(def.get("pool", []), to_cell(pos), monster_level, rng.randf() < 0.3, -1)
			for a in ambush:
				a.aggro = true
		Events.objective_changed.emit(objective_text())
	elif k == "altar":
		if not wave_state.get("active", false) and int(wave_state.get("wave", 0)) == 0:
			wave_state["active"] = true
			_take_interactable("altar")
			Events.message.emit("The Blood Altar awakens - survive!", Color("#ff4040"))
			_next_wave()

func _next_wave() -> void:
	wave_state["wave"] = int(wave_state["wave"]) + 1
	var pos: Vector2 = wave_state["pos"]
	var alive := []
	var elite_heavy: bool = def.get("endless", false) and depth % 3 == 0
	for i in 2 + int(wave_state["wave"]):
		var ang: float = TAU * i / (2.0 + float(wave_state["wave"]))
		var at: Vector2 = clamp_to_floor(pos, pos + Vector2.RIGHT.rotated(ang) * 80.0)
		var pack := _spawn_pack(def.get("pool", []), to_cell(at), monster_level, elite_heavy or rng.randf() < 0.25, -1)
		for e in pack:
			e.aggro = true
			e.loot_mult *= 0.6
			alive.append(e)
		add_fx(VFX.make("ring", at, Color("#ff4040"), 0.5, 20))
	wave_state["alive"] = alive
	Events.message.emit("Wave %d of %d" % [wave_state["wave"], wave_state["total"]], Color("#ff8060"))
	Events.objective_changed.emit(objective_text())

func _tick_waves() -> void:
	var alive: Array = wave_state["alive"].filter(func(e): return is_instance_valid(e) and e.alive)
	wave_state["alive"] = alive
	if alive.is_empty():
		if int(wave_state["wave"]) >= int(wave_state["total"]):
			wave_state["active"] = false
			for o in objectives:
				if o["type"] == "waves":
					_complete(o)
			for i in 3:
				spawn_drop({"kind": "item", "item": Loot.roll_item(monster_level, 150.0 + rarity_bonus(), player.ch.class_id)}, wave_state["pos"])
		else:
			_next_wave()

func _reveal_around(p: Vector2, rad: int) -> void:
	var c := to_cell(p)
	var changed := false
	for y in range(c.y - rad, c.y + rad + 1):
		for x in range(c.x - rad, c.x + rad + 1):
			if x < 0 or y < 0 or x >= gw or y >= gh:
				continue
			if (x - c.x) * (x - c.x) + (y - c.y) * (y - c.y) > rad * rad:
				continue
			var i := y * gw + x
			if reveal[i] == 0:
				reveal[i] = 1
				changed = true
				if grid[i] == FLOOR:
					minimap_img.set_pixel(x, y, Color(0.55, 0.5, 0.6, 0.9))
				elif _near_floor(x, y):
					minimap_img.set_pixel(x, y, Color(0.25, 0.22, 0.28, 0.9))
	if changed:
		minimap_tex.update(minimap_img)
