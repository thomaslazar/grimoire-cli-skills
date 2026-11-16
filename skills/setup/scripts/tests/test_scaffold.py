import json, os, subprocess, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCAFFOLD = os.path.join(HERE, "..", "scaffold.py")
sys.path.insert(0, os.path.join(HERE, ".."))
import tools_check


sys.path.insert(0, os.path.join(HERE, "..", "..", "..", "..", "lib"))
from grimoire_skills import config


def run(*args, cwd=None):
    return subprocess.run([sys.executable, SCAFFOLD, *args], capture_output=True, text=True, cwd=cwd)


def skills_repo(root):
    """A tiny local repo standing in for the skills repo."""
    os.makedirs(os.path.join(root, "skills", "demo"))
    open(os.path.join(root, "skills", "demo", "SKILL.md"), "w").write("x")
    for c in (["init", "-q"], ["add", "."], ["-c", "user.name=t", "-c", "user.email=nobody", "commit", "-qm", "x"]):
        subprocess.run(["git", "-C", root, *c], check=True, capture_output=True)


class T(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.d = os.path.join(self.tmp.name, "lib")
        self.addCleanup(self.tmp.cleanup)

    def conf(self):
        return json.load(open(os.path.join(self.d, "grimoire-skills.json")))

    def test_scaffold_plugin_mode(self):
        r = run("--mode", "plugin", "--ocr", "handover", "--cli", "/opt/bin/grimoire-cli", self.d)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertFalse(os.path.exists(os.path.join(self.d, "vendor")))
        self.assertFalse(os.path.exists(os.path.join(self.d, ".agents")))
        c = self.conf()
        self.assertEqual(c["ocr"], "handover")
        self.assertEqual(c["cli"], "/opt/bin/grimoire-cli")
        for p in ("grimoire/overrides", "grimoire/lines", "docs", ".git"):
            self.assertTrue(os.path.isdir(os.path.join(self.d, p)), p)
        self.assertEqual(open(os.path.join(self.d, ".gitignore")).read().split(), ["tmp/", "bin/"])
        self.assertIn("No secrets", open(os.path.join(self.d, "AGENTS.md")).read())

    def test_no_cli_key_without_flag(self):
        run("--mode", "plugin", "--ocr", "server", self.d)
        self.assertNotIn("cli", self.conf())
        self.assertNotEqual(run("--mode", "plugin", "--ocr", "server", "--collections", "books", self.d + "2").returncode, 0)

    def test_scaffold_submodule_mode(self):
        src = os.path.join(self.tmp.name, "src")
        skills_repo(src)
        r = run("--mode", "submodule", "--ocr", "server", "--skills-url", src, self.d)
        self.assertEqual(r.returncode, 0, r.stderr)
        for agent in (".agents", ".claude"):
            link = os.path.join(self.d, agent, "skills", "demo")
            self.assertTrue(os.path.islink(link))
            self.assertFalse(os.path.isabs(os.readlink(link)))
            self.assertTrue(os.path.isfile(os.path.join(link, "SKILL.md")))

    def test_scaffold_refuses_existing_config(self):
        os.makedirs(self.d)
        open(os.path.join(self.d, "grimoire-skills.json"), "w").write("{}")
        self.assertEqual(run("--mode", "plugin", "--ocr", "server", self.d).returncode, 2)
        self.assertEqual(open(os.path.join(self.d, "grimoire-skills.json")).read(), "{}")

    def test_scaffold_writes_chosen_profile(self):
        own = os.path.join(self.tmp.name, "mine")
        os.makedirs(own)
        r = run("--mode", "plugin", "--ocr", "server", "--profile", own, self.d)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.conf()["profile"], own)

    def test_scaffold_refuses_unknown_profile(self):
        r = run("--mode", "plugin", "--ocr", "server", "--profile", "nope-xyz", self.d)
        self.assertEqual(r.returncode, 2)
        self.assertFalse(os.path.exists(os.path.join(self.d, "grimoire-skills.json")))

    def test_relative_profile_and_cli_resolve_from_other_cwd(self):
        work = os.path.join(self.tmp.name, "work")
        os.makedirs(os.path.join(work, "myprof"))
        open(os.path.join(work, "myprof", "profile.json"), "w").write("{}")
        os.makedirs(os.path.join(work, "bin"))
        open(os.path.join(work, "bin", "gc"), "w").close()
        r = run("--mode", "plugin", "--ocr", "server", "--profile", "myprof", "--cli", "bin/gc", self.d, cwd=work)
        self.assertEqual(r.returncode, 0, r.stderr)
        cfg = config.load(self.d)
        self.assertEqual(os.path.realpath(cfg["profile_dir"]), os.path.realpath(os.path.join(work, "myprof")))
        self.assertEqual(os.path.realpath(config.cli_path(cfg)), os.path.realpath(os.path.join(work, "bin", "gc")))

    def test_no_nested_git_init_inside_a_repo(self):
        parent = os.path.join(self.tmp.name, "parent")
        os.makedirs(parent)
        subprocess.run(["git", "-C", parent, "init", "-q"], check=True)
        d = os.path.join(parent, "lib")
        self.assertEqual(run("--mode", "plugin", "--ocr", "server", d).returncode, 0)
        self.assertFalse(os.path.exists(os.path.join(d, ".git")))

    def test_tools_check_collections(self):
        self.assertNotIn("ffmpeg", tools_check.check(["books"]))
        self.assertIn("pdfinfo", tools_check.check(["books"]))
        a = tools_check.check(["audio"])
        self.assertIn("ffmpeg", a)
        self.assertEqual(a["ffmpeg"]["level"], "required")
        self.assertEqual(a["pdftoppm"]["level"], "recommended")
        self.assertIn("jq", a)
        self.assertEqual(set(a["jq"]), {"present", "level", "unlocks", "without", "install"})
        self.assertIn("Pillow", tools_check.check(["maps"]))

    def test_tools_check_levels(self):
        self.assertEqual(tools_check.check(["tokens"])["Pillow"]["level"], "required")
        b = tools_check.check(["books"])
        self.assertEqual(b["Pillow"]["level"], "recommended")
        self.assertEqual(b["pdftotext"]["level"], "required")
        self.assertEqual(tools_check.check(["maps"])["Pillow"]["install"]["apt"], "sudo apt install python3-pil")
        gh = tools_check.check([])["gh"]
        self.assertEqual((gh["level"], gh["install"]["brew"], gh["install"]["apt"]),
                         ("required", "brew install gh", "sudo apt install gh"))


if __name__ == "__main__":
    unittest.main()
