#pragma once

#include "core/songdocument.h"

#include <QFocusEvent>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QPaintEvent>
#include <QPointF>
#include <QRect>
#include <QString>
#include <QWheelEvent>
#include <QWidget>
#include <cstdint>
#include <functional>
#include <map>
#include <optional>
#include <utility>
#include <vector>
class QPainter;
class SongView;

namespace songview {

class PitchBendGraph final : public QWidget
{
  public:
    enum class Lane { PitchBend, ModWheel };
    struct Callbacks {
        std::function<void()> previewChanged;
        std::function<void()> commitRequested;
        std::function<void()> cancelRequested;
        std::function<void(int)> rangeChangeRequested;
        std::function<void()> auditionRequested;
    };
    explicit PitchBendGraph(::SongView *songView, int engineTrack, uint64_t startTick,
                            uint64_t endTick, bool unterminated, Lane lane, QWidget *parent);

    void setCallbacks(Callbacks callbacks);
    void setBendRange(int range);
    void setCurve(const std::map<uint64_t, int> &points, int endValue);
    void resetCurve();
    std::optional<uint64_t> selectedTick() const;
    void setSelectedTick(std::optional<uint64_t> tick);
    std::optional<std::pair<uint64_t, int>> hitTest(const QPointF &position) const;
    bool removeSelectedVertex();
    QPoint vertexPosition(uint64_t tick, int value) const;
    void setKeyboardFraction(double fraction);
    void cancelGesture();
    bool handleKeyPress(QKeyEvent *event);

    QRect canvasRect() const;
    bool hasGesture() const;
    int liveValue() const;
    std::vector<SongDocument::LanePointValue> curvePoints() const;
    Lane lane() const;

  protected:
    void paintEvent(QPaintEvent *event) override;
    void mousePressEvent(QMouseEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;
    void mouseReleaseEvent(QMouseEvent *event) override;
    void wheelEvent(QWheelEvent *event) override;
    void keyPressEvent(QKeyEvent *event) override;
    void focusInEvent(QFocusEvent *event) override;
    void focusOutEvent(QFocusEvent *event) override;

  private:
    enum class StrokeMode { Freehand, AngledLine };
    enum class Sampling { Normal, Fine };

    struct StrokeState {
        StrokeMode mode = StrokeMode::Freehand;
        std::map<uint64_t, int> snapshot;
        uint64_t anchorTick = 0;
        int anchorValue = 0;
        uint64_t previousTick = 0;
        int previousValue = 0;
    };

    struct VertexDragState {
        std::map<uint64_t, int> snapshot;
        uint64_t originalTick = 0;
    };

    static constexpr int kAxisGutter = 52;
    static constexpr int kGraphTop = 44;
    static constexpr int kGraphWidth = 280;
    static constexpr int kGraphHeight = 112;
    static constexpr int kAxisLabelHeight = 20;
    static constexpr int kZeroDetentPixels = 8;
    static constexpr int kBendStep = 128;
    static constexpr int kNodeHitRadius = 8;
    static constexpr int kNodePaintRadius = 3;
    static constexpr int kSelectedNodeRingRadius = 6;

    void paintGrid(QPainter &painter);
    void paintCurve(QPainter &painter);
    void paintLinePreview(QPainter &painter);
    void paintAxes(QPainter &painter);
    void paintFocus(QPainter &painter);
    void notifyPreviewChanged();
    void notifyCommitRequested();
    void notifyCancelRequested();
    void notifyAuditionRequested();
    void updateStroke(const QPointF &position);
    void updateVertexDrag(const QPointF &position, Qt::KeyboardModifiers modifiers = {});
    void finishGesture();
    void replaceSegment(uint64_t tick0, int value0, uint64_t tick1, int value1, Sampling sampling);
    bool isLineGesture() const;
    Sampling gestureSampling() const;
    uint64_t normalCellTicksAt(uint64_t tick) const;
    uint64_t samplingCellTicksAt(uint64_t tick, Sampling sampling) const;
    uint64_t nextSampleTick(uint64_t tick, Sampling sampling) const;
    uint64_t lastEditableTick(Sampling sampling) const;
    uint64_t tickAtFraction(double fraction, Sampling sampling) const;
    uint64_t tickAtX(qreal x, Sampling sampling) const;
    int xAtTick(uint64_t tick) const;
    int valueAtY(qreal y) const;
    int yAtValue(int value) const;
    int valueAtTick(uint64_t tick) const;
    int minimumValue() const;
    int maximumValue() const;
    int defaultValue() const;
    QString laneTitle() const;
    QString formatLiveValue() const;
    QString formatRangeLimit(bool positive) const;

    ::SongView *m_songView = nullptr;
    int m_engineTrack = -1;
    uint64_t m_startTick = 0;
    uint64_t m_endTick = 0;
    bool m_unterminated = false;
    int m_bendRange = 2;
    int m_endValue = 0;
    Lane m_lane = Lane::PitchBend;
    std::map<uint64_t, int> m_points;
    uint64_t m_keyboardTick = 0;
    int m_liveValue = 0;
    double m_rangeWheelRemainder = 0.0;
    std::optional<StrokeState> m_strokeState;
    std::optional<VertexDragState> m_vertexDragState;
    std::optional<uint64_t> m_selectedTick;
    Callbacks m_callbacks;
};
} // namespace songview
