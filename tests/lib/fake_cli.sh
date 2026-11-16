#!/usr/bin/env bash
# Stands in for grimoire-cli in tests. Replays fixtures, logs calls.
#   FAKE_CLI_DIR/responses/<key>.json           what to print
#   FAKE_CLI_DIR/responses/<key>__<slug>.json   path-scoped variant
#   FAKE_CLI_DIR/stderr/<key>                   stderr written before the body
#   FAKE_CLI_DIR/stderr_after/<key>             stderr written after the body
#   FAKE_CLI_DIR/exit/<key>                     what to exit with (default 0)
#   FAKE_CLI_DIR/exit/<key>__<slug>             path-scoped exit code
#   FAKE_CLI_DIR/calls.log                      every argv, one line each
#   FAKE_CLI_DIR/stdin.log                      every --stdin body, one line each
set -u
dir="${FAKE_CLI_DIR:?FAKE_CLI_DIR must be set}"
mkdir -p "$dir"
printf '%s\n' "$*" >> "$dir/calls.log"
case " $* " in *" --stdin "*) { cat; echo; } >> "$dir/stdin.log";; esac

key=""
path=""
skip_next=0
for arg in "$@"; do
  if [ "$skip_next" -eq 1 ]; then
    path="$arg"
    skip_next=0
  elif [ "$arg" = "--path" ]; then
    skip_next=1
  elif case "$arg" in -*) true;; *) false;; esac; then
    break
  else
    key="${key:+$key-}$arg"
  fi
done

# Extract slug from path: replace /, space, and other non-alphanumeric with _
slug=""
if [ -n "$path" ]; then
  slug="$(printf '%s' "$path" | sed 's|[^a-zA-Z0-9._-]|_|g')"
fi

# Count calls per key so a fixture can differ between the first and second call.
mkdir -p "$dir/.counts"
n=$(( $(cat "$dir/.counts/${key}" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$dir/.counts/${key}"

# Emit stderr if present: try path-scoped first, then sequenced, then base
if [ -n "$slug" ] && [ -f "$dir/stderr/${key}__${slug}.$n" ]; then
  cat "$dir/stderr/${key}__${slug}.$n" >&2
elif [ -n "$slug" ] && [ -f "$dir/stderr/${key}__${slug}" ]; then
  cat "$dir/stderr/${key}__${slug}" >&2
elif [ -f "$dir/stderr/${key}.$n" ]; then
  cat "$dir/stderr/${key}.$n" >&2
elif [ -f "$dir/stderr/${key}" ]; then
  cat "$dir/stderr/${key}" >&2
fi

# Try path-scoped fixture first, then numbered variant, then base variant
if [ -n "$slug" ] && [ -f "$dir/responses/${key}__${slug}.$n.json" ]; then
  cat "$dir/responses/${key}__${slug}.$n.json"
elif [ -n "$slug" ] && [ -f "$dir/responses/${key}__${slug}.json" ]; then
  cat "$dir/responses/${key}__${slug}.json"
elif [ -f "$dir/responses/${key}.$n.json" ]; then
  cat "$dir/responses/${key}.$n.json"
elif [ -f "$dir/responses/${key}.json" ]; then
  cat "$dir/responses/${key}.json"
fi
# The real CLI writes to stderr around the body, not only before it: the cached
# version check and --debug logging can land after the response has been printed.
if [ -n "$slug" ] && [ -f "$dir/stderr_after/${key}__${slug}.$n" ]; then
  cat "$dir/stderr_after/${key}__${slug}.$n" >&2
elif [ -n "$slug" ] && [ -f "$dir/stderr_after/${key}__${slug}" ]; then
  cat "$dir/stderr_after/${key}__${slug}" >&2
elif [ -f "$dir/stderr_after/${key}.$n" ]; then
  cat "$dir/stderr_after/${key}.$n" >&2
elif [ -f "$dir/stderr_after/${key}" ]; then
  cat "$dir/stderr_after/${key}" >&2
fi

# Exit codes follow the same ladder as responses: path-scoped, then sequenced,
# then base -- an absent folder fails for one path while its siblings succeed.
if [ -n "$slug" ] && [ -f "$dir/exit/${key}__${slug}.$n" ]; then
  exit "$(cat "$dir/exit/${key}__${slug}.$n")"
elif [ -n "$slug" ] && [ -f "$dir/exit/${key}__${slug}" ]; then
  exit "$(cat "$dir/exit/${key}__${slug}")"
elif [ -f "$dir/exit/${key}.$n" ]; then
  exit "$(cat "$dir/exit/${key}.$n")"
elif [ -f "$dir/exit/${key}" ]; then
  exit "$(cat "$dir/exit/${key}")"
fi
exit 0
