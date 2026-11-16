#!/usr/bin/env python3
"""Refuse a plan.json that cannot be imported as written. Reads only; writes nothing.

usage: check_plan.py --plan DIR|plan.json [--cli PATH]    (DIR holds plan.json; optional plan key "source_root" prefixes relative sources)

Lists every problem, then exits 2; exit 0 and "plan ok: N rows" when clean.
Refuses: no rows, empty source or target, a missing source file, duplicate targets,
a target outside a category folder (books/ categories, or the armory's under the armory root),
a variant naming no row target (unless the row marks an existing shelf parent with variant.of_id),
a variant kind outside book_variant_kinds, a refused file extension.
"""
import argparse, json, os, sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "..", "..", "lib"))
from grimoire_skills import config, shelf  # noqa: E402


def check(plan, profile):
    errs, rows = [], plan.get("rows") or []
    if not rows:
        return ["no rows in the plan"]
    armory = profile.get("roots", {}).get("armory", "armory")
    sp = plan.get("system_path", "")
    cats = profile["armory_category_folders" if sp.split("/")[0] == armory else "category_folders"]
    kinds, refused = profile["book_variant_kinds"], [e.lower() for e in profile["refused_book_formats"]]
    root = plan.get("source_root", "")
    nt = [shelf.nfc(r.get("target", "")) for r in rows]
    for t in {t for t in nt if nt.count(t) > 1}:
        errs.append(f"duplicate target {t!r}")
    for r, t in zip(rows, nt):
        src = r.get("source", "")
        if not src or not t:
            errs.append(f"empty source or target in row {r!r}")
            continue
        if r.get("disposition") not in ("present", "skip") and not os.path.isfile(os.path.join(root, src)):
            errs.append(f"missing source {src}")
        parts = t.split("/")
        if t.startswith("/") or ".." in parts:
            errs.append(f"bad target {t!r}")
        elif len(parts) < 2 or parts[0] not in cats:
            errs.append(f"{t}: target is not inside a category folder ({', '.join(cats)})")
        ext = os.path.splitext(t)[1].lower()
        if ext in refused:
            errs.append(f"{t}: {ext} is refused by the server")
        v = r.get("variant")
        if v:
            if shelf.nfc(v.get("of", "")) not in nt and not v.get("of_id"):
                errs.append(f"{t}: variant of {v.get('of')!r}, which is no row target and has no of_id")
            if v.get("kind") not in kinds:
                errs.append(f"{t}: variant kind {v.get('kind')!r} is not one of {', '.join(kinds)}")
    return errs


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--plan", required=True)
    ap.add_argument("--cli")  # accepted for uniformity with the other steps
    a = ap.parse_args()
    plan_file, run_dir = config.plan_paths(a.plan)
    plan = json.load(open(plan_file))
    errs = check(plan, config.load()["profile"])
    if errs:
        print("plan refused:\n  " + "\n  ".join(errs), file=sys.stderr)
        sys.exit(2)
    print(f"plan ok: {len(plan['rows'])} rows")
