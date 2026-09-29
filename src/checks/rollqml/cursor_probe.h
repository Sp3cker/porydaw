#pragma once

#include <QtCore/qobject.h>
#include <QtCore/qurl.h>
#include <QtQuick/qquickitem.h>

class CursorProbe : public QObject
{
    Q_OBJECT

  public:
    using QObject::QObject;

    Q_INVOKABLE bool artDiffers(QQuickItem *item, const QUrl &leftUrl, const QUrl &rightUrl,
                                int extent) const;
    Q_INVOKABLE bool matchesArt(QQuickItem *item, const QUrl &artUrl, int extent) const;
};
