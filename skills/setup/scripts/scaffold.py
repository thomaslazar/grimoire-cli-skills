#!/usr/bin/env python3
"""Scaffold a dedicated library repo: config, overrides, lines, docs, AGENTS.md, .gitignore."""
import argparse, json, os, subprocess, sys

CONFIG = "grimoire-skills.json"
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
DEFAULT_URL = "https://github.com/thomaslazar/grimoire-cli-skills.git"
AGENTS = """# Library repo

Work on the Grimoire library happens here, through the grimoire-cli skills.

- Skills: see `.agents/skills/` or `.claude/skills/` (or the installed plugin).
- Settings: `grimoire-skills.json` (profile, overrides, lines, OCR route).
- Your own rules go in `grimoire/overrides/`; line references in `grimoire/lines/`.
- What is on the shelves and lessons learned go in `docs/`. Run directories go in `tmp/` (ignored).

**No secrets in this repo.** Never copy `~/.grimoire-cli/config.json` (server login and tokens) here.
Log in with `grimoire-cli login` in your own terminal.
"""


def die(msg):
    print("scaffold: " + msg, file=sys.stderr)
    sys.exit(2)


def git(d, *a):
    subprocess.run(["git", "-C", d, *a], check=True, capture_output=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["plugin", "submodule"], required=True)
    ap.add_argument("--ocr", choices=["server", "handover"], required=True)
    ap.add_argument("--profile", default="default")
    ap.add_argument("--cli")
    ap.add_argument("--skills-url", default=DEFAULT_URL)
    ap.add_argument("dir")
    a = ap.parse_args()

    d = a.dir
    cfg = os.path.join(d, CONFIG)
    if os.path.exists(cfg):
        die(CONFIG + " already exists in " + d)
    if not (os.path.isdir(os.path.join(REPO, "profiles", a.profile)) or os.path.isdir(a.profile)):
        die("unknown profile %r: not a shipped profile and not a folder" % a.profile)

    os.makedirs(d, exist_ok=True)

    def rel(p):  # config paths resolve against the repo, so store them relative to it
        return p if os.path.isabs(p) else os.path.relpath(os.path.realpath(p), os.path.realpath(d))

    shipped = os.path.isdir(os.path.join(REPO, "profiles", a.profile))
    conf = {"profile": a.profile if shipped else rel(a.profile), "overrides": "grimoire/overrides", "lines": "grimoire/lines", "ocr": a.ocr}
    if a.cli:
        conf["cli"] = rel(a.cli)
    for sub in ("grimoire/overrides", "grimoire/lines", "docs"):
        os.makedirs(os.path.join(d, sub), exist_ok=True)
        open(os.path.join(d, sub, ".gitkeep"), "a").close()
    with open(cfg, "w") as f:
        json.dump(conf, f, indent=2)
        f.write("\n")
    for name, text in (("AGENTS.md", AGENTS), (".gitignore", "tmp/\nbin/\n")):
        p = os.path.join(d, name)
        if not os.path.exists(p):
            with open(p, "w") as f:
                f.write(text)

    inside = subprocess.run(["git", "-C", d, "rev-parse", "--is-inside-work-tree"], capture_output=True)
    if inside.returncode != 0:
        git(d, "init", "-q")
    if a.mode == "submodule":
        # file protocol allowed so a local path works offline; harmless for a URL
        git(d, "-c", "protocol.file.allow=always", "submodule", "add", "-q", a.skills_url, "vendor/grimoire-cli-skills")
        skills = os.path.join(d, "vendor", "grimoire-cli-skills", "skills")
        for agent in (".agents", ".claude"):
            os.makedirs(os.path.join(d, agent, "skills"), exist_ok=True)
            for n in sorted(os.listdir(skills)):
                link = os.path.join(d, agent, "skills", n)
                if not os.path.lexists(link):
                    os.symlink(os.path.join("..", "..", "vendor", "grimoire-cli-skills", "skills", n), link)
    print(json.dumps({"dir": d, "mode": a.mode, "config": conf}))


if __name__ == "__main__":
    main()
