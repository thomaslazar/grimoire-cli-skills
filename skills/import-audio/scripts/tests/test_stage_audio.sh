#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../../.." && pwd)"
. "$repo/tests/lib/assert.sh"
script="$here/../stage_audio.py"

if ! command -v ffmpeg >/dev/null || ! command -v ffprobe >/dev/null; then
  echo "SKIP: ffmpeg/ffprobe not installed - stage_audio tests NOT run"; exit 0
fi

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
src="$tmp/src [EX1234] (MP3)"; mkdir -p "$src"
# one untagged track, one tagged the way the publisher tags, and a cover
ffmpeg -v error -y -f lavfi -i sine=d=1 -c:a libmp3lame -b:a 64k "$src/01 Forest Edge.mp3"
ffmpeg -v error -y -f lavfi -i sine=f=660:d=1 -c:a libmp3lame -b:a 64k \
  -metadata title="Lonely Peaks Quiet Vales" -metadata album="Forest of Echoes" "$src/10 tagged.mp3"
ffmpeg -v error -y -f lavfi -i sine=f=880:d=1 -c:a libmp3lame -b:a 64k -metadata title="On the Sea" "$src/03 clean.mp3"
ffmpeg -v error -y -f lavfi -i color=red:s=64x64 -frames:v 1 "$tmp/cover.jpg"
before="$(cd "$src" && ls -l | cksum)"

cat > "$tmp/plan.json" <<EOF
{"root":"audio/Example Soundworks","rows":[
 {"source":"$src/01 Forest Edge.mp3","target":"Echoes/09 Forest Edge/01 - Forest Edge.mp3","title":"Forest Edge",
  "write":{"title":"Forest Edge","album":"Forest Edge","artist":"Jane Composer","album_artist":"Echoes","track":"01","date":"2021"},
  "cover":"$tmp/cover.jpg","tags":["soundtrack"]},
 {"source":"$src/10 tagged.mp3","target":"Echoes/08 Forest of Echoes/10 - Lonely Peaks Quiet Vales.mp3",
  "title":"Lonely Peaks Quiet Vales","write":{"title":"Lonely Peaks Quiet Vales"},"cover":null,"tags":[]},
 {"source":"$src/03 clean.mp3","target":"Echoes/08 Forest of Echoes/03 - On the Sea.mp3","title":"On the Sea","write":{},"cover":null,"tags":[]}
]}
EOF
out="$(python3 "$script" --plan "$tmp/plan.json" --run-dir "$tmp/run")"
assert_eq "$?" "0" "a clean plan stages with exit 0"
assert_contains "$out" '"copies":2' "rows that write tags become copies"
assert_contains "$out" '"symlinks":1' "a row with nothing to write stays a symlink"
tree="$tmp/run/stage/tree/Echoes"
assert_eq "$([ -L "$tree/08 Forest of Echoes/03 - On the Sea.mp3" ] && echo y)" "y" "the unchanged track is a symlink, zero bytes copied"

tags="$(ffprobe -v quiet -show_entries format_tags -of json "$tree/09 Forest Edge/01 - Forest Edge.mp3")"
assert_contains "$tags" '"album_artist": "Echoes"' "the untagged track gets the full tag set"
assert_contains "$tags" '"track": "01"' "…including the track number"
assert_eq "$(grep -ci encoder <<<"$tags")" "0" "no ffmpeg encoder stamp is written"
assert_eq "$(ffprobe -v quiet -select_streams v -show_entries stream=codec_name -of csv=p=0 "$tree/09 Forest Edge/01 - Forest Edge.mp3")" "mjpeg" "the cover is embedded"

t2="$(ffprobe -v quiet -show_entries format_tags -of json "$tree/08 Forest of Echoes/10 - Lonely Peaks Quiet Vales.mp3")"
assert_contains "$t2" 'Quiet Vales' "a corrected title is written"
assert_contains "$t2" '"album": "Forest of Echoes"' "the publisher's other tags survive a title fix"
assert_eq "$(cd "$src" && ls -l | cksum)" "$before" "the source folder is untouched"
assert_contains "$(cat "$tmp/run/receipts/stage.json")" '"ok": true' "the receipt records success"
assert_exit 0 python3 "$script" --plan "$tmp" --run-dir "$tmp/r7"   # a run directory works as --plan

# clean: the source's own tags are dropped, only the written ones remain
ffmpeg -v error -y -f lavfi -i sine=f=440:d=1 -c:a libmp3lame -b:a 64k -metadata title="01 - Junk" \
  -metadata comment="only for HS-Scene" -metadata encoded_by="Winamp" "$src/04 junk.mp3"
cat > "$tmp/clean.json" <<EOF
{"root":"audio/X","rows":[{"source":"$src/04 junk.mp3","target":"A/01 - Junk.mp3","title":"Junk",
  "clean":true,"write":{"title":"Junk","track":"01"},"cover":null,"tags":[]}]}
EOF
assert_exit 0 python3 "$script" --plan "$tmp/clean.json" --run-dir "$tmp/r6"
t3="$(ffprobe -v quiet -show_entries format_tags -of json "$tmp/r6/stage/tree/A/01 - Junk.mp3")"
assert_contains "$t3" '"title": "Junk"' "a clean copy carries the written title"
assert_eq "$(grep -ciE 'comment|encoded_by' <<<"$t3")" "0" "…and none of the source's own tags"

# refusals, before anything is staged
sed 's|03 clean.mp3|missing.mp3|' "$tmp/plan.json" > "$tmp/ghost.json"
assert_exit 2 python3 "$script" --plan "$tmp/ghost.json" --run-dir "$tmp/r2"
python3 - "$tmp/plan.json" "$tmp/dup.json" <<'PY'
import json,sys; p=json.load(open(sys.argv[1])); p['rows'][2]['target']=p['rows'][1]['target']; json.dump(p,open(sys.argv[2],'w'))
PY
assert_exit 2 python3 "$script" --plan "$tmp/dup.json" --run-dir "$tmp/r3"
python3 - "$tmp/plan.json" "$tmp/esc.json" <<'PY'
import json,sys; p=json.load(open(sys.argv[1])); p['rows'][0]['target']='../x.mp3'; json.dump(p,open(sys.argv[2],'w'))
PY
assert_exit 2 python3 "$script" --plan "$tmp/esc.json" --run-dir "$tmp/r4"
python3 - "$tmp/plan.json" "$tmp/slash.json" <<'PY'
import json,sys; p=json.load(open(sys.argv[1])); p['rows'][0]['title']='AC/DC'; json.dump(p,open(sys.argv[2],'w'))
PY
assert_exit 2 python3 "$script" --plan "$tmp/slash.json" --run-dir "$tmp/r5"

report
