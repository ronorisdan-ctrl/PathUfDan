"""Shared helpers for the art pipeline tools (art_ingest, validate_art,
make_placeholder_sheets, make_asset_list).

Requires Pillow:  pip install pillow
All paths are relative to the project root (the folder with project.godot).
"""
import json
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ASSETS = os.path.join(ROOT, "assets")
PLACEHOLDERS = os.path.join(ASSETS, "placeholders")
MANIFEST = os.path.join(ROOT, "data", "art", "sprites.json")
RENDER = os.path.join(ROOT, "data", "render.json")
PALETTE = os.path.join(ASSETS, "palette", "dying_canvas.hex")

# Pigment ramps from the Art Bible (dark -> light). Used for prompts and the style guide.
RAMPS = {
    "Bone black - umber": ["0c0a0d", "1a1416", "2a2020", "3d2e28", "544036"],
    "Burnt sienna": ["3a1f16", "5c2f1e", "83442a", "a8623c", "c98a5a"],
    "Yellow ochre": ["4a3a1e", "6e5628", "9a7a3a", "c4a25a", "e0c890"],
    "Verdigris": ["1c2a26", "2c403a", "3f5a50", "5c7a6c", "8aa08e"],
    "Lead white (aged)": ["6e665a", "968c7a", "bdb29a", "ddd2b8", "f0e8d4"],
    "Blood madder": ["2e0e10", "4e1418", "741c1e", "9a2a26", "c04a3a"],
    "Slate": ["1a1c22", "2a2e36", "3e434e", "5a6070", "80879a"],
}
ACCENTS = {
    "6a9ad0": "Smalt blue (uncommon)", "e8c860": "Naples yellow (rare)",
    "a868d0": "Tyrian violet (epic)", "f08038": "Cinnabar vermilion (legendary)",
    "3f8a90": "Spectral turquoise (mana)", "e0482a": "Vermilion (fire)",
    "5aa8c8": "Cerulean (ice)", "f4e890": "Naples yellow-white (lightning)",
    "6a5ad8": "Ultramarine violet (arcane)", "7aa040": "Verdigris green (poison)",
    "d8ccb0": "Raw canvas (void)", "2a2660": "Deep ultramarine", "6a6e50": "Verdaccio",
}

DIR_ROWS = {
    (8, True): ["S", "SE", "E", "NE", "N"],
    (8, False): ["S", "SE", "E", "NE", "N", "NW", "W", "SW"],
    (4, True): ["S", "E", "N"],
    (4, False): ["S", "E", "N", "W"],
    (2, True): ["E"],
    (2, False): ["E", "W"],
    (1, True): ["one view"],
    (1, False): ["one view"],
}


def need_pillow():
    try:
        import PIL  # noqa: F401
    except ImportError:
        sys.exit("These tools need Pillow. Install it with:  pip install pillow")


def load_json(path, default=None):
    if not os.path.exists(path):
        return default
    with open(path, encoding="utf-8-sig") as f:
        return json.load(f)


def save_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")


def load_palette(path=PALETTE):
    cols = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip().lstrip("#")
            if len(line) == 6:
                cols.append(tuple(int(line[i:i + 2], 16) for i in (0, 2, 4)))
    return cols


def load_manifest():
    return load_json(MANIFEST, {"defaults": {}, "sprites": {}})


def resolved_entry(manifest, sid):
    """Entry with defaults filled in (same rules as Art.sprite_def in GDScript)."""
    d = dict(manifest.get("defaults", {}))
    e = manifest["sprites"][sid]
    out = dict(d)
    out.update({k: v for k, v in e.items() if k != "anims"})
    anims = {}
    for name, a in e.get("anims", {}).items():
        aa = {"fps": out.get("fps", 10), "loop": False}
        aa.update(a)
        if "file" not in aa:
            aa["file"] = "sprites/%s/%s/%s_%s.png" % (out.get("category", "misc"), sid, sid, name)
        anims[name] = aa
    out["anims"] = anims
    out.setdefault("frame", [64, 64])
    out.setdefault("pivot", [out["frame"][0] // 2, out["frame"][1] - 6])
    out.setdefault("directions", 8)
    out.setdefault("mirror", True)
    return out


def rows_needed(directions, mirror):
    return len(DIR_ROWS.get((directions, bool(mirror)), ["x"]))


def nearest(col, palette):
    r, g, b = col
    best, bd = palette[0], 1 << 30
    for p in palette:
        d = (r - p[0]) ** 2 + (g - p[1]) ** 2 + (b - p[2]) ** 2
        if d < bd:
            best, bd = p, d
    return best
