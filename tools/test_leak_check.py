import os, subprocess, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "leak_check.py")


def run(text, patterns=None):
    with tempfile.TemporaryDirectory() as d:
        f = os.path.join(d, "x.md")
        with open(f, "w") as fh:
            fh.write(text + "\n")
        cmd = [sys.executable, SCRIPT]
        if patterns is not None:
            p = os.path.join(d, "pat.txt")
            with open(p, "w") as fh:
                fh.write("# comment\n" + patterns + "\n")
            cmd += ["--patterns", p]
        r = subprocess.run(cmd + [f], capture_output=True, text=True)
        return r.returncode, r.stdout


class LeakCheck(unittest.TestCase):
    def hit(self, text):
        rc, out = run(text)
        self.assertEqual(rc, 1, out)
        self.assertIn("x.md:1:", out)

    def test_flags_macos_home(self):
        self.hit("see /Users/alice/x")

    def test_flags_linux_home(self):
        self.hit("see /home/bob/x")

    def test_flags_tilde_and_HOME(self):
        self.hit("~/Documents/books")
        self.hit("$HOME/Documents")
        self.hit("${HOME}/Documents")

    def test_flags_email(self):
        self.hit("mail a.b@example.org")

    def test_flags_run_id(self):
        self.hit("tmp/import-books/20261114T100000-x")

    def test_private_patterns_file(self):
        self.assertEqual(run("host secret-host.lan")[0], 0)
        self.assertEqual(run("host secret-host.lan", r"secret-host\.lan")[0], 1)

    def test_same_name_elsewhere_is_flagged(self):
        with tempfile.TemporaryDirectory() as d:
            os.makedirs(os.path.join(d, "skills", "x"))
            f = os.path.join(d, "skills", "x", "test_leak_check.py")
            open(f, "w").write("/Users/alice/x\n")
            r = subprocess.run([sys.executable, SCRIPT, d], capture_output=True, text=True)
            self.assertEqual(r.returncode, 1, r.stdout)

    def test_clean_file_exits_0(self):
        self.assertEqual(run("nothing to see")[0], 0)

    def test_allows_placeholder_paths(self):
        rc, out = run("/path/to/library ~/.agents/skills ~/.grimoire-cli/config.json")
        self.assertEqual(rc, 0, out)


if __name__ == "__main__":
    unittest.main()
