#!/usr/bin/env python3
"""Read the shelf back against the plan after apply.py.

usage: readback.py --plan DIR|plan.json [--cli PATH]

Per row with a book_id: title/year/publisher/license as the plan says (on a diffed row only the
fields apply.py wrote) and every plan tag present. Per parent: variant_count, which counts child
rows, equal to the plan's linked children for a new parent, at least that for one already on the
shelf. Entries come from `systems get` (a plan entry missing there is reported `not a parent`);
variant children are read with `books get`. Fields the plan leaves null or `shelf_only` are skipped.
Exit 0 clean, 1 with every mismatch listed, 2 when the system cannot be resolved.
"""
import argparse, json, os, sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "..", "..", "lib"))
from grimoire_skills import config, shelf  # noqa: E402

FIELDS = ("title", "year", "publisher", "license")


def deferred(r):
    dv = ((r.get("diff") or {}).get("variant") or {}).get("verdict")
    return dv == "differs" and "variant" not in (r.get("apply") or [])


def check(cli, plan):
    rows = [r for r in plan["rows"] if r.get("book_id")]
    sid = plan.get("system_id") or (shelf.system_of(cli, rows[0]["book_id"]) if rows else None)
    if not sid:
        return None
    books = {b["id"]: b for b in shelf.run(cli, "systems", "get", "--id", sid)[1].get("books") or []}
    get = lambda i: books.get(i) or shelf.run(cli, "books", "get", "--id", i)[1]
    bad = []
    for r in rows:
        if r.get("variant"):
            x = shelf.run(cli, "books", "get", "--id", r["book_id"])[1]
        elif r["book_id"] in books:
            x = books[r["book_id"]]
        else:
            bad.append(f"{r['target']} not a parent: not among the system's entries")
            continue
        d, m = r.get("diff") or {}, r.get("metadata") or {}
        for f in FIELDS:
            v = (d.get(f) or {}).get("verdict")
            if m.get(f) is None or v == "shelf_only" or (v == "differs" and f not in (r.get("apply") or [])):
                continue
            if x.get(f) != m[f]:
                bad.append(f"{r['target']} {f}: shelf {x.get(f)!r}, plan {m[f]!r}")
        missing = set(r.get("tags") or []) - set(x.get("tags") or [])
        if missing:
            bad.append(f"{r['target']} tags missing: {sorted(missing)}")
    ids = {r["target"]: r for r in rows}
    kids = {}
    for r in rows:
        v = r.get("variant")
        if v and not deferred(r):
            p = ids.get(v.get("of"))
            key = (v.get("of"), p["book_id"], p.get("diff") is None) if p else (v.get("of"), v.get("of_id"), False)
            kids[key] = kids.get(key, 0) + 1
    for (name, pid, exact), n in kids.items():
        got = get(pid).get("variant_count") or 0
        if (got != n) if exact else (got < n):
            bad.append(f"{name} variant_count: shelf {got}, plan {'' if exact else 'at least '}{n}")
    return bad


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--plan", required=True)
    ap.add_argument("--cli")
    a = ap.parse_args()
    plan_file, run_dir = config.plan_paths(a.plan)
    cli = config.cli_path(config.load(), a.cli)
    bad = check(cli, json.load(open(plan_file)))
    if bad is None:
        print("cannot resolve the system from the plan's rows", file=sys.stderr)
        sys.exit(2)
    print("\n".join(bad) if bad else "readback clean")
    sys.exit(1 if bad else 0)
