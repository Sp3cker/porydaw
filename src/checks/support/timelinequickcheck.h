#pragma once

#include "ui/editordrawer/drawerchrome.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/timelinebandlayout.h"

#include <QQuickWindow>
#include <QRect>
#include <QRectF>
#include <QRegion>

#include <optional>

namespace checks::support {

inline bool quickWindowIsUnmasked(const songview::TimelineQuickView &quick)
{
    const QQuickWindow *const window = quick.quickWindow();
    return window && window->mask().isEmpty();
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
