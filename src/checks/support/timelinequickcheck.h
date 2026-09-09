#pragma once

#include "ui/layout.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/timelinebandlayout.h"

#include <QColor>
#include <QPointF>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRect>
#include <QRectF>
#include <QRegion>
#include <QSize>
#include <QString>

#include <algorithm>
#include <optional>

namespace checks::support {

inline bool quickWindowIsUnmasked(const songview::TimelineQuickView &quick)
{
    const QQuickWindow *const window = quick.quickWindow();
    return window && window->mask().isEmpty();
}

// Compare independent physical plot and gutter surfaces against canonical
// band geometry: input frames map through the canvas root item, so the
// comparison holds wherever a host places the translated viewport inside
// its window (root-relative, never window-local).
inline bool physicalInputsMatchCanonical(const songview::TimelineBandLayout &bandLayout,
                                         const QQuickItem &quickRoot, songview::TimelineBand band,
                                         const QString &plotInputObjectName,
                                         const QString &gutterInputObjectName)
{
    const std::optional<songview::TimelineBandGeometry> &geometry = bandLayout.geometry(band);
    const auto *plotInput = quickRoot.findChild<songview::TimelineInputItem *>(plotInputObjectName);
    const auto *gutterInput =
        quickRoot.findChild<songview::TimelineInputItem *>(gutterInputObjectName);
    if (!geometry || !plotInput || !gutterInput)
        return false;

    const QRect gutterRect =
        geometry->plotRect.isNull()
            ? geometry->rect
            : QRect(geometry->rect.topLeft(),
                    QSize(std::clamp(geometry->plotRect.left() - geometry->rect.left(), 0,
                                     geometry->rect.width()),
                          geometry->rect.height()));
    const auto surfaceMatches = [&](const songview::TimelineInputItem &input,
                                    const QRect &surfaceRect) {
        return input.isVisible() && input.bounds() == QRectF(QPointF{}, surfaceRect.size()) &&
               QRectF(input.mapToItem(&quickRoot, QPointF()), input.size()) == QRectF(surfaceRect);
    };
    return plotInput->interaction() == gutterInput->interaction() &&
           surfaceMatches(*plotInput, geometry->plotRect) &&
           surfaceMatches(*gutterInput, gutterRect);
}

inline bool layerHasColorIn(const songview::TimelineQuickLayerData &layer, const QRectF &probe,
                            const QColor &color)
{
    for (const songview::TimelineQuickRect &rect : layer.rects) {
        if (rect.rect.intersects(probe) &&
            (rect.topLeft == color || rect.topRight == color || rect.bottomRight == color ||
             rect.bottomLeft == color)) {
            return true;
        }
    }
    for (const songview::TimelineQuickTriangle &triangle : layer.triangles) {
        const qreal left = std::min({triangle.first.x(), triangle.second.x(), triangle.third.x()});
        const qreal right = std::max({triangle.first.x(), triangle.second.x(), triangle.third.x()});
        const qreal top = std::min({triangle.first.y(), triangle.second.y(), triangle.third.y()});
        const qreal bottom =
            std::max({triangle.first.y(), triangle.second.y(), triangle.third.y()});
        if (QRectF(QPointF(left, top), QPointF(right, bottom)).intersects(probe) &&
            (triangle.firstColor == color || triangle.secondColor == color ||
             triangle.thirdColor == color)) {
            return true;
        }
    }
    return false;
}

inline bool layerHasRingAt(const songview::TimelineQuickLayerData &layer,
                           const QPointF &viewportCenter, qreal radius, qreal width,
                           const QColor &color)
{
    const qreal tolerance = layout::singlePixel();
    const qreal inner = std::max<qreal>(0.0, radius - width / 2.0 - tolerance);
    const qreal outer = radius + width / 2.0 + tolerance;
    const qreal innerSquared = inner * inner;
    const qreal outerSquared = outer * outer;
    const auto onRing = [&](const QPointF &point) {
        const QPointF delta = point - viewportCenter;
        const qreal distanceSquared = delta.x() * delta.x() + delta.y() * delta.y();
        return distanceSquared >= innerSquared && distanceSquared <= outerSquared;
    };
    return std::count_if(layer.triangles.cbegin(), layer.triangles.cend(),
                         [&](const songview::TimelineQuickTriangle &triangle) {
                             return triangle.firstColor == color && triangle.secondColor == color &&
                                    triangle.thirdColor == color && onRing(triangle.first) &&
                                    onRing(triangle.second) && onRing(triangle.third);
                         }) >= 4;
}

} // namespace checks::support
