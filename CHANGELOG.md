# Changelog

## Unreleased

- **`import-books` OCR handover:** `ocr_handover.py` now also prints a paste-ready instruction
  block for the external OCR agent (files, rules, checks, what to report back), and the skill hands
  over by printing that block in the console rather than writing a file.

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
