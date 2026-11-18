extends Node2D
## Endgame 3D, The Broad Stroke: a strip of wet paint left by a stroke. Enemies in it get the
## status (chill); the player standing in it takes less damage (a short damage_reduction buff).
## Numbers: data/uniques.json broad_stroke effect_params.

var level = null
var owner_player = null
var a := Vector2.ZERO        # strip start (global)
var b := Vector2.ZERO        # strip end (global)
var width := 50.0
var life := 3.0
var tick := 0.25
var dr := 15.0
var status := "chill"
var _t := 0.0
var _age := 0.0

func setup(lv, pl, from: Vector2, to: Vector2, params: Dictionary) -> void:
	level = lv
	owner_player = pl
	a = from
	b = to
	width = float(params.get("width", 50))
	life = float(params.get("wet_life", 3.0))
	tick = maxf(0.05, float(params.get("tick", 0.25)))
	dr = float(params.get("wet_dr", 15))
	status = str(params.get("wet_status", "chill"))
	z_index = -1

static func seg_dist(p: Vector2, s0: Vector2, s1: Vector2) -> float:
	var d := s1 - s0
	var l2 := d.length_squared()
	if l2 < 0.001:
		return p.distance_to(s0)
	var k := clampf((p - s0).dot(d) / l2, 0.0, 1.0)
	return p.distance_to(s0 + d * k)

func contains(p: Vector2, pad: float = 0.0) -> bool:
	return seg_dist(p, a, b) <= width * 0.5 + pad

func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= life or level == null or not is_instance_valid(level):
		queue_free()
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = tick
	for e in level.enemies:
		if is_instance_valid(e) and e.alive and contains(e.global_position, float(e.radius)):
			Combat.apply_status(e, {"type": status}, {}, {"status_dur": 0.6})
	if owner_player != null and is_instance_valid(owner_player) and owner_player.alive and contains(owner_player.global_position):
		owner_player.add_buff("wet_paint", [{"stat": "damage_reduction", "type": "flat", "value": dr}], tick * 2.0)

func _draw() -> void:
	var k := clampf(1.0 - _age / maxf(0.1, life), 0.0, 1.0)
	draw_line(a - global_position, b - global_position, Color(0.95, 0.9, 0.78, 0.25 * k + 0.05), width)

func _process(_d: float) -> void:
	queue_redraw()
