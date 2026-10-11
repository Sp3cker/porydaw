import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from porydaw_dev import build, build_output, qt


class ConfigureReuseTests(unittest.TestCase):
    def test_windows_path_spellings_reuse_cache_but_compiler_change_requires_fresh_configure(
        self,
    ):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            (directory / "build.ninja").touch()
            cache = {
                "CMAKE_Swift_COMPILER": "C:/Users/Spencer/Swift/swiftc.exe",
                "PORYAAAA_DIR": "C:/src/poryaaaa",
                "Qt6_DIR": "C:/Qt/lib/cmake/Qt6",
                "CMAKE_BUILD_TYPE": "Release",
            }
            args = [
                r"-DCMAKE_Swift_COMPILER=C:\Users\Spencer\Swift\swiftc.exe",
                r"-DPORYAAAA_DIR=C:\src\poryaaaa",
                r"-DQt6_DIR:PATH=C:\Qt\lib\cmake\Qt6",
                "-DCMAKE_BUILD_TYPE=Release",
            ]
            with patch.object(build.sys, "platform", "win32"):
                self.assertEqual(
                    build.needs_configure(directory, cache, args), (False, False)
                )
                args[0] = (
                    r"-DCMAKE_Swift_COMPILER=C:\Users\Spencer\SwiftNext\swiftc.exe"
                )
                self.assertEqual(
                    build.needs_configure(directory, cache, args), (True, True)
                )

    def test_installed_local_kit_recovers_notfound_cache_then_reuses_configuration(
        self,
    ):
        with tempfile.TemporaryDirectory() as temp:
            repo = Path(temp)
            directory = repo / "build"
            directory.mkdir()
            (directory / "build.ninja").touch()
            _, _, kit = qt.installation()
            prefix = qt.install_root(repo) / "6.11.10" / kit
            (prefix / "lib/cmake/Qt6").mkdir(parents=True)
            (prefix / "lib/cmake/Qt6/Qt6Config.cmake").write_text("# installed\n")
            package = repo / "poryaaaa"
            cache = {
                "CMAKE_BUILD_TYPE": "Debug",
                "PORYDAW_ASAN": "OFF",
                "PORYDAW_BUILD_CHECKS": "OFF",
                "PORYAAAA_DIR": str(package),
                "Qt6_DIR": "Qt6_DIR-NOTFOUND",
            }
            with (
                patch.object(build.Path, "cwd", return_value=repo),
                patch.object(build, "swift_bin_dir", return_value=None),
            ):
                args = build.configure_args(
                    directory, "debug", package, False, cache, None
                )
                self.assertEqual(
                    build.needs_configure(directory, cache, args), (True, False)
                )
                cache["Qt6_DIR"] = str(prefix / "lib/cmake/Qt6")
                cache["CMAKE_PREFIX_PATH"] = str(prefix)
                args = build.configure_args(
                    directory, "debug", package, False, cache, None
                )
                self.assertEqual(
                    build.needs_configure(directory, cache, args), (False, False)
                )

    def test_fresh_compiler_configuration_retains_previously_selected_qt(self):
        with tempfile.TemporaryDirectory() as temp:
            repo = Path(temp)
            directory = repo / "build"
            directory.mkdir()
            (directory / "build.ninja").touch()
            package = repo / "poryaaaa"
            configured_qt = repo / "selected-qt/lib/cmake/Qt6"
            cache = {
                "CMAKE_BUILD_TYPE": "Debug",
                "PORYDAW_ASAN": "OFF",
                "PORYAAAA_DIR": str(package),
                "Qt6_DIR": str(configured_qt),
                "CMAKE_PREFIX_PATH": str(repo / "selected-qt"),
                "CMAKE_Swift_COMPILER": str(repo / "old-swift/swiftc"),
            }
            with patch.object(build, "swift_bin_dir", return_value=repo / "new-swift"):
                args = build.configure_args(
                    directory, "debug", package, None, cache, None
                )
            self.assertEqual(
                build.needs_configure(directory, cache, args), (True, True)
            )
            requested = {}
            for argument in args:
                if argument.startswith("-D"):
                    key, _, value = argument[2:].partition("=")
                    requested[key.split(":", 1)[0]] = value
            self.assertEqual(Path(requested["Qt6_DIR"]), configured_qt)
            self.assertEqual(Path(requested["CMAKE_PREFIX_PATH"]), repo / "selected-qt")


class SwiftInvalidationTests(unittest.TestCase):
    def test_flag_change_invalidates_only_affected_module_on_both_object_formats(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            module_a = [root / "A.o", root / "A.obj"]
            module_b = root / "B.o"

            def ninja(flags):
                (root / "build.ninja").write_text(
                    f"build A.o A.obj: Swift_COMPILER__A_Debug A.swift\n  FLAGS = {flags}\n"
                    "  INCLUDES = -Iheaders\n\nbuild B.o: Swift_COMPILER__B_Debug B.swift\n  FLAGS = -Onone\n"
                )

            ninja("-Onone")
            build.reconcile_swift_objects(root)
            for path in [*module_a, module_b]:
                path.write_bytes(b"compiled")
            self.assertFalse(build.reconcile_swift_objects(root))
            ninja("-O")
            self.assertTrue(build.reconcile_swift_objects(root))
            self.assertTrue(all(not path.exists() for path in module_a))
            self.assertEqual(module_b.read_bytes(), b"compiled")
            self.assertFalse(build.reconcile_swift_objects(root))

    def test_missing_stamp_does_not_trust_preexisting_objects(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "build.ninja").write_text(
                "build Old.o: Swift_COMPILER__Old_Debug Old.swift\n  FLAGS = -O\n"
            )
            (root / "Old.o").write_bytes(b"unknown flags")
            self.assertTrue(build.reconcile_swift_objects(root))
            self.assertFalse((root / "Old.o").exists())
            self.assertIsInstance(
                json.loads((root / ".porydaw-swift-commands.json").read_text()), dict
            )

    def test_corrupt_stamp_distrusts_objects_then_repairs_the_cache(self):
        for contents in (b"{", b"[]", b"null", b"\xff"):
            with self.subTest(contents=contents), tempfile.TemporaryDirectory() as temp:
                directory = Path(temp)
                (directory / "build.ninja").write_text(
                    "build A.o: Swift_COMPILER__A_Debug A.swift\n  FLAGS = -O\n",
                    encoding="utf-8",
                )
                stamp = directory / ".porydaw-swift-commands.json"
                stamp.write_bytes(contents)
                output = directory / "A.o"
                output.write_bytes(b"unknown flags")
                self.assertTrue(build.reconcile_swift_objects(directory))
                self.assertFalse(output.exists())
                output.write_bytes(b"current flags")
                self.assertFalse(build.reconcile_swift_objects(directory))
                self.assertEqual(output.read_bytes(), b"current flags")


class AttributionTests(unittest.TestCase):
    def test_history_is_excluded_and_only_shared_command_hashes_group_outputs(self):
        before = {"old.o": (0, 9000, "1", "old"), "changed.o": (10, 20, "1", "a")}
        after = {
            **before,
            "changed.o": (0, 300, "2", "swift"),
            "module.swiftmodule": (0, 300, "2", "swift"),
            "unrelated.o": (0, 300, "2", "cpp"),
        }
        edges = build.changed_edges(before, after)
        self.assertEqual(len(edges), 2)
        self.assertEqual(
            {tuple(outputs) for _, outputs in edges},
            {("changed.o", "module.swiftmodule"), ("unrelated.o",)},
        )
        self.assertEqual([duration for duration, _ in edges], [300, 300])
        self.assertEqual(build.changed_edges(after, after), [])


class OutputTests(unittest.TestCase):
    def test_source_error_wins_over_driver_failure_and_vendor_warnings_are_filtered(
        self,
    ):
        root = Path("/project")
        output = """[1/2] Compiling Swift
FAILED: A.o
swiftc -c A.swift
/project/src/A.swift:4:2: error: type mismatch
error: compile command failed with exit code 1
/project/src/B.swift:7: warning: useful project warning
/project/external/lib/B.swift:9: warning: vendor warning
ninja: build stopped: subcommand failed.
"""
        summary = build_output.summarize(output, root, root / "build/debug")
        self.assertEqual(summary.steps, 1)
        self.assertEqual(len(summary.failed_steps), 1)
        self.assertEqual(len(summary.errors), 1)
        self.assertIn("src/A.swift:4:2", summary.errors[0])
        self.assertEqual(len(summary.warnings), 1)
        self.assertIn("src/B.swift:7", summary.warnings[0])

    def test_bare_fatal_error_is_visible_instead_of_generic_driver_failure(self):
        summary = build_output.summarize(
            "[1/2] Compiling native\nFAILED: A.o\nclang++ -c A.cpp\n"
            "clang++: fatal error: missing SDK header\n"
            "error: compile command failed with exit code 1\n",
            Path("/project"),
            Path("/project/build"),
        )
        self.assertEqual(len(summary.errors), 1)
        self.assertIn("missing SDK header", summary.errors[0])

    def test_unrecognized_failure_is_not_silenced(self):
        summary = build_output.summarize(
            "[1/1] Custom command\nFAILED: result\nrun-tool\nlicense checkout denied\n",
            Path("/project"),
            Path("/project/build"),
        )
        self.assertTrue(
            any("license checkout denied" in error for error in summary.errors)
        )


class RootIsolationTests(unittest.TestCase):
    def test_foreign_checkout_cannot_be_built_with_this_worktrees_environment(self):
        repo = Path(__file__).resolve().parents[2]
        with tempfile.TemporaryDirectory() as temp:
            other = Path(temp)
            subprocess.run(["git", "init", "--quiet", str(other)], check=True)

            script = (
                repo
                / ".venv"
                / ("Scripts/dev.exe" if sys.platform == "win32" else "bin/dev")
            )
            result = subprocess.run(
                [str(script), "build:app"],
                cwd=other,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((other / "build").exists())
            self.assertIn("harness belongs to", result.stderr)
