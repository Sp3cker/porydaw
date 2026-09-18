#pragma once

#include "ui/pitchbendgeometry.h"
#include "ui/songview/grid.h"

#include <QPoint>
#include <QPointF>
#include <QRect>
#include <QtGlobal>

#include <cstdint>
#include <map>
#include <optional>
#include <utility>

namespace songview {

// The borrowed grid must outlive the kernel.
class PitchBendKernel
{
  public:
    enum class Lane { PitchBend, ModWheel };

    struct LinePreview {
        Tick anchorTick = 0;
        int anchorValue = 0;
        Tick previousTick = 0;
        int previousValue = 0;
    };

    PitchBendKernel(Lane lane, const Grid &grid, PitchBendGeometry geometry, Tick startTick,
                    Tick endTick, std::map<Tick, int> points, int endValue);

    void setMetrics(const PitchBendGeometry &geometry);
    const PitchBendGeometry &geometry() const { return m_geometry; }
    QRect canvasRect() const { return m_geometry.canvas; }

    void setCurve(const std::map<Tick, int> &points, int endValue);
    void resetCurve();

    const std::map<Tick, int> &points() const { return m_points; }
    Tick startTick() const { return m_startTick; }
    Tick endTick() const { return m_endTick; }
    Lane lane() const { return m_lane; }
    int endValue() const { return m_endValue; }
    int minimumValue() const;
    int maximumValue() const;
    int defaultValue() const;

    std::optional<Tick> selectedTick() const { return m_selectedTick; }
    // False when the visible selection is unchanged.
    bool setSelectedTick(std::optional<Tick> tick);
    bool removeSelectedVertex();

    void setKeyboardFraction(double fraction);
    Tick keyboardTick() const { return m_keyboardTick; }
    int liveValue() const { return m_liveValue; }

    std::optional<std::pair<Tick, int>> hitTest(const QPointF &position) const;
    QPoint vertexPosition(Tick tick, int value) const;
    int xAtTick(Tick tick) const;
    int yAtValue(int value) const;
    int valueAtY(qreal y) const;
    int valueAtTick(Tick tick) const;

    // Narrow grid gateway for the production renderer.
    Tick nextSnapTickAfter(Tick tick) const;
    Tick segmentStartAt(Tick tick) const;
    uint32_t fineGridTicks() const;
    template <typename Visitor>
    void forEachCurvePoint(Visitor &&visit) const
    {
        const Tick fineTick(fineGridTicks());
        auto previous = m_points.end();
        for (auto point = m_points.begin(); point != m_points.end(); ++point) {
            const auto &[tick, value] = *point;
            bool keep = previous == m_points.end() || tick == m_startTick || tick == m_endTick ||
                        value != previous->second;
            if (!keep) {
                auto next = point;
                if (++next != m_points.end() && next->first - tick == fineTick &&
                    next->second != value)
                    keep = true;
            }
            if (keep)
                visit(tick, value);
            previous = point;
        }
    }

    // Semantic gesture operations. beginStroke clears any selection and opens
    // a freehand or straight-line stroke at the event position; beginVertexDrag
    // pins the existing vertex under the press. Updates return whether a
    // gesture was active. endGesture keeps the preview; cancelGesture restores
    // the pre-gesture snapshot. The host owns every redraw/notification tail.
    void beginStroke(const QPointF &position, bool lineGesture);
    bool beginVertexDrag(Tick tick);
    bool updateStroke(const QPointF &position);
    bool updateVertexDrag(const QPointF &position, bool fine);
    // Updates whichever gesture is active (vertex drag takes precedence);
    // false when gesture-free.
    bool updateGestureAt(const QPointF &position, bool fine);
    void endGesture();
    void cancelGesture();
    bool hasGesture() const { return m_strokeState || m_vertexDragState; }
    std::optional<LinePreview> linePreview() const;

    // Wheel-range accumulation in scroll units; returns whole 120-unit steps
    // for the host to forward as rangeChangeRequested.
    int accumulateWheel(double units);

  private:
    enum class Sampling { Normal, Fine };
    enum class StrokeMode { Freehand, AngledLine };

    struct StrokeState {
        StrokeMode mode = StrokeMode::Freehand;
        std::map<Tick, int> snapshot;
        Tick initialKeyboardTick = 0;
        Tick anchorTick = 0;
        int anchorValue = 0;
        Tick previousTick = 0;
        int previousValue = 0;
    };

    struct VertexDragState {
        std::map<Tick, int> snapshot;
        Tick originalTick = 0;
    };

    static constexpr int kBendStep = 128;

    bool isLineGesture() const;
    Sampling gestureSampling() const;
    Tick nextSampleTick(Tick tick, Sampling sampling) const;
    Tick lastEditableTick(Sampling sampling) const;
    Tick tickAtFraction(double fraction, Sampling sampling) const;
    Tick tickAtX(qreal x, Sampling sampling) const;
    void replaceSegment(Tick tick0, int value0, Tick tick1, int value1, Sampling sampling);

    Lane m_lane = Lane::PitchBend;
    const Grid *m_grid = nullptr; // Required, borrowed; must outlive the kernel.
    PitchBendGeometry m_geometry;
    Tick m_startTick = 0;
    Tick m_endTick = 0;
    std::map<Tick, int> m_points;
    int m_endValue = 0;
    Tick m_keyboardTick = 0;
    int m_liveValue = 0;
    double m_wheelRemainder = 0.0;
    std::optional<StrokeState> m_strokeState;
    std::optional<VertexDragState> m_vertexDragState;
    std::optional<Tick> m_selectedTick;
};

} // namespace songview
