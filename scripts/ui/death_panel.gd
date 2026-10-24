extends "res://scripts/ui/base_panel.gd"
## Shown when the player dies. Returning to town costs a little experience.

var text: RichTextLabel

func _init() -> void:
	place = "center"
	build("You Have Fallen", Vector2(440, 220))
	text = UIKit.rich("", 420)
	body.add_child(text)
	body.add_child(UIKit.button("Return to Ashfall Sanctuary", _return))

func on_open() -> void:
	var ch = Game.ch
	text.text = "[center]The darkness takes you... but not forever.\n\nYou will wake in town with full life.\n[color=#ff8080]You lose %d experience (10%% of this level).[/color][/center]" % int(ch.xp_to_next() * 0.1)

func _return() -> void:
	var ch = Game.ch
	ch.xp = maxi(0, ch.xp - int(ch.xp_to_next() * 0.1))
	ch.progress["deaths"] = int(ch.progress.get("deaths", 0)) + 1
	ui.close("death")
	Game.carried_minions = 0
	Game.main.go_hub(false)
