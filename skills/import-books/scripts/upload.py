#!/usr/bin/env python3
"""Upload every new row of the plan, verifying each against the server's listing.

usage: upload.py --plan DIR|plan.json [--cli PATH] [--no-ocr TARGET ...]

Each file goes up through a symlink named like its target (DIR/stage/<n>/), `--on-conflict skip`,
so the source is never touched and the stored name is the target's. Success means `files browse`
lists the NFC-matched name at the source's size. Rows with disposition present/skip are not
uploaded. Upload exit 2 (a 409: already there) is `skipped` when the server holds the plan size,
`failed` otherwise. Receipts: DIR/receipts-upload.ndjson; a re-run skips rows already ok.
stdout: "uploaded N, skipped N, failed N". Exit 0 clean, 1 on any failed row.

With `ocr: handover` it refuses (exit 2, nothing uploaded) when DIR/ocr-survey.json is missing, or when a row
the survey marks none, partial or junk still has its original source rather than an OCR output under
DIR/ocr/ (resolve_ocr.py). `--no-ocr TARGET` (repeatable) lets a named row go up without its OCR, when the
user has said so.
"""
import argparse, json, os, sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "..", "..", "lib"))
from grimoire_skills import config, shelf  # noqa: E402

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--plan", required=True)
    ap.add_argument("--cli")
    ap.add_argument("--no-ocr", action="append", default=[], metavar="TARGET")
    a = ap.parse_args()
    plan_file, run_dir = config.plan_paths(a.plan)
    cfg = config.load()
    cli = config.cli_path(cfg, a.cli)
    plan = json.load(open(plan_file))
    sp, root = plan["system_path"].rstrip("/"), plan.get("source_root", "")
    if cfg["ocr"] == "handover":
        survey_file = os.path.join(run_dir, "ocr-survey.json")
        if not os.path.exists(survey_file):
            shelf.refuse("ocr mode is handover and ocr-survey.json is missing; run ocr_survey.py, then hand over")
        survey, ocr_dir = json.load(open(survey_file)), os.path.join(os.path.abspath(run_dir), "ocr") + os.sep
        open_rows = [r["target"] for r in plan["rows"]
                     if survey.get(r["target"], {}).get("text") in ("none", "partial", "junk")
                     and r.get("disposition") not in ("present", "skip") and r["target"] not in a.no_ocr
                     and not os.path.abspath(os.path.join(root, r["source"])).startswith(ocr_dir)]
        if open_rows:
            shelf.refuse("rows still need their OCR (hand over, then resolve_ocr.py; or --no-ocr TARGET "
                         "if the user said so): " + "; ".join(open_rows))
    rpath = os.path.join(run_dir, "receipts-upload.ndjson")
    state = {}  # target -> "uploaded" | "skipped" from earlier runs
    if os.path.exists(rpath):
        for l in open(rpath):
            r = json.loads(l)
            if r["ok"]:
                state[r["target"]] = r["state"]
    log = open(rpath, "a")
    for i, r in enumerate(plan["rows"]):
        t = r["target"]
        if t in state or r.get("disposition") in ("present", "skip"):
            continue
        src = os.path.abspath(os.path.join(root, r["source"]))
        link = os.path.join(run_dir, "stage", f"{i:04d}", os.path.basename(t))
        os.makedirs(os.path.dirname(link), exist_ok=True)
        if not os.path.islink(link):
            os.symlink(src, link)
        dest = os.path.dirname(f"{sp}/{t}")
        rc, _, err = shelf.run(cli, "files", "upload", "--destination", dest, "--file", link, "--on-conflict", "skip")
        got = (shelf.listing(cli, dest) or {}).get(shelf.nfc(os.path.basename(t)), {}).get("size")
        match = got == os.path.getsize(src)
        s = ("uploaded" if rc == 0 else "skipped" if rc == 2 else "failed") if match else "failed"
        log.write(json.dumps({"target": t, "rc": rc, "ok": s != "failed", "state": s, "size": got,
                              "err": err.strip()[-300:]}) + "\n")
        log.flush()
        if s == "failed":
            print(f"FAILED {t}: rc={rc}, server size {got}", file=sys.stderr)
        else:
            state[t] = s
    n = lambda k: sum(1 for v in state.values() if v == k)
    bad = sum(1 for r in plan["rows"] if r["target"] not in state and r.get("disposition") not in ("present", "skip"))
    print(f"uploaded {n('uploaded')}, skipped {n('skipped')}, failed {bad}")
    sys.exit(1 if bad else 0)
