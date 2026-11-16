#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../../.." && pwd)"
lib="$repo/tests/lib"
. "$lib/assert.sh"
script="$here/../publish_audio.py"
cli="$lib/fake_cli.sh"

setup() {  # a fresh fake server and a staged tree of two tracks
  tmp="$(mktemp -d)"; export FAKE_CLI_DIR="$tmp"
  mkdir -p "$tmp/responses" "$tmp/exit" "$tmp/stderr" "$tmp/run/stage/tree/Echoes/09 Forest"
  : > "$tmp/run/stage/tree/Echoes/09 Forest/01 - A.mp3"; : > "$tmp/run/stage/tree/Echoes/09 Forest/02 - B.mp3"
  cat > "$tmp/plan.json" <<'EOF'
{"root":"audio/Example","rows":[
 {"target":"Echoes/09 Forest/01 - A.mp3","title":"A","tags":["soundtrack","for:es005"],"description":"Blurb",
  "expect":{"album":"Forest","artist":"Jane Composer","artwork":true}},
 {"target":"Echoes/09 Forest/02 - B.mp3","title":"B","tags":["soundtrack"],"description":"",
  "expect":{"album":"Forest","artwork":true}}]}
EOF
  # audio/Example exists; the two levels below it do not yet
  # fake_cli numbers calls per command: browse #2 is Echoes, #3 is 09 Forest (both absent), #4 the post-upload listing
  for s in audio_Example_Echoes.2 audio_Example_Echoes_09_Forest.3; do
    echo 2 > "$tmp/exit/files-browse__$s"; echo "Not found. No such path in the library." > "$tmp/stderr/files-browse__$s"; done
  # after the upload, the server lists both tracks at their staged size (0 bytes here)
  echo '{"entries":[{"name":"01 - A.mp3","size":0},{"name":"02 - B.mp3","size":0}]}' > "$tmp/responses/files-browse__audio_Example_Echoes_09_Forest.4.json"
  echo '{"running":false}' > "$tmp/responses/library-scan-status.1.json"
  echo '{"running":true}'  > "$tmp/responses/library-scan-status.2.json"
  echo '{"running":false,"new_audio":1}' > "$tmp/responses/library-scan-status.3.json"
  echo '{"status":"scan_started"}' > "$tmp/responses/library-rescan.json"
  echo '{"name":"01 - A.mp3","size":0}' > "$tmp/responses/files-upload.1.json"
  echo 2 > "$tmp/exit/files-upload.2"
  echo "ERROR API request failed: 409 Conflict" > "$tmp/stderr/files-upload.2"
  echo '{"detail":"A file named '"'"'02 - B.mp3'"'"' already exists there"}' > "$tmp/responses/files-upload.2.json"
  echo '{"audio":[{"id":"i1","relative_path":"audio/Example/Echoes/09 Forest/01 - A.mp3"},{"id":"i2","relative_path":"audio/Example/Echoes/09 Forest/02 - B.mp3"}],"total":2}' \
    > "$tmp/responses/audio-list.json"
  echo '{"updated":["i1"],"errors":[]}' > "$tmp/responses/audio-batch-update.json"
  echo '{"updated":["i2"],"errors":[]}' > "$tmp/responses/audio-batch-tag.json"
  echo '{"id":"i1","title":"A","album":"Forest","artist":"Jane Composer","has_artwork":true,"tags":["soundtrack","for:es005"],"description":"Blurb"}' \
    > "$tmp/responses/audio-get.1.json"
  echo '{"id":"i2","title":"B","album":"Forest","artist":"x","has_artwork":true,"tags":["soundtrack","hand-added"],"description":""}' \
    > "$tmp/responses/audio-get.2.json"
}

setup
out="$(python3 "$script" --plan "$tmp/plan.json" --run-dir "$tmp/run" --cli "$cli" --poll-seconds 0)"
assert_eq "$?" "0" "a clean publish exits 0"
assert_contains "$out" '"uploaded":1' "counts the uploaded track"
assert_contains "$out" '"skipped":1' "a 409 already-exists is a skip, not a failure"
assert_contains "$out" '"created":2' "creates the two missing folder levels"
assert_contains "$out" '"verified":2' "every row reads back as planned"
log="$(cat "$tmp/calls.log")"
assert_contains "$(grep 'folder create' <<<"$log" | head -1)" "--parent audio/Example --name Echoes" "creates the parent level first"
assert_contains "$log" "library rescan --scope audio/Example --metadata-mode missing" "rescans only the plan root"
assert_eq "$(grep -c 'audio batch-update' <<<"$log")" "1" "one batch-update, for the newly uploaded rows"
assert_eq "$(grep -c 'audio batch-tag' <<<"$log")" "1" "the already-present row gets additive tags only"
assert_eq "$(grep -c 'library scan-status' <<<"$log")" "3" "polls until running is false"

setup
assert_exit 0 python3 "$script" --plan "$tmp" --run-dir "$tmp/run" --cli "$cli" --poll-seconds 0   # a run directory works as --plan

# a scan already running: refuse before writing anything
setup; echo '{"running":true}' > "$tmp/responses/library-scan-status.1.json"
assert_exit 2 python3 "$script" --plan "$tmp/plan.json" --run-dir "$tmp/run" --cli "$cli" --poll-seconds 0
assert_eq "$(grep -c 'files upload' "$tmp/calls.log")" "0" "nothing is uploaded while a scan runs"

# a track the server lists at the wrong size is a failure, found without any mount
setup; echo '{"entries":[{"name":"01 - A.mp3","size":0},{"name":"02 - B.mp3","size":7}]}' > "$tmp/responses/files-browse__audio_Example_Echoes_09_Forest.4.json"
err="$(python3 "$script" --plan "$tmp/plan.json" --run-dir "$tmp/run" --cli "$cli" --poll-seconds 0 2>&1 >/dev/null)"
assert_eq "$?" "2" "a size mismatch on the server exits 2"
assert_contains "$err" "on the server: 7 bytes" "and names the server's size"

# a real upload failure is not a skip
setup; echo "ERROR something else broke" > "$tmp/stderr/files-upload.2"; rm "$tmp/responses/files-upload.2.json"
assert_exit 2 python3 "$script" --plan "$tmp/plan.json" --run-dir "$tmp/run" --cli "$cli" --poll-seconds 0

# a row that reads back wrong fails verification
setup; echo '{"id":"i1","title":"","album":"","artist":"","has_artwork":false,"tags":[],"description":""}' > "$tmp/responses/audio-get.1.json"
err="$(python3 "$script" --plan "$tmp/plan.json" --run-dir "$tmp/run" --cli "$cli" --poll-seconds 0 2>&1 >/dev/null)"
assert_eq "$?" "3" "a mismatch on read-back exits 3"
assert_contains "$err" "title ''" "and names what was wrong"

# not staged yet
setup; rm "$tmp/run/stage/tree/Echoes/09 Forest/02 - B.mp3"
assert_exit 2 python3 "$script" --plan "$tmp/plan.json" --run-dir "$tmp/run" --cli "$cli" --poll-seconds 0

# a root outside audio/
setup; sed 's|"root":"audio/Example"|"root":"books/Example"|' "$tmp/plan.json" > "$tmp/p2" && mv "$tmp/p2" "$tmp/plan.json"
assert_exit 1 python3 "$script" --plan "$tmp/plan.json" --run-dir "$tmp/run" --cli "$cli" --poll-seconds 0

report
