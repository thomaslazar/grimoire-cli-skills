#!/usr/bin/env python3
"""Set the system's own metadata and cover from plan["system"].

usage: system_meta.py --plan DIR|plan.json [--cli PATH]

plan["system"] may carry name, parent_system, edition, genres, publishers, license, description,
dice (sent as dice_materials) and cover_book_target (a plan row's target). The system id is
resolved from the first row's book (`books get`), sent one `systems update`, and the cover is
copied with `systems cover from-source --source-type book`. The id is written back to plan.json
as system_id. Exit 2 without writing when plan.system is absent, no row has a book_id, or the
cover target is not a plan row with an id; exit 1 when a call fails.
"""
import argparse, json, os, sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "..", "..", "lib"))
from grimoire_skills import config, shelf  # noqa: E402

KEYS = ("name", "parent_system", "edition", "genres", "publishers", "license", "description")


def refuse(msg):
    print("refusing: " + msg, file=sys.stderr)
    sys.exit(2)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--plan", required=True)
    ap.add_argument("--cli")
    a = ap.parse_args()
    plan_file, run_dir = config.plan_paths(a.plan)
    cli = config.cli_path(config.load(), a.cli)
    f = plan_file
    plan = json.load(open(f))
    s = plan.get("system") or refuse("plan.json has no system block")
    ids = {r["target"]: r.get("book_id") for r in plan["rows"]}
    first = next((r["book_id"] for r in plan["rows"] if r.get("book_id")), None) or refuse("no row has a book_id")
    cover = s.get("cover_book_target")
    if cover and not ids.get(cover):
        refuse(f"cover_book_target {cover!r} is not a plan row with a book_id")
    sid = shelf.system_of(cli, first) or refuse(f"cannot resolve the system of book {first}")

    body = {k: s[k] for k in KEYS if k in s}
    if "dice" in s:
        body["dice_materials"] = s["dice"]
    rc, _, err = shelf.run(cli, "systems", "update", "--id", sid, body=body)
    fails = [f"systems update: {err.strip()[-300:]}"] if rc else []
    if cover:
        rc, _, err = shelf.run(cli, "systems", "cover", "from-source", "--id", sid,
                               "--source-type", "book", "--source-id", ids[cover])
        fails += [f"systems cover: {err.strip()[-300:]}"] if rc else []
    plan["system_id"] = sid
    json.dump(plan, open(f, "w"), ensure_ascii=False, indent=1)
    print("\n".join(fails) if fails else f"system {sid} updated")
    sys.exit(1 if fails else 0)
