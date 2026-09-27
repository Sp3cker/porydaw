import Foundation
import PorydawCore
import PorydawProject

@MainActor
extension DocumentSession {

    public func setSelectedNotes(_ ids: [NoteID]) {
        var membership = Set<NoteID>()
        let order = ids.filter { $0.isAssigned && membership.insert($0).inserted }
        guard order != selectedNoteOrder || (!order.isEmpty && timeSelection?.isActive == true) else { return }
        withStateChanges {
            if !order.isEmpty { clearTimeSelection() }
            guard order != selectedNoteOrder else { return }
            selectedNoteOrder = order
            selectedNotes = membership
            publishChange([.selection])
        }
    }

    public func applyTimeSelection(_ selection: AutomationTimeSelection?) {
        var sanitized = selection?.isActive == true ? selection : nil
        var nextScope: Set<Int>?
        if var active = sanitized {
            switch active.scope {
            case .lanes:
                active.lanes = Set(active.lanes.filter {
                    guard let track = $0.track else { return false }
                    return (0..<16).contains(track)
                })
                sanitized = active.lanes.isEmpty && !active.tempo ? nil : active
            case let .tracks(scope):
                let stored = Set(scope.filter { (0..<16).contains($0) })
                    .union(selectedTrack.map { [$0] } ?? [])
                nextScope = Set(stored.filter { (0..<document.engineTracks.usedTrackCount).contains($0) })
                active.scope = .tracks(stored)
                sanitized = active
            }
        }
        guard timeSelection != sanitized || nextScope.map({ selectedTracks != $0 }) == true else { return }
        withStateChanges {
            if let nextScope, selectedTracks != nextScope {
                selectedTracks = nextScope
                publishChange([.selection])
            }
            timeSelection = sanitized
            if sanitized != nil { clearSelectedNotes() }
            publishChange([.selection])
        }
    }

    public func clearTimeSelection() { applyTimeSelection(nil) }

    public func timeSelectionCoversTrack(_ track: Int) -> Bool {
        guard (0..<document.engineTracks.usedTrackCount).contains(track),
              let selection = timeSelection, selection.isActive,
              case let .tracks(scope) = selection.scope else { return false }
        return scope.contains(track)
    }

    public func timeSelectionCoversTempo() -> Bool {
        let usedTracks = Set(0..<document.engineTracks.usedTrackCount)
        guard let selection = timeSelection, selection.isActive else { return false }
        if case let .tracks(scope) = selection.scope {
            return !usedTracks.isEmpty && scope.intersection(usedTracks) == usedTracks
        }
        return selection.tempo
    }

    internal var trackTimeSelection: TrackTimeSelection {
        guard let selection = timeSelection, selection.isActive,
              case .tracks = selection.scope else { return TrackTimeSelection() }
        return TrackTimeSelection(startTick: selection.range.startTick,
                                  endTick: selection.range.endTick, trackScope: selectedTracks)
    }

    public func selectPrimaryTrack(_ track: Int) {
        guard (0..<document.engineTracks.usedTrackCount).contains(track),
              selectedTrack != track else { return }
        adjustTrackScope(track: track, action: .plain)
    }

    public func adjustTrackScope(track: Int, action: TrackScopeAction) {
        guard (0..<document.engineTracks.usedTrackCount).contains(track) else { return }
        var primary = selectedTrack ?? track
        var scope = selectedTracks
        var clearNotes = false
        var clearTime = false
        switch action {
        case .plain:
            clearTime = primary != track
            primary = track
            scope = [track]
            clearNotes = true
        case .toggle:
            if scope.contains(track) { scope.remove(track) }
            else { scope.insert(track) }
            guard !scope.isEmpty else { return }
            if !scope.contains(primary) {
                primary = scope.min()!
                clearNotes = true
            }
        case .range:
            scope = Set(min(primary, track)...max(primary, track))
        }
        withStateChanges {
            changingPrimaryInternally = true
            selectedTrack = primary
            changingPrimaryInternally = false
            if selectedTracks != scope {
                selectedTracks = scope
                publishChange([.selection])
            }
            if var selection = timeSelection, case .tracks = selection.scope,
               selection.scope != .tracks(scope) {
                selection.scope = .tracks(scope)
                timeSelection = selection
                publishChange([.selection])
            }
            if clearNotes { clearSelectedNotes() }
            if clearTime { clearTimeSelection() }
        }
    }

    public func addSelectedNote(_ id: NoteID) {
        guard id.isAssigned, !selectedNotes.contains(id) else { return }
        withStateChanges {
            clearTimeSelection()
            selectedNoteOrder.append(id)
            selectedNotes.insert(id)
            publishChange([.selection])
        }
    }

    public func removeSelectedNote(_ id: NoteID) {
        guard selectedNotes.contains(id) else { return }
        selectedNoteOrder.removeAll { $0 == id }
        selectedNotes.remove(id)
        publishChange([.selection])
    }

    public func removeSelectedNotes(_ ids: Set<NoteID>) {
        guard !selectedNotes.isDisjoint(with: ids) else { return }
        selectedNoteOrder.removeAll { ids.contains($0) }
        selectedNotes.subtract(ids)
        publishChange([.selection])
    }

    public func clearSelectedNotes() {
        guard !selectedNoteOrder.isEmpty else { return }
        selectedNoteOrder.removeAll()
        selectedNotes.removeAll()
        publishChange([.selection])
    }
}
