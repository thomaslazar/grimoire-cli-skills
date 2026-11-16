#!/usr/bin/env python3
"""Detect grimoire-cli command groups/version and which skills it can serve."""
import argparse, json, os, re, subprocess, sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "..", "..", "lib"))
from grimoire_skills import config  # noqa: E402


def groups(help_text):
    """Command names listed under the 'Commands:' section of --help."""
    out, on = set(), False
    for line in help_text.splitlines():
        if line.strip() == "Commands:":
            on = True
        elif on:
            m = re.match(r"\s+([a-z][a-z0-9-]*)(\s|$)", line)
            if m:
                out.add(m.group(1))
            elif line.strip():
                break
    return out


FLOOR = "0.8.0"
CONTENT_GROUPS = {"books", "maps", "tokens", "models", "audio", "armies", "leagues", "pins"}


def _tuple(v):
    return tuple(int(x) for x in re.findall(r"\d+", v)[:3])


def version(text):
    m = re.search(r"\d+\.\d+\.\d+", text)
    return m.group(0) if m else ""


def _metadata(path):
    """Minimal reader: the metadata: map of the --- frontmatter block."""
    with open(path, encoding="utf-8") as f:
        lines = f.read().splitlines()
    if not lines or lines[0].strip() != "---":
        return {}
    meta, in_meta, key = {}, False, None
    for line in lines[1:]:
        if line.strip() == "---":
            break
        if not line.startswith(" "):
            in_meta = line.strip() == "metadata:"
            continue
        if not in_meta:
            continue
        s = line.strip()
        if s.startswith("- ") and key:
            meta.setdefault(key, []).append(s[2:].strip().strip("\"'"))
        elif ":" in s:
            key, _, val = s.partition(":")
            val = val.strip().strip("\"'")
            meta[key] = val if val and val != "[]" else []
    return meta


def below_floor(cli_version):
    """True when the CLI is older than FLOOR; an unparseable version fails closed."""
    return not cli_version or _tuple(cli_version) < _tuple(FLOOR)


def unskilled(skills_dir, grps):
    """Content groups the CLI offers that no skill declares."""
    declared = set()
    for name in os.listdir(skills_dir):
        p = os.path.join(skills_dir, name, "SKILL.md")
        if os.path.isfile(p):
            declared |= set(_metadata(p).get("grimoire-cli-groups") or [])
    return sorted((grps & CONTENT_GROUPS) - declared)


def offerable(skills_dir, grps, cli_version):
    res = []
    for name in sorted(os.listdir(skills_dir)):
        p = os.path.join(skills_dir, name, "SKILL.md")
        if not os.path.isfile(p):
            continue
        m = _metadata(p)
        missing = sorted(set(m.get("grimoire-cli-groups") or []) - grps)
        min_cli = m.get("min-cli") or ""
        too_old = bool(min_cli) and _tuple(cli_version) < _tuple(min_cli)
        res.append({"skill": name, "ok": not missing and not too_old,
                    "missing": missing, "too_old": too_old})
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--skills-dir", required=True)
    ap.add_argument("--cli", help="CLI path (default: config `cli`, PATH, ./bin/grimoire-cli)")
    a = ap.parse_args()
    a.cli = config.cli_path(config.load(), a.cli)
    run = lambda *x: subprocess.run([a.cli, *x], capture_output=True, text=True, check=True).stdout
    try:
        g, v = groups(run("--help")), version(run("--version"))
    except (OSError, subprocess.CalledProcessError) as e:
        sys.exit(f"cannot run {a.cli}: {e}")
    print(json.dumps({"skills": offerable(a.skills_dir, g, v), "unskilled": unskilled(a.skills_dir, g),
                      "below_floor": below_floor(v)}))


if __name__ == "__main__":
    main()
