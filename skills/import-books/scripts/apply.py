#!/usr/bin/env python3
"""Write the plan's metadata and variant links to the shelf.

usage: apply.py --plan DIR|plan.json [--cli PATH]

Run after check_shelf.sh has merged dispositions/diffs and resolve_ids.py has filled book_id.
Rows with disposition `skip` are left alone. A row without a diff (a new row) is written in
full with `books batch-update`: every metadata field and the whole tag set, the category tag
first, since batch-update replaces tags. A row with a diff writes only `missing` fields plus the
`differs` fields its `apply` names, and its `diff.tags.add` through `books batch-tag`, which is
additive on the server, so no tag on the shelf is ever removed.
Variants are linked with `duplicates link`, 20 children per call, to the parent row's id
(`variant.of`) or to `variant.of_id` for a parent already on the shelf. A `differs` variant is
linked only when `apply` names `variant`; otherwise it is recorded `deferred`.

Refuses (exit 2, nothing written) when plan.json lacks check_shelf.sh's `shelf_checked` stamp, on
open questions, a row to write without book_id, a present row without a diff, an `apply` naming a
field that is not `differs`, a dangling or chained parent, a parent row without an id and no
`of_id`, or a new row whose category is neither in the plan nor on the server.
Receipts: DIR/receipts-apply.ndjson; a re-run skips rows already ok. Exit 1 on row failures.
"""
import argparse, json, os, sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "..", "..", "lib"))
from grimoire_skills import config, shelf  # noqa: E402


def refusals(rows):
    out, targets = [], {r["target"]: r for r in rows}
    parents = {(r.get("variant") or {}).get("of") for r in rows if r.get("variant")}
    for r in rows:
        t, d, v = r["target"], r.get("diff"), r.get("variant")
        if r.get("open_questions"):
            out.append(f"open questions on {t}")
        if r.get("disposition") == "skip":
            continue
        if not r.get("book_id"):
            out.append(f"no book_id for {t}")
        if r.get("disposition") == "present" and d is None:
            out.append(f"present row without a diff: {t} (run check_shelf.sh --plan)")
        for f in r.get("apply") or []:
            if ((d or {}).get(f) or {}).get("verdict") != "differs":
                out.append(f"apply names {f} on {t}, which is not differs" +
                           (" (tags need no approval)" if f == "tags" else ""))
        if v and not v.get("of_id") and not (targets.get(v.get("of")) or {}).get("book_id"):
            out.append(f"variant.of names no plan row with a book_id and there is no of_id: {t}")
        if v and t in parents:
            out.append(f"a variant cannot itself be a parent: {t}")
    return out


def item(r, category):
    """The batch-update item for a row, or None. A diffed row's tags go through batch-tag (adds())."""
    m, d, ap = r.get("metadata") or {}, r.get("diff"), r.get("apply") or []
    if d is None:
        return {"id": r["book_id"], **m, "tags": [category] + [x for x in r.get("tags") or [] if x != category]}
    v = lambda f: (d.get(f) or {}).get("verdict")
    it = {f: x for f, x in m.items() if v(f) == "missing" or (v(f) == "differs" and f in ap)}
    return {"id": r["book_id"], **it} if it else None


def adds(r):
    t = (r.get("diff") or {}).get("tags") or {}
    return t.get("add") or [] if t.get("verdict") == "adds" else []


def categories(cli, rows):
    """{book_id: server category} for new rows whose plan names no category."""
    need = [r["book_id"] for r in rows if r.get("diff") is None and "category" not in (r.get("metadata") or {})]
    if not need:
        return {}
    sid = shelf.system_of(cli, need[0])
    books = shelf.run(cli, "systems", "get", "--id", sid)[1].get("books") or [] if sid else []
    cat = {b["id"]: b.get("category") for b in books}
    for i in need:  # variant children are not listed under the system
        if i not in cat:
            cat[i] = shelf.run(cli, "books", "get", "--id", i)[1].get("category")
    return cat


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--plan", required=True)
    ap.add_argument("--cli")
    a = ap.parse_args()
    plan_file, run_dir = config.plan_paths(a.plan)
    cli = config.cli_path(config.load(), a.cli)
    plan = json.load(open(plan_file))
    rows = plan["rows"]
    if not plan.get("shelf_checked"):
        print("refusing: plan.json has no shelf_checked stamp; run check_shelf.sh --plan first", file=sys.stderr)
        sys.exit(2)
    bad = refusals(rows)
    rpath = os.path.join(run_dir, "receipts-apply.ndjson")
    done = {k for k, r in shelf.receipts(rpath).items() if r["status"] == "ok"}
    todo = [r for r in rows if r.get("disposition") != "skip"]
    pending = [r for r in todo if ("update", r["target"]) not in done]
    cat = {} if bad else categories(cli, pending)  # read-only; needs every book_id
    catof = lambda r: (r.get("metadata") or {}).get("category") or cat.get(r["book_id"])
    if not bad:
        bad = [f"no category for new row {r['target']}: neither in the plan nor on the server"
               for r in pending if r.get("diff") is None and not catof(r)]
    if bad:
        print("refusing:\n  " + "\n  ".join(bad), file=sys.stderr)
        sys.exit(2)

    log = open(rpath, "a")
    counts = {"ok": 0, "failed": 0, "deferred": 0}

    def note(step, r, status, detail=""):
        log.write(json.dumps({"step": step, "target": r["target"], "book_id": r.get("book_id"),
                              "status": status, "detail": detail}, ensure_ascii=False) + "\n")
        log.flush()
        counts[status] += 1

    fail = {}  # book_id -> why, for this run's update step

    def collect(rc, out, err, ids):
        good = set(out.get("updated") or []) if rc in (0, 3) else set()
        errs = {e.get("id"): e for e in out.get("errors") or [] if isinstance(e, dict)}
        for i in ids:
            if i not in good:
                fail.setdefault(i, json.dumps(errs[i], ensure_ascii=False) if i in errs else err.strip()[-300:])

    upd = [it for r in pending for it in [item(r, catof(r))] if it]
    for i in range(0, len(upd), 1000):
        chunk = upd[i:i + 1000]
        collect(*shelf.run(cli, "books", "batch-update", body={"items": chunk}), [it["id"] for it in chunk])
    by_tag = {}
    for r in pending:
        for tag in adds(r):
            by_tag.setdefault(tag, []).append(r["book_id"])
    for tag, ids_ in by_tag.items():
        for i in range(0, len(ids_), 1000):
            chunk = ids_[i:i + 1000]
            collect(*shelf.run(cli, "books", "batch-tag", body={"ids": chunk, "tags": [tag]}), chunk)
    sent = {it["id"] for it in upd} | {i for v in by_tag.values() for i in v}
    for r in pending:
        if r["book_id"] in sent:
            note("update", r, "failed" if r["book_id"] in fail else "ok", fail.get(r["book_id"], ""))

    ids = {r["target"]: r.get("book_id") for r in rows}
    fam = {}
    for r in rows:
        v, dv = r.get("variant"), ((r.get("diff") or {}).get("variant") or {}).get("verdict")
        if dv == "differs" and (v is None or "variant" not in (r.get("apply") or [])):
            note("link", r, "deferred", "shelf link differs from the plan; not approved"
                 if v else "shelf holds a variant link the plan does not propose")
        elif v and dv != "same" and ("link", r["target"]) not in done:
            fam.setdefault(ids.get(v.get("of")) or v["of_id"], []).append(r)
    for parent, kids in fam.items():
        for i in range(0, len(kids), 20):
            chunk = kids[i:i + 20]
            body = {"resource_type": "book", "parent_id": parent, "children": [
                {"id": r["book_id"], "kind": r["variant"]["kind"], "label": (r["variant"].get("label") or "")[:120]}
                for r in chunk]}
            rc, out, err = shelf.run(cli, "duplicates", "link", body=body)
            linked = set(out.get("linked") or [])
            errs = {e.get("id"): e for e in out.get("errors") or [] if isinstance(e, dict)}
            for r in chunk:
                ok = rc in (0, 3) and r["book_id"] in linked
                detail = json.dumps(errs.get(r["book_id"]), ensure_ascii=False) if r["book_id"] in errs else err.strip()[-300:]
                note("link", r, "ok" if ok else "failed", "" if ok else detail)

    print(json.dumps(counts))
    sys.exit(1 if counts["failed"] else 0)


if __name__ == "__main__":
    main()
