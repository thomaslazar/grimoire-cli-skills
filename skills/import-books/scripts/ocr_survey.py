#!/usr/bin/env python3
r"""Measure each PDF row's text layer, page by page, and mark it full | partial | none.

usage: ocr_survey.py --plan DIR|plan.json [--drop REGEX] [--partial-ratio R]

Reads plan.json rows (source under source_root; rows with disposition skip/present and non-PDFs are
ignored). A page with under 40 characters of text, after lines matching --drop (default `^\s*Order #`, a
common purchase-watermark line) are removed, counts as empty. none = under 100 characters per page on
average (image-only); partial = at least --partial-ratio (default 0.1) of the pages empty; else full.
An unreadable PDF (corrupt, encrypted) gets text `error` plus an `error` message and is skipped by
ocr_queue and ocr_handover, which report it. Writes DIR/ocr-survey.json: {target: {pages, cpp, empty, empty_pages, text}}.
Needs pdftotext (poppler); missing -> exit 2.
"""
import argparse, json, os, sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "..", "..", "lib"))
from grimoire_skills import config, shelf  # noqa: E402


def measure(path, drop, ratio):
    try:
        pages = shelf.pdf_pages(path, drop)
    except ValueError as e:
        return {"text": "error", "error": str(e)}
    n = len(pages) or 1
    empty = [i + 1 for i, p in enumerate(pages) if len(p) < 40]
    cpp = sum(map(len, pages)) // n
    text = "none" if cpp < 100 else "partial" if len(empty) / n >= ratio else "full"
    return {"pages": n, "cpp": cpp, "empty": len(empty), "empty_pages": empty, "text": text}


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--plan", required=True)
    ap.add_argument("--drop", default=r"^\s*Order #")
    ap.add_argument("--partial-ratio", type=float, default=0.1)
    a = ap.parse_args()
    plan_file, run_dir = config.plan_paths(a.plan)
    shelf.need_tool("pdftotext", "brew install poppler / apt install poppler-utils")
    plan = json.load(open(plan_file))
    root, out = plan.get("source_root", ""), {}
    for r in plan["rows"]:
        src = os.path.abspath(os.path.join(root, r["source"]))
        if r.get("disposition") in ("skip", "present") or not src.lower().endswith(".pdf"):
            continue
        out[r["target"]] = measure(src, a.drop, a.partial_ratio)
    json.dump(out, open(os.path.join(run_dir, "ocr-survey.json"), "w"), ensure_ascii=False, indent=1)
    c = {k: sum(v["text"] == k for v in out.values()) for k in ("full", "partial", "none", "error")}
    print(json.dumps(c))
