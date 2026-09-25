// Smoke acceptance for the Swift roll window, run by the rollqml lane:
//
//     roll_qml_tests {scratch} -input tst_SwiftRoll.qml
//
// The lane hosts the production composition by relative URL -- the same
// SwiftRollOverlay.qml the application's resource engine loads -- and drives
// it through its real seams: a genuine ApplicationSession declared as the
// bootstrap's QML child, a private drawer preference file under the runner
// scratch, and real pointer and keyboard input. Every expectation is read
// from the production session, from the drawn item or from a rendered pixel;
// this suite re-implements no container policy, and no production file knows
// it exists.
import QtQuick
import QtTest
import PorydawApp
import RollQmlCheck 1.0
// The production composition, reached exactly as the brief specifies: the
// relative path to ../../ui/songview/quick/swiftroll/SwiftRollOverlay.qml, the
// same file the application's resource engine loads. A directory import keeps
// one composition root -- the lane never copies, forks or re-declares it.
import Porydaw.Ui
import "../editorqml/NativeWait.js" as NativeWait

TestCase {
    id: testCase

    name: "SwiftRollWindow"
    // Only the rendered window gates the cases: `when` also gates initTestCase,
    // so it must never depend on the song the open assertion waits for. That
    // assertion carries the diagnostics and gates the remaining cases itself.
    when: windowShown
    width: 960
    height: 640
    // In Qt 6.11 a root TestCase item is invisible unless it says otherwise, and
    // effective visibility ANDs the whole chain: without this the mounted
    // surface renders nothing and the chrome takes neither pointer nor keyboard
    // input.
    visible: true

    property var overlay: null

    // What the session reported when an open failed, so a stalled open names
    // its cause instead of only timing out.
    property string openFailure: ""

    RollQmlBootstrap {
        id: bootstrap

        ApplicationSession { id: session }
    }

    // The session's own failure reports, recorded so the open assertion can
    // name what the production path actually said.
    Connections {
        target: session

        function onOpenFailed(message) { testCase.openFailure = message }
        function onOperationFailed(message) { testCase.openFailure = message }
    }

    // The production overlay reads `appSession` as a context property — the
    // window installs it with setContextProperty before loading the document.
    // A property declared on the created instance is the same lookup result:
    // the overlay's own context object answers the unqualified name before any
    // context property would, so the composition binds the real session
    // without a C++ host.
    Component {
        id: overlayComponent

        SwiftRollOverlay {
            property var appSession: session
        }
    }

    // Qt Quick Test waits pump Qt events but not Swift MainActor Tasks. Keep
    // production session calls intact and service the native event loop while
    // observing the same state the original checks require.
    function waitForNative(predicate, timeoutMs) {
        return NativeWait.waitForNative(bootstrap, function(ms) { wait(ms) }, predicate, timeoutMs)
    }

    function initTestCase() {
        // QtCore.Settings uses QGuiApplication's identity, not the test
        // runner's executable name. Establish it before any Settings or the
        // mounted drawer exists.
        Qt.application.name = "porydaw"
        Qt.application.organization = "sp3cker"
        Qt.application.domain = ""
        verify(bootstrap.captureSettings(), "saved the caller's native preferences")
        verify(bootstrap.start("mus_route101"),
               "the staged route101 project starts opening")
        verify(waitForNative(function() {
            return session.songOpen || testCase.openFailure.length > 0
        }, 30000), "the staged route101 song opened" + testCase.openDiagnostics())
        testCase.mountOverlay()
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

    // The labels the staged project actually offers, so a label mismatch is
    // part of the failure instead of something to guess from a timeout.
    function stagedLabels() {
        var labels = []
        var count = session.songCount()
        for (var i = 0; i < count && i < 8; ++i)
            labels.push(session.songLabel(i))
        return count > 8 ? labels.join(",") + ",…" : labels.join(",")
    }

    // The one production composition, mounted once the document is presented.
    // The mounted EditorSurface gets the lane's private preference file and
    // the same initial drawer layout the native fixture pushed, so no case can
    // read or write the caller's store.
    function mountOverlay() {
        var item = overlayComponent.createObject(testCase, {
            "width": testCase.width,
            "height": testCase.height
        })
        verify(item, "the production overlay came up")
        testCase.overlay = item
        var surface = null
        verify(waitForNative(function() {
            surface = testCase.selectedSurface()
            return surface !== null
        }, 5000), "the selected tab's production EditorSurface mounted")
        surface.drawerPreferenceLocation = bootstrap.preferencesUrl("lane-drawer.ini")
        var drawer = findChild(surface, "editorDrawer")
        verify(drawer, "the production drawer is mounted")
        drawer.presenter.restoreStoredPreferences(0, 160, 1, 240, 1, 90, 0)
        verify(waitForNative(function() {
            return surface.visible && surface.width > 0 && surface.height > 0
        }, 5000), "the mounted surface is drawn")
    }

    // The selected tab's EditorSurface: the overlay's root and the surface both
    // carry the production objectName, and findChild searches descendants, so
    // the one match under the overlay is the surface itself.
    function selectedSurface() {
        return testCase.overlay ? findChild(testCase.overlay, "swiftRollOverlay") : null
    }

    // Every case starts from the settled composition: whatever the previous
    // case left live — a page gesture, a prompt or a page modal — ends through
    // the composition's own cancellation path, the same call a hidden surface
    // makes, and the production polling task runs again for cases that do not
    // park it for determinism.
    function init() {
        bootstrap.cancelInput()
        bootstrap.resumePlayheadPolling()
    }
    function cleanup() {
        bootstrap.cancelInput()
        if (bootstrap.timeSigFixtureActive())
            verify(bootstrap.restoreTimeSigFixture(), "time-signature fixture restores its entry history")
        wait(0)
    }

    function cleanupTestCase() {
        bootstrap.pausePlayheadPolling()
        verify(bootstrap.bridgeStaleSelectionReleased(),
               "the stale selectedReference cannot reactivate a released BridgeProbe")
        verify(bootstrap.bridgeReturnedRowReleased(),
               "lastReturnedRow survives probe release without reactivating a replacement")
        verify(bootstrap.hostClosing(),
               "the session retains its page and song catalog until scene removal")
        verify(bootstrap.releasePresentedPage(),
               "closing the presented tab removes its page through the production strip")
        tryVerify(function() { return bootstrap.pageWorkspaceReleased() }, 5000,
                  "pageReleased retires the tabPageReleased workspace after page destruction")
        var retired = testCase.overlay
        testCase.overlay = null
        if (retired) {
            retired.destroy()
            wait(0)
            verify(bootstrap.acknowledgeSceneRemoval(),
                   "acknowledged scene removal releases the remaining document presentation")
            verify(bootstrap.releasedDocumentCannotPublish(),
                   "released camera, playback and document callbacks cannot mutate the old grid")
            verify(bootstrap.acknowledgeSceneRemovalAgain(),
                   "a second scene-removal acknowledgment does not re-release presentation")
        }
        verify(bootstrap.restoreSettings(), "restored the caller's native settings")
    }

    // ---- the smoke case ------------------------------------------------------

    // The mounted production window: the overlay publishes the selected tab's
    // real grid, the surface is drawn, and the window framebuffer holds the
    // rendered scene.
    function test_rollWindowMountsAndDraws() {
        verify(testCase.overlay !== null, "the production overlay is mounted")
        verify(testCase.overlay.gridModel !== null,
               "the overlay publishes the selected tab's grid")
        var surface = testCase.selectedSurface()
        verify(surface && surface.visible && surface.width > 0 && surface.height > 0,
               "the production EditorSurface is drawn")
        waitForRendering(surface)
        var image = grabImage(surface)
        verify(image.width > 0 && image.height > 0,
               "the window framebuffer holds the rendered surface")
        compare(session.songTabs.tabCount, 1, "the staged song occupies one tab")
    }
    function timeSigSnapshot() {
        return {
            bytes: bootstrap.timeSigBytes(),
            revision: bootstrap.timeSigRevision(),
            undoIndex: bootstrap.timeSigUndoIndex(),
            undoCount: bootstrap.timeSigUndoCount()
        }
    }

    function compareTimeSigSnapshot(expected, message) {
        compare(bootstrap.timeSigBytes(), expected.bytes, message + " bytes")
        compare(bootstrap.timeSigRevision(), expected.revision, message + " revision")
        compare(bootstrap.timeSigUndoIndex(), expected.undoIndex, message + " undo index")
        compare(bootstrap.timeSigUndoCount(), expected.undoCount, message + " undo count")
    }

    function openTimeSigChip(tick) {
        var surface = testCase.selectedSurface()
        var ruler = findChild(surface, "timelineRulerInput")
        verify(ruler && ruler.width > 0 && ruler.height > 0, "A001: live ruler input exists")
        var x = bootstrap.cameraContentX(tick)
        verify(x >= 0 && x < ruler.width, "the seeded signature chip is in the ruler")
        mouseDoubleClickSequence(ruler, x, ruler.height / 4, Qt.LeftButton)
        // QtBridge queues property notifications: observe the realized loader,
        // not just the Swift flag set by the input handler.
        tryVerify(function() { return findChild(surface, "timeSignaturePrompt") !== null },
                  5000, "the prompt loader responds to the published open state")
        var prompt = findChild(surface, "timeSignaturePrompt")
        verify(prompt, "A002: double-click opened the shared time-signature prompt")
        var numerator = findChild(prompt, "timeSignatureNumerator")
        verify(numerator, "A003: numerator text editor exists")
        tryCompare(numerator, "activeFocus", true)
        return { ruler: ruler, prompt: prompt, numerator: numerator }
    }

    function chooseTimeSigEight(prompt) {
        var button = findChild(prompt, "timeSignatureDenominator3")
        verify(button, "A005: denominator 8 button exists")
        mouseClick(button, button.width / 2, button.height / 2, Qt.LeftButton)
        tryCompare(button, "activeFocus", true)
    }

    function test_timeSignaturePromptAcceptUndoGrid() {
        var tick = bootstrap.seedTimeSigFixture()
        verify(tick > 0 && bootstrap.timeSigTicksPerBeat() > 0,
               "A001: the staged song seeded a 3/4 chip at four beats")
        var before = timeSigSnapshot()
        var opened = openTimeSigChip(tick)
        keyClick(Qt.Key_7)
        compare(opened.numerator.text, "7", "A004: typed 7 replaces selected 3")
        chooseTimeSigEight(opened.prompt)
        keyClick(Qt.Key_Return)
        tryCompare(session, "timeSigPromptOpen", false)
        compare(bootstrap.timeSigNumerator(tick), 7, "A007: numerator is 7")
        compare(bootstrap.timeSigDenominatorPower(tick), 3, "A007: denominator is 8")
        compare(bootstrap.timeSigRevision(), before.revision + 1, "A007: one revision")
        compare(bootstrap.timeSigUndoIndex(), before.undoIndex + 1, "A007: one undo index")
        compare(bootstrap.timeSigUndoCount(), before.undoCount + 1, "A007: one undo command")
        compare(bootstrap.timeSigSegmentStart(tick), tick, "A009: grid starts at signature")
        compare(bootstrap.timeSigSegmentBeats(tick), 7, "A009: seven beats per bar")
        compare(bootstrap.timeSigSegmentBeatTicks(tick), bootstrap.timeSigTicksPerBeat() / 2,
                "A009: denominator scales beat ticks")
        tryCompare(opened.ruler, "activeFocus", true)
        verify(bootstrap.undoTimeSignature(), "A011: one undo succeeds")
        compare(bootstrap.timeSigBytes(), before.bytes, "A011: original MIDI bytes restored")

        var unchanged = openTimeSigChip(tick)
        var same = timeSigSnapshot()
        var accept = findChild(unchanged.prompt, "timeSignatureAccept")
        verify(accept, "A013: reopened prompt has Accept")
        mouseClick(accept, accept.width / 2, accept.height / 2, Qt.LeftButton)
        tryCompare(session, "timeSigPromptOpen", false)
        compareTimeSigSnapshot(same, "A014: accepting unchanged 3/4")
    }

    function test_timeSignaturePromptCancelStale() {
        var tick = bootstrap.seedTimeSigFixture()
        verify(tick >= 0, "A015: the fixture opened")
        var before = timeSigSnapshot()
        var cancelled = openTimeSigChip(tick)
        keyClick(Qt.Key_7)
        var cancel = findChild(cancelled.prompt, "timeSignatureCancel")
        verify(cancel, "A017: Cancel button exists")
        mouseClick(cancel, cancel.width / 2, cancel.height / 2, Qt.LeftButton)
        tryCompare(session, "timeSigPromptOpen", false)
        compareTimeSigSnapshot(before, "A018: Cancel")
        tryCompare(cancelled.ruler, "activeFocus", true)

        var invalid = openTimeSigChip(tick)
        keyClick(Qt.Key_9)
        keyClick(Qt.Key_9)
        keyClick(Qt.Key_9)
        keyClick(Qt.Key_Return)
        compare(session.timeSigPromptOpen, true, "A021: invalid 999 keeps the prompt")
        compareTimeSigSnapshot(before, "A021: invalid 999")
        keyClick(Qt.Key_Escape)
        tryCompare(session, "timeSigPromptOpen", false)

        openTimeSigChip(tick)
        verify(bootstrap.setInterveningTimeSignature(tick + bootstrap.timeSigTicksPerBeat()),
               "an external document edit arrives while the prompt is open")
        var intervening = timeSigSnapshot()
        compare(session.timeSigPromptOpen, false, "A024: revision retires the stale prompt")
        compareTimeSigSnapshot(intervening, "A024: no extra command from stale prompt")
    }

    function test_timeSignaturePromptMenuEntries_data() {
        return [{ tag: "on chip", onChip: true }, { tag: "off chip", onChip: false }]
    }

    function test_timeSignaturePromptMenuEntries(data) {
        var tick = bootstrap.seedTimeSigFixture()
        verify(tick >= 0, "A025: the fixture opened")
        var surface = testCase.selectedSurface()
        var ruler = findChild(surface, "timelineRulerInput")
        verify(ruler, "A025: the mounted ruler input exists")
        var menuTick = tick + (data.onChip ? 0 : bootstrap.timeSigTicksPerBeat())
        mouseClick(ruler, bootstrap.cameraContentX(menuTick), ruler.height / 4, Qt.RightButton)
        tryVerify(function() { return findChild(surface, "quickMenuPanelRoot") !== null },
                  5000, "the menu loader responds to the published open state")
        var menu = findChild(surface, "quickMenuPanelRoot")
        verify(menu && session.timeSigMenuOpen, "A026: shared ruler menu opens")
        var editRow = findChild(menu, "rulerMenuRow_9")
        verify(editRow, "the existing Edit Time Signature menu row is rendered")
        mouseClick(editRow, editRow.width / 2, editRow.height / 2, Qt.LeftButton)
        compare(session.timeSigMenuOpen, false, "A027: menu no longer owns the prompt")
        tryVerify(function() { return findChild(surface, "timeSignaturePrompt") !== null },
                  5000, "the menu action realizes the prompt")
        var prompt = findChild(surface, "timeSignaturePrompt")
        verify(prompt && session.timeSigPromptOpen, "A028: menu action opens the form")
        var numerator = findChild(prompt, "timeSignatureNumerator")
        tryCompare(numerator, "activeFocus", true)
        keyClick(Qt.Key_Escape)
        tryCompare(session, "timeSigPromptOpen", false)
        tryCompare(ruler, "activeFocus", true)
    }

    function test_timeSignaturePromptCursorEntry_data() {
        return [{ tag: "on event", onEvent: true }, { tag: "off event", onEvent: false }]
    }

    function test_timeSignaturePromptCursorEntry(data) {
        var tick = bootstrap.seedTimeSigFixture()
        verify(tick >= 0, "A031: the fixture opened")
        var cursorTick = data.onEvent ? tick : tick + 7
        var before = timeSigSnapshot()
        verify(bootstrap.setTimeSigCursor(cursorTick), "A032: exact edit cursor established")
        var surface = testCase.selectedSurface()
        var ruler = findChild(surface, "timelineRulerInput")
        verify(ruler, "A032: the live ruler interaction exists")
        session.openTimeSigPromptAtCursor()
        tryVerify(function() { return findChild(surface, "timeSignaturePrompt") !== null },
                  5000, "the cursor action realizes the prompt")
        var prompt = findChild(surface, "timeSignaturePrompt")
        verify(prompt, "A033: cursor opens the live prompt")
        var numerator = findChild(prompt, "timeSignatureNumerator")
        verify(numerator, "A034: numerator input exists")
        tryCompare(numerator, "activeFocus", true)
        compare(numerator.text, "3", "A035: in-effect signature seeds numerator")
        keyClick(Qt.Key_5)
        compare(numerator.text, "5", "A036: typed 5 is displayed")
        chooseTimeSigEight(prompt)
        keyClick(Qt.Key_Return)
        tryCompare(session, "timeSigPromptOpen", false)
        compare(bootstrap.timeSigNumerator(cursorTick), 5, "A039: exact cursor numerator")
        compare(bootstrap.timeSigDenominatorPower(cursorTick), 3, "A039: exact cursor denominator")
        compare(bootstrap.timeSigRevision(), before.revision + 1, "A039: one revision")
        compare(bootstrap.timeSigUndoIndex(), before.undoIndex + 1, "A039: one undo index")
        compare(bootstrap.timeSigUndoCount(), before.undoCount + 1, "A039: one undo command")
        if (!data.onEvent) {
            compare(bootstrap.timeSigNumerator(tick), 3, "A040: original event numerator stays")
            compare(bootstrap.timeSigDenominatorPower(tick), 2,
                    "A040: original event denominator stays")
        }
        tryCompare(ruler, "activeFocus", true)
    }
}
