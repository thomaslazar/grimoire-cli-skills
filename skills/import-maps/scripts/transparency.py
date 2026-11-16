#!/usr/bin/env python3
"""Find map images with a transparent background, and optionally build opaque copies.

Grimoire's viewer is dark, so dark line art on transparency shows as
almost nothing. Report, per image: how much of it is transparent and how dark the visible
pixels are. With --flatten DIR, write a copy of each flagged image composited onto
--color into DIR (same filename). Sources are only read.

  python3 transparency.py FILE_OR_DIR... [--min-share 0.05] [--flatten DIR] [--color F2E8D5]
  python3 transparency.py --self-test
"""
import argparse, json, os, sys, tempfile
try:
    from PIL import Image, ImageStat
except ImportError:
    sys.exit("Pillow is required: python3 -m pip install Pillow")

Image.MAX_IMAGE_PIXELS = None
EXT = (".png", ".webp", ".gif", ".tif", ".tiff")


def measure(path, sample=512):
    im = Image.open(path)
    if "A" not in im.getbands() and "transparency" not in im.info:
        return {"transparent_share": 0.0, "visible_luma": None}
    im = im.convert("RGBA")
    im.thumbnail((sample, sample))  # ponytail: sampled at 512 px, enough to judge a background
    mask = im.getchannel("A").point(lambda v: 255 if v >= 128 else 0)
    total, vis = im.width * im.height, mask.histogram()[255]
    luma = ImageStat.Stat(im.convert("L"), mask).mean[0] if vis else None
    return {"transparent_share": round(1 - vis / total, 3), "visible_luma": None if luma is None else round(luma)}


def flatten(src, dst, color):
    im = Image.open(src).convert("RGBA")
    bg = Image.new("RGBA", im.size, tuple(int(color[i:i + 2], 16) for i in (0, 2, 4)) + (255,))
    bg.alpha_composite(im)
    bg.convert("RGB").save(dst, optimize=True)


def files(paths):
    for p in paths:
        if os.path.isdir(p):
            for d, _, fs in os.walk(p):
                yield from (os.path.join(d, f) for f in sorted(fs) if f.lower().endswith(EXT) and not f.startswith("."))
        elif p.lower().endswith(EXT):
            yield p


def main(argv):
    a = argparse.ArgumentParser()
    a.add_argument("paths", nargs="*")
    a.add_argument("--min-share", type=float, default=0.05)
    a.add_argument("--flatten")
    a.add_argument("--color", default="F2E8D5")
    a.add_argument("--self-test", action="store_true")
    o = a.parse_args(argv)
    if o.self_test:
        return self_test()
    out = []
    for f in files(o.paths):
        m = measure(f)
        if m["transparent_share"] < o.min_share:
            continue
        m["path"] = f
        if o.flatten:
            os.makedirs(o.flatten, exist_ok=True)
            m["flattened"] = os.path.join(o.flatten, os.path.basename(f))
            flatten(f, m["flattened"], o.color)
        out.append(m)
    print(json.dumps(out, ensure_ascii=False, indent=1))
    return 0


def self_test():
    with tempfile.TemporaryDirectory() as d:
        t = os.path.join(d, "lineart.png"); Image.new("RGBA", (40, 40), (0, 0, 0, 0)).save(t)
        im = Image.open(t); im.paste((0, 0, 0, 255), (0, 0, 40, 4)); im.save(t)  # 10 % black line, rest clear
        Image.new("RGB", (40, 40), "white").save(os.path.join(d, "opaque.png"))
        m = measure(t)
        assert m["transparent_share"] == 0.9 and m["visible_luma"] == 0, m
        assert measure(os.path.join(d, "opaque.png"))["transparent_share"] == 0.0
        flatten(t, os.path.join(d, "flat.png"), "F2E8D5")
        f = Image.open(os.path.join(d, "flat.png"))
        assert f.mode == "RGB" and f.getpixel((20, 20)) == (242, 232, 213) and f.getpixel((0, 0)) == (0, 0, 0)
    print("self-test ok")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
