#pragma once

#include "ui/songview/quick/timelinequickscene.h"

#include <QImage>
#include <QRect>
#include <QSize>
#include <QtGlobal>

#include <array>
#include <cstddef>

class QQuickItem;
class QString;
class SongView;

namespace checks::support {

void pumpQuick();
QRect devicePixelRect(const QImage &image, const QRect &logicalRect);
qreal quickRootX(const QQuickItem &item, QQuickItem &root);
using TimelineQuickLayerRevisions =
    std::array<quint64, static_cast<std::size_t>(songview::TimelineQuickLayer::Count)>;

TimelineQuickLayerRevisions timelineQuickLayerRevisions(const songview::TimelineQuickScene &scene);

// Sizes and exposes the already attached borrowed Quick window: an
// explicit scene host (canonical check host or fixture host) attaches the
// canvas and owns the window, so this never constructs a hidden host.
// Pumps the event loop once so window-driven layout settles. Returns false
// when the production Quick canvas is detached or its borrowed window is
// missing.
bool showQuickViewport(SongView &view, const QSize &size);

// Captures a canvas-local Quick framebuffer crop, mapped onto the window
// framebuffer through the attached canvas root item (the translated
// viewport may sit anywhere inside the host window); never walks the
// widget tree.
QImage captureQuickBand(SongView &view, const QRect &viewportRect, QString *error = nullptr);

} // namespace checks::support
