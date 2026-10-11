import contextlib
import io
import os
import shlex
import sys
import tempfile
import time
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from porydaw_dev import bench
from porydaw_dev.bench import distribution, measure


class BenchmarkTests(unittest.TestCase):
    def test_inclusive_quartiles_and_one_sample(self):
        self.assertEqual(distribution([12]), (12, 12, 12))
        self.assertEqual(distribution([40, 10, 30, 20]), (17.5, 25, 32.5))

    @unittest.skipUnless(os.name == "posix", "executable process fixtures")
    def test_partial_final_marker_is_received_before_exit(self):
        with tempfile.TemporaryDirectory() as folder:
            script = Path(folder) / "marker-app"
            script.write_text(
                f"#!{sys.executable}\nimport sys\nsys.stderr.write('PORYDAW_STARTUP_TRACE first-frame')\nsys.stderr.flush()\n"
            )
            script.chmod(0o755)
            read_stderr = bench._read_stderr

            def delayed_reader(stream, events):
                time.sleep(0.15)
                read_stderr(stream, events)

            options = SimpleNamespace(
                project=None, song=None, timeout_ms=1000, until="first-frame"
            )
            with patch.object(bench, "_read_stderr", delayed_reader):
                result = measure(script, options, 1)
            self.assertIsNotNone(result.ms)
            self.assertLess(result.ms, options.timeout_ms)
            self.assertEqual(result.stages["first-frame"], result.ms)

    @unittest.skipUnless(os.name == "posix", "POSIX escalation")
    def test_deadline_reaps_term_ignoring_app(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            script = root / "hang-app"
            pid_file = root / "pid"
            script.write_text(
                f"#!/bin/sh\ntrap '' TERM\nprintf '%s' $$ > {shlex.quote(str(pid_file))}\nsleep 5\n"
            )
            script.chmod(0o755)
            options = SimpleNamespace(
                project=None, song=None, timeout_ms=500, until="first-frame"
            )
            started = time.monotonic()
            with contextlib.redirect_stderr(io.StringIO()):
                result = measure(script, options, 1)
            self.assertIsNone(result.ms)
            self.assertTrue(result.message.startswith("TIMEOUT:"))
            self.assertLess(time.monotonic() - started, 2)
            with self.assertRaises(ProcessLookupError):
                os.kill(int(pid_file.read_text()), 0)

    @unittest.skipUnless(os.name == "posix", "owned group cleanup")
    def test_frame_cleanup_closes_descendant_held_stderr(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            script = root / "descendant-app"
            pid_file = root / "descendant-pid"
            script.write_text(
                f"#!{sys.executable}\nimport subprocess,sys\nfrom pathlib import Path\nchild = subprocess.Popen([sys.executable,'-c','import time;time.sleep(5)'])\nPath({str(pid_file)!r}).write_text(str(child.pid))\nsys.stderr.write('PORYDAW_STARTUP_TRACE first-frame\\n')\nsys.stderr.flush()\n"
            )
            script.chmod(0o755)
            options = SimpleNamespace(
                project=None, song=None, timeout_ms=1000, until="first-frame"
            )
            started = time.monotonic()
            result = measure(script, options, 1)
            self.assertIsNotNone(result.ms)
            self.assertLess(time.monotonic() - started, 2)
            pid = int(pid_file.read_text())
            deadline = time.monotonic() + 1
            while time.monotonic() < deadline:
                try:
                    os.kill(pid, 0)
                except ProcessLookupError:
                    break
                time.sleep(0.01)
            else:
                # An orphan may remain a zombie until the host reaper collects it.
                import subprocess

                state = subprocess.run(
                    ["ps", "-p", str(pid), "-o", "stat="],
                    check=False,
                    capture_output=True,
                    text=True,
                ).stdout.strip()
                self.assertTrue(state.startswith("Z"), state)
