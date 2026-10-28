#!/usr/bin/env python3
"""Validate loot filter JSON files against the schema used by loot_filter.gd.
Usage: python tools/validate_loot_filters.py [files...]   (default: data/loot_filters/*.json)
Exit code 1 if any ERROR is found."""
import json, re, sys, glob, os

RAR = ["common", "uncommon", "rare", "epic", "legendary"]
VIS = ["show", "minimal", "hide"]
SIZES = ["small", "normal", "large", "huge"]
SHAPES = ["circle", "diamond", "square", "star"]
KINDS = ["gear", "charm", "gem", "rune", "material", "other"]
SLOTS = ["weapon_1h", "weapon_2h", "offhand", "helm", "chest", "gloves", "boots", "belt", "ring", "amulet", "charm"]
COND = {"rarity_min", "rarity_max", "kind", "slot", "name_contains", "ilvl_min", "ilvl_max",
        "ilvl_vs_player_min", "ilvl_vs_player_max", "sockets_min", "affix_any", "affix_min_matches",
        "affix_count_min", "is_upgrade", "tier_min", "tier_max"}
ACT = {"visibility", "color", "size", "beam", "sound", "minimap", "continue"}
HEX = re.compile(r"^#?([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$")

def check(path):
    out = []
    try:
        d = json.load(open(path, encoding="utf-8"))
    except Exception as e:
        return ["ERROR: invalid JSON: %s" % e]
    if d.get("version") != 1: out.append("ERROR: version must be 1")
    if d.get("default", "show") not in VIS: out.append("ERROR: bad default")
    s = d.get("safety", {}).get("never_hide_min_rarity", "legendary")
    if s not in RAR + ["none"]: out.append("ERROR: bad safety rarity")
    rules = d.get("rules", [])
    for i, r in enumerate(rules, 1):
        t = "rule %d (%s): " % (i, r.get("name", "?"))
        c, a = r.get("conditions", {}), r.get("actions", {})
        for k in c:
            if k not in COND: out.append("ERROR: " + t + "unknown condition " + k)
        for k in a:
            if k not in ACT: out.append("ERROR: " + t + "unknown action " + k)
        for k in ("rarity_min", "rarity_max"):
            if k in c and c[k] not in RAR: out.append("ERROR: " + t + "bad " + k)
        if "kind" in c and not set(c["kind"]) <= set(KINDS): out.append("ERROR: " + t + "bad kind")
        if "slot" in c and not set(c["slot"]) <= set(SLOTS): out.append("ERROR: " + t + "bad slot")
        if a.get("visibility", "show") not in VIS: out.append("ERROR: " + t + "bad visibility")
        if a.get("size", "normal") not in SIZES: out.append("ERROR: " + t + "bad size")
        for k in ("color", "beam"):
            if k in a and a[k] != "none" and not HEX.match(a[k]): out.append("ERROR: " + t + "bad colour " + k)
        m = a.get("minimap")
        if isinstance(m, dict):
            if m.get("shape") not in SHAPES: out.append("ERROR: " + t + "bad minimap shape")
            if not HEX.match(m.get("color", "")): out.append("ERROR: " + t + "bad minimap colour")
        elif m not in (None, "none"): out.append("ERROR: " + t + "minimap must be 'none' or object")
        if not c and not a.get("continue") and r.get("enabled", True) and i < len(rules):
            out.append("WARN: " + t + "matches everything; rules below never run")
    if len(rules) > 100: out.append("ERROR: more than 100 rules")
    return out

if __name__ == "__main__":
    files = sys.argv[1:] or sorted(glob.glob(os.path.join(os.path.dirname(__file__), "..", "data", "loot_filters", "*.json")))
    bad = 0
    for f in files:
        res = check(f)
        n_err = sum(1 for x in res if x.startswith("ERROR"))
        bad += n_err
        print("%-22s %s" % (os.path.basename(f), "OK" if not res else ""))
        for x in res: print("   " + x)
    sys.exit(1 if bad else 0)
