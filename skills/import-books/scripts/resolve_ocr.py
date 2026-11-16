#!/usr/bin/env python3
"""Point plan rows at the OCR tool's output files.

usage: resolve_ocr.py --plan DIR|plan.json --handover CSV

For every handover row whose output_path exists, the plan row whose source is that source_path gets
source = output_path (plan.json is written back). Reports handover rows no plan row uses. Exit 1 if a
listed output file is missing, 0 otherwise. Runs in handover mode only.
"""
import argparse, csv, json, os, sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "..", "..", "lib"))
from grimoire_skills import config, shelf  # noqa: E402

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--plan", required=True)
    ap.add_argument("--handover", required=True)
    a = ap.parse_args()
    plan_file, run_dir = config.plan_paths(a.plan)
    mode = config.load()["ocr"]
    if mode != "handover":
        shelf.refuse(f"ocr mode is '{mode}', not 'handover'; resolve_ocr.py only runs in handover mode")
    f = plan_file
    plan = json.load(open(f))
    root = plan.get("source_root", "")
    by_src = {os.path.abspath(os.path.join(root, r["source"])): r for r in plan["rows"]}
    missing, unused, done = [], [], 0
    for h in csv.DictReader(open(a.handover, newline="")):
        row = by_src.get(h["source_path"]) or by_src.get(h["output_path"])  # second run: already resolved
        if not os.path.exists(h["output_path"]):
            missing.append(h["output_path"])
        elif row is None:
            unused.append(h["source_path"])
        else:
            row["source"] = h["output_path"]
            done += 1
    json.dump(plan, open(f, "w"), ensure_ascii=False, indent=1)
    print(json.dumps({"resolved": done, "unused": unused, "missing": missing}, ensure_ascii=False))
    sys.exit(1 if missing else 0)
