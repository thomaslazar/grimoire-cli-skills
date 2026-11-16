# grimoire-cli-skills

Agent skills that drive [`grimoire-cli`](https://github.com/thomaslazar/grimoire-cli) to manage a [Grimoire](https://github.com/hunter-read/grimoire) TTRPG library: import books, maps, tokens and audio, and audit shelf health. They use the open Agent Skills format (`SKILL.md`) and `AGENTS.md`, so they are not tied to one agent.

## Requirements

- [grimoire-cli](https://github.com/thomaslazar/grimoire-cli) 0.8.0 or newer ([releases](https://github.com/thomaslazar/grimoire-cli/releases); the `install-grimoire-cli` skill installs it for you) and [Grimoire](https://github.com/hunter-read/grimoire) 1.11.0 or newer.
- An admin account on the server for anything that imports.
- Helper tools (for example `ffmpeg`, `qpdf`, `pdfinfo`): the `setup` skill checks for them and offers to install the missing ones.

## Skills

| Skill | What it does |
|---|---|
| `setup` | First run: checks the CLI and tools, offers what to manage, scaffolds your library repo. |
| `install-grimoire-cli` | Installs or updates the `grimoire-cli` binary. |
| `import-books` | Shelves a folder of books: system, edition, filenames, variants, metadata. |
| `import-maps` | Imports map packs into the maps library. |
| `import-tokens` | Imports VTT token packs into the tokens library. |
| `import-audio` | Imports soundtrack albums, with titles fixed in the files. |
| `audit-library` | Read-only shelf health check: tags, vocabulary, coverage, variants. |

CLI resolution, first match wins: `--cli`, `cli` in `grimoire-skills.json`, `grimoire-cli` on `PATH`, `./bin/grimoire-cli`.

## Opinionated defaults

The skills follow one set of library conventions (layout, filenames, tags, variants, licence placement). They ship as the `default` profile and are defaults, not requirements. Override single rules in `grimoire/overrides/` of your library repo, or point `profile` in `grimoire-skills.json` at a whole other profile (a shipped one or your own folder). See [`docs/overrides.md`](docs/overrides.md).

## Install

### As a Claude Code plugin

```
/plugin marketplace add thomaslazar/grimoire-cli-skills
/plugin install grimoire-cli-skills@grimoire-cli
/reload-plugins
```

Update with `claude plugin update grimoire-cli-skills@grimoire-cli`. Auto-update is off by default for third-party marketplaces; enable it in the `/plugin` menu if you want it. Updates arrive only when the version in `plugin.json` changes.

### By clone or submodule

```
git clone https://github.com/thomaslazar/grimoire-cli-skills.git
ln -s "$PWD"/grimoire-cli-skills/skills/* ~/.agents/skills/
```

Link into `~/.agents/skills/` for every project, or into a project's `.agents/skills/` (and `.claude/skills/` for Claude Code). Inside a library repo, add it as a submodule instead (below).

## Your library repo

Keep your own rules and notes in a dedicated repo and pull these skills in:

```
my-library/
  grimoire-skills.json              # profile, overrides, lines, OCR route, optional cli path
  AGENTS.md
  grimoire/overrides/               # your rule changes
  grimoire/lines/                   # per-game references
  docs/                             # what is on the shelves, lessons learned
  tmp/                              # run directories (ignored)
  vendor/grimoire-cli-skills/       # submodule (not with the plugin route)
  .agents/skills/, .claude/skills/  # symlinks into vendor (not with the plugin route)
```

Update the submodule with `git submodule update --remote vendor/grimoire-cli-skills`. To pin, check out a tag inside it (`git -C vendor/grimoire-cli-skills checkout v0.1.0`) and commit the new pointer.

## Running setup

Ask your agent to "set up grimoire". It checks the CLI, asks what to manage, checks tools, then runs `skills/setup/scripts/scaffold.py` (`--mode plugin|submodule`, `--ocr server|handover`, `--profile`, `--cli`, `--skills-url`). It never overwrites an existing `grimoire-skills.json`, then hands over to the installer and `grimoire-cli login`.

## Other agents

Written to the open standard for Codex, Gemini CLI, Copilot CLI and others. Only Claude Code is tested; PRs welcome.

## Contributing a profile

1. Copy `profiles/default` to `profiles/<your-name>`.
2. Change the rules, keeping the keys and headings from [`profiles/README.md`](profiles/README.md).
3. Run `python3 -m unittest discover -s lib`; CI checks the same contract.
4. Open a PR. Keep examples neutral and free of private paths.

## Versioning

One semver version for the whole repo, in `.claude-plugin/plugin.json` only. Every user-visible change bumps it and adds a `CHANGELOG.md` entry; releases are tagged `vX.Y.Z`. The first release is v0.1.0.

## Roadmap

- A shipped OCR script for image-only scans (today: the server's OCR or an external handover).
- An `enrich-metadata` skill: audit, source, review and apply metadata on books already shelved.
- A `cleanup-rundirs` skill: find finished import run directories and offer to delete them.

## Related

- [grimoire-cli](https://github.com/thomaslazar/grimoire-cli): the command-line client these skills drive.
- [Grimoire](https://github.com/hunter-read/grimoire): the self-hosted TTRPG library server.

## License

MIT.
