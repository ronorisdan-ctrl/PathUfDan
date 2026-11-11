extends RefCounted
## Endgame Phase 3C: the live Burning Canvas of one zone (rules: scripts/core/burning_rules.gd, numbers:
## data/atlas.json mechanics.burning). Owned by the dungeon (dungeon.burn); every roll uses the
## dungeon's mech_rng, so the main run stream (layout, packs, loot) is untouched.
##
## The fire front is a distance (cells along the floor from the entrance). Cells at or below it are
## burnt: an overlay texture (one pixel per cell) shows them scorched with a glowing edge, and the
## minimap shows them too. Cisterns push the front back and hold it.

const BR = preload("res://scripts/core/burning_rules.gd")
const VFX = preload("res://scripts/fx/vfx.gd")
const MM_FLOOR := Color(0.55, 0.5, 0.6, 0.9)   # dungeon._reveal_around's floor colour

var lv = null
var t := {}
var dist := PackedInt32Array()
var order := PackedInt32Array()     # cell indices sorted by distance
var start_of := PackedInt32Array()  # order index where each distance starts (size max_d + 2)
var max_d := 0
var arena_d := 1
var front := -1.0                   # -1 = not burning yet (grace)
var shown := -1                     # highest distance painted
var speed := 1.0                    # base cells per second
var hold := 0.0
var kills := 0
var done := false
var was_burnt := false
var cisterns := []                  # [{pos, cell, room, d, used, node, key}]
var channel := {}                   # {i, t}
var img: Image
var tex: ImageTexture
var overlay: Sprite2D
var dot_acc := 0.0
var loot_t := 0.0
var fx_t := 0.0
var fx_rng := RandomNumberGenerator.new()   # cosmetic embers only
var c_burnt := Color("#3a1a0c")
var c_edge := Color("#ff7a20")
var c_mm := Color("#a0502a")
var stats := {"ash": 0, "ash_ahead": 0, "cisterns": 0, "burnt_items": 0, "burnt_gold": 0, "fire_t": 0.0,
	"burn_t": 0.0, "ahead_t": 0.0, "caught": 0, "burn_dmg": 0.0, "reach_arena_t": -1.0, "front_end": -1.0, "start_t": -1.0}

func setup(level, tuning: Dictionary) -> void:
	lv = level
	t = tuning
	var cols: Dictionary = t.get("colors", {})
	c_burnt = Color(str(cols.get("burnt", "#3a1a0c")), 0.62)
	c_edge = Color(str(cols.get("edge", "#ff7a20")), 0.55)
	c_mm = Color(str(cols.get("minimap", "#a0502a")), 0.95)
	fx_rng.seed = lv.run_seed * 7 + 3
	var start: Vector2i = lv.nearest_floor(lv.rooms[lv.layout["start"]]["anchor"])
	var g: PackedByteArray = lv.grid.duplicate()
	for c in lv.sealed_cells:   # the arena seal does not stop the fire (nor the distance field)
		g[c.y * lv.gw + c.x] = 1
	dist = BR.dist_field(g, lv.gw, lv.gh, start)
	max_d = 0
	for d in dist:
		max_d = maxi(max_d, d)
	# counting sort of the cells by distance
	var counts := PackedInt32Array()
	counts.resize(max_d + 2)
	counts.fill(0)
	for d in dist:
		if d >= 0:
			counts[d + 1] += 1
	start_of = PackedInt32Array()
	start_of.resize(max_d + 2)
	var acc := 0
	for d in max_d + 1:
		acc += counts[d + 1]
		start_of[d + 1] = acc
	start_of[0] = 0
	order = PackedInt32Array()
	order.resize(acc)
	var fill := start_of.duplicate()
	for i in dist.size():
		var d := dist[i]
		if d >= 0:
			order[fill[d]] = i
			fill[d] += 1
	# the arena distance: the nearest arena cell
	var br: Dictionary = lv.rooms[lv.layout["boss"]]
	var rect: Rect2i = br["rect"]
	arena_d = max_d
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var d := dist[y * lv.gw + x]
			if d >= 0 and d < arena_d:
				arena_d = d
	arena_d = maxi(1, arena_d)
	speed = BR.base_speed(arena_d, t)
	_place_cisterns()
	img = Image.create(lv.gw, lv.gh, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	tex = ImageTexture.create_from_image(img)
	overlay = Sprite2D.new()
	overlay.name = "BurnOverlay"
	overlay.texture = tex
	overlay.centered = false
	overlay.scale = Vector2(lv.T, lv.T)
	overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	overlay.z_index = -8
	lv.add_child(overlay)
	if not Events.player_damaged.is_connected(_on_hurt):
		Events.player_damaged.connect(_on_hurt)

func cleanup() -> void:
	if Events.player_damaged.is_connected(_on_hurt):
		Events.player_damaged.disconnect(_on_hurt)

func _place_cisterns() -> void:
	var fracs: Array = BR.cistern_fracs(int(lv.rot), t)
	var cands := []
	for r in lv.rooms:
		if r["kind"] != "normal":
			continue
		var c: Vector2i = lv.nearest_floor(r["anchor"])
		var d: int = dist[c.y * lv.gw + c.x] if c.x >= 0 else -1
		if d >= 0:
			cands.append({"room": int(r["id"]), "cell": c, "d": d})
	var col := Color(str(t.get("colors", {}).get("cistern", "#60b0ff")))
	for f in fracs:
		if cands.is_empty():
			break
		var want := float(f) * arena_d
		var bi := 0
		for i in cands.size():
			if absf(float(cands[i]["d"]) - want) < absf(float(cands[bi]["d"]) - want):
				bi = i
		var cd: Dictionary = cands.pop_at(bi)
		var key := "cistern_%d" % cisterns.size()
		var pos: Vector2 = lv.cell_center(cd["cell"]) + Vector2(lv.mech_rng.randf_range(-6, 6), lv.mech_rng.randf_range(-6, 6))
		var node = lv._add_portal(pos, "Cistern", key, col)
		lv.markers[key] = node
		cisterns.append({"pos": pos, "cell": cd["cell"], "room": cd["room"], "d": cd["d"], "used": false, "node": node, "key": key})

# ------------------------------------------------------------------ queries
func idx_of(p: Vector2) -> int:
	var c: Vector2i = lv.to_cell(p)
	if c.x < 0 or c.y < 0 or c.x >= lv.gw or c.y >= lv.gh:
		return -1
	return c.y * lv.gw + c.x

func dist_at(p: Vector2) -> int:
	var i := idx_of(p)
	return dist[i] if i >= 0 else -1

func is_burnt_idx(i: int) -> bool:
	return front >= 0.0 and i >= 0 and i < dist.size() and dist[i] >= 0 and float(dist[i]) <= front

func is_burnt(p: Vector2) -> bool:
	return is_burnt_idx(idx_of(p))

## Cells between a position and the front (negative = burnt; INF before the fire starts).
func gap(p: Vector2) -> float:
	var d := dist_at(p)
	if front < 0.0 or d < 0:
		return INF
	return float(d) - front

func cur_speed() -> float:
	return speed * BR.kill_mult(kills, t)

func active() -> bool:
	return not done and front >= 0.0

# ------------------------------------------------------------------ runtime
func tick(delta: float) -> void:
	if done:
		return
	var p = lv.player
	if lv.boss_dead:
		_finish()
		return
	_tick_channel(delta)
	if front < 0.0:
		if float(lv.run_t) >= float(t.get("grace", 15)):
			front = 0.0
			stats["start_t"] = float(lv.run_t)
			Events.message.emit("The canvas catches fire behind you!", c_edge)
		else:
			return
	var paused: bool = bool(t.get("pause_at_boss", false)) and float(lv.boss_t) >= 0.0
	if hold > 0.0:
		hold -= delta
	elif not paused:
		front = minf(float(max_d), front + cur_speed() * delta)
	if float(stats["reach_arena_t"]) < 0.0 and front >= arena_d:
		stats["reach_arena_t"] = float(lv.run_t)
	_repaint()
	stats["fire_t"] = float(stats["fire_t"]) + delta
	if p != null and is_instance_valid(p) and p.alive:
		var burnt := is_burnt(p.global_position)
		if burnt:
			if not was_burnt:
				stats["caught"] = int(stats["caught"]) + 1
			stats["burn_t"] = float(stats["burn_t"]) + delta
			dot_acc += delta
			var tick_s := maxf(0.05, float(t.get("dot_tick", 0.5)))
			while dot_acc >= tick_s:
				dot_acc -= tick_s
				var before: float = p.life
				p.take_dot(BR.dot_dps(int(lv.monster_level), t) * tick_s, "fire")
				stats["burn_dmg"] = float(stats["burn_dmg"]) + maxf(0.0, before - p.life)
				if not p.alive:
					p.last_hit_by = "the Burning Canvas"
					break
		else:
			stats["ahead_t"] = float(stats["ahead_t"]) + delta
			dot_acc = 0.0
		was_burnt = burnt
	loot_t -= delta
	if loot_t <= 0.0:
		loot_t = 0.25
		_burn_loot()
	fx_t -= delta
	if fx_t <= 0.0:
		fx_t = 0.12
		_ember()

func _finish() -> void:
	done = true
	stats["front_end"] = front
	if not channel.is_empty():
		channel = {}
	cleanup()

func _burn_loot() -> void:
	for n in lv.loot.duplicate():
		if not is_instance_valid(n) or n.picked:
			continue
		var rar: String = str(n.item.get("rarity", "")) if n.kind == "item" else ""
		if not BR.burns(str(n.kind), rar, t) or not is_burnt(n.global_position):
			continue
		n.picked = true
		lv.loot.erase(n)
		if n.kind == "gold":
			stats["burnt_gold"] = int(stats["burnt_gold"]) + int(n.amount)
		else:
			stats["burnt_items"] = int(stats["burnt_items"]) + 1
		lv.add_fx(VFX.make("ring", n.global_position, c_edge, 0.35, 10))
		n.queue_free()

func _ember() -> void:
	if front < 1.0 or lv.player == null or not is_instance_valid(lv.player):
		return
	var d := int(front)
	var lo := start_of[d]
	var hi := start_of[d + 1]
	if hi <= lo:
		return
	for k in 2:
		var i := order[fx_rng.randi_range(lo, hi - 1)]
		var pos: Vector2 = lv.cell_center(Vector2i(i % lv.gw, int(i / lv.gw)))
		if pos.distance_to(lv.player.global_position) < 420.0:
			lv.add_fx(VFX.make("spark", pos + Vector2(fx_rng.randf_range(-6, 6), fx_rng.randf_range(-6, 6)), c_edge.lightened(0.2), 0.45, 8))

# ------------------------------------------------------------------ painting
func _paint(d: int, col: Color, burnt: bool) -> bool:
	if d < 0 or d > max_d:
		return false
	var mm := false
	for k in range(start_of[d], start_of[d + 1]):
		var i := order[k]
		var x: int = i % int(lv.gw)
		var y: int = int(i / lv.gw)
		img.set_pixel(x, y, col)
		if lv.reveal.size() > i and lv.reveal[i] == 1:
			lv.minimap_img.set_pixel(x, y, c_mm if burnt else MM_FLOOR)
			mm = true
	return mm

func _repaint() -> void:
	var f := int(floor(front))
	if f == shown:
		return
	var e := maxi(1, int(t.get("edge_cells", 2)))
	var mm := false
	if f > shown:
		for d in range(maxi(0, shown + 1 - e), f + 1):
			mm = _paint(d, c_edge if d > f - e else c_burnt, true) or mm
	else:
		for d in range(f + 1, shown + 1):
			mm = _paint(d, Color(0, 0, 0, 0), false) or mm
		for d in range(maxi(0, f - e + 1), f + 1):
			mm = _paint(d, c_edge, true) or mm
	shown = f
	tex.update(img)
	if mm:
		lv.minimap_tex.update(lv.minimap_img)

# ------------------------------------------------------------------ cisterns
func cistern_index(key: String) -> int:
	for i in cisterns.size():
		if cisterns[i]["key"] == key:
			return i
	return -1

## Starts the channel at cistern i (interact). False if it cannot be used now.
func start_channel(i: int) -> bool:
	if done or i < 0 or i >= cisterns.size() or cisterns[i]["used"] or not channel.is_empty():
		return false
	channel = {"i": i, "t": float(t.get("channel", 1.0))}
	Events.message.emit("You pump the cistern...", Color(str(t.get("colors", {}).get("cistern", "#60b0ff"))))
	return true

func channeling() -> bool:
	return not channel.is_empty()

func _cancel(why: String) -> void:
	if channel.is_empty():
		return
	channel = {}
	Events.message.emit("The cistern slips from your grip: %s." % why, Color("#ff8080"))

func _on_hurt(amount: float) -> void:
	if channel.is_empty() or lv == null or lv.player == null or not is_instance_valid(lv.player):
		return
	if amount >= float(t.get("interrupt_pct", 0.1)) * float(lv.player.max_life):
		_cancel("a heavy blow")

func _tick_channel(delta: float) -> void:
	if channel.is_empty():
		return
	var c: Dictionary = cisterns[int(channel["i"])]
	var p = lv.player
	if p == null or not is_instance_valid(p) or not p.alive:
		channel = {}
		return
	if p.global_position.distance_to(c["pos"]) > float(t.get("cistern_reach", 40)):
		_cancel("you stepped away")
		return
	channel["t"] = float(channel["t"]) - delta
	if float(channel["t"]) <= 0.0:
		douse(int(channel["i"]))

## Douses cistern i: the front goes back push_frac of the arena distance and holds still.
func douse(i: int) -> void:
	if i < 0 or i >= cisterns.size() or cisterns[i]["used"]:
		return
	var c: Dictionary = cisterns[i]
	c["used"] = true
	channel = {}
	if front >= 0.0:
		front = BR.pushed(front, arena_d, t)
		_repaint()
	hold = float(t.get("hold", 8.0))
	stats["cisterns"] = int(stats["cisterns"]) + 1
	var used := Color(str(t.get("colors", {}).get("used", "#6a6a70")))
	if c["node"] != null and is_instance_valid(c["node"]):
		c["node"].color = used
		c["node"].label = "Cistern (dry)"
	var key: String = c["key"]
	lv.interactables = lv.interactables.filter(func(it): return it["kind"] != key)
	lv.add_fx(VFX.make("nova", c["pos"], Color(str(t.get("colors", {}).get("cistern", "#60b0ff"))), 0.8, 80))
	Sfx.play("portal", 0.0)
	Events.message.emit("The cistern floods the canvas: the fire falls back and holds for %d s." % int(hold), Color(str(t.get("colors", {}).get("cistern", "#60b0ff"))))

## Minimap markers: [{pos, color}] (dry cisterns grey).
func marks() -> Array:
	var out := []
	var col := Color(str(t.get("colors", {}).get("cistern", "#60b0ff")))
	var used := Color(str(t.get("colors", {}).get("used", "#6a6a70")))
	for c in cisterns:
		out.append({"pos": c["pos"], "color": used if c["used"] else col})
	return out

# ------------------------------------------------------------------ kills
func on_kill(e, is_boss: bool) -> void:
	if done and not is_boss:
		return
	if not is_boss:
		kills += 1
	var d := dist_at(e.global_position)
	var ahead := front >= 0.0 and d >= 0 and float(d) > front and float(d) - front <= float(t.get("ahead_cells", 6))
	var n := BR.ash_for_kill(lv.mech_rng, e.is_elite or e.is_miniboss, is_boss, ahead, t)
	if n > 0:
		stats["ash"] = int(stats["ash"]) + n
		if ahead:
			stats["ash_ahead"] = int(stats["ash_ahead"]) + n
		lv.spawn_drop({"kind": "material", "id": "ash", "amount": n}, e.global_position)

func line() -> String:
	var used := 0
	for c in cisterns:
		if c["used"]:
			used += 1
	var state := "smouldering" if front < 0.0 else ("held" if hold > 0.0 else ("out" if done else "spreading"))
	return "Burning Canvas: fire %s, %d / %d cisterns used, %d Ash" % [state, used, cisterns.size(), int(stats["ash"])]
