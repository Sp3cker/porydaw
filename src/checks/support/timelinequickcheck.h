#pragma once

#include "ui/editordrawer/automationcanvas.h"
#include "ui/layout.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/timelinebandlayout.h"

#include <QAnyStringView>
#include <QColor>

#include <QPointF>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRect>
#include <QRectF>
#include <QRegion>
#include <QSize>
#include <QString>
#include <QVariant>

#include <algorithm>
#include <optional>

namespace checks::support {
// The automation parameter catalog has one published direction:
// AutomationCanvas::parameterRow(index) forward-maps a catalog position to
// its row id, so test lookups walk it instead of duplicating an inverse
// mapping. Unknown rows return -1.
inline int automationParameterIndex(const AutomationCanvas &canvas,
                                    const EditorAutomationRowId &row)
{
    for (int index = 0;; ++index) {
        const std::optional<EditorAutomationRowId> published = canvas.parameterRow(index);
        if (!published)
            return -1;
        if (*published == row)
            return index;
    }
}

// QObject::findChild misses visually reparented Quick delegates, so shared
// selector-label lookups walk the visual childItems tree instead of object
// ownership. The root itself can match too.
inline QQuickItem *visualDescendant(QQuickItem *root, QAnyStringView name)
{
    if (!root)
        return nullptr;
    if (root->objectName() == name)
        return root;
    for (QQuickItem *const child : root->childItems())
        if (QQuickItem *const found = visualDescendant(child, name))
            return found;
    return nullptr;
}

// The automation parameter tabs overflow their gutter at the minimum drawer
// height, so the stack Flickable clips overflow and reveals tabs by contentY.
// These helpers find that Flickable, scroll one tab into view, and assert a
// rect stays inside the visible viewport within the hairline epsilon.
inline QQuickItem *automationTabsScroller(QQuickItem *root)
{
    QQuickItem *const tabs =
        root ? visualDescendant(root, QStringLiteral("automationParameterTabs")) : nullptr;
    if (!tabs)
        return nullptr;
    for (QQuickItem *const child : tabs->childItems()) {
        if (child->property("contentY").isValid() && child->property("contentHeight").isValid())
            return child;
    }
    return nullptr;
}

// Synchronous by invariant: the AutomationTabs.qml Flickable leaves contentY
// unbound and unanimated, so this write and the caller's geometry read-back land
// in the same frame; a future Behavior/animation on contentY would stale it by one frame.
inline void scrollTabIntoView(QQuickItem *scroller, const QQuickItem &tab)
{
    const qreal contentY = scroller->property("contentY").toReal();
    const qreal topInContent = tab.mapToItem(scroller, QPointF{}).y() + contentY;
    const qreal maximumContentY =
        std::max<qreal>(0.0, scroller->property("contentHeight").toReal() - scroller->height());
    scroller->setProperty("contentY",
                          QVariant::fromValue(std::clamp(topInContent, 0.0, maximumContentY)));
}

inline bool rectInside(const QRectF &inner, const QRectF &outer)
{
    const qreal epsilon = layout::singlePixel();
    return inner.left() >= outer.left() - epsilon && inner.right() <= outer.right() + epsilon &&
           inner.top() >= outer.top() - epsilon && inner.bottom() <= outer.bottom() + epsilon;
}

inline bool quickWindowIsUnmasked(const songview::TimelineQuickView &quick)
{
    const QQuickWindow *const window = quick.quickWindow();
    return window && window->mask().isEmpty();
}

// Compare independent physical plot and gutter surfaces against canonical
// band geometry: the unhosted Quick window is the full canonical viewport
// with origin (0, 0), so window-local input frames equal the layout rects.
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
