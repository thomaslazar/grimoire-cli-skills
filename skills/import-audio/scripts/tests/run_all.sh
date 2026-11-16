#!/usr/bin/env bash
# Runs every test in this directory; exits non-zero if any failed.
here="$(cd "$(dirname "$0")" && pwd)"; rc=0
for t in "$here"/test_*.sh; do echo "== $(basename "$t")"; bash "$t" || rc=1; done
exit $rc
