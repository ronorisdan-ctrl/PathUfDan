extends Node
## Scene manager: main menu -> hub <-> dungeon, with the persistent UI layer.

const UIRoot = preload("res://scripts/ui/ui_root.gd")
const Menus = preload("res://scripts/ui/menus.gd")
const Hub = preload("res://scripts/world/hub.gd")
const Dungeon = preload("res://scripts/world/dungeon.gd")
const AtlasRules = preload("res://scripts/core/atlas_rules.gd")

var world: Node2D
var ui = null
var menu_layer: CanvasLayer
var menus = null

const AUTOSAVE_INTERVAL := 120.0   # seconds between hub autosaves

func _ready() -> void:
	Game.main = self
	world = Node2D.new()
	world.name = "World"
	add_child(world)
	menu_layer = CanvasLayer.new()
	menu_layer.layer = 20
	add_child(menu_layer)
	Events.player_died.connect(_on_player_died)
	if not Game.testing:
		var t := Timer.new()
		t.wait_time = AUTOSAVE_INTERVAL
		t.timeout.connect(_on_autosave_timer)
		add_child(t)
		t.start()
	show_main_menu()

func _on_autosave_timer() -> void:
	# only while standing in the hub with the game UI up (never in menus or dungeons)
	if ui != null and Game.level is Hub:
		Game.autosave()

func show_main_menu() -> void:
	get_tree().paused = false
	_clear_level()
	if ui != null:
		ui.queue_free()
		ui = null
	if menus != null:
		menus.queue_free()
	menus = Menus.new()
	menus.main = self
	menu_layer.add_child(menus)

func start_game() -> void:
	if menus != null:
		menus.queue_free()
		menus = null
	if ui == null:
		ui = UIRoot.new()
		add_child(ui)
	go_hub(false)

func _clear_level() -> void:
	if Game.level != null and is_instance_valid(Game.level):
		var lv = Game.level
		if lv.player != null and is_instance_valid(lv.player):
			Game.carried_minions = lv.player.minions.size()
			lv.player.clear_summons()
		lv.cleanup()
		world.remove_child(lv)
		lv.queue_free()
	Game.level = null

func go_hub(completed: bool) -> void:
	get_tree().paused = false
	_clear_level()
	var ch = Game.ch
	ch.flask_charges = [3.0, 3.0]
	if completed:
		ch.progress["runs"] = int(ch.progress.get("runs", 0)) + 1
		Game.refresh_vendor()
	Sfx.play("portal", 0.0)
	var hub = Hub.new()
	world.add_child(hub)
	hub.setup(ch)
	Game.level = hub
	Events.level_ready.emit(hub)
	Events.objective_changed.emit("Prepare, then enter the Dungeon Gate")
	Game.save_game()
	Game.autosave()
	if ui != null:
		ui.close_all()
		if completed:
			ui.toast("Returned to town victorious. The merchant has new stock.", Color("#ffd080"))

func enter_dungeon(id: String, seed_value: int = 0, run: Dictionary = {}) -> bool:
	if id.begins_with("atlas:"):
		return enter_atlas(AtlasRules.parse(id.trim_prefix("atlas:")), seed_value)
	var def: Dictionary = Data.dungeons.get(id, Data.zones.get(id, {}))   # zones: biome templates (dev only)
	if def.is_empty():
		return false
	return _start_run(def, seed_value, run)

## Atlas of Ruin (Endgame Phase 1A): runs hex h of the character's atlas. The layout seed and
## base modifiers come from the atlas seed and the hex's clear count unless seed_value is given.
func enter_atlas(h: Vector2i, seed_value: int = 0) -> bool:
	var ch = Game.ch
	if ch == null:
		return false
	var st: Dictionary = AtlasRules.ensure(ch)
	if not AtlasRules.can_enter(st, h):
		return false
	var s0 := int(st["seed"])
	var def := AtlasRules.zone_def(s0, h)
	if def.is_empty():
		return false
	def = AtlasRules.apply_rot(def, AtlasRules.rot_of(st, h), s0, h, st)   # Rot (Phase 1C; Atelier-aware)
	var wr := AtlasRules.warden_at(st, h)   # Layer Warden summoned here (Phase 2A): replaces the boss, no Heart
	if wr > 0:
		def = AtlasRules.apply_warden(def, wr)
	var fx := AtlasRules.atelier_fx(st)   # The Atelier (Phase 3B): zone parameters only
	if fx["last_light"] and wr == 0 and not def.get("heart", false):
		def["last_light"] = true   # Bare Canvas tip: the arena holds waves of Lantern-bearer packs, no boss
	var n := AtlasRules.clears(st, h)
	# Zone mechanics: the slotted Pigments' (Phase 1E) plus the hex's natural roll (Phase 1D).
	# Game.atlas_force_mechanic ("none" = off, or an id) replaces the natural roll for bots/tests.
	var pigs := AtlasRules.run_pigments(st, h)
	var mechs := AtlasRules.run_mechanics(st, h, pigs)
	if Game.atlas_force_mechanic != "":
		mechs = []
		for p in pigs:
			if not mechs.has(str(p["id"])):
				mechs.append(str(p["id"]))
		for fm in Game.atlas_force_mechanic.split(",", false):   # Phase 2E: a comma list forces several (smartbot)
			if fm != "none" and not mechs.has(fm):
				mechs.append(fm)
	def["mechanics"] = mechs
	def["mechanic"] = mechs[0] if mechs.size() > 0 else ""
	AtlasRules.mark_seen(st, mechs)   # Phase 3C: met mechanics unlock their Guild contracts
	def["pigment_mods"] = AtlasRules.pigment_mods(pigs)
	def["pigment_uids"] = pigs.map(func(p): return int(p["uid"]))
	def["pigment_reward"] = (float(AtlasRules.pig_cfg().get("reward", 10)) + float(fx["pigment_reward"])) * pigs.size()
	def["atelier_fx"] = fx
	def["damage_mult"] = float(def.get("damage_mult", 1.0)) * float(fx["damage_mult"]) * (1.0 + float(fx["pigment_damage"]) * pigs.size())
	def["life_mult"] = float(def.get("life_mult", 1.0)) * float(fx["life_mult"])
	if int(fx["elite_mods"]) != 0:
		var em: Array = def.get("elite_mods", [1, 2])
		def["elite_mods"] = [int(em[0]) + int(fx["elite_mods"]), int(em[1]) + int(fx["elite_mods"])]
	if fx["elite_preview"]:   # Connoisseur's Eye: the run's elite modifier pool (shown on the Atlas)
		def["elite_pool"] = AtlasRules.elite_preview(s0, h, n)
	if not pigs.is_empty():
		var gone := AtlasRules.spend_pigments(st, def["pigment_uids"], 1)
		if not gone.is_empty() and ui != null:
			ui.toast("Used up: %s" % ", ".join(gone), Color("#e0c890"))
	if seed_value == 0:
		seed_value = AtlasRules.layout_seed(s0, h, n)
	return _start_run(def, seed_value, {"mods": AtlasRules.run_mods(s0, h, n, def, int(fx["base_mods"])), "depth": 1, "atlas": AtlasRules.key(h)})

func _start_run(def: Dictionary, seed_value: int, run: Dictionary) -> bool:
	Game.autosave()   # snapshot before the run starts
	var minions: int = Game.carried_minions
	_clear_level()
	Game.carried_minions = minions
	Sfx.play("portal", 0.0)
	var d = Dungeon.new()
	world.add_child(d)
	if run.is_empty():
		run = Game.take_prepared_run(def)
	if not d.setup(def, Game.ch, seed_value, run):
		push_error("Failed to build dungeon")
		world.remove_child(d)
		d.queue_free()
		go_hub(false)
		return false
	Game.level = d
	# minions follow you through portals
	var skel: Dictionary = Data.skills.get("summon_skeletons", {})
	for i in Game.carried_minions:
		if not skel.is_empty():
			d.player.spawn_minion(skel.get("minion", "skeleton_warrior"), Game.ch.skill_level("summon_skeletons"), d.player.global_position + Vector2(randf_range(-16, 16), randf_range(-16, 16)))
	Game.carried_minions = 0
	Events.level_ready.emit(d)
	Events.objective_changed.emit(d.objective_text())
	if ui != null:
		ui.toast("Entering %s" % def["name"], Color("#e8c890"))
	return true

func open_station(kind: String) -> void:
	if ui != null:
		ui.open_station(kind)

func _on_player_died() -> void:
	Game.carried_minions = 0
	# Atlas zones: death adds Rot to the hex (Phase 1C; idempotent, the death panel calls it too)
	if Game.level != null and Game.level.has_method("apply_death_rot"):
		Game.level.apply_death_rot()
