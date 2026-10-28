extends RefCounted
# Developer tools rules (Godot 4.0, no class_name). Pure functions: no scene or
# autoload access, so they are easy to unit test.
# Usage: const DevRules = preload("res://scripts/core/dev_rules.gd")
# Config: data/dev_tools.json, loaded as Data.dev_cfg.

## Runtime flags and their defaults. Nothing here is ever saved; turning the
## Developer tools setting off restores exactly these values.
static func default_flags() -> Dictionary:
	return {
		"god": false,            # player takes no damage, no stun, no statuses
		"one_hit": false,        # player hits are multiplied by one_hit_mult
		"damage_mult": 1.0,      # player hit multiplier
		"infinite_mana": false,  # skills cost nothing (mana or life)
		"no_cooldowns": false,
		"infinite_flasks": false,
		"move_mult": 1.0,
		"freeze_ai": false,      # enemies stand still and never attack
		"loot_luck": 1.0,        # multiplies drop chance and effective rarity
		"reveal_hidden": false,  # loot filter hidden items are shown (like holding Alt)
		"overlay": false,        # debug overlay on the HUD
		"hitboxes": false,       # Godot collision shape debug draw
		"time_scale": 1.0,
		"frame_pause": false,    # world paused, single-step with "Step"
	}

## Flags that make a character "dev tainted" when switched away from their default.
## Purely visual / debug flags (overlay, hitboxes, time scale, frame pause) do not.
const TAINTING_FLAGS := ["god", "one_hit", "damage_mult", "infinite_mana", "no_cooldowns",
	"infinite_flasks", "move_mult", "freeze_ai", "loot_luck", "reveal_hidden"]

static func flag_taints(flag: String) -> bool:
	return TAINTING_FLAGS.has(flag)

## Flags that differ from their defaults (for diagnostics).
static func active_flags(flags: Dictionary) -> Array:
	var d := default_flags()
	var out := []
	for k in d:
		if flags.has(k) and flags[k] != d[k]:
			out.append("%s=%s" % [k, str(flags[k])])
	return out

static func cfg_value(cfg: Dictionary, key: String, fallback):
	return cfg.get(key, fallback) if typeof(cfg) == TYPE_DICTIONARY else fallback

static func max_level(cfg: Dictionary) -> int:
	return int(cfg_value(cfg, "max_level", 60))

static func clamp_level(cfg: Dictionary, n: int) -> int:
	return clampi(n, 1, max_level(cfg))

## XP needed to go from (cur_level, cur_xp) to exactly the start of `target`.
## xp_for_level(l) is the game's own "XP to go from level l to l+1" function, so
## no levelling maths is duplicated here. Returns 0 when target <= cur_level.
static func xp_to_reach(cur_level: int, cur_xp: int, target: int, xp_for_level: Callable) -> int:
	if target <= cur_level:
		return 0
	var need := 0
	for l in range(cur_level, target):
		need += int(xp_for_level.call(l))
	return maxi(0, need - cur_xp)

## Adds delta to an amount, never below zero and never above the cap (JSON-safe).
static func add_amount(cfg: Dictionary, cur: int, delta: int) -> int:
	var cap := int(cfg_value(cfg, "amount_cap", 2000000000))
	return clampi(cur + delta, 0, cap)

static func set_amount(cfg: Dictionary, n: int) -> int:
	return add_amount(cfg, 0, n)

## Multiplier applied to player hits (damage multiplier and one-hit kills combined).
static func hit_mult(cfg: Dictionary, flags: Dictionary) -> float:
	var m := maxf(0.0, float(flags.get("damage_mult", 1.0)))
	if flags.get("one_hit", false):
		m *= float(cfg_value(cfg, "one_hit_mult", 1000))
	return m

## Effective rarity bonus under the loot luck multiplier: luck 1 leaves it unchanged,
## luck x multiplies (100 + bonus), so luck also helps when the base bonus is 0.
static func lucky_rarity(bonus: float, luck: float) -> float:
	if luck <= 1.0:
		return bonus
	return (bonus + 100.0) * luck - 100.0

static func clamp_time_scale(cfg: Dictionary, v: float) -> float:
	var ts: Dictionary = cfg_value(cfg, "time_scale", {})
	return clampf(v, float(ts.get("min", 0.1)), float(ts.get("max", 4.0)))

## Why an item spawn request is invalid ("" = valid). bases / rarities are the
## Data dictionaries keyed by id; max_sockets is Loot.max_sockets for that base.
static func spawn_refusal(cfg: Dictionary, bases: Dictionary, rarities: Dictionary, base_id: String, rarity: String, ilvl: int, sockets: int, max_sockets: int) -> String:
	if not bases.has(base_id):
		return "Unknown item base"
	if not rarities.has(rarity):
		return "Unknown rarity"
	if ilvl < 1 or ilvl > int(cfg_value(cfg, "spawn_ilvl_max", 100)):
		return "Item level must be 1-%d" % int(cfg_value(cfg, "spawn_ilvl_max", 100))
	if sockets < 0 or sockets > max_sockets:
		return "This base holds 0-%d sockets" % max_sockets
	return ""

## The best affix tier an item of ilvl may hold, and that tier's top value.
## tiers is the affix's "tiers" array: [[ilvl_req, min, max], ...]. Returns [index, value, ilvl_req].
static func max_affix_roll(tiers: Array, ilvl: int) -> Array:
	var best := 0
	for i in tiers.size():
		if int(tiers[i][0]) <= ilvl:
			best = i
	if tiers.is_empty():
		return [0, 0.0, 1]
	return [best, float(tiers[best][2]), int(tiers[best][0])]

## Points on a ring around `center` for spawning N things without stacking them.
static func spread_points(center: Vector2, n: int, radius: float) -> Array:
	var out := []
	if n <= 1:
		out.append(center)
		return out
	for i in n:
		out.append(center + Vector2.RIGHT.rotated(TAU * i / float(n)) * radius)
	return out

## Diagnostic text block (also used for the clipboard).
static func diagnostics(info: Dictionary) -> String:
	var keys := ["game", "engine", "save_version", "class", "level", "tier", "dungeon", "depth", "seed", "flags", "dev_used"]
	var lines := []
	for k in keys:
		if info.has(k):
			lines.append("%s: %s" % [k, str(info[k])])
	return "\n".join(lines)
