// Container acceptance for the editor drawer, run by the editorqml lane:
//
//     editor_qml_tests {scratch} -input tst_EditorDrawer.qml
//
// The lane hosts the production composition by relative URL -- the same
// EditorSurface.qml the application's resource engine loads -- and drives the
// container through its real seam: test-owned pages attached by the lane
// bootstrap, a private preference file under the runner scratch, and real
// pointer and keyboard input. Every expectation is read from the production
// presenter, from the drawn item or from a rendered pixel; this suite
// re-implements no container policy, and no production file knows it exists.
import QtCore
import QtQuick
import QtTest
import PorydawApp
import EditorQmlCheck 1.0
// The production composition, reached exactly as the brief specifies: the
// relative path to ../../ui/songview/quick/swiftroll/EditorSurface.qml, the same
// file the application's resource engine loads. A directory import keeps one
// composition root -- the lane never copies, forks or re-declares it.
import "../../ui/songview/quick/swiftroll"

TestCase {
    id: testCase

    name: "EditorDrawerLane"
    // Only the rendered window gates the cases: `when` also gates initTestCase,
    // so it must never depend on the song the open assertion waits for. That
    // assertion carries the diagnostics and gates the remaining cases itself.
    when: windowShown
    width: 900
    height: 700
    // In Qt 6.11 a root TestCase item is invisible unless it says otherwise, and
    // effective visibility ANDs the whole chain: without this the mounted surface
    // renders nothing and the chrome takes neither pointer nor keyboard input.
    visible: true

    // DrawerSectionKind raw values (EditorDrawer.swift).
    readonly property int automationKind: 0
    readonly property int velocityKind: 1
    readonly property int voiceChangesKind: 2

    // The test-owned page item the bootstrap's test pages resolve to.
    readonly property url testPageUrl: Qt.resolvedUrl("DrawerTestPage.qml")

    // The lane's two phases, each in its own process: the production phase hosts
    // the production Velocity page in the composition for the whole run, and the
    // container phase releases that page's slot before the composition mounts so
    // its container cases can host test pages in every kind. A phase's own cases
    // skip in the other phase, and neither phase reuses another's QML content
    // for a Swift owner it keeps.
    readonly property bool containerPhase: bootstrap.lanePhase === "container"
    readonly property bool productionPhase: !testCase.containerPhase

    // The historical store: one category, seven keys.
    readonly property var drawerKeys: ["automationVisible", "automationHeight",
                                       "velocityVisible", "velocityHeight",
                                       "voiceChangesVisible", "voiceChangesHeight",
                                       "activePage"]
    readonly property string absentKey: "__absent__"

    // Parent counters observe ordinary unclaimed key presses. The real window
    // shortcut below separately checks numeric focus at Qt's ShortcutOverride
    // phase, before key-press propagation.
    property int spacePropagations: 0
    property int returnPropagations: 0
    property int leftPropagations: 0
    property bool windowSpaceProbeActive: false
    property int windowSpaceActivations: 0

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

    function test_numericFieldWindowShortcutPriority_data() {
        return [
            { tag: "velocity", kind: testCase.velocityKind },
            { tag: "automation", kind: testCase.automationKind }
        ]
    }

    function test_numericFieldWindowShortcutPriority(data) {
        if (testCase.containerPhase) skip("the production owner runs in its own process")
        var location = bootstrap.preferencesUrl("numeric-space-" + data.tag)
        var field
        if (data.kind === testCase.velocityKind) {
            testCase.mountProductionVelocity(location)
            testCase.clickNode(testCase.velocityNodes()[0])
            tryCompare(testCase.velocityModel(), "selectedCount", 1)
            testCase.surface.applicationSession.performGridCommand(bootstrap.setVelocityCommand())
            tryCompare(testCase.velocityModel(), "promptOpen", true)
            field = findChild(testCase.velocityPageItem(), "noteVelocityInput")
        } else {
            testCase.mountProductionAutomation(location)
            verify(testCase.writeVolumeLanePoints(bootstrap.automationVolumeIndex()))
            verify(testCase.openAutomationNodeMenu(testCase.automationWrittenNodeIndex()))
            verify(testCase.triggerAutomationMenuRow(1))
            testCase.awaitAutomationModal("automationPrompt", true)
            field = findChild(testCase.automationPageItem(), "automationPromptInput")
        }
        verify(field, "the real numeric field is mounted")
        tryCompare(field, "activeFocus", true)
        var draft = field.text
        var expected = testCase.windowSpaceActivations + 1
        testCase.windowSpaceProbeActive = true
        keyClick(Qt.Key_Space)
        tryCompare(testCase, "windowSpaceActivations", expected, 1000,
                   "a focused numeric field yields Space to a real window shortcut")
        compare(field.text, draft, "the transport key does not change numeric text")
    }

    EditorQmlBootstrap {
        id: bootstrap

        ApplicationSession { id: session }
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

    Component {
        id: storeComponent

        Settings { category: "editorDrawer" }
    }

    function test_automationModalsRetireWithPage() {
        if (testCase.containerPhase) skip("the production owner runs in its own process")
        testCase.mountProductionAutomation(bootstrap.preferencesUrl("automation-modal-lifetime"))
        var loader = findChild(testCase.surface, "drawerBody_automation")
        var host = findChild(testCase.surface, "drawerModalLayer")
        verify(loader && host, "the production loader and external modal host are present")
        verify(findChild(host, "automationMenu"), "the page creates its hosted menu")
        verify(findChild(host, "automationPrompt"), "the page creates its hosted prompt")
        bootstrap.cancelInput()
        try {
            loader.setSource("")
            tryVerify(function() {
                return !findChild(host, "automationMenu") && !findChild(host, "automationPrompt")
            }, 1000, "unloading the page retires both modals while their host survives")
        } finally {
            loader.syncSource()
            tryVerify(function() { return !!testCase.automationPageItem() }, 1000,
                      "the existing document owner remounts through the same production loader")
        }
    }

    function initTestCase() {
        verify(bootstrap.start("mus_route101"), "the staged route101 project starts opening")
        var waited = 0
        while (waited < 30000 && !session.songOpen && testCase.openFailure.length === 0) {
            wait(50)
            waited += 50
        }
        verify(session.songOpen, "the staged route101 song opened" + testCase.openDiagnostics())
        // The container phase owns its own process: the production page releases
        // its slot before the composition mounts, so the document-bound page
        // owner's content is never loaded there and never outlives a QML item
        // that consumed it.
        if (testCase.containerPhase) {
            verify(bootstrap.detachProductionSection(testCase.velocityKind),
                   "the container phase releases the production velocity page before it mounts")
            verify(bootstrap.detachProductionSection(testCase.voiceChangesKind),
                   "the container phase releases the production voice page before it mounts")
            verify(bootstrap.detachProductionSection(testCase.automationKind),
                   "the container phase releases the production automation page before it mounts")
        }
        // One production composition for the document-bound owners' whole
        // lifetime: the scene that consumed their QObject proxies is not
        // destroyed for a case, exactly as the running application keeps its one
        // composition while the document is presented. Cases reset its state
        // explicitly; the scene goes in cleanupTestCase, after the host's close.
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

    // Every case starts with no test page attached: the drawer survives with
    // chrome values only, so the previous case's test pages are released here
    // through the container's own detach, which cancels synchronously. The
    // document-bound production page stays in its slot for the run — the
    // composition that consumed it is not torn down per case.
    function init() {
        bootstrap.detachTestSection(velocityKind)
        bootstrap.detachTestSection(voiceChangesKind)
        bootstrap.detachTestSection(automationKind)
        // Whatever the previous case left live — a page gesture, a prompt or a
        // page modal — ends here through the composition's own cancellation
        // path, the same call a hidden surface makes.
        verify(bootstrap.cancelInput(), "no interaction is live at a case boundary")
        // A playhead case holds the production polling task for determinism;
        // every case starts with it running again.
        bootstrap.resumePlayheadPolling()
        testCase.spacePropagations = 0
        testCase.returnPropagations = 0
        testCase.leftPropagations = 0
        testCase.pageDestructions = 0
    }

    // A case ends by settling the one composition: the next case's init()
    // releases this case's attachments through the container's own detach, so
    // nothing the scene bound is destroyed to end a case.
    function cleanup() {
        testCase.windowSpaceProbeActive = false
        // A case ends by settling what it opened: every live page interaction ends
        // through the composition's own cancellation path, and both modal surfaces
        // are waited down to their drawn closed state, so the next case starts
        // from the settled composition instead of a pass behind it.
        bootstrap.cancelInput()
        bootstrap.stopObservingVoiceAudition()
        testCase.awaitVoiceModal("voicePicker", false)
        testCase.awaitVoiceModal("voiceChangeMenu", false)
        testCase.awaitVoiceModal("automationPrompt", false)
        testCase.awaitVoiceModal("automationMenu", false)
        wait(0)
    }

    // ---- production composition and published state ------------------------

    // The one production composition, mounted in initTestCase for the whole
    // document presentation. `createSurface` is its only mount.
    function createSurface() {
        var item = surfaceComponent.createObject(testCase, {
            "width": testCase.width,
            "height": testCase.height,
            "applicationSession": session,
            "drawerPreferenceLocation": bootstrap.preferencesUrl("lane")
        })
        verify(item, "the production surface came up")
        testCase.surface = item
    }

    // A case's chrome state, stated in full: an absent key would leave the
    // previous case's value in place, exactly as the container's restore
    // documents, and no case may start from another case's chrome.
    function chromeState(values) {
        var state = { "velocityVisible": false, "velocityHeight": 0,
                      "automationVisible": false, "automationHeight": 0,
                      "voiceChangesVisible": false, "voiceChangesHeight": 0,
                      "activePage": "" }
        for (var key in values)
            state[key] = values[key]
        return state
    }

    // Resets the one composition's chrome to this case's private store, the way
    // a mount does: the store is seeded with the case's full state, the
    // container is pointed at it, and the container's own restore applies it.
    // Restoring records no preference change, so it writes nothing back.
    function resetChrome(location, values) {
        testCase.seedStore(location, testCase.chromeState(values))
        testCase.surface.drawerPreferenceLocation = location
        wait(0)
        testCase.drawer().restoreStoredPreferences()
        testCase.awaitRenderedLayout()
    }

    function presenter() { return testCase.surface.drawerPresenter }
    function section(kind) { return testCase.presenter().section(kind) }
    function drawerPalette() { return testCase.surface.gridModel.palette }
    function drawer() { return findChild(testCase.surface, "editorDrawer") }
    function bar() { return findChild(testCase.drawer(), "drawerBar") }
    function toggle(kind) { return findChild(testCase.drawer(), "drawerToggle_" + testCase.keyName(kind)) }
    function grip(kind) { return findChild(testCase.drawer(), "drawerHandle_" + testCase.keyName(kind)) }
    function body(kind) { return findChild(testCase.drawer(), "drawerBody_" + testCase.keyName(kind)) }
    function pageItem(kind) { return testCase.body(kind).item }
    function rollInput() { return findChild(testCase.surface, "swiftRollInput") }
    function hintStatus() { return findChild(testCase.surface, "mouseHintStatus") }
    function editorHeight() { return testCase.hintStatus().mapToItem(testCase.surface, 0, 0).y }
    function rollBand() { return findChild(testCase.surface, "swiftRollBand") }

    // ---- the shared playhead ------------------------------------------------

    // The one production presenter the session owns; the composition's playhead
    // mounts on this same object.
    function playheadPresenter() { return session.playheadPresenter() }
    function playheadClip(name) { return findChild(testCase.surface, name) }
    function playheadLine(name) {
        var clip = testCase.playheadClip(name)
        return clip ? findChild(clip, "sharedPlayheadLine") : null
    }
    function playheadSurfaceX(name) {
        var line = testCase.playheadLine(name)
        return line ? line.mapToItem(testCase.surface, line.width / 2, 0).x : -1
    }
    function verifyPlayheadPixels(name) {
        var line = testCase.playheadLine(name)
        verify(line && line.visible && line.width > 0 && line.height > 0)
        waitForRendering(line)
        var image = grabImage(testCase.surface)
        var region = testCase.regionOf(image, testCase.surface, line)
        compare(testCase.nearestPixel(image, region, testCase.channelsOf(line.color)).distance,
                0, name + " draws the playhead colour at its projected position")
    }
    // Production toggle activation until the kind's body is visible.
    function showSection(kind) {
        testCase.awaitRenderedLayout()
        if (!testCase.section(kind).visible)
            testCase.clickToggle(kind)
        testCase.awaitRenderedLayout()
    }
    // One authoritative observation through the production presenter, with the
    // drawn composition given a pass to catch up.
    function presentPlayhead(sample, transport) {
        var changed = bootstrap.presentPlayheadObservation(sample, transport)
        wait(0)
        return changed
    }
    // A drawn segment's visibility follows the published one on the next pass,
    // the same lag every other drawn binding in this suite accounts for.
    function awaitPlayheadVisibility(name, expected) {
        tryVerify(function() {
            var clip = testCase.playheadClip(name)
            return clip !== null && clip.visible === expected
        }, 2000, "the " + name + " segment visibility is " + expected)
    }

    function keyName(kind) {
        switch (kind) {
        case testCase.automationKind: return "automation"
        case testCase.velocityKind: return "velocity"
        case testCase.voiceChangesKind: return "voiceChanges"
        }
        return ""
    }

    function attachPage(kind) {
        return bootstrap.attachTestSection(kind, String(testCase.testPageUrl))
    }

    // The hosted page reports its own destruction. Connecting to the item the
    // lane is about to tear down shows the QML content dying with its surface,
    // which is what happens before the page's Swift owner is released.
    function observePageDestruction(item) {
        item.pageDestroyed.connect(function() { testCase.pageDestructions += 1 })
    }

    // ---- the historical store ---------------------------------------------

    function createStore(location) {
        var store = storeComponent.createObject(testCase, { "location": location })
        verify(store, "a private store at " + location)
        return store
    }

    function seedStore(location, values) {
        var store = testCase.createStore(location)
        for (var key in values)
            store.setValue(key, values[key])
        store.sync()
        store.destroy()
    }

    // A snapshot reads through a freshly created Settings instance, so it also
    // proves the drawer's sync(): every call re-reads what was written. Key
    // type and value are both recorded, because the historical formats are part
    // of the contract (bool, integer, 0 for unset, page name).
    function snapshotStore(location) {
        var store = testCase.createStore(location)
        var snapshot = {}
        for (var i = 0; i < testCase.drawerKeys.length; ++i) {
            var key = testCase.drawerKeys[i]
            var value = store.value(key, testCase.absentKey)
            snapshot[key] = value === testCase.absentKey ? "absent"
                                                         : (typeof value) + ":" + String(value)
        }
        store.destroy()
        return snapshot
    }

    function compareSnapshots(actual, expected, message) {
        for (var i = 0; i < testCase.drawerKeys.length; ++i) {
            var key = testCase.drawerKeys[i]
            compare(actual[key], expected[key], message + " [" + key + "]")
        }
    }

    // The drawer writes from a preference signal that arrives on the pass after
    // the call that caused it, so an interactive write is awaited through fresh
    // Settings instances before the store is read.
    function awaitStoreKey(location, key, expected) {
        tryVerify(function() { return testCase.snapshotStore(location)[key] === expected }, 2000,
                  "the store records " + key + "=" + expected)
    }

    // ---- input -------------------------------------------------------------

    // A real pointer activation of a chrome control: the drawer passes its own
    // live focus observation for that call. The drawn layout is gated first so
    // the pointer lands on the control the presenter published, not on the
    // position the previous publication left behind.
    function clickToggle(kind) {
        testCase.awaitRenderedLayout()
        var control = testCase.toggle(kind)
        mouseClick(control, control.width / 2, control.height / 2, Qt.LeftButton)
    }

    function focusControl(control) {
        control.forceActiveFocus(Qt.TabFocusReason)
        tryCompare(control, "activeFocus", true, 1000, "the control holds focus")
    }

    // The handle measures its drag against the scene position the press started
    // at, so the lane drives the same scene coordinates a pointer produces; the
    // drawn layout is gated first so the press lands on the published handle.
    function pressGrip(kind) {
        testCase.awaitRenderedLayout()
        var control = testCase.grip(kind)
        testCase.pressSceneY = control.mapToItem(null, 0, control.height / 2).y
        testCase.dragSceneY = testCase.pressSceneY
        mousePress(control, control.width / 2, control.height / 2, Qt.LeftButton)
    }

    function dragGripTo(kind, sceneY) {
        var control = testCase.grip(kind)
        testCase.dragSceneY = sceneY
        var local = control.mapFromItem(null, 0, sceneY)
        mouseMove(control, local.x, local.y, -1, Qt.LeftButton)
    }

    function releaseGrip(kind) {
        var control = testCase.grip(kind)
        var local = control.mapFromItem(null, 0, testCase.dragSceneY)
        mouseRelease(control, local.x, local.y, Qt.LeftButton)
    }

    // The window's active focus item is the page's own scope or a descendant of
    // it: the container focuses the page item, never a handler it re-declares.
    // The item chain is walked through the public `parent` property, because
    // QQuickItem's ancestor query is not QML-callable.
    function focusIsIn(item) {
        if (!item)
            return false
        var window = item.Window.window
        var focused = window ? window.activeFocusItem : null
        for (var current = focused; current; current = current.parent) {
            if (current === item)
                return true
        }
        return false
    }

    // ---- drawn rectangles --------------------------------------------------

    // A QML binding that depends on a changed property can re-evaluate on the
    // next event-loop pass rather than inside the call that changed it, so the
    // drawn composition may still show the previous layout (before the store is
    // restored, for instance) in the same JS turn. Gate every comparison and
    // every pointer action on the drawn container, band and bar agreeing with
    // the presenter; published presenter reads need no gate.
    function awaitRenderedLayout() {
        tryVerify(function() {
            var presenter = testCase.presenter()
            var container = testCase.drawer()
            var band = testCase.rollBand()
            var bar = testCase.bar()
            var status = testCase.hintStatus()
            if (!presenter || !container || !band || !bar || !status)
                return false
            if (container.height !== presenter.height)
                return false
            var rollOrigin = band.mapToItem(testCase.surface, 0, 0)
            var drawerOrigin = container.mapToItem(testCase.surface, 0, 0)
            var statusOrigin = status.mapToItem(testCase.surface, 0, 0)
            if (!status.visible || status.height <= 0
                || rollOrigin.x !== 0 || rollOrigin.y !== 0
                || drawerOrigin.x !== 0 || statusOrigin.x !== 0
                || band.width !== testCase.surface.width
                || container.width !== testCase.surface.width
                || status.width !== testCase.surface.width
                || band.height !== drawerOrigin.y
                || drawerOrigin.y + container.height !== statusOrigin.y
                || statusOrigin.y + status.height !== testCase.surface.height)
                return false
            if (bar.visible !== presenter.barVisible)
                return false
            return !bar.visible || (bar.x === presenter.barX && bar.y === presenter.barY
                                    && bar.width === presenter.barWidth
                                    && bar.height === presenter.barHeight)
        }, 2000, "the drawn composition catches up with the presenter")
    }

    // A drawn control sits exactly where the presenter published it, measured in
    // the container's own coordinate system.
    function verifyRect(item, x, y, width, height, what) {
        var origin = item.mapToItem(testCase.drawer(), 0, 0)
        fuzzyCompare(origin.x, x, 0.01, what + ": x")
        fuzzyCompare(origin.y, y, 0.01, what + ": y")
        fuzzyCompare(item.width, width, 0.01, what + ": width")
        fuzzyCompare(item.height, height, 0.01, what + ": height")
    }

    function renderedRect(item) {
        var origin = item.mapToItem(testCase.drawer(), 0, 0)
        return { x: origin.x, y: origin.y, width: item.width, height: item.height }
    }

    // A drawn item measured in the surface's own coordinates: the playhead's
    // segments live across the roll band and the drawer, so the container is not
    // the common ancestor they are compared in.
    function verifySurfaceRect(item, x, y, width, height, what) {
        var origin = item.mapToItem(testCase.surface, 0, 0)
        fuzzyCompare(origin.x, x, 0.01, what + ": x")
        fuzzyCompare(origin.y, y, 0.01, what + ": y")
        fuzzyCompare(item.width, width, 0.01, what + ": width")
        fuzzyCompare(item.height, height, 0.01, what + ": height")
    }

    // A drawn item follows the published geometry of its own kind only after the
    // layout gate, so a body stays inside the container when the published body
    // rect does.
    function bodyInsideContainer(kind) {
        var state = testCase.section(kind)
        var presenter = testCase.presenter()
        return state.bodyY + state.bodyHeight <= presenter.height - presenter.barHeight + 0.01
    }

    // ---- accessible contract ----------------------------------------------

    function verifyToggleAccessibility(kind, name) {
        var control = testCase.toggle(kind)
        compare(control.Accessible.role, Accessible.Button, name + ": role")
        compare(control.Accessible.name, name, name + ": name")
        compare(control.Accessible.checkable, true, name + ": checkable")
        compare(control.Accessible.checked, testCase.section(kind).visible, name + ": checked")
        compare(control.Accessible.focusable, true, name + ": focusable")
    }

    function verifyGripAccessibility(kind, name) {
        var control = testCase.grip(kind)
        compare(control.Accessible.role, Accessible.Grip, name + ": role")
        compare(control.Accessible.name, name, name + ": name")
        compare(control.Accessible.description, "Use Up and Down to resize", name + ": description")
        compare(control.Accessible.focusable, true, name + ": focusable")
    }

    // ---- rendered theme ----------------------------------------------------

    function channelsOf(color) {
        var value = parseInt(String(color).slice(-6), 16)
        return [(value >> 16) & 0xff, (value >> 8) & 0xff, value & 0xff]
    }

    // 0 = the button's own background, 1 = the pure keyboard-label tint, read
    // from the channel the two colours differ in most.
    function tintFraction(pixel, background, tint, channel) {
        return (background[channel] - pixel[channel]) / (background[channel] - tint[channel])
    }

    function widestChannel(background, tint) {
        var channel = 0
        for (var c = 1; c < 3; ++c) {
            if (Math.abs(background[c] - tint[c]) > Math.abs(background[channel] - tint[channel]))
                channel = c
        }
        return channel
    }

    // The rectangle of `control` inside a grab of `anchor`, in image pixels. The
    // lane reaches the control through the surface rather than through
    // grabImage(control): Qt Quick Test crops the window by the item's own local
    // rectangle, so an item whose ancestors are offset (the drawer sits at the
    // bottom of the surface) is captured over whatever shares its local
    // coordinates — here, demonstrably, the roll keyboard. The surface is
    // scene-aligned, so its local rectangle is its scene rectangle and the mapped
    // control rectangle is the region that was actually drawn.
    function regionOf(image, anchor, control) {
        var origin = control.mapToItem(anchor, 0, 0)
        var scaleX = anchor.width > 0 ? image.width / anchor.width : 1
        var scaleY = anchor.height > 0 ? image.height / anchor.height : 1
        return { x0: Math.round(origin.x * scaleX), y0: Math.round(origin.y * scaleY),
                 x1: Math.round((origin.x + control.width) * scaleX) - 1,
                 y1: Math.round((origin.y + control.height) * scaleY) - 1 }
    }

    // The control's own interior inside that region: two logical pixels in from
    // every edge, so no neighbouring row can reach the blend domain. The ring is
    // derived from the region's size against the control's logical size rather
    // than fixed, so a grabbed device pixel ratio needs no second constant.
    function interiorOf(region, control) {
        var scaleX = (control && control.width > 0)
                ? (region.x1 - region.x0 + 1) / control.width : 1
        var scaleY = (control && control.height > 0)
                ? (region.y1 - region.y0 + 1) / control.height : 1
        var ringX = Math.max(1, Math.ceil(2 * scaleX))
        var ringY = Math.max(1, Math.ceil(2 * scaleY))
        return { ringX: ringX, ringY: ringY,
                 x0: region.x0 + ringX, y0: region.y0 + ringY,
                 x1: region.x1 - ringX, y1: region.y1 - ringY,
                 usable: region.x1 - ringX >= region.x0 + ringX
                         && region.y1 - ringY >= region.y0 + ringY }
    }

    function isInterior(image, x, y, bounds) {
        return bounds.usable && x >= bounds.x0 && x <= bounds.x1
                && y >= bounds.y0 && y <= bounds.y1 && image.alpha(x, y) === 255
    }

    // The region pixel nearest an expected colour, measured as the largest channel
    // difference and skipping anything not fully opaque. Choosing by distance
    // rather than by tint fraction is what keeps the evidence strict: an exact
    // palette pixel always wins over a neighbouring artefact, and a control whose
    // glyph is missing or drawn in its own colours never gets near the expected
    // tint at all.
    function nearestPixel(image, region, target) {
        var best = null
        var bestAt = "(none)"
        var bestDistance = 256
        for (var x = region.x0; x <= region.x1; ++x) {
            for (var y = region.y0; y <= region.y1; ++y) {
                if (image.alpha(x, y) !== 255)
                    continue
                var pixel = [image.red(x, y), image.green(x, y), image.blue(x, y)]
                var distance = Math.max(Math.abs(pixel[0] - target[0]),
                                        Math.abs(pixel[1] - target[1]),
                                        Math.abs(pixel[2] - target[2]))
                if (distance < bestDistance) {
                    bestDistance = distance
                    best = pixel
                    bestAt = "(" + x + "," + y + ")"
                }
            }
        }
        return { pixel: best ? best : [0, 0, 0], at: bestAt, distance: bestDistance }
    }

    function renderDiagnostics(image, control, region, fill, tintMatch, background, tint) {
        if (!image || !region || !fill || !tintMatch)
            return " (no grab)"
        var bounds = testCase.interiorOf(region, control)
        return " (control " + (control ? control.width + "x" + control.height : "?")
                + ", grab " + image.width + "x" + image.height
                + ", region " + region.x0 + "," + region.y0 + " " 
                + (region.x1 - region.x0 + 1) + "x" + (region.y1 - region.y0 + 1)
                + ", blend ring " + bounds.ringX + "x" + bounds.ringY
                + ", nearest-fill " + fill.pixel.join("/") + " d=" + fill.distance + " " + fill.at
                + ", nearest-tint " + tintMatch.pixel.join("/") + " d=" + tintMatch.distance
                + " " + tintMatch.at
                + ", expected fill " + background.join("/")
                + ", expected tint " + tint.join("/") + ")"
    }

    // The drawn button is its own background plus the alpha-masked glyph filled
    // with the keyboard label, and the evidence is gathered from one region of a
    // surface grab: the surface is scene-aligned, so grabbing it and sampling the
    // toggle's mapped rectangle reads the pixels that were really drawn there
    // (grabImage(toggle) crops by the toggle's local rectangle and lands on
    // whatever shares it, which in this composition is the roll keyboard). Inside
    // that region the pixel nearest each expected colour proves the capture — an
    // exact palette pixel always wins over a neighbouring artefact — and the
    // region's interior must be an exact blend of exactly those two colours, so a
    // glyph drawn in its own icon colours or not drawn at all still fails.
    //
    // The tint tolerance is 24, measured rather than chosen. At the real 14px lane
    // toggle the strongest glyph pixel is 43/43/42 against a 26/26/26 tint over
    // the window-background button (distance 17), and 42/47/47 over the lighter
    // selection-ring button (distance 21), both at roughly 90% antialiased
    // coverage because no fully opaque glyph pixel exists at that size on this
    // backend. 24 is the measured worst case plus a small margin, still below the
    // 26 an untinted black glyph reaches, and such a glyph fails the exact blend
    // invariant as well. The fill tolerance stays at 2.
    function verifyToggleRendering(kind, background, message) {
        var control = testCase.toggle(kind)
        var anchor = testCase.surface
        var tint = testCase.channelsOf(testCase.drawerPalette().keyboardLabel)
        var base = testCase.channelsOf(background)
        var channel = testCase.widestChannel(base, tint)
        verify(Math.abs(base[channel] - tint[channel]) > 2,
               message + ": the button background and the tint must differ")
        var image = null
        var region = null
        var fill = null
        var tintMatch = null
        var waited = 0
        while (waited < 5000) {
            image = grabImage(anchor)
            region = testCase.regionOf(image, anchor, control)
            fill = testCase.nearestPixel(image, region, base)
            tintMatch = testCase.nearestPixel(image, region, tint)
            if (fill.distance <= 8 && tintMatch.distance <= 40)
                break
            wait(50)
            waited += 50
        }
        verify(fill.distance <= 8 && tintMatch.distance <= 40,
               message + ": the themed control rendered"
               + testCase.renderDiagnostics(image, control, region, fill, tintMatch, base, tint))
        for (var c = 0; c < 3; ++c) {
            fuzzyCompare(fill.pixel[c], base[c], 2,
                         message + ": button background channel " + c
                         + testCase.renderDiagnostics(image, control, region, fill, tintMatch,
                                                      base, tint))
            fuzzyCompare(tintMatch.pixel[c], tint[c], 24,
                         message + ": glyph tint channel " + c
                         + testCase.renderDiagnostics(image, control, region, fill, tintMatch,
                                                      base, tint))
        }

        // Every pixel of the control's own interior — two logical pixels in from
        // every edge, so no rounded-in neighbouring row can reach it — is an exact
        // blend of its fill and the keyboard-label tint.
        var bounds = testCase.interiorOf(region, control)
        for (var x = bounds.x0; x <= bounds.x1; ++x) {
            for (var y = bounds.y0; y <= bounds.y1; ++y) {
                if (!testCase.isInterior(image, x, y, bounds))
                    continue
                var pixel = [image.red(x, y), image.green(x, y), image.blue(x, y)]
                var fraction = testCase.tintFraction(pixel, base, tint, channel)
                verify(fraction > -0.2 && fraction < 1.2,
                       message + ": pixel " + x + "," + y + " is not a tint blend of the button"
                       + testCase.renderDiagnostics(image, control, region, fill, tintMatch,
                                                    base, tint))
                var clamped = Math.max(0, Math.min(1, fraction))
                for (var k = 0; k < 3; ++k) {
                    var blended = base[k] + (tint[k] - base[k]) * clamped
                    verify(Math.abs(blended - pixel[k]) <= 6,
                           message + ": pixel " + x + "," + y + " channel " + k + " is not a tint blend")
                }
            }
        }
    }

    // ---- cases -------------------------------------------------------------

    // With no page attached the container is honest and empty, even when the
    // store asks for a visible section: no height, no control, no page, no write.
    function test_noPageContributesNothing() {
        // This phase's own process: the production page keeps its slot in the lane's own run.
        if (testCase.productionPhase) skip("the container cases run in the lane's container child")

        var location = bootstrap.preferencesUrl("no-page")
        testCase.resetChrome(location, { "velocityVisible": true, "velocityHeight": 137,
                                         "activePage": "velocity" })
        var seeded = testCase.snapshotStore(location)

        compare(testCase.presenter().height, 0, "no page contributes no height")
        compare(testCase.presenter().barVisible, false, "no page claims a bar")
        compare(testCase.bar().visible, false, "no bar is rendered")
        testCase.compareSnapshots(testCase.snapshotStore(location), seeded,
                                 "no page writes to the store")

        var kinds = [testCase.velocityKind, testCase.voiceChangesKind, testCase.automationKind]
        for (var i = 0; i < kinds.length; ++i) {
            var kind = kinds[i]
            var state = testCase.section(kind)
            var what = testCase.keyName(kind)
            compare(state.available, false, what + ": no page means unavailable")
            compare(state.contentUrl, "", what + ": an unavailable kind publishes no URL")
            compare(state.bodyWidth, 0, what + ": empty body width")
            compare(state.bodyHeight, 0, what + ": empty body height")
            compare(state.handleHeight, 0, what + ": no handle height")
            compare(state.toggleSize, 0, what + ": no toggle size")
            compare(testCase.toggle(kind).visible, false, what + ": no toggle is rendered")
            compare(testCase.grip(kind).visible, false, what + ": no handle is rendered")
            compare(testCase.body(kind).item, null, what + ": no page is hosted")
        }

        compare(testCase.presenter().plotOrigin, testCase.surface.timelineSplitX,
                "the plot origin includes the headers and keyboard")
        compare(testCase.presenter().plotWidth,
                testCase.surface.width - testCase.surface.timelineSplitX,
                "the plot width is the rest of the surface")
        compare(testCase.rollBand().height, testCase.editorHeight(),
                "the roll fills the editor above the persistent status strip")
        compare(testCase.rollInput().height, testCase.editorHeight() - testCase.surface.gridModel.rulerHeight,
                "the roll input fills the editor below the ruler and above the persistent status strip")
    }

    // Three real pages host through the production seam: chrome and stacking
    // follow the published rectangles, pages map from the shared gutter, the
    // accessible contract holds, Return/Enter activate while bare Space stays
    // unclaimed, and the themed chrome is real rendered output.
    function test_hostedChromeAndStacking() {
        // This phase's own process: the production page keeps its slot in the lane's own run.
        if (testCase.productionPhase) skip("the container cases run in the lane's container child")

        var location = bootstrap.preferencesUrl("chrome")
        verify(testCase.attachPage(testCase.velocityKind), "the velocity page attaches")
        verify(testCase.attachPage(testCase.voiceChangesKind), "the voice-changes page attaches")
        verify(testCase.attachPage(testCase.automationKind), "the automation page attaches")
        testCase.resetChrome(location, { "automationVisible": true, "automationHeight": 150,
                                         "velocityVisible": true, "velocityHeight": 110,
                                         "voiceChangesVisible": true, "voiceChangesHeight": 130,
                                         "activePage": "automations" })

        var presenter = testCase.presenter()
        compare(presenter.barVisible, true, "an available section keeps the bar")
        compare(testCase.bar().visible, true, "the bar is rendered")
        testCase.verifyRect(testCase.bar(), presenter.barX, presenter.barY,
                            presenter.barWidth, presenter.barHeight, "bar")

        var order = [testCase.velocityKind, testCase.voiceChangesKind, testCase.automationKind]
        var aggregate = presenter.barHeight
        var rects = {}
        for (var i = 0; i < order.length; ++i) {
            var kind = order[i]
            var state = testCase.section(kind)
            var what = testCase.keyName(kind)
            compare(state.available, true, what + ": the attached page is available")
            verify(String(state.contentUrl).length > 0, what + ": the page has a resolved URL")
            compare(state.visible, true, what + ": the stored visibility applies")

            testCase.verifyRect(testCase.toggle(kind), state.toggleX, state.toggleY,
                                state.toggleSize, state.toggleSize, what + " toggle")
            testCase.verifyRect(testCase.grip(kind), 0, state.handleY, testCase.drawer().width,
                                state.handleHeight, what + " handle")

            var loader = testCase.body(kind)
            testCase.verifyRect(loader, state.bodyX, state.bodyY, state.bodyWidth,
                                state.bodyHeight, what + " body")
            tryVerify(function() { return testCase.pageItem(kind) !== null }, 2000,
                      what + ": the body loads its page")
            var item = loader.item
            verify(item, what + ": the body hosts a page item")
            fuzzyCompare(item.width, loader.width, 0.01, what + ": the page fills its body width")
            fuzzyCompare(item.height, loader.height, 0.01, what + ": the page fills its body height")
            fuzzyCompare(item.plotOrigin, presenter.plotOrigin, 0.01,
                         what + ": the page maps from the container's plot origin")
            compare(state.bodyWidth, presenter.plotOrigin + presenter.plotWidth,
                    what + ": the body spans the shared plot")

            rects[what] = testCase.renderedRect(loader)
            aggregate += state.handleHeight + state.bodyHeight
        }
        compare(presenter.plotOrigin, testCase.surface.timelineSplitX,
                "the container publishes the combined gutter")
        fuzzyCompare(presenter.height, aggregate, 0.01, "the container fits its sections and bar")

        verify(rects.velocity.y + rects.velocity.height <= rects.voiceChanges.y + 0.01,
               "velocity sits above voice changes")
        verify(rects.voiceChanges.y + rects.voiceChanges.height <= rects.automation.y + 0.01,
               "voice changes sit above automations")
        var barRect = testCase.renderedRect(testCase.bar())
        verify(barRect.y >= rects.automation.y + rects.automation.height - 0.01,
               "the bar sits below every body")
        fuzzyCompare(barRect.y + barRect.height, presenter.height, 0.01,
                     "the bar closes the container")

        testCase.verifyToggleAccessibility(testCase.velocityKind, "Velocity drawer")
        testCase.verifyToggleAccessibility(testCase.voiceChangesKind, "Voice-change drawer")
        testCase.verifyToggleAccessibility(testCase.automationKind, "Automation drawer")
        testCase.verifyGripAccessibility(testCase.velocityKind, "Resize velocity drawer")
        testCase.verifyGripAccessibility(testCase.voiceChangesKind, "Resize voice-change drawer")
        testCase.verifyGripAccessibility(testCase.automationKind, "Resize automation drawer")

        var hoverGrip = testCase.grip(testCase.velocityKind)
        mouseMove(hoverGrip, hoverGrip.width / 2, hoverGrip.height / 2)
        tryVerify(function() {
            return String(hoverGrip.color).toUpperCase()
                === String(testCase.drawerPalette().selectionRing).toUpperCase()
        }, 1000, "a hovered handle highlights")
        mouseMove(testCase.bar(), 2, 2)
        tryVerify(function() {
            return String(hoverGrip.color).toUpperCase()
                === String(testCase.drawerPalette().outline).toUpperCase()
        }, 1000, "leaving the handle returns its outline")

        // Return and Enter activate a focused toggle and are claimed by it.
        testCase.focusControl(testCase.toggle(testCase.voiceChangesKind))
        testCase.returnPropagations = 0
        keyClick(Qt.Key_Return)
        compare(testCase.section(testCase.voiceChangesKind).visible, false, "Return hides the section")
        compare(testCase.returnPropagations, 0, "the toggle claims Return")

        testCase.focusControl(testCase.toggle(testCase.velocityKind))
        keyClick(Qt.Key_Enter)
        compare(testCase.section(testCase.velocityKind).visible, false, "Enter hides the section")
        compare(testCase.returnPropagations, 0, "the toggle claims Enter")

        // Bare Space is never claimed: it reaches the surface's ancestor.
        testCase.focusControl(testCase.toggle(testCase.automationKind))
        testCase.spacePropagations = 0
        keyClick(Qt.Key_Space)
        compare(testCase.spacePropagations, 1, "bare Space propagates unclaimed")
        compare(testCase.section(testCase.automationKind).visible, true, "Space does not toggle")

        // Rendered theme: the unchecked control is the window background behind
        // the tinted glyph, the checked one is the selection ring behind it.
        testCase.clickToggle(testCase.automationKind)
        compare(testCase.section(testCase.automationKind).visible, false, "a click hides the section")
        testCase.awaitRenderedLayout()
        compare(testCase.toggle(testCase.automationKind).Accessible.checked, false,
                "the accessible state follows the hidden section")
        testCase.verifyToggleRendering(testCase.automationKind, testCase.drawerPalette().windowBackground,
                                       "unchecked toggle")

        testCase.clickToggle(testCase.automationKind)
        compare(testCase.section(testCase.automationKind).visible, true, "a click shows the section")
        testCase.awaitRenderedLayout()
        compare(testCase.toggle(testCase.automationKind).Accessible.checked, true,
                "the accessible state follows the shown section")
        testCase.verifyToggleRendering(testCase.automationKind, testCase.drawerPalette().selectionRing,
                                       "checked toggle")
    }

    // Pointer and keyboard hide and re-show one section: a hidden section
    // releases its height and the roll grows, re-showing restores the same body
    // height, and the last hidden section leaves the bar and its toggles in place.
    function test_toggleRetainsStoredHeight() {
        // This phase's own process: the production page keeps its slot in the lane's own run.
        if (testCase.productionPhase) skip("the container cases run in the lane's container child")

        var location = bootstrap.preferencesUrl("stored-height")
        verify(testCase.attachPage(testCase.automationKind), "the automation page attaches")
        testCase.resetChrome(location, { "automationVisible": true, "activePage": "automations" })

        var presenter = testCase.presenter()
        var kind = testCase.automationKind
        var barRow = presenter.barHeight
        var stored = testCase.section(kind).bodyHeight
        var openHeight = presenter.height
        verify(stored > 0 && openHeight > barRow, "the visible section has a body")
        tryVerify(function() { return testCase.pageItem(kind) !== null }, 2000,
                  "the visible section loads its page")
        var sectionPage = testCase.pageItem(kind)

        testCase.clickToggle(kind)
        compare(testCase.section(kind).visible, false, "the click hides the section")
        compare(presenter.height, barRow, "a hidden section releases its height")
        testCase.awaitRenderedLayout()
        compare(testCase.rollInput().height, testCase.editorHeight() - barRow - testCase.surface.gridModel.rulerHeight,
                "the roll grows by the released height")
        compare(testCase.grip(kind).visible, false, "no handle while hidden")
        compare(testCase.body(kind).visible, false, "no body while hidden")
        verify(testCase.pageItem(kind) === sectionPage, "hiding keeps the same page instance")

        testCase.clickToggle(kind)
        compare(testCase.section(kind).visible, true, "the click shows the section")
        fuzzyCompare(testCase.section(kind).bodyHeight, stored, 0.01, "the stored body height returns")
        fuzzyCompare(presenter.height, openHeight, 0.01, "the container height returns")

        // The keyboard path hides through the same transition.
        testCase.focusControl(testCase.toggle(kind))
        keyClick(Qt.Key_Return)
        compare(testCase.section(kind).visible, false, "Return hides the section")
        testCase.awaitRenderedLayout()
        compare(testCase.bar().visible, true, "the bar stays for the last hidden section")
        compare(testCase.toggle(kind).visible, true, "the toggle stays too")
        compare(testCase.grip(kind).visible, false, "no handle for the last hidden section")
        compare(testCase.body(kind).visible, false, "no body for the last hidden section")
        compare(presenter.height, barRow, "the container is the bar row")

        testCase.clickToggle(kind)
        compare(testCase.section(kind).visible, true, "the section shows again")
        testCase.awaitRenderedLayout()
        fuzzyCompare(testCase.section(kind).bodyHeight, stored, 0.01,
                     "re-showing restores the same body height")
        compare(testCase.rollInput().height, testCase.editorHeight() - openHeight - testCase.surface.gridModel.rulerHeight,
                "the roll gives the height back")
    }

    // Real press/drag/release resizes by the drag delta, the minimum and the
    // available height clamp, Up/Down step by the resize step, Left/Right are
    // consumed, a cancelled drag keeps the last applied height, and a host
    // shrink re-clamps without rewriting the stored height.
    function test_resizeClampAndCancellation() {
        // This phase's own process: the production page keeps its slot in the lane's own run.
        if (testCase.productionPhase) skip("the container cases run in the lane's container child")

        var location = bootstrap.preferencesUrl("resize")
        verify(testCase.attachPage(testCase.automationKind), "the automation page attaches")
        testCase.resetChrome(location, { "automationVisible": true, "activePage": "automations" })

        var presenter = testCase.presenter()
        var kind = testCase.automationKind
        var host = testCase.surface.height
        var stored = testCase.section(kind).bodyHeight
        var openHeight = presenter.height

        testCase.pressGrip(kind)
        testCase.dragGripTo(kind, testCase.dragSceneY - 40)
        fuzzyCompare(testCase.section(kind).bodyHeight, stored + 40, 1,
                     "the drag grows the body by its delta")
        fuzzyCompare(presenter.height, openHeight + 40, 1, "the container grows with the body")
        verify(presenter.height <= testCase.editorHeight(), "the container stays above the status strip")

        testCase.dragGripTo(kind, testCase.dragSceneY + 600)
        var floorHeight = testCase.section(kind).bodyHeight
        verify(floorHeight > 0 && floorHeight < stored, "dragging down clamps at a positive minimum")
        testCase.dragGripTo(kind, testCase.dragSceneY + 400)
        fuzzyCompare(testCase.section(kind).bodyHeight, floorHeight, 0.01, "the minimum is stable")
        verify(testCase.bodyInsideContainer(kind), "the body stays inside the container")
        testCase.releaseGrip(kind)

        // The grip's keyboard path reaches the same floor and steps by the
        // resize step, while the cross-axis arrows are consumed no-ops.
        testCase.focusControl(testCase.grip(kind))
        for (var i = 0; i < 24; ++i)
            keyClick(Qt.Key_Down)
        fuzzyCompare(testCase.section(kind).bodyHeight, floorHeight, 0.01,
                     "the keyboard path shares the minimum body")
        var beforeStep = testCase.section(kind).bodyHeight
        keyClick(Qt.Key_Up)
        var step = testCase.section(kind).bodyHeight - beforeStep
        verify(step > 0, "Up grows the body by the resize step")
        keyClick(Qt.Key_Up)
        fuzzyCompare(testCase.section(kind).bodyHeight, beforeStep + 2 * step, 0.01,
                     "each press adds one resize step")
        keyClick(Qt.Key_Down)
        fuzzyCompare(testCase.section(kind).bodyHeight, beforeStep + step, 0.01,
                     "Down takes one step back")
        testCase.leftPropagations = 0
        keyClick(Qt.Key_Left)
        keyClick(Qt.Key_Right)
        compare(testCase.leftPropagations, 0, "the grip consumes the cross-axis arrows")
        fuzzyCompare(testCase.section(kind).bodyHeight, beforeStep + step, 0.01,
                     "the cross-axis arrows resize nothing")

        // Dragging far up fills the host and stops there.
        testCase.pressGrip(kind)
        testCase.dragGripTo(kind, testCase.dragSceneY - 4000)
        fuzzyCompare(presenter.height, testCase.editorHeight(), 0.01,
                     "the container clamps above the status strip")
        var ceiling = testCase.section(kind).bodyHeight
        testCase.dragGripTo(kind, testCase.dragSceneY - 200)
        fuzzyCompare(testCase.section(kind).bodyHeight, ceiling, 0.01,
                     "the available height is stable")
        verify(testCase.bodyInsideContainer(kind), "the clamped body stays inside the container")
        testCase.releaseGrip(kind)

        // A cancelled drag keeps the height it applied and leaves no session:
        // further movement with the button still down changes nothing.
        testCase.pressGrip(kind)
        testCase.dragGripTo(kind, testCase.dragSceneY + 25)
        var applied = testCase.section(kind).bodyHeight
        fuzzyCompare(applied, ceiling - 25, 1, "the drag applied its delta")
        presenter.inputCancelled(1)
        testCase.dragGripTo(kind, testCase.dragSceneY + 120)
        fuzzyCompare(testCase.section(kind).bodyHeight, applied, 0.01,
                     "a cancelled drag has no session left")
        testCase.releaseGrip(kind)
        fuzzyCompare(testCase.section(kind).bodyHeight, applied, 0.01,
                     "releasing after a cancellation keeps the applied height")

        testCase.awaitRenderedLayout()
        var rightStart = testCase.section(kind).bodyHeight
        var rightGrip = testCase.grip(kind)
        mousePress(rightGrip, rightGrip.width / 2, rightGrip.height / 2, Qt.RightButton)
        var rightLocal = rightGrip.mapFromItem(null, 0, testCase.dragSceneY - 40)
        mouseMove(rightGrip, rightLocal.x, rightLocal.y, Qt.RightButton)
        mouseRelease(rightGrip, rightLocal.x, rightLocal.y, Qt.RightButton)
        fuzzyCompare(testCase.section(kind).bodyHeight, rightStart, 0.01,
                     "a right-button drag on the handle resizes nothing")

        // The host shrink re-clamps the drawn body and keeps the stored height.
        testCase.surface.height = host - 250
        verify(presenter.height <= testCase.editorHeight() + 0.01,
               "the container follows the host shrink")
        verify(testCase.section(kind).bodyHeight < applied, "the shrink re-clamps the drawn body")
        testCase.surface.height = host
        fuzzyCompare(testCase.section(kind).bodyHeight, applied, 0.01,
                     "the stored height survived the host shrink")
    }

    // The Voice-Changes to Automations spill while resizing, and the release
    // lifetime: releasing a page drops the content the composition hosted for it
    // while the composition itself stays mounted for the document-bound owners it
    // binds to.
    function test_voiceChangesSpillAndDetach() {
        // This phase's own process: the production page keeps its slot in the lane's own run.
        if (testCase.productionPhase) skip("the container cases run in the lane's container child")

        var location = bootstrap.preferencesUrl("voice-spill")
        verify(testCase.attachPage(testCase.voiceChangesKind), "the voice-changes page attaches")
        verify(testCase.attachPage(testCase.automationKind), "the automation page attaches")
        bootstrap.setTestSectionMaximumBodyHeight(testCase.voiceChangesKind, 90)
        testCase.resetChrome(location, { "automationVisible": true, "automationHeight": 100,
                                         "voiceChangesVisible": true, "voiceChangesHeight": 60,
                                         "activePage": "voiceChanges" })

        var presenter = testCase.presenter()
        var host = testCase.editorHeight()
        var voiceKind = testCase.voiceChangesKind
        var automationKind = testCase.automationKind
        var voiceStart = testCase.section(voiceKind).bodyHeight
        var automationStart = testCase.section(automationKind).bodyHeight
        fuzzyCompare(voiceStart, 60, 0.01, "the stored voice-changes height is restored")
        fuzzyCompare(automationStart, 100, 0.01, "the stored automation height is restored")

        // Dragging far past the declared maximum stops the voice-changes body at
        // it and lets the automations body take the excess, up to the height the
        // container has left for it: the pair still fits the host.
        testCase.pressGrip(voiceKind)
        testCase.dragGripTo(voiceKind, testCase.dragSceneY - 4000)
        fuzzyCompare(testCase.section(voiceKind).bodyHeight, 90, 0.01,
                     "the voice-changes body stops at its declared maximum")
        var spilled = testCase.section(automationKind).bodyHeight
        verify(spilled > automationStart, "the excess moves the automations body")
        testCase.dragGripTo(voiceKind, testCase.dragSceneY - 400)
        fuzzyCompare(testCase.section(automationKind).bodyHeight, spilled, 0.01,
                     "the automations body stops at the height left for it")
        fuzzyCompare(presenter.height, host, 0.01, "the spilled pair fills the host")
        var filled = spilled + 90 + presenter.barHeight + 2 * testCase.section(voiceKind).handleHeight
        verify(filled <= host + 0.01, "the spilled sections never overflow the host")

        // Returning to the drag start restores both stored heights.
        testCase.dragGripTo(voiceKind, testCase.pressSceneY)
        fuzzyCompare(testCase.section(voiceKind).bodyHeight, voiceStart, 0.01,
                     "the capped section returns to its stored height")
        fuzzyCompare(testCase.section(automationKind).bodyHeight, automationStart, 0.01,
                     "the spilled section returns to its stored height")
        testCase.releaseGrip(voiceKind)

        // A small overshoot past the maximum moves the automations body by the
        // excess only, not by the whole request.
        var overshoot = 30
        testCase.pressGrip(voiceKind)
        testCase.dragGripTo(voiceKind, testCase.pressSceneY - ((90 - voiceStart) + overshoot))
        fuzzyCompare(testCase.section(voiceKind).bodyHeight, 90, 0.01,
                     "the capped body stays at its maximum")
        fuzzyCompare(testCase.section(automationKind).bodyHeight, automationStart + overshoot, 1,
                     "the excess alone moves the automations body")
        testCase.releaseGrip(voiceKind)
        var automationAfterSpill = testCase.section(automationKind).bodyHeight

        // Releasing the page drops the content the composition hosted for it: the
        // container's own release cancels the page once, unloads its item, and
        // writes no key of the released kind. The spilled pair's own writes are
        // awaited first, so the snapshot describes a settled store the release
        // must leave unchanged.
        testCase.awaitStoreKey(location, "automationHeight",
                               "number:" + Math.round(automationAfterSpill))
        testCase.awaitStoreKey(location, "voiceChangesHeight", "number:90")
        var beforeRelease = testCase.snapshotStore(location)
        var cancels = bootstrap.pageCancelCount
        tryVerify(function() { return testCase.pageItem(voiceKind) !== null }, 2000,
                  "the voice-changes section loads its page")
        var voicePage = testCase.pageItem(voiceKind)
        verify(voicePage, "the voice-changes page is hosted")
        testCase.observePageDestruction(voicePage)
        wait(0)

        bootstrap.detachTestSection(voiceKind)
        tryCompare(testCase, "pageDestructions", 1, 2000,
                   "the release dropped the content the composition hosted for the page")
        compare(bootstrap.pageCancelCount, cancels + 1, "the release cancels the page once")
        testCase.compareSnapshots(testCase.snapshotStore(location), beforeRelease,
                                 "releasing a page writes nothing")

        // The live composition shows the surviving chrome, with the released kind
        // absent and the automations section untouched.
        testCase.awaitRenderedLayout()
        compare(testCase.section(voiceKind).available, false, "the released kind stays unavailable")
        compare(testCase.toggle(voiceKind).visible, false, "no toggle for the released kind")
        compare(testCase.grip(voiceKind).visible, false, "no handle for the released kind")
        compare(testCase.body(voiceKind).item, null, "no page for the released kind")
        compare(testCase.section(automationKind).available, true, "the automations section is untouched")
        compare(testCase.section(automationKind).visible, true, "and still visible")
        fuzzyCompare(testCase.section(automationKind).bodyHeight, automationAfterSpill, 0.01,
                     "and keeps the height the spill left it")
        testCase.compareSnapshots(testCase.snapshotStore(location), beforeRelease,
                                 "the release writes nothing")
    }

    // Focus returns to the roll when nothing visible remains, showing a section
    // focuses its page scope, every transition cancels exactly once, and a page
    // outlives a hide until its own release.
    function test_focusReturnAndPageCancellation() {
        // This phase's own process: the production page keeps its slot in the lane's own run.
        if (testCase.productionPhase) skip("the container cases run in the lane's container child")

        var location = bootstrap.preferencesUrl("focus")
        verify(testCase.attachPage(testCase.automationKind), "the automation page attaches")
        testCase.resetChrome(location, { "automationVisible": true, "activePage": "automation" })

        var cancels = bootstrap.pageCancelCount
        var automationKind = testCase.automationKind
        tryVerify(function() { return testCase.pageItem(automationKind) !== null }, 2000,
                  "the visible section loads its page")
        var automationPage = testCase.pageItem(automationKind)
        verify(automationPage, "the automation page is hosted")

        testCase.focusControl(testCase.toggle(automationKind))
        testCase.clickToggle(automationKind)
        compare(testCase.section(automationKind).visible, false, "the section hides")
        // The transition cancels the hidden page's interaction without detaching
        // it: the page keeps its instance and is cancelled exactly once for that
        // transition, and the release that follows the teardown comes later.
        compare(bootstrap.pageCancelCount, cancels + 1, "hiding cancels the page once")
        tryVerify(function() { return testCase.focusIsIn(testCase.rollInput()) }, 1000,
                  "hiding the only visible section returns focus to the roll input")
        verify(testCase.pageItem(automationKind) === automationPage,
               "hiding keeps the same page instance")
        compare(bootstrap.pageCancelCount, cancels + 1, "a hidden page is not cancelled again")

        testCase.focusControl(testCase.toggle(automationKind))
        testCase.clickToggle(automationKind)
        compare(testCase.section(automationKind).visible, true, "the section shows again")
        compare(bootstrap.pageCancelCount, cancels + 1, "showing does not cancel the page")
        tryVerify(function() { return testCase.focusIsIn(automationPage) }, 1000,
                  "showing focuses the page item's own scope")
        tryVerify(function() { return automationPage.pageFocused }, 1000,
                  "the page's own scope reports that focus")

        // A second section becoming active cancels the page that lost the slot,
        // without destroying or disabling it. The attach happens while the
        // composition is mounted, so the section's control and its page appear on
        // the pass that follows the publication, never in the same call.
        verify(testCase.attachPage(testCase.velocityKind), "the velocity page attaches")
        var velocityKind = testCase.velocityKind
        tryVerify(function() { return testCase.toggle(velocityKind).visible }, 2000,
                  "the attached section publishes its toggle")
        tryVerify(function() { return testCase.pageItem(velocityKind) !== null }, 2000,
                  "the attached section loads its page")
        var velocityPage = testCase.pageItem(velocityKind)
        testCase.awaitRenderedLayout()
        testCase.focusControl(testCase.toggle(velocityKind))
        testCase.clickToggle(velocityKind)
        compare(testCase.section(velocityKind).visible, true, "the second section shows")
        compare(bootstrap.pageCancelCount, cancels + 2, "losing the active slot cancels once")
        tryVerify(function() { return testCase.focusIsIn(velocityPage) }, 1000,
                  "the shown section focuses its page")
        verify(testCase.pageItem(automationKind) === automationPage,
               "the older page is still the same instance")
        testCase.awaitRenderedLayout()
        compare(testCase.section(automationKind).visible, true, "the older page stays visible")
        compare(testCase.pageItem(automationKind).enabled, true,
                "a cancelled but visible page keeps operating")

        // Releasing a page cancels it exactly once while the composition stays
        // mounted; the scene the page's items live in is the composition's own,
        // and it is retired only at the host's close.
        bootstrap.detachTestSection(velocityKind)
        compare(bootstrap.pageCancelCount, cancels + 3, "the release after the hide cancels once")
        bootstrap.detachTestSection(automationKind)
        compare(bootstrap.pageCancelCount, cancels + 4, "and so does the remaining release")
    }

    // The store is the historical one: the mount restores every value and writes
    // nothing back, interactive calls write that kind's two keys and the chosen
    // page name in the historical formats, sync() makes them readable, and the
    // scratch file is the only store touched.
    function test_preferencesRoundTrip() {
        // This phase's own process: the production page keeps its slot in the lane's own run.
        if (testCase.productionPhase) skip("the container cases run in the lane's container child")

        var location = bootstrap.preferencesUrl("round-trip")
        verify(testCase.attachPage(testCase.velocityKind), "the velocity page attaches")
        verify(testCase.attachPage(testCase.voiceChangesKind), "the voice-changes page attaches")
        verify(testCase.attachPage(testCase.automationKind), "the automation page attaches")
        testCase.resetChrome(location, { "automationVisible": true, "automationHeight": 110,
                                         "velocityVisible": true, "velocityHeight": 130,
                                         "voiceChangesVisible": true, "voiceChangesHeight": 150,
                                         "activePage": "velocity" })
        var seeded = testCase.snapshotStore(location)
        var defaultStore = testCase.snapshotStore("")

        var presenter = testCase.presenter()
        var velocityKind = testCase.velocityKind
        var voiceKind = testCase.voiceChangesKind
        var automationKind = testCase.automationKind
        testCase.compareSnapshots(testCase.snapshotStore(location), seeded,
                                 "mounting writes nothing back")
        compare(testCase.section(velocityKind).visible, true, "the stored visibility applies")
        compare(testCase.section(voiceKind).visible, true, "the stored voice visibility applies")
        compare(testCase.section(automationKind).visible, true, "the stored automation visibility applies")
        fuzzyCompare(testCase.section(velocityKind).bodyHeight, 130, 0.01, "the stored velocity height")
        fuzzyCompare(testCase.section(voiceKind).bodyHeight, 150, 0.01, "the stored voice height")
        fuzzyCompare(testCase.section(automationKind).bodyHeight, 110, 0.01, "the stored automation height")

        // The restored active page decides the focus request: with the drawer
        // owning focus, hiding a section targets the stored page, not a fallback.
        testCase.focusControl(testCase.toggle(voiceKind))
        presenter.setSectionVisible(voiceKind, false, true)
        compare(testCase.section(voiceKind).visible, false, "the hidden section releases its height")
        tryVerify(function() { return testCase.focusIsIn(testCase.pageItem(velocityKind)) }, 1000,
                  "the restored active page answers the focus request")

        // Hiding writes that kind's own two keys, in the historical formats,
        // and no other kind's keys. The drawer writes from a preference signal
        // that arrives on the pass after the call, so the store is polled through
        // fresh Settings instances until the write lands.
        var beforeHide = testCase.snapshotStore(location)
        testCase.clickToggle(velocityKind)
        compare(testCase.section(velocityKind).visible, false, "the click hides velocity")
        testCase.awaitStoreKey(location, "velocityVisible", "boolean:false")
        testCase.awaitStoreKey(location, "velocityHeight", "number:130")
        var written = testCase.snapshotStore(location)
        compare(written.velocityVisible, "boolean:false", "visibility is written as a bool")
        compare(written.velocityHeight, "number:130", "the height is written as an integer")
        compare(written.activePage, "string:velocity", "the page keeps its historical name")
        compare(written.voiceChangesHeight, beforeHide.voiceChangesHeight,
                "another kind's height is not written")
        compare(written.voiceChangesVisible, beforeHide.voiceChangesVisible,
                "another kind's visibility is not written")
        compare(written.automationHeight, beforeHide.automationHeight,
                "a third kind's height is not written")
        compare(written.automationVisible, beforeHide.automationVisible,
                "a third kind's visibility is not written")

        // An unset height is the historical 0, and the body falls back to the
        // page's own default instead of the forgotten value.
        presenter.setSectionBodyHeight(velocityKind, 0)
        testCase.awaitStoreKey(location, "velocityHeight", "number:0")
        compare(testCase.snapshotStore(location).velocityHeight, "number:0",
                "an unset height is written as 0")
        testCase.clickToggle(velocityKind)
        var fallback = testCase.section(velocityKind).bodyHeight
        verify(fallback > 0, "an unset height falls back to the page's default")
        verify(Math.abs(fallback - 130) > 0.5, "and not to the forgotten stored height")

        // A resize writes the resized kind's height and visibility alone.
        var beforeResize = testCase.snapshotStore(location)
        testCase.pressGrip(automationKind)
        testCase.dragGripTo(automationKind, testCase.dragSceneY - 30)
        testCase.releaseGrip(automationKind)
        var resized = testCase.section(automationKind).bodyHeight
        testCase.awaitStoreKey(location, "automationHeight", "number:" + Math.round(resized))
        var afterResize = testCase.snapshotStore(location)
        compare(afterResize.automationHeight, "number:" + Math.round(resized),
                "a resize writes the resized height")
        compare(afterResize.automationVisible, "boolean:true", "and its visibility")
        compare(afterResize.velocityHeight, beforeResize.velocityHeight,
                "the resize writes no other height")
        compare(afterResize.voiceChangesHeight, beforeResize.voiceChangesHeight,
                "the resize writes no third height")

        // Choosing another section writes the page name.
        testCase.clickToggle(voiceKind)
        testCase.awaitStoreKey(location, "activePage", "string:voiceChanges")
        compare(testCase.snapshotStore(location).activePage, "string:voiceChanges",
                "the chosen page is written under its historical name")

        // Only the injected file was written.
        testCase.compareSnapshots(testCase.snapshotStore(""), defaultStore,
                                 "the application's default store is untouched")
    }

    // ---- the shared playhead ------------------------------------------------

    // The production composition renders one playhead: a segment clipped to the
    // roll plot column and one clipped to every visible drawer body, all reading
    // the one position the session's presenter publishes. A stopped position
    // stays rendered, gutters and chrome stay clear, and position-only updates
    // rebuild nothing.
    function test_sharedPlayheadRendersRollAndVisibleBodies() {
        // This phase's own process: the production page keeps its slot in the lane's own run.
        if (testCase.productionPhase) skip("the container cases run in the lane's container child")

        var location = bootstrap.preferencesUrl("playhead-bodies")
        verify(testCase.attachPage(testCase.velocityKind), "the velocity page attaches")
        verify(testCase.attachPage(testCase.voiceChangesKind), "the voice-changes page attaches")
        verify(testCase.attachPage(testCase.automationKind), "the automation page attaches")
        testCase.resetChrome(location, { "velocityVisible": true, "voiceChangesVisible": true,
                                         "automationVisible": true, "activePage": "automation" })
        verify(bootstrap.pausePlayheadPolling(),
               "the lane holds the production polling task for a deterministic position")

        var playhead = testCase.playheadPresenter()
        var grid = testCase.surface.gridModel
        var origin = testCase.presenter().plotOrigin
        grid.resetCameraScroll()
        testCase.presentPlayhead(4000, 0)
        tryVerify(function() { return playhead.timelineAttached && playhead.visible
                                        && !playhead.playing }, 1000,
                  "the stopped position is attached, visible and not playing")
        compare(playhead.timelineAttached, true, "a document is attached")
        compare(playhead.playing, false, "the stopped transport is published as not playing")

        var rollClip = testCase.playheadClip("sharedPlayheadRollClip")
        var rollPlot = findChild(testCase.surface, "timelineQuickRollPlot")
        verify(rollClip !== null && rollPlot !== null, "the composition mounted the roll segment")
        testCase.awaitPlayheadVisibility("sharedPlayheadRollClip", true)
        var plotOrigin = rollPlot.mapToItem(testCase.surface, 0, 0)
        var clipOrigin = rollClip.mapToItem(testCase.surface, 0, 0)
        compare(clipOrigin.x, plotOrigin.x - playhead.triangleHalfWidthPx,
                "the roll segment permits the ruler triangle overhang")
        compare(clipOrigin.y, plotOrigin.y, "the roll segment starts at the plot top")
        compare(rollClip.width, rollPlot.width + playhead.triangleHalfWidthPx,
                "the roll segment ends at the plot right edge")
        compare(rollClip.height, rollPlot.height, "the roll segment covers the plot height")
        compare(testCase.playheadSurfaceX("sharedPlayheadRollClip"), origin + playhead.contentX,
                "the roll line is the published projection from the shared origin")
        testCase.verifyPlayheadPixels("sharedPlayheadRollClip")

        // A second published position moves the drawn segment with it.
        var firstX = testCase.playheadSurfaceX("sharedPlayheadRollClip")
        testCase.presentPlayhead(16000, 0)
        tryVerify(function() {
            return testCase.playheadSurfaceX("sharedPlayheadRollClip") !== firstX
        }, 2000, "the drawn segment tracks the published position")
        fuzzyCompare(testCase.playheadSurfaceX("sharedPlayheadRollClip"),
                     origin + playhead.contentX, 0.01,
                     "the moved line is still the published projection")
        testCase.verifyPlayheadPixels("sharedPlayheadRollClip")

        var kinds = [testCase.velocityKind, testCase.voiceChangesKind, testCase.automationKind]
        var names = ["sharedPlayheadVelocityClip", "sharedPlayheadVoiceChangesClip",
                     "sharedPlayheadAutomationClip"]
        var barY = testCase.presenter().barY
        var drawerY = testCase.drawer().y
        for (var i = 0; i < kinds.length; ++i) {
            testCase.showSection(kinds[i])
            var state = testCase.section(kinds[i])
            var clip = testCase.playheadClip(names[i])
            verify(clip !== null, "the " + testCase.keyName(kinds[i]) + " segment exists")
            testCase.awaitPlayheadVisibility(names[i], true)
            fuzzyCompare(clip.x, origin, 0.01, "the body segment starts at the shared origin")
            fuzzyCompare(clip.y, drawerY + state.bodyY, 0.01,
                         "the body segment covers the published body")
            fuzzyCompare(clip.width, testCase.presenter().plotWidth, 0.01,
                         "the body segment clips to the shared plot width")
            fuzzyCompare(clip.height, state.bodyHeight, 0.01,
                         "the body segment covers the published body height")
            fuzzyCompare(testCase.playheadSurfaceX(names[i]), origin + playhead.contentX, 0.01,
                         "the body line reads the same projected position")
            verify(clip.y + clip.height <= drawerY + barY + 0.01,
                   "no body segment covers the drawer chrome")
            testCase.verifyPlayheadPixels(names[i])
        }

        // The half of the container left of the shared origin is the gutter: no
        // segment may occupy it, and a hidden body renders none at all.
        testCase.clickToggle(testCase.voiceChangesKind)
        testCase.awaitRenderedLayout()
        compare(testCase.section(testCase.voiceChangesKind).visible, false,
                "the section hides behind its toggle")
        testCase.awaitPlayheadVisibility("sharedPlayheadVoiceChangesClip", false)
        testCase.showSection(testCase.voiceChangesKind)
        testCase.awaitPlayheadVisibility("sharedPlayheadVoiceChangesClip", true)

        // Position-only updates publish positions: the grid's notes, the page
        // rectangles and the document stay exactly as they were.
        var summary = grid.noteSummary
        var notes = grid.renderedNoteCount
        var revision = grid.appliedRevisionText
        var heights = [testCase.section(testCase.velocityKind).bodyHeight,
                       testCase.section(testCase.voiceChangesKind).bodyHeight,
                       testCase.section(testCase.automationKind).bodyHeight]
        for (var step = 1; step <= 128; ++step)
            bootstrap.presentPlayheadObservation(step * 1000, 0)
        wait(0)
        compare(grid.noteSummary, summary, "playhead-only updates rebuild no grid content")
        compare(grid.renderedNoteCount, notes, "playhead-only updates render the same notes")
        compare(grid.appliedRevisionText, revision, "playhead-only updates apply no revision")
        compare([testCase.section(testCase.velocityKind).bodyHeight,
                 testCase.section(testCase.voiceChangesKind).bodyHeight,
                 testCase.section(testCase.automationKind).bodyHeight], heights,
                "playhead-only updates leave every page rectangle alone")
        compare(playhead.timelineAttached, true, "the position stays attached")
        tryVerify(function() {
            var presenter = testCase.playheadPresenter()
            var drawn = testCase.playheadClip("sharedPlayheadRollClip")
            return drawn.visible === presenter.visible
                && testCase.playheadSurfaceX("sharedPlayheadRollClip") === origin + presenter.contentX
        }, 2000, "the drawn segment catches up with the last published position")
        testCase.awaitRenderedLayout()
        compare(rollClip.x + playhead.triangleHalfWidthPx, testCase.surface.timelineSplitX,
                "the last position retains only the ruler triangle overhang")
    }

    // A camera change reprojects the retained authoritative tick, an
    // out-of-viewport projection draws nothing, and scrolling back renders the
    // same position again.
    function test_sharedPlayheadHidesOutOfViewportAndReprojects() {
        // This phase's own process: the production page keeps its slot in the lane's own run.
        if (testCase.productionPhase) skip("the container cases run in the lane's container child")

        var location = bootstrap.preferencesUrl("playhead-viewport")
        verify(testCase.attachPage(testCase.velocityKind), "the velocity page attaches")
        testCase.resetChrome(location, { "velocityVisible": true, "activePage": "velocity" })
        verify(bootstrap.pausePlayheadPolling(),
               "the lane holds the production polling task for a deterministic position")
        testCase.showSection(testCase.velocityKind)

        var playhead = testCase.playheadPresenter()
        var grid = testCase.surface.gridModel
        var origin = testCase.presenter().plotOrigin
        grid.resetCameraScroll()
        testCase.presentPlayhead(4000, 0)
        tryVerify(function() { return playhead.timelineAttached && playhead.visible }, 1000,
                  "the position starts attached and visible")
        var tick = playhead.tick
        var publishedX = playhead.contentX
        var parkedScroll = grid.cameraScrollX

        // The camera moves the projection past the plot origin: the same tick,
        // a hidden segment.
        grid.setCameraHScroll(parkedScroll + publishedX + 20)
        tryVerify(function() { return !playhead.visible }, 1000,
                  "a projection left of the plot is hidden")
        fuzzyCompare(playhead.tick, tick, 0.000001,
                     "a camera change reprojects the retained tick without moving it")
        testCase.awaitPlayheadVisibility("sharedPlayheadRollClip", false)
        testCase.awaitPlayheadVisibility("sharedPlayheadVelocityClip", false)

        // Scrolling back renders the same retained position.
        grid.setCameraHScroll(parkedScroll)
        tryVerify(function() { return playhead.visible }, 1000, "the position returns")
        fuzzyCompare(playhead.tick, tick, 0.000001, "the returned position is the same tick")
        testCase.awaitPlayheadVisibility("sharedPlayheadRollClip", true)
        fuzzyCompare(testCase.playheadSurfaceX("sharedPlayheadRollClip"), origin + playhead.contentX,
                     0.01, "the returned segment reads the reprojected position")
    }

    // The 85%/10% follow rule is suspended by every member of the aggregate: the
    // page's own interaction, a live drawer resize and a live roll gesture, each
    // driven through the production owners, with a real pointer.
    function test_sharedPlayheadSuspendsFollowForEveryInteraction() {
        // This phase's own process: the production page keeps its slot in the lane's own run.
        if (testCase.productionPhase) skip("the container cases run in the lane's container child")

        var location = bootstrap.preferencesUrl("playhead-follow")
        verify(testCase.attachPage(testCase.velocityKind), "the velocity page attaches")
        testCase.resetChrome(location, { "velocityVisible": true, "activePage": "velocity" })
        verify(bootstrap.pausePlayheadPolling(),
               "the lane holds the production polling task for a deterministic position")
        testCase.showSection(testCase.velocityKind)

        var playhead = testCase.playheadPresenter()
        var grid = testCase.surface.gridModel
        var kind = testCase.velocityKind
        // ApplicationSession.playPause()'s playing transport raw value.
        var playing = 2
        // A sample far past the viewport: the presenter resolves its tick, so the
        // lane performs no sample-to-tick arithmetic of its own.
        var farSample = 100000000
        grid.resetCameraScroll()
        var parked = grid.cameraScrollX

        testCase.presentPlayhead(farSample, playing)
        tryVerify(function() { return grid.cameraScrollX !== parked }, 1000,
                  "an idle aggregate lets follow scroll the camera")
        compare(playhead.playing, true, "the playing transport is published")

        // The page's own interaction.
        grid.setCameraHScroll(parked)
        verify(bootstrap.setTestSectionInteraction(kind, true), "the page owns an interaction")
        testCase.presentPlayhead(farSample, playing)
        compare(grid.cameraScrollX, parked, "a page interaction suspends follow")
        verify(bootstrap.setTestSectionInteraction(kind, false), "the page releases it")
        testCase.presentPlayhead(farSample, playing)
        tryVerify(function() { return grid.cameraScrollX !== parked }, 1000,
                  "releasing the page lets the next observation follow")

        // The container's own resize session, through real pointer input.
        grid.setCameraHScroll(parked)
        testCase.pressGrip(kind)
        testCase.dragGripTo(kind, testCase.dragSceneY - 20)
        testCase.presentPlayhead(farSample, playing)
        compare(grid.cameraScrollX, parked, "a live drawer resize suspends follow")
        testCase.releaseGrip(kind)
        testCase.presentPlayhead(farSample, playing)
        tryVerify(function() { return grid.cameraScrollX !== parked }, 1000,
                  "ending the resize lets the next observation follow")

        // The roll's own pointer gesture. The press is cancelled the way the
        // input item cancels an ungrabbed pointer, so no note is committed.
        grid.setCameraHScroll(parked)
        var rollInput = testCase.rollInput()
        mousePress(rollInput, rollInput.width / 2, rollInput.height / 2, Qt.LeftButton)
        testCase.presentPlayhead(farSample, playing)
        compare(grid.cameraScrollX, parked, "a live roll gesture suspends follow")
        testCase.surface.applicationSession.cancelGridInput(
            testCase.surface.cancelReasonPointerUngrabbed)
        mouseRelease(rollInput, rollInput.width / 2, rollInput.height / 2, Qt.LeftButton)
        testCase.presentPlayhead(farSample, playing)
        tryVerify(function() { return grid.cameraScrollX !== parked }, 1000,
                  "ending the gesture lets the next observation follow")

        // The retained position is the authoritative one throughout: the
        // presenter published every observation the lane presented.
        compare(playhead.timelineAttached, true, "the position stays attached")
        tryVerify(function() { return playhead.visible === false
                                        || testCase.playheadClip("sharedPlayheadRollClip").visible },
                  1000, "the drawn segment agrees with the published visibility")
    }

    // ---- the production Velocity page ---------------------------------------

    // Every named descendant, in tree order: the page publishes one node group
    // per note, so a case never assumes document order from a single lookup.
    function collectByName(item, name, found) {
        var collected = found || []
        if (!item)
            return collected
        if (item.objectName === name)
            collected.push(item)
        for (var i = 0; i < item.children.length; ++i)
            testCase.collectByName(item.children[i], name, collected)
        return collected
    }

    // ---- visible text contract ------------------------------------------

    // "Text doesn't show / button labels missing" presents as geometry that
    // is correct with ink that is not: a page on its transparent
    // fallbackPalette, or label strings the owner never published. No case
    // asserted ink before, so every production mount below audits it.
    function isEffectivelyVisible(item) {
        for (var current = item; current; current = current.parent) {
            if (!current.visible)
                return false
        }
        return true
    }

    // Every QQuickText under the root, in tree order. Text, TextInput and
    // TextEdit all expose text/color/font, but only the editors carry the
    // read-only `length`, so it admits exactly Text.
    function collectVisibleTexts(item, found) {
        var collected = found || []
        if (!item || !item.children)
            return collected
        if (item.text !== undefined && item.color !== undefined && item.font !== undefined
                && item.length === undefined && testCase.isEffectivelyVisible(item))
            collected.push(item)
        for (var i = 0; i < item.children.length; ++i)
            testCase.collectVisibleTexts(item.children[i], collected)
        return collected
    }

    // Every QQuickText under the root whether drawn or not: a control that is
    // legitimately hidden (the Detents button while detents are unavailable)
    // must still carry opaque ink and its label, so it appears correctly when
    // shown. Ink failures here trip on the transparent fallback too.
    function collectAllTexts(item, found) {
        var collected = found || []
        if (!item || !item.children)
            return collected
        if (item.text !== undefined && item.color !== undefined && item.font !== undefined
                && item.length === undefined)
            collected.push(item)
        for (var i = 0; i < item.children.length; ++i)
            testCase.collectAllTexts(item.children[i], collected)
        return collected
    }

    // The sign-off gate: the mounted composition drew text at all, and every
    // visible run carries opaque ink. Returns the runs for the label-content
    // assertions the case adds itself.
    function auditVisibleTextInk(root, what) {
        var texts = testCase.collectVisibleTexts(root, [])
        verify(texts.length > 0, what + ": the mounted composition drew text at all")
        for (var i = 0; i < texts.length; ++i) {
            verify(texts[i].color.a > 0,
                   what + ": opaque ink for '" + texts[i].objectName + "' ('"
                   + texts[i].text + "')")
        }
        return texts
    }

    function velocityPageItem() { return testCase.pageItem(testCase.velocityKind) }
    function velocityPlot() { return findChild(testCase.velocityPageItem(), "velocityPlot") }
    function velocityPlotInput() { return findChild(testCase.velocityPageItem(), "velocityPlotInput") }
    function velocityRuler() { return findChild(testCase.velocityPageItem(), "velocityRuler") }
    function velocityModel() { return testCase.surface.applicationSession.velocityPage() }

    /// The drawn node fills of the hosted page, in tree order.
    function velocityNodes() {
        return testCase.collectByName(testCase.velocityPlot(), "velocityNodeFill", [])
    }

    /// The notes the production grid publishes, parsed from its own summary.
    function gridNotes() {
        return JSON.parse(testCase.surface.gridModel.noteSummary)
    }

    /// The one note the production page's own selection holds, or -1. The page's
    /// projection is the live one: the grid's summary is only as fresh as the
    /// grid's last publication.
    function selectedNoteId() {
        var ids = bootstrap.velocitySelectedNoteIds()
        if (ids.length === 0 || ids.indexOf(",") >= 0)
            return -1
        return parseInt(ids, 10)
    }

    function noteVelocity(noteId) {
        var notes = testCase.gridNotes()
        for (var i = 0; i < notes.length; ++i) {
            if (notes[i].id === noteId)
                return notes[i].velocity
        }
        return -1
    }

    /// A real left press/release on one drawn node, which is the page's own
    /// selection path.
    function clickNode(node) {
        var input = testCase.velocityPlotInput()
        var center = node.mapToItem(input, node.width / 2, node.height / 2)
        mouseClick(input, center.x, center.y, Qt.LeftButton)
    }

    /// Attaches and shows the production Velocity page. Every wait is tied to the
    /// published or drawn property the case actually needs — the kind's
    /// availability, its visibility, the hosted item, then the drawn size and the
    /// nodes the page publishes for its own notes — instead of the container's
    /// whole-layout gate, which also observes unrelated chrome. A case therefore
    /// observes its own node state whatever the process has run before it.
    function mountProductionVelocity(location, values) {
        verify(bootstrap.attachProductionSection(testCase.velocityKind),
               "the production Velocity page attaches to its slot")
        testCase.resetChrome(location, values)
        tryVerify(function() {
            var toggle = testCase.toggle(testCase.velocityKind)
            return toggle !== null && toggle.width > 0
        }, 2000, "the published velocity toggle is drawn for the attached page (grid "
                  + (testCase.surface.gridModel !== null)
                  + ", presenterLayout=" + testCase.presenter().barHeight
                  + ", gutter=" + testCase.presenter().plotOrigin + ")")
        if (!testCase.section(testCase.velocityKind).visible)
            testCase.clickToggle(testCase.velocityKind)
        tryVerify(function() { return testCase.section(testCase.velocityKind).visible }, 2000,
                  "the velocity section is visible")
        tryVerify(function() { return testCase.velocityPageItem() !== null }, 2000,
                  "the drawer hosts the production page item")
        // The page pushes its drawn body to the owner, and the owner publishes the
        // handles that body projects. Waiting on those two drawn facts is what
        // makes a case's node reads its own state rather than a mount's timing.
        tryVerify(function() {
            var page = testCase.velocityPageItem()
            return page !== null && page.width > 0 && page.height > 0
        }, 2000, "the hosted production page took its drawn body size")
        tryVerify(function() { return testCase.velocityNodes().length > 0 }, 2000,
                  "the hosted production page drew a node per published handle ("
                  + testCase.velocityNodes().length + " drawn, selected "
                  + testCase.velocityModel().selectedCount + ")")
        return testCase.velocityPageItem()
    }

    function test_velocityHintsResumeAfterOutsideRelease() {
        if (testCase.containerPhase) skip("the production owner runs in its own process")
        testCase.mountProductionVelocity(bootstrap.preferencesUrl("velocity-hint-release"))
        var input = testCase.velocityPlotInput()
        var ruler = testCase.velocityRuler()
        var status = findChild(testCase.surface, "mouseHintStatus")
        var text = findChild(status, "mouseHintStatusText")
        verify(status && text, "the production status strip is drawn")
        tryCompare(testCase.surface, "hintWindowActive", true)
        mouseMove(status, status.width / 2, status.height / 2)
        tryCompare(text, "text", "")

        var x = input.width / 2
        var y = input.height / 2
        mouseMove(input, x, y)
        tryVerify(function() { return text.text.length > 0 }, 1000,
                  "the plot supplies instructions before the gesture")
        var plotInstructions = text.text
        mouseMove(ruler, ruler.width / 2, ruler.height / 2)
        tryVerify(function() {
            return text.text.length > 0 && text.text !== plotInstructions
        }, 1000, "the gutter advertises its different interaction")
        mouseMove(input, x, y)
        tryCompare(text, "text", plotInstructions)

        // Keep x fixed so the middle-button grab changes no camera position.
        var outside = input.mapFromItem(status, status.width / 2, status.height / 2)
        mousePress(input, x, y, Qt.MiddleButton)
        mouseMove(input, x, outside.y, -1, Qt.MiddleButton)
        mouseRelease(input, x, outside.y, Qt.MiddleButton)
        tryCompare(text, "text", "", 1000,
                   "an outside release retires the originating plot instructions")
        mouseMove(input, x, y)
        tryCompare(text, "text", plotInstructions, 1000,
                   "returning to the plot restores its instructions")
    }

    function test_automationHintsRetainGrabOrigin() {
        if (testCase.containerPhase) skip("the production owner runs in its own process")
        testCase.mountProductionAutomation(bootstrap.preferencesUrl("automation-hint-grab"))
        verify(testCase.writeVolumeLanePoints(bootstrap.automationVolumeIndex()))
        var node = testCase.automationLaneNodes()[testCase.automationWrittenNodeIndex()]
        var point = testCase.automationNodePoint(node)
        verify(point, "the written node has a drawn hit target")
        var input = testCase.automationPlotInput()
        var status = findChild(testCase.surface, "mouseHintStatus")
        var text = findChild(status, "mouseHintStatusText")
        verify(status && text, "the production status strip is drawn")
        tryCompare(testCase.surface, "hintWindowActive", true)
        mouseMove(status, status.width / 2, status.height / 2)
        tryCompare(text, "text", "")
        mouseMove(input, point.x, point.y)
        tryVerify(function() { return text.text.length > 0 }, 1000,
                  "the node advertises its interaction before the grab")
        var instructions = text.text
        var outside = input.mapFromItem(status, status.width / 2, status.height / 2)
        mousePress(input, point.x, point.y, Qt.MiddleButton)
        tryCompare(text, "text", instructions, 1000,
                   "starting a grab retains the originating node instructions")
        mouseMove(input, point.x, outside.y, -1, Qt.MiddleButton)
        compare(text.text, instructions, "the originating instructions survive outside motion")
        mouseRelease(input, point.x, outside.y, Qt.MiddleButton)
        tryCompare(text, "text", "", 1000, "outside release retires the originating instructions")
        mouseMove(input, point.x, point.y)
        tryCompare(text, "text", instructions, 1000, "re-entry restores node instructions")
    }

    /// Renders one reference pane and records its metadata. The observed facts
    /// must be the requested profile's, so a DPR or font mismatch fails here
    /// rather than in a reviewer's eye.
    function captureProfilePane(pane) {
        var page = testCase.velocityPageItem()
        var voicePage = testCase.voicePageItem()
        var target = pane === "editor-drawer" ? testCase.drawer()
                   : pane === "velocity-prompt"
                     ? findChild(page, "velocityPromptCard")
                   : pane === "voice-picker"
                     ? voicePage.modalHost
                   : pane === "automation-tabs"
                     ? testCase.pageItem(testCase.automationKind)
                   : pane === "track-headers"
                     ? findChild(testCase.surface, "timelineQuickTrackHeaders")
                   : page
        verify(target, pane + " exposes its actual drawn capture root")
        if (pane === "velocity-prompt") {
            var model = testCase.velocityModel()
            if (!model.promptOpen) {
                testCase.surface.applicationSession.performGridCommand(bootstrap.setVelocityCommand())
                wait(0)
            }
            if (!model.promptOpen)
                return false
        }
        if (pane === "automation-tabs") {
            // The reference pane is the production automation band: the selector,
            // a parameter lane with written events, its nodes and the readout. The
            // profile case has already mounted and shown the page.
            var automationPage = testCase.pageItem(testCase.automationKind)
            if (!automationPage)
                return false
            // A representative band: the Volume lane, with points written through
            // the production sweep so the reference carries a curve and nodes.
            var automationTab = bootstrap.automationVolumeIndex()
            if (automationTab >= 0)
                testCase.writeVolumeLanePoints(automationTab)
            tryVerify(function() {
                return findChild(automationPage, "automationPlot") !== null
            }, 2000, "the profile composition drew the automation plot")
            testCase.verifyAutomationLabelsFitGutter()
        }
        if (pane === "voice-picker") {
            var voice = testCase.voiceModel()
            if (!voice.pickerOpen) {
                var column = testCase.freeVoiceColumn(24)
                if (column >= 0)
                    testCase.doubleClickPlot(column)
                wait(0)
            }
            if (!voice.pickerOpen)
                return false
            testCase.awaitVoiceModal("voicePicker", true)
        }
        verify(waitForPolish(target.Window.window), pane + " completed layout before capture")
        var captureWidth = Math.floor(target.width)
        var captureHeight = Math.floor(target.height)
        var origin = target.mapToItem(testCase.surface, 0, 0)
        var url = bootstrap.profilePngUrl(pane)
        var saved = false
        target.grabToImage(function(result) { saved = result.saveToFile(url) })
        tryVerify(function() { return saved }, 5000, pane + " rendered a PNG")
        // The record names the production component and the exact pixel-backed
        // logical extent captured: the grab truncates logical bounds before DPR
        // scaling. The drawn root still identifies the pane's own production item.
        var recorded = bootstrap.writeProfileMetadata(pane, page.Screen.devicePixelRatio,
                                              pane === "voice-picker"
                                              ? testCase.voiceModel().baseFontPx
                                          : pane === "automation-tabs"
                                              ? testCase.automationModel().baseFontPx
                                          : pane === "track-headers"
                                              ? testCase.surface.gridModel.baseFontPx
                                              : testCase.velocityModel().baseFontPx,
                                              String(target.objectName),
                                              captureWidth, captureHeight,
                                              origin.x, origin.y,
                                              captureWidth, captureHeight)
        // Each original popup fixture retires its modal before the next case.
        // The next pane's input needs the drawn modal closed and its focus restored,
        // not merely the owner's promptOpen flag cleared.
        if (pane === "velocity-prompt") {
            testCase.velocityModel().cancelPrompt()
            testCase.awaitVoiceModal("velocityPrompt", false)
            wait(0)
        } else if (pane === "voice-picker") {
            testCase.voiceModel().cancelPicker()
            testCase.awaitVoiceModal("voicePicker", false)
        }
        return recorded
    }

    // The legacy fixture includes top chrome that EditorSurface does not host.
    // Reuse its band-local bounds at its original height, never its checked-in PNG.
    function captureTrackHeadersProfile() {
        var source = bootstrap.trackHeaderReferenceJson()
        verify(source.length > 0, "the checked-in track-header geometry is readable")
        var reference = JSON.parse(source)
        compare(reference.environment.fontPx, bootstrap.profileFontPx)
        compare(reference.image.dpr, bootstrap.profileDpr)
        var bandBounds = reference.regions.filter(function(region) {
            return region.name === "track-headers.band"
        })[0]
        var rowBounds = reference.regions.filter(function(region) {
            return region.name === "track-headers.rows"
        })[0]
        verify(bandBounds && rowBounds, "the reference names the band and row viewport")
        var band = findChild(testCase.surface, "timelineQuickTrackHeaders")
        var rows = findChild(band, "timelineTrackHeaderRows")
        verify(band && rows, "the mounted production band retains its automation identities")
        var originalHeight = testCase.surface.height
        try {
            // The drawer measures its own height against the surface it draws
            // in, and a section's stored height can still resolve after the
            // resize, so the band's height is re-aimed by its own residual
            // until it holds the reference height across an event-loop turn.
            for (var attempt = 0; attempt < 6; ++attempt) {
                testCase.surface.height += bandBounds.h - band.height
                testCase.surface.configureViewport()
                tryCompare(band, "height", bandBounds.h)
                wait(0)
                if (band.height === bandBounds.h)
                    break
            }
            compare(band.height, bandBounds.h,
                    "the band settled at the reference height")
            fuzzyCompare(band.width, Math.round(bootstrap.profileFontPx * 17.5), 0.01,
                         "headers retain their font-relative width (210 at 12, 280 at 16)")
            fuzzyCompare(band.width, bandBounds.w, 0.01, "band width matches the checked-in region")
            var origin = band.mapToItem(testCase.surface, 0, 0)
            fuzzyCompare(origin.x, bandBounds.x, 0.01, "the band starts at the left edge")
            compare(origin.y, testCase.surface.gridModel.rulerHeight, "the header band starts below the ruler")
            // The rows region includes the scrollbar, not just the narrower row delegates.
            var viewport = rows.parent.parent.parent
            var rowOrigin = viewport.mapToItem(band, 0, 0)
            fuzzyCompare(rowOrigin.x, rowBounds.x - bandBounds.x, 0.01)
            fuzzyCompare(rowOrigin.y, rowBounds.y - bandBounds.y, 0.01)
            fuzzyCompare(viewport.width, rowBounds.w, 0.01)
            fuzzyCompare(viewport.height, rowBounds.h, 0.01)
            tryVerify(function() { return rows.count > 1 }, 2000,
                      "the song draws track rows and its add-track row")
            for (var i = 0; i < rows.count; ++i) {
                var row = rows.itemAt(i)
                verify(row, "every header row is instantiated")
                fuzzyCompare(row.width + testCase.surface.headersModel.scrollbarWidth,
                             rowBounds.w, 0.01, "each row fills the width beside the scrollbar")
            }
            testCase.auditVisibleTextInk(band, "track headers")
            return testCase.captureProfilePane("track-headers")
        } finally {
            testCase.surface.height = originalHeight
            testCase.surface.configureViewport()
        }
    }

    // ---- production page cases ----------------------------------------------

    function test_quickSurfacePublishesAndRendersHeaders() {
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")
        testCase.resetChrome(bootstrap.preferencesUrl("track-header-surface"))
        var band = findChild(testCase.surface, "timelineQuickTrackHeaders")
        var input = findChild(band, "timelineTrackHeadersInput")
        var rows = findChild(band, "timelineTrackHeaderRows")
        var scrollbar = findChild(band, "timelineTrackHeaderScrollBar")
        verify(band && input && rows && scrollbar, "the production header surface is mounted")
        verify(band.visible && input.visible, "the header band and its input are visible")
        var origin = band.mapToItem(testCase.surface, 0, 0)
        compare(origin.x, 0, "the mounted header band: x")
        compare(origin.y, testCase.surface.gridModel.rulerHeight, "the mounted header band: y")
        compare(band.width, testCase.surface.headersModel.trackHeaderWidth,
                "the mounted header band: width")
        compare(band.height, testCase.rollBand().height - testCase.surface.gridModel.rulerHeight,
                "the mounted header band: height")
        fuzzyCompare(input.width + scrollbar.width, band.width, 0.01)
        fuzzyCompare(input.height, band.height, 0.01)
        fuzzyCompare(scrollbar.x, input.width, 0.01)
        tryVerify(function() { return rows.count > 1 }, 2000, "the song publishes its header rows")
        compare(testCase.surface.headersModel.contentHeight,
                rows.count * testCase.surface.headersModel.rowHeight)
        waitForRendering(band)
        var image = grabImage(testCase.surface)
        var row = rows.itemAt(0)
        var region = testCase.regionOf(image, testCase.surface, row)
        var fill = testCase.channelsOf(row.baseColor)
        var outline = testCase.channelsOf(testCase.surface.headersModel.appearance.buttonOutline)
        verify(fill.join(",") !== outline.join(","), "the row fill differs from its separator")
        compare(testCase.nearestPixel(image, region, fill).distance, 0,
                "the production row fill reaches the rendered image")
        compare(testCase.nearestPixel(image, region, outline).distance, 0,
                "the separator reaches the rendered image with distinct pixels")
    }

    function headerMeterPixels(row) {
        waitForRendering(row)
        var image = grabImage(testCase.surface)
        var origin = row.mapToItem(testCase.surface, 0, 0)
        var model = testCase.surface.headersModel
        var dpr = image.width / testCase.surface.width
        verify(dpr > 0, "the rendered meter has an observed DPR")
        var x0 = Math.round(origin.x * dpr)
        var y0 = Math.round(origin.y * dpr)
        var width = Math.round((origin.x + model.activityWidth) * dpr) - x0
        var height = Math.round((origin.y + model.rowHeight - model.separatorWidth) * dpr) - y0
        verify(width > 0 && height > 0, "the meter capture excludes the separator")
        var pixels = []
        for (var y = 0; y < height; ++y) {
            for (var x = 0; x < width; ++x) {
                compare(image.alpha(x0 + x, y0 + y), 255, "meter pixels remain opaque")
                pixels.push([image.red(x0 + x, y0 + y), image.green(x0 + x, y0 + y),
                             image.blue(x0 + x, y0 + y)].join(","))
            }
        }
        return { pixels: pixels, width: width, height: height, dpr: dpr }
    }

    function test_trackActivityRenderedMeterParity() {
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")
        testCase.resetChrome(bootstrap.preferencesUrl("track-header-activity"))
        bootstrap.pausePlayheadPolling()
        var band = findChild(testCase.surface, "timelineQuickTrackHeaders")
        var rows = findChild(band, "timelineTrackHeaderRows")
        verify(rows && rows.count > 1, "the real header has track rows")
        var row = rows.itemAt(0)
        var track = row.track
        verify(bootstrap.presentHeaderActivity(track, 0, 0, true))
        var silent = testCase.headerMeterPixels(row)
        verify(bootstrap.presentHeaderActivity(track, 255, 0, true))
        var leftOnly = testCase.headerMeterPixels(row)
        var expectedSpan = Math.round(row.activityLeftHeight * leftOnly.dpr)
        var leftColumn = Math.floor(leftOnly.width / 4)
        var observedSpan = 0
        for (var scanY = leftOnly.height - 1; scanY >= 0; --scanY) {
            var offset = scanY * leftOnly.width + leftColumn
            if (leftOnly.pixels[offset] === silent.pixels[offset]) break
            ++observedSpan
        }
        compare(row.activityRightHeight, 0, "left-only activity leaves the right meter dark")
        verify(row.activityLeftHeight > 0)
        verify(observedSpan >= Math.max(1, expectedSpan - 2),
               "rendered changed span reaches the published height at observed grab scale")
        verify(observedSpan <= expectedSpan + 2,
               "rendered changed span does not exceed the published height tolerance")
        verify(bootstrap.presentHeaderActivity(track, 128, 128, true))
        var active = testCase.headerMeterPixels(row)
        var height = testCase.surface.headersModel.rowHeight - testCase.surface.headersModel.separatorWidth
        function physical(level) { return Math.round(level / 255 * height * active.dpr) }
        var shared = 128
        while (shared < 255 && physical(shared) !== physical(shared + 1)) ++shared
        verify(shared < 255, "two adjacent levels share a physical pixel")
        verify(bootstrap.presentHeaderActivity(track, shared, shared, true))
        var within = testCase.headerMeterPixels(row)
        verify(bootstrap.presentHeaderActivity(track, shared + 1, shared + 1, true))
        var same = testCase.headerMeterPixels(row)
        compare(same.pixels, within.pixels, "levels within one physical pixel render identically")
        var across = shared + 2
        while (across < 255 && physical(across) <= physical(shared + 1)) ++across
        verify(across < 255, "a larger level crosses a physical pixel")
        verify(bootstrap.presentHeaderActivity(track, across, across, true))
        var changed = testCase.headerMeterPixels(row)
        verify(JSON.stringify(changed.pixels) !== JSON.stringify(within.pixels),
               "crossing a physical pixel changes the rendered meter")
        verify(bootstrap.presentHeaderActivity(track, 255, 64, true))
        var stereo = testCase.headerMeterPixels(row)
        var left = Math.floor(stereo.width / 4)
        var right = Math.floor(stereo.width * 3 / 4)
        var top = Math.floor(stereo.height / 8)
        verify(stereo.pixels[top * stereo.width + left] !== stereo.pixels[top * stereo.width + right],
               "stereo channel tops render different fill heights")
        compare(stereo.pixels[(stereo.height - 1) * stereo.width + left],
                stereo.pixels[(stereo.height - 1) * stereo.width + right],
                "stereo channels share their track identity at the bottom")
        verify(bootstrap.presentHeaderActivity(track, 0, 0, false))
        var paused = testCase.headerMeterPixels(row)
        compare(paused.width, active.width)
        compare(paused.height, active.height)
        compare(paused.dpr, active.dpr)
        var complete = 0
        var columns = [Math.floor(paused.width / 4), Math.floor(paused.width / 2),
                       Math.floor(paused.width * 3 / 4)]
        for (var index = 0; index < columns.length; ++index) {
            var column = columns[index]
            var bottom = paused.pixels[(paused.height - 1) * paused.width + column]
            var filled = 0
            for (var scan = paused.height - 1;
                 scan >= 0 && paused.pixels[scan * paused.width + column] === bottom; --scan) ++filled
            if (filled >= paused.height - 1) ++complete
        }
        verify(complete >= 2, "paused fill covers at least two complete meter columns")
        var probe = Math.floor(active.height / 4) * active.width + Math.floor(active.width / 4)
        verify(active.pixels[probe] !== paused.pixels[probe], "paused fill differs from active half level")
    }

    function test_headerVoiceChangeAltersRetainedRaster() {
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")
        testCase.resetChrome(bootstrap.preferencesUrl("track-header-voice-raster"))
        bootstrap.pausePlayheadPolling()
        var band = findChild(testCase.surface, "timelineQuickTrackHeaders")
        var rows = findChild(band, "timelineTrackHeaderRows")
        var input = findChild(band, "timelineTrackHeadersInput")
        verify(rows && input && rows.count > 1)
        testCase.surface.headersModel.scrollY = 0
        var row = rows.itemAt(0)
        var point = row.mapToItem(input, row.subtitleRect.x + row.subtitleRect.width / 2,
                                 row.subtitleRect.y + row.subtitleRect.height / 2)
        // Select before the reference capture so selection styling cannot supply
        // the image difference attributed to the changed voice subtitle.
        mouseClick(input, point.x, point.y, Qt.LeftButton)
        testCase.awaitRenderedLayout()
        var beforeSubtitle = row.subtitle
        var before = grabImage(testCase.surface)
        var region = testCase.regionOf(before, testCase.surface, row)
        var revision = bootstrap.automationDocumentRevision()
        mouseDoubleClickSequence(input, point.x, point.y, Qt.LeftButton)
        session.completeTrackHeaderVoiceRequest(127)
        tryVerify(function() { return bootstrap.automationDocumentRevision() !== revision }, 2000,
                  "the real voice picker completion writes the fixture program")
        tryVerify(function() { return row.subtitle !== beforeSubtitle }, 2000,
                  "the changed program publishes a new header subtitle")
        waitForRendering(row)
        var after = grabImage(testCase.surface)
        compare(after.width, before.width)
        compare(after.height, before.height)
        var differences = 0
        for (var y = region.y0; y <= region.y1; ++y) {
            for (var x = region.x0; x <= region.x1; ++x) {
                if (before.red(x, y) !== after.red(x, y)
                        || before.green(x, y) !== after.green(x, y)
                        || before.blue(x, y) !== after.blue(x, y)) ++differences
            }
        }
        verify(differences > 0, "the retained original header QML renders the changed subtitle")
        verify(bootstrap.requestAutomationUndo(), "the production undo completes through the Swift run loop")
        tryCompare(row, "subtitle", beforeSubtitle, 2000,
                   "undo restores the original program subtitle")
    }

    function test_hoveringHeadersDoesNotCreateTooltip() {
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")
        testCase.resetChrome(bootstrap.preferencesUrl("track-header-hover"))
        var band = findChild(testCase.surface, "timelineQuickTrackHeaders")
        var rows = findChild(band, "timelineTrackHeaderRows")
        var input = findChild(band, "timelineTrackHeadersInput")
        verify(rows && input, "the production header rows accept pointer input")
        tryVerify(function() { return rows.count > 1 }, 2000)
        var row = rows.itemAt(0)
        var point = row.mapToItem(input, row.titleRect.x + row.titleRect.width / 2,
                                 row.titleRect.y + row.titleRect.height / 2)
        mouseMove(input, point.x, point.y)
        wait(0)
        compare(findChild(testCase.surface, "timelineTrackHeaderToolTip"), null,
                "hovering a header title does not create a tooltip")
    }

    function test_headerCtrlScopeKeepsPrimaryAndRendersOverlay() {
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")
        testCase.resetChrome(bootstrap.preferencesUrl("track-header-scope"))
        bootstrap.pausePlayheadPolling()
        var band = findChild(testCase.surface, "timelineQuickTrackHeaders")
        var rows = findChild(band, "timelineTrackHeaderRows")
        var input = findChild(band, "timelineTrackHeadersInput")
        verify(rows && input && rows.count > 2, "fixture has two real header tracks")
        testCase.surface.headersModel.scrollY = 0
        var primary = rows.itemAt(0)
        var secondary = rows.itemAt(1)
        verify(!primary.isAddTrack && !secondary.isAddTrack)
        function point(row) {
            return row.mapToItem(input, row.titleRect.x + row.titleRect.width / 2,
                                  row.titleRect.y + row.titleRect.height / 2)
        }
        var first = point(primary)
        mouseClick(input, first.x, first.y, Qt.LeftButton)
        tryCompare(primary, "titleBold", true)
        compare(secondary.titleBold, false)
        compare(secondary.overlayColor.a, 0)
        var revision = bootstrap.automationDocumentRevision()
        var second = point(secondary)
        mouseClick(input, second.x, second.y, Qt.LeftButton, Qt.ControlModifier)
        tryVerify(function() { return secondary.overlayColor.a > 0 }, 1000,
                  "Ctrl-click paints the secondary selected-track overlay")
        compare(primary.titleBold, true, "Ctrl-click retains the original primary")
        compare(secondary.titleBold, false, "secondary track does not become primary")
        fuzzyCompare(secondary.overlayColor.a, 99 / 255, 0.001,
                     "secondary overlay retains the original alpha")
        waitForRendering(secondary)
        var image = grabImage(testCase.surface)
        var region = testCase.regionOf(image, testCase.surface, secondary)
        var background = testCase.channelsOf(secondary.baseColor)
        var overlay = testCase.channelsOf(secondary.overlayColor)
        var blended = background.map(function(value, index) {
            return Math.round(value * (1 - 99 / 255) + overlay[index] * 99 / 255)
        })
        verify(testCase.nearestPixel(image, region, blended).distance <= 1,
               "the original overlay primitive renders the secondary scope color")
        compare(bootstrap.automationDocumentRevision(), revision,
                "Ctrl scope is session-only and writes no document")
        mouseClick(input, second.x, second.y, Qt.LeftButton, Qt.ControlModifier)
        tryCompare(secondary, "overlayColor", "#00000000")
        compare(primary.titleBold, true, "removing secondary scope still retains primary")
        compare(bootstrap.automationDocumentRevision(), revision)
    }

    // The production page mounts through the real presenter and renders its own
    // composition: the shared gutter splits ruler and plot, every note of the
    // track publishes a node, and the axis ladder is drawn.
    function test_productionVelocityPageMountsAndRenders() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = bootstrap.preferencesUrl("production-velocity")
        var page = testCase.mountProductionVelocity(location)
        compare(String(testCase.section(testCase.velocityKind).contentUrl).length > 0, true,
                "the kind publishes the production page URL")

        var ruler = testCase.velocityRuler()
        var plot = testCase.velocityPlot()
        verify(ruler && plot, "the page composed its ruler and plot")
        fuzzyCompare(ruler.width, testCase.surface.timelineSplitX, 0.01,
                     "the ruler is the shared gutter column")
        fuzzyCompare(plot.x, ruler.width, 0.01, "the plot starts at the shared origin")
        fuzzyCompare(plot.width, page.width - ruler.width, 0.01,
                     "the plot spans the body beside the ruler")
        fuzzyCompare(plot.height, page.height, 0.01, "the plot spans the body height")

        var nodes = testCase.velocityNodes()
        compare(nodes.length, testCase.gridNotes().length,
                "every note of the primary track published a node")
        verify(testCase.collectByName(ruler, "velocityTick", []).length
                   + testCase.collectByName(ruler, "velocityGraduation", []).length > 0,
               "the ruler rendered its value ladder")
        var detent = findChild(testCase.drawer(), "drawerDetent")
        verify(detent, "the drawer composed its original detent control")
        compare(detent.Accessible.role, Accessible.CheckBox, "the original detent control is a checkbox")
        compare(detent.Accessible.checkable, true, "the detent control is checkable")
        compare(detent.Accessible.checked, testCase.velocityModel().detentsEnabled,
                "the detent control shows the page's own preference")
        if (testCase.isEffectivelyVisible(detent) && detent.enabled) {
            var enabledBefore = testCase.velocityModel().detentsEnabled
            mouseClick(detent, detent.width / 2, detent.height / 2, Qt.LeftButton)
            compare(testCase.velocityModel().detentsEnabled, !enabledBefore,
                    "the drawer control toggles the velocity preference")
            mouseClick(detent, detent.width / 2, detent.height / 2, Qt.LeftButton)
            compare(testCase.velocityModel().detentsEnabled, enabledBefore)
        }
        testCase.auditVisibleTextInk(page, "velocity page")
    }

    function test_productionDrawerBlankBarFocus() {
        if (testCase.containerPhase) skip("production composition only")
        var location = bootstrap.preferencesUrl("drawer-blank-focus")
        testCase.mountProductionVelocity(location)
        testCase.focusControl(testCase.rollInput())
        var before = testCase.snapshotStore(location)
        var revision = bootstrap.automationDocumentRevision()
        var bar = testCase.bar()
        mouseClick(bar, bar.width - 3, bar.height / 2, Qt.LeftButton)
        tryVerify(function() { return testCase.drawer().activeFocus }, 1000,
                  "blank drawer chrome takes focus from the roll")
        compare(bootstrap.automationDocumentRevision(), revision,
                "blank chrome does not execute a document command")
        testCase.compareSnapshots(testCase.snapshotStore(location), before,
                                  "blank chrome changes no section preference")
    }

    // Real pointer input on the drawn nodes: a selection click, then a vertical
    // drag that previews and commits exactly one document transaction.
    function test_productionVelocityPointerEdit() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = bootstrap.preferencesUrl("production-velocity-pointer")
        testCase.mountProductionVelocity(location)
        var nodes = testCase.velocityNodes()
        verify(nodes.length > 0, "the page drew at least one node")
        var notes = testCase.gridNotes()
        compare(notes.length > 0, true, "the grid published its notes")

        var input = testCase.velocityPlotInput()
        var node = nodes[0]
        var center = node.mapToItem(input, node.width / 2, node.height / 2)
        mouseClick(input, center.x, center.y, Qt.LeftButton)
        tryVerify(function() { return testCase.velocityModel().selectedCount === 1 },
                  1000, "a node click selected exactly its own note")

        var targetId = testCase.selectedNoteId()
        verify(targetId >= 0, "the click left one note selected in the grid's own summary")
        var before = testCase.noteVelocity(targetId)
        var raised = center.y - 24
        mousePress(input, center.x, center.y, Qt.LeftButton)
        mouseMove(input, center.x, raised, -1, Qt.LeftButton)
        compare(testCase.velocityModel().interactionActive, true,
                "a live drag reports an active interaction to the container")
        mouseRelease(input, center.x, raised, Qt.LeftButton)
        tryVerify(function() {
            return testCase.noteVelocity(targetId) !== before
        }, 1000, "the released drag committed one velocity change")
        compare(testCase.velocityModel().interactionActive, false,
                "the release ended the page's interaction")
    }

    // The existing Set Velocity command opens the page's captured prompt, the
    // field accepts a typed value into one transaction, and both the Escape and
    // outside-dismissal paths close it without a write.
    function test_productionVelocityPromptTransaction() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = bootstrap.preferencesUrl("production-velocity-prompt")
        testCase.mountProductionVelocity(location)
        var nodes = testCase.velocityNodes()
        verify(nodes.length > 0, "the page drew at least one node")
        testCase.clickNode(nodes[0])
        var model = testCase.velocityModel()
        tryVerify(function() { return model.selectedCount === 1 }, 1000,
                  "the prompt case starts from one selected note")
        var noteId = testCase.selectedNoteId()
        verify(noteId >= 0, "the prompt case acts on the grid's selected note")
        var before = testCase.noteVelocity(noteId)

        testCase.surface.applicationSession.performGridCommand(bootstrap.setVelocityCommand())
        tryVerify(function() { return model.promptOpen }, 1000,
                  "the Set Velocity command opened the page's prompt")
        var field = findChild(testCase.velocityPageItem(), "noteVelocityInput")
        verify(field, "the prompt composed its text field")
        tryVerify(function() { return field.activeFocus }, 1000,
                  "the prompt took active focus in its field")
        var velocityCard = findChild(testCase.surface, "velocityPromptCard")
        verify(velocityCard, "the prompt composed its card")
        var base = model.baseFontPx
        compare(velocityCard.appearance.font.pixelSize, Math.round(base),
                "the original velocity prompt follows application typography")
        compare(velocityCard.appearance.dialogPadding, Math.max(1, Math.round(base * 0.25)))
        compare(velocityCard.appearance.verticalPadding, Math.max(1, Math.round(base * 0.125)))
        compare(velocityCard.appearance.radius, Math.max(1, Math.round(base * 0.125)))
        compare(velocityCard.appearance.dragThreshold, base)
        compare(velocityCard.appearance.background, testCase.velocityPageItem().gridPalette.windowBackground,
                "the original prompt binds the live window theme role")
        compare(String(findChild(velocityCard, "velocityPromptTitle").text).length > 0, true,
                "the prompt draws its title")
        var velocityCardLabels = testCase.collectVisibleTexts(velocityCard, []).map(function(t) { return t.text })
        verify(velocityCardLabels.indexOf("OK") >= 0, "the prompt draws its OK label")
        verify(velocityCardLabels.indexOf("Cancel") >= 0, "the prompt draws its Cancel label")
        testCase.auditVisibleTextInk(velocityCard, "velocity prompt")
        compare(field.text, String(before), "the prompt opened with the captured value")
        keyClick(Qt.Key_9)
        wait(0)
        compare(field.text, "9", "typing replaced the selected numeric text")
        compare(testCase.noteVelocity(noteId), before, "typing committed nothing")
        keyClick(Qt.Key_Return)
        tryVerify(function() { return !model.promptOpen }, 1000, "Enter accepted the prompt")
        tryVerify(function() { return testCase.noteVelocity(noteId) === 9 }, 1000,
                  "the accepted value reached the captured note")

        // Escape cancels with no write.
        var accepted = testCase.noteVelocity(noteId)
        testCase.surface.applicationSession.performGridCommand(bootstrap.setVelocityCommand())
        tryVerify(function() { return model.promptOpen }, 1000, "the prompt reopened")
        keyClick(Qt.Key_Escape)
        tryVerify(function() { return !model.promptOpen }, 1000, "Escape closed the prompt")
        compare(testCase.noteVelocity(noteId), accepted, "Escape wrote nothing")

        // An outside press dismisses without a write. The probe lands in an
        // empty plot column, so a leak past the underlay would be visible as a
        // paint rather than hidden by the ruler's click-to-set.
        testCase.surface.applicationSession.performGridCommand(bootstrap.setVelocityCommand())
        tryVerify(function() { return model.promptOpen }, 1000, "the prompt reopened")
        var underlay = findChild(testCase.velocityPageItem(), "velocityPromptUnderlay")
        verify(underlay, "the prompt composed its dismissing underlay")
        var empty = underlay.mapFromItem(testCase.velocityPlot(),
                                         testCase.velocityPlot().width - 4,
                                         testCase.velocityPlot().height - 4)
        mouseClick(underlay, empty.x, empty.y, Qt.LeftButton)
        tryVerify(function() { return !model.promptOpen }, 1000,
                  "an outside press dismissed the prompt")
        compare(testCase.noteVelocity(noteId), accepted, "the outside dismissal wrote nothing")
    }

    function test_productionVelocityNumericInput() {
        if (testCase.containerPhase) skip("production composition only")
        testCase.mountProductionVelocity(bootstrap.preferencesUrl("velocity-numeric-input"))
        testCase.clickNode(testCase.velocityNodes()[0])
        var noteId = testCase.selectedNoteId()
        var before = testCase.noteVelocity(noteId)
        session.performGridCommand(bootstrap.setVelocityCommand())
        var model = testCase.velocityModel()
        tryVerify(function() { return model.promptOpen }, 1000)
        var field = findChild(testCase.surface, "noteVelocityInput")
        var accept = findChild(testCase.surface, "noteVelocityAccept")
        var cancel = findChild(testCase.surface, "noteVelocityCancel")
        verify(field && accept && cancel, "the original numeric form is drawn")
        tryVerify(function() { return field.activeFocus }, 1000)
        keyClick(Qt.Key_5)
        keyClick(Qt.Key_0)
        keyClick(Qt.Key_Tab)
        compare(accept.activeFocus, true)
        compare(field.text, "50")
        keyClick(Qt.Key_Tab)
        compare(cancel.activeFocus, true)
        keyClick(Qt.Key_Tab)
        compare(field.activeFocus, true)
        var reverse = [cancel, accept, field]
        for (var i = 0; i < reverse.length; ++i) {
            keyClick(Qt.Key_Backtab, Qt.ShiftModifier)
            compare(reverse[i].activeFocus, true)
        }
        keyClick(Qt.Key_Up)
        compare(field.text, "51")
        keyClick(Qt.Key_Down, Qt.ControlModifier)
        compare(field.text, "41")
        keyClick(Qt.Key_PageUp)
        compare(field.text, "51")
        keyClick(Qt.Key_PageDown)
        compare(field.text, "41")
        mouseWheel(field, field.width / 2, field.height / 2, 0, 60, Qt.NoButton)
        compare(field.text, "41", "a half-notch is retained, not rounded")
        mouseWheel(field, field.width / 2, field.height / 2, 0, 60, Qt.NoButton)
        tryCompare(field, "text", "42", 1000)
        mouseWheel(field, field.width / 2, field.height / 2, 0, 120,
                   Qt.NoButton, Qt.ControlModifier)
        tryCompare(field, "text", "52", 1000, "Control wheel steps by ten")
        var threshold = field.parent.appearance.dragThreshold
        var x = field.width / 2
        var y = field.height / 2
        mousePress(field, x, y, Qt.LeftButton)
        mouseMove(field, x, y - threshold + 1, -1, Qt.LeftButton)
        compare(field.text, "52", "motion below the scrub threshold writes nothing")
        mouseMove(field, x, y - threshold - 30, -1, Qt.LeftButton)
        mouseRelease(field, x, y - threshold - 30, Qt.LeftButton)
        tryCompare(field, "text", "67", 1000, "normal scrub accumulates half a step per pixel")
        mousePress(field, x, y, Qt.LeftButton, Qt.ShiftModifier)
        mouseMove(field, x, y - threshold - 30, -1, Qt.LeftButton, Qt.ShiftModifier)
        mouseRelease(field, x, y - threshold - 30, Qt.LeftButton, Qt.ShiftModifier)
        tryCompare(field, "text", "73", 1000, "Shift scrub accumulates one fifth step per pixel")
        compare(testCase.noteVelocity(noteId), before, "numeric interaction remains a draft")
        keyClick(Qt.Key_Return)
        tryVerify(function() { return !model.promptOpen }, 1000)
        compare(testCase.noteVelocity(noteId), 73, "acceptance commits the scrubbed draft")
    }

    // Hiding the section cancels the page's live gesture without a write, and a
    // stale document change cancels instead of retargeting.
    function test_productionVelocityCancellation() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = bootstrap.preferencesUrl("production-velocity-cancel")
        testCase.mountProductionVelocity(location)
        var nodes = testCase.velocityNodes()
        verify(nodes.length > 0, "the page drew at least one node")
        var input = testCase.velocityPlotInput()
        var node = nodes[0]
        var center = node.mapToItem(input, node.width / 2, node.height / 2)
        mousePress(input, center.x, center.y, Qt.LeftButton)
        mouseMove(input, center.x, center.y - 24, -1, Qt.LeftButton)
        var model = testCase.velocityModel()
        compare(model.interactionActive, true, "the gesture is live before the hide")
        var selected = model.selectedCount
        compare(selected > 0, true, "the gesture owns a selection")

        // The container's own hide path cancels the page synchronously.
        testCase.clickToggle(testCase.velocityKind)
        tryVerify(function() { return !testCase.section(testCase.velocityKind).visible }, 1000,
                  "the section hid")
        compare(model.interactionActive, false, "hiding the section cancelled the gesture")
        mouseRelease(input, center.x, center.y - 24, Qt.LeftButton)
        compare(model.interactionActive, false, "the released pointer committed nothing")
        testCase.clickToggle(testCase.velocityKind)
        tryVerify(function() { return testCase.section(testCase.velocityKind).visible }, 1000,
                  "the section is visible again")
    }

    // The shared playhead: 128 distinct presentations inside one voice context
    // rebuild no static velocity content, and every published presentation reaches
    // the page's diagnostics through the session's own Swift fan-out. The case
    // waits on those published facts with the suite's bounded settle pattern
    // instead of assuming how many event-loop passes the delivery took.
    function test_productionVelocityPlayheadPerformance() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = bootstrap.preferencesUrl("production-velocity-playhead")
        testCase.mountProductionVelocity(location)
        verify(bootstrap.pausePlayheadPolling(),
               "the lane holds the production polling task for determinism")
        // Warm up the playing context first: the stopped context resolves at the
        // edit cursor, so the first playing presentation may legitimately cross
        // into the span the loop then measures inside of. The Swift-owned
        // observation entry is the production drive: the session's fan-out reaches
        // the page inside this call, so the loop needs no event-loop sleeps.
        bootstrap.presentPlayheadObservation(1000, 2)
        var builds = bootstrap.velocityContentBuilds()
        var presented = bootstrap.velocityPlayheadPresentations()
        var published = bootstrap.publishedPlayheadPresentations()
        var slot = bootstrap.velocityPresentedSlot()
        // 128 distinct shared ticks, one per presentation: the presenter publishes
        // every one of them and the page consumes every publication.
        var updates = 128
        for (var step = 1; step <= updates; ++step)
            bootstrap.presentPlayheadObservation((1 + step) * 1000, 2)
        var expected = published + updates
        tryVerify(function() {
            return bootstrap.publishedPlayheadPresentations() === expected
        }, 2000, "the presenter published all " + updates + " shared presentations ("
                  + (bootstrap.publishedPlayheadPresentations() - published) + ")")
        tryVerify(function() {
            return bootstrap.velocityPlayheadPresentations() === presented + updates
        }, 2000, "every published presentation reached the page's diagnostics (page "
                  + (bootstrap.velocityPlayheadPresentations() - presented) + ", presenter "
                  + (bootstrap.publishedPlayheadPresentations() - published) + ")")
        compare(bootstrap.velocityPresentedSlot(), slot,
                "every presented tick stayed inside its own voice context")
        compare(bootstrap.velocityContentBuilds(), builds,
                "128 shared-playhead presentations rebuilt no velocity content")
    }

    // The page's unsupported-context diagnostic: the staged fixture's programs
    // are parsed top-level voices, so the page must be editing exactly.
    function test_productionVelocityContextIsExact() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = bootstrap.preferencesUrl("production-velocity-context")
        testCase.mountProductionVelocity(location)
        compare(bootstrap.velocityContextUnsupported(), false,
                "the staged fixture resolves an exact top-level map")
        compare(testCase.velocityModel().contextDiagnostic, "",
                "an exact context publishes no diagnostic")
    }

    // ---- the production Automation page -------------------------------------

    function automationPageItem() { return testCase.pageItem(testCase.automationKind) }
    function automationModel() { return testCase.surface.applicationSession.automationPage() }
    function automationGutter() { return findChild(testCase.automationPageItem(), "automationGutter") }
    function automationPlot() { return findChild(testCase.automationPageItem(), "automationPlot") }
    function automationPlotInput() {
        return findChild(testCase.automationPageItem(), "automationPlotInput")
    }

    /// Every named descendant whose objectName is exactly one of `names`, in tree
    /// walk order. The page's own primitives carry child names that extend their
    /// parent's, so an exact match is what keeps a tab's label out of the tab
    /// count and a node's ring out of the node count.
    function collectByNames(item, names, found) {
        var collected = found || []
        if (!item)
            return collected
        if (names.indexOf(String(item.objectName)) >= 0)
            collected.push(item)
        for (var i = 0; i < item.children.length; ++i)
            testCase.collectByNames(item.children[i], names, collected)
        return collected
    }

    /// The drawn selector tabs of the hosted page, in tree order.
    function automationTabItems() {
        return testCase.collectByNames(testCase.automationPageItem(),
                                       testCase.automationTabNames(), [])
    }

    function automationTabNames() {
        var names = []
        var count = testCase.automationModel().tabCount
        for (var i = 0; i < count; ++i)
            names.push("automationParameterTab" + i)
        return names
    }

    /// The drawn node markers of the hosted page, in tree order.
    function automationNodeItems() {
        return testCase.collectByNames(testCase.automationPageItem(),
                                       ["automationNode", "automationNodePhantom"], [])
    }

    /// The drawn curve runs, in tree order: ghost runs first, the active curve
    /// second, exactly as the page publishes them.
    function automationCurveItems() {
        return testCase.collectByNames(testCase.automationPageItem(),
                                       ["automationCurve", "automationGhostCurve"], [])
    }

    /// The drawn ramps, in tree order.
    function automationRampItems() {
        return testCase.collectByNames(testCase.automationPageItem(),
                                       ["automationRamp", "automationGhostRamp"], [])
    }

    /// The drawn menu rows of the *open* menu, and the separators beside them: a
    /// closed menu keeps its last delegates in the tree, and a stale delegate is
    /// not a row a case may click.
    function automationMenuRowItems() {
        var root = findChild(testCase.surface, "automationMenu")
        if (!root || root.visible !== true)
            return []
        return testCase.collectByPrefix(root, "automationMenuRow_", []).filter(function(row) {
            return !row.model.separator
        })
    }

    // Like the original quick_popup driver: resolve the current typed row in
    // its owning panel, not through the editor's pre-modal visual subtree.
    function menuRowByAction(panel, actionId) {
        if (!panel) return null
        for (var i = 0; i < panel.rowCount; ++i) {
            var row = panel.rowItem(i)
            if (row && row.model.actionId === actionId) return row
        }
        return null
    }

    function automationMenuSeparatorItems() {
        var root = findChild(testCase.surface, "automationMenu")
        if (!root || root.visible !== true)
            return []
        return testCase.collectByPrefix(root, "automationMenuRow_", []).filter(function(row) {
            return row.model.separator
        })
    }

    /// Attaches and shows the production Automation page. Every wait is tied to
    /// the drawn or published fact the case needs — the kind's availability, its
    /// visibility, the hosted item and its drawn size, then the selector and the
    /// readout the page composes — so a case observes its own state whatever ran
    /// before it.
    function mountProductionAutomation(location, values) {
        verify(bootstrap.attachProductionSection(testCase.automationKind),
               "the production Automation page attaches to its slot")
        // The camera is shared with every page, so a mounted case starts from the
        // lane's own park instead of inheriting wherever another case left it.
        testCase.surface.gridModel.resetCameraScroll()
        testCase.resetChrome(location, values)
        tryVerify(function() {
            var toggle = testCase.toggle(testCase.automationKind)
            return toggle !== null && toggle.width > 0
        }, 2000, "the published automation toggle is drawn for the attached page")
        if (!testCase.section(testCase.automationKind).visible)
            testCase.clickToggle(testCase.automationKind)
        tryVerify(function() { return testCase.section(testCase.automationKind).visible }, 2000,
                  "the automation section is visible")
        tryVerify(function() { return testCase.automationPageItem() !== null }, 2000,
                  "the drawer hosts the production Automation page item")
        tryVerify(function() {
            var page = testCase.automationPageItem()
            return page !== null && page.width > 0 && page.height > 0
        }, 2000, "the hosted production page took its drawn body size")
        tryVerify(function() {
            return testCase.automationTabItems().length
                   === testCase.automationModel().tabCount
        }, 2000, "the page drew one selector tab per published catalog parameter"
                  + testCase.automationBridgeDiagnostics())
        return testCase.automationPageItem()
    }

    /// What the hosted page's own QML really sees of the published owner, so a
    /// bridge gap names itself instead of only failing a count.
    function automationBridgeDiagnostics() {
        var page = testCase.automationPageItem()
        var lines = ["drawnTabs=" + testCase.automationTabItems().length,
                     "publishedTabs=" + testCase.automationModel().tabCount]
        if (page) {
            lines.push("pageModel=" + (typeof page.pageModel))
            lines.push("qmlTabs=" + (page.pageModel ? typeof page.pageModel.tabs : "n/a"))
            lines.push("qmlTabCount=" + (page.pageModel ? page.pageModel.tabCount : -1))
            lines.push("qmlNodeCount=" + (page.pageModel ? page.pageModel.nodeCount : -1))
            lines.push("drawnTabs=" + page.selectorTabCount)
        }
        return " (" + lines.join("; ") + ")"
    }

    /// One drawn tab by its published index, or null.
    function automationTab(index) {
        var tabs = testCase.automationTabItems()
        for (var i = 0; i < tabs.length; ++i) {
            if (tabs[i].objectName === "automationParameterTab" + index)
                return tabs[i]
        }
        return null
    }

    /// The labels of the drawn tabs, in tree order, so a case compares the
    /// selector it can see against the catalog the page published.
    function drawnAutomationTabLabels() {
        var labels = []
        var texts = testCase.collectByNames(testCase.automationPageItem(),
                                           ["automationParameterTabText"], [])
        for (var i = 0; i < texts.length; ++i)
            labels.push(texts[i].text)
        return labels.join(",")
    }

    function verifyAutomationLabelsFitGutter() {
        var gutter = testCase.automationGutter()
        var scroller = findChild(gutter, "automationTabsScroller")
        verify(gutter && scroller, "the selector exposes its gutter and clipped scroller")
        fuzzyCompare(gutter.width, testCase.surface.timelineSplitX, 0.01,
                     "the label gutter includes the track headers and keyboard")
        fuzzyCompare(gutter.width, testCase.surface.headersModel.trackHeaderWidth
                                   + testCase.surface.gridModel.keyboardWidth, 0.01)
        var labels = bootstrap.automationTabLabels().split(",")
        var tabs = testCase.automationTabItems()
        compare(tabs.length, labels.length, "every catalog label has a tab")
        var previousScroll = scroller.contentY
        try {
            scroller.contentY = 0
            var bounds = []
            for (var i = 0; i < labels.length; ++i) {
                var tab = testCase.automationTab(i)
                verify(tab && tab.width > 0 && tab.height > 0, "the parameter tab has bounds")
                var origin = tab.mapToItem(gutter, 0, 0)
                verify(origin.x >= -0.5 && origin.x + tab.width <= gutter.width + 0.5,
                       "parameter " + labels[i] + " stays inside the widened gutter")
                var text = findChild(tab, "automationParameterTabText")
                verify(text, "the parameter tab has its production Text item")
                compare(text.text, labels[i])
                verify(text.contentWidth > 0 && text.contentHeight > 0,
                       "the parameter label has rendered ink")
                verify(text.contentWidth <= text.width + 0.5
                       && text.contentHeight <= text.height + 0.5,
                       labels[i] + " fits without clipping its rendered text")
                var textOrigin = text.mapToItem(tab, 0, 0)
                verify(textOrigin.x >= -0.5 && textOrigin.x + text.width <= tab.width + 0.5,
                       labels[i] + " text remains inside its own tab")
                var center = { x: origin.x + tab.width / 2, y: origin.y + tab.height / 2 }
                for (var j = 0; j < bounds.length; ++j)
                    verify(Math.abs(center.x - bounds[j].x) > 0.5
                           || Math.abs(center.y - bounds[j].y) > 0.5,
                           "parameter tabs do not overlap at one center")
                bounds.push(center)
            }
            for (var pair = 0; pair + 1 < labels.length - 1; pair += 2)
                fuzzyCompare(bounds[pair].y, bounds[pair + 1].y, 0.5,
                             "related controller pairs share a row")
            var tempo = testCase.automationTab(labels.length - 1)
            var left = testCase.automationTab(0)
            var right = testCase.automationTab(1)
            fuzzyCompare(tempo.x, left.x, 0.01, "Tempo shares the first column's left edge")
            fuzzyCompare(tempo.x + tempo.width, right.x + right.width, 0.01,
                         "Tempo spans both columns")
            verify(bounds[bounds.length - 1].y > bounds[bounds.length - 2].y,
                   "Tempo closes the selector below the controllers")
            compare(scroller.clip, true, "the selector clips its scrolling content")
        } finally {
            scroller.contentY = previousScroll
        }
    }

    function test_parameterLabelsFitGutterAtDerivedMinimum_data() {
        return [{ tag: "font12", fontPx: 12 }, { tag: "font16", fontPx: 16 }]
    }

    function test_parameterLabelsFitGutterAtDerivedMinimum(data) {
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")
        var previousFont = testCase.surface.gridModel.baseFontPx
        try {
            testCase.surface.gridModel.baseFontPx = data.fontPx
            testCase.surface.configureViewport()
            testCase.mountProductionAutomation(bootstrap.preferencesUrl("automation-labels-" + data.tag),
                                               { "automationVisible": true, "automationHeight": 1 })
            var gutter = testCase.automationGutter()
            verify(gutter.height > 1, "the requested height is clamped to the derived minimum")
            var minimum = gutter.height
            testCase.pressGrip(testCase.automationKind)
            testCase.dragGripTo(testCase.automationKind, testCase.dragSceneY + testCase.surface.height)
            testCase.releaseGrip(testCase.automationKind)
            fuzzyCompare(gutter.height, minimum, 0.01, "further shrinking keeps the derived minimum")
            testCase.verifyAutomationLabelsFitGutter()
            var scroller = findChild(gutter, "automationTabsScroller")
            verify(scroller.contentHeight > scroller.height, "the catalog scrolls at minimum height")
            scroller.contentY = 0
            var first = testCase.automationTab(0)
            var firstOrigin = first.mapToItem(scroller, 0, 0)
            verify(firstOrigin.y >= -0.5 && firstOrigin.y + first.height <= scroller.height + 0.5,
                   "the first parameter is visible at the content top")
            scroller.contentY = scroller.contentHeight - scroller.height
            var last = testCase.automationTab(testCase.automationModel().tabCount - 1)
            var lastOrigin = last.mapToItem(scroller, 0, 0)
            verify(lastOrigin.y >= -0.5 && lastOrigin.y + last.height <= scroller.height + 0.5,
                   "Tempo is visible at the content bottom")
        } finally {
            testCase.surface.gridModel.baseFontPx = previousFont
            testCase.surface.configureViewport()
        }
    }

    /// The drawn tab that reports itself checked, or null.
    function drawnAutomationActiveTab() {
        var tabs = testCase.automationTabItems()
        for (var i = 0; i < tabs.length; ++i) {
            if (tabs[i].Accessible.selected)
                return tabs[i]
        }
        return null
    }

    /// The tab index of the first per-track parameter whose lane carries written
    /// events in the staged song, or -1. The selector's event pip is the drawn
    /// oracle for the same fact.
    function automationTabWithEvents() { return bootstrap.automationTabWithEvents() }

    /// The tab index of the first per-track parameter whose lane is empty.
    function automationEmptyTab() { return bootstrap.automationEmptyTab() }

    /// One real click on a drawn selector tab, in its label area: the Tempo row
    /// overlays its own Tap control on the tab's right edge, and the production
    /// row is the whole control either way.
    function revealAutomationTab(index) {
        var tab = testCase.automationTab(index)
        verify(tab, "the selector drew tab " + index)
        if (tab.activeFocus)
            testCase.focusControl(testCase.automationPlot())
        testCase.focusControl(tab)
        var scroller = findChild(testCase.automationGutter(), "automationTabsScroller")
        tryVerify(function() {
            var origin = tab.mapToItem(scroller, 0, 0)
            return origin.y >= 0 && origin.y + tab.height <= scroller.height
        }, 1000, "keyboard focus minimally reveals the whole parameter control")
        return tab
    }

    function clickAutomationTab(index, modifiers) {
        var tab = testCase.revealAutomationTab(index)
        verify(tab, "the selector drew tab " + index)
        mouseClick(tab, tab.width * 0.2, tab.height / 2, Qt.LeftButton,
                   modifiers === undefined ? Qt.NoModifier : modifiers)
    }

    /// Control-press on a drawn tab: the production ghost toggle entry.
    function pressAutomationTabWithControl(index) {
        var tab = testCase.revealAutomationTab(index)
        verify(tab, "the selector drew tab " + index)
        mouseClick(tab, tab.width * 0.2, tab.height / 2, Qt.LeftButton, Qt.ControlModifier)
    }

    /// One real right press on a drawn tab: the production context request.
    function rightClickAutomationTab(index) {
        var tab = testCase.revealAutomationTab(index)
        verify(tab, "the selector drew tab " + index)
        mouseClick(tab, tab.width * 0.2, tab.height / 2, Qt.RightButton)
    }


    /// The drawn fill of one node marker: the delegate itself fills the plot and
    /// its children carry the projected position.
    function automationNodeFill(handle) {
        return handle ? findChild(handle, "automationNodeFill") : null
    }

    /// One drawn node marker's centre, in the plot input's own coordinates.
    function automationNodePoint(handle) {
        var input = testCase.automationPlotInput()
        var fill = testCase.automationNodeFill(handle)
        if (!fill)
            return null
        return fill.mapToItem(input, fill.width / 2, fill.height / 2)
    }

    /// The drawn node markers of the active lane whose projected tick matches, in
    /// tree order: the projection publishes one marker per display point.
    function automationNodesAtTick(tick) {
        var nodes = testCase.automationNodeItems()
        var matches = []
        for (var i = 0; i < nodes.length; ++i) {
            if (Math.abs(nodes[i].model.tick - tick) < 0.5
                    && !nodes[i].model.phantom)
                matches.push(nodes[i])
        }
        return matches
    }

    /// Whether the active lane's own hover reports a node under one plot point:
    /// the page's own hit test answers, so a case never guesses the node radius.
    function automationNodeUnderPoint(x, y) {
        var input = testCase.automationPlotInput()
        mouseMove(input, x, y, -1, Qt.NoButton, Qt.NoModifier)
        wait(0)
        var nodes = testCase.automationLaneNodes()
        for (var i = 0; i < nodes.length; ++i) {
            if (nodes[i].model.hovered === true)
                return true
        }
        return false
    }

    /// A press point in empty space: a sweep, a band and a pencil press must all
    /// start clear of every drawn node, so the candidates are checked against the
    /// page's own hover before one is handed back.
    function automationFreePoint() {
        var input = testCase.automationPlotInput()
        var candidates = [Math.round(input.height / 2), Math.round(input.height * 0.75), 4]
        for (var x = 24; x < input.width - 4; x += 16) {
            for (var c = 0; c < candidates.length; ++c) {
                if (!testCase.automationNodeUnderPoint(x, candidates[c]))
                    return { "x": x, "y": candidates[c] }
            }
        }
        return null
    }

    /// A column at or after `step` that holds no drawn node of the active lane,
    /// checked against the page's own hover at the row the caller will press.
    function automationFreeColumn(step, row) {
        var input = testCase.automationPlotInput()
        var y = row === undefined ? Math.round(input.height / 2) : row
        for (var x = step; x < input.width - 4; x += 16) {
            if (!testCase.automationNodeUnderPoint(x, y))
                return x
        }
        return -1
    }

    /// Writes the Volume lane through the production sweep, so a case that needs a
    /// written occurrence creates one with real input instead of inheriting
    /// whatever lane state another case left behind.
    function writeVolumeLanePoints(tabIndex) {
        testCase.clickAutomationTab(tabIndex)
        tryVerify(function() { return bootstrap.automationActiveParameterIndex() === tabIndex }, 2000,
                  "the Volume lane is active")
        var free = testCase.automationFreePoint()
        if (!free)
            return false
        var input = testCase.automationPlotInput()
        testCase.dragAutomationPlot(free.x, free.y,
                                    Math.min(input.width - 4, free.x + 120), free.y)
        tryVerify(function() { return bootstrap.automationLaneEventCount() > 0 }, 2000,
                  "the sweep left the Volume lane written events")
        tryVerify(function() { return testCase.automationWrittenNodeIndex() >= 0 }, 2000,
                  "the written Volume lane draws a written node")
        return testCase.automationWrittenNodeIndex() >= 0
    }

    /// The index of the first drawn node that names a *written* occurrence: the
    /// projected engine node's Delete row is published disabled by design.
    function automationWrittenNodeIndex() {
        var nodes = testCase.automationLaneNodes()
        for (var i = 0; i < nodes.length; ++i) {
            if (!nodes[i].model.projected)
                return i
        }
        return -1
    }

    /// Every drawn node marker of the active lane, without the origin phantom.
    function automationLaneNodes() {
        var nodes = testCase.automationNodeItems()
        var matches = []
        for (var i = 0; i < nodes.length; ++i) {
            if (!nodes[i].model.phantom)
                matches.push(nodes[i])
        }
        return matches
    }

    /// One real press/move/release drag inside the page's own plot, in plot
    /// coordinates, so every case drives the production pointer route.
    function dragAutomationPlot(fromX, fromY, toX, toY, modifiers) {
        var input = testCase.automationPlotInput()
        var mods = modifiers === undefined ? Qt.NoModifier : modifiers
        mousePress(input, fromX, fromY, Qt.LeftButton, mods)
        // The first move past the slop arms the stroke; the second drafts it,
        // exactly as the production sweep's own activation rule reads them.
        mouseMove(input, (fromX + toX) / 2, (fromY + toY) / 2, -1, Qt.LeftButton, mods)
        mouseMove(input, toX, toY, -1, Qt.LeftButton, mods)
        mouseRelease(input, toX, toY, Qt.LeftButton, mods)
    }

    /// A time selection through the production range entry: a right press, a
    /// travel and a right release, all in plot coordinates. The row is the case's
    /// own: a right press on a node opens that node's menu instead of a band.
    function automateRangeSelection(fromX, toX, row) {
        var input = testCase.automationPlotInput()
        var y = row === undefined ? input.height / 2 : row
        mousePress(input, fromX, y, Qt.RightButton)
        mouseMove(input, toX, y, -1, Qt.LeftButton)
        mouseRelease(input, toX, y, Qt.RightButton)
    }

    /// One real node drag whose pointer arms on the pressed column and settles at
    /// `settleY`: the production drag maps its own delta from where it armed, so
    /// the pointer lands the value there through the row it settles on while the
    /// tick keeps the press's column.
    function dragAutomationPlotRow(x, pressY, armY, settleY, modifiers) {
        var input = testCase.automationPlotInput()
        var mods = modifiers === undefined ? Qt.NoModifier : modifiers
        mousePress(input, x, pressY, Qt.LeftButton, mods)
        mouseMove(input, x, armY, -1, Qt.LeftButton, mods)
        mouseMove(input, x, armY + (settleY - pressY), -1, Qt.LeftButton, mods)
        mouseRelease(input, x, armY + (settleY - pressY), Qt.LeftButton, mods)
    }

    /// The plot row whose mapped value is `value`, derived from two drawn nodes of
    /// the active lane: the projection is linear in y, so two drawn centres name
    /// the whole scale without the case copying any page policy.
    function automationRowForValue(value) {
        var known = []
        var nodes = testCase.automationLaneNodes()
        for (var i = 0; i < nodes.length && known.length < 2; ++i) {
            if (nodes[i].model.value === undefined || nodes[i].model.y === undefined)
                continue
            known.push({ "y": nodes[i].model.y, "value": nodes[i].model.value })
        }
        if (known.length < 2 || known[0].value === known[1].value)
            return -1
        var scale = (known[1].y - known[0].y) / (known[0].value - known[1].value)
        return known[0].y + (known[0].value - value) * scale
    }

    /// Empties one parameter's lane through the lane menu's own destructive row
    /// and its captured confirmation, so a case that needs a known-empty lane
    /// builds it with real input instead of assuming what the staged song holds.
    function clearAutomationLane(tabIndex) {
        testCase.openAutomationTabMenu(tabIndex)
        if (!bootstrap.automationMenuOpen())
            return false
        if (!testCase.triggerAutomationMenuRow(6))
            return false
        tryVerify(function() { return bootstrap.automationPromptOpen() }, 2000,
                  "the destructive row opened the captured confirmation")
        testCase.awaitAutomationModal("automationPrompt", true)
        var cancel = findChild(testCase.surface, "automationPromptCancel")
        tryVerify(function() { return cancel && cancel.activeFocus }, 1000,
                  "the original confirmation is drawn with Cancel focused")
        var accept = findChild(testCase.surface, "automationPromptAccept")
        verify(accept, "the confirmation draws its explicit Delete action")
        verify(waitForPolish(accept.Window.window), "the confirmation completed layout before input")
        mouseClick(accept, accept.width / 2, accept.height / 2, Qt.LeftButton)
        tryVerify(function() { return !bootstrap.automationPromptOpen() }, 2000,
                  "the confirmation's acceptance closed the form")
        tryVerify(function() { return bootstrap.automationLaneEventCount() === 0 }, 2000,
                  "the accepted confirmation emptied the lane")
        return bootstrap.automationLaneEventCount() === 0
    }

    /// The visible automation modal produced by the page's own publications, and
    /// a wait for the drawn state a case is about to hit.
    function awaitAutomationModal(name, expected) {
        tryVerify(function() {
            var item = findChild(testCase.surface, name)
            return expected ? (item !== null && item.visible === true)
                            : (item === null || item.visible === false)
        }, 2000, name + " visibility is " + expected)
        if (expected && name === "automationMenu") {
            tryVerify(function() {
                var actions = bootstrap.automationMenuActions().split(",")
                return testCase.automationMenuRowItems().length
                    + testCase.automationMenuSeparatorItems().length === actions.length
            }, 2000, "the open menu has realized every published action and separator")
            var menu = findChild(testCase.surface, name)
            tryVerify(function() { return menu.activeFocus }, 1000,
                      "the open menu acquired keyboard focus before input")
            verify(waitForPolish(menu.Window.window), "the menu completed layout before input")
        }
    }

    /// The lane menu of one parameter tab: the production selector's context
    /// request, opened with a real right click on the drawn tab.
    function openAutomationTabMenu(index) {
        wait(0)
        var tab = testCase.revealAutomationTab(index)
        verify(tab, "the selector drew tab " + index)
        mouseClick(tab, tab.width * 0.2, tab.height / 2, Qt.LeftButton)
        tryVerify(function() { return bootstrap.automationActiveParameterIndex() === index }, 1000,
                  "a left press reaches the selector's own activation")
        mousePress(tab, tab.width * 0.2, tab.height / 2, Qt.RightButton)
        var opened = bootstrap.automationMenuOpen()
        mouseRelease(tab, tab.width * 0.2, tab.height / 2, Qt.RightButton)
        verify(opened || bootstrap.automationMenuOpen(),
               "the tab's context request opened the lane menu")
        testCase.awaitAutomationModal("automationMenu", true)
    }

    /// The drawn preview markers of a live gesture.
    function automationPreviewItems() {
        return testCase.collectByNames(testCase.automationPageItem(),
                                       ["automationPreviewNode"], [])
    }

    /// A right press on the drawn node at one index, re-derived from the current
    /// projection: a committed edit moves a node's own value axis, so a case that
    /// reuses an old centre would press empty space.
    function rightClickAutomationNode(index) {
        wait(0)
        var nodes = testCase.automationLaneNodes()
        if (index >= nodes.length)
            return null
        var point = testCase.automationNodePoint(nodes[index])
        if (!point)
            return null
        mouseClick(testCase.automationPlotInput(), point.x, point.y, Qt.RightButton)
        return point
    }

    /// The open menu's current row action id, read from the drawn panel itself.
    function currentAutomationMenuAction() {
        var root = findChild(testCase.surface, "automationMenu")
        return root && root.visible === true ? root.currentActionId() : -1
    }

    /// One row activation through the menu's own keyboard contract: the panel
    /// walks its drawn rows with the arrow keys and activates the current one with
    /// Return, so the action is named by the row that really holds it.
    function triggerAutomationMenuRow(actionId) {
        for (var attempt = 0; attempt < 8; ++attempt) {
            if (testCase.currentAutomationMenuAction() === actionId) {
                keyClick(Qt.Key_Return)
                return true
            }
            keyClick(Qt.Key_Down)
        }
        return false
    }

    /// The node's own menu and one of its rendered rows in one turn: a document
    /// write landing between the press and the activation legitimately retires the
    /// captured menu, so the pair is exercised without an intervening settle and
    /// the caller can assert what the activation itself did.
    function activateAutomationNodeMenuRow(nodeIndex, actionId) {
        return testCase.openAutomationNodeMenu(nodeIndex)
            && testCase.triggerAutomationMenuRow(actionId)
    }

    /// Opens the drawn node menu and waits for its actual keyboard target,
    /// including the shared ListView's deferred delegate realization.
    function openAutomationNodeMenu(nodeIndex) {
        var point = testCase.rightClickAutomationNode(nodeIndex)
        if (!point)
            return false
        testCase.awaitAutomationModal("automationMenu", true)
        keyClick(Qt.Key_Down)
        tryVerify(function() { return testCase.currentAutomationMenuAction() >= 0 }, 1000,
                  "Down selects a realized point-menu action")
        return bootstrap.automationMenuOpen()
    }

    /// One real click on a drawn menu row by its captured action id: the row's own
    /// delegate hands the page that same action, so a list model never has to be
    /// indexed from JavaScript.
    function clickAutomationMenuRow(actionId) {
        var published = bootstrap.automationMenuActions().split(",")
        var rows = testCase.automationMenuRowItems()
        for (var i = 0; i < rows.length; ++i) {
            // The delegate's own record, checked against the capture the page
            // really published: a reused delegate whose model moved on is not a
            // row this case may click.
            if (rows[i].model.actionId === actionId && published.indexOf(String(actionId)) >= 0) {
                mouseClick(rows[i], rows[i].width / 2, rows[i].height / 2, Qt.LeftButton)
                return true
            }
        }
        return false
    }

    /// The lane's own cancel of the live tap session: no commit, no draft.
    function resetAutomationTap() {
        testCase.automationModel().resetTapTempo()
        wait(0)
    }

    // ---- the production Voice Changes page ----------------------------------

    function voicePageItem() { return testCase.pageItem(testCase.voiceChangesKind) }
    function voicePlot() { return findChild(testCase.voicePageItem(), "voicePlot") }
    function voicePlotInput() { return findChild(testCase.voicePageItem(), "voicePlotInput") }
    function voiceModel() { return testCase.surface.applicationSession.voiceChangesPage() }

    /// The drawn marker rules of the hosted page, in tree order.
    function voiceMarkerLines() {
        return testCase.collectByName(testCase.voicePlot(), "voiceChangeMarkerLine", [])
    }

    /// Attaches and shows the production Voice Changes page. Every wait is tied
    /// to the drawn or published fact the case needs — the kind's availability,
    /// its visibility, the hosted item and its drawn size, then the readout the
    /// page composes — so a case observes its own state whatever ran before it.
    /// The staged song may carry no program change at all, so the marker set is
    /// the case's own to create through the page's insertion path.
    function mountProductionVoice(location, values) {
        verify(bootstrap.attachProductionSection(testCase.voiceChangesKind),
               "the production Voice Changes page attaches to its slot")
        testCase.resetChrome(location, values)
        tryVerify(function() {
            var toggle = testCase.toggle(testCase.voiceChangesKind)
            return toggle !== null && toggle.width > 0
        }, 2000, "the published voice-changes toggle is drawn for the attached page")
        if (!testCase.section(testCase.voiceChangesKind).visible)
            testCase.clickToggle(testCase.voiceChangesKind)
        tryVerify(function() { return testCase.section(testCase.voiceChangesKind).visible }, 2000,
                  "the voice-changes section is visible")
        tryVerify(function() { return testCase.voicePageItem() !== null }, 2000,
                  "the drawer hosts the production Voice Changes page item")
        tryVerify(function() {
            var page = testCase.voicePageItem()
            return page !== null && page.width > 0 && page.height > 0
        }, 2000, "the hosted production page took its drawn body size")
        tryVerify(function() {
            return findChild(testCase.voicePageItem(), "voiceReadout") !== null
        }, 2000, "the hosted production page composed its readout")
        return testCase.voicePageItem()
    }

    /// Every named descendant whose objectName starts with `prefix`, in tree
    /// walk order: a view instantiates one delegate per visible row, so the
    /// drawn rows are the lane's oracle for the picker's published model.
    function collectByPrefix(item, prefix, found) {
        var collected = found || []
        if (!item)
            return collected
        if (String(item.objectName).indexOf(prefix) === 0)
            collected.push(item)
        for (var i = 0; i < item.children.length; ++i)
            testCase.collectByPrefix(item.children[i], prefix, collected)
        return collected
    }

    /// The drawn picker rows of the hosted page.
    function voicePickerRowItems() {
        return testCase.collectByPrefix(findChild(testCase.surface, "voicePicker"), "voicePickerRow_", [])
    }

    /// Inserts one voice change through the production picker: the real
    /// double-click entry on a free lane column, the picker's own arrow
    /// navigation onto another slot than the captured one, then Enter
    /// acceptance. Returns the drawn marker rule the insertion produced, or null.
    function insertVoiceChange(startColumn) {
        var model = testCase.voiceModel()
        var drawnBefore = testCase.voiceMarkerLines().length
        var column = startColumn ? startColumn : 24
        for (var attempt = 0; attempt < 6; ++attempt) {
            var candidate = testCase.freeVoiceColumn(column)
            if (candidate < 0)
                return null
            testCase.doubleClickPlot(candidate)
            tryVerify(function() { return model.pickerOpen }, 1000,
                      "the double-click on the empty lane opened the picker")
            if (bootstrap.voiceMarkerTicks().split(",")
                    .indexOf(String(bootstrap.voicePickerTargetTick())) >= 0) {
                // The snapped tick already holds a change, so an acceptance here
                // would be production's value replacement instead of an
                // insertion. Another column is this helper's case.
                model.cancelPicker()
                column = candidate + 24
                continue
            }
            testCase.awaitVoiceModal("voicePicker", true)
            testCase.awaitVoicePickerFocus()
            var index = model.pickerIndex
            keyClick(Qt.Key_Down)
            var list = findChild(testCase.surface, "voicePickerList")
            tryVerify(function() { return list && list.activeFocus }, 1000,
                      "Down transfers search focus to the matched voice list")
            compare(model.pickerIndex, index, "focus transfer preserves the current match")
            keyClick(Qt.Key_Down)
            tryVerify(function() { return model.pickerIndex === index + 1 }, 1000,
                      "the picker moved onto another slot than the captured one")
            keyClick(Qt.Key_Return)
            tryVerify(function() { return !model.pickerOpen }, 1000, "Enter accepted the picker")
            tryVerify(function() {
                return testCase.voiceMarkerLines().length === drawnBefore + 1
            }, 1000, "the accepted picker inserted exactly one voice change")
            var drawn = testCase.voiceMarkerLines()
            for (var i = 0; i < drawn.length; ++i) {
                if (Math.abs(drawn[i].x - candidate) < 14)
                    return drawn[i]
            }
            return null
        }
        return null
    }

    /// A plot column that holds no change: the drawn marker rules publish their
    /// own x, so a column at least the hit radius clear of every rule is free.
    /// `start` is only the first candidate: the scan walks the lane in the
    /// marker-reach stride so a plot narrower than two preferred columns still
    /// offers the columns between them.
    function freeVoiceColumn(start) {
        var lines = testCase.voiceMarkerLines()
        var input = testCase.voicePlotInput()
        var reach = 14
        for (var x = start; x < input.width - 4; x += 24) {
            var free = true
            for (var i = 0; i < lines.length; ++i) {
                if (Math.abs(lines[i].x - x) < reach) {
                    free = false
                    break
                }
            }
            if (free)
                return x
        }
        return -1
    }

    /// One real double-click in the page's own plot coordinates.
    function doubleClickPlot(x) {
        var input = testCase.voicePlotInput()
        mouseDoubleClickSequence(input, x, input.height / 2, Qt.LeftButton)
    }

    /// The page pushes modality to a modal surface on its own change signal, and
    /// the surface renders that flag on the next pass: a case that drives a modal
    /// with the pointer waits for the drawn state it is about to hit, the same way
    /// every other case in this suite waits for what it clicks.
    function awaitVoiceModal(name, expected) {
        // A kind that hosts no page, or a hosted page that composes no such modal
        // (the container cases host their own test pages), is already settled.
        tryVerify(function() {
            var item = findChild(testCase.surface, name)
            return expected ? (item !== null && item.visible === true)
                            : (item === null || item.visible === false)
        }, 1000, name + " visibility is " + expected)
        if (expected && name === "voiceChangeMenu") {
            tryVerify(function() {
                var panel = findChild(testCase.surface, "voiceMenuPanel")
                if (!panel || panel.rowCount === 0) return false
                for (var i = 0; i < panel.rowCount; ++i) {
                    var row = panel.rowItem(i)
                    if (!row || !row.visible || row.width <= 0 || row.height <= 0) return false
                }
                return true
            }, 1000, "the shared voice menu realizes its drawn rows")
        }
    }

    /// The picker's search field takes active focus one event-loop pass after it
    /// opens; a key case waits for the focus the key will be delivered to.
    function awaitVoicePickerFocus() {
        tryVerify(function() {
            var field = findChild(testCase.surface, "voicePickerSearch")
            return field !== null && field.activeFocus
        }, 1000, "the picker took focus in its search field")
    }

    /// Types one zero-padded program number into the picker's focused search
    /// field, one real key at a time.
    function typeProgram(value) {
        var text = ("000" + value).slice(-3)
        for (var i = 0; i < text.length; ++i)
            keyClick(Qt.Key_0 + parseInt(text.charAt(i), 10))
        wait(0)
    }

    /// The production page mounts through the real presenter and renders its own
    // composition: the shared gutter splits gutter and plot, every change
    // publishes a marker rule, and the context readout is drawn.
    function test_productionVoiceChangesPageMountsAndRenders() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = bootstrap.preferencesUrl("production-voice")
        var page = testCase.mountProductionVoice(location)
        compare(String(testCase.section(testCase.voiceChangesKind).contentUrl).length > 0, true,
                "the kind publishes the production page URL")

        var gutter = findChild(page, "voiceGutter")
        var plot = testCase.voicePlot()
        verify(gutter && plot, "the page composed its gutter and plot")
        fuzzyCompare(gutter.width, testCase.surface.timelineSplitX, 0.01,
                     "the gutter is the shared column")
        fuzzyCompare(plot.x, gutter.width, 0.01, "the plot starts at the shared origin")
        fuzzyCompare(plot.width, page.width - gutter.width, 0.01,
                     "the plot spans the body beside the gutter")
        fuzzyCompare(plot.height, page.height, 0.01, "the plot spans the body height")

        var model = testCase.voiceModel()
        verify(findChild(page, "voiceGridLines"), "the page composed its grid")
        verify(findChild(page, "voiceReadout"), "the page composed its context readout")
        verify(findChild(page, "voiceHoverLabel"), "the page composed its hover label")
        verify(findChild(page, "voicePlotMessage"), "the page composed its plot message")
        compare(plot.Accessible.name, "Voice changes", "the plot publishes its accessible name")

        // The staged song may carry no voice change at all, so this case creates
        // one through the production insertion path and checks the drawn result.
        var drawnBefore = testCase.voiceMarkerLines().length
        var inserted = testCase.insertVoiceChange(360)
        verify(inserted, "the production picker inserted a voice change")
        compare(testCase.voiceMarkerLines().length, drawnBefore + 1,
                "the insertion published exactly one more drawn marker rule")
        compare(findChild(page, "voiceReadout").visible, true,
                "the readout is drawn for the presented track")
        compare(String(findChild(page, "voiceReadout").text).length > 0, true,
                "the readout draws the presented track's context")
        testCase.auditVisibleTextInk(page, "voice page")
        var readout = findChild(page, "voiceReadout")
        verify(readout.width > 0 && readout.height > 0,
               "the readout draws a usable rect")
        compare(readout.horizontalAlignment, Text.AlignRight,
                "the readout draws right-aligned")
        var hoverInput = testCase.voicePlotInput()
        var hoverColumn = testCase.freeVoiceColumn(120)
        verify(hoverColumn >= 0, "the lane leaves a free column to hover")
        mouseMove(hoverInput, hoverColumn, hoverInput.height / 2)
        var hoverLabel = findChild(page, "voiceHoverLabel")
        tryVerify(function() { return hoverLabel.visible }, 1000,
                  "the background hover draws its label")
        verify(hoverLabel.width > 0 && hoverLabel.height > 0,
               "the hover draws a usable label rect")
    }

    // Real pointer input on the drawn composition: the double-click picker entry,
    // a typed filter, Enter acceptance, one insertion, and then the point menu's
    // typed rows with the delete that consumes them.
    function test_productionVoiceChangesPointerAndMenuTransactions() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = bootstrap.preferencesUrl("production-voice-pointer")
        var page = testCase.mountProductionVoice(location)
        var model = testCase.voiceModel()
        var drawnBefore = testCase.voiceMarkerLines().length

        // The picker's filter: a real double-click on a free lane column opens
        // the insertion picker, and real keystrokes filter its published rows.
        var column = testCase.freeVoiceColumn(360)
        verify(column >= 0, "the staged song leaves a free voice-lane column")
        testCase.doubleClickPlot(column)
        tryVerify(function() { return model.pickerOpen }, 1000,
                  "the double-click on the empty lane opened the picker")
        compare(model.pickerTitle, "Insert voice change",
                "an empty-lane target opens the insertion title")
        var field = findChild(testCase.surface, "voicePickerSearch")
        verify(field, "the picker composed its search field")
        testCase.awaitVoiceModal("voicePicker", true)
        tryVerify(function() { return field.activeFocus }, 1000,
                  "the picker took focus in its search field")
        var picker = findChild(testCase.surface, "voicePicker")
        verify(picker, "the picker composed its production surface")
        compare(findChild(testCase.surface, "voicePickerTitle").text, model.pickerTitle,
                "the picker draws its title")
        testCase.auditVisibleTextInk(picker, "voice picker")
        testCase.typeProgram(0)
        tryVerify(function() { return model.pickerFilter === "000" }, 1000,
                  "the typed text reached the page's filter (filter '"
                  + model.pickerFilter + "')")
        compare(model.pickerHasMatch, true, "the typed filter matched the slot it names")
        var rows = testCase.voicePickerRowItems()
        compare(rows.length > 0, true, "the filter drew its visible rows")
        compare(String(rows[0].Accessible.name).indexOf("000") >= 0, true,
                "a filtered row names the slot it matched ('" + rows[0].Accessible.name + "')")
        compare(model.interactionActive, true, "the open picker is an active interaction")
        keyClick(Qt.Key_Escape)
        tryVerify(function() { return !model.pickerOpen }, 1000, "Escape closed the picker")
        compare(testCase.voiceMarkerLines().length, drawnBefore,
                "the cancelled picker wrote nothing")
        compare(testCase.voicePlot().activeFocus, true,
                "focus returned to the page's plot after the picker closed")

        // The insertion path: the same double-click entry, the picker's own arrow
        // navigation onto another slot, then Enter.
        var inserted = testCase.insertVoiceChange(360)
        verify(inserted, "the production picker inserted a voice change")
        compare(testCase.voiceMarkerLines().length, drawnBefore + 1,
                "the inserted occurrence published its own drawn rule")
        compare(session.canUndo, true, "the insertion reached the document's history")

        // The point menu on the inserted marker, driven through the rendered rows.
        var input = testCase.voicePlotInput()
        var markerPoint = input.mapFromItem(inserted.parent, inserted.x + 1,
                                            inserted.y + inserted.height / 2)
        mouseClick(input, markerPoint.x, markerPoint.y, Qt.RightButton)
        tryVerify(function() { return model.menuOpen }, 1000,
                  "the right press on the marker opened the context menu")
        testCase.awaitVoiceModal("voiceChangeMenu", true)
        var panel = findChild(testCase.surface, "voiceMenuPanel")
        verify(panel, "the menu composed its panel")
        testCase.auditVisibleTextInk(panel, "voice context menu")
        compare(findChild(panel, "quickMenuFrame").Accessible.role, Accessible.PopupMenu,
                "the panel publishes the popup-menu role")
        var changeRow = testCase.menuRowByAction(panel, 1)
        var deleteRow = testCase.menuRowByAction(panel, 3)
        verify(changeRow && deleteRow, "the marker target published both typed rows")
        compare(changeRow.Accessible.role, Accessible.MenuItem,
                "a row publishes the menu-item role")
        compare(String(deleteRow.Accessible.name).length > 0, true,
                "a row publishes its accessible name")
        mouseClick(deleteRow, deleteRow.width / 2, deleteRow.height / 2, Qt.LeftButton)
        tryVerify(function() { return testCase.voiceMarkerLines().length === drawnBefore }, 1000,
                  "the rendered delete row removed the captured occurrence")
        testCase.awaitVoiceModal("voiceChangeMenu", false)
        compare(session.canUndo, true, "the deletion reached the document's history")

        // An outside press dismisses the menu and writes nothing.
        var kept = testCase.insertVoiceChange(60)
        verify(kept, "the case inserted another marker for the dismissal")
        var settled = testCase.voiceMarkerLines().length
        markerPoint = input.mapFromItem(kept.parent, kept.x + 1, kept.y + kept.height / 2)
        mouseClick(input, markerPoint.x, markerPoint.y, Qt.RightButton)
        tryVerify(function() { return model.menuOpen }, 1000, "the menu reopened")
        testCase.awaitVoiceModal("voiceChangeMenu", true)
        var underlay = findChild(testCase.surface, "voiceMenuUnderlay")
        verify(underlay, "the menu composed its dismissing underlay")
        mouseClick(underlay, 4, 4, Qt.LeftButton)
        tryVerify(function() { return !model.menuOpen }, 1000,
                  "the outside press dismissed the menu")
        compare(testCase.voiceMarkerLines().length, settled,
                "the outside dismissal wrote nothing")
    }

    // The picker's own keyboard and focus contract: arrow navigation over the
    // published rows, Escape cancelling, the outside press cancelling, and focus
    // returning to the page's plot.
    function test_productionVoiceChangesPickerKeyboardAndCancellation() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = bootstrap.preferencesUrl("production-voice-keyboard")
        var page = testCase.mountProductionVoice(location)
        var model = testCase.voiceModel()
        var marker = testCase.insertVoiceChange(60)
        verify(marker, "the case created a marker through the production picker")
        var before = testCase.voiceMarkerLines().length
        var column = testCase.freeVoiceColumn(24)
        verify(column >= 0, "the staged song leaves a free voice-lane column")

        testCase.doubleClickPlot(column)
        tryVerify(function() { return model.pickerOpen }, 1000, "the picker opened")
        testCase.awaitVoiceModal("voicePicker", true)
        testCase.awaitVoicePickerFocus()
        var index = model.pickerIndex
        compare(index >= 0, true, "the picker publishes a current row")
        var search = findChild(testCase.surface, "voicePickerSearch")
        var list = findChild(testCase.surface, "voicePickerList")
        var accept = findChild(testCase.surface, "voicePickerAccept")
        var cancel = findChild(testCase.surface, "voicePickerCancel")
        verify(search && list && accept && cancel, "the picker draws its complete focus cycle")
        keyClick(Qt.Key_Down)
        tryVerify(function() { return list.activeFocus }, 1000,
                  "Down from search transfers focus to the list")
        compare(model.pickerIndex, index, "focus transfer does not skip the selected match")
        keyClick(Qt.Key_Down)
        tryVerify(function() { return model.pickerIndex === index + 1 }, 1000,
                  "Down in the list moves the current row")
        keyClick(Qt.Key_Up)
        tryVerify(function() { return model.pickerIndex === index }, 1000,
                  "the up arrow returned to the captured row")
        var forward = [accept, cancel, search, list]
        for (var f = 0; f < forward.length; ++f) {
            keyClick(Qt.Key_Tab)
            compare(forward[f].activeFocus, true, "Tab follows the picker cycle at " + f)
        }
        var backward = [search, cancel, accept, list]
        for (var b = 0; b < backward.length; ++b) {
            keyClick(Qt.Key_Backtab, Qt.ShiftModifier)
            compare(backward[b].activeFocus, true, "Backtab reverses the picker cycle at " + b)
        }
        var rows = testCase.voicePickerRowItems()
        compare(rows.length > 0, true, "the picker drew its visible rows")
        compare(String(rows[0].Accessible.name).length > 0, true,
                "a drawn row publishes its accessible name ('" + rows[0].Accessible.name + "')")
        compare(rows[0].Accessible.role, Accessible.ListItem,
                "a drawn row publishes the list-item role")
        keyClick(Qt.Key_Escape)
        tryVerify(function() { return !model.pickerOpen }, 1000, "Escape closed the picker")
        testCase.awaitVoiceModal("voicePicker", false)
        compare(testCase.voiceMarkerLines().length, before, "Escape wrote nothing")
        compare(testCase.voicePlot().activeFocus, true,
                "focus returned to the page's plot after the picker closed")

        // An outside press dismisses without a write and without a gesture.
        testCase.doubleClickPlot(column)
        tryVerify(function() { return model.pickerOpen }, 1000, "the picker reopened")
        testCase.awaitVoiceModal("voicePicker", true)
        var underlay = findChild(testCase.surface, "voicePickerUnderlay")
        verify(underlay, "the picker composed its dismissing underlay")
        mouseClick(underlay, 4, 4, Qt.LeftButton)
        tryVerify(function() { return !model.pickerOpen }, 1000,
                  "the outside press dismissed the picker")
        testCase.awaitVoiceModal("voicePicker", false)
        compare(model.interactionActive, false,
                "the dismissing press left no interaction behind")
        compare(testCase.voiceMarkerLines().length, before, "the outside dismissal wrote nothing")

        // A live marker drag, cancelled by hiding the section, commits nothing.
        var input = testCase.voicePlotInput()
        var lines = testCase.voiceMarkerLines()
        var dragged = null
        for (var i = 0; i < lines.length; ++i) {
            if (Math.abs(lines[i].x - marker.x) < 1)
                dragged = lines[i]
        }
        verify(dragged, "the inserted marker is still drawn for the drag")
        var start = input.mapFromItem(dragged.parent, dragged.x + dragged.width / 2,
                                      dragged.y + dragged.height / 2)
        mousePress(input, start.x, start.y, Qt.LeftButton)
        mouseMove(input, start.x + 30, start.y, -1, Qt.LeftButton)
        compare(model.interactionActive, true, "the live drag reports an active interaction")
        testCase.clickToggle(testCase.voiceChangesKind)
        tryVerify(function() { return !testCase.section(testCase.voiceChangesKind).visible }, 1000,
                  "the section hid")
        compare(model.interactionActive, false, "hiding the section cancelled the drag")
        mouseRelease(input, start.x + 30, start.y, Qt.LeftButton)
        compare(model.interactionActive, false, "the released pointer committed nothing")
        compare(testCase.voiceMarkerLines().length, before, "the cancelled drag wrote nothing")
        testCase.clickToggle(testCase.voiceChangesKind)
        tryVerify(function() { return testCase.section(testCase.voiceChangesKind).visible }, 1000,
                  "the section is visible again")
    }

    function test_productionVoicePickerPointerAudition() {
        if (testCase.containerPhase) skip("production composition only")
        testCase.mountProductionVoice(bootstrap.preferencesUrl("voice-picker-audition"))
        testCase.doubleClickPlot(testCase.freeVoiceColumn(24))
        testCase.awaitVoiceModal("voicePicker", true)
        testCase.awaitVoicePickerFocus()
        verify(bootstrap.observeVoiceAudition(), "the observer retains the production audio callback")
        var rows = testCase.voicePickerRowItems()
        var list = findChild(testCase.surface, "voicePickerList")
        var row = null
        for (var i = 0; i < rows.length; ++i) {
            var point = rows[i].mapToItem(list, rows[i].width / 2, rows[i].height / 2)
            if (point.y > 0 && point.y < list.height) {
                row = rows[i]
                break
            }
        }
        verify(row, "a picker row is visible inside the list viewport")
        var program = Number(row.objectName.substring("voicePickerRow_".length))
        var revision = bootstrap.automationDocumentRevision()
        mousePress(row, row.width / 2, row.height / 2, Qt.LeftButton)
        tryVerify(function() {
            return bootstrap.voiceAuditionEvents() === program + ":60:112"
        }, 2000, "the real row press auditions its own program at middle C")
        mouseRelease(row, row.width / 2, row.height / 2, Qt.LeftButton)
        compare(bootstrap.voiceAuditionEvents(),
                program + ":60:112," + program + ":60:0",
                "release stops the sounding program")
        compare(bootstrap.automationDocumentRevision(), revision, "audition does not edit the song")
        verify(bootstrap.observeVoiceAudition())
        mousePress(row, row.width / 2, row.height / 2, Qt.LeftButton)
        compare(bootstrap.voiceAuditionEvents(), program + ":60:112")
        keyClick(Qt.Key_Escape)
        testCase.awaitVoiceModal("voicePicker", false)
        mouseRelease(testCase.surface, 1, 1, Qt.LeftButton)
        compare(bootstrap.voiceAuditionEvents(),
                program + ":60:112," + program + ":60:0",
                "Escape stops a held audition exactly once before physical release")
    }

    // The shared playhead: presentations inside one voice span rebuild no static
    // content and every published presentation reaches the page through the
    // session's own Swift fan-out — the one callback, fanned to both pages.
    function test_productionVoiceChangesPlayheadPerformance() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = bootstrap.preferencesUrl("production-voice-playhead")
        var page = testCase.mountProductionVoice(location)
        verify(testCase.insertVoiceChange(90),
               "the case created a marker so the presented span has a boundary")
        verify(bootstrap.pausePlayheadPolling(),
               "the lane holds the production polling task for determinism")
        // The lane presents real observations, so it learns the sample-to-tick
        // rate from the production presenter itself instead of assuming a tempo.
        bootstrap.presentPlayheadObservation(0, 2)
        var probe = 250.0
        while (probe <= 8000 && bootstrap.voicePresentedTick() < 1) {
            bootstrap.presentPlayheadObservation(probe, 2)
            probe *= 2
        }
        var warmTick = bootstrap.voicePresentedTick()
        verify(warmTick >= 1, "the presented samples advanced the shared tick")
        var perTick = probe / 2 / warmTick
        var endTick = bootstrap.voiceContextEndTick()
        verify(endTick > warmTick + 1, "the presented span has room to move inside it")
        var builds = bootstrap.voiceContentBuilds()
        var presented = bootstrap.voicePlayheadPresentations()
        var published = bootstrap.publishedPlayheadPresentations()
        var slot = bootstrap.voicePresentedSlot()
        var sample = probe / 2
        var step = Math.max(1, Math.floor(perTick / 4))
        var updates = 0
        while (updates < 24 && bootstrap.voicePresentedTick() + 3 < endTick) {
            // One iteration is one distinct presented tick: the samples that
            // round to a tick the page already has are the dedupe the page owes.
            var previous = bootstrap.voicePresentedTick()
            var guard = 0
            while (bootstrap.voicePresentedTick() === previous && guard < 32) {
                sample += step
                bootstrap.presentPlayheadObservation(sample, 2)
                guard += 1
            }
            updates += 1
        }
        compare(updates > 0, true, "the case presented inside the span")
        compare(bootstrap.voiceContentBuilds(), builds,
                "shared-playhead movement inside one span rebuilt no voice content")
        compare(bootstrap.voicePresentedSlot(), slot,
                "every presented tick stayed inside its own voice context")
        compare(bootstrap.voicePlayheadPresentations() - presented, updates,
                "every distinct context presentation reached the Voice Changes page ("
                + (bootstrap.voicePlayheadPresentations() - presented) + " of " + updates + ")")
        compare(bootstrap.publishedPlayheadPresentations() - published >= updates, true,
                "the shared presenter published every presentation the page consumed")

        // Crossing the span boundary updates the readout and rebuilds once.
        var crossingGuard = 0
        while (bootstrap.voicePresentedSlot() === slot && crossingGuard < 64) {
            sample += step
            bootstrap.presentPlayheadObservation(sample, 2)
            crossingGuard += 1
        }
        compare(bootstrap.voicePresentedSlot() !== slot, true,
                "the crossed boundary changed the presented context")
        compare(bootstrap.voiceContentBuilds(), builds + 1,
                "crossing a span rebuilt the projection exactly once")
        compare(testCase.voiceMarkerLines().length > 0, true,
                "the rebuilt projection still draws its markers")
        compare(page.objectName, "voiceChangesPage", "the case composition is the production page")
    }

    // The container's one modal layer: the picker is composed into it, it really
    // sits above another section's body, an outside press inside that other
    // section dismisses it without starting that page's gesture, and the
    // composited drawer pixel proves the stacking rather than a subtree grab.
    function test_productionVoiceChangesModalLayerComposition() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = bootstrap.preferencesUrl("production-voice-modal-layer")
        var values = testCase.chromeState({ "velocityVisible": true, "voiceChangesVisible": true })
        testCase.mountProductionVelocity(location, values)
        verify(bootstrap.attachProductionSection(testCase.voiceChangesKind),
               "the composition hosts both document-bound pages")
        testCase.resetChrome(location, values)
        testCase.showSection(testCase.voiceChangesKind)
        var marker = testCase.insertVoiceChange(120)
        verify(marker, "the case created a marker through the production picker")

        var column = testCase.freeVoiceColumn(240)
        verify(column >= 0, "the lane leaves a free column for the picker")
        testCase.doubleClickPlot(column)
        tryVerify(function() { return testCase.voiceModel().pickerOpen }, 1000,
                  "the picker opened")
        testCase.awaitVoiceModal("voicePicker", true)
        var layer = findChild(testCase.surface, "drawerModalLayer")
        var card = findChild(testCase.surface, "voicePickerCard")
        verify(layer && card, "the modal layer hosts the picker's card")
        var base = testCase.voiceModel().baseFontPx
        compare(card.minimumWidth, Math.round(base * 30), "original picker width floor")
        compare(findChild(card, "voicePickerList").height, Math.round(base * 110 / 3),
                "original picker list viewport, not the shortened replacement")
        compare(card.appearance.dialogPadding, Math.max(1, Math.round(base * 0.25)))
        compare(card.appearance.verticalPadding, Math.max(1, Math.round(base * 0.125)))
        compare(layer.width, testCase.Window.window.contentItem.width)
        compare(layer.height, testCase.Window.window.contentItem.height)
        var pickerRoot = findChild(testCase.surface, "voicePicker")
        verify(pickerRoot, "the picker root is composed")
        compare(pickerRoot.parent, layer,
                "the picker composes into the container's one modal layer")

        // The card crosses another section's body: that is where stacking matters.
        var velocityBody = findChild(testCase.drawer(), "drawerBody_" + testCase.keyName(testCase.velocityKind))
        verify(velocityBody, "the velocity body is hosted beside the voice body")
        var cardInDrawer = card.mapToItem(testCase.drawer(), 0, 0)
        var bodyInDrawer = velocityBody.mapToItem(testCase.drawer(), 0, 0)
        var left = Math.max(cardInDrawer.x, bodyInDrawer.x)
        var right = Math.min(cardInDrawer.x + card.width,
                             bodyInDrawer.x + velocityBody.width)
        var top = Math.max(cardInDrawer.y, bodyInDrawer.y)
        var bottom = Math.min(cardInDrawer.y + card.height,
                              bodyInDrawer.y + velocityBody.height)
        compare(right > left && bottom > top, true,
                "the picker's card overlaps the velocity body (card "
                + Math.round(cardInDrawer.x) + "," + Math.round(cardInDrawer.y) + " "
                + Math.round(card.width) + "x" + Math.round(card.height) + "; body "
                + Math.round(bodyInDrawer.x) + "," + Math.round(bodyInDrawer.y) + " "
                + Math.round(velocityBody.width) + "x" + Math.round(velocityBody.height) + ")")

        var drawer = testCase.drawer()
        var withModal = grabImage(drawer)
        verify(withModal && withModal.width > 0, "the drawer composited into an image")
        var scale = drawer.width > 0 ? withModal.width / drawer.width : 1
        var probeX = Math.min(withModal.width - 1,
                              Math.max(0, Math.round((left + (right - left) / 2) * scale)))
        var probeY = Math.min(withModal.height - 1,
                              Math.max(0, Math.round((top + (bottom - top) / 2) * scale)))
        verify(withModal.alpha(probeX, probeY) === 255,
               "the composited overlap pixel is opaque")
        var cardChannels = testCase.channelsOf(card.appearance.background)
        // The overlap region is read through the suite's own pixel oracle: an
        // exact palette pixel inside it proves the card was composited over the
        // other section's body, whichever glyph happens to sit at the centre.
        var radius = Math.max(2, Math.round(4 * scale))
        var probeRegion = {
            "x0": Math.max(0, probeX - radius), "y0": Math.max(0, probeY - radius),
            "x1": Math.min(withModal.width - 1, probeX + radius),
            "y1": Math.min(withModal.height - 1, probeY + radius)
        }
        var cardFill = testCase.nearestPixel(withModal, probeRegion, cardChannels)
        verify(cardFill.distance <= 6,
               "the composited overlap region carries the card's own fill ("
               + cardFill.pixel.join("/") + " vs " + cardChannels.join("/")
               + " at " + cardFill.at + ")")

        // An outside press inside the other section dismisses the modal and never
        // reaches that section's own input.
        var velocityBefore = bootstrap.velocitySelectedNoteIds()
        var velocityGesture = testCase.velocityModel().interactionActive
        // A point inside the other section's body that the card does not cover:
        // the dismissing press must reach the modal's underlay, not the card.
        var crossX = bodyInDrawer.x + 6
        var crossY = bodyInDrawer.y + velocityBody.height / 2
        compare(crossX < cardInDrawer.x || crossX > cardInDrawer.x + card.width
                || crossY < cardInDrawer.y || crossY > cardInDrawer.y + card.height, true,
                "the cross-section press point lies outside the card")
        var underlay = findChild(testCase.surface, "voicePickerUnderlay")
        verify(underlay, "the picker composed its dismissing underlay")
        var underlayPoint = underlay.mapFromItem(testCase.drawer(), crossX, crossY)
        compare(underlayPoint.x >= 0 && underlayPoint.x <= underlay.width
                && underlayPoint.y >= 0 && underlayPoint.y <= underlay.height, true,
                "the cross-section press point lies inside the modal layer's underlay")
        mouseClick(underlay, underlayPoint.x, underlayPoint.y, Qt.LeftButton)
        tryVerify(function() { return !testCase.voiceModel().pickerOpen }, 1000,
                  "the outside press inside another section dismissed the picker")
        testCase.awaitVoiceModal("voicePicker", false)
        compare(bootstrap.velocitySelectedNoteIds(), velocityBefore,
                "the dismissing press did not reach the other section's selection")
        compare(testCase.velocityModel().interactionActive, velocityGesture,
                "the dismissing press started no gesture in the other section")

        var withoutModal = grabImage(drawer)
        verify(withoutModal && withoutModal.width > 0, "the drawer composited again")
        var bodyFill = testCase.nearestPixel(withoutModal, probeRegion, cardChannels)
        verify(bodyFill.distance > cardFill.distance + 6,
               "the overlap region belongs to the section body once the modal is gone ("
               + cardFill.pixel.join("/") + " d=" + cardFill.distance + " -> "
               + bodyFill.pixel.join("/") + " d=" + bodyFill.distance + ")")
    }

    // Bare Space priority: the voice page never claims it, the picker's search
    // field is the explicit text-entry exception, and every other picker/menu
    // surface leaves it to the window transport.
    function test_productionVoiceChangesSpacePriority() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = bootstrap.preferencesUrl("production-voice-space")
        var page = testCase.mountProductionVoice(location)
        var model = testCase.voiceModel()
        var marker = testCase.insertVoiceChange(60)
        verify(marker, "the case created a marker for the menu")
        var propagations = testCase.spacePropagations

        // The plot: bare Space reaches the window's transport command.
        testCase.voicePlot().forceActiveFocus(Qt.OtherFocusReason)
        keyClick(Qt.Key_Space)
        tryVerify(function() { return testCase.spacePropagations === propagations + 1 }, 1000,
                  "the voice plot leaves bare Space to the window transport")

        // The picker's search field is the modal's one text-entry surface.
        var column = testCase.freeVoiceColumn(120)
        verify(column >= 0, "the lane leaves a free column for the picker")
        testCase.doubleClickPlot(column)
        tryVerify(function() { return model.pickerOpen }, 1000, "the picker opened")
        testCase.awaitVoiceModal("voicePicker", true)
        testCase.awaitVoicePickerFocus()
        var typed = String(model.pickerFilter).length
        keyClick(Qt.Key_Space)
        tryVerify(function() { return String(model.pickerFilter).length === typed + 1 }, 1000,
                  "the focused search field takes Space as text")
        compare(testCase.spacePropagations, propagations + 1,
                "the focused search field keeps Space out of the transport")

        // Original PromptButton Space is a local modal acceptance key.
        keyClick(Qt.Key_Down)
        keyClick(Qt.Key_Down)
        var markerCount = testCase.voiceMarkerLines().length
        var accept = findChild(testCase.surface, "voicePickerAccept")
        verify(accept, "the picker composed its accept control")
        accept.forceActiveFocus(Qt.TabFocusReason)
        keyClick(Qt.Key_Space)
        tryVerify(function() { return !model.pickerOpen }, 1000,
                  "Space activates the focused original OK button")
        tryVerify(function() { return testCase.voiceMarkerLines().length === markerCount + 1 }, 1000,
                  "local Space acceptance inserts the selected voice exactly once")
        compare(testCase.spacePropagations, propagations + 1,
                "modal acceptance never leaks into transport")
        testCase.awaitVoiceModal("voicePicker", false)

        // The original menu host contains Space as local type-ahead input.
        var input = testCase.voicePlotInput()
        var point = input.mapFromItem(marker.parent, marker.x + 1,
                                      marker.y + marker.height / 2)
        mouseClick(input, point.x, point.y, Qt.RightButton)
        tryVerify(function() { return model.menuOpen }, 1000, "the context menu opened")
        testCase.awaitVoiceModal("voiceChangeMenu", true)
        tryVerify(function() {
            var menu = findChild(testCase.surface, "voiceChangeMenu")
            return menu && menu.activeFocus
        }, 1000, "the visible voice menu owns keyboard focus")
        var revision = bootstrap.automationDocumentRevision()
        keyClick(Qt.Key_Space)
        compare(testCase.spacePropagations, propagations + 1,
                "the modal menu contains Space instead of leaking into transport")
        compare(model.menuOpen, true, "Space does not activate a menu command")
        compare(bootstrap.automationDocumentRevision(), revision,
                "menu type-ahead does not edit the song")
        keyClick(Qt.Key_Escape)
        tryVerify(function() { return !model.menuOpen }, 1000, "Escape closed the menu")
        testCase.awaitVoiceModal("voiceChangeMenu", false)
        compare(model.interactionActive, false, "the case left no interaction behind")
    }

    // The production Automation page mounts through the real presenter and
    // renders its own composition: the shared gutter splits the selector from the
    // plot, every catalog parameter publishes a tab, the lane's written events
    // publish nodes, the value axis and the context readout are drawn, and the
    // selector's accessible contract holds.
    function test_productionAutomationPageMountsAndRenders() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = bootstrap.preferencesUrl("production-automation")
        var page = testCase.mountProductionAutomation(location)
        compare(String(testCase.section(testCase.automationKind).contentUrl).length > 0, true,
                "the kind publishes the production page URL")
        compare(page.objectName, "automationPage", "the hosted item is the production page")

        var gutter = testCase.automationGutter()
        var plot = testCase.automationPlot()
        verify(gutter && plot, "the page composed its selector column and plot")
        fuzzyCompare(gutter.width, testCase.surface.timelineSplitX, 0.01,
                     "the selector column is the shared gutter")
        fuzzyCompare(plot.x, gutter.width, 0.01, "the plot starts at the shared origin")
        fuzzyCompare(plot.width, page.width - gutter.width, 0.01,
                     "the plot spans the body beside the selector")
        fuzzyCompare(plot.height, page.height, 0.01, "the plot spans the body height")

        var model = testCase.automationModel()
        compare(testCase.automationTabItems().length, model.tabCount,
                "every catalog parameter drew a selector tab")
        compare(testCase.drawnAutomationTabLabels(), bootstrap.automationTabLabels(),
                "the drawn selector matches the published catalog labels")

        // The selector's own facts: one active tab, one pip per lane with events,
        // and the accessible contract of a checkable button.
        var activeTab = testCase.drawnAutomationActiveTab()
        verify(activeTab, "the active parameter's tab is drawn")
        compare(activeTab.Accessible.selected, true, "the active parameter reports itself selected")
        compare(String(activeTab.Accessible.name).length > 0, true,
                "a tab publishes its accessible name ('" + activeTab.Accessible.name + "')")
        var tempoTab = testCase.automationTab(model.tabCount - 1)
        verify(tempoTab, "the Tempo tab is drawn last")
        compare(bootstrap.automationTabLabels().split(",").slice(-1)[0],
                testCase.collectByNames(tempoTab, ["automationParameterTabText"], [])[0].text,
                "the last catalog parameter is the Tempo row the selector drew")
        compare(tempoTab.Accessible.selected, false, "the Tempo row is not active yet")
        var tapControl = findChild(tempoTab, "automationTempoTapButton")
        verify(tapControl, "the Tempo row composed its Tap control")
        compare(tapControl.Accessible.role, Accessible.Button, "the Tap control is a button")
        compare(tapControl.Accessible.name, "Tap tempo", "the Tap control names its action")

        // The plot's own facts: the grid, the value axis and the lane's nodes.
        verify(findChild(page, "automationGridLines"), "the page composed its time grid")
        verify(findChild(page, "automationValueLines"), "the page composed its value axis")
        verify(findChild(page, "automationReadout"), "the page composed its context readout")
        verify(findChild(page, "automationHoverLabel"), "the page composed its hover label")
        verify(findChild(page, "automationPreviewLabel"), "the page composed its gesture readout")
        verify(findChild(page, "automationRangeBand"), "the page composed its range band")
        verify(findChild(page, "automationPlotMessage"), "the page composed its plot message")
        compare(plot.Accessible.name, "Automation", "the plot publishes its accessible name")
        compare(String(plot.Accessible.description).length > 0, true,
                "the plot publishes the page's readout as its description")

        var tabWithEvents = testCase.automationTabWithEvents()
        verify(tabWithEvents >= 0, "the staged song gives one parameter written events")
        testCase.clickAutomationTab(tabWithEvents)
        tryVerify(function() { return bootstrap.automationActiveParameterIndex()
                                       === tabWithEvents }, 2000,
                  "the tab click switched the active parameter (index "
                  + bootstrap.automationActiveParameterIndex() + " of " + tabWithEvents + ")")
        tryVerify(function() { return testCase.automationNodeItems().length
                                       === testCase.automationModel().nodeCount }, 2000,
                  "the active lane drew one marker per published node ("
                  + testCase.automationNodeItems().length + " drawn of "
                  + testCase.automationModel().nodeCount + ")")
        compare(testCase.automationNodeItems().length > 0, true,
                "the lane with written events drew its nodes")
        compare(testCase.automationCurveItems().length > 0, true,
                "the lane with written events drew its curve")
        compare(findChild(page, "automationReadout").visible, true,
                "the readout is drawn while the lane holds a value at the shared tick")
        testCase.auditVisibleTextInk(page, "automation page")
    }

    // A parameter switch is view-only, and the selector's Control press is the
    // production ghost entry: a tab with events pins its curve, the active tab
    // clears every pin, and a tab without events refuses.
    function test_productionAutomationTabSwitchAndGhosts() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = bootstrap.preferencesUrl("production-automation-tabs")
        testCase.mountProductionAutomation(location)
        var model = testCase.automationModel()
        var trackTab = testCase.automationTabWithEvents()
        var emptyTab = testCase.automationEmptyTab()
        verify(trackTab >= 0 && emptyTab >= 0,
               "the staged song offers an occupied and an empty parameter lane")
        var revisionBefore = model.interactionActive
        var focusTab = testCase.automationTab(0)
        var scroller = findChild(testCase.automationGutter(), "automationTabsScroller")
        scroller.contentY = 0
        testCase.focusControl(testCase.automationPlot())
        mouseMove(testCase.automationPlotInput(), 4, 4)
        waitForRendering(testCase.surface)
        var idle = grabImage(testCase.surface)
        var region = testCase.regionOf(idle, testCase.surface, focusTab)
        var widthBefore = focusTab.width
        var heightBefore = focusTab.height
        testCase.focusControl(focusTab)
        waitForRendering(testCase.surface)
        var focused = grabImage(testCase.surface)
        compare(focusTab.width, widthBefore, "keyboard focus never changes tab width")
        compare(focusTab.height, heightBefore, "keyboard focus never changes tab height")
        var x = Math.round((region.x0 + region.x1) / 2)
        var stroke = Math.max(1, Math.round(model.baseFontPx / 13))
        var y = region.y0 + Math.floor(stroke * 1.5 * idle.height / testCase.surface.height)
        verify(idle.red(x, y) !== focused.red(x, y)
               || idle.green(x, y) !== focused.green(x, y)
               || idle.blue(x, y) !== focused.blue(x, y),
               "keyboard focus changes the original inset outline color")
        testCase.clickAutomationTab(trackTab)
        tryVerify(function() { return bootstrap.automationActiveParameterIndex() === trackTab }, 2000,
                  "the pointer switched the active parameter")

        // The explicit selection survives a parameter switch, and the switch
        // writes nothing to the document.
        var ticksBefore = bootstrap.automationLaneTicks()
        var bandRow = testCase.automationFreePoint()
        verify(bandRow, "the lane leaves a pointer row clear of every drawn node")
        testCase.automationModel().dismissMenu()
        wait(0)
        var bandInput = testCase.automationPlotInput()
        // The band's ends snap to the document's own lattice, so the range covers
        // the rest of the visible plot rather than a pixel span that may not leave
        // the bar the press landed in.
        var bandFrom = bandRow.x
        var bandTo = bandInput.width - 4
        mousePress(bandInput, bandFrom, bandRow.y, Qt.RightButton)
        mouseMove(bandInput, bandTo, bandRow.y, -1, Qt.RightButton)
        compare(model.bandVisible, true, "the band stayed visible until its release")
        mouseRelease(bandInput, bandTo, bandRow.y, Qt.RightButton)
        var selected = bootstrap.automationSelectionRange()
        compare(selected.length > 0, true,
                "the right-button band published the explicit selection ('" + selected
                + "' from " + bandFrom + " to " + bandTo + " in a "
                + bandInput.width + "-wide plot)")
        var bounds = selected.split(":")
        compare(parseInt(bounds[0]) < parseInt(bounds[1]), true,
                "the published band spans a tick range (" + selected + ")")
        testCase.clickAutomationTab(emptyTab)
        tryVerify(function() { return bootstrap.automationActiveParameterIndex() === emptyTab }, 2000,
                  "a second tab click switched again")
        testCase.clickAutomationTab(trackTab)
        tryVerify(function() { return bootstrap.automationActiveParameterIndex() === trackTab }, 2000,
                  "the tab switched back")
        compare(bootstrap.automationLaneTicks(), ticksBefore,
                "switching parameters wrote nothing to the lane")
        compare(bootstrap.automationSelectionRange(), selected,
                "the explicit selection survives a parameter switch")
        var insideBand = (bandFrom + bandTo) / 2
        mouseClick(bandInput, insideBand, bandRow.y, Qt.RightButton)
        compare(bootstrap.automationSelectionRange(), selected,
                "a stationary right click inside the selected time range preserves it")
        keyClick(Qt.Key_Escape)
        mousePress(bandInput, insideBand, bandRow.y, Qt.RightButton)
        mouseMove(bandInput, insideBand, bandRow.y > 32 ? bandRow.y - 32 : bandRow.y + 32,
                  -1, Qt.RightButton)
        mouseRelease(bandInput, insideBand, bandRow.y > 32 ? bandRow.y - 32 : bandRow.y + 32,
                     Qt.RightButton)
        compare(bootstrap.automationSelectionRange(), "",
                "an activated band with zero snapped width clears the time range")
        compare(model.interactionActive, revisionBefore,
                "a parameter switch leaves no interaction live")

        // Control press on another row pins its curve as a ghost and toggles it
        // off again; the active row's own Control press is the rule that clears
        // every pin. The page publishes the pinned set throughout.
        var ghostTab = model.tabCount - 1
        testCase.pressAutomationTabWithControl(ghostTab)
        tryVerify(function() { return bootstrap.automationGhostParameters().length > 0 }, 2000,
                  "the Control press pinned the Tempo row as a ghost")
        tryVerify(function() {
            var drawn = testCase.automationCurveItems()
            return drawn.length > 0
        }, 2000, "the selector drew the active curve over its ghost")
        compare(bootstrap.automationLaneTicks(), ticksBefore,
                "pinning a ghost wrote nothing to the lane")
        testCase.pressAutomationTabWithControl(ghostTab)
        tryVerify(function() { return bootstrap.automationGhostParameters().length === 0 }, 2000,
                  "a second Control press cleared the pin")
        testCase.pressAutomationTabWithControl(ghostTab)
        tryVerify(function() { return bootstrap.automationGhostParameters().length > 0 }, 2000,
                  "a third Control press pinned it again")
        testCase.pressAutomationTabWithControl(trackTab)
        tryVerify(function() { return bootstrap.automationGhostParameters().length === 0 }, 2000,
                  "the active row's own Control press cleared every pin")
        compare(bootstrap.automationLaneTicks(), ticksBefore,
                "the ghost pins still wrote nothing to the lane")
    }

    // The five reopened domain rows through real input: a drag sweep steps its
    // lattice and restores the trailing held value, a Shift sweep ramps, a Pan
    // drag snaps to the neutral, a node drag moves one occurrence (and a
    // Shift-held stationary release deletes nothing), and a pencil stroke writes
    // its point range.
    function test_productionAutomationDomainRowsThroughInput() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = bootstrap.preferencesUrl("production-automation-rows")
        testCase.mountProductionAutomation(location)
        var model = testCase.automationModel()
        var input = testCase.automationPlotInput()
        var volumeTab = bootstrap.automationVolumeIndex()
        verify(volumeTab >= 0, "the catalog publishes the Volume parameter")
        testCase.clickAutomationTab(volumeTab)
        tryVerify(function() { return bootstrap.automationActiveParameterIndex() === volumeTab }, 2000,
                  "the Volume lane is active")

        // a) A drag sweep over the lane: every crossed lattice tick is written,
        // and the trailing held value is restored one step past the release.
        var before = bootstrap.automationLaneValues()
        var nodes = testCase.automationLaneNodes()
        compare(nodes.length > 1, true,
                "the Volume lane projects more than one display point (" + nodes.length + ")")
        var free = testCase.automationFreePoint()
        verify(free, "the lane leaves an empty press point for a sweep ("
               + testCase.automationLaneNodes().length + " nodes)")
        mousePress(input, free.x, free.y, Qt.LeftButton)
        mouseMove(input, Math.min(input.width - 4, free.x + 80), free.y, -1, Qt.LeftButton)
        mouseMove(input, Math.min(input.width - 4, free.x + 160), free.y, -1, Qt.LeftButton)
        tryVerify(function() { return testCase.automationPreviewItems().length > 0 }, 1000,
                  "the moving sweep published its draft markers")
        mouseRelease(input, Math.min(input.width - 4, free.x + 160), free.y, Qt.LeftButton)
        var swept = bootstrap.automationLaneValues()
        compare(swept !== before, true,
                "the released sweep committed a document change (" + swept + " of " + before + ")")
        compare(bootstrap.automationLaneTicks().split(",").length > 1, true,
                "sweepSteppingAndRampFinish: the swept lane carries more than one written tick")

        // b) A Shift sweep is the ramp: its end value differs from its anchor.
        testCase.dragAutomationPlot(free.x, free.y, Math.min(input.width - 4, free.x + 220),
                                    free.y < input.height / 2 ? input.height * 0.8
                                                              : input.height * 0.2,
                                    Qt.ShiftModifier)
        compare(bootstrap.automationLaneValues() !== swept, true,
                "sweepSteppingAndRampFinish: the ramp sweep committed a document change")
        compare(session.canUndo, true, "the ramp sweep reached the document history")

        // c) The Pan lane's neutral snap: the case empties the lane, writes two
        // of its own rows, and the Control-armed drag settles just inside the
        // neutral radius — the same drag without the modifier keeps the pointer's
        // own value, so the snap is the modifier's own work.
        var panTab = bootstrap.automationPanIndex()
        verify(panTab >= 0, "the catalog publishes the Pan parameter")
        verify(testCase.clearAutomationLane(panTab), "the Pan lane starts empty")
        var highColumn = testCase.automationFreeColumn(24)
        verify(highColumn > 0, "the empty Pan lane leaves a column for its first row")
        testCase.dragAutomationPlot(highColumn, Math.round(input.height * 0.15),
                                    Math.min(input.width - 4, highColumn + 96),
                                    Math.round(input.height * 0.15))
        tryVerify(function() { return bootstrap.automationLaneEventCount() > 0 }, 2000,
                  "the Pan sweep wrote its first row")
        var lowColumn = testCase.automationFreeColumn(highColumn + 140)
        verify(lowColumn > 0, "the lane leaves a column for its second row")
        testCase.dragAutomationPlot(lowColumn, Math.round(input.height * 0.85),
                                    Math.min(input.width - 4, lowColumn + 96),
                                    Math.round(input.height * 0.85))
        tryVerify(function() { return testCase.automationLaneNodes().length > 1 }, 2000,
                  "the Pan lane projects both written rows")
        var neutralRow = testCase.automationRowForValue(64)
        compare(neutralRow > 0, true,
                "the drawn rows name the neutral's own row (" + Math.round(neutralRow) + ")")
        var panNodes = testCase.automationLaneNodes()
        var panItem = null
        for (var p = 0; p < panNodes.length; ++p) {
            if (!panNodes[p].model.projected && Math.abs(panNodes[p].model.value - 64) >= 20) {
                panItem = panNodes[p]
                break
            }
        }
        verify(panItem, "the written Pan lane draws a node away from the neutral ("
               + panNodes.length + " drawn)")
        var panPoint = testCase.automationNodePoint(panItem)
        verify(panPoint, "the Pan node projects a drawn centre")
        var panTick = String(panItem.model.tick)
        var panValue = panItem.model.value
        var panBefore = bootstrap.automationLaneValues()
        compare(panBefore.indexOf(panTick + ":64") >= 0, false,
                "the dragged Pan node starts away from the neutral (" + panTick + ":"
                + panValue + " of " + panBefore + ")")
        var settleRow = neutralRow + 2
        testCase.dragAutomationPlotRow(panPoint.x, panPoint.y, panPoint.y - 30, settleRow)
        var unsnapped = bootstrap.automationLaneValues()
        compare(unsnapped !== panBefore, true,
                "the same drag without the modifier moved the node (" + panTick + ":"
                + panValue + " of " + panBefore + " became " + unsnapped + ")")
        compare(unsnapped.indexOf(panTick + ":64") >= 0, false,
                "the same drag without the modifier keeps the pointer's own value ("
                + unsnapped + ")")
        verify(bootstrap.requestAutomationUndo(), "the production undo completed (error='"
               + session.lastSaveError + "')")
        compare(bootstrap.automationLaneValues(), panBefore, "Undo restored the written Pan lane")
        var restored = testCase.automationWrittenNodeIndex()
        panPoint = restored < 0 ? null
                                : testCase.automationNodePoint(testCase.automationLaneNodes()[restored])
        verify(panPoint, "the restored Pan lane draws its node again")
        testCase.dragAutomationPlotRow(panPoint.x, panPoint.y, panPoint.y - 30, settleRow,
                                       Qt.ControlModifier)
        var snapped = bootstrap.automationLaneValues()
        compare(snapped.indexOf(panTick + ":64") >= 0, true,
                "panNeutralSnap: the Control-armed drag committed the neutral 64 at the node's own"
                + " tick (" + snapped + ")")
        compare(snapped.split(",").length, panBefore.split(",").length,
                "the snap moved the value without adding or dropping an occurrence")

        // d) A node drag on the Volume lane moves one occurrence, and a
        // Shift-held stationary release deletes nothing.
        testCase.clickAutomationTab(volumeTab)
        tryVerify(function() { return bootstrap.automationActiveParameterIndex() === volumeTab }, 2000,
                  "the Volume lane is active again")
        var dragged = testCase.automationLaneNodes()
        verify(dragged.length > 0, "the swept Volume lane still projects nodes")
        var first = testCase.automationNodePoint(dragged[0])
        var valuesBefore = bootstrap.automationLaneValues()
        testCase.dragAutomationPlot(first.x, first.y, first.x, first.y - 30)
        compare(bootstrap.automationLaneValues() !== valuesBefore, true,
                "nodeDragAndPhantomOutcomes: the released node drag moved its value ("
                + bootstrap.automationLaneValues() + ")")
        var afterMove = bootstrap.automationLaneValues()
        var shiftNode = testCase.automationNodePoint(testCase.automationLaneNodes()[0])
        testCase.dragAutomationPlot(shiftNode.x, shiftNode.y, shiftNode.x, shiftNode.y,
                                    Qt.ShiftModifier)
        compare(bootstrap.automationLaneValues(), afterMove,
                "nodeDragAndPhantomOutcomes: a Shift-held stationary release deletes nothing")

        // e) The pencil tool: a stroke writes the point range it crossed.
        var pencilNode = testCase.automationNodePoint(testCase.automationLaneNodes()[0])
        model.isPencilMode = true
        wait(0)
        var beforeStroke = bootstrap.automationLaneValues()
        testCase.dragAutomationPlot(pencilNode.x, pencilNode.y, pencilNode.x + 24, pencilNode.y + 6)
        compare(bootstrap.automationLaneValues() !== beforeStroke, true,
                "pointRangeAndPencilReplacements: the pencil stroke committed its range ("
                + bootstrap.automationLaneValues() + ")")
        model.isPencilMode = false
        wait(0)
        compare(session.canUndo, true, "the stroke reached the document history")
    }

    // The point menu and the prompt: a right press on a node opens its own typed
    // rows, Set Value opens the captured value form, a typed draft commits one
    // transaction, and both cancel paths write nothing and leave no frozen state.
    function test_productionAutomationPromptTransaction() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = bootstrap.preferencesUrl("production-automation-prompt")
        testCase.mountProductionAutomation(location)
        var model = testCase.automationModel()
        var volumeTab = bootstrap.automationVolumeIndex()
        verify(testCase.writeVolumeLanePoints(volumeTab),
               "the case created a written Volume lane with a real sweep")
        var input = testCase.automationPlotInput()
        var nodes = testCase.automationLaneNodes()
        verify(nodes.length > 0, "the Volume lane projects a written node")
        var valuesBefore = bootstrap.automationLaneValues()

        // The node's own menu, driven by a real right press.
        var writtenIndex = testCase.automationWrittenNodeIndex()
        verify(writtenIndex >= 0, "the Volume lane draws a written node")
        verify(testCase.rightClickAutomationNode(writtenIndex), "the written node has a centre")
        tryVerify(function() { return bootstrap.automationMenuOpen() }, 2000,
                  "the right press on the node opened its menu")
        testCase.awaitAutomationModal("automationMenu", true)
        compare(bootstrap.automationMenuActions(), "1,2",
                "the point menu publishes Set Value and Delete")
        var panel = findChild(testCase.surface, "automationMenuPanel")
        verify(panel, "the menu composed its panel")
        compare(findChild(panel, "quickMenuFrame").Accessible.role, Accessible.PopupMenu,
                "the drawn menu frame publishes the popup-menu role")
        var rows = testCase.automationMenuRowItems()
        compare(rows.length, 2, "the point menu drew its two rows")
        compare(rows[0].Accessible.role, Accessible.MenuItem, "a row publishes the menu-item role")
        compare(String(rows[0].Accessible.name).length > 0, true,
                "a row publishes its accessible name ('" + rows[0].Accessible.name + "')")
        testCase.auditVisibleTextInk(panel, "automation point menu")
        var menuRowTexts = testCase.collectVisibleTexts(rows[0], [])
        compare(menuRowTexts.length > 0 && String(menuRowTexts[0].text).length > 0, true,
                "the menu draws its row label ('" + (menuRowTexts.length > 0 ? menuRowTexts[0].text : "") + "')")

        // Set Value opens the captured form.
        compare(bootstrap.automationMenuActions().indexOf("1") >= 0, true,
                "the captured point menu publishes Set Value ("
                + bootstrap.automationMenuActions() + ")")
        verify(testCase.triggerAutomationMenuRow(1), "the Set Value row is the current one")
        compare(bootstrap.automationPromptOpen(), true,
                "Set Value opened the captured form")
        testCase.awaitAutomationModal("automationPrompt", true)
        var field = findChild(testCase.automationPageItem(), "automationPromptInput")
        verify(field, "the prompt composed its value field")
        tryVerify(function() { return field.activeFocus }, 2000,
                  "the prompt took active focus in its field")
        compare(model.promptDraft.length > 0, true, "the prompt opened with the captured value")
        var autoPrompt = findChild(testCase.surface, "automationPrompt")
        verify(autoPrompt, "the prompt composed its production surface")
        testCase.auditVisibleTextInk(autoPrompt, "automation prompt")

        // A typed draft commits exactly one transaction.
        field.selectAll()
        keyClick(Qt.Key_9)
        wait(0)
        compare(field.text, "9", "typing replaced the selected numeric text")
        compare(bootstrap.automationLaneValues(), valuesBefore, "typing committed nothing")
        keyClick(Qt.Key_Return)
        tryVerify(function() { return !model.promptOpen }, 2000, "Enter accepted the prompt")
        tryVerify(function() { return bootstrap.automationLaneValues() !== valuesBefore }, 2000,
                  "the accepted value reached the captured node ("
                  + bootstrap.automationLaneValues() + ")")
        compare(bootstrap.automationFrozenRevision() < 0, true,
                "an accepted prompt leaves no frozen revision behind")

        // An out-of-domain intermediate draft is refused locally by the original
        // IntValidator; Return leaves it open without document or history writes.
        verify(testCase.openAutomationNodeMenu(testCase.automationWrittenNodeIndex()),
               "the written node's menu reopened for the draft case")
        verify(testCase.triggerAutomationMenuRow(1), "the Set Value row is the current one")
        testCase.awaitAutomationModal("automationPrompt", true)
        field = findChild(testCase.automationPageItem(), "automationPromptInput")
        verify(field, "the prompt composed its value field again")
        var invalid = String(Number(model.promptMaximum) + 1)
        var promptValues = bootstrap.automationLaneValues()
        var promptRevision = bootstrap.automationDocumentRevision()
        var undoBefore = session.canUndo
        field.selectAll()
        for (var digit = 0; digit < invalid.length; ++digit)
            keyClick(Qt.Key_0 + Number(invalid.charAt(digit)))
        wait(0)
        compare(field.text, invalid,
                "the field took the out-of-domain digits (" + invalid + ")")
        keyClick(Qt.Key_Return)
        wait(0)
        compare(bootstrap.automationPromptOpen(), true,
                "the refused acceptance left the prompt open")
        compare(bootstrap.automationLaneValues(), promptValues,
                "the refused acceptance wrote nothing")
        compare(bootstrap.automationDocumentRevision(), promptRevision,
                "the refused acceptance published no revision")
        compare(session.canUndo, undoBefore, "the refused acceptance recorded no history entry")
        var valid = String(Number(model.promptMaximum) - 1)
        field.selectAll()
        for (var validDigit = 0; validDigit < valid.length; ++validDigit)
            keyClick(Qt.Key_0 + Number(valid.charAt(validDigit)))
        compare(field.text, valid, "the user corrected the intermediate draft")
        keyClick(Qt.Key_Return)
        tryVerify(function() { return !bootstrap.automationPromptOpen() }, 2000,
                  "the valid draft accepted through the form's own route")

        // Escape cancels with no write, and leaves no frozen revision.
        var accepted = bootstrap.automationLaneValues()
        verify(testCase.openAutomationNodeMenu(testCase.automationWrittenNodeIndex()),
               "the written node's menu reopened")
        verify(testCase.triggerAutomationMenuRow(1),
               "the reopened menu's Set Value row is the current one")
        compare(bootstrap.automationPromptOpen(), true,
                "the prompt reopened")
        testCase.awaitAutomationModal("automationPrompt", true)
        compare(bootstrap.automationFrozenRevision() >= 0, true,
                "an open prompt holds the revision it captured")
        keyClick(Qt.Key_Escape)
        tryVerify(function() { return !bootstrap.automationPromptOpen() }, 2000,
                  "Escape closed the prompt")
        compare(bootstrap.automationLaneValues(), accepted, "Escape wrote nothing")
        compare(bootstrap.automationFrozenRevision(), -1,
                "a cancelled prompt leaves no frozen revision behind")
        verify(bootstrap.cancelInput(), "the composition's own cancellation settles the page")
        compare(bootstrap.automationInteractionActive(), false,
                "the cancelled page reports no interaction")

        // An outside press dismisses without a write.
        verify(testCase.openAutomationNodeMenu(testCase.automationWrittenNodeIndex()),
               "the written node's menu opened once more")
        verify(testCase.triggerAutomationMenuRow(1),
               "the menu's Set Value row is the current one once more")
        compare(bootstrap.automationPromptOpen(), true,
                "the prompt reopened once more")
        testCase.awaitAutomationModal("automationPrompt", true)
        var underlay = findChild(testCase.surface, "automationPromptUnderlay")
        verify(underlay, "the prompt composed its dismissing underlay")
        mouseClick(underlay, 4, 4, Qt.LeftButton)
        tryVerify(function() { return !bootstrap.automationPromptOpen() }, 2000,
                  "an outside press dismissed the prompt")
        compare(bootstrap.automationLaneValues(), accepted, "the outside dismissal wrote nothing")
        compare(bootstrap.automationFrozenRevision(), -1,
                "the dismissed prompt left no frozen revision either")
    }

    // The point menu's Delete and the lane menu's own commands: a written node is
    // deletable, the projected engine node's row is disabled and never acts, the
    // lane menu publishes the production labels, and an unavailable row is
    // refused rather than silently reported as done.
    function test_productionAutomationRangeSubmenu() {
        if (testCase.containerPhase) skip("production composition only")
        testCase.mountProductionAutomation(bootstrap.preferencesUrl("automation-range-submenu"))
        var volume = bootstrap.automationVolumeIndex()
        testCase.clickAutomationTab(volume)
        var revision = bootstrap.automationDocumentRevision()
        var undo = session.canUndo
        var redo = session.canRedo
        testCase.openAutomationTabMenu(volume)
        var menuPanel = findChild(testCase.surface, "automationMenuPanel")
        var childPanel = findChild(testCase.surface, "automationMenuSubmenu")
        var range = testCase.menuRowByAction(menuPanel, 12)
        verify(range, "Volume offers the historical Value range submenu")
        mouseMove(range, range.width / 2, range.height / 2)
        tryVerify(function() {
            var child = testCase.menuRowByAction(childPanel, 16)
            return child && testCase.isEffectivelyVisible(child)
        }, 1000, "hover reveals the hierarchical range choices")
        var full = testCase.menuRowByAction(childPanel, 17)
        compare(full.model.checked, true, "Volume initially uses the full range")
        var range64 = testCase.menuRowByAction(childPanel, 16)
        mouseClick(range64, range64.width / 2, range64.height / 2, Qt.LeftButton)
        testCase.awaitAutomationModal("automationMenu", false)
        testCase.openAutomationTabMenu(volume)
        range = testCase.menuRowByAction(menuPanel, 12)
        mouseMove(range, range.width / 2, range.height / 2)
        tryVerify(function() {
            var child = testCase.menuRowByAction(childPanel, 16)
            return child && child.model.checked
        }, 1000, "reopening remembers the selected 64 range")
        var checked = 0
        for (var action = 13; action <= 17; ++action) {
            var child = testCase.menuRowByAction(childPanel, action)
            verify(child, "every historical range choice is drawn")
            if (child.model.checked) ++checked
        }
        compare(checked, 1, "exactly one range is checked")
        keyClick(Qt.Key_Escape)
        keyClick(Qt.Key_Escape)
        testCase.openAutomationTabMenu(volume)
        keyClick(Qt.Key_Left)
        for (var step = 0; step < 12 && testCase.currentAutomationMenuAction() !== 12; ++step)
            keyClick(Qt.Key_Down)
        compare(testCase.currentAutomationMenuAction(), 12)
        keyClick(Qt.Key_Right)
        keyClick(Qt.Key_End)
        keyClick(Qt.Key_Return)
        testCase.awaitAutomationModal("automationMenu", false)
        testCase.openAutomationTabMenu(volume)
        range = testCase.menuRowByAction(menuPanel, 12)
        mouseMove(range, range.width / 2, range.height / 2)
        tryVerify(function() {
            var child = testCase.menuRowByAction(childPanel, 17)
            return child && child.model.checked
        }, 1000, "keyboard selection restored the full range")
        keyClick(Qt.Key_Escape)
        keyClick(Qt.Key_Escape)
        compare(bootstrap.automationDocumentRevision(), revision, "range choices are view-only")
        compare(session.canUndo, undo, "range choices add no undo entry")
        compare(session.canRedo, redo, "range choices preserve redo history")
    }

    function test_productionAutomationOutsideRightRetarget() {
        if (testCase.containerPhase) skip("production composition only")
        testCase.mountProductionAutomation(bootstrap.preferencesUrl("automation-menu-retarget"))
        verify(testCase.writeVolumeLanePoints(bootstrap.automationVolumeIndex()))
        var nodes = testCase.automationLaneNodes()
        var first = testCase.automationWrittenNodeIndex()
        verify(first >= 0)
        var firstTick = nodes[first].model.tick
        verify(testCase.openAutomationNodeMenu(first))
        var panel = findChild(testCase.surface, "automationMenuPanel")
        panel = findChild(panel, "quickMenuFrame")
        verify(panel, "the point menu has a drawn frame")
        var targetIndex = -1
        for (var i = 0; i < nodes.length; ++i) {
            if (i === first || nodes[i].model.projected) continue
            var p = testCase.automationNodePoint(nodes[i])
            var local = panel.mapFromItem(testCase.automationPlotInput(), p.x, p.y)
            if (local.x < 0 || local.x > panel.width || local.y < 0 || local.y > panel.height) {
                targetIndex = i
                break
            }
        }
        verify(targetIndex >= 0, "another written node lies outside the open menu")
        var targetTick = nodes[targetIndex].model.tick
        // Retargeting rebuilds the menu too; use the same drawn-row and keyboard
        // readiness contract as the initial open rather than the old open flag.
        verify(testCase.openAutomationNodeMenu(targetIndex))
        compare(bootstrap.automationMenuOpen(), true, "outside right click retargets rather than dismisses")
        verify(testCase.triggerAutomationMenuRow(2))
        var remaining = bootstrap.automationLaneTicks().split(",")
        compare(remaining.indexOf(String(targetTick)), -1, "Delete acts on the newly hit node")
        verify(remaining.indexOf(String(firstTick)) >= 0, "the original menu target survives")
    }

    function test_productionAutomationMenusAndLaneCommands() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = bootstrap.preferencesUrl("production-automation-menus")
        testCase.mountProductionAutomation(location)
        var model = testCase.automationModel()
        var volumeTab = bootstrap.automationVolumeIndex()
        verify(testCase.writeVolumeLanePoints(volumeTab),
               "the case created a written Volume lane with a real sweep")
        var input = testCase.automationPlotInput()
        var nodes = testCase.automationLaneNodes()
        verify(nodes.length > 0, "the Volume lane projects a written node")
        var ticksBefore = bootstrap.automationLaneTicks()

        // The lane menu of the active tab: Copy CC lane, Paste CC lane (replace),
        // Clear events and Delete automation events.
        testCase.openAutomationTabMenu(volumeTab)
        var actions = bootstrap.automationMenuActions().split(",")
        compare(actions.length >= 5, true,
                "the lane menu publishes its production rows (" + actions.join("/") + ")")
        compare(actions.indexOf("5") >= 0, true, "the lane menu publishes Clear events")
        compare(actions.indexOf("6") >= 0, true,
                "the CC lane menu publishes Delete automation events")
        compare(testCase.automationMenuSeparatorItems().length, 1,
                "the lane menu drew its separator")
        for (var a = 0; a < actions.length; ++a) {
            if (actions[a] === "-1")
                continue
            compare(testCase.automationMenuRowItems().filter(function(item) {
                return item.objectName === "automationMenuRow_" + actions[a]
            }).length, 1, "the menu drew exactly one row for action " + actions[a])
        }
        compare(testCase.automationMenuRowItems().length,
                actions.length - testCase.automationMenuSeparatorItems().length,
                "the menu drew one action row per published action ("
                + testCase.automationMenuRowItems().length + " of " + actions.length + ")")

        // Copy CC lane fills the accepted clipboard, which enables Paste.
        verify(testCase.triggerAutomationMenuRow(3), "the Copy CC lane row is reachable")
        wait(0)
        compare(bootstrap.automationLaneClipAvailable(), true,
                "Copy CC lane filled the accepted clipboard for this parameter")
        testCase.openAutomationTabMenu(volumeTab)
        verify(testCase.triggerAutomationMenuRow(4), "the Paste CC lane (replace) row is reachable")
        tryVerify(function() { return !bootstrap.automationMenuOpen() }, 2000,
                  "the paste consumed the menu")

        // Clear events writes the lane empty; the point menu's disabled Delete on
        // a projected node is refused without a write.
        var clearedBefore = bootstrap.automationLaneEventCount()
        testCase.openAutomationTabMenu(volumeTab)
        verify(testCase.triggerAutomationMenuRow(5), "the Clear events row is reachable")
        tryVerify(function() { return !bootstrap.automationMenuOpen() }, 2000,
                  "the clear consumed the menu")
        compare(clearedBefore > 0, true, "the lane held written events before the clear")
        tryVerify(function() { return bootstrap.automationLaneEventCount() === 0 }, 2000,
                  "Clear events left the lane empty")

        // Delete through the rendered row removes exactly the captured occurrence:
        // a written occurrence's row, because the projected engine node's row is
        // published disabled — and the clear above emptied the lane, so this case
        // writes its own points again with a real sweep.
        verify(testCase.writeVolumeLanePoints(volumeTab),
               "the case wrote the lane again for the delete step")
        var writtenIndex = testCase.automationWrittenNodeIndex()
        verify(writtenIndex >= 0, "the Volume lane draws a written node")
        ticksBefore = bootstrap.automationLaneTicks()
        verify(testCase.rightClickAutomationNode(writtenIndex), "the written node has a centre")
        tryVerify(function() { return bootstrap.automationMenuOpen() }, 2000,
                  "the node menu opened")
        testCase.awaitAutomationModal("automationMenu", true)
        verify(testCase.clickAutomationMenuRow(2), "the Delete row is drawn")
        tryVerify(function() { return bootstrap.automationLaneTicks() !== ticksBefore }, 2000,
                  "the rendered Delete row removed the captured occurrence ("
                  + bootstrap.automationLaneTicks() + " of " + ticksBefore + ")")
        compare(bootstrap.automationMenuOpen(), false, "activating a row consumes the menu")
        compare(session.canUndo, true, "the deletion reached the document's history")

        // Delete automation events: the destructive lane row opens the page's
        // captured confirmation (the sibling `cc-delete-confirm` form), and its
        // acceptance is the one write that empties the lane.
        verify(testCase.writeVolumeLanePoints(volumeTab),
               "the case wrote the lane again for the confirmation")
        var beforeConfirmation = bootstrap.automationLaneEventCount()
        compare(beforeConfirmation > 0, true, "the lane carries events before the confirmation")
        testCase.openAutomationTabMenu(volumeTab)
        verify(testCase.triggerAutomationMenuRow(6), "the Delete automation events row is reachable")
        compare(bootstrap.automationPromptOpen(), true,
                "the destructive row opened the captured confirmation")
        testCase.awaitAutomationModal("automationPrompt", true)
        compare(testCase.automationModel().promptKind, 1,
                "the open form is the lane-delete confirmation")
        var cancel = findChild(testCase.surface, "automationPromptCancel")
        tryVerify(function() { return cancel && cancel.activeFocus }, 1000,
                  "the destructive confirmation initially focuses Cancel")
        var revision = bootstrap.automationDocumentRevision()
        keyClick(Qt.Key_Return)
        tryVerify(function() { return !bootstrap.automationPromptOpen() }, 2000,
                  "initial Return cancels the destructive confirmation")
        compare(bootstrap.automationLaneEventCount(), beforeConfirmation,
                "initial Return preserves every written event")
        compare(bootstrap.automationDocumentRevision(), revision,
                "initial Return records no document change")
        verify(testCase.clearAutomationLane(volumeTab),
               "an explicit Delete pointer activation empties the lane")

        // A projected engine node: the case writes a lane whose first occurrence
        // is after tick zero, so the visible tick-zero column draws the engine's
        // own projection — its Delete row is published disabled and an activation
        // attempt performs nothing.
        testCase.clickAutomationTab(volumeTab)
        tryVerify(function() { return bootstrap.automationActiveParameterIndex() === volumeTab }, 2000,
                  "the Volume lane is active for the projection")
        var row = testCase.automationFreePoint()
        verify(row, "the lane leaves a pointer row clear of every drawn node")
        // A sweep across the second half of the visible plot: its occurrences all
        // start well after tick zero, which is the column the projection needs.
        var farColumn = testCase.automationFreeColumn(Math.round(input.width * 0.45), row.y)
        verify(farColumn > 0, "the lane leaves a column clear of every node past its middle")
        testCase.dragAutomationPlot(farColumn, row.y,
                                    Math.min(input.width - 4, farColumn + 96), row.y)
        tryVerify(function() { return bootstrap.automationLaneEventCount() > 0 }, 2000,
                  "the sweep left the Volume lane written events")
        compare(bootstrap.automationLaneTicks().split(",").indexOf("0"), -1,
                "the written lane starts after tick zero (" + bootstrap.automationLaneTicks() + ")")
        var projected = null
        var atZero = testCase.automationNodesAtTick(0)
        for (var z = 0; z < atZero.length; ++z) {
            if (atZero[z].model.projected === true)
                projected = atZero[z]
        }
        verify(projected, "the visible tick-zero column draws the projected engine node ("
               + atZero.length + " drawn at tick zero)")
        var projectedPoint = testCase.automationNodePoint(projected)
        verify(projectedPoint, "the projected node projects a drawn centre")
        mouseClick(input, projectedPoint.x, projectedPoint.y, Qt.RightButton)
        wait(0)
        tryVerify(function() { return bootstrap.automationMenuOpen() }, 2000,
                  "the projected node opened its own menu")
        testCase.awaitAutomationModal("automationMenu", true)
        var disabledRow = null
        var drawn = testCase.automationMenuRowItems()
        for (var d = 0; d < drawn.length; ++d) {
            if (drawn[d].objectName === "automationMenuRow_2")
                disabledRow = drawn[d]
        }
        verify(disabledRow, "the projected node's Delete row is drawn")
        compare(disabledRow.model.enabled, false,
                "the projected engine node's Delete row is published disabled")
        var beforeDisabled = bootstrap.automationLaneTicks()
        testCase.clickAutomationMenuRow(2)
        wait(0)
        compare(bootstrap.automationLaneTicks(), beforeDisabled,
                "a disabled Delete row performs nothing")
        testCase.automationModel().dismissMenu()
        wait(0)
    }

    // The Tempo row's Tap control through real input: a pointer tap and a
    // keyboard tap register on the control, the page averages the tapped
    // intervals, cancelling the session writes nothing, and the idle window
    // lands exactly one tempo edit and one history entry.
    function test_productionAutomationTapTempoThroughInput() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = bootstrap.preferencesUrl("production-automation-tap")
        testCase.mountProductionAutomation(location)
        var model = testCase.automationModel()
        var tempoTab = testCase.revealAutomationTab(model.tabCount - 1)
        verify(tempoTab, "the Tempo row is drawn in the selector")
        var tapControl = findChild(tempoTab, "automationTempoTapButton")
        verify(tapControl, "the Tempo row composed its Tap control")
        var tempoBefore = bootstrap.automationTempoBpm()
        verify(tempoBefore > 0, "the staged song names a tick-zero tempo (" + tempoBefore + ")")
        var revisionBefore = bootstrap.automationDocumentRevision()
        var undoBefore = session.canUndo
        compare(String(tapControl.Accessible.name).length > 0, true,
                "the Tap control publishes its accessible name ('" + tapControl.Accessible.name + "')")

        // A real pointer press on the Tap control registers one tap at the event
        // boundary, and the panel publishes the live session.
        mouseClick(tapControl, tapControl.width / 2, tapControl.height / 2, Qt.LeftButton)
        tryVerify(function() { return bootstrap.automationTapCount() >= 1 }, 2000,
                  "the pointer tap registered a tap")
        compare(bootstrap.automationInteractionActive(), true,
                "a live tap session is the page's interaction fact")
        compare(bootstrap.automationDocumentRevision(), revisionBefore,
                "tapping writes nothing to the document")
        compare(session.canUndo, undoBefore, "tapping records no history entry")

        // The keyboard's own tap: Return on the focused control.
        testCase.focusControl(tapControl)
        keyClick(Qt.Key_Return)
        wait(0)
        compare(bootstrap.automationTapCount() >= 1, true,
                "Return on the focused Tap control registered a tap")
        verify(bootstrap.automationTapIdleCommitMs() > 0,
               "the panel published its idle commit window ("
               + bootstrap.automationTapIdleCommitMs() + " ms)")

        // Cancelling the session takes the draft with it and writes nothing.
        testCase.resetAutomationTap()
        compare(bootstrap.automationTapCount(), 0, "the cancel cleared the tap session")
        compare(bootstrap.automationTempoBpm(), tempoBefore,
                "a cancelled session wrote no tempo")
        compare(bootstrap.automationDocumentRevision(), revisionBefore,
                "a cancelled session published no revision")
        compare(session.canUndo, undoBefore, "a cancelled session recorded no history entry")

        // One deterministic cadence: the draft is the tapped average, and the
        // idle window commits that tempo as exactly one edit and one entry. The
        // gaps are chosen so the draft cannot name the tempo already in place.
        var gapMs = (tempoBefore === 150) ? 500 : 400
        var taps = 4
        var expectedDraft = (tempoBefore === 150) ? 120 : 150
        verify(bootstrap.automationTapCadence(gapMs, taps),
               "the production tap route took the cadence")
        compare(bootstrap.automationTapDraftBpm(), expectedDraft,
                "the draft is the tapped average (" + bootstrap.automationTapDraftBpm() + ")")
        compare(bootstrap.automationTapCount(), taps, "the session holds every tap")
        verify(bootstrap.automationTapIdleElapsed(), "the idle window committed the ready draft")
        tryVerify(function() { return bootstrap.automationTempoBpm() === expectedDraft }, 2000,
                  "the tick-zero tempo now names the tapped tempo ("
                  + bootstrap.automationTempoBpm() + ")")
        compare(session.canUndo, true, "the tempo edit recorded one history entry")
        compare(bootstrap.automationDocumentRevision() > revisionBefore, true,
                "the tempo edit published its own revision")
        compare(bootstrap.automationTapCount(), 0, "the commit cleared the session")
        compare(bootstrap.automationInteractionActive(), false,
                "the committed session left no interaction live")
        var committedRevision = bootstrap.automationDocumentRevision()
        compare(committedRevision > revisionBefore, true,
                "the tempo edit published one revision")
        verify(bootstrap.requestAutomationUndo(), "the production undo completed (error='"
               + session.lastSaveError + "')")
        compare(bootstrap.automationTempoBpm(), tempoBefore,
                "Undo restored the previous tick-zero tempo")
        compare(session.canUndo, undoBefore, "the tempo edit was exactly one history entry")
        verify(bootstrap.requestAutomationRedo(), "the production redo completed (error='"
               + session.lastSaveError + "')")
        compare(bootstrap.automationTempoBpm(), expectedDraft, "Redo restored the tapped tempo")
        compare(bootstrap.automationDocumentRevision() >= committedRevision, true,
                "the undo and redo each published their own revision")

        // The panel's own readout is driven by the published session, and a
        // single tap is not commit-ready.
        verify(bootstrap.automationTapCadence(500, 3), "the production tap route took 500 ms gaps")
        compare(model.tapTempoTapCount, 3, "the panel publishes the live tap count")
        compare(model.tapTempoActive, true, "the panel publishes the live session")
        var inlineDraft = testCase.collectByName(tempoTab, "automationTempoTapDraft", [])[0]
        tryVerify(function() { return inlineDraft && inlineDraft.visible }, 1000,
                  "the live cadence is drawn inside the Tempo tab")
        tryCompare(inlineDraft, "text", "120 BPM", 1000,
                   "the original inline readout shows the tapped tempo")
        compare(bootstrap.automationTempoBpm(), expectedDraft,
                "a live session writes nothing until its idle window")
        testCase.resetAutomationTap()
        verify(bootstrap.automationTapCadence(500, 1), "the production tap route took a lone tap")
        compare(bootstrap.automationTapCount(), 1, "the lone tap stands in the session")
        verify(!bootstrap.automationTapIdleElapsed(),
               "a lone tap's idle window commits nothing")
        compare(bootstrap.automationTempoBpm(), expectedDraft,
                "a lone tap left the tempo stream alone")
    }

    // Mounted follow, cancellation ownership and history round trips: a playhead
    // observation re-projects without rebuilding static content, the page's own
    // gestures, modals and tap sessions are the only interactions that suspend
    // follow, the composition's cancellation reaches the page's capture without a
    // write, and one edit round-trips through Undo and Redo.
    function test_productionAutomationFollowAndCancellation() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = bootstrap.preferencesUrl("production-automation-follow")
        testCase.mountProductionAutomation(location)
        var input = testCase.automationPlotInput()
        var volumeTab = bootstrap.automationVolumeIndex()
        verify(volumeTab >= 0, "the catalog publishes the Volume parameter")
        verify(bootstrap.pausePlayheadPolling(),
               "the lane holds the production polling task for a deterministic position")
        var grid = testCase.surface.gridModel
        // ApplicationSession.playPause()'s playing transport raw value.
        var playing = 2
        var farSample = 100000000
        grid.resetCameraScroll()
        var parked = grid.cameraScrollX

        // One playhead observation follows, and the page re-projects without
        // rebuilding any of its static content.
        var builds = bootstrap.automationContentBuilds()
        var presentations = bootstrap.automationPlayheadPresentations()
        testCase.presentPlayhead(farSample, playing)
        tryVerify(function() { return grid.cameraScrollX !== parked }, 1000,
                  "an idle page lets follow scroll the camera")
        compare(bootstrap.automationPlayheadPresentations() > presentations, true,
                "the page received the shared presentation")
        compare(bootstrap.automationContentBuilds(), builds,
                "the follow scroll re-projects the lane without rebuilding static content")

        // The same observation with the camera already at its target publishes
        // nothing at all, so no static content is rebuilt.
        builds = bootstrap.automationContentBuilds()
        presentations = bootstrap.automationPlayheadPresentations()
        testCase.presentPlayhead(farSample, playing)
        compare(bootstrap.automationContentBuilds(), builds,
                "an unchanged shared-playhead observation rebuilds no static content")

        // A pointer merely resting on the plot is a hover, not an interaction.
        grid.setCameraHScroll(parked)
        var hovers = bootstrap.automationHoverBuilds()
        builds = bootstrap.automationContentBuilds()
        mouseMove(input, input.width - 4, input.height - 4, -1, Qt.NoButton, Qt.NoModifier)
        tryVerify(function() { return bootstrap.automationHoverBuilds() > hovers }, 1000,
                  "the pointer resting on the plot published its hover")
        compare(bootstrap.automationInteractionActive(), false,
                "a hover is not the page's interaction")
        testCase.presentPlayhead(farSample, playing)
        tryVerify(function() { return grid.cameraScrollX !== parked }, 1000,
                  "a hover never suspends follow")

        // A live gesture suspends follow, and its release resumes it.
        var free = testCase.automationFreePoint()
        verify(free, "the lane leaves an empty press point for a live gesture")
        mousePress(input, free.x, free.y, Qt.LeftButton)
        compare(bootstrap.automationInteractionActive(), true,
                "the live press is the page's interaction")
        compare(bootstrap.automationFrozenRevision() >= 0, true,
                "the live gesture froze the revision it captured")
        grid.setCameraHScroll(parked)
        builds = bootstrap.automationContentBuilds()
        testCase.presentPlayhead(farSample, playing)
        compare(grid.cameraScrollX, parked, "a live gesture suspends follow")
        compare(bootstrap.automationContentBuilds(), builds,
                "an observation under a live gesture rebuilds no static content")
        mouseRelease(input, free.x, free.y, Qt.LeftButton)
        compare(bootstrap.automationInteractionActive(), false,
                "the released gesture left no interaction live")
        testCase.presentPlayhead(farSample, playing)
        tryVerify(function() { return grid.cameraScrollX !== parked }, 1000,
                  "releasing the gesture lets the next observation follow")

        // An open menu suspends follow, and dismissing it resumes.
        testCase.openAutomationTabMenu(volumeTab)
        compare(bootstrap.automationMenuOpen(), true, "the lane menu is open")
        compare(bootstrap.automationInteractionActive(), true,
                "an open menu is the page's interaction")
        grid.setCameraHScroll(parked)
        testCase.presentPlayhead(farSample, playing)
        compare(grid.cameraScrollX, parked, "the open menu suspends follow")
        keyClick(Qt.Key_Escape)
        tryVerify(function() { return !bootstrap.automationMenuOpen() }, 2000,
                  "Escape closed the menu")
        testCase.presentPlayhead(farSample, playing)
        tryVerify(function() { return grid.cameraScrollX !== parked }, 1000,
                  "dismissing the menu lets the next observation follow")

        // The composition's own cancellation reaches the page's capture: a live
        // gesture and an open modal both end with nothing written.
        var revisionBefore = bootstrap.automationDocumentRevision()
        var ticksBefore = bootstrap.automationLaneTicks()
        mousePress(input, free.x, free.y, Qt.LeftButton)
        compare(bootstrap.automationFrozenRevision() >= 0, true,
                "the cancelled gesture froze the revision it captured")
        verify(bootstrap.cancelInput(), "the composition cancelled the live gesture")
        compare(bootstrap.automationFrozenRevision(), -1,
                "the cancelled gesture left no frozen revision behind")
        compare(bootstrap.automationInteractionActive(), false, "the cancelled gesture ended")
        compare(bootstrap.automationDocumentRevision(), revisionBefore,
                "the cancelled gesture wrote nothing")
        compare(bootstrap.automationLaneTicks(), ticksBefore,
                "the cancelled gesture left the lane alone")
        mouseRelease(input, free.x, free.y, Qt.LeftButton)

        testCase.openAutomationTabMenu(volumeTab)
        compare(bootstrap.automationMenuOpen(), true, "the lane menu opened again")
        verify(bootstrap.cancelInput(), "the composition cancelled the open menu")
        compare(bootstrap.automationMenuOpen(), false, "the cancelled menu closed")
        compare(bootstrap.automationFrozenRevision(), -1,
                "the cancelled menu left no frozen revision behind")
        compare(bootstrap.automationDocumentRevision(), revisionBefore,
                "the cancelled menu wrote nothing")

        // One edit round-trips: the case empties the lane, writes its own
        // occurrences, and the page republishes what Undo and Redo restore.
        verify(testCase.clearAutomationLane(volumeTab), "the case emptied the lane for the round trip")
        var cleared = bootstrap.automationLaneValues()
        verify(testCase.writeVolumeLanePoints(volumeTab), "the case wrote the lane")
        var written = bootstrap.automationLaneValues()
        compare(written !== cleared, true, "the write changed the emptied lane")
        var writtenTicks = bootstrap.automationLaneTicks()
        compare(written.length > 0, true, "the write reached the published lane")
        compare(session.canUndo, true, "the write reached the document history (error='"
                + session.lastSaveError + "')")
        verify(bootstrap.requestAutomationUndo(), "the production undo completed (error='"
               + session.lastSaveError + "')")
        compare(bootstrap.automationLaneValues(), cleared,
                "Undo republished the emptied lane the page draws from")
        var undone = bootstrap.automationLaneValues()
        verify(bootstrap.requestAutomationRedo(), "the production redo completed (error='"
               + session.lastSaveError + "')")
        compare(bootstrap.automationLaneValues(), written, "Redo republished the committed lane")
        compare(bootstrap.automationLaneTicks(), writtenTicks,
                "Redo restored the committed ticks")
        compare(testCase.automationLaneNodes().length > 0, true,
                "the redrawn lane projects the restored occurrences")
        verify(bootstrap.requestAutomationUndo(), "the second production undo completed")
        compare(bootstrap.automationLaneValues(), undone,
                "a second Undo restored the state before the write")

        // The camera is shared with every other page: the case hands it back at
        // the scroll the lane's own mounts start from.
        testCase.presentPlayhead(0, 0)
        grid.resetCameraScroll()
        compare(grid.cameraScrollX, parked, "the case handed the shared camera back")
    }

    function test_productionAutomationSpacePriority() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = bootstrap.preferencesUrl("production-automation-space")
        testCase.mountProductionAutomation(location)
        var model = testCase.automationModel()
        var propagations = testCase.spacePropagations

        // The plot leaves bare Space to the transport.
        testCase.automationPlot().forceActiveFocus(Qt.OtherFocusReason)
        keyClick(Qt.Key_Space)
        tryVerify(function() { return testCase.spacePropagations === propagations + 1 }, 2000,
                  "the automation plot leaves bare Space to the window transport")

        // Focusing the original selector and pressing Space never edits the lane.
        var volumeTab = bootstrap.automationVolumeIndex()
        verify(testCase.writeVolumeLanePoints(volumeTab),
               "the case created a written Volume lane with a real sweep")
        var tab = testCase.automationTab(volumeTab)
        verify(tab, "the selector drew the Volume tab")
        testCase.focusControl(tab)
        var revision = bootstrap.automationDocumentRevision()
        keyClick(Qt.Key_Space)
        compare(bootstrap.automationDocumentRevision(), revision,
                "Space on the focused selector does not edit automation")
        propagations = testCase.spacePropagations
        keyClick(Qt.Key_Return)
        tryVerify(function() { return bootstrap.automationActiveParameterIndex() === volumeTab }, 2000,
                  "Return activates the focused tab")

        // The Tempo row's Tap control claims only Return/Enter.
        var tempoTab = testCase.revealAutomationTab(model.tabCount - 1)
        var tapControl = findChild(tempoTab, "automationTempoTapButton")
        verify(tapControl, "the Tempo row composed its Tap control")
        testCase.focusControl(tapControl)
        keyClick(Qt.Key_Space)
        compare(bootstrap.automationDocumentRevision(), revision,
                "Space on the inline Tap control does not edit automation")
        propagations = testCase.spacePropagations
        compare(bootstrap.automationTapCount(), 0, "the Space key registered no tap")
        testCase.resetAutomationTap()

        // The original popup host contains Space without activating a command.
        var nodes = testCase.automationLaneNodes()
        verify(nodes.length > 0, "the Volume lane projects a written node")
        verify(testCase.rightClickAutomationNode(0), "the first drawn node has a centre")
        tryVerify(function() { return bootstrap.automationMenuOpen() }, 2000,
                  "the node menu opened")
        testCase.awaitAutomationModal("automationMenu", true)
        keyClick(Qt.Key_Space)
        compare(testCase.spacePropagations, propagations,
                "the automation menu contains Space instead of leaking into transport")
        compare(bootstrap.automationMenuOpen(), true, "Space leaves the menu open")
        compare(bootstrap.automationDocumentRevision(), revision,
                "menu keyboard input does not edit the song")
        keyClick(Qt.Key_Escape)
        tryVerify(function() { return !bootstrap.automationMenuOpen() }, 2000,
                  "Escape closed the menu")

        compare(bootstrap.automationMenuOpen(), false, "the case left no menu open")
        verify(bootstrap.cancelInput(), "the composition's own cancellation settles the page")
        compare(bootstrap.automationInteractionActive(), false,
                "the cancelled page reports no interaction")
    }

    // The complete production drawer's playhead contract: with the real
    // Velocity, Voice Changes and Automation pages all mounted and visible
    // through the production chrome, 128 distinct authoritative stopped
    // positions advance the one shared publication and each page's own
    // presentation diagnostic by exactly 128, rebuild no page's static content,
    // and leave every page rectangle and all four shared segments where they
    // were — aligned on the one published projection.
    function test_productionAllPagesPlayheadPerformance() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = bootstrap.preferencesUrl("production-all-pages-playhead")
        var values = testCase.chromeState({ "velocityVisible": true, "velocityHeight": 110,
                                            "voiceChangesVisible": true, "voiceChangesHeight": 130,
                                            "automationVisible": true, "automationHeight": 150,
                                            "activePage": "automation" })
        testCase.mountProductionVelocity(location, values)
        verify(bootstrap.attachProductionSection(testCase.voiceChangesKind),
               "the production Voice Changes page attaches to its slot")
        verify(bootstrap.attachProductionSection(testCase.automationKind),
               "the production Automation page attaches to its slot")
        testCase.resetChrome(location, values)
        testCase.showSection(testCase.velocityKind)
        testCase.showSection(testCase.voiceChangesKind)
        testCase.showSection(testCase.automationKind)
        // The case's own state, stated before it measures anything: three hosted
        // production pages in three visible bodies, so every counter below is one
        // shared presentation reaching all of them.
        tryVerify(function() {
            var pages = [testCase.velocityPageItem(), testCase.voicePageItem(),
                         testCase.automationPageItem()]
            for (var i = 0; i < pages.length; ++i) {
                if (pages[i] === null || pages[i].width <= 0 || pages[i].height <= 0)
                    return false
            }
            return testCase.section(testCase.velocityKind).visible
                    && testCase.section(testCase.voiceChangesKind).visible
                    && testCase.section(testCase.automationKind).visible
        }, 2000, "all three production pages are hosted and visible through the chrome")

        var grid = testCase.surface.gridModel
        var playhead = testCase.playheadPresenter()
        var origin = testCase.presenter().plotOrigin
        verify(bootstrap.pausePlayheadPolling(),
               "the lane holds the production polling task for a deterministic position")
        grid.resetCameraScroll()
        // Warm and settle the stopped presentation first: the pages' playing state
        // and resolved context are whatever the previous case left, so this is the
        // one observation of the case that may legitimately rebuild. The loop
        // below measures inside the stopped context this leaves behind.
        testCase.presentPlayhead(1000, 0)
        tryVerify(function() { return playhead.timelineAttached && playhead.visible
                                       && !playhead.playing }, 1000,
                  "the stopped position is attached, visible and not playing")
        testCase.awaitRenderedLayout()

        var builds = [bootstrap.velocityContentBuilds(), bootstrap.voiceContentBuilds(),
                      bootstrap.automationContentBuilds()]
        var presented = [bootstrap.velocityPlayheadPresentations(),
                         bootstrap.voicePlayheadPresentations(),
                         bootstrap.automationPlayheadPresentations()]
        var published = bootstrap.publishedPlayheadPresentations()
        var kinds = [testCase.velocityKind, testCase.voiceChangesKind, testCase.automationKind]
        var rects = []
        for (var i = 0; i < kinds.length; ++i) {
            var rect = testCase.renderedRect(testCase.body(kinds[i]))
            rects.push(rect.x, rect.y, rect.width, rect.height)
        }

        // 128 distinct authoritative stopped positions: the sample spacing the
        // lane's production Velocity case already proves into distinct shared
        // ticks, presented through the one production owner. Each page dedupes its
        // own presentation, so a repeated tick would show up as a short count
        // instead of a passing run.
        var updates = 128
        for (var step = 1; step <= updates; ++step)
            bootstrap.presentPlayheadObservation((1 + step) * 1000, 0)

        tryVerify(function() {
            return bootstrap.publishedPlayheadPresentations() === published + updates
        }, 2000, "the one presenter published all " + updates + " shared positions ("
                  + (bootstrap.publishedPlayheadPresentations() - published) + ")")
        tryVerify(function() {
            return bootstrap.velocityPlayheadPresentations() === presented[0] + updates
                    && bootstrap.voicePlayheadPresentations() === presented[1] + updates
                    && bootstrap.automationPlayheadPresentations() === presented[2] + updates
        }, 2000, "each production page consumed exactly " + updates
                  + " shared presentations (velocity "
                  + (bootstrap.velocityPlayheadPresentations() - presented[0]) + ", voice "
                  + (bootstrap.voicePlayheadPresentations() - presented[1]) + ", automation "
                  + (bootstrap.automationPlayheadPresentations() - presented[2]) + ")")
        compare(bootstrap.velocityContentBuilds(), builds[0],
                "128 shared-playhead positions rebuilt no Velocity content")
        compare(bootstrap.voiceContentBuilds(), builds[1],
                "128 shared-playhead positions rebuilt no Voice Changes content")
        compare(bootstrap.automationContentBuilds(), builds[2],
                "128 shared-playhead positions rebuilt no Automation content")

        // Position-only updates move no page rectangle, and every segment still
        // reads the one published projection.
        var after = []
        for (var i = 0; i < kinds.length; ++i) {
            var moved = testCase.renderedRect(testCase.body(kinds[i]))
            after.push(moved.x, moved.y, moved.width, moved.height)
        }
        compare(after, rects, "every page rectangle survived the 128 shared positions")
        tryVerify(function() { return playhead.visible }, 2000,
                  "the last presented position is inside the shared viewport")
        var names = ["sharedPlayheadRollClip", "sharedPlayheadVelocityClip",
                     "sharedPlayheadVoiceChangesClip", "sharedPlayheadAutomationClip"]
        for (var i = 0; i < names.length; ++i) {
            testCase.awaitPlayheadVisibility(names[i], true)
            // The drawn binding catches up on the next event-loop pass, the same
            // lag every other drawn binding in this suite accounts for.
            tryVerify(function() {
                return testCase.playheadSurfaceX(names[i]) === origin + playhead.contentX
            }, 2000, "the " + names[i] + " line catches up with the shared published position")
        }
    }

    // The suite hands the document presentation back the way the host does at
    // close, around the one composition the lane mounted: polling stops, the
    // session cancels while the scene still exists, the scene is removed, and the
    // acknowledgment — `detachGridScene()`'s own call — releases the page slot,
    // the grid, the audio binding and the document session. Nothing QML still
    // binds to is released before the scene is really gone, and the lane never
    // relies on ApplicationSession's deinit for that release.
    function cleanupTestCase() {
        bootstrap.pausePlayheadPolling()
        verify(bootstrap.hostClosing(),
               "the session still presents its document while the scene exists")
        var retired = testCase.surface
        testCase.surface = null
        verify(retired, "the lane mounted its one composition")
        retired.destroy()
        // The host removes the scene before it acknowledges the removal, so the
        // composition is really gone — its bindings included — before the
        // session releases the document-bound owners they read.
        wait(0)
        verify(bootstrap.acknowledgeSceneRemoval(),
               "the session released its document presentation after the acknowledged"
               + " scene removal")
        // Retirement is observable the same way the running lane is: the presenter
        // outlives the document presentation, so the lane can present one more
        // authoritative observation and watch it refused. A callback or a publish
        // that survived the acknowledgment would move the settled count.
        var settled = bootstrap.publishedPlayheadPresentations()
        verify(settled > 0, "the lane published presentations before retirement")
        compare(bootstrap.presentPlayheadObservation(192000, 2), false,
                "an authoritative observation after the acknowledged removal is refused")
        compare(bootstrap.publishedPlayheadPresentations(), settled,
                "no shared presentation survives the acknowledged removal")
    }

    // The reference profiles: one child process per required DPR/font profile
    // renders the panes that profile is authoritative for. The ordinary run skips
    // this case; the parent verifies the artifacts each child wrote.
    function test_referenceProfileCapture() {
        if (!bootstrap.profileActive)
            skip("the reference capture runs in a dedicated profile child")
        var location = bootstrap.preferencesUrl("profile-" + bootstrap.profileName)
        // Both document-bound pages mount in this composition: the drawer capture
        // carries the whole production surface, and the picker pane needs the
        // Voice Changes page in its slot and visible.
        var values = testCase.chromeState({ "velocityVisible": true, "voiceChangesVisible": true })
        var page = testCase.mountProductionVelocity(location, values)
        verify(bootstrap.attachProductionSection(testCase.voiceChangesKind),
               "the profile composition attaches the production Voice Changes page")
        testCase.resetChrome(location, values)
        testCase.showSection(testCase.voiceChangesKind)
        tryVerify(function() { return testCase.voiceMarkerLines().length > 0 }, 2000,
                  "the profile composition drew the voice change markers")
        // The profile's font is pushed through the production composition: the
        // grid's base font is the font-relative geometry base the roll, the
        // drawer chrome and both pages measure from.
        testCase.surface.gridModel.baseFontPx = bootstrap.profileFontPx
        testCase.surface.configureViewport()
        wait(0)
        verify(bootstrap.attachProductionSection(testCase.automationKind),
               "the profile composition attaches the production Automation page")
        testCase.showSection(testCase.automationKind)
        var nodes = testCase.velocityNodes()
        verify(nodes.length > 0, "the profile composition drew its nodes")
        testCase.clickNode(nodes[0])
        tryVerify(function() { return testCase.velocityModel().selectedCount === 1 }, 1000,
                  "the profile composition shows a selected note")
        compare(Math.round(Screen.devicePixelRatio), Math.round(bootstrap.profileDpr),
                "the child renders at its profile's device pixel ratio")
        compare(testCase.velocityModel().baseFontPx, bootstrap.profileFontPx,
                "the page received the profile's base font")
        compare(testCase.voiceModel().baseFontPx, bootstrap.profileFontPx,
                "the Voice Changes page received the profile's base font too")

        var panes = bootstrap.profilePanes
        for (var i = 0; i < panes.length; ++i)
            verify(panes[i] === "track-headers" ? testCase.captureTrackHeadersProfile()
                                              : testCase.captureProfilePane(panes[i]),
                   "captured the " + panes[i] + " pane at " + bootstrap.profileName
                   + " (dpr " + Screen.devicePixelRatio + " of " + bootstrap.profileDpr
                   + ", automationFont " + testCase.automationModel().baseFontPx
                   + " of " + bootstrap.profileFontPx + ")")
        compare(page.objectName, "velocityPage", "the capture composition is the production page")
    }
}
