# Minimal assertions. Source this; call report at the end.
_pass=0; _fail=0

fail() { printf 'FAIL: %s\n' "$1" >&2; _fail=$((_fail+1)); }
pass() { _pass=$((_pass+1)); }

assert_eq() { # actual expected msg
  if [ "$1" = "$2" ]; then pass; else
    fail "$3
  expected: [$2]
  actual:   [$1]"
  fi
}

assert_contains() { # haystack needle msg
  case "$1" in *"$2"*) pass;; *) fail "$3
  missing: [$2]";; esac
}

assert_exit() { # expected-code cmd...
  local want="$1"; shift
  "$@" >/dev/null 2>&1
  local got=$?
  assert_eq "$got" "$want" "exit code of: $*"
}

report() {
  printf '%s passed, %s failed\n' "$_pass" "$_fail"
  [ "$_fail" -eq 0 ]
}
