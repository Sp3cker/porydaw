#pragma once

#include <QtCore/qabstractitemmodel.h>
#include <QtCore/qpointer.h>
#include <QtQuick/qquickitem.h>

#include <vector>

class QuickDisplayListItem : public QQuickItem
{
    Q_OBJECT
    Q_PROPERTY(QAbstractItemModel *rects READ rects WRITE setRects NOTIFY rectsChanged)

public:
    explicit QuickDisplayListItem(QQuickItem *parent = nullptr);

    QAbstractItemModel *rects() const;
    void setRects(QAbstractItemModel *rects);

signals:
    void rectsChanged();

protected:
    QSGNode *updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *) override;

private:
    struct Rect {
        float x;
        float y;
        float width;
        float height;
        unsigned char red;
        unsigned char green;
        unsigned char blue;
        unsigned char alpha;
    };

    void rebuildSnapshot();

    QPointer<QAbstractItemModel> m_rects;
    std::vector<Rect> m_snapshot;
};

void registerQuickDisplayListQmlType();
