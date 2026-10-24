extends Node
## Makes a torch light flicker.

var light: PointLight2D
var t := 0.0
var base := 1.0
var seed_off := 0.0

func _ready() -> void:
	seed_off = randf() * 10.0
	if light:
		base = light.energy

func _process(delta: float) -> void:
	if light == null:
		return
	t += delta
	light.energy = base * (0.85 + 0.1 * sin(t * 9.0 + seed_off) + 0.06 * sin(t * 23.0 + seed_off * 2.0))
