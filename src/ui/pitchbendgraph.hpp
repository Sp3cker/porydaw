#pragma once

#include "core/songdocument.h"
#include "ui/songview/quick/timelinequicklayer.h"

#include <QCursor>
#include <QPointF>
#include <QQuickItem>
#include <QRect>
#include <QSize>
#include <QString>
#include <cstdint>
#include <functional>
#include <map>
#include <optional>
#include <utility>
#include <vector>

class QFocusEvent;
class QKeyEvent;
class QMouseEvent;
class QSGNode;
class QWheelEvent;
class SongView;

namespace songview {

class Grid;

// One geometry authority for the pitch/modulation popup. resolve() derives
// every value from typography and layout primitives (never raw pixel
// literals); the session resolves it once, injects it into each graph's
// initial state, and applies later changes through setMetrics so C++ hit-testing,
// projection, and rendering agree with the QML labels.
struct PitchBendGeometry {
    static PitchBendGeometry resolve(const QFont &font, qreal dpr);

    QSize popupSize;
    int headerHeight = 0;
    int graphHeight = 0;
    int outerInset = 0;
    int titleHeight = 0;
    int descriptionHeight = 0;
    int controlsHeight = 0;
    int fieldWidth = 0;
    int fieldHeight = 0;
    int resetWidth = 0;
    int resetHeight = 0;
    int axisLabelHeight = 0;
    QRect canvas; // Graph-local canvas rectangle; labels align around it.
    qreal zeroDetent = 0.0;
    qreal nodeHitRadius = 0.0;
    qreal nodePaintRadius = 0.0;
    qreal selectedRingRadius = 0.0;
    qreal curveStroke = 0.0;
    qreal scrubThreshold = 0.0;
    qreal hairline = 0.0;
};

// One editable lane of the note-automation popup. A QQuickItem whose curve,
// gesture, sampling, collision, and wheel algorithms stay in C++ with exact
// uint64_t tick precision; QML owns only the labels around the canvas. The
// retained scene-graph layer is rebuilt on the GUI thread and synchronized on
// the render thread through timeline_quick::syncLayerNode (see
// pitchbendgraph_render.cpp). Not final: QML registration instantiates the
// type through QQmlElement<T>.
class PitchBendGraph : public QQuickItem
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(PitchBendGraph)

    Q_PROPERTY(QString laneTitle READ laneTitle NOTIFY presentationChanged FINAL)
    Q_PROPERTY(QString liveValueText READ liveValueText NOTIFY liveValueChanged FINAL)
    Q_PROPERTY(QString upperValueText READ upperValueText NOTIFY presentationChanged FINAL)
    Q_PROPERTY(QString lowerValueText READ lowerValueText NOTIFY presentationChanged FINAL)
    Q_PROPERTY(QString endLabel READ endLabel NOTIFY presentationChanged FINAL)
    Q_PROPERTY(bool bipolar READ bipolar NOTIFY presentationChanged FINAL)
    Q_PROPERTY(QRect canvasRect READ canvasRect NOTIFY presentationChanged FINAL)

  public:
    enum class Lane { PitchBend, ModWheel };
    Q_ENUM(Lane)
    struct Callbacks {
        std::function<void()> previewChanged;
        std::function<void()> commitRequested;
        std::function<void()> cancelRequested; // Escape close.
        std::function<void(int)> rangeChangeRequested;
        std::function<void()> auditionRequested;
        // Unexpected grab loss commits the pending preview while open.
        // Dismissal settles by its own action before releasing the grab.
        std::function<void()> grabLost;
    };

    struct Initialization {
        ::SongView *songView = nullptr;
        int engineTrack = -1;
        uint64_t startTick = 0;
        uint64_t endTick = 0;
        bool unterminated = false;
        Lane lane = Lane::PitchBend;
        PitchBendGeometry geometry;
        int bendRange = 2;
        std::map<uint64_t, int> points;
        int endValue = 0;
        Callbacks callbacks;
    };

    explicit PitchBendGraph(QQuickItem *parent = nullptr);

    // Establishes all dependencies and initial state before rendering, input,
    // or property notifications are enabled.
    void initialize(Initialization initial);
    void setMetrics(const PitchBendGeometry &geometry);

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

    // Read-only presentation values backing the QML labels.
    QString laneTitle() const;
    QString liveValueText() const;
    QString upperValueText() const;
    QString lowerValueText() const;
    QString endLabel() const;
    bool bipolar() const;

  signals:
    void presentationChanged();
    void liveValueChanged();

  protected:
    QSGNode *updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *data) override;
    void mousePressEvent(QMouseEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;
    void mouseReleaseEvent(QMouseEvent *event) override;
    void wheelEvent(QWheelEvent *event) override;
    void keyPressEvent(QKeyEvent *event) override;
    void focusInEvent(QFocusEvent *event) override;
    void focusOutEvent(QFocusEvent *event) override;
    void mouseUngrabEvent() override;

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

    // redraw() rebuilds the retained layer and schedules a scene-graph sync.
    void redraw();
    void notifyPresentationChanged();
    void notifyLiveValueChanged();
    // Retained-layer rebuild (grid, curve, nodes, preview, focus frame);
    // implemented in pitchbendgraph_render.cpp.
    void rebuildLayer();
    void buildGrid(const QRectF &plot);
    void buildCurve(const QRectF &plot);
    void buildLinePreview(const QRectF &plot);
    void buildFocusFrame();

    void notifyPreviewChanged();
    void notifyCommitRequested();
    void notifyCancelRequested();
    void notifyAuditionRequested();
    void notifyGrabLost();
    void updateStroke(const QPointF &position);
    void updateVertexDrag(const QPointF &position, Qt::KeyboardModifiers modifiers = {});
    void finishGesture();
    void replaceSegment(uint64_t tick0, int value0, uint64_t tick1, int value1, Sampling sampling);
    bool isLineGesture() const;
    Sampling gestureSampling() const;
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
    QString formatLiveValue() const;
    QString formatRangeLimit(bool positive) const;

    static constexpr int kBendStep = 128;

    bool m_initialized = false;
    ::SongView *m_songView = nullptr;
    const songview::Grid *m_grid = nullptr;
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
    PitchBendGeometry m_geometry;
    TimelineQuickLayerData m_layer;
};
} // namespace songview
