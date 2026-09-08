#pragma once

#include "ui/songview/quick/timelinequickscene.h"

#include <QImage>
#include <QRect>
#include <QSize>
#include <QtGlobal>

#include <array>
#include <cstddef>

class QColor;
class QQuickItem;
class QString;
class SongView;

namespace checks::support {

void pumpQuick();
QRect devicePixelRect(const QImage &image, const QRect &logicalRect);
int playheadWidthAt(const QImage &image, int logicalY, qreal logicalX, const QColor &color);
bool isPlayheadPixel(const QColor &actual, const QColor &expected);
bool hasPlayheadPixel(const QImage &image, const QRect &logicalRect, const QColor &color);
bool hasSolidPlayheadPixel(const QImage &image, const QRect &logicalRect, const QColor &color);
qreal quickRootX(const QQuickItem &item, QQuickItem &root);
using TimelineQuickLayerRevisions =
    std::array<quint64, static_cast<std::size_t>(songview::TimelineQuickLayer::Count)>;

TimelineQuickLayerRevisions timelineQuickLayerRevisions(const songview::TimelineQuickScene &scene);

// Sizes and exposes the real unhosted Quick window: SongView is a pure
// QObject coordinator, so the QQuickWindow is the full canonical viewport.
// Pumps the event loop once so window-driven layout settles. Returns false
// when the production Quick canvas or its window is missing.
bool showQuickViewport(SongView &view, const QSize &size);

// Captures a viewport-local Quick framebuffer crop (the Quick window spans
// the canonical viewport with origin (0, 0)); never walks the widget tree.
QImage captureQuickBand(SongView &view, const QRect &viewportRect, QString *error = nullptr);

} // namespace checks::support
