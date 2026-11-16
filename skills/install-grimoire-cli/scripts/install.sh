#!/usr/bin/env bash
# Install or update grimoire-cli into --dest (default ./bin/grimoire-cli).
#
# Source can be:
#   - latest GitHub release (default)
#   - a specific release tag (e.g. v0.8.0)
#   - the latest successful "Build and Test" run for a PR
#
# Stdout: a single JSON object describing the action.
# Stderr: human-readable progress.
#
# Exit codes:
#   0  success (install, update, or noop)
#   1  user/environment error (bad args, missing tools, gh unauthenticated, etc.)
#   2  pin conflict (different version already installed; rerun with --force)
#   3  verification failed (SHA256SUMS mismatch, or binary did not pass --version or self-test)

# Also runnable as `sh install.sh`: re-exec under bash.
[ -n "${BASH_VERSION:-}" ] || exec bash "$0" "$@"

set -euo pipefail

REPO="thomaslazar/grimoire-cli"
WORKFLOW_NAME="Build and Test"

DEST="./bin/grimoire-cli"
TARGET=""
PLAN_ONLY=0
FORCE=0

usage() {
  cat <<'USAGE' >&2
Usage: install.sh [options] [<target>]

Targets:
  (no arg)       Respect pin: refresh PR if pinned to one, else install latest release.
  latest         Install newest release (ignore pin).
  v0.8.0         Install that specific release tag.
  <pr ref>       Install from PR. Accepts: full URL, pr/6, #6, or 6.

Options:
  --dest PATH    Where to install the binary (default ./bin/grimoire-cli).
                 The pin file (.installed.json) is kept beside it.
  --plan         Print planned action as JSON; do not install.
  --force        Install even on noop or pin conflict.
  -h, --help     Show this help.

Exit codes:
  0  success
  1  user/environment error
  2  pin conflict (no --force)
  3  verification failed
USAGE
}

log()  { printf '%s\n' "$*" >&2; }
die()  { log "error: $*"; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"; }

# ---- args ----
while [ $# -gt 0 ]; do
  case "$1" in
    --plan)    PLAN_ONLY=1; shift ;;
    --force)   FORCE=1; shift ;;
    --dest)    [ $# -ge 2 ] || die "--dest needs a path"; DEST="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --)        shift; break ;;
    -*)        die "unknown option: $1" ;;
    *)
      [ -z "$TARGET" ] || die "multiple targets given: '$TARGET' and '$1'"
      TARGET="$1"; shift ;;
  esac
done

# ---- paths ----
case "$DEST" in /*) ;; *) DEST="$PWD/${DEST#./}" ;; esac
BIN_PATH="$DEST"
BIN_DIR="$(dirname "$BIN_PATH")"
PIN_PATH="$BIN_DIR/.installed.json"
PREV_PATH="$BIN_PATH.prev"

# ---- prereqs ----
need gh
need jq
need uname
need mktemp
gh auth status >/dev/null 2>&1 || die "gh is not authenticated. Run: gh auth login"

# ---- platform ----
# CI also builds win-x64/win-arm64; this script is POSIX-only by design.
detect_asset() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"
  case "$os/$arch" in
    Darwin/x86_64)             echo "grimoire-cli-osx-x64"     ;;
    Darwin/arm64)              echo "grimoire-cli-osx-arm64"   ;;
    Linux/x86_64)              echo "grimoire-cli-linux-x64"   ;;
    Linux/aarch64|Linux/arm64) echo "grimoire-cli-linux-arm64" ;;
    *) die "unsupported platform: $os/$arch" ;;
  esac
}
ASSET="$(detect_asset)"

# ---- pin ----
read_pin() {
  if [ -f "$PIN_PATH" ]; then cat "$PIN_PATH"; else echo "null"; fi
}

# ---- target classification ----
# Sets: TARGET_KIND in {default, latest, release, pr}, TARGET_REF
classify_target() {
  local t="$1"
  if [ -z "$t" ]; then TARGET_KIND="default"; TARGET_REF=""; return; fi
  case "$t" in
    latest)    TARGET_KIND="latest";  TARGET_REF=""; return ;;
    v[0-9]*)   TARGET_KIND="release"; TARGET_REF="$t"; return ;;
  esac
  local pr=""
  case "$t" in
    https://github.com/*/*/pull/*) pr="${t##*/pull/}" ;;
    pr/*)    pr="${t#pr/}" ;;
    '#'*)    pr="${t#\#}" ;;
    [0-9]*)  pr="$t" ;;
    *) die "could not parse target as PR or release: '$t'" ;;
  esac
  pr="${pr%%/*}"
  pr="${pr%%\?*}"
  pr="${pr%%#*}"
  case "$pr" in
    ''|*[!0-9]*) die "could not parse PR number from '$t'" ;;
  esac
  TARGET_KIND="pr"; TARGET_REF="$pr"
}

# ---- resolve plan ----
# Sets: PLAN_SOURCE, PLAN_TAG, PLAN_PR, PLAN_RUN, PLAN_SHA
resolve_plan() {
  local kind="$1" ref="$2"
  PLAN_SOURCE=""; PLAN_TAG=""; PLAN_PR=""; PLAN_RUN=""; PLAN_SHA=""

  if [ "$kind" = "default" ]; then
    local pin pin_source
    pin="$(read_pin)"
    if [ "$pin" != "null" ]; then
      pin_source="$(echo "$pin" | jq -r '.source')"
      if [ "$pin_source" = "pr" ]; then
        kind="pr"; ref="$(echo "$pin" | jq -r '.pr')"
      else
        kind="latest"
      fi
    else
      kind="latest"
    fi
  fi

  case "$kind" in
    latest)
      PLAN_SOURCE="release"
      if ! PLAN_TAG="$(gh release view --repo "$REPO" --json tagName -q .tagName 2>/dev/null)"; then
        # gh exits non-zero both for "no release" and for transport/auth failures.
        if gh api "repos/$REPO" --silent >/dev/null 2>&1; then
          die "no releases in $REPO yet — install from a PR: install.sh pr/N"
        fi
        die "failed to reach $REPO (gh auth / network?)"
      fi
      [ -n "$PLAN_TAG" ] || die "latest release tag came back empty"
      ;;
    release)
      PLAN_SOURCE="release"
      gh release view "$ref" --repo "$REPO" --json tagName -q .tagName >/dev/null 2>&1 \
        || die "release '$ref' not found in $REPO"
      PLAN_TAG="$ref"
      ;;
    pr)
      PLAN_SOURCE="pr"
      PLAN_PR="$ref"
      PLAN_SHA="$(gh pr view "$ref" --repo "$REPO" --json headRefOid -q .headRefOid 2>/dev/null)" \
        || die "PR #$ref not found in $REPO"
      local run
      run="$(gh api "repos/$REPO/actions/runs?head_sha=$PLAN_SHA&status=success&per_page=20" \
        --jq ".workflow_runs | map(select(.name == \"$WORKFLOW_NAME\")) | .[0]")" \
        || die "failed to query workflow runs for sha $PLAN_SHA"
      [ -n "$run" ] && [ "$run" != "null" ] \
        || die "no successful '$WORKFLOW_NAME' run for PR #$ref (sha ${PLAN_SHA:0:8})"
      PLAN_RUN="$(echo "$run" | jq -r '.id')"
      ;;
    *) die "internal: unknown target kind '$kind'" ;;
  esac
}

# ---- compare pin to plan ----
# Echoes one of: noop, refresh, conflict, fresh
plan_action() {
  local pin; pin="$(read_pin)"
  if [ "$pin" = "null" ]; then echo "fresh"; return; fi
  local p_source p_tag p_pr p_run
  p_source="$(echo "$pin" | jq -r '.source')"
  p_tag="$(echo "$pin"    | jq -r '.tag // ""')"
  p_pr="$(echo "$pin"     | jq -r '.pr // ""')"
  p_run="$(echo "$pin"    | jq -r '.run_id // ""')"

  if [ "$p_source" = "$PLAN_SOURCE" ]; then
    if [ "$PLAN_SOURCE" = "release" ]; then
      [ "$p_tag" = "$PLAN_TAG" ] && { echo "noop"; return; }
      echo "refresh"; return
    fi
    if [ "$PLAN_SOURCE" = "pr" ] && [ "$p_pr" = "$PLAN_PR" ]; then
      [ "$p_run" = "$PLAN_RUN" ] && { echo "noop"; return; }
      echo "refresh"; return
    fi
  fi
  echo "conflict"
}

# ---- emit JSON ----
# Uses CURRENT_SNAPSHOT captured at script start so post-install output still
# reports the *pre-install* pin in `current`.
emit_json() {
  local action="$1"
  local current="$CURRENT_SNAPSHOT"
  local target
  if [ "$PLAN_SOURCE" = "release" ]; then
    target="$(jq -n --arg src release --arg tag "$PLAN_TAG" --arg asset "$ASSET" \
      '{source:$src, tag:$tag, asset:$asset}')"
  else
    target="$(jq -n --arg src pr --argjson pr "$PLAN_PR" --argjson run "$PLAN_RUN" \
      --arg sha "$PLAN_SHA" --arg asset "$ASSET" \
      '{source:$src, pr:$pr, run_id:$run, sha:$sha, asset:$asset}')"
  fi
  jq -n \
    --arg action "$action" \
    --argjson current "$current" \
    --argjson target  "$target" \
    --arg platform    "${ASSET#grimoire-cli-}" \
    --arg binary_path "$BIN_PATH" \
    '{action:$action, current:$current, target:$target, platform:$platform, binary_path:$binary_path}'
}

# ---- download + install ----
do_install() {
  local tmp; tmp="$(mktemp -d)"
  # Expand $tmp now so the trap doesn't hit set -u after the function returns.
  trap "rm -rf '$tmp'" EXIT

  if [ "$PLAN_SOURCE" = "release" ]; then
    log "downloading $ASSET from release $PLAN_TAG..."
    gh release download "$PLAN_TAG" --repo "$REPO" \
      --pattern "$ASSET" --output "$tmp/grimoire-cli" --clobber \
      || die "release download failed"
    gh release download "$PLAN_TAG" --repo "$REPO" \
      --pattern SHA256SUMS --output "$tmp/SHA256SUMS" --clobber \
      || die "release $PLAN_TAG has no SHA256SUMS; refusing unverified install"
    local want got
    want="$(awk -v a="$ASSET" '$2 == a || $2 == "*" a { print $1 }' "$tmp/SHA256SUMS")"
    [ -n "$want" ] || die "SHA256SUMS has no entry for $ASSET"
    if command -v sha256sum >/dev/null 2>&1; then
      got="$(sha256sum "$tmp/grimoire-cli" | awk '{print $1}')"
    else
      got="$(shasum -a 256 "$tmp/grimoire-cli" | awk '{print $1}')"
    fi
    [ "$got" = "$want" ] || { log "checksum mismatch for $ASSET: expected $want, got $got"; exit 3; }
    log "sha256 ok ($ASSET)"
  else
    log "downloading $ASSET from PR #$PLAN_PR run $PLAN_RUN..."
    gh run download "$PLAN_RUN" --repo "$REPO" -n "$ASSET" -D "$tmp" \
      || die "PR artifact download failed (artifacts expire after 5 days)"
    # The PR workflow uploads the whole publish/ dir: grimoire-cli plus debug
    # symbols. Release assets come as a single file named grimoire-cli-<rid>.
    if   [ -f "$tmp/grimoire-cli" ]; then :
    elif [ -f "$tmp/$ASSET" ];       then mv "$tmp/$ASSET" "$tmp/grimoire-cli"
    else die "unexpected layout in PR artifact (no grimoire-cli in $tmp)"
    fi
  fi

  chmod +x "$tmp/grimoire-cli"

  mkdir -p "$BIN_DIR"
  if [ -f "$BIN_PATH" ]; then
    mv "$BIN_PATH" "$PREV_PATH"
  else
    rm -f "$PREV_PATH"
  fi
  mv "$tmp/grimoire-cli" "$BIN_PATH"

  if [ "$(uname -s)" = "Darwin" ]; then
    xattr -d com.apple.quarantine "$BIN_PATH" 2>/dev/null || true
  fi
}

# ---- verify ----
do_verify() {
  log "verifying installed binary..."
  local ok=1
  "$BIN_PATH" --version  >/dev/null 2>&1 || { log "binary failed --version"; ok=0; }
  if [ $ok = 1 ]; then
    "$BIN_PATH" self-test >/dev/null 2>&1 || { log "binary failed self-test"; ok=0; }
  fi
  if [ $ok = 0 ]; then
    if [ -f "$PREV_PATH" ]; then
      log "restoring previous binary"
      mv "$PREV_PATH" "$BIN_PATH"
    else
      rm -f "$BIN_PATH"
    fi
    return 3
  fi
  rm -f "$PREV_PATH"
}

# ---- write pin ----
write_pin() {
  local now; now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [ "$PLAN_SOURCE" = "release" ]; then
    jq -n --arg source release --arg tag "$PLAN_TAG" --arg asset "$ASSET" --arg ts "$now" \
      '{source:$source, tag:$tag, asset:$asset, installed_at:$ts}' > "$PIN_PATH"
  else
    jq -n --arg source pr --argjson pr "$PLAN_PR" --argjson run "$PLAN_RUN" \
      --arg sha "$PLAN_SHA" --arg asset "$ASSET" --arg ts "$now" \
      '{source:$source, pr:$pr, run_id:$run, sha:$sha, asset:$asset, installed_at:$ts}' > "$PIN_PATH"
  fi
}

# ---- main ----
# Snapshot the pre-install pin so emit_json always reports "what we started from".
CURRENT_SNAPSHOT="$(read_pin)"
classify_target "$TARGET"
resolve_plan "$TARGET_KIND" "$TARGET_REF"
ACTION="$(plan_action)"

if [ "$PLAN_ONLY" = "1" ]; then
  emit_json "$ACTION"
  exit 0
fi

if [ "$ACTION" = "noop" ] && [ "$FORCE" != "1" ]; then
  emit_json "noop"
  exit 0
fi

if [ "$ACTION" = "conflict" ] && [ "$FORCE" != "1" ]; then
  emit_json "conflict"
  exit 2
fi

do_install
do_verify || { emit_json "verify-failed"; exit 3; }
write_pin
emit_json "installed"
exit 0
