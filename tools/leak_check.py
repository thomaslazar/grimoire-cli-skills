#!/usr/bin/env python3
"""Fail on private data in files. Usage: leak_check.py [--patterns FILE] PATH..."""
import argparse, os, re, sys

RULES = {
    "macos-home": r"/Users/[^/\s]+",
    "linux-home": r"/home/[^/\s]+",
    "tilde-path": r"~/(?!\.agents/|\.grimoire-cli/|\.claude/)[^\s]*",
    "HOME-path": r"\$\{?HOME\}?/[^\s]*",
    "email": r"[\w.+-]+@[\w-]+\.[\w.-]+",
    "run-id": r"tmp/import-[\w-]+/\d{8}T\d{6}",
}
# these hold the rule patterns and deliberate fake examples
_HERE = os.path.dirname(os.path.abspath(__file__))
SELF_TESTS = {os.path.join(_HERE, n) for n in ("test_leak_check.py", "leak_check.py")}


def files(paths):
    for p in paths:
        if os.path.isfile(p):
            if os.path.abspath(p) not in SELF_TESTS:
                yield p
            continue
        for root, dirs, names in os.walk(p):
            dirs[:] = [d for d in dirs if d != ".git"]
            for n in names:
                f = os.path.join(root, n)
                if os.path.abspath(f) not in SELF_TESTS:
                    yield f


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--patterns")
    ap.add_argument("paths", nargs="+")
    a = ap.parse_args()
    rules = {k: re.compile(v) for k, v in RULES.items()}
    if a.patterns:
        with open(a.patterns) as fh:
            for i, ln in enumerate(fh, 1):
                ln = ln.strip()
                if ln and not ln.startswith("#"):
                    rules[f"private-{i}"] = re.compile(ln)
    hits = 0
    for f in files(a.paths):
        try:
            text = open(f, encoding="utf-8").read()
        except (UnicodeDecodeError, OSError):
            continue  # binary
        for n, line in enumerate(text.splitlines(), 1):
            for name, rx in rules.items():
                m = rx.search(line)
                if m:
                    print(f"{f}:{n}: {name}: {m.group(0)}")
                    hits += 1
    return 1 if hits else 0


if __name__ == "__main__":
    sys.exit(main())
