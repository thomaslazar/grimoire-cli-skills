#!/usr/bin/env python3
"""Report which helper tools are present and what each unlocks. Installs nothing."""
import argparse, json, shutil

R, REC = "required", "recommended"


def poppler():
    return {"brew": "brew install poppler", "apt": "sudo apt install poppler-utils"}


def one(name):
    return {"brew": "brew install " + name, "apt": "sudo apt install " + name}


# name -> (collections that need it or None for always, level, unlocks, without, install)
TOOLS = {
    "gh": (None, R, "installing and updating grimoire-cli (install-grimoire-cli)", "the CLI cannot be installed by the skill", one("gh")),
    "jq": (None, R, "reading the CLI's JSON output", "most skill steps cannot run", one("jq")),
    "python3": (None, R, "the skills' helper scripts", "no helper script runs", {"brew": "brew install python", "apt": "sudo apt install python3"}),
    "pdfinfo": ({"books"}, REC, "page counts and PDF metadata", "page counts and imprint reading are lost", poppler()),
    "pdftotext": ({"books"}, R, "reading imprint and credits text, the OCR survey", "imprint reading and the OCR survey cannot run", poppler()),
    "pdftoppm": ({"books", "audio"}, REC, "rendering pages as images (covers, back covers)", "no rendered covers or back-cover reading", poppler()),
    "qpdf": ({"books"}, REC, "merging and repairing PDFs", "merges and repairs are not possible", one("qpdf")),
    "ffmpeg": ({"audio"}, R, "tagging and converting audio", "audio cannot be imported", one("ffmpeg")),
    "ffprobe": ({"audio"}, R, "reading audio tags and durations", "audio cannot be imported", one("ffmpeg")),
}


def pillow():
    try:
        import PIL  # noqa: F401
        return True
    except ImportError:
        return False


def check(collections):
    cols = set(collections)
    out = {}
    for n, (need, level, unlocks, without, inst) in TOOLS.items():
        if need is None or need & cols:
            out[n] = {"present": shutil.which(n) is not None, "level": level, "unlocks": unlocks, "without": without, "install": inst}
    if cols & {"books", "maps", "tokens", "audio"}:
        out["Pillow"] = {"present": pillow(), "level": R if "tokens" in cols else REC,
                         "unlocks": "image sizes, resizing, cropping, transparency checks, contact sheets",
                         "without": "image checks and covers are skipped; token drafting cannot run",
                         "install": {"brew": "python3 -m pip install Pillow", "apt": "sudo apt install python3-pil"}}
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--collections", default="")
    print(json.dumps(check([c for c in ap.parse_args().collections.split(",") if c])))
