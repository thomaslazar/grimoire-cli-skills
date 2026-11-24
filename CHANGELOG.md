# Changelog

## Unreleased

- **Titles follow the cover:** the title printed on the cover (then the title page) is the rule, not a
  per-run decision; only a cover that contradicts its title page or looks misprinted is surfaced.
- **Product codes are looked for but optional:** the cover, barcode label, imprint and source are checked;
  a row without one is flagged in the walkthrough, never a gap, open question or decision.
- **`import-books` identifiers:** every ISBN is checked with its check digit before it reaches the plan; the
  back-cover barcode label is read from a 150 dpi crop, where it often carries the stock number too.
- **`import-books` broken page objects:** the survey finds PDFs whose damaged xref lists `0 x 0` pages
  (`pdfinfo`, `qpdf --check`) and the walkthrough reports them as defects with page ranges; the
  repair is left to the user, since OCR alone does not restore them.
- **`import-books` failed lookups:** a lookup that errored (timeout, refused, 403/429, bot challenge) is retried
  before a field is flagged; flagged fields name the sources searched and any that could not be reached.
- **`import-books` advert codes:** a stock number printed beside another title (an advert on the back cover
  or end pages) is not the row's product code; only the book's own cover block or barcode label counts.
- **`import-books` template leftovers:** a cover spread that kept a sibling's back cover (blurb and code of
  another product) gives no code; a code printed by two books belongs to neither.

## 0.1.3 - 2026-11-19

- **`import-books` OCR handover:** the walkthrough's OCR section ends with the handover block, so
  the user can start the OCR while reviewing the plan, instead of waiting for "proceed". Approvals
  that change which rows need OCR regenerate the block. Returned OCR still needs its own go before
  phase 5.

## 0.1.2 - 2026-11-19

- **Default profile, entry rule:** the lighter build is the entry only when the size gap makes the
  heavy file slow to read in the browser; with a small gap the better-quality file is the entry.
- **Default profile, look-alike files:** two non-identical files of one product that share the PDF
  creation date, page count or image size are compared (`pdfinfo`, `pdfimages -list`) and the
  findings presented, instead of being settled by the entry rule.

## 0.1.1 - 2026-11-18

- **`import-books` OCR handover:** `ocr_handover.py` writes the full instructions for the external
  OCR agent (files, rules, checks, what to report back) to a Markdown file beside the CSV and prints
  a short paste-ready block naming both by absolute path; the skill hands over that block in the
  console. Above 25 files the instructions give totals and point at the CSV.
- **`import-books` after OCR:** returned OCR is resolved and scored, then the run asks again before
  phase 5.
- **`import-books` OCR rules:** the handover asks for orientation detection (sideways pages OCR'd in
  reading orientation, display rotation kept), `--redo-ocr` over a junk text layer, a corrected
  working copy for images that render garbled, and a per-page non-word check.
- **`ocr_quality.py --words <list>`:** a `lowpg` column lists pages that read as mostly non-words,
  which `garble%` misses (sideways OCR, garbled renders).
- **`import-books` gaps:** a missing description, author or year is a gap only after the row's first
  and last pages were read and its cover rendered.

## 0.1.0 - 2026-11-16

First release.

- **Skills:** `setup`, `install-grimoire-cli`, `import-books`, `import-maps`, `import-tokens`,
  `import-audio`, `audit-library`, in the Agent Skills format with an `AGENTS.md` for the repo.
- **Requirements:** grimoire-cli 0.8.0 or newer and Grimoire 1.11.0 or newer. `setup` stops on an
  older CLI and offers to update it.
- **Default profile:** opinionated library conventions (layout, filenames, variants, tags, licence
  placement, maps/tokens/models/audio, armory, metadata), with a contract that shipped and
  contributed profiles must meet, checked in CI.
- **Overrides:** a library repo layers its own rules on top in `grimoire/overrides/` (prose rules
  add, `profile.json` keys replace); see `docs/overrides.md`.
- **`setup`:** checks the CLI and what it can manage, checks helper tools, scaffolds a library
  repo in plugin or submodule mode, records the profile, the OCR route (`server` or `handover`) and
  an optional CLI path.
- **`import-books` pipeline:** plan check, shelf reconciliation, folders, upload, id resolution,
  metadata with safety gates, variant links, read-back, system metadata, and OCR for both routes.
- **Install:** as a Claude Code plugin (`grimoire-cli-skills@grimoire-cli`) or by clone/submodule.
- **Leak guard:** pre-commit and CI leak check, with optional private patterns; a commit-msg hook.
