#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../../.." && pwd)"
. "$repo/tests/lib/assert.sh"
script="$here/../check_shelf.sh"
cli="$repo/tests/lib/fake_cli.sh"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/responses"
export FAKE_CLI_DIR="$tmp"

printf 'a.pdf\tCore/A.pdf\nb.pdf\tHandouts/B.pdf\n' > "$tmp/m.tsv"

# What the live server actually answers for a path that is not there (verified
# 2026-09-08). It is an error exit with a message, never an empty listing.
notfound='2026-09-08T16:53:46Z ERROR Not found. No such path in the library. List a folder with: grimoire-cli files browse --path <path>'

# Test 1: Greenfield -- books/ exists and is empty, every level below it is
# absent, and absent means the browse FAILS. This is the skill's first
# advertised trigger, so it must survive that without a precondition error.
mkdir -p "$tmp/exit" "$tmp/stderr"
echo '[]' > "$tmp/responses/systems-list.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books.json"
for lvl in books_Fam books_Fam_Line books_Fam_Line_5_DE; do
  echo '2' > "$tmp/exit/files-browse__$lvl"
  printf '%s\n' "$notfound" > "$tmp/stderr/files-browse__$lvl"
done

out="$(bash "$script" --manifest "$tmp/m.tsv" --system-path "books/Fam/Line/5 DE" --cli "$cli")"
assert_eq "$?" "0" "greenfield check exits 0 though every level is not found"
create="$(jq -c '.structure.create' <<<"$out")"
assert_eq "$(jq -c '.[] | select(.path=="books/Fam") | .container_kind' <<<"$create")" '"family"' \
  "a not-found ancestor goes to create, like an absent one"
assert_eq "$(jq -c '.[] | select(.path=="books/Fam/Line") | .container_kind' <<<"$create")" '"parent"' \
  "the level below a not-found ancestor is planned too"
assert_eq "$(jq -c '.existing_books' <<<"$out")" '0' "a not-found system holds no books"

# Proper assertions, not vacuous
dispositions="$(jq -c '.dispositions' <<<"$out")"
assert_eq "$(jq -c '.[] | select(.target=="Core/A.pdf") | .disposition' <<<"$dispositions")" '"new"' "Core/A.pdf is new"
assert_eq "$(jq -c '.[] | select(.target=="Handouts/B.pdf") | .disposition' <<<"$dispositions")" '"new"' "Handouts/B.pdf is new"

needed="$(jq -c '.structure.scaffold.needed' <<<"$out")"
assert_eq "$needed" '["Core","Handouts"]' "scaffold.needed has the right categories"
assert_eq "$(jq -c '.structure.scaffold.run' <<<"$out")" 'true' "scaffold.run is true when needed"
assert_eq "$(jq -c '.structure.conflicts' <<<"$out")" '[]' "no conflicts on greenfield"

# Test 2: Ancestor with wrong container_kind
rm "$tmp/responses/"*
rm -rf "$tmp/exit" "$tmp/stderr" "$tmp/.counts"
echo '[]' > "$tmp/responses/systems-list.json"
echo '{"entries":[{"name":"Fam","is_dir":true,"container_kind":""}]}' > "$tmp/responses/files-browse__books.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam_Line.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam_Line_5_DE.json"

out="$(bash "$script" --manifest "$tmp/m.tsv" --system-path "books/Fam/Line/5 DE" --cli "$cli")"
conflicts="$(jq -c '.structure.conflicts' <<<"$out")"
assert_eq "$(jq -c 'length' <<<"$conflicts")" '1' "exactly one conflict for wrong container_kind"
assert_contains "$conflicts" 'expected_container_kind' "conflict records expected container_kind"

# Test 3: Missing ancestor -> create, existing ancestor -> reuse
rm "$tmp/responses/"*
echo '[]' > "$tmp/responses/systems-list.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books.json"
echo '{"entries":[{"name":"Line","is_dir":true,"container_kind":"parent"}]}' > "$tmp/responses/files-browse__books_Fam.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam_Line.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam_Line_5_DE.json"

out="$(bash "$script" --manifest "$tmp/m.tsv" --system-path "books/Fam/Line/5 DE" --cli "$cli")"
create="$(jq -c '.structure.create' <<<"$out")"
assert_eq "$(jq -c '.[] | select(.path=="books/Fam") | .container_kind' <<<"$create")" '"family"' "missing Fam is in create"
reuse="$(jq -c '.structure.reuse' <<<"$out")"
assert_eq "$(jq -c '.[] | select(.path=="books/Fam/Line") | .container_kind' <<<"$reuse")" '"parent"' "existing Line is in reuse"

# Test 4: a realistic shelf -- books sit inside category folders, never at the
# system root, so the walk must descend a level and compare full path with full
# path. Same basename in another category must stay new.
printf 'a.pdf\tCore/Foo.pdf\nb.pdf\tHandouts/Foo.pdf\nc.pdf\tHandouts/Sets/Bar.pdf\n' > "$tmp/m2.tsv"
rm "$tmp/responses/"*
echo '[]' > "$tmp/responses/systems-list.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam_Line.json"
echo '{"entries":[{"name":"Core","is_dir":true},{"name":"Handouts","is_dir":true}]}' \
  > "$tmp/responses/files-browse__books_Fam_Line_5_DE.json"
echo '{"entries":[{"name":"Foo.pdf","is_dir":false,"record_id":"book123"}]}' \
  > "$tmp/responses/files-browse__books_Fam_Line_5_DE_Core.json"
echo '{"entries":[{"name":"Sets","is_dir":true}]}' \
  > "$tmp/responses/files-browse__books_Fam_Line_5_DE_Handouts.json"
echo '{"entries":[{"name":"Bar.pdf","is_dir":false,"record_id":"book456"}]}' \
  > "$tmp/responses/files-browse__books_Fam_Line_5_DE_Handouts_Sets.json"

out="$(bash "$script" --manifest "$tmp/m2.tsv" --system-path "books/Fam/Line/5 DE" --cli "$cli")"
dispositions="$(jq -c '.dispositions' <<<"$out")"
assert_eq "$(jq -c '.[] | select(.target=="Core/Foo.pdf") | .disposition' <<<"$dispositions")" '"skip"' \
  "a file already indexed in its category folder is a skip"
assert_eq "$(jq -c '.[] | select(.target=="Handouts/Foo.pdf") | .disposition' <<<"$dispositions")" '"new"' \
  "the same basename in another category is still new"
assert_eq "$(jq -c '.[] | select(.target=="Handouts/Sets/Bar.pdf") | .disposition' <<<"$dispositions")" '"skip"' \
  "the walk descends past the category level"
assert_eq "$(jq -c '.existing_books' <<<"$out")" '2' "existing_books counts what the shelf already holds"

# Test 5: the line is already filed under a different family. Rows carry the
# server's real shape: a child system is NAMED "<parent leaf> <leaf>" and keyed
# by a slug of its whole path, so "5 DE" never appears as a name.
rm "$tmp/responses/"*
mkdir -p "$tmp/stderr"
echo '[{"name":"Line 5 DE","id":"sys1","slug":"otherfam--line--5-de","container_kind":"system","parent_name":"Line","parent_system":"Line"}]' \
  > "$tmp/responses/systems-list.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam_Line.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam_Line_5_DE.json"

out="$(bash "$script" --manifest "$tmp/m.tsv" --system-path "books/Fam/Line/5 DE" --cli "$cli")"
conflicts="$(jq -c '.structure.conflicts' <<<"$out")"
assert_eq "$(jq -c 'length' <<<"$conflicts")" '1' "the same line under another family is a conflict"
assert_contains "$conflicts" 'a system with this name already exists at a different path' "conflict message identifies the issue"
assert_contains "$conflicts" '"our_slug":"fam--line--5-de"' "the conflict records the slug we derived from the path"

# Test 6: our own system already exists -- same slug, so reuse, not a conflict.
rm "$tmp/responses/"*
echo '[{"name":"Line 5 DE","id":"sys1","slug":"fam--line--5-de","container_kind":"system","parent_name":"Line","parent_system":"Line"}]' \
  > "$tmp/responses/systems-list.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam_Line.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam_Line_5_DE.json"

out="$(bash "$script" --manifest "$tmp/m.tsv" --system-path "books/Fam/Line/5 DE" --cli "$cli")"
conflicts="$(jq -c '.structure.conflicts' <<<"$out")"
assert_eq "$(jq -c 'length' <<<"$conflicts")" '0' "our own system at our own slug is reuse, not a conflict"
assert_eq "$(jq -c '.known_systems[0].slug' <<<"$out")" '"fam--line--5-de"' "known_systems carries the slug the match keys on"

# Test 6b: an unrelated line whose folder leaf happens to be "5 DE" is not a
# conflict. Matching bare leaves would fire on every edition folder in the
# library.
rm "$tmp/responses/"*
echo '[{"name":"Other Game 5 DE","id":"sys9","slug":"other-game--5-de","container_kind":"system","parent_name":"Other Game","parent_system":"Other Game"}]' \
  > "$tmp/responses/systems-list.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam_Line.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam_Line_5_DE.json"
out="$(bash "$script" --manifest "$tmp/m.tsv" --system-path "books/Fam/Line/5 DE" --cli "$cli")"
assert_eq "$(jq -c '.structure.conflicts | length' <<<"$out")" '0' "another line sharing the folder leaf is not a conflict"

# Test 7: Stderr output doesn't corrupt JSON parsing
# The system_path browse returns indexed books; if stderr isn't separated, jq parse fails
rm "$tmp/responses/"*
rm -rf "$tmp/stderr"
mkdir -p "$tmp/stderr"
# Response from system_path browse: contains one indexed book (record_id present)
echo '{"entries":[{"name":"A.pdf","is_dir":false,"record_id":"book1"}]}' > "$tmp/responses/files-browse__books_Fam_Line_5_DE.json"
# Server version check message to stderr (path-scoped fixture, modern fake_cli.sh finds this)
echo 'DEBUG: cached server version check' > "$tmp/stderr/files-browse__books_Fam_Line_5_DE"
echo '[]' > "$tmp/responses/systems-list.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam_Line.json"

out="$(bash "$script" --manifest "$tmp/m.tsv" --system-path "books/Fam/Line/5 DE" --cli "$cli")"
assert_eq "$?" "0" "stderr output from CLI doesn't break script exit"
# existing_books comes from the indexed entries in the system_path browse response
# If stderr corruption occurs, jq parse fails and existing_books is missing
assert_eq "$(jq -c '.existing_books' <<<"$out")" '1' "existing_books correctly parsed despite stderr output"

# Test 8: Error message from failed browse includes stderr text
rm "$tmp/responses/"*
rm -rf "$tmp/stderr" "$tmp/exit" "$tmp/.counts"
mkdir -p "$tmp/stderr" "$tmp/exit"
# Set up systems-list and ancestor browses to succeed
echo '[]' > "$tmp/responses/systems-list.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam.json"
# Make the 3rd files-browse call (system_path) fail using sequenced exit code
# Call sequence: books (1), books/Fam (2), books/Fam/Line/5 DE (3)
echo '1' > "$tmp/exit/files-browse.3"
echo 'error: server connection timeout' > "$tmp/stderr/files-browse.3"

err_output="$(bash "$script" --manifest "$tmp/m.tsv" --system-path "books/Fam/Line/5 DE" --cli "$cli" 2>&1)" || true
assert_contains "$err_output" 'server connection timeout' "error message includes stderr text from failed browse"

# Test 9: systems list is subject to the same stream separation as browse --
# a stderr line merged into its stdout corrupts the JSON handed to jq.
rm "$tmp/responses/"*
rm -rf "$tmp/stderr" "$tmp/stderr_after" "$tmp/exit" "$tmp/.counts"
mkdir -p "$tmp/stderr"
echo '[{"name":"5 DE","id":"sys1","container_kind":"system","parent_system":"books/Fam/Line"}]' > "$tmp/responses/systems-list.json"
echo 'server version check: cached, next due in 23h' > "$tmp/stderr/systems-list"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam_Line.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam_Line_5_DE.json"

out="$(bash "$script" --manifest "$tmp/m.tsv" --system-path "books/Fam/Line/5 DE" --cli "$cli" 2>/dev/null)"
assert_eq "$?" "0" "a stderr line on systems list does not break the run"
assert_eq "$(jq -c '.known_systems | map(.id)' <<<"$out")" '["sys1"]' "known_systems parses despite stderr output"

# Test 10: a failed systems list reports the CLI's own stderr text.
rm -rf "$tmp/stderr" "$tmp/exit" "$tmp/.counts"; mkdir -p "$tmp/stderr" "$tmp/exit"
echo '1' > "$tmp/exit/systems-list"
echo 'error: 401 token expired' > "$tmp/stderr/systems-list"
err_output="$(bash "$script" --manifest "$tmp/m.tsv" --system-path "books/Fam/Line/5 DE" --cli "$cli" 2>&1)" || true
assert_contains "$err_output" '401 token expired' "a failed systems list surfaces its stderr text"

# Test 11: a browse that fails for any OTHER reason is still a precondition
# failure. The not-found signal must not be broadened into "every error means
# the folder is absent" -- that would read a populated shelf as empty.
rm "$tmp/responses/"*
rm -rf "$tmp/stderr" "$tmp/exit" "$tmp/.counts"; mkdir -p "$tmp/stderr" "$tmp/exit"
echo '[]' > "$tmp/responses/systems-list.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books.json"
echo '2' > "$tmp/exit/files-browse__books_Fam"
echo '2026-09-08T16:53:46Z ERROR Unauthorized. Your token has expired.' > "$tmp/stderr/files-browse__books_Fam"

err_real="$(bash "$script" --manifest "$tmp/m.tsv" --system-path "books/Fam/Line/5 DE" --cli "$cli" 2>&1 >/dev/null)"
assert_eq "$?" "2" "a browse failure that is not 'not found' still exits 2"
assert_contains "$err_real" "Your token has expired" "the real failure keeps reporting its stderr text"

# Test 12: a directory that the parent listed but that 404s when descended into
# must not abort the walk either.
rm "$tmp/responses/"*
rm -rf "$tmp/stderr" "$tmp/exit" "$tmp/.counts"; mkdir -p "$tmp/stderr" "$tmp/exit"
echo '[]' > "$tmp/responses/systems-list.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam_Line.json"
echo '{"entries":[{"name":"Core","is_dir":true},{"name":"Handouts","is_dir":true}]}' \
  > "$tmp/responses/files-browse__books_Fam_Line_5_DE.json"
echo '{"entries":[{"name":"Foo.pdf","is_dir":false,"record_id":"book123"}]}' \
  > "$tmp/responses/files-browse__books_Fam_Line_5_DE_Core.json"
echo '2' > "$tmp/exit/files-browse__books_Fam_Line_5_DE_Handouts"
printf '%s\n' "$notfound" > "$tmp/stderr/files-browse__books_Fam_Line_5_DE_Handouts"

out="$(bash "$script" --manifest "$tmp/m2.tsv" --system-path "books/Fam/Line/5 DE" --cli "$cli")"
assert_eq "$?" "0" "a not-found subdirectory does not abort the descent"
dispositions="$(jq -c '.dispositions' <<<"$out")"
assert_eq "$(jq -c '.[] | select(.target=="Core/Foo.pdf") | .disposition' <<<"$dispositions")" '"skip"' \
  "the rest of the walk still resolves after a not-found subdirectory"
assert_eq "$(jq -c '.[] | select(.target=="Handouts/Sets/Bar.pdf") | .disposition' <<<"$dispositions")" '"new"' \
  "nothing under the not-found subdirectory is claimed as present"

# Test 13: systems list is the one call of the four with no stderr_after pin.
# A log line written AFTER the body is what `2>&1` capture actually eats, and
# the before-case leaves the JSON as the last line, so only the after-case
# proves the separation.
rm "$tmp/responses/"*
rm -rf "$tmp/stderr" "$tmp/stderr_after" "$tmp/exit" "$tmp/.counts"
mkdir -p "$tmp/stderr_after"
echo '[{"name":"Line 5 DE","id":"sys1","slug":"fam--line--5-de","parent_name":"Line","parent_system":"Line"}]' \
  > "$tmp/responses/systems-list.json"
echo 'server version check: cached, next due in 23h' > "$tmp/stderr_after/systems-list"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam_Line.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam_Line_5_DE.json"

out="$(bash "$script" --manifest "$tmp/m.tsv" --system-path "books/Fam/Line/5 DE" --cli "$cli" 2>/dev/null)"
assert_eq "$?" "0" "a stderr line after the systems list body does not break the run"
assert_eq "$(jq -c '.known_systems | map(.id)' <<<"$out")" '["sys1"]' "known_systems parses despite a trailing stderr line"
assert_eq "$(jq -c '.structure.conflicts | length' <<<"$out")" '0' "the conflict pass sees the same intact JSON"

# and a genuinely unparseable systems list is a precondition failure, not
# something to half-parse and carry on from
rm -rf "$tmp/stderr_after" "$tmp/.counts"
echo 'not json at all' > "$tmp/responses/systems-list.json"
err_badjson="$(bash "$script" --manifest "$tmp/m.tsv" --system-path "books/Fam/Line/5 DE" --cli "$cli" 2>&1 >/dev/null)"
assert_eq "$?" "2" "an unparseable systems list exits 2"
assert_contains "$err_badjson" "unparseable systems list response" "and says so"

# Test 14: the walk cap. A shelf that keeps reporting one more subdirectory
# would otherwise browse forever; the cap refuses at 8 levels.
rm "$tmp/responses/"*
rm -rf "$tmp/stderr" "$tmp/stderr_after" "$tmp/exit" "$tmp/.counts" "$tmp/calls.log"
echo '[]' > "$tmp/responses/systems-list.json"
# every path with no scoped fixture answers "one more directory below me"
echo '{"entries":[{"name":"deep","is_dir":true}]}' > "$tmp/responses/files-browse.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam.json"

err_deep="$(bash "$script" --manifest "$tmp/m.tsv" --system-path "books/Fam/Line/5 DE" --cli "$cli" 2>&1 >/dev/null)"
assert_eq "$?" "2" "an endlessly nested shelf exits 2 instead of looping"
assert_contains "$err_deep" "nested deeper than 8 levels" "the cap says what it refused"
assert_eq "$(grep -c 'files browse' "$tmp/calls.log" || true)" "11" "the cap stops after 2 ancestors + root + 8 levels"

# --help prints the header comment, and nothing below it
assert_eq "$(bash "$script" --help | grep -c 'set -uo pipefail')" "0" "--help does not leak the set line"

# Test 15: --plan is optional. Without it, output is byte-identical to today's
# -- this is the compatibility pin: other tests and earlier phases call the
# script this way, and the diff machinery must cost them nothing.
rm "$tmp/responses/"*
rm -rf "$tmp/stderr" "$tmp/stderr_after" "$tmp/exit" "$tmp/.counts" "$tmp/calls.log"
echo '[]' > "$tmp/responses/systems-list.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam_Line.json"
echo '{"entries":[{"name":"Core","is_dir":true},{"name":"Handouts","is_dir":true}]}' \
  > "$tmp/responses/files-browse__books_Fam_Line_5_DE.json"
echo '{"entries":[{"name":"Foo.pdf","is_dir":false,"record_id":"book123"}]}' \
  > "$tmp/responses/files-browse__books_Fam_Line_5_DE_Core.json"
echo '{"entries":[{"name":"Sets","is_dir":true}]}' \
  > "$tmp/responses/files-browse__books_Fam_Line_5_DE_Handouts.json"
echo '{"entries":[{"name":"Bar.pdf","is_dir":false,"record_id":"book456"}]}' \
  > "$tmp/responses/files-browse__books_Fam_Line_5_DE_Handouts_Sets.json"
baseline='{"known_systems":[],"dispositions":[{"target":"Core/Foo.pdf","disposition":"skip"},{"target":"Handouts/Foo.pdf","disposition":"new"},{"target":"Handouts/Sets/Bar.pdf","disposition":"skip"}],"structure":{"create":[{"path":"books/Fam","container_kind":"family"},{"path":"books/Fam/Line","container_kind":"parent"}],"reuse":[],"scaffold":{"needed":["Core","Handouts"],"present":["Core","Handouts"],"run":false},"conflicts":[]},"existing_books":2}'
out="$(bash "$script" --manifest "$tmp/m2.tsv" --system-path "books/Fam/Line/5 DE" --cli "$cli")"
assert_eq "$out" "$baseline" "without --plan the output is byte-identical to today's"
assert_eq "$(grep -c 'books get\|books-get' "$tmp/calls.log" 2>/dev/null || true)" "0" "no --plan means no books get calls at all"

# The gate itself: a mutated `if [ -n "$plan" ]` -> `if true` leaves stdout
# untouched here (an empty $plan makes `cat ""` fail and `jq empty` on the
# resulting empty string a zero-iteration no-op, so the diff machinery
# silently computes nothing) -- but `cat ""` still writes its own error to
# stderr. The correctly-gated script writes nothing to stderr at all on this
# path, so that is the assertion that actually distinguishes the two.
err_noplan="$(bash "$script" --manifest "$tmp/m2.tsv" --system-path "books/Fam/Line/5 DE" --cli "$cli" 2>&1 >/dev/null)"
assert_eq "$err_noplan" "" "without --plan the script writes nothing to stderr"

# Test 16: a shelf copy that matches the plan exactly is skip, with an
# empty-writable diff (nothing missing, nothing that adds, nothing that
# differs).
rm "$tmp/responses/"*
rm -rf "$tmp/stderr" "$tmp/exit" "$tmp/.counts" "$tmp/calls.log"
printf 'a.pdf\tCore/A.pdf\n' > "$tmp/m3.tsv"
echo '[]' > "$tmp/responses/systems-list.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam_Line.json"
echo '{"entries":[{"name":"Core","is_dir":true}]}' > "$tmp/responses/files-browse__books_Fam_Line_5_DE.json"
echo '{"entries":[{"name":"A.pdf","is_dir":false,"record_id":"bookX"}]}' \
  > "$tmp/responses/files-browse__books_Fam_Line_5_DE_Core.json"
cat > "$tmp/plan.json" <<'EOF'
{"system_path": "books/Fam/Line/5 DE", "rows": [
  {"target": "Core/A.pdf",
   "metadata": {"title": "The Title", "description": "Desc", "isbn": "9780000000000",
                "language": "de", "year": 2020, "month": 1, "day": 2,
                "publisher": "Pub", "authors": ["Author One", "Author Two"]},
   "tags": ["core"],
   "variant": null}
]}
EOF
cat > "$tmp/responses/books-get.json" <<'EOF'
{"title": "The Title", "description": "Desc", "isbn": "9780000000000",
 "language": "de", "year": 2020, "month": 1, "day": 2,
 "publisher": "Pub", "authors": ["Author One", "Author Two"],
 "tags": ["core"], "variant_parent_id": null, "variant_kind": null}
EOF
out="$(bash "$script" --manifest "$tmp/m3.tsv" --system-path "books/Fam/Line/5 DE" --cli "$cli" --plan "$tmp/plan.json")"
row="$(jq -c '.dispositions[] | select(.target=="Core/A.pdf")' <<<"$out")"
assert_eq "$(jq -r '.disposition' <<<"$row")" "skip" "a shelf copy matching the plan exactly is skip"
assert_eq "$(jq -r '.book_id' <<<"$row")" "bookX" "the matched row carries its book_id"
assert_eq "$(jq -c '.diff | [.[] | .verdict] | unique - ["same","absent_both"]' <<<"$row")" '[]' \
  "every field verdict is same or absent_both -- nothing writable"

# Test 17: an empty shelf description with a plan value is present, with
# description: missing.
rm "$tmp/responses/books-get.json"
cat > "$tmp/responses/books-get.json" <<'EOF'
{"title": "The Title", "description": null, "isbn": "9780000000000",
 "language": "de", "year": 2020, "month": 1, "day": 2,
 "publisher": "Pub", "authors": ["Author One", "Author Two"],
 "tags": ["core"], "variant_parent_id": null, "variant_kind": null}
EOF
out="$(bash "$script" --manifest "$tmp/m3.tsv" --system-path "books/Fam/Line/5 DE" --cli "$cli" --plan "$tmp/plan.json")"
row="$(jq -c '.dispositions[] | select(.target=="Core/A.pdf")' <<<"$out")"
assert_eq "$(jq -r '.disposition' <<<"$row")" "present" "a missing field makes the row present"
assert_eq "$(jq -c '.diff.description' <<<"$row")" '{"verdict":"missing"}' \
  "an empty shelf field with a plan value is missing"

# Test 18: both hold a value and they disagree -- present, with differs
# carrying both values in full.
rm "$tmp/responses/books-get.json"
cat > "$tmp/responses/books-get.json" <<'EOF'
{"title": "The Title", "description": "Shelf wrote this one", "isbn": "9780000000000",
 "language": "de", "year": 2020, "month": 1, "day": 2,
 "publisher": "Pub", "authors": ["Author One", "Author Two"],
 "tags": ["core"], "variant_parent_id": null, "variant_kind": null}
EOF
out="$(bash "$script" --manifest "$tmp/m3.tsv" --system-path "books/Fam/Line/5 DE" --cli "$cli" --plan "$tmp/plan.json")"
row="$(jq -c '.dispositions[] | select(.target=="Core/A.pdf")' <<<"$out")"
assert_eq "$(jq -r '.disposition' <<<"$row")" "present" "a disagreeing field makes the row present"
assert_eq "$(jq -c '.diff.description' <<<"$row")" '{"verdict":"differs","shelf":"Shelf wrote this one","plan":"Desc"}' \
  "differs carries both the shelf's and the plan's value"

# Test 19: tags never produce differs -- only adds (what the plan would add
# that the shelf lacks) or same.
rm "$tmp/responses/books-get.json"
cat > "$tmp/responses/books-get.json" <<'EOF'
{"title": "The Title", "description": "Desc", "isbn": "9780000000000",
 "language": "de", "year": 2020, "month": 1, "day": 2,
 "publisher": "Pub", "authors": ["Author One", "Author Two"],
 "tags": ["character-sheet"], "variant_parent_id": null, "variant_kind": null}
EOF
cat > "$tmp/plan.json" <<'EOF'
{"system_path": "books/Fam/Line/5 DE", "rows": [
  {"target": "Core/A.pdf",
   "metadata": {"title": "The Title", "description": "Desc", "isbn": "9780000000000",
                "language": "de", "year": 2020, "month": 1, "day": 2,
                "publisher": "Pub", "authors": ["Author One", "Author Two"]},
   "tags": ["character-sheet", "sku:ex10042"],
   "variant": null}
]}
EOF
out="$(bash "$script" --manifest "$tmp/m3.tsv" --system-path "books/Fam/Line/5 DE" --cli "$cli" --plan "$tmp/plan.json")"
row="$(jq -c '.dispositions[] | select(.target=="Core/A.pdf")' <<<"$out")"
assert_eq "$(jq -c '.diff.tags' <<<"$row")" '{"verdict":"adds","add":["sku:ex10042"],"shelf":["character-sheet"]}' \
  "a tag the plan has and the shelf lacks is adds, carrying the shelf's current list"
assert_eq "$(jq -r '.disposition' <<<"$row")" "present" "a tag to add makes the row present"

# Test 20: a shelf variant linked to a different parent than the plan intends
# is variant: differs, carrying both parent ids. Never re-parented silently.
rm "$tmp/responses/"*
rm -rf "$tmp/stderr" "$tmp/exit" "$tmp/.counts" "$tmp/calls.log"
printf 'child.pdf\tCore/Child.pdf\nparent.pdf\tCore/ParentB.pdf\n' > "$tmp/m4.tsv"
echo '[]' > "$tmp/responses/systems-list.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam_Line.json"
echo '{"entries":[{"name":"Core","is_dir":true}]}' > "$tmp/responses/files-browse__books_Fam_Line_5_DE.json"
echo '{"entries":[{"name":"Child.pdf","is_dir":false,"record_id":"childId"},{"name":"ParentB.pdf","is_dir":false,"record_id":"parentBId"}]}' \
  > "$tmp/responses/files-browse__books_Fam_Line_5_DE_Core.json"
cat > "$tmp/plan.json" <<'EOF'
{"system_path": "books/Fam/Line/5 DE", "rows": [
  {"target": "Core/Child.pdf",
   "metadata": {"title": "Child"},
   "tags": [],
   "variant": {"of": "Core/ParentB.pdf", "kind": "version", "label": "First Printing"}}
]}
EOF
cat > "$tmp/responses/books-get.json" <<'EOF'
{"title": "Child", "tags": [], "variant_parent_id": "parentAId", "variant_kind": "version"}
EOF
out="$(bash "$script" --manifest "$tmp/m4.tsv" --system-path "books/Fam/Line/5 DE" --cli "$cli" --plan "$tmp/plan.json")"
row="$(jq -c '.dispositions[] | select(.target=="Core/Child.pdf")' <<<"$out")"
assert_eq "$(jq -c '.diff.variant' <<<"$row")" '{"verdict":"differs","shelf":"parentAId","plan":"parentBId"}' \
  "a variant linked to a different parent is differs, carrying both parent ids"
assert_eq "$(jq -r '.disposition' <<<"$row")" "present" "a variant conflict makes the row present"
assert_eq "$(grep -c 'books get\|books-get' "$tmp/calls.log" 2>/dev/null || true)" "1" \
  "only the row with a matching plan entry is fetched -- ParentB.pdf has none"

# Test 21 (fix round 1, CRITICAL): a shelf row that is itself a variant
# PARENT reads variant_main_id = its own id -- verified against the live
# server. Reading that field as "am I linked" would make every parent look
# linked to itself and misreport a conflict on every re-run. variant_parent_id
# is null on a parent (and on an unlinked row); that is the field that must
# gate "is this a variant of something".
rm "$tmp/responses/"*
rm -rf "$tmp/stderr" "$tmp/exit" "$tmp/.counts" "$tmp/calls.log"
printf 'a.pdf\tCore/A.pdf\n' > "$tmp/m5.tsv"
echo '[]' > "$tmp/responses/systems-list.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam_Line.json"
echo '{"entries":[{"name":"Core","is_dir":true}]}' > "$tmp/responses/files-browse__books_Fam_Line_5_DE.json"
echo '{"entries":[{"name":"A.pdf","is_dir":false,"record_id":"selfId"}]}' \
  > "$tmp/responses/files-browse__books_Fam_Line_5_DE_Core.json"
cat > "$tmp/plan.json" <<'EOF'
{"system_path": "books/Fam/Line/5 DE", "rows": [
  {"target": "Core/A.pdf", "metadata": {"title": "Parent"}, "tags": [], "variant": null}
]}
EOF
# The live shape of a variant PARENT: variant_main_id is its OWN id,
# variant_parent_id is null.
cat > "$tmp/responses/books-get.json" <<'EOF'
{"title": "Parent", "tags": [], "variant_main_id": "selfId", "variant_parent_id": null, "variant_kind": null}
EOF
out="$(bash "$script" --manifest "$tmp/m5.tsv" --system-path "books/Fam/Line/5 DE" --cli "$cli" --plan "$tmp/plan.json")"
row="$(jq -c '.dispositions[] | select(.target=="Core/A.pdf")' <<<"$out")"
assert_eq "$(jq -c '.diff.variant' <<<"$row")" '{"verdict":"absent_both"}' \
  "a variant PARENT row (variant_main_id = its own id) is not misread as linked to itself"
assert_eq "$(jq -r '.disposition' <<<"$row")" "skip" "a parent row with no plan-side variant intent is skip"

# Test 22 (fix round 1, CRITICAL, child shape): a shelf CHILD row correctly
# matches the plan's resolved parent via variant_parent_id.
rm "$tmp/responses/"*
rm -rf "$tmp/stderr" "$tmp/exit" "$tmp/.counts" "$tmp/calls.log"
printf 'child.pdf\tCore/Child.pdf\nparent.pdf\tCore/Parent.pdf\n' > "$tmp/m6.tsv"
echo '[]' > "$tmp/responses/systems-list.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam_Line.json"
echo '{"entries":[{"name":"Core","is_dir":true}]}' > "$tmp/responses/files-browse__books_Fam_Line_5_DE.json"
echo '{"entries":[{"name":"Child.pdf","is_dir":false,"record_id":"childId"},{"name":"Parent.pdf","is_dir":false,"record_id":"parentId"}]}' \
  > "$tmp/responses/files-browse__books_Fam_Line_5_DE_Core.json"
cat > "$tmp/plan.json" <<'EOF'
{"system_path": "books/Fam/Line/5 DE", "rows": [
  {"target": "Core/Child.pdf",
   "metadata": {"title": "Child"},
   "tags": [],
   "variant": {"of": "Core/Parent.pdf", "kind": "version", "label": "First Printing"}}
]}
EOF
# The live shape of a variant CHILD: variant_main_id and variant_parent_id
# both hold the parent's id.
cat > "$tmp/responses/books-get.json" <<'EOF'
{"title": "Child", "tags": [], "variant_main_id": "parentId", "variant_parent_id": "parentId", "variant_kind": "version"}
EOF
out="$(bash "$script" --manifest "$tmp/m6.tsv" --system-path "books/Fam/Line/5 DE" --cli "$cli" --plan "$tmp/plan.json")"
row="$(jq -c '.dispositions[] | select(.target=="Core/Child.pdf")' <<<"$out")"
assert_eq "$(jq -c '.diff.variant' <<<"$row")" '{"verdict":"same"}' \
  "a shelf child already linked to the plan's resolved parent, same kind, is same"
assert_eq "$(jq -r '.disposition' <<<"$row")" "skip" "a correctly-linked variant is skip"

# Test 23 (fix round 1, spec deviation): a shelf-held variant link the plan
# does not propose is differs, not same -- a curated relationship must not be
# silently dropped from the walkthrough.
rm "$tmp/responses/"*
rm -rf "$tmp/stderr" "$tmp/exit" "$tmp/.counts" "$tmp/calls.log"
printf 'a.pdf\tCore/A.pdf\n' > "$tmp/m7.tsv"
echo '[]' > "$tmp/responses/systems-list.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam_Line.json"
echo '{"entries":[{"name":"Core","is_dir":true}]}' > "$tmp/responses/files-browse__books_Fam_Line_5_DE.json"
echo '{"entries":[{"name":"A.pdf","is_dir":false,"record_id":"childId"}]}' \
  > "$tmp/responses/files-browse__books_Fam_Line_5_DE_Core.json"
cat > "$tmp/plan.json" <<'EOF'
{"system_path": "books/Fam/Line/5 DE", "rows": [
  {"target": "Core/A.pdf", "metadata": {"title": "A"}, "tags": [], "variant": null}
]}
EOF
cat > "$tmp/responses/books-get.json" <<'EOF'
{"title": "A", "tags": [], "variant_main_id": "curatedParent", "variant_parent_id": "curatedParent", "variant_kind": "other"}
EOF
out="$(bash "$script" --manifest "$tmp/m7.tsv" --system-path "books/Fam/Line/5 DE" --cli "$cli" --plan "$tmp/plan.json")"
row="$(jq -c '.dispositions[] | select(.target=="Core/A.pdf")' <<<"$out")"
assert_eq "$(jq -c '.diff.variant' <<<"$row")" '{"verdict":"differs","shelf":"curatedParent","plan":null}' \
  "a curated shelf variant the plan doesn't propose is differs, carrying shelf and a null plan"
assert_eq "$(jq -r '.disposition' <<<"$row")" "present" "a dropped variant link makes the row present, never silently skip"

# Test 24 (fix round 1, gap): absent_both on a SCALAR field, pinned
# independently of the variant field (which reaches it incidentally today).
rm "$tmp/responses/"*
rm -rf "$tmp/stderr" "$tmp/exit" "$tmp/.counts" "$tmp/calls.log"
printf 'a.pdf\tCore/A.pdf\n' > "$tmp/m8.tsv"
echo '[]' > "$tmp/responses/systems-list.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam_Line.json"
echo '{"entries":[{"name":"Core","is_dir":true}]}' > "$tmp/responses/files-browse__books_Fam_Line_5_DE.json"
echo '{"entries":[{"name":"A.pdf","is_dir":false,"record_id":"bookY"}]}' \
  > "$tmp/responses/files-browse__books_Fam_Line_5_DE_Core.json"
cat > "$tmp/plan.json" <<'EOF'
{"system_path": "books/Fam/Line/5 DE", "rows": [
  {"target": "Core/A.pdf", "metadata": {"title": "A", "isbn": null}, "tags": [], "variant": null}
]}
EOF
cat > "$tmp/responses/books-get.json" <<'EOF'
{"title": "A", "isbn": "", "tags": [], "variant_main_id": null, "variant_parent_id": null, "variant_kind": null}
EOF
out="$(bash "$script" --manifest "$tmp/m8.tsv" --system-path "books/Fam/Line/5 DE" --cli "$cli" --plan "$tmp/plan.json")"
row="$(jq -c '.dispositions[] | select(.target=="Core/A.pdf")' <<<"$out")"
assert_eq "$(jq -c '.diff.isbn' <<<"$row")" '{"verdict":"absent_both"}' \
  "a scalar field empty on both the shelf and the plan is absent_both, not missing"

# Test 25 (fix round 1, gap): the --plan gate itself. Structurally: with no
# --plan, no disposition may carry a "diff" key at all, and no `books get`
# call may be made -- the call log is the cleanest signal that the new
# machinery didn't run.
rm "$tmp/responses/"*
rm -rf "$tmp/stderr" "$tmp/exit" "$tmp/.counts" "$tmp/calls.log"
echo '[]' > "$tmp/responses/systems-list.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam_Line.json"
echo '{"entries":[{"name":"Core","is_dir":true}]}' > "$tmp/responses/files-browse__books_Fam_Line_5_DE.json"
echo '{"entries":[{"name":"A.pdf","is_dir":false,"record_id":"bookZ"}]}' \
  > "$tmp/responses/files-browse__books_Fam_Line_5_DE_Core.json"
out="$(bash "$script" --manifest "$tmp/m8.tsv" --system-path "books/Fam/Line/5 DE" --cli "$cli")"
assert_eq "$(jq -c '[.dispositions[] | has("diff")] | any' <<<"$out")" "false" \
  "with no --plan, no disposition carries a diff key at all"
assert_eq "$(grep -c 'books get' "$tmp/calls.log" 2>/dev/null || true)" "0" \
  "with no --plan, no books get call is made"

# Test 26 (fix round 1, gap): a missing --plan file is a usage refusal (exit 1).
err_noplan="$(bash "$script" --manifest "$tmp/m8.tsv" --system-path "books/Fam/Line/5 DE" --cli "$cli" --plan "$tmp/does-not-exist.json" 2>&1 >/dev/null)"
assert_eq "$?" "1" "a --plan file that does not exist is a usage refusal, exit 1"
assert_contains "$err_noplan" "no such plan" "and says so"

# Test 27 (fix round 1, gap): an unparseable plan is a precondition failure
# (exit 2) -- matching the file's own existing "unparseable systems list"
# convention rather than a silent half-parse.
printf 'not json at all' > "$tmp/plan.json"
err_badplan="$(bash "$script" --manifest "$tmp/m8.tsv" --system-path "books/Fam/Line/5 DE" --cli "$cli" --plan "$tmp/plan.json" 2>&1 >/dev/null)"
assert_eq "$?" "2" "an unparseable plan exits 2"
assert_contains "$err_badplan" "unparseable plan" "and says so"

# Test 28 (fix round 1, gap): a `books get` CLI failure is a precondition
# failure (exit 2), and its stderr text is surfaced.
rm "$tmp/responses/"*
rm -rf "$tmp/stderr" "$tmp/exit" "$tmp/.counts" "$tmp/calls.log"
echo '[]' > "$tmp/responses/systems-list.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam_Line.json"
echo '{"entries":[{"name":"Core","is_dir":true}]}' > "$tmp/responses/files-browse__books_Fam_Line_5_DE.json"
echo '{"entries":[{"name":"A.pdf","is_dir":false,"record_id":"bookZ"}]}' \
  > "$tmp/responses/files-browse__books_Fam_Line_5_DE_Core.json"
cat > "$tmp/plan.json" <<'EOF'
{"system_path": "books/Fam/Line/5 DE", "rows": [
  {"target": "Core/A.pdf", "metadata": {"title": "A"}, "tags": [], "variant": null}
]}
EOF
mkdir -p "$tmp/exit" "$tmp/stderr"
echo '1' > "$tmp/exit/books-get"
echo 'error: 500 internal server error' > "$tmp/stderr/books-get"
err_getfail="$(bash "$script" --manifest "$tmp/m8.tsv" --system-path "books/Fam/Line/5 DE" --cli "$cli" --plan "$tmp/plan.json" 2>&1 >/dev/null)"
assert_eq "$?" "2" "a books get failure exits 2"
assert_contains "$err_getfail" "500 internal server error" "and surfaces the CLI's stderr text"

# Test 29 (fix round 1, gap): an unparseable `books get` response is a
# precondition failure (exit 2), not something to half-parse and carry on
# from.
rm -rf "$tmp/exit" "$tmp/stderr" "$tmp/.counts"
echo 'not json at all' > "$tmp/responses/books-get.json"
err_getbad="$(bash "$script" --manifest "$tmp/m8.tsv" --system-path "books/Fam/Line/5 DE" --cli "$cli" --plan "$tmp/plan.json" 2>&1 >/dev/null)"
assert_eq "$?" "2" "an unparseable books get response exits 2"
assert_contains "$err_getbad" "unparseable books get response" "and says so"

# ---------------------------------------------------------------------------
# Fix round 2. The shared fixture for the diff tests below: one indexed row,
# Core/A.pdf -> bookQ, with the plan supplied per test.
diff_fixture() {   # $1 = plan json text
  rm -f "$tmp/responses/"*
  rm -rf "$tmp/stderr" "$tmp/exit" "$tmp/.counts" "$tmp/calls.log"
  printf 'a.pdf\tCore/A.pdf\n' > "$tmp/m9.tsv"
  echo '[]' > "$tmp/responses/systems-list.json"
  echo '{"entries":[]}' > "$tmp/responses/files-browse__books.json"
  echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam.json"
  echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Fam_Line.json"
  echo '{"entries":[{"name":"Core","is_dir":true}]}' > "$tmp/responses/files-browse__books_Fam_Line_5_DE.json"
  echo '{"entries":[{"name":"A.pdf","is_dir":false,"record_id":"bookQ"}]}' \
    > "$tmp/responses/files-browse__books_Fam_Line_5_DE_Core.json"
  printf '%s' "$1" > "$tmp/plan.json"
}
diff_row() {
  bash "$script" --manifest "$tmp/m9.tsv" --system-path "books/Fam/Line/5 DE" \
    --cli "$cli" --plan "$tmp/plan.json" \
    | jq -c '.dispositions[] | select(.target=="Core/A.pdf")'
}

# Test 30 (fix round 2, I3): a plan that proposes NOTHING for a field never
# reports `differs` against the shelf. `differs` is defined as both sides
# holding values that disagree; a plan carrying only a title holds no opinion
# about description/isbn/publisher/year/authors, so a populated shelf must not
# read as five conflicts -- which also flipped the row from skip to present.
diff_fixture '{"system_path":"books/Fam/Line/5 DE","rows":[
  {"target":"Core/A.pdf","metadata":{"title":"A"},"tags":[],"variant":null}]}'
cat > "$tmp/responses/books-get.json" <<'EOF'
{"title":"A","description":"Curated blurb","isbn":"9780000000000","language":"de",
 "year":2020,"publisher":"Pub","authors":["Author One"],"tags":[],
 "variant_main_id":null,"variant_parent_id":null,"variant_kind":null}
EOF
row="$(diff_row)"
assert_eq "$(jq -c '[.diff[] | select(.verdict=="differs")] | length' <<<"$row")" "0" \
  "a field the plan does not propose is never differs against a populated shelf"
assert_eq "$(jq -c '.diff | keys' <<<"$row")" '["tags","title","variant"]' \
  "the diff covers exactly the keys the plan carries, plus tags and variant"
assert_eq "$(jq -r '.disposition' <<<"$row")" "skip" \
  "a plan holding only a matching title leaves the row skip, not present"

# Test 31 (fix round 2, I3): the plan naming a field but holding null for it
# is the same "no opinion" -- `shelf_only`, which licenses no write and does
# not make the row present. (An explicit "" is different: that is how the CLI
# clears a field, so it stays a differs.)
diff_fixture '{"system_path":"books/Fam/Line/5 DE","rows":[
  {"target":"Core/A.pdf","metadata":{"title":"A","description":null},"tags":[],"variant":null}]}'
cat > "$tmp/responses/books-get.json" <<'EOF'
{"title":"A","description":"Curated blurb","tags":[],
 "variant_main_id":null,"variant_parent_id":null,"variant_kind":null}
EOF
row="$(diff_row)"
assert_eq "$(jq -c '.diff.description' <<<"$row")" '{"verdict":"shelf_only","shelf":"Curated blurb"}' \
  "a shelf value the plan holds no opinion about is shelf_only, carrying the shelf value"
assert_eq "$(jq -r '.disposition' <<<"$row")" "skip" "shelf_only is not writable, so the row stays skip"

diff_fixture '{"system_path":"books/Fam/Line/5 DE","rows":[
  {"target":"Core/A.pdf","metadata":{"title":"A","description":""},"tags":[],"variant":null}]}'
cat > "$tmp/responses/books-get.json" <<'EOF'
{"title":"A","description":"Curated blurb","tags":[],
 "variant_main_id":null,"variant_parent_id":null,"variant_kind":null}
EOF
row="$(diff_row)"
assert_eq "$(jq -r '.diff.description.verdict' <<<"$row")" "differs" \
  'an explicit "" is a deliberate clear, still differs, still needing approval'

# Test 32 (fix round 2, I3, list family): the same rule on a list field --
# a plan with no authors must not read as differing from the shelf's.
diff_fixture '{"system_path":"books/Fam/Line/5 DE","rows":[
  {"target":"Core/A.pdf","metadata":{"title":"A","authors":null},"tags":[],"variant":null}]}'
cat > "$tmp/responses/books-get.json" <<'EOF'
{"title":"A","authors":["Author One","Author Two"],"tags":[],
 "variant_main_id":null,"variant_parent_id":null,"variant_kind":null}
EOF
row="$(diff_row)"
assert_eq "$(jq -c '.diff.authors' <<<"$row")" \
  '{"verdict":"shelf_only","shelf":["Author One","Author Two"]}' \
  "a shelf list the plan holds no opinion about is shelf_only, not differs"
assert_eq "$(jq -r '.disposition' <<<"$row")" "skip" "a shelf_only list leaves the row skip"

# Test 33 (fix round 2, I6): list_verdict's `differs` branch. authors is the
# only list field the old fixed diff carried, and every test gave it identical
# values on both sides -- so a curator fixing an author name diffed as `same`
# and stopped surfacing. Both sides populated and disagreeing is differs,
# carrying both lists.
diff_fixture '{"system_path":"books/Fam/Line/5 DE","rows":[
  {"target":"Core/A.pdf","metadata":{"title":"A","authors":["Mira Halden"]},"tags":[],"variant":null}]}'
cat > "$tmp/responses/books-get.json" <<'EOF'
{"title":"A","authors":["Mira Haldem"],"tags":[],
 "variant_main_id":null,"variant_parent_id":null,"variant_kind":null}
EOF
row="$(diff_row)"
assert_eq "$(jq -c '.diff.authors' <<<"$row")" \
  '{"verdict":"differs","shelf":["Mira Haldem"],"plan":["Mira Halden"]}' \
  "two populated author lists that disagree are differs, carrying both lists"
assert_eq "$(jq -r '.disposition' <<<"$row")" "present" "a differing author list makes the row present"

# Test 34 (fix round 2, I6): list_verdict's `missing` branch -- the shelf's
# list is empty and the plan has one, so it is writable without approval.
diff_fixture '{"system_path":"books/Fam/Line/5 DE","rows":[
  {"target":"Core/A.pdf","metadata":{"title":"A","authors":["Mira Halden"]},"tags":[],"variant":null}]}'
cat > "$tmp/responses/books-get.json" <<'EOF'
{"title":"A","authors":[],"tags":[],
 "variant_main_id":null,"variant_parent_id":null,"variant_kind":null}
EOF
row="$(diff_row)"
assert_eq "$(jq -c '.diff.authors' <<<"$row")" '{"verdict":"missing"}' \
  "an empty shelf list with a plan list is missing"
assert_eq "$(jq -r '.disposition' <<<"$row")" "present" "a missing author list makes the row present"

# Test 35 (fix round 2, I4): every key the plan carries is diffed, not a
# hard-coded nine. `metadata` goes to `books batch-update` as-is, and that
# request also takes genres, artists, category, license, publisher_url, urls,
# is_explicit and access_level -- an un-diffed key is silently dropped from a
# `present` row's write, which is the quietest failure in the feature.
diff_fixture '{"system_path":"books/Fam/Line/5 DE","rows":[
  {"target":"Core/A.pdf",
   "metadata":{"title":"A","genres":["Fantasy"],"publisher_url":"https://example.test/a",
               "category":"core","is_explicit":false},
   "tags":[],"variant":null}]}'
cat > "$tmp/responses/books-get.json" <<'EOF'
{"title":"A","genres":["Horror"],"publisher_url":null,"category":"core","is_explicit":false,
 "tags":[],"variant_main_id":null,"variant_parent_id":null,"variant_kind":null}
EOF
row="$(diff_row)"
assert_eq "$(jq -c '.diff.genres' <<<"$row")" \
  '{"verdict":"differs","shelf":["Horror"],"plan":["Fantasy"]}' \
  "genres is diffed as a list, not dropped"
assert_eq "$(jq -c '.diff.publisher_url' <<<"$row")" '{"verdict":"missing"}' \
  "publisher_url is diffed as a scalar, not dropped"
assert_eq "$(jq -c '.diff.category' <<<"$row")" '{"verdict":"same"}' \
  "a non-core key that agrees is reported same"
assert_eq "$(jq -c '.diff.is_explicit' <<<"$row")" '{"verdict":"same"}' \
  "a boolean key that agrees is reported same, not absent_both"
assert_eq "$(jq -c '.diff | keys' <<<"$row")" \
  '["category","genres","is_explicit","publisher_url","tags","title","variant"]' \
  "every metadata key the plan carries appears in the diff"

# Test 36 (fix round 2, M12): a failed mktemp is reported once, not
# misdiagnosed as a server error for every absent folder. $_err_tmp is where
# every CLI call's stderr goes; an empty name makes `2>"$_err_tmp"` an
# ambiguous redirect, so every browse -- including the not-found path that
# must read as "create" -- would fail as a precondition error instead.
mkdir -p "$tmp/stub"
cat > "$tmp/stub/mktemp" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
chmod +x "$tmp/stub/mktemp"
err_mktemp="$(PATH="$tmp/stub:$PATH" bash "$script" --manifest "$tmp/m9.tsv" \
  --system-path "books/Fam/Line/5 DE" --cli "$cli" 2>&1 >/dev/null)"
assert_eq "$?" "2" "a failed mktemp exits 2"
assert_contains "$err_mktemp" "mktemp failed" "a failed mktemp says so, instead of blaming the server"
assert_eq "$(printf '%s\n' "$err_mktemp" | grep -c 'files browse failed')" "0" \
  "a failed mktemp is not reported as a browse failure"

# Test: a line with no family above it (books/<line>/<system>, e.g.
# books/Starfall RPG/4 EN). The level directly above the system is the line and
# carries `parent`; reading it as `family` raised a false conflict.
rm -rf "$tmp/responses" "$tmp/exit" "$tmp/stderr" "$tmp/.counts"; mkdir -p "$tmp/responses"
echo '[]' > "$tmp/responses/systems-list.json"
echo '{"entries":[{"name":"Line","is_dir":true,"container_kind":"parent"}]}' > "$tmp/responses/files-browse__books.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Line.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books_Line_4_EN.json"
out="$(bash "$script" --manifest "$tmp/m.tsv" --system-path "books/Line/4 EN" --cli "$cli")"
assert_eq "$(jq -c '.structure.conflicts' <<<"$out")" '[]' "a familyless line's parent container is no conflict"
assert_eq "$(jq -c '.structure.reuse[0].container_kind' <<<"$out")" '"parent"' "the familyless line is reused as parent"

# --plan DIR alone: targets and system path come from plan.json, and the
# dispositions, ids and diffs are merged back into its rows.
rm -rf "$tmp/responses" "$tmp/exit" "$tmp/stderr" "$tmp/.counts"; mkdir -p "$tmp/responses" "$tmp/run"
echo '[]' > "$tmp/responses/systems-list.json"
echo '{"entries":[{"name":"Line","is_dir":true,"container_kind":"parent"}]}' > "$tmp/responses/files-browse__books.json"
echo '{"entries":[{"name":"1 EN","is_dir":true}]}' > "$tmp/responses/files-browse__books_Line.json"
echo '{"entries":[{"name":"Core","is_dir":true}]}' > "$tmp/responses/files-browse__books_Line_1_EN.json"
echo '{"entries":[{"name":"A.pdf","record_id":"id-a"}]}' > "$tmp/responses/files-browse__books_Line_1_EN_Core.json"
echo '{"id":"id-a","title":"Old","tags":[]}' > "$tmp/responses/books-get.json"
cat > "$tmp/run/plan.json" <<'EOF'
{"system_path": "books/Line/1 EN", "rows": [
 {"target": "Core/A.pdf", "metadata": {"title": "New"}, "tags": [], "variant": null},
 {"target": "Core/B.pdf", "metadata": {"title": "B"}, "tags": [], "variant": null}]}
EOF
out="$(bash "$script" --plan "$tmp/run" --cli "$cli")"
assert_eq "$?" "0" "--plan DIR alone runs"
assert_eq "$(jq -c '[.rows[] | [.target, .disposition, .book_id]]' "$tmp/run/plan.json")" \
  '[["Core/A.pdf","present","id-a"],["Core/B.pdf","new",null]]' "dispositions and ids merged into plan.json"
assert_eq "$(jq -r '.rows[0].diff.title.verdict' "$tmp/run/plan.json")" "differs" "diff merged into the row"
assert_eq "$(jq -r '.shelf_checked | test("^[0-9]{4}-")' "$tmp/run/plan.json")" "true" "plan stamped shelf_checked"

# no --cli: the CLI path comes from grimoire-skills.json
echo "{\"cli\": \"$cli\"}" > "$tmp/run/grimoire-skills.json"
out="$(cd "$tmp/run" && bash "$script" --plan "$tmp/run")"
assert_eq "$?" "0" "the CLI path resolves from the config"

# A row that turns new (renamed target, or the shelf row vanished) loses the
# stale book_id and diff, or apply would write onto the old book.
cat > "$tmp/run/plan.json" <<'EOF2'
{"system_path": "books/Line/1 EN", "rows": [
 {"target": "Core/C.pdf", "disposition": "present", "book_id": "id-old",
  "diff": {"title": {"verdict": "missing"}}, "metadata": {"title": "C"}, "tags": [], "variant": null}]}
EOF2
out="$(bash "$script" --plan "$tmp/run" --cli "$cli")"
assert_eq "$(jq -c '.rows[0] | [.disposition, .book_id, .diff]' "$tmp/run/plan.json")" \
  '["new",null,null]' "a row turned new drops its stale book_id and diff"

# structure is merged into plan.json; a container_kind the plan already set for a path is kept
rm -rf "$tmp/responses" "$tmp/.counts"; mkdir -p "$tmp/responses"
echo '[]' > "$tmp/responses/systems-list.json"
echo '{"entries":[]}' > "$tmp/responses/files-browse__books.json"
mkdir -p "$tmp/exit" "$tmp/stderr"
for lvl in books_Fam books_Fam_Line books_Fam_Line_1_EN; do
  echo '2' > "$tmp/exit/files-browse__$lvl"; printf '%s\n' "$notfound" > "$tmp/stderr/files-browse__$lvl"
done
cat > "$tmp/run/plan.json" <<'EOF2'
{"system_path": "books/Fam/Line/1 EN", "rows": [
 {"target": "Core/A.pdf", "metadata": {"title": "A"}, "tags": [], "variant": null}]}
EOF2
out="$(bash "$script" --plan "$tmp/run" --cli "$cli")"
assert_eq "$(jq -c '[.structure.create[] | [.path, .container_kind]]' "$tmp/run/plan.json")" \
  '[["books/Fam","family"],["books/Fam/Line","parent"]]' "computed structure merged into plan.json"
jq '.structure.create[0].container_kind = "publisher"' "$tmp/run/plan.json" > "$tmp/p.json" && mv "$tmp/p.json" "$tmp/run/plan.json"
out="$(bash "$script" --plan "$tmp/run" --cli "$cli")"
assert_eq "$(jq -r '.structure.create[0].container_kind' "$tmp/run/plan.json")" "publisher" "a plan-set container_kind survives a re-check"
assert_eq "$(jq -r '.structure.scaffold.run' "$tmp/run/plan.json")" "true" "the rest of structure is refreshed"

report
