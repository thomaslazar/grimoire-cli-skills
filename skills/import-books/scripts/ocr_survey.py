#!/usr/bin/env python3
r"""Measure each PDF row's text layer, page by page, and mark it full | partial | none | junk.

usage: ocr_survey.py --plan DIR|plan.json [--drop REGEX] [--partial-ratio R] [--junk-garble PCT] [--words FILE]

Reads plan.json rows (source under source_root; rows with disposition skip/present and non-PDFs are
ignored). A page with under 40 characters of text, after lines matching --drop (default `^\s*Order #`, a
common purchase-watermark line) are removed, counts as empty. none = under 100 characters per page on
average (image-only); junk = a text layer whose garble% (ocr_quality.py) is at least --junk-garble
(default 5) and whose words of four or more letters are under 25% in the --words list (default
/usr/share/dict/words; pass the books' language): an old scanner OCR to replace, which wins over partial.
Both are needed: maps and stat-heavy books reach 10-35% garble on location and stat codes, but 39%+ of their
words are real; a junk layer sits near 3%. No word list -> no junk verdict, and the summary says so.
A degraded but partly readable scanner layer (garble 5-12%, 45-60% real words) overlaps with those maps,
so it is not classified: the summary's `check` lists every non-junk row at or above --junk-garble, for
the walkthrough to judge (maps and stat-heavy books are expected there);
partial = at least --partial-ratio (default 0.1) of the pages empty; else full.
An unreadable PDF (corrupt, encrypted) gets text `error` plus an `error` message and is skipped by
ocr_queue and ocr_handover, which report it. Writes DIR/ocr-survey.json: {target: {pages, cpp, empty, empty_pages, garble, dict, text}}.
Needs pdftotext (poppler); missing -> exit 2.
"""
import argparse, json, os, sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "..", "..", "lib"))
from grimoire_skills import config, shelf  # noqa: E402
from ocr_quality import dict_share, garble, long_words  # noqa: E402


def measure(path, drop, ratio, junk=5.0, words=None):
    try:
        pages = shelf.pdf_pages(path, drop)
    except ValueError as e:
        return {"text": "error", "error": str(e)}
    n = len(pages) or 1
    empty = [i + 1 for i, p in enumerate(pages) if len(p) < 40]
    cpp = sum(map(len, pages)) // n
    t = "\n".join(pages)
    g = garble(t)
    d = round(dict_share(long_words(t), words) * 100, 1) if words else None
    text = ("none" if cpp < 100 else "junk" if g >= junk and d is not None and d < 25 else
            "partial" if len(empty) / n >= ratio else "full")
    return {"pages": n, "cpp": cpp, "empty": len(empty), "empty_pages": empty, "garble": g, "dict": d, "text": text}


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--plan", required=True)
    ap.add_argument("--drop", default=r"^\s*Order #")
    ap.add_argument("--partial-ratio", type=float, default=0.1)
    ap.add_argument("--junk-garble", type=float, default=5.0)
    ap.add_argument("--words", default="/usr/share/dict/words")
    a = ap.parse_args()
    plan_file, run_dir = config.plan_paths(a.plan)
    shelf.need_tool("pdftotext", "brew install poppler / apt install poppler-utils")
    plan = json.load(open(plan_file))
    words = ({w.strip().lower() for w in open(a.words, encoding="utf-8", errors="replace")}
             if os.path.exists(a.words) else None)
    root, out = plan.get("source_root", ""), {}
    for r in plan["rows"]:
        src = os.path.abspath(os.path.join(root, r["source"]))
        if r.get("disposition") in ("skip", "present") or not src.lower().endswith(".pdf"):
            continue
        out[r["target"]] = measure(src, a.drop, a.partial_ratio, a.junk_garble, words)
    json.dump(out, open(os.path.join(run_dir, "ocr-survey.json"), "w"), ensure_ascii=False, indent=1)
    c = {k: sum(v["text"] == k for v in out.values()) for k in ("full", "partial", "junk", "none", "error")}
    c["check"] = sorted(k for k, v in out.items() if v["text"] != "junk" and v.get("garble", 0) >= a.junk_garble)
    if words is None:
        c["junk_check"] = f"skipped: no word list at {a.words} (pass --words)"
    print(json.dumps(c))
