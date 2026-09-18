#include "policy_smoke.h"

#include "ui/songview/editactions.h"

// Thin conversion over the extracted production table (spec §4): the C ABI
// answers what songview::editCommandPolicy returns — no logic, no second
// table. editcommandtable.cpp is compiled into this same target, so the
// parity sweep reads the exact production rows.

int32_t sgp_command_count(void)
{
    return static_cast<int32_t>(SongView::EditCommand::GridTriplet) + 1;
}

void sgp_policy_row(int32_t commandOrdinal, SGECommandPolicyRow *out)
{
    const songview::EditCommandPolicy &policy =
        songview::editCommandPolicy(static_cast<SongView::EditCommand>(commandOrdinal));
    out->command = commandOrdinal;
    out->rangeOperation = static_cast<int32_t>(policy.rangeOperation);
    out->notesOperation = static_cast<int32_t>(policy.notesOperation);
    out->standaloneOperation = static_cast<int32_t>(policy.standaloneOperation);
    out->keyRoute = static_cast<int32_t>(policy.keyRoute);
    out->originRule = static_cast<int32_t>(policy.originRule);
    out->autoRepeatRule = static_cast<int32_t>(policy.autoRepeatRule);
    out->ownershipOnUnavailable = static_cast<int32_t>(policy.ownershipOnUnavailable);
    out->focusedTextOwnership = static_cast<int32_t>(policy.focusedTextOwnership);
    out->transposeSemitones = policy.transposeSemitones;
    out->nudgeDelta = policy.nudgeDelta;
    out->eventRowDelta = policy.eventRowDelta;
    out->survivesPointerGesture = policy.survivesPointerGesture ? 1 : 0;
    out->terminalWhenUnmatched = policy.terminalWhenUnmatched ? 1 : 0;
}
