extends Node
## Scene manager: main menu -> hub <-> dungeon, with the persistent UI layer.

const UIRoot = preload("res://scripts/ui/ui_root.gd")
const Menus = preload("res://scripts/ui/menus.gd")
const Hub = preload("res://scripts/world/hub.gd")
const Dungeon = preload("res://scripts/world/dungeon.gd")

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
	var def: Dictionary = Data.dungeons.get(id, {})
	if def.is_empty():
		return false
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
