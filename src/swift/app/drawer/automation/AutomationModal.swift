import Foundation
import PorydawCore

// Captured prompt/menu state and acceptance policy. All accepted mutations route
// through AutomationCommit; modal state never owns document history.

/// The published menu actions, under the production ids they name.
public enum AutomationMenuAction: Int, Sendable {
    case setValue = 1
    case deleteNode = 2
    case copyLane = 3
    case pasteLane = 4
    case clearLane = 5
    case deleteLaneEvents = 6
    case rangeCopy = 7
    case rangeCut = 8
    case rangePaste = 9
    case rangeDelete = 10
    case rangeClear = 11
    case valueRange = 12
    case rangeAuto = 13
    case range16 = 14
    case range32 = 15
    case range64 = 16
    case range127 = 17
}

/// What an open prompt is: the value form, or the CC-lane delete confirmation.
public enum AutomationPromptKind: Int, Sendable {
    case value = 0
    case confirmLaneDelete = 1
}

/// One open menu: the frozen facts, the target it captured, its anchor and
/// the rows it published. Nothing here re-reads live state.
struct AutomationMenuState {
    let facts: AutomationFrozenFacts
    let target: AutomationMenuTarget
    let anchorX: Double
    let anchorY: Double
    var rows: [AutomationMenuRowHandle]
}

enum AutomationMenuTarget: Equatable {
    case point(tick: Tick, value: Int)
    case lane
    case range
}

/// The captured CC-lane delete confirmation: the parameter, its written
/// event count and the revision the count was read at.
struct AutomationLaneDeleteConfirmation {
    let facts: AutomationFrozenFacts
    let eventCount: Int
    let title: String
    let message: String
}



@MainActor
extension AutomationPage {
    /// The captured point's own value prompt, revalidated against the captured
    /// revision: a stale capture opens nothing, exactly as the production
    /// dispatch revalidates before it opens a form. The projected engine node has
    /// no written occurrence, so its promotion goes through the same resolver the
    /// press path uses.
    func openCapturedPointPrompt(tick: Tick, value: Int,
                                        facts: AutomationFrozenFacts) -> Bool {
        guard let session, facts.revision == session.document.revision else { return false }
        return openPrompt(tick: tick, value: value)
    }

    /// The confirmation's acceptance: every written occurrence of the captured
    /// parameter goes as one plan, revalidated against the captured revision.
    @discardableResult
    func acceptLaneDeleteConfirmation() -> Bool {
        guard let session, let confirmation = laneDelete else { return false }
        laneDelete = nil
        publishPrompt()
        guard confirmation.facts.revision == session.document.revision,
              confirmation.facts.parameter == activeParameter,
              confirmation.facts.parameter.track == nil
                || confirmation.facts.parameter.track == activeTrack() else {
            publishInteractionState()
            return false
        }
        let ticks = confirmation.facts.snapshot.sources.map(\.tick)
        guard !ticks.isEmpty,
              let plan = AutomationNodeResolver.deletions(
                  revision: confirmation.facts.revision,
                  [AutomationNodeResolver.LaneDeletes(parameter: confirmation.facts.parameter,
                                                      snapshot: confirmation.facts.snapshot,
                                                      ticks: ticks)]) else {
            publishInteractionState()
            return false
        }
        let committed = AutomationCommit.apply(plan, in: session.document)
        if committed { refreshFromDocument() } else { publishInteractionState() }
        return committed
    }

    func openPointMenu(hit: AutomationProjectedPoint, facts: AutomationFrozenFacts,
                               x: Double, y: Double) {
        _ = openMenu(facts: facts, target: .point(tick: hit.tick, value: hit.value),
                     x: x + plotOrigin, y: y)
    }

    func openRangeMenu(x: Double, y: Double) {
        guard let selection, selection.isActive, let facts = frozenFacts(modifiers: .init()),
              selection.covers(facts.parameter, usedTracks: usedTracks()) else { return }
        _ = openMenu(facts: facts, target: .range, x: x + plotOrigin, y: y)
    }

    @discardableResult
    func openMenu(facts: AutomationFrozenFacts, target: AutomationMenuTarget,
                          x: Double, y: Double) -> Bool {
        guard session != nil else { return false }
        var state = AutomationMenuState(facts: facts, target: target,
                                        anchorX: max(0, x), anchorY: max(0, y), rows: [])
        state.rows = menuRows(for: target, facts: facts)
        guard !state.rows.isEmpty else { return false }
        menu = state
        menuX = state.anchorX
        menuY = state.anchorY
        publishMenuRows()
        publishInteractionState()
        return true
    }

    /// The rows one captured target publishes. Availability is read from the
    /// frozen facts and the accepted clipboard alone, so a row never claims an
    /// action the capture cannot perform.
    func menuRows(for target: AutomationMenuTarget,
                          facts: AutomationFrozenFacts) -> [AutomationMenuRowHandle] {
        switch target {
        case let .point(tick, _):
            // Delete only ever writes what the document holds: the projected
            // engine-default node has no written event at its tick, so its row is
            // disabled; Set Value stays enabled and promotes it.
            let written = !facts.snapshot.occurrences(at: tick).isEmpty
            return [
                AutomationMenuRowHandle(actionId: AutomationMenuAction.setValue.rawValue,
                                        text: "Set Value", enabled: true),
                AutomationMenuRowHandle(actionId: AutomationMenuAction.deleteNode.rawValue,
                                        text: "Delete", enabled: written),
            ]
        case .lane:
            var rows = [
                AutomationMenuRowHandle(actionId: AutomationMenuAction.copyLane.rawValue,
                                        text: facts.parameter.isTempo ? "Copy" : "Copy CC lane",
                                        enabled: facts.snapshot.eventCount > 0),
                AutomationMenuRowHandle(actionId: AutomationMenuAction.pasteLane.rawValue,
                                        text: facts.parameter.isTempo
                                              ? "Paste" : "Paste CC lane (replace)",
                                        enabled: laneClipPoints(facts.parameter) != nil),
                AutomationMenuRowHandle(separator: true),
                AutomationMenuRowHandle(actionId: AutomationMenuAction.clearLane.rawValue,
                                        text: facts.parameter.isTempo ? "Clear Tempo"
                                                                      : "Clear events",
                                        enabled: facts.snapshot.eventCount > 0),
            ]
            if !facts.parameter.isTempo {
                rows.append(AutomationMenuRowHandle(
                    actionId: AutomationMenuAction.deleteLaneEvents.rawValue,
                    text: "Delete automation events", enabled: facts.snapshot.eventCount > 0))
            }
            if facts.metadata.zoomable {
                let row = AutomationMenuRowHandle(
                    actionId: AutomationMenuAction.valueRange.rawValue,
                    text: "Value range", enabled: true)
                row.hasSubmenu = true
                rows.append(row)
            }
            return rows
        case .range:
            let covered = resolvedSelectionScope() != nil
            return [
                AutomationMenuRowHandle(actionId: AutomationMenuAction.rangeCopy.rawValue,
                                        text: "Copy", enabled: covered),
                AutomationMenuRowHandle(actionId: AutomationMenuAction.rangeCut.rawValue,
                                        text: "Cut", enabled: covered),
                AutomationMenuRowHandle(actionId: AutomationMenuAction.rangePaste.rawValue,
                                        text: "Paste", enabled: selectionCommandAvailable(command: .paste)),
                AutomationMenuRowHandle(separator: true),
                AutomationMenuRowHandle(actionId: AutomationMenuAction.rangeDelete.rawValue,
                                        text: "Delete", enabled: covered),
                AutomationMenuRowHandle(actionId: AutomationMenuAction.rangeClear.rawValue,
                                        text: "Clear Selection", enabled: true),
            ]
        }
    }

    /// The lane menu's destructive command: the confirmation captures the
    /// parameter, the written event count and the revision the count was read at.
    func openLaneDeleteConfirmation(_ facts: AutomationFrozenFacts) {
        let count = facts.snapshot.eventCount
        guard count > 0 else { return }
        let title = AutomationCatalog.title(facts.parameter)
        laneDelete = AutomationLaneDeleteConfirmation(
            facts: facts, eventCount: count, title: "Delete automation events",
            message: "Delete the \(title) parameter's \(count) written events?"
                + " The \(title) parameter remains.")
        applyPrompt(nil)
        promptDraft = ""
        promptError = ""
        publishPrompt()
        publishInteractionState()
    }

    // MARK: Lane and range commands

    /// The historical lane clipboard stores absolute tick/value pairs, separate
    /// from the system's note/time-selection clipboard.
    @discardableResult
    func copyLanePoints(_ facts: AutomationFrozenFacts) -> Bool {
        guard session != nil, facts.snapshot.eventCount > 0 else { return false }
        laneClipboardPoints = facts.snapshot.sources.map {
            AutomationLanePoint(tick: $0.tick, value: $0.value)
        }
        return true
    }

    /// `Paste CC lane (replace)` / `Paste`: one whole-lane replacement.
    @discardableResult
    func pasteLanePoints(_ facts: AutomationFrozenFacts) -> Bool {
        guard let session, let points = laneClipPoints(facts.parameter) else { return false }
        let committed = AutomationCommit.apply(
            AutomationRangeEditor.replaceLane(facts, points: points), in: session.document)
        if committed { refreshFromDocument() }
        return committed
    }

    /// `Clear events` / `Clear Tempo`: the same whole-lane replacement with no
    /// points, which leaves the parameter itself in place.
    @discardableResult
    func clearLanePoints(_ facts: AutomationFrozenFacts) -> Bool {
        guard let session, facts.snapshot.eventCount > 0 else { return false }
        let committed = AutomationCommit.apply(
            AutomationRangeEditor.replaceLane(facts, points: []), in: session.document)
        if committed { refreshFromDocument() }
        return committed
    }


    /// A copied lane may be pasted into another parameter; clamp at destination.
    func laneClipPoints(_ parameter: AutomationParameter) -> [AutomationLanePoint]? {
        guard !laneClipboardPoints.isEmpty else { return nil }
        let metadata = AutomationParameterMetadata(parameter: parameter)
        return laneClipboardPoints.map {
            AutomationLanePoint(tick: $0.tick,
                                value: min(metadata.maximum, max(metadata.minimum, $0.value)))
        }
    }

}

@MainActor
extension AutomationPage {
    func openCapturedPrompt(tick: Tick, value: Int) -> Bool {
        guard let facts = frozenFacts(modifiers: .init()) else { return false }
        let occupants = facts.occupants(at: tick)
        let nextPrompt = AutomationPromptTransaction(
            facts: facts,
            anchor: AutomationLanePoint(tick: tick, value: value),
            source: occupants.last,
            forExistingNode: !occupants.isEmpty,
            metadata: facts.metadata)
        applyPrompt(nextPrompt)
        guard let nextPrompt else { return false }
        frozen = facts
        frozenCamera = liveCamera()
        laneDelete = nil
        promptDraft = String(nextPrompt.prompt.initialValue)
        promptError = ""
        publishPrompt()
        publishInteractionState()
        return true
    }

    func acceptCapturedPrompt(displayedValue: Int) -> Bool {
        guard let session, let prompt else { return false }
        applyPrompt(nil)
        frozen = nil
        frozenCamera = nil
        publishPrompt()
        guard prompt.facts.revision == session.document.revision,
              prompt.facts.parameter == activeParameter,
              prompt.facts.parameter.track == nil || prompt.facts.parameter.track == activeTrack() else {
            publishInteractionState()
            return false
        }
        var committed = false
        switch prompt.outcome(displayed: displayedValue) {
        case .none:
            break
        case let .move(move):
            committed = commit(AutomationNodeResolver.moves([
                AutomationNodeResolver.LaneMoves(prompt.facts, [move])
            ]))
        case let .insert(edit):
            committed = AutomationCommit.apply(edit, in: session.document)
        }
        if committed {
            refreshFromDocument()
        } else {
            publishContext()
            publishInteractionState()
        }
        return committed
    }

    func updateCapturedPromptDraft(draft text: String) {
        guard promptOpen else { return }
        promptDraft = text
        promptError = draftError ?? ""
    }

    func acceptCapturedPromptDraft() -> Bool {
        if laneDelete != nil { return acceptLaneDeleteConfirmation() }
        guard prompt != nil else { return false }
        if let error = draftError {
            promptError = error
            return false
        }
        guard let value = Int(promptDraft.trimmingCharacters(in: .whitespaces)) else {
            promptError = draftError ?? ""
            return false
        }
        return acceptPrompt(displayedValue: value)
    }

    func cancelCapturedPrompt() {
        applyPrompt(nil)
        laneDelete = nil
        if gesture == nil {
            frozen = nil
            frozenCamera = nil
        }
        publishPrompt()
        publishInteractionState()
    }

    func deleteCapturedPoints(at ticks: [Tick]) -> Bool {
        guard !ticks.isEmpty, let facts = frozenFacts(modifiers: .init()),
              commit(AutomationNodeResolver.deletions(
                  revision: facts.revision,
                  [AutomationNodeResolver.LaneDeletes(parameter: facts.parameter,
                                                      snapshot: facts.snapshot, ticks: ticks)]))
        else { return false }
        refreshFromDocument()
        return true
    }

    func deleteCapturedSelection() -> Bool {
        guard let session, let selection, let scope = resolvedSelectionScope() else { return false }
        let changed = ClipboardSemantics.deleteTimeRange(selection.range, scope: scope,
                                                        from: session.document)
        if changed { refreshFromDocument() }
        return changed
    }

    func copyCapturedTimeSelection() -> Bool {
        guard let session, let selection, let scope = resolvedSelectionScope(),
              let clip = ClipboardSemantics.extractTimeRange(
                selection.range, scope: scope, from: session.document,
                unterminatedDuration: selectionSnapDuration()) else { return false }
        return clipboard.write(clip, ticksPerBeat: UInt32(session.document.ticksPerBeat))
    }

    func cutCapturedTimeSelection() -> Bool {
        guard copyCapturedTimeSelection() else { return false }
        _ = deleteCapturedSelection()
        return true
    }

    func pasteCapturedTimeSelection(at cursor: Tick) -> Tick? {
        pasteClipboard(at: cursor)
    }

    func openCapturedParameterMenu(index: Int, x: Double, y: Double) -> Bool {
        guard session != nil, index >= 0, index < AutomationCatalog.count else { return false }
        if index != activeParameterIndex, !activateParameter(index: index) { return false }
        guard let facts = frozenFacts(modifiers: .init()) else { return false }
        return openMenu(facts: facts, target: .lane, x: x, y: y)
    }

    func dismissCapturedMenu() {
        guard menu != nil else { return }
        menu = nil
        publishMenuRows()
        publishInteractionState()
    }

    func consumeCapturedMenuAction(actionId: Int) -> Bool {
        guard let session, let live = menu else { return false }
        let childRows: [AutomationMenuRowHandle]
        if case .lane = live.target { childRows = rangeMenuRows(facts: live.facts) }
        else { childRows = [] }
        guard let row = (live.rows + childRows).first(where: { $0.actionId == actionId }) else {
            return false
        }
        guard row.enabled, !row.separator,
              let action = AutomationMenuAction(rawValue: row.actionId) else { return false }
        guard live.facts.revision == session.document.revision,
              live.facts.parameter == activeParameter,
              live.facts.parameter.track == nil || live.facts.parameter.track == activeTrack() else {
            dismissMenu()
            return false
        }
        if action == .valueRange { return true }
        menu = nil
        publishMenuRows()

        switch (action, live.target) {
        case (.rangeAuto, .lane), (.range16, .lane), (.range32, .lane),
             (.range64, .lane), (.range127, .lane):
            let ranges: [AutomationMenuAction: Int] = [
                .rangeAuto: 0, .range16: 16, .range32: 32, .range64: 64, .range127: 127]
            laneRanges[live.facts.parameter] = ranges[action]
            rebuildContent()
        case let (.setValue, .point(tick, value)):
            // The form it opens is the action's own outcome: the returned row
            // consumption below stays this method's contract, and a refused
            // capture (a moved revision) opens nothing without changing it.
            _ = openCapturedPointPrompt(tick: tick, value: value, facts: live.facts)
        case let (.deleteNode, .point(tick, _)):
            deletePoints(at: [tick])
        case (.copyLane, _):
            copyLanePoints(live.facts)
        case (.pasteLane, _):
            pasteLanePoints(live.facts)
        case (.clearLane, _):
            clearLanePoints(live.facts)
        case (.deleteLaneEvents, _):
            openLaneDeleteConfirmation(live.facts)
        case (.rangeCopy, _):
            copyTimeSelection()
        case (.rangeCut, _):
            cutTimeSelection()
        case (.rangePaste, _):
            consumeSelectionCommand(command: .paste)
        case (.rangeDelete, _):
            deleteSelectedNodes()
        case (.rangeClear, _):
            clearTimeSelection()
        default:
            break
        }
        publishInteractionState()
        return true
    }

    func rangeMenuRows(facts: AutomationFrozenFacts) -> [AutomationMenuRowHandle] {
        guard facts.metadata.zoomable else { return [] }
        let selected = laneRanges[facts.parameter]
            ?? Int(AutomationCatalog.defaultRange(facts.parameter.controller ?? 0))
        let entries: [(AutomationMenuAction, Int, String)] = [
            (.rangeAuto, 0, "Auto (fit to data)"), (.range16, 16, "0–16"),
            (.range32, 32, "0–32"), (.range64, 64, "0–64"), (.range127, 127, "0–127 (full)")]
        return entries.map { action, value, text in
            let row = AutomationMenuRowHandle(actionId: action.rawValue, text: text, enabled: true)
            row.checkable = true
            row.checked = selected == value
            return row
        }
    }

    var capturedPromptDraftError: String? {
        guard let prompt else { return nil }
        let trimmed = promptDraft.trimmingCharacters(in: .whitespaces)
        guard let value = Int(trimmed),
              value >= prompt.prompt.minimum, value <= prompt.prompt.maximum else {
            return "Enter a whole number from \(prompt.prompt.minimum)"
                + " to \(prompt.prompt.maximum)."
        }
        return nil
    }

}
