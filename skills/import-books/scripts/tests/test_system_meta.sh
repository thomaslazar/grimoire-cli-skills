#!/usr/bin/env bash
# system_meta.py: systems update from plan["system"], then the cover from a plan row's book.
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../../.." && pwd)"
. "$repo/tests/lib/assert.sh"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
export FAKE_CLI_DIR="$t/fake"
cli="$repo/tests/lib/fake_cli.sh"
mkdir -p "$FAKE_CLI_DIR/responses"
echo '{"id": "id-a", "game_system": {"id": "sys1"}}' > "$FAKE_CLI_DIR/responses/books-get.json"
echo '{"id": "sys1"}' > "$FAKE_CLI_DIR/responses/systems-update.json"

cat > "$t/plan.json" <<'JSON'
{"system_path": "books/Starfall RPG/1 EN",
 "system": {"name": "Starfall RPG 1 EN", "parent_system": "Starfall RPG", "edition": "1 EN", "genres": ["Science Fiction"],
            "publishers": [{"name": "Example Press", "url": ""}], "license": "Proprietary", "description": "A game.",
            "dice": ["D6"], "cover_book_target": "Core/B.pdf"},
 "rows": [
 {"target": "Core/A.pdf", "book_id": "id-a", "variant": null},
 {"target": "Core/B.pdf", "book_id": "id-b", "variant": null}]}
JSON
cp "$t/plan.json" "$t/plan.orig"

out="$(python3 "$here/../system_meta.py" --plan "$t" --cli "$cli" 2>&1)"; rc=$?
assert_eq "$rc" "0" "exits 0: $out"
assert_contains "$(cat "$FAKE_CLI_DIR/calls.log")" "books get --id id-a" "system resolved from the first row's book"
assert_contains "$(cat "$FAKE_CLI_DIR/calls.log")" "systems update --id sys1 --stdin" "update sent to that system"
assert_eq "$(head -1 "$FAKE_CLI_DIR/stdin.log")" \
  '{"name": "Starfall RPG 1 EN", "parent_system": "Starfall RPG", "edition": "1 EN", "genres": ["Science Fiction"], "publishers": [{"name": "Example Press", "url": ""}], "license": "Proprietary", "description": "A game.", "dice_materials": ["D6"]}' \
  "update body from plan.system, dice as dice_materials"
assert_contains "$(cat "$FAKE_CLI_DIR/calls.log")" "systems cover from-source --id sys1 --source-type book --source-id id-b" "cover from the cover row's book"
assert_eq "$(python3 -c "import json;print(json.load(open('$t/plan.json'))['system_id'])")" "sys1" "system_id written to plan.json"

# a cover target that is not a plan row refuses before anything is written
python3 -c "import json;p=json.load(open('$t/plan.orig'));p['system']['cover_book_target']='Core/Z.pdf';json.dump(p,open('$t/plan.json','w'))"
: > "$FAKE_CLI_DIR/calls.log"
python3 "$here/../system_meta.py" --plan "$t" --cli "$cli" > /dev/null 2>&1; rc=$?
assert_eq "$rc" "2" "unknown cover target refuses"
assert_eq "$(grep -c '^systems' "$FAKE_CLI_DIR/calls.log")" "0" "nothing written"
report
