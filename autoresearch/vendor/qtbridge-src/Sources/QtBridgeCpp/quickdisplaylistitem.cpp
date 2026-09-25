#include "quickdisplaylistitem.h"

#include <QtCore/qhash.h>
#include <QtCore/qvariant.h>
#include <QtGui/qcolor.h>
#include <QtQml/qqml.h>
#include <QtQuick/qsggeometry.h>
#include <QtQuick/qsgnode.h>
#include <QtQuick/qsgvertexcolormaterial.h>

#include <cmath>
#include <mutex>

namespace {

class RectGeometryNode final : public QSGGeometryNode
{
public:
    RectGeometryNode()
        : geometry(QSGGeometry::defaultAttributes_ColoredPoint2D(), 0)
    {
        geometry.setDrawingMode(QSGGeometry::DrawTriangles);
        geometry.setVertexDataPattern(QSGGeometry::DynamicPattern);
        setGeometry(&geometry);
        setMaterial(&material);
    }

    QSGGeometry geometry;
    QSGVertexColorMaterial material;
    int allocatedRectCount = 0;
};

int requiredRole(const QHash<int, QByteArray> &roles, const QByteArray &name)
{
    const int role = roles.key(name, -1);
    if (role < 0)
        qFatal("QuickDisplayList model is missing the required '%s' role", name.constData());
    return role;
}

}

QuickDisplayListItem::QuickDisplayListItem(QQuickItem *parent)
    : QQuickItem(parent)
{
    setFlag(ItemHasContents, true);
}

QAbstractItemModel *QuickDisplayListItem::rects() const
{
    return m_rects;
}

void QuickDisplayListItem::setRects(QAbstractItemModel *rects)
{
    if (m_rects == rects)
        return;

    if (m_rects)
        disconnect(m_rects, nullptr, this, nullptr);
    m_rects = rects;

    if (m_rects) {
        const auto rebuild = [this] { rebuildSnapshot(); };
        connect(m_rects, &QAbstractItemModel::modelReset, this, rebuild);
        connect(m_rects, &QAbstractItemModel::dataChanged, this, rebuild);
        connect(m_rects, &QAbstractItemModel::rowsInserted, this, rebuild);
        connect(m_rects, &QAbstractItemModel::rowsRemoved, this, rebuild);
        connect(m_rects, &QAbstractItemModel::rowsMoved, this, rebuild);
        connect(m_rects, &QAbstractItemModel::layoutChanged, this, rebuild);
        connect(m_rects, &QObject::destroyed, this, [this] {
            m_rects = nullptr;
            rebuildSnapshot();
        });
    }

    rebuildSnapshot();
    emit rectsChanged();
}

void QuickDisplayListItem::rebuildSnapshot()
{
    m_snapshot.clear();
    if (m_rects) {
        const auto roles = m_rects->roleNames();
        const int xRole = requiredRole(roles, "x");
        const int yRole = requiredRole(roles, "y");
        const int widthRole = requiredRole(roles, "width");
        const int heightRole = requiredRole(roles, "height");
        const int colorRole = requiredRole(roles, "fillColor");
        const int count = m_rects->rowCount();
        m_snapshot.reserve(size_t(count));
        for (int row = 0; row < count; ++row) {
            const QModelIndex index = m_rects->index(row, 0);
            const float x = m_rects->data(index, xRole).toFloat();
            const float y = m_rects->data(index, yRole).toFloat();
            const float width = m_rects->data(index, widthRole).toFloat();
            const float height = m_rects->data(index, heightRole).toFloat();
            const QColor color(m_rects->data(index, colorRole).toString());
            if (!std::isfinite(x) || !std::isfinite(y) || !std::isfinite(width)
                || !std::isfinite(height) || !color.isValid())
                qFatal("QuickDisplayList received invalid rectangle data at row %d", row);
            if (width <= 0 || height <= 0 || color.alpha() == 0)
                continue;
            m_snapshot.push_back(Rect{
                x, y, width, height,
                static_cast<unsigned char>(color.red()),
                static_cast<unsigned char>(color.green()),
                static_cast<unsigned char>(color.blue()),
                static_cast<unsigned char>(color.alpha())});
        }
    }
    update();
}

QSGNode *QuickDisplayListItem::updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *)
{
    if (m_snapshot.empty()) {
        delete oldNode;
        return nullptr;
    }

    auto *node = static_cast<RectGeometryNode *>(oldNode);
    if (!node)
        node = new RectGeometryNode;

    const int count = int(m_snapshot.size());
    if (node->allocatedRectCount != count) {
        node->geometry.allocate(count * 6);
        node->allocatedRectCount = count;
    }
    auto *vertices = node->geometry.vertexDataAsColoredPoint2D();
    for (int i = 0; i < count; ++i) {
        const Rect &rect = m_snapshot[size_t(i)];
        const float right = rect.x + rect.width;
        const float bottom = rect.y + rect.height;
        const int alpha = rect.alpha;
        const auto red = static_cast<unsigned char>((rect.red * alpha + 127) / 255);
        const auto green = static_cast<unsigned char>((rect.green * alpha + 127) / 255);
        const auto blue = static_cast<unsigned char>((rect.blue * alpha + 127) / 255);
        const int vertex = i * 6;
        vertices[vertex].set(rect.x, rect.y, red, green, blue, rect.alpha);
        vertices[vertex + 1].set(rect.x, bottom, red, green, blue, rect.alpha);
        vertices[vertex + 2].set(right, rect.y, red, green, blue, rect.alpha);
        vertices[vertex + 3].set(right, rect.y, red, green, blue, rect.alpha);
        vertices[vertex + 4].set(rect.x, bottom, red, green, blue, rect.alpha);
        vertices[vertex + 5].set(right, bottom, red, green, blue, rect.alpha);
    }
    node->geometry.markVertexDataDirty();
    node->markDirty(QSGNode::DirtyGeometry);
    return node;
}

void registerQuickDisplayListQmlType()
{
    static std::once_flag once;
    std::call_once(once, [] {
        qmlRegisterType<QuickDisplayListItem>("QtBridge", 1, 0, "QuickDisplayList");
    });
}
