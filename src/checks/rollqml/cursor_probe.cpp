#include "cursor_probe.h"

#include <QtCore/qcoreapplication.h>
#include <QtGui/qicon.h>
#include <QtGui/qimage.h>
#include <QtGui/qpixmap.h>
#include <QtQml/qqml.h>
#include <QtQml/qqmlfile.h>
#include <QtQuick/qquickwindow.h>

namespace {

QImage artImage(const QUrl &url, int extent, qreal dpr)
{
    return QIcon(QQmlFile::urlToLocalFileOrQrc(url))
        .pixmap(QSize(extent, extent), dpr)
        .toImage();
}

void registerCursorProbe()
{
    qmlRegisterType<CursorProbe>("PorydawRollTest", 1, 0, "CursorProbe");
}

} // namespace

Q_COREAPP_STARTUP_FUNCTION(registerCursorProbe)

bool CursorProbe::artDiffers(QQuickItem *item, const QUrl &leftUrl, const QUrl &rightUrl,
                             int extent) const
{
    if (!item || !item->window() || extent <= 0)
        return false;
    const qreal dpr = item->window()->devicePixelRatio();
    const QImage left = artImage(leftUrl, extent, dpr);
    const QImage right = artImage(rightUrl, extent, dpr);
    return !left.isNull() && !right.isNull() && left != right;
}

bool CursorProbe::matchesArt(QQuickItem *item, const QUrl &artUrl, int extent) const
{
    if (!item || !item->window() || extent <= 0 || item->cursor().shape() != Qt::BitmapCursor)
        return false;
    const QImage expected = artImage(artUrl, extent, item->window()->devicePixelRatio());
    return !expected.isNull() && item->cursor().pixmap().toImage() == expected;
}
