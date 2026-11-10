"""Check every sprite-sheet manifest entry (data/art/sprites.json) against the files.

    python tools/validate_art.py               # report
    python tools/validate_art.py --quiet       # only problems and the summary line
    python tools/validate_art.py --strict      # palette warnings count as errors

ERRORS (exit code 1):
  - an entry is malformed (frames, pivot, directions, impact/corpse frame out of range)
  - a sheet exists but its size isn't frames x frame width by rows x frame height
  - semi-transparent pixels (alpha other than 0 or 255) in a character sheet
  - a sprite id used in data/*.json has neither sheet art nor an old Art.sprite fallback
WARNINGS:
  - colours outside the master palette (assets/palette/dying_canvas.hex)
  - content touching the frame edge, or feet far from the pivot line
  - an entry with no real art yet (listed as missing / placeholder)
"""
import glob
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
import art_common as ac  # noqa: E402


def art_sprite_ids():
    """Sprite ids defined in scripts/gfx/art.gd (the old ASCII art = fallbacks)."""
    src = open(os.path.join(ac.ROOT, "scripts", "gfx", "art.gd"), encoding="utf-8").read()
    start = src.index("const SPRITES := {")
    end = src.index("const ICONS := {")
    return set(re.findall(r'^\t"([a-z0-9_]+)": \[', src[start:end], re.M))


def data_sprite_ids():
    used = {}
    for path in glob.glob(os.path.join(ac.ROOT, "data", "*.json")):
        try:
            data = ac.load_json(path)
        except Exception:
            continue

        def walk(v):
            if isinstance(v, dict):
                if isinstance(v.get("sprite"), str):
                    used.setdefault(v["sprite"], os.path.basename(path))
                for x in v.values():
                    walk(x)
            elif isinstance(v, list):
                for x in v:
                    walk(x)
        walk(data)
    return used


def check_sheet(path, e, a, rows, palette, errors, warnings, sid, an):
    from PIL import Image
    im = Image.open(path).convert("RGBA")
    fw, fh = e["frame"]
    n = int(a.get("frames", 1))
    if im.size != (fw * n, fh * rows):
        errors.append("%s/%s: sheet is %dx%d, expected %dx%d (%d frames x %d rows of %dx%d)"
                      % (sid, an, im.size[0], im.size[1], fw * n, fh * rows, n, rows, fw, fh))
        return
    px = im.load()
    semi = 0
    off = {}
    pal = set(palette)
    for y in range(im.size[1]):
        for x in range(im.size[0]):
            r, g, b, al = px[x, y]
            if al == 0:
                continue
            if al != 255:
                semi += 1
            if (r, g, b) not in pal:
                off[(r, g, b)] = off.get((r, g, b), 0) + 1
    if semi:
        errors.append("%s/%s: %d semi-transparent pixels (run art_ingest.py to clean)" % (sid, an, semi))
    if off:
        warnings.append("%s/%s: %d pixels in %d colours outside the palette" % (sid, an, sum(off.values()), len(off)))
    # feet line and edges per frame
    pvx, pvy = e["pivot"]
    for r in range(rows):
        for f in range(n):
            box = im.crop((f * fw, r * fh, (f + 1) * fw, (r + 1) * fh)).getbbox()
            if box is None:
                warnings.append("%s/%s: frame %d row %d is empty" % (sid, an, f, r))
                continue
            if an not in ("death",) and abs(box[3] - 1 - pvy) > 3:
                warnings.append("%s/%s: frame %d row %d: feet at y=%d, pivot y=%d" % (sid, an, f, r, box[3] - 1, pvy))
                return
            if box[0] == 0 or box[1] == 0 or box[2] == fw or box[3] == fh:
                warnings.append("%s/%s: frame %d row %d touches the frame edge" % (sid, an, f, r))
                return


def main(argv):
    ac.need_pillow()
    quiet = "--quiet" in argv
    strict = "--strict" in argv
    manifest = ac.load_manifest()
    palette = ac.load_palette()
    errors, warnings, status = [], [], {}
    fallbacks = art_sprite_ids()
    for sid in manifest.get("sprites", {}):
        e = ac.resolved_entry(manifest, sid)
        fw, fh = e["frame"]
        pvx, pvy = e["pivot"]
        dirs, mirror = int(e["directions"]), bool(e["mirror"])
        if dirs not in (1, 2, 4, 8):
            errors.append("%s: directions must be 1, 2, 4 or 8" % sid)
        if not (0 <= pvx < fw and 0 <= pvy < fh):
            errors.append("%s: pivot %s outside the %dx%d frame" % (sid, e["pivot"], fw, fh))
        if e.get("fallback") not in fallbacks:
            errors.append("%s: fallback '%s' is not an Art.sprite id" % (sid, e.get("fallback")))
        if "idle" not in e["anims"]:
            errors.append("%s: no idle animation" % sid)
        rows = ac.rows_needed(dirs, mirror)
        real = ph = 0
        for an, a in e["anims"].items():
            n = int(a.get("frames", 0))
            if n < 1:
                errors.append("%s/%s: frames must be >= 1" % (sid, an))
                continue
            for k in ("impact_frame", "corpse_frame"):
                if k in a and not 0 <= int(a[k]) < n:
                    errors.append("%s/%s: %s %s out of range" % (sid, an, k, a[k]))
            path = os.path.join(ac.ASSETS, a["file"])
            ppath = os.path.join(ac.PLACEHOLDERS, a["file"])
            if os.path.exists(path):
                real += 1
                check_sheet(path, e, a, rows, palette, errors, warnings, sid, an)
            elif os.path.exists(ppath):
                ph += 1
                check_sheet(ppath, e, a, rows, palette, errors, [], sid, an)   # placeholders: size only
        total = len(e["anims"])
        status[sid] = "done" if real == total else ("partial" if real else ("placeholder" if ph else "missing"))
    used = data_sprite_ids()
    for sid, where in sorted(used.items()):
        if sid not in fallbacks and sid not in manifest.get("sprites", {}):
            errors.append("sprite id '%s' (%s) has no art and no fallback" % (sid, where))
    if not quiet:
        counts = {}
        for s in status.values():
            counts[s] = counts.get(s, 0) + 1
        print("Manifest: %d entries  (%s)" % (len(status), ", ".join("%s %d" % kv for kv in sorted(counts.items()))))
        for sid, s in sorted(status.items()):
            if s != "missing":
                print("  %-18s %s" % (sid, s))
    for w in warnings:
        print("WARNING", w)
    for e in errors:
        print("ERROR  ", e)
    bad = len(errors) + (len(warnings) if strict else 0)
    print("validate_art: %d errors, %d warnings" % (len(errors), len(warnings)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
