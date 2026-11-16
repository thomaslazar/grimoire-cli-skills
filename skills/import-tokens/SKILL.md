---
name: import-tokens
description: >-
  Use when importing VTT token packs (round-framed creature/NPC portraits, PNG) into Grimoire's
  tokens library. Triggers: "import these tokens", "add this token pack", "where do these tokens
  go". NOT for a book's own tokens (→ import-books, they stay beside the book in Tokens/), NOT for
  maps or map-asset stamps (→ import-maps).
metadata:
  grimoire-cli-groups:
    - tokens
    - files
    - library
    - duplicates
  min-cli: "0.8.0"
  min-server: "1.11.0"
---

# import-tokens

Takes a token pack and leaves it in `tokens/<Creator>/<Pack>/<Creature>/`, one row per token, each
with a clean filename, a one-line description and tags for creator, pack and creature. Sibling of
`import-maps`, whose principles hold: read-only source, extraction only in the run dir, a hard-stop
walkthrough, long runs kept awake, verify through the server. The upload, wait, tagging and
read-back are `import-maps`' `publish_maps.py`, which reads the collection off the plan root. This
skill adds what tokens need and maps do not: sorting tokens from raw art, and naming files that come
out of an AI pipeline. Script paths are resolved from this skill folder; the working directory stays your library repo; `publish_maps.py` lives in
`../import-maps/scripts/`. The rules are the profile's section *Maps, tokens, models and audio*
(plus *Variants and the entry* and *Tags*); print the resolved profile and rule files with
`python3 ../../lib/grimoire_skills/config.py` (`profile_dir`, `rules`).

## First decision: is it a token pack?

| the files are | they go to |
|---|---|
| a book's tokens (its monsters, NPCs) | **beside the book**, `Tokens/` → `import-books` |
| a standalone token pack | `tokens/<Creator>/<Pack>/` (this skill) |
| props, furniture, blood stamps for map-making | `maps/` asset zip → `import-maps` |

## What Grimoire does with tokens

| fact | consequence |
|---|---|
| Same metadata surface as maps: `description`, `tags`, `is_explicit`; no title | the filename is the token's only name |
| `files browse` carries `record_id` and `collection: tokens` once indexed | ids resolve exactly as for maps |
| `tokens batch-update` replaces tags, `batch-tag` adds | as for maps; the script handles it |
| Variant kinds `black-and-white`, `color-variation`, `version`, `other` | a colour and a b/w pack with different art are **not** variants; only link the same art |
| The watcher indexes new tokens inside a full-library scan, which can take minutes | expect the wait; do not rescan early |
| `files upload --relative-dir` creates missing folders, several levels deep | no folder-creation step needed |
| `tokens/` takes zips (indexed, `is_archive: true`, no thumbnail) | a pack's raw art can ride along as one zip |
| `tokens list --limit 100000` returns every token with tags, description and `relative_path` in one call | verify in bulk; `tokens get` per row is far slower |
| `tokens list` takes `--query`, `--tags` (JSON), `--folder`, `--sort`, `--order`, `--added-since`; the response key is `tokens` | |

## Phases

1. **Preflight.** `grimoire-cli me` (admin), `grimoire-cli library scan-status` idle. Run dir
   `tmp/import-tokens/<YYYYMMDDTHHMMSS>-<slug>/` (or the parent import's run dir).
2. **Extract** every archive into the run dir (`unzip`, or `ditto -x -k` on macOS). Hash all files
   (`shasum -a 256`, or `md5 -r`) for byte twins, within and across packs; two downloads of one pack
   are common.
3. **Draft** per pack (needs Pillow: `python3 -m pip install Pillow`):
   ```bash
   python3 scripts/draft_tokens.py --pack <run>/x/<pack> \
     --target "<Pack>" --tags token,<creator-slug> --title "<Creator>'s <Pack> (<source>, <year>)" \
     [--rename "Old=New" ...]  > <run>/<pack>.json
   ```
   It splits tokens from raw art (a token is a square RGBA ≤512 px with a transparent corner),
   cleans names, numbers them and tags each token with its name and folder slug. Read its three
   outputs:
   - `art`: everything that is not a token. **Render a contact sheet and look.** Packs often hold raw
     generated images (406-2048 px, no frame, some 2×2 grids) among the tokens.
   - `unnamed`: files with no name of their own (`9.png`, `token_7.png`) that took their folder's
     name. Look at each; if the folder name does not describe it (a mixed `Pack 01/`), name it
     `Token NN`, never an invented creature.
   - the folder names: creator typos (`Owlbaer`) are fixed with `--rename`, and stated.
4. **Plan.** Merge the drafts into one `plan.json` per creator (`{"root": "tokens/<Creator>",
   "rows": [...]}`) with a small `plan.py` in the run dir. Add the art zip row if the user wants it.
   Every extracted file must be a row, inside the art zip, or excluded with a reason.
   `python3 ../import-maps/scripts/publish_maps.py --plan <run> --check` validates (`--plan` takes the run dir or the plan file; the run dir defaults to the plan's folder).
5. **Walkthrough (HARD STOP)**, in the console: layout with counts per folder, the naming rules
   with examples of every rule that fired, renames, the `unnamed` list, tags, the raw-art decision
   (zip / leave out / loose), exclusions with evidence. Wait for "proceed".
6. **Publish**: `python3 ../import-maps/scripts/publish_maps.py --plan <run>`
   (on macOS, prefix long runs with `caffeinate -i`). Pass `--cli` as an absolute path when the working
   directory is not the one holding `./bin/grimoire-cli`.
7. **Settle.** Compare `tokens list --folder …` and `tokens folder-counts` with the plan, then
   record the run wherever the user keeps library notes.

## Names and tags

- `<Name> NN.png`: `_Token`/`Token` dropped, `_` → space, two-digit number. The **source number is
  kept**: an `Extra/` set whose `Aarakocra_Token_6-13` continue the main pack's 1-5 stays 06-13.
- A name that occurs once without a number stays bare (`Owlbear.png`).
- Layout mirrors the creator's folders, brackets stripped. A flat extra set gets one folder per
  creature (`Extra/<Creature>/`), so a creature is together there too.
- Tags: `token`, the creator slug, `black-and-white` for a b/w pack, `ai-generated` when the
  product's own page or files declare the art AI-generated, then the creature name and folder
  (`chest-mimic`, `mimics`). The user finds "a mimic token" by tag. Add any provenance tag the
  user's overrides require.
- Description: `<Name NN>, a token from <Creator>'s <Pack> (<source>, <year>).`

## Traps

- **`files upload --on-conflict skip` answers 409 with exit 2** for a file already there; count it as
  present, not failed.
- One `files upload` per file, about 0.35 s each, so thousands of tokens take many minutes. Run it
  unattended and kept awake. The size check after each upload adds one
  `files browse` per file.
- `files browse` truncates a folder at 2000 entries, so keep creature folders below that.
