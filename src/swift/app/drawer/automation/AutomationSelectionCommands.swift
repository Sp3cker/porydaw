import Foundation
import PorydawCore
import QtBridge

/// The page samples the native clipboard and snapping policy once before dispatch.
/// Neither value can be read by the pure command planner.
struct AutomationSelectionRequest: Sendable {
    let command: EditCommand
    let clipboardAvailable: Bool
    let snappedPasteCursor: Tick
}

enum AutomationSelectionEffect: Sendable {
    case paste(at: Tick)
    case range(policy: EditCommandPolicy, selection: AutomationTimeSelection, scope: TimeScope?)
}

enum AutomationSelectionCommands {
    static func resolvedScope(_ selection: AutomationTimeSelection,
                              usedTracks: Set<Int>) -> TimeScope? {
        guard selection.isActive, !selection.range.hasReservedEndpoint else { return nil }
        var scope: TimeScope
        switch selection.scope {
        case .lanes:
            let lanes = selection.lanes.reduce(into: Set<TimeScope.ScopedLane>()) { result, item in
                guard let track = item.track, let lane = item.lane else { return }
                result.insert(TimeScope.ScopedLane(track: track, lane: lane))
            }
            scope = TimeScope(tracks: [], lanes: lanes, tempo: selection.tempo)
        case let .tracks(tracks):
            scope = TimeScope(tracks: tracks, lanes: [],
                              tempo: selection.coversTempo(usedTracks: usedTracks))
        }
        scope.tracks.formIntersection(usedTracks)
        scope.lanes = scope.lanes.filter { usedTracks.contains($0.track) }
        return scope.tracks.isEmpty && scope.lanes.isEmpty && !scope.tempo ? nil : scope
    }

    static func available(_ state: AutomationState, command: EditCommand,
                          clipboardAvailable: Bool) -> Bool {
        guard state.document.attached else { return false }
        if command == .paste { return state.activeTrack != nil && clipboardAvailable }
        guard let selection = state.selection, selection.isActive else { return false }
        let scope = resolvedScope(selection, usedTracks: state.document.usedTracks)
        switch editCommandPolicy(command).rangeOperation {
        case .none: return false
        case .clearTimeSelection, .loopFromSelection: return true
        case .transpose:
            if case .lanes = selection.scope { return false }
            return scope != nil
        default:
            return state.document.hasRawChunks && scope != nil
        }
    }

    static func reduce(_ state: inout AutomationState,
                       request: AutomationSelectionRequest) -> AutomationTransition {
        guard state.document.attached, !state.pointerGestureActive, !state.modal.isOpen else {
            return AutomationTransition()
        }
        if request.command == .paste {
            return AutomationTransition(
                effects: [.selection(.paste(at: request.snappedPasteCursor))],
                outcome: AutomationOutcome(consumed: true))
        }
        let policy = editCommandPolicy(request.command)
        guard let selection = state.selection, selection.isActive,
              policy.rangeOperation != .none else { return AutomationTransition() }
        guard available(state, command: request.command,
                        clipboardAvailable: request.clipboardAvailable) else {
            return AutomationTransition(outcome: AutomationOutcome(consumed: true))
        }
        let scope = resolvedScope(selection, usedTracks: state.document.usedTracks)
        if policy.rangeOperation == .clearTimeSelection {
            state.selection = nil
            return AutomationTransition(publication: .content,
                                        outcome: AutomationOutcome(consumed: true),
                                        selectionBuild: true,
                                        commandAvailabilityChanged: true)
        }
        return AutomationTransition(
            effects: [.selection(.range(policy: policy, selection: selection, scope: scope))],
            outcome: AutomationOutcome(consumed: true))
    }
}

// Canonical window commands for the drawer's shared time selection. Scope and
// content gathering use the same semantics as the native selection clipboard.
@MainActor
extension AutomationPage {
    @QtIgnored
    public func selectionCommandAvailable(command: EditCommand) -> Bool {
        AutomationSelectionCommands.available(state, command: command,
                                              clipboardAvailable: command == .paste && hasClipboard)
    }

    func executeSelectionEffect(_ effect: AutomationSelectionEffect) {
        guard let session else { return }
        switch effect {
        case let .paste(cursor):
            _ = pasteClipboard(at: cursor)
        case let .range(policy, selection, scope):
            session.withStateChanges {
                switch policy.rangeOperation {
                case .copySelection: _ = copySelection(selection, scope: scope)
                case .cut:
                    if copySelection(selection, scope: scope) {
                        _ = deleteSelection(selection, scope: scope)
                    }
                case .delete: _ = deleteSelection(selection, scope: scope)
                case .clearTimeSelection: break
                case .loopFromSelection:
                    // The original ruler contract deliberately records two undo entries.
                    session.document.setLoop(end: false, tick: Int64(selection.range.startTick))
                    session.document.setLoop(end: true, tick: Int64(selection.range.endTick))
                case .nudge: nudgeSelection(policy.nudgeDelta, selection: selection, scope: scope)
                case .transpose:
                    transposeSelection(policy.transposeSemitones, selection: selection, scope: scope)
                case .duplicate, .insertTime, .removeContents:
                    transformSelection(policy.rangeOperation, selection: selection, scope: scope)
                case .none: break
                }
            }
        }
    }

    private func copySelection(_ selection: AutomationTimeSelection, scope: TimeScope?) -> Bool {
        guard let session, let scope,
              let clip = ClipboardSemantics.extractTimeRange(
                selection.range, scope: scope, from: session.document,
                unterminatedDuration: selectionSnapDuration()) else { return false }
        return clipboard.write(clip, ticksPerBeat: UInt32(session.document.ticksPerBeat))
    }

    private func deleteSelection(_ selection: AutomationTimeSelection, scope: TimeScope?) -> Bool {
        guard let session, let scope else { return false }
        let changed = ClipboardSemantics.deleteTimeRange(selection.range, scope: scope,
                                                        from: session.document)
        if changed { refreshFromDocument() }
        return changed
    }

    func resolvedSelectionScope() -> TimeScope? {
        guard let selection = state.selection else { return nil }
        return AutomationSelectionCommands.resolvedScope(
            selection, usedTracks: state.document.usedTracks)
    }

    func selectionSnapPolicy() -> AutomationSnapPolicy? {
        guard let session else { return nil }
        return AutomationSnapPolicy(
            baseFontPx: baseFontPx, devicePixelRatio: devicePixelRatio,
            timeAxis: session.projectionCache.timeAxis,
            clockTicks: TimelineSnapPolicy.clockTicks(
                division: session.document.ticksPerBeat,
                extendedClocks: session.document.state.config.extendedClocks))
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

    private func transformSelection(_ operation: EditRangeOperation,
                                    selection captured: AutomationTimeSelection, scope: TimeScope?) {
        guard let session, let scope else { return }
        var selection = captured
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

    private func nudgeSelection(_ direction: Int, selection captured: AutomationTimeSelection,
                                scope: TimeScope?) {
        guard let session, let scope, let snap = selectionSnapPolicy() else { return }
        var selection = captured
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

    private func transposeSelection(_ semitones: Int, selection: AutomationTimeSelection,
                                    scope: TimeScope?) {
        guard let session, let scope else { return }
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
