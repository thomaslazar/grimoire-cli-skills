#!/usr/bin/env bash
# ocr_survey.py, ocr_handover.py, resolve_ocr.py, ocr_queue.py, ocr_quality.py
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../../.." && pwd)"
. "$repo/tests/lib/assert.sh"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
export FAKE_CLI_DIR="$t/fake"
cli="$repo/tests/lib/fake_cli.sh"
mkdir -p "$t/bin" "$t/src" "$t/plan" "$t/cfg" "$FAKE_CLI_DIR/responses"
cp "$here/fake_pdftotext.sh" "$t/bin/pdftotext"
S="$here/.."
page() { python3 -c "print('word ' * 60)"; }

# full: 3 text pages; none: no text; partial: 3 of 4 pages text, 1 empty; watermark-only: none
for n in full none partial wm; do : > "$t/src/$n.pdf"; done
{ page; printf '\f'; page; printf '\f'; page; printf '\f'; } > "$t/src/full.pdf.txt"
: > "$t/src/none.pdf.txt"
{ page; printf '\f'; printf '\f'; page; printf '\f'; page; printf '\f'; } > "$t/src/partial.pdf.txt"
{ for i in 1 2; do echo "Order #123 for someone $(page)"; printf '\f'; done; } > "$t/src/wm.pdf.txt"
echo notpdf > "$t/src/readme.txt"
cat > "$t/plan/plan.json" <<JSON
{"system_path": "books/Starfall RPG/1 EN", "source_root": "$t/src", "rows": [
 {"source": "full.pdf", "target": "Core/Full.pdf", "disposition": "new", "book_id": "id-full"},
 {"source": "none.pdf", "target": "Core/None.pdf", "disposition": "new", "book_id": "id-none"},
 {"source": "partial.pdf", "target": "Core/Partial.pdf", "disposition": "new", "book_id": "id-part"},
 {"source": "wm.pdf", "target": "Core/Wm.pdf", "disposition": "new", "book_id": "id-wm"},
 {"source": "readme.txt", "target": "Core/Readme.txt", "disposition": "new"},
 {"source": "full.pdf", "target": "Core/Skip.pdf", "disposition": "skip"}]}
JSON

# survey
PATH="$t/bin:$PATH" python3 "$S/ocr_survey.py" --plan "$t/plan" > /dev/null; rc=$?
assert_eq "$rc" "0" "survey runs"
got="$(python3 -c "
import json; d=json.load(open('$t/plan/ocr-survey.json'))
print(sorted((k.split('/')[1], v['text']) for k, v in d.items()), d['Core/Partial.pdf']['empty_pages'])")"
assert_eq "$got" "[('Full.pdf', 'full'), ('None.pdf', 'none'), ('Partial.pdf', 'partial'), ('Wm.pdf', 'none')] [2]" "survey classes, watermark dropped, non-pdf and skip ignored"
mkdir "$t/empty"; py="$(command -v python3)"
out="$(PATH="$t/empty" "$py" "$S/ocr_survey.py" --plan "$t/plan" 2>&1)"; rc=$?
assert_eq "$rc" "2" "missing pdftotext exits 2"; assert_contains "$out" "install" "install hint"

# config: server (default, no config file) vs handover
cd "$t/cfg"
out="$(python3 "$S/ocr_handover.py" --plan "$t/plan" --out "$t/h.csv" 2>&1)"; rc=$?
assert_eq "$rc" "2" "handover in server mode refuses"
assert_contains "$out" "'server'" "message names the mode"
echo '{"ocr": "handover"}' > "$t/cfg/grimoire-skills.json"
python3 "$S/ocr_handover.py" --plan "$t/plan" --out "$t/h.csv" > /dev/null; rc=$?
assert_eq "$rc" "0" "handover writes"
assert_eq "$(head -1 "$t/h.csv")" "source_path,output_path,reason" "csv header"
assert_eq "$(wc -l < "$t/h.csv" | tr -d ' ')" "4" "none+partial+wm rows only"
assert_contains "$(cat "$t/h.csv")" "$t/src/none.pdf,$t/plan/ocr/001-none.pdf," "absolute source and full output file path"
assert_contains "$(cat "$t/h.csv")" "pages 2 have no text" "partial reason names pages"

# resolve_ocr: one output exists, one missing, one handover row unused
mkdir -p "$t/plan/ocr"; : > "$t/plan/ocr/none.pdf"
echo "source_path,output_path,reason
$t/src/none.pdf,$t/plan/ocr/none.pdf,x
$t/src/other.pdf,$t/plan/ocr/other.pdf,x" > "$t/h2.csv"
: > "$t/plan/ocr/other.pdf"
out="$(python3 "$S/resolve_ocr.py" --plan "$t/plan" --handover "$t/h2.csv")"; rc=$?
assert_eq "$rc" "0" "resolve ok"
assert_eq "$(python3 -c "import json;print(json.load(open('$t/plan/plan.json'))['rows'][1]['source'])")" "$t/plan/ocr/none.pdf" "row source rewritten"
assert_contains "$out" "other.pdf\"]" "unused handover row reported"
python3 "$S/resolve_ocr.py" --plan "$t/plan" --handover "$t/h.csv" > /dev/null 2>&1; rc=$?
assert_eq "$rc" "1" "missing listed output exits 1"
echo '{"ocr": "server"}' > "$t/cfg/grimoire-skills.json"
python3 "$S/resolve_ocr.py" --plan "$t/plan" --handover "$t/h2.csv" > /dev/null 2>&1; rc=$?
assert_eq "$rc" "2" "resolve in server mode refuses"

# ocr_queue (server mode): only image-only rows
echo '{"running": false}' > "$FAKE_CLI_DIR/responses/library-scan-status.json"
echo '{"reindex_queued": true}' > "$FAKE_CLI_DIR/responses/books-reindex.json"
out="$(python3 "$S/ocr_queue.py" --plan "$t/plan" --cli "$cli" --interval 0 2>&1)"; rc=$?
assert_eq "$rc" "0" "queue ok: $out"
calls="$(grep '^books reindex' "$FAKE_CLI_DIR/calls.log")"
assert_eq "$calls" "books reindex --id id-none
books reindex --id id-wm" "reindex only for image-only rows"
assert_contains "$(cat "$FAKE_CLI_DIR/calls.log")" "library rescan --metadata-mode missing" "one unscoped rescan"
assert_eq "$(grep -c cancel-scan "$FAKE_CLI_DIR/calls.log")" "0" "never cancels"
: > "$FAKE_CLI_DIR/calls.log"
python3 "$S/ocr_queue.py" --plan "$t/plan" --cli "$cli" --interval 0 > /dev/null; rc=$?
assert_eq "$(grep -c '^books reindex' "$FAKE_CLI_DIR/calls.log")" "0" "re-run skips rows already ok"

# 400 recorded, not fatal; other failure exits 1
rm "$t/plan/receipts-ocr_queue.ndjson"; : > "$FAKE_CLI_DIR/calls.log"
mkdir -p "$FAKE_CLI_DIR/exit" "$FAKE_CLI_DIR/stderr"; echo 1 > "$FAKE_CLI_DIR/exit/books-reindex"
 echo "Error: 400 not an image-only book" > "$FAKE_CLI_DIR/stderr/books-reindex"
out="$(python3 "$S/ocr_queue.py" --plan "$t/plan" --cli "$cli" --interval 0 2>&1)"; rc=$?
assert_eq "$rc" "0" "400 is not a failure"
assert_contains "$(cat "$t/plan/receipts-ocr_queue.ndjson")" "400: not image-only" "400 noted in receipt"
assert_eq "$(grep -c '^library rescan' "$FAKE_CLI_DIR/calls.log")" "0" "no rescan when nothing queued"
rm "$t/plan/receipts-ocr_queue.ndjson"; echo "Error: 500 boom" > "$FAKE_CLI_DIR/stderr/books-reindex"
python3 "$S/ocr_queue.py" --plan "$t/plan" --cli "$cli" --interval 0 > /dev/null 2>&1; rc=$?
assert_eq "$rc" "1" "other failure exits 1"

# queue refuses: missing id, wrong mode
rm "$t/plan/receipts-ocr_queue.ndjson"
python3 - "$t/plan/plan.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1])); p["rows"][1]["book_id"] = None
json.dump(p, open(sys.argv[1], "w"))
PY
python3 "$S/ocr_queue.py" --plan "$t/plan" --cli "$cli" > /dev/null 2>&1; rc=$?
assert_eq "$rc" "2" "missing book_id refuses"
echo '{"ocr": "handover"}' > "$t/cfg/grimoire-skills.json"
out="$(python3 "$S/ocr_queue.py" --plan "$t/plan" --cli "$cli" 2>&1)"
assert_contains "$out" "'handover'" "queue in handover mode names the mode"

# ocr_quality: markers optional
printf 'The quick brown fox jumps over the lazy dog and more words here\nstatLli Z1ubers x_y\n' > "$t/src/q.pdf.txt"
out="$(PATH="$t/bin:$PATH" python3 "$S/ocr_quality.py" "$t/src")"
assert_contains "$out" "garble%" "report header"
case "$out" in *mk/1k*) fail "no markers, no column";; *) pass;; esac
out="$(PATH="$t/bin:$PATH" python3 "$S/ocr_quality.py" --markers "o,e" "$t/src")"
assert_contains "$out" "mk/1k" "markers add a column"

# ---- fix round 1 ----
echo '{"ocr": "server"}' > "$t/cfg/grimoire-skills.json"
reset() { rm -rf "$FAKE_CLI_DIR" "$t/p2"; mkdir -p "$FAKE_CLI_DIR/responses" "$FAKE_CLI_DIR/exit" "$FAKE_CLI_DIR/stderr" "$t/p2"
  echo '{"running": false}' > "$FAKE_CLI_DIR/responses/library-scan-status.json"
  echo '{"system_path": "s", "rows": [{"source": "a.pdf", "target": "A.pdf", "book_id": "id-a"}, {"source": "b.pdf", "target": "B.pdf", "book_id": "id-b"}]}' > "$t/p2/plan.json"
  echo '{"A.pdf": {"text": "none"}, "B.pdf": {"text": "none"}}' > "$t/p2/ocr-survey.json"; }
q() { python3 "$S/ocr_queue.py" --plan "$t/p2" --cli "$cli" --interval 0 "$@" 2>&1; }

# 1: interrupted before the rescan -> re-run fires exactly one rescan
reset
echo '{"step":"ocr_queue","target":"A.pdf","ok":true,"queued":true}
{"step":"ocr_queue","target":"B.pdf","ok":true,"queued":true}' > "$t/p2/receipts-ocr_queue.ndjson"
q > /dev/null; rc=$?
assert_eq "$rc" "0" "recovery run ok"
assert_eq "$(grep -c '^library rescan' "$FAKE_CLI_DIR/calls.log")" "1" "interrupted run: one rescan"
assert_eq "$(grep -c '^books reindex' "$FAKE_CLI_DIR/calls.log")" "0" "interrupted run: no new reindex"
: > "$FAKE_CLI_DIR/calls.log"; q > /dev/null
assert_eq "$(grep -c '^library rescan' "$FAKE_CLI_DIR/calls.log")" "0" "rescan receipt stops a further rescan"

# 2: failing scan-status is never idle
reset
echo 1 > "$FAKE_CLI_DIR/exit/library-scan-status"
q > /dev/null; rc=$?
assert_eq "$rc" "1" "scan-status failure exits 1"
assert_eq "$(grep -c '^books reindex' "$FAKE_CLI_DIR/calls.log")" "0" "no reindex while scan state unknown"

# 3: rescan failure counts, and is retried next run
reset
echo 1 > "$FAKE_CLI_DIR/exit/library-rescan"
q > /dev/null; rc=$?
assert_eq "$rc" "1" "rescan failure exits 1"
rm "$FAKE_CLI_DIR/exit/library-rescan"; : > "$FAKE_CLI_DIR/calls.log"
q > /dev/null; rc=$?
assert_eq "$rc" "0" "retry succeeds"
assert_eq "$(grep -c '^library rescan' "$FAKE_CLI_DIR/calls.log")" "1" "failed rescan retried"

# 4: 4001 is not a 400
reset
echo 1 > "$FAKE_CLI_DIR/exit/books-reindex"; echo "Error: request 4001 failed" > "$FAKE_CLI_DIR/stderr/books-reindex"
q > /dev/null; rc=$?
assert_eq "$rc" "1" "4001 is a failure"

# 5: unreadable PDF -> error row, skipped by queue and handover
for p in corrupt; do : > "$t/src/$p.pdf"; done; rm -f "$t/src/corrupt.pdf.txt"
cat > "$t/p3.json" <<JSON
{"system_path": "s", "source_root": "$t/src", "rows": [
 {"source": "corrupt.pdf", "target": "Core/Bad.pdf", "book_id": "id-bad"},
 {"source": "none.pdf", "target": "Core/None.pdf", "book_id": "id-n"}]}
JSON
mkdir -p "$t/p3"; cp "$t/p3.json" "$t/p3/plan.json"
PATH="$t/bin:$PATH" python3 "$S/ocr_survey.py" --plan "$t/p3" > /dev/null; rc=$?
assert_eq "$rc" "0" "survey survives a corrupt pdf"
assert_eq "$(python3 -c "import json;print(json.load(open('$t/p3/ocr-survey.json'))['Core/Bad.pdf']['text'])")" "error" "corrupt pdf marked error"
rm -rf "$FAKE_CLI_DIR"; mkdir -p "$FAKE_CLI_DIR"
out="$(python3 "$S/ocr_queue.py" --plan "$t/p3" --cli "$cli" --interval 0 2>&1)"
assert_contains "$out" "Core/Bad.pdf" "queue reports the unreadable row"
assert_eq "$(grep -c 'id-bad' "$FAKE_CLI_DIR/calls.log")" "0" "unreadable row not queued"
echo '{"ocr": "handover"}' > "$t/cfg/grimoire-skills.json"
out="$(python3 "$S/ocr_handover.py" --plan "$t/p3" --out "$t/h3.csv")"
assert_eq "$(wc -l < "$t/h3.csv" | tr -d ' ')" "2" "handover skips the error row"
assert_contains "$out" "Core/Bad.pdf" "handover reports the unreadable row"

# 6: second resolve_ocr run does not call resolved rows unused
python3 "$S/resolve_ocr.py" --plan "$t/p3" --handover "$t/h3.csv" > /dev/null
mkdir -p "$t/p3/ocr"; out_path="$(sed -n 2p "$t/h3.csv" | cut -d, -f2)"; : > "$out_path"
python3 "$S/resolve_ocr.py" --plan "$t/p3" --handover "$t/h3.csv" > /dev/null
out="$(python3 "$S/resolve_ocr.py" --plan "$t/p3" --handover "$t/h3.csv")"
assert_contains "$out" '"unused": []' "second run: nothing unused"
assert_contains "$out" '"resolved": 1' "second run: still resolved"

# 7: same file name in two folders gets distinct outputs
mkdir -p "$t/src/d1" "$t/src/d2" "$t/p4"; : > "$t/src/d1/x.pdf"; : > "$t/src/d2/x.pdf"
cat > "$t/p4/plan.json" <<JSON
{"system_path": "s", "source_root": "$t/src", "rows": [
 {"source": "d1/x.pdf", "target": "A/x.pdf"}, {"source": "d2/x.pdf", "target": "B/x.pdf"}]}
JSON
echo '{"A/x.pdf": {"text": "none"}, "B/x.pdf": {"text": "none"}}' > "$t/p4/ocr-survey.json"
python3 "$S/ocr_handover.py" --plan "$t/p4" --out "$t/h4.csv" > /dev/null
assert_eq "$(cut -d, -f2 "$t/h4.csv" | tail -n +2 | sort -u | wc -l | tr -d ' ')" "2" "outputs distinct for equal names"

# 8: only a line-start watermark is dropped
printf 'Order # 55 watermark\f' > "$t/src/wm2.pdf.txt"; : > "$t/src/wm2.pdf"
{ python3 -c "print('real text mentioning Order # inside a sentence ' * 5)"; printf '\f'; } > "$t/src/wm3.pdf.txt"; : > "$t/src/wm3.pdf"
mkdir -p "$t/p5"
echo "{\"system_path\": \"s\", \"source_root\": \"$t/src\", \"rows\": [{\"source\": \"wm3.pdf\", \"target\": \"W.pdf\"}]}" > "$t/p5/plan.json"
PATH="$t/bin:$PATH" python3 "$S/ocr_survey.py" --plan "$t/p5" > /dev/null
assert_eq "$(python3 -c "import json;print(json.load(open('$t/p5/ocr-survey.json'))['W.pdf']['text'])")" "full" "mid-line Order # kept"
report
