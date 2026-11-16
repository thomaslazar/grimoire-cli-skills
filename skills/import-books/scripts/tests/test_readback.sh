#!/usr/bin/env bash
# readback.py: fields and tags per row, variant_count per parent, against the plan.
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../../.." && pwd)"
. "$repo/tests/lib/assert.sh"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
export FAKE_CLI_DIR="$t/fake"
cli="$repo/tests/lib/fake_cli.sh"
R="$FAKE_CLI_DIR/responses"

cat > "$t/plan.json" <<'JSON'
{"system_path": "books/Starfall RPG/1 EN", "rows": [
 {"target": "Core/A.pdf", "book_id": "id-a", "metadata": {"title": "A", "year": 2020}, "tags": ["x"], "variant": null},
 {"target": "Core/A (print).pdf", "book_id": "id-v1", "metadata": {"title": "A (print)"}, "tags": [],
  "variant": {"of": "Core/A.pdf", "kind": "printer-friendly"}},
 {"target": "Core/B (beta).pdf", "book_id": "id-v2", "metadata": {"title": "B beta"}, "tags": [],
  "variant": {"of": "Core/B.pdf", "of_id": "id-shelf", "kind": "version"}},
 {"target": "Core/P.pdf", "disposition": "present", "book_id": "id-p", "metadata": {"title": "P new", "publisher": "Example Press", "license": null},
  "tags": ["y"], "variant": null, "diff": {"title": {"verdict": "differs"}, "publisher": {"verdict": "missing"}, "license": {"verdict": "shelf_only"}}}]}
JSON

fixtures() { # $1 = title of A, $2 = variant_count of A
  rm -rf "$FAKE_CLI_DIR"; mkdir -p "$R"
  echo "{\"books\": [{\"id\": \"id-a\", \"title\": \"$1\", \"year\": 2020, \"tags\": [\"core\", \"x\"], \"variant_count\": $2},
    {\"id\": \"id-p\", \"title\": \"Shelf title\", \"publisher\": \"Example Press\", \"license\": \"Proprietary\", \"tags\": [\"x\", \"y\"], \"variant_count\": 0},
    {\"id\": \"id-shelf\", \"title\": \"B\", \"variant_count\": 3}]}" > "$R/systems-get.json"
  echo '{"game_system": {"id": "sys1"}}' > "$R/books-get.1.json"
  echo '{"id": "id-v1", "title": "A (print)", "tags": []}' > "$R/books-get.2.json"
  echo '{"id": "id-v2", "title": "B beta", "tags": []}' > "$R/books-get.3.json"
}

fixtures "A" 1
out="$(python3 "$here/../readback.py" --plan "$t" --cli "$cli" 2>&1)"; rc=$?
assert_eq "$rc" "0" "clean shelf reads back clean: $out"
assert_contains "$(cat "$FAKE_CLI_DIR/calls.log")" "books get --id id-v1" "variant child read via books get"

fixtures "Wrong" 0
out="$(python3 "$here/../readback.py" --plan "$t" --cli "$cli" 2>&1)"; rc=$?
assert_eq "$rc" "1" "mismatch exits 1"
assert_contains "$out" "Core/A.pdf title" "wrong title reported"
assert_contains "$out" "Core/A.pdf variant_count" "wrong variant_count reported"
assert_eq "$(grep -c 'Core/P.pdf' <<<"$out")" "0" "an unapproved differs is not a mismatch"

# an entry row that systems get does not list as an entry is a mismatch
fixtures "A" 1
python3 - "$R/systems-get.json" <<'PY2'
import json, sys
s = json.load(open(sys.argv[1])); s["books"] = [b for b in s["books"] if b["id"] != "id-p"]; json.dump(s, open(sys.argv[1], "w"))
PY2
out="$(python3 "$here/../readback.py" --plan "$t" --cli "$cli" 2>&1)"; rc=$?
assert_eq "$rc" "1" "missing entry exits 1"
assert_contains "$out" "Core/P.pdf not a parent" "missing entry reported as not a parent"
report
