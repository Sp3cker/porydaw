import Foundation
import PorydawCore
import QtBridge

// Canonical window commands for the drawer's shared time selection. Scope and
// content gathering use the same semantics as the native selection clipboard.
@MainActor
extension AutomationPage {
    @QtIgnored
    public func selectionCommandAvailable(command: EditCommand) -> Bool {
        guard let session else { return false }
        if command == .paste { return activeTrack() != nil && hasClipboard }
        guard let selection, selection.isActive else { return false }
        switch editCommandPolicy(command).rangeOperation {
        case .none: return false
        case .clearTimeSelection, .loopFromSelection: return true
        case .transpose:
            if case .lanes = selection.scope { return false }
            return resolvedSelectionScope() != nil
        default:
            return !session.document.rawChunks.isEmpty && resolvedSelectionScope() != nil
        }
    }

    /// A selection owns its command even when its mutation is unavailable or
    /// empty. Never let an owned range command fall through to selected notes.
    @QtIgnored
    @discardableResult
    public func consumeSelectionCommand(command: EditCommand) -> Bool {
        guard let session, !pointerGestureActive, !menuOpen, !promptOpen else { return false }
        if command == .paste {
            let cursor = selectionSnapPolicy()?.snap(Double(session.editCursor), fine: false,
                                                     camera: session.camera) ?? session.editCursor
            _ = pasteClipboard(at: cursor)
            return true
        }
        let policy = editCommandPolicy(command)
        guard let selection, selection.isActive, policy.rangeOperation != .none else { return false }
        guard selectionCommandAvailable(command: command) else { return true }
        session.withStateChanges {
            switch policy.rangeOperation {
            case .copySelection: _ = copyCapturedTimeSelection()
            case .cut: _ = cutCapturedTimeSelection()
            case .delete: _ = deleteCapturedSelection()
            case .clearTimeSelection: clearTimeSelection()
            case .loopFromSelection:
                // The original ruler contract deliberately records two undo entries.
                session.document.setLoop(end: false, tick: Int64(selection.range.startTick))
                session.document.setLoop(end: true, tick: Int64(selection.range.endTick))
            case .nudge: nudgeSelection(policy.nudgeDelta)
            case .transpose: transposeSelection(policy.transposeSemitones)
            case .duplicate, .insertTime, .removeContents:
                transformSelection(policy.rangeOperation)
            case .none: break
            }
        }
        return true
    }

    func resolvedSelectionScope() -> TimeScope? {
        guard let selection, selection.isActive, !selection.range.hasReservedEndpoint else { return nil }
        var scope = selectionScope(selection)
        let used = usedTracks()
        scope.tracks.formIntersection(used)
        scope.lanes = scope.lanes.filter { used.contains($0.track) }
        guard !scope.tracks.isEmpty || !scope.lanes.isEmpty || scope.tempo else { return nil }
        return scope
    }

    func selectionSnapPolicy() -> AutomationSnapPolicy? {
        guard let session else { return nil }
        return AutomationSnapPolicy(document: session.document, timeline: session.timeline,
                                    baseFontPx: baseFontPx, devicePixelRatio: devicePixelRatio)
    }

    func selectionSnapDuration() -> Tick {
        guard let session, let snap = selectionSnapPolicy() else { return 1 }
        let tick = session.editCursor
        return max(1, snap.next(after: tick, fine: false, limit: TimeDefaults.maxTick,
                                camera: session.camera) - tick)
    }

    /// One native read, one atomic semantic paste, and one final state publication.
    func pasteClipboard(at cursor: Tick) -> Tick? {
        guard let session, let track = activeTrack(), let decoded = clipboard.read() else { return nil }
        let clip = ClipboardCodec.rescale(decoded.clip, sourceTicksPerBeat: decoded.ticksPerBeat,
                                          destinationTicksPerBeat: UInt32(session.document.ticksPerBeat))
        let destination = cursor
        guard let anticipated = ClipboardSemantics.pasteCursor(for: clip, at: destination) else { return nil }
        return session.withStateChanges {
            let priorCursor = session.editCursor
            session.editCursor = anticipated
            guard let result = ClipboardSemantics.paste(clip, at: destination, selectedTrack: track,
                                                        into: session.document) else {
                session.editCursor = priorCursor
                return nil
            }
            session.editCursor = result.nextCursor
            if clip.span == 0 { session.setSelectedNotes(result.insertedNoteIDs) }
            else { clearTimeSelection() }
            refreshFromDocument()
            _ = session.mutateCamera { _ = $0.ensureTickVisible(UInt64(destination), dpr: devicePixelRatio) }
            return result.nextCursor
        }
    }

    private func transformSelection(_ operation: EditRangeOperation) {
        guard let session, var selection, let scope = resolvedSelectionScope() else { return }
        let range = selection.range
        let changed: Bool
        switch operation {
        case .duplicate:
            changed = session.document.duplicateTime(range, scope: scope)
            if changed {
                selection.range = TimeRange(startTick: range.endTick,
                                            endTick: range.endTick + range.span)
                applyTimeSelection(selection)
                session.editCursor = selection.range.endTick
                revealSelectionRange(start: selection.range.startTick, end: selection.range.endTick)
            }
        case .insertTime:
            changed = session.document.insertBlankTime(range, scope: scope)
            if changed { session.editCursor = range.startTick }
        case .removeContents:
            changed = session.document.removeTime(range, scope: scope)
            if changed {
                clearTimeSelection()
                session.editCursor = range.startTick
            }
        default: return
        }
        if changed { refreshFromDocument() }
    }

    private func nudgeSelection(_ direction: Int) {
        guard let session, var selection, let scope = resolvedSelectionScope(),
              let snap = selectionSnapPolicy() else { return }
        let start = selection.range.startTick
        let destination = direction > 0
            ? snap.next(after: start, fine: false, limit: TimeDefaults.maxTick, camera: session.camera)
            : snap.snapDown(Double(start) - 1, fine: false, camera: session.camera)
        let delta = Int64(destination) - Int64(start)
        let end = Int64(selection.range.endTick) + delta
        guard delta != 0, end <= Int64(TimeDefaults.maxTick) else { return }
        let contents = ClipboardSemantics.gather(selection.range, scope: scope, from: session.document)
        let notes = contents.tracks.flatMap(\.notes)
        let points = contents.lanes.flatMap(\.points)
        let hasContent = !notes.isEmpty || !points.isEmpty || !contents.tempo.isEmpty
        let changed = session.document.moveRange(notes: notes, points: points, by: delta,
                                                  tempo: contents.tempo)
        guard changed || !hasContent else { return }
        selection.range = TimeRange(startTick: destination, endTick: Tick(end))
        applyTimeSelection(selection)
        if changed { refreshFromDocument() }
        revealSelectionRange(start: destination, end: Tick(end), preferEnd: direction > 0)
    }

    private func transposeSelection(_ semitones: Int) {
        guard let session, let selection, let scope = resolvedSelectionScope() else { return }
        let notes = ClipboardSemantics.gather(selection.range, scope: scope,
                                              from: session.document).tracks.flatMap(\.notes)
        guard !notes.isEmpty, notes.allSatisfy({ (0...127).contains(Int($0.pitch) + semitones) }) else { return }
        let before = session.document.revision
        session.document.nudgeNotes(notes.map(\.id), byTicks: 0, byKeys: semitones)
        if session.document.revision != before {
            let edge = notes.reduce(Int(notes[0].pitch)) {
                semitones > 0 ? max($0, Int($1.pitch)) : min($0, Int($1.pitch))
            }
            _ = session.mutateCamera { _ = $0.ensureKeyVisible(edge + semitones) }
            refreshFromDocument()
        }
    }

    private func revealSelectionRange(start: Tick, end: Tick, preferEnd: Bool = true) {
        guard let session else { return }
        _ = session.mutateCamera {
            _ = $0.ensureRangeVisible(startTick: UInt64(start), endTick: UInt64(end),
                                     preferEnd: preferEnd, dpr: devicePixelRatio)
        }
    }
}
