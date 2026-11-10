"""Draw the images used by docs/ART_STYLE_GUIDE.md:
  docs/img/palette.png     the master palette as labelled swatches, ramp by ramp
  docs/img/size_chart.png  tile, hero, small enemy, item drop and boss canvases to scale

    python tools/make_style_images.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import art_common as ac  # noqa: E402

OUT = os.path.join(ac.ROOT, "docs", "img")


def hexcol(h):
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def palette_png():
    from PIL import Image, ImageDraw
    sw, pad = 40, 6
    rows = list(ac.RAMPS.items()) + [("Accents", list(ac.ACCENTS.keys()))]
    width = 170 + max(len(c) for _, c in rows) * (sw + pad)
    im = Image.new("RGB", (width, len(rows) * (sw + 18) + 10), hexcol("1a1416"))
    d = ImageDraw.Draw(im)
    y = 8
    for name, cols in rows:
        d.text((8, y + sw // 2 - 5), name, fill=hexcol("ddd2b8"))
        x = 170
        for c in cols:
            d.rectangle([x, y, x + sw - 1, y + sw - 1], fill=hexcol(c))
            d.text((x, y + sw + 2), c, fill=hexcol("968c7a"))
            x += sw + pad
        y += sw + 18
    im.save(os.path.join(OUT, "palette.png"))


def size_chart_png():
    from PIL import Image, ImageDraw
    k = 3   # each art pixel drawn as 3x3
    items = [("floor tile 32x32", 32, 32, 32, "5c7a6c"), ("hero / humanoid 64x64\nfigure 44-50 px, feet y=58", 64, 64, 48, "9a2a26"),
             ("small enemy 32x32\nfigure 20-30 px", 32, 32, 26, "3f5a50"), ("item drop 16x16", 16, 16, 14, "e8c860"),
             ("boss 128x128\n(80-160 px)", 128, 128, 112, "6a5ad8")]
    W = sum(w * k + 30 for _, w, _, _, _ in items) + 20
    H = 128 * k + 70
    im = Image.new("RGB", (W, H), hexcol("1a1416"))
    d = ImageDraw.Draw(im)
    base = 128 * k + 20
    x = 20
    for label, w, h, fig, col in items:
        top = base - h * k
        d.rectangle([x, top, x + w * k - 1, base - 1], outline=hexcol("544036"))
        if label.startswith("floor"):
            d.rectangle([x + 1, top + 1, x + w * k - 2, base - 2], fill=hexcol("2a2020"))
        else:
            feet = base - (6 if h >= 64 else 4) * k if h > 16 else base - 1 * k
            fw = max(4, int(fig * 0.42)) * k
            d.rectangle([x + (w * k - fw) // 2, feet - fig * k, x + (w * k + fw) // 2, feet], fill=hexcol(col))
            d.line([x, feet, x + w * k, feet], fill=hexcol("e0c890"))
        d.multiline_text((x, base + 6), label, fill=hexcol("ddd2b8"))
        x += w * k + 30
    d.text((20, 4), "To scale: 1 art pixel = 1 screen pixel at 1280x720 (drawn 3x here). Ochre line = feet/pivot.",
           fill=hexcol("bdb29a"))
    im.save(os.path.join(OUT, "size_chart.png"))


if __name__ == "__main__":
    ac.need_pillow()
    os.makedirs(OUT, exist_ok=True)
    palette_png()
    size_chart_png()
    print("Wrote docs/img/palette.png and docs/img/size_chart.png")
