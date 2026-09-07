#pragma once

#include <QList>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickWindow>

namespace songview {

inline QQmlEngine *quickEngine(QQuickWindow *window)
{
    if (!window)
        return nullptr;
    if (QQmlEngine *engine = qmlEngine(window))
        return engine;
    const QList<QQuickItem *> children = window->contentItem()->childItems();
    for (QQuickItem *child : children) {
        if (QQmlEngine *engine = qmlEngine(child))
            return engine;
    }
    return nullptr;
}

} // namespace songview
