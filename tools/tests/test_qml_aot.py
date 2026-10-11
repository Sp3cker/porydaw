import json
import tempfile
import unittest
from pathlib import Path

from porydaw_dev.qml_aot import Baseline, analyze, growth, read_baseline


class AotTests(unittest.TestCase):
    def fixture(self, folder, qml):
        root = Path(folder)
        source = root / "src/ui/Editor.qml"
        source.parent.mkdir(parents=True)
        source.write_text(qml, encoding="utf-8")
        stats = root / "stats"
        stats.mkdir()
        data = {
            "modules": [
                {
                    "moduleFiles": [
                        {
                            "filePath": "src/ui/Editor.qml",
                            "entries": [
                                {"codegenResult": 0},
                                {"codegenResult": 1, "message": "dynamic access"},
                            ],
                        }
                    ]
                }
            ]
        }
        (stats / "module_app.aotstats").write_text(json.dumps(data), encoding="utf-8")
        return root, stats, data

    def test_only_module_production_stats_count_and_comments_do_not_create_guards(self):
        qml = """pragma ComponentBehavior: Bound
Item {
    // property var fake; document.revision;
    property string hint: "property var fake; document.revision;"
    property var real: null
    function value() {
        document.revision;
        const unused = document.otherRevision;
        const used = document.revision;
        return used;
    }
}
"""
        with tempfile.TemporaryDirectory() as folder:
            root, stats, data = self.fixture(folder, qml)
            (stats / "all.aotstats").write_text(json.dumps(data), encoding="utf-8")
            report = analyze(root, stats)
            self.assertEqual((report.current.total, report.current.rejected), (2, 1))
            self.assertEqual(report.current.property_var_count, 1)
            self.assertEqual(
                report.revision_sites, ["src/ui/Editor.qml:7", "src/ui/Editor.qml:8"]
            )
            self.assertEqual(report.current.pragma_allowlist, [])
            self.assertEqual(report.banned, [])

    def test_duplicate_or_invalid_stats_cannot_hide_codegen_failure(self):
        with tempfile.TemporaryDirectory() as folder:
            root, stats, data = self.fixture(
                folder, "pragma ComponentBehavior: Bound\nItem {}"
            )
            second = stats / "module_duplicate.aotstats"
            second.write_text(json.dumps(data), encoding="utf-8")
            with self.assertRaises(RuntimeError):
                analyze(root, stats)
            second.unlink()
            data["modules"][0]["moduleFiles"][0]["entries"][0]["codegenResult"] = False
            (stats / "module_app.aotstats").write_text(
                json.dumps(data), encoding="utf-8"
            )
            with self.assertRaises(RuntimeError):
                analyze(root, stats)

    def test_javascript_file_and_live_import_are_banned_but_comments_are_not(self):
        with tempfile.TemporaryDirectory() as folder:
            root, stats, _ = self.fixture(
                folder,
                """pragma ComponentBehavior: Bound
// import "ignored.js" as Ignored
import "helper.js" as Helper
Item {}
""",
            )
            (root / "src/ui/helper.js").write_text(
                "function value() { return 1; }", encoding="utf-8"
            )
            self.assertEqual(
                set(analyze(root, stats).banned),
                {
                    "JavaScript file: src/ui/helper.js",
                    "JavaScript import: src/ui/Editor.qml",
                },
            )

    def test_global_improvement_cannot_hide_per_file_or_source_regression(self):
        baseline = Baseline(10, 100, {"old.qml": 10, "new.qml": 0}, 1, 1, ["old.qml"])
        current = Baseline(2, 110, {"old.qml": 0, "new.qml": 2}, 2, 2, ["new.qml"])
        failures = growth(current, baseline)
        self.assertEqual(len(failures), 4)
        self.assertTrue(any("new.qml: rejected" in failure for failure in failures))
        self.assertTrue(any("property var" in failure for failure in failures))
        self.assertTrue(any("revision reads" in failure for failure in failures))
        self.assertTrue(
            any("new.qml: missing pragma" in failure for failure in failures)
        )
        self.assertEqual(growth(Baseline(0, 120, {}, 0, 0, []), baseline), [])

    def test_invalid_numeric_budget_is_not_a_permissive_baseline(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "baseline.json"
            for value in (-1, True, 1.5, 2**53, "100"):
                with self.subTest(value=value):
                    data = Baseline(1, 10, {"Editor.qml": 1}, 0, 0, []).json()
                    data["rejected"] = value
                    path.write_text(json.dumps(data), encoding="utf-8")
                    with self.assertRaises(RuntimeError):
                        read_baseline(path)
