#include "ui/editordrawer/tempolane.h"

#include <algorithm>
#include <cmath>

#include <QAction>
#include <QCoreApplication>
#include <QInputDialog>
#include <QMenu>
#include <QMouseEvent>
#include <QPainter>
#include <QPen>
#include <QPolygon>

#include "core/timedefaults.h"
#include "ui/contextmenu.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationgesture.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/drawerpage.h"
#include "ui/editordrawer/nodelane/hover.h"
#include "ui/editordrawer/nodelane/paint.h"

#include "ui/layout.h"
#include "ui/songview/editorselectionmodel.h"
#include "ui/theme/themeruntime.h"

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
    return false;
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

void TempoLane::paint(QPainter &painter, const AutomationGeometry &geometry,
                      const QRect &labelGutter, const QFont &titleFont, const QFont &captionFont,
                      const NodeLaneHoverState &hoverState, bool pencilMode)
{
    if (!m_page || !m_page->ready() || !m_page->timeline() || !m_page->document())
        return;
    const AutomationProjection projection(geometry, {}, m_page, 0);
    const qreal dpr = painter.device()->devicePixelRatioF();
    const auto &points = m_page->document()->tempoPoints();
    const auto selectedRange = [&] {
        if (m_band.active)
            return AutomationCanvas::TickRange::orderedNonEmpty(m_band.startTick, m_band.endTick);
        if (!hasTimeSelection())
            return std::optional<AutomationCanvas::TickRange>{};
        const auto &selection = m_page->m_owner.selectionModel().timeSelection();
        return AutomationCanvas::TickRange::orderedNonEmpty(selection.startTick, selection.endTick);
    }();
    const QRect band = m_expanded ? m_body : m_header;
    painter.save();
    painter.setClipRect(band, Qt::IntersectClip);
    painter.fillRect(band, themes::color(themes::Role::song_view_piano_roll_background));
    painter.setPen(themes::color(themes::Role::song_view_separator));
    painter.drawLine(band.left(), band.bottom(), band.right(), band.bottom());
    painter.restore();
    if (!m_expanded && selectedRange)
        AutomationCanvas::paintSelectionReticle(painter, *selectedRange, projection, band, dpr);
    painter.save();
    painter.setClipRect(QRect(labelGutter.x(), band.top(), labelGutter.width(), band.height()),
                        Qt::IntersectClip);
    const QRect strip(band.left(), band.top(), band.width(), geometry.addLaneStripHeight);
    const int arrowSize = std::max(layout::fontPx(0.5), strip.height() / 3);
    const QRect arrow(labelGutter.left(), strip.center().y() - arrowSize / 2, arrowSize, arrowSize);
    const QPolygon triangle = m_expanded ? QPolygon{{arrow.left(), arrow.top()},
                                                    {arrow.right(), arrow.top()},
                                                    {arrow.center().x(), arrow.bottom()}}
                                         : QPolygon{{arrow.left(), arrow.top()},
                                                    {arrow.right(), arrow.center().y()},
                                                    {arrow.left(), arrow.bottom()}};
    painter.setPen(Qt::NoPen);
    painter.setBrush(themes::color(themes::Role::song_view_primary_text));
    painter.drawPolygon(triangle);
    const QRect textBounds(
        labelGutter.x() + arrowSize + layout::space(layout::Space::One), strip.top(),
        std::max(0, labelGutter.width() - arrowSize - layout::space(layout::Space::One)),
        strip.height());
    painter.setFont(m_expanded ? titleFont : captionFont);
    painter.setPen(themes::color(themes::Role::song_view_primary_text));
    painter.drawText(textBounds, Qt::AlignLeft | Qt::AlignVCenter,
                     QCoreApplication::translate("AutomationCanvas", "Tempo (BPM)"));
    if (m_expanded) {
        const QRect summaryBounds(textBounds.x(), strip.top() + strip.height(), textBounds.width(),
                                  strip.height());
        painter.setFont(captionFont);
        painter.setPen(themes::color(themes::Role::song_view_secondary_text));
        painter.drawText(summaryBounds, Qt::AlignLeft | Qt::AlignVCenter,
                         QCoreApplication::translate("AutomationCanvas", "%n point(s)", nullptr,
                                                     int(points.size())));
    }
    painter.restore();
    if (!m_expanded)
        return;
    const QRect plot = nodelane::plotRect(m_body, geometry);
    painter.save();
    painter.setClipRect(m_body, Qt::IntersectClip);
    painter.save();
    painter.setClipRect(plot, Qt::IntersectClip);
    if (!m_page->paintGrid(painter, plot, geometry.plotOrigin))
        AutomationCanvas::paintPlainGridFallback(painter, plot, *m_page, geometry.plotOrigin, dpr);
    painter.restore();
    std::optional<NodePoint> leadIn;
    if (!points.empty() && points.front().tick > 0)
        leadIn = NodePoint{0, CoreTimeDefaults::kTempoBpm};
    const NodeDragGesture *nodeDrag = nullptr;
    const SweepGesture *sweep = nullptr;
    if (m_activeGesture) {
        nodeDrag = std::get_if<NodeDragGesture>(&*m_activeGesture);
        sweep = std::get_if<SweepGesture>(&*m_activeGesture);
    }
    const bool bandLane = m_band.active;
    const uint64_t bandFirst = std::min(m_band.startTick, m_band.endTick);
    const uint64_t bandLast = std::max(m_band.startTick, m_band.endTick);
    bool multipleSelectedNodes = false;
    int selectedCount = 0;
    for (const TempoPoint &point : points) {
        if (!pointInTimeSelection(point.tick) &&
            !(bandLane && point.tick >= bandFirst && point.tick < bandLast))
            continue;
        if (++selectedCount > 1) {
            multipleSelectedNodes = true;
            break;
        }
    }
    const QColor color = themes::color(themes::Role::song_view_automation_tempo_curve);
    nodelane::paintNodeLane(painter, nodelane::NodeLanePaint{
                                         .lane = *this,
                                         .body = m_body,
                                         .geometry = geometry,
                                         .projection = projection,
                                         .color = color,
                                         .leadIn = leadIn,
                                         .handle = LaneHandle{0},
                                         .hoverState = hoverState,
                                         .nodeDrag = nodeDrag,
                                         .sweep = sweep,
                                         .gestureRow = 0,
                                         .pencilMode = pencilMode,
                                         .multipleSelectedNodes = multipleSelectedNodes,
                                         .selectedLane = hasTimeSelection() || bandLane,
                                         .bandLane = bandLane,
                                         .bandFirstTick = bandFirst,
                                         .bandLastTick = bandLast,
                                         .preparedPreviewCurve = true,
                                         .selectedColor = m_page->palette().highlight().color(),
                                         .dimmedColor = color,
                                     });
    painter.save();
    painter.setClipRect(plot, Qt::IntersectClip);
    AutomationCanvas::paintEditCursor(painter, plot,
                                      projection.displayX(m_page->liveState().editCursorTick, dpr));
    painter.restore();
    if (selectedRange)
        AutomationCanvas::paintSelectionReticle(painter, *selectedRange, projection, plot, dpr);
    painter.restore();
}
