#include "ui/editordrawer/tempolane.h"

#include <algorithm>
#include <cmath>

#include <QAction>
#include <QCoreApplication>
#include <QInputDialog>
#include <QMenu>
#include <QMouseEvent>

#include "core/timedefaults.h"
#include "ui/contextmenu.h"
#include "ui/editordrawer/automationarea.h"
#include "ui/editordrawer/automationgesture.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/drawerpage.h"
#include "ui/layout.h"

namespace {

QString translated(const char *text)
{
    return QCoreApplication::translate("AutomationArea", text);
}

EditorAutomationRowId tempoHeightKey()
{
    return {EditorAutomationRowKind::Tempo, 0, 0};
}
int tempoBpmAt(const QRect &body, const AutomationGeometry &geometry, qreal y)
{
    return std::clamp(
        qRound(AutomationProjection::valueAtY(body, geometry, CoreTimeDefaults::kMinTempoBpm,
                                              CoreTimeDefaults::kMaxTempoBpm, y)),
        CoreTimeDefaults::kMinTempoBpm, CoreTimeDefaults::kMaxTempoBpm);
}

} // namespace

TempoLane::TempoLane(AutomationPage *page) noexcept : m_page(page) {}

void TempoLane::updateLayout(int width, const AutomationGeometry &geometry)
{
    const int header = headerHeight(geometry);
    m_header = {layout::space(layout::Space::Zero), layout::space(layout::Space::Zero), width,
                header};
    m_body = {layout::space(layout::Space::Zero), header, width,
              m_expanded ? bodyHeight(geometry) : 0};
}

int TempoLane::totalHeight(const AutomationGeometry &geometry) const
{
    return headerHeight(geometry) + (m_expanded ? bodyHeight(geometry) : 0);
}

bool TempoLane::interactionActive() const noexcept
{
    return m_drag.has_value() || m_draw.has_value() || m_band.pending;
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
    m_drag.reset();
    m_draw.reset();
    m_band = {};
}

void TempoLane::clearHover()
{
    m_hoveredPoint.reset();
}

bool TempoLane::mousePress(AutomationArea &area, QMouseEvent *event,
                           const AutomationGeometry &geometry)
{
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
    const auto hit = hitPoint(event->position(), projection, geometry, area.devicePixelRatioF());
    if (hit) {
        const TempoPoint point = m_page->document()->tempoPoints()[*hit];
        m_drag = DragState{point, point, event->position()};
        return true;
    }
    const TempoPoint point{
        projection.snapTickAt(event->position().x(), event->modifiers() & Qt::AltModifier),
        CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(
            tempoBpmAt(m_body, geometry, event->position().y()))};
    DrawState draw;
    draw.previous = point;
    appendDrawPoint(draw, point);
    m_draw = std::move(draw);
    return true;
}

bool TempoLane::mouseMove(AutomationArea &area, QMouseEvent *event,
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
    if (m_drag) {
        const TempoPoint original = m_drag->original;
        TempoPoint next{
            projection.snapTickAt(event->position().x(), event->modifiers() & Qt::AltModifier),
            CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(
                tempoBpmAt(m_body, geometry, event->position().y()))};
        const qreal dx = event->position().x() - m_drag->pressPosition.x();
        const qreal dy = event->position().y() - m_drag->pressPosition.y();
        if ((event->modifiers() & Qt::ShiftModifier && std::abs(dx) >= std::abs(dy)) ||
            std::abs(dy) <= layout::singlePixel())
            next.microsecondsPerQuarterNote = original.microsecondsPerQuarterNote;
        if (event->modifiers() & Qt::ShiftModifier && std::abs(dy) > std::abs(dx))
            next.tick = original.tick;
        m_drag->current = next;
        return true;
    }
    if (m_draw) {
        const TempoPoint next{
            projection.snapTickAt(event->position().x(), event->modifiers() & Qt::AltModifier),
            CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(
                tempoBpmAt(m_body, geometry, event->position().y()))};
        m_draw->moved = m_draw->moved || next != m_draw->previous;
        appendDrawSegment(*m_draw, next, event->modifiers() & Qt::AltModifier);
        return true;
    }
    if (!contains(event->pos()))
        return false;
    m_hoveredPoint = containsBody(event->position()) ? hitPoint(event->position(), projection,
                                                                geometry, area.devicePixelRatioF())
                                                     : std::nullopt;
    return true;
}

bool TempoLane::mouseRelease(AutomationArea &area, QMouseEvent *event,
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
    if (event->button() != Qt::LeftButton)
        return false;
    if (m_drag) {
        const DragState drag = *m_drag;
        m_drag.reset();
        if (drag.current != drag.original)
            applyEdit({{drag.original}, {drag.current}});
        return true;
    }
    if (m_draw) {
        DrawState draw = std::move(*m_draw);
        m_draw.reset();
        if (draw.moved && !draw.points.empty()) {
            const uint64_t first = draw.points.front().tick;
            const uint64_t last = draw.points.back().tick;
            TempoEdit edit;
            for (const TempoPoint &point : m_page->document()->tempoPoints())
                if (point.tick >= first && point.tick <= last)
                    edit.remove.push_back(point);
            edit.add = std::move(draw.points);
            applyEdit(edit);
        } else {
            m_page->commitEditCursor(draw.previous.tick);
        }
        return true;
    }
    return false;
}

bool TempoLane::mouseDoubleClick(AutomationArea &area, QMouseEvent *event,
                                 const AutomationGeometry &geometry)
{
    if (!m_page || !m_page->document() || event->button() != Qt::LeftButton ||
        !containsBody(event->position()) || event->position().x() < geometry.plotOrigin)
        return false;
    const AutomationProjection projection(geometry, {}, m_page, 0);
    if (hitPoint(event->position(), projection, geometry, area.devicePixelRatioF()))
        return true;
    const uint64_t tick =
        projection.snapTickAt(event->position().x(), event->modifiers() & Qt::AltModifier);
    int bpm = tempoBpmAt(m_body, geometry, event->position().y());
    if (!promptBpm(area, bpm, &bpm))
        return true;
    applyEdit({{}, {{tick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(bpm)}}});
    return true;
}

int TempoLane::headerHeight(const AutomationGeometry &geometry) const
{
    return geometry.rowDefaultHeight;
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

std::optional<std::size_t> TempoLane::hitPoint(const QPointF &position,
                                               const AutomationProjection &projection,
                                               const AutomationGeometry &geometry,
                                               qreal devicePixelRatio) const
{
    if (!m_page || !m_page->document() || !containsBody(position))
        return std::nullopt;
    return nearestPointInRadius(
        m_page->document()->tempoPoints(), projection.rawTickAt(position.x()), position,
        geometry.pointHitRadius,
        [&projection, devicePixelRatio](const TempoPoint &point) {
            return projection.displayX(point.tick, devicePixelRatio);
        },
        [this, &geometry](const TempoPoint &point) {
            return AutomationProjection::valueY(
                m_body, geometry, CoreTimeDefaults::kMinTempoBpm, CoreTimeDefaults::kMaxTempoBpm,
                CoreTimeDefaults::tempoBpm(point.microsecondsPerQuarterNote));
        });
}

bool TempoLane::promptBpm(AutomationArea &area, int currentBpm, int *bpm) const
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

void TempoLane::appendDrawPoint(DrawState &draw, TempoPoint point)
{
    upsertByTick(draw.points, std::move(point));
}

void TempoLane::appendDrawSegment(DrawState &draw, TempoPoint next, bool fine)
{
    const TempoPoint previous = draw.previous;
    const uint64_t first = std::min(previous.tick, next.tick);
    const uint64_t last = std::max(previous.tick, next.tick);
    if (first == last) {
        appendDrawPoint(draw, next);
        draw.previous = next;
        return;
    }
    const int previousBpm = qRound(CoreTimeDefaults::tempoBpm(previous.microsecondsPerQuarterNote));
    const int nextBpm = qRound(CoreTimeDefaults::tempoBpm(next.microsecondsPerQuarterNote));
    for (uint64_t tick = first;;) {
        const double fraction = double(int64_t(tick) - int64_t(previous.tick)) /
                                double(int64_t(next.tick) - int64_t(previous.tick));
        const int bpm = std::clamp(qRound(previousBpm + fraction * (nextBpm - previousBpm)),
                                   CoreTimeDefaults::kMinTempoBpm, CoreTimeDefaults::kMaxTempoBpm);
        appendDrawPoint(draw, {tick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(bpm)});
        if (tick == last)
            break;
        const uint64_t following = m_page->nextGridTick(tick, fine, last);
        if (following <= tick)
            break;
        tick = following;
    }
    draw.previous = next;
}

void TempoLane::applyEdit(const TempoEdit &edit) const
{
    if (edit.empty() || !m_page || !m_page->document())
        return;
    m_page->document()->applyTempoEdit(edit);
    m_page->requestRefresh();
}

void TempoLane::showTempoMenu(AutomationArea &area, const QPoint &globalPosition)
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

void TempoLane::showPointMenu(AutomationArea &area, std::size_t pointIndex,
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
