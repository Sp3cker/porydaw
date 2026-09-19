#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Exercises the Swift submission API against the executor registered for
// document_id. Returns 0 on success, otherwise the first failing step.
int32_t sgc_check_swift_submission(uint64_t document_id);

#ifdef __cplusplus
}
#endif
