#pragma once

class QObject;
class QQuickItem;
class QQuickWindow;

void verifyDocumentFeed(QQuickWindow *window, QQuickItem *viewport, QQuickItem *surface,
                        QObject *model);
