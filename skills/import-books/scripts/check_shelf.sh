#!/usr/bin/env bash
# Compare a plan and its target system against what the library already
# holds. Reads the server only.
#
#   check_shelf.sh --plan <dir|plan.json> [--manifest <tsv>] [--system-path <path>] [--cli <path>]
#   check_shelf.sh --manifest <tsv> --system-path <path> [--cli <path>]
#
# Targets come from the manifest's second column, or from plan.json's rows when
# no manifest is given; the system path defaults to plan.json's system_path.
# Without --plan every indexed target is a bare "skip". With it, every indexed
# row also carries book_id and a field-level diff against the plan's metadata,
# disposition becomes "present" when the diff holds anything writable or a
# differs, "skip" otherwise, and disposition/book_id/diff are merged back into
# plan.json's rows by target (a row turned new loses book_id/diff), stamping
# shelf_checked; the computed structure is merged too (plan-set kinds kept).
# --cli defaults to the configured CLI.
set -uo pipefail

manifest=""; system_path=""; cli=""; plan=""
while [ $# -gt 0 ]; do
  case "$1" in
    --manifest) manifest="${2:?}"; shift 2;;
    --system-path) system_path="${2:?}"; shift 2;;
    --plan) plan="${2:?}"; shift 2;;
    --cli) cli="${2:?}"; shift 2;;
    -h|--help) sed -n '2,16p' "$0"; exit 0;;
    *) echo "unknown argument: $1" >&2; exit 1;;
  esac
done
[ -n "$plan" ] && [ -d "$plan" ] && plan="$plan/plan.json"
if [ -n "$plan" ]; then
  [ -f "$plan" ] || { echo "no such plan: $plan" >&2; exit 1; }
fi
[ -n "$cli" ] || cli="$(python3 -c 'import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(sys.argv[1])), "..", "..", "..", "lib"))
from grimoire_skills import config; print(config.cli_path(config.load()))' "$0")"
if [ -n "$plan" ] && [ -z "$system_path" ]; then
  system_path="$(jq -r '.system_path // empty' "$plan" 2>/dev/null)"
fi
[ -n "$system_path" ] && { [ -n "$manifest" ] || [ -n "$plan" ]; } \
  || { echo "usage: --plan <dir|plan.json> [--manifest <tsv>] [--system-path <path>] [--cli <path>]" >&2; exit 1; }
if [ -n "$manifest" ]; then
  [ -f "$manifest" ] || { echo "no such manifest: $manifest" >&2; exit 1; }
fi
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

# The container kind an ancestor level should carry, counted up from the system:
# the level directly above it is the line (parent), the one above that the
# family. So books/<family>/<line>/<system> wants family+parent, and a line with
# no family, books/<line>/<system>, wants just parent. $1 = depth, $2 = levels.
kind_for_depth() { case $(( $2 - 1 - $1 )) in 0) echo parent;; 1) echo family;; *) echo "";; esac; }

_err_tmp="$(mktemp)"; _idx_tmp="$(mktemp)"; _q_tmp="$(mktemp)"; _q2_tmp="$(mktemp)"; _idmap_tmp="$(mktemp)"; _man_tmp="$(mktemp)"
trap 'rm -f "$_err_tmp" "$_idx_tmp" "$_q_tmp" "$_q2_tmp" "$_idmap_tmp" "$_man_tmp"' EXIT
# A failed mktemp is not survivable: $_err_tmp is where every CLI call's stderr
# goes, so an empty name turns `2>"$_err_tmp"` into an ambiguous redirect and
# every browse -- including the absent-folder path that must read as "create"
# -- fails as a server error. Say so once instead of misdiagnosing it n times.
for _t in "$_err_tmp" "$_idx_tmp" "$_q_tmp" "$_q2_tmp" "$_idmap_tmp" "$_man_tmp"; do
  [ -n "$_t" ] && [ -f "$_t" ] || { echo "could not create a temporary file (mktemp failed)" >&2; exit 2; }
done
if [ -z "$manifest" ]; then
  jq -r '.rows[] | ["", .target] | @tsv' "$plan" > "$_man_tmp" 2>/dev/null \
    || { echo "unparseable plan: $plan" >&2; exit 2; }
  manifest="$_man_tmp"
fi

# A path that does not exist is data, not a failure: the server answers an
# absent folder with an error exit, never an empty listing, and a greenfield
# import is nothing but absent folders. Verified against the live instance
# 2026-09-08:
#
#   $ grimoire-cli files browse --path "books/Does Not Exist"
#   rc=2
#   … ERROR Not found. No such path in the library. List a folder with: …
#
# The exit code alone cannot be trusted to say which failure this is — it is 2
# for other errors too — so the message is the discriminator. Keep this pattern
# NARROW: if a real outage ever matched it, an import would read a populated
# shelf as empty and re-upload over it.
NOT_FOUND_SIGNAL='No such path in the library'

# Prints the listing. An absent path prints an empty listing and succeeds; any
# other non-zero exit is passed back with its stderr left in $_err_tmp.
browse() {
  local out rc
  out="$("$cli" files browse --path "$1" 2>"$_err_tmp")"
  rc=$?
  if [ "$rc" -eq 0 ]; then printf '%s' "$out"; return 0; fi
  case "$(cat "$_err_tmp")" in
    *"$NOT_FOUND_SIGNAL"*) printf '%s' '{"entries":[]}'; return 0;;
  esac
  return "$rc"
}

# Fetch known systems once
systems_json="$("$cli" systems list --include-children 2>"$_err_tmp")"
systems_exit=$?
if [ "$systems_exit" -ne 0 ]; then
  systems_err="$(cat "$_err_tmp")"
  echo "server error: systems list failed${systems_err:+: $systems_err}" >&2; exit 2
fi
# Validate before parsing: jq prints the first value it reads and only then
# errors on trailing garbage, so a log line merged into the body would be
# silently tolerated rather than caught.
printf '%s' "$systems_json" | jq empty 2>/dev/null \
  || { echo "unparseable systems list response" >&2; exit 2; }

# Grimoire's own slugify (backend/indexer/categories.py): lowercase, drop
# everything that is not a word character, whitespace or hyphen, collapse runs
# of whitespace/underscore/hyphen to one hyphen, trim hyphens. \w is unicode
# aware there, so python3 mirrors it where sed and tr would not.
#   books/Starfall RPG/Core Line/5 EN -> starfall-rpg--core-line--5-en
path_slug() {
  python3 -c 'import sys, re
parts = [p for p in sys.argv[1].split("/") if p]
if parts and parts[0] == "books":
    parts = parts[1:]
out = []
for p in parts:
    v = re.sub(r"[^\w\s-]", "", p.lower())
    v = re.sub(r"[-\s_]+", "-", v)
    out.append(v.strip("-"))
print("--".join(out))' "$1"
}

# The name the server derives for a child system: "<parent leaf> <leaf>".
# A system directly under books/ keeps its bare leaf.
derived_name() {
  local leaf parent
  leaf="$(basename "$1")"
  parent="$(basename "$(dirname "$1")")"
  if [ -z "$parent" ] || [ "$parent" = "books" ] || [ "$parent" = "." ] || [ "$parent" = "/" ]; then
    printf '%s' "$leaf"
  else
    printf '%s %s' "$parent" "$leaf"
  fi
}

system_slug="$(path_slug "$system_path")"
system_name="$(derived_name "$system_path")"

known_systems="$(jq -c '[.[] | {name:.name, id:.id, slug:.slug, container_kind:.container_kind,
                                parent_name:.parent_name, parent_system:.parent_system}]' <<<"$systems_json")"

# The conflict the design doc names: the line is already there under a different
# name. The server derives a child system's name as "<parent leaf> <leaf>", so a
# row carrying OUR derived name at a DIFFERENT slug is the same line filed under
# another family. Our own slug is a reuse, never a conflict. Matching the bare
# folder leaf against .name, or .parent_system against a path, can never fire:
# real rows read name "Core Line 5 EN", parent_system "Core Line".
system_conflicts="$(jq -c --arg slug "$system_slug" --arg name "$system_name" \
  '.[] | select(.name == $name and (.slug // "") != $slug)
       | {slug: (.slug // ""), name: .name, parent_name: (.parent_name // ""), our_slug: $slug}' <<<"$systems_json")"

conflicts_arr="[]"
if [ -n "$system_conflicts" ]; then
  while IFS= read -r conflict; do
    [ -z "$conflict" ] && continue
    conflicts_arr="$(jq -c '. + [{conflict: "a system with this name already exists at a different path", existing: '"$conflict"'}]' <<<"$conflicts_arr")"
  done < <(echo "$system_conflicts" | jq -c .)
fi

# Walk the ancestors (not including the system leaf), recording create/reuse/conflicts.
create="[]"; reuse="[]"
IFS='/' read -r -a parts <<< "$system_path"
path=""
depth=0
for part in "${parts[@]}"; do
  depth=$((depth+1))
  parent="$path"
  path="${path:+$path/}$part"
  [ "$depth" -eq 1 ] && continue            # the collection folder (books/) always exists
  [ "$depth" -eq ${#parts[@]} ] && break    # stop before the system leaf
  want="$(kind_for_depth "$depth" "${#parts[@]}")"

  # browse with error handling (capture stdout and stderr separately)
  browse_out="$(browse "$parent")"
  browse_exit=$?
  if [ "$browse_exit" -ne 0 ]; then
    browse_err="$(cat "$_err_tmp")"
    echo "server error: files browse failed at $parent${browse_err:+: $browse_err}" >&2; exit 2
  fi

  entry="$(echo "$browse_out" | jq -c --arg n "$part" '.entries[]? | select(.name==$n)' 2>/dev/null)"
  if [ -z "$entry" ]; then
    create="$(jq -c --arg p "$path" --arg k "$want" '. + [{path:$p,container_kind:$k}]' <<<"$create")"
  else
    have="$(jq -r '.container_kind // ""' <<<"$entry")"
    if [ "$have" != "$want" ]; then
      conflicts_arr="$(jq -c --arg p "$path" --arg w "$want" --arg h "$have" \
        '. + [{path:$p,expected_container_kind:$w,actual_container_kind:$h}]' <<<"$conflicts_arr")"
    fi
    reuse="$(jq -c --arg p "$path" --arg k "$have" '. + [{path:$p,container_kind:$k}]' <<<"$reuse")"
  fi
done

# Categories the manifest needs, and which already exist.
needed="$(cut -f2 "$manifest" | awk -F/ '{print $1}' | sort -u | jq -R . | jq -sc .)"
browse_out="$(browse "$system_path")"
browse_exit=$?
if [ "$browse_exit" -ne 0 ]; then
  # Server error
  browse_err="$(cat "$_err_tmp")"
  echo "server error: files browse failed at $system_path${browse_err:+: $browse_err}" >&2; exit 2
fi
present="$(echo "$browse_out" | jq -c '[.entries[]? | select(.is_dir) | .name]' 2>/dev/null)"
[ -n "$present" ] || present="[]"
run="$(jq -n --argjson n "$needed" --argjson p "$present" '($n - $p) | length > 0')"

# Dispositions: a target whose full path matches an indexed entry is a skip.
# A manifest target is <category>/[…/]<file> while files browse lists one level
# at a time, so the whole system subtree is walked and full paths are compared
# with full paths. Only directories the server actually reported are descended
# into, so this adds no request that could 404.
record_level() {   # $1 = directory relative to the system root, $2 = browse output
  printf '%s' "$2" | jq -r --arg d "$1" \
    '.entries[]? | select(.record_id) | (if $d == "" then .name else $d + "/" + .name end)' \
    2>/dev/null >> "$_idx_tmp"
  # Same rows, but path\tid -- needed only when --plan asks for a diff.
  printf '%s' "$2" | jq -r --arg d "$1" \
    '.entries[]? | select(.record_id) | [(if $d == "" then .name else $d + "/" + .name end), .record_id] | @tsv' \
    2>/dev/null >> "$_idmap_tmp"
  printf '%s' "$2" | jq -r --arg d "$1" \
    '.entries[]? | select(.is_dir) | (if $d == "" then .name else $d + "/" + .name end)' \
    2>/dev/null >> "$_q2_tmp"
}

: > "$_idx_tmp"; : > "$_idmap_tmp"; : > "$_q2_tmp"
record_level "" "$browse_out"
cp "$_q2_tmp" "$_q_tmp"
level=0
while [ -s "$_q_tmp" ]; do
  level=$((level+1))
  [ "$level" -gt 8 ] && { echo "shelf is nested deeper than 8 levels below $system_path" >&2; exit 2; }
  : > "$_q2_tmp"
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    sub_out="$(browse "$system_path/$rel")"
    sub_exit=$?
    if [ "$sub_exit" -ne 0 ]; then
      sub_err="$(cat "$_err_tmp")"
      echo "server error: files browse failed at $system_path/$rel${sub_err:+: $sub_err}" >&2; exit 2
    fi
    record_level "$rel" "$sub_out"
  done < "$_q_tmp"
  cp "$_q2_tmp" "$_q_tmp"
done

indexed_full="$(jq -R . < "$_idx_tmp" | jq -sc .)"
[ -n "$indexed_full" ] || indexed_full="[]"

dispositions="$(cut -f2 "$manifest" | jq -R . | jq -sc --argjson idx "$indexed_full" \
  'map({target:., disposition: (if . as $path | ($idx | index($path)) then "skip" else "new" end)})')"

existing="$(jq -n --argjson i "$indexed_full" '$i | length')"

# --plan: for every row already on the shelf, fetch its row (`books
# get`, since `books list` omits language and tags) and diff it against the
# plan. Without --plan none of this runs and the output above is untouched.
if [ -n "$plan" ]; then
  plan_json="$(cat "$plan")"
  printf '%s' "$plan_json" | jq empty 2>/dev/null \
    || { echo "unparseable plan: $plan" >&2; exit 2; }

  idx_map="$(jq -R -s '
    split("\n") | map(select(length > 0) | split("\t"))
    | map({(.[0]): .[1]}) | add // {}
  ' "$_idmap_tmp")"

  # The per-field diff, run once per already-indexed row that the plan also
  # names. shelf_row is a `books get` response; plan_row is one entry of
  # plan.rows; idx is the path->book_id map this same walk just built, which
  # is how a variant's target-path "of" is resolved to the id it must match.
  read -r -d '' diff_prog <<'JQ_EOF' || true
# "differs" means BOTH sides hold a value and they disagree. A plan
# that proposes nothing for a field -- the key absent, or present and null,
# which is also how grimoire-cli spells "leave this alone" -- holds no opinion
# to disagree with, so it is "shelf_only": the shelf has something, the plan
# does not ask for anything, and no phase may write. An explicit "" is NOT
# that case: "" is how the CLI clears a field, so it keeps the old reading.
def emptyish: (. == null) or (. == "");
def scalar($shelfv; $planv):
  if ($planv == null) then
    (if ($shelfv|emptyish) then {verdict:"absent_both"}
     else {verdict:"shelf_only", shelf:$shelfv} end)
  elif ($shelfv|emptyish) and ($planv|emptyish) then {verdict:"absent_both"}
  elif ($shelfv|emptyish) then {verdict:"missing"}
  elif ($shelfv == $planv) then {verdict:"same"}
  else {verdict:"differs", shelf:$shelfv, plan:$planv}
  end;
def list_verdict($shelfv; $planv):
  ($shelfv // []) as $s
  | if ($planv == null) then
      (if ($s|length) == 0 then {verdict:"absent_both"}
       else {verdict:"shelf_only", shelf:$s} end)
    else ($planv) as $p
    | if (($s|length) == 0) and (($p|length) == 0) then {verdict:"absent_both"}
      elif ($s|length) == 0 then {verdict:"missing"}
      elif $s == $p then {verdict:"same"}
      else {verdict:"differs", shelf:$s, plan:$p}
      end
    end;
# Which family a field belongs to is read off the values, not a hard-coded
# list: `books batch-update` accepts genres, artists and urls as well as
# authors, and a hard-coded list silently drops whatever it forgot.
def field_verdict($shelfv; $planv):
  if (($planv|type) == "array") or (($planv == null) and (($shelfv|type) == "array"))
  then list_verdict($shelfv; $planv)
  else scalar($shelfv; $planv)
  end;

($plan_row.metadata // {}) as $pm
| ($plan_row.tags // []) as $ptags
| ($plan_row.variant // null) as $pvariant
# EVERY key the plan carries is diffed, because apply.py writes only
# the keys the diff licensed: an un-diffed key is written on a `new` row and
# silently dropped on a `present` one. `metadata` is handed to
# `books batch-update` as-is, so its keys are that request's field names --
# genres, artists, category, license, publisher_url, urls, is_explicit,
# access_level and version among them, none of which a fixed list held.
# (the whole sum is parenthesised: `A + B as $x` binds `as` to B alone.)
| ((reduce ($pm | keys_unsorted[]) as $f
     ({}; . + {($f): field_verdict($shelf_row[$f]; $pm[$f])}))
# tags and variant are computed from the row, not from metadata, so they are
# added last and win over a same-named metadata key.
+ {
    tags: (
      ($shelf_row.tags // []) as $s | ($ptags // []) as $p | ($p - $s) as $add
      | if ($add|length) == 0 then {verdict:"same"}
        else {verdict:"adds", add:$add, shelf:$s} end
    ),
    # variant_main_id is USELESS for "is this row linked" -- on a parent row
    # it holds the parent's own id (verified against the live server), so a
    # parent always looks "linked to itself". variant_parent_id is the field
    # that is null on both a parent and an unlinked row, and holds the
    # parent's id only on an actual child -- that is the field to test for
    # presence, and (being the same id) also the one to compare.
    variant: (
      ($shelf_row.variant_parent_id // null) as $sm
      | ($shelf_row.variant_kind // null) as $sk
      | ($pvariant.of // null) as $of
      | (if ($of|type) == "string" and ($of|length) > 0 then ($idx[$of] // null) else null end) as $pp
      | ($pvariant.kind // null) as $pk
      | if ($of == null or $of == "") then
          # A shelf-held variant link the plan does not propose is a
          # curated relationship, not nothing -- surfaced as differs like
          # every other field family, never silently kept as same. It IS
          # actionable (`duplicates unlink` exists) but only on approval,
          # never applied by a re-run on its own.
          (if ($sm == null) then {verdict:"absent_both"} else {verdict:"differs", shelf:$sm, plan:null} end)
        elif ($sm == null) then {verdict:"missing"}
        elif ($sm == $pp and $sk == $pk) then {verdict:"same"}
        else {verdict:"differs", shelf:$sm, plan:$pp}
        end
    )
  }) as $diff
| ([$diff[] | .verdict] | any(. == "missing" or . == "adds" or . == "differs")) as $writable
| {target:$target, book_id:$id, disposition:(if $writable then "present" else "skip" end), diff:$diff}
JQ_EOF

  overrides="[]"
  skip_targets="$(jq -r '.[] | select(.disposition=="skip") | .target' <<<"$dispositions")"
  while IFS= read -r row_path; do
    [ -n "$row_path" ] || continue
    row_id="$(jq -r --arg p "$row_path" '.[$p] // empty' <<<"$idx_map")"
    [ -n "$row_id" ] || continue
    plan_row="$(jq -c --arg t "$row_path" '[.rows[]? | select(.target==$t)] | first // empty' <<<"$plan_json")"
    [ -n "$plan_row" ] || continue

    shelf_row="$("$cli" books get --id "$row_id" 2>"$_err_tmp")"
    shelf_rc=$?
    if [ "$shelf_rc" -ne 0 ]; then
      shelf_err="$(cat "$_err_tmp")"
      echo "server error: books get failed for $row_id${shelf_err:+: $shelf_err}" >&2; exit 2
    fi
    printf '%s' "$shelf_row" | jq empty 2>/dev/null \
      || { echo "unparseable books get response for $row_id" >&2; exit 2; }

    row_result="$(jq -cn --argjson plan_row "$plan_row" --argjson shelf_row "$shelf_row" \
      --argjson idx "$idx_map" --arg id "$row_id" --arg target "$row_path" "$diff_prog")"
    overrides="$(jq -c --argjson r "$row_result" '. + [$r]' <<<"$overrides")"
  done <<< "$skip_targets"

  dispositions="$(jq -c --argjson ov "$overrides" '
    ( ($ov | map({(.target): .}) | add) // {} ) as $om
    | map(. as $d | ($om[$d.target] // $d))
  ' <<<"$dispositions")"
fi

result="$(jq -cn --argjson ks "$known_systems" --argjson d "$dispositions" --argjson c "$create" --argjson r "$reuse" \
      --argjson n "$needed" --argjson p "$present" --argjson run "$run" \
      --argjson conf "$conflicts_arr" --argjson e "$existing" \
  '{known_systems:$ks,
    dispositions:$d,
    structure:{create:$c, reuse:$r,
               scaffold:{needed:$n, present:$p, run:$run},
               conflicts:$conf},
    existing_books:$e}')"
printf '%s\n' "$result"

# Merge back by target: apply.py and upload.py read disposition, book_id and
# diff off the plan's rows. A plan left unmerged looks brand new to them, so
# apply.py refuses a plan without the shelf_checked stamp. A row that turns
# `new` (target renamed, or the shelf row gone) drops a stale book_id and diff,
# or apply.py would write onto the old book. `structure` is always refreshed
# for make_folders.py; a container_kind the plan already set for a path wins.
if [ -n "$plan" ]; then
  merged="$(jq --argjson d "$dispositions" --argjson st "$(jq -c .structure <<<"$result")" \
      --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
    .shelf_checked = $now
    | ([(.structure.create // [])[] | select(.container_kind) | {key: .path, value: .container_kind}] | from_entries) as $k
    | .structure = ($st | .create |= map(.container_kind = ($k[.path] // .container_kind)))
    | ([$d[] | {key: .target, value: .}] | from_entries) as $m
    | .rows |= map(. as $row | ($m[$row.target] // {}) as $s
        | ($row + ($s | with_entries(select(.key != "target" and .value != null))))
        | if .disposition == "new" then del(.book_id, .diff) else . end)
  ' "$plan")" && printf '%s\n' "$merged" > "$plan"
fi
