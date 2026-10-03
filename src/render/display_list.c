#include "display_list.h"

static int pd_dl_aligned(const void *p) {
    return ((uintptr_t)p & 7u) == 0;
}

static bool pd_dl_align8(size_t n, size_t *out) {
    if (n > SIZE_MAX - 7) return false;
    *out = (n + 7u) & ~(size_t)7u;
    return true;
}

/* Offsets are computed, never stored: every section follows the previous one
   at the next 8-byte boundary, so a bad count or a short buffer fails bounds. */
bool pd_dl_decode(const void *bytes, size_t length, PdDlView *out) {
    const uint8_t *base = (const uint8_t *)bytes;
    if (!base || !out || length < sizeof(PdDlHeader) || !pd_dl_aligned(base)) {
        return false;
    }
    const PdDlHeader *header = (const PdDlHeader *)base;
    if (header->magic != PD_DL_MAGIC || header->version != PD_DL_VERSION) {
        return false;
    }

    size_t fontsOff, rectOff, labelOff, textOff;
    if (!pd_dl_align8(sizeof(PdDlHeader), &fontsOff)) return false;
    if ((size_t)header->fontCount > (SIZE_MAX - fontsOff) / sizeof(PdDlFont)) {
        return false;
    }
    if (!pd_dl_align8(fontsOff + (size_t)header->fontCount * sizeof(PdDlFont), &rectOff)) {
        return false;
    }
    if ((size_t)header->rectCount > (SIZE_MAX - rectOff) / sizeof(PdDlRect)) {
        return false;
    }
    if (!pd_dl_align8(rectOff + (size_t)header->rectCount * sizeof(PdDlRect), &labelOff)) {
        return false;
    }
    if ((size_t)header->labelCount > (SIZE_MAX - labelOff) / sizeof(PdDlLabel)) {
        return false;
    }
    if (!pd_dl_align8(labelOff + (size_t)header->labelCount * sizeof(PdDlLabel), &textOff)) {
        return false;
    }
    if (textOff > length || (size_t)header->textBytes != length - textOff) {
        return false;
    }

    const PdDlFont *fonts = (const PdDlFont *)(base + fontsOff);
    const PdDlRect *rects = (const PdDlRect *)(base + rectOff);
    const PdDlLabel *labels = (const PdDlLabel *)(base + labelOff);
    const char *text = (const char *)(base + textOff);
    if (!pd_dl_aligned(fonts) || !pd_dl_aligned(rects) || !pd_dl_aligned(labels)
        || !pd_dl_aligned(text)) {
        return false;
    }

    for (uint32_t i = 0; i < header->fontCount; ++i) {
        const uint64_t familyEnd =
            (uint64_t)fonts[i].familyOffset + (uint64_t)fonts[i].familyLength;
        if (familyEnd > (uint64_t)header->textBytes) {
            return false;
        }
    }
    for (uint32_t i = 0; i < header->labelCount; ++i) {
        const uint64_t textEnd =
            (uint64_t)labels[i].textOffset + (uint64_t)labels[i].textLength;
        if (textEnd > (uint64_t)header->textBytes) {
            return false;
        }
    }
    for (uint32_t i = 0; i < header->rectCount; ++i) {
        if (rects[i].flags & (uint32_t)~PD_DL_RECT_OVER) {
            return false;
        }
    }
    for (uint32_t i = 0; i < header->labelCount; ++i) {
        if (labels[i].flags
            & (uint32_t)~(PD_DL_LABEL_CLIP | PD_DL_LABEL_ALIGN_MASK)) {
            return false;
        }
        uint32_t j = 0;
        while (j < header->fontCount && fonts[j].id != labels[i].fontId) {
            ++j;
        }
        if (j == header->fontCount) {
            return false;
        }
    }

    out->header = header;
    out->fonts = fonts;
    out->rects = rects;
    out->labels = labels;
    out->text = text;
    return true;
}
