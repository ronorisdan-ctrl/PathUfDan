extends RefCounted
## Endgame Phase 3C: the live Pigment Wells of one zone (rules: scripts/core/wells_rules.gd, numbers:
## data/atlas.json mechanics.wells). Owned by the dungeon (dungeon.wells); placement and rewards use
## the dungeon's mech_rng (item rolls use Loot's stream, as the vault caches do).

const WR = preload("res://scripts/core/wells_rules.gd")
const WellVisual = preload("res://scripts/world/well_visual.gd")
const VFX = preload("res://scripts/fx/vfx.gd")

var lv = null
var t := {}
var wells := []          # [{id, name, color, room, pos, fill, node, umber, full}]
var buff_t := 0.0
var done := false        # the boss died: no more fill
var easel_pos := Vector2.ZERO
var easel := false       # the easel stands in the arena
var mixed := false
var warned := false
var result := {}         # the mix (WR.mix + drops)
var stats := {"kill_fill": 0.0, "time_fill": 0.0, "full": 0, "kills": 0, "near_t": 0.0}

func setup(level, tuning: Dictionary, umber: bool) -> void:
	lv = level
	t = tuning
	var n := WR.roll_count(lv.mech_rng, t)
	var ids := WR.pick_colours(lv.mech_rng, n, t)
	if umber:
		ids.append(str(t.get("umber", {}).get("id", "umber")))
	# chambers: the normal ones by depth, split into len(ids) bands, one random pick per band
	var normals: Array = lv.rooms.filter(func(r): return r["kind"] == "normal")
	normals.sort_custom(func(a, b): return int(a["depth"]) < int(b["depth"]) or (int(a["depth"]) == int(b["depth"]) and int(a["id"]) < int(b["id"])))
	var k := mini(ids.size(), normals.size())
	var used := {}
	for i in k:
		var lo := int(floor(float(i) * normals.size() / k))
		var hi := maxi(lo, int(floor(float(i + 1) * normals.size() / k)) - 1)
		var r: Dictionary = normals[lv.mech_rng.randi_range(lo, hi)]
		if used.has(r["id"]):
			continue
		used[r["id"]] = true
		var info := WR.colour_info(str(ids[i]), t)
		var pos: Vector2 = lv.cell_center(lv.nearest_floor(r["anchor"]))
		var node = WellVisual.new()
		node.position = pos
		node.color = Color(str(info.get("color", "#ffffff")))
		node.label = "%s Well" % str(info.get("name", ids[i]))
		lv.floor_layer.add_child(node)
		wells.append({"id": str(ids[i]), "name": str(info.get("name", ids[i])), "color": node.color, "room": int(r["id"]), "pos": pos,
			"fill": 0.0, "node": node, "umber": str(ids[i]) == str(t.get("umber", {}).get("id", "umber")), "full": false})

func colour_wells() -> Array:
	return wells.filter(func(w): return not w["umber"])

func well_of_room(room: int) -> Dictionary:
	for w in wells:
		if int(w["room"]) == room:
			return w
	return {}

## The well a position belongs to: its chamber's, else one within radius_cells ({} = none).
func well_at(p: Vector2) -> Dictionary:
	var w := well_of_room(lv.chamber_at(p))
	if not w.is_empty():
		return w
	var r: float = float(t.get("radius_cells", 6)) * float(lv.T)
	var best := {}
	var bd := r
	for o in wells:
		var d: float = p.distance_to(o["pos"])
		if d <= bd:
			bd = d
			best = o
	return best

func _add_fill(w: Dictionary, x: float) -> void:
	if x <= 0.0 or float(w["fill"]) >= 1.0:
		return
	w["fill"] = minf(1.0, float(w["fill"]) + x)
	if w["node"] != null and is_instance_valid(w["node"]):
		w["node"].fill = w["fill"]
	if float(w["fill"]) >= 1.0 and not w["full"]:
		w["full"] = true
		stats["full"] = int(stats["full"]) + 1
		lv.add_fx(VFX.make("nova", w["pos"], w["color"], 0.7, 60))
		Events.message.emit("The %s Well is full!" % str(w["name"]), w["color"])

func on_kill(e) -> void:
	if done or e.is_boss:
		return
	var w := well_at(e.global_position)
	if w.is_empty():
		return
	var x := WR.kill_fill(e.is_elite or e.is_miniboss, t)
	stats["kills"] = int(stats["kills"]) + 1
	stats["kill_fill"] = float(stats["kill_fill"]) + minf(x, 1.0 - float(w["fill"]))
	_add_fill(w, x)

func tick(delta: float) -> void:
	if done:
		return
	if lv.boss_dead:
		done = true
		return
	var p = lv.player
	if p != null and is_instance_valid(p) and p.alive:
		var near: float = float(t.get("near_cells", 4)) * float(lv.T)
		for w in wells:
			if p.global_position.distance_to(w["pos"]) <= near:
				var x := WR.time_fill(delta, t)
				stats["time_fill"] = float(stats["time_fill"]) + minf(x, 1.0 - float(w["fill"]))
				stats["near_t"] = float(stats["near_t"]) + delta
				_add_fill(w, x)
	buff_t -= delta
	if buff_t <= 0.0:
		buff_t = 0.5
		_apply_danger()

## Monsters in a well's chamber get its colour's effect x its fill (bonuses replace the last ones,
## so they compose with glaze peels and elite modifiers).
func _apply_danger() -> void:
	for e in lv.enemies:
		if not is_instance_valid(e) or not e.alive or e.is_boss or e.def.get("object", false):
			continue
		var w := well_of_room(lv.chamber_at(e.global_position))
		var dg: Dictionary = WR.danger(str(w.get("id", "")), float(w.get("fill", 0.0)), t) if not w.is_empty() else {"fire": 0.0, "ignite": 0.0, "armour": 0.0, "poison": 0.0}
		var prev: Dictionary = e.get_meta("well_buff", {"fire": 0.0, "armour": 0.0})
		e.added_fire = float(e.added_fire) - float(prev.get("fire", 0.0)) + float(dg["fire"])
		e.armour = float(e.armour) / (1.0 + float(prev.get("armour", 0.0))) * (1.0 + float(dg["armour"]))
		var sts := []
		if float(dg["ignite"]) > 0.0:
			sts.append({"type": "ignite", "chance": float(dg["ignite"])})
		if float(dg["poison"]) > 0.0:
			sts.append({"type": "poison", "chance": float(dg["poison"])})
		e.extra_status = sts
		e.set_meta("well_buff", {"fire": float(dg["fire"]), "armour": float(dg["armour"])})

func total_fill() -> float:
	var s := 0.0
	for w in wells:
		s += float(w["fill"])
	return s

## After the boss: the easel appears at pos when any well holds pigment.
func on_zone_done(pos: Vector2) -> void:
	done = true
	if easel or mixed:
		return
	if total_fill() <= 0.0:
		Events.message.emit("The Pigment Wells stayed empty.", Color("#8a8494"))
		return
	easel_pos = lv.clamp_to_floor(pos, pos + Vector2(60, -28))
	easel = true
	lv.markers["wells_easel"] = lv._add_portal(easel_pos, "Pigment Easel", "wells_easel", Color(str(t.get("easel_color", "#e8d8a0"))))
	Events.message.emit("An easel waits in the arena: mix your Pigment Wells.", Color(str(t.get("easel_color", "#e8d8a0"))))

func pending() -> bool:
	return easel and not mixed

## Mixes the wells: the chest drops at the easel. Returns the mix.
func mix() -> Dictionary:
	if mixed or not easel:
		return {}
	mixed = true
	var fills := {}
	var umber := -1.0
	for w in wells:
		if w["umber"]:
			umber = float(w["fill"])
		else:
			fills[w["id"]] = float(w["fill"])
	result = WR.mix(fills, umber, int(lv.rot), t)
	var lvl: int = int(lv.monster_level)
	var cid: String = lv.player.ch.class_id
	var extra := float(t.get("chest_rarity", 0))
	var drops := []
	var first := {"crimson": true, "verdigris": true}
	for id in result["draws"]:
		drops.append_array(WR.roll_draw(str(id), lvl, cid, first.get(id, false), extra, t))
		first[id] = false
	if float(result["legendary"]) > 0.0 and lv.mech_rng.randf() < float(result["legendary"]):
		drops.append({"kind": "item", "item": Loot.roll_item(lvl + 1, 0.0, cid, "legendary")})
		result["got_legendary"] = true
	if float(result["unique"]) > 0.0 and lv.mech_rng.randf() < float(result["unique"]):
		var u: Dictionary = Loot.roll_unique(lvl, cid)
		if not u.is_empty():
			drops.append({"kind": "item", "item": u})
			result["got_unique"] = true
	var value := 0
	for d in drops:
		lv.spawn_drop(d, easel_pos + Vector2(lv.mech_rng.randf_range(-20, 20), lv.mech_rng.randf_range(4, 22)))
		match str(d.get("kind", "")):
			"gold":
				value += int(d["amount"])
			"item":
				value += Loot.sell_value(d["item"]) if not d["item"].is_empty() else 0
	result["drops"] = drops.size()
	result["value"] = value
	lv._take_interactable("wells_easel")
	lv.add_fx(VFX.make("nova", easel_pos, Color(str(t.get("easel_color", "#e8d8a0"))), 0.9, 90))
	Sfx.play("levelup", 0.0)
	var kind_txt := {"pure": "a pure %s chest" % str(WR.colour_info(str(result["dominant"]), t).get("name", "")),
		"mixed": "a %s chest touched with %s" % [str(WR.colour_info(str(result["dominant"]), t).get("name", "")), str(WR.colour_info(str(result["second"]), t).get("name", ""))],
		"balanced": "a balanced chest"}
	Events.message.emit("The pigments blend into %s (%d draw%s)." % [str(kind_txt.get(str(result["kind"]), "a chest")), result["draws"].size(), "" if result["draws"].size() == 1 else "s"], Color(str(t.get("easel_color", "#e8d8a0"))))
	return result

## Minimap markers: [{pos, color}].
func marks() -> Array:
	var out := []
	for w in wells:
		out.append({"pos": w["pos"], "color": w["color"]})
	if easel and not mixed:
		out.append({"pos": easel_pos, "color": Color(str(t.get("easel_color", "#e8d8a0")))})
	return out

func line() -> String:
	var parts := []
	for w in wells:
		parts.append("%s %d%%" % [str(w["name"]), int(round(float(w["fill"]) * 100.0))])
	var tail := ""
	if mixed:
		tail = " (mixed)"
	elif easel:
		tail = " - mix them at the easel"
	return "Pigment Wells: %s%s" % [", ".join(parts), tail]
