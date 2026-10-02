import QtQuick
import QtTest
import PorydawApp
import EditorQmlCheck 1.0
import Porydaw.Ui
import "EditorDrawerLayoutSupport.js" as LayoutSupport
import "EditorDrawerVoiceSupport.js" as VoiceSupport

TestCase {
    id: testCase
    property alias bootstrap: drawerBootstrap
    property alias session: drawerSession
    property alias regularFont: drawerRegularFont
    property alias semiboldFont: drawerSemiboldFont
    property alias monoFont: drawerMonoFont

    name: "EditorDrawerLane"
    when: windowShown
    width: 900
    height: 700
    visible: true

    // DrawerSectionKind raw values (EditorDrawer.swift).
    readonly property int automationKind: 0
    readonly property int velocityKind: 1
    readonly property int voiceChangesKind: 2

    // The test-owned page item the bootstrap's test pages resolve to.
    readonly property url testPageUrl: Qt.resolvedUrl("DrawerTestPage.qml")

    readonly property bool containerPhase: bootstrap.lanePhase === "container"
    readonly property bool productionPhase: !testCase.containerPhase

    // The historical store: one category, seven keys.
    readonly property var drawerKeys: ["automationVisible", "automationHeight",
                                       "velocityVisible", "velocityHeight",
                                       "voiceChangesVisible", "voiceChangesHeight",
                                       "activePage"]
    readonly property string absentKey: "__absent__"

    property int spacePropagations: 0
    property int returnPropagations: 0
    property int leftPropagations: 0
    property bool windowSpaceProbeActive: false
    property int windowSpaceActivations: 0
    function polishWindow(item) { return waitForPolish(item.Window.window) }
    function automationTabSelected(item) { return item.Accessible.selected }

    function verifyToggleAccessibility(kind, name) {
        var control = toggle(kind)
        compare(control.Accessible.role, Accessible.Button, name + ": role")
        compare(control.Accessible.name, name, name + ": name")
        compare(control.Accessible.checkable, true, name + ": checkable")
        compare(control.Accessible.checked, section(kind).visible, name + ": checked")
        compare(control.Accessible.focusable, true, name + ": focusable")
    }

    function verifyGripAccessibility(kind, name) {
        var control = grip(kind)
        compare(control.Accessible.role, Accessible.Grip, name + ": role")
        compare(control.Accessible.name, name, name + ": name")
        compare(control.Accessible.description, "Use Up and Down to resize", name + ": description")
        compare(control.Accessible.focusable, true, name + ": focusable")
    }

    FontLoader {
        id: drawerRegularFont
        source: "qrc:/fonts/AtkinsonHyperlegibleNext-Regular.ttf"
    }
    FontLoader {
        id: drawerSemiboldFont
        source: "qrc:/fonts/AtkinsonHyperlegibleNext-SemiBold.ttf"
    }
    FontLoader {
        id: drawerMonoFont
        source: "qrc:/fonts/AtkinsonHyperlegibleMono-Regular.ttf"
    }

    Shortcut {
        sequence: "Space"
        context: Qt.WindowShortcut
        enabled: testCase.windowSpaceProbeActive
        onActivated: testCase.windowSpaceActivations += 1
    }

    property var surface: null
    property real pressSceneY: 0
    property real dragSceneY: 0
    property int pageDestructions: 0

    // What the session reported when an open failed, so a stalled open names its
    // cause instead of only timing out.
    property string openFailure: ""

    Keys.onSpacePressed: (event) => {
        testCase.spacePropagations += 1
        event.accepted = true
    }
    Keys.onReturnPressed: (event) => {
        testCase.returnPropagations += 1
        event.accepted = true
    }
    Keys.onLeftPressed: (event) => {
        testCase.leftPropagations += 1
        event.accepted = true
    }

    EditorQmlBootstrap {
        id: drawerBootstrap

        ApplicationSession { id: drawerSession }
    }

    // The session's own failure reports, recorded so the open assertion can name
    // what the production path actually said.
    Connections {
        target: session

        function onOpenFailed(message) { testCase.openFailure = message }
        function onOperationFailed(message) { testCase.openFailure = message }
    }

    Component {
        id: surfaceComponent

        EditorSurface {}
    }

    function initTestCase() {
        if (bootstrap.profileActive)
            session.configureTypography(bootstrap.profileFontPx)
        verify(bootstrap.start("mus_route101"), "the staged route101 project starts opening")
        var waited = 0
        while (waited < 30000 && !session.songOpen && testCase.openFailure.length === 0) {
            wait(50)
            waited += 50
        }
        verify(session.songOpen, "the staged route101 song opened" + testCase.openDiagnostics())
        if (testCase.containerPhase) {
            verify(bootstrap.detachProductionSection(testCase.velocityKind),
                   "the container phase releases the production velocity page before it mounts")
            verify(bootstrap.detachProductionSection(testCase.voiceChangesKind),
                   "the container phase releases the production voice page before it mounts")
            verify(bootstrap.detachProductionSection(testCase.automationKind),
                   "the container phase releases the production automation page before it mounts")
        }
        testCase.createSurface()
    }

    function openDiagnostics() {
        var details = ["projectRoot=" + bootstrap.projectRoot,
                       "label=mus_route101",
                       "projectOpen=" + session.projectOpen,
                       "songOpen=" + session.songOpen,
                       "stagedLabels=[" + testCase.stagedLabels() + "]"]
        if (testCase.openFailure.length > 0)
            details.push("openFailed=" + testCase.openFailure)
        if (session.lastSaveError.length > 0)
            details.push("lastSaveError=" + session.lastSaveError)
        return " (" + details.join("; ") + ")"
    }

    // The labels the staged project actually offers, so a label mismatch is part
    // of the failure instead of something to guess from a timeout.
    function stagedLabels() {
        var labels = []
        var count = session.songCount()
        for (var i = 0; i < count && i < 8; ++i)
            labels.push(session.songLabel(i))
        return count > 8 ? labels.join(",") + ",…" : labels.join(",")
    }

    function init() {
        bootstrap.detachTestSection(velocityKind)
        bootstrap.detachTestSection(voiceChangesKind)
        bootstrap.detachTestSection(automationKind)
        verify(bootstrap.cancelInput(), "no interaction is live at a case boundary")
        // A playhead case holds the production polling task for determinism;
        // every case starts with it running again.
        bootstrap.resumePlayheadPolling()
        testCase.spacePropagations = 0
        testCase.returnPropagations = 0
        testCase.leftPropagations = 0
        testCase.pageDestructions = 0
        verify(bootstrap.resetPreferences(), "each drawer case starts with empty preferences")
    }

    function cleanup() {
        testCase.windowSpaceProbeActive = false
        bootstrap.cancelInput()
        bootstrap.stopObservingVoiceAudition()
        VoiceSupport.awaitVoiceModal(testCase, "voicePicker", false)
        VoiceSupport.awaitVoiceModal(testCase, "voiceChangeMenu", false)
        VoiceSupport.awaitVoiceModal(testCase, "automationPrompt", false)
        VoiceSupport.awaitVoiceModal(testCase, "automationMenu", false)
        wait(0)
    }

    // ---- production composition and published state ------------------------

    // The one production composition, mounted in initTestCase for the whole
    // document presentation. `createSurface` is its only mount.
    function createSurface() {
        var item = surfaceComponent.createObject(testCase, {
            "width": testCase.width,
            "height": testCase.height,
            "applicationSession": session.songTabs.selectedPage
        })
        verify(item, "the production surface came up")
        testCase.surface = item
    }

    function chromeState(values) {
        var state = { "velocityVisible": false, "velocityHeight": 0,
                      "automationVisible": false, "automationHeight": 0,
                      "voiceChangesVisible": false, "voiceChangesHeight": 0,
                      "activePage": "" }
        for (var key in values)
            state[key] = values[key]
        return state
    }

    // Restoring records no preference change, so it writes nothing back.
    function resetChrome(location, values) {
        LayoutSupport.seedStore(testCase, location, testCase.chromeState(values))
        wait(0)
        session.configurePersistence()
        LayoutSupport.awaitRenderedLayout(testCase)
    }

    function presenter() { return testCase.surface.drawerPresenter }

    function section(kind) { return testCase.presenter().section(kind) }

    function drawerPalette() { return testCase.surface.gridModel.palette }

    function drawer() { return findChild(testCase.surface, "editorDrawer") }

    function bar() { return findChild(testCase.drawer(), "drawerBar") }

    function toggle(kind) { return findChild(testCase.drawer(), "drawerToggle_" + LayoutSupport.keyName(testCase, kind)) }

    function grip(kind) { return findChild(testCase.drawer(), "drawerHandle_" + LayoutSupport.keyName(testCase, kind)) }

    function body(kind) { return findChild(testCase.drawer(), "drawerBody_" + LayoutSupport.keyName(testCase, kind)) }

    function pageItem(kind) { return testCase.body(kind).item }

    function rollInput() { return findChild(testCase.surface, "swiftRollInput") }

    function editorHeight() {
        return findChild(testCase.surface, "timelineOtherEventsBand")
            .mapToItem(testCase.surface, 0, 0).y
    }

    function rollBand() { return findChild(testCase.surface, "swiftRollBand") }

    function cleanupTestCase() {
        bootstrap.pausePlayheadPolling()
        verify(bootstrap.hostClosing(),
               "the session still presents its document while the scene exists")
        var retired = testCase.surface
        testCase.surface = null
        verify(retired, "the lane mounted its one composition")
        retired.destroy()
        wait(0)
        verify(bootstrap.acknowledgeSceneRemoval(),
               "the session released its document presentation after the acknowledged"
               + " scene removal")
        var settled = bootstrap.publishedPlayheadPresentations()
        verify(settled > 0, "the lane published presentations before retirement")
        compare(bootstrap.presentPlayheadObservation(192000, 2), false,
                "an authoritative observation after the acknowledged removal is refused")
        compare(bootstrap.publishedPlayheadPresentations(), settled,
                "no shared presentation survives the acknowledged removal")
    }
}
