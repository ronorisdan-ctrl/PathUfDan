"""Generate docs/ART_ASSET_LIST.md from data/art/sprites.json and data/*.json.

    python tools/make_asset_list.py

For every sprite id: size, directions, animations, pivot, palette subset, gameplay notes,
status (missing / placeholder / partial / done) and a ready-to-paste generation prompt per
animation. Ordered by phase, then tier. Re-run after ingesting art or editing the manifest.
"""
import datetime
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import art_common as ac  # noqa: E402

OUT = os.path.join(ac.ROOT, "docs", "ART_ASSET_LIST.md")
PHASE_ORDER = ["V1", "V2", "V3", "V4", "V5", "V6"]
PHASE_NAME = {"V1": "V1 - Player and feel", "V2": "V2 - Tier 1 world", "V3": "V3 - Enemies and bosses",
              "V4": "V4 - VFX", "V5": "V5 - UI art", "V6": "V6 - Remaining tiers and polish"}
CAT_ORDER = {"classes": 0, "monsters": 1, "bosses": 2, "minions": 3}
KEYWORDS = [  # description words -> palette ramps (bone black is always added for outlines)
    (("slate", "iron", "armour", "armoured", "brass"), "Slate"),
    (("madder", "blood", "tabard"), "Blood madder"),
    (("sienna", "leather", "wood", "skin"), "Burnt sienna"),
    (("verdigris", "mould", "damp", "corroded"), "Verdigris"),
    (("ochre", "gold", "gilt", "gilded", "brass", "fletching", "varnish", "naples"), "Yellow ochre"),
    (("lead white", "bone", "bones", "chalky", "trim", "linen", "canvas", "flakes", "peeling"), "Lead white (aged)"),
]
ACCENT_WORDS = [
    (("ultramarine",), ["2a2660", "6a5ad8"]), (("cerulean", "frost", "rime", "ice"), ["5aa8c8"]),
    (("vermilion", "fire", "ember"), ["e0482a", "f08038"]), (("lightning", "storm", "yellow-white"), ["f4e890"]),
    (("linen", "canvas", "void", "hole"), ["d8ccb0"]), (("verdaccio", "dead colour"), ["6a6e50"]),
]
BEATS = {
    "idle": "held breathing loop, strong still pose; enemies may twitch wrongly on frame 2",
    "run": "run/walk loop, contact - passing - contact - passing poses, no sliding",
    "channel": "looping channel pose for beam skills, hands held out, fresh-paint glow pulsing",
    "dodge": "dodge roll in the facing direction, ends back in a ready pose",
    "hit": "frame 0 recoil flash to lead white, frame 1 recovering",
    "death": "collapse, ending in pigment flakes that scatter; the last frame is the corpse left on the floor",
    "phase_change": "phase change pose: one paint layer peels away to show the next",
    "stagger": "poise break: off balance, vulnerable, looping",
}


def ramps_for(e):
    text = e.get("desc", "").lower()
    cols = list(ac.RAMPS["Bone black - umber"])
    names = ["Bone black - umber"]
    for words, ramp in KEYWORDS:
        if any(w in text for w in words) and ramp not in names:
            names.append(ramp)
            cols += ac.RAMPS[ramp]
    if len(names) == 1:
        names.append("Lead white (aged)")
        cols += ac.RAMPS["Lead white (aged)"]
    for glint in ("ddd2b8", "f0e8d4"):   # lead white highlights and metal glints
        if glint not in cols:
            cols.append(glint)
    for words, acc in ACCENT_WORDS:
        if any(w in text for w in words):
            cols += [a for a in acc if a not in cols]
    return names, cols


def beat(an, a, e):
    n = int(a.get("frames", 1))
    if an in ("attack", "cast", "special"):
        imp = int(a.get("impact_frame", 0))
        if imp == 0:
            pre = "frame 0 is already the release/impact (the hit lands at once in gameplay)"
        else:
            pre = "frames 0-%d wind-up%s" % (imp - 1, " (the first two read as a clear pose change)" if imp >= 2 else "")
        what = {"attack": e.get("attack_label", "attack"), "cast": "spell cast, hands catch fresh-paint colour",
                "special": a.get("what", "special move")}[an]
        return "%s: %s, frame %d = IMPACT (smear frame), frames %d-%d recovery" % (what, pre, imp, imp + 1, n - 1) \
            if imp < n - 1 else "%s: %s, frame %d = IMPACT" % (what, pre, imp)
    return BEATS.get(an, an)


def figure_height(e):
    fw, fh = e["frame"]
    if e.get("category") == "bosses":
        return "%d-%d px" % (int(fh * 0.7), fh - 10)
    if fh <= 32:
        return "20-30 px"
    return "44-50 px"


def prompt(sid, an, a, e, cols):
    fw, fh = e["frame"]
    rows = ac.DIR_ROWS[(int(e["directions"]), bool(e["mirror"]))]
    n = int(a.get("frames", 1))
    rows_txt = ("%d rows for directions in the order %s" % (len(rows), ", ".join(
        {"S": "south", "SE": "south-east", "E": "east", "NE": "north-east", "N": "north", "NW": "north-west",
         "W": "west", "SW": "south-west"}.get(r, r) for r in rows))) if len(rows) > 1 else "1 row"
    no_weapon = " No weapon in hand (weapons are a separate layer)." if e.get("category") == "classes" else ""
    return (
        "Pixel art sprite sheet, top-down three-quarter view, dark gothic fantasy ARPG that looks like a "
        "forgotten master's oil painting rendered as pixel art.\n"
        "Subject: %s.\n"
        "Canvas: each frame %dx%d px, %d frames in a row, %s. Transparent background, no padding, "
        "no grid lines. Figure about %s tall, feet on the line y=%d centred at x=%d, same position in every frame.\n"
        "Style: 1 px selective outline (darkest material shade on the lit side, near-black #0c0a0d on the shadow "
        "side and at the feet), key light from the upper left, 4-6 shades per material, highlights shift toward "
        "ochre and shadows toward violet-umber, no anti-aliasing against the transparent edge, dithering only on "
        "broad surfaces. Limited palette: %s.\n"
        "No text, no border.%s\n"
        "Animation: %s, %d frames at %s fps: %s."
        % (e.get("desc", sid), fw, fh, n, rows_txt, figure_height(e), e["pivot"][1], e["pivot"][0],
           " ".join("#" + c for c in cols), no_weapon, an, n, a.get("fps", 10), beat(an, a, e)))


def anim_status(a):
    if os.path.exists(os.path.join(ac.ASSETS, a["file"])):
        return "done"
    if os.path.exists(os.path.join(ac.PLACEHOLDERS, a["file"])):
        return "placeholder"
    return "missing"


BOX = {"done": "[x]", "placeholder": "[~]", "partial": "[~]", "missing": "[ ]"}


def main():
    manifest = ac.load_manifest()
    entries = []
    for sid in manifest["sprites"]:
        e = ac.resolved_entry(manifest, sid)
        st = [anim_status(a) for a in e["anims"].values()]
        s = "done" if all(x == "done" for x in st) else ("partial" if "done" in st else (
            "placeholder" if "placeholder" in st else "missing"))
        entries.append((PHASE_ORDER.index(e.get("phase", "V6")) if e.get("phase", "V6") in PHASE_ORDER else 9,
                        int(e.get("priority", 99)), CAT_ORDER.get(e.get("category"), 9), int(e.get("tier", 0)), sid, e, s))
    entries.sort()
    total = {"done": 0, "placeholder": 0, "partial": 0, "missing": 0}
    sheets = {"done": 0, "placeholder": 0, "missing": 0}
    for *_, e, s in entries:
        total[s] += 1
        for a in e["anims"].values():
            sheets[anim_status(a)] += 1
    L = []
    L.append("# Path of Dan: art asset list")
    L.append("")
    L.append("Generated by `python tools/make_asset_list.py` from `data/art/sprites.json` on %s. "
             "Don't edit by hand: change the manifest and re-run." % datetime.date.today().isoformat())
    L.append("")
    L.append("Status: `[x]` done (real art for every animation), `[~]` placeholder or partial, `[ ]` missing. "
             "Rules for sizes, palette and hand-over are in [ART_STYLE_GUIDE.md](ART_STYLE_GUIDE.md).")
    L.append("")
    L.append("| | Entries | Sheets (one PNG per animation) |")
    L.append("|---|---|---|")
    L.append("| Done | %d | %d |" % (total["done"], sheets["done"]))
    L.append("| Placeholder / partial | %d | %d |" % (total["placeholder"] + total["partial"], sheets["placeholder"]))
    L.append("| Missing | %d | %d |" % (total["missing"], sheets["missing"]))
    L.append("")
    L.append("**Start here (first vertical slice):** `warrior` (idle, run, attack, hit, death), then `ghoul`. "
             "Hand-over: save as `assets/incoming/<id>_<anim>.png` (e.g. `warrior_run.png`) and run "
             "`python tools/art_ingest.py`.")
    L.append("")
    phase = None
    for ph_i, _, _, _, sid, e, s in entries:
        ph = e.get("phase", "V6")
        if ph != phase:
            phase = ph
            L.append("## " + PHASE_NAME.get(ph, ph))
            L.append("")
        fw, fh = e["frame"]
        rows = ac.DIR_ROWS[(int(e["directions"]), bool(e["mirror"]))]
        names, cols = ramps_for(e)
        tier = (", tier %d" % e["tier"]) if e.get("tier") else ""
        L.append("### %s `%s` (%s%s)" % (BOX[s], sid, e.get("category", ""), tier))
        L.append("")
        L.append("- **Frame** %dx%d px, figure %s, pivot (feet) %s. **Directions** %d: rows %s%s."
                 % (fw, fh, figure_height(e), e["pivot"], int(e["directions"]), ", ".join(rows),
                    " (SW, W, NW are mirrored)" if e["mirror"] and int(e["directions"]) == 8 else
                    (" (W is mirrored)" if e["mirror"] and int(e["directions"]) == 4 else "")))
        L.append("- **Look:** %s." % e.get("desc", ""))
        if e.get("notes"):
            L.append("- **Gameplay notes:** %s" % e["notes"])
        L.append("- **Palette:** %s." % ", ".join(names))
        L.append("- **Old sprite (fallback):** `%s`." % e.get("fallback", ""))
        L.append("")
        L.append("| Anim | Status | Frames | fps | Loop | Sync / impact | Sheet size | File |")
        L.append("|---|---|---|---|---|---|---|---|")
        for an, a in e["anims"].items():
            n = int(a.get("frames", 1))
            sync = (("%s, impact frame %d" % (a["sync"], int(a["impact_frame"]))) if "impact_frame" in a else a["sync"]) if a.get("sync") else (
                "corpse frame %d" % int(a["corpse_frame"]) if "corpse_frame" in a else "")
            L.append("| %s | %s %s | %d | %s | %s | %s | %dx%d | `assets/%s` |" % (
                an, BOX[anim_status(a)], anim_status(a), n, a.get("fps", 10), "yes" if a.get("loop") else "",
                sync, fw * n, fh * len(rows), a["file"]))
        L.append("")
        L.append("<details><summary>Generation prompts for %s</summary>" % sid)
        L.append("")
        for an, a in e["anims"].items():
            L.append("**%s_%s.png**" % (sid, an))
            L.append("")
            L.append("```")
            L.append(prompt(sid, an, a, e, cols))
            L.append("```")
            L.append("")
        L.append("</details>")
        L.append("")
    L.append("## Later phases (not in the sprite manifest yet)")
    L.append("")
    L.append("These get manifest entries and prompts in their own phase:")
    L.append("")
    L.append("- **V1:** weapon layer for every weapon family in `data/item_bases.json` (sword, dagger, axe, mace, "
             "greatsword, greataxe, hammer, spear, shield, tower shield, bow, longbow, crossbow, pistol, rifle, "
             "wand, staff, orb, book).")
    L.append("- **V2:** crypt and hub tile kits (floor, wall top, wall front, outer corner, inner corner, doorway, "
             "pillar, rubble, candle cluster, brazier, chest, door), NPCs.")
    L.append("- **V3:** turrets, mines and traps, elite affix markers, status overlays.")
    L.append("- **V4:** flipbook VFX per damage type and skill behaviour, loot beams.")
    L.append("- **V5:** 32x32 item, legendary, skill and rune icons; UI frames (coordinated with the HUD work).")
    L.append("- **V6:** tiers 2-6 tile kits and props, 16 pets.")
    L.append("")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(L))
    print("Wrote %s: %d entries (%d done, %d placeholder/partial, %d missing)."
          % (os.path.relpath(OUT, ac.ROOT), len(entries), total["done"], total["placeholder"] + total["partial"], total["missing"]))


if __name__ == "__main__":
    main()
