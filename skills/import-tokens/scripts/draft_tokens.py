#!/usr/bin/env python3
"""Sort a token pack into tokens and raw art, and draft clean names and creature tags.

usage: draft_tokens.py --pack DIR --target "<Pack>" [--rename "Old=New" ...] [--tags t1,t2] [--title "..."]
       draft_tokens.py --self-test

DIR is an extracted pack in the run dir (never the corpus). Each subfolder becomes a target folder
(brackets stripped: "[Kobold]" -> "Kobold"); loose files group by their cleaned name.

stdout: {"rows": [...import-maps plan rows...], "art": [paths], "unnamed": [targets]}
  - a token is a 256x256-ish square RGBA image whose corner is transparent (the frame's outside);
    anything else is raw art and goes to "art" for the walkthrough, never into rows
  - names: "_Token" and "Token" dropped, "_" -> " ", trailing number zero-padded ("Kobold_Token_3" -> "Kobold 03");
    a nameless file ("9.png", "token_7.png") takes its folder's name and lands in "unnamed"
  - numbering keeps the source number; a missing or clashing number gets the next free one;
    a name that occurs once and has no number stays bare ("Owlbear.png")
  - tags: the given --tags, then the slug of the name and of the folder ("Mimics/Chest Mimic 01" -> chest-mimic, mimics)
"""
import argparse, collections, json, os, re, sys

slug = lambda s: re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")


def is_token(path):
    try:
        from PIL import Image
    except ImportError:
        sys.exit("Pillow is required: python3 -m pip install Pillow")
    im = Image.open(path)
    w, h = im.size
    return (w == h and w <= 512 and im.mode == "RGBA"
            and im.getchannel("A").getpixel((2, 2)) == 0)


def split(stem, fallback):
    s = re.sub(r"(?i)[ _-]*\btoken\b[ _-]*", " ", stem.replace("_", " ")).strip(" -")
    m = re.fullmatch(r"(.*?)\s*(\d+)", s)
    name, n = (m.group(1).strip(), int(m.group(2))) if m else (s, None)
    return name or fallback, n, not name


def number(items):
    """items: [(name, n, key)] in one folder -> {key: filename stem}."""
    used, out = collections.defaultdict(set), {}
    many = collections.Counter(name for name, _, _ in items)
    for name, n, key in sorted(items, key=lambda x: (x[0], x[1] is None, x[1] or 0, x[2])):
        if n is None or n in used[name]:
            n = next(i for i in range(1, 1000) if i not in used[name])
        used[name].add(n)
        out[key] = f"{name} {n:02d}" if (many[name] > 1 or n > 1) else name
    return out


def draft(pack, target, renames, tags, title, token_test=is_token):
    groups, art, unnamed = collections.defaultdict(list), [], set()
    for r, _, fs in os.walk(pack):
        for f in sorted(fs):
            p = os.path.join(r, f)
            if f.startswith(".") or not f.lower().endswith((".png", ".webp")) or not token_test(p):
                art.append(p); continue
            folder = os.path.relpath(r, pack)
            folder = "" if folder == "." else "/".join(renames.get(x.strip("[]"), x.strip("[]")) for x in folder.split("/"))
            name, n, nameless = split(os.path.splitext(f)[0], os.path.basename(folder) or "Token")
            tf = folder or name
            groups[tf].append((name, n, p, folder, nameless))
    rows = []
    for tf, items in groups.items():
        names = number([(name, n, p) for name, n, p, *_ in items])
        for name, n, p, folder, nameless in items:
            t = f"{target}/{tf}/{names[p]}.png"
            if nameless: unnamed.add(t)
            rows.append({"source": os.path.abspath(p), "target": t, "variant": None,
                         "description": f"{names[p]}, a token from {title}." if title else "",
                         "tags": list(dict.fromkeys(tags + [slug(name)] + [slug(x) for x in folder.split("/") if x]))})
    rows.sort(key=lambda x: x["target"])
    dup = [k for k, v in collections.Counter(r["target"] for r in rows).items() if v > 1]
    if dup:
        sys.exit(f"duplicate targets: {dup[:5]}")
    return {"rows": rows, "art": sorted(art), "unnamed": sorted(unnamed)}


def self_test():
    assert split("Kobold_Token_3", "X")[:2] == ("Kobold", 3)
    assert split("Giant Spider 1 - Token", "X")[:2] == ("Giant Spider", 1)
    assert split("token_7", "Goblin") == ("Goblin", 7, True)
    assert split("9", "Bard") == ("Bard", 9, True)
    assert split("Abyssal_Hunter_Token", "X")[:2] == ("Abyssal Hunter", None)
    got = number([("A", None, "a"), ("A", 2, "b"), ("B", None, "c"), ("C", 1, "d"), ("C", 1, "e")])
    assert got == {"a": "A 01", "b": "A 02", "c": "B", "d": "C 01", "e": "C 02"}, got
    import tempfile
    with tempfile.TemporaryDirectory() as d:
        for f in ["[Mimics]/Chest_Mimic_Token_1.png", "[Mimics]/Chest_Mimic_Token_2.png", "[Bard]/9.png", "[Owlbaer]/Owlbear_Token_1.png", "[Mimics]/raw.png"]:
            os.makedirs(os.path.dirname(f"{d}/{f}"), exist_ok=True); open(f"{d}/{f}", "w").close()
        out = draft(d, "P", {"Owlbaer": "Owlbear"}, ["token"], "the P pack", token_test=lambda p: "raw" not in p)
        t = [r["target"] for r in out["rows"]]
        assert t == ["P/Bard/Bard 09.png", "P/Mimics/Chest Mimic 01.png", "P/Mimics/Chest Mimic 02.png", "P/Owlbear/Owlbear.png"], t
        assert out["rows"][1]["tags"] == ["token", "chest-mimic", "mimics"], out["rows"][1]["tags"]
        assert out["unnamed"] == ["P/Bard/Bard 09.png"] and len(out["art"]) == 1
    print("self-test ok")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--pack"); ap.add_argument("--target"); ap.add_argument("--title", default="")
    ap.add_argument("--rename", action="append", default=[]); ap.add_argument("--tags", default="")
    ap.add_argument("--self-test", action="store_true")
    a = ap.parse_args()
    if a.self_test:
        self_test(); sys.exit()
    if not (a.pack and a.target):
        sys.exit("need --pack and --target")
    json.dump(draft(a.pack, a.target, dict(x.split("=", 1) for x in a.rename),
                    [t for t in a.tags.split(",") if t], a.title), sys.stdout, ensure_ascii=False, indent=1)
