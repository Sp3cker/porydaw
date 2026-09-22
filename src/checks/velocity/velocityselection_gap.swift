import Foundation
@testable import PorydawApp
import PorydawCore
import QtBridge

@MainActor
private func velocitySelectionRows(_ report: CheckReport, _ rows: [(String, Bool)]) {
    for (row, predicate) in rows {
        report.expect(predicate, cppID: "velocity/velocityselection.cpp", message: row)
    }
}

@MainActor
private func selectionTimelineVelocity(_ fixture: drawerVelocityLegacyFixture,
                                       _ id: NoteID) -> Int? {
    fixture.session.timeline.events.first { $0.noteID == id && $0.data1 > 0 }.map { Int($0.data1) }
}

@MainActor
private func velocityBandGeometry(_ fixture: drawerVelocityLegacyFixture)
    -> (start: (Double, Double), expanded: (Double, Double), contracted: (Double, Double),
        horizontal: Double, vertical: Double)? {
    guard fixture.notes.count == 3,
          let quiet = fixture.handle(fixture.notes[0]),
          let loud = fixture.handle(fixture.notes[1]),
          let later = fixture.handle(fixture.notes[2]) else { return nil }
    let horizontal = abs(later.x - quiet.x) / 4
    let vertical = abs(loud.y - quiet.y) / 4
    let start = (quiet.x - horizontal, min(quiet.y, loud.y) - vertical)
    let expanded = (later.x + horizontal, max(quiet.y, loud.y) + vertical)
    let contracted = ((quiet.x + later.x) / 2, expanded.1)
    return (start, expanded, contracted, horizontal, vertical)
}

@MainActor
func drawerVelocitySelectionGapPredicates(_ report: CheckReport,
                                          session: DocumentSession,
                                          service: ProjectService) {
    let track = drawerVelocityLegacyFixture(session: session, service: service)
    guard track.notes.count == 3, let trackHandle = track.handle(track.notes[0]) else {
        report.fail("velocity/velocityselection.cpp", "track-switch fixture admission failed")
        return
    }
    let trackNotes = track.notes
    let addedTrack = track.document.addTrack(voice: 2)
    track.page.refreshFromDocument()
    velocitySelectionRows(report, [
        ("A001", addedTrack == 1),
        ("A002", track.session.timeline.tracks.indices.contains(1)
            && track.session.timeline.tracks[1].firstProgram == 2),
    ])
    track.session.setSelectedNotes([trackNotes[0].id, trackNotes[2].id])
    track.page.refreshFromDocument()
    let trackBefore = drawerVelocityDocumentSnapshot(track.document)
    _ = track.page.pointerPress(x: trackHandle.x, y: trackHandle.y, surface: 1,
                                button: 1, modifiers: 0)
    _ = track.page.pointerMove(x: trackHandle.x, y: trackHandle.y - 28, buttons: 1)
    velocitySelectionRows(report, [
        ("A003", track.page.frozenPreview[trackNotes[0].id] != nil),
        ("A004", track.page.frozenPreview[trackNotes[2].id] != nil),
        ("A005", track.page.observation.gestureKind == .relative),
    ])
    track.session.selectedTrack = 1
    track.page.refreshFromDocument()
    velocitySelectionRows(report, [
        ("A006", track.document.revision == trackBefore.revision),
        ("A007", track.page.observation.gestureKind == nil),
        ("A008", track.page.frozenPreview[trackNotes[0].id] == nil),
        ("A009", track.page.frozenPreview[trackNotes[2].id] == nil),
        ("A010", track.page.axisModel.mode == .intrinsic),
        ("A011", track.page.axisModel.graduations.count == 5),
    ])
    _ = track.page.pointerRelease(x: trackHandle.x, y: trackHandle.y - 28, button: 1)
    velocitySelectionRows(report, [
        ("A012", track.document.revision == trackBefore.revision),
        ("A013", track.document.history.currentIdentity == trackBefore.identity),
        ("A014", track.document.note(trackNotes[0].id)?.velocity == 20),
        ("A015", track.document.note(trackNotes[1].id)?.velocity == 70),
        ("A016", track.document.note(trackNotes[2].id)?.velocity == 70),
        ("A017", track.page.frozenPreview[trackNotes[0].id] == nil),
        ("A018", track.page.frozenPreview[trackNotes[2].id] == nil),
    ])

    let ungrab = drawerVelocityLegacyFixture(session: session, service: service)
    guard ungrab.notes.count == 3, let loudHandle = ungrab.handle(ungrab.notes[1]) else {
        report.fail("velocity/velocityselection.cpp", "pointer-ungrab fixture admission failed")
        return
    }
    let ungrabNotes = ungrab.notes
    ungrab.session.setSelectedNotes([ungrabNotes[0].id])
    ungrab.page.refreshFromDocument()
    let ungrabBefore = drawerVelocityDocumentSnapshot(ungrab.document)
    velocitySelectionRows(report, [("A019", ungrab.session.selectedNotes == [ungrabNotes[0].id])])
    _ = ungrab.page.pointerPress(x: loudHandle.x, y: loudHandle.y, surface: 1,
                                 button: 1, modifiers: 0)
    velocitySelectionRows(report, [("A020", ungrab.session.selectedNotes == [ungrabNotes[1].id])])
    ungrab.page.cancelSectionInteraction()
    velocitySelectionRows(report, [
        ("A024", ungrab.session.selectedNotes == [ungrabNotes[0].id]),
        ("A025", ungrab.document.revision == ungrabBefore.revision),
        ("A026", ungrab.document.history.currentIdentity == ungrabBefore.identity),
        ("A027", ungrab.document.note(ungrabNotes[0].id)?.velocity == 20),
        ("A028", ungrab.document.note(ungrabNotes[1].id)?.velocity == 70),
        ("A029", ungrab.document.note(ungrabNotes[2].id)?.velocity == 70),
    ])
    _ = ungrab.page.pointerRelease(x: loudHandle.x, y: loudHandle.y, button: 1)
    velocitySelectionRows(report, [
        ("A030", ungrab.session.selectedNotes == [ungrabNotes[0].id]),
        ("A031", ungrab.document.revision == ungrabBefore.revision),
        ("A032", ungrab.document.history.currentIdentity == ungrabBefore.identity),
        ("A033", ungrab.document.note(ungrabNotes[0].id)?.velocity == 20),
        ("A034", ungrab.document.note(ungrabNotes[1].id)?.velocity == 70),
        ("A035", ungrab.document.note(ungrabNotes[2].id)?.velocity == 70),
    ])

    let band = drawerVelocityLegacyFixture(session: session, service: service)
    guard band.notes.count == 3, let bandGeometry = velocityBandGeometry(band) else {
        report.fail("velocity/velocityselection.cpp", "band fixture admission failed")
        return
    }
    let bandNotes = band.notes
    band.session.setSelectedNotes([bandNotes[2].id])
    band.page.refreshFromDocument()
    let bandBefore = drawerVelocityDocumentSnapshot(band.document)
    velocitySelectionRows(report, [
        ("A036", band.session.selectedNotes == [bandNotes[2].id]),
        ("A037", bandGeometry.horizontal > 0),
        ("A038", bandGeometry.vertical > 0),
        ("A039", bandGeometry.start.0 >= 0 && bandGeometry.start.0 <= band.page.plotWidth
            && bandGeometry.start.1 >= 0 && bandGeometry.start.1 <= band.page.plotHeight),
        ("A040", bandGeometry.expanded.0 >= 0 && bandGeometry.expanded.0 <= band.page.plotWidth
            && bandGeometry.expanded.1 >= 0 && bandGeometry.expanded.1 <= band.page.plotHeight),
        ("A041", bandGeometry.contracted.0 >= 0 && bandGeometry.contracted.0 <= band.page.plotWidth
            && bandGeometry.contracted.1 >= 0 && bandGeometry.contracted.1 <= band.page.plotHeight),
        ("A042", abs(bandGeometry.expanded.0 - bandGeometry.start.0)
            + abs(bandGeometry.expanded.1 - bandGeometry.start.1) >= 10),
    ])
    _ = band.page.pointerPress(x: bandGeometry.start.0, y: bandGeometry.start.1, surface: 1,
                               button: 2, modifiers: 0)
    _ = band.page.pointerMove(x: bandGeometry.expanded.0, y: bandGeometry.expanded.1, buttons: 2)
    _ = band.page.pointerMove(x: bandGeometry.contracted.0, y: bandGeometry.contracted.1,
                              buttons: 2)
    _ = band.page.pointerRelease(x: bandGeometry.contracted.0, y: bandGeometry.contracted.1,
                                 button: 2)
    velocitySelectionRows(report, [
        ("A044", band.session.selectedNotes == Set([bandNotes[0].id, bandNotes[1].id])),
        ("A045", band.document.revision == bandBefore.revision),
        ("A046", band.document.history.currentIdentity == bandBefore.identity),
        ("A047", band.document.note(bandNotes[0].id)?.velocity == 20),
        ("A048", band.document.note(bandNotes[1].id)?.velocity == 70),
        ("A049", band.document.note(bandNotes[2].id)?.velocity == 70),
        ("A050", selectionTimelineVelocity(band, bandNotes[0].id) == 20),
        ("A051", selectionTimelineVelocity(band, bandNotes[1].id) == 70),
        ("A052", selectionTimelineVelocity(band, bandNotes[2].id) == 70),
    ])

    let bandCancel = drawerVelocityLegacyFixture(session: session, service: service)
    guard bandCancel.notes.count == 3,
          let cancelGeometry = velocityBandGeometry(bandCancel) else {
        report.fail("velocity/velocityselection.cpp", "band-ungrab fixture admission failed")
        return
    }
    let bandCancelNotes = bandCancel.notes
    bandCancel.session.setSelectedNotes([bandCancelNotes[0].id])
    bandCancel.page.refreshFromDocument()
    let bandCancelBefore = drawerVelocityDocumentSnapshot(bandCancel.document)
    velocitySelectionRows(report, [
        ("A053", bandCancel.session.selectedNotes == [bandCancelNotes[0].id]),
        ("A054", cancelGeometry.horizontal > 0),
        ("A055", cancelGeometry.vertical > 0),
        ("A056", cancelGeometry.start.0 >= 0 && cancelGeometry.start.0 <= bandCancel.page.plotWidth
            && cancelGeometry.start.1 >= 0 && cancelGeometry.start.1 <= bandCancel.page.plotHeight),
        ("A057", cancelGeometry.expanded.0 >= 0
            && cancelGeometry.expanded.0 <= bandCancel.page.plotWidth
            && cancelGeometry.expanded.1 >= 0
            && cancelGeometry.expanded.1 <= bandCancel.page.plotHeight),
        ("A058", abs(cancelGeometry.expanded.0 - cancelGeometry.start.0)
            + abs(cancelGeometry.expanded.1 - cancelGeometry.start.1) >= 10),
    ])
    _ = bandCancel.page.pointerPress(x: cancelGeometry.start.0, y: cancelGeometry.start.1,
                                     surface: 1, button: 2, modifiers: 0)
    _ = bandCancel.page.pointerMove(x: cancelGeometry.expanded.0, y: cancelGeometry.expanded.1,
                                    buttons: 2)
    bandCancel.page.cancelSectionInteraction()
    velocitySelectionRows(report, [
        ("A062", bandCancel.session.selectedNotes == [bandCancelNotes[0].id]),
    ])
    _ = bandCancel.page.pointerMove(x: cancelGeometry.expanded.0, y: cancelGeometry.expanded.1,
                                    buttons: 2)
    _ = bandCancel.page.pointerRelease(x: cancelGeometry.expanded.0,
                                       y: cancelGeometry.expanded.1, button: 2)
    velocitySelectionRows(report, [
        ("A063", bandCancel.session.selectedNotes == [bandCancelNotes[0].id]),
        ("A064", bandCancel.document.revision == bandCancelBefore.revision),
        ("A065", bandCancel.document.history.currentIdentity == bandCancelBefore.identity),
        ("A066", bandCancel.document.note(bandCancelNotes[0].id)?.velocity == 20),
        ("A067", bandCancel.document.note(bandCancelNotes[1].id)?.velocity == 70),
        ("A068", bandCancel.document.note(bandCancelNotes[2].id)?.velocity == 70),
    ])
}
