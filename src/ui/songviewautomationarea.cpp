#include "ui/songviewautomationarea_p.hpp"

#include <QApplication>
#include <QInputDialog>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QResizeEvent>
#include <QScrollArea>
#include <QScrollBar>
#include <QWheelEvent>

#include <algorithm>
#include <climits>
#include <cmath>
#include <utility>

#include "core/mid2agbtables.h"
#include "ui/songview.h"

namespace songview {

namespace {

constexpr int kLaneH = 48;
constexpr int kMinLaneH = 28;
constexpr int kMaxLaneH = 128;
constexpr int kAddLaneH = 20;

} // namespace

AutomationArea::State::State(AutomationArea *area, SongView *songView, QScrollArea *scroll)
    : QWidget(area), m_area(area), m_sv(songView), m_scroll(scroll)
{
    setObjectName(QStringLiteral("automationArea")); // findChild for tests
    m_area->setMinimumHeight(kLaneH);
    setMouseTracking(true); // divider hover cursor
    // Range shortcuts stay scoped to the lanes area; a click focuses it,
    // like the roll.
    setFocusPolicy(Qt::ClickFocus);
    createTimeRangeActions();
}

int AutomationArea::State::laneHeight() const
{
    return m_laneH;
}

const QHash<QString, int> &AutomationArea::State::rowHeightOverrides() const
{
    return m_rowHeights;
}

bool AutomationArea::State::gestureActive() const
{
    return m_panning || m_gesture != Gesture::None || m_dragRow >= 0
        || m_resizeRow >= 0 || m_rightPress;
}

void AutomationArea::State::setViewHeights(int laneH, const QHash<QString, int> &overrides)
{
    m_laneH = laneH > 0 ? std::clamp(laneH, kMinLaneH, kMaxLaneH) : kLaneH;
    m_rowHeights.clear();
    for (auto it = overrides.begin(); it != overrides.end(); ++it)
        m_rowHeights.insert(it.key(), std::clamp(it.value(), kMinLaneH, kMaxLaneH));
    applyHeight();
    update();
}

void AutomationArea::State::rebuildRows()
{
    m_rows.clear();
    m_dragRow = -1;
    m_resizeRow = -1;
    m_gesture = Gesture::None;
    m_sweep.clear();
    m_rightPress = false;
    m_selSweep = false;
    m_hoverRow = -1;
    if (m_sv->timeline()) {
        m_rows.push_back({Row::Tempo, nullptr});
        const SongViewModel &model = m_sv->model();
        const int selected = m_sv->selectedTrack();
        // The voice row shows whenever the track has changes; with a
        // document attached it is always present as the place to add one.
        bool voiceRow = m_sv->document() != nullptr;
        for (const VoiceChange &vc : model.voices) {
            if (vc.track == selected) {
                voiceRow = true;
                break;
            }
        }
        if (voiceRow)
            m_rows.push_back({Row::Voice, nullptr});
        for (const AutoLane &lane : model.lanes)
            if (lane.track == selected)
                m_rows.push_back({Row::Lane, &lane});
    }
    applyHeight();
    update();
}

void AutomationArea::State::wheelEvent(QWheelEvent *event)
{
    // Same bindings as the roll's notes area: plain wheel over the plot
    // zooms the timeline; Ctrl+wheel resizes the lane rows (the roll's
    // key-height analog); Shift (or a trackpad's horizontal delta)
    // scrolls horizontally. Over the gutter the wheel pages the lane
    // list vertically via the scroll area.
    const QPoint delta = event->angleDelta();
    const int d = delta.y() ? delta.y() : delta.x();
    if (event->modifiers() & Qt::ControlModifier) {
        zoomLaneHeight(d, int(event->position().y()));
    } else if (event->modifiers() & Qt::ShiftModifier) {
        m_sv->scrollByPx(-d);
    } else if (delta.x() && !delta.y()) {
        m_sv->scrollByPx(-delta.x());
    } else if (event->position().x() < kGutterW) {
        event->ignore();
        return;
    } else {
        m_sv->zoomAroundContentX(std::pow(1.0015, delta.y()),
                                 int(event->position().x()) - kGutterW);
    }
    event->accept();
}

void AutomationArea::State::mousePressEvent(QMouseEvent *event)
{
    // Any press starts a gesture (or a menu); the idle readout would
    // paint stale under it. The next idle move restores it.
    clearHover();
    if (event->button() == Qt::MiddleButton) {
        // Reaper-style pan: drag scrolls the timeline and the lane list.
        // Tracked in global coords — the vertical scroll moves this
        // widget under the cursor, so local deltas would double-count.
        m_panning = true;
        m_panPos = event->globalPosition().toPoint();
        setCursor(Qt::ClosedHandCursor);
        return;
    }
    const int boundary = event->button() == Qt::LeftButton
                             ? rowBoundaryAt(event->pos().y())
                             : -1;
    if (boundary >= 0) {
        // Dragging the divider under a row gives it an individual
        // height, overriding the shared Ctrl+wheel height.
        m_resizeRow = boundary;
        m_resizeOrigH = rowHeight(m_rows[boundary]);
        m_resizePressY = event->pos().y();
        return;
    }
    SongDocument *doc = m_sv->document();
    if (!doc)
        return;
    if (event->button() == Qt::LeftButton
        && addLaneRect().contains(event->pos())) {
        showAddLaneMenu(event->globalPosition().toPoint());
        return;
    }
    const int ri = rowIndexAt(event->pos().y());
    if (ri < 0)
        return;
    setFocus();
    const Row &row = m_rows[ri];
    if (event->pos().x() < kGutterW) {
        if (row.kind == Row::Lane
            && (event->button() == Qt::LeftButton
                || event->button() == Qt::RightButton))
            showLaneMenu(*row.lane, event->globalPosition().toPoint());
        return;
    }
    if (event->button() == Qt::RightButton) {
        // Deferred: a drag from here sweeps a time selection across the
        // crossed rows; releasing in place context-acts (menu inside the
        // selection, point/voice-marker delete elsewhere). Resolved in
        // mouseReleaseEvent.
        m_rightPress = true;
        m_rightPressPos = event->pos();
        m_rightRow = ri;
        m_selAnchorTick = m_sv->snapTick(rawTickAt(event->pos().x()),
                                         event->modifiers() & Qt::AltModifier);
        return;
    }
    if (row.kind == Row::Voice) {
        voiceRowPress(event);
        return;
    }
    uint8_t cc;
    int track;
    if (!rowTarget(row, &cc, &track))
        return;

    if (event->button() != Qt::LeftButton)
        return;
    m_dragRow = ri;
    const bool fine = event->modifiers() & Qt::AltModifier;
    updateDrag(event->pos(), fine, event->modifiers() & Qt::ControlModifier);
    const LanePoint *grab = grabPoint(row, ri, event->pos());
    if (event->modifiers() & Qt::ShiftModifier) {
        // Line ramp: the press anchors one end, release commits the
        // interpolated segment (checked before the point grab so a
        // ramp can start exactly on an existing point).
        m_gesture = Gesture::Line;
        m_lineStartTick = m_dragTick;
        m_lineStartValue = m_dragValue;
    } else if (grab) {
        // Grabbing requires hitting the point's dot (x and y), so a
        // freehand redraw over a dense curve isn't captured by every
        // cell's point — sweeping overwrites them instead.
        m_gesture = Gesture::Point;
        m_dragOrigTick = int64_t(grab->tick);
        // Start from the point's exact position, not the pixel-derived
        // one: a no-motion click (or the first half of a double-click)
        // must not quantize the value to the pixel grid.
        m_dragTick = grab->tick;
        m_dragValue = grab->value;
    } else {
        // Freehand sweep; a no-motion click degenerates to a single
        // point (overwriting any point already on that tick).
        m_gesture = Gesture::Sweep;
        m_dragOrigTick = -1;
        m_sweep.assign(1, {m_dragTick, m_dragValue});
        m_prevTick = rawTickAt(event->pos().x());
        m_prevValue = m_dragValue;
    }
    update();
}

void AutomationArea::State::mouseMoveEvent(QMouseEvent *event)
{
    if (m_panning) {
        const QPoint pos = event->globalPosition().toPoint();
        const QPoint d = pos - m_panPos;
        m_panPos = pos;
        m_sv->scrollByPx(-d.x());
        if (m_scroll) {
            QScrollBar *vbar = m_scroll->verticalScrollBar();
            vbar->setValue(vbar->value() - d.y());
        }
        return;
    }
    if (m_resizeRow >= 0 && m_resizeRow < int(m_rows.size())) {
        const int newH =
            std::clamp(m_resizeOrigH + event->pos().y() - m_resizePressY,
                       kMinLaneH, kMaxLaneH);
        if (newH != rowHeight(m_rows[m_resizeRow])) {
            m_rowHeights.insert(rowKey(m_rows[m_resizeRow]), newH);
            applyHeight();
            update();
        }
        return;
    }
    if (m_rightPress) {
        if (!m_selSweep
            && (event->pos() - m_rightPressPos).manhattanLength()
                   >= QApplication::startDragDistance())
            m_selSweep = true;
        if (m_selSweep)
            updateSelSweep(event);
        return;
    }
    if (m_dragRow < 0) {
        setCursor(rowBoundaryAt(event->pos().y()) >= 0 ? Qt::SplitVCursor
                                                       : Qt::ArrowCursor);
        updateHover(event->pos());
        return;
    }
    const bool fine = event->modifiers() & Qt::AltModifier;
    updateDrag(event->pos(), fine, event->modifiers() & Qt::ControlModifier);
    if (m_gesture == Gesture::Sweep)
        extendSweep(event->pos(), fine);
    update();
}

void AutomationArea::State::mouseReleaseEvent(QMouseEvent *event)
{
    if (event->button() == Qt::MiddleButton && m_panning) {
        m_panning = false;
        setCursor(Qt::ArrowCursor);
        return;
    }
    if (event->button() == Qt::RightButton && m_rightPress) {
        m_rightPress = false;
        if (m_selSweep) {
            m_selSweep = false;
            if (m_sv->timeSelection().active())
                m_sv->announceTimeSelection();
            else
                m_sv->clearTimeSelection();
        } else {
            rightClickInPlace(event);
        }
        return;
    }
    if (event->button() == Qt::LeftButton && m_resizeRow >= 0) {
        m_resizeRow = -1;
        return;
    }
    if (event->button() != Qt::LeftButton || m_dragRow < 0
        || m_dragRow >= int(m_rows.size()))
        return;
    const Row &row = m_rows[m_dragRow];
    const Gesture gesture = m_gesture;
    m_gesture = Gesture::None;
    m_dragRow = -1;
    update();

    SongDocument *doc = m_sv->document();
    uint8_t cc;
    int track;
    if (!doc || !rowTarget(row, &cc, &track))
        return;
    if (gesture == Gesture::Point) {
        if (m_dragOrigTick < 0)
            return;
        DocLanePoint pt;
        // Skip the no-op commit: a plain click on a point (including the
        // first half of a double-click) must not touch the document.
        if (doc->findLanePoint(track, cc, uint64_t(m_dragOrigTick), &pt)
            && (pt.tick != m_dragTick || pt.value != m_dragValue))
            doc->moveLanePoint(track, cc, pt, m_dragTick, m_dragValue);
    } else if (gesture == Gesture::Sweep) {
        // writeLanePoints even for a plain click: it overwrites any
        // point already sitting on the tick instead of duplicating it.
        if (!m_sweep.empty())
            doc->writeLanePoints(track, cc, m_sweep.front().first,
                                 m_sweep.back().first, sweepPoints());
        m_sweep.clear();
    } else if (gesture == Gesture::Line) {
        const bool fine = event->modifiers() & Qt::AltModifier;
        uint64_t a = m_lineStartTick, b = m_dragTick;
        int va = m_lineStartValue, vb = m_dragValue;
        if (a > b) {
            std::swap(a, b);
            std::swap(va, vb);
        }
        if (a == b) {
            doc->writeLanePoints(track, cc, a, a, {{a, vb}});
            return;
        }
        const uint64_t g =
            std::max<uint64_t>(1, fine ? m_sv->fineGridTicks() : m_sv->gridTicksAt(a));
        std::vector<SongDocument::LanePointValue> pts;
        for (uint64_t t = a; t < b; t += g)
            pts.push_back({t, va
                                  + int(std::llround(double(vb - va) * double(t - a)
                                                     / double(b - a)))});
        pts.push_back({b, vb});
        doc->writeLanePoints(track, cc, a, b, pts);
    }
}

void AutomationArea::State::mouseDoubleClickEvent(QMouseEvent *event)
{
    SongDocument *doc = m_sv->document();
    if (!doc || event->button() != Qt::LeftButton
        || event->pos().x() < kGutterW)
        return;
    const int ri = rowIndexAt(event->pos().y());
    if (ri < 0)
        return;
    const Row &row = m_rows[ri];
    uint8_t cc;
    int track;
    if (!rowTarget(row, &cc, &track))
        return;
    // The double-click replaced this pair's second press; drop any
    // half-open gesture so its release is a no-op.
    m_gesture = Gesture::None;
    m_dragRow = -1;
    m_sweep.clear();
    update();

    uint64_t tick;
    int value;
    if (const LanePoint *nearPt = nearestPoint(row, event->pos().x())) {
        tick = nearPt->tick;
        value = nearPt->value;
    } else {
        // The click's point can sit farther than nearestPoint's radius
        // when the snap grid is coarse; re-derive its tick the same way.
        tick = m_sv->snapTick(rawTickAt(event->pos().x()),
                              event->modifiers() & Qt::AltModifier);
        DocLanePoint pt;
        value = doc->findLanePoint(track, cc, tick, &pt)
                    ? pt.value
                    : valueAtY(row, ri, event->pos().y());
    }
    if (!editValue(row, &value))
        return;
    doc->writeLanePoints(track, cc, tick, tick, {{tick, value}});
}

void AutomationArea::State::keyPressEvent(QKeyEvent *event)
{
    if (event->key() == Qt::Key_Escape) {
        m_rightPress = false;
        m_selSweep = false;
        m_sv->clearTimeSelection();
        event->accept();
        return;
    }
    QWidget::keyPressEvent(event);
}

void AutomationArea::State::leaveEvent(QEvent *)
{
    clearHover();
}

void AutomationArea::State::updateSelSweep(QMouseEvent *event)
{
    if (m_rightRow < 0 || m_rightRow >= int(m_rows.size()))
        return;
    const bool fine = event->modifiers() & Qt::AltModifier;
    const uint64_t tick = m_sv->snapTick(rawTickAt(event->pos().x()), fine);
    SongView::TimeSelection sel;
    sel.startTick = std::min(m_selAnchorTick, tick);
    sel.endTick = std::max(m_selAnchorTick, tick);
    sel.scope = SongView::TimeSelection::Lanes;
    int r0 = m_rightRow;
    int r1 = rowIndexAt(
        std::clamp(event->pos().y(), 0, rowTop(int(m_rows.size())) - 1));
    if (r1 < 0)
        r1 = r0;
    if (r0 > r1)
        std::swap(r0, r1);
    for (int ri = r0; ri <= r1 && ri < int(m_rows.size()); ri++)
        sel.lanes.push_back(rowIdentity(m_rows[ri]));
    m_sv->setTimeSelection(sel);
}

QString AutomationArea::State::rowKey(const Row &row) const
{
    switch (row.kind) {
    case Row::Tempo:
        return QStringLiteral("tempo");
    case Row::Voice:
        return QStringLiteral("voice:%1").arg(m_sv->selectedTrack());
    case Row::Lane:
        return QStringLiteral("cc:%1:%2").arg(row.lane->track).arg(row.lane->cc);
    }
    return QString();
}

int AutomationArea::State::rowHeight(const Row &row) const
{
    const auto it = m_rowHeights.constFind(rowKey(row));
    return it != m_rowHeights.constEnd() ? it.value() : m_laneH;
}

int AutomationArea::State::rowTop(int index) const
{
    int y = 0;
    for (int i = 0; i < index && i < int(m_rows.size()); i++)
        y += rowHeight(m_rows[i]);
    return y;
}

int AutomationArea::State::rowBottom(int index) const
{
    return rowTop(index) + rowHeight(m_rows[index]);
}

int AutomationArea::State::rowIndexAt(int y) const
{
    if (y < 0)
        return -1;
    int bottom = 0;
    for (size_t i = 0; i < m_rows.size(); i++) {
        bottom += rowHeight(m_rows[i]);
        if (y < bottom)
            return int(i);
    }
    return -1;
}

int AutomationArea::State::rowBoundaryAt(int y) const
{
    int bottom = 0;
    for (size_t i = 0; i < m_rows.size(); i++) {
        bottom += rowHeight(m_rows[i]);
        if (std::abs(y - bottom) <= 3)
            return int(i);
    }
    return -1;
}

QRect AutomationArea::State::addLaneRect() const
{
    return QRect(0, rowTop(int(m_rows.size())), width(), kAddLaneH);
}

void AutomationArea::State::applyHeight()
{
    // Minimum, not fixed: the scroll area stretches the widget to fill
    // its viewport when the user drags the lanes area taller.
    const int addH = m_sv->timeline() && m_sv->document() ? kAddLaneH : 0;
    m_area->setMinimumHeight(std::max(m_laneH, rowTop(int(m_rows.size())) + addH));
}

void AutomationArea::State::zoomLaneHeight(int wheelDelta, int anchorY)
{
    m_laneZoomAccum += wheelDelta;
    const int steps = m_laneZoomAccum / 120;
    if (steps == 0)
        return;
    m_laneZoomAccum -= steps * 120;
    const int newH = std::clamp(m_laneH + steps * 4, kMinLaneH, kMaxLaneH);
    if (newH == m_laneH)
        return;
    const double factor = double(newH) / double(m_laneH);
    for (auto it = m_rowHeights.begin(); it != m_rowHeights.end(); ++it)
        it.value() = std::clamp(int(std::lround(it.value() * factor)),
                                kMinLaneH, kMaxLaneH);
    m_laneH = newH;
    applyHeight();
    if (m_scroll) {
        QScrollBar *vbar = m_scroll->verticalScrollBar();
        const int viewportY = anchorY - vbar->value();
        vbar->setValue(int(std::lround(anchorY * factor)) - viewportY);
    }
    update();
}

bool AutomationArea::State::voiceChangeNear(int x, DocLanePoint *out) const
{
    SongDocument *doc = m_sv->document();
    if (!doc)
        return false;
    bool found = false;
    int bestDist = 9;
    for (const DocLanePoint &pt :
         doc->lanePoints(m_sv->selectedTrack(), DOC_CC_VOICE)) {
        const int dist = std::abs(kGutterW + m_sv->contentX(double(pt.tick)) - x);
        if (dist < bestDist) {
            bestDist = dist;
            *out = pt;
            found = true;
        }
    }
    return found;
}

void AutomationArea::State::voiceRowPress(QMouseEvent *event)
{
    SongDocument *doc = m_sv->document();
    const int track = m_sv->selectedTrack();
    if (event->button() != Qt::LeftButton)
        return;
    DocLanePoint hitPt;
    if (voiceChangeNear(event->pos().x(), &hitPt)) {
        const DocLanePoint *hit = &hitPt;
        int voice = hit->value;
        if (m_sv->pickVoice(SongView::tr("Change voice"), hit->value, &voice)
            && voice != hit->value)
            doc->moveLanePoint(track, DOC_CC_VOICE, *hit, hit->tick, voice);
    } else {
        const std::vector<DocLanePoint> changes =
            doc->lanePoints(track, DOC_CC_VOICE);
        const uint64_t tick = m_sv->snapTick(
            m_sv->tickAtContentX(std::max(kGutterW, event->pos().x()) - kGutterW));
        // Preselect the voice already sounding at that tick.
        int voice = 0;
        for (const DocLanePoint &pt : changes) {
            if (pt.tick > tick)
                break;
            voice = pt.value;
        }
        if (m_sv->pickVoice(SongView::tr("Insert voice change"), voice, &voice))
            doc->addLanePoint(track, DOC_CC_VOICE, tick, voice);
    }
}

bool AutomationArea::State::rowTarget(const Row &row, uint8_t *cc, int *track) const
{
    if (row.kind == Row::Tempo) {
        *cc = DOC_CC_TEMPO;
        *track = m_sv->selectedTrack();
        return true;
    }
    if (row.kind == Row::Lane) {
        *cc = row.lane->cc; // LANE_CC_BEND == DOC_CC_BEND
        *track = row.lane->track;
        return true;
    }
    return false;
}

const std::vector<LanePoint> *AutomationArea::State::rowPoints(const Row &row) const
{
    if (row.kind == Row::Tempo)
        return &m_sv->model().tempoLane;
    if (row.kind == Row::Lane)
        return &row.lane->points;
    return nullptr;
}

void AutomationArea::State::rowRange(const Row &row, int *minV, int *maxV) const
{
    *minV = 0;
    *maxV = 127;
    if (row.kind == Row::Tempo) {
        *maxV = 200;
        for (const LanePoint &pt : m_sv->model().tempoLane)
            *maxV = std::max(*maxV, pt.value + 20);
    } else if (row.kind == Row::Lane && row.lane->cc == LANE_CC_BEND) {
        *minV = -8192;
        *maxV = 8191;
    }
}

QString AutomationArea::State::rowTitle(const Row &row) const
{
    switch (row.kind) {
    case Row::Tempo:
        return SongView::tr("Tempo (BPM)");
    case Row::Voice:
        return SongView::tr("Voice");
    case Row::Lane: {
        if (row.lane->cc == LANE_CC_BEND)
            return SongView::tr("Pitch bend (BEND)");
        const M4aCcInfo info = m4aClassifyCc(row.lane->cc);
        return QStringLiteral("%1 (%2)").arg(row.lane->name,
                                             QLatin1String(info.name));
    }
    }
    return QString();
}

QString AutomationArea::State::formatRowValue(const Row &row, int v) const
{
    if (row.kind == Row::Lane) {
        if (row.lane->cc == LANE_CC_BEND)
            return m4aFormatBend(v);
        return m4aFormatCcValue(row.lane->cc, uint8_t(v));
    }
    return QString::number(v);
}

bool AutomationArea::State::rowDetent(const Row &row, int *value) const
{
    if (row.kind != Row::Lane)
        return false;
    if (row.lane->cc == 0x0A || row.lane->cc == 0x18) { // PAN/TUNE: c_v 0
        *value = 64;
        return true;
    }
    if (row.lane->cc == LANE_CC_BEND) {
        *value = 0;
        return true;
    }
    return false;
}

bool AutomationArea::State::editValue(const Row &row, int *value)
{
    int minShown = 0, maxShown = 127, offset = 0; // stored = shown + offset
    QString label = SongView::tr("Value:");
    if (row.kind == Row::Tempo) {
        minShown = 1;
        maxShown = 999;
        label = SongView::tr("BPM:");
    } else if (row.lane->cc == LANE_CC_BEND) {
        minShown = -8192;
        maxShown = 8191;
        label = SongView::tr("Bend (0 = none):");
    } else if (row.lane->cc == 0x0A || row.lane->cc == 0x18) {
        minShown = -64;
        maxShown = 63;
        offset = 64;
        label = SongView::tr("c_v value (0 = center):");
    }
    bool ok = false;
    const int shown = QInputDialog::getInt(this, rowTitle(row), label,
                                           *value - offset, minShown,
                                           maxShown, 1, &ok);
    if (ok)
        *value = shown + offset;
    return ok;
}

const LanePoint *AutomationArea::State::nearestPoint(const Row &row, int x) const
{
    const std::vector<LanePoint> *points = rowPoints(row);
    if (!points)
        return nullptr;
    const LanePoint *best = nullptr;
    int bestDist = 9;
    for (const LanePoint &pt : *points) {
        const int dist = std::abs(kGutterW + m_sv->contentX(double(pt.tick)) - x);
        if (dist < bestDist) {
            bestDist = dist;
            best = &pt;
        }
    }
    return best;
}

const LanePoint *AutomationArea::State::grabPoint(const Row &row, int ri, QPoint pos) const
{
    const std::vector<LanePoint> *points = rowPoints(row);
    if (!points)
        return nullptr;
    int minV, maxV;
    rowRange(row, &minV, &maxV);
    // paintCurve's valueY mapping for this row.
    const int top = rowTop(ri) + 5;
    const int bottom = rowBottom(ri) - 1 - 4;
    const LanePoint *best = nullptr;
    int bestDist = INT_MAX;
    for (const LanePoint &pt : *points) {
        const int dx = kGutterW + m_sv->contentX(double(pt.tick)) - pos.x();
        const int dy = bottom
                       - (pt.value - minV) * (bottom - top) / std::max(1, maxV - minV)
                       - pos.y();
        if (std::abs(dx) > 7 || std::abs(dy) > 7)
            continue;
        const int dist = dx * dx + dy * dy;
        if (dist < bestDist) {
            bestDist = dist;
            best = &pt;
        }
    }
    return best;
}

double AutomationArea::State::rawTickAt(int x) const
{
    return std::max(0.0, m_sv->tickAtContentX(std::max(kGutterW, x) - kGutterW));
}

void AutomationArea::State::updateHover(QPoint pos)
{
    const int ri = pos.x() >= kGutterW ? rowIndexAt(pos.y()) : -1;
    if (ri < 0 || !rowPoints(m_rows[ri])) {
        clearHover();
        return;
    }
    const double tick = rawTickAt(pos.x());
    if (ri == m_hoverRow && tick == m_hoverTick)
        return;
    m_hoverRow = ri;
    m_hoverTick = tick;
    update();
}

void AutomationArea::State::clearHover()
{
    if (m_hoverRow < 0)
        return;
    m_hoverRow = -1;
    update();
}

int AutomationArea::State::valueAtY(const Row &row, int ri, int yPos) const
{
    int minV, maxV;
    rowRange(row, &minV, &maxV);
    const int top = rowTop(ri) + 5;
    const int bottom = rowBottom(ri) - 1 - 4;
    const int y = std::clamp(yPos, top, bottom);
    return minV + (bottom - y) * (maxV - minV) / std::max(1, bottom - top);
}

void AutomationArea::State::updateDrag(QPoint pos, bool fine, bool detent)
{
    if (m_dragRow < 0 || m_dragRow >= int(m_rows.size()))
        return;
    const Row &row = m_rows[m_dragRow];
    m_dragValue = valueAtY(row, m_dragRow, pos.y());
    if (row.kind == Row::Tempo)
        m_dragValue = std::max(1, m_dragValue);
    // Ctrl detent: magnetize to the lane's neutral value within ~8 px,
    // so dead-center doesn't require pixel-perfect aim.
    int neutral;
    if (detent && rowDetent(row, &neutral)) {
        int minV, maxV;
        rowRange(row, &minV, &maxV);
        const int plotH = std::max(1, rowHeight(row) - 10); // bottom - top
        if (std::abs(m_dragValue - neutral) <= (maxV - minV) * 8 / plotH)
            m_dragValue = neutral;
    }
    m_dragTick = m_sv->snapTick(rawTickAt(pos.x()), fine);
}

void AutomationArea::State::extendSweep(QPoint pos, bool fine)
{
    const double rawTick = rawTickAt(pos.x());
    const double from = m_prevTick;
    const double to = rawTick;
    const uint64_t t0 = m_sv->snapTick(std::min(from, to), fine);
    const uint64_t t1 = m_sv->snapTick(std::max(from, to), fine);
    const uint64_t g =
        std::max<uint64_t>(1, fine ? m_sv->fineGridTicks() : m_sv->gridTicksAt(t0));
    for (uint64_t t = t0; t <= t1; t += g) {
        int v = m_dragValue;
        if (to != from) {
            const double f =
                std::clamp((double(t) - from) / (to - from), 0.0, 1.0);
            v = m_prevValue + int(std::llround(f * (m_dragValue - m_prevValue)));
        }
        sweepUpsert(t, v);
    }
    m_prevTick = rawTick;
    m_prevValue = m_dragValue;
}

void AutomationArea::State::sweepUpsert(uint64_t tick, int value)
{
    auto it = std::lower_bound(
        m_sweep.begin(), m_sweep.end(), tick,
        [](const std::pair<uint64_t, int> &a, uint64_t t) { return a.first < t; });
    if (it != m_sweep.end() && it->first == tick)
        it->second = value;
    else
        m_sweep.insert(it, {tick, value});
}

std::vector<SongDocument::LanePointValue> AutomationArea::State::sweepPoints() const
{
    std::vector<SongDocument::LanePointValue> pts;
    pts.reserve(m_sweep.size());
    for (const std::pair<uint64_t, int> &s : m_sweep)
        pts.push_back({s.first, s.second});
    return pts;
}

AutomationArea::AutomationArea(SongView *songView, QScrollArea *scrollArea)
    : QWidget(nullptr), m_state(std::make_unique<State>(this, songView, scrollArea))
{
    setFocusProxy(m_state.get());
    m_state->setGeometry(rect());
}

AutomationArea::~AutomationArea() = default;

QSize AutomationArea::minimumSizeHint() const
{
    return QSize(0, std::max(kLaneH + kAddLaneH, minimumHeight()));
}

void AutomationArea::showTimeSelectionContextMenu(const QPoint &globalPosition)
{
    m_state->showTimeSelectionContextMenu(globalPosition);
}

int AutomationArea::laneHeight() const
{
    return m_state->laneHeight();
}

const QHash<QString, int> &AutomationArea::rowHeightOverrides() const
{
    return m_state->rowHeightOverrides();
}

bool AutomationArea::gestureActive() const
{
    return m_state->gestureActive();
}

void AutomationArea::setViewHeights(int laneHeight, const QHash<QString, int> &overrides)
{
    m_state->setViewHeights(laneHeight, overrides);
}

void AutomationArea::rebuildRows()
{
    m_state->rebuildRows();
}

void AutomationArea::refresh()
{
    m_state->update();
}

void AutomationArea::resizeEvent(QResizeEvent *event)
{
    QWidget::resizeEvent(event);
    m_state->setGeometry(rect());
}

} // namespace songview
