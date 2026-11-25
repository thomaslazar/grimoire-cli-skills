#!/usr/bin/env bash
# make_folders.py and upload.py against the fake CLI.
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../../.." && pwd)"
. "$repo/tests/lib/assert.sh"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
cd "$t"  # no grimoire-skills.json above: ocr mode server
export FAKE_CLI_DIR="$t/fake"
cli="$repo/tests/lib/fake_cli.sh"
mkdir -p "$FAKE_CLI_DIR/responses" "$FAKE_CLI_DIR/exit"
printf 'abc' > "$t/a.pdf"; printf 'abcde' > "$t/b.pdf"
cat > "$t/plan.json" <<JSON
{"system_path": "books/Starfall RPG/1 EN", "rows": [
 {"source": "$t/a.pdf", "target": "Core/A.pdf", "disposition": "new"},
 {"source": "$t/b.pdf", "target": "Core/B.pdf", "disposition": "new"},
 {"source": "$t/a.pdf", "target": "Core/C.pdf", "disposition": "present"}]}
JSON
echo '{"entries": [{"name": "A.pdf", "size": 3}, {"name": "B.pdf", "size": 5}]}' \
  > "$FAKE_CLI_DIR/responses/files-browse__books_Starfall_RPG_1_EN_Core.json"
echo 2 > "$FAKE_CLI_DIR/exit/files-upload.2"   # second upload: 409, file already there

out="$(python3 "$here/../upload.py" --plan "$t" --cli "$cli" 2>&1)"; rc=$?
assert_eq "$rc" "0" "upload exits 0"
assert_contains "$out" "uploaded 1, skipped 1, failed 0" "one fresh, one 409 that matches the server size"
assert_eq "$(grep -c '^files upload' "$FAKE_CLI_DIR/calls.log")" "2" "the present row is not uploaded"
assert_contains "$(cat "$FAKE_CLI_DIR/calls.log")" "--on-conflict skip" "skip policy"
[ -L "$t/stage/0000/A.pdf" ]; assert_eq "$?" "0" "staged through a symlink named like the target"

# a re-run takes the rows from the receipts
: > "$FAKE_CLI_DIR/calls.log"
python3 "$here/../upload.py" --plan "$t" --cli "$cli" > /dev/null 2>&1
assert_eq "$(grep -c '^files upload' "$FAKE_CLI_DIR/calls.log")" "0" "resumed run uploads nothing"

# a 409 with a different size on the server is a failure
rm -rf "$t/stage" "$t"/receipts-*; rm -f "$FAKE_CLI_DIR/exit/files-upload.2"
echo 2 > "$FAKE_CLI_DIR/exit/files-upload.1"
echo '{"entries": [{"name": "A.pdf", "size": 99}, {"name": "B.pdf", "size": 5}]}' \
  > "$FAKE_CLI_DIR/responses/files-browse__books_Starfall_RPG_1_EN_Core.json"
out="$(python3 "$here/../upload.py" --plan "$t" --cli "$cli" 2>&1)"; rc=$?
assert_eq "$rc" "1" "a wrong size on the server exits 1"
assert_contains "$out" "uploaded 1, skipped 0, failed 1" "wrong-size 409 is a failure"

# ocr: handover -> upload refuses rows whose OCR is not resolved
h="$t/ho"; mkdir -p "$h/run/ocr"; echo '{"ocr": "handover"}' > "$h/grimoire-skills.json"
printf 'xyz' > "$h/scan.pdf"; printf 'xyz' > "$h/run/ocr/000-scan.pdf"
cat > "$h/run/plan.json" <<JSON
{"system_path": "books/Starfall RPG/1 EN", "rows": [
 {"source": "$h/scan.pdf", "target": "Core/Scan.pdf", "disposition": "new"},
 {"source": "$t/a.pdf", "target": "Core/A.pdf", "disposition": "new"}]}
JSON
: > "$FAKE_CLI_DIR/calls.log"
out="$(cd "$h" && python3 "$here/../upload.py" --plan "$h/run" --cli "$cli" 2>&1)"; rc=$?
assert_eq "$rc" "2" "handover mode without a survey refuses"
assert_contains "$out" "ocr-survey.json is missing" "names the missing survey"
echo '{"Core/Scan.pdf": {"text": "junk"}, "Core/A.pdf": {"text": "full"}}' > "$h/run/ocr-survey.json"
out="$(cd "$h" && python3 "$here/../upload.py" --plan "$h/run" --cli "$cli" 2>&1)"; rc=$?
assert_eq "$rc" "2" "an unresolved junk row refuses"
assert_contains "$out" "Core/Scan.pdf" "names the row"
assert_eq "$(grep -c '^files upload' "$FAKE_CLI_DIR/calls.log")" "0" "nothing uploaded on refusal"
echo '{"entries": [{"name": "Scan.pdf", "size": 3}, {"name": "A.pdf", "size": 3}]}' \
  > "$FAKE_CLI_DIR/responses/files-browse__books_Starfall_RPG_1_EN_Core.json"
rm -f "$FAKE_CLI_DIR"/exit/files-upload.*
out="$(cd "$h" && python3 "$here/../upload.py" --plan "$h/run" --cli "$cli" --no-ocr Core/Scan.pdf 2>&1)"; rc=$?
assert_eq "$rc" "0" "--no-ocr lets the named row go up"
rm -f "$h/run"/receipts-*; rm -rf "$h/run/stage"
python3 - "$h/run/plan.json" "$h/run/ocr/000-scan.pdf" <<'PY'
import json, sys
p = json.load(open(sys.argv[1])); p["rows"][0]["source"] = sys.argv[2]; json.dump(p, open(sys.argv[1], "w"))
PY
out="$(cd "$h" && python3 "$here/../upload.py" --plan "$h/run" --cli "$cli" 2>&1)"; rc=$?
assert_eq "$rc" "0" "a row resolved to its OCR output goes up"

# make_folders: creates the missing levels, parent first, with container kinds
rm -rf "$FAKE_CLI_DIR"; mkdir -p "$FAKE_CLI_DIR/responses" "$FAKE_CLI_DIR/exit"
echo 1 > "$FAKE_CLI_DIR/exit/files-browse__books_Starfall_RPG"
echo 1 > "$FAKE_CLI_DIR/exit/files-browse__books_Starfall_RPG_1_EN"
echo 1 > "$FAKE_CLI_DIR/exit/files-browse__books_Starfall_RPG_1_EN_Core"
python3 - "$t/plan.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1]))
p["structure"] = {"create": [{"path": "books/Starfall RPG", "container_kind": "family"}]}
json.dump(p, open(sys.argv[1], "w"))
PY
rm -f "$t"/receipts-*
out="$(python3 "$here/../make_folders.py" --plan "$t" --cli "$cli" 2>&1)"; rc=$?
assert_eq "$rc" "0" "make_folders exits 0"
creates="$(grep '^files folder create' "$FAKE_CLI_DIR/calls.log")"
assert_eq "$creates" "files folder create --parent books --name Starfall RPG --container-kind family
files folder create --parent books/Starfall RPG --name 1 EN
files folder create --parent books/Starfall RPG/1 EN --name Core" "levels created parent first, container kind only where planned"
report
