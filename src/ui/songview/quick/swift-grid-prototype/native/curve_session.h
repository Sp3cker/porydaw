#pragma once

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct SGCurveSession SGCurveSession;

typedef struct {
    int64_t tick;
    int32_t value;
} SGCurveValue;

typedef struct {
    int32_t canvas_x, canvas_y, canvas_width, canvas_height;
    double zero_detent, node_hit_radius;
} SGCurveMetrics;

typedef struct {
    int64_t tick;
    int32_t value;
    double x, y;
} SGCurveVertex;

typedef struct {
    int64_t selected_tick;
    int64_t keyboard_tick;
    int32_t live_value;
    int has_gesture;
    int has_line_preview;
    double anchor_x, anchor_y, pointer_x, pointer_y;
} SGCurveState;

SGCurveSession *sgc_create(int modulation, int64_t start_tick, int64_t end_tick,
                           const SGCurveValue *points, size_t count, int end_value,
                           SGCurveMetrics metrics);
void sgc_destroy(SGCurveSession *session);
void sgc_set_metrics(SGCurveSession *session, SGCurveMetrics metrics);
size_t sgc_point_count(const SGCurveSession *session);
void sgc_copy_vertices(const SGCurveSession *session, SGCurveVertex *vertices);
// Caller must supply a buffer with capacity >= sgc_point_count(); returns the canonical
// point count (<= capacity). Canonical export drops redundant plateau interiors.
size_t sgc_copy_curve_points(const SGCurveSession *session, SGCurveValue *points);
uint32_t sgc_fine_ticks(const SGCurveSession *session);
SGCurveState sgc_state(const SGCurveSession *session);
void sgc_press(SGCurveSession *session, double x, double y, int line_gesture);
void sgc_move(SGCurveSession *session, double x, double y, int fine);
void sgc_release(SGCurveSession *session, double x, double y, int fine);
void sgc_cancel(SGCurveSession *session);
void sgc_reset(SGCurveSession *session);
void sgc_remove_selected(SGCurveSession *session);
void sgc_set_keyboard_fraction(SGCurveSession *session, double fraction);
int sgc_wheel_steps(SGCurveSession *session, double units);
double sgc_x_at_tick(const SGCurveSession *session, int64_t tick);
double sgc_y_at_value(const SGCurveSession *session, int value);
int64_t sgc_next_snap_tick(const SGCurveSession *session, int64_t tick);

#ifdef __cplusplus
}
#endif
