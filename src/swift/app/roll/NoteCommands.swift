import Foundation
import PorydawCore

@MainActor
final class NoteCommands {
    private let session: DocumentSession
    private let clipboard = GridClipboard()

    /// The Set Velocity command's dispatch: the document-bound page owns the
    /// prompt transaction, so this row asks for it instead of committing a value.
    /// `true` means the request was accepted; the document is untouched either
    /// way until the prompt's own acceptance runs.
    var requestSetVelocity: (() -> Bool)?

    init(session: DocumentSession) {
        self.session = session
    }

    func isAvailable(_ command: EditCommand) -> Bool {
        switch command {
        case .copy, .cut, .duplicate, .delete, .transposeUp, .transposeDown,
             .transposeUpOctave, .transposeDownOctave, .nudgeLeft, .nudgeRight,
             .split, .join, .lengthenNote, .shortenNote, .setVelocity:
            return !selectedNotes().isEmpty
        case .paste, .selectAll, .muteTracks, .soloTracks,
             .pencilMode, .gridNarrow, .gridWiden, .gridTriplet:
            return selectedTrack != nil
        default:
            return false
        }
    }

    @discardableResult
    func execute(_ command: EditCommand, snapTicks: Tick, editCursor: Tick,
                 nextSubdivision: (Tick) -> Tick) -> Bool {
        // Set Velocity is a prompt transaction, not a value commit: the row's
        // dispatch asks the document-bound page to open its captured prompt and
        // never touches the document here.
        if command == .setVelocity {
            return requestSetVelocity?() ?? false
        }
        let before = session.document.revision
        switch command {
        case .copy:
            _ = copySelection(snapTicks: snapTicks)
        case .cut:
            if copySelection(snapTicks: snapTicks) { deleteSelection() }
        case .duplicate:
            duplicateSelection(snapTicks: snapTicks)
        case .paste:
            paste(at: editCursor)
        case .selectAll:
            selectAll()
        case .delete:
            deleteSelection()
        case .transposeUp:
            transpose(1)
        case .transposeDown:
            transpose(-1)
        case .transposeUpOctave:
            transpose(12)
        case .transposeDownOctave:
            transpose(-12)
        case .nudgeLeft:
            nudge(-1, snapTicks: snapTicks)
        case .nudgeRight:
            nudge(1, snapTicks: snapTicks)
        case .muteTracks:
            toggleMute()
        case .soloTracks:
            toggleSolo()
        case .split:
            split(editCursor: editCursor, nextSubdivision: nextSubdivision)
        case .join:
            join()
        case .lengthenNote:
            resizeTrailing(Int64(max(1, snapTicks)))
        case .shortenNote:
            resizeTrailing(-Int64(max(1, snapTicks)))
        default:
            return false
        }
        return session.document.revision != before || command == .copy
            || command == .selectAll || command == .muteTracks || command == .soloTracks
    }

    private var selectedTrack: Int? {
        guard let track = session.selectedTrack,
              track >= 0, track < session.document.engineTracks.usedTrackCount
        else { return nil }
        return track
    }

    private func selectedNotes() -> [Note] {
        guard let track = selectedTrack else { return [] }
        return session.selectedNotes.compactMap { session.document.note($0) }
            .filter { $0.track == track }
            .sorted { $0.id.rawValue < $1.id.rawValue }
    }

    private func copySelection(snapTicks: Tick) -> Bool {
        guard let track = selectedTrack,
              let clip = ClipboardSemantics.copyNotes(
                  selectedNotes(), from: track, unterminatedDuration: snapTicks)
        else { return false }
        return clipboard.write(clip, ticksPerBeat: UInt32(session.document.ticksPerBeat))
    }

    private func deleteSelection() {
        let ids = selectedNotes().map(\.id)
        guard !ids.isEmpty else { return }
        session.document.deleteNotes(ids)
        session.selectedNotes.subtract(ids)
    }

    private func duplicateSelection(snapTicks: Tick) {
        guard let track = selectedTrack else { return }
        let notes = selectedNotes()
        guard let start = notes.map(\.tick).min() else { return }
        let end = notes.reduce(UInt64(start)) { value, note in
            max(value, UInt64(note.tick) + UInt64(note.isUnterminated ? max(1, snapTicks)
                                                                    : max(1, note.duration)))
        }
        let span = max(UInt64(1), end - UInt64(start))
        var additions: [NewNote] = []
        additions.reserveCapacity(notes.count)
        for note in notes {
            let destination = UInt64(note.tick) + span
            guard destination < UInt64(TimeDefaults.maxTick) else { continue }
            additions.append(NewNote(track: track, tick: Tick(destination), pitch: note.pitch,
                                     duration: note.isUnterminated ? max(1, snapTicks)
                                                                   : max(1, note.duration),
                                     velocity: note.velocity))
        }
        guard !additions.isEmpty, let inserted = try? session.document.addNotes(additions),
              !inserted.isEmpty else { return }
        session.selectedNotes = Set(inserted)
    }

    private func paste(at editCursor: Tick) {
        guard let track = selectedTrack, let decoded = clipboard.read() else { return }
        let clip = ClipboardCodec.rescale(decoded.clip, sourceTicksPerBeat: decoded.ticksPerBeat,
                                          destinationTicksPerBeat:
                                              UInt32(session.document.ticksPerBeat))
        guard let anticipatedCursor = ClipboardSemantics.pasteCursor(for: clip, at: editCursor)
        else { return }

        // Publish the destination before the document callback refreshes the grid.
        // Restore it if the atomic paste rejects or has no useful content.
        let priorCursor = session.editCursor
        session.editCursor = anticipatedCursor
        guard let result = ClipboardSemantics.paste(
            clip, at: editCursor, selectedTrack: track, into: session.document)
        else {
            session.editCursor = priorCursor
            return
        }
        session.editCursor = result.nextCursor
        if clip.span == 0 {
            session.selectedNotes = Set(result.insertedNoteIDs)
        }
    }

    private func selectAll() {
        guard let track = selectedTrack else { return }
        session.selectedNotes = Set(session.document.notes(in: track).map(\.id))
    }

    private func transpose(_ semitones: Int) {
        let notes = selectedNotes()
        guard !notes.isEmpty,
              notes.allSatisfy({ (0...127).contains(Int($0.pitch) + semitones) })
        else { return }
        session.document.moveNotes(notes.map(\.id), byTicks: 0, byKeys: semitones)
    }

    private func nudge(_ direction: Int, snapTicks: Tick) {
        let notes = selectedNotes()
        guard let anchor = notes.map(\.tick).min() else { return }
        let step = max(1, snapTicks)
        let destination: Tick
        if direction < 0 {
            destination = anchor == 0 ? 0 : ((anchor - 1) / step) * step
        } else {
            let remainder = anchor % step
            let delta = remainder == 0 ? step : step - remainder
            destination = TimeDefaults.shiftTickClamped(anchor, by: Int64(delta))
        }
        let delta = Int64(destination) - Int64(anchor)
        guard delta != 0 else { return }
        session.document.moveNotes(notes.map(\.id), byTicks: delta, byKeys: 0)
    }

    private func resizeTrailing(_ delta: Int64) {
        let notes = selectedNotes()
        guard !notes.isEmpty else { return }
        session.document.resizeNotes(notes.map(\.id), edge: .trailing, byTicks: delta)
    }

    private func toggleMute() {
        guard let track = selectedTrack else { return }
        if session.mutedTracks.contains(track) {
            session.mutedTracks.remove(track)
        } else {
            session.mutedTracks.insert(track)
        }
    }

    private func toggleSolo() {
        guard let track = selectedTrack else { return }
        if session.soloedTracks.contains(track) {
            session.soloedTracks.remove(track)
        } else {
            session.soloedTracks.insert(track)
        }
    }

    private func split(editCursor: Tick, nextSubdivision: (Tick) -> Tick) {
        guard let track = selectedTrack else { return }
        let selected = selectedNotes()
        let selectedIDs = Set(selected.map(\.id))
        var removals: [Note] = []
        var additions: [NewNote] = []
        var selectedPositions = Set<FragmentPosition>()

        for note in selected where !note.isUnterminated {
            let end = UInt64(note.tick) + UInt64(note.duration)
            var boundary = nextSubdivision(note.tick)
            guard boundary > note.tick, UInt64(boundary) < end else { continue }
            removals.append(note)
            var partTick = note.tick
            while boundary > partTick, UInt64(boundary) < end {
                additions.append(NewNote(track: track, tick: partTick, pitch: note.pitch,
                                         duration: boundary - partTick, velocity: note.velocity))
                selectedPositions.insert(FragmentPosition(tick: partTick, pitch: note.pitch))
                partTick = boundary
                boundary = nextSubdivision(partTick)
            }
            additions.append(NewNote(track: track, tick: partTick, pitch: note.pitch,
                                     duration: Tick(end - UInt64(partTick)), velocity: note.velocity))
            selectedPositions.insert(FragmentPosition(tick: partTick, pitch: note.pitch))
        }
        for note in session.document.notes(in: track)
        where !note.isUnterminated && !selectedIDs.contains(note.id)
            && editCursor > note.tick && UInt64(editCursor) < UInt64(note.tick) + UInt64(note.duration) {
            removals.append(note)
            additions.append(NewNote(track: track, tick: note.tick, pitch: note.pitch,
                                     duration: editCursor - note.tick, velocity: note.velocity))
            additions.append(NewNote(track: track, tick: editCursor, pitch: note.pitch,
                                     duration: note.duration - (editCursor - note.tick),
                                     velocity: note.velocity))
        }
        guard !removals.isEmpty else { return }
        let oldIDs = Set(session.document.notes(in: track).map(\.id))
        guard session.document.applyRangeEdit(RangeEdit(removeNotes: removals,
                                                        addNotes: additions)) else { return }
        let removedIDs = Set(removals.map(\.id))
        session.selectedNotes.subtract(removedIDs)
        for note in session.document.notes(in: track)
        where !oldIDs.contains(note.id)
            && selectedPositions.contains(FragmentPosition(tick: note.tick, pitch: note.pitch)) {
            session.selectedNotes.insert(note.id)
        }
    }

    private func join() {
        guard let track = selectedTrack else { return }
        let groups = Dictionary(grouping: selectedNotes(), by: \.pitch)
        var removals: [Note] = []
        var additions: [NewNote] = []
        for (pitch, group) in groups where group.count > 1 && group.allSatisfy({ !$0.isUnterminated }) {
            let sorted = group.sorted { $0.tick < $1.tick }
            guard let first = sorted.first else { continue }
            let end = sorted.reduce(UInt64(first.tick)) {
                max($0, UInt64($1.tick) + UInt64($1.duration))
            }
            removals.append(contentsOf: sorted)
            additions.append(NewNote(track: track, tick: first.tick, pitch: pitch,
                                     duration: Tick(min(UInt64(UInt32.max), end - UInt64(first.tick))),
                                     velocity: first.velocity))
        }
        guard !additions.isEmpty else { return }
        let oldIDs = Set(session.document.notes(in: track).map(\.id))
        guard session.document.applyRangeEdit(RangeEdit(removeNotes: removals,
                                                        addNotes: additions)) else { return }
        session.selectedNotes.subtract(removals.map(\.id))
        session.selectedNotes.formUnion(session.document.notes(in: track).compactMap {
            oldIDs.contains($0.id) ? nil : $0.id
        })
    }
}

private struct FragmentPosition: Hashable {
    var tick: Tick
    var pitch: UInt8
}
