#!/usr/bin/env bash
# apply.py: refusals, full write on new rows, gated write on diffed rows, variants.
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../../.." && pwd)"
. "$repo/tests/lib/assert.sh"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
export FAKE_CLI_DIR="$t/fake"
cli="$repo/tests/lib/fake_cli.sh"
apply="$here/../apply.py"
R="$FAKE_CLI_DIR/responses"

reset() { rm -rf "$FAKE_CLI_DIR" "$t/receipts-apply.ndjson"; mkdir -p "$R" "$FAKE_CLI_DIR/exit"
  echo '{"id": "x", "game_system": {"id": "sys1"}, "category": "core"}' > "$R/books-get.json"
  echo '{"id": "sys1", "books": [{"id": "id-a", "category": "core"}, {"id": "id-p", "category": "core"}]}' > "$R/systems-get.json"
  echo '{"updated": ["id-a", "id-p", "id-v1", "id-v2"], "errors": []}' > "$R/books-batch-update.json"
  echo '{"updated": ["id-p"], "errors": []}' > "$R/books-batch-tag.json"
  echo '{"linked": ["id-v1", "id-v2"], "errors": []}' > "$R/duplicates-link.json"; }
edit() { python3 -c "import json;p=json.load(open('$t/plan.orig'));$1;json.dump(p,open('$t/plan.json','w'))"; }
body() { python3 -c "import json,sys;print(json.dumps(json.loads(open('$FAKE_CLI_DIR/stdin.log').readlines()[$1])$2))"; }

cat > "$t/plan.json" <<'JSON'
{"system_path": "books/Starfall RPG/1 EN", "shelf_checked": "2026-01-01T00:00:00Z", "rows": [
 {"target": "Core/A.pdf", "disposition": "new", "book_id": "id-a", "metadata": {"title": "A", "year": 2020}, "tags": ["x"], "variant": null},
 {"target": "Core/P.pdf", "disposition": "present", "book_id": "id-p",
  "metadata": {"title": "P new", "description": "d", "publisher": "Example Press", "license": "CC BY 4.0"}, "tags": ["x", "y"], "variant": null,
  "diff": {"title": {"verdict": "differs"}, "description": {"verdict": "missing"}, "publisher": {"verdict": "differs"},
           "license": {"verdict": "differs"}, "tags": {"verdict": "adds", "add": ["y"], "shelf": ["x", "old"]}},
  "apply": ["publisher"]},
 {"target": "Core/A (print).pdf", "disposition": "new", "book_id": "id-v1", "metadata": {}, "tags": [],
  "variant": {"of": "Core/A.pdf", "kind": "printer-friendly", "label": "Print"}},
 {"target": "Core/B (beta).pdf", "disposition": "new", "book_id": "id-v2", "metadata": {}, "tags": [],
  "variant": {"of": "Core/B.pdf", "of_id": "id-shelf", "kind": "version", "label": "Beta"}},
 {"target": "Core/A (old).pdf", "disposition": "present", "book_id": "id-v3", "metadata": {}, "tags": [],
  "variant": {"of": "Core/A.pdf", "kind": "version", "label": "Old"},
  "diff": {"variant": {"verdict": "differs", "shelf": "id-other", "plan": "id-a"}}}]}
JSON
cp "$t/plan.json" "$t/plan.orig"

# refusals: an open question, then a row to write without an id
reset
python3 -c "import json;p=json.load(open('$t/plan.orig'));p['rows'][0]['open_questions']=['which year?'];json.dump(p,open('$t/plan.json','w'))"
err="$(python3 "$apply" --plan "$t" --cli "$cli" 2>&1)"; rc=$?
assert_eq "$rc" "2" "open question refuses"
assert_contains "$err" "Core/A.pdf" "names the row"
assert_eq "$(cat "$FAKE_CLI_DIR/calls.log" 2>/dev/null)" "" "nothing called"
python3 -c "import json;p=json.load(open('$t/plan.orig'));p['rows'][2]['book_id']=None;json.dump(p,open('$t/plan.json','w'))"
python3 "$apply" --plan "$t" --cli "$cli" > /dev/null 2>&1; rc=$?
assert_eq "$rc" "2" "null book_id refuses"
assert_eq "$(cat "$FAKE_CLI_DIR/calls.log" 2>/dev/null)" "" "nothing called"
edit "del p['shelf_checked']"
err="$(python3 "$apply" --plan "$t" --cli "$cli" 2>&1)"; rc=$?
assert_eq "$rc" "2" "a plan check_shelf.sh never stamped refuses"
assert_contains "$err" "check_shelf" "says to run check_shelf.sh"
reset; edit "p['rows'][0].update(disposition='skip', book_id=None)"
err="$(python3 "$apply" --plan "$t" --cli "$cli" 2>&1)"; rc=$?
assert_eq "$rc" "2" "variant whose parent row has no id and no of_id refuses"
assert_contains "$err" "Core/A (print).pdf" "names the variant"
reset
echo '{"id": "sys1", "books": [{"id": "id-a", "category": null}]}' > "$R/systems-get.json"
echo '{"game_system": {"id": "sys1"}, "category": null}' > "$R/books-get.json"
cp "$t/plan.orig" "$t/plan.json"
err="$(python3 "$apply" --plan "$t" --cli "$cli" 2>&1)"; rc=$?
assert_eq "$rc" "2" "a new row without a category refuses"
assert_contains "$err" "category" "says why"
assert_eq "$(grep -cE '^(books batch|duplicates)' "$FAKE_CLI_DIR/calls.log")" "0" "nothing written"

# the real run
reset; cp "$t/plan.orig" "$t/plan.json"
out="$(python3 "$apply" --plan "$t" --cli "$cli" 2>&1)"; rc=$?
assert_eq "$rc" "0" "clean run exits 0: $out"
items="$(body 0 "['items']")"
assert_eq "$(body 0 "['items'][0]")" '{"id": "id-a", "title": "A", "year": 2020, "tags": ["core", "x"]}' "new row: full metadata, category tag first"
assert_eq "$(body 0 "['items'][1]")" '{"id": "id-p", "description": "d", "publisher": "Example Press"}' \
  "diffed row: missing + approved differs only, no tags (batch-update would replace the server's)"
assert_eq "$(body 1 "")" '{"ids": ["id-p"], "tags": ["y"]}' "diffed row's adds go through additive batch-tag"
assert_eq "$(grep -c 'id-v3' <<<"$items")" "0" "a row with nothing writable is not sent"
assert_eq "$(grep -c '^duplicates link' "$FAKE_CLI_DIR/calls.log")" "2" "one link call per parent"
assert_eq "$(body 2 "")" '{"resource_type": "book", "parent_id": "id-a", "children": [{"id": "id-v1", "kind": "printer-friendly", "label": "Print"}]}' \
  "variant linked to the plan parent; the differs variant is not"
assert_eq "$(body 3 "['parent_id']")" '"id-shelf"' "variant linked to a shelf parent via of_id"
assert_contains "$(grep id-v3 "$t/receipts-apply.ndjson")" '"deferred"' "differs variant deferred in the receipts"

# re-run: everything ok already, nothing written again
: > "$FAKE_CLI_DIR/calls.log"
python3 "$apply" --plan "$t" --cli "$cli" > /dev/null 2>&1; rc=$?
assert_eq "$rc" "0" "re-run exits 0"
assert_eq "$(grep -cE '^(books batch-|duplicates link)' "$FAKE_CLI_DIR/calls.log")" "0" "re-run writes nothing"

# a partial link (exit 3) is a row failure, retried on the next run
reset
echo '{"linked": [], "errors": [{"id": "id-v2", "detail": "kind refused"}]}' > "$R/duplicates-link.json"
echo 3 > "$FAKE_CLI_DIR/exit/duplicates-link"
python3 "$apply" --plan "$t" --cli "$cli" > /dev/null 2>&1; rc=$?
assert_eq "$rc" "1" "a partial link exits 1"
assert_contains "$(grep id-v2 "$t/receipts-apply.ndjson")" '"failed"' "failed child recorded"

# batch-update exit 3: the failed row's receipt carries its own error
reset
echo '{"updated": ["id-p", "id-v1", "id-v2"], "errors": [{"id": "id-a", "detail": "bad year"}]}' > "$R/books-batch-update.json"
echo 3 > "$FAKE_CLI_DIR/exit/books-batch-update"
python3 "$apply" --plan "$t" --cli "$cli" > /dev/null 2>&1; rc=$?
assert_eq "$rc" "1" "a partial batch-update exits 1"
assert_contains "$(grep '"update"' "$t/receipts-apply.ndjson" | grep id-a)" "bad year" "row receipt carries its own error"
report
