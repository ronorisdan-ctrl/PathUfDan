extends "res://scripts/world/level.gd"
## A dungeon run: generated layout, tier scaling, run modifiers, monster packs
## with elites, hazards, objectives (guardian, mechanisms, relics, waves), a sealed
## boss arena, minimap reveal, exit / town / descend portals and endless depth.

const DungeonGen = preload("res://scripts/world/dungeon_gen.gd")
const ZoneGen = preload("res://scripts/world/zone_gen.gd")
const Hazard = preload("res://scripts/entities/hazard.gd")
const Portal = preload("res://scripts/world/portal.gd")
const AtlasRules = preload("res://scripts/core/atlas_rules.gd")
const AtlasCraft = preload("res://scripts/core/atlas_craft_rules.gd")
const GuildRules = preload("res://scripts/core/guild_rules.gd")
const WV = preload("res://scripts/core/wager_vault_rules.gd")
const VaultSeal = preload("res://scripts/world/vault_seal.gd")

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
# Endgame zone spike (def "generator": "zone"): chamber-stitched layout, local flow field,
# far packs asleep (process disabled, removed from physics) until the player comes near.
var is_zone := false
var sleeping := 0              # enemies asleep after the last pass (bench / tests)
var zone_sleep_t := 0.0
var _chamber_dist := []
var _dist_from := -1
var awake_pool := []           # awake enemies (zones): the only ones packs spread around
var atlas_hex := ""            # Atlas of Ruin run: the hex key ("q,r"); "" otherwise
var atlas_revealed := []       # keys revealed by this run's boss kill (tests / UI)
# Rot (Endgame Phase 1C): the hex's Rot when the run started, Heart boss and its choice
var rot := 0
var rot_spread := []           # keys the Rot spread to when this run's boss died
var death_rot := -2            # -2 = not applied yet; else the result of AtlasRules.add_death_rot
var heart_choice := ""         # "", "restore" or "harvest"
# Zone mechanics (Endgame Phase 1D): "", "glazed" or "unfinished". Own RNG so the layout/pack stream
# of a run without a mechanic is unchanged.
var mechanic := ""             # the first active mechanic (compat); mechanics = all of them (Phase 1E)
var mechanics := []
var glaze_tune := {}            # mechanic tuning with Pigment modifiers applied (Phase 1E)
var sketch_tune := {}
var pigment_uids := []          # Easel Pigments used by this run (a death spends more charges)
var death_charged := false
var afx := {}                  # The Atelier's zone effects (AtlasRules.atelier_fx; Phase 3B)
var first_elite_done := false   # Atelier First Blood: the first elite kill dropped its rare
var last_light := {}           # Atelier Last Light: {active, wave, waves, members: [], leaders: [], t, times: [], done}
# Layer Wardens (Endgame Phase 2A): the ring whose Warden this run fights (0 = none)
var warden := 0
var warden_result := {}         # AtlasRules.warden_victory result (tests / UI)
var shard_drop := 0             # Ground Shards this run's clear dropped
var warden_name := ""
var mech_rng := RandomNumberGenerator.new()
var rot_rng := RandomNumberGenerator.new()   # Rot-touched implicit rolls (Endgame 2B); own stream
var rot_touched := 0                          # items Rot-touched this run (tests / smartbot)
var elite_kills := 0                          # elites killed this run (Commission Board, Endgame 2C)
var guild_report := {}                        # the run report credited to the Commission Board (tests)
var guild_result := {}                        # GuildRules.credit result of the zone clear (tests / UI)
var mech_stats := {"glazed": 0, "peels": 0, "shattered": 0, "full_peels": 0, "flakes": 0, "glaze_kills": 0, "ttk_sum": 0.0, "sketch_packs": 0, "sketches": 0, "painted": 0, "filled": 0, "dust": 0}
var _packs := []               # packs spawned by _populate (sketch selection)
# Endgame 2D: the Collector's Wager, Pentimento Vaults and the extra run report fields
var run_t := 0.0                # seconds in the zone until the boss died
var boss_t := -1.0              # seconds since the boss woke (-1 = not yet)
var boss_fight := -1.0          # boss_t when the boss died
var zone_kills := 0             # monsters killed before the boss died (vault walls excluded)
var wager := {}                 # {} or {state: offer|active|won|lost, offers, lim, bet, mult, stake, t, ...}
var collector_pos := Vector2.ZERO
var vaults := []                # [{type, dir, f, mouth, pocket, centre, wall, seal, open, done, ...}]
var wv_stats := {"wagers_won": 0, "wager_3x": 0, "wagers_lost": 0, "vaults": 0, "treasure_vaults": 0, "trap_vaults": 0, "riddle_vaults": 0, "vault_shards": 0}

func corruption_drop_context() -> Dictionary:
	return {"tier": int(def.get("tier", 1)), "depth": depth, "endless": bool(def.get("endless", false))}

func setup(d: Dictionary, ch, seed_value: int = 0, run: Dictionary = {}) -> bool:
	def = d
	depth = int(run.get("depth", 1))
	palette = d.get("palette", "crypt")
	level_name = "%s  (Tier %d)" % [d["name"], int(d.get("tier", 1))]
	if d.get("endless", false):
		level_name = "%s  -  Depth %d" % [d["name"], depth]
	atlas_hex = str(run.get("atlas", "")) if d.get("atlas", false) else ""
	if atlas_hex != "":
		level_name = "%s  (Atlas ring %d)" % [d["name"], int(d.get("atlas_ring", 1))]
		rot = int(d.get("rot", 0))
		if rot > 0:
			level_name += "  - Rot %d" % rot
		warden = int(d.get("warden", 0))
		if warden > 0:
			warden_name = str(AtlasRules.warden_def(Data.enemies.get(str(d.get("boss", "")), {}), warden).get("name", ""))
			level_name += "  - Warden"
	ambient = Color(d.get("ambient", "#56526a"))
	var lo := int(d.get("min_level", 1)) + 2 * (depth - 1)
	monster_level = clampi(maxi(ch.level, lo), int(d.get("min_level", 1)), int(d.get("max_level", 10)) + (depth - 1))
	run_seed = seed_value if seed_value != 0 else randi()
	rng.seed = run_seed
	rot_rng.seed = run_seed * 53 + 11
	_apply_modifiers(run.get("mods", []))
	mechanics = []
	var mlist = d.get("mechanics", null)
	if typeof(mlist) != TYPE_ARRAY:
		mlist = [str(d.get("mechanic", ""))]
	for m in mlist:
		if not AtlasRules.mechanic_info(str(m)).is_empty() and not mechanics.has(str(m)):
			mechanics.append(str(m))
	mechanic = mechanics[0] if mechanics.size() > 0 else ""
	var pmods: Dictionary = d.get("pigment_mods", {})
	afx = d.get("atelier_fx", {})
	glaze_tune = AtlasRules.mech_tuning("glazed", pmods.get("glazed", []))
	sketch_tune = AtlasRules.mech_tuning("unfinished", pmods.get("unfinished", []))
	if not afx.is_empty():   # The Atelier (Phase 3B): Drawing smalls
		for k in ["min_layers", "max_layers"]:
			glaze_tune[k] = int(glaze_tune.get(k, 2)) + int(afx.get("glaze_layers", 0))
		for k in ["peel_flakes", "shatter_flakes"]:
			glaze_tune[k] = int(glaze_tune.get(k, 0)) + int(afx.get("glaze_flakes", 0))
		sketch_tune["colours"] = int(sketch_tune.get("colours", 1)) + int(afx.get("sketch_colours", 0))
	pigment_uids = d.get("pigment_uids", []).duplicate()
	if not mechanics.is_empty():
		mech_rng.seed = run_seed * 31 + 7
		if has_mech("glazed"):
			elite_mult *= float(glaze_tune.get("elite_chance_mult", 1.0))
		for m in mechanics:
			level_name += "  - " + str(AtlasRules.mechanic_info(m).get("name", m))
	# Pigments (Phase 1E) and the Atelier (Phase 3B): rewards, pack size, elite chance
	reward_bonus += float(d.get("pigment_reward", 0.0))
	if not afx.is_empty():
		density *= float(afx.get("density", 1.0))
		elite_mult *= float(afx.get("elite_mult", 1.0))
		reward_bonus += float(afx.get("reward", 0.0))
	is_zone = d.get("generator", "") == "zone"
	var gen = ZoneGen.new() if is_zone else DungeonGen.new()
	layout = gen.generate(d, run_seed)
	if layout.is_empty():
		return false
	rooms = layout["rooms"]
	init_grid(layout["w"], layout["h"])
	grid = layout["grid"]
	if is_zone:
		cell_zone = layout["cell_chamber"]
		zone_adj = layout["adjacency"]
		flow_reach = int(d.get("flow_reach", 160))
		summon_lifetime = int(d.get("summon_lifetime", 0))
		tile_chunk = int(d.get("tile_chunk", 32))
		if has_mech("vault"):
			_carve_vaults()   # Endgame 2D: pockets carved into the rock before the world is built
		index_zone_cells()
	build_world()
	_seal_vaults()
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
	if has_mech("unfinished"):
		_sketch_packs()
	_place_hazards()
	_setup_objectives()
	_place_vault_walls()
	if has_mech("wager"):
		_place_collector()
	if is_zone:
		update_sleep()
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
	# Rot (Phase 1C): bigger packs and more rewards (life/damage are already in the def)
	density *= float(def.get("rot_density", 1.0))
	reward_bonus += float(def.get("rot_reward", 0.0))
	enemy_run["attack_speed"] = float(enemy_run.get("attack_speed", 1.0)) * float(def.get("rot_attack_speed", 1.0))
	if def.has("rot_move_speed"):
		enemy_run["speed"] = float(enemy_run.get("speed", 1.0)) * float(def["rot_move_speed"])
	if def.has("rot_proj_speed"):
		enemy_run["proj_speed"] = float(enemy_run.get("proj_speed", 1.0)) * float(def["rot_proj_speed"])

func _apply_player_mods() -> void:
	var pm := []
	var heal := 1.0
	for m in mods:
		pm.append_array(m.get("player_mods", []))
		heal *= float(m.get("player_heal", 1.0))
	player.heal_mult = heal * float(def.get("rot_heal", 1.0))   # Rot (Phase 1E)
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
			var pk := _spawn_pack(pool, anchor, monster_level + int(r["depth"] / 3), rng.randf() < float(def.get("elite_chance", 0.15)) * elite_mult, r["id"])
			if not mechanics.is_empty():
				_packs.append(pk)
	# The Atelier, Craquelure choice b (Crowded Finale): extra elite packs in the deepest normal chamber
	# (with Last Light they become extra waves instead)
	var extra := int(afx.get("last_chamber_packs", 0))
	if extra > 0 and not def.get("last_light", false):
		var deep := {}
		for r in rooms:
			if r["kind"] == "normal" and (deep.is_empty() or int(r["depth"]) > int(deep["depth"])):
				deep = r
		if not deep.is_empty():
			for i in extra:
				var pk := _spawn_pack(pool, deep["anchor"], monster_level + int(deep["depth"] / 3), true, deep["id"])
				if not mechanics.is_empty():
					_packs.append(pk)

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
			if has_mech("glazed"):
				em_list = _glaze_mods(em_list)
		var d2 := ed
		if i > 0 and rng.randf() < 0.25:
			var alt: Dictionary = Data.enemies.get(_weighted_enemy(pool), {})
			if not alt.is_empty() and not alt.has("pack"):
				d2 = alt
		var e = spawn_enemy(d2, lvl, em_list, pos)
		e.room_id = room_id
		if has_mech("glazed") and e.is_elite and not e.is_miniboss:
			e.make_glazed(glaze_tune)
			e.damage_mult *= float(glaze_tune.get("elite_damage", 1.0))
			mech_stats["glazed"] += 1
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
	var ids := _elite_mod_ids()
	var out := []
	for i in n:
		if ids.is_empty():
			break
		var id: String = ids[rng.randi() % ids.size()]
		ids.erase(id)
		out.append(id)
	return out

## The elite modifier ids elites can roll: all, or the run's pool (Atelier Connoisseur's Eye).
func _elite_mod_ids() -> Array:
	var pool: Array = def.get("elite_pool", [])
	if not pool.is_empty():
		return pool.duplicate()
	var ids := []
	for m in Data.elite_mod_list:
		ids.append(m["id"])
	return ids

# ------------------------------------------------------------------ zone mechanics (Phase 1D)
func has_mech(id: String) -> bool:
	return mechanics.has(id)

## Glazed Elites: tops the modifier list up to min_layers (mech_rng, so the main stream is untouched).
func _glaze_mods(em_list: Array) -> Array:
	var want := clampi(maxi(em_list.size(), int(glaze_tune.get("min_layers", 2))), 1, int(glaze_tune.get("max_layers", 4)))
	var out := em_list.slice(0, want)
	var ids := []
	for id in _elite_mod_ids():
		if not out.has(id):
			ids.append(id)
	while out.size() < want and not ids.is_empty():
		out.append(ids.pop_at(mech_rng.randi_range(0, ids.size() - 1)))
	return out

## The Unfinished: pack_chance of the populated packs (at least min_packs) become sketches.
func _sketch_packs() -> void:
	var u: Dictionary = sketch_tune
	var pal: Array = u.get("palette", [])
	if pal.is_empty():
		return
	var packs := _packs.filter(func(pk): return not pk.is_empty())
	var pick := []
	var rest := []
	for pk in packs:
		if mech_rng.randf() < float(u.get("pack_chance", 0.35)):
			pick.append(pk)
		else:
			rest.append(pk)
	while pick.size() < int(u.get("min_packs", 3)) and not rest.is_empty():
		pick.append(rest.pop_at(mech_rng.randi_range(0, rest.size() - 1)))
	var n := AtlasRules.sketch_colours(int(def.get("atlas_ring", 1)), rot, u)
	for pk in pick:
		var choice := pal.duplicate()
		var cols := []
		while cols.size() < n and not choice.is_empty():
			cols.append(choice.pop_at(mech_rng.randi_range(0, choice.size() - 1)))
		for e in pk:
			if is_instance_valid(e) and e.alive:
				e.make_sketch(cols, u)
				e.damage_mult *= float(u.get("sketch_damage", 1.0))
				mech_stats["sketches"] += 1
		mech_stats["sketch_packs"] += 1

func on_glaze_peel(e, _m: Dictionary) -> void:
	var n := 1 + int(glaze_tune.get("peel_flakes", 0))
	mech_stats["peels"] += 1
	mech_stats["flakes"] += n
	spawn_drop({"kind": "material", "id": "glaze_flake", "amount": n}, e.global_position)

## A glazed elite died: its remaining layers shatter by kill speed; all layers gone = full-glaze bonus.
func on_glaze_death(e, shattered: int) -> void:
	var g: Dictionary = glaze_tune
	var n := shattered * (1 + int(g.get("shatter_flakes", 0)))
	mech_stats["shattered"] = int(mech_stats.get("shattered", 0)) + shattered
	if e.glaze_peeled + shattered >= e.glaze_total:
		n += int(g.get("full_bonus", 1)) + int(floor(rot / 2.0))
		mech_stats["full_peels"] += 1
		e.loot_rarity_extra += float(g.get("full_rarity_bonus", 150))
	mech_stats["ttk_sum"] = float(mech_stats.get("ttk_sum", 0.0)) + maxf(0.0, e.glaze_fight_t)
	mech_stats["glaze_kills"] = int(mech_stats.get("glaze_kills", 0)) + 1
	if n > 0:
		mech_stats["flakes"] += n
		spawn_drop({"kind": "material", "id": "glaze_flake", "amount": n}, e.global_position)
		if shattered > 0:
			add_fx(VFX.make("nova", e.global_position, Color(str(g.get("color", "#e0c890"))), 0.35, e.radius * 5.0))
			Combat.number(self, e.global_position + Vector2(0, -20), "Shattered x%d" % shattered, Color("#f0dca8"))

func on_sketch_painted(_e, by: String) -> void:
	mech_stats["painted" if by == "colour" else "filled"] += 1

func _mechanic_line() -> String:
	var out := []
	for m in mechanics:
		var l := _mech_line(m)
		if l != "":
			out.append(l)
	return "\n".join(out)

func _mech_line(m: String) -> String:
	match m:
		"glazed":
			return "Glazed Elites: %d peeled, %d shattered (%d fully), %d Flakes" % [int(mech_stats["peels"]), int(mech_stats["shattered"]), int(mech_stats["full_peels"]), int(mech_stats["flakes"])]
		"unfinished":
			var left := 0
			for e in enemies:
				if is_instance_valid(e) and "sketched" in e and e.sketched:
					left += 1
			return "The Unfinished: %d painted, %d sketches left" % [int(mech_stats["painted"]) + int(mech_stats["filled"]), left]
		"wager":
			return wager_line()
		"vault":
			return vault_line()
	return ""

func _place_hazards() -> void:
	var kinds: Array = def.get("hazards", [])
	if kinds.is_empty():
		return
	for r in _normal_rooms():
		if rng.randf() > float(def.get("hazard_rooms", 0.3)):
			continue
		var kind: String = kinds[rng.randi() % kinds.size()]
		var hpr: Array = def.get("hazards_per_room", [1, 3])
		for i in rng.randi_range(int(hpr[0]), int(hpr[1])):
			var h = Hazard.new()
			h.level = self
			h.setup(kind, monster_level)
			h.position = _room_floor(r)
			floor_layer.add_child(h)

# ------------------------------------------------------------------ objectives
func _setup_objectives() -> void:
	var list: Array = def.get("objectives", ["boss"]).duplicate()
	var opool: Array = def.get("objective_pool", [])
	if opool.size() > 0:
		list = (opool[rng.randi() % opool.size()] as Array).duplicate()
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
			if warden_name != "":
				return "Defeat %s" % warden_name
			if def.get("last_light", false):   # Atelier Last Light
				if last_light.get("active", false):
					return "Survive the Last Light (wave %d/%d)" % [int(last_light["wave"]), int(last_light["waves"])]
				return "Survive the Last Light in the arena"
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
	lines.append("Monsters remaining: %d" % enemies.filter(func(e): return is_instance_valid(e) and not e.def.get("object", false)).size())
	if mechanic != "":
		lines.append(_mechanic_line())
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
	if is_zone:
		zone_sleep_t -= delta
		if zone_sleep_t <= 0:
			zone_sleep_t = 0.25
			update_sleep()
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
		_tick_waves(delta)
	if not boss_dead:
		run_t += delta
		if boss_t >= 0.0:
			boss_t += delta
	if wager.get("state", "") == "active":
		_tick_wager(delta)

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
	if def.get("last_light", false):
		_start_last_light(r)
		return
	boss_spawned = true
	var bd: Dictionary = Data.enemies.get(_boss_id(), {})
	if bd.is_empty():
		return
	var blvl := monster_level + 1
	if def.get("heart", false):
		bd = AtlasRules.heart_def(bd, def.get("heart_mutations", []))
		bd["life"] = float(bd.get("life", 100)) * float(def.get("heart_life", 1.0))   # Atelier Ripened Hearts
	var bmods := []
	if warden > 0:
		bd = AtlasRules.warden_def(bd, warden)
		blvl += int(AtlasRules.ward_cfg().get("level_bonus", 2))
		bd["life"] = float(bd.get("life", 100)) * float(afx.get("warden_life", 1.0))   # Atelier Shard Seeker
	elif int(afx.get("boss_elite_mods", 0)) > 0 and atlas_hex != "":
		# Atelier Crowned Bosses: elite modifiers on the boss (the miniboss path: no elite life x2.6)
		bmods = _roll_elite_mods(int(afx["boss_elite_mods"]))
		bd = bd.duplicate(true)
		bd["miniboss"] = true
	var pos := cell_center(r["anchor"])
	boss = spawn_enemy(bd, blvl, bmods, pos)
	boss.aggro = true
	boss_t = 0.0
	add_fx(VFX.make("nova", pos, Color(bd.get("light", "#60d0c0")), 0.9, 80))
	shake(3.0)
	Events.boss_spawned.emit(boss)
	Sfx.play("boss", 0.0)
	Events.message.emit("%s awakens!" % bd["name"], Color("#ff6060"))
	if bd.get("heart", false):
		var names := []
		for m in bd.get("heart_applied", []):
			names.append(str(m.get("name", "")))
		Events.message.emit("The Rot has mutated it: %s" % ", ".join(names), Color("#b0e050"))

# ------------------------------------------------------------------ Last Light (Atelier, Phase 3B)
## Bare Canvas tip: an ordinary Atlas zone has no boss. Entering the arena starts waves of packs,
## each led by a Lantern-bearer (atlas.json atelier.last_light). The last kill of the last wave is
## the zone's boss death (_on_boss_dead), so the clear, Rot, shards, Guild and loot all follow.
func _ll_cfg() -> Dictionary:
	return AtlasRules.atelier_cfg().get("last_light", {})

func _start_last_light(r: Dictionary) -> void:
	boss_spawned = true
	var ll := _ll_cfg()
	last_light = {"active": true, "wave": 0, "waves": maxi(1, int(ll.get("waves", 3)) + int(afx.get("last_chamber_packs", 0))),
		"members": [], "leaders": [], "leader_t0": {}, "times": [], "anchor": r["anchor"], "room": r["id"], "killed": 0}
	boss_t = 0.0
	var pos := cell_center(r["anchor"])
	add_fx(VFX.make("nova", pos, Color(str(ll.get("color", "#ffe9a8"))), 0.9, 90))
	shake(2.0)
	Sfx.play("boss", 0.0)
	Events.message.emit("The Last Light wakes: %d packs come out of the dark." % int(last_light["waves"]), Color(str(ll.get("color", "#ffe9a8"))))
	_ll_next_wave()

func _ll_next_wave() -> void:
	var ll := _ll_cfg()
	last_light["wave"] = int(last_light["wave"]) + 1
	var anchor: Vector2i = last_light["anchor"]
	var pool: Array = def.get("pool", [])
	var em: Array = def.get("elite_mods", [1, 2])
	var lvl := monster_level + 1
	var spawned := []
	var ne := maxi(1, int(ll.get("elites", 2)))
	for i in ne:
		var ed: Dictionary = Data.enemies.get(_weighted_enemy(pool), {})
		if ed.is_empty():
			continue
		var leader := i == 0
		var n := rng.randi_range(int(em[0]), int(em[1])) + (int(ll.get("leader_mods", 2)) if leader else 0)
		var em_list := _roll_elite_mods(n)
		if has_mech("glazed"):
			em_list = _glaze_mods(em_list)
		var e = spawn_enemy(ed, lvl + (int(ll.get("leader_level", 1)) if leader else 0), em_list, random_floor_near(anchor, 3))
		if leader:
			e.max_life *= float(ll.get("leader_life", 2.5))
			e.life = e.max_life
			e.display_name = "%s, %s" % [str(ed.get("name", "")), str(ll.get("name", "Lantern-bearer"))]
			last_light["leaders"].append(e)
			last_light["leader_t0"][e.get_instance_id()] = run_t
		if has_mech("glazed") and e.is_elite and not e.is_miniboss:
			e.make_glazed(glaze_tune)
			e.damage_mult *= float(glaze_tune.get("elite_damage", 1.0))
			mech_stats["glazed"] += 1
		spawned.append(e)
	var ps: Array = ll.get("pack_size", [3, 5])
	var cnt := int(round(rng.randi_range(int(ps[0]), int(ps[1])) * density))
	for i in cnt:
		var ed: Dictionary = Data.enemies.get(_weighted_enemy(pool), {})
		if not ed.is_empty():
			spawned.append(spawn_enemy(ed, monster_level, [], random_floor_near(anchor, 3)))
	for e in spawned:
		e.room_id = int(last_light["room"])
		e.aggro = true
		total_enemies += 1
		last_light["members"].append(e)
	Events.message.emit("Wave %d of %d: a %s approaches" % [int(last_light["wave"]), int(last_light["waves"]), str(ll.get("name", "Lantern-bearer"))], Color(str(ll.get("color", "#ffe9a8"))))
	Events.objective_changed.emit(objective_text())

## Alive members of the Last Light waves.
func _ll_alive() -> Array:
	return last_light.get("members", []).filter(func(m): return is_instance_valid(m) and m.alive)

func _ll_on_kill(e) -> void:
	var ll := _ll_cfg()
	if not last_light["members"].has(e):
		Events.objective_changed.emit(objective_text())
		return
	last_light["killed"] = int(last_light["killed"]) + 1
	if last_light["leaders"].has(e):
		var t0 := float(last_light["leader_t0"].get(e.get_instance_id(), run_t))
		last_light["times"].append(run_t - t0)
		for i in int(ll.get("leader_rares", 1)):
			spawn_drop({"kind": "item", "item": Loot.roll_item(monster_level + 1, 300.0 + rarity_bonus(), player.ch.class_id, "rare")}, e.global_position)
	var alive := _ll_alive()
	if int(last_light["wave"]) < int(last_light["waves"]):
		# the next wave comes when the waves alive are down to next_at monsters
		if alive.size() <= int(ll.get("next_at", 1)):
			_ll_next_wave()
		else:
			Events.objective_changed.emit(objective_text())
		return
	if alive.is_empty():
		last_light["active"] = false
		last_light["done"] = true
		_on_boss_dead(e)
	else:
		Events.objective_changed.emit(objective_text())

# ------------------------------------------------------------------ zone: pack sleeping
func chamber_at(p: Vector2) -> int:
	if cell_zone.size() != gw * gh:
		return 255
	var c := to_cell(p)
	if c.x < 0 or c.y < 0 or c.x >= gw or c.y >= gh:
		return 255
	return cell_zone[c.y * gw + c.x]

## Chamber-graph distance from chamber `from` to every chamber (cached per chamber).
func chamber_dist(from: int) -> Array:
	if from == _dist_from:
		return _chamber_dist
	var dist := []
	dist.resize(zone_adj.size())
	dist.fill(99)
	if from < zone_adj.size():
		dist[from] = 0
		var q := [from]
		var head := 0
		while head < q.size():
			var c: int = q[head]
			head += 1
			for n in zone_adj[c]:
				if int(dist[n]) > int(dist[c]) + 1:
					dist[n] = int(dist[c]) + 1
					q.append(int(n))
	_dist_from = from
	_chamber_dist = dist
	return dist

## Enemies more than `wake_chambers` links from the player's chamber sleep: no AI, no
## physics body. Aggro'd enemies get one extra link; bosses and anything within
## `wake_radius` units (default 0 = off) always stay awake. Unlinked chambers sleep even when
## they are next to the player's: the generator keeps 6+ cells of rock between them.
func update_sleep() -> void:
	if player == null or not is_instance_valid(player):
		return
	var pc := chamber_at(player.global_position)
	if pc == 255:
		return
	var dist := chamber_dist(pc)
	var wake := int(def.get("wake_chambers", 1))
	var wr := float(def.get("wake_radius", 0.0))
	var pp: Vector2 = player.global_position
	var n := 0
	awake_pool.clear()
	for e in enemies:
		if not is_instance_valid(e) or not e.alive:
			continue
		var ec := chamber_at(e.global_position)
		var cd: int = int(dist[ec]) if ec < dist.size() else 99
		var awake: bool = cd <= wake or (e.aggro and cd <= wake + 1) or e.is_boss or e.global_position.distance_to(pp) < wr
		var want := Node.PROCESS_MODE_INHERIT if awake else Node.PROCESS_MODE_DISABLED
		if e.process_mode != want:
			e.process_mode = want
		if not awake:
			n += 1
		else:
			awake_pool.append(e)
	sleeping = n

func separation_pool() -> Array:
	return awake_pool if is_zone else enemies

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
	if e.def.get("object", false):   # Endgame 2D: a vault wall was scraped away
		_on_vault_wall(e)
		Events.objective_changed.emit(objective_text())
		return
	if not boss_dead:
		zone_kills += 1
	if wager.get("state", "") == "active":
		_wager_kill(e)
	if not vaults.is_empty():
		_vault_kill(e)
	if "painted_by" in e and e.painted_by != "":
		var u: Dictionary = sketch_tune
		var dn := int(u.get("dust", 1)) * (int(u.get("elite_dust", 2)) if e.is_elite else 1)
		if e.painted_by != "colour":
			# filled in by raw hits (Phase 1E): a chance at 1 Dust (elites always)
			dn = 1 if (e.is_elite or mech_rng.randf() < float(u.get("filled_dust_chance", 0.0))) else 0
		var dm := float(afx.get("dust_mult", 1.0))
		if dn > 0 and dm != 1.0:   # Atelier Loose Sketching: x dust_mult, seeded rounding
			var x := dn * dm
			dn = int(floor(x)) + (1 if mech_rng.randf() < x - floor(x) else 0)
		if dn > 0:
			mech_stats["dust"] += dn
			spawn_drop({"kind": "material", "id": "pigment_dust", "amount": dn}, e.global_position)
	if atlas_hex != "" and e.is_elite and not boss_dead and e != boss:
		elite_kills += 1
		if bool(afx.get("first_elite_rare", false)) and not first_elite_done:   # Atelier First Blood
			first_elite_done = true
			spawn_drop({"kind": "item", "item": Loot.roll_item(monster_level, 200.0 + rarity_bonus(), player.ch.class_id, "rare")}, e.global_position)
	if last_light.get("active", false):
		_ll_on_kill(e)
		return
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
	# zone spike and Atlas runs: no dungeon first-kill point, no tier unlock (the Atlas rewards
	# exploration instead: a clear reveals the neighbouring hexes)
	var spike: bool = def.get("spike", false) or atlas_hex != ""
	boss_fight = boss_t
	if wager.get("state", "") == "active":
		_wager_boss_dead()
	if atlas_hex != "":
		var res := AtlasRules.complete_run(AtlasRules.ensure(ch), AtlasRules.parse(atlas_hex))
		atlas_revealed = res["revealed"]
		rot_spread = res["spread"]
		ch.progress["atlas_clears"] = int(ch.progress.get("atlas_clears", 0)) + 1
		if not atlas_revealed.is_empty():
			Events.message.emit("The Atlas grows: %d new region%s revealed" % [atlas_revealed.size(), "" if atlas_revealed.size() == 1 else "s"], Color("#e8c890"))
		if not rot_spread.is_empty():
			Events.message.emit("The Rot spreads to %d region%s" % [rot_spread.size(), "" if rot_spread.size() == 1 else "s"], Color("#b0d060"))
		if warden > 0:
			_on_warden_dead(e)
		else:
			_roll_shard()
		_credit_guild()
		if def.get("heart", false):
			markers["rot_restore"] = _add_portal(clamp_to_floor(e.global_position, e.global_position + Vector2(-56, -24)), "Restore the Region", "rot_restore", Color(str(AtlasRules.rot_cfg().get("colors", {}).get("restored", "#e8c060"))))
			markers["rot_harvest"] = _add_portal(clamp_to_floor(e.global_position, e.global_position + Vector2(56, -24)), "Harvest the Heart", "rot_harvest", Color(str(AtlasRules.rot_cfg().get("colors", {}).get("heart", "#b0e050"))))
			Events.message.emit("The Heart of Rot lies still. Restore the region, or harvest the Heart?", Color("#b0e050"))
	if not spike:
		var key: String = def["id"]
		var first: bool = not ch.progress["bosses_killed"].has(key)
		ch.progress["bosses_killed"][key] = int(ch.progress["bosses_killed"].get(key, 0)) + 1
		if first:
			ch.bonus_passive_points += 1
			Events.message.emit("First victory: +1 Passive Skill Point!", Color("#ffd040"))
	ch.add_xp(int(60 * monster_level * int(def.get("tier", 1)) * xp_bonus()))
	if not spike:
		ch.progress["highest_tier"] = mini(6, maxi(int(ch.progress.get("highest_tier", 1)), int(def.get("tier", 1)) + 1))
	# tier rewards: extra loot, legendary chance at the highest tiers
	var tier := int(def.get("tier", 1))
	for i in tier - 1 + int(depth / 2.0):
		spawn_drop({"kind": "item", "item": Loot.roll_item(monster_level + 1, 300.0 + rarity_bonus(), ch.class_id)}, e.global_position)
	if tier >= 5 and rng.randf() < 0.25 + 0.03 * depth:
		spawn_drop({"kind": "item", "item": Loot.roll_item(monster_level + 1, 0.0, ch.class_id, "legendary")}, e.global_position)
	if atlas_hex != "" and warden == 0 and last_light.is_empty():   # Atelier Crowned Bosses
		for i in int(afx.get("boss_rares", 0)):
			spawn_drop({"kind": "item", "item": Loot.roll_item(monster_level + 1, 300.0 + rarity_bonus(), ch.class_id, "rare")}, e.global_position)
	if def.get("endless", false):
		if not ch.dev_used:   # developer-tainted characters never set depth records
			var abyss_pts: int = ch.abyss_passive_points()
			ch.progress["abyss_best"] = maxi(int(ch.progress.get("abyss_best", 0)), depth)
			if ch.abyss_passive_points() > abyss_pts:
				Events.message.emit("Abyss depth %d: +1 Passive Skill Point!" % depth, Color("#ffd040"))
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
	elif k == "collector":
		if Game.main != null and Game.main.ui != null:
			Game.main.ui.open("wager")
	elif k.begins_with("vault_sigil_"):
		strike_sigil(k)
	elif k == "rot_restore" or k == "rot_harvest":
		choose_heart("restore" if k == "rot_restore" else "harvest")
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

# ------------------------------------------------------------------ Rot (Phase 1C)
## The Heart choice after a Heart of Rot dies. Restore: the hex goes to Rot 0 and is Restored
## (Rot never enters it again). Harvest: a payout now, the hex keeps its Rot and the next
## spread gets an extra front. One choice per run.
func choose_heart(choice: String) -> bool:
	if heart_choice != "" or not boss_dead or not def.get("heart", false) or atlas_hex == "":
		return false
	var st: Dictionary = AtlasRules.ensure(player.ch)
	var h := AtlasRules.parse(atlas_hex)
	heart_choice = choice
	var pos: Vector2 = player.global_position
	_take_interactable("rot_restore")
	_take_interactable("rot_harvest")
	var hrep := {"zones": 0, "ring": AtlasRules.ring_of(h), "rot": rot}
	hrep[choice] = 1
	_announce_guild(GuildRules.credit(st, hrep))
	if choice == "restore":
		var eased := AtlasRules.restore(st, h)
		add_fx(VFX.make("nova", pos, Color("#e8c060"), 0.9, 90))
		Events.message.emit("The region is restored. Rot will never take it again.", Color("#e8c060"))
		if not eased.is_empty():   # Atelier Gilded Firebreak
			Events.message.emit("The gilding eases the Rot in %d neighbouring region%s." % [eased.size(), "" if eased.size() == 1 else "s"], Color("#e8c060"))
		_restore_payout(st, h, pos)
	else:
		AtlasRules.fester(st, h)
		_harvest_payout(pos)
		add_fx(VFX.make("nova", pos, Color("#b0e050"), 0.9, 90))
		Events.message.emit("You harvest the Heart. The Rot festers and will spread faster.", Color("#b0e050"))
	Sfx.play("portal", 0.0)
	Game.save_game()
	return true

## Restore payout from the Atelier (none without nodes): Ripened Hearts' material rolls per Rot
## level, Shard of the Restored's Ground Shard chance (seeded by atlas seed, hex and clears).
func _restore_payout(st: Dictionary, h: Vector2i, pos: Vector2) -> void:
	for i in maxi(1, rot) * int(afx.get("heart_material_rolls", 0)):
		spawn_drop({"kind": "material", "id": Loot._roll_material(), "amount": 1}, pos)
	var sc := float(afx.get("restore_shard_chance", 0.0))
	if sc > 0.0 and AtlasRules._rng(int(st.get("seed", 1)), h, 650 + AtlasRules.clears(st, h)).randf() < sc:
		var ring := AtlasRules.ring_of(h)
		if AtlasRules.add_shards(st, ring, 1) > 0:
			var wc := AtlasRules.warden_cfg(ring)
			Events.message.emit("%s found in the restored region (%d/%d)" % [str(wc.get("shard", "Ground Shard")), AtlasRules.shards(st, ring), AtlasRules.summon_cost(st)], Color(str(AtlasRules.ward_cfg().get("colors", {}).get("shard", "#e8d8a0"))))

func _harvest_payout(pos: Vector2) -> void:
	var hv: Dictionary = AtlasRules.rot_cfg().get("harvest", {})
	var n := maxi(1, rot)
	var cid: String = player.ch.class_id
	spawn_drop({"kind": "item", "item": Loot.roll_item(monster_level + 1, 0.0, cid, "legendary")}, pos)
	spawn_drop({"kind": "gold", "amount": int(round(monster_level * int(hv.get("gold_per_level", 30)) * n * float(afx.get("harvest_gold_mult", 1.0))))}, pos)
	for i in n * (int(hv.get("material_rolls", 3)) + int(afx.get("heart_material_rolls", 0))):
		spawn_drop({"kind": "material", "id": Loot._roll_material(), "amount": 1}, pos)
	for i in int(afx.get("harvest_gems", 0)):   # Atelier Gemmed Harvest
		spawn_drop({"kind": "gem", "id": Loot.random_gem(monster_level)}, pos)
	for i in maxi(0, n - 2):
		spawn_drop({"kind": "gem", "id": Loot.random_gem(monster_level)}, pos)
		spawn_drop({"kind": "item", "item": Loot.roll_item(monster_level + 1, 300.0 + rarity_bonus(), cid, "rare")}, pos)

# ------------------------------------------------------------------ Commission Board (Phase 2C)
## The zone was completed: credit the run report to the Restorers' Guild contracts.
func _credit_guild() -> void:
	var st: Dictionary = AtlasRules.ensure(player.ch)
	guild_report = {"zones": 1, "ring": AtlasRules.ring_of(AtlasRules.parse(atlas_hex)), "rot": rot,
		"hearts": 1 if def.get("heart", false) else 0, "peels": int(mech_stats["peels"]),
		"painted": int(mech_stats["painted"]) + int(mech_stats["filled"]), "elites": elite_kills,
		"pigment_zones": 1 if not pigment_uids.is_empty() else 0, "wardens": 1 if warden > 0 else 0,
		"kills": zone_kills, "bosses": 1 if last_light.is_empty() else last_light.get("times", []).size(), "time": run_t, "boss_time": boss_fight if boss_fight >= 0.0 else 9999.0,
		"pigments": pigment_uids.size(), "wagers_won": int(wv_stats["wagers_won"]), "wager_3x": int(wv_stats["wager_3x"]),
		"vaults": int(wv_stats["vaults"]), "trap_vaults": int(wv_stats["trap_vaults"]), "riddle_vaults": int(wv_stats["riddle_vaults"])}
	if not last_light.is_empty():
		guild_report["boss_times"] = last_light.get("times", []).duplicate()   # each Lantern-bearer counts as a boss
	guild_result = GuildRules.credit(st, guild_report)
	_announce_guild(guild_result)

func _announce_guild(res: Dictionary) -> void:
	var col := Color(str(GuildRules.cfg().get("colors", {}).get("rep", "#e8c060")))
	for t in res.get("completed", []):
		Events.message.emit("Commission complete: %s" % t, col)
	if int(res.get("rep", 0)) > 0:
		Events.message.emit("+%d Guild reputation, +%d Seals - see %s in the Sanctuary" % [int(res["rep"]), int(res["seals"]), str(GuildRules.cfg().get("npc", {}).get("name", "the Guild"))], col)
	if int(res.get("rank_up", 0)) > 0:
		var r := int(res["rank_up"])
		Events.message.emit("Restorers' Guild rank %d: %s! %s" % [r, GuildRules.rank_name(r), str(GuildRules.rank_info(r).get("desc", ""))], Color("#ffd040"))

# ------------------------------------------------------------------ Layer Wardens (Phase 2A)
## A normal Atlas clear can drop a Ground Shard of the ring's layer (seeded; Hearts always).
func _roll_shard() -> void:
	var st: Dictionary = AtlasRules.ensure(player.ch)
	var h := AtlasRules.parse(atlas_hex)
	shard_drop = AtlasRules.roll_shard(st, h, rot, def.get("heart", false))
	if shard_drop > 0:
		var ring := AtlasRules.ring_of(h)
		var wc := AtlasRules.warden_cfg(ring)
		var need := AtlasRules.summon_cost(st)
		var have := AtlasRules.shards(st, ring)
		var tail := " - summon the Warden from the Atlas!" if have >= need and AtlasRules.summoned_hex(st, ring) == "" else ""
		Events.message.emit("%s found (%d/%d)%s" % [str(wc.get("shard", "Ground Shard")), have, need, tail], Color(str(AtlasRules.ward_cfg().get("colors", {}).get("shard", "#e8d8a0"))))

## The Warden is dead: spend the shards, roll the Ground Pigment, first-kill passive point, loot.
func _on_warden_dead(e) -> void:
	var ch = player.ch
	var st: Dictionary = AtlasRules.ensure(ch)
	var wc := AtlasRules.warden_cfg(warden)
	var wcfg := AtlasRules.ward_cfg()
	warden_result = AtlasRules.warden_victory(st, warden, rot)
	var gold := Color(str(wcfg.get("colors", {}).get("summon", "#ffe070")))
	if warden_result.get("ground", false):
		Events.message.emit("%s obtained! Ground Pigments: %d of %d layers (%d open the pinnacle)" % [str(wc.get("ground", "Ground Pigment")), AtlasRules.ground_kinds(st), int(wcfg.get("layers_total", 6)), int(wcfg.get("pinnacle_need", 4))], gold)
	if int(warden_result.get("rot_shards", 0)) > 0:   # Atelier Rot-Fed Wardens
		Events.message.emit("The Rot feeds the Warden's remains: +%d %s" % [int(warden_result["rot_shards"]), str(wc.get("shard", "Ground Shard"))], gold)
	var pk := "atlas_warden_%d" % warden
	var first: bool = not ch.progress["bosses_killed"].has(pk)
	ch.progress["bosses_killed"][pk] = int(ch.progress["bosses_killed"].get(pk, 0)) + 1
	if first and wcfg.get("passive_point", true):
		ch.bonus_passive_points += 1
		Events.message.emit("First victory over %s: +1 Passive Skill Point!" % str(wc.get("title", "the Warden")), Color("#ffd040"))
	var rw: Dictionary = wcfg.get("reward", {})
	var pos: Vector2 = e.global_position
	var cid: String = ch.class_id
	for i in int(rw.get("legendary", 1)):
		spawn_drop({"kind": "item", "item": Loot.roll_item(monster_level + 1, 0.0, cid, "legendary")}, pos)
	for i in int(rw.get("rares", 2)) + int(afx.get("warden_rares", 0)):
		spawn_drop({"kind": "item", "item": Loot.roll_item(monster_level + 1, float(rw.get("rarity", 300)) + rarity_bonus(), cid, "rare")}, pos)
	spawn_drop({"kind": "gold", "amount": monster_level * int(rw.get("gold_per_level", 40))}, pos)
	add_fx(VFX.make("nova", pos, gold, 1.0, 110))

## Endgame 2B: item drops in an Atlas zone at Rot 4+ may be Rot-touched (own stream).
func _on_item_drop(it: Dictionary) -> void:
	if atlas_hex == "" or rot <= 0:
		return
	if AtlasCraft.roll(it, rot, rot_rng):
		rot_touched += 1

## Death in an Atlas zone before the boss dies: +1 Rot on the hex (once per run).
## Returns the hex's new Rot, or -1 when it did not change.
func apply_death_rot() -> int:
	if death_rot != -2:
		return death_rot
	death_rot = -1
	if atlas_hex != "" and player != null:   # Endgame 2D: a death loses the wager and breaks streak contracts
		if wager.get("state", "") == "active":
			_wager_lose("You fell")
		if GuildRules.on_death(AtlasRules.ensure(player.ch)) > 0:
			Events.message.emit("Your fall breaks a Commission streak", Color("#ff8080"))
	if atlas_hex == "" or boss_dead or player == null:
		return death_rot
	if not death_charged and not pigment_uids.is_empty() and not bool(afx.get("death_no_charge", false)):   # Phase 1E: a death spends extra Pigment charges (not with the Atelier's Steady Hand)
		death_charged = true
		AtlasRules.spend_pigments(AtlasRules.ensure(player.ch), pigment_uids, int(AtlasRules.pig_cfg().get("death_charges", 1)))
	death_rot = AtlasRules.add_death_rot(AtlasRules.ensure(player.ch), AtlasRules.parse(atlas_hex))
	return death_rot

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

func _tick_waves(delta: float = 0.0) -> void:
	var alive: Array = wave_state["alive"].filter(func(e): return is_instance_valid(e) and e.alive)
	wave_state["alive"] = alive
	_rescue_wave_enemies(alive, delta)
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

## Safety net for the Blood Altar: a wave enemy that the player cannot reach (inside rock,
## outside the grid, or in a floor pocket with no path) would keep the arena sealed forever.
## After 3 s without a path (accumulated; free time only slowly cancels it) it is moved back
## to the floor next to the altar.
const WAVE_RESCUE_AFTER := 3.0

func _rescue_wave_enemies(alive: Array, delta: float) -> void:
	if player == null or not is_instance_valid(player) or not player.alive:
		return
	var altar: Vector2 = wave_state["pos"]
	if player.global_position.distance_to(altar) > 640.0:
		return    # the player walked away; the flow field does not cover the altar
	if flow_value(to_cell(player.global_position)) < 0:
		return    # flow field not valid this frame (player mid-roll over a wall edge)
	var lost: Dictionary = wave_state.get("lost", {})
	for e in alive:
		var id: int = e.get_instance_id()
		var stuck: bool = is_solid(e.global_position) or flow_value(to_cell(e.global_position)) < 0
		if not stuck:
			# slow decay: an enemy that keeps slipping back into the rock still adds up
			var left: float = float(lost.get(id, 0.0)) - delta * 0.25
			if left <= 0.0:
				lost.erase(id)
			else:
				lost[id] = left
			continue
		lost[id] = float(lost.get(id, 0.0)) + delta
		if lost[id] >= WAVE_RESCUE_AFTER:
			lost.erase(id)
			e.global_position = random_floor_near(to_cell(altar), 2)
			e.velocity = Vector2.ZERO
			if "knock" in e:
				e.knock = Vector2.ZERO
			add_fx(VFX.make("ring", e.global_position, Color("#ff4040"), 0.5, 20))
	wave_state["lost"] = lost

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

func cleanup() -> void:
	_wager_disconnect()
	super.cleanup()

# ------------------------------------------------------------------ Endgame 2D: helpers on mech_rng
## A floor cell of room r picked with mech_rng (the main stream stays untouched).
func _mech_floor(r: Dictionary) -> Vector2:
	var rect: Rect2i = r["rect"]
	for i in 60:
		var c := Vector2i(mech_rng.randi_range(rect.position.x + 2, rect.end.x - 3), mech_rng.randi_range(rect.position.y + 2, rect.end.y - 3))
		if cell(c.x, c.y) == FLOOR and cell(c.x + 1, c.y) == FLOOR and cell(c.x - 1, c.y) == FLOOR and cell(c.x, c.y + 1) == FLOOR and cell(c.x, c.y - 1) == FLOOR:
			return cell_center(c)
	return cell_center(r["anchor"])

func _mech_enemy_id(pool: Array) -> String:
	var total := 0.0
	for p in pool:
		total += float(p.get("w", 10))
	var roll := mech_rng.randf() * total
	for p in pool:
		roll -= float(p.get("w", 10))
		if roll <= 0:
			return p["id"]
	return pool[0]["id"] if pool.size() > 0 else "ghoul"

func _mech_elite_mods(n: int) -> Array:
	var ids := []
	for m in Data.elite_mod_list:
		ids.append(m["id"])
	var out := []
	while out.size() < n and not ids.is_empty():
		out.append(ids.pop_at(mech_rng.randi_range(0, ids.size() - 1)))
	return out

func _boss_chamber_links(from: Vector2) -> int:
	if not is_zone:
		return 3
	var a := chamber_at(from)
	var b := chamber_at(cell_center(rooms[layout["boss"]]["anchor"]))
	if a == 255 or b == 255:
		return 3
	var d: Array = chamber_dist(a)
	return int(d[b]) if b < d.size() and int(d[b]) < 99 else 3

# ------------------------------------------------------------------ Endgame 2D: the Collector's Wager
## The Collector stands in a mid-depth chamber; the bets on offer are drawn now (seeded).
func _place_collector() -> void:
	var normals := _normal_rooms()
	if normals.is_empty():
		return
	normals.sort_custom(func(a, b): return a["depth"] < b["depth"])
	var lo := int(normals.size() / 3.0)
	var hi := maxi(lo, normals.size() - 1 - int(normals.size() / 3.0))
	var room: Dictionary = normals[mech_rng.randi_range(lo, hi)]
	collector_pos = _mech_floor(room)
	var col := Color(str(AtlasRules.mechanic_info("wager").get("color", "#c89be8")))
	markers["collector"] = _add_portal(collector_pos, "The Collector", "collector", col, "npc_collector")
	# Phase 2E: only what is still ahead counts (rooms at least as deep as the Collector's), so
	# "next elite" / Frenzy bets are never offered with nothing left to kill before the boss
	var depth_of := {}
	for r in rooms:
		depth_of[int(r.get("id", -1))] = int(r.get("depth", 0))
	var elites := 0
	var ahead := 0
	for e in enemies:
		if not is_instance_valid(e) or e.is_boss or e.def.get("object", false):
			continue
		if int(depth_of.get(int(e.room_id), -1)) < int(room.get("depth", 0)):
			continue
		ahead += 1
		if e.is_elite:
			elites += 1
	var ids := WV.offers(mech_rng, mechanics, elites, -1, ahead, _ll_cfg().get("no_bets", []) if def.get("last_light", false) else [])
	var links := _boss_chamber_links(collector_pos)
	var lim := {}
	for id in ids:
		lim[id] = WV.limits(id, links)
	wager = {"state": "offer", "offers": ids, "lim": lim, "elites": elites, "ahead": ahead}

## The stake multipliers the Collector accepts here (the Atelier's High Stakes adds 4x).
func wager_mults() -> Array:
	return WV.mults(int(afx.get("wager_max_mult", 0)))

## Takes the bet: the stake is paid now. Returns "" or why not.
func accept_wager(id: String, mult: int) -> String:
	if wager.get("state", "") != "offer":
		return "The Collector has no bet to offer"
	if not wager["offers"].has(id) or not wager_mults().has(mult):
		return "No such bet"
	if boss_dead or player == null or not player.alive:
		return "Too late for that"
	var nope := wager_refusal(id)
	if nope != "":
		return nope
	var ch = player.ch
	var why := WV.stake_refusal(int(ch.gold), monster_level, mult)
	if why != "":
		return why
	var st := WV.stake(monster_level, mult)
	ch.gold = int(ch.gold) - st
	Events.currency_changed.emit()
	wager["state"] = "active"
	wager["bet"] = id
	wager["mult"] = mult
	wager["stake"] = st
	wager["t"] = 0.0
	wager["kills"] = 0
	wager["hits"] = 0
	wager["skills"] = {}
	wager["flasks0"] = int(player.flasks_used)
	wager["peels0"] = int(mech_stats["peels"])
	wager["painted0"] = int(mech_stats["painted"]) + int(mech_stats["filled"])
	wager["vaults0"] = int(wv_stats["vaults"])
	if not Events.player_damaged.is_connected(_on_wager_hurt):
		Events.player_damaged.connect(_on_wager_hurt)
	if not Events.player_skill_used.is_connected(_on_wager_skill):
		Events.player_skill_used.connect(_on_wager_skill)
	Sfx.play("pickup", 0.0)
	Events.message.emit("The Collector takes your %d gold: \"%s.\" (%dx)" % [st, wager_text(id), mult], Color(str(AtlasRules.mechanic_info("wager").get("color", "#c89be8"))))
	Events.objective_changed.emit(objective_text())
	return ""

## Phase 2E: a bet that can no longer be won is not taken (its vault was already opened, every
## elite is dead). "" = can be taken.
func wager_refusal(id: String) -> String:
	match id:
		"archaeology":
			var sealed := 0
			for v in vaults:
				if not v["open"]:
					sealed += 1
			if sealed < int(wager.get("lim", {}).get(id, {}).get("count", 1)):
				return "No sealed vault is left here"
		"unscathed":
			for e in enemies:
				if is_instance_valid(e) and e.alive and e.is_elite and not e.is_boss:
					return ""
			return "No elite is left here"
	return ""

func wager_text(id: String) -> String:
	return WV.text(id, wager.get("lim", {}).get(id, WV.limits(id)))

func _wager_lim() -> Dictionary:
	return wager.get("lim", {}).get(str(wager.get("bet", "")), {})

## Progress text of the active bet ("" when there is none).
func wager_progress() -> String:
	if wager.get("state", "") != "active":
		return ""
	var lim := _wager_lim()
	match str(wager["bet"]):
		"boss_rush":
			return "%d s left" % maxi(0, int(ceil(float(lim["time"]) - float(wager["t"]))))
		"frenzy":
			return "%d / %d, %d s left" % [int(wager["kills"]), int(lim["count"]), maxi(0, int(ceil(float(lim["time"]) - float(wager["t"]))))]
		"few_skills":
			return "skills used %d / %d" % [wager["skills"].size(), int(lim["skills"])]
		"unscathed":
			if int(lim.get("hits", 0)) > 0:
				return "hits taken %d / %d" % [int(wager.get("hits", 0)), int(lim["hits"])]
		"flaking":
			return "%d / %d" % [int(mech_stats["peels"]) - int(wager["peels0"]), int(lim["count"])]
		"colourist":
			if float(lim.get("time", 0)) > 0.0:
				return "%d / %d, %d s left" % [int(mech_stats["painted"]) + int(mech_stats["filled"]) - int(wager["painted0"]), int(lim["count"]), maxi(0, int(ceil(float(lim["time"]) - float(wager["t"]))))]
			return "%d / %d" % [int(mech_stats["painted"]) + int(mech_stats["filled"]) - int(wager["painted0"]), int(lim["count"])]
		"archaeology":
			if float(lim.get("time", 0)) > 0.0:
				return "%d / %d, %d s left" % [int(wv_stats["vaults"]) - int(wager["vaults0"]), int(lim["count"]), maxi(0, int(ceil(float(lim["time"]) - float(wager["t"]))))]
			return "%d / %d" % [int(wv_stats["vaults"]) - int(wager["vaults0"]), int(lim["count"])]
	return "in progress"

func wager_line() -> String:
	match str(wager.get("state", "")):
		"offer":
			return "The Collector's Wager: the Collector waits with %d bets" % wager["offers"].size()
		"active":
			return "The Collector's Wager (%dx, %d gold): %s - %s" % [int(wager["mult"]), int(wager["stake"]), wager_text(str(wager["bet"])), wager_progress()]
		"won":
			return "The Collector's Wager: won (%s)" % str(wager.get("why", ""))
		"lost":
			return "The Collector's Wager: lost (%s)" % str(wager.get("why", ""))
	return ""

func _tick_wager(delta: float) -> void:
	wager["t"] = float(wager["t"]) + delta
	var lim := _wager_lim()
	match str(wager["bet"]):
		"boss_rush", "frenzy":
			if float(wager["t"]) > float(lim.get("time", 0)):
				_wager_lose("out of time")
		"abstinence":
			if player != null and int(player.flasks_used) > int(wager["flasks0"]):
				_wager_lose("you drank a flask")
		"iron_will":
			if player != null and player.life < player.max_life * float(lim.get("life", 50)) / 100.0:
				_wager_lose("your life fell below %d%%" % int(lim.get("life", 50)))
		"flaking":
			if int(mech_stats["peels"]) - int(wager["peels0"]) >= int(lim.get("count", 1)):
				_wager_win()
		"colourist":
			if int(mech_stats["painted"]) + int(mech_stats["filled"]) - int(wager["painted0"]) >= int(lim.get("count", 1)):
				_wager_win()
		"archaeology":
			if int(wv_stats["vaults"]) - int(wager["vaults0"]) >= int(lim.get("count", 1)):
				_wager_win()
	# Phase 2E: count bets can carry a time limit (Archaeology, Colourist; Flaking if given one)
	if str(wager.get("state", "")) == "active" and str(wager["bet"]) in ["flaking", "colourist", "archaeology"]:
		if float(lim.get("time", 0)) > 0.0 and float(wager["t"]) > float(lim["time"]):
			_wager_lose("out of time")

func _on_wager_hurt(amount: float) -> void:
	if wager.get("state", "") != "active" or amount <= 0.0:
		return
	if str(wager["bet"]) == "unscathed":
		wager["hits"] = int(wager.get("hits", 0)) + 1   # Phase 2E: a small hit allowance (max_hits)
		if int(wager["hits"]) > int(_wager_lim().get("hits", 0)):
			_wager_lose("you were hit" if int(_wager_lim().get("hits", 0)) <= 0 else "you were hit %d times" % int(wager["hits"]))
	elif str(wager["bet"]) == "iron_will" and player != null and player.life < player.max_life * float(_wager_lim().get("life", 50)) / 100.0:
		_wager_lose("your life fell below %d%%" % int(_wager_lim().get("life", 50)))

func _on_wager_skill(skill_id: String) -> void:
	if wager.get("state", "") != "active" or str(wager["bet"]) != "few_skills":
		return
	wager["skills"][skill_id] = true
	if wager["skills"].size() > int(_wager_lim().get("skills", 2)):
		_wager_lose("you used a %s skill" % ["second", "third", "fourth", "fifth"][clampi(int(_wager_lim().get("skills", 2)) - 1, 0, 3)])

func _wager_kill(e) -> void:
	match str(wager["bet"]):
		"frenzy":
			wager["kills"] = int(wager["kills"]) + 1
			if int(wager["kills"]) >= int(_wager_lim().get("count", 25)):
				_wager_win()
		"unscathed":
			if e.is_elite and not e.is_boss:
				_wager_win()

func _wager_boss_dead() -> void:
	var id := str(wager["bet"])
	if WV.ends_at_boss(id):
		if id == "boss_rush" and float(wager["t"]) > float(_wager_lim().get("time", 0)):
			_wager_lose("out of time")
		else:
			_wager_win()
	else:
		_wager_lose("the zone boss fell first")

func _wager_end() -> void:
	_wager_disconnect()
	if markers.has("collector"):
		var p = markers["collector"]
		if is_instance_valid(p):
			add_fx(VFX.make("nova", p.global_position, Color(str(AtlasRules.mechanic_info("wager").get("color", "#c89be8"))), 0.6, 40))
		_take_interactable("collector")
	if Game.main != null and Game.main.ui != null and Game.main.ui.is_open("wager"):
		Game.main.ui.panels["wager"].refresh()
	Events.objective_changed.emit(objective_text())

func _wager_disconnect() -> void:
	if Events.player_damaged.is_connected(_on_wager_hurt):
		Events.player_damaged.disconnect(_on_wager_hurt)
	if Events.player_skill_used.is_connected(_on_wager_skill):
		Events.player_skill_used.disconnect(_on_wager_skill)

func _wager_win() -> void:
	if wager.get("state", "") != "active":
		return
	var id := str(wager["bet"])
	var mult := int(wager["mult"])
	var pay := WV.payout(id, monster_level, mult, rot)
	wager["state"] = "won"
	wager["why"] = "%dx" % mult
	wager["payout"] = pay
	wv_stats["wagers_won"] += 1
	if mult >= 3:
		wv_stats["wager_3x"] += 1
	var ch = player.ch
	ch.gold = int(ch.gold) + int(pay["gold"])
	Events.currency_changed.emit()
	var pos: Vector2 = player.global_position
	for i in int(pay["materials"]):
		spawn_drop({"kind": "material", "id": Loot._roll_material(), "amount": 1}, pos)
	if int(pay["flakes"]) > 0:
		spawn_drop({"kind": "material", "id": "glaze_flake", "amount": int(pay["flakes"])}, pos)
	if int(pay["dust"]) > 0:
		spawn_drop({"kind": "material", "id": "pigment_dust", "amount": int(pay["dust"])}, pos)
	if pay["rare"]:
		spawn_drop({"kind": "item", "item": Loot.roll_item(monster_level + 1, float(WV.wcfg().get("rare_rarity", 300)) + rarity_bonus(), ch.class_id, "rare")}, pos)
	Sfx.play("levelup", 0.0)
	Events.message.emit("The Collector pays out: %d gold and materials. \"Well played.\"" % int(pay["gold"]), Color("#ffd060"))
	_wager_end()

func _wager_lose(why: String) -> void:
	if wager.get("state", "") != "active":
		return
	wager["state"] = "lost"
	wager["why"] = why
	wv_stats["wagers_lost"] += 1
	Events.message.emit("Wager lost - %s. The Collector keeps your %d gold." % [why, int(wager["stake"])], Color("#ff8080"))
	_wager_end()

# ------------------------------------------------------------------ Endgame 2D: Pentimento Vaults
const _DIRS4 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

## Carves vault pockets into solid rock behind chamber walls (zones; before the world is built).
func _carve_vaults() -> void:
	var n := WV.vault_count(int(def.get("atlas_ring", 1)), rot)
	var cands := _normal_rooms()
	for i in range(cands.size() - 1, 0, -1):   # Fisher-Yates on mech_rng
		var j := mech_rng.randi_range(0, i)
		var tmp = cands[i]
		cands[i] = cands[j]
		cands[j] = tmp
	for r in cands:
		if vaults.size() >= n:
			break
		var v := _vault_site(r)
		if v.is_empty():
			continue
		v["type"] = WV.roll_type(mech_rng)
		for c in v["mouth"] + v["cells"]:
			grid[c.y * gw + c.x] = FLOOR
			if cell_zone.size() == gw * gh:
				cell_zone[c.y * gw + c.x] = int(v["chamber"])
		vaults.append(v)

func _vault_site(r: Dictionary) -> Dictionary:
	var pk := int(WV.vcfg().get("pocket", 5))
	var md := int(WV.vcfg().get("mouth", 2))
	var rect: Rect2i = r["rect"]
	var half := int(pk / 2)
	for attempt in 40:
		var dir: Vector2i = _DIRS4[mech_rng.randi_range(0, 3)]
		var perp := Vector2i(-dir.y, dir.x)
		var c := Vector2i(mech_rng.randi_range(rect.position.x, rect.end.x - 1), mech_rng.randi_range(rect.position.y, rect.end.y - 1))
		if cell(c.x, c.y) != FLOOR:
			continue
		var steps := 0
		while cell(c.x + dir.x, c.y + dir.y) == FLOOR and steps < 80:
			c += dir
			steps += 1
		var f := c
		if cell(f.x + perp.x, f.y + perp.y) != FLOOR or cell(f.x + perp.x + dir.x, f.y + perp.y + dir.y) != WALL:
			continue
		var ok := true
		for d in range(1, md + pk + 2):
			for l in range(-half - 1, half + 2):
				var q := f + dir * d + perp * l
				if q.x < 1 or q.y < 1 or q.x >= gw - 1 or q.y >= gh - 1 or cell(q.x, q.y) != WALL:
					ok = false
					break
				if cell_zone.size() == gw * gh and cell_zone[q.y * gw + q.x] != 255 and grid[q.y * gw + q.x] == FLOOR:
					ok = false
			if not ok:
				break
		if not ok:
			continue
		var mouth := []
		for d in range(1, md + 1):
			mouth.append(f + dir * d)
			mouth.append(f + dir * d + perp)
		var cells := []
		for d in range(md + 1, md + pk + 1):
			for l in range(-half, half + 1):
				cells.append(f + dir * d + perp * l)
		var ch_id: int = cell_zone[f.y * gw + f.x] if cell_zone.size() == gw * gh else 255
		return {"dir": dir, "perp": perp, "f": f, "mouth": mouth, "cells": cells, "room": r["id"], "chamber": ch_id,
			"centre": f + dir * (md + 1 + half), "wall": null, "seal": null, "open": false, "done": false,
			"order": [], "next": 0, "sigils": [], "trap": [], "counted": false}
	return {}

## The mouths start sealed: wall cells with a body and the shimmer drawn over them.
func _seal_vaults() -> void:
	for v in vaults:
		var body := StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		for c in v["mouth"]:
			set_cell(c.x, c.y, WALL)
			var cs := CollisionShape2D.new()
			var sh := RectangleShape2D.new()
			sh.size = Vector2(T, T)
			cs.shape = sh
			cs.position = cell_center(c)
			body.add_child(cs)
		add_child(body)
		var vis = VaultSeal.new()
		vis.cells = v["mouth"]
		vis.level = self
		vis.color = Color(str(WV.vcfg().get("color", "#8fc4d8")))
		body.add_child(vis)
		v["seal"] = body

## The shimmering wall in front of each mouth: an object with a life bar and the plaque.
func _place_vault_walls() -> void:
	for v in vaults:
		var ti := WV.type_info(str(v["type"]))
		var wd := {"id": "pentimento_wall", "name": "Pentimento Vault", "sprite": "pentimento_wall", "category": "object",
			"life": float(WV.vcfg().get("life", 90)) * float(afx.get("vault_wall_life", 1.0)), "damage": [0, 0], "dmg_type": "physical", "speed": 0, "radius": 8,
			"armour": 0, "evasion": 0, "resist": {}, "detect": 0, "attack": "none", "attack_range": 0, "windup": 1.0, "recover": 1.0,
			"xp": 0, "loot_mult": 0.0, "object": true, "plaque": "Vault: %s" % str(ti.get("name", v["type"])), "plaque_color": str(ti.get("color", "#8fc4d8"))}
		var pos := cell_center(v["f"]) + Vector2(v["perp"]) * (T * 0.5)
		var w = spawn_enemy(wd, monster_level, [], pos)
		w.room_id = int(v["room"])
		v["wall"] = w

func vault_line() -> String:
	if vaults.is_empty():
		return "Pentimento Vaults: none could be found here"
	var opened := 0
	var extra := ""
	for v in vaults:
		if v["open"]:
			opened += 1
		if v["open"] and not v["done"] and v["type"] == "riddle":
			var names := []
			for i in v["order"]:
				names.append(WV.sigil_name(int(i)))
			extra = "  Riddle: strike %s (%d/%d)" % [", ".join(names), int(v["next"]), v["order"].size()]
		elif v["open"] and not v["done"] and v["type"] == "trap":
			extra = "  Trap: %d left" % v["trap"].filter(func(e): return is_instance_valid(e) and e.alive).size()
	return "Pentimento Vaults: %d / %d opened%s" % [opened, vaults.size(), extra]

func _vault_of_wall(e) -> Dictionary:
	for v in vaults:
		if v["wall"] == e:
			return v
	return {}

func _on_vault_wall(e) -> void:
	var v := _vault_of_wall(e)
	if v.is_empty() or v["open"]:
		return
	open_vault(v)

## Opens a vault: the mouth clears, the shard roll, then its Treasure / Trap / Riddle.
func open_vault(v: Dictionary) -> void:
	if v["open"]:
		return
	v["open"] = true
	if v["wall"] != null and is_instance_valid(v["wall"]) and v["wall"].alive:
		v["wall"].alive = false
		enemies.erase(v["wall"])
		v["wall"].queue_free()
	for c in v["mouth"]:
		set_cell(c.x, c.y, FLOOR)
	if v["seal"] != null and is_instance_valid(v["seal"]):
		v["seal"].queue_free()
	v["seal"] = null
	flow_timer = -2.0
	wv_stats["vaults"] += 1
	var ti := WV.type_info(str(v["type"]))
	var pos := cell_center(v["centre"])
	add_fx(VFX.make("nova", cell_center(v["f"]), Color(str(WV.vcfg().get("color", "#8fc4d8"))), 0.8, 70))
	Sfx.play("portal", 0.0)
	Events.message.emit("The paint flakes away: a %s Vault!" % str(ti.get("name", v["type"])), Color(str(ti.get("color", "#8fc4d8"))))
	if atlas_hex != "" and mech_rng.randf() < WV.shard_chance(rot):
		var st: Dictionary = AtlasRules.ensure(player.ch)
		var ring := AtlasRules.ring_of(AtlasRules.parse(atlas_hex))
		if AtlasRules.add_shards(st, ring, 1) > 0:
			wv_stats["vault_shards"] += 1
			var wc := AtlasRules.warden_cfg(ring)
			Events.message.emit("%s found in the vault (%d/%d)" % [str(wc.get("shard", "Ground Shard")), AtlasRules.shards(st, ring), AtlasRules.summon_cost(st)], Color(str(AtlasRules.ward_cfg().get("colors", {}).get("shard", "#e8d8a0"))))
	match str(v["type"]):
		"trap":
			var tc: Dictionary = WV.vcfg().get("trap", {})
			var pool: Array = def.get("pool", [])
			var em: Array = tc.get("elite_mods", [2, 3])
			for i in int(tc.get("elites", 2)) + int(afx.get("trap_elites", 0)):
				var ed: Dictionary = Data.enemies.get(_mech_enemy_id(pool), {})
				if ed.is_empty():
					continue
				var a = spawn_enemy(ed, monster_level + 1, _mech_elite_mods(mech_rng.randi_range(int(em[0]), int(em[1]))), _vault_spot(v))
				v["trap"].append(a)
			if tc.get("pack", true):
				var pd: Dictionary = Data.enemies.get(_mech_enemy_id(pool), {})
				if not pd.is_empty():
					for i in mech_rng.randi_range(3, 4):
						v["trap"].append(spawn_enemy(pd, monster_level, [], _vault_spot(v)))
			for a in v["trap"]:
				a.room_id = int(v["room"])
				a.aggro = true
				a.loot_mult *= float(tc.get("loot_mult", 2.0))
				total_enemies += 1
			Events.message.emit("It was a trap! Slay the ambush for its hoard.", Color("#ff6060"))
			if v["trap"].is_empty():
				_vault_done(v)
		"riddle":
			v["order"] = WV.riddle_order(mech_rng)
			var n: int = v["order"].size()
			var pk := int(WV.vcfg().get("pocket", 5))
			for i in n:
				var lat := int(round((float(i) - (n - 1) / 2.0) * maxf(1.0, float(pk - 1) / maxf(1.0, n - 1))))
				var sc: Vector2i = v["centre"] + v["perp"] * lat + v["dir"] * (1 if i % 2 == 1 else -1)   # staggered so the labels never overlap
				var key := "vault_sigil_%d_%d" % [vaults.find(v), i]
				markers[key] = _add_portal(cell_center(sc), WV.sigil_name(i), key, Color(WV.sigil_color(i)), "shrine")
				v["sigils"].append(key)
			var names := []
			for i in v["order"]:
				names.append(WV.sigil_name(int(i)))
			Events.message.emit("The plaque reads: strike %s." % ", ".join(names), Color("#80c0ff"))
		_:
			_vault_done(v)
	Events.objective_changed.emit(objective_text())

func _vault_spot(v: Dictionary) -> Vector2:
	var cells: Array = v["cells"]
	return cell_center(cells[mech_rng.randi_range(0, cells.size() - 1)]) + Vector2(mech_rng.randf_range(-3, 3), mech_rng.randf_range(-3, 3))

func _vault_kill(e) -> void:
	for v in vaults:
		if v["type"] != "trap" or v["done"] or not v["trap"].has(e):
			continue
		v["trap"].erase(e)
		if v["trap"].filter(func(a): return is_instance_valid(a) and a.alive).is_empty():
			_vault_done(v)

## A riddle sigil was struck (interact key vault_sigil_<vault>_<sigil>).
func strike_sigil(key: String) -> bool:
	var parts := key.split("_")
	if parts.size() < 4:
		return false
	var vi := int(parts[2])
	var si := int(parts[3])
	if vi < 0 or vi >= vaults.size():
		return false
	var v: Dictionary = vaults[vi]
	if v["done"] or not v["open"] or v["type"] != "riddle":
		return false
	var p = markers.get(key)
	var pos: Vector2 = p.global_position if p != null and is_instance_valid(p) else cell_center(v["centre"])
	if v["order"].slice(0, int(v["next"])).has(si):
		return false   # already lit
	if int(v["order"][int(v["next"])]) == si:
		v["next"] = int(v["next"]) + 1
		add_fx(VFX.make("ring", pos, Color(WV.sigil_color(si)), 0.4, 30))
		Sfx.play("pickup", 0.0)
		if int(v["next"]) >= v["order"].size():
			for k in v["sigils"]:
				_take_interactable(k)
			Events.message.emit("The riddle is solved!", Color("#80c0ff"))
			_vault_done(v)
		else:
			Events.message.emit("The %s Sigil glows (%d/%d)" % [WV.sigil_name(si), int(v["next"]), v["order"].size()], Color(WV.sigil_color(si)))
	elif int(v.get("mistakes", 0)) < int(afx.get("riddle_mistakes", 0)):   # Atelier Forgiving Riddles
		v["mistakes"] = int(v.get("mistakes", 0)) + 1
		Events.message.emit("Wrong sigil - the vault forgives you once. Try again.", Color("#80c0ff"))
	else:
		v["next"] = 0
		Events.message.emit("Wrong sigil - the order resets and the vault wakes its guardians!", Color("#ff6060"))
		if WV.vcfg().get("riddle", {}).get("wrong_pack", true):
			var pd: Dictionary = Data.enemies.get(_mech_enemy_id(def.get("pool", [])), {})
			if not pd.is_empty():
				for i in 3:
					var a = spawn_enemy(pd, monster_level, [], _vault_spot(v))
					a.room_id = int(v["room"])
					a.aggro = true
					total_enemies += 1
	Events.objective_changed.emit(objective_text())
	return true

## The vault pays its cache; Trap and Riddle vaults count for their contracts.
func _vault_done(v: Dictionary) -> void:
	if v["done"]:
		return
	v["done"] = true
	var kind := str(v["type"])
	wv_stats["%s_vaults" % kind] = int(wv_stats.get("%s_vaults" % kind, 0)) + 1
	var c := WV.cache(monster_level, rot, kind, int(afx.get("treasure_rares", 0)))
	var pos := cell_center(v["centre"])
	var cid: String = player.ch.class_id
	for i in int(c["rares"]):
		spawn_drop({"kind": "item", "item": Loot.roll_item(monster_level + 1, float(c["rarity"]) + rarity_bonus(), cid, "rare")}, pos)
	for i in int(c["gems"]):
		spawn_drop({"kind": "gem", "id": Loot.random_gem(monster_level)}, pos)
	for i in int(c["materials"]):
		spawn_drop({"kind": "material", "id": Loot._roll_material(), "amount": 1}, pos)
	spawn_drop({"kind": "gold", "amount": int(c["gold"])}, pos)
	if mech_rng.randf() < float(c["legendary_chance"]):
		spawn_drop({"kind": "item", "item": Loot.roll_item(monster_level + 1, 0.0, cid, "legendary")}, pos)
	add_fx(VFX.make("nova", pos, Color("#ffd060"), 0.7, 50))
	Events.objective_changed.emit(objective_text())
