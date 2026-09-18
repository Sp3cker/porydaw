import Foundation
import NativeGridSmoke

// Wave-2 policy selftest driver (spec §4, §6.3). Task 3 asserts the
// policy-table-parity sweep: every command, every field, Swift ==
// production through sgp_*. Task 4 appends the policy-dimensions matrix
// here. Called from App.init after runMathSelftestIfRequested so a
// mismatch fails fast, before any window opens. A FAIL exits nonzero; the
// final `SWIFT_GRID_SMOKE PASS` line still comes from the C++ exercise().

/// No-op unless PORYDAW_SWIFT_GRID_SMOKE == "1".
func runPolicySelftestIfRequested() {
    guard ProcessInfo.processInfo.environment["PORYDAW_SWIFT_GRID_SMOKE"] == "1" else {
        return
    }
    runPolicyTableParitySweep()
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
