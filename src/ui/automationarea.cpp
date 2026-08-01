#include "ui/automationarea.h"

#include <algorithm>
#include <cmath>
#include <limits>

#include <QApplication>
#include <QEvent>
#include <QFontMetrics>
#include <QInputDialog>
#include <QKeyEvent>
#include <QMenu>
#include <QMessageBox>
#include <QMouseEvent>
#include <QPainter>
#include <QRegion>
#include <QScrollArea>
#include <QScrollBar>
#include <QWheelEvent>
#include <QTimer>

#include "core/songdocument.h"
#include "theme/themeruntime.h"
#include "theme/trackidentitycolors.h"
#include "typography.h"
#include "ui/automationpage.h"
#include "ui/layout.h"
#include "ui/selectionreticle.h"
#include "ui/m4asemantics.h"

namespace {

constexpr uint8_t kBendController = LANE_CC_BEND;

EditorAutomationRowId tempoRow()
{
    return {EditorAutomationRowKind::Tempo, 0, DOC_CC_TEMPO};
}

EditorAutomationRowId voiceRow(int track)
{
    return {EditorAutomationRowKind::Voice, uint8_t(track), DOC_CC_VOICE};
}

EditorAutomationRowId laneRow(int track, uint8_t controller)
{
    return {EditorAutomationRowKind::ControlChange, uint8_t(track), controller};
}

bool rangeZoomable(uint8_t controller)
{
    return controller != kBendController && controller != 10 && controller != 24;
}

uint8_t defaultRange(uint8_t controller)
{
    return controller == 1 ? 0 : 127;
}

int autoRange(int maximum)
{
    if (maximum <= 16)
        return 16;
    if (maximum <= 32)
        return 32;
    if (maximum <= 64)
        return 64;
    return 127;
}

QString laneLabel(uint8_t controller)
{
    if (controller == kBendController)
        return QStringLiteral("Pitch bend (BEND)");
    const auto info = m4aClassifyCc(controller);
    return QStringLiteral("%1 (%2)").arg(QLatin1String(info.display), QLatin1String(info.name));
}

bool laneRangeMatches(const std::vector<DocLanePoint> &existing, uint64_t first, uint64_t last,
                      const std::vector<SongDocument::LanePointValue> &replacement)
{
    size_t replacementIndex = 0;
    for (const auto &point : existing) {
        if (point.tick < first || point.tick > last)
            continue;
        if (replacementIndex == replacement.size() || point.tick != replacement[replacementIndex].tick
            || point.value != replacement[replacementIndex].value)
            return false;
        ++replacementIndex;
    }
    return replacementIndex == replacement.size();
}

} // namespace

AutomationArea::AutomationArea(AutomationPage *page, QScrollArea *scroll)
    : songview::TimelineSurface(nullptr)
    , m_page(page)
    , m_scroll(scroll)
{
    setObjectName(QStringLiteral("automationArea"));
    setMouseTracking(true);
    setFocusPolicy(Qt::ClickFocus);
    setMinimumHeight(layout::editorGeometry().automationRowDefaultHeight);
    m_pendingTimer = new QTimer(this);
    m_pendingTimer->setSingleShot(true);
    connect(m_pendingTimer, &QTimer::timeout, this, [this] { commitPendingSweeps(); });
}


bool AutomationArea::event(QEvent *event)
{
    if (event->type() == QEvent::Hide || event->type() == QEvent::WindowDeactivate
        || event->type() == QEvent::UngrabMouse)
        cancelInteraction();
    return songview::TimelineSurface::event(event);
}
void AutomationArea::rebuildRows()
{
    cancelInteraction();
    m_timeSelection = {};
    m_rows.clear();
    if (!m_page || !m_page->ready() || !m_page->timeline()) {
        applyHeight();
        invalidateContent();
        return;
    }
    m_rows.push_back({tempoRow()});
    const int track = m_page->selectedTrack();
    if (track < 0) {
        applyHeight();
        invalidateContent();
        return;
    }
    bool hasVoice = m_page->document() != nullptr;
    for (const auto &change : m_page->model().voices) {
        if (change.track == track) {
            hasVoice = true;
            break;
        }
    }
    if (hasVoice)
        m_rows.push_back({voiceRow(track)});
    std::vector<uint8_t> controllers;
    const auto addController = [&controllers](uint8_t controller) {
        if (std::find(controllers.cbegin(), controllers.cend(), controller) == controllers.cend())
            controllers.push_back(controller);
    };
    for (const auto &lane : m_page->model().lanes)
        if (lane.track == track)
            addController(lane.cc);
    for (const auto &row : m_page->m_viewState.emptyLanes)
        if (row.kind == EditorAutomationRowKind::ControlChange && row.track == uint8_t(track))
            addController(row.controller);
    std::sort(controllers.begin(), controllers.end());
    for (const uint8_t controller : controllers) {
        const auto row = laneRow(track, controller);
        if (!m_page->m_viewState.isLaneHidden(row))
            m_rows.push_back({row});
    }
    applyHeight();
    invalidateContent();
}

void AutomationArea::cancelInteraction()
{
    const bool wasActive = m_panning || m_resizeRow >= 0 || m_rightPending || m_gesture != Gesture::None;
    m_panning = false;
    m_resizeRow = -1;
    m_rightPending = false;
    m_bandActive = false;
    m_rightRow = -1;
    m_bandEndRow = -1;
    m_gesture = Gesture::None;
    m_dragRow = -1;
    m_originalTick = -1;
    m_sweep.clear();
    m_pendingSweeps.clear();
    if (m_pendingTimer)
        m_pendingTimer->stop();
    clearHover();
    unsetCursor();
    if (mouseGrabber() == this)
        releaseMouse();
    if (wasActive)
        setGestureActive(false);
    invalidateContent();
}

int AutomationArea::rowHeight(const AutomationRow &row) const
{
    if (!m_page)
        return layout::editorGeometry().automationRowDefaultHeight;
    const int shared = m_page->m_viewState.laneHeight > 0
                           ? m_page->m_viewState.laneHeight
                           : layout::editorGeometry().automationRowDefaultHeight;
    const auto it = m_page->m_viewState.laneHeights.find(row.id);
    return std::clamp(it == m_page->m_viewState.laneHeights.cend() ? shared : it->second,
                      layout::editorGeometry().automationRowMinimumHeight, layout::editorGeometry().automationRowMaximumHeight);
}

int AutomationArea::rowTop(int index) const
{
    int top = layout::space(layout::Space::Zero);
    for (int row = 0; row < index && row < int(m_rows.size()); ++row)
        top += rowHeight(m_rows[row]);
    return top;
}

int AutomationArea::rowIndexAt(int y) const
{
    int bottom = layout::space(layout::Space::Zero);
    for (int row = 0; row < int(m_rows.size()); ++row) {
        bottom += rowHeight(m_rows[row]);
        if (y < bottom)
            return row;
    }
    return -1;
}

int AutomationArea::rowBoundaryAt(int y) const
{
    int bottom = layout::space(layout::Space::Zero);
    for (int row = 0; row < int(m_rows.size()); ++row) {
        bottom += rowHeight(m_rows[row]);
        if (std::abs(y - bottom) <= layout::singlePixel())
            return row;
    }
    return -1;
}

int AutomationArea::rowMinimum(const AutomationRow &row) const
{
    return row.id.kind == EditorAutomationRowKind::ControlChange
                   && row.id.controller == kBendController
               ? -8192
               : 0;
}

int AutomationArea::rowMaximum(const AutomationRow &row) const
{
    if (row.id.kind == EditorAutomationRowKind::Tempo) {
        int maximum = 200;
        for (const auto &point : m_page->model().tempoLane)
            maximum = std::max(maximum, point.value + 20);
        return maximum;
    }
    if (row.id.kind != EditorAutomationRowKind::ControlChange)
        return 127;
    if (row.id.controller == kBendController)
        return 8191;
    if (!rangeZoomable(row.id.controller))
        return 127;
    int dataMaximum = 0;
    if (const auto *lane = laneFor(row))
        for (const auto &point : lane->points)
            dataMaximum = std::max(dataMaximum, point.value);
    const auto it = m_page->m_viewState.laneRanges.find(row.id);
    const uint8_t mode = it == m_page->m_viewState.laneRanges.cend() ? defaultRange(row.id.controller)
                                                                       : it->second;
    return mode == 0 ? autoRange(dataMaximum) : std::max(int(mode), dataMaximum);
}

int AutomationArea::valueAtY(int rowIndex, int y) const
{
    if (rowIndex < 0 || rowIndex >= int(m_rows.size()))
        return 0;
    const int top = rowTop(rowIndex) + layout::space(layout::Space::Half);
    const int bottom = rowTop(rowIndex) + rowHeight(m_rows[rowIndex]) - layout::singlePixel()
                       - layout::space(layout::Space::Half);
    const int minimum = rowMinimum(m_rows[rowIndex]);
    const int maximum = rowMaximum(m_rows[rowIndex]);
    const int clamped = std::clamp(y, top, bottom);
    return minimum + (bottom - clamped) * (maximum - minimum) / std::max(1, bottom - top);
}

double AutomationArea::rawTickAt(qreal x) const
{
    return std::max(0.0, m_page->tickAtContentX(std::max(qreal(layout::editorGeometry().plotOrigin), x)
                                                 - layout::editorGeometry().plotOrigin));
}

const AutoLane *AutomationArea::laneFor(const AutomationRow &row) const
{
    if (row.id.kind != EditorAutomationRowKind::ControlChange)
        return nullptr;
    return m_page->model().findLane(int(row.id.track), row.id.controller);
}

const std::vector<LanePoint> *AutomationArea::pointsFor(const AutomationRow &row) const
{
    if (row.id.kind == EditorAutomationRowKind::Tempo)
        return &m_page->model().tempoLane;
    if (const auto *lane = laneFor(row))
        return &lane->points;
    return nullptr;
}

QString AutomationArea::titleFor(const AutomationRow &row) const
{
    if (row.id.kind == EditorAutomationRowKind::Tempo)
        return tr("Tempo (BPM)");
    if (row.id.kind == EditorAutomationRowKind::Voice)
        return tr("Voice");
    return laneLabel(row.id.controller);
}

QString AutomationArea::voiceShortName(int program) const
{
    QString name;
    QString type;
    const auto *voicegroup = m_page ? m_page->voicegroup() : nullptr;
    if (voicegroup && program >= 0 && program < VOICEGROUP_SIZE) {
        name = QString::fromUtf8(voicegroup->voiceNames[program]).trimmed();
        type = m4aVoiceTypeName(voicegroup->voices[program].type);
    }
    return name.isEmpty() ? (type.isEmpty() ? tr("Voice") : type)
                          : QStringLiteral("%1 (%2)").arg(name, type);
}

QString AutomationArea::valueTextFor(const AutomationRow &row, int value) const
{
    if (row.id.kind == EditorAutomationRowKind::Tempo)
        return QString::number(value);
    if (row.id.controller == kBendController)
        return m4aFormatBend(value);
    return m4aFormatCcValue(row.id.controller, uint8_t(value));
}

bool AutomationArea::rowTarget(const AutomationRow &row, int *track, uint8_t *controller) const
{
    if (!m_page || !m_page->document())
        return false;
    if (row.id.kind == EditorAutomationRowKind::Voice)
        return false;
    *track = row.id.kind == EditorAutomationRowKind::Tempo ? m_page->selectedTrack() : int(row.id.track);
    *controller = row.id.kind == EditorAutomationRowKind::Tempo ? DOC_CC_TEMPO : row.id.controller;
    return *track >= 0;
}

std::pair<int, uint8_t> AutomationArea::rowIdentity(const AutomationRow &row) const
{
    if (row.id.kind == EditorAutomationRowKind::Tempo)
        return {-1, DOC_CC_TEMPO};
    if (row.id.kind == EditorAutomationRowKind::Voice)
        return {m_page ? m_page->selectedTrack() : -1, DOC_CC_VOICE};
    return {int(row.id.track), row.id.controller};
}

bool AutomationArea::deletePointNear(const AutomationRow &row, qreal x)
{
    if (!m_page || !m_page->document())
        return false;
    int track = -1;
    uint8_t controller = 0;
    if (row.id.kind == EditorAutomationRowKind::Voice) {
        track = m_page->selectedTrack();
        controller = DOC_CC_VOICE;
    } else if (!rowTarget(row, &track, &controller)) {
        return false;
    }
    if (track < 0)
        return false;
    const qreal dpr = devicePixelRatioF();
    const DocLanePoint *nearest = nullptr;
    qreal distance = layout::editorGeometry().automationDeleteTimeRadius + 1;
    const auto points = m_page->document()->lanePoints(track, controller);
    for (const auto &point : points) {
        const qreal candidate = std::abs(
            m_page->displayX(point.tick, layout::editorGeometry().plotOrigin, dpr) - x);
        if (candidate <= layout::editorGeometry().automationDeleteTimeRadius
            && (!nearest || candidate <= distance)) {
            nearest = &point;
            distance = candidate;
        }
    }
    if (!nearest)
        return false;
    m_page->document()->deleteLanePoints(track, controller, {*nearest});
    m_page->requestRefresh();
    return true;
}

void AutomationArea::applyHeight()
{
    const int rowsHeight = rowTop(int(m_rows.size()));
    const int strip = m_page && m_page->document()
                          ? layout::editorGeometry().addAutomationLaneStripHeight
                          : layout::space(layout::Space::Zero);
    setMinimumHeight(std::max(layout::editorGeometry().automationRowDefaultHeight, rowsHeight + strip));
}

void AutomationArea::setGestureActive(bool active)
{
    if (m_page)
        m_page->setFollowScrollPaused(active);
}

void AutomationArea::clearTimeSelection()
{
    if (!m_timeSelection.active())
        return;
    m_timeSelection = {};
    invalidateContent();
}

bool AutomationArea::selectionContains(int rowIndex, qreal x) const
{
    if (!m_timeSelection.active() || rowIndex < m_timeSelection.firstRow
        || rowIndex > m_timeSelection.lastRow)
        return false;
    const qreal dpr = devicePixelRatioF();
    const qreal first = m_page->displayX(m_timeSelection.startTick, layout::editorGeometry().plotOrigin, dpr);
    const qreal last = m_page->displayX(m_timeSelection.endTick, layout::editorGeometry().plotOrigin, dpr);
    return x >= first && x < last;
}

void AutomationArea::showTimeSelectionMenu(const QPoint &globalPosition)
{
    if (m_timeSelection.active()) {
        EditorPageTimeSelectionMenuRequest request;
        request.startTick = m_timeSelection.startTick;
        request.endTick = m_timeSelection.endTick;
        request.globalPosition = globalPosition;
        for (int row = m_timeSelection.firstRow;
             row <= m_timeSelection.lastRow && row < int(m_rows.size()); ++row)
            request.lanes.push_back(rowIdentity(m_rows[row]));
        m_page->showTimeSelectionMenu(request);
        return;
    }
    QMenu menu;
    QAction *clear = menu.addAction(tr("Clear time selection"));
    if (menu.exec(globalPosition) == clear)
        clearTimeSelection();
}

void AutomationArea::wheelEvent(QWheelEvent *event)
{
    if (!m_page || !m_page->ready())
        return;
    const QPoint delta = event->angleDelta();
    const int vertical = delta.y() != 0 ? delta.y() : delta.x();
    if (event->modifiers() & Qt::ControlModifier) {
        m_wheelRemainder += vertical;
        const int steps = m_wheelRemainder / 120;
        if (steps != 0) {
            m_wheelRemainder -= steps * 120;
            const int shared = m_page->m_viewState.laneHeight > 0
                                   ? m_page->m_viewState.laneHeight
                                   : layout::editorGeometry().automationRowDefaultHeight;
            const int height = std::clamp(shared + steps * layout::editorGeometry().automationRowWheelIncrement,
                                          layout::editorGeometry().automationRowMinimumHeight,
                                          layout::editorGeometry().automationRowMaximumHeight);
            if (height != shared) {
                const double factor = double(height) / double(shared);
                for (auto &[row, rowHeight] : m_page->m_viewState.laneHeights)
                    rowHeight = std::clamp(int(std::lround(rowHeight * factor)),
                                           layout::editorGeometry().automationRowMinimumHeight,
                                           layout::editorGeometry().automationRowMaximumHeight);
                m_page->m_viewState.laneHeight = height;
                m_page->publishViewState();
                applyHeight();
                invalidateContent();
            }
        }
    } else if (event->modifiers() & Qt::ShiftModifier) {
        m_page->requestHorizontalScroll(m_page->liveState().horizontalScroll - vertical);
    } else if (delta.x() != 0 && delta.y() == 0) {
        m_page->requestHorizontalScroll(m_page->liveState().horizontalScroll - delta.x());
    } else if (event->position().x() < layout::editorGeometry().plotOrigin) {
        event->ignore();
        return;
    } else if (vertical != 0) {
        const double factor = std::pow(1.0015, double(vertical));
        m_page->requestTimeZoom(m_page->pxPerBeat() * factor);
    }
    event->accept();
}

void AutomationArea::mousePressEvent(QMouseEvent *event)
{
    clearHover();
    if (!m_page || !m_page->document())
        return;
    if (event->button() == Qt::MiddleButton) {
        m_panning = true;
        m_panPosition = event->globalPosition();
        setCursor(Qt::ClosedHandCursor);
        setGestureActive(true);
        return;
    }
    const int boundary = event->button() == Qt::LeftButton ? rowBoundaryAt(event->pos().y()) : -1;
    if (boundary >= 0) {
        m_resizeRow = boundary;
        m_resizeStartHeight = rowHeight(m_rows[boundary]);
        m_resizeStartY = event->pos().y();
        setGestureActive(true);
        return;
    }
    const QRect addRect(layout::space(layout::Space::Zero), rowTop(int(m_rows.size())), width(),
                        layout::editorGeometry().addAutomationLaneStripHeight);
    if ((event->button() == Qt::LeftButton || event->button() == Qt::RightButton)
        && addRect.contains(event->pos())) {
        showAddLaneMenu(event->globalPosition().toPoint());
        return;
    }
    const int rowIndex = rowIndexAt(event->pos().y());
    if (rowIndex < 0)
        return;
    setFocus();
    const auto &row = m_rows[rowIndex];
    if (event->position().x() < layout::editorGeometry().plotOrigin) {
        if (event->button() == Qt::RightButton
            && row.id.kind == EditorAutomationRowKind::ControlChange)
            showLaneMenu(row, event->globalPosition().toPoint());
        return;
    }
    if (event->button() == Qt::RightButton) {
        m_rightPending = true;
        m_bandActive = false;
        m_rightStart = event->pos();
        m_rightRow = rowIndex;
        m_bandEndRow = rowIndex;
        m_bandStartTick = m_page->snapTick(rawTickAt(event->position().x()),
                                            event->modifiers() & Qt::AltModifier);
        setGestureActive(true);
        return;
    }
    if (event->button() != Qt::LeftButton)
        return;
    if (row.id.kind == EditorAutomationRowKind::Voice) {
        showVoiceMenu(row, event->globalPosition().toPoint());
        return;
    }
    int track = -1;
    uint8_t controller = 0;
    if (!rowTarget(row, &track, &controller))
        return;
    m_dragRow = rowIndex;
    setGestureActive(true);
    const bool fine = event->modifiers() & Qt::AltModifier;
    updateDrag(event->position().x(), event->pos().y(), fine, event->modifiers() & Qt::ControlModifier);
    const auto *points = pointsFor(row);
    const LanePoint *hit = nullptr;
    if (points) {
        const int top = rowTop(rowIndex) + layout::space(layout::Space::Half);
        const int bottom = rowTop(rowIndex) + rowHeight(row) - layout::singlePixel()
                           - layout::space(layout::Space::Half);
        const qreal dpr = devicePixelRatioF();
        qreal distance = std::numeric_limits<qreal>::max();
        for (const auto &point : *points) {
            const qreal dx = m_page->displayX(point.tick, layout::editorGeometry().plotOrigin, dpr)
                             - event->position().x();
            const int dy = bottom - (point.value - rowMinimum(row)) * (bottom - top)
                                         / std::max(1, rowMaximum(row) - rowMinimum(row))
                           - event->pos().y();
            if (std::abs(dx) > layout::editorGeometry().automationPointHitRadius
                || std::abs(dy) > layout::editorGeometry().automationPointHitRadius)
                continue;
            const qreal candidate = dx * dx + qreal(dy * dy);
            if (!hit || candidate <= distance) {
                hit = &point;
                distance = candidate;
            }
        }
    }
    if (event->modifiers() & Qt::ShiftModifier) {
        m_gesture = Gesture::Ramp;
        m_rampStart = m_drag;
    } else if (hit) {
        m_gesture = Gesture::Point;
        m_originalTick = hit->tick;
        m_drag = {hit->tick, hit->value};
    } else {
        m_gesture = Gesture::Sweep;
        m_originalTick = -1;
        m_sweep = {m_drag};
        m_previousRawTick = rawTickAt(event->position().x());
        m_previousValue = m_drag.value;
    }
    invalidateContent();
}

void AutomationArea::mouseMoveEvent(QMouseEvent *event)
{
    if (m_panning) {
        const QPointF delta = event->globalPosition() - m_panPosition;
        m_panPosition = event->globalPosition();
        m_page->requestHorizontalScroll(m_page->liveState().horizontalScroll - delta.x());
        if (m_scroll)
            m_scroll->verticalScrollBar()->setValue(m_scroll->verticalScrollBar()->value() - int(delta.y()));
        return;
    }
    if (m_resizeRow >= 0 && m_resizeRow < int(m_rows.size())) {
        const int height = std::clamp(m_resizeStartHeight + event->pos().y() - m_resizeStartY,
                                      layout::editorGeometry().automationRowMinimumHeight,
                                      layout::editorGeometry().automationRowMaximumHeight);
        if (height != rowHeight(m_rows[m_resizeRow])) {
            m_page->m_viewState.laneHeights[m_rows[m_resizeRow].id] = height;
            m_page->publishViewState();
            applyHeight();
            invalidateContent();
        }
        return;
    }
    if (m_rightPending) {
        if (!m_bandActive && (event->pos() - m_rightStart).manhattanLength()
                                 >= QApplication::startDragDistance())
            m_bandActive = true;
        if (m_bandActive) {
            m_bandEndTick = m_page->snapTick(rawTickAt(event->position().x()),
                                              event->modifiers() & Qt::AltModifier);
            const int lastY = std::max(layout::space(layout::Space::Zero),
                                       rowTop(int(m_rows.size())) - layout::singlePixel());
            m_bandEndRow =
                rowIndexAt(std::clamp(event->pos().y(), layout::space(layout::Space::Zero), lastY));
            invalidateContent();
        }
        return;
    }
    if (m_dragRow < 0) {
        setCursor(rowBoundaryAt(event->pos().y()) >= 0 ? Qt::SplitVCursor : Qt::ArrowCursor);
        updateHover(event->position().x(), event->pos().y());
        return;
    }
    const bool fine = event->modifiers() & Qt::AltModifier;
    updateDrag(event->position().x(), event->pos().y(), fine, event->modifiers() & Qt::ControlModifier);
    if (m_gesture == Gesture::Sweep)
        extendSweep(event->position().x(), fine);
    invalidateContent();
}

void AutomationArea::mouseReleaseEvent(QMouseEvent *event)
{
    if (event->button() == Qt::MiddleButton && m_panning) {
        m_panning = false;
        unsetCursor();
        setGestureActive(false);
        return;
    }
    if (event->button() == Qt::RightButton && m_rightPending) {
        const int rowIndex = m_rightRow;
        m_rightPending = false;
        if (m_bandActive) {
            m_bandActive = false;
            const uint64_t first = std::min(m_bandStartTick, m_bandEndTick);
            const uint64_t last = std::max(m_bandStartTick, m_bandEndTick);
            if (first < last && rowIndex >= 0 && m_bandEndRow >= 0) {
                m_timeSelection = {first, last, std::min(rowIndex, m_bandEndRow),
                                   std::max(rowIndex, m_bandEndRow)};
                std::vector<std::pair<int, uint8_t>> lanes;
                for (int row = m_timeSelection.firstRow;
                     row <= m_timeSelection.lastRow && row < int(m_rows.size()); ++row)
                    lanes.push_back(rowIdentity(m_rows[row]));
                m_page->publishTimeSelection(first, last, lanes);
                m_page->announce(tr("Automation range [%1, %2)").arg(first).arg(last));
            } else {
                clearTimeSelection();
            }
        } else if (selectionContains(rowIndex, event->position().x())) {
            showTimeSelectionMenu(event->globalPosition().toPoint());
        } else if (rowIndex >= 0 && rowIndex < int(m_rows.size())) {
            if (!deletePointNear(m_rows[rowIndex], event->position().x())
                && m_rows[rowIndex].id.kind != EditorAutomationRowKind::Voice)
                clearTimeSelection();
        }
        m_rightRow = -1;
        m_bandEndRow = -1;
        setGestureActive(false);
        invalidateContent();
        return;
    }
    if (event->button() == Qt::LeftButton && m_resizeRow >= 0) {
        m_resizeRow = -1;
        setGestureActive(false);
        return;
    }
    if (event->button() != Qt::LeftButton || m_dragRow < 0)
        return;
    if (m_gesture == Gesture::Sweep && m_sweep.size() == 1) {
        int track = -1;
        uint8_t controller = 0;
        if (rowTarget(m_rows[m_dragRow], &track, &controller))
            queuePendingSweep(track, controller);
    } else {
        commitDrag(event->modifiers() & Qt::AltModifier);
    }
    m_dragRow = -1;
    m_gesture = Gesture::None;
    m_sweep.clear();
    setGestureActive(false);
    invalidateContent();
}

void AutomationArea::mouseDoubleClickEvent(QMouseEvent *event)
{
    if (!m_page || !m_page->document()
        || event->button() != Qt::LeftButton || event->position().x() < layout::editorGeometry().plotOrigin)
        return;
    const int rowIndex = rowIndexAt(event->pos().y());
    if (rowIndex < 0 || m_rows[rowIndex].id.kind == EditorAutomationRowKind::Voice)
        return;
    int track = -1;
    uint8_t controller = 0;
    if (!rowTarget(m_rows[rowIndex], &track, &controller))
        return;
    m_gesture = Gesture::None;
    m_dragRow = -1;
    m_sweep.clear();
    if (!m_pendingSweeps.empty()) {
        m_pendingSweeps.pop_back();
        if (m_pendingSweeps.empty())
            m_pendingTimer->stop();
    }
    setGestureActive(false);
    const uint64_t tick = m_page->snapTick(rawTickAt(event->position().x()),
                                           event->modifiers() & Qt::AltModifier);
    DocLanePoint existing;
    const bool hasExisting
        = m_page->document()->findLanePoint(track, controller, tick, &existing);
    int value = hasExisting ? existing.value : valueAtY(rowIndex, event->pos().y());
    int minimum = 0;
    int maximum = 127;
    QString label = tr("Value:");
    if (m_rows[rowIndex].id.kind == EditorAutomationRowKind::Tempo) {
        minimum = 1;
        maximum = 999;
        label = tr("BPM:");
    } else if (controller == kBendController) {
        minimum = -8192;
        maximum = 8191;
        label = tr("Bend (0 = none):");
    } else if (controller == 10 || controller == 24) {
        minimum = -64;
        maximum = 63;
        value -= 64;
        label = tr("c_v value (0 = center):");
    }
    bool accepted = false;
    const int entered = QInputDialog::getInt(this, titleFor(m_rows[rowIndex]), label, value,
                                             minimum, maximum, 1, &accepted);
    if (!accepted)
        return;
    const int stored = (controller == 10 || controller == 24) ? entered + 64 : entered;
    if (hasExisting && existing.value == stored)
        return;
    m_page->document()->writeLanePoints(track, controller, tick, tick, {{tick, stored}});
    m_page->requestRefresh();
}

void AutomationArea::keyPressEvent(QKeyEvent *event)
{
    if (event->key() == Qt::Key_Escape) {
        if (m_rightPending || m_bandActive || m_gesture != Gesture::None) {
            cancelInteraction();
        } else {
            clearTimeSelection();
            clearHover();
        }
        event->accept();
        return;
    }
    QWidget::keyPressEvent(event);
}

void AutomationArea::leaveEvent(QEvent *)
{
    clearHover();
}

QString AutomationArea::hoverTextFor(const AutomationRow &row, double tick, qreal x) const
{
    if (!m_page || !m_page->ready())
        return {};
    if (row.id.kind == EditorAutomationRowKind::Voice) {
        const int track = m_page->selectedTrack();
        if (track < 0)
            return {};
        if (const auto *document = m_page->document(); document)
            for (const auto &point : document->lanePoints(track, DOC_CC_VOICE))
                if (std::abs(m_page->displayX(point.tick, layout::editorGeometry().plotOrigin,
                                               devicePixelRatioF())
                             - x)
                    <= layout::editorGeometry().automationDeleteTimeRadius)
                    return {};
        const auto voice = m_page->voiceContext(
            static_cast<uint64_t>(std::floor(std::max(0.0, tick) + 0.5)));
        const int voiceSlot = voice.voiceSlot;
        if (voiceSlot < 0)
            return {};
        return QStringLiteral("→ %1 %2")
            .arg(voiceSlot, 3, 10, QLatin1Char('0'))
            .arg(voiceShortName(voiceSlot));
    }
    const auto *points = pointsFor(row);
    if (!points)
        return {};
    const LanePoint *held = nullptr;
    for (const auto &point : *points) {
        if (point.tick > tick)
            break;
        held = &point;
    }
    return held ? valueTextFor(row, held->value) : QString{};
}

QRect AutomationArea::hoverPaintBounds(int rowIndex, double tick) const
{
    if (!m_page || !m_page->ready() || rowIndex < 0 || rowIndex >= int(m_rows.size()))
        return {};
    const AutomationRow &row = m_rows[rowIndex];
    const QRect plot(layout::editorGeometry().plotOrigin, rowTop(rowIndex),
                     std::max(0, width() - layout::editorGeometry().plotOrigin), rowHeight(row));
    const qreal x = m_page->displayX(tick, layout::editorGeometry().plotOrigin, devicePixelRatioF());
    const QString text = hoverTextFor(row, tick, x);
    if (row.id.kind == EditorAutomationRowKind::Voice && text.isEmpty())
        return {};
    const int paintPadding = layout::editorGeometry().automationHoverPaintPadding;
    QRect bounds =
        QRectF(x - paintPadding, plot.top(), 2 * paintPadding, plot.height()).toAlignedRect();
    if (!text.isEmpty()) {
        const QRect textArea(qFloor(x + layout::space(layout::Space::One)), plot.top(),
                             std::max(0, qCeil(plot.right() - x)), plot.height());
        const QFontMetrics metrics(typography::bold(font()));
        bounds = bounds.united(metrics.boundingRect(textArea, Qt::AlignLeft | Qt::AlignVCenter,
                                                    text)
                                   .adjusted(-paintPadding, -paintPadding, paintPadding,
                                             paintPadding));
    }
    return bounds.intersected(rect());
}

void AutomationArea::updateHover(qreal x, int y)
{
    const int rowIndex = x >= layout::editorGeometry().plotOrigin ? rowIndexAt(y) : -1;
    if (rowIndex < 0 || (m_rows[rowIndex].id.kind != EditorAutomationRowKind::Voice
                         && !pointsFor(m_rows[rowIndex]))) {
        clearHover();
        return;
    }
    const QRect previousBounds = hoverPaintBounds(m_hoverRow, m_hoverTick);
    const double rawTick = rawTickAt(x);
    const double tick = m_rows[rowIndex].id.kind == EditorAutomationRowKind::Voice
                            ? m_page->snapTick(rawTick, false)
                            : rawTick;
    if (rowIndex == m_hoverRow && tick == m_hoverTick)
        return;
    m_hoverRow = rowIndex;
    m_hoverTick = tick;
    QRegion dirty(previousBounds);
    dirty += hoverPaintBounds(m_hoverRow, m_hoverTick);
    if (!dirty.isEmpty())
        invalidateContent(dirty);
}

void AutomationArea::clearHover()
{
    if (m_hoverRow < 0)
        return;
    const QRect previousBounds = hoverPaintBounds(m_hoverRow, m_hoverTick);
    m_hoverRow = -1;
    if (!previousBounds.isEmpty())
        invalidateContent(QRegion(previousBounds));
}

void AutomationArea::updateDrag(qreal x, int y, bool fineMode, bool detent)
{
    if (m_dragRow < 0 || m_dragRow >= int(m_rows.size()))
        return;
    const auto &row = m_rows[m_dragRow];
    m_drag.value = valueAtY(m_dragRow, y);
    if (row.id.kind == EditorAutomationRowKind::Tempo)
        m_drag.value = std::max(1, m_drag.value);
    if (detent && row.id.kind == EditorAutomationRowKind::ControlChange) {
        const int neutral = row.id.controller == kBendController ? 0
                            : (row.id.controller == 10 || row.id.controller == 24 ? 64 : -1);
        if (neutral >= 0) {
            const int span = rowMaximum(row) - rowMinimum(row);
            if (std::abs(m_drag.value - neutral) <= span * layout::editorGeometry().automationNeutralSnapRadius
                                                    / std::max(1, rowHeight(row)))
                m_drag.value = neutral;
        }
    }
    m_drag.tick = m_page->snapTick(rawTickAt(x), fineMode);
}

void AutomationArea::extendSweep(qreal x, bool fineMode)
{
    const double rawTick = rawTickAt(x);
    const double from = m_previousRawTick;
    const uint64_t first = m_page->snapTick(std::min(from, rawTick), fineMode);
    const uint64_t last = m_page->snapTick(std::max(from, rawTick), fineMode);
    for (uint64_t tick = first;;) {
        int value = m_drag.value;
        if (rawTick != from) {
            const double fraction = std::clamp((double(tick) - from) / (rawTick - from), 0.0, 1.0);
            value = m_previousValue + int(std::llround(fraction * (m_drag.value - m_previousValue)));
        }
        const auto position = std::lower_bound(m_sweep.begin(), m_sweep.end(), tick,
                                               [](const DragPoint &point, uint64_t value) {
                                                   return point.tick < value;
                                               });
        if (position != m_sweep.end() && position->tick == tick)
            position->value = value;
        else
            m_sweep.insert(position, {tick, value});
        if (tick == last)
            break;
        tick = m_page->nextGridTick(tick, fineMode, last);
    }
    m_previousRawTick = rawTick;
    m_previousValue = m_drag.value;
}

void AutomationArea::queuePendingSweep(int track, uint8_t controller)
{
    if (m_sweep.empty())
        return;
    m_pendingSweeps.push_back({track, controller, m_sweep});
    m_pendingTimer->start(QApplication::doubleClickInterval());
}

void AutomationArea::commitPendingSweeps()
{
    if (!m_page || !m_page->document()) {
        m_pendingSweeps.clear();
        return;
    }
    auto pendingSweeps = std::move(m_pendingSweeps);
    m_pendingSweeps.clear();
    auto *document = m_page->document();
    bool changed = false;
    for (const auto &pending : pendingSweeps) {
        if (pending.points.empty())
            continue;
        std::vector<SongDocument::LanePointValue> points;
        points.reserve(pending.points.size());
        for (const auto &point : pending.points)
            points.push_back({point.tick, point.value});
        const uint64_t first = points.front().tick;
        const uint64_t last = points.back().tick;
        if (laneRangeMatches(document->lanePoints(pending.track, pending.controller), first, last,
                             points))
            continue;
        document->writeLanePoints(pending.track, pending.controller, first, last, points);
        changed = true;
    }
    if (changed)
        m_page->requestRefresh();
}

void AutomationArea::commitDrag(bool fineMode)
{
    if (!m_page || !m_page->document() || m_dragRow < 0
        || m_dragRow >= int(m_rows.size()))
        return;
    const auto &row = m_rows[m_dragRow];
    int track = -1;
    uint8_t controller = 0;
    if (!rowTarget(row, &track, &controller))
        return;
    auto *document = m_page->document();
    bool changed = false;
    if (m_gesture == Gesture::Point) {
        DocLanePoint original;
        if (m_originalTick >= 0
            && document->findLanePoint(track, controller, uint64_t(m_originalTick), &original)
            && (original.tick != m_drag.tick || original.value != m_drag.value)) {
            document->moveLanePoint(track, controller, original, m_drag.tick, m_drag.value);
            changed = true;
        }
    } else if (m_gesture == Gesture::Sweep) {
        std::vector<SongDocument::LanePointValue> points;
        points.reserve(m_sweep.size());
        for (const auto &point : m_sweep)
            points.push_back({point.tick, point.value});
        if (!points.empty()
            && !laneRangeMatches(document->lanePoints(track, controller), points.front().tick,
                                 points.back().tick, points)) {
            document->writeLanePoints(track, controller, points.front().tick, points.back().tick,
                                      points);
            changed = true;
        }
    } else if (m_gesture == Gesture::Ramp) {
        uint64_t first = m_rampStart.tick;
        uint64_t last = m_drag.tick;
        int firstValue = m_rampStart.value;
        int lastValue = m_drag.value;
        if (first > last) {
            std::swap(first, last);
            std::swap(firstValue, lastValue);
        }
        std::vector<SongDocument::LanePointValue> points;
        for (uint64_t tick = first;;) {
            const int value = firstValue + int(std::llround(double(lastValue - firstValue)
                                                             * double(tick - first)
                                                             / std::max<uint64_t>(1, last - first)));
            points.push_back({tick, value});
            if (tick == last)
                break;
            tick = m_page->nextGridTick(tick, fineMode, last);
        }
        if (!laneRangeMatches(document->lanePoints(track, controller), first, last, points)) {
            document->writeLanePoints(track, controller, first, last, points);
            changed = true;
        }
    }
    if (changed)
        m_page->requestRefresh();
}

void AutomationArea::showAddLaneMenu(const QPoint &globalPosition)
{
    if (!m_page)
        return;
    const int track = m_page->selectedTrack();
    if (track < 0)
        return;
    static constexpr uint8_t candidates[] = {1, 7, 10, 20, 21, kBendController};
    QMenu menu;
    std::vector<EditorAutomationRowId> hidden;
    for (const uint8_t controller : candidates) {
        const auto row = laneRow(track, controller);
        if (m_page->m_viewState.isLaneHidden(row)
            || laneFor({row})
            || m_page->m_viewState.emptyLanes.find(row) != m_page->m_viewState.emptyLanes.cend())
            continue;
        auto *action = menu.addAction(laneLabel(controller));
        action->setData(int(controller));
    }
    for (const auto &row : m_page->m_viewState.hiddenLanes())
        if (row.kind == EditorAutomationRowKind::ControlChange && row.track == uint8_t(track))
            hidden.push_back(row);
    if (menu.isEmpty())
        menu.addAction(tr("All parameters already have lanes"))->setEnabled(false);
    if (!hidden.empty()) {
        menu.addSeparator();
        menu.addAction(tr("Hidden lanes"))->setEnabled(false);
        for (const auto &row : hidden) {
            auto *action = menu.addAction(tr("Show: %1 (hidden)").arg(laneLabel(row.controller)));
            action->setData(256 + int(row.controller));
        }
    }
    QAction *chosen = menu.exec(globalPosition);
    if (!chosen || !chosen->data().isValid())
        return;
    const int value = chosen->data().toInt();
    if (value >= 256) {
        const auto row = laneRow(track, uint8_t(value - 256));
        if (m_page->m_viewState.unhideLane(row)) {
            m_page->publishViewState();
            rebuildRows();
            m_page->announce(tr("Showed the %1 lane").arg(laneLabel(row.controller)));
        }
    } else {
        m_page->addEmptyLane(track, uint8_t(value));
        m_page->announce(tr("Added %1 lane").arg(laneLabel(uint8_t(value))));
    }
}

void AutomationArea::showLaneMenu(const AutomationRow &row, const QPoint &globalPosition)
{
    const auto *lane = laneFor(row);
    const bool empty = !lane || lane->points.empty();
    QMenu menu;
    QAction *copy = menu.addAction(tr("Copy lane"));
    copy->setEnabled(!empty);
    QAction *paste = menu.addAction(tr("Paste lane (replace)"));
    paste->setEnabled(!m_clipboard.empty());
    menu.addSeparator();
    QAction *clear = menu.addAction(tr("Clear events"));
    clear->setEnabled(!empty);
    QAction *remove = menu.addAction(empty ? tr("Remove empty lane") : tr("Delete lane"));
    QAction *hide = menu.addAction(tr("Hide lane"));
    std::vector<std::pair<QAction *, uint8_t>> ranges;
    if (rangeZoomable(row.id.controller)) {
        auto *rangeMenu = menu.addMenu(tr("Value range"));
        const auto range = m_page->m_viewState.laneRanges.find(row.id);
        const uint8_t current = range == m_page->m_viewState.laneRanges.cend()
                                    ? defaultRange(row.id.controller)
                                    : range->second;
        for (const uint8_t value : {uint8_t(0), uint8_t(16), uint8_t(32), uint8_t(64),
                                    uint8_t(127)}) {
            const QString label = value == 0 ? tr("Auto (fit to data)")
                                  : value == 127 ? tr("0–127 (full)")
                                                 : QStringLiteral("0–%1").arg(value);
            auto *action = rangeMenu->addAction(label);
            action->setCheckable(true);
            action->setChecked(value == current);
            ranges.emplace_back(action, value);
        }
    }
    QAction *chosen = menu.exec(globalPosition);
    if (!chosen)
        return;
    for (const auto &[action, range] : ranges) {
        if (chosen == action) {
            m_page->setLaneRange(row.id, range);
            return;
        }
    }
    const int track = int(row.id.track);
    const uint8_t controller = row.id.controller;
    auto *document = m_page->document();
    const auto points = document->lanePoints(track, controller);
    bool changed = false;
    if (chosen == copy) {
        m_clipboard.clear();
        for (const auto &point : points)
            m_clipboard.push_back({point.tick, point.value});
        m_page->announce(tr("Copied the %1 lane (%n point(s))", nullptr, int(points.size()))
                             .arg(titleFor(row)));
    } else if (chosen == paste) {
        std::vector<SongDocument::LanePointValue> replacementPoints;
        replacementPoints.reserve(m_clipboard.size());
        const int minimum = controller == kBendController ? -8192 : 0;
        const int maximum = controller == kBendController ? 8191 : 127;
        for (const auto &point : m_clipboard)
            replacementPoints.push_back({point.tick, std::clamp(point.value, minimum, maximum)});
        if (!laneRangeMatches(points, 0, std::numeric_limits<uint64_t>::max(), replacementPoints)) {
            SongDocument::RangeEdit edit;
            edit.removePoints = points;
            SongDocument::RangeEdit::LaneWrite replacement{track, controller, replacementPoints};
            edit.addPoints.push_back(std::move(replacement));
            document->applyRangeEdit(tr("paste lane"), edit);
            changed = true;
            m_page->announce(tr("Replaced the %1 lane").arg(titleFor(row)));
        }
    } else if (chosen == clear) {
        if (!points.empty()) {
            m_page->addEmptyLane(track, controller);
            document->deleteLanePoints(track, controller, points);
            changed = true;
        }
    } else if (chosen == remove) {
        if (!points.empty()
            && QMessageBox::question(this, tr("Delete lane"),
                                      tr("Delete the %1 lane and its %2 events?")
                                          .arg(titleFor(row))
                                          .arg(points.size())) != QMessageBox::Yes)
            return;
        m_page->removeEmptyLane(track, controller);
        if (!points.empty()) {
            document->deleteLanePoints(track, controller, points);
            changed = true;
        }
    } else if (chosen == hide) {
        if (m_page->m_viewState.hideLane(row.id)) {
            m_page->publishViewState();
            rebuildRows();
            m_page->announce(tr("Hid the %1 lane").arg(titleFor(row)));
        }
    }
    if (changed)
        m_page->requestRefresh();
}

void AutomationArea::showVoiceMenu(const AutomationRow &row, const QPoint &globalPosition)
{
    Q_UNUSED(row);
    if (!m_page || !m_page->document())
        return;
    const int track = m_page->selectedTrack();
    if (track < 0)
        return;
    const qreal x = mapFromGlobal(globalPosition).x();
    const qreal dpr = devicePixelRatioF();
    const auto points = m_page->document()->lanePoints(track, DOC_CC_VOICE);
    const DocLanePoint *marker = nullptr;
    qreal distance = layout::editorGeometry().automationDeleteTimeRadius + 1;
    for (const auto &point : points) {
        const qreal candidate
            = std::abs(m_page->displayX(point.tick, layout::editorGeometry().plotOrigin, dpr) - x);
        if (candidate <= layout::editorGeometry().automationDeleteTimeRadius && (!marker || candidate <= distance)) {
            marker = &point;
            distance = candidate;
        }
    }
    const uint64_t tick = marker ? marker->tick : m_page->snapTick(rawTickAt(x), false);
    int current = marker ? marker->value : 0;
    if (!marker)
        current = m_page->voiceContext(tick).voiceSlot;
    if (!marker) {
        for (const auto &point : points) {
            if (point.tick > tick)
                break;
            current = point.value;
        }
    }
    int selectedVoice = 0;
    if (!m_page->pickVoice(marker ? tr("Change voice") : tr("Insert voice change"),
                           std::max(0, current), &selectedVoice))
        return;
    DocLanePoint existing;
    bool changed = false;
    if (m_page->document()->findLanePoint(track, DOC_CC_VOICE, tick, &existing)) {
        if (existing.value != selectedVoice) {
            m_page->document()->moveLanePoint(track, DOC_CC_VOICE, existing, tick,
                                               selectedVoice);
            changed = true;
        }
    } else {
        m_page->document()->addLanePoint(track, DOC_CC_VOICE, tick, selectedVoice);
        changed = true;
    }
    if (changed)
        m_page->requestRefresh();
}

void AutomationArea::paintContent(QPainter &painter)
{
    painter.fillRect(rect(), themes::color(themes::Role::song_view_piano_roll_background));
    if (!m_page || !m_page->ready() || !m_page->timeline())
        return;
    int y = layout::space(layout::Space::Zero);
    for (int rowIndex = 0; rowIndex < int(m_rows.size()); ++rowIndex) {
        const int height = rowHeight(m_rows[rowIndex]);
        paintRow(painter, m_rows[rowIndex], rowIndex,
                 QRect(layout::space(layout::Space::Zero), y, width(), height));
        y += height;
    }
    if (m_page->document()) {
        const QRect add(layout::space(layout::Space::Zero), y, width(),
                        layout::editorGeometry().addAutomationLaneStripHeight);
        painter.setPen(themes::color(themes::Role::song_view_add_automation_lane_action));
        painter.drawText(add.adjusted(layout::space(layout::Space::One),
                                      layout::space(layout::Space::Zero),
                                      -layout::space(layout::Space::One),
                                      layout::space(layout::Space::Zero)),
                         Qt::AlignLeft | Qt::AlignVCenter, tr("+ Add lane"));
    }
    uint64_t first = 0;
    uint64_t last = 0;
    int firstRow = -1;
    int lastRow = -1;
    if (m_bandActive) {
        first = std::min(m_bandStartTick, m_bandEndTick);
        last = std::max(m_bandStartTick, m_bandEndTick);
        firstRow = std::min(m_rightRow, m_bandEndRow);
        lastRow = std::max(m_rightRow, m_bandEndRow);
    } else if (m_timeSelection.active()) {
        first = m_timeSelection.startTick;
        last = m_timeSelection.endTick;
        firstRow = m_timeSelection.firstRow;
        lastRow = m_timeSelection.lastRow;
    }
    if (first < last && firstRow >= 0 && lastRow >= firstRow) {
        const qreal dpr = painter.device()->devicePixelRatioF();
        const qreal x0 = m_page->displayX(first, layout::editorGeometry().plotOrigin, dpr);
        const qreal x1 = m_page->displayX(last, layout::editorGeometry().plotOrigin, dpr);
        const int top = rowTop(firstRow);
        const int bottom = rowTop(lastRow + 1);
        songview::paintSelectionReticle(
            painter, QRectF(std::min(x0, x1), top, std::abs(x1 - x0), bottom - top));
    }
}

void AutomationArea::paintRow(QPainter &painter, const AutomationRow &row, int rowIndex,
                              const QRect &bounds)
{
    const QRect plot(layout::editorGeometry().plotOrigin, bounds.top(),
                     std::max(0, width() - layout::editorGeometry().plotOrigin), bounds.height());
    painter.save();
    painter.setClipRect(bounds, Qt::IntersectClip);
    painter.setPen(themes::color(themes::Role::song_view_separator));
    painter.drawLine(bounds.left(), bounds.bottom(), bounds.right(), bounds.bottom());
    const auto titleFont = typography::bold(painter.font());
    const auto captionFont = typography::caption(painter.font());
    const QRect textBounds(layout::space(layout::Space::One), bounds.top(),
                           layout::editorGeometry().plotOrigin - 2 * layout::space(layout::Space::One),
                           bounds.height());
    const auto textLayout =
        layout::twoLineText(titleFont, titleFont, captionFont, layout::Space::Zero);
    const auto textBoxes = textLayout.align(textBounds, layout::VerticalAlignment::Center);
    painter.setFont(titleFont);
    painter.setPen(themes::color(themes::Role::song_view_primary_text));
    painter.drawText(textBoxes.primary, Qt::AlignLeft | Qt::AlignVCenter, titleFor(row));
    painter.setFont(captionFont);
    const auto *points = pointsFor(row);
    if (points && !points->empty()) {
        painter.setPen(themes::color(themes::Role::song_view_secondary_text));
        painter.drawText(textBoxes.secondary, Qt::AlignLeft | Qt::AlignVCenter,
                         tr("%1 points · %2..%3")
                             .arg(points->size())
                             .arg(rowMinimum(row))
                             .arg(rowMaximum(row)));
    } else if (points && row.id.kind == EditorAutomationRowKind::ControlChange) {
        painter.setPen(themes::color(themes::Role::song_view_secondary_text));
        painter.drawText(textBoxes.secondary, Qt::AlignLeft | Qt::AlignVCenter,
                         tr("empty · click to add points"));
    } else if (row.id.kind == EditorAutomationRowKind::Voice && m_page->document()) {
        const int changeCount =
            int(std::count_if(m_page->model().voices.cbegin(), m_page->model().voices.cend(),
                              [this](const VoiceChange &change) {
                                  return change.track == m_page->selectedTrack();
                              }));
        painter.setPen(themes::color(themes::Role::song_view_secondary_text));
        painter.drawText(textBoxes.secondary, Qt::AlignLeft | Qt::AlignVCenter,
                         changeCount ? tr("%n change(s) · click to edit", nullptr, changeCount)
                                     : tr("no voice set · click to add"));
    }
    painter.setClipRect(plot, Qt::IntersectClip);
    const qreal dpr = painter.device()->devicePixelRatioF();
    const bool hostPaintedGrid = m_page->paintGrid(painter, plot, layout::editorGeometry().plotOrigin);
    if (!hostPaintedGrid) {
        const uint64_t length = m_page->timeline()->lengthTicks;
        const double pxPerTick =
            m_page->pxPerBeat() / double(std::max(1u, m_page->timeline()->ticksPerBeat));
        if (row.id.kind == EditorAutomationRowKind::Voice) {
            if (m_page->ready()) {
                QColor subdivision = themes::color(themes::Role::song_view_grid);
                subdivision.setAlpha((subdivision.alpha() * 125 + 127) / 255);
                painter.setPen(QPen(subdivision, layout::singlePixel()));
                const double firstVisibleTick =
                    std::max(0.0, m_page->tickAtContentX(layout::space(layout::Space::Zero)));
                for (uint64_t tick = m_page->snapTick(firstVisibleTick, false);;) {
                    const auto state = m_page->gridState(tick, false);
                    const qreal x = m_page->displayX(tick, layout::editorGeometry().plotOrigin, dpr);
                    if (x > plot.right())
                        break;
                    if (state.snapTicks < state.gridTicks
                        && pxPerTick * double(state.snapTicks)
                               >= layout::editorGeometry().automationGridMinimumCellWidth
                        && x >= plot.left())
                        painter.drawLine(QPointF(x, plot.top()), QPointF(x, plot.bottom()));
                    if (tick >= length)
                        break;
                    const uint64_t next = m_page->snapTick(
                        double(tick) + double(std::max<uint64_t>(1, state.snapTicks)) * 0.75,
                        false);
                    if (next <= tick)
                        break;
                    tick = std::min(next, length);
                }
            }
        }
        painter.setPen(QPen(themes::color(themes::Role::song_view_grid), layout::singlePixel()));
        for (uint64_t tick = 0;;) {
            const qreal x = m_page->displayX(tick, layout::editorGeometry().plotOrigin, dpr);
            if (x >= plot.left() && x <= plot.right())
                painter.drawLine(QPointF(x, plot.top()), QPointF(x, plot.bottom()));
            if (tick >= length)
                break;
            tick = m_page->nextGridTick(tick, false, length);
        }
    }
    if (row.id.kind == EditorAutomationRowKind::Voice) {
        paintVoiceRow(painter, plot);
    } else if (points) {
        const QColor color = row.id.kind == EditorAutomationRowKind::Tempo
                                 ? themes::color(themes::Role::song_view_automation_tempo_curve)
                                 : themes::trackIdentityColor(row.id.track % themes::trackIdentityColorCount);
        paintCurve(painter, plot, *points, rowMinimum(row), rowMaximum(row), color);
    }
    if (rowIndex == m_dragRow) {
        const int top = plot.top() + layout::space(layout::Space::Half);
        const int bottom = plot.bottom() - layout::space(layout::Space::Half);
        const auto valueY = [&](int value) {
            return bottom - (value - rowMinimum(row)) * (bottom - top)
                   / std::max(1, rowMaximum(row) - rowMinimum(row));
        };
        const auto tickX = [&](uint64_t tick) {
            return m_page->displayX(tick, layout::editorGeometry().plotOrigin, dpr);
        };
        painter.setPen(
            QPen(themes::color(themes::Role::song_view_edit_preview_outline), layout::singlePixel()));
        painter.setBrush(Qt::NoBrush);
        if (m_gesture == Gesture::Sweep && m_sweep.size() > 1) {
            for (size_t index = 0; index + 1 < m_sweep.size(); ++index) {
                const int y = valueY(m_sweep[index].value);
                painter.drawLine(
                    QLineF(tickX(m_sweep[index].tick), y, tickX(m_sweep[index + 1].tick), y));
                painter.drawLine(QLineF(tickX(m_sweep[index + 1].tick), y,
                                        tickX(m_sweep[index + 1].tick),
                                        valueY(m_sweep[index + 1].value)));
            }
        } else if (m_gesture == Gesture::Ramp) {
            painter.drawLine(QLineF(tickX(m_rampStart.tick), valueY(m_rampStart.value),
                                    tickX(m_drag.tick), valueY(m_drag.value)));
        }
        const qreal x = tickX(m_drag.tick);
        const int y = valueY(m_drag.value);
        const qreal markerRadius =
            layout::space(layout::Space::Half) + layout::singlePixel();
        painter.drawEllipse(QPointF(x, y), markerRadius, markerRadius);
        painter.drawText(QPointF(x + layout::space(layout::Space::One)
                                     + layout::space(layout::Space::Half),
                                 y - layout::space(layout::Space::One)),
                         valueTextFor(row, m_drag.value));
    }
    paintHover(painter, row, rowIndex, plot);
    const qreal cursorX = m_page->displayX(m_page->liveState().editCursorTick,
                                           layout::editorGeometry().plotOrigin, dpr);
    painter.setPen(QPen(themes::color(themes::Role::song_view_edit_cursor), layout::singlePixel(),
                         Qt::DashLine));
    painter.drawLine(QPointF(cursorX, plot.top()), QPointF(cursorX, plot.bottom()));
    painter.restore();
}

void AutomationArea::paintHover(QPainter &painter, const AutomationRow &row, int rowIndex,
                                const QRect &plot)
{
    if (rowIndex != m_hoverRow)
        return;
    const qreal dpr = painter.device()->devicePixelRatioF();
    const qreal x = m_page->displayX(m_hoverTick, layout::editorGeometry().plotOrigin, dpr);
    const QString text = hoverTextFor(row, m_hoverTick, x);
    if (row.id.kind == EditorAutomationRowKind::Voice) {
        if (text.isEmpty())
            return;
        painter.setPen(QPen(themes::color(themes::Role::song_view_secondary_text),
                            layout::singlePixel(), Qt::DotLine));
        painter.drawLine(QPointF(x, plot.top()), QPointF(x, plot.bottom()));
        painter.drawText(QRectF(x + layout::space(layout::Space::One), plot.top(),
                                std::max<qreal>(0, plot.right() - x), plot.height()),
                         Qt::AlignLeft | Qt::AlignVCenter, text);
        return;
    }
    painter.setPen(QPen(themes::color(themes::Role::song_view_secondary_text), layout::singlePixel(),
                         Qt::DotLine));
    painter.drawLine(QPointF(x, plot.top()), QPointF(x, plot.bottom()));
    const auto *points = pointsFor(row);
    if (!points)
        return;
    const LanePoint *held = nullptr;
    for (const auto &point : *points) {
        if (point.tick > m_hoverTick)
            break;
        held = &point;
    }
    if (!held)
        return;
    const int top = plot.top() + layout::space(layout::Space::Half);
    const int bottom = plot.bottom() - layout::space(layout::Space::Half);
    const int valueY = bottom - (held->value - rowMinimum(row)) * (bottom - top)
                       / std::max(1, rowMaximum(row) - rowMinimum(row));
    painter.setBrush(themes::color(themes::Role::song_view_secondary_text));
    painter.setPen(Qt::NoPen);
    painter.drawEllipse(QPointF(x, valueY), layout::singlePixel(), layout::singlePixel());
    painter.drawText(QRectF(x + layout::space(layout::Space::One), plot.top(),
                            std::max<qreal>(0, plot.right() - x), plot.height()),
                     Qt::AlignLeft | Qt::AlignVCenter, text);
}

void AutomationArea::paintCurve(QPainter &painter, const QRect &plot,
                                const std::vector<LanePoint> &points, int minimum, int maximum,
                                const QColor &color)
{
    if (points.empty())
        return;
    const int top = plot.top() + layout::space(layout::Space::Half);
    const int bottom = plot.bottom() - layout::space(layout::Space::Half);
    const auto valueY = [&](int value) {
        return bottom - (value - minimum) * (bottom - top) / std::max(1, maximum - minimum);
    };
    const qreal dpr = painter.device()->devicePixelRatioF();
    const qreal curveStrokeWidth = layout::singlePixel() + layout::singlePixel();
    const qreal pointHalfExtent = layout::singlePixel();
    const qreal pointExtent = pointHalfExtent + layout::singlePixel() + pointHalfExtent;
    painter.setPen(QPen(color, curveStrokeWidth));
    for (size_t index = 0; index < points.size(); ++index) {
        const qreal x0 = m_page->displayX(points[index].tick, layout::editorGeometry().plotOrigin, dpr);
        const qreal x1 = index + 1 < points.size()
                              ? m_page->displayX(points[index + 1].tick,
                                                 layout::editorGeometry().plotOrigin, dpr)
                              : plot.right();
        if (x1 < plot.left() || x0 > plot.right())
            continue;
        const int y = valueY(points[index].value);
        painter.drawLine(QLineF(x0, y, x1, y));
        if (index + 1 < points.size())
            painter.drawLine(QLineF(x1, y, x1, valueY(points[index + 1].value)));
        if (m_page->pxPerBeat() >= layout::editorGeometry().automationPointDetailThreshold)
            painter.fillRect(QRectF(x0 - pointHalfExtent, y - pointHalfExtent, pointExtent,
                                    pointExtent),
                             color);
    }
}

void AutomationArea::paintVoiceRow(QPainter &painter, const QRect &plot)
{
    const int track = m_page->selectedTrack();
    const qreal dpr = painter.device()->devicePixelRatioF();
    const auto &live = m_page->liveState();
    const double contextTick =
        live.playback.playing ? live.playback.playheadTick : double(live.editCursorTick);
    const auto context = m_page->voiceContext(
        static_cast<uint64_t>(std::floor(std::max(0.0, contextTick) + 0.5)));
    const QString contextText =
        context.voiceSlot >= 0
            ? QStringLiteral("%1 %2")
                  .arg(context.voiceSlot, 3, 10, QLatin1Char('0'))
                  .arg(voiceShortName(context.voiceSlot))
            : tr("No voice");
    painter.setPen(themes::color(themes::Role::song_view_secondary_text));
    painter.drawText(plot.adjusted(layout::space(layout::Space::One),
                                   layout::space(layout::Space::Zero),
                                   -layout::space(layout::Space::One),
                                   layout::space(layout::Space::Zero)),
                     Qt::AlignRight | Qt::AlignVCenter, contextText);
    const qreal markerStrokeWidth = layout::singlePixel() + layout::singlePixel();
    for (const auto &change : m_page->model().voices) {
        if (change.track != track)
            continue;
        const qreal x = m_page->displayX(change.tick, layout::editorGeometry().plotOrigin, dpr);
        painter.setPen(
            QPen(themes::trackIdentityColor(track % themes::trackIdentityColorCount), markerStrokeWidth));
        painter.drawLine(QPointF(x, plot.top() + layout::space(layout::Space::One)),
                         QPointF(x, plot.bottom() - layout::space(layout::Space::One)));
        painter.setPen(themes::color(themes::Role::song_view_primary_text));
        painter.drawText(QRectF(x + layout::space(layout::Space::One), plot.top(),
                                std::max<qreal>(0, plot.right() - x), plot.height()),
                         Qt::AlignLeft | Qt::AlignVCenter,
                         QStringLiteral("%1 %2")
                             .arg(change.program, 3, 10, QLatin1Char('0'))
                             .arg(voiceShortName(change.program)));
    }
}
