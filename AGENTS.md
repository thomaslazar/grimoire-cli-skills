# AGENTS.md

Skills for driving `grimoire-cli` against a Grimoire server.

## Rules

- **No attribution of any kind in this repo**: no `Co-Authored-By`, no "Generated with ...", no Claude/AI/agent names, no robot emoji, in commits, PRs, issues, tags, release notes, CHANGELOG or files. The work is authored as the user. Mentioning the Claude Code plugin as a feature is fine.
- **Nothing private**: no personal paths, emails, server hosts, corpus folder names, run ids or purchase data. Use neutral examples (`/path/to/library`, "Example Press").
- Skills drive `grimoire-cli` only and go through the server (`files browse`/`get` to verify), never the library mount or the HTTP API directly.
- Skills use the Agent Skills format: `skills/<name>/SKILL.md`. Script paths in SKILL.md are relative to the skill folder (`scripts/x.py`).
- Scripts: `python3` stdlib, bash and jq; Pillow only in image scripts (recommended, install hint on ImportError).
- Commits: Conventional Commits, `type: subject`, imperative, lowercase, max ~72 chars.

## Checks

- Tests: `python3 -m unittest discover -s tools`, plus each `skills/*/scripts/tests/run_all.sh` and `python3 -m unittest discover -s lib` where present.
- Leak check: `python3 tools/leak_check.py .` (add `--patterns FILE` for local private regexes, one per line). The pre-commit hook passes `$LEAK_PATTERNS` (path to such a file) when set.
- Hooks: `git config core.hooksPath tools` (pre-commit leak check, commit-msg attribution check).

## Config and profile (shared call forms)

In every SKILL.md the agent resolves `scripts/…` and `../../lib/…` paths from the skill's folder but keeps the library repo as the working directory: `config.load()` finds `grimoire-skills.json` by walking up from the cwd.

Every skill resolves its rules through `lib/grimoire_skills/config.py` (profile, overrides, lines, `ocr`). Use these two forms verbatim:

- **From a skill folder (SKILL.md):** `python3 <skill folder>/../../lib/grimoire_skills/config.py`, run from the library repo (the current directory), prints the resolved config as JSON (`--start DIR` to resolve from elsewhere).
- **From a skill script:** insert the repo's `lib` into `sys.path` before importing:

```python
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "..", "..", "lib"))
from grimoire_skills import config
```

Read `config.rule_files(cfg)` for the prose rules (default `conventions.md` plus any override `*.md`).
