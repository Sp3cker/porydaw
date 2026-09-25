import Foundation
import PorydawApp
import PorydawCore

private let playheadGuidesID = "swiftcore/PlayheadFeature::guidesResizeScrollAndOwnership"
private let playheadFollowID = "swiftcore/PlayheadFeature::followScroll"
private let playheadAppearanceID = "swiftcore/PlayheadFeature::appearanceMetrics"
private let playheadMathID = "swiftcore/PlayheadFeature::devicePixelRect"
private let playheadPanID = "swiftcore/PlayheadFeature::middlePan"

private func playheadCppID(_ stem: String, _ assertion: String) -> String {
    "\(stem)::\(assertion)"
}

private func playheadNear(_ lhs: Double, _ rhs: Double, tolerance: Double = 1e-9) -> Bool {
    abs(lhs - rhs) <= tolerance
}

private func playheadFeatureFixture() -> MidiFile {
    let tempo = { (tick: Tick, microseconds: UInt32) -> MidiEvent in
        .meta(tick: tick, type: 0x51, data: [
            UInt8((microseconds >> 16) & 0xFF),
            UInt8((microseconds >> 8) & 0xFF),
            UInt8(microseconds & 0xFF),
        ])
    }
    let conductor: [MidiEvent] = [
        tempo(0, 500_000),
        tempo(48, 250_000),
        .meta(tick: 48, type: 0x01, data: Array("[".utf8)),
        .meta(tick: 144, type: 0x01, data: Array("]".utf8)),
    ]
    let notes: [MidiEvent] = [
        .channel(tick: 0, status: 0x90, data0: 60, data1: 100),
        .channel(tick: 24, status: 0x80, data0: 60),
        .channel(tick: 72, status: 0x90, data0: 67, data1: 100),
        .channel(tick: 96, status: 0x80, data0: 67),
    ]
    return MidiFile(division: 24, chunks: [
        MidiChunk(events: conductor, endTick: 192),
        MidiChunk(events: notes, endTick: 192),
    ])
}

@MainActor
private func playheadFeatureSession(_ suite: DocumentSession,
                                    service: ProjectService) -> DocumentSession {
    let document = SongDocument(file: playheadFeatureFixture(),
                                config: suite.document.state.config,
                                source: suite.document.source,
                                trackBudget: suite.document.trackBudget)
    return DocumentSession(document: document, service: service,
                           lease: suite.bankLease, slots: suite.bankSlots,
                           dirty: false, loadName: suite.bankLoadName, sampleRate: 48_000)
}

@MainActor
private func configurePlayheadCamera(_ session: DocumentSession, width: Double,
                                     height: Double, pixelsPerBeat: Double? = nil) {
    let ticksPerBeat = UInt32(max(1, session.document.ticksPerBeat))
    let lengthTicks = UInt64(session.timeline.lengthTicks)
    session.mutateCamera { camera in
        camera.updateViewport(width: width, rollHeight: height)
        camera.updateTimeDomain(ticksPerBeat: ticksPerBeat, lengthTicks: lengthTicks)
        if let pixelsPerBeat {
            _ = camera.setTimeZoom(pixelsPerBeat)
        }
    }
}

@MainActor
private func checkPlayheadGuides(_ report: CheckReport, suite: DocumentSession,
                                 service: ProjectService) {
    let session = playheadFeatureSession(suite, service: service)
    configurePlayheadCamera(session, width: 320, height: 240)

    let guides = PlayheadGuidesPresenter()
    guides.attach(session: session)
    session.onChange = { [weak guides] change in
        guides?.sessionDidChange(change)
    }
    session.onCameraChange = { [weak guides] _ in
        guides?.refreshProjection()
    }

    report.expect(guides.hover.kind == PlayheadGuideKind.hover.rawValue
                    && guides.edit.kind == PlayheadGuideKind.edit.rawValue,
                  cppID: playheadCppID(playheadGuidesID, "A008"),
                  message: "the attached presenter exposes independent hover and edit guides")

    let editTick = 48.0
    session.editCursor = Tick(editTick)
    let editX = session.camera.contentX(tick: editTick)
    report.expect(guides.edit.visible, cppID: playheadCppID(playheadGuidesID, "A013"),
                  message: "a nonnegative session edit cursor makes the edit guide visible")
    report.expect(!guides.hover.visible, cppID: playheadCppID(playheadGuidesID, "A014"),
                  message: "the edit guide is visible without an active hover owner")
    report.expect(playheadNear(guides.edit.contentX, editX, tolerance: 1.0),
                  cppID: playheadCppID(playheadGuidesID, "A016"),
                  message: "the edit guide follows the session camera contentX")

    let automation = PlayheadGuideHoverOwner.automation.rawValue
    let voiceChanges = PlayheadGuideHoverOwner.voiceChanges.rawValue
    let roll = PlayheadGuideHoverOwner.roll.rawValue
    let automationTick = 72.0
    let automationX = session.camera.contentX(tick: automationTick)
    guides.updateHover(owner: automation, contentX: automationX)
    report.expect(guides.hover.visible && !guides.edit.visible,
                  cppID: playheadCppID(playheadGuidesID, "A017"),
                  message: "a valid hover replaces the edit guide")
    report.expect(playheadNear(guides.hover.contentX, automationX, tolerance: 1.0),
                  cppID: playheadCppID(playheadGuidesID, "A019"),
                  message: "the hover guide projects its owning tick through the camera")
    report.expect(playheadNear(guides.hover.contentX,
                               session.camera.contentX(tick: automationTick), tolerance: 1.0),
                  cppID: playheadCppID(playheadGuidesID, "A020"),
                  message: "hover content remains plot-local after publication")
    report.expect(playheadNear(guides.edit.contentX, editX, tolerance: 1.0),
                  cppID: playheadCppID(playheadGuidesID, "A021"),
                  message: "the retained edit projection remains coherent while hover owns visibility")

    let voiceTick = 96.0
    let voiceX = session.camera.contentX(tick: voiceTick)
    guides.updateHover(owner: voiceChanges, contentX: voiceX)
    guides.clearHover(owner: automation)
    report.expect(guides.hover.visible,
                  cppID: playheadCppID(playheadGuidesID, "A022"),
                  message: "a later hover owner remains visible when an older owner clears")
    report.expect(playheadNear(guides.hover.contentX, voiceX, tolerance: 1.0),
                  cppID: playheadCppID(playheadGuidesID, "A023"),
                  message: "owner arbitration retains the later owner's projected tick")

    guides.clearHover(owner: voiceChanges)
    report.expect(!guides.hover.visible,
                  cppID: playheadCppID(playheadGuidesID, "A024"),
                  message: "clearing the current hover owner hides the hover guide")
    report.expect(guides.edit.visible,
                  cppID: playheadCppID(playheadGuidesID, "A025"),
                  message: "clearing hover restores edit-guide visibility")

    guides.updateHover(owner: automation, contentX: automationX)
    guides.updateHover(owner: automation, contentX: -1.0)
    report.expect(!guides.hover.visible,
                  cppID: playheadCppID(playheadGuidesID, "A010"),
                  message: "a hover tick before song start is hidden")
    report.expect(guides.edit.visible,
                  cppID: playheadCppID(playheadGuidesID, "A011"),
                  message: "an invalid hover does not suppress the edit guide")

    let viewportWidth = session.camera.snapshot.viewportWidth
    guides.updateHover(owner: roll, contentX: viewportWidth + 1.0)
    report.expect(!guides.hover.visible && guides.hover.contentX >= viewportWidth,
                  cppID: playheadCppID(playheadGuidesID, "viewport-edge"),
                  message: "a projected hover outside [0, viewportWidth) is hidden")

    guides.updateHover(owner: roll, contentX: automationX)
    let editBeforeScroll = guides.edit.contentX
    let hoverBeforeScroll = guides.hover.contentX
    let priorScroll = session.camera.snapshot.scrollX
    let scrollChanged = session.mutateCamera { camera in
        _ = camera.setHScroll(priorScroll + 24.0)
    }
    guides.refreshProjection()
    report.expect(scrollChanged && !playheadNear(guides.edit.contentX, editBeforeScroll)
                    && !playheadNear(guides.hover.contentX, hoverBeforeScroll),
                  cppID: playheadCppID(playheadGuidesID, "A029"),
                  message: "camera scrolling changes both retained guide projections")
    report.expect(!playheadNear(guides.edit.contentX, editBeforeScroll),
                  cppID: playheadCppID(playheadGuidesID, "A030"),
                  message: "camera scrolling reprojects the edit guide")
    report.expect(playheadNear(guides.edit.contentX,
                               session.camera.contentX(tick: editTick), tolerance: 1.0)
                    && playheadNear(guides.hover.contentX,
                                    session.camera.contentX(tick: automationTick), tolerance: 1.0),
                  cppID: playheadCppID(playheadGuidesID, "A031"),
                  message: "scrolled guides remain aligned with the current camera")

    session.mutateCamera { camera in
        camera.updateViewport(width: viewportWidth / 2.0,
                              rollHeight: camera.snapshot.rollHeight)
    }
    guides.refreshProjection()
    report.expect(playheadNear(guides.edit.contentX,
                               session.camera.contentX(tick: editTick), tolerance: 1.0)
                    && playheadNear(guides.hover.contentX,
                                    session.camera.contentX(tick: automationTick), tolerance: 1.0),
                  cppID: playheadCppID(playheadGuidesID, "A028"),
                  message: "resizing the camera keeps guide contentX projections coherent")

    guides.detach()
    report.expect(!guides.timelineAttached && !guides.hover.visible && !guides.edit.visible,
                  cppID: playheadCppID(playheadGuidesID, "detach"),
                  message: "detaching synchronously hides both guides")
}

@MainActor
private func checkPlayheadFollow(_ report: CheckReport, suite: DocumentSession,
                                 service: ProjectService) {
    let session = playheadFeatureSession(suite, service: service)
    configurePlayheadCamera(session, width: 320, height: 240, pixelsPerBeat: 512.0)
    session.mutateCamera { camera in
        _ = camera.setHScroll(0)
    }

    let presenter = SharedPlayheadPresenter()
    presenter.attach(session: session, audio: nil, grid: nil, drawer: nil)
    presenter.setFollowEnabled(true)

    let endTick = Tick(session.timeline.lengthTicks)
    report.expect(endTick > 1, cppID: playheadCppID(playheadFollowID, "A033"),
                  message: "the follow fixture has a nontrivial timeline")
    let snapshot = session.camera.snapshot
    let candidate = max(0.0, snapshot.viewportWidth * 4.0 / snapshot.pixelsPerTick + 1.0)
    let farTick = endTick > 1 ? min(endTick - 1, Tick(candidate)) : 0
    report.expect(farTick > 0, cppID: playheadCppID(playheadFollowID, "A035"),
                  message: "the follow probe chooses a positive far tick")

    let sample = session.timeline.sample(for: farTick)
    _ = presenter.observe(sample: sample, transport: 2)
    report.expect(session.camera.snapshot.scrollX > 0,
                  cppID: playheadCppID(playheadFollowID, "A036"),
                  message: "playing a far tick follows the playhead horizontally")

    session.mutateCamera { camera in
        _ = camera.setHScroll(0)
    }
    presenter.setFollowEnabled(false)
    _ = presenter.observe(sample: sample, transport: 2)
    report.expect(playheadNear(session.camera.snapshot.scrollX, 0),
                  cppID: playheadCppID(playheadFollowID, "A037"),
                  message: "disabling follow leaves the camera parked")

    presenter.setFollowEnabled(true)
    _ = presenter.observe(sample: sample, transport: 2)
    report.expect(session.camera.snapshot.scrollX > 0,
                  cppID: playheadCppID(playheadFollowID, "A038"),
                  message: "re-enabling follow moves the parked camera to the playhead")
}

@MainActor
private func checkPlayheadAppearance(_ report: CheckReport, suite: DocumentSession,
                                      service: ProjectService) {
    let session = playheadFeatureSession(suite, service: service)
    let grid = PianoGrid(session: session)
    grid.configureViewport(width: 320, height: 240, fontPx: 13, dpr: 1)
    let presenter = SharedPlayheadPresenter()
    presenter.attach(session: session, audio: nil, grid: grid, drawer: nil)
    let sample = session.timeline.sample(for: 48)

    _ = presenter.observe(sample: sample, transport: 0)
    report.expect(playheadNear(presenter.glowLeft, 8.0)
                    && playheadNear(presenter.glowRight, 8.0),
                  cppID: playheadCppID(playheadAppearanceID, "paused-glow"),
                  message: "paused glow extents use the full radius on both sides")
    report.expect(playheadNear(presenter.peakAlpha, 0.06),
                  cppID: playheadCppID(playheadAppearanceID, "paused-alpha"),
                  message: "paused peak alpha is the low-opacity value")

    _ = presenter.observe(sample: sample, transport: 2)
    report.expect(playheadNear(presenter.glowLeft, 7.0)
                    && playheadNear(presenter.glowRight, 0.5),
                  cppID: playheadCppID(playheadAppearanceID, "playing-glow"),
                  message: "playing glow extents use the asymmetric core-facing spans")
    report.expect(playheadNear(presenter.peakAlpha, 0.13),
                  cppID: playheadCppID(playheadAppearanceID, "playing-alpha"),
                  message: "playing peak alpha is the active-opacity value")
    report.expect(playheadNear(presenter.lineWidthPx, 1.0)
                    && playheadNear(presenter.triangleHalfWidthPx, 3.0)
                    && playheadNear(presenter.triangleHeightPx, 7.0)
                    && presenter.trianglePointsUp == false,
                  cppID: playheadCppID(playheadAppearanceID, "triangle-metrics"),
                  message: "line width, font-derived triangle metrics, and down polarity are published")

    grid.configureViewport(width: 320, height: 240, fontPx: 26, dpr: 1)
    presenter.refreshProjection()
    let largerBase = grid.baseFontPx
    report.expect(largerBase == 26
                    && playheadNear(presenter.glowLeft, 15.0)
                    && playheadNear(presenter.glowRight, 0.5)
                    && playheadNear(presenter.triangleHalfWidthPx, 7.0)
                    && playheadNear(presenter.triangleHeightPx, 13.0),
                  cppID: playheadCppID(playheadAppearanceID, "base-font-reprojection"),
                  message: "changing baseFontPx recomputes every published appearance metric")
}

/// QRectF-compatible logical/device rect for the devicePixelRect oracle port.
/// Named locally because `CGRect` resolves to Qt's opaque forward declaration
/// (qrect.h) under C++ interop, not CoreGraphics.
private struct PlayheadDeviceRect: Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

fileprivate func devicePixelRect(_ logicalRect: PlayheadDeviceRect, dpr: Double,
                                 imageWidth: Double, imageHeight: Double) -> PlayheadDeviceRect {
    let scale = dpr.isFinite && dpr > 0 ? dpr : 1.0
    let imageWidth = max(0.0, imageWidth)
    let imageHeight = max(0.0, imageHeight)
    let logicalLeft = min(logicalRect.x, logicalRect.x + logicalRect.width)
    let logicalRight = max(logicalRect.x, logicalRect.x + logicalRect.width)
    let logicalTop = min(logicalRect.y, logicalRect.y + logicalRect.height)
    let logicalBottom = max(logicalRect.y, logicalRect.y + logicalRect.height)
    let left = min(imageWidth, max(0.0, floor(logicalLeft * scale)))
    let right = min(imageWidth, max(0.0, ceil(logicalRight * scale)))
    let top = min(imageHeight, max(0.0, floor(logicalTop * scale)))
    let bottom = min(imageHeight, max(0.0, ceil(logicalBottom * scale)))
    return PlayheadDeviceRect(x: left, y: top, width: max(0.0, right - left),
                              height: max(0.0, bottom - top))
}

@MainActor
private func checkPlayheadDevicePixelRect(_ report: CheckReport) {
    let logicalRect = PlayheadDeviceRect(x: 3, y: 2, width: 5, height: 4)
    report.expectEqual(expected: logicalRect,
                       actual: devicePixelRect(logicalRect, dpr: 1.0, imageWidth: 16, imageHeight: 10),
                       cppID: playheadCppID(playheadMathID, "A001"),
                       what: "DPR 1 preserves the logical rectangle")
    report.expectEqual(expected: PlayheadDeviceRect(x: 6, y: 4, width: 10, height: 8),
                       actual: devicePixelRect(logicalRect, dpr: 2.0, imageWidth: 32, imageHeight: 20),
                       cppID: playheadCppID(playheadMathID, "A002"),
                       what: "DPR 2 doubles position and extent")
    report.expectEqual(expected: PlayheadDeviceRect(x: 4, y: 3, width: 8, height: 6),
                       actual: devicePixelRect(logicalRect, dpr: 1.5, imageWidth: 12, imageHeight: 14),
                       cppID: playheadCppID(playheadMathID, "A003"),
                       what: "fractional DPR floors the origin and ceils the far edge")
    report.expectEqual(expected: PlayheadDeviceRect(x: 1, y: 1, width: 4, height: 4),
                       actual: devicePixelRect(PlayheadDeviceRect(x: 1, y: 1, width: 2, height: 2),
                                       dpr: 1.5, imageWidth: 12, imageHeight: 14),
                       cppID: playheadCppID(playheadMathID, "A004"),
                       what: "fractional DPR rounds a second logical rectangle outward")
}

@MainActor
private func checkPlayheadMiddlePan(_ report: CheckReport, suite: DocumentSession,
                                    service: ProjectService) {
    let session = playheadFeatureSession(suite, service: service)
    let grid = PianoGrid(session: session)
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 1)
    session.mutateCamera { camera in
        _ = camera.setTimeZoom(512.0)
        _ = camera.setHScroll(120.0)
        _ = camera.setVScroll(200.0)
    }

    let before = session.camera.snapshot
    grid.beginPan(x: 100, y: 100)
    report.expect(grid.interactionActive && grid.cursorKind == 4,
                  cppID: playheadCppID(playheadPanID, "begin"),
                  message: "middle-pan begins with an active interaction and closed-hand cursor")
    grid.updatePan(x: 112, y: 80)
    let after = session.camera.snapshot
    report.expect(playheadNear(after.scrollX, before.scrollX - 12.0)
                    && playheadNear(after.scrollY, before.scrollY + 20.0),
                  cppID: playheadCppID(playheadPanID, "camera-delta"),
                  message: "pan moves the camera by the negative pointer delta on both axes")
    report.expect(grid.interactionActive && grid.cursorKind == 4,
                  cppID: playheadCppID(playheadPanID, "active"),
                  message: "the gesture retains ownership while the pointer is down")

    let presenter = SharedPlayheadPresenter()
    presenter.attach(session: session, audio: nil, grid: grid, drawer: nil)
    presenter.setFollowEnabled(true)
    let followBefore = session.camera.snapshot
    _ = presenter.observe(sample: session.timeline.sample(for: 120), transport: 2)
    let followDuring = session.camera.snapshot
    report.expect(grid.interactionActive
                    && playheadNear(followDuring.scrollX, followBefore.scrollX)
                    && playheadNear(followDuring.scrollY, followBefore.scrollY),
                  cppID: playheadCppID(playheadPanID, "follow-suspended"),
                  message: "a live pan suspends shared playhead follow")

    grid.endPan()
    report.expect(!grid.interactionActive && grid.cursorKind == 0,
                  cppID: playheadCppID(playheadPanID, "end"),
                  message: "ending pan clears the gesture and restores the arrow cursor")

    grid.beginPan(x: 200, y: 200)
    grid.inputCancelled(reason: GridCancelReason.pointerUngrabbed.rawValue)
    report.expect(!grid.interactionActive && grid.cursorKind == 0,
                  cppID: playheadCppID(playheadPanID, "cancel"),
                  message: "input cancellation clears pan ownership and cursor state")
}

@MainActor
func runPlayheadFeatureChecks(_ report: CheckReport, suite: DocumentSession,
                              service: ProjectService) {
    checkPlayheadGuides(report, suite: suite, service: service)
    checkPlayheadFollow(report, suite: suite, service: service)
    checkPlayheadAppearance(report, suite: suite, service: service)
    checkPlayheadDevicePixelRect(report)
    checkPlayheadMiddlePan(report, suite: suite, service: service)
}
