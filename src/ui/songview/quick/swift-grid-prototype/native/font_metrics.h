#pragma once

#ifdef __cplusplus
extern "C" {
#endif

typedef struct SGFontMetrics SGFontMetrics;
typedef struct {
    double ascent;
    double height;
} SGFontExtents;

SGFontMetrics *sgf_create(const char *family, int pixel_size, int weight, double letter_spacing);
void sgf_destroy(SGFontMetrics *metrics);
SGFontExtents sgf_extents(const SGFontMetrics *metrics);
double sgf_advance(const SGFontMetrics *metrics, const char *text);
int sgf_fit(const SGFontMetrics *metrics, double row_height);

#ifdef __cplusplus
}
#endif
