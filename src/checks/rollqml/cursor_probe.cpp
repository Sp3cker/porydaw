#include "cursor_probe.h"

#include <QtCore/qcoreapplication.h>
#include <QtGui/qcursor.h>
#include <QtGui/qicon.h>
#include <QtGui/qimage.h>
#include <QtGui/qpixmap.h>
#include <QtQml/qqml.h>
#include <QtQml/qqmlfile.h>

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

bool CursorProbe::artDiffers(const QUrl &leftUrl, const QUrl &rightUrl,
                             int extent, qreal devicePixelRatio) const
{
    if (extent <= 0)
        return false;
    const QImage left = artImage(leftUrl, extent, devicePixelRatio);
    const QImage right = artImage(rightUrl, extent, devicePixelRatio);
    return !left.isNull() && !right.isNull() && left != right;
}

bool CursorProbe::matchesArt(QQuickItem *item, const QUrl &artUrl, int extent,
                             qreal devicePixelRatio) const
{
    if (!item || extent <= 0 || item->cursor().shape() != Qt::BitmapCursor)
        return false;
    const QImage expected = artImage(artUrl, extent, devicePixelRatio);
    return !expected.isNull() && item->cursor().pixmap().toImage() == expected;
}
