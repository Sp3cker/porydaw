import tempfile
import unittest
from pathlib import Path

from porydaw_dev import qt


class QtSelectionTests(unittest.TestCase):
    def test_warm_setup_keeps_configured_kit_and_explicit_request_selects_new_kit(self):
        with tempfile.TemporaryDirectory() as temp:
            repo = Path(temp)
            _, _, kit = qt.installation()

            def installed(version):
                prefix = qt.install_root(repo) / version / kit
                cmake = prefix / "lib/cmake/Qt6"
                cmake.mkdir(parents=True)
                (cmake / "Qt6Config.cmake").write_text("# installed kit\n")
                return prefix

            old = installed("6.11.9")
            new = installed("6.11.10")
            installed("6.10.20")
            incomplete = qt.install_root(repo) / "6.11.99" / kit
            incomplete.mkdir(parents=True)
            self.assertEqual(qt.local_prefix(repo), new)
            self.assertEqual(
                qt.local_prefix(repo, configured_dir=str(old / "lib/cmake/Qt6")), old
            )
            self.assertEqual(
                qt.local_prefix(repo, "6.11.10", str(old / "lib/cmake/Qt6")), new
            )
            self.assertIsNone(qt.local_prefix(repo, "6.11.8"))

    def test_no_installation_is_not_mistaken_for_a_configured_kit(self):
        with tempfile.TemporaryDirectory() as temp:
            self.assertIsNone(
                qt.local_prefix(Path(temp), configured_dir="/unrelated/Qt6")
            )
