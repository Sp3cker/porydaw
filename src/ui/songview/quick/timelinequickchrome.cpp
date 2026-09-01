#include "ui/songview/quick/timelinequickchrome.h"

#include <QSGGeometry>
#include <QSGGeometryNode>
#include <QSGVertexColorMaterial>
#include <QtMath>

#include <algorithm>

#include "ui/layout.h"
#include "ui/theme/themeruntime.h"

namespace songview {
namespace {

class TimelineChromeNode final : public QSGGeometryNode
{
  public:
    TimelineChromeNode()
    {
        auto *geometry = new QSGGeometry(QSGGeometry::defaultAttributes_ColoredPoint2D(), 0);
        geometry->setDrawingMode(QSGGeometry::DrawTriangles);
        geometry->setVertexDataPattern(QSGGeometry::DynamicPattern);
        setGeometry(geometry);
        setFlag(OwnsGeometry);

        auto *material = new QSGVertexColorMaterial;
        material->setFlag(QSGMaterial::Blending);
        setMaterial(material);
        setFlag(OwnsMaterial);
    }
};

void setVertex(QSGGeometry::ColoredPoint2D &vertex, const QPointF &point, const QColor &color)
{
    const int alpha = color.alpha();
    const auto premultiplied = [alpha](int component) {
        return uchar((component * alpha + 127) / 255);
    };
    vertex.set(float(point.x()), float(point.y()), premultiplied(color.red()),
               premultiplied(color.green()), premultiplied(color.blue()), uchar(alpha));
}

class GeometryWriter
{
  public:
    explicit GeometryWriter(QSGGeometry::ColoredPoint2D *vertices) : m_vertices(vertices) {}

    void rect(qreal left, qreal top, qreal right, qreal bottom, const QColor &leftColor,
              const QColor &rightColor)
    {
        setVertex(*m_vertices++, QPointF(left, top), leftColor);
        setVertex(*m_vertices++, QPointF(left, bottom), leftColor);
        setVertex(*m_vertices++, QPointF(right, top), rightColor);
        setVertex(*m_vertices++, QPointF(right, top), rightColor);
        setVertex(*m_vertices++, QPointF(left, bottom), leftColor);
        setVertex(*m_vertices++, QPointF(right, bottom), rightColor);
    }

  private:
    QSGGeometry::ColoredPoint2D *m_vertices = nullptr;
};

void appendGuide(GeometryWriter &writer, qreal height, const QColor &color)
{
    const qreal pixel = layout::singlePixel();
    for (qreal top = 0.0; top < height; top += pixel + pixel) {
        const qreal bottom = (std::min)(top + pixel, height);
        writer.rect(-pixel / 2.0, top, pixel / 2.0, bottom, color, color);
    }
}

int guideRectCount(qreal height)
{
    if (height <= 0.0)
        return 0;
    return qCeil(height / (layout::singlePixel() + layout::singlePixel()));
}

} // namespace

TimelineChromeItem::TimelineChromeItem(QQuickItem *parent) : QQuickItem(parent)
{
    setFlag(ItemHasContents, true);
}

TimelineChromeItem::Kind TimelineChromeItem::kind() const noexcept
{
    return m_kind;
}

void TimelineChromeItem::setKind(Kind kind)
{
    if (m_kind == kind)
        return;
    m_kind = kind;
    emit kindChanged();
    update();
}

void TimelineChromeItem::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    QQuickItem::geometryChange(newGeometry, oldGeometry);
    if (newGeometry.size() != oldGeometry.size())
        update();
}

QSGNode *TimelineChromeItem::updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *)
{
    auto *node = static_cast<TimelineChromeNode *>(oldNode);
    if (!node)
        node = new TimelineChromeNode;

    QSGGeometry *const geometry = node->geometry();
    const int rectCount = guideRectCount(height());
    geometry->allocate(rectCount * 6);
    if (rectCount == 0)
        return node;

    GeometryWriter writer(geometry->vertexDataAsColoredPoint2D());
    const themes::Role role = m_kind == Kind::Hover ? themes::Role::song_view_secondary_text
                                                    : themes::Role::song_view_edit_cursor;
    appendGuide(writer, height(), themes::color(role));
    geometry->markVertexDataDirty();
    node->markDirty(QSGNode::DirtyGeometry);
    return node;
}

} // namespace songview
