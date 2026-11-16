import glob, json, os, unittest

P = os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "profiles", "default")
CATS = ["Core", "Supplements", "Adventures", "Character Sheets", "Maps", "Handouts",
        "Homebrew", "Starter Sets", "Magazines"]


ARMORY = ["Core", "Army Books", "Supplements", "Campaigns", "Mission Packs", "Unit References",
          "Errata", "Starter Sets", "Painting Guides", "Lore", "Magazines"]
KEYS = ("category_folders", "book_variant_kinds", "map_variant_kinds", "token_variant_kinds", "filename_pattern",
        "refused_book_formats", "licence_placement", "entry_rule", "roots", "armory_category_folders")
HEADINGS = ["Goal", "Layout", "Filenames", "Variants and the entry", "Tags", "Licence placement",
            "Maps, tokens, models and audio", "Armory", "Metadata"]


def prof():
    with open(os.path.join(P, "profile.json")) as f:
        return json.load(f)


class ProfileTest(unittest.TestCase):
    def test_profile_json_has_required_keys(self):
        for k in ("category_folders", "book_variant_kinds", "map_variant_kinds", "token_variant_kinds",
                  "filename_pattern", "refused_book_formats", "licence_placement", "entry_rule"):
            self.assertIn(k, prof())
        self.assertEqual(prof()["filename_pattern"], "<code> - <title> - <qualifier> [<year>]")

    def test_profile_has_roots_and_armory(self):
        self.assertEqual(prof()["roots"], {"books": "books", "armory": "armory", "maps": "maps",
                                           "tokens": "tokens", "models": "models", "audio": "audio"})
        self.assertEqual(prof()["armory_category_folders"], ARMORY)

    def test_every_profile_meets_contract(self):
        root = os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "profiles")
        dirs = [d for d in sorted(glob.glob(os.path.join(root, "*"))) if os.path.isdir(d)]
        self.assertTrue(dirs)
        for d in dirs:
            with open(os.path.join(d, "profile.json")) as f:
                p = json.load(f)
            for k in KEYS:
                self.assertIn(k, p, f"{d}: profile.json lacks {k}")
            with open(os.path.join(d, "conventions.md")) as f:
                lines = f.read().splitlines()
            self.assertTrue(lines[0].startswith("# "), f"{d}: first line must be '# <description>'")
            have = {l[3:].strip() for l in lines if l.startswith("## ")}
            for h in HEADINGS:
                self.assertIn(h, have, f"{d}: conventions.md lacks '## {h}'")

    def test_category_folders_exact(self):
        self.assertEqual(prof()["category_folders"], CATS)

    def test_conventions_exists_and_is_opinionated_up_front(self):
        with open(os.path.join(P, "conventions.md")) as f:
            head = f.read(1500).lower()
        self.assertIn("opinionated", head)
        self.assertIn("grimoire-skills.json", head)


if __name__ == "__main__":
    unittest.main()
