#!/usr/bin/env bash
# Stands in for pdftotext: prints "<file>.txt" for the .pdf argument.
for a in "$@"; do case "$a" in *.pdf) cat "$a.txt" 2>/dev/null || { echo "Syntax Error: bad pdf" >&2; exit 1; }; exit 0;; esac; done
exit 1
