#!/usr/bin/env bash
# Every scripts/... path SKILL.md names must exist, relative to the skill folder.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
skill="$(cd "$here/../.." && pwd)"
fail=0; n=0
for p in $(grep -oE '(\.\./[A-Za-z0-9_-]+/)?scripts/[A-Za-z0-9_./-]+\.(py|sh)' "$skill/SKILL.md" | sort -u); do
  n=$((n+1))
  [ -f "$skill/$p" ] || { echo "FAIL: SKILL.md names missing $p"; fail=1; }
done
[ "$n" -gt 0 ] || { echo "FAIL: no script paths found"; fail=1; }
echo "skill doc: $n script paths checked"

# The example plan.json in SKILL.md passes check_plan (sources stubbed in a temp dir).
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
python3 - "$skill/SKILL.md" "$t" <<'PY' || { echo "FAIL: example plan.json not extractable"; fail=1; }
import json, os, re, sys
doc, t = sys.argv[1], sys.argv[2]
text = open(doc, encoding="utf-8").read()
block = re.search(r"### plan.json\n\n```json\n(.*?)\n```", text, re.S).group(1)
plan = json.loads(block)
plan["source_root"] = t
for r in plan["rows"]:
    os.makedirs(os.path.dirname(os.path.join(t, r["source"])), exist_ok=True)
    open(os.path.join(t, r["source"]), "w").close()
json.dump(plan, open(os.path.join(t, "plan.json"), "w"))
PY
out="$(python3 "$skill/scripts/check_plan.py" --plan "$t" 2>&1)" || { echo "FAIL: example plan refused: $out"; fail=1; }
exit $fail
