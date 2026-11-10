"""Generate labelled placeholder sprite sheets for manifest entries, so animation timing,
direction picking and the gallery can be built and tested before real art exists.

    python tools/make_placeholder_sheets.py warrior ghoul      # chosen ids
    python tools/make_placeholder_sheets.py --all              # every manifest entry
    python tools/make_placeholder_sheets.py --v0               # the Phase V0 set

Sheets go to assets/placeholders/<file> (never to the real art path), one PNG per
animation: rows = directions, columns = frames. Each frame shows a silhouette, an arrow
for the direction, the frame number and the animation initial. The impact frame of synced
animations has an ochre border. Placeholders are only used in game when
data/render.json "placeholders_in_game" is true (or with --art-placeholders).
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import art_common as ac  # noqa: E402

V0_SET = ["warrior", "ranger", "mage", "ghoul"]
CAT_COL = {"classes": (0x9a, 0x2a, 0x26), "monsters": (0x5c, 0x7a, 0x6c), "bosses": (0x6a, 0x5a, 0xd8),
           "minions": (0x96, 0x8c, 0x7a)}
DIR_VEC = {"S": (0, 1), "SE": (1, 1), "E": (1, 0), "NE": (1, -1), "N": (0, -1), "NW": (-1, -1),
           "W": (-1, 0), "SW": (-1, 1), "one view": (1, 0)}
OUTLINE = (0x0c, 0x0a, 0x0d, 255)
OCHRE = (0xe0, 0xc8, 0x90, 255)
WHITE = (0xf0, 0xe8, 0xd4, 255)


def draw_frame(img, ox, oy, e, anim_name, a, fi, dname, col):
    from PIL import ImageDraw
    d = ImageDraw.Draw(img)
    fw, fh = e["frame"]
    px, py = e["pivot"]
    n = int(a.get("frames", 1))
    t = fi / max(1, n - 1) if n > 1 else 0.0
    h = max(8, int(py * 0.78))          # figure height in px
    w = max(5, int(h * 0.45))
    bob = 0
    lean = 0
    sink = 0
    c = col
    if anim_name == "idle":
        bob = -1 if fi % 2 else 0
    elif anim_name == "run":
        bob = -2 if fi % 2 else 0
        lean = 2
    elif anim_name in ("attack", "cast", "special"):
        imp = int(a.get("impact_frame", 0))
        lean = -2 if fi < imp else 3
    elif anim_name == "hit":
        c = (0xdd, 0xd2, 0xb8)
        lean = -2
    elif anim_name == "death":
        sink = int(h * 0.7 * t)
    elif anim_name == "dodge":
        sink = int(h * 0.4 * math.sin(t * math.pi))
    elif anim_name in ("stagger", "phase_change"):
        c = (0xe8, 0xc8, 0x60) if fi % 2 else col
    vx, vy = DIR_VEC.get(dname, (1, 0))
    cx = ox + px + int(lean * vx)
    feet = oy + py + int(lean * vy * 0.5)
    top = feet - h + sink + bob
    # shadow-side outline + body
    body = [cx - w // 2, top + h // 4, cx + w // 2, feet]
    d.rectangle(body, fill=c + (255,), outline=OUTLINE)
    hr = max(2, w // 2)
    d.ellipse([cx - hr, top, cx + hr, top + 2 * hr], fill=c + (255,), outline=OUTLINE)
    # direction arrow from the chest
    ax, ay = cx, top + h // 2
    L = max(4, fw // 5)
    nx, ny = (vx, vy)
    m = math.hypot(nx, ny) or 1
    ex, ey = ax + int(L * nx / m), ay + int(L * ny / m * 0.7)
    d.line([ax, ay, ex, ey], fill=WHITE, width=1)
    d.rectangle([ex - 1, ey - 1, ex + 1, ey + 1], fill=WHITE)
    if anim_name in ("attack", "cast", "special"):
        # the 'arm': pulled back before the impact frame, thrust out from it
        imp = int(a.get("impact_frame", 0))
        reach = (-0.5 if fi < imp else 1.6) * L
        sx, sy = cx + (w // 2) * (1 if vx >= 0 else -1), top + h // 3
        d.line([sx, sy, sx + int(reach * nx / m), sy + int(reach * ny / m * 0.7)], fill=OCHRE, width=2)
    # labels: frame number top-left, anim initial top-right
    d.text((ox + 1, oy), str(fi), fill=WHITE)
    if fw >= 48:
        d.text((ox + fw - 8, oy), anim_name[:1].upper(), fill=OCHRE)
    if a.get("sync") and fi == int(a.get("impact_frame", -1)):
        d.rectangle([ox, oy, ox + fw - 1, oy + fh - 1], outline=OCHRE)
    if anim_name == "death" and fi == int(a.get("corpse_frame", n - 1)):
        d.line([ox + 2, oy + fh - 2, ox + fw - 3, oy + fh - 2], fill=OCHRE)


def make(sid, manifest, quiet=False):
    from PIL import Image
    e = ac.resolved_entry(manifest, sid)
    rows = ac.DIR_ROWS.get((int(e["directions"]), bool(e["mirror"])), ["one view"])
    col = CAT_COL.get(e.get("category", ""), (0x83, 0x44, 0x2a))
    fw, fh = e["frame"]
    written = []
    for an, a in e["anims"].items():
        n = int(a.get("frames", 1))
        img = Image.new("RGBA", (fw * n, fh * len(rows)), (0, 0, 0, 0))
        for r, dname in enumerate(rows):
            for fi in range(n):
                draw_frame(img, fi * fw, r * fh, e, an, a, fi, dname, col)
        # hard alpha only (the text is drawn anti-aliased)
        img.putalpha(img.getchannel("A").point(lambda v: 255 if v >= 128 else 0))
        out = os.path.join(ac.PLACEHOLDERS, a["file"])
        os.makedirs(os.path.dirname(out), exist_ok=True)
        img.save(out)
        written.append(os.path.relpath(out, ac.ROOT))
    if not quiet:
        print("%-18s %d sheets  (%dx%d, %d rows)" % (sid, len(written), fw, fh, len(rows)))
    return written


def main(argv):
    ac.need_pillow()
    manifest = ac.load_manifest()
    ids = [x for x in argv if not x.startswith("--")]
    if "--all" in argv:
        ids = list(manifest["sprites"].keys())
    elif "--v0" in argv or not ids:
        ids = ids or V0_SET
    bad = [i for i in ids if i not in manifest["sprites"]]
    if bad:
        sys.exit("Not in data/art/sprites.json: " + ", ".join(bad))
    total = 0
    for sid in ids:
        total += len(make(sid, manifest))
    print("Wrote %d placeholder sheets under assets/placeholders/." % total)
    print("Open Godot once so it imports them, then run tests/art_gallery.tscn.")


if __name__ == "__main__":
    main(sys.argv[1:])
