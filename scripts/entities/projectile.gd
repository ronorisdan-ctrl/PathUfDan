extends Node2D
## Projectiles for players, turrets and enemies. Supports pierce, chain,
## explode-on-impact and light homing. Destroyed by walls or range.

const VFX = preload("res://scripts/fx/vfx.gd")

var level = null
var source = null
var packet := {}
var faction := "player"
var vel := Vector2.ZERO
var max_dist := 300.0
var traveled := 0.0
var radius := 4.0
var pierce := 0
var chain := 0
var explode_radius := 0.0
var kind := "arrow"
var color := Color.WHITE
var origin := Vector2.ZERO
var hit_ids := {}
var homing := 0.0
var pull := false
var trail := []
var light: PointLight2D

func _ready() -> void:
	origin = global_position
	rotation = vel.angle()
	z_index = 5
	if kind in ["fire", "ice", "orb", "spark"]:
		light = PointLight2D.new()
		light.texture = Art.light_tex
		light.color = color
		light.energy = 0.8
		light.texture_scale = 0.45
		add_child(light)

func _physics_process(delta: float) -> void:
	if level == null:
		queue_free()
		return
	if homing > 0:
		var tgt = level.nearest_hostile(global_position, faction, 160.0, hit_ids)
		if tgt != null:
			var want: Vector2 = (tgt.global_position - global_position).normalized() * vel.length()
			vel = vel.lerp(want, clampf(homing * delta, 0, 1))
			rotation = vel.angle()
	var step := vel * delta
	var nxt := global_position + step
	if kind != "wave" and level.is_solid(nxt):
		_end(true)
		return
	if kind == "wave" and level.is_solid(nxt):
		_end(false)
		return
	trail.push_front(global_position)
	if trail.size() > 4:
		trail.pop_back()
	global_position = nxt
	traveled += step.length()
	var targets: Array = level.enemies if faction == "player" else level.allies
	for t in targets:
		if not is_instance_valid(t) or not t.alive:
			continue
		var id: int = t.get_instance_id()
		if hit_ids.has(id):
			continue
		if global_position.distance_to(t.global_position + Vector2(0, -4)) <= radius + t.radius + 2:
			hit_ids[id] = true
			_hit(t)
			if not is_inside_tree() or is_queued_for_deletion():
				return
	if traveled >= max_dist:
		_end(false)
	queue_redraw()

func _hit(t) -> void:
	if explode_radius > 0:
		_explode()
		queue_free()
		return
	Combat.deal(packet, source, t, origin)
	if pull and t.alive and not t.is_boss and source != null and is_instance_valid(source):
		t.knock += (source.global_position - t.global_position).normalized() * minf(420.0, t.global_position.distance_to(source.global_position) * 3.0)
		t.add_status("stun", 0.4, {})
	if packet.get("knockback", 0.0) > 0 and t.alive and not t.is_boss:
		t.knock += vel.normalized() * packet["knockback"]
	if chain > 0:
		var nxt = level.nearest_hostile(global_position, faction, 150.0, hit_ids)
		if nxt != null:
			chain -= 1
			vel = (nxt.global_position - global_position).normalized() * vel.length()
			rotation = vel.angle()
			traveled = maxf(0.0, traveled - 120.0)
			return
	if pierce > 0:
		pierce -= 1
		return
	queue_free()

func _end(hit_wall: bool) -> void:
	if explode_radius > 0:
		_explode()
	elif hit_wall and level != null:
		level.add_fx(VFX.make("spark", global_position, color, 0.15, 8))
	queue_free()

func _explode() -> void:
	if level == null:
		return
	level.add_fx(VFX.make("explosion", global_position, color, 0.35, explode_radius))
	for t in level.hostiles_in_radius(global_position, explode_radius, faction):
		Combat.deal(packet, source, t, origin)

func _draw() -> void:
	match kind:
		"arrow":
			draw_line(Vector2(-7, 0), Vector2(3, 0), Color("#8a5a34"), 1.0)
			draw_line(Vector2(3, 0), Vector2(6, 0), Color("#d0d8e0"), 2.0)
			draw_line(Vector2(-7, -1.5), Vector2(-4, 0), Color("#f0ece0"), 1.0)
			draw_line(Vector2(-7, 1.5), Vector2(-4, 0), Color("#f0ece0"), 1.0)
		"bolt":
			draw_line(Vector2(-8, 0), Vector2(6, 0), Color(1, 1, 1, 0.35), 4.0)
			draw_line(Vector2(-8, 0), Vector2(6, 0), Color("#e0e0e0"), 1.5)
		"fire":
			for i in trail.size():
				var lp: Vector2 = to_local(trail[i])
				draw_circle(lp, radius * (0.8 - i * 0.15), Color(1, 0.4, 0.1, 0.35 - i * 0.07))
			draw_circle(Vector2.ZERO, radius, Color(1, 0.45, 0.1, 0.9))
			draw_circle(Vector2(1, 0), radius * 0.55, Color(1, 0.9, 0.5, 1))
		"ice":
			var pts := PackedVector2Array([Vector2(8, 0), Vector2(0, -2.5), Vector2(-7, 0), Vector2(0, 2.5)])
			draw_colored_polygon(pts, Color("#9ae4ff"))
			draw_line(Vector2(-6, 0), Vector2(7, 0), Color(1, 1, 1, 0.9), 1.0)
		"orb":
			draw_circle(Vector2.ZERO, radius + 1.5, Color(color.r, color.g, color.b, 0.35))
			draw_circle(Vector2.ZERO, radius, color)
			draw_circle(Vector2.ZERO, radius * 0.4, Color(1, 1, 1, 0.9))
		"wave":
			var a := 1.0 - traveled / max_dist * 0.6
			draw_arc(Vector2(-4, 0), radius, -0.9, 0.9, 10, Color(0.8, 0.65, 0.45, a), 4.0)
			draw_arc(Vector2(-8, 0), radius * 0.8, -0.8, 0.8, 8, Color(0.5, 0.4, 0.3, a * 0.7), 3.0)
		_:
			draw_circle(Vector2.ZERO, radius, color)
