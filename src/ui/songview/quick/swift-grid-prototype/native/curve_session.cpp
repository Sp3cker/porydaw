#include "curve_session.h"

#include "ui/pitchbendkernel.h"

#include <map>

using namespace songview;

namespace {
PitchBendGeometry geometry(SGCurveMetrics metrics)
{
    PitchBendGeometry result;
    result.canvas = {metrics.canvas_x, metrics.canvas_y, metrics.canvas_width,
                     metrics.canvas_height};
    result.zeroDetent = metrics.zero_detent;
    result.nodeHitRadius = metrics.node_hit_radius;
    return result;
}

std::map<Tick, int> curveValues(const SGCurveValue *points, size_t count)
{
    std::map<Tick, int> result;
    for (size_t i = 0; i < count; ++i)
        result[Tick(points[i].tick)] = points[i].value;
    return result;
}

Grid fixedGrid(const TimeAxis &axis, const TimeCamera &camera)
{
    Grid result(axis, camera);
    result.setTicksPerClock(1);
    result.setSelection(GridSelection::musical(16));
    return result;
}
} // namespace

struct SGCurveSession {
    TimeAxis axis;
    PitchProjection projection;
    TimeCamera camera{axis, projection};
    Grid grid{fixedGrid(axis, camera)};
    PitchBendKernel kernel;

    SGCurveSession(bool modulation, Tick start, Tick end, const SGCurveValue *points, size_t count,
                   int endValue, SGCurveMetrics metrics)
        : kernel(modulation ? PitchBendKernel::Lane::ModWheel : PitchBendKernel::Lane::PitchBend,
                 grid, geometry(metrics), start, end, curveValues(points, count), endValue)
    {}
};

SGCurveSession *sgc_create(int modulation, int64_t start_tick, int64_t end_tick,
                           const SGCurveValue *points, size_t count, int end_value,
                           SGCurveMetrics metrics)
{
    return new SGCurveSession(modulation, Tick(start_tick), Tick(end_tick), points, count,
                              end_value, metrics);
}

void sgc_destroy(SGCurveSession *session)
{
    delete session;
}

void sgc_set_metrics(SGCurveSession *session, SGCurveMetrics metrics)
{
    session->kernel.setMetrics(geometry(metrics));
}

size_t sgc_point_count(const SGCurveSession *session)
{
    return session->kernel.points().size();
}

void sgc_copy_vertices(const SGCurveSession *session, SGCurveVertex *vertices)
{
    const auto &kernel = session->kernel;
    for (const auto &[tick, value] : kernel.points()) {
        const auto position = kernel.vertexPosition(tick, value);
        *vertices++ = {int64_t(tick), value, double(position.x()), double(position.y())};
    }
}

SGCurveState sgc_state(const SGCurveSession *session)
{
    const auto &kernel = session->kernel;
    SGCurveState result{};
    result.selected_tick = kernel.selectedTick() ? int64_t(*kernel.selectedTick()) : -1;
    result.keyboard_tick = kernel.keyboardTick();
    result.live_value = kernel.liveValue();
    result.has_gesture = kernel.hasGesture();
    if (const auto line = kernel.linePreview()) {
        result.has_line_preview = true;
        result.anchor_x = kernel.xAtTick(line->anchorTick);
        result.anchor_y = kernel.yAtValue(line->anchorValue);
        result.pointer_x = kernel.xAtTick(line->previousTick);
        result.pointer_y = kernel.yAtValue(line->previousValue);
    }
    return result;
}

void sgc_press(SGCurveSession *session, double x, double y, int line_gesture)
{
    auto &kernel = session->kernel;
    const QPointF position(x, y);
    if (const auto hit = kernel.hitTest(position))
        kernel.beginVertexDrag(hit->first);
    else
        kernel.beginStroke(position, line_gesture);
}

void sgc_move(SGCurveSession *session, double x, double y, int fine)
{
    session->kernel.updateGestureAt(QPointF(x, y), fine);
}

void sgc_release(SGCurveSession *session, double x, double y, int fine)
{
    session->kernel.updateGestureAt(QPointF(x, y), fine);
    session->kernel.endGesture();
}

void sgc_cancel(SGCurveSession *session)
{
    session->kernel.cancelGesture();
}

void sgc_reset(SGCurveSession *session)
{
    session->kernel.resetCurve();
}

void sgc_remove_selected(SGCurveSession *session)
{
    session->kernel.removeSelectedVertex();
}

void sgc_set_keyboard_fraction(SGCurveSession *session, double fraction)
{
    session->kernel.setKeyboardFraction(fraction);
}

int sgc_wheel_steps(SGCurveSession *session, double units)
{
    return session->kernel.accumulateWheel(units);
}

double sgc_x_at_tick(const SGCurveSession *session, int64_t tick)
{
    return session->kernel.xAtTick(Tick(tick));
}

double sgc_y_at_value(const SGCurveSession *session, int value)
{
    return session->kernel.yAtValue(value);
}

int64_t sgc_next_snap_tick(const SGCurveSession *session, int64_t tick)
{
    return session->kernel.nextSnapTickAfter(Tick(tick));
}
