import Foundation
@testable import PorydawApp
import PorydawCore
import QtBridge

@MainActor
func checkGhostNotes(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::ghostNoteRaster"
    let document = session.document
    let initialState = document.state
    let initialIdentity = document.history.currentIdentity
    let oldCamera = session.camera
    let priorSelection = session.selectedNoteOrder
    let priorTrack = session.selectedTrack
    defer {
        session.clearSelectedNotes()
        if let priorTrack, session.selectedTrack != priorTrack {
            session.selectPrimaryTrack(priorTrack)
        }
        while document.history.currentIdentity != initialIdentity && document.history.canUndo {
            guard document.history.undoDocument() else { break }
        }
        session.selectedTrack = priorTrack
        session.setSelectedNotes(priorSelection)
        session.mutateCamera { $0 = oldCamera }
        report.expect(document.state == initialState
                          && document.history.currentIdentity == initialIdentity,
                      cppID: id, message: "undo restores the ghost fixture and its track")
    }
    let grid = PianoGrid(session: session)
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    grid.resetCameraScroll()
    _ = session.mutateCamera { _ = $0.setTimeZoom(35) }
    grid.refreshCamera()
    let primary = grid.trackIndex
    guard document.canAddTrack, let other = document.addTrack(voice: 0),
          other != primary else {
        report.fail(id, "ghost fixture cannot provision a second engine track")
        return
    }
    report.expect(document.engineTracks.usedTrackCount > other && other != primary,
                  cppID: id, message: "A016 a distinct other track exists for the ghost seed")
    grid.refreshFromSession()
    guard let ghost = ghostSeed(report, id: id, session: session, grid: grid,
                                track: other, spanCells: 8) else { return }
    guard let plain = ghostSeed(report, id: id, session: session, grid: grid,
                                track: primary, spanCells: 1, nearPitch: ghost.pitch,
                                nearTick: ghost.tick, excluding: [ghost.pitch]) else { return }
    func projected(_ noteID: NoteID) -> GridNote? {
        grid.notes.first { $0.noteId == noteID }
    }
    func ghostFill(named name: String) -> String? {
        firstNoteRect(named: name, in: grid.scene.pianoNoteFills)?.fillColor
    }
    report.expect(projected(plain.id)?.ghost == false && projected(ghost.id)?.ghost == true,
                  cppID: id, message: "A016 both fixture notes project, other-track note as ghost")
    guard let ghostNote = document.note(ghost.id),
          let plainNote = document.note(plain.id),
          let ghostBox = noteBox(grid, session: session, note: ghostNote),
          let plainBox = noteBox(grid, session: session, note: plainNote) else {
        report.fail(id, "ghost fixture has no projected scene box")
        return
    }
    let expectedGhost = PaletteMath.ghostFill(
        track: other, accidentalRow: GridScene.isBlackKey(ghost.pitch),
        rollBackground: grid.palette.rollBackground, accidentalLane: grid.palette.accidentalLane)
    report.expect(ghostFill(named: "gridNote_\(ghost.id.rawValue)") == expectedGhost,
                  cppID: id, message: "A017 ghost face uses the track-identity mix")
    ShellAppearance.apply(to: grid.palette, mode: "immaterial", contrast: 50)
    grid.refreshFromSession()
    let themedBackdrop = GridScene.isBlackKey(ghost.pitch)
        ? grid.palette.accidentalLane : grid.palette.rollBackground
    let backdropChannels = PaletteMath.channels(themedBackdrop)
    let backdrop = PaletteMath.oklab(r: backdropChannels.r, g: backdropChannels.g,
                                     b: backdropChannels.b)
    let identity = PaletteMath.trackIdentityOklab(other)
    let weight = 60.0 / 255.0
    let lightness = backdrop.lightness
        + min(0.055, max(-0.055, (identity.lightness - backdrop.lightness) * weight))
    let immaterialGhost = PaletteMath.hex(PaletteMath.Oklab(
        lightness: lightness, a: backdrop.a + (identity.a - backdrop.a) * weight,
        b: backdrop.b + (identity.b - backdrop.b) * weight))
    report.expect(ghostFill(named: "gridNote_\(ghost.id.rawValue)") == immaterialGhost,
                  cppID: id, message: "A017 immaterial ghost face mixes into its themed roll lane")
    ShellAppearance.apply(to: grid.palette, mode: "vanilla", contrast: 50)
    grid.refreshFromSession()
    let ring = 3.0 / grid.devicePixelRatio
    let border = 2.0 / grid.devicePixelRatio
    session.setSelectedNotes([plain.id])
    grid.refreshCamera()
    report.expect(hasFrame(grid.scene.pianoNoteBordersAndSelection, box: plainBox, inset: 0,
                           thickness: ring, color: grid.palette.selectionRing),
                  cppID: id, message: "the plain note rings while the ghost face stays flat")
    report.expect(!hasFrame(grid.scene.pianoNoteBordersAndSelection, box: ghostBox, inset: 0,
                            thickness: border, color: grid.palette.noteBorder)
                      && !hasFrame(grid.scene.pianoNoteBordersAndSelection, box: ghostBox, inset: 0,
                                   thickness: ring, color: grid.palette.selectionRing),
                  cppID: id, message: "A017 ghost face edge matches its interior: no border or ring")
    session.setSelectedNotes([ghost.id])
    grid.refreshCamera()
    report.expect(!hasFrame(grid.scene.pianoNoteBordersAndSelection, box: ghostBox, inset: 0,
                            thickness: ring, color: grid.palette.selectionRing),
                  cppID: id, message: "selecting a ghost publishes no selection ring")
    session.clearSelectedNotes()
    grid.refreshCamera()
    grid.setTrack(index: other)
    report.expect(grid.trackIndex == other
                      && projected(plain.id)?.ghost == true
                      && projected(ghost.id)?.ghost == false,
                  cppID: id, message: "selecting the other track swaps plain and ghost roles")
    report.expect(ghostFill(named: "gridNote_\(plain.id.rawValue)")
                      == PaletteMath.ghostFill(
                          track: primary, accidentalRow: GridScene.isBlackKey(plain.pitch),
                          rollBackground: grid.palette.rollBackground,
                          accidentalLane: grid.palette.accidentalLane)
                      && ghostFill(named: "gridNote_\(ghost.id.rawValue)")
                      == grid.palette.noteFill(track: other, velocity: 100),
                  cppID: id, message: "swapped faces follow their new roles")
    grid.setTrack(index: primary)
    grid.setVelocityColorMode(enabled: true)
    let ghostVelocityFill = ghostFill(named: "gridNote_\(ghost.id.rawValue)")
    grid.setVelocityColorMode(enabled: false)
    report.expect(ghostVelocityFill == expectedGhost
                      && ghostFill(named: "gridNote_\(ghost.id.rawValue)") == expectedGhost,
                  cppID: id, message: "A031 velocity-color mode leaves the ghost fill byte-identical")
    let ghostOrigin = viewportPoint(grid, x: ghostBox.x, y: ghostBox.y)
    let pressX = ghostOrigin.x + ghostBox.w / 2
    let pressY = ghostOrigin.y + ghostBox.h / 2
    let revision = session.document.revision
    grid.beginPointer(x: pressX, y: pressY, modifiers: 0)
    report.expect(!session.selectedNotes.contains(ghost.id)
                      && session.document.revision == revision,
                  cppID: id, message: "pressing a ghost selects and edits nothing")
    grid.inputCancelled(reason: GridCancelReason.hidden.rawValue)
    report.expect(!session.selectedNotes.contains(ghost.id) && !grid.interactionActive
                      && session.document.revision == revision,
                  cppID: id, message: "cancelling a ghost press leaves no gesture or edit")
    grid.beginRightPointer(x: ghostOrigin.x - 4, y: ghostOrigin.y - 4)
    grid.updateRightPointer(x: ghostOrigin.x + ghostBox.w + 4,
                            y: ghostOrigin.y + ghostBox.h + 4)
    grid.endRightPointer(x: ghostOrigin.x + ghostBox.w + 4,
                         y: ghostOrigin.y + ghostBox.h + 4)
    report.expect(!session.selectedNotes.contains(ghost.id),
                  cppID: id, message: "a band over a ghost never selects it")
    session.clearSelectedNotes()
    let stateBefore = session.document.state
    grid.doublePointer(x: pressX, y: pressY)
    report.expect(session.document.note(ghost.id) != nil
                      && session.document.state == stateBefore,
                  cppID: id, message: "double-tapping a ghost deletes nothing")
    session.mutateCamera { camera in
        _ = camera.setKeyHeight(32)
        _ = camera.setVScroll(max(0, (127.5 - Double(plain.pitch)) * 32 - 160))
    }
    grid.refreshCamera()
    _ = session.mutateCamera { _ = $0.setTimeZoom(280) }
    grid.refreshCamera()
    _ = session.mutateCamera { camera in
        _ = camera.setHScroll(max(camera.snapshot.minHScroll,
                                  camera.contentX(tick: Double(min(ghost.tick, plain.tick))) - 160))
    }
    grid.refreshCamera()
    grid.setNoteNameMode(enabled: true)
    let labels = grid.scene.pianoNoteTextModel.asArray
    report.expect(labels.contains { $0.labelText == GridScene.keyName(plain.pitch) },
                  cppID: id, message: "the wide selected-track note keeps its name label")
    report.expect(!labels.contains { $0.labelText == GridScene.keyName(ghost.pitch) },
                  cppID: id, message: "A036 ghost notes are never labeled")
    grid.setNoteNameMode(enabled: false)
}
