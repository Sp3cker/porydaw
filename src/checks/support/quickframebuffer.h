#pragma once

#include "ui/songview/quick/timelinequickscene.h"

#include <QImage>
#include <QRect>
#include <QWidget>
#include <QtGlobal>

#include <array>
#include <cstddef>

class QColor;
class QQuickItem;
class QString;
class SongView;

namespace checks::support {

template <typename T>
T *findWidgetDescendant(QWidget &root)
{
    for (QWidget *widget : root.findChildren<QWidget *>()) {
        if (auto *typed = dynamic_cast<T *>(widget))
            return typed;
    }
    return nullptr;
}

void pumpQuick();
QRect devicePixelRect(const QImage &image, const QRect &logicalRect);
QRect widgetRectIn(const QWidget &widget, const QWidget &owner);
int playheadWidthAt(const QImage &image, int logicalY, qreal logicalX, const QColor &color);
bool isPlayheadPixel(const QColor &actual, const QColor &expected);
bool hasPlayheadPixel(const QImage &image, const QRect &logicalRect, const QColor &color);
qreal quickRootX(const QQuickItem &item, QQuickItem &root);
using TimelineQuickLayerRevisions =
    std::array<quint64, static_cast<std::size_t>(songview::TimelineQuickLayer::Count)>;

TimelineQuickLayerRevisions timelineQuickLayerRevisions(const songview::TimelineQuickScene &scene);

QImage captureQuickBand(SongView &view, const QRect &rectInSongView, QString *error = nullptr);

} // namespace checks::support
