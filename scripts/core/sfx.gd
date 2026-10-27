extends Node
## Procedural sound effects synthesised at startup (no audio files needed).
## Call Sfx.play("hit"). A small player pool keeps overlapping sounds cheap.

const RATE := 22050
const POOL := 12

var streams := {}
var players := []
var next := 0
var last_played := {}
var rng := RandomNumberGenerator.new()

const VOLUMES := {"swing": -10.0, "hit": -8.0, "crit": -5.0, "shoot": -12.0, "spell": -11.0, "explode": -6.0,
	"pickup": -8.0, "drop_rare": -11.0, "drop_epic": -9.0, "drop_legendary": -6.0, "gold": -12.0, "levelup": -4.0, "hurt": -9.0, "death": -10.0, "portal": -8.0, "block": -8.0, "ui": -14.0, "boss": -3.0, "nope": -10.0, "chirp": -13.0}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	_build()

func play(id: String, pitch_var: float = 0.08) -> void:
	if not streams.has(id):
		return
	var now := Time.get_ticks_msec()
	if now - int(last_played.get(id, -1000)) < 45:
		return
	last_played[id] = now
	var p: AudioStreamPlayer = players[next]
	next = (next + 1) % POOL
	p.stream = streams[id]
	p.volume_db = VOLUMES.get(id, -8.0)
	p.pitch_scale = 1.0 + rng.randf_range(-pitch_var, pitch_var)
	p.play()

## Plays a sound at a fixed pitch (pets use this for their own chirp voice).
func play_pitched(id: String, pitch: float) -> void:
	play(id, 0.0)
	var p: AudioStreamPlayer = players[(next - 1 + POOL) % POOL]
	if p.stream == streams.get(id):
		p.pitch_scale = clampf(pitch, 0.25, 4.0) * (1.0 + rng.randf_range(-0.05, 0.05))

func _build() -> void:
	streams["swing"] = _make(0.13, func(t, k): return _noise() * (1.0 - k) * (0.6 * sin(TAU * (900.0 - 700.0 * k) * t) + 0.4))
	streams["hit"] = _make(0.10, func(t, k): return (sin(TAU * (140.0 - 60.0 * k) * t) * 0.8 + _noise() * 0.5) * pow(1.0 - k, 2.0))
	streams["crit"] = _make(0.16, func(t, k): return (sin(TAU * (320.0 - 150.0 * k) * t) * 0.7 + _noise() * 0.5) * pow(1.0 - k, 1.6))
	streams["block"] = _make(0.12, func(t, k): return (sin(TAU * 1250.0 * t) * 0.5 + sin(TAU * 1870.0 * t) * 0.3) * pow(1.0 - k, 3.0))
	streams["shoot"] = _make(0.12, func(t, k): return _square((620.0 - 380.0 * k) * t) * 0.4 * pow(1.0 - k, 2.0) + _noise() * 0.15 * (1.0 - k))
	streams["spell"] = _make(0.28, func(t, k): return sin(TAU * (380.0 + 420.0 * k + 25.0 * sin(TAU * 18.0 * t)) * t) * 0.5 * sin(PI * k))
	streams["explode"] = _make(0.45, func(t, k): return (_noise() * 0.9 + sin(TAU * 55.0 * t) * 0.6) * pow(1.0 - k, 2.2))
	streams["pickup"] = _make(0.14, func(t, k): return sin(TAU * (660.0 if k < 0.5 else 990.0) * t) * 0.45 * (1.0 - k))
	streams["drop_rare"] = _make(0.25, func(t, k): return (sin(TAU * (880.0 if k < 0.45 else 1318.5) * t) * 0.4 + sin(TAU * 1760.0 * t) * 0.1) * pow(1.0 - k, 1.5))
	streams["drop_epic"] = _make(0.4, func(t, k):
		var n: float = [659.25, 830.6, 987.8][mini(2, int(k * 3.0))]
		return (sin(TAU * n * t) * 0.42 + _square(n * 2.0 * t) * 0.06) * (1.0 - k * 0.6))
	streams["drop_legendary"] = _make(0.7, func(t, k):
		var n: float = [523.25, 659.25, 783.99, 1046.5, 1318.5][mini(4, int(k * 5.0))]
		return (sin(TAU * n * t) * 0.45 + sin(TAU * n * 1.5 * t) * 0.15 + _square(n * t) * 0.08) * (1.0 - k * 0.5))
	streams["gold"] = _make(0.18, func(t, k): return (sin(TAU * 1568.0 * t) + 0.5 * sin(TAU * 2349.0 * t)) * 0.3 * pow(1.0 - k, 2.0))
	streams["levelup"] = _make(0.7, func(t, k):
		var notes := [523.25, 659.25, 783.99, 1046.5]
		var n: float = notes[mini(3, int(k * 4.0))]
		return (sin(TAU * n * t) * 0.5 + _square(n * t) * 0.12) * (1.0 - k * 0.7))
	streams["hurt"] = _make(0.16, func(t, k): return _square((180.0 - 80.0 * k) * t) * 0.35 * (1.0 - k))
	streams["death"] = _make(0.6, func(t, k): return (_square((220.0 - 170.0 * k) * t) * 0.3 + _noise() * 0.15) * (1.0 - k))
	streams["portal"] = _make(0.6, func(t, k): return sin(TAU * (200.0 + 600.0 * k) * t) * 0.3 * sin(PI * k) + _noise() * 0.1 * sin(PI * k))
	streams["nope"] = _make(0.22, func(t, k): return _square((330.0 if k < 0.5 else 247.0) * t) * 0.25 * (1.0 - k * 0.6))
	streams["chirp"] = _make(0.12, func(t, k): return sin(TAU * (900.0 + 700.0 * sin(PI * k)) * t) * 0.4 * sin(PI * k))
	streams["ui"] = _make(0.04, func(t, k): return sin(TAU * 1400.0 * t) * 0.3 * (1.0 - k))
	streams["boss"] = _make(1.0, func(t, k): return (sin(TAU * 60.0 * t) * 0.7 + _square(90.0 * t) * 0.15 + _noise() * 0.2) * sin(PI * k))

func _noise() -> float:
	return rng.randf_range(-1.0, 1.0)

func _square(phase: float) -> float:
	return 1.0 if fmod(phase, 1.0) < 0.5 else -1.0

func _make(dur: float, fn: Callable) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / RATE
		var k := float(i) / n
		var v: float = clampf(fn.call(t, k), -1.0, 1.0)
		# short fade-in avoids clicks
		if i < 40:
			v *= i / 40.0
		data.encode_s16(i * 2, int(v * 30000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s
