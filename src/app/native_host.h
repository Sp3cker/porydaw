#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*PdConsumeBytesCallback)(void *context, const uint8_t *bytes, size_t count);

bool pd_clipboard_write(const uint8_t *bytes, size_t count);
bool pd_clipboard_read(void *context, PdConsumeBytesCallback consume);

#ifdef __cplusplus
}
#endif
