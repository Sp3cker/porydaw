#include "ui/editordrawer/tempolane.h"

#include <algorithm>
#include <optional>

#include <QAction>
#include <QCoreApplication>
#include <QFont>
#include <QInputDialog>
#include <QMenu>
#include <QPainter>
#include <QPolygon>

#include "core/timedefaults.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/drawerpage.h"
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

void TempoLane::updateLayout(int width, int top, const AutomationGeometry &geometry)
{
    // Expanded, the lane is a single automation row: the header shrinks to
    // that row's label gutter (the collapse click target) while the body
    // spans the full row. Collapsed, only a thin caption strip remains.
    const int height = totalHeight(geometry);
    m_header = {layout::space(layout::Space::Zero), top, m_expanded ? geometry.plotOrigin : width,
                height};
    m_body = {layout::space(layout::Space::Zero), top, width, m_expanded ? height : 0};
}

int TempoLane::totalHeight(const AutomationGeometry &geometry) const
{
    return m_expanded ? bodyHeight(geometry) : collapsedHeight(geometry);
}

bool TempoLane::containsHeader(const QPoint &position) const
{
    return m_header.contains(position);
}

void TempoLane::toggleExpanded()
{
    m_expanded = !m_expanded;
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

void TempoLane::cancel() {}

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

void TempoLane::paint(QPainter &painter, const AutomationGeometry &geometry,
                      const QRect &labelGutter, const QFont &titleFont, const QFont &captionFont)
{
    if (!m_page || !m_page->ready() || !m_page->timeline() || !m_page->document())
        return;
    const AutomationProjection projection(geometry, m_page);
    const qreal dpr = painter.device()->devicePixelRatioF();
    const auto &points = m_page->document()->tempoPoints();
    const auto selectedRange = [&] {
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
}
