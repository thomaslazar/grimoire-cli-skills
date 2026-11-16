#!/usr/bin/env python3
"""Fill each row's book_id from `files browse` record_id, waiting for the server to index.

usage: resolve_ids.py --plan DIR|plan.json [--cli PATH] [--wait SECONDS] [--interval SECONDS]

Polls every --interval (default 20) until no row lacks an id or --wait (default 900) has passed.
On a timeout it runs one scoped `library rescan --scope <system_path> --metadata-mode new` once the
scan is idle and polls again for the same time. plan.json is written back with the ids (also on
failure, so a re-run starts from what resolved). Exit 0 all resolved, 2 rows still without an id.
"""
import argparse, json, os, sys, time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "..", "..", "lib"))
from grimoire_skills import config, shelf  # noqa: E402


def resolve(cli, sp, rows):
    cache = {}
    for r in rows:
        if r.get("book_id"):
            continue
        folder = f"{sp}/{os.path.dirname(r['target'])}".rstrip("/")
        if folder not in cache:
            cache[folder] = shelf.listing(cli, folder) or {}
        r["book_id"] = cache[folder].get(shelf.nfc(os.path.basename(r["target"])), {}).get("record_id")
    return [r["target"] for r in rows if not r.get("book_id")]


def wait(cli, sp, rows, seconds, interval):
    t0 = time.time()
    while True:
        missing = resolve(cli, sp, rows)
        if not missing or time.time() - t0 >= seconds:
            return missing
        time.sleep(interval)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--plan", required=True)
    ap.add_argument("--cli")
    ap.add_argument("--wait", type=int, default=900)
    ap.add_argument("--interval", type=int, default=20)
    a = ap.parse_args()
    plan_file, run_dir = config.plan_paths(a.plan)
    cli = config.cli_path(config.load(), a.cli)
    f = plan_file
    plan = json.load(open(f))
    sp = plan["system_path"].rstrip("/")
    rows = [r for r in plan["rows"] if r.get("disposition") != "skip"]
    missing = wait(cli, sp, rows, a.wait, a.interval)
    if missing:
        while shelf.run(cli, "library", "scan-status")[1].get("running"):
            time.sleep(a.interval)
        shelf.run(cli, "library", "rescan", "--scope", sp, "--metadata-mode", "new")
        missing = wait(cli, sp, rows, a.wait, a.interval)
    json.dump(plan, open(f, "w"), ensure_ascii=False, indent=1)
    print(json.dumps({"rows": len(rows), "missing": missing}, ensure_ascii=False))
    sys.exit(2 if missing else 0)
