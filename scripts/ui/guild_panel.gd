extends "res://scripts/ui/base_panel.gd"
## The Restorers' Guild (Endgame Phase 2C): the Commission Board (contracts that complete while
## you clear Atlas zones), Seal caches, the Guild rank ladder and the rank-2 Pigment vendor.
## Opened from the Guild NPC in Ashfall Sanctuary.

const Chrome = preload("res://scripts/ui/components/station_chrome.gd")
const AtlasRules = preload("res://scripts/core/atlas_rules.gd")
const GuildRules = preload("res://scripts/core/guild_rules.gd")

var info: RichTextLabel
var board_box: VBoxContainer
var cache_box: VBoxContainer
var vendor_box: VBoxContainer
var rank_box: VBoxContainer
var last_msg := ""

func _init() -> void:
	place = "center"
	build(str(Data.atlas_cfg.get("guild", {}).get("name", "Restorers' Guild")), Vector2(860, 560))
	Chrome.apply(self)
	info = UIKit.rich()
	info.fit_content = true
	body.add_child(info)
	var h := HBoxContainer.new()
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_theme_constant_override("separation", 14)
	body.add_child(h)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(left)
	left.add_child(Chrome.caption("Commission Board"))
	board_box = VBoxContainer.new()
	left.add_child(board_box)
	left.add_child(Chrome.caption("Guild ranks"))
	rank_box = VBoxContainer.new()
	left.add_child(rank_box)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(right)
	right.add_child(Chrome.caption("Seal caches"))
	var sc := Chrome.reading_scroll(right, 230)
	cache_box = VBoxContainer.new()
	cache_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(cache_box)
	right.add_child(Chrome.caption("Pigment vendor"))
	vendor_box = VBoxContainer.new()
	right.add_child(vendor_box)

func reposition() -> void:
	Chrome.place_panel(self, Vector2(940, 640))

func state() -> Dictionary:
	if Game.ch == null or not AtlasRules.unlocked(Game.ch):
		return {}
	return AtlasRules.ensure(Game.ch)

func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()

func _row(box: Node, text: String) -> HBoxContainer:
	var r := HBoxContainer.new()
	var l := UIKit.rich(text)
	l.fit_content = true
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(l)
	box.add_child(r)
	return r

func _act(ok: bool, msg: String) -> void:
	last_msg = msg
	if ui != null and msg != "":
		ui.toast(msg, Color("#e0c890") if ok else Color("#ff8080"))
	Game.save_game()
	refresh()

func _reroll(i: int) -> void:
	var why := GuildRules.reroll(state(), i)
	_act(why == "", "Contract rerolled" if why == "" else why)

func _open_cache(id: String) -> void:
	var res := GuildRules.open_cache(state(), Game.ch, id)
	if res.get("ok", false):
		_act(true, "%s: %s" % [str(res["msg"]), ", ".join(res.get("text", []))])
	else:
		_act(false, str(res.get("msg", "")))

func _buy(id: String) -> void:
	var res := GuildRules.buy_pigment(state(), Game.ch, id)
	if res.get("ok", false):
		_act(true, "Bought %s - slot it at the Easel" % AtlasRules.pigment_label(res["pigment"]))
	else:
		_act(false, str(res.get("msg", "")))

func refresh() -> void:
	for b in [board_box, cache_box, vendor_box, rank_box]:
		_clear(b)
	var st := state()
	if st.is_empty():
		info.text = "[color=#ff8080]Locked - %s[/color]" % str(AtlasRules.cfg().get("unlock_text", ""))
		return
	var g := GuildRules.ensure(st)
	var gc := GuildRules.cfg()
	var cols: Dictionary = gc.get("colors", {})
	var r := GuildRules.rank(st)
	var nxt := GuildRules.next_rep(st)
	var rep_line := "%d reputation" % int(g["rep"])
	if nxt > 0:
		rep_line += " (%d to rank %d)" % [nxt - int(g["rep"]), r + 1]
	info.text = "[color=%s]Rank %d: %s[/color]   %s   [color=%s]Seals: %d[/color]\n[color=#8a8494]Contracts progress as you complete Atlas zones (and when you choose at a Heart). The board refreshes in %d zone%s; free rerolls left: %d.[/color]" % [
		str(cols.get("rep", "#e8c060")), r, GuildRules.rank_name(r), rep_line, str(cols.get("seal", "#d8b46a")), int(g["seals"]),
		GuildRules.zones_to_refresh(st), "" if GuildRules.zones_to_refresh(st) == 1 else "s", GuildRules.rerolls_left(st)]
	# board
	var b: Array = g["board"]
	for i in b.size():
		var c: Dictionary = b[i]
		var done: bool = c.get("done", false)
		var t := "%s  [color=#8a8494]%d / %d[/color]\n[color=#8a8494]Reward: %d reputation, %d Seal%s[/color]" % [
			GuildRules.label(c), int(c["have"]), int(c["need"]), int(c["rep"]), int(c["seals"]), "" if int(c["seals"]) == 1 else "s"]
		if done:
			t = "[color=%s]Done:[/color] %s\n[color=#8a8494]A new contract arrives when the board refreshes.[/color]" % [str(cols.get("done", "#80e080")), GuildRules.label(c)]
		var row := _row(board_box, t)
		if not done:
			var idx := i
			var btn := UIKit.button("Reroll", func(): _reroll(idx))
			btn.disabled = GuildRules.rerolls_left(st) <= 0
			row.add_child(btn)
	# ranks
	for i in GuildRules.ranks().size():
		var ri: Dictionary = GuildRules.ranks()[i]
		var have := r >= i + 1
		_row(rank_box, "%s %d. %s  [color=#8a8494](%d rep) %s[/color]" % ["[color=#80e080]*[/color]" if have else "[color=#5a5464]-[/color]", i + 1, str(ri.get("name", "")), int(ri.get("rep", 0)), str(ri.get("desc", ""))])
	# caches
	_row(cache_box, "[color=#8a8494]%d Seals open one cache; the offer changes after each one.[/color]" % GuildRules.cache_cost())
	for id in GuildRules.cache_offers(st):
		var ci := GuildRules.cache_info(id)
		var row := _row(cache_box, "%s\n[color=#8a8494]%s[/color]" % [str(ci.get("name", id)), str(ci.get("desc", ""))])
		var cid: String = id
		var btn := UIKit.button("Open", func(): _open_cache(cid))
		btn.disabled = int(g["seals"]) < GuildRules.cache_cost()
		row.add_child(btn)
	# vendor
	if not GuildRules.has_unlock(st, "vendor"):
		_row(vendor_box, "[color=#8a8494]Opens at Guild rank %d (%s).[/color]" % [GuildRules.unlock_rank("vendor"), GuildRules.rank_name(GuildRules.unlock_rank("vendor"))])
	else:
		_row(vendor_box, "[color=#8a8494]%d left until the board refreshes. Gold: %d[/color]" % [GuildRules.vendor_left(st), int(Game.ch.gold)])
		for v in GuildRules.vendor_list():
			var pid := str(v.get("id", ""))
			var pi := AtlasRules.pigment_info(pid)
			var row := _row(vendor_box, "%s  [color=#8a8494]%d gold, random modifier[/color]" % [str(pi.get("name", pid)), int(v.get("gold", 0))])
			var btn := UIKit.button("Buy", func(): _buy(pid))
			btn.disabled = GuildRules.buy_refusal(st, Game.ch, pid) != ""
			row.add_child(btn)
