extends AnimatedSprite2D
## Animated sheet sprite for an actor (player, enemy, boss, minion) built at runtime from
## data/art/sprites.json (see Art.sprite_def). Purely visual: it reads the actor's public
## state every frame and never writes to it, never touches an RNG and has no collision.
##
## Gameplay drives animation, never the other way round:
##  - actions marked "sync" are stretched over the gameplay timing (player use time and
##    melee impact delay, enemy wind-up + recover, dodge time), and the manifest's
##    impact_frame is the frame on screen when the hit lands;
##  - loops (idle, run, channel) run on their own clock at the manifest fps.
##
## The actor's old Sprite2D stays in the tree (its texture is hidden with self_modulate)
## so existing code that sets sprite.modulate / sprite.visible keeps working: this node
## copies those two values from it each frame.

const Rules = preload("res://scripts/gfx/anim_rules.gd")

var def := {}
var actor = null
var src: Sprite2D = null        # the actor's fallback sprite we mirror visibility/modulate from
var dir := 0                    # current 8-way direction (anim_rules.gd)
var cur := ""                   # current animation name (manifest name)
var cur_frame := 0
var clock := 0.0                # seconds in the current looped / one-shot animation
var speed := 1.0                # gallery speed slider
var fixed_dir := -1             # gallery: force a direction
var forced_anim := ""           # gallery: force an animation (synced ones then loop on their fps)
var face_vec := Vector2.DOWN
var _hit_left := 0.0
var _last_flash := 0.0
var _hysteresis := Rules.HYSTERESIS_DEG
var _move_speed := 4.0

func setup(d: Dictionary, a = null, source: Sprite2D = null) -> void:
	def = d
	actor = a
	src = source
	sprite_frames = Art.sprite_frames_for(d)
	centered = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	scale = Vector2(Art.ART_SCALE, Art.ART_SCALE)
	_hysteresis = float(Art.render.get("direction_hysteresis_deg", Rules.HYSTERESIS_DEG))
	_move_speed = float(Art.render.get("move_anim_speed", 4.0))
	if src != null:
		src.self_modulate.a = 0.0
	_show("idle", 0)

func has_anim(n: String) -> bool:
	return def.get("anims", {}).has(n)

## Height of the drawn figure above the actor's origin, in world units.
func height_world() -> float:
	return float(def["pivot"][1]) * Art.ART_SCALE

func _process(delta: float) -> void:
	delta *= speed
	if src != null:
		visible = src.visible
		modulate = src.modulate
	if actor != null and is_instance_valid(actor):
		_from_actor(delta)
	else:
		_free_run(delta)

# ------------------------------------------------------------------ gallery / preview
func _free_run(delta: float) -> void:
	var n := forced_anim if forced_anim != "" and has_anim(forced_anim) else "idle"
	if n != cur:
		clock = 0.0
	clock += delta
	if fixed_dir >= 0:
		dir = fixed_dir
	var a: Dictionary = def["anims"][n]
	var f := Rules.looped_frame(clock, float(a.get("fps", 10)), int(a.get("frames", 1)), true)
	_show(n, f)

# ------------------------------------------------------------------ actor driven
func _from_actor(delta: float) -> void:
	var st := _state()
	var n: String = st["anim"]
	if not has_anim(n):
		n = _substitute(n)
	if n != cur:
		clock = 0.0
	clock += delta
	if st.has("face") and st["face"] != Vector2.ZERO:
		face_vec = st["face"]
	dir = fixed_dir if fixed_dir >= 0 else Rules.pick(face_vec, dir, int(def.get("directions", 8)), _hysteresis)
	var a: Dictionary = def["anims"][n]
	var nf := int(a.get("frames", 1))
	var f := 0
	if st.has("k") and a.has("sync"):
		f = Rules.synced_frame(st["k"], st.get("impact_k", 0.0), nf, int(a.get("impact_frame", 0)))
	elif n == "death":
		f = mini(Rules.looped_frame(clock, float(a.get("fps", 10)), nf, false), int(a.get("corpse_frame", nf - 1)))
	else:
		var fps := float(a.get("fps", 10))
		var loop := bool(a.get("loop", false)) or n in ["idle", "run"]
		f = Rules.looped_frame(clock, fps, nf, loop)
	_show(n, f)

## Missing animations borrow the closest one the sheet has.
func _substitute(n: String) -> String:
	var order := {"cast": ["attack"], "attack": ["cast"], "channel": ["cast", "attack"],
		"special": ["attack"], "dodge": ["run"], "run": ["idle"], "hit": ["idle"],
		"death": ["hit", "idle"], "stagger": ["hit", "idle"], "phase_change": ["idle"]}
	for alt in order.get(n, []):
		if has_anim(alt):
			return alt
	return "idle"

## Reads the actor's public state. Returns {"anim", "face"?, "k"?, "impact_k"?}.
func _state() -> Dictionary:
	var a = actor
	var vel: Vector2 = a.velocity if "velocity" in a else Vector2.ZERO
	var moving := vel.length() > _move_speed
	if not a.alive:
		return {"anim": "death"}
	var out := {}
	if "dodge_t" in a:   # player
		var aim: Vector2 = a.aim_pos - a.global_position if "aim_pos" in a else Vector2.ZERO
		if a.dodge_t > 0.0:
			var dd := 0.24
			var cm: Dictionary = a.get_script().get_script_constant_map() if a.get_script() != null else {}
			if cm.has("DODGE_TIME"):
				dd = float(cm["DODGE_TIME"])
			return {"anim": "dodge", "face": a.dodge_dir, "k": 1.0 - a.dodge_t / maxf(dd, 0.001)}
		if a.busy > 0.0 and a.current_use_time > 0.0:
			var kind: String = str(a.get("swing_skill_kind")) if a.get("swing_skill_kind") != null else ""
			var n := "attack" if kind == "attack" else "cast"
			if a.swing_kind == "beam":
				return {"anim": "channel", "face": aim}
			var dur: float = a.current_use_time
			var imp: float = float(a.get("swing_impact")) if a.get("swing_impact") != null else 0.0
			return {"anim": n, "face": aim, "k": 1.0 - a.busy / dur, "impact_k": imp / dur}
		out = {"anim": "run" if moving else "idle"}
		if moving:
			out["face"] = vel
	elif "state" in a and "state_t" in a and "def" in a:   # enemy / boss
		var s: String = str(a.state)
		var face: Vector2 = a.attack_dir if "attack_dir" in a else Vector2.ZERO
		if s == "windup" or s == "recover":
			var wu := maxf(float(a.def.get("windup", 0.5)), 0.01)
			var rc := maxf(float(a.def.get("recover", 0.8)), 0.01)
			var ik := wu / (wu + rc)
			var k := 0.0
			if s == "windup":
				k = clampf(1.0 - a.state_t / wu, 0.0, 1.0) * ik
			else:
				k = ik + clampf(1.0 - a.state_t / rc, 0.0, 1.0) * (1.0 - ik)
			return {"anim": "attack", "face": face, "k": k, "impact_k": ik}
		out = {"anim": "run" if moving else "idle"}
		if moving:
			out["face"] = vel
	else:
		out = {"anim": "run" if moving else "idle"}
		if moving:
			out["face"] = vel
	# short hit reaction when not acting
	var fl: float = float(a.flash) if "flash" in a else 0.0
	if fl > _last_flash + 0.01 and has_anim("hit"):
		var ha: Dictionary = def["anims"]["hit"]
		_hit_left = float(ha.get("frames", 2)) / maxf(float(ha.get("fps", 10)), 1.0)
	_last_flash = fl
	if _hit_left > 0.0:
		_hit_left -= get_process_delta_time() * speed
		out["anim"] = "hit"
	return out

func _show(n: String, f: int) -> void:
	var rf: Array = Rules.row_for(dir, int(def.get("directions", 8)), bool(def.get("mirror", true)))
	var an := "%s_%d" % [n, int(rf[0])]
	if not sprite_frames.has_animation(an):
		return
	if animation != StringName(an):
		animation = an
	cur = n
	cur_frame = clampi(f, 0, sprite_frames.get_frame_count(an) - 1)
	frame = cur_frame
	flip_h = rf[1]
	var fw := float(def["frame"][0])
	var px := float(def["pivot"][0])
	var py := float(def["pivot"][1])
	offset = Vector2(-(fw - px) if flip_h else -px, -py)
