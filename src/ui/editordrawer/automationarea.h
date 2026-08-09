#pragma once

#include <array>
#include <cstdint>
#include <optional>
#include <utility>
#include <variant>
#include <vector>

#include <QColor>
#include <QFont>
#include <QPointF>
#include <QRect>
#include <QRectF>
#include <QString>

#include "ui/editordrawer/automationgesture.h"
#include "ui/editordrawer/automationhover.h"
#include "ui/editordrawer/automationlaneedit.h"
#include "ui/editordrawer/automationpaint.h"
#include "ui/editordrawer/automationpencilgesture.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/automationrows.h"
#include "ui/editorviewstate.h"
#include "ui/songviewmodel.h"
#include "ui/timelinesurface.h"

class AutomationPage;
class QEvent;
class QKeyEvent;
class QPainter;
class QScrollArea;
class QWheelEvent;
class QMouseEvent;
struct AutoLane;

// AutomationArea is the paint and input surface owned by AutomationPage.
// Temporary gesture state stays local to this canvas; song data and routing
// are obtained from the page's stable SongView owner.
class AutomationArea final : public songview::TimelineSurface
{
  public:
    explicit AutomationArea(AutomationPage *page, QScrollArea *scroll);
    using songview::TimelineSurface::invalidateContent;
    void invalidateContent();

    const std::vector<AutomationRow> &rows() const noexcept { return m_rowData.rows(); }
    void rebuildRows();
    void cancelInteraction();
    void setPencilMode(bool enabled);
    bool isPanning() const noexcept;
    bool bandPreviewContains(int rowIndex, uint64_t tick) const noexcept;
    bool bandPreviewContainsRow(int rowIndex) const noexcept;
    QRect labelGutter() const noexcept { return m_labelGutter; }
    int plotOrigin() const noexcept { return m_geometry.plotOrigin; }

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
    void contentGeometryChanged() override;

  private:
    friend class AutomationPage;

    void refreshGeometry();
    QFont captionLabelFont() const;

    // Pixel <-> tick <-> value mapping over the current geometry, rows, and
    // page timeline. Constructed fresh per event or paint pass.
    AutomationProjection projection() const;

    bool promptPointValue(const AutomationRow &row, uint8_t controller, int currentValue,
                          int *storedValue);
    bool showPointMenuNear(const AutomationRow &row, int rowIndex, const QPoint &position,
                           const QPoint &globalPosition);
    bool commitLaneEdit(int rowIndex, const AutomationLaneEdit::Completion &completion);
    bool pencilPointHit(const AutomationRow &row, int rowIndex, const QPointF &position,
                        DocLanePoint *point) const;
    bool pencilPointHit(const AutomationRow &row, int rowIndex, const QPointF &position,
                        const AutomationProjection &proj, DocLanePoint *point) const;
    void updateAxisLockCursor(AxisLock lock);
    ValuePoint mappedForRow(int row, QPointF pos, bool fine, bool snapValue,
                            const AutomationProjection &proj) const;
    void updateActiveGesture(const QPointF &position, Qt::KeyboardModifiers modifiers,
                             bool activateSweep);
    void finishActiveGesture(bool fineMode);
    void showTimeSelectionMenu(const QPoint &globalPosition);
    void showAddLaneMenu(const QPoint &globalPosition);
    void showLaneMenu(const AutomationRow &row, const QPoint &globalPosition);
    void showVoiceMenu(const AutomationRow &row, const QPoint &globalPosition);
    void setGestureActive(bool active);
    AutomationGeometry m_geometry;
    QRect m_labelGutter;
    AutomationPage *m_page = nullptr;
    QScrollArea *m_scroll = nullptr;
    AutomationRows m_rowData;
    struct ResizeState {
        int row = -1;
        int startHeight = 0;
        int startY = 0;
        int wheelRemainder = 0;
        bool active() const noexcept { return row >= 0; }
        void clear() noexcept { row = -1; }
    } m_resize;
    struct PanState {
        bool active = false;
        QPointF pos;
        double startHScroll = 0;
        int startVScroll = 0;
    } m_pan;
    struct BandState {
        bool rightPending = false;
        QPoint rightStart;
        int rightRow = -1;
        bool active = false;
        uint64_t startTick = 0;
        uint64_t endTick = 0;
        int endRow = -1;
    } m_band;
    std::vector<ValuePoint> m_clipboard;
    bool m_pencilMode = false;
    std::optional<ActiveGesture> m_activeGesture;
    AutomationHoverState m_hoverState;
};
