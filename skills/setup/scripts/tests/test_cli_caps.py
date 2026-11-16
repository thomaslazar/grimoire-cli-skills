import os, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
import cli_caps


def skill(root, name, meta=None):
    d = os.path.join(root, name)
    os.makedirs(d)
    fm = f"---\nname: {name}\ndescription: Use when testing.\n"
    if meta:
        fm += "metadata:\n"
        if "groups" in meta:
            fm += "  grimoire-cli-groups:\n" + "".join(f"    - {g}\n" for g in meta["groups"])
        if "min-cli" in meta:
            fm += f'  min-cli: "{meta["min-cli"]}"\n'
        if "min-server" in meta:
            fm += f'  min-server: "{meta["min-server"]}"\n'
    with open(os.path.join(d, "SKILL.md"), "w") as f:
        f.write(fm + "---\n\n# body\n")


class Caps(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def offer(self, groups, ver="0.8.0"):
        return {r["skill"]: r for r in cli_caps.offerable(self.tmp.name, groups, ver)}

    def test_groups_from_fixture(self):
        with open(os.path.join(HERE, "fixtures", "help-0.8.0.txt")) as f:
            g = cli_caps.groups(f.read())
        for want in ("books", "maps", "tokens", "models", "audio", "systems", "files"):
            self.assertIn(want, g)
        self.assertNotIn("Usage", g)

    def test_groups_from_080_fixture(self):
        with open(os.path.join(HERE, "fixtures", "help-0.8.0.txt")) as f:
            g = cli_caps.groups(f.read())
        for want in ("armies", "leagues", "pins"):
            self.assertIn(want, g)

    def test_below_floor(self):
        self.assertTrue(cli_caps.below_floor("0.7.6"))
        self.assertFalse(cli_caps.below_floor("0.8.0"))
        self.assertFalse(cli_caps.below_floor("0.10.0"))
        self.assertTrue(cli_caps.below_floor(""))

    def test_unskilled_lists_groups_without_skill(self):
        skill(self.tmp.name, "a", {"groups": ["books", "maps", "tokens", "models", "audio"]})
        with open(os.path.join(HERE, "fixtures", "help-0.8.0.txt")) as f:
            g = cli_caps.groups(f.read())
        self.assertEqual(cli_caps.unskilled(self.tmp.name, g), ["armies", "leagues", "pins"])

    def test_version(self):
        self.assertEqual(cli_caps.version("0.8.0\n"), "0.8.0")
        self.assertEqual(cli_caps.version("grimoire-cli 1.2.3+abc"), "1.2.3")

    def test_offerable_missing_group(self):
        skill(self.tmp.name, "a", {"groups": ["books", "armory"]})
        r = self.offer({"books"})["a"]
        self.assertFalse(r["ok"])
        self.assertEqual(r["missing"], ["armory"])

    def test_offerable_too_old(self):
        skill(self.tmp.name, "a", {"groups": ["books"], "min-cli": "9.0.0"})
        r = self.offer({"books"})["a"]
        self.assertTrue(r["too_old"])
        self.assertFalse(r["ok"])

    def test_offerable_ok(self):
        skill(self.tmp.name, "a", {"groups": ["books"], "min-cli": "0.7.0", "min-server": "1.10.1"})
        r = self.offer({"books"})["a"]
        self.assertEqual((r["ok"], r["missing"], r["too_old"]), (True, [], False))

    def test_frontmatter_without_metadata_is_ok(self):
        skill(self.tmp.name, "a")
        self.assertTrue(self.offer(set())["a"]["ok"])

    def test_semver_numeric_not_lexical(self):
        skill(self.tmp.name, "a", {"min-cli": "0.10.0"})
        self.assertTrue(self.offer(set(), "0.9.0")["a"]["too_old"])

    def test_empty_inline_list_is_empty(self):
        d = os.path.join(self.tmp.name, "a"); os.makedirs(d)
        with open(os.path.join(d, "SKILL.md"), "w") as f:
            f.write("---\nname: a\ndescription: x\nmetadata:\n  grimoire-cli-groups: []\n---\n")
        r = self.offer(set())["a"]
        self.assertEqual((r["ok"], r["missing"]), (True, []))

    def test_folded_description_does_not_break_metadata(self):
        d = os.path.join(self.tmp.name, "a"); os.makedirs(d)
        with open(os.path.join(d, "SKILL.md"), "w") as f:
            f.write('---\nname: a\ndescription: >-\n  Use when testing. Triggers: "go",\n  "pr #6".\n'
                    'metadata:\n  grimoire-cli-groups:\n    - books\n  min-cli: "0.8.0"\n---\n')
        self.assertEqual(cli_caps._metadata(os.path.join(d, "SKILL.md")),
                         {"grimoire-cli-groups": ["books"], "min-cli": "0.8.0"})

    def test_cli_defaults_to_config(self):
        import json, stat, subprocess
        root = os.path.realpath(self.tmp.name)
        skill(root, "a", {"groups": ["books"]})
        fake = os.path.join(root, "bin", "gc"); os.makedirs(os.path.dirname(fake))
        with open(fake, "w") as f:
            f.write('#!/bin/sh\n[ "$1" = --version ] && echo 0.8.0 && exit 0\nprintf "Commands:\\n  books  x\\n"\n')
        os.chmod(fake, 0o755)
        with open(os.path.join(root, "grimoire-skills.json"), "w") as f:
            json.dump({"cli": "bin/gc"}, f)
        env = {**os.environ, "PATH": "/usr/bin:/bin"}
        r = subprocess.run([sys.executable, os.path.join(HERE, "..", "cli_caps.py"), "--skills-dir", root],
                           capture_output=True, text=True, cwd=root, env=env)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(json.loads(r.stdout)["skills"][0]["ok"])

    def test_every_shipped_skill_offerable_on_floor_cli(self):
        with open(os.path.join(HERE, "fixtures", "help-0.8.0.txt")) as f:
            g = cli_caps.groups(f.read())
        skills = os.path.join(HERE, "..", "..", "..")
        bad = [r for r in cli_caps.offerable(skills, g, "0.8.0") if not r["ok"]]
        self.assertEqual(bad, [])


if __name__ == "__main__":
    unittest.main()
