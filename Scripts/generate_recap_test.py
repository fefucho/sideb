import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("recap", Path(__file__).with_name("generate_recap.py"))
recap = importlib.util.module_from_spec(spec)
spec.loader.exec_module(recap)


class RecapTests(unittest.TestCase):
    def test_unified_register_filters_tags_and_does_not_republish_imported_history(self):
        with tempfile.TemporaryDirectory(prefix="sideb-recap-") as folder:
            root = Path(folder)
            (root / "FIXES.md").write_text(
                "### [FIX-088] [Compartido] - Shared fix\n"
                "### [FIX-084] [Apple] - Old Mac fix\n- Histórico: sí; imported.\n"
                "### [FIX-090] [Apple] - New Mac fix\n"
                "### [FIX-087] [Windows] - Old Windows fix\n- Histórico: sí.\n"
                "### [FIX-091] [Windows] - New Windows fix\n", encoding="utf-8")
            self.assertEqual([f["id"] for f in recap.extract_fixes_since_tag(None, "macos", root)], ["FIX-088", "FIX-090"])
            self.assertEqual([f["id"] for f in recap.extract_fixes_since_tag(None, "windows", root)], ["FIX-088", "FIX-091"])

    def test_no_new_fix_does_not_fall_back_to_old_fixes_or_invent_improvements(self):
        with tempfile.TemporaryDirectory(prefix="sideb-recap-") as folder:
            root = Path(folder)
            def git(*args):
                return subprocess.run(["git", *args], cwd=root, check=True, capture_output=True)
            git("init", "--initial-branch=main")
            file = root / "FIXES.md"
            file.write_text("### [FIX-088] [Compartido] - Already released\n", encoding="utf-8")
            git("add", "--", "FIXES.md")
            git("-c", "user.name=Recap Test", "-c", "user.email=recap@example.invalid", "-c", "commit.gpgsign=false", "commit", "-m", "base")
            git("-c", "tag.gpgsign=false", "tag", "v1.0.0")
            fixes = recap.extract_fixes_since_tag("v1.0.0", root=root)
            self.assertEqual(fixes, [])
            self.assertNotIn("Already released", recap.generate_markdown(fixes, "1.0.1"))
            file.write_text(file.read_text() + "### [FIX-089] [Compartido] - New local fix\n", encoding="utf-8")
            self.assertEqual([f["id"] for f in recap.extract_fixes_since_tag("v1.0.0", root=root)], ["FIX-089"])

    def test_alias_prevents_republishing_an_entry_after_register_migration(self):
        with tempfile.TemporaryDirectory(prefix="sideb-recap-") as folder:
            root = Path(folder)
            def git(*args):
                return subprocess.run(["git", *args], cwd=root, check=True, capture_output=True)
            git("init", "--initial-branch=main")
            file = root / "FIXES.md"
            file.write_text("### [GENERAL-001] - Already released\n", encoding="utf-8")
            git("add", "--", "FIXES.md")
            git("-c", "user.name=Recap Test", "-c", "user.email=recap@example.invalid", "-c", "commit.gpgsign=false", "commit", "-m", "base")
            git("-c", "tag.gpgsign=false", "tag", "v1.0.0")
            file.write_text("### [FIX-088] [Compartido] - Already released\n- ID anterior: GENERAL-001.\n", encoding="utf-8")
            self.assertEqual(recap.extract_fixes_since_tag("v1.0.0", root=root), [])

    def test_historical_suffix_ids_are_preserved_and_bad_scope_is_reported(self):
        parsed = recap.entries("### [FIX-027-2] [Compartido] - Old queue fix\n- Histórico: sí.\n")
        self.assertEqual(parsed[0]["id"], "FIX-027-2")
        self.assertTrue(parsed[0]["historical"])
        with self.assertRaises(ValueError):
            recap.entries("### [FIX-090] [Typo] - Wrong scope\n")


if __name__ == "__main__":
    unittest.main()
