#pragma once

#include "ui/songviewautomationarea.hpp"

#include <QHash>
#include <QPoint>
#include <QRect>
#include <QString>
#include <QWidget>

#include <cstdint>
#include <utility>
#include <vector>

#include "core/songdocument.h"
#include "ui/songviewmodel.h"

class QColor;
class QAction;
class QEvent;
class QKeyEvent;
class QMouseEvent;
class QPaintEvent;
class QPainter;
class QScrollArea;
class QWheelEvent;

namespace songview {

class AutomationArea::State final : public QWidget
{
public:
    State(AutomationArea *area, SongView *songView, QScrollArea *scroll);

    int laneHeight() const;
    const QHash<QString, int> &rowHeightOverrides() const;
    bool gestureActive() const;
    void setViewHeights(int laneHeight, const QHash<QString, int> &overrides);
    void rebuildRows();
    void showTimeSelectionContextMenu(const QPoint &globalPosition);

protected:
    void paintEvent(QPaintEvent *event) override;
    void wheelEvent(QWheelEvent *event) override;
    void mousePressEvent(QMouseEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;
    void mouseReleaseEvent(QMouseEvent *event) override;
    void mouseDoubleClickEvent(QMouseEvent *event) override;
    void keyPressEvent(QKeyEvent *event) override;
    void leaveEvent(QEvent *event) override;

private:
    struct TimeRangeActions {
        QAction *copy = nullptr;
        QAction *cut = nullptr;
        QAction *deleteRange = nullptr;
        QAction *removeContents = nullptr;
        QAction *paste = nullptr;
        QAction *clear = nullptr;
        QAction *nudgeLeft = nullptr;
        QAction *nudgeRight = nullptr;
        QAction *transposeUp = nullptr;
        QAction *transposeDown = nullptr;
        QAction *transposeUpOctave = nullptr;
        QAction *transposeDownOctave = nullptr;
        QAction *shortenNotes = nullptr;
        QAction *lengthenNotes = nullptr;
        QAction *decreaseVelocity = nullptr;
        QAction *increaseVelocity = nullptr;
    };

    struct Row {
        enum Kind { Tempo, Voice, Lane } kind;
        const AutoLane *lane;
    };

    enum class Gesture { None, Point, Sweep, Line };

    void createTimeRangeActions();
    bool canEditTimeRange() const;
    bool canPasteTimeRange() const;
    void showTimeRangeMenu(const QPoint &globalPosition);
    void showAddLaneMenu(const QPoint &globalPosition);
    void showLaneMenu(const AutoLane &lane, const QPoint &globalPosition);
    std::pair<int, uint8_t> rowIdentity(const Row &row) const;
    void updateSelSweep(QMouseEvent *event);
    void rightClickInPlace(QMouseEvent *event);
    bool voiceChangeNear(int x, DocLanePoint *out) const;

    QString rowKey(const Row &row) const;
    int rowHeight(const Row &row) const;
    int rowTop(int index) const;
    int rowBottom(int index) const;
    int rowIndexAt(int y) const;
    int rowBoundaryAt(int y) const;
    QRect addLaneRect() const;
    void applyHeight();
    void zoomLaneHeight(int wheelDelta, int anchorY);

    void voiceRowPress(QMouseEvent *event);
    bool rowTarget(const Row &row, uint8_t *cc, int *track) const;
    const std::vector<LanePoint> *rowPoints(const Row &row) const;
    void rowRange(const Row &row, int *minValue, int *maxValue) const;
    QString rowTitle(const Row &row) const;
    QString formatRowValue(const Row &row, int value) const;
    bool rowDetent(const Row &row, int *value) const;
    bool editValue(const Row &row, int *value);
    const LanePoint *nearestPoint(const Row &row, int x) const;
    const LanePoint *grabPoint(const Row &row, int rowIndex, QPoint position) const;
    double rawTickAt(int x) const;
    void updateHover(QPoint position);
    void clearHover();
    int valueAtY(const Row &row, int rowIndex, int yPosition) const;
    void updateDrag(QPoint position, bool fine, bool detent);
    void extendSweep(QPoint position, bool fine);
    void sweepUpsert(uint64_t tick, int value);
    std::vector<SongDocument::LanePointValue> sweepPoints() const;

    void paintHoverReadout(QPainter &painter);
    void paintRow(QPainter &painter, const Row &row, const QRect &rect);
    void paintCurve(QPainter &painter, const QRect &plot,
                    const std::vector<LanePoint> &points, int minValue, int maxValue,
                    const QColor &color, bool centerLine);
    void paintVoiceRow(QPainter &painter, const QRect &plot);

    AutomationArea *m_area;
    SongView *m_sv;
    QScrollArea *m_scroll;
    std::vector<Row> m_rows;
    int m_laneH = 48;
    int m_laneZoomAccum = 0;
    QHash<QString, int> m_rowHeights;
    int m_resizeRow = -1;
    int m_resizeOrigH = 0;
    int m_resizePressY = 0;
    bool m_panning = false;
    QPoint m_panPos;
    bool m_rightPress = false;
    bool m_selSweep = false;
    QPoint m_rightPressPos;
    int m_rightRow = -1;
    uint64_t m_selAnchorTick = 0;
    Gesture m_gesture = Gesture::None;
    int m_dragRow = -1;
    int64_t m_dragOrigTick = -1;
    uint64_t m_dragTick = 0;
    int m_dragValue = 0;
    std::vector<std::pair<uint64_t, int>> m_sweep;
    uint64_t m_lineStartTick = 0;
    int m_lineStartValue = 0;
    double m_prevTick = 0.0;
    int m_prevValue = 0;
    int m_hoverRow = -1;
    double m_hoverTick = 0.0;
    TimeRangeActions m_timeRangeActions;
};

} // namespace songview
