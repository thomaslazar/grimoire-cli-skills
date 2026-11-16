---
name: audit-library
description: >-
  Use when checking the Grimoire library's health rather than adding to it — tag vocabulary drift,
  off-vocabulary system fields, unpaired companion tags, stale folder records, metadata coverage,
  variant families. Triggers: "audit the library", "what's inconsistent on the shelves", "check
  the tags", "coverage report", "is the shelf clean". NOT for importing (→ import-books) or
  installing the CLI (→ install-grimoire-cli).
metadata:
  grimoire-cli-groups:
    - systems
    - books
    - tags
    - genres
    - licenses
    - parent-systems
    - system-families
    - dice-materials
    - files
    - duplicates
    - library
    - logs
    - backups
  min-cli: "0.8.0"
  min-server: "1.11.0"
---

# audit-library

Measures what is on the shelves against the profile's conventions and against the server's own
vocabularies, and reports. **It writes nothing to the library** (only its own run directory). Every fix it proposes is a separate, explicit
decision by the user. Not a metadata sweep: it only tells you what is wrong. Script-free; the
commands below are the skill. Run them as `grimoire-cli …` (or the path your
`grimoire-skills.json` names).

## Principles

1. **Read-only.** No `update`, no `batch-*`, no `link`, no `delete`. If the report is wrong,
   nothing has to be undone.
2. **Count rows, not shelf entries.** `systems get` and `books list` return parents only, which
   hides every variant child. An audit built on either silently skips them.
3. **Measure, don't infer.** A capability is what the server does when asked, not what the shelf
   happens to contain.
4. **Report every finding with its evidence**: the count, the ids, the query that produced it. A
   finding nobody can re-derive is a rumour.
5. **An unexplained number stays unexplained.** Say so rather than inventing a cause.

## Phase 0: preflight

`me` reports `admin` (or `gm`), the server is 1.11.0 or newer, `jq` and `python3` are available.
No PDF tools and no library mount: this skill never leaves the server.

```bash
run_dir="./tmp/audit-library/$(date +%Y%m%dT%H%M%S)"; mkdir -p "$run_dir"
python3 <skill folder>/../../lib/grimoire_skills/config.py | jq '{rules, vocab: .profile}' > "$run_dir/profile.json"
```

Run it from your library repo (the current directory): the script path is resolved from this skill's
folder, like every script path here, but the config is searched upward from the current directory.

The rules being audited against are the profile's `conventions.md` (its `## Tags` section: the
closed vocabulary, the prefixed identifiers, the companion-tag prefix) plus every override file
that `rule_files()` lists. Read them before the tag checks; never audit against a list you
remembered.

## Phase 1: collect the row-complete set

Three steps per shelf, not one call per row.

```bash
# every system, containers included
grimoire-cli systems list --include-children > "$run_dir/systems.json"

# every shelf entry, with full book records embedded
for id in $(jq -r '.[]|select(.book_count>0)|.id' "$run_dir/systems.json"); do
  grimoire-cli systems get --id "$id" | jq -c --arg s "$id" '.books[]|.+{_system:$s}'
done > "$run_dir/entries.ndjson"

# the variant children those responses omit
jq -r 'select((.variant_count//0)>0)|.id' "$run_dir/entries.ndjson" \
  | while read -r p; do grimoire-cli books get --id "$p" | jq -r '.variants[]?.id'; done \
  | while read -r v; do grimoire-cli books get --id "$v" | jq -c '.+{_variant:true}'; done \
  > "$run_dir/variants.ndjson"

cat "$run_dir/entries.ndjson" "$run_dir/variants.ndjson" > "$run_dir/rows.ndjson"
```

`systems get` carries only `variant_count` and `variant_kinds`, so children come from `books get`
on each parent. `books get` returns `relative_path: null`; `systems get` carries it. `books list`
filters only by system, category and added date: for anything else, list everything and filter
locally (check `--help` for the current filters).

Cross-check the entry count against `grimoire-cli books list --limit 1 | jq .total`. They must
agree; if they do not, a system was missed.

## Phase 2: the checks

Each check writes a finding: `check`, `severity`, `count`, `evidence` (ids or paths), and `fix`
(the command that would repair it, **not run**).

### Tag vocabulary

- **Paired tags.** If the profile or an override pairs tags (a library that keeps paired editions
  in two languages can check that every row has its twin; a companion tag such as `for:<parent>`
  names a parent that should exist), read the pairs from the rules and report any row carrying
  one side without the other.

  ```bash
  python3 - "$run_dir/rows.ndjson" en-tag other-tag <<'PY'
  import json,sys
  rows=[json.loads(l) for l in open(sys.argv[1])]
  a,b=sys.argv[2:4]
  bad=[r for r in rows if (a in (r.get("tags") or [])) != (b in (r.get("tags") or []))]
  print(f"{a}/{b}: {len(bad)} unpaired")
  for r in bad[:20]: print("  ",r["id"],r.get("relative_path") or r["filename"])
  PY
  ```

- **Casing and plural splits.** `tags list` gives the whole vocabulary; fold on lowercase and a
  trailing `s` and report any key with more than one spelling.
- **Off-vocabulary tags.** Anything outside the closed set in the profile's `## Tags` section
  that is not one of its prefixed identifiers. The prefixes come from the profile and its
  overrides, not from this skill.

Count with `tags items --tag X` and read `.total` (or `.counts`), never `.items | length`:
`tags items` pages (default 100). `tags list` counts agree with `tags items` totals; a tag with a
count and zero items is still a finding worth reporting. Cross-check anything that matters
against `rows.ndjson`.

### System fields against the server's vocabularies

`systems update` validates nothing: an unmatched value is stored as written, so these drift
silently and only a comparison finds them.

```bash
for v in genres licenses parent-systems system-families dice-materials; do
  grimoire-cli "$v" list > "$run_dir/vocab-$v.json"
done
```

Compare every system's `license`, `dice_materials` and `genres` against `licenses list`,
`dice-materials list` and `genres list`. Judge `license` and `dice_materials` strictly; the rest
loosely. `parent-systems list` ships empty by design: Grimoire seeds no defaults and a container
child's `parent_system` is folder-derived, so a value in use need not appear. `system-families
list` can be sparse for the same reason. Never report either as drift.

### Stale folder records

```bash
for id in $(jq -r '.[].id' "$run_dir/systems.json"); do
  grimoire-cli systems books folders list --id "$id" \
    | jq -r --arg i "$id" '.folders[]|"\($i)\t\(.path)\t\(.tags|join(","))"'
done
```

A record is created only by `books folders set`; nothing enumerates the tree and nothing prunes a
record when its folder is renamed or removed. After any category rename, records survive pointing
at paths that no longer exist. `path` is `{system-id}/{category}/{subfolder}`; resolve each against
`files browse` and report the misses. A record with empty `tags` is inert but still stale. Folder
tags never appear in a book's own `tags`, so a row can inherit a tag that no per-row check will
ever see.

### Metadata coverage

Per system, over `rows.ndjson`: `description`, `isbn`, `language`, `publisher`, `year`,
`authors`, `artists`, `genres`, `urls`, `publisher_url`, `product_code` and the category tag.
Report ratios per shelf, not a library total: a gap normal on one line is a defect on another.

`jq 'select(.isbn)'` counts `""` as present. Always `select(.f != null and .f != "")`.

Two facts that are **not** defects: a free download has no ISBN, and a companion sheet usually
has no `authors`.

### Variant families

- A parent whose `variant_count` disagrees with `variants|length`.
- A variant child missing `language`, `description` or its category tag. The listing endpoints
  hide these rows, so this is where metadata rots unseen.
- Rows that look like twins but are not linked: `duplicates scan --accuracy exact
  --resource-types book`, then `duplicates groups`. `duplicates scan` answers 409 while a library
  scan runs, and a scan already in flight answers 200 `already_running` with exit 3. A pair
  deliberately not a duplicate belongs in `duplicates dismiss`; check `duplicates dismissals`
  before re-reporting one.

### Files on disk but not indexed

`files browse` marks an entry with `record_id` when it is in the catalogue and without when it is
only on disk. Walk the shelves and report the bare ones: an interrupted import or a hand-copied
file. The listing caps at 2000 entries; read `total` and `truncated`. Sidecars are excluded from
both.

The inverse, rows whose file is gone, is `is_missing` on the row, and `library cleanup-missing`
is the repair. It has no dry-run, refuses with 409 while a scan runs, commits per row, and reads
an absent library directory as wholly deleted, so never run it while the server cannot see its
library volume: `files browse` a known shelf first and stop if it answers empty. `--force` goes
past the empty-library guard; never pass it without a fresh backup.

### Server-side failures

`grimoire-cli logs --level error` (admin only) reads the server's own log, a 20 000-entry ring
buffer. It is the only view of failures that never reached a CLI response: a scan that died
mid-book, an OCR pass that threw, a rename that half-applied. Poll with `--after-seq <max_seq>`
rather than re-reading; `max_seq` advances over the whole buffer, so a `--level` that matches
nothing still moves the cursor, and a backlog larger than `--limit` silently drops its oldest
entries. Report anything at `error` or above since the last audit, with its timestamp.

## Phase 3: report

One table per check: severity, count, the shelf, and the repair command **unrun**. Then, one line
each:

- what is a defect versus what is simply uneven,
- which findings are cheap (a metadata write) versus a rename or relink,
- anything measured but unexplained, said plainly as unexplained.

Offer the fixes as a numbered list and **stop**. Applying them is the user's call, one by one or
in a batch they name: a `batch-update` across every system is one call and one mistake.

## Repairs, for when the user says yes

| finding | repair |
|---|---|
| unpaired tag | `books batch-tag` with the missing tag: additive, cannot remove. To remove a wrong tag, `books update` with the full replacement set |
| off-vocabulary `license`/`dice_materials` | `systems batch-update` with `{items:[…]}`, up to 1000 |
| stale folder record | `systems books folders delete --id <sys> --path <path>` (404 if already gone) |
| wrong container marker | `files folder markers`; omitted fields are left alone |
| unlinked twin | `duplicates link`, taking `suggested_kind`/`suggested_label` from `duplicates groups` |
| genuine non-duplicate re-raised | `duplicates dismiss` |
| row whose file is gone | `library cleanup-missing` |
| missing page text on an image-only PDF | `books reindex --id <id>`; never `library cancel-scan`, which restarts the OCR queue from zero |

Take a backup first if the batch is large or touches rows this session did not create:
`backups list | jq -r '.backups|sort_by(.created_at)|last|.created_at'`, and `backups create`
only if that is over a day old.

## Related

- The profile's `conventions.md` and override files: the rules being audited against.
- `import-books`: shares the CLI traps list, and is where a finding that needs new files goes.
- Metadata fixes follow one loop: audit, classify each row (map, periodical, pre-generated character,
  component, product) before looking anything up, source, plan, review the plan, apply, verify. The plan is the
  reviewable artifact; writes go sidecar first, then `books update`. A dedicated enrich skill is on the roadmap;
  until then these fixes are manual and run only on the user's yes.
