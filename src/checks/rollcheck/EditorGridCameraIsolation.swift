import Foundation
@testable import PorydawApp
import PorydawCore
import QtBridge

@MainActor
func checkIsolation(
    _ report: CheckReport, session: DocumentSession, grid: PianoGrid,
    counters: GridCameraIntegrationCounters
) {
    let revision = session.document.revision
    let dirty = session.document.isDirty
    let canUndo = session.document.history.canUndo
    let canRedo = session.document.history.canRedo
    let cursor = session.editCursor
    counters.camera = 0
    counters.playback = 0
    counters.document = 0
    counters.cursor = 0

    _ = session.mutateCamera { _ = $0.setTimeZoom(140) }
    grid.handleWheel(
        angleDeltaX: 0, angleDeltaY: -10, pixelDeltaX: 0, pixelDeltaY: 0,
        modifiers: 0x0200_0000, phase: QtScrollPhase.update.rawValue,
        overGutter: false, anchorX: 200, anchorY: 100)
    grid.resetCameraScroll()
    var before = counters.camera
    _ = session.mutateCamera {
        _ = $0.ensureTickVisible(UInt64(session.timeline.lengthTicks), dpr: grid.devicePixelRatio)
    }
    let tickReveal = session.camera.snapshot
    let expectedTickReveal = min(
        tickReveal.maxHScroll,
        Double(session.timeline.lengthTicks) * tickReveal.pixelsPerTick
            - tickReveal.viewportWidth / 3)
    report.expect(
        counters.camera == before + 1
            && gridCameraNear(tickReveal.scrollX, expectedTickReveal),
        cppID: isolationID, message: "ensureTickVisible uses the reveal fraction in one publication")

    grid.resetCameraScroll()
    before = counters.camera
    _ = session.mutateCamera {
        _ = $0.ensureRangeVisible(
            startTick: 0, endTick: UInt64(session.timeline.lengthTicks),
            preferEnd: true, dpr: grid.devicePixelRatio)
    }
    let endReveal = session.camera.snapshot
    report.expect(
        counters.camera == before + 1
            && gridCameraNear(
                endReveal.scrollX,
                endReveal.maxHScroll - endReveal.viewportWidth
                    + 1 / grid.devicePixelRatio),
        cppID: isolationID, message: "preferEnd true aligns an oversized range to the right edge")

    grid.setCameraHScroll(value: session.camera.snapshot.maxHScroll)
    before = counters.camera
    _ = session.mutateCamera {
        _ = $0.ensureRangeVisible(
            startTick: 0, endTick: UInt64(session.timeline.lengthTicks),
            preferEnd: false, dpr: grid.devicePixelRatio)
    }
    let startReveal = session.camera.snapshot
    report.expect(
        counters.camera == before + 1 && gridCameraNear(startReveal.scrollX, 0),
        cppID: isolationID, message: "preferEnd false aligns an oversized range to its start")

    grid.setCameraVScroll(value: 0)
    before = counters.camera
    _ = session.mutateCamera { _ = $0.ensureKeyVisible(0) }
    let keyReveal = session.camera.snapshot
    report.expect(
        counters.camera == before + 1
            && gridCameraNear(keyReveal.scrollY, keyReveal.maxVScroll),
        cppID: isolationID, message: "ensureKeyVisible aligns the bottom pitch at the viewport edge")
    report.expect(
        gridCameraNear(grid.cameraScrollX, session.camera.snapshot.scrollX)
            && gridCameraNear(grid.cameraScrollY, session.camera.snapshot.scrollY),
        cppID: isolationID, message: "presenter scroll values track the revealed session camera")

    before = counters.camera
    let current = session.camera.snapshot
    grid.setCameraHScroll(value: current.scrollX)
    grid.setCameraVScroll(value: current.scrollY)
    grid.setCameraHScroll(value: .nan)
    grid.setCameraVScroll(value: .infinity)
    _ = session.mutateCamera { _ = $0.ensureKeyVisible(-1) }
    if let centerPitch = session.camera.projection.pitch(
        atY: current.rollHeight / 2, keyHeight: current.keyHeight,
        scrollY: current.scrollY, dpr: grid.devicePixelRatio)
    {
        _ = session.mutateCamera { _ = $0.ensureKeyVisible(centerPitch) }
    } else {
        report.fail(
            isolationID, "viewport centre row did not resolve to a visible projected pitch")
    }
    report.expect(
        counters.camera == before,
        cppID: isolationID, message: "redundant, non-finite, hidden, and already-visible navigation is silent")

    let published = session.camera.snapshot
    session.editCursor = cursor == 0 ? 24 : 0
    report.expect(
        session.camera.snapshot == published && grid.editCursorTick == Int(cursor),
        cppID: isolationID, message: "direct edit-cursor change neither moves camera nor republishes presenter cursor")
    report.expect(
        counters.document == 0 && counters.playback == 0 && counters.cursor == 1
            && session.document.revision == revision && session.document.isDirty == dirty
            && session.document.history.canUndo == canUndo
            && session.document.history.canRedo == canRedo,
        cppID: isolationID, message: "camera navigation is isolated from document, playback, dirty state, and history")

    counters.camera = 0
    counters.playback = 0
    counters.document = 0
    counters.coherentDocumentCallback = false
    let editTick = Tick(
        min(
            UInt64(TimeDefaults.maxTick - 1), UInt64(session.timeline.lengthTicks) + 24))
    let inserted = try? session.document.addNotes([
        NewNote(
            track: grid.trackIndex, tick: editTick, pitch: 60,
            duration: 1, velocity: 100)
    ])
    report.expect(
        inserted?.count == 1 && counters.camera == 0,
        cppID: isolationID, message: "committed document edit performs no standalone camera publication")
    report.expect(
        counters.playback == 1 && counters.document == 1 && counters.coherentDocumentCallback,
        cppID: isolationID,
        message: "one edit publishes one coherent playback and document refresh after reconciliation")
    session.editCursor = cursor
}
