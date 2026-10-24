extends RefCounted
## Collects modifiers from every source and resolves final values.
##
## Rules (applied everywhere):
##   final = (base + sum(flat)) * (1 + sum(increased)/100) * product(1 + more/100)
## "increased" modifiers are ADDITIVE with each other; "more" modifiers are MULTIPLICATIVE.
## Every modifier records its source (base, level, equipment, passive, buff, attribute)
## so the character sheet can show where a value comes from.

var mods := {}   # stat -> {flat, inc, more, src:{source:{flat,inc,more}}}
var flags := {}  # special mechanics (keystones, legendary effects) -> count

func add(stat: String, type: String, amount: float, source: String = "base") -> void:
	var m = mods.get(stat)
	if m == null:
		m = {"flat": 0.0, "inc": 0.0, "more": 1.0, "src": {}}
		mods[stat] = m
	match type:
		"flat":
			m["flat"] += amount
		"inc":
			m["inc"] += amount
		"more":
			m["more"] *= (1.0 + amount / 100.0)
		_:
			push_warning("Unknown modifier type %s on %s" % [type, stat])
			return
	var s = m["src"].get(source)
	if s == null:
		s = {"flat": 0.0, "inc": 0.0, "more": 0.0}
		m["src"][source] = s
	s[type] += amount

func add_mod(mod: Dictionary, source: String) -> void:
	add(mod.get("stat", ""), mod.get("type", "flat"), float(mod.get("value", 0.0)), source)

func add_flag(flag: String) -> void:
	flags[flag] = flags.get(flag, 0) + 1

func has_flag(flag: String) -> bool:
	return flags.get(flag, 0) > 0

func flat(stat: String) -> float:
	return mods[stat]["flat"] if mods.has(stat) else 0.0

func inc(stat: String) -> float:
	return mods[stat]["inc"] if mods.has(stat) else 0.0

func more(stat: String) -> float:
	return mods[stat]["more"] if mods.has(stat) else 1.0

func value(stat: String, base: float = 0.0) -> float:
	return (base + flat(stat)) * maxf(0.0, 1.0 + inc(stat) / 100.0) * more(stat)

## Sum of "increased" across several stats (e.g. damage + fire_damage + spell_damage)
func inc_sum(stats: Array) -> float:
	var t := 0.0
	for s in stats:
		t += inc(s)
	return t

func more_prod(stats: Array) -> float:
	var t := 1.0
	for s in stats:
		t *= more(s)
	return t

func source_breakdown(stat: String) -> Dictionary:
	return mods[stat]["src"] if mods.has(stat) else {}
