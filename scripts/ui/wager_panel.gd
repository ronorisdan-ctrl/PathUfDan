extends "res://scripts/ui/base_panel.gd"
## The Collector's Wager (Endgame Phase 2D): opened from the Collector in an Atlas zone. Pick one
## of the bets on offer and a stake (1x / 2x / 3x gold); the stake is paid when you accept.

const WV = preload("res://scripts/core/wager_vault_rules.gd")

var info: RichTextLabel
var box: VBoxContainer

func _init() -> void:
	place = "center"
	build("The Collector's Wager", Vector2(640, 300))
	info = UIKit.rich("", 600)
	info.fit_content = true
	body.add_child(info)
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	body.add_child(box)
	body.add_child(UIKit.button("Walk away", func(): ui.close(panel_name)))

func _level():
	var lv = Game.level
	if lv == null or not ("wager" in lv):
		return null
	return lv

func _accept(id: String, mult: int) -> void:
	var lv = _level()
	if lv == null:
		return
	var why: String = lv.accept_wager(id, mult)
	if ui != null:
		ui.toast("Wager accepted" if why == "" else why, Color("#c89be8") if why == "" else Color("#ff8080"))
	refresh()

func refresh() -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	var lv = _level()
	if lv == null or lv.wager.is_empty():
		info.text = "[color=#8a8494]The Collector is not here.[/color]"
		return
	var w: Dictionary = lv.wager
	var gold := int(Game.ch.gold) if Game.ch != null else 0
	match str(w.get("state", "")):
		"offer":
			info.text = "[color=#c89be8]\"Care to wager on your own hand, restorer?\"[/color]\n[color=#8a8494]One bet per zone. The stake is paid now; a win pays it back with profit plus materials (a rare item at 3x). Gold: %d[/color]" % gold
			for id in w["offers"]:
				var b := WV.bet_info(id)
				var row := VBoxContainer.new()
				var l := UIKit.rich("[color=#e8d8a0]%s[/color]: %s  [color=#8a8494](odds %.2f)[/color]" % [str(b.get("name", id)), lv.wager_text(id), float(b.get("odds", 1.0))], 600)
				l.fit_content = true
				row.add_child(l)
				var h := HBoxContainer.new()
				for m in (lv.wager_mults() if lv.has_method("wager_mults") else WV.mults()):
					var mm := int(m)
					var pay := WV.payout(id, lv.monster_level, mm, lv.rot)
					var btn := UIKit.button("%dx: stake %d, win %d" % [mm, WV.stake(lv.monster_level, mm), int(pay["gold"])], func(): _accept(id, mm))
					var nope: String = lv.wager_refusal(id) if lv.has_method("wager_refusal") else ""
					if nope == "":
						nope = WV.stake_refusal(gold, lv.monster_level, mm)
					btn.disabled = nope != "" or lv.boss_dead
					btn.tooltip_text = nope
					h.add_child(btn)
				row.add_child(h)
				box.add_child(row)
		"active":
			info.text = "[color=#c89be8]\"I am watching.\"[/color]\n%s (%dx, %d gold staked)\n[color=#8a8494]%s[/color]" % [lv.wager_text(str(w["bet"])), int(w["mult"]), int(w["stake"]), lv.wager_progress()]
		"won":
			info.text = "[color=#ffd060]Won (%s).[/color] The Collector has paid and gone." % str(w.get("why", ""))
		"lost":
			info.text = "[color=#ff8080]Lost - %s.[/color] The Collector has gone with your stake." % str(w.get("why", ""))
