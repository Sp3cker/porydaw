#pragma once

#include <QtCore/qhash.h>
#include <QtCore/qobject.h>
#include <QtCore/qpointer.h>
#include <QtCore/qurl.h>
#include <QtGui/qcursor.h>
#include <QtQml/qqmlregistration.h>
#include <QtQuick/qquickitem.h>

class ItemCursor : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QQuickItem *target READ target WRITE setTarget NOTIFY targetChanged REQUIRED)
    Q_PROPERTY(Qt::CursorShape shape READ shape WRITE setShape NOTIFY shapeChanged)
    Q_PROPERTY(QUrl source READ source WRITE setSource NOTIFY sourceChanged)
    Q_PROPERTY(int extent READ extent WRITE setExtent NOTIFY extentChanged)
    Q_PROPERTY(qreal devicePixelRatio READ devicePixelRatio WRITE setDevicePixelRatio NOTIFY
                   devicePixelRatioChanged)

  public:
    explicit ItemCursor(QObject *parent = nullptr);

    [[nodiscard]] QQuickItem *target() const { return m_target; }
    void setTarget(QQuickItem *target);
    [[nodiscard]] Qt::CursorShape shape() const { return m_shape; }
    void setShape(Qt::CursorShape shape);
    [[nodiscard]] QUrl source() const { return m_source; }
    void setSource(const QUrl &source);
    [[nodiscard]] int extent() const { return m_extent; }
    void setExtent(int extent);
    [[nodiscard]] qreal devicePixelRatio() const { return m_devicePixelRatio; }
    void setDevicePixelRatio(qreal devicePixelRatio);

  signals:
    void targetChanged();
    void shapeChanged();
    void sourceChanged();
    void extentChanged();
    void devicePixelRatioChanged();

  private:
    const QCursor &pixmapCursor();
    void apply();

    QPointer<QQuickItem> m_target;
    Qt::CursorShape m_shape = Qt::ArrowCursor;
    QUrl m_source;
    int m_extent = 0;
    qreal m_devicePixelRatio = 1.0;
    QHash<QUrl, QCursor> m_pixmapCursors;
};
