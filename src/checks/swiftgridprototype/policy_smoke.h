#pragma once

// Parity seam for the Swift EditCommandPolicy table port (spec §4): C ABI
// over the extracted production table (src/ui/songview/editcommandtable.cpp),
// imported by Swift through the NativeGridSmoke module. Swift drives, C++
// answers — no @_cdecl, no C++→Swift calls. Prefix sgp_ (sgm_ is the Wave-1
// math seam, sgc_ the curve seam; both stay frozen).

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct SGECommandPolicyRow { // one EditCommandPolicy, flat ints
    int32_t command;                 // SongView::EditCommand ordinal
    int32_t rangeOperation, notesOperation, standaloneOperation;
    int32_t keyRoute, originRule, autoRepeatRule;
    int32_t ownershipOnUnavailable, focusedTextOwnership;
    int32_t transposeSemitones, nudgeDelta, eventRowDelta;
    int32_t survivesPointerGesture; // 0/1
    int32_t terminalWhenUnmatched;  // 0/1
} SGECommandPolicyRow;

int32_t sgp_command_count(void); // 35
void sgp_policy_row(int32_t commandOrdinal, SGECommandPolicyRow *out);

#ifdef __cplusplus
} // extern "C"
#endif
