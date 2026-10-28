import json
import os
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from porydaw_dev.checks import Options, Processes, UsageError, parse_manifest, select


def entry(name="core", **changes):
    return {
        "name": name,
        "argv": [],
        "binary": "checks",
        "windowing": "offscreen",
        "framework": "qt-test",
        "optIn": False,
        "scratchKind": "unused",
        "fixtureRootKind": "none",
        "fixtureFiles": [],
        **changes,
    }


class ManifestTests(unittest.TestCase):
    def test_invalid_classification_cannot_silently_skip_a_check(self):
        for change in (
            {"windowing": "unknown"},
            {"framework": "unknown"},
            {"binary": "unknown"},
            {"scratchKind": "unknown"},
            {"fixtureRootKind": "unknown"},
            {"optIn": 1},
            {"platforms": ["unknown"]},
            {"argv": [1]},
            {"environment": {"QT_QPA_PLATFORM": "offscreen"}},
        ):
            with self.subTest(change=change), self.assertRaises(UsageError):
                parse_manifest({"checks": [entry(**change)]})
        with self.assertRaises(UsageError):
            parse_manifest({"checks": [entry(), entry()]})

    def test_fixture_paths_cannot_escape_scratch(self):
        for filename in (
            "",
            "/tmp/song.s",
            "../song.s",
            "sub/../../song.s",
            "C:\\song.s",
            "\\song.s",
            "sub\\..\\song.s",
        ):
            with self.subTest(filename=filename), self.assertRaises(UsageError):
                parse_manifest(
                    {
                        "checks": [
                            entry(
                                scratchKind="existing-directory",
                                fixtureRootKind="decomp-project",
                                fixtureFiles=[filename],
                            )
                        ]
                    }
                )
        for change in ({"scratchKind": "unused"}, {"fixtureRootKind": "none"}):
            with self.subTest(change=change), self.assertRaises(UsageError):
                parse_manifest(
                    {
                        "checks": [
                            entry(
                                **{
                                    "scratchKind": "existing-directory",
                                    "fixtureRootKind": "decomp-project",
                                    "fixtureFiles": ["song.s"],
                                    **change,
                                }
                            )
                        ]
                    }
                )

    def test_selection_respects_platform_opt_in_and_window_class(self):
        checks = parse_manifest(
            {
                "checks": [
                    entry(),
                    entry("dialog", windowing="window-system"),
                    entry("manual", optIn=True),
                    entry("linux-only", platforms=["linux"]),
                    entry("visual-roll"),
                ]
            }
        )
        self.assertEqual(
            {check.name for check in select(checks, Options(), "macos", False)},
            {"core", "dialog"},
        )
        self.assertEqual(
            {check.name for check in select(checks, Options(all=True), "macos", False)},
            {"core", "dialog", "manual", "visual-roll"},
        )
        self.assertEqual(
            {
                check.name
                for check in select(checks, Options(no_windowing=True), "macos", True)
            },
            {"core", "visual-roll"},
        )
        self.assertEqual(
            [
                check.name
                for check in select(
                    checks, Options(filters=("manual",)), "macos", False
                )
            ],
            ["manual"],
        )
        self.assertEqual(
            {
                check.name
                for check in select(
                    checks,
                    Options(filters=("core", "dialog"), exclusions=("dialog",)),
                    "macos",
                    False,
                )
            },
            {"core"},
        )

    def test_invalid_or_empty_selection_is_not_success(self):
        checks = parse_manifest(
            {"checks": [entry(), entry("linux-only", platforms=["linux"])]}
        )
        for options in (
            Options(filters=("missing",)),
            Options(exclusions=("typo",)),
            Options(filters=("core",), exclusions=("core",)),
            Options(filters=("linux-only",)),
        ):
            with self.subTest(options=options), self.assertRaises(UsageError):
                select(checks, options, "macos", True)
        with self.assertRaises(UsageError):
            select([], Options(), "macos", True)

    def test_qt_payload_requires_one_qt_consumer(self):
        checks = parse_manifest(
            {"checks": [entry(), entry("process", framework="process")]}
        )
        for options in (
            Options(qt=("--help",)),
            Options(filters=("process",), qt=("--help",)),
            Options(filters=("core",), qt=()),
        ):
            with self.subTest(options=options), self.assertRaises(UsageError):
                select(checks, options, "macos", True)
        self.assertEqual(
            [
                check.name
                for check in select(
                    checks, Options(filters=("core",), qt=("--help",)), "macos", True
                )
            ],
            ["core"],
        )


class ProcessTests(unittest.TestCase):
    @unittest.skipUnless(os.name == "posix", "POSIX signal escalation")
    def test_timeout_preserves_diagnostics_and_reaps_sigterm_ignorer(self):
        with tempfile.TemporaryDirectory() as folder:
            result = Processes(timeout=0.5, grace=0.05).run(
                Path(sys.executable),
                [
                    "-u",
                    "-c",
                    (
                        "import os, signal, sys, time; signal.signal(signal.SIGTERM, signal.SIG_IGN); "
                        "print(os.getpid()); print('fatal diagnostic before timeout', file=sys.stderr); time.sleep(3)"
                    ),
                ],
                dict(os.environ),
                Path(folder) / "output",
            )
            self.assertTrue(result.timed_out)
            self.assertEqual(result.code, -signal.SIGKILL)
            self.assertIn("fatal diagnostic before timeout", result.output)
            pid = int(result.output.splitlines()[0])
            with self.assertRaises(ProcessLookupError):
                os.kill(pid, 0)

    def test_cancel_stops_active_and_prevents_queued_children(self):
        with (
            tempfile.TemporaryDirectory() as folder,
            ThreadPoolExecutor(max_workers=1) as pool,
        ):
            root = Path(folder)
            ready, finished, queued = root / "ready", root / "finished", root / "queued"
            processes = Processes(timeout=5, grace=0.1)
            code = f"from pathlib import Path; import time; Path({str(ready)!r}).touch(); time.sleep(3); Path({str(finished)!r}).touch()"
            future = pool.submit(
                processes.run,
                Path(sys.executable),
                ["-c", code],
                dict(os.environ),
                root / "active-output",
            )
            deadline = time.monotonic() + 2
            while not ready.exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            try:
                self.assertTrue(
                    ready.exists(), "child did not reach the cancellation boundary"
                )
            finally:
                processes.cancel()
            result = future.result(timeout=2)
            self.assertNotEqual(result.code, 0)
            self.assertFalse(result.timed_out)
            self.assertFalse(finished.exists())
            result = processes.run(
                Path(sys.executable),
                ["-c", f"from pathlib import Path; Path({str(queued)!r}).touch()"],
                dict(os.environ),
                root / "queued-output",
            )
            self.assertEqual(result.code, 130)
            self.assertFalse(queued.exists())

    @unittest.skipUnless(os.name == "posix", "POSIX runner interruption")
    def test_sigterm_reaps_active_check_and_removes_its_scratch(self):
        with tempfile.TemporaryDirectory(prefix="porydaw-signal-regression-") as folder:
            root = Path(folder)
            ready, binary = root / "ready.json", root / "slow-check"
            manifest = json.dumps(
                {
                    "checks": [
                        entry(
                            argv=["{scratch}", str(ready)],
                            framework="process",
                            scratchKind="existing-directory",
                        )
                    ]
                }
            )
            binary.write_text(
                f"""#!{sys.executable}
import json, os, sys, time
from pathlib import Path
if sys.argv[1:] == ["--manifest"]:
    print({manifest!r})
    raise SystemExit
scratch, ready = map(Path, sys.argv[1:])
temporary = ready.with_suffix(".tmp")
temporary.write_text(json.dumps({{"pid": os.getpid(), "scratch": str(scratch)}}))
temporary.replace(ready)
time.sleep(5)
""",
                encoding="utf-8",
            )
            binary.chmod(0o755)
            (root / "mid2agb").touch()
            parent = subprocess.Popen(
                [
                    sys.executable,
                    "-c",
                    "from porydaw_dev.cli import main; raise SystemExit(main())",
                    "checks:run",
                    str(binary),
                ],
                cwd=Path(__file__).resolve().parents[2],
                env={**os.environ, "TMPDIR": folder},
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            pid = None
            try:
                deadline = time.monotonic() + 3
                while not ready.exists() and time.monotonic() < deadline:
                    time.sleep(0.01)
                self.assertTrue(
                    ready.exists(), "check did not reach interruption boundary"
                )
                state = json.loads(ready.read_text())
                pid = state["pid"]
                scratch = Path(state["scratch"])
                parent.send_signal(signal.SIGTERM)
                parent.communicate(timeout=5)
                self.assertEqual(parent.returncode, 130)
                self.assertFalse(scratch.parent.exists())
                with self.assertRaises(ProcessLookupError):
                    os.kill(pid, 0)
                pid = None
            finally:
                if pid is not None:
                    try:
                        os.killpg(pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                if parent.poll() is None:
                    parent.kill()
                parent.communicate(timeout=5)
