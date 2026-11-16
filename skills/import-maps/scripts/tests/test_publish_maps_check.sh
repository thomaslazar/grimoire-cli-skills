#!/usr/bin/env bash
# --check validates a plan against the profile and writes nothing.
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../../.." && pwd)"
. "$repo/tests/lib/assert.sh"
script="$here/../publish_maps.py"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
export FAKE_CLI_DIR="$t/fake"
cli="$repo/tests/lib/fake_cli.sh"
touch "$t/a.png" "$t/b.png"

plan() { # kind [root]
  cat > "$t/plan.json" <<JSON
{"root": "${2:-maps}/Example Press", "rows": [
 {"source": "$t/a.png", "target": "Forest Pack/Camp.png", "description": "Camp.", "tags": ["map"], "variant": null},
 {"source": "$t/b.png", "target": "Forest Pack/Camp - Grid.png", "description": "Camp.", "tags": ["map", "grid"],
  "variant": {"of": "Forest Pack/Camp.png", "kind": "$1", "label": "Grid"}}]}
JSON
}

plan gridded
out="$(python3 "$script" --plan "$t/plan.json" --run-dir "$t/run" --check --cli "$cli" 2>&1)"
assert_eq "$?" "0" "gridded variant passes --check"
assert_contains "$out" "plan ok: 2 rows, 1 entries" "check summary"
[ ! -e "$t/run" ] && [ ! -e "$t/fake" ]; assert_eq "$?" "0" "check writes nothing and calls no cli"
out="$(python3 "$script" --plan "$t" --check --cli "$cli" 2>&1)"
assert_contains "$out" "plan ok" "a run directory works as --plan, run dir defaults to it"

plan print
out="$(python3 "$script" --plan "$t/plan.json" --run-dir "$t/run" --check --cli "$cli" 2>&1)"
rc=$?
[ "$rc" -ne 0 ]; assert_eq "$?" "0" "print variant kind fails --check"
assert_contains "$out" "print" "the offending kind is named"
plan color-variation tokens
python3 "$script" --plan "$t/plan.json" --run-dir "$t/run" --check --cli "$cli" >/dev/null 2>&1
assert_eq "$?" "0" "color-variation passes --check for tokens"
plan gridded tokens
out="$(python3 "$script" --plan "$t/plan.json" --run-dir "$t/run" --check --cli "$cli" 2>&1)"
[ "$?" -ne 0 ]; assert_eq "$?" "0" "gridded fails --check for tokens"
assert_contains "$out" "gridded" "the offending token kind is named"
report
