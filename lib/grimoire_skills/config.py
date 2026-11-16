"""Resolve grimoire-skills.json, the profile and its overrides."""
import argparse, glob, json, os, shutil

CONFIG_NAME = "grimoire-skills.json"


def repo_root():
    return os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__))))


def _read(path):
    with open(path) as f:
        return json.load(f)


def _find_config(start):
    d = os.path.realpath(start)
    while True:
        if os.path.isfile(os.path.join(d, CONFIG_NAME)):
            return d
        parent = os.path.dirname(d)
        if parent == d:
            return None
        d = parent


def load(start=None):
    root = _find_config(start or os.getcwd())
    conf = _read(os.path.join(root, CONFIG_NAME)) if root else {}
    rel = lambda p: p if os.path.isabs(p) else os.path.join(root, p)

    name = conf.get("profile", "default")
    builtin = os.path.join(repo_root(), "profiles", name)
    profile_dir = builtin if os.path.isdir(builtin) else rel(name)
    ov = conf.get("overrides")
    overrides_dir = rel(ov) if ov else None
    lines = conf.get("lines")
    lines_dir = rel(lines) if lines else None

    ocr = conf.get("ocr", "server")
    if ocr not in ("server", "handover"):
        raise ValueError("ocr must be 'server' or 'handover', got %r" % (ocr,))

    profile = _read(os.path.join(profile_dir, "profile.json"))
    ov_json = os.path.join(overrides_dir, "profile.json") if overrides_dir else None
    if ov_json and os.path.isfile(ov_json):
        profile.update(_read(ov_json))  # key by key; lists replace

    cli = conf.get("cli")
    return {"cli": rel(cli) if cli else None, "root": root, "profile_dir": profile_dir, "overrides_dir": overrides_dir,
            "lines_dir": lines_dir, "ocr": ocr, "profile": profile}


def cli_path(cfg, override=None):
    """--cli > `cli` in the config > grimoire-cli on PATH > ./bin/grimoire-cli."""
    fallback = os.path.join(cfg["root"], "bin", "grimoire-cli") if cfg.get("root") else "./bin/grimoire-cli"
    return override or cfg.get("cli") or shutil.which("grimoire-cli") or fallback


def plan_paths(arg):
    """(plan file, run dir) from a run directory holding plan.json, or from a plan file."""
    if os.path.isdir(arg):
        return os.path.join(arg, "plan.json"), arg
    return arg, os.path.dirname(os.path.abspath(arg))


def rule_files(cfg):
    files = [os.path.join(cfg["profile_dir"], "conventions.md")]
    if cfg["overrides_dir"]:
        files += sorted(glob.glob(os.path.join(cfg["overrides_dir"], "*.md")))
    return files


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--start", default=os.getcwd())
    cfg = load(ap.parse_args().start)
    print(json.dumps({**cfg, "rules": rule_files(cfg)}))
