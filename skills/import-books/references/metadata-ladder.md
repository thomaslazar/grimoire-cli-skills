# Pulling metadata out of files and sources

Method notes for phase 2. A line reference (`<lines_dir>/<line>.md`) names the sources for one line;
this page is how to use any of them.

## The ladder, cheapest first

Each rung shrinks the next rung's worklist. Do the free rungs before touching the network, but size
each one honestly before building anything for it: score the text a rung extracts, not the number of
rows it would fill.

| # | rung | cost |
|---|---|---|
| 1 | the filename | free |
| 2 | embedded PDF metadata (`pdfinfo`) | free, almost always useless |
| 3 | the imprint / credits page | free |
| 4 | the back cover (last page of a bound book) | free |
| 5 | render a page and read it as an image | free, needs a vision-capable model |
| 6 | the line's catalogue, the publisher, shops, web archives | slow, rate-limited |
| 7 | Grimoire's metadata add-ons | server-side, returns a diff |

## Embedded PDF metadata

Never trust an embedded title. Most are prepress boilerplate (a PDF/X conformance string), a layout
filename (`.indd`, `.qxd`, `.doc`, `.pub`), under four characters, or the filename itself.

## Imprint credits

Only the writing credit is `authors`. Editors, layout, cover and interior art, proofreading and
translation are other roles (art credits go to `artists`). The traps when parsing a credits block:

1. A terminating role can carry a modifier (`… Jane Doe Senior Editor:`), which swallows a word into
   the last name.
2. An over-broad modifier pattern truncates real names instead.
3. A conjunction (`and`, `und`, `et`) separates names; a trailing collective credit ("and the
   playtest team") is not a person.
4. The colon after the role can be missing; pair an optional colon with a name-shape test.

Use a name-shape test, not a phrase blocklist: every token of a personal name is capitalised, and a
candidate over five tokens is not a name. Names like `O.C. Smith`, `RJ Jones` and multi-part surnames
must survive it.

## The back cover

A blurb lives on the back cover of a **bound book**. A zine, a dossier or an errata sheet has none:
its last page is body text. Gate the rung on document type (page-count floor, skip periodical runs).

- Do not walk backwards past the last page: pages before it are rules, bestiary and appendices, and
  no shape test separates marketing prose from rules prose.
- Reject a candidate that matches `ISBN`, a price, `www.` or an e-mail domain (ad pages for other
  products), has many `_` (form fields), fewer than ~60 words, fewer than three sentence boundaries,
  a low share of lowercase-initial words (tables, indexes), or many all-caps tokens (stat blocks).
- **Casing thresholds are per language.** A language that capitalises nouns scores lower on
  lowercase share; re-measure on confirmed blurbs before porting a threshold.

## Rendering a page

Where text is flattened into artwork, `pdftoppm -f N -l N -r 110 -png book.pdf out` and read the
image. A missing text layer usually means there is no blurb in the file, not that it is hidden.

## Printed codes and ISBNs

A PDF often prints its own article number (imprint, last page, cover art). That is the code of the
artifact in hand. A print ISBN belongs to the print edition; a PDF-only product has no ISBN to find.
Imprints lie too: a missing digit, or two books claiming one number. Extract identifiers corpus-wide
and check for collisions; corroborate with a second source.

## Web method

- Harvest every field on the first page load; never split one lookup into two visits.
- Take page titles from a series index or navigation page, never guess them from filenames.
- A batch export returns only pages that exist: count what came back against what you asked for.
- The Wayback Machine reaches pages a site no longer serves: `web.archive.org/web/<ts>id_/<url>`
  returns the original bytes, often gzip, so fetch with `curl --compressed`. To list archived pages
  under a path, the CDX API with `matchType=prefix`; a domain-wide regex filter times out.
- For sites that refuse scripted clients, a browser-automation CLI (agent-browser, Playwright), or
  the server's add-on, which fetches from the server.

## Add-ons

`<books|systems> metadata-sources` → `metadata-search` → `metadata-fetch` is read-only and returns a
per-field diff (`field`, `current`, `incoming`, `status`); applying is a separate `update`. A
system-level wiki add-on may index one record per line, describing the current edition in English:
use it for line-level facts (genre, dice) at most.

## Parents and inheritance

The parent of a component is path derivation, no lookup: a file under `<Title>/Maps/` belongs to
`<Title>`; files sharing a `<Prefix> - ` are components of `<Prefix>`. Require the parent to be
unambiguous (two editions in one folder become each other's parent otherwise). Inherit `publisher`,
`year`, `language`; take `genres` from the system. **Never inherit a description verbatim**: write
one that names the component and its parent ("Overview map of the docks, from *Example Adventure*").

## Method

- Gate every extraction on a human-reviewed table before writing. First runs produce false positives,
  and each is a rule bug.
- Repairs (dropped diacritics, transliterations) come from an explicit reviewed word list, matched on
  whole tokens, never a general rule.
- Test idempotency: extract, apply, extract again; the second run must be empty.
- Never infer truncation from length. Verify against the source before calling a field cut off.
