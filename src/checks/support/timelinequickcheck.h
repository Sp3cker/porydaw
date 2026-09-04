#pragma once

#include "ui/editordrawer/drawerchrome.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/timelinebandlayout.h"

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

// Compare independent physical plot and gutter surfaces against SongView-local
// canonical band geometry after translating it into the Quick host.
inline bool physicalInputsMatchCanonical(const songview::TimelineBandLayout &bandLayout,
                                         const songview::TimelineQuickView &quick,
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
               QRectF(input.mapToItem(&quickRoot, QPointF()), input.size()) ==
                   QRectF(surfaceRect.translated(-quick.geometry().topLeft()));
    };
    return plotInput->interaction() == gutterInput->interaction() &&
           surfaceMatches(*plotInput, geometry->plotRect) &&
           surfaceMatches(*gutterInput, gutterRect);
}

inline QRect canonicalVisibleQuickHostRect(const songview::TimelineBandLayout &bandLayout,
                                           const DrawerChrome *chrome)
{
    std::optional<QRect> hostRect;
    for (const std::optional<songview::TimelineBandGeometry> &band : bandLayout.bands) {
        if (!band)
            continue;
        hostRect = hostRect ? hostRect->united(band->rect) : band->rect;
    }

    const auto addChrome = [&hostRect](const QRectF &rect, bool visible) {
        if (!visible || rect.isEmpty())
            return;
        const QRect aligned = rect.toAlignedRect();
        hostRect = hostRect ? hostRect->united(aligned) : aligned;
    };
    if (chrome) {
        addChrome(chrome->voiceChangesHandleRect(), chrome->voiceChangesHandleVisible());
        addChrome(chrome->velocityHandleRect(), chrome->velocityHandleVisible());
        addChrome(chrome->automationHandleRect(), chrome->automationHandleVisible());
        addChrome(chrome->barRect(), chrome->barVisible());
        addChrome(chrome->voiceChangesToggleRect(), chrome->voiceChangesToggleVisible());
        addChrome(chrome->automationToggleRect(), chrome->automationToggleVisible());
        addChrome(chrome->velocityToggleRect(), chrome->velocityToggleVisible());
        addChrome(chrome->detentRect(), chrome->detentVisible());
        addChrome(chrome->automationScrollbarRect(), chrome->automationScrollbarVisible());
    }
    return hostRect.value_or(QRect{});
}

} // namespace checks::support
