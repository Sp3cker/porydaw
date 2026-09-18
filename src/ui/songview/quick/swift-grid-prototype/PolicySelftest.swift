import Foundation
import NativeGridSmoke

// Wave-2 policy selftest driver (spec §4, §6.3). Task 3 asserts the
// policy-table-parity sweep: every command, every field, Swift ==
// production through sgp_*. Task 4 adds the policy-dimensions matrix:
// the six selectionkey scenario dimensions as frozen decisions over
// EditKeyArbiter. Called from App.init after runMathSelftestIfRequested so a
// mismatch fails fast, before any window opens. A FAIL exits nonzero; the
// final `SWIFT_GRID_SMOKE PASS` line still comes from the C++ exercise().

/// No-op unless PORYDAW_SWIFT_GRID_SMOKE == "1".
func runPolicySelftestIfRequested() {
    guard ProcessInfo.processInfo.environment["PORYDAW_SWIFT_GRID_SMOKE"] == "1" else {
        return
    }
    runPolicyTableParitySweep()
    runPolicyDimensionsMatrix()
}

private func policyFail(_ detail: String) -> Never {
    fputs("SWIFT_GRID_SMOKE policy-table-parity FAIL: \(detail)\n", stderr)
    fflush(stderr)
    exit(EXIT_FAILURE)
}

// MARK: - policy-table-parity (spec §6.3, frozen)

/// For every command 0…34 and all 14 fields, Swift `editCommandTable`
/// equals `sgp_policy_row`; a mismatch names command, field, Swift value,
/// C++ value.
private func runPolicyTableParitySweep() {
    let count = Int(sgp_command_count())
    if count != EditCommand.allCases.count || editCommandTable.count != count {
        policyFail(
            "command count: swift enum=\(EditCommand.allCases.count) "
                + "table=\(editCommandTable.count) c++=\(count)")
    }

    for command in EditCommand.allCases {
        var row = SGECommandPolicyRow()
        sgp_policy_row(Int32(command.rawValue), &row)
        let swift = editCommandTable[command.rawValue]
        let name = String(describing: command)

        check(name, "command", Int32(swift.command.rawValue), row.command)
        check(name, "rangeOperation", Int32(swift.rangeOperation.rawValue), row.rangeOperation)
        check(name, "notesOperation", Int32(swift.notesOperation.rawValue), row.notesOperation)
        check(
            name, "standaloneOperation", Int32(swift.standaloneOperation.rawValue),
            row.standaloneOperation)
        check(name, "keyRoute", Int32(swift.keyRoute.rawValue), row.keyRoute)
        check(name, "originRule", Int32(swift.originRule.rawValue), row.originRule)
        check(name, "autoRepeatRule", Int32(swift.autoRepeatRule.rawValue), row.autoRepeatRule)
        check(
            name, "ownershipOnUnavailable", Int32(swift.ownershipOnUnavailable.rawValue),
            row.ownershipOnUnavailable)
        check(
            name, "focusedTextOwnership", Int32(swift.focusedTextOwnership.rawValue),
            row.focusedTextOwnership)
        check(name, "transposeSemitones", Int32(swift.transposeSemitones), row.transposeSemitones)
        check(name, "nudgeDelta", Int32(swift.nudgeDelta), row.nudgeDelta)
        check(name, "eventRowDelta", Int32(swift.eventRowDelta), row.eventRowDelta)
        check(
            name, "survivesPointerGesture", swift.survivesPointerGesture ? 1 : 0,
            row.survivesPointerGesture)
        check(
            name, "terminalWhenUnmatched", swift.terminalWhenUnmatched ? 1 : 0,
            row.terminalWhenUnmatched)
    }

    print("SWIFT_GRID_SMOKE policy-table-parity PASS")
}

private func check(_ command: String, _ field: String, _ swift: Int32, _ cxx: Int32) {
    if swift != cxx {
        policyFail("\(command).\(field) swift=\(swift) c++=\(cxx)")
    }
}

// MARK: - policy-dimensions (spec §6.3, frozen)

private func dimensionsFail(_ detail: String) -> Never {
    fputs("SWIFT_GRID_SMOKE policy-dimensions FAIL: \(detail)\n", stderr)
    fflush(stderr)
    exit(EXIT_FAILURE)
}

/// EditSurfaceState fixture shorthand: the five distinct surfaces the
/// matrix's decide rows exercise. `noteSelectionEmpty` is snapshot input
/// for the host's availability answer; the resolver never reads it (the
/// production target resolver doesn't either).
private func surface(
    gesture: Bool = false,
    timeSelection: Bool = false,
    notesEmpty: Bool = false,
    origin: EditKeyOrigin = .timeline,
    autoRepeat: Bool = false,
    available: Bool = true
) -> EditSurfaceState {
    EditSurfaceState(
        pointerGestureActive: gesture,
        timeSelectionActive: timeSelection,
        noteSelectionEmpty: notesEmpty,
        origin: origin,
        autoRepeat: autoRepeat,
        commandAvailable: available)
}

private func expectDecision(
    _ row: String, _ command: EditCommand?, _ surface: EditSurfaceState,
    _ want: EditKeyDecision
) {
    let got = EditKeyArbiter.decide(command: command, surface: surface)
    if got != want {
        dimensionsFail("\(row): got \(got) want \(want)")
    }
}

private func expectEnabled(
    _ row: String, _ command: EditCommand, textFocused: Bool, rowAvailable: Bool,
    _ want: Bool
) {
    let got = EditKeyArbiter.windowActionEnabled(
        command: command, textFocused: textFocused, rowAvailable: rowAvailable)
    if got != want {
        dimensionsFail("\(row): got \(got) want \(want)")
    }
}

/// The frozen six-dimension matrix (spec §6.3): 19 rows, one decision
/// each, ported from the selectionkey suites named per row.
private func runPolicyDimensionsMatrix() {
    // The five distinct surface fixtures the decide rows use; the
    // unbound-key dimension reuses them verbatim.
    let eligibleRepeat = surface(autoRepeat: true)
    let unavailableNotes = surface(available: false)
    let eventList = surface(origin: .eventList)
    let gestureActive = surface(gesture: true)
    let eligible = surface()

    // autoRepeat consumption — selectionkey-core (drawer transpose
    // audition) and selectionkey-local-input (pitch-bend repeat).
    expectDecision("pitchbend-autorepeat-consumes", .pitchBend, eligibleRepeat, .consume)
    expectDecision("pencilmode-autorepeat-consumes", .pencilMode, eligibleRepeat, .consume)
    expectDecision("transposeup-autorepeat-reexecutes", .transposeUp, eligibleRepeat, .execute)

    // unavailable-ownership — selectionkey-core (lane-scoped transpose
    // owns the key as a consumed no-op).
    expectDecision("transposeup-unavailable-ownsky", .transposeUp, unavailableNotes, .consume)
    expectDecision("cut-unmatched-declines", .cut, eventList, .decline)
    expectDecision("duplicate-unmatched-terminal", .duplicate, eventList, .consume)

    // gesture survival — selectionkey-gesture (drag guards shared
    // commands; pencil toggle survives).
    expectDecision("delete-gesture-consumes", .delete, gestureActive, .consume)
    expectDecision("pencilmode-gesture-executes", .pencilMode, gestureActive, .execute)

    // origin routing — selectionkey-local-input (event list keeps
    // row-local keys; grid commands stay timeline-owned).
    expectDecision("moveeventup-timeline-declines", .moveEventUp, eligible, .decline)
    expectDecision("gridnarrow-eventlist-declines", .gridNarrow, eventList, .decline)
    expectDecision("gridnarrow-timeline-executes", .gridNarrow, eligible, .execute)

    // prompt text ownership — selectionkey-local-input (text fields own
    // Copy; Solo still needs its song target).
    expectEnabled("copy-textfocused-enabled", .copy, textFocused: true, rowAvailable: false, true)
    expectEnabled("solo-textfocused-disabled", .soloTracks, textFocused: true, rowAvailable: false, false)
    expectEnabled("copy-unfocused-follows-row", .copy, textFocused: false, rowAvailable: false, false)

    // unbound-key neutrality — selectionkey-window (unrecognized key is
    // a terminal no-op): nil declines on every surface variant.
    expectDecision("unbound-eligiblerepeat-declines", nil, eligibleRepeat, .decline)
    expectDecision("unbound-unavailablenotes-declines", nil, unavailableNotes, .decline)
    expectDecision("unbound-eventlist-declines", nil, eventList, .decline)
    expectDecision("unbound-gesture-declines", nil, gestureActive, .decline)
    expectDecision("unbound-eligible-declines", nil, eligible, .decline)

    print("SWIFT_GRID_SMOKE policy-dimensions PASS")
}
