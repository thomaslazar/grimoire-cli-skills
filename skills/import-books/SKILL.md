---
name: import-books
description: >-
  Use when importing a folder of TTRPG books into Grimoire — a new system, a new edition, or a
  batch added to an existing shelf. Triggers: "import these books", "add this folder to Grimoire",
  "set up a new system from these files", "shelve these PDFs". NOT for system-independent maps (→
  import-maps), token packs (→ import-tokens) or soundtracks (→ import-audio), NOT for installing
  the CLI (→ install-grimoire-cli).
metadata:
  grimoire-cli-groups:
    - books
    - systems
    - files
    - library
    - duplicates
    - tags
    - licenses
    - logs
    - backups
    - addons
  min-cli: "0.8.0"
  min-server: "1.11.0"
---

# import-books

Takes a folder of TTRPG files and leaves a finished shelf: the right folder tree, uploaded files,
indexed rows, publisher metadata, variant links, and a note of what the run left behind. Books
only, including a book's own maps, handouts and tokens, which stay beside it. Not a rescue tool for
a broken shelf and not a metadata sweep over an existing one.

The rules are the profile's (`conventions.md`, plus any override `*.md`): *Layout*, *Filenames*,
*Variants and the entry*, *Tags*, *Licence placement* and *Metadata*. This skill is how to apply
them. Print the resolved config: Run it from your library repo (the current directory), with the script path resolved from this skill's folder: `python3 <skill folder>/../../lib/grimoire_skills/config.py`. It names the
profile, the overrides folder, the lines folder and the `ocr` mode (`server` unless the user set
`handover`). Script paths are resolved from this skill folder, the working directory stays your library repo; every script takes `--plan DIR` (the
run dir holding `plan.json`) and finds the CLI from `--cli`, then the `cli` key of
`grimoire-skills.json`, then `PATH`, then `./bin/grimoire-cli`. `references/design.md` explains
why the phases run in this order; `references/metadata-ladder.md` is the method for pulling
metadata out of files and sources.

## Principles

1. **The source folder is read-only.** Uploads go through symlinks named like the target;
   conversions and extractions happen in the run dir. Never rename, convert or delete in the
   source.
2. **Only phase 2 touches external sources.** Every other phase reads the source folder, the
   server and the run dir, and can be re-run.
3. **Names are right before the first write.** Research comes before the plan, so nothing needs
   renaming afterwards.
4. **Scripts refuse, they do not warn.** An unmet precondition is a non-zero exit (2), never a
   log line to skim past.
5. **Agreement is silent, disagreement is vocal, and a judgement is never silent.** Grouping files
   into one product, choosing a category, or turning a source folder into a filename qualifier is
   approved by the user before the write, because reversing it means renaming files.
6. **Surface suspected defects; never auto-correct.** Dropped diacritics, typos and contradictory
   printings are reported with evidence. Repairs come from a word list the user reviewed.

Order of work: duplicates first, then path work (names, folders), then metadata. Metadata written
before either is metadata written twice.

## Inputs

- **Source folder(s).** Read-only for the whole run. Import only what the user named; do not
  widen the run to other folders, not even to compare.
- **Target system path**, e.g. `books/Starfall RPG/1 EN`. It may be absent, empty or populated;
  never assume greenfield.
- **The line reference**, `<lines_dir>/<line>.md`, when the config names a `lines` folder. It
  holds that line's lookup sources, catalogue-code rules, field precedence and traps (shape in
  the repo's `lines/README.md`). None ship with the skills. Without one, the line has no agreed
  phase-2 source: propose one and ask before using it.

## Phase 0: preflight

- `grimoire-cli me`: the role must be `admin`. Record the CLI and server versions (`grimoire-cli
  --version`; the server version shows with `--debug`). Below this skill's `min-cli`/`min-server`,
  stop and tell the user to update; the skill carries no workaround for older versions.
- **An expired session cannot be fixed non-interactively.** `login` needs a real console; with
  redirected stdin its prompt throws. Ask the user to log in from their own terminal, or to pipe
  the password with `--username … --password-stdin`. Never type a password yourself.
- A newly installed CLI binary can be blocked by a local firewall; the symptom looks like a TLS or
  server fault. If plain HTTPS to the same host works and the CLI does not, ask the user to allow
  it, then retry once.
- `grimoire-cli library scan-status` must be idle (`running: false`). A previous import's OCR tail
  blocks this run's scans; wait for it rather than cancelling it.
- Tools: `python3` and `jq` are required. `pdfinfo`/`pdftotext`/`pdftoppm`/`pdfimages`
  (poppler) are needed for page counts, text layers, the OCR scripts and renders; without them
  identification leans on filenames alone, so say so. `qpdf` is needed only to merge print parts.
- Everything goes through the server. Never read or write the library's storage directly, even if
  it is mounted.
- Create a fresh run dir and never reuse one: `tmp/import-books/<YYYYMMDDTHHMMSS>-<slug>/`. Long
  steps (upload, OCR, waits) must keep the machine awake: on macOS, prefix long runs with `caffeinate -i`.

## Phase 1: survey (source and shelf)

Read-only. Record both halves in the run dir.

**Source half.**
- Walk the source, ignoring dotfiles and OS litter (`.DS_Store`, `@eaDir`, `Thumbs.db`). Per file:
  size, `file` type (a `.pdf` can be a JPEG), `pdfinfo` fields, page count.
- **List the members of every archive**, whatever its name says. A zip named like a soundtrack
  can hold book PDFs. Report 0-byte members as a defect of the archive. Extract only into the run
  dir. Handout zips under `books/` index as one inert row, so extract them and shelve the files.
  Plain `unzip` can silently drop CP437 bytes in member names; check the extracted names.
- **Byte twins.** Hash the source (`shasum -a 256`) for twins inside it. For twins already on the
  shelf, compare source sizes against `files browse` sizes and hash only the candidates; on the
  server side, `grimoire-cli duplicates scan --accuracy exact --resource-types book`, then
  `duplicates groups` (each member with `suggested_kind`/`suggested_label`, ready for `link`) and
  `duplicates compare` (2–4 ids; `suggested_parent_id`, `reference_counts`). A pair that is not a
  duplicate is closed with `duplicates dismiss`.
- **Grouping.** Group candidate products by folder plus stem, never stem alone: equal basenames in
  different folders are normal, and the folder is the qualifier the flatter target name will need
  (`A4 Print/…` → ` - A4 Print`). Compare names NFC/NFD-insensitively. Folder and archive names
  are hints, not proof: open the files.
- **Text layer, per page.** A file-level text share hides interior image pages. Check the whole
  file before calling it image-only: covers are often scans in an otherwise digital book. The
  OCR survey in phase 3 measures every page.
- Map images beside a book go through `python3 ../import-maps/scripts/transparency.py <dir>`: a
  transparent map is offered an opaque copy as its entry (profile *Maps, tokens, models and
  audio*).

**Shelf half.**
- `grimoire-cli systems list --include-children` (without the flag, children are hidden before
  filters apply, so `--genre`, `--family`, `--edition` and `--license` return `[]`).
- `files browse` down the target path level by level, stopping at the first that does not exist,
  noting each level's `container_kind`, the category folders present, and every existing row with
  its `record_id` (the `book_id`). A browse lists at most 2000 entries: read `truncated`.
- `systems get --id <id>` embeds a full record for every book on the shelf in one call (with
  `language`, `tags`, `isbn`, `description`, `relative_path`) and returns `scope_path`, a ready
  `--scope` value. It lists parents only and carries no `variants[]`; `--include-books false`
  drops the books.

**House style.** The shelf's existing rows are the convention and outrank general rules until the
user says otherwise: a batch that spells `publisher` or shapes `title` differently from its
neighbours splits the shelf. From the `systems get` books, derive:

| derive | from | why |
|---|---|---|
| does `title` carry the catalogue code? | `title` vs the filename stem | half a shelf titled `ES005 - Example Bestiary`, half `Example Bestiary` |
| code width | digits in the filename prefix | `ES10` sorts before `ES2` unpadded |
| `publisher` spelling | distinct values | `Example Press` vs `Example Press Ltd.` |
| `genres` | distinct sets | one set per shelf is normal |
| `urls` labels, `publisher_url` | distinct values | one label per source |
| tags in use and their casing | union of `tags` | catches `supplement`/`supplements` |
| `artists` populated? | count of rows | tells enrichment from inconsistency |
| category folder spelling | folder names | the server's spelling wins |

More than one value where one is expected means the shelf is already inconsistent: say so, do not
pick silently. A greenfield system borrows the style of its siblings under the same line or
family first, then the rest of the library, and the walkthrough names the shelf it came from.

## Phase 2: identify (the only network phase)

For each product, establish its identity and fetch its record. Cache raw responses in the run dir
so a re-run costs no requests. Use the line reference's sources first. Use whatever web access
your agent has; for sites that refuse bots, a browser-automation CLI such as agent-browser or
Playwright. When the line's source misses, look further: the publisher's own site, crowdfunding
pages, storefronts such as itch.io. A product with no publisher of record takes its creator as
publisher. If the user keeps an order of sources, it is in their overrides.

Field precedence (a line reference may refine it):

| field | wins |
|---|---|
| printing, edition, © year | the file's own imprint / credits page |
| ISBN, release date, page count, authors, blurb | the line's source (catalogue, publisher, shop) |
| product code / SKU | **what is printed on the file** (cover artwork, back cover, imprint), else the source |
| catalogue code | **the line's catalogue**, never a previous importer's filename |

- **Embedded PDF metadata never wins.** It is prepress boilerplate or a layout filename.
- **A printed code beats the corpus's numbering**, and a catalogue beats a filename: a source
  folder's numbering can be shifted against a series that was renumbered since. A disagreement
  decides a filename, so it is a `rename` decision for the walkthrough.
- **Look at the rendered cover before saying "no code printed".** Stock numbers sit in the cover
  art; render the cover pages (`pdftoppm -f 1 -l 2 -r 100 -png`) and read them. A back-cover
  barcode beats a credits-page ISBN.
- **The publisher's own © year beats a shop's listing year and the OGL's year.**
- **Edition is decided per book**: a "for use with … edition" note first, then the © year, then
  the release date against the core book's; wiki and shop edition labels last.
- **A blurb printed over artwork garbles in text extraction.** Render the page and read it.
- Credits read off the file where the source has none go in with their provenance
  (`sources.artists = "pdf:credits"`). Only the writing credit is `authors`.
- When a catalogue's type field and the publisher's blurb disagree about what a product is, the
  blurb decides.
- `pdfinfo` Creator/Producer tells who built a PDF, not who sanctioned it. For "is this official",
  read the series' own page.
- **Corroborate every identifier across two sources** before it reaches a filename. Extract
  identifiers corpus-wide and check for duplicates first: two books claiming one number is
  invisible to a single-source check.
- **Record a firm negative** ("no listing at the publisher, the shop or the archive") so the next
  pass does not repeat it.

**Through the server's add-ons.** A shop that refuses scripted clients is often reachable through a
metadata add-on, because it answers from the server. `grimoire-cli addons list` shows what is
installed and runnable. `books metadata-search` and `metadata-fetch` need an `--id`, and no row of
this import exists yet: **use any indexed book as a read-only anchor** (on a greenfield import,
borrow one from another system). Nothing is written to it.

```bash
grimoire-cli books metadata-sources --id <anchor>
grimoire-cli books metadata-search  --id <anchor> --source-id <source> --query "<catalogue title>"
grimoire-cli books metadata-fetch   --id <anchor> --source-id <source> --paste "<identity>"
```

- `metadata-sources` answers `{sources: [{id, name, description, homepage, attribution, supports_paste}]}`:
  list the ids with `.sources[] | {id, name}`; `--source-id` takes `id`.
- The diff is under `.fields`: read `.fields[] | select(.field=="description") | .incoming` and
  ignore `current`. A field the record does not carry is absent from the diff, which is an answer.
- Matching traps: a component (token sheet, errata) matches its parent product; an identical score
  across a whole series means one wrong product; build the query for the catalogue's wording,
  not from the filename.
- `title` and `publisher` usually report `differs` (the naming convention, a storefront's
  imprint name). Pick one spelling per shelf and keep it.
- A storefront add-on may never return `isbn`; an absent ISBN there is no evidence.
- A system-level add-on knows line-level facts at most (genre, dice); it may hold one record per
  line for the current edition only. Never take `edition` from a provider.

## Phase 3: plan (local only)

Write `plan.json` into the run dir, with a small `plan.py` there if it helps. A gap found here is
an `open_question` on the row, or a targeted return to phase 2, never a silent fetch.

- **Every row has an explicit title**, carrying the code as the filename does (profile
  *Filenames*). Never ship Grimoire's filename-derived title.
- **Every row conforms to the house style** unless a `naming` decision says why not. Bringing an
  existing shelf into line is its own job, not a side effect of an import.
- Targets follow the profile's *Layout* and *Filenames*: the category folder exactly one level
  below the system, from the profile's `category_folders`.
- **Licence** follows *Licence placement*. An import that makes a uniform shelf mixed must backfill
  the rows already there and clear the system's licence (`""`), so it is a walkthrough item.
  Values come from `grimoire-cli licenses list`.
- Multi-file print parts of one product merge into one row (`qpdf --empty --pages a.pdf b.pdf --
  out.pdf`, in the run dir). A PDF/EPUB pair lands as the PDF with the EPUB as an `other` variant;
  a format the server refuses is left out with that reason.
- A book that belongs on a second system's shelf is one row on its home shelf, linked over in
  phase 9; never a second copy.
- Every source file is used or excluded with a reason. Assert that none is left over.

### plan.json

```json
{
  "system_path": "books/Starfall RPG/1 EN",
  "source_root": "/path/to/source/Starfall",
  "structure": {"create": [{"path": "books/Starfall RPG", "container_kind": "parent"}]},
  "system": {"genres": ["Science Fiction"], "publishers": [{"name": "Example Press", "url": ""}],
             "license": "Proprietary", "description": "…",
             "cover_book_target": "Core/SF001 - Core Rules [2022].pdf"},
  "rows": [
    {"source": "Core/Starfall Core Rules.pdf",
     "target": "Core/SF001 - Core Rules [2022].pdf",
     "metadata": {"title": "SF001 - Core Rules", "language": "en", "year": 2022,
                  "publisher": "Example Press"},
     "tags": ["core"], "variant": null, "sources": {"year": "imprint"}, "open_questions": []},
    {"source": "Core/Starfall Core Rules 2nd print.pdf",
     "target": "Core/SF001 - Core Rules - Second Printing [2021].pdf",
     "metadata": {"title": "SF001 - Core Rules (Second Printing)", "isbn": "9780000000000",
                  "language": "en", "year": 2021, "publisher": "Example Press",
                  "product_code": "EXP1001"},
     "tags": ["core", "printing:second"],
     "variant": {"of": "Core/SF001 - Core Rules [2022].pdf", "kind": "version",
                 "label": "Second Printing"},
     "sources": {"isbn": "imprint", "year": "imprint", "product_code": "cover"},
     "open_questions": []}
  ],
  "decisions": [
    {"kind": "printing", "chose": "2022 printing is the entry", "because": "newest printing",
     "alternatives": ["2021 printing"], "cost_to_reverse": "relink"}
  ]
}
```

| key | written by | notes |
|---|---|---|
| `system_path`, `source_root` | you | `source_root` prefixes relative `source` paths; targets are relative to `system_path` |
| `structure` | `check_shelf.sh` | `create` lists container levels to create, parent first, with `container_kind` (`family`, `parent` by depth); other levels are created plain. Refreshed on every check; a `container_kind` you set for a path is kept |
| `system` | you | for `system_meta.py`: `parent_system`, `edition`, `genres`, `publishers`, `license`, `description`, `dice`, `cover_book_target`. **Leave `name` out** unless a `permanent` decision approved the rename: setting it marks the system custom forever |
| row `source` `target` `metadata` `tags` `variant` `sources` `open_questions` | you | `metadata` goes to `books batch-update` as-is, so its keys are that request's fields (`title`, `isbn`, `language`, `year`/`month`/`day`, `publisher`, `description`, `authors`, `artists`, `genres`, `category`, `license`, `publisher_url`, `urls`, `product_code`, …) and every key is diffed |
| `variant` | you | `of` names a plan row's **target**; for a parent already on the shelf add `of_id` (its book id). `kind` from the profile's `book_variant_kinds` |
| row `disposition` `book_id` `diff`, plan `shelf_checked` | `check_shelf.sh` | merged into plan.json by target |
| row `book_id` (new rows), plan `system_id` | `resolve_ids.py`, `system_meta.py` | |
| row `apply` | you, from the walkthrough's approvals | names `differs` fields only |

Values carry provenance in `sources`; a `null` is legitimate only with a reason in
`open_questions` or a decision.

**Decision records.** Every judgement, as opposed to a copied fact, goes into `decisions` with
`kind`, `chose`, `because`, `alternatives` and `cost_to_reverse`:

| `cost_to_reverse` | meaning |
|---|---|
| `cheap` | a metadata write fixes it later (title, description, tags) |
| `rename` | needs `files rename`/`files move` |
| `relink` | needs `duplicates unlink`/`link` |
| `permanent` | cannot be undone (a custom system name, a deleted file) |

Kinds that always produce a record: `grouping`, `qualifier`, `folder`, `category`, `naming`,
`printing`, `identity`, `omission`, `authored`.

### Check and reconcile

```bash
python3 scripts/check_plan.py --plan <run>
bash scripts/check_shelf.sh --plan <run> > <run>/check_shelf.json
```

`check_plan.py` reads only. It lists every problem and exits 2 on: no rows, an empty source or
target, a missing source file, duplicate targets, a target outside a category folder, a variant
naming no row target and no `of_id`, a variant kind outside `book_variant_kinds`, or a refused
file extension (the profile's `refused_book_formats`).

`check_shelf.sh` reads the server and writes `disposition`, `book_id` and `diff` into plan.json's
rows by target (a row that turns `new` drops a stale `book_id` and `diff`), writes `structure`
(`create`, `reuse`, `scaffold`, `conflicts`) into the plan, and stamps `shelf_checked`. **Run it on
every import, greenfield included: `apply.py` refuses a plan without the stamp.** Its stdout also
holds `known_systems` and `existing_books`. To give a level another container kind, set its
`container_kind` in `structure.create`; a re-check keeps it. It exits 2
on a server error. A level that does not exist is data ("No such path in the library" becomes a
`create`); any other browse failure is an error, never an empty shelf.

| disposition | file | metadata |
|---|---|---|
| `new` | upload it | write everything the plan has |
| `present` | already there | reconcile per the diff |
| `skip` | already there | the diff holds nothing writable |

| verdict | meaning | `apply.py` may |
|---|---|---|
| `missing` | the shelf is empty, the plan has a value | write it |
| `same` | they agree | nothing |
| `differs` | both hold values and disagree | **nothing unless the row's `apply` names the field** |
| `absent_both` | neither has it | nothing |
| `shelf_only` | the shelf has a value, the plan none (key absent or `null`) | nothing |
| `adds` (tags) | tags the plan adds | add them (`batch-tag`, additive) |

An explicit `""` in the plan clears a field, so it is a `differs` needing approval. For `variant`,
`{"shelf": "<id>", "plan": null}` is a `differs`: the shelf holds a link the plan does not propose.
**`differs` is never written because of a re-run**; the shelf's value may be a human decision.

**Re-run `check_shelf.sh` after every plan edit, but never after the upload.** Once this run's files
are indexed it reads them as `present` and gates their titles behind `differs`.

### OCR (branches on `ocr`)

Survey every plan:

```bash
python3 scripts/ocr_survey.py --plan <run>
```

It writes `ocr-survey.json`: per PDF row, pages, characters per page, empty pages and `text` =
`full`, `partial` (at least 10% of pages empty, `--partial-ratio`), `none` (image-only) or `error`
(unreadable, reported and skipped). Lines matching `--drop` (default `^\s*Order #`, a purchase
watermark) do not count as text.

- **`ocr: server`**: nothing to do before upload; phase 7 queues the `none` rows. Partial rows
  are reported in the walkthrough; the server only OCRs image-only books.
- **`ocr: handover`** (the user runs their own OCR tool):
  ```bash
  python3 scripts/ocr_handover.py --plan <run> --out <run>/ocr-handover.csv
  ```
  The CSV has `source_path,output_path,reason`, both paths absolute, the output a full file path
  under `<run>/ocr/` (prefixed with the row index, so equal names never collide). Draft it here so
  the walkthrough can show it, but **hand it over only after "proceed"**, and regenerate it if the
  approved plan changed rows. Wait for the outputs, then point the plan at them and re-check before
  phase 5:
  ```bash
  python3 scripts/resolve_ocr.py --plan <run> --handover <run>/ocr-handover.csv
  python3 scripts/check_plan.py --plan <run>
  ```
  `resolve_ocr.py` rewrites each matching row's `source` to the output, reports handover rows no
  plan row uses, and exits 1 if a listed output is missing. **Every plan of every run in a batch
  resolves through the handover**, not only the first. Before deleting the OCR work folder,
  check that every output is the source of an uploaded row or was left out with a reason.

Score text quality before upload: `python3 scripts/ocr_quality.py [--markers é,è,à,ç] <dir>…`. See
*OCR quality* below for reading it.

## Phase 4: walkthrough (HARD STOP)

Show it in the console. **Do not continue without an explicit "proceed"; showing the table is not
approval.** Order strictly by cost to reverse, so attention goes where a wrong "proceed" costs
something:

1. **Decisions with `cost_to_reverse` `permanent`, `rename` or `relink`**, grouped by kind: what
   was chosen, on what evidence, and the alternative. The test: if it is wrong, does fixing it
   touch the filesystem? If yes, show it in full, however many there are.
2. **The reconciliation diff**: every `differs` in full (field, shelf value, plan value). Approval
   means adding the field to that row's `apply`. `missing` and `adds` are written regardless:
   count them. Lead with what overwrites a non-empty field, then new tag vocabulary, then class
   assignments (category, kind): a misclassified row is plausibly wrong everywhere.
3. **House-style conformance**: every field where the plan departs from the style, with both
   shapes and the rows. **Say "conforms" when nothing diverges.** Name the shelf the style came
   from when it was not the target.
4. **The target tree**: each level `create` or `reuse`; new system or `N books already on this
   shelf`; container kinds.
5. **A row table**: source → target, disposition, title, ISBN, year, tags, variant.
6. **Structure conflicts** (`check_shelf.sh` `conflicts`): nothing is re-marked or renamed without a
   yes.
7. **Surfaced defects**, each with evidence and no correction applied.
8. **Exclusions**: one table row per excluded file (path, size or pages, reason, evidence). Never
   a summary count; an exclusion is the one decision that silently loses content. A byte twin names
   both paths and which is kept; a judgement about what a file *is* quotes the evidence (the line
   from the PDF, the catalogue field, the `file` output). Then the authored fields: text you wrote
   rather than a publisher.
9. **OCR**: rows the survey marked `none` or `partial`, what happens to each, and the time budget.
10. **Open questions**, by row.
11. **What is written where**, in one line: folders created, files uploaded, rows updated, links
    made.

Cheap decisions are summarised, not enumerated. Record the approvals in plan.json (`apply`, any
`container_kind` change), then re-run `check_plan.py` and `check_shelf.sh`. With `ocr: handover`,
hand the CSV over now and resolve it (phase 3) before phase 5.

## Phase 5: structure

Back up first only when the newest archive is over a day old, or the run is unusually destructive
(touching rows this import did not create). `grimoire-cli backups list` answers `{backups,
directory, total_bytes}`; `backups create` locks writes until it finishes and covers the database,
campaign uploads and covers, **not the library files**. A 409 means one is already running: poll
`backups list`, do not retry `create`. Record the archive you relied on.

```bash
python3 scripts/make_folders.py --plan <run>
```

Creates every missing ancestor of `system_path` and of each target's folder, parent first, after
checking each with `files browse`. A level in `structure.create` gets its `--container-kind`; the
system folder and category folders are plain. Receipts: `receipts-folders.ndjson`; exit 1 if a
create failed. For the full standard category set, `grimoire-cli files folder scaffold --path
<system path>` (safe to re-run).

A level with the wrong container kind is not recreated: `files folder markers` sets the markers on
an existing folder (omitted fields are left alone). `files folder contents` answers `has_content`,
which decides whether a later `files delete` needs `--confirm-name`.

## Phase 6: upload

```bash
python3 scripts/upload.py --plan <run>
```

Uploads every row not `present`/`skip`, one `files upload --on-conflict skip` per file through a
symlink named like the target (`<run>/stage/`), so the source is never touched and the stored name
is the target's. A row succeeds when `files browse` lists the name at the source's size. A 409
(exit 2, already there) counts as `skipped` when the server holds the plan size, `failed`
otherwise. Receipts: `receipts-upload.ndjson`; a re-run skips rows already ok. Prints `uploaded N,
skipped N, failed N`; exit 1 on any failure. Count `uploaded + skipped` against the new rows.

- Uploads stream with no timeout; the server refuses a file over 8 GiB (413).
- `500 The disk is full` means the server's library volume is full.
- The upload receipt's `record_id` is `null`; the id comes in phase 7.

## Phase 7: index

```bash
python3 scripts/resolve_ids.py --plan <run>
```

The server's file watcher indexes uploads about two minutes after the last one. The script polls
`files browse` for each row's `record_id` every `--interval` (20 s) up to `--wait` (900 s), writes
the ids into plan.json as `book_id` (also on failure, so a re-run continues), and on a timeout
runs one scoped `library rescan --scope <system_path> --metadata-mode new` once the scan is idle,
then polls again. Exit 2 lists the rows still without an id. A server error mid-run (a 502 from a
proxy) is recovered by re-running it once `scan-status` is idle.

- **Poll `running`, never the counters**: a loose file under `books/` counts toward `total_books`
  and is never scanned.
- **A `--scope` that matches nothing still answers `scan_started`.** The scope is the directory
  part of a book's path from the library root.
- **Read the log before calling a scan stuck.** `grimoire-cli logs` (admin; a 20 000-entry ring
  buffer) carries `Reading text from '<title>' - N page(s)…` and `Finished reading …` per book,
  the only view of progress inside an OCR job; `scan-status` stays flat for as long as one book
  takes. Diff the `Finished` timestamps for a rate. `logs --level error` is where real failures
  show. Poll with `--after-seq <max_seq>`; `max_seq` moves even when `--level` matches nothing, and
  a backlog over `--limit` is dropped.
- Rows are usable before OCR ends; only full-text search waits for it. Vector map PDFs have no
  text layer, so an import with many maps queues many OCR jobs.

**`ocr: server`**: queue the image-only rows.

```bash
python3 scripts/ocr_queue.py --plan <run>
```

It needs `ocr-survey.json` and a `book_id` on each `none` row. It waits for `scan-status` idle (a
failing status is retried, never read as idle), fires `books reindex` for every row back to back
(the first OCRs, the rest are left cleared), waits for idle, then runs one unscoped `library
rescan --metadata-mode missing`, which collects every text-less book into one server-side queue
that runs unattended. A 400 (not image-only) is recorded, not fatal. Receipts:
`receipts-ocr_queue.ndjson`, one per reindex plus a `rescan` receipt; a re-run skips rows already
ok and runs the rescan if reindexes were queued without one after them. Exit 2 on unmet
preconditions, 1 on a failed reindex, rescan or status call. Budget about 25 s per page.

- **Never use `library cancel-scan` to unstick OCR.** It restarts the whole OCR queue from zero on
  the next run; repeated cancels make no progress at all. Let it finish, then `books reindex`
  whatever was cut off.
- **A reindex fired during a running scan is silently dropped** after clearing the book's text, so
  the book has no text until something scans it again. The script waits for idle; do the same by
  hand.

**`ocr: handover`**: the files went up with their text layers. A text layer repaired outside the
server after upload goes back with `files upload --on-conflict replace` (see *Traps*).

## Phase 8: metadata

```bash
python3 scripts/apply.py --plan <run>
```

Refuses (exit 2, nothing written) without the `shelf_checked` stamp, on any open question, a row to
write without `book_id`, a `present` row without a diff, an `apply` naming a field that is not
`differs`, a dangling or chained variant parent, a parent row without an id and no `of_id`, or a new
row whose category is neither in the plan nor on the server. `skip` rows are left alone.

- **A new row (no diff) is written in full** with `books batch-update` (body key `items`, ≤1000
  per call): every metadata field and the whole tag set, **category tag first**, because
  `batch-update` replaces tags and the scanner does not write the category tag.
- **A diffed row writes only `missing` fields plus the `differs` fields its `apply` names**, and
  its `diff.tags.add` through `books batch-tag` (additive), so no shelf tag is ever removed.
- Variant links are the same run (phase 9).
- Receipts: `receipts-apply.ndjson` (steps `update`, `link`); a re-run skips rows already ok.
  Prints counts; exit 1 on row failures. A batch exit 3 is a partial write: the failed rows carry
  their own errors in the receipt.

Notes:
- `books update`/`batch-update` write `isbn`, `language` and `product_code`, which no sidecar
  carries. `updated` in the response lists ids that resolved, not fields that changed.
- **A variant family need not be retyped**: `grimoire-cli duplicates merge-metadata` copies fields
  between members. Without `--overwrite` it fills only empty fields (the rest come back in
  `skipped`); tags are additive; `--fields` takes `title`, `description`, `authors`, `artists`,
  `publisher`, `publisher_url`, `urls`, `genres`, `isbn`, `version`, `language`, `license`,
  `year`, `month`, `day`, `category`, `is_explicit`, `tags`. Exit 3 is a partial write.
- A wrong tag needs `books update` with the full intended set (`existing ∪ proposed`);
  `batch-tag` cannot remove one.

## Phase 9: variants and cross-system links

`apply.py` links each row's `variant` with `duplicates link`, ≤20 children per call, to the parent
row's `book_id` or to `variant.of_id` for a parent already on the shelf. A `same` variant sends
nothing; a `missing` one links; a `differs` one links **only when the row's `apply` names
`variant`**, otherwise it is recorded `deferred` in the receipt. A shelf link the plan does not
propose is always `deferred`, never unlinked.

- `duplicates link` **moves** a child already filed under another parent rather than refusing.
  That is why `differs` is gated.
- `duplicates groups` proposes `kind` and `label` per member; read it before inventing either.
  Kinds are a closed set per collection; book variants refuse map kinds such as `gridded` (use
  `other` with a label). Labels are trimmed to 120 characters without warning. `link` also takes
  `parent_kind`/`parent_label` (both `""` = "Main version"); the script does not send them.
- To drop one child, `duplicates unlink --resource-type book --ids <child id>`. **Never
  `--parent-id`**, which frees every variant of that parent.
- `duplicates promote` swaps which member is the parent.
- **A book that belongs on a second system's shelf**: `grimoire-cli books links add --id <book>
  --system-id <system>`. One file and one row, listed on both shelves; category, tags and access
  come from the book. 400 for its own system, a variant (link its main version), or a role-playing
  book onto a wargame system. Companion material is a `for:` tag (profile *Tags*), not a link.

## Phase 10: settle

```bash
python3 scripts/readback.py --plan <run>
```

Reads the shelf back against the plan: per row with a `book_id`, title/year/publisher/licence as
the plan says (on a diffed row only the fields that were written) and every plan tag present; per
parent, `variant_count` equal to the planned children for a new parent, at least that for one
already on the shelf. Entries come from `systems get` (a plan entry missing there is reported
`not a parent`), children from `books get`. Exit 1 lists every mismatch, 2 when the system cannot be
resolved. **Count rows, not entries**: `systems get` and `books list` return parents only; `files
browse` lists every file with its `record_id`, and `books get --id <parent>` carries `variants[]`.

**System metadata.** A new folder creates a system with only its name; the edition is derived from
the folder name, and a value set with `systems update` survives a rescan. `plan.system` goes on
with:

```bash
python3 scripts/system_meta.py --plan <run>
```

It resolves the system from the first row's book, sends one `systems update` (`dice` goes as
`dice_materials`) and copies the cover with `systems cover from-source --source-type book` from
`cover_book_target`, then writes `system_id` into plan.json. **It overwrites without a diff**, so
run it directly only for a greenfield system. For an existing system, first show `grimoire-cli
systems get --id <id> --include-books false` values beside `plan.system` and get the user's yes.
`system_family` is not in its keys: set it with `systems update` directly.

- The system's metadata ladder: the folder (edition, language; never overwrite), the system's own
  core book in-file (edition, year, publisher, ISBN), the publisher's site in that language, a web
  lookup, then a wiki add-on for line-level facts only.
- **An uploaded system cover beats `cover_book_id`.** Setting `cover_book_id` changes nothing once
  a cover was uploaded; use `systems cover from-source`. A book whose page 1 is tiny renders a
  fine thumbnail but is too small as a system cover: upload a proper image instead.
- Renaming a system (`name`) marks it custom forever; the scanner never re-derives it.

Finally, update the user's library notes **in place** (wherever they keep them, e.g. a
library-state document): the new inventory and every imperfection the run knowingly left behind.
Never write a dated handover document.

## OCR quality

`python3 scripts/ocr_quality.py [--markers a,b,c] <dir>…` scores each PDF's text: `garble%` (word
tokens showing scan damage: a digit inside a letter run, an internal case flip, a junk character;
digital PDFs sit near 0.2%, 1.4% or more is a fair bar for re-OCR; dice and stat codes are not
counted) and `frag%` (one-letter tokens). `--markers` lists characters your language uses often
and adds a per-1000-letters column that catches a wrong-language OCR model. The readings only work
together:

| reading | means |
|---|---|
| high garble, many digit hits | often not damage: tables, stat blocks and map legends are letter+digit tokens |
| low garble, very high frag% | shattered text, letters split into tokens; unsearchable, and garble cannot see it |
| near-zero marker density on text in that language | the wrong OCR language model |

- **Garble undercounts shredded text.** Cross-check with the share of tokens that are the
  language's common function words (for English *the, of, and, to, in, a …*; roughly a third of
  real prose): clearly lower means garbage. A word count that moves a lot between two OCR passes of
  the same pages is the other tell. Ghostscript merges fragmented text objects, which improves any
  per-word metric without changing a character.
- **Read `pdfinfo`'s `Producer` before the score.** `… with ClearScan`: the page was redrawn in
  synthesised fonts with an approximate Unicode map, so the page can be flawless while the text is
  garbage (the index is still poor, which is a separate problem). `Paper Capture` without ClearScan
  keeps the scan under an invisible text layer, so the score means what it says. Mixed producers
  across one corpus usually mean an earlier OCR pass skipped some files.
- **Raster resolution is a ceiling no OCR setting lifts.** `pdfimages -list` gives the ppi; at
  72 ppi only a better scan helps.
- Letter-spaced text layers (`T h e  s t a r s`) need OCR too.
- Renders settle what numbers cannot: `pdftoppm -f N -l N -r 100 -jpeg` and look at the page.
- Encrypted PDFs index fine. Two-up scans halve `page_count`.

## Traps

- **`files browse` caps at 2000 entries** and leaves sidecars (`.opf`, `.nfo`, `.grimoire.yaml`) out
  of both the listing and `total`. Read `truncated`.
- **`--category` is the normalised value and case-sensitive** (`supplement`, never `Supplements`;
  `Core` matches nothing), in `books list` and `systems get` alike. `--genre` is not.
  `systems get --category X` makes `book_count` the filtered count.
- **A system is matched by slug, never by its folder leaf.** The server names a child system
  `<parent leaf> <leaf>`; the slug is the path below `books/` with each segment slugified and joined
  by `--`, a dot dropped (`2.5 EN` → `25-en`). The derived name collapses ` - ` and hyphens
  (`Star-Fall` → `Star Fall`).
- **`books update` clears with `""`; `null` is a no-op**; `year`/`month`/`day` cannot be cleared.
- **`jq 'select(.isbn)'` counts `""` as present.** Use `select(.f != null and .f != "")`.
- **`books list` omits `language` and `tags`**; `systems get` has no `variants[]`; `books get`
  answers `relative_path: null` where `systems get` carries the path.
- **Count tags with `tags items` `.total`** (it pages at 100), never `.items | length`. Tag counts
  include parents only: a variant child carrying the tag is in neither `tags list` nor `tags items`.
- **`systems list` hides children before filters**; pass `--include-children` (`--parent-id`
  implies it).
- **Search:** any `field:` filter switches page-text search off, `text:` switches it back on; an
  unknown prefix is searched literally rather than refused. `results` holds page-text hits,
  `book_matches` title/metadata hits, so a `tag:` query has an empty `results` by design. Every
  array is capped at 50. Repeated `tag:` terms widen (OR).
- **`books rescan` is PDF-only** (400 on EPUB, 404 if the file is gone) and rebuilds a book from its
  current text layer without OCR. A library scan running makes it a silent no-op, and a running
  `books rescan` blocks a `library rescan` started right after; every call still answers
  `rescan_queued`. Poll `scan-status` between calls.
- **Replacing a shelved file**: `files upload --on-conflict replace` overwrites an indexed book in
  place and keeps its id, refreshes `file_size` and re-indexes on its own. That re-index counts as a
  scan, so a second replace straight after gets 409: wait for `running: false` between replaces.
  Delete-then-upload loses tags and favourites. **A good text score does not prove the page is
  intact**: before swapping a re-OCRed file in, compare page ink against the shelf copy
  (`pdftoppm -r 12 -gray`, share of dark pixels, top vs bottom half); the same check finds pages
  stored upside down.
- **`files move` and `files rename` keep metadata and the book's system**; check the system's
  `book_count` before and after. A rename on the storage itself strands the row and its API-only
  fields.
- **`files delete` is soft**: index entries go, files stay, and a rescan re-adds them as new rows
  without their tags. `--delete-files` is irreversible and needs `--confirm-name` for a non-empty
  folder.
- **Refused formats under `books/`** are the profile's `refused_book_formats` (`'.x' is not a file
  type this part of the library indexes`). Convert in the run dir, never the source: an office file
  to PDF (`soffice --headless --convert-to pdf`, or Pages on macOS), a TIFF to PNG with identical
  pixels. RTF and EPUB index as they are.
- **The plan's `source` must be the bytes on disk.** A source filename can carry raw control bytes
  (CP437 where an accented letter belongs). Sanitise only for matching against a catalogue title.
- **Thumbnails are a cache.** `has_thumbnail: false` means the render is missing, never the content.
- **A container cannot hold books.** A folder that holds books is a system.

## Deferred

- A metadata sweep over an already-imported shelf (the read-only half is `audit-library`).
- Sidecar (`.opf`) writing: everything here goes through the API. If a library keeps sidecars, the
  sidecar is edited and then `books update` writes the same value; never a `--metadata-mode replace`
  rescan. Sidecar tags are all-or-nothing under `missing`.
- Automatic defect correction, permanently.
- Parallel uploads: sequential is fast enough and keeps failures attributable.
