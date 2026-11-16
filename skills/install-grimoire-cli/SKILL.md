---
name: install-grimoire-cli
description: >-
  Use when installing or updating the grimoire-cli binary — from the latest GitHub release, a
  specific release tag, or a PR's CI artifacts (URL, pr/6, #6, or 6). Acts as both install and
  update; idempotent. Installs to ./bin/grimoire-cli unless told otherwise.
metadata:
  grimoire-cli-groups: []
  min-cli: "0.8.0"
  min-server: "1.11.0"
---

# install-grimoire-cli

Installs or updates the `grimoire-cli` binary. The work is done by `scripts/install.sh` (path relative to this skill folder). Your job is to translate the user's intent into the right invocation, interpret the JSON it returns, and confirm with the user when needed.

The skills in this repo need grimoire-cli 0.8.0 or newer; pinning an older tag is unsupported.

Requires `gh` (authenticated), `jq`, and a POSIX platform (macOS or Linux, x64 or arm64). Windows builds exist but this script does not install them.

## When to use

- User says "install / update / refresh / reinstall grimoire-cli"
- User points at a PR build to test (e.g. "install from PR #6", a PR URL)
- User wants to move to a specific release tag

## Install location

`--dest PATH` sets where the binary goes; the default is `./bin/grimoire-cli` (relative to the current directory). The pin file `.installed.json` is written beside it. Other skills find the CLI in this order: their `--cli` flag, the `cli` key in `grimoire-skills.json`, `grimoire-cli` on `PATH`, then `bin/grimoire-cli` under the library repo (the folder holding `grimoire-skills.json`, else the current directory). An older `grimoire-cli` on `PATH` therefore wins over a fresh `./bin/` install: record the installed path as `cli` (setup's `scaffold.py --cli`, or edit `grimoire-skills.json`) so it does not.

## Targets

| user intent | pass to `install.sh` |
|---|---|
| just install or update; figure it out | (no arg) |
| force latest release, ignore current pin | `latest` |
| specific release | a tag such as `v0.8.0` |
| from a PR | full URL, `pr/6`, `#6`, or `6` |

Pass a GitHub URL through as-is; the script parses it. A bare invocation resolves to the newest release, or refreshes the PR if one is pinned.

## Invocation

Run `--plan` first to decide what to do, then act on the JSON.

```sh
bash scripts/install.sh --plan [--dest PATH] <target>
```

Single JSON object on stdout:

```json
{
  "action": "<see below>",
  "current": null,
  "target":  { "source": "release|pr", "tag": "...", "pr": 0, "run_id": 0, "sha": "...", "asset": "..." },
  "platform": "osx-arm64",
  "binary_path": "/abs/path/to/bin/grimoire-cli"
}
```

`current` is the existing pin object, or `null`. `target` carries `tag` for releases and `pr`/`run_id`/`sha` for PRs.

| context | `action` | meaning | what you do |
|---|---|---|---|
| `--plan` | `fresh` | nothing installed yet | run for real |
| `--plan` | `refresh` | same source pinned, different tag/run available | run for real |
| `--plan` | `noop` | already on the exact target | tell the user; proceed only if they want a reinstall (`--force`) |
| `--plan` | `conflict` | a different source is pinned (e.g. PR pinned, release requested) | show the user the difference, confirm, then run with `--force` |
| real run | `installed` | binary in place, pin written | report success |
| real run | `noop` | already on target (without `--force`) | report unchanged |
| real run | `conflict` | refused, different pin (without `--force`) | comes with exit 2 |
| real run | `verify-failed` | installed binary failed `--version`/`self-test`; prior binary restored | report failure (exit 3) |

## Real install

```sh
bash scripts/install.sh [--force] [--dest PATH] <target>
```

Exit codes:
- `0` success; the final JSON has the resulting action.
- `1` user or environment error. Read stderr. Common causes: `gh` not authenticated (`gh auth login`), unsupported platform, PR or release tag not found, an expired PR artifact. A freshly tagged release can exist with no assets yet while CI builds them; check `gh release view <tag> --json assets` and wait rather than retrying blindly.
- `2` pin conflict without `--force`. Confirm with the user, retry with `--force`.
- `3` verification failed: either the asset's SHA-256 did not match the release's `SHA256SUMS` (nothing installed, current binary untouched), or the install completed but `--version` or `self-test` failed (prior binary restored). Report it; do not retry blindly. A checksum mismatch means a corrupt or tampered download.

Release installs are verified against the release's `SHA256SUMS`; a release without one is refused (exit 1). PR artifacts carry no checksum file, so PR installs are unverified.

PR artifacts expire after 5 days. An older PR needs its CI workflow re-run before it can be installed.

## After installing

A local application firewall can block a freshly installed binary. The symptom is a TLS EOF or handshake error that looks like a server fault. If `curl` to the same host works and the binary does not, ask the user to allow the binary and retry.

## Reporting back

Say exactly what was installed, not just "success":

- PR: `installed grimoire-cli from PR #6 (sha 799cd728, run 24346270346, osx-arm64) -> ./bin/grimoire-cli`
- Release: `installed grimoire-cli v0.8.0 (osx-arm64) -> ./bin/grimoire-cli`
- Noop: `already on PR #6 run 24346270346; nothing to do`

The pin file beside the binary is the source of truth for "what is installed?".

## Do not

- Reimplement the script's logic in shell snippets; call the script.
- `chmod` the binary or strip quarantine yourself; the script does both (quarantine is a no-op on Linux).
- Commit the installed binary or its pin file; both are per-machine.
- Pass options the script does not define (e.g. `--repo`, `--arch`). If something is missing, surface it as a script change.
- Try to install a Windows build.
