#!/usr/bin/env python3
"""Write the handover CSV for an external OCR tool: rows whose survey says none or partial.

usage: ocr_handover.py --plan DIR|plan.json --out CSV

Needs DIR/ocr-survey.json (ocr_survey.py) and `ocr: handover` in grimoire-skills.json.
Columns: source_path,output_path,reason. Both paths are absolute; output_path is the full file path
the OCR tool should write (DIR/ocr/NNN-<file name>, NNN the plan row index, so equal names never collide). Exit 2 on a missing survey or the wrong ocr mode.

After the count line it prints a paste-ready instruction block for the OCR agent (between the
`----- OCR handover -----` markers): the files, the rules (source read-only, text layer only, exact
output paths) and the checks to run before reporting back. Hand that block to the user; do not write
it to a file.
"""
import argparse, csv, json, os, sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "..", "..", "lib"))
from grimoire_skills import config, shelf  # noqa: E402

def prompt(csv_path, ocr_dir, items):
    files = []
    for k, (src, out, s, lang) in enumerate(items, 1):
        what = ("image-only, OCR every page" if s["text"] == "none" else
                "OCR only pages %s; keep the existing text layer on the others" % ",".join(map(str, s["empty_pages"])))
        size = os.path.getsize(src) / 1048576 if os.path.exists(src) else 0
        files.append(f"{k}. {src}  ({s.get('pages', '?')} pages, {size:.0f} MB, language: {lang}; {what})\n   -> {out}")
    return "\n".join([
        "----- OCR handover -----",
        f"OCR handover: {len(items)} PDF(s) need a searchable text layer.",
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
        "- Write exactly the output paths above, keeping their file names. Leave no other files in the ocr/",
        "  folder except .log/.txt logs.",
        "- Do not upload anything anywhere. Do not touch any plan.json.",
        "",
        "Check each output before reporting done:",
        "- pdfinfo: page count equals the source's.",
        "- pdftotext <output> - | wc -m: well above the source's count.",
        "- pdftotext on an early prose page (credits, contents, intro) reads as real words in the stated language.",
        "- Render page 1 of the source and of the output (pdftoppm -f 1 -l 1 -r 50 -png): they look identical.",
        "- File size is close to the source's. A much smaller file means the images were recompressed.",
        "",
        "Report back, per file: the output path, page count, character count, OCR tool and language model used,",
        "and any page that failed or came out empty. If you had to break a rule above, say which rule and why.",
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
                      "pages %s have no text layer: OCR them and keep the existing text elsewhere" % ",".join(map(str, s["empty_pages"])))
            out = os.path.join(plandir, "ocr", f"{i:03d}-{os.path.basename(src)}")
            w.writerow([src, out, reason])
            items.append((src, out, s, (r.get("metadata") or {}).get("language") or "unknown"))
            n += 1
    print(f"{n} rows -> {a.out}" + (f"; unreadable, left out: {errors}" if errors else ""))
    if items:
        print(prompt(os.path.abspath(a.out), os.path.join(plandir, "ocr"), items))
