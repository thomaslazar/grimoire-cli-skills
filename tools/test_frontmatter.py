import glob, os, unittest

try:
    import yaml
except ImportError:
    yaml = None

REPO = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))


def frontmatter(path):
    text = open(path, encoding="utf-8").read()
    assert text.startswith("---\n"), path
    return text[4:text.index("\n---\n", 4)]


@unittest.skipIf(yaml is None, "SKIP: PyYAML not installed (python3 -m pip install pyyaml)")
class Frontmatter(unittest.TestCase):
    def test_every_skill_frontmatter_is_valid_yaml(self):
        files = sorted(glob.glob(os.path.join(REPO, "skills", "*", "SKILL.md")))
        self.assertTrue(files)
        for p in files:
            with self.subTest(p):
                fm = yaml.safe_load(frontmatter(p))
                self.assertEqual(fm["name"], os.path.basename(os.path.dirname(p)))
                self.assertIsInstance(fm["description"], str)
                self.assertTrue(fm["description"].rstrip().endswith("."), "description looks truncated")
                groups = fm.get("metadata", {}).get("grimoire-cli-groups", [])
                self.assertIsInstance(groups, list)


if __name__ == "__main__":
    unittest.main()
