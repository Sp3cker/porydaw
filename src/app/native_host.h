#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*PdConsumeBytesCallback)(void *context, const uint8_t *bytes, size_t count);
typedef void (*PdClipboardChangedCallback)(void *context);

bool pd_clipboard_write(const uint8_t *bytes, size_t count);
bool pd_clipboard_read(void *context, PdConsumeBytesCallback consume);
void *pd_clipboard_observe(void *context, PdClipboardChangedCallback changed);
void pd_clipboard_unobserve(void *token);

#ifdef __cplusplus
}
#endif
