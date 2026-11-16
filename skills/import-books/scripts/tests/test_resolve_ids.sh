#!/usr/bin/env bash
# resolve_ids.py: ids from files browse; one scoped rescan when the watcher is late.
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../../.." && pwd)"
. "$repo/tests/lib/assert.sh"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
export FAKE_CLI_DIR="$t/fake"
cli="$repo/tests/lib/fake_cli.sh"
mkdir -p "$FAKE_CLI_DIR/responses"
cat > "$t/plan.json" <<JSON
{"system_path": "books/Starfall RPG/1 EN", "rows": [
 {"source": "/x/a.pdf", "target": "Core/A.pdf", "disposition": "new", "book_id": null},
 {"source": "/x/b.pdf", "target": "Core/B.pdf", "disposition": "new", "book_id": null}]}
JSON
f="$FAKE_CLI_DIR/responses/files-browse__books_Starfall_RPG_1_EN_Core"
echo '{"entries": [{"name": "A.pdf", "record_id": "id-a"}, {"name": "B.pdf", "record_id": "id-b"}]}' > "$f.json"
out="$(python3 "$here/../resolve_ids.py" --plan "$t" --cli "$cli" --wait 5 --interval 0 2>&1)"; rc=$?
assert_eq "$rc" "0" "all ids present"
assert_eq "$(python3 -c "import json;print([r['book_id'] for r in json.load(open('$t/plan.json'))['rows']])")" "['id-a', 'id-b']" "ids written to plan.json"
assert_eq "$(grep -c '^library rescan' "$FAKE_CLI_DIR/calls.log" 2>/dev/null)" "0" "no rescan when the watcher was on time"

# B shows up only after the timeout: exactly one scoped rescan, then ids resolve
python3 - "$t/plan.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1]))
for r in p["rows"]: r["book_id"] = None
json.dump(p, open(sys.argv[1], "w"))
PY
rm -f "$f.json"; : > "$FAKE_CLI_DIR/calls.log"; rm -rf "$FAKE_CLI_DIR/.counts"
echo '{"entries": [{"name": "A.pdf", "record_id": "id-a"}, {"name": "B.pdf"}]}' > "$f.1.json"
echo '{"entries": [{"name": "A.pdf", "record_id": "id-a"}, {"name": "B.pdf", "record_id": "id-b"}]}' > "$f.json"
out="$(python3 "$here/../resolve_ids.py" --plan "$t" --cli "$cli" --wait 0 --interval 0 2>&1)"; rc=$?
assert_eq "$rc" "0" "ids resolve after the rescan"
assert_eq "$(grep -c '^library rescan' "$FAKE_CLI_DIR/calls.log")" "1" "exactly one rescan"
assert_contains "$(grep '^library rescan' "$FAKE_CLI_DIR/calls.log")" "--scope books/Starfall RPG/1 EN --metadata-mode new" "scoped, mode new"

# never indexed: still one rescan, then exit 2
rm -f "$f.1.json"
echo '{"entries": [{"name": "A.pdf", "record_id": "id-a"}, {"name": "B.pdf"}]}' > "$f.json"
python3 - "$t/plan.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1]))
for r in p["rows"]: r["book_id"] = None
json.dump(p, open(sys.argv[1], "w"))
PY
: > "$FAKE_CLI_DIR/calls.log"
python3 "$here/../resolve_ids.py" --plan "$t" --cli "$cli" --wait 0 --interval 0 > /dev/null 2>&1; rc=$?
assert_eq "$rc" "2" "unresolved ids exit 2"
assert_eq "$(grep -c '^library rescan' "$FAKE_CLI_DIR/calls.log")" "1" "one rescan only"
report
