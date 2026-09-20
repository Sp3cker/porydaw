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
class QQuickWindow;
class QString;
class QWidget;
class SongView;

namespace checks::support {

void pumpQuick();
// Waits for exposure and a requested frame so QML layout is published before
// fixtures snapshot geometry. Does not capture or discard a framebuffer.
bool waitForQuickFrame(QQuickWindow &window, QString *error = nullptr);
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
// Waits for a rendered frame so QML-measured layout settles. Returns false
// when the production Quick canvas/window is missing or cannot render.
bool showQuickViewport(SongView &view, const QSize &size);

// Captures a viewport-local Quick framebuffer crop (the Quick window spans
// the canonical viewport with origin (0, 0)); never walks the widget tree.
QImage captureQuickBand(SongView &view, const QRect &viewportRect, QString *error = nullptr);

// Grabs `root` and paints the live `quickWindow` framebuffer over `container`'s
// bounds: QWidget::grab() cannot see a native embedded window, so a mixed
// QWidget + Quick surface compares as one image only after this composition.
// `containerBounds` receives the container's logical bounds inside `root` (the
// caller's semantic "quick surface" region). Waits for a rendered frame before
// grabbing the framebuffer; returns a null image and, when `error` is given, a
// description of what failed: the root grab, the frame wait, or the Quick grab.
// `container` must be a descendant of `root`.
QImage compositeQuickWindowIntoGrab(QWidget &root, QWidget &container, QQuickWindow &quickWindow,
                                    QRect *containerBounds, QString *error = nullptr);

} // namespace checks::support
