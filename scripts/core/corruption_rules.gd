extends RefCounted
## Pure item-corruption rules (no scene access; only reads Data.corruption_cfg).
## An item dictionary carries an optional integer "corruption" (0-100). The key is
## absent at 0, so old items and saves need no migration (same idea as "locked").
## Rolling crafts (see data/corruption.json) always apply in full first; then one
## roll decides whether the item gains `step` corruption. At `max` the item can no
## longer be crafted with a rolling craft. Exempt crafts always work.
## `cfg` is optional everywhere: tests pass their own, the game uses Data.corruption_cfg.

static func _c(cfg) -> Dictionary:
	return cfg if cfg != null else Data.corruption_cfg

static func max_level(cfg = null) -> int:
	return maxi(1, int(_c(cfg).get("max", 100)))

static func step(cfg = null) -> int:
	return maxi(1, int(_c(cfg).get("step", 20)))

static func chance(cfg = null) -> float:
	return clampf(float(_c(cfg).get("chance", 0.5)), 0.0, 1.0)

static func drop_start(cfg = null) -> int:
	return clampi(int(_c(cfg).get("drop_start", 0)), 0, max_level(cfg))

## Integer 0..max, 0 when the item is null or has no field.
static func get_level(it, cfg = null) -> int:
	if it == null or typeof(it) != TYPE_DICTIONARY:
		return 0
	return clampi(int(it.get("corruption", 0)), 0, max_level(cfg))

static func is_maxed(it, cfg = null) -> bool:
	return get_level(it, cfg) >= max_level(cfg)

static func rolls_for(craft_id: String, cfg = null) -> bool:
	return craft_id in _c(cfg).get("rolling_crafts", [])

static func is_exempt(craft_id: String, cfg = null) -> bool:
	return craft_id in _c(cfg).get("exempt_crafts", [])

## "" = allowed, otherwise the reason. Exempt crafts are always allowed.
static func craft_refusal(it, craft_id: String, cfg = null) -> String:
	if rolls_for(craft_id, cfg) and is_maxed(it, cfg):
		return str(_c(cfg).get("refusal_text", "Corrupted: this item can no longer be crafted"))
	return ""

## Clamps to 0..max and erases the key at 0 (saves stay unchanged for clean items).
static func set_level(it: Dictionary, n: int, cfg = null) -> void:
	var v := clampi(n, 0, max_level(cfg))
	if v == 0:
		it.erase("corruption")
	else:
		it["corruption"] = v

## How many more corruption hits the item can take before it locks (derived, not stored).
static func events_remaining(it, cfg = null) -> int:
	var left := max_level(cfg) - get_level(it, cfg)
	return int(ceil(float(left) / float(step(cfg))))

## Call AFTER the craft has been applied. Takes exactly one rng.randf() for a
## rolling craft and none otherwise. Returns {rolled, hit, before, after}.
static func roll(it: Dictionary, craft_id: String, rng: RandomNumberGenerator, cfg = null) -> Dictionary:
	var before := get_level(it, cfg)
	if not rolls_for(craft_id, cfg):
		return {"rolled": false, "hit": false, "before": before, "after": before}
	var hit: bool = rng.randf() < chance(cfg)
	if hit:
		set_level(it, before + step(cfg), cfg)
	return {"rolled": true, "hit": hit, "before": before, "after": get_level(it, cfg)}

## Text for the craft button, e.g. "50% chance of +20% corruption".
static func risk_text(cfg = null) -> String:
	return "%d%% chance of +%d%% corruption" % [int(round(chance(cfg) * 100.0)), step(cfg)]

## Toast text after a craft; r is the dictionary returned by roll().
static func result_text(r: Dictionary) -> String:
	if not r.get("rolled", false):
		return ""
	if r.get("hit", false):
		return "Corruption rose to %d%%" % int(r["after"])
	return "No corruption gained"

## Level to give a freshly dropped item (data: drop_start, default 0).
static func apply_drop_start(it: Dictionary, cfg = null) -> void:
	var s := drop_start(cfg)
	if s > 0:
		set_level(it, s, cfg)

# ------------------------------------------------------------------ display helpers (pure text and colours)

## Grey (low) -> amber (mid) -> red (high), interpolated smoothly from the data colours.
static func level_color(level: int, cfg = null) -> Color:
	var c: Dictionary = _c(cfg).get("colors", {})
	var low := Color(str(c.get("low", "#9aa0a6")))
	var mid := Color(str(c.get("mid", "#e0a030")))
	var high := Color(str(c.get("high", "#d03030")))
	var t := clampf(float(level) / float(max_level(cfg)), 0.0, 1.0)
	return low.lerp(mid, t * 2.0) if t < 0.5 else mid.lerp(high, (t - 0.5) * 2.0)

## Text bar for RichTextLabel tooltips (Godot 4.0 has no [bgcolor]): `segs` solid blocks,
## the filled ones in the corruption colour, the rest dark.
static func bar_bbcode(level: int, segs: int = 10, cfg = null) -> String:
	var filled := clampi(int(round(float(level) / float(max_level(cfg)) * float(segs))), 0, segs)
	var s := ""
	if filled > 0:
		s += "[color=#%s]%s[/color]" % [level_color(level, cfg).to_html(false), "\u2588".repeat(filled)]
	if filled < segs:
		s += "[color=#2e2a36]%s[/color]" % "\u2588".repeat(segs - filled)
	return s

## "3 more corruption events before lock" (derived, never stored).
static func events_text(it, cfg = null) -> String:
	var n := events_remaining(it, cfg)
	if n <= 0:
		return "Corrupted: cannot be crafted"
	return "%d more corruption event%s before lock" % [n, "" if n == 1 else "s"]

## Item tooltip block: the line with the number, the bar and, at max, the red lock line.
static func tooltip_bbcode(it, cfg = null) -> String:
	var lv := get_level(it, cfg)
	var col := level_color(lv, cfg).to_html(false)
	var out := "[color=#%s]Corruption: %d%%[/color]  %s" % [col, lv, bar_bbcode(lv, 10, cfg)]
	if is_maxed(it, cfg):
		out += "\n[color=#%s]Corrupted: cannot be crafted[/color]" % level_color(max_level(cfg), cfg).to_html(false)
	return out

## Extra lines for the Blacksmith confirm dialog ("" for crafts that do not roll).
static func confirm_text(it, craft_id: String, cfg = null) -> String:
	if not rolls_for(craft_id, cfg):
		return ""
	var lv := get_level(it, cfg)
	var s := "[color=#e0a030]Risk: %s[/color]\nCorruption is %d%%: %s." % [risk_text(cfg), lv, events_text(it, cfg)]
	if lv > int(_c(cfg).get("confirm_above", 60)):
		s += "\n[color=#ff8080]Warning: this item is close to being locked. Another hit may end its crafting.[/color]"
	return s

static func needs_warning(it, craft_id: String, cfg = null) -> bool:
	return rolls_for(craft_id, cfg) and get_level(it, cfg) > int(_c(cfg).get("confirm_above", 60))
