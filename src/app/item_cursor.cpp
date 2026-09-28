#include "item_cursor.h"

#include <QtCore/qmath.h>
#include <QtGui/qguiapplication.h>
#include <QtGui/qicon.h>
#include <QtGui/qpixmap.h>
#include <QtQml/qqmlfile.h>

namespace {

QCursor centeredCursor(const QPixmap &pixmap)
{
    const qreal dpr =
        QGuiApplication::platformName() == QLatin1String("xcb") ? 1.0 : pixmap.devicePixelRatio();
    return QCursor(pixmap, qRound(pixmap.width() / (2.0 * dpr)),
                   qRound(pixmap.height() / (2.0 * dpr)));
}

} // namespace

ItemCursor::ItemCursor(QObject *parent) : QObject(parent) {}

void ItemCursor::setTarget(QQuickItem *target)
{
    if (m_target == target)
        return;
    m_target = target;
    apply();
    emit targetChanged();
}

void ItemCursor::setShape(Qt::CursorShape shape)
{
    if (m_shape == shape)
        return;
    m_shape = shape;
    apply();
    emit shapeChanged();
}

void ItemCursor::setSource(const QUrl &source)
{
    if (m_source == source)
        return;
    m_source = source;
    apply();
    emit sourceChanged();
}

void ItemCursor::setExtent(int extent)
{
    if (m_extent == extent)
        return;
    m_extent = extent;
    m_pixmapCursors.clear();
    apply();
    emit extentChanged();
}

void ItemCursor::setDevicePixelRatio(qreal devicePixelRatio)
{
    if (qFuzzyCompare(m_devicePixelRatio, devicePixelRatio))
        return;
    m_devicePixelRatio = devicePixelRatio;
    m_pixmapCursors.clear();
    apply();
    emit devicePixelRatioChanged();
}

const QCursor &ItemCursor::pixmapCursor()
{
    auto it = m_pixmapCursors.find(m_source);
    if (it == m_pixmapCursors.end()) {
        const QIcon icon(QQmlFile::urlToLocalFileOrQrc(m_source));
        it = m_pixmapCursors.insert(
            m_source, centeredCursor(icon.pixmap(QSize(m_extent, m_extent), m_devicePixelRatio)));
    }
    return *it;
}

void ItemCursor::apply()
{
    if (!m_target)
        return;
    if (m_source.isEmpty())
        m_target->setCursor(QCursor(m_shape));
    else
        m_target->setCursor(pixmapCursor());
}
