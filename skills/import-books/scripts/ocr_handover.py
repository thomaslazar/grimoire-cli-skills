#!/usr/bin/env python3
"""Write the handover CSV for an external OCR tool: rows whose survey says none or partial.

usage: ocr_handover.py --plan DIR|plan.json --out CSV

Needs DIR/ocr-survey.json (ocr_survey.py) and `ocr: handover` in grimoire-skills.json.
Columns: source_path,output_path,reason. Both paths are absolute; output_path is the full file path
the OCR tool should write (DIR/ocr/NNN-<file name>, NNN the plan row index, so equal names never collide). Exit 2 on a missing survey or the wrong ocr mode.
"""
import argparse, csv, json, os, sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "..", "..", "lib"))
from grimoire_skills import config, shelf  # noqa: E402

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
    n, errors = 0, []
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
            w.writerow([src, os.path.join(plandir, "ocr", f"{i:03d}-{os.path.basename(src)}"), reason])
            n += 1
    print(f"{n} rows -> {a.out}" + (f"; unreadable, left out: {errors}" if errors else ""))
