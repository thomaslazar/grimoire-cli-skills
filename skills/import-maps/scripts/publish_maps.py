#!/usr/bin/env python3
"""Upload a map or token plan into maps/ or tokens/, wait for indexing, write tags and descriptions, link variants, verify.

usage: publish_maps.py --plan DIR|plan.json [--run-dir DIR] [--cli PATH]   (run dir defaults to the plan's folder)
                       [--index-timeout 900]
       publish_maps.py --plan DIR|plan.json --check   (validate only, write nothing)
       publish_maps.py --self-test

The collection is read off the root: maps/... or tokens/... (tokens have no variants in practice,
but the same link call works with resource_type token).

--cli: PATH, else the `cli` key of grimoire-skills.json, else grimoire-cli on PATH, else ./bin/grimoire-cli.
Variant kinds come from the profile's map_variant_kinds (maps/) or token_variant_kinds (tokens/).

plan.json: {"root": "maps/<Publisher>", "rows": [{"source": "/abs/corpus/file.png",
  "target": "<Product>/<Name>.png", "description": "...", "tags": [...],
  "variant": null | {"of": "<target of the entry>", "kind": "gridded", "label": "Square grid"}}]}

Steps, each re-runnable:
  1. refuse if a library scan is running
  2. create missing folders below root, parent first
  3. upload each row through a symlink named like the target (the corpus is never touched),
     --on-conflict skip; a 409 is a skip. Check the size on the server (files browse); never the mount
  4. wait for the file watcher to index (record_id on files browse), then for scan idle.
     If the watcher has not indexed all rows by --index-timeout, one scoped rescan, then wait again
  5. maps batch-update (tags REPLACE) for rows uploaded now; additive batch-tag for skipped rows
  6. duplicates link per entry, resource_type map, at most 20 children per call
  7. maps get every row: tags contain the plan's, description equal, variant under its entry

stdout: {"rows","uploaded","skipped","verified","failed":[...]}; receipt DIR/receipts/publish.json
exit: 0 ok, 1 usage/plan error, 2 precondition/server error, 3 verification failed
"""
import argparse, json, os, sys, time
from collections import defaultdict

sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "..", "..", "lib"))
from grimoire_skills import config, shelf  # noqa: E402

NFC = shelf.nfc
CLI = None
COLL, KIND = "maps", "map"  # set from the plan root: ("tokens", "token") for tokens/


def run(*args, body=None):
    return shelf.run(CLI, *args, body=body)


def die(code, msg):
    print(msg, file=sys.stderr)
    sys.exit(code)


def check_plan(plan, kinds=None):
    """Return a list of problems; empty means the plan is publishable."""
    errs, rows = [], plan.get("rows", [])
    if not plan.get("root", "").startswith(("maps/", "tokens/")):
        errs.append("root must start with maps/ or tokens/")
    targets = [r.get("target", "") for r in rows]
    if len(set(targets)) != len(targets):
        errs.append("duplicate targets")
    entries = {r["target"] for r in rows if not r.get("variant")}
    kids = defaultdict(int)
    for r in rows:
        t = r.get("target", "")
        if not t or t.startswith("/") or ".." in t.split("/"):
            errs.append(f"bad target {t!r}")
        if not r.get("tags") or not r.get("description"):
            errs.append(f"{t}: tags and description are required")
        v = r.get("variant")
        if v:
            if v.get("of") not in entries:
                errs.append(f"{t}: variant of {v.get('of')!r}, which is not an entry in this plan")
            if kinds is not None and v.get("kind") not in kinds:
                errs.append(f"{t}: variant kind {v.get('kind')!r} is not one of {', '.join(kinds)}")
            kids[v.get("of")] += 1
    return errs


def wait_idle():
    while run("library", "scan-status")[1].get("running"):
        time.sleep(10)


def listing(path):
    return shelf.listing(CLI, path)


def browse_ids(root, rows):
    cache, ids = {}, {}
    for r in rows:
        folder = f"{root}/{os.path.dirname(r['target'])}".rstrip("/")
        if folder not in cache:
            _, out, _ = run("files", "browse", "--path", folder)
            cache[folder] = {NFC(e["name"]): e.get("record_id") for e in out.get("entries", [])}
        ids[r["target"]] = cache[folder].get(NFC(os.path.basename(r["target"])))
    return ids


def main():
    global CLI, COLL, KIND
    ap = argparse.ArgumentParser()
    ap.add_argument("--plan"); ap.add_argument("--run-dir"); ap.add_argument("--cli")
    ap.add_argument("--index-timeout", type=int, default=900)
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--check", action="store_true", help="validate the plan and sources, write nothing")
    a = ap.parse_args()
    if a.self_test:
        return self_test()
    if not a.plan:
        die(1, "need --plan (a run directory holding plan.json, or a plan file)")
    plan_file, plan_dir = config.plan_paths(a.plan)
    a.run_dir = a.run_dir or plan_dir
    cfg = config.load()
    CLI = config.cli_path(cfg, a.cli)
    plan = json.load(open(plan_file)); root = plan["root"].rstrip("/"); rows = plan["rows"]
    COLL = root.split("/")[0]; KIND = {"maps": "map", "tokens": "token"}.get(COLL, "map")
    errs = check_plan(plan, cfg["profile"]["token_variant_kinds" if plan["root"].startswith("tokens/") else "map_variant_kinds"])
    if errs:
        die(1, "plan refused:\n  " + "\n  ".join(errs))
    for r in rows:
        if not os.path.isfile(r["source"]):
            die(1, f"missing source {r['source']}")
    if a.check:
        print(f"plan ok: {len(rows)} rows, {sum(1 for r in rows if not r.get('variant'))} entries")
        return
    if run("library", "scan-status")[1].get("running"):
        die(2, "a library scan is running; wait for it")

    # 2. folders, parent first
    for folder in sorted({os.path.dirname(f"{root}/{r['target']}") for r in rows}):
        parts = folder.split("/")
        for i in range(2, len(parts) + 1):
            if listing("/".join(parts[:i])) is None:
                rc, _, err = run("files", "folder", "create", "--parent", "/".join(parts[:i - 1]), "--name", parts[i - 1])
                if rc and "already exists" not in err:
                    die(2, f"folder create {'/'.join(parts[:i])}: {err[-300:]}")

    # 3. upload
    stage = os.path.join(a.run_dir, "stage"); fresh, skipped = set(), set()
    for i, r in enumerate(rows):
        link = os.path.join(stage, f"{i:04d}", os.path.basename(r["target"]))
        os.makedirs(os.path.dirname(link), exist_ok=True)
        if not os.path.islink(link):
            os.symlink(os.path.abspath(r["source"]), link)
        dest = os.path.dirname(f"{root}/{r['target']}")
        rc, _, err = run("files", "upload", "--destination", dest, "--file", link, "--on-conflict", "skip")
        if rc and "409" not in err and "exists" not in err:
            print(f"upload rc={rc} {r['target']}: {err[-200:]}", file=sys.stderr)
        got = (listing(dest) or {}).get(NFC(os.path.basename(r["target"])), {}).get("size")
        if got != os.path.getsize(r["source"]):
            die(2, f"not on the server at source size ({got}): {dest}/{os.path.basename(r['target'])}")
        (fresh if rc == 0 else skipped).add(r["target"])

    # 4. wait for the watcher, one scoped rescan as fallback
    t0, rescanned = time.time(), False
    while True:
        ids = browse_ids(root, rows)
        missing = [t for t, v in ids.items() if not v]
        if not missing:
            break
        if time.time() - t0 > a.index_timeout:
            if rescanned:
                die(2, f"{len(missing)} rows never indexed, e.g. {missing[:3]}")
            wait_idle()
            run("library", "rescan", "--metadata-mode", "missing", "--scope", root)
            rescanned, t0 = True, time.time()
        time.sleep(20)
    wait_idle()

    # 5. tags and descriptions
    # a skipped row that is still blank (uploaded by an interrupted run) is treated as fresh, keeping any tags it has
    for r in rows:
        if r["target"] in skipped:
            m = run(COLL, "get", "--id", ids[r["target"]])[1]
            if not m.get("description"):
                skipped.discard(r["target"]); fresh.add(r["target"]); r["tags"] = sorted(set(r["tags"]) | set(m.get("tags") or []))
    items = [{"id": ids[r["target"]], "description": r["description"], "tags": sorted(set(r["tags"]))}
             for r in rows if r["target"] in fresh]
    for i in range(0, len(items), 1000):
        rc, out, err = run(COLL, "batch-update", body={"items": items[i:i + 1000]})
        if rc or out.get("errors"):
            die(2, f"{COLL} batch-update: {err[-300:]}")
    for r in rows:
        if r["target"] in skipped:
            run(COLL, "batch-tag", body={"ids": [ids[r["target"]]], "tags": r["tags"]})

    # 6. variants
    fam = defaultdict(list)
    for r in rows:
        if r.get("variant"):
            v = r["variant"]
            fam[v["of"]].append({"id": ids[r["target"]], "kind": v["kind"], "label": v.get("label", "")})
    for parent, kids in fam.items():
        for i in range(0, len(kids), 20):
            rc, _, err = run("duplicates", "link", body={"resource_type": KIND, "parent_id": ids[parent], "children": kids[i:i + 20]})
            if rc not in (0, 3):
                die(2, f"duplicates link {parent}: {err[-300:]}")

    # 7. read back
    # one list call carries tags and description for every entry (thousands of rows in seconds, against minutes of gets);
    # variants are hidden from lists, so those rows still get their own call
    _, lst, _ = run(COLL, "list", "--limit", "100000")
    listed = {NFC(m["relative_path"]): m for m in lst.get(COLL, [])}
    failed = []
    for r in rows:
        m = listed.get(NFC(f"{root}/{r['target']}"))
        if r.get("variant") or m is None:
            _, m, _ = run(COLL, "get", "--id", ids[r["target"]])
        why = []
        if not set(r["tags"]) <= set(m.get("tags") or []): why.append("tags")
        if r["target"] in fresh and m.get("description") != r["description"]: why.append("description")
        if r.get("variant") and m.get("variant_parent_id") != ids[r["variant"]["of"]]: why.append("variant")
        if why: failed.append({"target": r["target"], "why": why})
    res = {"rows": len(rows), "uploaded": len(fresh), "skipped": len(skipped),
           "verified": len(rows) - len(failed), "failed": failed}
    os.makedirs(os.path.join(a.run_dir, "receipts"), exist_ok=True)
    json.dump({**res, "ids": ids}, open(os.path.join(a.run_dir, "receipts", "publish.json"), "w"), ensure_ascii=False, indent=1)
    print(json.dumps(res, ensure_ascii=False))
    sys.exit(3 if failed else 0)


def self_test():
    ok = {"root": "maps/P", "rows": [
        {"source": "/x/a.png", "target": "Prod/A.png", "description": "A.", "tags": ["map"], "variant": None},
        {"source": "/x/b.png", "target": "Prod/A - Night.png", "description": "A.", "tags": ["map", "night"],
         "variant": {"of": "Prod/A.png", "kind": "other", "label": "Night"}}]}
    assert check_plan(ok) == [], check_plan(ok)
    bad = json.loads(json.dumps(ok)); bad["root"] = "books/X"; bad["rows"][1]["variant"]["of"] = "Prod/B.png"
    bad["rows"][0]["tags"] = []; bad["rows"].append(dict(ok["rows"][0], target="../A.png"))
    e = " | ".join(check_plan(bad))
    for want in ("root must", "not an entry", "required", "bad target"):
        assert want in e, (want, e)
    tok = json.loads(json.dumps(ok)); tok["root"] = "tokens/P"
    assert check_plan(tok) == [], check_plan(tok)
    print("self-test ok")


if __name__ == "__main__":
    main()
