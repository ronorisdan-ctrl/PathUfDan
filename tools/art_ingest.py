"""Bring raw sprite sheets from assets/incoming/ into the project.

Name each file <id>_<anim>.png (e.g. warrior_run.png, ghoul_attack.png) and drop it in
assets/incoming/, then run:

    python tools/art_ingest.py                    # process everything in assets/incoming/
    python tools/art_ingest.py warrior_run.png    # one file
    python tools/art_ingest.py --dry-run          # report only, write nothing

What it does, per file:
  1. Works out the sprite id and animation from the file name, and the frame size,
     frame count and direction rows from data/art/sprites.json.
  2. Removes a flat background colour if the image has no transparency (--key-bg).
  3. Downscales a sheet that was delivered at an exact whole multiple of the target
     size (2x, 3x, 4x ...) with nearest-neighbour sampling. Any other size is refused:
     the sheet must be frames x frame width by rows x frame height.
  4. Thresholds alpha to 0 or 255 (--alpha 128), removing stray semi-transparent pixels,
     and removes isolated single pixels (--keep-specks to skip).
  5. Optionally quantises to the master palette (--quantise) and reports pixels changed.
  6. Aligns frames on the feet line so the pivot is the same in every frame
     (--align frame | row | none; default: frame for idle/run/hit, row for the rest,
     which keeps intentional motion such as a leap).
  7. Writes assets/<file> from the manifest, adding the manifest entry/animation if
     needed (--category, --frames, --directions for new ids).
  8. Moves the raw file to assets/incoming/_done/.

It never overwrites existing art unless you pass --replace, and then it first copies the
old file to assets/_backup/<date-time>/.
"""
import argparse
import datetime
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(__file__))
import art_common as ac  # noqa: E402

INCOMING = os.path.join(ac.ASSETS, "incoming")
FRAME_ALIGN = ("idle", "run", "hit", "channel")


def split_name(fname, manifest):
    base = os.path.splitext(os.path.basename(fname))[0].lower().replace("-", "_").replace(" ", "_")
    ids = sorted(manifest["sprites"].keys(), key=len, reverse=True)
    for sid in ids:
        if base.startswith(sid + "_"):
            return sid, base[len(sid) + 1:]
    if "_" in base:
        i = base.rindex("_")
        return base[:i], base[i + 1:]
    return base, "idle"


def key_background(im, report):
    """If nothing is transparent, treat the top-left corner colour as background."""
    px = im.load()
    w, h = im.size
    alphas = set(px[x, y][3] for x, y in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)))
    if alphas != {255}:
        return im
    bg = px[0, 0][:3]
    n = 0
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if abs(r - bg[0]) + abs(g - bg[1]) + abs(b - bg[2]) <= 24:
                px[x, y] = (0, 0, 0, 0)
                n += 1
    report.append("background #%02x%02x%02x removed (%d px)" % (bg + (n,)))
    return im


def fit_size(im, want_w, want_h, report):
    from PIL import Image
    w, h = im.size
    if (w, h) == (want_w, want_h):
        return im
    if w % want_w == 0 and h % want_h == 0 and w // want_w == h // want_h:
        k = w // want_w
        out = Image.new("RGBA", (want_w, want_h))
        src, dst = im.load(), out.load()
        for y in range(want_h):
            for x in range(want_w):
                dst[x, y] = src[x * k + k // 2, y * k + k // 2]
        report.append("downscaled %dx from %dx%d" % (k, w, h))
        return out
    raise ValueError("sheet is %dx%d; expected %dx%d (or an exact multiple)" % (w, h, want_w, want_h))


def threshold_alpha(im, cut, report):
    px = im.load()
    n = 0
    for y in range(im.size[1]):
        for x in range(im.size[0]):
            r, g, b, a = px[x, y]
            if 0 < a < 255:
                px[x, y] = (r, g, b, 255) if a >= cut else (0, 0, 0, 0)
                n += 1
            elif a == 0 and (r or g or b):
                px[x, y] = (0, 0, 0, 0)
    if n:
        report.append("%d semi-transparent pixels snapped" % n)


def despeckle(im, report):
    """Remove isolated opaque pixels (no opaque neighbour in 8 directions): AI-tool dust."""
    px = im.load()
    w, h = im.size
    kill = []
    for y in range(h):
        for x in range(w):
            if px[x, y][3] == 0:
                continue
            alone = True
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    if (dx or dy) and 0 <= x + dx < w and 0 <= y + dy < h and px[x + dx, y + dy][3]:
                        alone = False
                        break
                if not alone:
                    break
            if alone:
                kill.append((x, y))
    for x, y in kill:
        px[x, y] = (0, 0, 0, 0)
    if kill:
        report.append("%d stray single pixels removed" % len(kill))


def quantise(im, palette, report):
    px = im.load()
    pal = set(palette)
    cache = {}
    n = 0
    for y in range(im.size[1]):
        for x in range(im.size[0]):
            r, g, b, a = px[x, y]
            if a == 0 or (r, g, b) in pal:
                continue
            c = cache.get((r, g, b))
            if c is None:
                c = cache[(r, g, b)] = ac.nearest((r, g, b), palette)
            px[x, y] = c + (255,)
            n += 1
    report.append("quantised: %d pixels changed (%d colours mapped)" % (n, len(cache)))


def feet_anchor(frame):
    """(centre x, bottom y) of the lowest opaque rows of a frame, or None if empty."""
    box = frame.getbbox()
    if box is None:
        return None
    px = frame.load()
    bottom = box[3] - 1
    xs = [x for y in range(max(box[1], bottom - 2), bottom + 1) for x in range(box[0], box[2]) if px[x, y][3]]
    return (sum(xs) / len(xs) if xs else (box[0] + box[2]) / 2.0, bottom)


def align(im, e, a, mode, rows, report):
    from PIL import Image
    if mode == "none":
        return im
    fw, fh = e["frame"]
    pvx, pvy = e["pivot"]
    n = int(a.get("frames", 1))
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    moved = 0
    for r in range(rows):
        row_off = None
        for f in range(n):
            box = (f * fw, r * fh, (f + 1) * fw, (r + 1) * fh)
            fr = im.crop(box)
            if mode == "row":
                if row_off is None:
                    anc = feet_anchor(fr)
                    row_off = (0, 0) if anc is None else (int(round(pvx - anc[0])), pvy - anc[1])
                dx, dy = row_off
            else:
                anc = feet_anchor(fr)
                dx, dy = (0, 0) if anc is None else (int(round(pvx - anc[0])), pvy - anc[1])
            if dx or dy:
                moved += 1
            shifted = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
            shifted.paste(fr, (dx, dy), fr)
            out.paste(shifted, box[:2])
    report.append("aligned to pivot %s (%s mode, %d frames moved)" % (e["pivot"], mode, moved))
    return out


def ingest(path, args, manifest, palette):
    from PIL import Image
    report = []
    sid, an = split_name(path, manifest)
    if sid not in manifest["sprites"]:
        if not args.category:
            raise ValueError("'%s' is not in data/art/sprites.json; pass --category (classes, monsters, "
                             "bosses, minions, npcs, pets, props) to add it" % sid)
        manifest["sprites"][sid] = {"category": args.category, "fallback": args.fallback or "ghoul", "anims": {}}
        if args.directions:
            manifest["sprites"][sid]["directions"] = args.directions
        report.append("new manifest entry '%s'" % sid)
    entry = manifest["sprites"][sid]
    if an not in entry.setdefault("anims", {}):
        if not args.frames:
            raise ValueError("%s has no '%s' animation in the manifest; pass --frames N to add it" % (sid, an))
        entry["anims"][an] = {"frames": args.frames}
        if an in ("idle", "run", "channel"):
            entry["anims"][an]["loop"] = True
        report.append("new animation '%s' (%d frames)" % (an, args.frames))
    e = ac.resolved_entry(manifest, sid)
    a = e["anims"][an]
    rows = ac.rows_needed(int(e["directions"]), bool(e["mirror"]))
    fw, fh = e["frame"]
    want = (fw * int(a["frames"]), fh * rows)
    im = Image.open(path).convert("RGBA")
    if args.key_bg:
        im = key_background(im, report)
    im = fit_size(im, want[0], want[1], report)
    threshold_alpha(im, args.alpha, report)
    if not args.keep_specks:
        despeckle(im, report)
    if args.quantise:
        quantise(im, palette, report)
    mode = args.align or ("frame" if an in FRAME_ALIGN else "row")
    im = align(im, e, a, mode, rows, report)
    dest = os.path.join(ac.ASSETS, a["file"])
    if os.path.exists(dest) and not args.replace:
        raise ValueError("%s already exists; pass --replace to overwrite (a backup is kept)" % os.path.relpath(dest, ac.ROOT))
    if not args.dry_run:
        if os.path.exists(dest):
            stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
            bak = os.path.join(ac.ASSETS, "_backup", stamp, a["file"])
            os.makedirs(os.path.dirname(bak), exist_ok=True)
            shutil.copy2(dest, bak)
            report.append("old file backed up to " + os.path.relpath(bak, ac.ROOT))
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        im.save(dest)
        if os.path.dirname(os.path.abspath(path)) == os.path.abspath(INCOMING):
            done = os.path.join(INCOMING, "_done")
            os.makedirs(done, exist_ok=True)
            shutil.move(path, os.path.join(done, os.path.basename(path)))
    report.insert(0, "%s -> %s  [%s / %s, %d frames x %d rows of %dx%d]" % (
        os.path.basename(path), os.path.relpath(dest, ac.ROOT), sid, an, int(a["frames"]), rows, fw, fh))
    return report


def main(argv):
    ac.need_pillow()
    p = argparse.ArgumentParser(description="Ingest raw sprite sheets from assets/incoming/.")
    p.add_argument("files", nargs="*")
    p.add_argument("--replace", action="store_true", help="overwrite existing art (keeps a backup)")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--quantise", "--quantize", action="store_true", help="snap colours to the master palette")
    p.add_argument("--alpha", type=int, default=128, help="alpha threshold (default 128)")
    p.add_argument("--align", choices=["frame", "row", "none"])
    p.add_argument("--key-bg", action="store_true", help="remove a flat background colour")
    p.add_argument("--keep-specks", action="store_true", help="don't remove isolated single pixels")
    p.add_argument("--category")
    p.add_argument("--fallback")
    p.add_argument("--frames", type=int)
    p.add_argument("--directions", type=int, choices=[1, 2, 4, 8])
    args = p.parse_args(argv)
    manifest = ac.load_manifest()
    palette = ac.load_palette()
    files = args.files or sorted(os.path.join(INCOMING, f) for f in os.listdir(INCOMING)
                                 if f.lower().endswith(".png")) if os.path.isdir(INCOMING) else args.files
    files = [f if os.path.exists(f) else os.path.join(INCOMING, f) for f in files]
    if not files:
        print("Nothing to do: put PNGs named <id>_<anim>.png in assets/incoming/.")
        return 0
    ok = bad = 0
    for f in files:
        try:
            for i, line in enumerate(ingest(f, args, manifest, palette)):
                print(("OK   " if i == 0 else "       ") + line)
            ok += 1
        except Exception as ex:  # report and carry on with the next file
            print("SKIP %s: %s" % (os.path.basename(f), ex))
            bad += 1
    if ok and not args.dry_run:
        ac.save_json(ac.MANIFEST, manifest)
    print("\n%d ingested, %d skipped%s. Next: open Godot (imports the PNGs), then run "
          "python tools/validate_art.py and tests/art_gallery.tscn." % (ok, bad, " (dry run)" if args.dry_run else ""))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
