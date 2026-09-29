import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("version", Path(__file__).resolve().parents[1] / "scripts/version.py")
version = importlib.util.module_from_spec(spec)
spec.loader.exec_module(version)


class VersionTests(unittest.TestCase):
    def test_bump_rules(self):
        self.assertEqual(version.next_version("0.2.0"), "0.2.1")
        self.assertEqual(version.next_version("1.2.9", "minor"), "1.3.0")
        self.assertEqual(version.next_version("1.2.9", "major"), "2.0.0")

    def test_invalid_versions_and_mismatched_tag(self):
        for value in ["v0.2.0", "01.2.0", "1.2", "$(echo bad)", "1.2.3-beta"]:
            with self.assertRaises(ValueError):
                version.next_version(value)
        with self.assertRaises(ValueError):
            version.validate_tag("0.2.0", "v0.2.1")
        version.validate_tag("0.2.0", "v0.2.0")

    def test_metadata_and_changelog_advance_together(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Resources").mkdir()
            path = root / "Resources/Info.plist"
            path.write_bytes(plistlib.dumps({"CFBundleShortVersionString": "0.2.0", "CFBundleVersion": "2"}))
            (root / "CHANGELOG.md").write_text("# Changelog\n\n## [Unreleased]\n\n- Permission fix.\n\n## [0.2.0]\n\n- First app.\n")
            self.assertEqual(version.bump(root, notes="Additional notes."), "0.2.1")
            self.assertEqual(version.read_metadata(root)["CFBundleVersion"], "3")
            text = (root / "CHANGELOG.md").read_text()
            self.assertIn("- Permission fix.", text)
            self.assertIn("Additional notes.", text)
            self.assertIn("## [0.2.0]", text)
            self.assertEqual(text.count("## [Unreleased]"), 1)
            self.assertEqual(version.bump(root), "0.2.2")
            self.assertEqual((root / "CHANGELOG.md").read_text().count("- Permission fix."), 1)


if __name__ == "__main__":
    unittest.main()
