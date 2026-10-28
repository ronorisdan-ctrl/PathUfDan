extends Node
## Screenshots for the pet system: Pet Keeper in town, shop panel, pets in a dungeon,
## a fetch in progress and a sheet of every pet sprite.
## Run with a display: godot --path . res://tests/screens_pets.tscn -- <outdir>

const MainScript = preload("res://scripts/main.gd")
var main = null
var outdir := "user://screens_pets"

func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func shot(tag: String) -> void:
	await frames(3)
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [outdir, tag])
	print("shot ", tag)

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		outdir = args[0]
	DirAccess.make_dir_recursive_absolute(outdir)
	Game.testing = true
	Game.pets_in_tests = true
	main = MainScript.new()
	add_child(main)
	await frames(5)
	Game.new_character("warrior")
	var ch = Game.ch
	ch.gold = 40000
	for k in Data.materials:
		ch.materials[k] = 3000
	ch.buy_pet("fox")
	ch.buy_pet("slime")
	ch.buy_pet("goblin")
	ch.pets["fox"]["tier"] = 3
	ch.rename_pet("fox", "Ember")
	main.start_game()
	await frames(20)
	var lv = Game.level
	lv.player.global_position = lv.cell_center(Vector2i(10, 7))
	await frames(30)
	await shot("pets_hub")
	main.ui.open_station("pets")
	main.ui.panels["pets"].select("fox")
	await frames(5)
	await shot("pets_panel")
	main.ui.close_all()
	main.enter_dungeon("forgotten_depths", 4242)
	await frames(10)
	lv = Game.level
	for e in lv.enemies:
		e.set_physics_process(false)
	var p = lv.player
	await frames(20)
	var it: Dictionary = Loot.make_item(Data.item_base_list[0]["id"], "rare", 5)
	var pos: Vector2 = lv.clamp_to_floor(p.global_position, p.global_position + Vector2(130, 0))
	lv.spawn_drop({"kind": "item", "item": it}, pos)
	lv.spawn_drop({"kind": "gold", "amount": 12}, lv.clamp_to_floor(p.global_position, p.global_position + Vector2(-60, 30)))
	await frames(20)
	lv.interact(p, lv.loot[-2].label_rect().get_center() if lv.loot.size() >= 2 else pos)
	await frames(6)
	await shot("pets_fetch")
	# sprite sheet
	main.ui.close_all()
	var sheet := Node2D.new()
	var bg := ColorRect.new()
	bg.color = Color(0.16, 0.15, 0.18)
	bg.size = Vector2(1280, 720)
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	layer.add_child(bg)
	layer.add_child(sheet)
	var i := 0
	for pd in Data.pet_list + [{"sprite": "pet_mimic_chest", "name": "(mimic posing)"}, {"sprite": "npc_petkeeper", "name": "Pet Keeper"}]:
		var s := Sprite2D.new()
		s.texture = Art.sprite(pd["sprite"])
		s.scale = Vector2(6, 6)
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.position = Vector2(90 + (i % 6) * 200, 90 + int(i / 6) * 220)
		sheet.add_child(s)
		var l := Label.new()
		l.text = pd["name"]
		l.position = s.position + Vector2(-60, 60)
		sheet.add_child(l)
		i += 1
	await shot("pets_sprites")
	get_tree().quit(0)
