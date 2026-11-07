import contextlib
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from porydaw_dev.format import run_staged


class StagedFormatTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(self.enterContext(tempfile.TemporaryDirectory())).resolve()
        environment = {
            key: value
            for key, value in os.environ.items()
            if not key.startswith("GIT_")
        }
        environment.update(GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1")
        self.enterContext(mock.patch.dict(os.environ, environment, clear=True))
        self.enterContext(contextlib.chdir(self.root))
        self.git("init", "--quiet")
        version = Path(__file__).resolve().parents[2] / ".swift-version"
        self.stage(".swift-version", version.read_text(encoding="utf-8"))
        self.commit()

    def git(self, *args):
        return subprocess.run(["git", *args], capture_output=True, check=True).stdout

    def commit(self):
        self.git(
            "-c",
            "user.name=Format check",
            "-c",
            "user.email=format@example.invalid",
            "commit",
            "--allow-empty",
            "--quiet",
            "-m",
            "fixture",
        )

    def stage(self, name, contents):
        path = self.root / name
        path.write_text(contents)
        self.git("add", "--", name)
        return path

    def languages(self):
        yield "py", "value = 1\n", "value=1\n"
        if shutil.which("swift"):
            yield "swift", "let value = 1\n", "let value=1\n"

    def test_formatted_index_ignores_unstaged_and_untracked_sources(self):
        for suffix, good, bad in self.languages():
            with self.subTest(language=suffix):
                path = self.stage(f"staged space Ω.{suffix}", good)
                path.write_text(bad)
                untracked = self.root / f"untracked.{suffix}"
                untracked.write_text(bad)
                index = self.git("ls-files", "--stage", "-z")
                self.assertEqual(run_staged(), 0)
                self.assertEqual(path.read_text(), bad)
                self.assertEqual(untracked.read_text(), bad)
                self.assertEqual(self.git("ls-files", "--stage", "-z"), index)

    def test_unformatted_index_is_rejected_even_when_working_copy_is_formatted(self):
        for suffix, good, bad in self.languages():
            with self.subTest(language=suffix):
                path = self.stage(f"staged.{suffix}", bad)
                path.write_text(good)
                index = self.git("ls-files", "--stage", "-z")
                self.assertEqual(run_staged(), 1)
                self.assertEqual(path.read_text(), good)
                self.assertEqual(self.git("ls-files", "--stage", "-z"), index)
                self.git("reset", "--quiet")

    def test_indexed_python_configuration_ignores_invalid_working_configuration(self):
        config = self.stage("pyproject.toml", "[tool.ruff]\nline-length = 88\n")
        config.write_text("not valid toml !!!\n")
        self.stage("staged.py", "value = 1\n")
        self.assertEqual(run_staged(), 0)
        self.assertEqual(config.read_text(), "not valid toml !!!\n")

    @unittest.skipUnless(shutil.which("swift"), "Swift formatter unavailable")
    def test_indexed_swift_configuration_and_changed_hunks_are_used(self):
        config = self.stage(".swift-format", '{"indentation": {"spaces": 2}}\n')
        path = self.stage(
            "staged.swift", "let untouched=1\nstruct Value {\n  let number = 1\n}\n"
        )
        self.commit()
        path.write_text("let untouched=1\nstruct Value {\n  let number = 2\n}\n")
        self.git("add", "--", "staged.swift")
        config.write_text("not valid json !!!\n")
        self.assertEqual(run_staged(), 0)
        self.assertEqual(config.read_text(), "not valid json !!!\n")
        self.assertTrue(path.read_text().startswith("let untouched=1\n"))

    def test_staged_deletion_does_not_read_missing_source(self):
        self.stage("deleted.py", "value=1\n")
        self.commit()
        self.git("rm", "deleted.py")
        self.assertEqual(run_staged(), 0)
