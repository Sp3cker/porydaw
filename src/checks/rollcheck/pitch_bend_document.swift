import Foundation
@testable import PorydawApp
import PorydawCore
import QtBridge

@MainActor
func pitchBendReadoutPredicates(_ report: CheckReport, session: DocumentSession) {
    let readoutID = "swiftcore/PitchBendEditingTest::liveValueReadout"
    if let scene = pitchBendCheckScene(report, cppID: readoutID, session: session) {
        defer { scene.presenter.cancelAndClose() }
        let roles = Typography(baseFontPx: 13)
        func matches(_ key: String, _ expected: [String: QVariantSettable]) -> Bool {
            guard let map = scene.presenter.appearance[key] as? [String: QVariantSettable] else {
                return false
            }
            return map["family"] as? String == expected["family"] as? String
                && map["pixelSize"] as? Int == expected["pixelSize"] as? Int
                && map["weight"] as? Int == expected["weight"] as? Int
        }
        report.expect(
            matches("titleFont", roles.bodyBold.map) && matches("captionFont", roles.caption.map)
                && matches("monospaceFont", roles.bodyMono.map),
            cppID: readoutID,
            message: "the popup title, caption, and readout publish bold body, caption, and body mono faces")
        let drag = scene.presenter.appearance["dragInput"] as? [String: QVariantSettable]
        let dragFont = drag?["font"] as? [String: QVariantSettable]
        report.expect(
            dragFont?["family"] as? String == roles.body.family
                && dragFont?["pixelSize"] as? Int == roles.body.pixelSize
                && dragFont?["weight"] as? Int == roles.body.weight,
            cppID: readoutID,
            message: "pitch drag inputs use the published body font face")
        let resized = Typography(baseFontPx: 26)
        scene.presenter.configure(fontPx: 26, lineSpacing: 29, dpr: 2)
        let resizedDrag = scene.presenter.appearance["dragInput"] as? [String: QVariantSettable]
        let resizedFont = resizedDrag?["font"] as? [String: QVariantSettable]
        report.expect(
            matches("titleFont", resized.bodyBold.map) && matches("captionFont", resized.caption.map)
                && matches("monospaceFont", resized.bodyMono.map)
                && resizedFont?["family"] as? String == resized.body.family
                && resizedFont?["pixelSize"] as? Int == resized.body.pixelSize
                && resizedDrag?["horizontalPadding"] as? Double == Double(resized.space(.one)),
            cppID: readoutID,
            message: "resizing the pitch popup republishes the title, caption, readout, and input roles")
        scene.presenter.configure(fontPx: 13, lineSpacing: 13, dpr: 2)
        report.expectEqual(
            expected: "0 st", actual: scene.presenter.pitchGraph().liveValueText,
            cppID: readoutID,
            what: "the pitch readout at rest is 0 st")
        report.expectEqual(
            expected: "0", actual: scene.presenter.modGraph().liveValueText,
            cppID: readoutID,
            what: "the modulation readout at rest is the plain decimal")
    }

    let geometry = PitchBendGeometry(fontPx: 14, lineSpacing: 17, dpr: 2)
    let pitch = PitchBendLane(
        kernel: PitchBendKernel(
            lane: .pitch, geometry: geometry,
            startTick: 96, endTick: 192,
            fineTicks: 1, snap: pitchBendFixtureSnap,
            snapUp: pitchBendFixtureSnapUp,
            points: [96: 4096, 192: 0], endValue: 0),
        palette: GridPalette(), track: 0)
    pitch.bendRange = 5
    pitch.rebuild()
    report.expectEqual(
        expected: "+2.50 st", actual: pitch.liveValueText,
        cppID: readoutID,
        what: "the pitch readout formats liveValue 4096 at bendRange 5 "
            + "as +2.50 st")
}

@MainActor
func pitchBendDocumentPredicates(_ report: CheckReport, session: DocumentSession) {
    let undoPreservationID = "swiftcore/PitchBendEditingTest::bendrFixtureUndoPreservation"
    let shiftLineID = "swiftcore/PitchBendEditingTest::shiftDragDrawsLinearRamp"
    let freehandID = "swiftcore/PitchBendEditingTest::freehandStrokePushesSingleUndoCommand"
    let undoShortcutID = "swiftcore/PitchBendEditingTest::standardUndoShortcutRestoresCurve"
    let navigationID = "swiftcore/PitchBendEditingTest::navigationKeysDoNotModifyCurve"
    let stackedID = "swiftcore/PitchBendEditingTest::stackedStrokesPushIndependentUndoCommands"
    let confinementID = "swiftcore/PitchBendEditingTest::freehandStrokeConfinedToNoteSpan"
    let smfID = "swiftcore/PitchBendEditingTest::pitchWheelSerializesValidSmfEvents"

    let document = session.document

    if let scene = pitchBendCheckScene(report, cppID: undoPreservationID, session: session) {
        defer { scene.presenter.cancelAndClose() }
        let before = coreTimeBytes(document)
        let index = document.history.undoIndex
        document.writeLane(
            track: scene.note.track, lane: .controller(0x14),
            from: scene.note.tick, through: scene.note.tick,
            points: [LaneWrite(tick: scene.note.tick, value: 12)])
        report.expectEqual(
            expected: index + 1, actual: document.history.undoIndex,
            cppID: undoPreservationID,
            what: "one BENDR write pushes exactly one history entry")
        report.expect(
            pitchBendLaneHasPoint(
                document, track: scene.note.track,
                lane: .controller(0x14), tick: scene.note.tick,
                value: 12),
            cppID: undoPreservationID,
            message: "the written BENDR point is visible in the lane")
        report.expect(
            document.history.undoDocument() && document.history.undoIndex == index,
            cppID: undoPreservationID,
            message: "undoing the BENDR write restores the history index")
        report.expectEqual(
            expected: before, actual: coreTimeBytes(document),
            cppID: undoPreservationID,
            what: "undoing the BENDR write restores the serialized song")
        report.expect(
            pitchBendSpanAlive(session, note: scene.note, noteEnd: scene.noteEnd),
            cppID: undoPreservationID,
            message: "the note span survives its lane undo")
    }

    if let scene = pitchBendCheckScene(report, cppID: shiftLineID, session: session) {
        defer { scene.presenter.cancelAndClose() }
        let graph = scene.presenter.pitchGraph()
        report.expect(
            graph.kernel.geometry.canvasWidth > 0
                && graph.kernel.geometry.canvasHeight > 0,
            cppID: shiftLineID,
            message: "the pitch graph presents a real canvas")
        let index = document.history.undoIndex
        let before = coreTimeBytes(document)
        pitchBendStroke(
            graph, x0f: 0.15, y0f: 0.80, x1f: 0.85, y1f: 0.20,
            modifiers: 0x0200_0000)
        report.expectEqual(
            expected: index + 1, actual: document.history.undoIndex,
            cppID: shiftLineID,
            what: "one Shift-line stroke pushes exactly one history entry")
        report.expect(
            scene.presenter.isOpen, cppID: shiftLineID,
            message: "rendering the Shift line keeps the editor open")
        let interior = document.lanePoints(track: scene.note.track, lane: .pitchBend)
            .filter { $0.tick > scene.note.tick && $0.tick < scene.noteEnd }
        report.expect(
            interior.count >= 2, cppID: shiftLineID,
            message: "the Shift line serializes interior lane points")
        report.expect(
            !interior.indices.dropFirst().contains(where: {
                interior[$0].value == interior[$0 - 1].value
            }), cppID: shiftLineID,
            message: "adjacent interior lane points never share one value")
        report.expect(
            document.history.undoDocument() && coreTimeBytes(document) == before,
            cppID: shiftLineID,
            message: "undoing the Shift line restores the serialized song")
    }

    if let scene = pitchBendCheckScene(report, cppID: freehandID, session: session) {
        defer { scene.presenter.cancelAndClose() }
        let graph = scene.presenter.pitchGraph()
        let index = document.history.undoIndex
        pitchBendDrawCurve(graph)
        report.expectEqual(
            expected: index + 1, actual: document.history.undoIndex,
            cppID: freehandID,
            what: "one freehand stroke pushes exactly one history entry")
        report.expect(
            scene.presenter.isOpen, cppID: freehandID,
            message: "a committed freehand stroke keeps the editor open")
        report.expect(
            document.history.undoDocument(), cppID: freehandID,
            message: "the freehand stroke's history entry undoes")
    }

    if let scene = pitchBendCheckScene(report, cppID: undoShortcutID, session: session) {
        defer { scene.presenter.cancelAndClose() }
        let graph = scene.presenter.pitchGraph()
        let before = coreTimeBytes(document)
        let index = document.history.undoIndex
        pitchBendDrawCurve(graph)
        report.expect(
            document.history.undoDocument() && document.history.undoIndex == index,
            cppID: undoShortcutID,
            message: "undoing the drawn curve restores the history index")
        report.expectEqual(
            expected: before, actual: coreTimeBytes(document),
            cppID: undoShortcutID,
            what: "undoing the drawn curve restores the serialized song")
        report.expect(
            scene.presenter.isOpen, cppID: undoShortcutID,
            message: "the editor survives undoing its curve")
    }

    if let scene = pitchBendCheckScene(report, cppID: navigationID, session: session) {
        defer { scene.presenter.cancelAndClose() }
        let before = coreTimeBytes(document)
        let index = document.history.undoIndex
        for key in [
            0x01000012, 0x01000014, 0x01000010, 0x01000011, 0x01000015,
            0x01000016, 0x01000017, 0x30,
        ] {
            let modifiers = key == 0x01000016 ? 0x0200_0000 : 0
            report.expect(
                !scene.presenter.routeUnclaimedKey(
                    key: key, modifiers: modifiers,
                    autoRepeat: false)
                    && document.history.undoIndex == index,
                cppID: navigationID,
                message: "navigation key \(key) pushes no history entry")
            report.expectEqual(
                expected: before, actual: coreTimeBytes(document),
                cppID: navigationID,
                what: "navigation key \(key) leaves the serialized song")
        }
        report.expect(
            scene.presenter.isOpen, cppID: navigationID,
            message: "navigation keys keep the editor open")
    }

    if let scene = pitchBendCheckScene(report, cppID: stackedID, session: session) {
        defer { scene.presenter.cancelAndClose() }
        let graph = scene.presenter.pitchGraph()
        let baseline = coreTimeBytes(document)
        let baselineIndex = document.history.undoIndex
        pitchBendDrawCurve(graph)
        let first = coreTimeBytes(document)
        let firstIndex = document.history.undoIndex
        report.expectEqual(
            expected: baselineIndex + 1, actual: firstIndex,
            cppID: stackedID,
            what: "the first stroke pushes one independent history entry")
        pitchBendStroke(graph, x0f: 0.10, y0f: 0.25, x1f: 0.40, y1f: 0.75)
        report.expectEqual(
            expected: firstIndex + 1, actual: document.history.undoIndex,
            cppID: stackedID,
            what: "the second stroke pushes its own history entry")
        report.expect(
            coreTimeBytes(document) != first, cppID: stackedID,
            message: "stacked strokes serialize different curves")
        report.expect(
            document.history.undoDocument() && document.history.undoIndex == firstIndex,
            cppID: stackedID,
            message: "the first undo returns to the first stroke's index")
        report.expectEqual(
            expected: first, actual: coreTimeBytes(document),
            cppID: stackedID,
            what: "the first undo restores the first stroke's bytes")
        report.expect(
            document.history.undoDocument() && document.history.undoIndex == baselineIndex,
            cppID: stackedID,
            message: "the second undo returns to the pre-stroke index")
        report.expectEqual(
            expected: baseline, actual: coreTimeBytes(document),
            cppID: stackedID,
            what: "the second undo restores the pre-stroke bytes")
    }

    let canonicalID = "swiftcore/PitchBendEditingTest::canonicalCurveCommit"
    let canonicalService = ProjectService()
    let canonicalSession = pitchBendSyntheticSession(session, service: canonicalService)
    defer { withExtendedLifetime(canonicalService) {} }
    if let scene = pitchBendCheckScene(report, cppID: canonicalID, session: canonicalSession) {
        defer { scene.presenter.cancelAndClose() }
        let graph = scene.presenter.pitchGraph()
        let start = Int(scene.note.tick)
        let end = Int(scene.noteEnd)
        let fine = graph.kernel.fineTicks
        guard end - start > 10 * fine else {
            report.fail(canonicalID, "the canonical curve fixture needs space for fine samples")
            return
        }
        let strokeStart = start + 8 * fine
        let strokeEnd = start + 10 * fine
        graph.kernel.setCurve(
            [
                start: 0, start + 3 * fine: 0, start + 4 * fine: 0,
                start + 5 * fine: 4096, start + 6 * fine: 4096, end: 0,
            ], endValue: 0)
        graph.rebuild()
        let index = canonicalSession.document.history.undoIndex
        graph.press(
            x: graph.kernel.x(at: strokeStart), y: graph.kernel.y(at: 8191),
            modifiers: 0x0200_0000)
        graph.drag(
            x: graph.kernel.x(at: strokeEnd), y: graph.kernel.y(at: 8191),
            modifiers: 0x0200_0000)
        let sampledStroke = graph.kernel.isSampledStroke
        graph.release(
            x: graph.kernel.x(at: strokeEnd), y: graph.kernel.y(at: 8191),
            modifiers: 0x0200_0000)
        let written = canonicalSession.document.lanePoints(
            track: scene.note.track,
            lane: .pitchBend)
        let prefix = written.prefix { $0.tick <= Tick(start + 5 * fine) }
        report.expect(
            sampledStroke && canonicalSession.document.history.undoIndex == index + 1
                && prefix.count == 3
                && prefix[0].tick == Tick(start) && prefix[0].value == 0
                && prefix[1].tick == Tick(start + 4 * fine) && prefix[1].value == 0
                && prefix[2].tick == Tick(start + 5 * fine) && prefix[2].value == 4096
                && written.last?.tick == scene.noteEnd && written.last?.value == 0,
            cppID: canonicalID,
            message: "the committed curve drops coarse plateaus but keeps fine neighbors and endpoints")
    }

    if let scene = pitchBendCheckScene(report, cppID: confinementID, session: session) {
        defer { scene.presenter.cancelAndClose() }
        let graph = scene.presenter.pitchGraph()
        var endValue = 0
        for point in document.lanePoints(track: scene.note.track, lane: .pitchBend) {
            if point.tick > scene.noteEnd { break }
            endValue = point.value
        }
        let before = document.lanePoints(track: scene.note.track, lane: .pitchBend)
        pitchBendDrawCurve(graph)
        let after = document.lanePoints(track: scene.note.track, lane: .pitchBend)
        var wroteInside = false
        var confined = true
        for point in after {
            let existedBefore = before.contains { $0.tick == point.tick && $0.value == point.value }
            if existedBefore { continue }
            confined = confined && point.tick >= scene.note.tick && point.tick <= scene.noteEnd
            if point.tick < scene.noteEnd && point.value != 0 { wroteInside = true }
        }
        report.expect(
            confined, cppID: confinementID,
            message: "every new curve point stays inside the note span")
        report.expect(
            wroteInside, cppID: confinementID,
            message: "the freehand stroke writes a nonzero interior point")
        report.expect(
            pitchBendLaneHasPoint(
                document, track: scene.note.track,
                lane: .pitchBend, tick: scene.noteEnd,
                value: endValue),
            cppID: confinementID,
            message: "the note-off lane point keeps its effective value")
        report.expect(
            document.history.undoDocument(), cppID: confinementID,
            message: "the confined stroke's history entry undoes")
    }

    if let scene = pitchBendCheckScene(report, cppID: smfID, session: session) {
        defer { scene.presenter.cancelAndClose() }
        let graph = scene.presenter.pitchGraph()
        pitchBendDrawCurve(graph)
        let map = document.engineTracks
        report.expect(
            scene.note.track < map.usedTrackCount
                && map.tracks.indices.contains(scene.note.track)
                && map.tracks[scene.note.track].midiChunk != nil,
            cppID: smfID,
            message: "the note's track maps to a serialized chunk")
        var found = false
        var data0Valid = true
        var data1Valid = true
        if let chunk = map.tracks[scene.note.track].midiChunk {
            for event in document.state.file.chunks[chunk].events {
                guard event.tick >= scene.note.tick && event.tick <= scene.noteEnd,
                    case let .channel(status, data0, data1) = event.payload,
                    status >> 4 == 0xE
                else { continue }
                found = true
                data0Valid = data0Valid && data0 <= 0x7F
                data1Valid = data1Valid && data1 <= 0x7F
            }
        }
        report.expect(
            data0Valid, cppID: smfID,
            message: "pitch-wheel data0 stays within 7 bits")
        report.expect(
            data1Valid, cppID: smfID,
            message: "pitch-wheel data1 stays within 7 bits")
        report.expect(
            found, cppID: smfID,
            message: "the note span serializes at least one pitch-wheel event")
        report.expect(
            document.history.undoDocument(), cppID: smfID,
            message: "the serialized stroke's history entry undoes")
    }
}
