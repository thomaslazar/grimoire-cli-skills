#!/usr/bin/env bash
# check_plan.py: one case per refusal.
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../../.." && pwd)"
. "$repo/tests/lib/assert.sh"
script="$here/../check_plan.py"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
echo a > "$t/a.pdf"; echo b > "$t/b.pdf"

# mk <rows-json> [system_path]
mk() { printf '{"system_path": "%s", "rows": %s}' "${2:-books/Starfall RPG/1 EN}" "$1" > "$t/plan.json"; }
row() { # target [extra json members, leading comma]
  printf '{"source": "%s/a.pdf", "target": "%s", "disposition": "new", "variant": null%s}' "$t" "$1" "${2:-}"
}
# refuses <needle> <msg>
refuses() {
  out="$(python3 "$script" --plan "$t" 2>&1)"; rc=$?
  assert_eq "$rc" "2" "$2: exit 2"
  assert_contains "$out" "$1" "$2: names the problem"
}

mk "[$(row Core/A.pdf)]"
assert_exit 0 python3 "$script" --plan "$t"
assert_exit 0 python3 "$script" --plan "$t/plan.json"   # a plan file works too

mk "[]"; refuses "no rows" "empty plan"
mk "[$(row Core/A.pdf | sed "s|$t/a.pdf|$t/gone.pdf|")]"; refuses "missing source" "source missing"
mk "[$(row Core/A.pdf), $(row Core/A.pdf)]"; refuses "duplicate target" "duplicate target"
mk "[$(row Loose/A.pdf)]"; refuses "category folder" "target outside a category folder"
mk "[$(row A.pdf)]"; refuses "category folder" "bare filename"
mk "[$(row Core/A.xlsx)]"; refuses ".xlsx" "refused extension"
mk "[$(row Core/A.pdf), $(row Core/B.pdf | sed 's|"variant": null|"variant": {"of": "Core/Z.pdf", "kind": "version"}|')]"
refuses "Core/Z.pdf" "variant of nothing"
mk "[$(row Core/A.pdf), $(row Core/B.pdf | sed 's|"variant": null|"variant": {"of": "Core/A.pdf", "kind": "scan"}|')]"
refuses "scan" "variant kind not in the profile"

# a variant of a row already on the shelf names its id and passes
mk "[$(row Core/B.pdf | sed 's|"variant": null|"variant": {"of": "Core/Z.pdf", "of_id": "abc", "kind": "version"}|')]"
assert_exit 0 python3 "$script" --plan "$t"
# a variant of a row in the plan passes
mk "[$(row Core/A.pdf), $(row Core/B.pdf | sed 's|"variant": null|"variant": {"of": "Core/A.pdf", "kind": "version"}|')]"
assert_exit 0 python3 "$script" --plan "$t"
# present rows need no source on disk
mk "[$(row Core/A.pdf | sed -e "s|$t/a.pdf|$t/gone.pdf|" -e 's|"new"|"present"|')]"
assert_exit 0 python3 "$script" --plan "$t"
# armory roots use the armory categories
mk "[$(row 'Factions/A.pdf')]" "armory/Starfall Wars/1 EN"
assert_exit 0 python3 "$script" --plan "$t"
mk "[$(row 'Factions/A.pdf')]"; refuses "category folder" "armory category on a books system"
report
