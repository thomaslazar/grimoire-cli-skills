#!/usr/bin/env python3
"""Write the handover CSV for an external OCR tool: rows whose survey says none, partial or junk.

usage: ocr_handover.py --plan DIR|plan.json --out CSV

Needs DIR/ocr-survey.json (ocr_survey.py) and `ocr: handover` in grimoire-skills.json.
Columns: source_path,output_path,reason. Both paths are absolute; output_path is the full file path
the OCR tool should write (DIR/ocr/NNN-<file name>, NNN the plan row index, so equal names never collide). Exit 2 on a missing survey or the wrong ocr mode.

The full instructions for the OCR agent (the files, the rules: source read-only, text layer only,
exact output paths; the checks to run; what to report back) go to a Markdown file beside the CSV
(<out>.md). After the count line it prints a short paste-ready block (between the
`----- OCR handover -----` markers) naming both files by absolute path. Hand that block to the user.
"""
import argparse, csv, json, os, sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "..", "..", "lib"))
from grimoire_skills import config, shelf  # noqa: E402

LIST_MAX = 25  # above this, the block summarises and points at the CSV


def instructions(csv_path, ocr_dir, items):
    files = []
    for k, (src, out, s, lang) in enumerate(items, 1):
        what = ("image-only, OCR every page" if s["text"] == "none" else
                "junk text layer (garble %s%%): replace it on every page, ocrmypdf --redo-ocr" % s.get("garble") if s["text"] == "junk" else
                "OCR only pages %s; keep the existing text layer on the others" % ",".join(map(str, s["empty_pages"])))
        size = os.path.getsize(src) / 1048576 if os.path.exists(src) else 0
        files.append(f"{k}. {src}  ({s.get('pages', '?')} pages, {size:.0f} MB, language: {lang}; {what})\n   -> {out}")
    if len(files) > LIST_MAX:  # a corpus-wide pass: the CSV carries the list, the block the totals
        none = [it for it in items if it[2]["text"] == "none"]
        junk = [it for it in items if it[2]["text"] == "junk"]
        part = [it for it in items if it[2]["text"] == "partial"]
        langs = sorted({it[3] for it in items})
        files = [f"{len(none)} image-only PDFs ({sum(it[2].get('pages', 0) for it in none)} pages): OCR every page.",
                 f"{len(junk)} PDFs with a junk text layer ({sum(it[2].get('pages', 0) for it in junk)} pages):"
                 " replace the layer on every page (ocrmypdf --redo-ocr).",
                 f"{len(part)} PDFs with some empty pages ({sum(len(it[2]['empty_pages']) for it in part)} pages):"
                 " OCR only the pages the CSV's reason column names; keep the existing text layer on the others.",
                 f"Languages: {', '.join(langs)}. The full list, with each output path, is in the CSV."]
    return "\n".join([
        f"# OCR handover: {len(items)} PDF(s) need a searchable text layer",
        "",
        f"Handover CSV (columns source_path,output_path,reason; all paths absolute):\n{csv_path}",
        "",
        "Files:", *files,
        "",
        "Rules:",
        "- The source files are read-only. Do not rename, modify, re-save or delete them. If your tool works in",
        f"  place, copy the file into {ocr_dir}/ first and work on the copy.",
        "- Add an invisible text layer over the original page images only. Do not re-render, downsample,",
        "  recompress, deskew, rotate, crop or clean the images. Do not reorder, drop or merge pages. No Acrobat",
        "  ClearScan or any \"replace image with text\" mode.",
        "- Detect page orientation (ocrmypdf --rotate-pages, or Tesseract OSD per page). Pages printed sideways",
        "  (tables, maps) are OCR'd in reading orientation, but every page keeps the display rotation (/Rotate)",
        "  it has in the source.",
        "- A file that already has a text layer of junk (an old scanner OCR) gets that layer replaced",
        "  (ocrmypdf --redo-ocr), not skipped.",
        "- If a page renders blank or garbled (e.g. 1-channel JPEGs tagged /DeviceRGB), OCR a working copy with",
        "  the colour space corrected, then keep the source's image bytes and image dictionaries in the output.",
        "- Write exactly the output paths given, keeping their file names. Leave no other files in the ocr/",
        "  folder except .log/.txt logs.",
        "- Do not upload anything anywhere. Do not touch any plan.json.",
        "",
        "Check each output before reporting done:",
        "- pdfinfo: page count equals the source's.",
        "- pdftotext <output> - | wc -m: well above the source's count.",
        "- pdftotext on an early prose page (credits, contents, intro) reads as real words in the stated language.",
        "- Per page: no page with plenty of text reads as mostly non-words (a sideways or garbled page).",
        "- Render page 1 of the source and of the output (pdftoppm -f 1 -l 1 -r 50 -png): they look identical.",
        "- File size is close to the source's. A much smaller file means the images were recompressed.",
        "",
        "Report back, per file: the output path, page count, character count, OCR tool and language model used,",
        "and any page that failed or came out empty. If you had to break a rule above, say which rule and why.",
        "",
    ])


def block(md_path, csv_path, n):
    return "\n".join([
        "----- OCR handover -----",
        f"OCR handover: {n} PDF(s) need a searchable text layer.",
        f"Read and follow the instructions (files, rules, checks, report): {md_path}",
        f"Files and output paths (CSV): {csv_path}",
        "----- end OCR handover -----",
    ])


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--plan", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    plan_file, run_dir = config.plan_paths(a.plan)
    mode = config.load()["ocr"]
    if mode != "handover":
        shelf.refuse(f"ocr mode is '{mode}', not 'handover'; ocr_handover.py only runs in handover mode")
    sp = os.path.join(run_dir, "ocr-survey.json")
    if not os.path.exists(sp):
        shelf.refuse("ocr-survey.json missing; run ocr_survey.py first")
    survey, plan = json.load(open(sp)), json.load(open(plan_file))
    root, plandir = plan.get("source_root", ""), os.path.abspath(run_dir)
    n, errors, items = 0, [], []
    with open(a.out, "w", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["source_path", "output_path", "reason"])
        for i, r in enumerate(plan["rows"]):
            s = survey.get(r["target"])
            if s and s["text"] == "error":
                errors.append(r["target"])
            if not s or s["text"] in ("full", "error"):
                continue
            src = os.path.abspath(os.path.join(root, r["source"]))
            reason = ("image-only: OCR every page and add a text layer" if s["text"] == "none" else
                      "junk text layer (garble %s%%): replace it on every page with ocrmypdf --redo-ocr" % s.get("garble")
                      if s["text"] == "junk" else
                      "pages %s have no text layer: OCR them and keep the existing text elsewhere" % ",".join(map(str, s["empty_pages"])))
            out = os.path.join(plandir, "ocr", f"{i:03d}-{os.path.basename(src)}")
            w.writerow([src, out, reason])
            items.append((src, out, s, (r.get("metadata") or {}).get("language") or "unknown"))
            n += 1
    print(f"{n} rows -> {a.out}" + (f"; unreadable, left out: {errors}" if errors else ""))
    if items:
        csv_abs = os.path.abspath(a.out)
        md = os.path.splitext(csv_abs)[0] + ".md"
        with open(md, "w") as f:
            f.write(instructions(csv_abs, os.path.join(plandir, "ocr"), items))
        print(block(md, csv_abs, len(items)))
