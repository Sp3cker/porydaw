#include "ui/editordrawer/tempolane.h"

#include <algorithm>
#include <cmath>
#include <set>

#include <QAction>
#include <QCoreApplication>
#include <QInputDialog>
#include <QMenu>
#include <QMouseEvent>

#include "core/timedefaults.h"
#include "ui/contextmenu.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationgesture.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/drawerpage.h"
#include "ui/layout.h"
#include "ui/songview/editorselectionmodel.h"

namespace {

QString translated(const char *text)
{
    return QCoreApplication::translate("AutomationCanvas", text);
}

EditorAutomationRowId tempoHeightKey()
{
    return {EditorAutomationRowKind::Tempo, 0, 0};
}

} // namespace

TempoLane::TempoLane(AutomationPage *page) noexcept : m_page(page) {}

TempoLane::TempoLane(SongDocument &document, const songview::EditorSelectionModel &selection,
                     uint32_t usedTrackMask) noexcept
    : m_document(&document)
    , m_selection(&selection)
    , m_usedTrackMask(usedTrackMask)
{}

QString TempoLane::title() const
{
    return QCoreApplication::translate("AutomationCanvas", "Tempo (BPM)");
}

std::vector<NodePoint> TempoLane::points() const
{
    std::vector<NodePoint> points;
    const SongDocument *document = boundDocument();
    if (!document)
        return points;
    const auto &tempoPoints = document->tempoPoints();
    points.reserve(tempoPoints.size());
    for (const TempoPoint &point : tempoPoints)
        points.push_back(
            {point.tick, qRound(CoreTimeDefaults::tempoBpm(point.microsecondsPerQuarterNote))});
    return points;
}

int TempoLane::minimumValue() const
{
    return CoreTimeDefaults::kMinTempoBpm;
}

int TempoLane::maximumValue() const
{
    return CoreTimeDefaults::kMaxTempoBpm;
}

QString TempoLane::valueText(int value) const
{
    return QString::number(value);
}

bool TempoLane::pointSelected(uint64_t tick) const
{
    const auto *selection = boundSelection();
    if (!selection || !selection->timeSelectionCoversTempo(boundUsedTrackMask()))
        return false;
    const auto &range = selection->timeSelection();
    return tick >= range.startTick && tick < range.endTick;
}

void TempoLane::deletePoints(const std::vector<uint64_t> &ticks)
{
    SongDocument *document = boundDocument();
    if (!document || ticks.empty())
        return;
    const std::set<uint64_t> tickSet(ticks.begin(), ticks.end());
    TempoEdit edit;
    for (const TempoPoint &point : document->tempoPoints()) {
        if (tickSet.contains(point.tick))
            edit.remove.push_back(point);
    }
    if (edit.empty())
        return;
    document->applyTempoEdit(edit);
    if (m_page)
        m_page->requestRefresh();
}

void TempoLane::movePoints(const std::vector<NodePointMove> &moves)
{
    SongDocument *document = boundDocument();
    if (!document || moves.empty())
        return;
    const auto &tempoPoints = document->tempoPoints();
    TempoEdit edit;
    for (const NodePointMove &move : moves) {
        const TempoPoint *source = nullptr;
        for (const TempoPoint &point : tempoPoints) {
            if (point.tick == move.fromTick) {
                source = &point;
                break;
            }
        }
        if (!source)
            continue;
        const int currentBpm =
            qRound(CoreTimeDefaults::tempoBpm(source->microsecondsPerQuarterNote));
        TempoPoint destination{move.to.tick, source->microsecondsPerQuarterNote};
        if (move.to.value != currentBpm)
            destination.microsecondsPerQuarterNote =
                CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(move.to.value);
        if (destination == *source)
            continue;
        edit.remove.push_back(*source);
        edit.add.push_back(destination);
    }
    if (edit.empty())
        return;
    document->applyTempoEdit(edit);
    if (m_page)
        m_page->requestRefresh();
}

void TempoLane::replaceSpan(uint64_t first, uint64_t last, const std::vector<NodePoint> &points)
{
    SongDocument *document = boundDocument();
    if (!document)
        return;
    const auto &tempoPoints = document->tempoPoints();
    TempoEdit edit;
    for (const TempoPoint &point : tempoPoints) {
        if (point.tick >= first && point.tick <= last)
            edit.remove.push_back(point);
    }
    edit.add.reserve(points.size());
    for (const NodePoint &point : points)
        edit.add.push_back(
            {point.tick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(point.value)});
    document->applyTempoEdit(edit);
    if (m_page)
        m_page->requestRefresh();
}

void TempoLane::updateLayout(int width, const AutomationGeometry &geometry)
{
    // Expanded, the lane is a single automation row: the header shrinks to
    // that row's label gutter (the collapse click target) while the body
    // spans the full row. Collapsed, only a thin caption strip remains.
    const int height = totalHeight(geometry);
    m_header = {layout::space(layout::Space::Zero), layout::space(layout::Space::Zero),
                m_expanded ? geometry.plotOrigin : width, height};
    m_body = {layout::space(layout::Space::Zero), layout::space(layout::Space::Zero), width,
              m_expanded ? height : 0};
}

int TempoLane::totalHeight(const AutomationGeometry &geometry) const
{
    return m_expanded ? bodyHeight(geometry) : collapsedHeight(geometry);
}

bool TempoLane::interactionActive() const noexcept
{
    return m_activeGesture.has_value() || m_band.pending;
}

bool TempoLane::hasTimeSelection() const
{
    if (!m_page)
        return false;
    const auto &selection = m_page->m_owner.selectionModel();
    return selection.timeSelectionCoversTempo(m_page->usedTrackMask());
}

bool TempoLane::selectionContains(const AutomationProjection &projection, qreal x,
                                  qreal devicePixelRatio) const
{
    if (!hasTimeSelection())
        return false;
    const auto &selection = m_page->m_owner.selectionModel().timeSelection();
    const qreal first = projection.displayX(selection.startTick, devicePixelRatio);
    const qreal last = projection.displayX(selection.endTick, devicePixelRatio);
    return x >= std::min(first, last) && x < std::max(first, last);
}

void TempoLane::cancel()
{
    m_activeGesture.reset();
    m_activeNodeIdentities.clear();
    m_band.clear();
    m_deletedNodeClick.clear();
}

void TempoLane::clearHover()
{
    m_hoveredPoint.reset();
}

bool TempoLane::mousePress(AutomationCanvas &area, QMouseEvent *event,
                           const AutomationGeometry &geometry)
{
    m_deletedNodeClick.clear();
    m_activeNodeIdentities.clear();
    if (!m_page || !m_page->document() || !contains(event->pos()))
        return false;
    const AutomationProjection projection(geometry, {}, m_page, 0);
    if ((event->button() == Qt::LeftButton || event->button() == Qt::RightButton) &&
        m_page->m_owner.selectionModel().timeSelection().active() &&
        (!hasTimeSelection() ||
         !selectionContains(projection, event->position().x(), area.devicePixelRatioF())))
        m_page->m_owner.selectionModel().clearTimeSelection();
    const bool inHeader = m_header.contains(event->pos());
    const bool inBody = containsBody(event->position());
    if (event->button() == Qt::RightButton &&
        (inHeader || (inBody && event->position().x() >= geometry.plotOrigin))) {
        m_band.press(event->pos(), projection.snapTickAt(event->position().x(),
                                                         event->modifiers() & Qt::AltModifier));
        if (!inHeader)
            m_hoveredPoint =
                hitPoint(event->position(), projection, geometry, area.devicePixelRatioF());
        return true;
    }
    if (inHeader) {
        if (event->button() == Qt::LeftButton) {
            m_expanded = !m_expanded;
            cancel();
            area.updateTempoLayout();
        }
        return true;
    }
    if (!inBody)
        return true;
    if (event->position().x() < geometry.plotOrigin) {
        if (event->button() == Qt::RightButton)
            showTempoMenu(area, event->globalPosition().toPoint());
        return true;
    }
    if (event->button() != Qt::LeftButton)
        return true;
    if (auto nodeDrag = nodeDragGestureAt(event->position(), event->modifiers() & Qt::ShiftModifier,
                                          projection, geometry, area.devicePixelRatioF())) {
        m_activeNodeIdentities = std::move(nodeDrag->identities);
        m_activeGesture.emplace(std::move(nodeDrag->gesture));
        return true;
    }
    const ValuePoint mapped =
        mappedPoint(event->position(), projection, geometry, event->modifiers() & Qt::AltModifier);
    SweepGesture sweep;
    sweep.row = 0;
    sweep.mode = event->modifiers() & Qt::ShiftModifier ? SweepGesture::Mode::Ramp
                                                        : SweepGesture::Mode::Drag;
    sweep.anchor = mapped;
    sweep.current = mapped;
    sweep.previousRawTick = projection.rawTickAt(event->position().x());
    sweep.previousValue = mapped.value;
    sweep.pressPosition = event->position();
    sweep.slop.origin = event->position();
    if (sweep.mode == SweepGesture::Mode::Ramp)
        sweep.slop.markExceeded(event->position());
    m_activeGesture.emplace(std::move(sweep));
    return true;
}

bool TempoLane::mouseMove(AutomationCanvas &area, QMouseEvent *event,
                          const AutomationGeometry &geometry)
{
    if (!m_page || !m_page->document())
        return false;
    const AutomationProjection projection(geometry, {}, m_page, 0);
    if (m_band.pending) {
        if (!(event->buttons() & Qt::RightButton)) {
            m_band.clear();
            return true;
        }
        m_band.move(event->pos(), projection.snapTickAt(event->position().x(),
                                                        event->modifiers() & Qt::AltModifier));
        return true;
    }
    if (m_activeGesture) {
        updateActiveGesture(area, event->position(), event->modifiers(), geometry, true);
        return true;
    }
    if (!contains(event->pos()))
        return false;
    m_hoveredPoint = containsBody(event->position()) ? hitPoint(event->position(), projection,
                                                                geometry, area.devicePixelRatioF())
                                                     : std::nullopt;
    return true;
}

bool TempoLane::mouseRelease(AutomationCanvas &area, QMouseEvent *event,
                             const AutomationGeometry &geometry)
{
    if (!m_page || !m_page->document())
        return false;
    const AutomationProjection projection(geometry, {}, m_page, 0);
    if (event->button() == Qt::RightButton && m_band.pending) {
        const auto selection = m_band.release();
        if (selection && selection->first < selection->second) {
            publishTimeSelection(selection->first, selection->second);
            return true;
        }
        if (selectionContains(projection, event->position().x(), area.devicePixelRatioF())) {
            showTimeSelectionMenu(event->globalPosition().toPoint());
            return true;
        }
        if (m_header.contains(event->pos()) || event->position().x() < geometry.plotOrigin) {
            showTempoMenu(area, event->globalPosition().toPoint());
            return true;
        }
        if (const auto hit =
                hitPoint(event->position(), projection, geometry, area.devicePixelRatioF())) {
            showPointMenu(area, *hit, event->globalPosition().toPoint());
            return true;
        }
        return true;
    }
    if (event->button() != Qt::LeftButton || !m_activeGesture)
        return false;
    updateActiveGesture(area, event->position(), event->modifiers(), geometry, false);
    finishActiveGesture(event->modifiers() & Qt::AltModifier, geometry);
    m_activeGesture.reset();
    m_activeNodeIdentities.clear();
    area.updateAxisLockCursor(AxisLock::None);
    return true;
}

bool TempoLane::mouseDoubleClick(AutomationCanvas &area, QMouseEvent *event,
                                 const AutomationGeometry &geometry)
{
    if (!m_page || !m_page->document() || event->button() != Qt::LeftButton)
        return false;
    if (m_deletedNodeClick.consume())
        return true;
    // Qt delivers a stationary second click as MouseButtonDblClick, so header
    // double-clicks must reuse the press path or the toggle needs a mouse move.
    if (m_header.contains(event->pos()))
        return mousePress(area, event, geometry);
    if (!containsBody(event->position()) || event->position().x() < geometry.plotOrigin)
        return false;
    const AutomationProjection projection(geometry, {}, m_page, 0);
    if (hitPoint(event->position(), projection, geometry, area.devicePixelRatioF()))
        return true;
    const uint64_t tick =
        projection.snapTickAt(event->position().x(), event->modifiers() & Qt::AltModifier);
    int bpm = bpmAt(event->position().y(), geometry);
    if (!promptBpm(area, bpm, &bpm))
        return true;
    applyEdit({{}, {{tick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(bpm)}}});
    return true;
}

int TempoLane::collapsedHeight(const AutomationGeometry &geometry) const
{
    return geometry.addLaneStripHeight;
}

int TempoLane::bodyHeight(const AutomationGeometry &geometry) const
{
    if (!m_page)
        return geometry.rowDefaultHeight;
    return std::clamp(m_page->laneHeightFor(tempoHeightKey()), geometry.rowMinimumHeight,
                      geometry.rowMaximumHeight);
}

bool TempoLane::contains(const QPoint &position) const
{
    return m_header.contains(position) || (m_expanded && m_body.contains(position));
}

bool TempoLane::containsBody(const QPointF &position) const
{
    return m_expanded && m_body.contains(position.toPoint());
}

bool TempoLane::promptBpm(AutomationCanvas &area, int currentBpm, int *bpm) const
{
    bool accepted = false;
    const int entered = QInputDialog::getInt(
        &area, translated("Set tempo"), translated("BPM:"),
        std::clamp(currentBpm, CoreTimeDefaults::kMinTempoBpm, CoreTimeDefaults::kMaxTempoBpm),
        CoreTimeDefaults::kMinTempoBpm, CoreTimeDefaults::kMaxTempoBpm, 1, &accepted);
    if (!accepted)
        return false;
    *bpm = entered;
    return true;
}

void TempoLane::applyEdit(const TempoEdit &edit) const
{
    if (edit.empty() || !m_page || !m_page->document())
        return;
    m_page->document()->applyTempoEdit(edit);
    m_page->requestRefresh();
}

void TempoLane::showTempoMenu(AutomationCanvas &area, const QPoint &globalPosition)
{
    if (!m_page || !m_page->document())
        return;
    const auto &points = m_page->document()->tempoPoints();
    QMenu menu(&area);
    QAction *copy = menu.addAction(translated("Copy"));
    copy->setEnabled(!points.empty());
    QAction *paste = menu.addAction(translated("Paste"));
    paste->setEnabled(!m_clipboard.empty());
    menu.addSeparator();
    QAction *clear = menu.addAction(translated("Clear Tempo"));
    QAction *chosen = menu.exec(globalPosition);
    if (chosen == copy) {
        m_clipboard = points;
        m_page->announce(translated("Copied Tempo"));
    } else if (chosen == paste) {
        TempoEdit edit;
        edit.remove = points;
        edit.add = m_clipboard;
        applyEdit(edit);
        m_page->announce(translated("Pasted Tempo"));
    } else if (chosen == clear) {
        TempoEdit edit;
        edit.remove = points;
        applyEdit(edit);
        m_page->announce(translated("Cleared Tempo"));
    }
}

void TempoLane::showPointMenu(AutomationCanvas &area, std::size_t pointIndex,
                              const QPoint &globalPosition)
{
    if (!m_page || !m_page->document())
        return;
    const auto &points = m_page->document()->tempoPoints();
    if (pointIndex >= points.size())
        return;
    const TempoPoint point = points[pointIndex];
    ui::ContextMenu menu(&area);
    QAction *setValue = menu.addAction(translated("Set Value"));
    QAction *remove = menu.addAction(translated("Delete"));
    QAction *chosen = menu.exec(globalPosition);
    if (chosen == setValue) {
        int bpm = qRound(CoreTimeDefaults::tempoBpm(point.microsecondsPerQuarterNote));
        if (!promptBpm(area, bpm, &bpm))
            return;
        const TempoPoint replacement{point.tick,
                                     CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(bpm)};
        if (replacement != point)
            applyEdit({{point}, {replacement}});
    } else if (chosen == remove) {
        TempoEdit edit;
        edit.remove.push_back(point);
        applyEdit(edit);
    }
}

void TempoLane::showTimeSelectionMenu(const QPoint &globalPosition) const
{
    if (!m_page || !hasTimeSelection())
        return;
    const auto &selection = m_page->m_owner.selectionModel().timeSelection();
    DrawerPageTimeSelectionMenuRequest request;
    request.startTick = selection.startTick;
    request.endTick = selection.endTick;
    request.tempo = true;
    request.globalPosition = globalPosition;
    m_page->showTimeSelectionMenu(request);
}

void TempoLane::publishTimeSelection(uint64_t first, uint64_t last) const
{
    if (!m_page || first >= last)
        return;
    m_page->publishTimeSelection(first, last, {}, true);
    m_page->announce(translated("Tempo range [%1, %2)").arg(first).arg(last));
}

QString TempoLane::bpmText(uint32_t microsecondsPerQuarterNote) const
{
    const double bpm = CoreTimeDefaults::tempoBpm(microsecondsPerQuarterNote);
    const double rounded = std::round(bpm);
    return bpm == rounded ? QString::number(int(rounded)) : QString::number(bpm, 'f', 2);
}

SongDocument *TempoLane::boundDocument() const noexcept
{
    return m_page ? m_page->document() : m_document;
}

const songview::EditorSelectionModel *TempoLane::boundSelection() const noexcept
{
    return m_page ? &m_page->m_owner.selectionModel() : m_selection;
}

uint32_t TempoLane::boundUsedTrackMask() const noexcept
{
    return m_page ? m_page->usedTrackMask() : m_usedTrackMask;
}
