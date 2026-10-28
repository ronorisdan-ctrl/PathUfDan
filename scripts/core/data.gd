extends Node
## Loads every data definition from res://data/*.json.
## Content (classes, skills, passives, items, affixes, enemies, dungeons) lives in data,
## so the game can be expanded without touching engine code.

var classes := {}
var class_list := []
var skills := {}
var skill_list := []
var summons := {}
var enemies := {}
var elite_mods := {}
var elite_mod_list := []
var item_bases := {}
var item_base_list := []
var affixes := {}
var affix_list := []
var uniques := {}
var unique_list := []
var loot := {}
var rarities := {}
var rarity_list := []
var materials := {}
var passives := {}
var passive_list := []
var dungeons := {}
var dungeon_list := []
var skill_runes := {}
var gems := {}
var gem_list := []
var gem_cfg := {}
var skill_rune_list := []
var specs := {}
var spec_list := []
var spec_nodes := {}
var dungeon_mods := {}
var dungeon_mod_list := []
var rooms := {}
var attributes := {}
var stat_info := {}
var stun_cfg := {}
var pets_cfg := {}   # data/pets.json
var pet_list := []
var pets := {}
var stash_cfg := {}   # data/stash.json: tab size, tab price curve, tab cap
var corruption_cfg := {}  # data/corruption.json: item corruption tuning
var dev_cfg := {}     # data/dev_tools.json: developer tools presets
var training_cfg := {}  # data/training.json: Training Grounds tuning
var load_errors := []

func _ready() -> void:
	load_all()

func load_all() -> void:
	load_errors.clear()
	class_list = _load("classes"); classes = _index(class_list)
	skill_list = _load("skills"); skills = _index(skill_list)
	summons = _load("summons")
	var el = _load("enemies"); enemies = _index(el)
	elite_mod_list = _load("elite_mods"); elite_mods = _index(elite_mod_list)
	item_base_list = _load("item_bases"); item_bases = _index(item_base_list)
	affix_list = _load("affixes"); affixes = _index(affix_list)
	unique_list = _load("uniques"); uniques = _index(unique_list)
	loot = _load("loot")
	rarity_list = loot.get("rarities", []); rarities = _index(rarity_list)
	materials = loot.get("materials", {})
	passive_list = _load("passive_tree"); passives = _index(passive_list)
	dungeon_list = _load("dungeons"); dungeons = _index(dungeon_list)
	dungeon_mod_list = _load("dungeon_mods"); dungeon_mods = _index(dungeon_mod_list)
	skill_rune_list = _load("skill_runes"); skill_runes = _index(skill_rune_list)
	gem_cfg = _load("gems")
	gem_list = gem_cfg.get("gems", [])
	gems = _index(gem_list)
	spec_list = _load("specializations"); specs = _index(spec_list)
	spec_nodes = {}
	for sp in spec_list:
		for n in sp.get("nodes", []):
			n["spec"] = sp["id"]
			spec_nodes[n["id"]] = n
	rooms = _load("rooms")
	attributes = _load("attributes")
	stat_info = _load("stats")
	stun_cfg = _load("stun")
	pets_cfg = _load("pets")
	pet_list = pets_cfg.get("pets", []) if pets_cfg is Dictionary else []
	pets = _index(pet_list)
	stash_cfg = _load("stash")
	corruption_cfg = _load("corruption")
	dev_cfg = _load("dev_tools")
	training_cfg = _load("training")
	if load_errors.size() > 0:
		push_error("Data load errors: " + str(load_errors))

func _load(file_id: String):
	var path := "res://data/%s.json" % file_id
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		load_errors.append("missing " + path)
		return {}
	var j := JSON.new()
	var err := j.parse(f.get_as_text())
	if err != OK:
		load_errors.append("%s line %d: %s" % [path, j.get_error_line(), j.get_error_message()])
		return {}
	return j.data

func _index(arr) -> Dictionary:
	var d := {}
	if typeof(arr) != TYPE_ARRAY:
		return d
	for e in arr:
		d[e["id"]] = e
	return d

func stat_name(stat: String) -> String:
	return stat_info.get(stat, {}).get("name", stat.capitalize())

func rarity_color(rarity: String) -> Color:
	return Color(rarities.get(rarity, {}).get("color", "#ffffff"))

func rarity_index(rarity: String) -> int:
	for i in rarity_list.size():
		if rarity_list[i]["id"] == rarity:
			return i
	return 0

func specs_for_class(cls: String) -> Array:
	return spec_list.filter(func(s): return s.get("class", "") == cls)

func skills_for_class(cls: String) -> Array:
	var out := []
	for s in skill_list:
		if s.get("class", "") == cls:
			out.append(s)
	return out
