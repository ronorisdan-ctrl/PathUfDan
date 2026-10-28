extends Node
## Render actual UI states; no generated image is used as a screen background.

const Preview = preload("res://scripts/ui/preview/inventory_preview.gd")
const OUT := "res://tests/screens_out_inventory_preview"
var preview

func _ready() -> void:
	preview = Preview.new()
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(preview)
	for i in 4:
		await get_tree().process_frame
	await preview.verify_interactions()
	await shot("01_idle")
	preview._hover(preview.bag_slots[0])
	await shot("02_hover_comparison")
	preview._select(preview.bag_slots[0])
	await shot("03_selected")
	preview.equip_inspected()
	await shot("04_equipped")
	preview.reset_sample()
	preview._select(preview.bag_slots[5])
	await shot("05_unavailable")
	get_tree().quit(1 if preview.failures else 0)

func shot(tag: String) -> void:
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var error := get_viewport().get_texture().get_image().save_png(OUT + "/" + tag + ".png")
	print("PREVIEW_SCREEN ", tag, " ", error)
