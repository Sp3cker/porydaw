import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from tools.gen_swift_compdb import CompileJob, index_command

SCRIPT = Path(__file__).resolve().parents[1] / "gen_swift_compdb.py"


class SwiftIndexTests(unittest.TestCase):
    def test_empty_graph_fails_without_marking_an_existing_index_fresh(self):
        with tempfile.TemporaryDirectory() as temp:
            build = Path(temp)
            ninja = shutil.which("ninja")
            if ninja is None:
                raise RuntimeError(
                    "test environment needs the project's Ninja dependency"
                )
            (build / "CMakeCache.txt").write_text(
                f"CMAKE_MAKE_PROGRAM:FILEPATH={ninja}\n"
            )
            (build / "build.ninja").write_text("build nothing: phony\n")
            compdb = build / "compile_commands.json"
            compdb.write_text('[{"file": "native.cpp", "command": "unchanged"}]\n')
            stamp = build / "indexstore/swiftc-stamp.txt"
            stamp.parent.mkdir()
            stamp.write_text("previous successful compiler\n")
            original_compdb = compdb.read_bytes()
            original_stamp = (stamp.read_bytes(), stamp.stat().st_mtime_ns)
            result = subprocess.run(
                [sys.executable, str(SCRIPT), str(build), "--index"],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("no Swift compile commands", result.stderr)
            self.assertIn(str(build / "build.ninja"), result.stderr)
            self.assertEqual(compdb.read_bytes(), original_compdb)
            self.assertEqual(
                (stamp.read_bytes(), stamp.stat().st_mtime_ns), original_stamp
            )

    def test_same_filename_in_two_modules_has_disjoint_scratch_outputs(self):
        with tempfile.TemporaryDirectory() as temp:
            build = Path(temp)
            outputs = []
            for name in ("First", "Second"):
                source = build / name / "Shared.swift"
                original = build / f"{name}-output.json"
                original.write_text(
                    json.dumps(
                        {str(source): {"object": str(build / name / "Shared.swift.o")}}
                    )
                )
                before = original.read_bytes()
                job = CompileJob(
                    build,
                    [
                        "swiftc",
                        "-module-name",
                        name,
                        "-c",
                        str(source),
                        "-emit-module-path",
                        str(build / f"{name}.swiftmodule"),
                        "-output-file-map",
                        str(original),
                    ],
                    (source,),
                )
                command = index_command(job, build / "indexstore")
                remapped = Path(command[command.index("-output-file-map") + 1])
                output = Path(json.loads(remapped.read_text())[str(source)]["object"])
                outputs.append(output)
                self.assertNotEqual(output, build / name / "Shared.swift.o")
                self.assertEqual(original.read_bytes(), before)
            self.assertNotEqual(outputs[0], outputs[1])
