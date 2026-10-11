import tempfile
import unittest
from pathlib import Path

from porydaw_dev.bridge_surface import (
    Source,
    analyze,
    reachability,
    signal_checks,
    swift_model,
)


class BridgeTests(unittest.TestCase):
    def model(self, text):
        sources = [Source.from_text("src/swift/Owner.swift", text)]
        findings = []
        classes = swift_model(sources, findings)
        return sources, classes, findings

    def test_comments_raw_strings_and_interpolation_cannot_forge_members_or_emission(
        self,
    ):
        text = r'''@QtBridgeable
final class Editor {
    /* outer { /* @QtTracked var fake: String */ } */
    var title: String = #"saved() \#(call("}"))"#
    var help: String = #"""
      } @QtTracked var forged: String
      \#(call("{"))
    """#
    @QtSignal func saved() {}
    func nested() { let text = "saved()" }
}
'''
        sources, classes, findings = self.model(text)
        self.assertEqual(set(classes["Editor"].members), {"title", "help"})
        self.assertFalse(classes["Editor"].signals["saved"].emitted)
        self.assertEqual(findings, [])
        signal_checks([], sources, classes, findings)
        self.assertEqual(
            {finding.key() for finding in findings},
            {"SIGNAL_NEVER_OBSERVED src/swift/Owner.swift Editor.saved"},
        )

    def test_member_exposure_and_optional_return_rules(self):
        _, classes, findings = self.model("""@QtBridgeable
final class Editor {
    var inferred = 1
    var document: Document
    @QtTracked var title: String = ""
    @QtTracked var session: Session
    @QtIgnored private var native: Native
    var computed: String { "value" }
    var observed: Int = 0 { didSet {} }
    public func bad() -> String? { nil }
    public func good() -> Optional<String> { nil }
}
""")
        self.assertEqual(
            {(finding.check, finding.detail) for finding in findings},
            {
                ("UNANNOTATED_MEMBER", "inferred"),
                ("UNTRACKED_CUSTOM_TYPE", "document"),
                ("REDUNDANT_TRACKED", "title"),
                ("REDUNDANT_IGNORED", "native"),
                ("SUGAR_OPTIONAL_RETURN", "bad"),
            },
        )
        self.assertEqual(
            set(classes["Editor"].members), {"inferred", "document", "title", "session"}
        )

    def test_connections_resolve_enclosing_owner_not_sibling_typed_property(self):
        sources, classes, findings = self.model("""@QtBridgeable
class Editor {
    var title: String = ""
}
@QtBridgeable
class Other {
    @QtSignal func ghost() {}
}
var instantiableTypes: [Any.Type] = [Editor.self, Other.self]
""")
        qml = Source.from_text(
            "src/ui/Main.qml",
            """Item {
    id: root
    property Editor editor
    Item {
        id: sibling
        property Other editor
    }
    Connections {
        target: root.editor
        function onTitleChanged() {}
        function onGhost() {}
    }
}
""",
        )
        signal_checks([qml], sources, classes, findings)
        self.assertEqual(
            {finding.key() for finding in findings},
            {"HANDLER_NEVER_EMITTED src/ui/Main.qml Editor.ghost"},
        )

    def test_real_emit_and_connections_form_an_observed_signal(self):
        sources, classes, findings = self.model(r"""@QtBridgeable
class Editor {
    @QtSignal func saved() {}
    func save() { emitSignal(for: \.saved) }
    @QtSignal func archived() {}
    func archive() { emitSignal(for: \Editor.archived) }
}
var instantiableTypes: [Any.Type] = [Editor.self]
""")
        qml = Source.from_text(
            "src/ui/Main.qml",
            """Editor {
    id: editor
    Connections {
        target: editor
        function onSaved() {}
        function onArchived() {}
    }
}
""",
        )
        signal_checks([qml], sources, classes, findings)
        self.assertTrue(classes["Editor"].signals["saved"].emitted)
        self.assertTrue(classes["Editor"].signals["archived"].emitted)
        self.assertEqual(findings, [])

    def test_reachability_follows_local_components_literals_and_native_roots(self):
        cmake = """set(shell_qml src/ui/Main.qml)
qt_add_qml_module(porydaw_app
    QML_FILES
        src/ui/Main.qml
)
"""
        swift = [
            Source.from_text(
                "src/swift/Shell.swift",
                """var qmlFileName = "Main"
let path = QmlEngineAccess.moduleResourcePrefix + "src/ui/Dynamic.qml"
// QmlEngineAccess.moduleResourcePrefix + "src/ui/Ghost.qml"
""",
            )
        ]
        qml = [
            Source.from_text("src/ui/" + name + ".qml", text)
            for name, text in {
                "Main": 'Item { Child {} Loader { source: "Extra.qml" } /* Ghost {} */ }',
                "Child": "Item { Grandchild {} }",
                "Grandchild": "Item {}",
                "Extra": "Item {}",
                "Dynamic": "Item {}",
                "Dead": "Item {}",
                "Ghost": "Item {}",
            }.items()
        ]
        qml.append(Source.from_text("src/checks/Harness.qml", "Item {}"))
        findings = []
        reachability(qml, swift, cmake, findings)
        self.assertEqual(
            {finding.path for finding in findings},
            {"src/ui/Dead.qml", "src/ui/Ghost.qml"},
        )

    def test_missing_scan_root_cannot_pass_an_empty_baseline(self):
        for missing in ("src/swift", "src/checks", "src/ui"):
            with self.subTest(missing=missing), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                for directory in ("src/swift", "src/checks", "src/ui"):
                    if directory != missing:
                        (root / directory).mkdir(parents=True)
                with self.assertRaises(RuntimeError):
                    analyze(root)
