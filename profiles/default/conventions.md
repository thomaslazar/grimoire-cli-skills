# Library conventions (default profile)

This layout is **opinionated**. It is one coherent way to shelve a tabletop RPG library in Grimoire,
chosen so the tree stands on its own and sorts sensibly. You do not have to adopt it as is. Point
`grimoire-skills.json` at your own rules: `overrides` names a folder whose `*.md` files are read
after this one (prose overrides add to these rules and win where they conflict), and its
`profile.json` merges over this profile's `profile.json` key by key (lists replace, they are not
appended). `lines` names a folder of per-line notes and `ocr` is `server` or `handover`.

Requires a Grimoire server and `grimoire-cli` that support `files folder scaffold`, variants and
`product_code`.

## Goal

The library is for playing from. Structure and titles come first; exhaustive metadata is filled in
over time. **The filesystem is the artifact**: the tree must make sense if Grimoire is replaced, so
filenames are fixed properly even though a title in metadata would hide an ugly one in the UI.

- Redundant tokens come off, because the path already says it. A map under `Maps/` needs no `MAP` in
  its filename. Build noise (`final`, `_web`, `v02-20190730`) describes a production step, not the
  content, and goes too.
- Suspected filename defects (dropped diacritics, transliterations) are surfaced to the user, never
  auto-corrected by a general rule.

## Layout

    books/[<Family>/]<Line>/<Edition> <LANG>/<Category>/[<Grouping>/]<file>

- `<Family>/` is optional and carries `.system-family-container`; use it when a family has several
  lines.
- `<Line>/` carries `.parent-system-container`.
- Both markers are written by `files folder create --container-kind family|parent`, so the whole tree
  can be built over the API.
- `<Edition> <LANG>` names the system (`2 EN`, `Revised EN`). Grimoire shows `"<Line> <Edition> <LANG>"`
  and stores the edition verbatim. The setting decides the line; the edition decides the system.
- `<Category>` is one of the folders `files folder scaffold` creates (see `category_folders` in
  `profile.json`): `Core`, `Supplements`, `Adventures`, `Character Sheets`, `Maps`, `Handouts`,
  `Homebrew`, `Starter Sets`, `Magazines`. The server's spelling wins.
- The category folder sits **exactly one level below** the system folder; deeper is invisible to the
  scanner. Below the category, nesting is free-form and inherits the category.
- A container cannot hold books. A folder that holds books is a system.
- Books tied to no system go in a plain parent such as `books/Agnostic/EN`. Do not name a folder
  `system-agnostic`, `generic` or `any`: the server claims those as special collections.

### Folders group what filenames cannot

A folder earns its place when names alone would not keep related files together. Files that share a
stem need no folder (a variant collapses behind its parent anyway). Files that do not share a stem
(a module, its handouts and a map pack) get one. A growing collection gets one plural grouping
folder (`Handouts/Card Sets/`) rather than a folder per item. The test: does it still pay for itself
at ten times the file count?

## Filenames

    [<Code> - ]<Title>[ - <Qualifier>][ [<SKU>]][ [<Year>]].<ext>

(`filename_pattern` in `profile.json`.)

- Bracket slots are optional and always in that order. Nothing else goes in brackets; other tokens
  become tags.
- **No line or system prefix.** The folder already states it, and an identical prefix on every file
  wastes the leading characters sorting depends on.
- **Catalogue codes are zero-padded to three digits** (`ES001`, `ES012`), because titles sort as text.
  A decimal sub-number pads its integer part only (`ES002.1`).
- Never invent a code. Use the one the publisher or community already cites, and only if it indexes a
  sequential catalogue. Otherwise it is a tag (`code:<value>`).
- The **title in metadata carries the code too**: `ES005 - Example Bestiary`. A printing qualifier
  moves into parentheses (`ES001 - Core Rules (First Printing)`). A book with no code takes none.
- Periodical runs keep their `<name>_<YYYY-MM>` form; it already sorts.
- Rename through the CLI (`files rename`, `files move`), never on the mount: a rename on disk strands
  the row and loses `isbn`, `language` and other API-only fields. A CLI move or rename keeps the
  book's system, title and thumbnail; the category follows the folder. No rescan is needed.

## Variants and the entry

A second file of the same thing keeps its own row and collapses behind a parent in listings, counts
and search. It is written only with `duplicates link`; the scanner never infers one. Two levels only.

| the second file is | book kind | label example |
|---|---|---|
| a later or earlier printing | `version` | `Second Printing` |
| an A4 print-at-home sheet | `printer-friendly` | `A4 Print` |
| a fillable sheet | `form-fillable` | |
| a scan of the same document | `other` | `Scan` |

Also for books: `spreads`, `single-page`, `black-and-white`. Maps use `gridded`, `gridless`,
`black-and-white`, `printer-friendly`, `universal-vtt`, `version`, `other` (`map_variant_kinds`). Token variants use `black-and-white`, `color-variation`, `version`, `other` (`token_variant_kinds`).

- **The filename still says what the file is**; the variant label lives in the database.
- **Entry rule (`entry_rule: lighter-build`)**: the lighter build (reduced size, optimized,
  compressed) is the entry and the full-size file is its variant. Between printings, the newest is
  the parent. A file with a real text layer beats a scan of it.
- Refused by the upload API under `books/` (`refused_book_formats`): `.xlsx`, `.mobi`, `.azw3`,
  `.doc`, `.tif`. Convert first (PDF for office files, PNG for TIFF). RTF is supported as is.

## Tags

A closed, lowercase vocabulary. A tag describes either the artifact or what is inside it.

| tag | meaning |
|---|---|
| `map`, `character-sheet`, `handout`, `errata`, `cheat-sheet`, `pregen`, `solo` | what the artifact is |
| `periodical` | part of a dated or numbered run |
| `free` | released at no cost |
| `code:<value>` | a code that is not a filename prefix |
| `printing:<slug>` | printing or edition note, e.g. `printing:second` |
| `for:<code>` | companion material's parent (`for:es005`); a parent with no code takes a slug |
| `region:<slug>` | everything for one region of a setting |
| `campaign:<slug>` | every part of a published adventure run, handouts included |

- A library may override the prefix per language (in its overrides).
- `for:` exists because Grimoire only relates two books as variants, and a variant hides the child.
  Companion material is different content that belongs to a parent, so a tag is the link.
- A campaign is a tag, not a folder: a campaign folder would break the code sort within a category.
- The category name is also carried as a tag so it stays searchable.
- Tags never cascade from a parent to its variants; tag each row.
- Domain tags (character concepts, species and so on) use the system's own vocabulary in the book's
  language. Keep one language per library for them.
- The publisher's article number goes in the book's `product_code`, in its printed form and upper
  case. The catalogue code is not a product code.

## Licence placement

`licence_placement: system-when-uniform`. Put the licence on the system when every row on it shares
one; when a shelf mixes licences, put it on the rows. Use only the server's licence vocabulary
(`licenses list`).

## Maps, tokens, models and audio

- A title's own maps live beside it in `Maps/` and are tagged `map`. The same holds for its tokens
  (`Tokens/`) and cards and handouts (`Handouts/`), each tagged `for:<book>`.
- Top-level `maps/` and `tokens/` hold **system-independent** packs only. A setting's own maps belong
  on that setting's books shelf. `maps/` has no category axis: folders carry no meaning and grouping
  is by tags.
- A map product is one folder, `maps/<publisher>/<product>/`, and each map is one entry; its other
  renderings are variants. The gridless day rendering is the entry. A product with adventure content
  is a book and goes on the books shelf.
- Tag every map with what is on it: kind (`battlemap`, `dungeon-map`), setting (`indoor`, `outdoor`,
  `underground`), terrain, place, features, grid (`grid`/`gridless`) and style.
- The maps API sets no title; the filename is the map's name. `maps/` takes PDFs and archives (a zip
  indexes as one row without a thumbnail).
- Map-asset packs (transparent stamps) go in `maps/` as one archive per pack and resolution, tagged
  `map-assets`.
- A map on a transparent background gets an opaque copy as its entry (flatten onto a light beige) and
  the original becomes a `Transparent` variant. Tokens stay transparent.
- **Audio** lives under `audio/<Line>/<Series>/<NN> <Album>/<NN> - <Title>.mp3`, with no systems and
  no container markers. Titles are fixed in the file's ID3 tags because the API writes only
  `description` and `tags`. Tag every track (folder tags do not reach `tag:` search): `soundtrack`,
  the series, and `for:<parent>`. Booklets are books and go on the shelf of the product they belong to.
- **Models** (3D prints) live under `models/<creator>/<product>/`.
- Novels, audiobooks and radio plays are not table audio and do not belong here.

## Armory

- Wargame systems live under `armory/` with the same container model as `books/`: system folders
  with category folders (`armory_category_folders` in `profile.json`: `Core`, `Factions`,
  `Rules Updates`, `Missions`, `Campaigns`, `Supplements`, the set `files folder scaffold` creates
  under `armory/`). Container markers are written with `files folder create --container-kind`.
- `Campaigns` is the category `campaign` under `armory/` and `adventure` under `books/`.
- Inside `Factions/`, no per-faction layout is prescribed until a wargame skill exists.
- A book that belongs on a second system's shelf is linked with `books links add`, not copied.

## Metadata

Only one layer can own each field: the **folder** owns system identity and category; an **OPF
sidecar** (`<stem>.opf` beside the book) owns title, authors, description, publisher, year, tags and
cover; the **API/CLI** owns `isbn`, `language`, `product_code`, system-level fields and anything bulk.
Rescan with `--metadata-mode missing` so populated fields are never overwritten; pass it explicitly.
