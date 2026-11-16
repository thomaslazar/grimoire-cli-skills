---
name: import-audio
description: >-
  Use when importing background music or soundtrack albums into Grimoire's audio library — any MP3
  album meant for play at the table. Triggers: "import this soundtrack", "add this album to
  Grimoire", "import this background music". NOT for books or the PDF booklets that ship with an
  album (→ import-books), NOT for audiobooks, radio plays or novels (not table audio), NOT for
  installing the CLI (→ install-grimoire-cli).
metadata:
  grimoire-cli-groups:
    - audio
    - files
    - library
  min-cli: "0.8.0"
  min-server: "1.11.0"
---

# import-audio

Takes one or more album folders of MP3s and leaves them in `audio/` with clean filenames,
complete ID3 tags, an embedded cover, and Grimoire tags that tie each track to the books it
belongs with. Sibling of `import-books`, and deliberately separate from it: audio has its own
library root, no systems or categories, a different metadata surface, and one step books never
need, writing tags into files. The rules are the profile's section *Maps, tokens, models and
audio* (plus *Tags* and *Metadata*); this skill is how to apply them. Print the resolved profile and rule files (`profile_dir`, `rules`). Run it from your library repo (the current directory), with the script path resolved from this skill's folder: `python3 <skill folder>/../../lib/grimoire_skills/config.py`. Script paths are resolved from
this skill folder; the working directory stays your library repo. ffmpeg and ffprobe are required.

## What Grimoire does with audio

Every rule below follows from one of these measured facts. Re-probe with two tracks after a
server upgrade.

| fact | consequence |
|---|---|
| **Audio lives in its own root, `audio/`**, beside `books/` | a track can never sit on a book's shelf |
| **Container markers are refused** under `audio/` | folders are plain; there is no system link at all |
| **The list groups by folder**: first folder under `audio/` = group, the rest of the path = the heading, joined ` / ` | the folder tree is the browsing structure; keep it shallow |
| **Headings are reformatted**: ` - ` dropped, every word title-cased | UI behaviour, nothing to do |
| **The list and the details page show ID3**: title, track number, album, artist; the thumbnail is the embedded artwork | ID3 has to be complete, or the row is blank |
| **An untagged file gets `title: ""`**, with no fallback to the filename | tag it |
| **The API writes only `description` and `tags`** for audio; title, album and artist come from the file | fixing a title means changing the file, hence the tagged-copy step |
| **Folder tags do not match `tag:` search**; per-track tags do | tag every track, never only the folder |
| **Search covers audio** in its own `audio` array, so a tag shared with books returns both | `for:` and `region:` on a track put it in the book family's search |
| **WAV tags are not read** | convert to MP3 first |
| `audio folders set` records are never removed, even when the folder is deleted | a folder-tag typo is permanent; avoid folder tags |

The `NN - Title.mp3` filename is a convention, not the display title: it keeps files in order when
browsing and sorts a folder by path.

## Principles

Those of `import-books`: read-only source, one network phase, names right before the first write,
scripts refuse rather than warn, a hard-stop walkthrough, defects surfaced rather than silently
corrected. Plus:

1. **Bytes change only in copies, and the audio never does.** A track whose tags need writing is
   copied into the run directory with `ffmpeg -c copy`; the source is never touched.
   `stage_audio.py` proves every copy's raw audio frames hash equal to the source's. A track that
   needs no change is a symlink.
2. **The artifact's wording wins; a lost character does not.** Where the file carries the
   publisher's own ID3 title, keep it, even when a catalogue spells it differently and even when a
   dash is missing. But `Baldurs Gate` for *Baldur’s Gate* is a character the publisher's tagger dropped: fix it
   from the catalogue, in title and filename, and name it in the walkthrough.
3. **A rip's tags are not the artifact.** Principle 2 is about a publisher's own tags. A CD rip was
   tagged by whoever ripped it. A comment such as `ripped by …` or `only for <group>`, Title-Cased
   titles, a `NN - ` baked into the title, and an artist like `no artist` give it away. There the
   CD's own tracklist wins: a back-cover scan first, else the catalogue. A plain catalogue typo
   loses to the rip. Such rows get `"clean": true`, so none of the ripper's tags survive.
4. **Titles in the library's default language.** When a release carries tracklists in several
   languages, use the library's default language where a title exists in it, and the original only
   where none does. Say which in the walkthrough. Overrides may make an exception for works of one
   origin.
5. **A series' functional marker stays in the title.** A `(L)` for a loop or `(E)` for event music
   tells the GM whether to put a track on repeat.
6. **A CD with no titles gets `Track NN`.** Never invent one.

## Inputs

- **Album folders** (read-only), typically a shop download: `Example Soundworks [EX1234] Forest
  of Echoes (MP3)/` with `NN Title.mp3` files, a booklet and/or inlay PDF, maybe a cover image.
- **A catalogue source** for the line, when the files lack tags: a publisher or shop page, a wiki,
  or the album's own back cover.

## Phase 0, preflight

```bash
grimoire-cli me | jq -r .role                    # admin
command -v ffmpeg ffprobe                        # required: tagging and every check
grimoire-cli library scan-status | jq .running   # false, or wait
run_dir="$(mktemp -d)"; mkdir -p "$run_dir"/{receipts,stage}
```

## Phase 1, survey

For every file: `ffprobe -show_format -show_streams` gives duration, bitrate, **every ID3 tag, and
whether a picture stream exists**. Record per album whether it is **tagged** (take its tag shape as
the model) or **untagged** (every field has to come from a catalogue). Classify the non-audio
files: booklets and inlays are books; a cover image is either the art already embedded (compare
dimensions) or the cover source for an untagged album.

**Source filenames are untrustworthy**: archives unpacked on another system drop accented
characters and can hold a private-use character where a bracket belonged. Resolve sources from the
directory listing itself, never from a retyped name.

## Phase 2, identify (the only network phase)

Find the tracklist, album title, artist, year and parent product for each album:

- **The tracklist** corrects spellings on an untagged album and is the check against a tagged one.
  **Check a borrowed tracklist against the files' durations** before trusting its order: some
  files carry no track numbers and titles like `Track`.
- **The front cover is a source** for spellings and credits, including a credit for one track
  that a catalogue lists for the whole album.
- A **back-cover scan** in the source folder beats a catalogue (principle 3).
- Two takes with one name (vocal and instrumental) can be told apart by band-limited loudness
  (`highpass=300,lowpass=3400,volumedetect`): the vocal take reads louder; calibrate on a labelled
  pair from the same album.
- The **parent product** says which book family the album belongs to (the `for:` tag).

## Phase 3, plan

**Layout**: `audio/<Line>/<Series>/<NN> <Album>/<NN> - <Title>.mp3`, e.g.
`audio/Example Soundworks/Echoes/09 Forest of Echoes/03 - The Quiet Vale.mp3`. It renders as group
*Example Soundworks*, heading *Echoes / 09 Forest of Echoes*. `<NN>` for the album is the series
number. Do **not** mirror the books tree (system and edition folders): under `audio/` it carries
no meaning and only lengthens every heading. An album in **no numbered series** goes under
`Soundtracks/<YYYY> <Album>/`; the release year orders them and a local number would be invented.
`:` in a title becomes ` - ` in the filename; a `/` is refused, so use the rip's ` - ` form.

**Duplicate albums**: hash the raw audio frames (as `stage_audio.py` does). Two rips of one CD never
match byte for byte, so compare duration and bitrate too, and keep the best MP3. WAV masters are
unmeasured.

**ID3 for an untagged album copies a tagged sibling field for field.** A model:

| field | value |
|---|---|
| `title` | tracklist |
| `album` | album title |
| `artist`, `composer` | credited artist |
| `album_artist` | the series |
| `genre` | `Soundtrack RPG` |
| `track` | zero-padded, no total: `01` |
| `date` | release year |
| `comment` | the shop product name |
| cover | embedded front cover, up to ~1080 px square; never enlarge a smaller one |

**Grimoire tags per track**: `soundtrack`, the series slug, `for:<parent code>` (the profile's
companion tag; a parent with no code takes a slug) and `region:<slug>` where the book family has
one. Transliterate accents, as in every tag.

`plan.json`:

```json
{"root": "audio/Example Soundworks",
 "rows": [{
   "source": "/path/to/album/01 Forest Edge.mp3",
   "target": "Echoes/09 Forest of Echoes/01 - Forest Edge.mp3",
   "title": "Forest Edge",
   "write": {"title": "Forest Edge", "album": "Forest of Echoes", "artist": "Jane Composer",
             "album_artist": "Echoes", "composer": "Jane Composer", "genre": "Soundtrack RPG",
             "track": "01", "date": "2021", "comment": "Example Soundworks [EX1234] Forest of Echoes"},
   "cover": "/path/to/album/cover.jpg",
   "tags": ["region:greenmarch", "soundtrack", "echoes", "for:es005"],
   "description": "A short blurb from the album page.",
   "expect": {"album": "Forest of Echoes", "artist": "Jane Composer", "artwork": true}}]}
```

`"clean": true` drops every tag the source carries before `write` is applied, and `stage_audio.py`
fails the copy if any other tag survives. Use it for rips, and whenever a source holds an `encoder`
tag, which the encoder-stamp check would otherwise fail on. `write` empty and `cover` null gives a
symlink. A tagged track with a lost-character fix carries only `{"title": …}` in `write`;
everything else it has is kept. `expect` is what `publish_audio.py` reads back. Invent no
`description`: leave it out when the source has none.

## Phase 4, walkthrough (HARD STOP)

Ordered by cost to reverse: layout and filenames; which tracks become copies and why; every title
that differs from the artifact, with the reason (lost character, untagged, or a rip); the ID3 value
table; the Grimoire tags; each album's track list as it will display; defects; **every excluded
file with its evidence**; what gets written. Do not proceed without an explicit "proceed".

## Phase 5, stage

```bash
python3 scripts/stage_audio.py --plan "$run_dir/plan.json" --run-dir "$run_dir"
```

Builds `$run_dir/stage/tree/`. Exit 2, refused, on a missing source or cover, a duplicate or
escaping target, or a title holding `/`. Exit 3 if any copy fails a check: audio frames not
identical, a written tag not reading back, an `encoder` stamp, or a requested cover not embedded.

Two ffmpeg details the script already handles:
- **`-fflags +bitexact`**, or ffmpeg stamps `encoder: Lavf…` into every copy.
- **The identity check strips tags and the Xing frame before hashing**
  (`-map_metadata -1 -id3v2_version 0 -write_id3v1 0 -write_xing 0`). Without that every retagged
  copy looks altered.

## Phase 6, publish

```bash
python3 scripts/publish_audio.py --plan "$run_dir/plan.json" --run-dir "$run_dir"
```

`--cli PATH` overrides the CLI. The script creates missing folder levels, uploads, **checks every
target's size on the server** (`files browse`; skills never read the library mount), runs one scoped
rescan polled until it is idle, resolves ids by `relative_path`, writes tags and descriptions, and
reads every track back. Safe to re-run: an existing file answers 409 (exit 2) and is counted
`skipped`, not failed, and a skipped track gets only additive `batch-tag`, because
`audio batch-update` *replaces* tags and is used only on tracks uploaded in this run. A re-run over
imported tracks reports `uploaded 0, skipped N, verified N`. Exit 3 means a row failed read-back;
the failures are on stderr.

## Phase 7, companions and settle

- **Booklets and inlays are books.** Put them through `import-books` onto the shelf of the product
  they belong to, with the same `for:`/`region:` tags, so the booklet and the tracks come up
  together.
- **Out of scope, say so and stop**: audiobooks, radio plays and narrated stories. They are not
  table audio.
- Record what was imported wherever the library keeps its state.

## Traps

- **Hard-delete a probe track before re-uploading it.** A move keeps the old, untagged file;
  `files delete --delete-files` on a file needs no `--confirm-name`.
- **`audio list` has no page cap by default**: pass a large `--limit`, and match `relative_path`
  with NFC on both sides. It also filters: `--folder` (one exact folder, not a subtree),
  `--query 'album:"…"'`, `--added-since`, `--sort`. `--sort track` gives album order (disc, track
  number, name) within each folder, the quick check that track numbers landed.
- **Do not `audio folders set`** unless you mean it permanently (see the table above).
- **Resizing a cover can enlarge it.** Read the size first and shrink only above ~1080 px. Pick the
  largest front among the embedded art, the source images and the catalogue's cover, and look at a
  contact sheet: files named `CD.jpg` are disc labels. Use Pillow (`python3 -m pip install Pillow`)
  or any image tool for resizing.
- **Old ID3v2.2 files keep composer under `tcm`**, not `composer`: ffprobe reports the raw key.
  Read both, or a `clean` copy silently loses the credit.

## Limits

- **Other audio formats.** Only MP3 has been measured.
- **Tests** live in `scripts/tests/` (`run_all.sh`) and use the repo's shared `tests/lib` helpers.
  The `stage_audio.py` tests run real ffmpeg on generated fixtures and print `SKIP` when it is not
  installed.
