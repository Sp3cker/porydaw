import Foundation
import PorydawCore
import QtBridge
import PorydawAppCommands

@MainActor
extension PianoGrid {
    private func gridDivisionText(_ selection: GridSelection) -> String {
        switch selection {
        case .auto: "Auto"
        case .musical(let denominator): "1/\(denominator)"
        case .clock: "Clock"
        }
    }

    func refreshGridMenuPresentation() {
        let selection = session.grid.selection
        gridSelectionMenuId = selection.toMenuId()
        gridDivisionControlText = gridDivisionText(selection)
        tripletGrid = session.grid.feel == .triplet
        gridFeelControlText = tripletGrid ? "Triplet" : "Straight"
        if gridMenuKind == 1 {
            gridMenuRows.reset(to: session.grid.selections.map { item in
                let text = gridDivisionText(item)
                return GridSubdivisionMenuItem(actionId: item.toMenuId(), text: text,
                                               checked: item == selection)
            })
        } else if gridMenuKind == 2 {
            gridMenuRows.reset(to: [
                GridSubdivisionMenuItem(actionId: 0, text: "Straight",
                                        checked: !tripletGrid),
                GridSubdivisionMenuItem(actionId: 1, text: "Triplet",
                                        checked: tripletGrid),
            ])
        }
    }

    @QtIgnored
    func applyPressSelection(_ id: NoteID, modifiers: Int) {
        if modifiers & QtFact.controlModifier != 0 {
            if !session.selectedNotes.contains(id) {
                addSelectedNoteFromLeftPointer(id)
            }
        } else if modifiers & QtFact.shiftModifier != 0 {
            addSelectedNoteFromLeftPointer(id)
        } else if !session.selectedNotes.contains(id) {
            session.setSelectedNotes([id])
        }
    }

    @QtIgnored
    func addSelectedNoteFromLeftPointer(_ id: NoteID) {
        session.addSelectedNote(id)
        if case .band = rightGesture, !rightBandDemoted,
           !selectionAtRightPress.contains(id) {
            selectionAtRightPress.append(id)
        }
    }

    @QtIgnored
    func removeSelectedNoteFromLeftPointer(_ id: NoteID) {
        session.removeSelectedNote(id)
        if case .band = rightGesture, !rightBandDemoted {
            selectionAtRightPress.removeAll { $0 == id }
        }
    }

    @QtIgnored
    func commitGesture() {
        guard let gesture else { return }
        let ids = session.selectedNoteOrder
        switch gesture {
        case .pendingDraw:
            break
        case .draw(let state):
            addNote(tick: state.tick, duration: state.duration, pitch: state.key)
        case .velocity(let state):
            if state.delta != 0 {
                var changes: [NoteVelocity] = []
                for id in session.selectedNoteOrder {
                    guard let current = session.document.note(id) else { continue }
                    changes.append(NoteVelocity(
                        noteID: id, velocity: Int(current.velocity) + state.delta))
                }
                if changes.isEmpty {
                    changes.append(NoteVelocity(
                        noteID: state.noteId, velocity: state.original + state.delta))
                }
                if session.document.setVelocities(
                    changes, expectedRevision: session.document.revision) != nil {
                    lastVelocity = min(127, max(1, state.original + state.delta))
                }
            }
        case .move(let state):
            if session.scaleProjection.fold && state.dKey != 0 {
                let selected = ids.compactMap { session.document.note($0) }
                if let pitches = session.scaleProjection.destinations(for: selected, steps: state.dKey) {
                    _ = session.document.moveNotes(
                        selected.map(\.id), toPitches: pitches, byTicks: Int64(state.dTick))
                }
            } else {
                session.document.moveNotes(ids, byTicks: Int64(state.dTick), byKeys: state.dKey)
            }
        case .resize(let state):
            session.document.resizeNotes(ids, edge: state.leading ? .leading : .trailing,
                                         byTicks: Int64(state.delta))
        case .pendingMenu, .band, .pan:
            break
        }
    }

    @QtIgnored
    private func addNote(tick: Int, duration: Int, pitch: Int) {
        guard session.selectedTrack != nil, tick >= 0, duration > 0,
              (0...127).contains(pitch), tick < Int(TimeDefaults.maxTick),
              Int64(tick) + Int64(duration) <= Int64(TimeDefaults.maxTick)
        else { return }
        guard let ids = try? session.document.addNotes([
            NewNote(track: trackIndex, tick: Tick(tick), pitch: UInt8(pitch),
                    duration: Tick(duration), velocity: UInt8(min(127, max(1, lastVelocity))))
        ]), let id = ids.first else { return }
        session.setSelectedNotes([id])
        activeNoteId = id.rawValue
    }

    @QtIgnored
    func applyBandSelection() {
        guard let band = selectionBand else { return }
        var covered: [NoteID] = []
        for note in notes where !note.ghost {
            let displayed = displayedNote(note)
            let rect = metrics.noteRect(
                camera: session.camera,
                x0: session.camera.displayX(tick: Double(displayed.tick), origin: 0, dpr: metrics.dpr),
                x1: session.camera.displayX(tick: Double(displayed.end), origin: 0, dpr: metrics.dpr),
                pitch: displayed.pitch)
            if rect.x < band.x + band.w, rect.x + rect.w > band.x,
               rect.y < band.y + band.h, rect.y + rect.h > band.y {
                covered.append(note.noteId)
            }
        }
        session.setSelectedNotes(selectionAtRightPress + covered)
    }

    @QtIgnored
    func auditionBandEntrants() {
        guard let band = selectionBand else { return }
        var covered: [NoteID: (track: Int, pitch: Int)] = [:]
        for note in notes where !note.ghost {
            guard let source = session.document.note(note.noteId), source.duration > 0 else {
                continue
            }
            let rect = metrics.noteRect(
                camera: session.camera,
                x0: session.camera.displayX(tick: Double(note.tick), origin: 0, dpr: metrics.dpr),
                x1: session.camera.displayX(
                    tick: Double(note.tick + note.duration), origin: 0, dpr: metrics.dpr),
                pitch: note.pitch)
            if rect.x < band.x + band.w, rect.x + rect.w > band.x,
               rect.y < band.y + band.h, rect.y + rect.h > band.y {
                covered[note.noteId] = (note.track, note.pitch)
                if bandAuditioned[note.noteId] == nil {
                    onAudition?(note.track, note.pitch, note.velocity)
                }
            }
        }
        for (id, entry) in bandAuditioned where covered[id] == nil {
            onAudition?(entry.track, entry.pitch, 0)
        }
        bandAuditioned = covered
    }

    @QtIgnored
    func releaseBandAudition() {
        for (_, entry) in bandAuditioned {
            onAudition?(entry.track, entry.pitch, 0)
        }
        bandAuditioned.removeAll()
    }
}
