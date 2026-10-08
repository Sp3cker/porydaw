#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PD_DL_MAGIC   0x314C4450u        /* "PDL1" little-endian */
#define PD_DL_VERSION 2u

typedef struct {
    uint32_t magic, version;
    uint32_t fontCount, rectCount, labelCount, textBytes;
} PdDlHeader;                            /* 24 B; followed by fonts, rects, labels, text — each array
                                            starts on an 8-byte boundary (writer pads, decoder checks) */

typedef struct {                         /* 24 B */
    uint32_t id;                         /* PD_DL_FONT_* slot the labels reference */
    int32_t  weight;
    double   letterSpacing;
    uint32_t familyOffset, familyLength; /* UTF-8 in the text block */
} PdDlFont;

typedef struct {                         /* 56 B; viewport logical px, already snapped; w,h > 0 */
    double   x, y, w, h;
    uint64_t id;                         /* PD_DL_ID_NONE, a note id, or a PD_DL_ID_* reserved id */
    uint32_t argb, argbRight;            /* left/right edge colours, interpolated across w;
                                            equal for a solid fill */
    uint32_t flags;                      /* PD_DL_RECT_OVER: paint above this list's labels */
    uint32_t reserved;                   /* zero */
} PdDlRect;

typedef struct {                         /* 64 B; viewport logical px; text laid out in (w,h) */
    double   x, y, w, h;
    uint64_t id;
    uint32_t textOffset, textLength;     /* UTF-8 in the text block */
    uint32_t argb, flags;                /* PD_DL_LABEL_CLIP | PD_DL_LABEL_ALIGN_{LEFT,RIGHT,CENTER} */
    uint32_t fontId, pixelSize;          /* pixelSize is the fitted size Swift decided */
} PdDlLabel;

enum { PD_DL_RECT_OVER = 1u };
enum { PD_DL_LABEL_CLIP = 1u, PD_DL_LABEL_ALIGN_LEFT = 0u, PD_DL_LABEL_ALIGN_RIGHT = 2u,
       PD_DL_LABEL_ALIGN_CENTER = 4u, PD_DL_LABEL_ALIGN_MASK = 6u };

/* Reserved ids are exported to QML as double: keep them double-exact (< 2^53). */
enum { PD_DL_ID_NONE = 0, PD_DL_ID_LOOP_START = 0x0010000000000001ull,
       PD_DL_ID_LOOP_END = 0x0010000000000002ull };

typedef struct {
    const PdDlHeader *header; const PdDlFont *fonts; const PdDlRect *rects;
    const PdDlLabel *labels; const char *text;
} PdDlView;

bool pd_dl_decode(const void *bytes, size_t length, PdDlView *out);  /* false on any inconsistency */

#ifdef __cplusplus
}
#endif
