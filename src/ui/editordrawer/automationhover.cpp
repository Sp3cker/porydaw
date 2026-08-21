#include "ui/editordrawer/automationhover.h"

#include <algorithm>
#include <cmath>
#include <variant>

#include <QFontMetrics>
#include <QRegion>

#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/automationrows.h"
#include "ui/layout.h"
#include "ui/typography.h"

namespace {

template <class... Ts>
struct Visitor : Ts... {
    using Ts::operator()...;
};
template <class... Ts>
Visitor(Ts...) -> Visitor<Ts...>;

} // namespace

double AutomationHoverState::hoverTick(const AutomationProjection &projection) const
{
    return hover.hasPoint ? double(hover.point.tick) : projection.rawTickAt(hover.pos.x());
}

double AutomationHoverState::insertionTick(const AutomationProjection &projection,
                                           const AutomationRow &row, bool pencilMode) const
{
    const double tick = hoverTick(projection);
    if (hover.hasPoint)
        return tick;
    if (!pencilMode || row.id.kind == EditorAutomationRowKind::Voice)
        return double(projection.fineSnapTick(tick));
    return double(
        projection.pointerMapping(hover.row, hover.pos.x(), hover.pos.y()).cell.tickBegin);
}

int AutomationHoverState::hoverValue(const AutomationProjection &projection) const
{
    return hover.hasPoint
               ? hover.point.value
               : projection.pointerMapping(hover.row, hover.pos.x(), hover.pos.y()).point.value;
}

bool AutomationHoverState::hoverValueFor(const AutomationRows &rows,
                                         const AutomationProjection &projection,
                                         const AutomationRow &row, int rowIndex, double tick,
                                         bool pencilMode, int *value) const
{
    if (rowIndex == hover.row && (hover.hasPoint || pencilMode)) {
        *value = hoverValue(projection);
        return true;
    }
    const auto &points = rows.pointsFor(row, projection);
    const LanePoint *held = nullptr;
    for (const auto &point : points) {
        if (point.tick > tick)
            break;
        held = &point;
    }
    if (!held)
        return false;
    *value = held->value;
    return true;
}

QString AutomationHoverState::hoverTextFor(const AutomationCanvas &area, const AutomationPage &page,
                                           const AutomationGeometry &geometry,
                                           const AutomationRows &rows,
                                           const AutomationProjection &projection,
                                           const AutomationRow &row, int rowIndex, double tick,
                                           qreal x, bool pencilMode) const
{
    if (!page.ready())
        return {};
    if (row.id.kind == EditorAutomationRowKind::Voice) {
        const int track = page.m_owner.selectionModel().primaryTrack();
        if (track < 0)
            return {};
        if (const auto *document = page.document(); document)
            for (const auto &point : document->lanePoints(track, DOC_CC_VOICE))
                if (std::abs(
                        page.displayX(point.tick, geometry.plotOrigin, area.devicePixelRatioF()) -
                        x) <= geometry.deleteTimeRadius)
                    return {};
        const auto voice =
            page.voiceContext(static_cast<uint64_t>(std::floor(std::max(0.0, tick) + 0.5)));
        const int voiceSlot = voice.voiceSlot;
        if (voiceSlot < 0 || voiceSlot >= VOICEGROUP_SIZE)
            return {};
        return rows.voicePaintTextFor(voiceSlot).hoverLabel;
    }
    int value = 0;
    return hoverValueFor(rows, projection, row, rowIndex, tick, pencilMode, &value)
               ? rows.valueTextFor(row, value)
               : QString{};
}

const QString &AutomationHoverState::hoverTextCached(
    const AutomationCanvas &area, const AutomationPage &page, const AutomationGeometry &geometry,
    const AutomationRows &rows, const AutomationProjection &projection, int rowIndex, double tick,
    qreal x, bool pencilMode) const
{
    const uint64_t revision = page.liveState().documentRevision;
    if (hoverTextRow == rowIndex && hoverTextTick == tick && hoverTextX == x &&
        hoverTextRevision == revision && hoverTextPencilMode == pencilMode)
        return hoverText;
    const AutomationRow &row = rows.rows()[std::size_t(rowIndex)];
    hoverText =
        hoverTextFor(area, page, geometry, rows, projection, row, rowIndex, tick, x, pencilMode);
    hoverTextRow = rowIndex;
    hoverTextTick = tick;
    hoverTextX = x;
    hoverTextRevision = revision;
    hoverTextPencilMode = pencilMode;
    return hoverText;
}

QRect AutomationHoverState::hoverValueRect(const AutomationCanvas &area, const AutomationPage &page,
                                           const AutomationGeometry &geometry,
                                           const AutomationRows &rows,
                                           const AutomationProjection &projection,
                                           const AutomationRow &row, int rowIndex, qreal x,
                                           bool pencilMode) const
{
    const QRect plot(geometry.plotOrigin, projection.rowTop(rowIndex),
                     std::max(0, area.width() - geometry.plotOrigin), projection.rowHeight(row));
    qreal anchorX = x;
    int hoverValue = 0;
    if (!hoverValueFor(rows, projection, row, rowIndex, insertionTick(projection, row, pencilMode),
                       pencilMode, &hoverValue))
        return {};
    if (rowIndex == hover.row && hover.hasPoint)
        anchorX = page.displayX(hover.point.tick, geometry.plotOrigin, area.devicePixelRatioF());
    const int anchorY = qRound(projection.pointY(row, rowIndex, hoverValue));
    const QFontMetrics metrics(valueLabelFont(area.font()));
    const int textWidth = metrics.horizontalAdvance(QStringLiteral("0000"));
    const int textHeight = metrics.height();
    const int gap = layout::space(layout::Space::One);
    int textX = qCeil(anchorX - gap - textWidth);
    int textY = anchorY - gap - textHeight;
    if (textX < plot.left())
        textX = qFloor(anchorX + gap);
    if (textY < plot.top())
        textY = anchorY + gap;
    textX = std::clamp(textX, plot.left(), std::max(plot.left(), plot.right() - textWidth + 1));
    textY = std::clamp(textY, plot.top(), std::max(plot.top(), plot.bottom() - textHeight + 1));
    return {textX, textY, textWidth, textHeight};
}

QRect AutomationHoverState::hoverPaintBounds(const AutomationCanvas &area,
                                             const AutomationPage *page,
                                             const AutomationGeometry &geometry,
                                             const AutomationRows &rows,
                                             const AutomationProjection &projection, int rowIndex,
                                             bool pencilMode) const
{
    if (!page || !page->ready() || rowIndex < 0 || rowIndex >= int(rows.rows().size()))
        return {};
    const AutomationRow &row = rows.rows()[rowIndex];
    const double tick = insertionTick(projection, row, pencilMode);
    const QRect plot(geometry.plotOrigin, projection.rowTop(rowIndex),
                     std::max(0, area.width() - geometry.plotOrigin), projection.rowHeight(row));
    const qreal x = page->displayX(tick, geometry.plotOrigin, area.devicePixelRatioF());
    const QString &text = hoverText;
    const int paintPadding = geometry.hoverPaintPadding;
    QRect bounds =
        QRectF(x - paintPadding, plot.top(), 2 * paintPadding, plot.height()).toAlignedRect();
    if (rowIndex == hover.row && hover.hasPoint) {
        const qreal markerRadius = layout::space(layout::Space::Half) + 2 * layout::singlePixel();
        const qreal outerRadius = markerRadius + layout::singlePixel() + paintPadding;
        const QPointF center(
            page->displayX(hover.point.tick, geometry.plotOrigin, area.devicePixelRatioF()),
            projection.pointY(row, rowIndex, hover.point.value));
        bounds = bounds.united(QRectF(center.x() - outerRadius, center.y() - outerRadius,
                                      2 * outerRadius, 2 * outerRadius)
                                   .toAlignedRect());
    } else if (row.id.kind != EditorAutomationRowKind::Voice && !hover.hasPoint) {
        const qreal outerRadius =
            geometry.nodePaintRadius + geometry.nodeOutlineDipWidth + paintPadding;
        if (pencilMode) {
            const QPointF center(x, projection.pointY(row, rowIndex, hoverValue(projection)));
            bounds = bounds.united(QRectF(center.x() - outerRadius, center.y() - outerRadius,
                                          2 * outerRadius, 2 * outerRadius)
                                       .toAlignedRect());
        } else {
            int heldValue = 0;
            if (hoverValueFor(rows, projection, row, rowIndex, tick, false, &heldValue)) {
                const QPointF center(x, projection.pointY(row, rowIndex, heldValue));
                bounds = bounds.united(QRectF(center.x() - outerRadius, center.y() - outerRadius,
                                              2 * outerRadius, 2 * outerRadius)
                                           .toAlignedRect());
            }
        }
    }
    if (row.id.kind == EditorAutomationRowKind::Voice)
        return bounds.intersected(area.rect());
    if (text.isEmpty())
        return bounds.intersected(area.rect());
    if (hoverValueLabel.valid && hoverValueLabel.row == rowIndex)
        bounds = bounds.united(hoverValueLabel.bounds.adjusted(-paintPadding, -paintPadding,
                                                               paintPadding, paintPadding));
    return bounds.intersected(area.rect());
}

QFont AutomationHoverState::valueLabelFont(const QFont &font) const
{
    if (!valueLabelFontValid) {
        valueLabelFontCache = typography::noteName(font);
        valueLabelFontValid = true;
    }
    return valueLabelFontCache;
}

AutomationHoverState::ClampedValueLabel
AutomationHoverState::clampedValueLabel(qreal x, int y, const QRect &plot, const QFont &font) const
{
    const QFontMetrics metrics(valueLabelFont(font));
    const int gap = layout::space(layout::Space::One);
    const int half = layout::space(layout::Space::Half);
    const int width = metrics.horizontalAdvance(QStringLiteral("0000"));
    QRect textRect(qCeil(x + gap + half), y - gap - metrics.height(), width, metrics.height());
    if (textRect.right() > plot.right())
        textRect.moveRight(plot.right());
    if (textRect.left() < plot.left())
        textRect.moveLeft(plot.left());
    if (textRect.top() < plot.top())
        textRect.moveTop(plot.top());
    if (textRect.bottom() > plot.bottom())
        textRect.moveBottom(plot.bottom());
    return {textRect};
}

void AutomationHoverState::updateHoverValueLabel(
    const AutomationCanvas &area, const AutomationPage *page, const AutomationGeometry &geometry,
    const AutomationRows &rows, const AutomationProjection &projection, bool pencilMode)
{
    hoverValueLabel = {};
    const auto syncDirtyBounds = [&] {
        hoverDirtyBounds =
            hoverPaintBounds(area, page, geometry, rows, projection, hover.row, pencilMode);
    };
    if (!page || !page->ready() || hover.row < 0 || hover.row >= int(rows.rows().size())) {
        syncDirtyBounds();
        return;
    }
    const AutomationRow &row = rows.rows()[std::size_t(hover.row)];
    const double tick = insertionTick(projection, row, pencilMode);
    const qreal x = page->displayX(tick, geometry.plotOrigin, area.devicePixelRatioF());
    const QString &text =
        hoverTextCached(area, *page, geometry, rows, projection, hover.row, tick, x, pencilMode);
    if (text.isEmpty()) {
        syncDirtyBounds();
        return;
    }
    auto &label = hoverValueLabel;
    label.row = hover.row;
    label.text = text;
    label.font = valueLabelFont(area.font());
    const QRect plot(geometry.plotOrigin, projection.rowTop(hover.row),
                     std::max(0, area.width() - geometry.plotOrigin), projection.rowHeight(row));
    if (row.id.kind == EditorAutomationRowKind::Voice) {
        label.rect = QRectF(x + layout::space(layout::Space::One), plot.top(),
                            std::max<qreal>(0, plot.right() - x), plot.height());
        label.bounds = QFontMetrics(label.font)
                           .boundingRect(label.rect.toAlignedRect(),
                                         Qt::AlignLeft | Qt::AlignVCenter, label.text);
    } else if (pencilMode) {
        const QFontMetrics metrics(label.font);
        const int gap = layout::space(layout::Space::One);
        const int width = metrics.horizontalAdvance(QStringLiteral("0000"));
        const int height = metrics.height();
        const QRect bounds(qFloor(x + gap), plot.top() + (plot.height() - height) / 2, width,
                           height);
        label.rect = bounds;
        label.bounds = bounds;
    } else {
        const QRect bounds =
            hoverValueRect(area, *page, geometry, rows, projection, row, hover.row, x, pencilMode);
        label.rect = bounds;
        label.bounds = bounds;
    }
    label.valid = true;
    syncDirtyBounds();
}

void AutomationHoverState::updatePreviewValueLabel(
    const AutomationCanvas &area, const AutomationPage *page, const AutomationGeometry &geometry,
    const AutomationRows &rows, const AutomationProjection &projection,
    const std::optional<ActiveGesture> &activeGesture)
{
    previewValueLabel = {};
    if (!activeGesture || !page || !page->ready())
        return;
    const auto setLabel = [this, &area, page, &geometry, &rows,
                           &projection](int rowIndex, uint64_t tick, int value) {
        if (rowIndex < 0 || rowIndex >= int(rows.rows().size()))
            return;
        const AutomationRow &row = rows.rows()[std::size_t(rowIndex)];
        const qreal x = page->displayX(tick, geometry.plotOrigin, area.devicePixelRatioF());
        const int y = qRound(projection.pointY(row, rowIndex, value));
        const QRect plot(geometry.plotOrigin, projection.rowTop(rowIndex),
                         std::max(0, area.width() - geometry.plotOrigin),
                         projection.rowHeight(row));
        const auto clamped = clampedValueLabel(x, y, plot, area.font());
        auto &label = previewValueLabel;
        label.row = rowIndex;
        label.text = rows.valueTextFor(row, value);
        label.font = valueLabelFont(area.font());
        label.rect = clamped.bounds;
        label.bounds = clamped.bounds;
        label.valid = true;
    };
    std::visit(Visitor{[&](const NodeDragGesture &gesture) {
                           if (gesture.grabbedPoint < gesture.points.size()) {
                               const auto &point = gesture.points[gesture.grabbedPoint];
                               setLabel(gesture.row, point.current.tick, point.current.value);
                           }
                       },
                       [&](const SweepGesture &gesture) {
                           setLabel(gesture.row, gesture.current.tick, gesture.current.value);
                       },
                       [&](const PencilGesture &gesture) {
                           if (gesture.row < 0 || gesture.row >= int(rows.rows().size()))
                               return;
                           const AutomationRow &row = rows.rows()[std::size_t(gesture.row)];
                           const auto &sample = gesture.stroke.lastSample();
                           const int value = int(std::lround(sample.continuousValue));
                           const QRect plot(geometry.plotOrigin, projection.rowTop(gesture.row),
                                            std::max(0, area.width() - geometry.plotOrigin),
                                            projection.rowHeight(row));
                           const auto clamped = clampedValueLabel(
                               sample.logicalX, qRound(projection.pointY(row, gesture.row, value)),
                               plot, area.font());
                           auto &label = previewValueLabel;
                           label.row = gesture.row;
                           label.text = rows.valueTextFor(row, value);
                           label.font = valueLabelFont(area.font());
                           label.rect = clamped.bounds;
                           label.bounds = clamped.bounds;
                           label.valid = true;
                       }},
               *activeGesture);
}

void AutomationHoverState::updateHover(AutomationCanvas &area, AutomationPage &page,
                                       const AutomationGeometry &geometry,
                                       const AutomationRows &rows,
                                       const AutomationProjection &projection, qreal x, int y,
                                       bool pencilMode)
{
    const int rowIndex = x >= geometry.plotOrigin ? projection.rowIndexAt(y) : -1;
    if (rowIndex < 0) {
        clearHover(area);
        return;
    }
    const QRect previousBounds = hoverDirtyBounds;
    int mappedValue = 0;
    if (pencilMode && rows.rows()[rowIndex].id.kind != EditorAutomationRowKind::Voice)
        mappedValue = projection.pointerMapping(rowIndex, x, y).point.value;
    if (rowIndex == hover.row && hover.pos == QPointF(x, y) &&
        (!pencilMode || mappedValue == hoverValue(projection)))
        return;
    hover.row = rowIndex;
    hover.pos = QPointF(x, y);
    hover.hasPoint = false;
    DocLanePoint hovered;
    if ((!pencilMode || projection.nodeMarkersVisible()) &&
        rows.cachedPointHit(rows.rows()[rowIndex], rowIndex, hover.pos, projection, geometry,
                            area.devicePixelRatioF(), &hovered)) {
        hover.hasPoint = true;
        hover.point = {hovered.tick, hovered.value};
    }
    hoverTextRow = -1;
    updateHoverValueLabel(area, &page, geometry, rows, projection, pencilMode);
    const QRect currentBounds = hoverDirtyBounds;
    QRegion dirty(previousBounds);
    dirty += currentBounds;
    if (!dirty.isEmpty())
        area.invalidateContent(dirty);
}

void AutomationHoverState::setContextPointHighlight(
    AutomationCanvas &area, const AutomationPage *page, const AutomationGeometry &geometry,
    const AutomationRows &rows, const AutomationProjection &projection, int rowIndex,
    const QPointF &position, const DocLanePoint &point, bool pencilMode)
{
    const QRect previousBounds = hoverDirtyBounds;
    hover.row = rowIndex;
    hover.pos = position;
    hover.hasPoint = true;
    hover.point = {point.tick, point.value};
    hover.highlightLocked = true;
    hoverTextRow = -1;
    updateHoverValueLabel(area, page, geometry, rows, projection, pencilMode);
    const QRect currentBounds = hoverDirtyBounds;
    QRegion dirty(previousBounds);
    dirty += currentBounds;
    if (!dirty.isEmpty())
        area.invalidateContent(dirty);
}

void AutomationHoverState::clearHover(AutomationCanvas &area)
{
    if (hover.highlightLocked)
        return;
    const QRect previousBounds = hoverDirtyBounds;
    hoverDirtyBounds = {};
    hoverText.clear();
    hoverTextRow = -1;
    hoverValueLabel = {};
    if (hover.row < 0)
        return;
    hover.row = -1;
    hover.hasPoint = false;
    hover.pos = {};
    if (!previousBounds.isEmpty())
        area.invalidateContent(previousBounds);
}
