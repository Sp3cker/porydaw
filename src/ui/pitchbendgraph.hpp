#pragma once

#include "core/songdocument.h"
#include "pitchbendkernel.h"
#include "ui/mousehints/hintprofiles.h"
#include "ui/songview/quick/timelinequicklayer.h"
#include <QCursor>
#include <QPointF>
#include <QPointer>
#include <QQuickItem>
#include <QRect>
#include <QString>
#include <QtQmlIntegration/qqmlintegration.h>
#include <cstdint>
#include <functional>
#include <map>
#include <optional>
#include <utility>
#include <vector>

class QFocusEvent;
class QHoverEvent;
class QKeyEvent;
class QMouseEvent;
class QSGNode;
class QWheelEvent;
class SongView;

namespace ui {
class MouseHints;
}

namespace songview {

// One editable lane of the note-automation popup. A QQuickItem whose curve,
// gesture, sampling, collision, and wheel algorithms stay in C++ with exact
// Tick tick precision; QML owns only the labels around the canvas. The
// retained scene-graph layer is rebuilt on the GUI thread and synchronized on
// the render thread through timeline_quick::syncLayerNode (see
// pitchbendgraph_render.cpp). Not final: QML registration instantiates the
// type through QQmlElement<T>.
class PitchBendGraph : public QQuickItem
{
    Q_OBJECT
    QML_ELEMENT
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
        Tick startTick = 0;
        Tick endTick = 0;
        bool unterminated = false;
        Lane lane = Lane::PitchBend;
        PitchBendGeometry geometry;
        int bendRange = 2;
        std::map<Tick, int> points;
        int endValue = 0;
        Callbacks callbacks;
    };

    explicit PitchBendGraph(QQuickItem *parent = nullptr);

    // Establishes all dependencies and initial state before rendering, input,
    // or property notifications are enabled.
    void initialize(Initialization initial);
    void setMetrics(const PitchBendGeometry &geometry);

    void setBendRange(int range);
    void setCurve(const std::map<Tick, int> &points, int endValue);
    void resetCurve();
    std::optional<Tick> selectedTick() const;
    void setSelectedTick(std::optional<Tick> tick);
    std::optional<std::pair<Tick, int>> hitTest(const QPointF &position) const;
    bool removeSelectedVertex();
    QPoint vertexPosition(Tick tick, int value) const;
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
    void hoverEnterEvent(QHoverEvent *event) override;
    void hoverMoveEvent(QHoverEvent *event) override;
    void hoverLeaveEvent(QHoverEvent *event) override;
    void mouseUngrabEvent() override;
    void itemChange(ItemChange change, const ItemChangeData &data) override;

  private:
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
    void finishGesture();
    QString formatLiveValue() const;
    QString formatRangeLimit(bool positive) const;
    static PitchBendKernel::Lane toKernelLane(Lane lane);
    static Lane fromKernelLane(PitchBendKernel::Lane lane);
    // Mouse-hint presentation: this item is its own physical Quick source.
    // The service borrow is lazy and QPointer-guarded so teardown never
    // recreates it.
    ui::MouseHints *mouseHints() const;
    // Source-check clear; only the current owner clears.
    void clearMouseHint();
    // True while this item is a live hover or exclusive-grab hint source.
    bool hintSourceActive() const;
    // The profile ID for an item-local position. Background and interior
    // vertices have distinct profiles; pinned endpoints and margins select Empty.
    ui::hint_profiles::Id hintProfileAt(const QPointF &position) const;
    // Claims the profile at `position` while this item is a live source;
    // also records it as the gesture's originating profile.
    void publishMouseHintAt(const QPointF &position);
    // Idle recompute at the actual cursor position: only a still-hovered,
    // gesture-free graph republishes; a cursor that left the item clears.
    void refreshIdleMouseHint();
    // One hover-pass entry point: an active gesture republishes its
    // originating profile, an idle pass classifies and claims at position.
    void updateMouseHint(const QPointF &position);
    // Gesture-end settle by actual position: inside keeps/refreshes the
    // current target, outside clears. Release passes its event position;
    // ungrab and programmatic cancel use the live cursor.
    void settleMouseHintAt(const QPointF &position);
    void settleMouseHintAtCursor();

    int m_engineTrack = -1;
    bool m_unterminated = false;
    int m_bendRange = 2;
    Callbacks m_callbacks;
    // Canonical curve/gesture/sampling state. Empty until initialize()
    // supplies the grid, span, and document snapshot; the kernel itself is
    // always fully constructed once present.
    std::optional<PitchBendKernel> m_kernel;
    TimelineQuickLayerData m_layer;
    mutable QPointer<ui::MouseHints> m_mouseHints;
    // Originating profile retained for the whole gesture.
    ui::hint_profiles::Id m_gestureProfile = ui::hint_profiles::Id::Empty;
    bool m_hovered = false;
};

} // namespace songview
