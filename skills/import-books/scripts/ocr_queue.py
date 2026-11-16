#!/usr/bin/env python3
"""Server-side OCR: queue `books reindex` for every row the survey marks image-only (none).

usage: ocr_queue.py --plan DIR|plan.json [--cli PATH] [--interval SECONDS]

Needs `ocr: server`, DIR/ocr-survey.json and a book_id on each such row (resolve_ids.py). Waits for
`library scan-status` running false (a reindex fired during a running scan is silently dropped; a
failing scan-status is retried, never read as idle), fires every reindex back to back (the first
OCRs, the rest stay cleared), waits for idle again, then runs one unscoped
`library rescan --metadata-mode missing`, which collects the text-less books into one server-side
queue. Never cancels a scan. A 400 (not image-only) is recorded, not fatal. Rows the survey could
not read are reported, not queued.
Receipts: DIR/receipts-ocr_queue.ndjson (a reindex per row, plus a `rescan` receipt). A re-run skips
rows already ok, and runs the rescan if reindexes were queued without one after them.
Prints the queued ids. Exit 2 on unmet preconditions, 1 on a failed reindex, rescan or scan-status.
"""
import argparse, json, os, re, sys, time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "..", "..", "lib"))
from grimoire_skills import config, shelf  # noqa: E402


def idle(cli, interval, tries=3):
    fails = 0
    while True:
        rc, out, err = shelf.run(cli, "library", "scan-status")
        if rc == 0:
            if not out.get("running"):
                return
            fails = 0
        else:
            fails += 1
            if fails >= tries:
                sys.stderr.write("library scan-status keeps failing: " + err.strip()[-200:] + "\n")
                sys.exit(1)
        time.sleep(interval)


def rescan_pending(rpath):
    """True when a reindex was queued and no ok rescan receipt follows it."""
    pending = False
    if os.path.exists(rpath):
        for l in filter(str.strip, open(rpath)):
            r = json.loads(l)
            if r.get("step") == "rescan" and r["ok"]:
                pending = False
            elif r.get("queued"):
                pending = True
    return pending


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--plan", required=True)
    ap.add_argument("--cli")
    ap.add_argument("--interval", type=int, default=20)
    a = ap.parse_args()
    plan_file, run_dir = config.plan_paths(a.plan)
    cfg = config.load()
    if cfg["ocr"] != "server":
        shelf.refuse(f"ocr mode is '{cfg['ocr']}', not 'server'; ocr_queue.py only runs in server mode")
    cli = config.cli_path(cfg, a.cli)
    sp = os.path.join(run_dir, "ocr-survey.json")
    if not os.path.exists(sp):
        shelf.refuse("ocr-survey.json missing; run ocr_survey.py first")
    survey, plan = json.load(open(sp)), json.load(open(plan_file))
    unreadable = [r["target"] for r in plan["rows"] if survey.get(r["target"], {}).get("text") == "error"]
    rows = [r for r in plan["rows"] if survey.get(r["target"], {}).get("text") == "none"]
    if [r["target"] for r in rows if not r.get("book_id")]:
        shelf.refuse("image-only rows without a book_id: " + ", ".join(r["target"] for r in rows if not r.get("book_id"))
                     + "; run resolve_ids.py first")
    rpath = os.path.join(run_dir, "receipts-ocr_queue.ndjson")
    done = {t for (s, t), r in shelf.receipts(rpath).items() if s == "ocr_queue" and r["ok"]}
    todo = [r for r in rows if r["target"] not in done]
    queued, failed = [], 0
    log = open(rpath, "a")
    if todo:
        idle(cli, a.interval)
        for r in todo:
            rc, _, err = shelf.run(cli, "books", "reindex", "--id", r["book_id"])
            not_image = rc != 0 and re.search(r"\b400\b", err) is not None
            ok = rc == 0 or not_image
            failed += not ok
            if rc == 0:
                queued.append(r["book_id"])
            log.write(json.dumps({"step": "ocr_queue", "target": r["target"], "id": r["book_id"], "ok": ok,
                                  "queued": rc == 0, "note": "400: not image-only" if not_image else err.strip()[-300:]}) + "\n")
            log.flush()
    if rescan_pending(rpath):
        idle(cli, a.interval)
        rc, _, err = shelf.run(cli, "library", "rescan", "--metadata-mode", "missing")
        failed += rc != 0
        log.write(json.dumps({"step": "rescan", "target": "*", "ok": rc == 0, "note": err.strip()[-300:] if rc else ""}) + "\n")
    print(json.dumps({"queued": queued, "failed": failed, "unreadable": unreadable}))
    sys.exit(1 if failed else 0)
