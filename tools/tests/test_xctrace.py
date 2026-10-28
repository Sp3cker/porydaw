import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from porydaw_dev.xctrace import compare, export, inline, summarize


class ExportTests(unittest.TestCase):
    def test_split_utf8_refs_share_identity_and_rows_detach(self):
        parser = export.Parser({"row", "node"})
        document = '<root><node><row><binary id="b" name="café"/></row><row><binary ref="b"/></row></node></root>'.encode()
        items = []
        for byte in document:
            items.extend(parser.feed(bytes([byte])))
        items.extend(parser.feed(b"", final=True))
        self.assertIs(items[0].child("binary"), items[1].child("binary"))
        self.assertEqual(items[0].child("binary").attrs["name"], "café")
        self.assertEqual(items[2].children, [])
        with self.assertRaisesRegex(ValueError, "unresolved ref"):
            list(
                export.Parser({"row"}).feed(
                    b'<root><row><binary ref="missing"/></row></root>', final=True
                )
            )

    def test_profile_decodes_both_weights_and_main_thread(self):
        parser = export.Parser({"row"})
        xml = b'<root><row><sample-time>2</sample-time><weight>4</weight><thread fmt="MAIN THREAD (0x1)"/><process fmt="app (123)"/><tagged-backtrace id="t"><frame name="leaf" addr="0x10"><binary name="app"/></frame></tagged-backtrace></row><row><sample-time>3</sample-time><cycle-weight>7</cycle-weight><thread fmt="worker"/><tagged-backtrace ref="t"/></row><row><sample-time>NaN</sample-time><weight>99</weight></row></root>'
        source = (row for row in parser.feed(xml, final=True))
        samples = list(export.samples(source))
        self.assertEqual([sample.weight for sample in samples], [4, 7])
        self.assertTrue(samples[0].main)
        self.assertEqual(samples[0].process, "app")
        self.assertIs(samples[0].stack, samples[1].stack)
        self.assertEqual(samples[0].stack[0].addr, 16)

    @unittest.skipUnless(os.name == "posix", "native process fixture")
    def test_closing_export_reaps_its_producer(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            script = root / "xcrun"
            ready = root / "pid"
            script.write_text(
                f"#!{sys.executable}\nimport os,sys,time\nfrom pathlib import Path\nPath({str(ready)!r}).write_text(str(os.getpid()))\nsys.stdout.write('<root><row>ready</row>')\nsys.stdout.flush()\ntime.sleep(5)\n"
            )
            script.chmod(0o755)
            with patch.dict(
                os.environ, {"PATH": f"{root}{os.pathsep}{os.environ['PATH']}"}
            ):
                source = export.elements(["xctrace", "export"], {"row"})
                try:
                    self.assertEqual(next(source).text, "ready")
                finally:
                    source.close()
            with self.assertRaises(ProcessLookupError):
                os.kill(int(ready.read_text()), 0)


class AggregationTests(unittest.TestCase):
    def test_recursion_counts_inclusive_once_and_self_only_leaf(self):
        frames = (
            export.Frame("leaf", "app", 1),
            export.Frame("leaf", "app", 2),
            export.Frame("caller", "lib", 3),
        )
        sample = export.Sample(0, "main thread", True, "app", 8, frames)
        result = summarize.profile([sample], "app")
        self.assertEqual(result["total"], 8)
        self.assertEqual(
            result["symbols"],
            [{"sym": "leaf", "binary": "app", "self": 8, "incl": 8, "samples": 1}],
        )
        self.assertEqual(result["binaries"], [{"name": "app", "self": 8, "pct": 100}])

    def test_signposts_pair_before_filter_with_lifo_and_ids(self):
        run = export.Run(1, "signpost", 100, 110, 10, ("os-signpost",))

        def event(time, kind, ident="one"):
            return export.Event(time * 1e9, kind, "s", "c", "name", ident)

        result = summarize.signpost(
            [
                event(1, "Begin"),
                event(2, "Begin"),
                event(3, "End"),
                event(4, "End"),
                event(5, "End", "different"),
                event(2.5, "Event"),
                event(2.2, "Begin", "open"),
            ],
            run,
            summarize.Interval(102, 103, "flag"),
        )
        self.assertEqual(result["groups"][0]["totalMs"], 1000)
        self.assertEqual(result["groups"][0]["count"], 1)
        self.assertEqual(
            (result["unpairedBegins"], result["unpairedEnds"], result["events"]),
            (1, 0, 1),
        )

    def test_sidecar_precedence_and_malformed_existing_input(self):
        with tempfile.TemporaryDirectory() as folder:
            trace = str(Path(folder) / "a.trace")
            Path(trace + ".json").write_text(
                json.dumps({"startEpoch": 10, "endEpoch": 20})
            )
            Path(trace[:-6] + ".json").write_text(json.dumps({"start": 30, "end": 40}))
            self.assertEqual(
                summarize.resolve_interval(trace), summarize.Interval(10, 20, "sidecar")
            )
            self.assertEqual(
                summarize.resolve_interval(trace, (50, 60)),
                summarize.Interval(50, 60, "flag"),
            )
            Path(trace + ".json").write_text('{"start": NaN, "end": 20}')
            with self.assertRaises(ValueError):
                summarize.resolve_interval(trace)

    def test_comparison_interval_preserves_fractional_epochs_and_integer_flags(self):
        for start, end, source, expected in (
            (
                1760000000.123,
                1760000004.5,
                "sidecar",
                "1760000000.123,1760000004.5 (sidecar)",
            ),
            (100.0, 200.0, "flag", "100,200 (flag)"),
        ):
            endpoint = compare._endpoint(
                {
                    "trace": "a.trace",
                    "interval": {"start": start, "end": end, "source": source},
                }
            )
            self.assertEqual(endpoint["interval"], expected)

    def test_zero_baselines_and_mixed_units(self):
        self.assertEqual(compare.reduction(0, 0), 0)
        self.assertIsNone(compare.reduction(0, 5))
        self.assertEqual(compare.reduction(10, 5), 50)
        with self.assertRaisesRegex(ValueError, "mismatch"):
            compare.pair({"schema": "cpu-profile"}, {"schema": "time-profile"})

    def test_metric_prefers_exact_within_category_and_thread_first(self):
        summary = {
            "threads": [
                {"name": "main worker", "weight": 1},
                {"name": "MAIN", "weight": 8},
            ],
            "binaries": [{"name": "main", "self": 9}],
            "symbols": [{"sym": "tail beyond top", "binary": "app", "self": 7}],
        }
        self.assertEqual(compare.metric_weight(summary, "main"), ('thread "MAIN"', 8))
        self.assertEqual(
            compare.metric_weight(summary, "tail"),
            ('symbol "tail beyond top" [app]', 7),
        )

    def test_inline_local_outside_recursion_and_call_sites(self):
        frames = (
            export.Frame("external", "lib", None),
            export.Frame("leaf", "app", 1),
            export.Frame("leaf", "app", 2),
            export.Frame("caller", "app", 3),
            export.Frame("leaf", "app", 4),
            export.Frame("caller", "app", 5),
        )
        sample = export.Sample(0, "worker", False, "app", 10, frames)
        result = inline.aggregate([sample], "app")
        edge = next(
            call
            for call in result["calls"]
            if call["caller"] == "caller" and call["callee"] == "leaf"
        )
        self.assertEqual(
            (edge["local"], edge["outside"], edge["incl"], edge["sites"]),
            (10, 10, 10, 2),
        )
        self.assertEqual(inline.call_kind("outlined copy of Widget"), "copy")
        self.assertEqual(inline.call_kind("partial apply for closure #1"), "closure")
