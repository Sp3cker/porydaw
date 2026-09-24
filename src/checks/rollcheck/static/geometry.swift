import Foundation
import PorydawApp
import PorydawCore

@MainActor
func runGeometryChecks(_ report: CheckReport, session: DocumentSession) {
    checkDefaultBindKeepsGeometry(report)
    checkTicksPerBeatKeepsGeometry(report)
    checkScaleProjectionInvariants(report, session: session)
    checkScaleHighlightRasterDocumentGuards(report, session: session)
}

private func geometryCamera(lengthTicks: UInt64? = nil,
                            projection: PitchProjection = PitchProjection()) -> EditorCamera {
    let limits = EditorCamera.Limits(
        defaultPixelsPerBeat: 35, minPixelsPerBeat: 4, maxPixelsPerBeat: 693,
        defaultKeyHeight: 13, minKeyHeight: 4, maxKeyHeight: 35,
        revealViewportFraction: 1.0 / 3.0, minimumPlotWidth: 54)
    return EditorCamera(ticksPerBeat: 24, lengthTicks: lengthTicks,
                        viewportWidth: 1280, rollHeight: 800,
                        limits: limits, projection: projection)
}

private func checkDefaultBindKeepsGeometry(_ report: CheckReport) {
    let id = "swiftcore/PianoRollStaticTest::defaultBindKeepsGeometry"
    var camera = geometryCamera()
    let initialZoom = camera.snapshot.pixelsPerBeat
    let original = (0..<6).map { camera.contentX(tick: Double($0 * 4 * 24)) }
    camera.updateTimeDomain(ticksPerBeat: 24, lengthTicks: 16 * 4 * 24)
    report.expect(gridCameraNear(camera.snapshot.pixelsPerBeat, initialZoom, tolerance: 1e-9),
                  cppID: id, message: "A032 binding 4/4 preserves the default beat zoom")
    for bar in 0..<6 {
        report.expect(gridCameraNear(camera.contentX(tick: Double(bar * 4 * 24)),
                                     original[bar], tolerance: 1e-9),
                      cppID: id, message: "A035 bar \(bar) keeps unbound content geometry")
    }
}

private func checkTicksPerBeatKeepsGeometry(_ report: CheckReport) {
    let id = "swiftcore/PianoRollStaticTest::ticksPerBeatKeepsGeometry"
    var camera = geometryCamera(lengthTicks: 16 * 4 * 24)
    let original = (1...8).map { camera.contentX(tick: Double($0 * 24)) }
    let initialZoom = camera.snapshot.pixelsPerBeat
    let originalColumns = (1...3).map { camera.displayX(tick: Double($0 * 24), origin: 0, dpr: 1) }
    camera.updateTimeDomain(ticksPerBeat: 48, lengthTicks: 16 * 4 * 48)
    report.expect(gridCameraNear(camera.snapshot.pixelsPerBeat, initialZoom, tolerance: 1e-9),
                  cppID: id, message: "A037 binding 48 TPB retains the default beat zoom")
    for beat in 1...3 {
        report.expect(abs(camera.displayX(tick: Double(beat * 48), origin: 0, dpr: 1)
                          - originalColumns[beat - 1]) <= 1,
                      cppID: id, message: "A039 beat \(beat) retains its display column")
    }
    for beat in 1...8 {
        report.expect(abs(camera.contentX(tick: Double(beat * 48)) - original[beat - 1]) <= 1e-6,
                      cppID: id, message: "A042 beat \(beat) retains its content coordinate")
    }
}

@MainActor
private func checkScaleProjectionInvariants(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRollTest::scaleProjectionInvariants"
    let chromatic = PitchProjection()
    report.expect(chromatic.visibleRowCount == 128, cppID: id,
                  message: "A001 Off projects all 128 pitches")
    report.expect((0..<128).allSatisfy { chromatic.row(forPitch: $0) != PitchProjection.hiddenRow },
                  cppID: id, message: "A002 Off hides no pitch")
    // PitchProjection has no root or scale argument; the root-change path remains unproved.
    report.expect(PitchProjection().visibleRowCount == chromatic.visibleRowCount, cppID: id,
                  message: "A003 related chromatic construction remains 128 rows")
    let track = session.selectedTrack ?? 0
    let notes = session.document.notes(in: track)
    let occupied = Set(notes.map(\.pitch))
    let folded = PitchProjection(visiblePitches: occupied.sorted())
    report.expect(folded.visibleRowCount == occupied.count, cppID: id,
                  message: "A004 folded row count equals distinct selected-track pitches")
    var previous = 128
    var descending = true
    for row in 0..<folded.visibleRowCount {
        guard let pitch = folded.visiblePitch(at: row), pitch < previous else {
            descending = false
            break
        }
        previous = pitch
    }
    report.expect(descending, cppID: id, message: "A005 folded rows descend strictly")
    report.expect((0..<128).allSatisfy {
        (folded.row(forPitch: $0) != PitchProjection.hiddenRow) == occupied.contains(UInt8($0))
    }, cppID: id, message: "A006 folded visible pitches exactly equal selected-track occupancy")
    report.expect((0..<folded.visibleRowCount).allSatisfy { row in
        folded.visiblePitch(at: row).map { folded.row(forPitch: $0) == row } == true
    }, cppID: id, message: "A007 each visible folded row maps back to itself")
    report.expect((0..<128).allSatisfy { pitch in
        let row = folded.row(forPitch: pitch)
        return row == PitchProjection.hiddenRow || folded.visiblePitch(at: row) == pitch
    }, cppID: id, message: "A008 each visible folded pitch maps back to itself")
    let freeBase = stride(from: 1, through: 115, by: 12).first {
        !occupied.contains(UInt8($0)) && !occupied.contains(UInt8($0 + 12))
    }
    checkDocumentUndoProbe(
        report, session: session, id: id,
        messages: UndoProbeMessages(
            insertionFailure: "A010-A012 selected-track insertion was not committed",
            undoFailure: "A015-A016 fold occupancy probe could not undo its note insertion",
            errorPrefix: "A010-A012 selected-track insertion failed",
            history: "A015 undo restores the pre-probe document history",
            bytes: "A016 undo restores serialized MIDI"
        ),
        makeNote: { document in
            guard let freeBase else {
                report.fail(id, "A010-A012 no free C-sharp octave pair in selected track")
                return nil
            }
            return NewNote(track: track,
                           tick: session.timeline.lengthTicks + Tick(document.ticksPerBeat * 8),
                           pitch: UInt8(freeBase), duration: Tick(document.ticksPerBeat),
                           velocity: 100)
        },
        inspectAdded: { document, note in
            let insertedBase = Int(note.pitch)
            let inserted = PitchProjection(visiblePitches:
                Set(document.notes(in: track).map(\.pitch)).sorted())
            report.expect(inserted.row(forPitch: insertedBase) != PitchProjection.hiddenRow,
                          cppID: id, message: "A010 occupied off-scale C-sharp becomes visible")
            report.expect(inserted.row(forPitch: insertedBase + 12) == PitchProjection.hiddenRow,
                          cppID: id, message: "A011 unused off-scale octave remains hidden")
            let freePitch = stride(from: 1, through: 127, by: 12).first {
                !occupied.contains(UInt8($0)) && $0 != insertedBase
            }
            report.expect(freePitch.map { inserted.row(forPitch: $0) == PitchProjection.hiddenRow }
                          == true, cppID: id, message: "A012 unused off-scale pitch remains hidden")
        },
        afterUndo: {
            let tieProjection = PitchProjection(visiblePitches: [60, 62])
            report.expect(tieProjection.nearestVisiblePitch(to: 61) == 60, cppID: id,
                          message: "A013 equal-distance nearest pitch chooses lower pitch")
            var camera = geometryCamera(projection: folded)
            _ = camera.setVScroll(1.0e9)
            let maximum = max(0, folded.totalHeight(keyHeight: camera.snapshot.keyHeight)
                              - camera.snapshot.rollHeight)
            report.expect(camera.snapshot.scrollY >= -1e-9 && camera.snapshot.scrollY <= maximum + 1e-9,
                          cppID: id, message: "A014 folded scroll remains inside its projected height")
        }
    )
}

@MainActor
private func checkScaleHighlightRasterDocumentGuards(
    _ report: CheckReport, session: DocumentSession
) {
    let id = "swiftcore/PianoRollTest::scaleHighlightRaster"
    let track = session.selectedTrack ?? 0
    let pitches = Set(session.document.notes(in: track).map(\.pitch))
    guard let freePitch = (0..<128).first(where: { !pitches.contains(UInt8($0)) }) else {
        report.fail(id, "A031-A032 no unused pitch for highlight probe")
        return
    }
    checkDocumentUndoProbe(
        report, session: session, id: id,
        messages: UndoProbeMessages(
            insertionFailure: "A031-A032 highlight note probe could not undo its insertion",
            undoFailure: "A031-A032 highlight note probe could not undo its insertion",
            errorPrefix: "A031-A032 highlight note probe failed",
            history: "A031 highlight note probe restores document history",
            bytes: "A032 highlight note probe restores serialized MIDI"
        ),
        makeNote: { _ in
            NewNote(track: track, tick: session.timeline.lengthTicks + 8,
                    pitch: UInt8(freePitch), duration: 1, velocity: 100)
        }
    )
}

private struct UndoProbeMessages {
    let insertionFailure: String
    let undoFailure: String
    let errorPrefix: String
    let history: String
    let bytes: String
}

@MainActor
private func checkDocumentUndoProbe(
    _ report: CheckReport, session: DocumentSession, id: String,
    messages: UndoProbeMessages,
    makeNote: (SongDocument) -> NewNote?,
    inspectAdded: ((SongDocument, NewNote) -> Void)? = nil,
    afterUndo: (() -> Void)? = nil
) {
    let document = SongDocument(file: session.document.state.file,
                                config: session.document.state.config)
    let before = try? document.captureSave().bytes
    let identity = document.history.currentIdentity
    if let note = makeNote(document) {
        do {
            let added = try document.addNotes([note])
            guard added.count == 1 else {
                report.fail(id, messages.insertionFailure)
                return
            }
            inspectAdded?(document, note)
            guard document.history.undoDocument() else {
                report.fail(id, messages.undoFailure)
                return
            }
        } catch {
            report.fail(id, "\(messages.errorPrefix): \(error)")
            return
        }
    }
    afterUndo?()
    report.expect(document.history.currentIdentity == identity, cppID: id,
                  message: messages.history)
    report.expect(before != nil && (try? document.captureSave().bytes) == before,
                  cppID: id, message: messages.bytes)
}

