extends Node2D
## A loot pet. It follows the player along a breadcrumb trail, auto-collects gold
## and crafting materials, and fetches a far-away drop when F is pressed on it.
##
## Never in the way: this is a plain Node2D with no physics body, hurtbox, life or
## take_damage, and it is not in level.allies or any targetable list. Enemies,
## projectiles and skills cannot see it.
## Never changes outcomes: every collection goes through level.pickup(), the same
## function manual pickup uses, and quirks use their own RNG (never the loot RNG).

const PetRules = preload("res://scripts/core/pet_rules.gd")
const DamageNumber = preload("res://scripts/fx/damage_number.gd")
const VFX = preload("res://scripts/fx/vfx.gd")

var is_pet := true
var level = null
var player = null
var pet_id := ""
var def := {}
var tier := 0
var st := {}
var pet_name := ""
var rng := RandomNumberGenerator.new()   # quirks only

var state := "follow"      # follow | fetch | blink_out | blink_back | return
var target = null
var target_is_auto := false
var fetch_cd := 0.0
var auto_cd := 0.0
var blink_t := 0.0
var return_t := 0.0
var fetch_origin := Vector2.ZERO
var trail := []            # player breadcrumbs (global positions)
var trail_i := 0
var face := 1.0
var moving := false
var idle_t := 0.0
var t := 0.0
var last_refusal := ""     # read by tests
var refusals := 0
var fetches := 0
var collected := 0
var magnet_moved_last := 0

# visuals
var tex: Texture2D
var carry_tex: Texture2D = null
var carry_col := Color.WHITE
var carry_t := 0.0
var beam_t := 0.0
var hop := 0.0
var spin := 0.0
var squash := 1.0
var alpha := 1.0
var flip_v := false
var posing := false
var particles := []        # {p (global), v, life, max, col, kind}
var q_timer := 0.0
var q_state := ""
var q_state_t := 0.0
var seen_drops := {}
var light: PointLight2D
var _pending_texts := []   # [delay, text, color]

func setup(lv, p, id: String) -> void:
	level = lv
	player = p
	pet_id = id
	def = Data.pets.get(id, {})
	tier = p.ch.pet_tier(id)
	pet_name = p.ch.pet_name(id)
	st = PetRules.stats(id, tier)
	rng.seed = hash(id) ^ 0x5eed
	tex = Art.sprite(def.get("sprite", "pet_dog"))
	q_timer = rng.randf_range(2.0, 5.0)

func _ready() -> void:
	z_index = 1
	light = PointLight2D.new()
	light.texture = Art.light_tex
	light.texture_scale = 0.35
	light.color = Color("#ffd8a0")
	light.energy = 0.0
	add_child(light)
	if tier >= 4 or def.get("quirk", "") == "hiccup":
		light.energy = 0.25 + 0.1 * tier
	if player != null and is_instance_valid(player):
		trail.append(player.global_position)
	_puff(global_position)

func despawn() -> void:
	cancel_fetch()
	if is_inside_tree():
		_puff(global_position)
	queue_free()

# ------------------------------------------------------------------ helpers
func camera_rect() -> Rect2:
	var center: Vector2 = player.global_position
	var zoom := Vector2(2, 2)
	if player.cam != null and is_instance_valid(player.cam) and player.cam.is_inside_tree():
		center = player.cam.get_screen_center_position()
		zoom = player.cam.zoom
	var sz: Vector2 = get_viewport_rect().size / zoom
	return Rect2(center - sz / 2.0, sz)

func in_view(pos: Vector2) -> bool:
	return camera_rect().has_point(pos)

func busy() -> bool:
	return state in ["fetch", "blink_out"] and not target_is_auto

func _player_ok() -> bool:
	return player != null and is_instance_valid(player) and level != null and is_instance_valid(level)

func _follow_index() -> int:
	# newest breadcrumb at least follow_distance behind the player
	var fd := float(PetRules.setting("follow_distance", 26))
	var pp: Vector2 = player.global_position
	for j in range(trail.size() - 1, -1, -1):
		if trail[j].distance_to(pp) >= fd:
			return j
	return 0

func _record_trail() -> void:
	var pp: Vector2 = player.global_position
	if trail.is_empty() or pp.distance_to(trail.back()) >= float(PetRules.setting("trail_spacing", 6)):
		trail.append(pp)
		if trail.size() > int(PetRules.setting("trail_max_points", 240)):
			trail.pop_front()
			trail_i = maxi(0, trail_i - 1)

func _move_toward(goal: Vector2, speed: float, delta: float) -> bool:
	var d := global_position.distance_to(goal)
	var step := speed * delta
	if d <= step or d < 0.5:
		global_position = goal
		return true
	var dir := (goal - global_position) / d
	if absf(dir.x) > 0.2:
		face = signf(dir.x)
	global_position += dir * step
	moving = true
	return false

func _follow_speed() -> float:
	var ps := float(player.ch.final.get("move_speed", 100))
	return maxf(float(st.get("speed", 90)), ps * 1.15)

func teleport_to_player() -> void:
	_puff(global_position)
	global_position = player.global_position + Vector2(-12 * face, 6)
	_puff(global_position)
	trail_i = _follow_index()

# ------------------------------------------------------------------ fetch
## F on a far drop. Returns "" if the pet accepted, else the refusal text it showed.
func request_fetch(drop) -> String:
	if drop == null or not is_instance_valid(drop) or drop.picked:
		return "gone"
	var need := PetRules.required_tier(drop.kind, drop.item.get("rarity", "common") if drop.kind == "item" else "common")
	if tier < need:
		return refuse("Too heavy")
	var pos: Vector2 = drop.global_position
	var rng_ok: bool = in_view(pos) and (float(st["fetch_range"]) < 0 or pos.distance_to(player.global_position) <= float(st["fetch_range"]))
	var wall_ok: bool = st["blink"] or st["wall_pass"] or level.has_los(global_position, pos)
	if not rng_ok or not wall_ok:
		return refuse("Can't reach")
	if busy():
		return refuse("Busy")
	if fetch_cd > 0.0:
		return refuse("Resting")
	var why: String = level.collect_block(drop, self)
	if why == "hidden":
		return refuse("Hidden")
	if why != "":
		return why
	if state in ["fetch", "blink_out"]:
		cancel_fetch()    # an auto-loot run never starves F
	if not drop.claim(self):
		return "claimed"
	target = drop
	target_is_auto = false
	fetch_cd = float(st["fetch_cd"])
	fetch_origin = global_position
	fetches += 1
	chirp()
	if st["blink"]:
		state = "blink_out"
		blink_t = float(PetRules.setting("blink_delay", 0.14))
		_puff(global_position)
	else:
		state = "fetch"
	return ""

func refuse(text: String) -> String:
	last_refusal = text
	refusals += 1
	float_text(text, Color("#ffb0a0"))
	Sfx.play("nope", 0.04)
	return text

func cancel_fetch() -> void:
	if target != null and is_instance_valid(target):
		target.release(self)
	target = null
	target_is_auto = false
	if state in ["fetch", "blink_out"]:
		state = "return"
		return_t = 0.0

func _arrive() -> void:
	var drop = target
	target = null
	var was_auto := target_is_auto
	target_is_auto = false
	if drop != null and is_instance_valid(drop):
		if not level.pickup(drop, self):
			drop.release(self)
			if not was_auto and drop.kind == "item" and player.ch.free_bag_slot() < 0:
				float_text("Bag full", Color("#ff8080"))
	if st["blink"] and not was_auto:
		state = "blink_back"
		blink_t = 0.25
	else:
		state = "return"
		return_t = 0.0

## Called by level.pickup() after this pet collected a drop.
func on_collected(n) -> void:
	collected += 1
	carry_t = 0.9
	carry_col = n.color
	match n.kind:
		"gold":
			carry_tex = Art.icon("gold")
		"material", "rune", "gem":
			carry_tex = Art.icon({"material": "material", "rune": "rune", "gem": "gem"}[n.kind])
		_:
			carry_tex = Art.icon(n.item.get("icon", "charm"))
			if n.rarity_idx() >= 2:
				beam_t = 0.8   # keep the rarity beam moment
			if def.get("quirk", "") == "pocket":
				_pending_texts.append([0.0, "Mine!", Color("#a0e070")])
				_pending_texts.append([0.7, "...jk, here", Color("#a0e070")])
	if n.kind == "item":
		chirp()

func _try_auto_loot() -> void:
	var pp: Vector2 = player.global_position
	var rad := float(st["auto_radius"])
	var best = null
	var bd := INF
	for n in level.loot:
		if not is_instance_valid(n) or n.picked or n.t < 0.3 or not (n.kind in ["gold", "material"]):
			continue
		var pos: Vector2 = n.global_position
		if not in_view(pos):
			continue
		if rad >= 0 and pos.distance_to(pp) > rad:
			continue
		if level.collect_block(n, self) != "":
			continue
		if not st["wall_pass"] and not level.has_los(global_position, pos):
			continue
		var d := pos.distance_to(global_position)
		if d < bd:
			bd = d
			best = n
	if best != null and best.claim(self):
		target = best
		target_is_auto = true
		fetch_origin = global_position
		state = "fetch"
		auto_cd = float(st["auto_cd"])
	else:
		auto_cd = 0.1

func _magnet(delta: float) -> void:
	magnet_moved_last = 0
	var r := float(st["magnet_radius"])
	if r <= 0:
		return
	var cap := int(PetRules.setting("magnet_max_per_frame", 4))
	var cd := float(PetRules.setting("magnet_collect_distance", 8))
	var bag_full: bool = player.ch.free_bag_slot() < 0
	for n in level.loot.duplicate():
		if magnet_moved_last >= cap:
			break
		if not is_instance_valid(n) or n.picked or n.t < 0.3 or n == target:
			continue
		if n.kind == "item" and bag_full:
			continue
		if n.global_position.distance_to(global_position) > r or not in_view(n.global_position):
			continue
		if level.collect_block(n, self) != "":
			continue
		magnet_moved_last += 1
		n.magnet_by = self
		var to: Vector2 = global_position - n.global_position
		var step := float(st["magnet_speed"]) * delta
		if to.length() <= cd + step:
			level.pickup(n, self)
		else:
			n.global_position += to.normalized() * step

# ------------------------------------------------------------------ main loop
func _physics_process(delta: float) -> void:
	if not _player_ok():
		return
	t += delta
	moving = false
	_record_trail()
	fetch_cd = maxf(0.0, fetch_cd - delta)
	auto_cd = maxf(0.0, auto_cd - delta)
	var far: bool = global_position.distance_to(player.global_position) > float(PetRules.setting("catch_up_distance", 400))
	match state:
		"follow":
			if far:
				teleport_to_player()
			_follow(delta)
			if auto_cd <= 0.0 and player.alive:
				_try_auto_loot()
		"fetch":
			if target == null or not is_instance_valid(target) or target.picked or target.is_claimed_by_other(self):
				cancel_fetch()
			elif _move_toward(target.global_position, float(st["speed"]) * (1.15 if target_is_auto else 1.0), delta) \
					or global_position.distance_to(target.global_position) <= float(PetRules.setting("fetch_touch_distance", 7)):
				_arrive()
		"blink_out":
			blink_t -= delta
			if target == null or not is_instance_valid(target) or target.picked:
				cancel_fetch()
			elif blink_t <= 0.0:
				global_position = target.global_position
				_puff(global_position)
				_arrive()
		"blink_back":
			blink_t -= delta
			if blink_t <= 0.0:
				teleport_to_player()
				state = "follow"
		"return":
			return_t += delta
			if far or return_t > 4.0:
				teleport_to_player()
				state = "follow"
			else:
				_return(delta)
	_magnet(delta)
	_tick_visuals(delta)
	queue_redraw()

func _follow(delta: float) -> void:
	var j := _follow_index()
	if trail_i > j:
		trail_i = j
	var spd := _follow_speed()
	var budget := 3
	while trail_i < j and budget > 0:
		budget -= 1
		if _move_toward(trail[trail_i], spd, delta):
			trail_i += 1
		else:
			break

func _return(delta: float) -> void:
	var pp: Vector2 = player.global_position
	if st["wall_pass"] or level.has_los(global_position, pp):
		_move_toward(pp, _follow_speed() * 1.1, delta)
		if global_position.distance_to(pp) <= float(PetRules.setting("follow_distance", 26)) + 4.0:
			state = "follow"
			trail_i = _follow_index()
	else:
		# retrace the straight (wall-checked) line back to where the fetch began
		if _move_toward(fetch_origin, _follow_speed(), delta):
			state = "follow"
			var bi := 0
			var bd := INF
			for i in trail.size():
				var d: float = trail[i].distance_to(fetch_origin)
				if d < bd:
					bd = d
					bi = i
			trail_i = bi

# ------------------------------------------------------------------ cosmetics
func chirp() -> void:
	Sfx.play_pitched("chirp", float(def.get("chirp", 1.0)))

func float_text(text: String, col: Color) -> void:
	if level == null or not is_instance_valid(level):
		return
	var dn = DamageNumber.new()
	dn.setup(text, col, false)
	dn.position = global_position + Vector2(0, -18)
	level.fx_layer.add_child(dn)

func _puff(pos: Vector2) -> void:
	if level == null or not is_instance_valid(level) or not level.is_inside_tree():
		return
	var v = VFX.make("ring", pos + Vector2(0, -4), Color(1, 1, 1, 0.8), 0.3, 10)
	level.fx_layer.add_child(v)

func _particle(gpos: Vector2, vel: Vector2, life: float, col: Color, kind: String = "dot") -> void:
	if particles.size() > 60:
		particles.pop_front()
	particles.append({"p": gpos, "v": vel, "life": life, "max": life, "col": col, "kind": kind})

func _tick_visuals(delta: float) -> void:
	carry_t = maxf(0.0, carry_t - delta)
	beam_t = maxf(0.0, beam_t - delta)
	for pt in _pending_texts.duplicate():
		pt[0] -= delta
		if pt[0] <= 0.0:
			float_text(pt[1], pt[2])
			_pending_texts.erase(pt)
	var player_still: bool = player.velocity.length() < 5.0 if "velocity" in player else true
	idle_t = idle_t + delta if (player_still and state == "follow" and not moving) else 0.0
	for p in particles.duplicate():
		p["life"] -= delta
		p["p"] += p["v"] * delta
		if p["life"] <= 0:
			particles.erase(p)
	hop = maxf(0.0, hop - delta * 4.0)
	squash = lerpf(squash, 1.0, minf(1.0, delta * 6.0))
	posing = false
	flip_v = false
	alpha = 1.0
	if moving and def.get("quirk", "") != "roll":
		spin = 0.0
	_quirk(delta)

func _quirk(delta: float) -> void:
	q_timer -= delta
	q_state_t = maxf(0.0, q_state_t - delta)
	if q_state_t <= 0.0:
		q_state = ""
	var gp := global_position
	var idle := idle_t > 1.5
	match def.get("quirk", ""):
		"stick":
			if idle and q_timer <= 0.0:
				q_state = "stick"
				q_state_t = 2.0
				hop = 1.0
				q_timer = rng.randf_range(5.0, 9.0)
		"nap":
			if idle_t > 2.5:
				squash = 0.82
				if q_timer <= 0.0:
					_particle(gp + Vector2(4 * face, -12), Vector2(6, -10), 1.6, Color("#c0d0ff"), "z")
					q_timer = 0.9
		"fireflies":
			if moving and q_timer <= 0.0:
				hop = 1.0
				q_timer = 0.45
			elif idle and q_timer <= 0.0:
				_particle(gp + Vector2(rng.randf_range(-16, 16), rng.randf_range(-22, -6)), Vector2(rng.randf_range(-8, 8), rng.randf_range(-6, 6)), 2.2, Color("#f0ff80"), "glow")
				if rng.randf() < 0.3:
					q_state = "tongue"
					q_state_t = 0.25
				q_timer = rng.randf_range(0.8, 1.6)
		"split":
			if idle and q_timer <= 0.0:
				q_state = "split"
				q_state_t = 1.6
				q_timer = rng.randf_range(6.0, 10.0)
		"holo":
			if q_timer <= 0.0:
				var emotes := ["!", "<3", "?", ":)", "^_^", "beep"]
				float_text(emotes[rng.randi() % emotes.size()], Color("#80f0ff"))
				q_timer = rng.randf_range(4.0, 8.0)
		"pocket":
			pass
		"pawprints":
			if moving and q_timer <= 0.0:
				_particle(gp + Vector2(rng.randf_range(-2, 2), 0), Vector2.ZERO, 2.5, Color("#ffb060"), "paw")
				q_timer = 0.12
		"hop":
			if q_timer <= 0.0:
				hop = 1.0
				q_timer = rng.randf_range(1.5, 4.0)
		"roll":
			if moving:
				spin += delta * 14.0 * face
			else:
				spin = 0.0
		"hiccup":
			if q_timer <= 0.0:
				for i in 4:
					_particle(gp + Vector2(6 * face, -6), Vector2(rng.randf_range(10, 30) * face, rng.randf_range(-25, 5)), 0.5, Color("#ffa040"), "spark")
				hop = 0.6
				q_timer = rng.randf_range(3.0, 6.0)
		"bubbles":
			if q_timer <= 0.0:
				_particle(gp + Vector2(-5 * face, -6), Vector2(rng.randf_range(-4, 4), -14), 1.4, Color("#a0e8ff"), "bubble")
				q_timer = 0.35
		"sheet":
			alpha = 0.72 + 0.12 * sin(t * 2.0)
		"hoot":
			for n in level.loot:
				if is_instance_valid(n) and n.kind == "item" and n.rarity_idx() >= 2 and not seen_drops.has(n.get_instance_id()):
					seen_drops[n.get_instance_id()] = true
					if in_view(n.global_position) and not n.hidden_by_filter:
						face = signf(n.global_position.x - gp.x) if absf(n.global_position.x - gp.x) > 1 else face
						float_text("Hoo!", Color("#ffe8a0"))
						hop = 0.7
		"spores":
			if q_timer <= 0.0:
				_particle(gp + Vector2(0, -10), Vector2(rng.randf_range(-8, 8), -8), 1.0, Color("#e0c0ff"), "dot")
				if moving:
					var cols := [Color("#ff90c0"), Color("#ffffff"), Color("#ffe070")]
					_particle(gp + Vector2(rng.randf_range(-4, 4), 1), Vector2.ZERO, 6.0, cols[rng.randi() % 3], "flower")
				q_timer = 0.8
		"hang":
			if idle_t > 2.5:
				flip_v = true
		"chest":
			if idle_t > 2.0:
				posing = true
				if q_timer <= 0.0:
					q_state = "yawn"
					q_state_t = 0.6
					for i in 3:
						_particle(gp + Vector2(0, -8), Vector2(rng.randf_range(-20, 20), rng.randf_range(-40, -25)), 0.8, Color("#ffd040"), "coin")
					q_timer = rng.randf_range(4.0, 7.0)
	if not idle and def.get("quirk", "") in ["stick", "split"]:
		q_state = ""

func _draw() -> void:
	# particles are stored in global space
	for p in particles:
		var a: float = clampf(p["life"] / maxf(0.01, p["max"]), 0.0, 1.0)
		var lp: Vector2 = p["p"] - global_position
		var c: Color = p["col"]
		c.a = a
		match p["kind"]:
			"z":
				draw_string(ThemeDB.fallback_font, lp, "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, c)
			"paw":
				draw_circle(lp, 1.2, Color(c.r, c.g, c.b, a * 0.6))
				draw_circle(lp + Vector2(-1.5, -1.6), 0.6, Color(c.r, c.g, c.b, a * 0.6))
				draw_circle(lp + Vector2(1.5, -1.6), 0.6, Color(c.r, c.g, c.b, a * 0.6))
			"bubble":
				draw_arc(lp, 1.6, 0, TAU, 8, c, 0.8)
			"flower":
				draw_circle(lp, 1.0, c)
				draw_circle(lp + Vector2(0, 1.2), 0.5, Color(0.4, 0.8, 0.4, a))
			"coin":
				draw_rect(Rect2(lp - Vector2(1, 1), Vector2(2, 2)), c)
			"glow":
				draw_circle(lp, 2.2, Color(c.r, c.g, c.b, a * 0.25))
				draw_circle(lp, 0.8, c)
			_:
				draw_circle(lp, 0.9, c)
	# shadow
	draw_set_transform(Vector2.ZERO, 0, Vector2(1, 0.4))
	draw_circle(Vector2(0, 0), 5.0, Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2.ZERO)
	# fetch cooldown ring (only once the pet can fetch with F)
	if tier >= 1 and fetch_cd > 0.0 and float(st["fetch_cd"]) > 0:
		var k := 1.0 - fetch_cd / float(st["fetch_cd"])
		draw_arc(Vector2(0, -6), 9.0, -PI / 2, -PI / 2 + TAU * k, 24, Color(0.7, 0.9, 1.0, 0.55), 1.0)
	elif tier >= 1 and state == "follow":
		draw_arc(Vector2(0, -6), 9.0, 0, TAU, 24, Color(0.6, 1.0, 0.7, 0.18), 1.0)
	if state in ["blink_out"]:
		return   # vanished mid-blink
	var bob := -sin(hop * PI) * 4.0 * minf(1.0, hop * 2.0)
	if def.get("quirk", "") in ["bubbles", "sheet", "hang"]:
		bob += sin(t * 3.0) * 2.0 - 3.0
	var scale_v := Vector2(face, squash)
	if flip_v:
		scale_v.y = -1.0
		bob -= 14.0
	var tex_draw: Texture2D = tex
	var mod := Color(1, 1, 1, alpha)
	if posing:
		tex_draw = Art.sprite("pet_mimic_chest")
		scale_v = Vector2(1, 1)
	draw_set_transform(Vector2(0, bob), spin, scale_v)
	var sz := tex_draw.get_size()
	draw_texture(tex_draw, Vector2(-sz.x / 2.0, -sz.y), mod)
	# tier accessories, drawn in sprite space
	if tier >= 1:
		draw_line(Vector2(-2, -sz.y + 6), Vector2(2, -sz.y + 6), Color("#e04848"), 1.0)   # scarf
	if tier >= 2:
		draw_rect(Rect2(Vector2(0, -sz.y + 6), Vector2(1, 1)), Color("#ffe060"))      # bell
	if tier >= 3:
		var hat_col: Color = Color("#5060c0") if def.get("quirk", "") != "pocket" else [Color("#8a5a34"), Color("#5ab0ff"), Color("#ffe35a"), Color("#c070ff"), Color("#ff8c2a")][clampi(tier - 1, 0, 4)]
		draw_rect(Rect2(Vector2(-2, -sz.y - 2), Vector2(4, 2)), hat_col)
	if tier >= 5:
		var tw := 0.5 + 0.5 * sin(t * 6.0)
		draw_rect(Rect2(Vector2(-2, -sz.y - 4), Vector2(1, 1)), Color(1, 0.85, 0.3, tw))
		draw_rect(Rect2(Vector2(1, -sz.y - 4), Vector2(1, 1)), Color(1, 0.85, 0.3, 1.0 - tw))
	if def.get("quirk", "") == "pocket" and tier < 3:
		draw_rect(Rect2(Vector2(-2, -sz.y - 1), Vector2(4, 1)), Color("#8a5a34"))
	if q_state == "stick":
		draw_line(Vector2(3, -4), Vector2(9, -6), Color("#8a5a34"), 1.0)
	if q_state == "tongue":
		draw_line(Vector2(3, -5), Vector2(12, -9), Color("#ff8080"), 1.0)
	draw_set_transform(Vector2.ZERO)
	if q_state == "split":
		var k2 := sin(clampf(q_state_t / 1.6, 0, 1) * PI)
		for sx in [-1.0, 1.0]:
			var off := Vector2(sx * 9.0 * k2, 0)
			draw_texture_rect(tex, Rect2(off + Vector2(-3, -6), Vector2(6, 6)), false, mod)
	if q_state == "yawn":
		draw_rect(Rect2(Vector2(-3, -9), Vector2(6, 2)), Color("#300818"))
	# what it just picked up, carried overhead
	if carry_t > 0.0 and carry_tex != null:
		draw_texture(carry_tex, Vector2(-6, -sz.y - 14 + bob), Color(1, 1, 1, minf(1.0, carry_t * 2.0)))
	if beam_t > 0.0:
		var h := 30.0 * beam_t
		draw_line(Vector2(0, -sz.y), Vector2(0, -sz.y - h), Color(carry_col.r, carry_col.g, carry_col.b, 0.5 * beam_t), 2.0)
