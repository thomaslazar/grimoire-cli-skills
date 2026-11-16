import json, os, sys, tempfile, unittest

HERE = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, HERE)
from grimoire_skills import config  # noqa: E402


def w(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(data if isinstance(data, str) else json.dumps(data))


class ConfigTest(unittest.TestCase):
    def setUp(self):
        self.t = tempfile.TemporaryDirectory()
        self.d = os.path.realpath(self.t.name)

    def tearDown(self):
        self.t.cleanup()

    def test_no_config_gives_defaults(self):
        c = config.load(self.d)
        self.assertTrue(c["profile_dir"].endswith("profiles/default"))
        self.assertEqual(c["ocr"], "server")
        self.assertIsNone(c["overrides_dir"])
        self.assertIsNone(c["root"])

    def test_finds_config_in_parent(self):
        w(os.path.join(self.d, "grimoire-skills.json"), {"ocr": "handover"})
        sub = os.path.join(self.d, "a", "b")
        os.makedirs(sub)
        c = config.load(sub)
        self.assertEqual(c["root"], self.d)
        self.assertEqual(c["ocr"], "handover")

    def _with_override(self, profile_override):
        w(os.path.join(self.d, "grimoire-skills.json"), {"overrides": "ov", "lines": "ln"})
        w(os.path.join(self.d, "ov", "profile.json"), profile_override)
        return config.load(self.d)

    def test_override_scalar_wins(self):
        c = self._with_override({"entry_rule": "newest"})
        self.assertEqual(c["profile"]["entry_rule"], "newest")
        self.assertEqual(c["profile"]["licence_placement"], "system-when-uniform")
        self.assertEqual(c["overrides_dir"], os.path.join(self.d, "ov"))
        self.assertEqual(c["lines_dir"], os.path.join(self.d, "ln"))

    def test_override_list_replaces(self):
        c = self._with_override({"category_folders": ["Core"]})
        self.assertEqual(c["profile"]["category_folders"], ["Core"])

    def test_prose_overrides_add(self):
        w(os.path.join(self.d, "grimoire-skills.json"), {"overrides": "ov"})
        w(os.path.join(self.d, "ov", "b.md"), "b")
        w(os.path.join(self.d, "ov", "a.md"), "a")
        files = config.rule_files(config.load(self.d))
        self.assertTrue(files[0].endswith("profiles/default/conventions.md"))
        self.assertEqual([os.path.basename(f) for f in files[1:]], ["a.md", "b.md"])

    def test_profile_path_may_be_custom_dir(self):
        w(os.path.join(self.d, "grimoire-skills.json"), {"profile": "mine"})
        w(os.path.join(self.d, "mine", "profile.json"), {"entry_rule": "x"})
        w(os.path.join(self.d, "mine", "conventions.md"), "x")
        c = config.load(self.d)
        self.assertEqual(c["profile_dir"], os.path.join(self.d, "mine"))
        self.assertEqual(c["profile"], {"entry_rule": "x"})

    def test_repo_root_through_symlink(self):
        link = os.path.join(self.d, "lib")
        os.symlink(HERE, link)
        code = ("import sys; sys.path.insert(0, %r); "
                "from grimoire_skills import config; print(config.repo_root())" % link)
        import subprocess
        out = subprocess.check_output([sys.executable, "-c", code]).decode().strip()
        self.assertEqual(out, os.path.dirname(HERE))
        self.assertEqual(config.repo_root(), os.path.dirname(HERE))

    def test_invalid_ocr_value_raises(self):
        w(os.path.join(self.d, "grimoire-skills.json"), {"ocr": "magic"})
        with self.assertRaises(ValueError):
            config.load(self.d)

    def test_cli_path_order(self):
        w(os.path.join(self.d, "grimoire-skills.json"), {"cli": "tools/gc"})
        c = config.load(self.d)
        self.assertEqual(config.cli_path(c, "/x/gc"), "/x/gc")
        self.assertEqual(config.cli_path(c), os.path.join(self.d, "tools/gc"))
        c["cli"] = None
        old = os.environ.get("PATH")
        try:
            os.environ["PATH"] = self.d
            bindir = os.path.join(self.d, "bin")
            os.makedirs(bindir)
            w(os.path.join(bindir, "grimoire-cli"), "")
            cwd = os.getcwd(); os.chdir(self.d)
            self.assertEqual(config.cli_path(c), os.path.join(self.d, "bin", "grimoire-cli"))
            exe = os.path.join(self.d, "grimoire-cli")
            w(exe, "#!/bin/sh\n"); os.chmod(exe, 0o755)
            self.assertEqual(config.cli_path(c), exe)
        finally:
            os.chdir(cwd)
            os.environ["PATH"] = old

    def test_cli_path_bin_fallback_uses_root(self):
        w(os.path.join(self.d, "grimoire-skills.json"), {})
        c = config.load(self.d)
        old = os.environ.get("PATH")
        try:
            os.environ["PATH"] = os.path.join(self.d, "nothing-here")
            self.assertEqual(config.cli_path(c), os.path.join(self.d, "bin", "grimoire-cli"))
            c["root"] = None
            self.assertEqual(config.cli_path(c), "./bin/grimoire-cli")
        finally:
            os.environ["PATH"] = old

    def test_main_prints_rules(self):
        import subprocess
        w(os.path.join(self.d, "grimoire-skills.json"), {"overrides": "ov"})
        w(os.path.join(self.d, "ov", "a.md"), "a")
        out = json.loads(subprocess.check_output(
            [sys.executable, os.path.join(HERE, "grimoire_skills", "config.py"), "--start", self.d]))
        self.assertEqual(out["rules"], config.rule_files(config.load(self.d)))
        self.assertEqual(len(out["rules"]), 2)

    def test_plan_paths_dir_or_file(self):
        f = os.path.join(self.d, "plan.json")
        w(f, "{}")
        self.assertEqual(config.plan_paths(self.d), (f, self.d))
        self.assertEqual(config.plan_paths(f), (f, self.d))
        other = os.path.join(self.d, "x", "mine.json")
        w(other, "{}")
        self.assertEqual(config.plan_paths(other), (other, os.path.join(self.d, "x")))


if __name__ == "__main__":
    unittest.main()
