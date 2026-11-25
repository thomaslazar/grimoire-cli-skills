#!/usr/bin/env python3
"""OCR-quality scorer.

usage: ocr_quality.py [--markers a,b,c] FOLDER [FOLDER ...]

garble% = share of word tokens showing OCR damage: a digit inside a letter run, an underscore, an
internal case flip (statLli) or a junk character. A digital-native PDF sits near 0.2%; 1.4% or more
is a reasonable bar for re-OCR. Dice and stat codes (1d6, 2d20+3, AC15, DMG2d6) are not counted.
frag% = share of one-letter tokens. --markers is a comma list of characters or strings that your
language uses often (e.g. `é,è,à,ç`); the report then adds a markers-per-1000-letters column, which
catches a wrong-language OCR model. Default: no markers, no column.
--words FILE is a word list for the book's language (one word per line, e.g. /usr/share/dict/words for
English). The report then adds a lowpg column: pages with 60+ words of four or more letters where under
25% are in the list. Those are pages OCR'd sideways (rotated tables and maps) or from a garbled render,
which garble% misses because the junk is made of letters. Read the listed pages before re-OCR: hex maps
and name tables score low too.
Needs pdftotext (poppler); missing -> exit 2.
"""
import argparse, os, re, subprocess, sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "..", "..", "lib"))
from grimoire_skills import shelf  # noqa: E402

L = r"[^\W\d_]"
TOK = re.compile(r"[^\s]{2,}")
STAT = re.compile(r"^(?:\d*[dDwW]\d+(?:[+-]\d+)?|[A-Z]{1,3}[a-z]?\d{1,3}|[A-Z]{1,3}\d*[dDwW]\d+)$")


def long_words(t):
    return [w.lower() for w in re.findall(L + "{4,}", t)]


def dict_share(ws, words):
    """Share of words (lower case) found in the word list, plural s allowed."""
    return sum(w in words or w.rstrip("s") in words for w in ws) / (len(ws) or 1)


def low_pages(t, words):
    bad = []
    for i, pg in enumerate(t.split("\f"), 1):
        ws = long_words(pg)
        if len(ws) >= 60 and dict_share(ws, words) < 0.25:
            bad.append(i)
    return bad


def counts(t):
    """Word count and the damage counts that make up garble%."""
    words = [w for w in TOK.findall(t) if re.search(L, w)]
    return dict(
        words=words,
        digit=sum(1 for w in words if re.search(L + r"\d|\d" + L, w) and not STAT.match(w)),
        under=sum("_" in w for w in words),
        flip=sum(1 for w in words if re.search(r"[^\W\dA-Z_][A-Z]", w) and re.search(r"[a-z][A-Z]", w)),
        junk=sum(1 for w in words if re.search(r"[�|~^`<>{}\\]", w)))


def garble(t):
    """garble% of a text: share of word tokens showing OCR damage."""
    c = counts(t)
    return round((c["digit"] + c["under"] + c["flip"] + c["junk"]) / (len(c["words"]) or 1) * 100, 2)


def score(path, markers=(), wordlist=None):
    t = subprocess.run(["pdftotext", path, "-"], capture_output=True, text=True, errors="replace").stdout
    c = counts(t)
    words, digit, under, flip, junk = c["words"], c["digit"], c["under"], c["flip"], c["junk"]
    n = len(words) or 1
    frag = sum(1 for w in words if len(re.sub(r"[\W\d_]", "", w)) == 1)
    letters = max(sum(c.isalpha() for c in t), 1)
    r = dict(words=n, garble=garble(t), digit=round(digit / n * 100, 2),
             underscore=round(under / n * 100, 2), caseflip=round(flip / n * 100, 2), junk=round(junk / n * 100, 2),
             frag=round(frag / n * 100, 1))
    if markers:
        r["per1k"] = round(sum(t.count(m) for m in markers) / letters * 1000, 1)
    if wordlist:
        r["lowpg"] = low_pages(t, wordlist)
    return r


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--markers", default="")
    ap.add_argument("--words", help="word list for the low-dictionary page check")
    ap.add_argument("folders", nargs="+")
    a = ap.parse_args()
    shelf.need_tool("pdftotext", "brew install poppler / apt install poppler-utils")
    mk = [m for m in a.markers.split(",") if m]
    wl = {w.strip().lower() for w in open(a.words, encoding="utf-8", errors="replace")} if a.words else None
    rows = []
    for root in a.folders:
        for dp, _, fs in os.walk(root):
            for f in sorted(fs):
                if f.lower().endswith(".pdf"):
                    s = score(os.path.join(dp, f), mk, wl)
                    s["name"] = f[:-4]
                    rows.append(s)
    rows.sort(key=lambda r: -r["garble"])
    print(f"{'file':44}{'garble%':>8}{'digit':>7}{'under':>7}{'case':>7}{'junk':>6}{'frag%':>7}" + (f"{'mk/1k':>7}" if mk else "") + ("  lowpg" if wl else ""))
    for r in rows:
        print(f"{r['name'][:42]:44}{r['garble']:>8}{r['digit']:>7}{r['underscore']:>7}{r['caseflip']:>7}{r['junk']:>6}{r['frag']:>7}"
              + (f"{r['per1k']:>7}" if mk else "")
              + (f"  {len(r['lowpg'])} {r['lowpg'][:12]}" if wl and r["lowpg"] else ("  0" if wl else "")))
