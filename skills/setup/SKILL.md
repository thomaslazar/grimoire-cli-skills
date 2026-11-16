---
name: setup
description: >-
  Use when starting out with these skills or a new library repo — checks the CLI, offers what it
  can manage, checks helper tools, scaffolds the library repo, and hands over to the installer and
  login. Triggers: "set up grimoire", "get started", "first run", "scaffold my library repo". NOT
  for importing (→ import-books and the other import skills) or for updating the binary alone (→
  install-grimoire-cli).
metadata:
  grimoire-cli-groups: []
  min-cli: "0.8.0"
  min-server: "1.11.0"
---

# setup

The first thing a new user runs. Five steps, in order. Scripts are relative to this skill folder.
Ask one question at a time; run nothing that installs or writes until the user has said yes.

## 1. The CLI

If `grimoire-cli` is not installed, use `install-grimoire-cli` first. Then:

```
python3 scripts/cli_caps.py --skills-dir <folder holding the skills> [--cli PATH]
```

The CLI is found from `--cli`, then the `cli` key in `grimoire-skills.json`, then `grimoire-cli` on
`PATH`, then `./bin/grimoire-cli`. If `install-grimoire-cli` just installed it (to `./bin/` or a
custom `--dest`) and another `grimoire-cli` is on `PATH`, pass the installed path as `--cli`.

It prints `{"skills": [...], "unskilled": [...], "below_floor": bool}`. **If `below_floor` is true,
stop** and offer to update the CLI with `install-grimoire-cli`; do no partial setup on an old CLI.
The skills need grimoire-cli 0.8.0 and Grimoire 1.11.0 or newer.

## 2. What to manage

Offer collections from `skills` only (books, maps, tokens, audio, ...), with what each skill does.
Mention `unskilled` groups as "supported by your CLI, no skill yet". Ask which the user wants.

## 3. Tools

```
python3 scripts/tools_check.py --collections books,audio
```

Per tool: `present`, `level`, `unlocks`, `without`, `install` (`brew` and `apt` commands).
`required` tools block the skill. `recommended` tools are not optional extras: list each missing one
with what it unlocks and what is lost without it, and **offer to install them by default**.
Print the install command for the user's platform and run it only after a yes. The script never installs.

## 4. Scaffold the library repo

Ask, then run `python3 scripts/scaffold.py --mode plugin|submodule --ocr server|handover
[--profile NAME] [--cli PATH] DIR`. It refuses (exit 2) to overwrite an existing
`grimoire-skills.json`, so never delete one to get past it.

- **Install mode.** `plugin`: skills come from the plugin, no `vendor/` and no symlinks. `submodule`
  (or a clone): adds `vendor/grimoire-cli-skills` and symlinks into `.agents/skills/` and `.claude/skills/`
  (`--skills-url` overrides the source). Ask how the skills were installed; if unsure, `plugin`.
- **Profile.** List every `profiles/*/` with the first line of its `conventions.md` (the description).
  Recommend `default`. Also offer "my own folder": a path to a folder with `profile.json` and
  `conventions.md`. A name that is neither a shipped profile nor an existing folder is refused.
- **OCR for image-only scans.** `server`: the server's own OCR (`books reindex`, then a rescan).
  `handover`: you OCR externally; the skill writes a handover CSV of absolute source paths and full
  target paths and reads the OCRed copies back. A shipped OCR script (`ocrmypdf`/`tesseract`) is on the
  roadmap, not available yet.
- `--cli PATH` when the binary is not the one on `PATH` (for example `bin/grimoire-cli` from the installer); it is written relative to the config and wins over `PATH`, so a stale binary on `PATH` is not used.

The result is `grimoire-skills.json`, `grimoire/overrides/`, `grimoire/lines/`, `docs/`, a short
`AGENTS.md`, `.gitignore` (`tmp/`, `bin/`) and a git repo.

## 5. Server and login

- **Server URL.** Read `~/.grimoire-cli/config.json` (`server`) or the `GRIMOIRE_SERVER` variable; if neither
  exists, ask the user. Only `login` takes `--server`.
- **Login is the user's, in their own terminal.** The password prompt needs a real console and the agent
  never types a password: have them run `grimoire-cli login --server https://<host>`.
  In Claude Code they can run it in-session with the `! ` prefix: `! grimoire-cli login --server https://<host>`.
  Local password accounts only; OIDC accounts cannot use the CLI login.
- The CLI renews the 30-minute access token from a 30-day refresh token and writes renewals back; log in
  again only after 30 days idle or a revoked session. It checks the server version on ordinary commands
  (cached about a day; `--debug` shows when).
- **Never copy `~/.grimoire-cli/config.json` into the repo.** It holds the server, tokens and version cache.
- Confirm with `grimoire-cli me`, then point at the import skills.
