/// Mirrors `SongView::EditKeyOrigin` (src/ui/songview.h): which editor
/// surface physically received the key.
public enum EditKeyOrigin: Int {
    case timeline, eventList
}

/// The routing verdict for one recognized key: decline hands the key back
/// to its local owner, consume swallows it without acting, execute runs
/// the command's activation path.
public enum EditKeyDecision: Int {
    case decline = 0, consume = 1, execute = 2
}

/// The host-arbitrated surface snapshot the resolver judges (spec §1 D1):
/// plain values only — Swift never observes Qt, the focus chain, or the
/// selection model directly.
public struct EditSurfaceState {
    public var pointerGestureActive: Bool   // live grid gesture
    public var timeSelectionActive: Bool
    public var noteSelectionEmpty: Bool
    public var origin: EditKeyOrigin
    public var autoRepeat: Bool
    public var commandAvailable: Bool       // host answers eligibility (editCommandAvailable analog)
}

public enum EditKeyArbiter {

    /// The selection target of one selection-routed command, ported from
    /// `resolveSelectionTarget` (editkeyrouting.cpp:41-50): an active time
    /// selection wins when the row has a range operation, then notes —
    /// eligible only from the timeline, never the event list — else none.
    private enum SelectionTarget {
        case none, notes, timeRange
    }

    private static func resolveSelectionTarget(
        _ policy: EditCommandPolicy, surface: EditSurfaceState
    ) -> SelectionTarget {
        if surface.timeSelectionActive && policy.rangeOperation != .none {
            return .timeRange
        }
        if policy.notesOperation != .none && surface.origin == .timeline {
            return .notes
        }
        return .none
    }

    /// Routes one recognized command through the frozen policy table in
    /// `handleEditKey` statement order (editkeyrouting.cpp:404-491). A nil
    /// command is an unbound key: host-owned, always declined.
    public static func decide(command: EditCommand?, surface: EditSurfaceState) -> EditKeyDecision {
        guard let command else {
            return .decline  // editkeyrouting.cpp:428 — unbound keys are host-owned
        }
        let policy = editCommandPolicy(command)

        // A live pointer gesture owns every matched command except rows
        // that explicitly survive it; the key is consumed without acting.
        if surface.pointerGestureActive && !policy.survivesPointerGesture {
            return .consume  // editkeyrouting.cpp:436
        }

        // Origin rows: the event page alone receives row-reorder delivery,
        // and grid commands belong to the timeline surface.
        if policy.originRule == .eventListOnly && surface.origin != .eventList {
            return .decline  // editkeyrouting.cpp:442-443
        }
        if policy.originRule == .timelineOnly && surface.origin != .timeline {
            return .decline  // editkeyrouting.cpp:444-445
        }

        switch policy.keyRoute {  // editkeyrouting.cpp:447
        case .alwaysConsume:
            // The executor no-ops when the command is ineligible.
            return .execute  // editkeyrouting.cpp:448-451 → :489

        case .availabilityGated:
            if !surface.commandAvailable {
                return .decline  // editkeyrouting.cpp:456-457
            }
            if surface.autoRepeat && policy.autoRepeatRule == .consumeWhenEligible {
                return .consume  // editkeyrouting.cpp:458-459
            }
            return .execute  // editkeyrouting.cpp:460 → :489

        case .selectionTargeted:
            let target = resolveSelectionTarget(policy, surface: surface)  // :463-464
            if target == .none {
                return policy.terminalWhenUnmatched ? .consume : .decline  // :465-466
            }
            // Keys judge live eligibility, not cached enablement: an
            // unavailable command resolves through the row's ownership —
            // ownsKey is a consumed no-op (lane-scoped transpose), else
            // terminalWhenUnmatched decides.
            if !surface.commandAvailable {
                return policy.ownershipOnUnavailable == .ownsKey
                    ? .consume
                    : (policy.terminalWhenUnmatched ? .consume : .decline)  // :475-478
            }
            if target == .notes && surface.autoRepeat
                && policy.autoRepeatRule == .consumeWhenEligible {
                return .consume  // editkeyrouting.cpp:480-482
            }
            return .execute  // editkeyrouting.cpp:483 → :489
        }
    }
}
