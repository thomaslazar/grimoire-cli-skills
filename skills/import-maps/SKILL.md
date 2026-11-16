---
name: import-maps
description: >-
  Use when importing battle maps, dungeon maps, map packs or map-asset packs (PNG/JPG/PDF/zip)
  into Grimoire's maps library. Triggers: "import these maps", "add this map pack", "where do
  these maps go". NOT for a book's own maps or a setting's region maps (→ import-books, they stay
  on the books shelf), NOT for audio (→ import-audio).
metadata:
  grimoire-cli-groups:
    - maps
    - files
    - library
    - duplicates
  min-cli: "0.8.0"
  min-server: "1.11.0"
---

# import-maps

Takes a folder of map files and leaves one product folder in `maps/`. In that folder, each map is
one entry, its other renderings are variants of it, and every row carries tags for what is on the
map. Sibling of `import-books` and `import-audio`; its principles apply: the source folder is
read-only, the walkthrough is a hard stop, scripts refuse instead of warn, and long runs should keep
the machine awake. The rules are the profile's section *Maps, tokens, models and audio* (plus
*Variants and the entry* and *Tags*); this skill is how to apply them. Print the resolved profile and rule files (`profile_dir`, `rules`). Run it from your library repo (the current directory), with the script path resolved from this skill's folder: `python3 <skill folder>/../../lib/grimoire_skills/config.py`. Script paths are resolved from this skill folder; the working directory stays your library repo.

## First decision: is it a map at all?

Decide this before anything else.

| the files are | they go to |
|---|---|
| a book's own maps, handouts, tokens | **books shelf**, beside the book in `Maps/`, `Handouts/`, `Tokens/` → `import-books` |
| a publisher's map set that ships with that publisher's book | **beside the book**, even if the book never mentions them: a publisher's material stays together |
| a map set with adventure content (random tables, keyed rooms, a mini adventure) | **books shelf**, `Adventures/`, maps in `Maps/` → `import-books` |
| a setting's region or city maps | **that edition's books shelf**, `Maps/` → `import-books` |
| system-independent battle/dungeon maps, no other content | `maps/<Publisher>/<Product>/` (this skill) |
| map-asset stamps (props, furniture, blood) | `maps/<Publisher>/<Pack>/`, one zip per pack and resolution (this skill) |
| map-making tools | ask the user |

**Source sorting is unreliable.** An archive or folder name is a hint, never proof: a "No Grid"
folder can hold night maps under day names, and an archive can hold another product's maps. Render a
contact sheet (ImageMagick `montage`, or any thumbnail tool), open the files, and state the evidence
in the walkthrough.

## Phases

1. **Preflight.** `grimoire-cli me` (admin); `grimoire-cli library scan-status` idle. Everything
   goes through the server; never read the library's storage directly. Run dir
   `tmp/import-maps/<YYYYMMDDTHHMMSS>-<slug>/`.
2. **Survey.** List every file with its pixel dimensions and size. Extract archives **in the run dir
   only**. Look at every image. Work out the families: one map, all its renderings. Filename
   suffixes vary per publisher (plain = square grid, `hex`, `ng` = no grid, `_day`/`_night`); prove
   each suffix by eye on one family.
   Then run `python3 scripts/transparency.py <run>/x` on the extracted images. It lists every map
   with a transparent background (`transparent_share`) and how dark its visible pixels are
   (`visible_luma`, 0 = black). Grimoire's viewer is dark, so dark line art on transparency shows as
   almost nothing. **Offer an opaque copy in the walkthrough** for every hit; tokens and stamps stay
   transparent. On a yes, `--flatten <run>/flat` writes beige (`F2E8D5`) copies. Needs Pillow
   (`python3 -m pip install Pillow`).
3. **Identify.** Find the publisher and product: the shop it came from first, then the creator's own
   page. Follow the identify method in `import-books` (use whatever web access your agent has; for
   sites that refuse bots, a browser-automation CLI such as agent-browser or Playwright). Read any
   text printed on the maps (names, hints, legends). If the user has an order for lookups, it is in
   their overrides.
4. **Plan.** Write `plan.json` with a small `plan.py` in the run dir (shape below). Then run
   `python3 scripts/publish_maps.py --plan <run> --check`, which validates
   the plan (variant kinds against the profile's `map_variant_kinds`, targets, tags, sources) and
   writes nothing. Every source file must be used or excluded with a reason: assert that none is
   left over.
5. **Walkthrough (HARD STOP).** Show the user, in the console and never as an artifact:
   - the shelf decision from the table above, with its evidence;
   - the transparent maps, with the offer of opaque copies;
   - the folder layout;
   - one line per family: the entry and its variants with kind and label;
   - the tags per entry;
   - every rename, with its reason;
   - every exclusion, with its evidence.

   Do not continue without an explicit "proceed".
6. **Publish.** `python3 scripts/publish_maps.py --plan <run>` (on macOS, prefix long runs
   with `caffeinate -i`). The CLI is found from `--cli`, then the
   `cli` key of `grimoire-skills.json`, then `PATH`, then `./bin/grimoire-cli`. The script also
   publishes a `tokens/` plan; `import-tokens` uses it. Exit 3 means some rows failed verification:
   read `receipts/publish.json`. For very large packs, split the plan and upload in batches of about
   1 GB.
7. **Settle.** Check the result against the plan with `grimoire-cli maps folder-counts` and
   `maps list --folder …`, then record the run wherever the user keeps library notes.

## plan.json

```json
{"root": "maps/Example Press",
 "rows": [
  {"source": "/abs/source/Forest Pack/Camp_ng.png", "target": "Forest Pack/Forest Camp.png",
   "description": "Forest Camp, a battle map from Example Press's Forest Pack.",
   "tags": ["map", "example-press", "battlemap", "outdoor", "forest", "camp", "gridless"],
   "variant": null},
  {"source": "/abs/source/Forest Pack/Camp.png", "target": "Forest Pack/Forest Camp - Square Grid.png",
   "description": "Forest Camp, a battle map from Example Press's Forest Pack.",
   "tags": ["map", "example-press", "battlemap", "outdoor", "forest", "camp", "grid"],
   "variant": {"of": "Forest Pack/Forest Camp.png", "kind": "gridded", "label": "Square grid"}}]}
```

- **The filename is the map's only name.** The maps API cannot set a title. Write plain names, with
  the rendering after ` - ` (`Forest Camp - Night - Hex Grid.png`).
- **Entry** = the gridless day rendering. If none exists, use the plainest one.
- **Variant kinds** come from the profile's `map_variant_kinds` (default: `gridded`, `gridless`,
  `black-and-white`, `printer-friendly`, `universal-vtt`, `version`, `other`); the check rejects any
  other. Label each variant (`Night`, `Snow`, `Print PDF`, `Large`). A bigger copy of the same map
  is a `version`; a print rendering is `printer-friendly` or `other` labelled `Print`.
- **A flattened copy is the entry** and keeps the plain name; the transparent original becomes
  `… - Transparent.png`, an `other` variant labelled `Transparent`, tagged `transparent`.
- **Tags**: start with a publisher slug and `map`, then what is on the map, read off the image,
  using the profile's vocabulary: kind, setting, terrain, place, features, grid, style. A variant
  carries its entry's tags plus what its rendering adds (`night`, `grid`, `print`). Generic tags
  alone are a defect: the user must be able to find "a night forest camp" by tags. Add any
  provenance tag the user's overrides require.
- **Descriptions**: one sentence that names the map and the product. A hint printed on the map goes
  into the description.
- **Asset packs**: one zip per pack and resolution, built in the run dir. Tag it `map-assets` plus
  the theme of its contents. The VTT zip is the entry, the print zip an `other` variant.
- PDFs and zips index in `maps/`. PDFs get a thumbnail; zips get none.
- Reading back: `maps list` takes `--query`, `--tags` (JSON), `--folder`, `--favorites`,
  `--added-since`, `--sort`, `--order`, `--limit`; the response key is `maps`, not `items`.

## Traps

- **The watcher indexes uploads about 75-120 s after the last one.** The script polls
  `files browse` `record_id`, then falls back to one scoped rescan. Do not rescan straight away.
- **A thumbnail is missing over ~179 megapixels** (Pillow's decompression-bomb guard). This is not
  damage; record it.
- **`files upload --on-conflict replace` swaps a map's file in place** and keeps its id, tags and
  description. `--on-conflict skip` answers 409 and exit 2 for a file already there; count it as
  present.
- **Linking a variant to a shelf entry** needs `grimoire-cli duplicates link` with
  `resource_type: map` outside the script, which links only within its plan. A linked row drops out
  of `maps list` (parents only), so a link script that resolves ids from that list is safe to re-run
  after a partial failure.
- **Zip member names stored as UTF-8 without the UTF-8 flag** read as CP437 in Python
  (accented names come out as mojibake): re-decode with `name.encode("cp437").decode("utf-8")` before matching.
- **`maps batch-update` replaces tags.** The script uses it only on rows uploaded in this run; rows
  that already exist get the additive `batch-tag`.
- **Repeated `tag:` terms in `search` widen (OR).** Verify a tag set with `maps list --tags`.
- **`tags list` counts are not row counts.** Count with `maps list`.
- `.aftemplate` and other tool formats are refused. Exclude them with the reason.
