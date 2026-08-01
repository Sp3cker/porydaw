#pragma once

#include <cstdint>
#include <vector>

#include "ui/editorviewstate.h"
#include "ui/timelinesurface.h"

class AutomationPage;
class QEvent;
class QKeyEvent;
class QPainter;
class QScrollArea;
class QTimer;
class QWheelEvent;
class QMouseEvent;
struct AutoLane;
struct LanePoint;

struct AutomationRow {
    EditorAutomationRowId id;
};

// AutomationArea is the paint and input surface owned by AutomationPage.
// Temporary gesture state stays local to this canvas; song data and routing
// are obtained from the page's stable SongView owner.
class AutomationArea final : public songview::TimelineSurface
{
  public:
    explicit AutomationArea(AutomationPage *page, QScrollArea *scroll);

    const std::vector<AutomationRow> &rows() const noexcept { return m_rows; }
    void rebuildRows();
    void cancelInteraction();

  protected:
    bool event(QEvent *event) override;
    void paintContent(QPainter &painter) override;
    void wheelEvent(QWheelEvent *event) override;
    void mousePressEvent(QMouseEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;
    void mouseReleaseEvent(QMouseEvent *event) override;
    void mouseDoubleClickEvent(QMouseEvent *event) override;
    void keyPressEvent(QKeyEvent *event) override;
    void leaveEvent(QEvent *event) override;

  private:
    enum class Gesture : uint8_t { None, Point, Sweep, Ramp };
    struct DragPoint {
        uint64_t tick = 0;
        int value = 0;
    };
    struct PendingSweep {
        int track = -1;
        uint8_t controller = 0;
        std::vector<DragPoint> points;
    };
    struct TimeSelection {
        uint64_t startTick = 0;
        uint64_t endTick = 0;
        int firstRow = -1;
        int lastRow = -1;

        bool active() const noexcept { return startTick < endTick && firstRow >= 0; }
    };

    int rowHeight(const AutomationRow &row) const;
    int rowTop(int index) const;
    int rowIndexAt(int y) const;
    int rowBoundaryAt(int y) const;
    int valueAtY(int rowIndex, int y) const;
    int rowMinimum(const AutomationRow &row) const;
    bool deletePointNear(const AutomationRow &row, qreal x);
    int rowMaximum(const AutomationRow &row) const;
    double rawTickAt(qreal x) const;
    const AutoLane *laneFor(const AutomationRow &row) const;
    const std::vector<LanePoint> *pointsFor(const AutomationRow &row) const;
    QString titleFor(const AutomationRow &row) const;
    QString voiceShortName(int program) const;
    QString valueTextFor(const AutomationRow &row, int value) const;
    bool rowTarget(const AutomationRow &row, int *track, uint8_t *controller) const;
    std::pair<int, uint8_t> rowIdentity(const AutomationRow &row) const;
    void applyHeight();
    void updateHover(qreal x, int y);
    QString hoverTextFor(const AutomationRow &row, double tick, qreal x) const;
    QRect hoverPaintBounds(int rowIndex, double tick) const;
    void clearHover();
    void updateDrag(qreal x, int y, bool fineMode, bool detent);
    void extendSweep(qreal x, bool fineMode);
    void commitDrag(bool fineMode);
    void queuePendingSweep(int track, uint8_t controller);
    void commitPendingSweeps();
    void clearTimeSelection();
    bool selectionContains(int rowIndex, qreal x) const;
    void showTimeSelectionMenu(const QPoint &globalPosition);
    void showAddLaneMenu(const QPoint &globalPosition);
    void showLaneMenu(const AutomationRow &row, const QPoint &globalPosition);
    void showVoiceMenu(const AutomationRow &row, const QPoint &globalPosition);
    void paintRow(QPainter &painter, const AutomationRow &row, int rowIndex, const QRect &bounds);
    void paintHover(QPainter &painter, const AutomationRow &row, int rowIndex, const QRect &plot);
    void paintCurve(QPainter &painter, const QRect &plot,
                    const std::vector<LanePoint> &points, int minimum, int maximum,
                    const QColor &color);
    void paintVoiceRow(QPainter &painter, const QRect &plot);
    void setGestureActive(bool active);

    AutomationPage *m_page = nullptr;
    QScrollArea *m_scroll = nullptr;
    std::vector<AutomationRow> m_rows;
    int m_resizeRow = -1;
    int m_resizeStartHeight = 0;
    int m_resizeStartY = 0;
    int m_wheelRemainder = 0;
    bool m_panning = false;
    QPointF m_panPosition;
    bool m_rightPending = false;
    bool m_bandActive = false;
    uint64_t m_bandEndTick = 0;
    std::vector<DragPoint> m_clipboard;
    QPoint m_rightStart;
    int m_rightRow = -1;
    uint64_t m_bandStartTick = 0;
    int m_bandEndRow = -1;
    TimeSelection m_timeSelection;
    Gesture m_gesture = Gesture::None;
    int m_dragRow = -1;
    int64_t m_originalTick = -1;
    DragPoint m_drag;
    DragPoint m_rampStart;
    std::vector<DragPoint> m_sweep;
    std::vector<PendingSweep> m_pendingSweeps;
    QTimer *m_pendingTimer = nullptr;
    double m_previousRawTick = 0.0;
    int m_previousValue = 0;
    int m_hoverRow = -1;
    double m_hoverTick = 0.0;
};
