"""CLI calls and `files browse` helpers shared by the pipeline scripts."""
import json, subprocess, unicodedata


def nfc(s):
    return unicodedata.normalize("NFC", s)


def run(cli, *args, body=None):
    """Return (exit code, parsed stdout or {}, stderr + stdout)."""
    if body is not None:
        args = (*args, "--stdin")
    p = subprocess.run([cli, *args], capture_output=True, text=True,
                       input=None if body is None else json.dumps(body, ensure_ascii=False))
    try:
        out = json.loads(p.stdout) if p.stdout.strip() else {}
    except json.JSONDecodeError:
        out = {}
    return p.returncode, out, p.stderr + p.stdout


def listing(cli, path):
    """{NFC name: entry} of a library folder as the server sees it, or None if it does not exist."""
    rc, out, _ = run(cli, "files", "browse", "--path", path)
    return None if rc or "entries" not in out else {nfc(e["name"]): e for e in out["entries"]}


def system_of(cli, book_id):
    """The id of the system a book sits on, or None."""
    gs = run(cli, "books", "get", "--id", book_id)[1].get("game_system")
    return gs.get("id") if isinstance(gs, dict) else gs


def receipts(path):
    """{key: last receipt} of an append-only ndjson receipt file; missing file reads as empty."""
    try:
        with open(path) as f:
            return {(r.get("step"), r["target"]): r for r in map(json.loads, filter(str.strip, f))}
    except FileNotFoundError:
        return {}


def need_tool(name, hint):
    """Exit 2 with an install hint when a recommended tool is missing."""
    import shutil, sys
    if not shutil.which(name):
        refuse(f"{name} not found; install it ({hint}) and re-run")


def pdf_pages(path, drop=None):
    """Text of each page of a PDF via pdftotext (ValueError if it fails); lines matching the regex `drop` are removed first."""
    import re
    p = subprocess.run(["pdftotext", "-layout", path, "-"], capture_output=True, text=True, errors="replace")
    if p.returncode:
        raise ValueError(p.stderr.strip()[-200:] or f"pdftotext exit {p.returncode}")
    t = p.stdout
    pages = t.split("\f")
    if pages and not pages[-1].strip():
        pages = pages[:-1]
    rx = re.compile(drop) if drop else None
    return ["\n".join(l for l in p.splitlines() if not (rx and rx.search(l))).strip() for p in pages]


def refuse(msg):
    """Unmet precondition: message on stderr, exit 2."""
    import sys
    sys.stderr.write(msg + "\n")
    sys.exit(2)
