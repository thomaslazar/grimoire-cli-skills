#!/usr/bin/env python3
"""Create every missing folder level of the plan, parent first, checking each with `files browse`.

usage: make_folders.py --plan DIR|plan.json [--cli PATH]

Levels: every ancestor of system_path and of each row's target directory. A level listed in
plan["structure"]["create"] as {"path": ..., "container_kind": ...} gets that --container-kind;
any other level is a plain folder. Receipts: DIR/receipts-folders.ndjson. Exit 0, or 1 if a create failed.
"""
import argparse, json, os, sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "..", "..", "lib"))
from grimoire_skills import config, shelf  # noqa: E402

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--plan", required=True)
    ap.add_argument("--cli")
    a = ap.parse_args()
    plan_file, run_dir = config.plan_paths(a.plan)
    cli = config.cli_path(config.load(), a.cli)
    plan = json.load(open(plan_file))
    sp = plan["system_path"].rstrip("/")
    kind = {c["path"]: c.get("container_kind") for c in plan.get("structure", {}).get("create", [])}
    levels = set()
    for d in {sp, *(os.path.dirname(f"{sp}/{r['target']}") for r in plan["rows"])}:
        parts = d.split("/")
        levels |= {"/".join(parts[:i]) for i in range(2, len(parts) + 1)}  # level 1 is a collection root
    log, bad = open(os.path.join(run_dir, "receipts-folders.ndjson"), "a"), 0
    for path in sorted(levels, key=lambda p: (p.count("/"), p)):
        if shelf.listing(cli, path) is not None:
            continue
        parent, name = path.rsplit("/", 1)
        args = ["files", "folder", "create", "--parent", parent, "--name", name]
        if kind.get(path):
            args += ["--container-kind", kind[path]]
        rc, _, err = shelf.run(cli, *args)
        ok = rc == 0 or "already exists" in err
        bad += not ok
        log.write(json.dumps({"path": path, "ok": ok, "err": "" if ok else err[-300:]}) + "\n")
        print(("created " if ok else "FAILED ") + path, file=sys.stdout if ok else sys.stderr)
    sys.exit(1 if bad else 0)
