import Foundation
import PorydawCore

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

public enum AutomationPromptKind: Int, Sendable {
    case value = 0
    case confirmLaneDelete = 1
}

/// A published menu row is a value; the publication boundary creates Qt handles.
struct AutomationMenuRowValue: Equatable, Sendable {
    var actionId: Int
    var text: String
    var enabled: Bool
    var separator = false
    var checkable = false
    var checked = false
    var hasSubmenu = false

    init(_ action: AutomationMenuAction, _ text: String, enabled: Bool = true,
         checkable: Bool = false, checked: Bool = false, hasSubmenu: Bool = false) {
        actionId = action.rawValue
        self.text = text
        self.enabled = enabled
        self.checkable = checkable
        self.checked = checked
        self.hasSubmenu = hasSubmenu
    }

    private init(separator: Bool) {
        actionId = -1
        text = ""
        enabled = false
        self.separator = separator
    }

    static let divider = Self(separator: true)
}

struct AutomationMenuState: Sendable {
    let facts: AutomationFrozenFacts
    let target: AutomationMenuTarget
    let anchorX: Double
    let anchorY: Double
    let rows: [AutomationMenuRowValue]
    let childRows: [AutomationMenuRowValue]
}

enum AutomationMenuTarget: Equatable, Sendable {
    case point(tick: Tick, value: Int)
    case lane
    case range
}

struct AutomationLaneDeleteConfirmation: Sendable {
    let facts: AutomationFrozenFacts
    let eventCount: Int
    let title: String
    let message: String
}

/// Exactly one modal surface can be open. Draft and validation belong to that
/// surface, not to the Qt publication or a second page-side source of truth.
struct AutomationModalState: Sendable {
    var menu: AutomationMenuState?
    var prompt: AutomationPromptTransaction?
    var laneDelete: AutomationLaneDeleteConfirmation?
    var draft = ""
    var error = ""

    static let none = Self()
    var isOpen: Bool { menu != nil || prompt != nil || laneDelete != nil }
    var facts: AutomationFrozenFacts? { prompt?.facts ?? laneDelete?.facts ?? menu?.facts }

    var draftError: String? {
        guard let prompt else { return nil }
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard let value = Int(text),
              value >= prompt.prompt.minimum, value <= prompt.prompt.maximum else {
            return "Enter a whole number from \(prompt.prompt.minimum)"
                + " to \(prompt.prompt.maximum)."
        }
        return nil
    }
}

enum AutomationModalEvent: Sendable {
    case openPrompt(facts: AutomationFrozenFacts, tick: Tick, value: Int)
    case openLaneDeleteConfirmation(AutomationFrozenFacts)
    case openMenu(facts: AutomationFrozenFacts, target: AutomationMenuTarget,
                  x: Double, y: Double, selectionScopeAvailable: Bool,
                  systemClipboardAvailable: Bool, laneClipboardAvailable: Bool)
    case draftChanged(String)
    case acceptDraft
    case acceptValue(Int)
    case cancelPrompt
    case dismissMenu
    case consumeMenuAction(Int)
}

/// Only boundary operations are effects. All captured-target policy, stale
/// checks, collision resolution and menu availability remain in the reducer.
enum AutomationModalEffect: Sendable {
    case copyTimeSelection
    case cutTimeSelection
    case pasteTimeSelection
    case deleteTimeSelection
    case clearTimeSelection
}

enum AutomationModal {
    static func reduce(_ state: inout AutomationState,
                       event: AutomationModalEvent) -> AutomationTransition {
        switch event {
        case let .openPrompt(facts, tick, value):
            guard valid(facts, in: state) else { return AutomationTransition() }
            return openPrompt(&state, facts: facts, tick: tick, value: value)

        case let .openLaneDeleteConfirmation(facts):
            guard valid(facts, in: state), facts.snapshot.eventCount > 0 else {
                return AutomationTransition()
            }
            openConfirmation(&state, facts: facts)
            return AutomationTransition(publication: [.prompt, .menu, .interaction],
                                        outcome: AutomationOutcome(consumed: true, accepted: true))

        case let .openMenu(facts, target, x, y, scopeAvailable, systemClip, laneClip):
            guard valid(facts, in: state) else { return AutomationTransition() }
            let rows = menuRows(for: target, facts: facts,
                                selectionScopeAvailable: scopeAvailable,
                                systemClipboardAvailable: systemClip,
                                laneClipboardAvailable: laneClip)
            guard !rows.isEmpty else { return AutomationTransition() }
            let children: [AutomationMenuRowValue]
            if case .lane = target {
                children = rangeMenuRows(facts: facts, selected: state.laneRanges[facts.parameter])
            } else {
                children = []
            }
            state.modal = AutomationModalState(menu: AutomationMenuState(
                facts: facts, target: target, anchorX: max(0, x), anchorY: max(0, y),
                rows: rows, childRows: children))
            return AutomationTransition(publication: [.prompt, .menu, .interaction],
                                        outcome: AutomationOutcome(consumed: true, accepted: true))

        case let .draftChanged(text):
            guard state.modal.prompt != nil || state.modal.laneDelete != nil else {
                return AutomationTransition()
            }
            state.modal.draft = text
            state.modal.error = state.modal.draftError ?? ""
            return AutomationTransition(publication: .prompt,
                                        outcome: AutomationOutcome(consumed: true, accepted: true))

        case .acceptDraft:
            if state.modal.laneDelete != nil { return acceptLaneDelete(&state) }
            guard state.modal.prompt != nil else { return AutomationTransition() }
            if let error = state.modal.draftError {
                state.modal.error = error
                return AutomationTransition(publication: .prompt)
            }
            guard let value = Int(state.modal.draft.trimmingCharacters(in: .whitespaces)) else {
                return AutomationTransition()
            }
            return acceptValue(&state, displayed: value)

        case let .acceptValue(value):
            return acceptValue(&state, displayed: value)

        case .cancelPrompt:
            guard state.modal.prompt != nil || state.modal.laneDelete != nil else {
                return AutomationTransition()
            }
            state.modal = .none
            return AutomationTransition(publication: [.prompt, .interaction],
                                        outcome: AutomationOutcome(consumed: true, accepted: true))

        case .dismissMenu:
            guard state.modal.menu != nil else { return AutomationTransition() }
            state.modal = .none
            return AutomationTransition(publication: [.menu, .interaction],
                                        outcome: AutomationOutcome(consumed: true, accepted: true))

        case let .consumeMenuAction(actionId):
            return consumeMenuAction(&state, actionId: actionId)
        }
    }

    private static func valid(_ facts: AutomationFrozenFacts,
                              in state: AutomationState) -> Bool {
        state.document.attached && facts.revision == state.document.revision
            && facts.parameter == state.activeParameter
            && (facts.parameter.track == nil || facts.parameter.track == state.activeTrack)
    }

    private static func openPrompt(_ state: inout AutomationState,
                                   facts: AutomationFrozenFacts, tick: Tick,
                                   value: Int) -> AutomationTransition {
        let occupants = facts.occupants(at: tick)
        guard let prompt = AutomationPromptTransaction(
            facts: facts, anchor: AutomationLanePoint(tick: tick, value: value),
            source: occupants.last, forExistingNode: !occupants.isEmpty,
            metadata: facts.metadata) else { return AutomationTransition() }
        state.modal = AutomationModalState(prompt: prompt,
                                           draft: String(prompt.prompt.initialValue))
        return AutomationTransition(publication: [.prompt, .menu, .interaction],
                                    outcome: AutomationOutcome(consumed: true, accepted: true))
    }

    private static func openConfirmation(_ state: inout AutomationState,
                                         facts: AutomationFrozenFacts) {
        let title = AutomationCatalog.title(facts.parameter)
        let count = facts.snapshot.eventCount
        state.modal = AutomationModalState(laneDelete: AutomationLaneDeleteConfirmation(
            facts: facts, eventCount: count, title: "Delete automation events",
            message: "Delete the \(title) parameter's \(count) written events?"
                + " The \(title) parameter remains."))
    }

    private static func acceptValue(_ state: inout AutomationState,
                                    displayed: Int) -> AutomationTransition {
        guard let prompt = state.modal.prompt else { return AutomationTransition() }
        state.modal = .none
        guard valid(prompt.facts, in: state) else {
            return AutomationTransition(publication: [.prompt, .context, .interaction])
        }
        var effects: [AutomationEffect] = []
        switch prompt.outcome(displayed: displayed) {
        case .none:
            break
        case let .move(move):
            if let plan = AutomationNodeResolver.moves([
                AutomationNodeResolver.LaneMoves(prompt.facts, [move])]) {
                effects = [.commitDocument(plan, selectionDelta: nil)]
            }
        case let .insert(edit):
            effects = [.commitLane(edit)]
        }
        return AutomationTransition(publication: [.prompt, .context, .interaction],
                                    effects: effects,
                                    outcome: AutomationOutcome(consumed: true,
                                                               accepted: !effects.isEmpty,
                                                               written: !effects.isEmpty))
    }

    private static func acceptLaneDelete(_ state: inout AutomationState) -> AutomationTransition {
        guard let confirmation = state.modal.laneDelete else { return AutomationTransition() }
        state.modal = .none
        guard valid(confirmation.facts, in: state) else {
            return AutomationTransition(publication: [.prompt, .interaction])
        }
        let facts = confirmation.facts
        let ticks = facts.snapshot.sources.map(\.tick)
        guard !ticks.isEmpty, let plan = AutomationNodeResolver.deletions(
            revision: facts.revision,
            [AutomationNodeResolver.LaneDeletes(parameter: facts.parameter,
                                                snapshot: facts.snapshot, ticks: ticks)]) else {
            return AutomationTransition(publication: [.prompt, .interaction])
        }
        return AutomationTransition(publication: [.prompt, .interaction],
                                    effects: [.commitDocument(plan, selectionDelta: nil)],
                                    outcome: AutomationOutcome(consumed: true, accepted: true,
                                                               written: true))
    }

    private static func consumeMenuAction(_ state: inout AutomationState,
                                          actionId: Int) -> AutomationTransition {
        guard let menu = state.modal.menu,
              let row = (menu.rows + menu.childRows).first(where: { $0.actionId == actionId }),
              row.enabled, !row.separator,
              let action = AutomationMenuAction(rawValue: row.actionId) else {
            return AutomationTransition()
        }
        guard valid(menu.facts, in: state) else {
            state.modal = .none
            return AutomationTransition(publication: [.menu, .interaction])
        }
        if action == .valueRange {
            return AutomationTransition(outcome: AutomationOutcome(consumed: true, accepted: true))
        }
        state.modal = .none
        var transition = AutomationTransition(publication: [.menu, .interaction],
                                              outcome: AutomationOutcome(consumed: true,
                                                                         accepted: true))
        switch (action, menu.target) {
        case (.rangeAuto, .lane), (.range16, .lane), (.range32, .lane),
             (.range64, .lane), (.range127, .lane):
            let ranges: [AutomationMenuAction: Int] = [
                .rangeAuto: 0, .range16: 16, .range32: 32, .range64: 64, .range127: 127]
            state.laneRanges[menu.facts.parameter] = ranges[action]
            transition.publication.insert(.content)

        case let (.setValue, .point(tick, value)):
            transition.merge(openPrompt(&state, facts: menu.facts, tick: tick, value: value))

        case let (.deleteNode, .point(tick, _)):
            if let plan = AutomationNodeResolver.deletions(
                revision: menu.facts.revision,
                [AutomationNodeResolver.LaneDeletes(parameter: menu.facts.parameter,
                                                    snapshot: menu.facts.snapshot, ticks: [tick])]) {
                transition.effects = [.commitDocument(plan, selectionDelta: nil)]
                transition.outcome.written = true
            }

        case (.copyLane, .lane):
            state.laneClipboardPoints = menu.facts.snapshot.sources.map {
                AutomationLanePoint(tick: $0.tick, value: $0.value)
            }
            transition.commandAvailabilityChanged = true
        case (.pasteLane, .lane):
            let metadata = AutomationParameterMetadata(parameter: menu.facts.parameter)
            let points = state.laneClipboardPoints.map {
                AutomationLanePoint(tick: $0.tick,
                                    value: min(metadata.maximum, max(metadata.minimum, $0.value)))
            }
            transition.effects = [.commitLane(AutomationRangeEditor.replaceLane(
                menu.facts, points: points))]
            transition.outcome.written = true
        case (.clearLane, .lane):
            transition.effects = [.commitLane(AutomationRangeEditor.replaceLane(
                menu.facts, points: []))]
            transition.outcome.written = true
        case (.deleteLaneEvents, .lane):
            openConfirmation(&state, facts: menu.facts)
            transition.publication.insert(.prompt)
        case (.rangeCopy, .range):
            transition.effects = [.modal(.copyTimeSelection)]
        case (.rangeCut, .range):
            transition.effects = [.modal(.cutTimeSelection)]
        case (.rangePaste, .range):
            transition.effects = [.modal(.pasteTimeSelection)]
        case (.rangeDelete, .range):
            transition.effects = [.modal(.deleteTimeSelection)]
        case (.rangeClear, .range):
            state.selection = nil
            transition.publication.insert(.content)
            transition.selectionBuild = true
            transition.commandAvailabilityChanged = true
        default:
            // The action-target pairing is captured by the row's menu kind.
            transition.outcome.accepted = false
        }
        return transition
    }

    static func menuRows(for target: AutomationMenuTarget, facts: AutomationFrozenFacts,
                         selectionScopeAvailable: Bool, systemClipboardAvailable: Bool,
                         laneClipboardAvailable: Bool) -> [AutomationMenuRowValue] {
        switch target {
        case let .point(tick, _):
            return [
                .init(.setValue, "Set Value"),
                .init(.deleteNode, "Delete",
                      enabled: !facts.snapshot.occurrences(at: tick).isEmpty),
            ]
        case .lane:
            let written = facts.snapshot.eventCount > 0
            var rows: [AutomationMenuRowValue] = [
                .init(.copyLane, facts.parameter.isTempo ? "Copy" : "Copy CC lane",
                      enabled: written),
                .init(.pasteLane, facts.parameter.isTempo ? "Paste" : "Paste CC lane (replace)",
                      enabled: laneClipboardAvailable),
                .divider,
                .init(.clearLane, facts.parameter.isTempo ? "Clear Tempo" : "Clear events",
                      enabled: written),
            ]
            if !facts.parameter.isTempo {
                rows.append(.init(.deleteLaneEvents, "Delete automation events", enabled: written))
            }
            if facts.metadata.zoomable {
                rows.append(.init(.valueRange, "Value range", hasSubmenu: true))
            }
            return rows
        case .range:
            return [
                .init(.rangeCopy, "Copy", enabled: selectionScopeAvailable),
                .init(.rangeCut, "Cut", enabled: selectionScopeAvailable),
                .init(.rangePaste, "Paste", enabled: systemClipboardAvailable),
                .divider,
                .init(.rangeDelete, "Delete", enabled: selectionScopeAvailable),
                .init(.rangeClear, "Clear Selection"),
            ]
        }
    }

    static func rangeMenuRows(facts: AutomationFrozenFacts,
                              selected override: Int?) -> [AutomationMenuRowValue] {
        guard facts.metadata.zoomable else { return [] }
        let selected = override ?? Int(AutomationCatalog.defaultRange(facts.parameter.controller ?? 0))
        return [
            .init(.rangeAuto, "Auto (fit to data)", checkable: true, checked: selected == 0),
            .init(.range16, "0–16", checkable: true, checked: selected == 16),
            .init(.range32, "0–32", checkable: true, checked: selected == 32),
            .init(.range64, "0–64", checkable: true, checked: selected == 64),
            .init(.range127, "0–127 (full)", checkable: true, checked: selected == 127),
        ]
    }
}

// Document and clipboard operations stay at the page boundary. They are called
// only when interpreting an emitted effect, never by modal policy.
@MainActor
extension AutomationPage {

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
}
