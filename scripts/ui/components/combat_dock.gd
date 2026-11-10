extends Control
## Presentation children live in this logical canvas; input remains with Player.

const HUDStyle = preload("res://scripts/ui/components/hud_style.gd")
const ResourceView = preload("res://scripts/ui/components/hud_resource.gd")
const ActionView = preload("res://scripts/ui/components/hud_action_slot.gd")
const ProgressionView = preload("res://scripts/ui/components/hud_progression.gd")
const StatusView = preload("res://scripts/ui/components/hud_status_strip.gd")
const DESIGN_SIZE := Vector2(912, 172)
var life
var mana
var source = null
var slots := []
var flasks := []
var evade
var progression
var statuses

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	theme = HUDStyle.THEME
	size = DESIGN_SIZE
	life = ResourceView.new()
	life.position = Vector2(0, 16)
	add_child(life)
	mana = ResourceView.new()
	mana.resource_name = "MANA"
	mana.mana = true
	mana.position = Vector2(772, 16)
	add_child(mana)
	for i in 7:
		var slot = ActionView.new()
		slot.position = Vector2(256 + i * 58, 70)
		add_child(slot)
		slot.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		slots.append(slot)
	for i in 2:
		var flask = ActionView.new()
		flask.position = Vector2(148 + i * 48, 76)
		add_child(flask)
		flask.size = Vector2(42, 54)
		flask.icon = Art.icon("flask_life" if i == 0 else "flask_mana")
		flask.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		flasks.append(flask)
	evade = ActionView.new()
	evade.position = Vector2(704, 76)
	add_child(evade)
	evade.size = Vector2(52, 54)
	evade.dodge = true
	progression = ProgressionView.new()
	progression.position = Vector2(144, 142)
	add_child(progression)
	statuses = StatusView.new()
	statuses.position.x = 256
	add_child(statuses)

func present(player, character, delta: float) -> void:
	var snap: bool = source != player
	source = player
	if snap:
		for action in slots + flasks + [evade]:
			action.initialized = false
			action.activation = 0
			action.completion = 0
	life.present(player.life, player.max_life, snap)
	mana.present(player.mana, character.final.get("max_mana", 0), snap)
	life.advance(delta)
	mana.advance(delta)
	for i in slots.size():
		var slot = slots[i]
		if snap: slot.initialized = false
		var skill: Dictionary = player.skill_in_slot(i)
		var blocked: String = player.use_block_reason(skill)
		if not player.alive or not player.input_enabled or player.speed_mult() <= 0:
			blocked = "Unavailable"
		if not skill.is_empty() and skill.get("behavior", "") in ["summon", "deploy", "buff"] and player.level != null and not player.level.allow_combat and not player.level.training_active:
			blocked = "Unavailable in town"
		slot.present(skill, player.cooldowns.get(skill.get("id", ""), 0), float(skill.get("cooldown", 0)) * character.final.get("cdr_mult", 1), blocked, player.held[i], player.SLOT_ACTIONS[i])
		slot.advance(delta)
	for i in flasks.size():
		var flask = flasks[i]
		if snap: flask.initialized = false
		var charges: float = character.flask_charges[i]
		if not snap and charges < flask.charges: flask.activation = 0.25
		flask.charges = charges
		flask.present({}, 0, 1, "No charges" if flask.charges < 1 and not Dev.infinite_flasks() else ("Unavailable" if not player.alive else ""), false, "flask_%d" % (i + 1))
		flask.advance(delta)
	if snap: evade.initialized = false
	if not snap and player.dodge_cd > evade.cooldown + 0.05: evade.activation = 0.25
	var dodge_duration: float = player.DODGE_CD * (0.5 if character.stats.has_flag("phantom_step") else 1.0) * (0.6 if character.stats.has_flag("phantom_treads") else 1.0)
	var dodge_blocked: bool = not player.alive or not player.input_enabled or (player.speed_mult() <= 0 and not player.can_dodge_out_of_stun())
	evade.present({}, player.dodge_cd, dodge_duration, "Unavailable" if dodge_blocked else "", player.dodge_t > 0, "dodge")
	evade.advance(delta)
	progression.present(character, delta, snap)
	statuses.present(player)
	queue_redraw()

func trigger_skill(skill_id: String) -> void:
	for slot in slots:
		if slot.skill.get("id", "") == skill_id:
			slot.activation = 0.25

func _draw() -> void:
	HUDStyle.frame(self, Rect2(140, 62, 632, 78))
	HUDStyle.centered(self, Vector2(192, 57), "RESTORE", 10, HUDStyle.color("muted"))
	HUDStyle.centered(self, Vector2(456, 57), "SKILLS", 10, HUDStyle.color("muted"))
	HUDStyle.centered(self, Vector2(730, 57), "EVADE", 10, HUDStyle.color("muted"))

func fit_to(viewport_size: Vector2) -> void:
	var factor := minf(1.0, maxf(0.1, (viewport_size.x - 24.0) / DESIGN_SIZE.x))
	scale = Vector2.ONE * factor
	position = Vector2((viewport_size.x - DESIGN_SIZE.x * factor) * 0.5, viewport_size.y - DESIGN_SIZE.y * factor - 6)
