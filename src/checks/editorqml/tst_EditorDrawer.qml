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

    // The historical store: one category, seven keys.
    readonly property var drawerKeys: ["automationVisible", "automationHeight",
                                       "velocityVisible", "velocityHeight",
                                       "voiceChangesVisible", "voiceChangesHeight",
                                       "activePage"]
    readonly property string absentKey: "__absent__"

    // Key traffic that crosses the drawer unclaimed and reaches the surface's
    // ancestors. Production hands the bare Space key to the window transport;
    // the lane proves only the controls' own claim policy.
    property int spacePropagations: 0
    property int returnPropagations: 0
    property int leftPropagations: 0

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

    // Production session creation: RewriteWindow.cpp builds
    // "import PorydawApp\nApplicationSession {}\n" and injects that instance
    // into the composition. The bootstrap holds it through the framework's
    // QML-child seam.
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

    // The staged route101 project and song open through the real production path:
    // RewriteWindow.cpp builds "import PorydawApp\nApplicationSession {}\n" and
    // calls openProjectAndSong(path:label:) with the project root and the label
    // the staged project's song table declares (sound/song_table.inc). The open is
    // asynchronous, so the lane drives the event loop, stops as soon as the
    // session reports a failure, and names the cause it was given.
    function initTestCase() {
        verify(bootstrap.start("mus_route101"), "the staged route101 project starts opening")
        var waited = 0
        while (waited < 30000 && !session.songOpen && testCase.openFailure.length === 0) {
            wait(50)
            waited += 50
        }
        verify(session.songOpen, "the staged route101 song opened" + testCase.openDiagnostics())
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

    // Every case starts with no surface and no attachment: the drawer survives
    // with chrome values only, so the previous case's pages are released here,
    // after its surface was destroyed in cleanup().
    function init() {
        bootstrap.detachTestSection(velocityKind)
        bootstrap.detachTestSection(voiceChangesKind)
        bootstrap.detachTestSection(automationKind)
        // A playhead case holds the production polling task for determinism;
        // every case starts with it running again.
        bootstrap.resumePlayheadPolling()
        testCase.spacePropagations = 0
        testCase.returnPropagations = 0
        testCase.leftPropagations = 0
        testCase.pageDestructions = 0
    }

    // A case ends with its scene gone: the composition is settled first so the
    // case's last publication has landed, then the surface is destroyed. Hiding
    // it instead would be a scene hide, which cancels every attached page and
    // would blur the cancellation the cases assert.
    function cleanup() {
        if (testCase.surface) {
            var retired = testCase.surface
            testCase.surface = null
            wait(0)
            retired.destroy()
        }
    }

    // ---- production composition and published state ------------------------

    function createSurface(preferenceLocation) {
        var item = surfaceComponent.createObject(testCase, {
            "width": testCase.width,
            "height": testCase.height,
            "applicationSession": session,
            "drawerPreferenceLocation": preferenceLocation
        })
        verify(item, "the production surface came up")
        testCase.surface = item
        return item
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
    // A line is plot-local, so its surface position is its clip's origin plus
    // the one shared projection.
    function playheadSurfaceX(name) {
        var clip = testCase.playheadClip(name)
        var line = testCase.playheadLine(name)
        return clip && line ? clip.x + line.x : -1
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
            if (!presenter || !container || !band || !bar)
                return false
            if (container.height !== presenter.height)
                return false
            if (band.height !== testCase.surface.height - presenter.height)
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
        var location = bootstrap.preferencesUrl("no-page")
        testCase.seedStore(location, { "velocityVisible": true, "velocityHeight": 137,
                                       "activePage": "velocity" })
        var seeded = testCase.snapshotStore(location)
        testCase.createSurface(location)
        testCase.awaitRenderedLayout()

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

        compare(testCase.presenter().plotOrigin, testCase.surface.gridModel.keyboardWidth,
                "the plot origin is the grid's gutter")
        compare(testCase.presenter().plotWidth,
                testCase.surface.width - testCase.surface.gridModel.keyboardWidth,
                "the plot width is the rest of the surface")
        compare(testCase.rollBand().height, testCase.surface.height, "the roll keeps the surface")
        compare(testCase.rollInput().height, testCase.surface.height, "the roll input keeps the surface")
    }

    // Three real pages host through the production seam: chrome and stacking
    // follow the published rectangles, pages map from the shared gutter, the
    // accessible contract holds, Return/Enter activate while bare Space stays
    // unclaimed, and the themed chrome is real rendered output.
    function test_hostedChromeAndStacking() {
        var location = bootstrap.preferencesUrl("chrome")
        testCase.seedStore(location, { "automationVisible": true, "automationHeight": 150,
                                       "velocityVisible": true, "velocityHeight": 110,
                                       "voiceChangesVisible": true, "voiceChangesHeight": 130,
                                       "activePage": "automations" })
        verify(testCase.attachPage(testCase.velocityKind), "the velocity page attaches")
        verify(testCase.attachPage(testCase.voiceChangesKind), "the voice-changes page attaches")
        verify(testCase.attachPage(testCase.automationKind), "the automation page attaches")
        testCase.createSurface(location)
        testCase.awaitRenderedLayout()

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
        compare(presenter.plotOrigin, testCase.surface.gridModel.keyboardWidth,
                "the container publishes the grid's gutter")
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
        var location = bootstrap.preferencesUrl("stored-height")
        verify(testCase.attachPage(testCase.automationKind), "the automation page attaches")
        testCase.createSurface(location)
        testCase.awaitRenderedLayout()

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
        compare(testCase.rollInput().height, testCase.surface.height - barRow,
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
        fuzzyCompare(testCase.rollInput().height, testCase.surface.height - openHeight, 0.01,
                     "the roll gives the height back")
    }

    // Real press/drag/release resizes by the drag delta, the minimum and the
    // available height clamp, Up/Down step by the resize step, Left/Right are
    // consumed, a cancelled drag keeps the last applied height, and a host
    // shrink re-clamps without rewriting the stored height.
    function test_resizeClampAndCancellation() {
        var location = bootstrap.preferencesUrl("resize")
        verify(testCase.attachPage(testCase.automationKind), "the automation page attaches")
        testCase.createSurface(location)
        testCase.awaitRenderedLayout()

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
        verify(presenter.height <= host, "the container stays inside the host")

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
        fuzzyCompare(presenter.height, host, 0.01, "the container clamps at the host")
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

        // The host shrink re-clamps the drawn body and keeps the stored height.
        testCase.surface.height = host - 250
        verify(presenter.height <= testCase.surface.height + 0.01,
               "the container follows the host shrink")
        verify(testCase.section(kind).bodyHeight < applied, "the shrink re-clamps the drawn body")
        testCase.surface.height = host
        fuzzyCompare(testCase.section(kind).bodyHeight, applied, 0.01,
                     "the stored height survived the host shrink")
    }

    // The Voice-Changes to Automations spill while resizing, and the detach
    // lifetime: a released page is dropped only after the surface that hosted it
    // is gone.
    function test_voiceChangesSpillAndDetach() {
        var location = bootstrap.preferencesUrl("voice-spill")
        testCase.seedStore(location, { "automationVisible": true, "automationHeight": 100,
                                       "voiceChangesVisible": true, "voiceChangesHeight": 60 })
        verify(testCase.attachPage(testCase.voiceChangesKind), "the voice-changes page attaches")
        verify(testCase.attachPage(testCase.automationKind), "the automation page attaches")
        bootstrap.setTestSectionMaximumBodyHeight(testCase.voiceChangesKind, 90)
        testCase.createSurface(location)
        testCase.awaitRenderedLayout()

        var presenter = testCase.presenter()
        var host = testCase.surface.height
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

        // A page is released only after the surface that hosted it is gone: the
        // teardown destroys the hosted content but cancels nothing, the release
        // then cancels once, and no key of a released kind is written. The
        // spilled pair's own release records both its heights, so those writes are
        // awaited before the teardown snapshot, which then describes a settled
        // store the detach must leave unchanged. The composition is settled too,
        // and nothing bridged is read through the dead surface afterwards: the
        // remount below makes the same claims through a live one.
        testCase.awaitStoreKey(location, "automationHeight",
                               "number:" + Math.round(automationAfterSpill))
        testCase.awaitStoreKey(location, "voiceChangesHeight", "number:90")
        var beforeTeardown = testCase.snapshotStore(location)
        var cancels = bootstrap.pageCancelCount
        tryVerify(function() { return testCase.pageItem(voiceKind) !== null }, 2000,
                  "the voice-changes section loads its page")
        var voicePage = testCase.pageItem(voiceKind)
        verify(voicePage, "the voice-changes page is hosted")
        testCase.observePageDestruction(voicePage)
        wait(0)
        testCase.surface.destroy()
        testCase.surface = null
        tryCompare(testCase, "pageDestructions", 1, 2000,
                   "the teardown destroyed the hosted page content")
        compare(bootstrap.pageCancelCount, cancels, "tearing the surface down releases no page")

        bootstrap.detachTestSection(voiceKind)
        compare(bootstrap.pageCancelCount, cancels + 1, "the release cancels the page once")
        testCase.compareSnapshots(testCase.snapshotStore(location), beforeTeardown,
                                 "releasing a page writes nothing")

        // Remounting shows the surviving chrome, with the released kind absent
        // and the automations section untouched.
        testCase.createSurface(location)
        testCase.awaitRenderedLayout()
        compare(testCase.section(voiceKind).available, false, "the released kind stays unavailable")
        compare(testCase.toggle(voiceKind).visible, false, "no toggle for the released kind")
        compare(testCase.grip(voiceKind).visible, false, "no handle for the released kind")
        compare(testCase.body(voiceKind).item, null, "no page for the released kind")
        compare(testCase.section(automationKind).available, true, "the automations section is untouched")
        compare(testCase.section(automationKind).visible, true, "and still visible")
        fuzzyCompare(testCase.section(automationKind).bodyHeight, automationAfterSpill, 0.01,
                     "and keeps the height the spill left it")
        testCase.compareSnapshots(testCase.snapshotStore(location), beforeTeardown,
                                 "remounting writes nothing")
    }

    // Focus returns to the roll when nothing visible remains, showing a section
    // focuses its page scope, every transition cancels exactly once, and a page
    // outlives both a hide and the teardown of its surface.
    function test_focusReturnAndPageCancellation() {
        var location = bootstrap.preferencesUrl("focus")
        verify(testCase.attachPage(testCase.automationKind), "the automation page attaches")
        testCase.createSurface(location)
        testCase.awaitRenderedLayout()

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

        // Teardown releases nothing; the release after it cancels each page once.
        // The composition settles before it goes, so the teardown itself cancels
        // nothing, and nothing bridged is read through the dead surface after.
        wait(0)
        testCase.surface.destroy()
        testCase.surface = null
        compare(bootstrap.pageCancelCount, cancels + 2, "tearing the surface down cancels nothing")
        bootstrap.detachTestSection(velocityKind)
        compare(bootstrap.pageCancelCount, cancels + 3, "the release after teardown cancels once")
        bootstrap.detachTestSection(automationKind)
        compare(bootstrap.pageCancelCount, cancels + 4, "and so does the remaining release")
    }

    // The store is the historical one: the mount restores every value and writes
    // nothing back, interactive calls write that kind's two keys and the chosen
    // page name in the historical formats, sync() makes them readable, and the
    // scratch file is the only store touched.
    function test_preferencesRoundTrip() {
        var location = bootstrap.preferencesUrl("round-trip")
        testCase.seedStore(location, { "automationVisible": true, "automationHeight": 110,
                                       "velocityVisible": true, "velocityHeight": 130,
                                       "voiceChangesVisible": true, "voiceChangesHeight": 150,
                                       "activePage": "velocity" })
        var seeded = testCase.snapshotStore(location)
        var defaultStore = testCase.snapshotStore("")
        verify(testCase.attachPage(testCase.velocityKind), "the velocity page attaches")
        verify(testCase.attachPage(testCase.voiceChangesKind), "the voice-changes page attaches")
        verify(testCase.attachPage(testCase.automationKind), "the automation page attaches")
        testCase.createSurface(location)
        testCase.awaitRenderedLayout()

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
        var location = bootstrap.preferencesUrl("playhead-bodies")
        verify(testCase.attachPage(testCase.velocityKind), "the velocity page attaches")
        verify(testCase.attachPage(testCase.voiceChangesKind), "the voice-changes page attaches")
        verify(testCase.attachPage(testCase.automationKind), "the automation page attaches")
        testCase.createSurface(location)
        testCase.awaitRenderedLayout()
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
        testCase.verifySurfaceRect(rollClip, rollPlot.x, rollPlot.y, rollPlot.width, rollPlot.height,
                                   "the roll segment clips to the plot column")
        fuzzyCompare(testCase.playheadSurfaceX("sharedPlayheadRollClip"),
                     origin + playhead.contentX, 0.01,
                     "the roll line is the published projection from the shared origin")
        verify(rollClip.x >= grid.keyboardWidth - 0.01, "no segment covers the keyboard gutter")

        // A second published position moves the drawn segment with it.
        var firstX = testCase.playheadSurfaceX("sharedPlayheadRollClip")
        testCase.presentPlayhead(16000, 0)
        tryVerify(function() {
            return testCase.playheadSurfaceX("sharedPlayheadRollClip") !== firstX
        }, 2000, "the drawn segment tracks the published position")
        fuzzyCompare(testCase.playheadSurfaceX("sharedPlayheadRollClip"),
                     origin + playhead.contentX, 0.01,
                     "the moved line is still the published projection")

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
            var line = testCase.playheadLine("sharedPlayheadRollClip")
            return drawn.visible === presenter.visible
                && Math.abs(drawn.x + line.x - (origin + presenter.contentX)) < 0.01
        }, 2000, "the drawn segment catches up with the last published position")
        testCase.awaitRenderedLayout()
        compare(rollClip.x >= grid.keyboardWidth - 0.01, true,
                "the last position still never covers the gutter")
    }

    // A camera change reprojects the retained authoritative tick, an
    // out-of-viewport projection draws nothing, and scrolling back renders the
    // same position again.
    function test_sharedPlayheadHidesOutOfViewportAndReprojects() {
        var location = bootstrap.preferencesUrl("playhead-viewport")
        verify(testCase.attachPage(testCase.velocityKind), "the velocity page attaches")
        testCase.createSurface(location)
        testCase.awaitRenderedLayout()
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
        var location = bootstrap.preferencesUrl("playhead-follow")
        verify(testCase.attachPage(testCase.velocityKind), "the velocity page attaches")
        testCase.createSurface(location)
        testCase.awaitRenderedLayout()
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
}
