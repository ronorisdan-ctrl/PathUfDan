extends RefCounted
## Pure helper rules for sheet animation: 8-way direction picking with hysteresis,
## direction -> sheet row mapping (with mirroring) and gameplay-synced frame timing.
## No nodes, no RNG, no engine state, so everything here is unit tested.
##
## Direction index (8-way), screen space (x right, y down):
##   0 S, 1 SE, 2 E, 3 NE, 4 N, 5 NW, 6 W, 7 SW
## Sheet rows (data/art/sprites.json "directions" + "mirror"):
##   8 + mirror : S, SE, E, NE, N         (NW, W, SW = NE, E, SE flipped)
##   8 no mirror: S, SE, E, NE, N, NW, W, SW
##   4 + mirror : S, E, N                 (W = E flipped)
##   4 no mirror: S, E, N, W
##   2 + mirror : E                       (W = E flipped)
##   2 no mirror: E, W
##   1          : one row (flipped when facing left if mirror is true)

const NAMES := ["S", "SE", "E", "NE", "N", "NW", "W", "SW"]
const HYSTERESIS_DEG := 8.0

## Centre angle (radians, Vector2.angle() convention) of an 8-way direction.
static func dir_angle(d8: int) -> float:
	return deg_to_rad(90.0 - 45.0 * float(d8))

## Raw 8-way index for a vector (no hysteresis). Zero vector -> -1.
static func dir8(v: Vector2) -> int:
	if v.length_squared() < 0.0001:
		return -1
	var deg := rad_to_deg(v.angle())
	return posmod(int(round((90.0 - deg) / 45.0)), 8)

## Raw index snapped to the set of directions a sheet supports, returned in 8-way terms.
static func snap(v: Vector2, directions: int) -> int:
	if v.length_squared() < 0.0001:
		return -1
	match directions:
		8:
			return dir8(v)
		4:
			var deg := rad_to_deg(v.angle())
			return posmod(int(round((90.0 - deg) / 90.0)), 4) * 2
		2:
			return 6 if v.x < 0 else 2
		_:
			return 6 if v.x < 0 else 2

## Picks the direction for `v`, keeping `current` while `v` is still within the current
## sector plus a hysteresis margin, so facing doesn't flicker on sector boundaries.
static func pick(v: Vector2, current: int, directions: int, margin_deg: float = HYSTERESIS_DEG) -> int:
	if v.length_squared() < 0.0001:
		return current if current >= 0 else 0
	if current >= 0 and directions >= 4:
		var half := 180.0 / float(directions)
		var diff := absf(rad_to_deg(angle_difference_compat(v.angle(), dir_angle(current))))
		if diff <= half + margin_deg:
			return current
	elif current >= 0 and directions <= 2:
		# left/right only: switch when x clearly changes sign
		if absf(v.x) < 0.05 * v.length():
			return current
	return snap(v, directions)

## Godot 4.0 has no angle_difference(); wrap to [-PI, PI].
static func angle_difference_compat(a: float, b: float) -> float:
	return wrapf(a - b, -PI, PI)

## Maps an 8-way direction to [row, flip_h] for a sheet layout.
static func row_for(d8: int, directions: int, mirror: bool) -> Array:
	var d := posmod(d8, 8)
	match directions:
		8:
			if not mirror:
				return [d, false]
			match d:
				5: return [3, true]
				6: return [2, true]
				7: return [1, true]
				_: return [d, false]
		4:
			# 0 S, 1 E, 2 N, 3 W (d is normally already snapped to an even value)
			var q := int(round(float(d) / 2.0)) % 4
			if not mirror:
				return [q, false]
			if q == 3:
				return [1, true]
			return [q, false]
		2:
			var west := d in [5, 6, 7]
			if mirror:
				return [0, west]
			return [1 if west else 0, false]
		_:
			return [0, mirror and d in [5, 6, 7]]

## Number of authored rows a sheet must have.
static func rows_needed(directions: int, mirror: bool) -> int:
	match directions:
		8: return 5 if mirror else 8
		4: return 3 if mirror else 4
		2: return 1 if mirror else 2
		_: return 1

## Frame for a gameplay-synced action.
##   k            : progress through the whole action, 0..1 (gameplay time / gameplay duration)
##   impact_k     : progress at which gameplay applies the hit (0 = at once, 1 = at the end)
##   frames       : frames in the animation
##   impact_frame : frame that must be showing when the hit lands
## Frames 0..impact_frame-1 share the time before the hit; impact_frame..end share the rest.
## The impact frame is always the one shown at k == impact_k.
static func synced_frame(k: float, impact_k: float, frames: int, impact_frame: int) -> int:
	if frames <= 1:
		return 0
	k = clampf(k, 0.0, 1.0)
	impact_k = clampf(impact_k, 0.0, 1.0)
	impact_frame = clampi(impact_frame, 0, frames - 1)
	if k < impact_k and impact_frame > 0:
		return clampi(int(floor(k / impact_k * float(impact_frame))), 0, impact_frame - 1)
	var after := frames - impact_frame
	if impact_k >= 1.0 or after <= 1:
		return impact_frame
	var k2 := (k - impact_k) / (1.0 - impact_k)
	return clampi(impact_frame + int(floor(k2 * float(after))), impact_frame, frames - 1)

## Frame of a free-running animation after `t` seconds.
static func looped_frame(t: float, fps: float, frames: int, loop: bool) -> int:
	if frames <= 1 or fps <= 0.0:
		return 0
	var f := int(floor(maxf(t, 0.0) * fps))
	return posmod(f, frames) if loop else mini(f, frames - 1)
