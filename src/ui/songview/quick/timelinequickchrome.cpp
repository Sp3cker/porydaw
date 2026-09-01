#include "ui/songview/quick/timelinequickchrome.h"

#include <QSGGeometry>
#include <QSGGeometryNode>
#include <QSGVertexColorMaterial>
#include <QtMath>

#include <algorithm>

#include "ui/theme/themeruntime.h"

namespace songview {
namespace {

constexpr qreal cPlayheadGlowRadius = 10.0;
constexpr qreal cPlayheadTriangleHalfWidth = 4.0;
constexpr qreal cPlayheadTriangleHeight = 8.0;
constexpr qreal cPlayheadLineWidth = 1.0;
constexpr qreal cPlayheadPeakPlaying = 0.13;
constexpr qreal cPlayheadPeakPaused = 0.06;
constexpr qreal cGuideDash = 1.0;
constexpr qreal cGuideGap = 1.0;
constexpr int cGradientStops = 8;

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

    void triangle(const QPointF &first, const QPointF &second, const QPointF &third,
                  const QColor &color)
    {
        setVertex(*m_vertices++, first, color);
        setVertex(*m_vertices++, second, color);
        setVertex(*m_vertices++, third, color);
    }

  private:
    QSGGeometry::ColoredPoint2D *m_vertices = nullptr;
};

QColor withAlpha(const QColor &color, qreal alpha)
{
    QColor result = color;
    result.setAlphaF(alpha);
    return result;
}

void appendGuide(GeometryWriter &writer, qreal height, const QColor &color)
{
    for (qreal top = 0.0; top < height; top += cGuideDash + cGuideGap) {
        const qreal bottom = (std::min)(top + cGuideDash, height);
        writer.rect(-cPlayheadLineWidth / 2.0, top, cPlayheadLineWidth / 2.0, bottom, color, color);
    }
}

void appendPlayhead(GeometryWriter &writer, qreal height, bool playing,
                    TimelineChromeItem::RulerTriangle rulerTriangle)
{
    const QColor color = themes::color(themes::Role::song_view_playhead);
    const qreal leftExtent = playing ? cPlayheadGlowRadius - 1.0 : cPlayheadGlowRadius;
    const qreal rightExtent = playing ? 0.0 : cPlayheadGlowRadius;
    const qreal peak = playing ? cPlayheadPeakPlaying : cPlayheadPeakPaused;
    for (int index = 0; index < cGradientStops; ++index) {
        const qreal start = qreal(index) / cGradientStops;
        const qreal end = qreal(index + 1) / cGradientStops;
        writer.rect(-leftExtent + leftExtent * start, 0.0, -leftExtent + leftExtent * end, height,
                    withAlpha(color, peak * start * start), withAlpha(color, peak * end * end));
        if (rightExtent > 0.0) {
            writer.rect(rightExtent * (1.0 - end), 0.0, rightExtent * (1.0 - start), height,
                        withAlpha(color, peak * end * end), withAlpha(color, peak * start * start));
        }
    }
    writer.rect(-cPlayheadLineWidth / 2.0, 0.0, cPlayheadLineWidth / 2.0, height, color, color);

    if (rulerTriangle == TimelineChromeItem::RulerTriangle::None)
        return;
    const qreal top = (std::max)(0.0, height - cPlayheadTriangleHeight);
    if (rulerTriangle == TimelineChromeItem::RulerTriangle::Down) {
        writer.triangle(QPointF(-cPlayheadTriangleHalfWidth, top),
                        QPointF(cPlayheadTriangleHalfWidth, top), QPointF(0.0, height), color);
    } else {
        writer.triangle(QPointF(-cPlayheadTriangleHalfWidth, height),
                        QPointF(cPlayheadTriangleHalfWidth, height), QPointF(0.0, top), color);
    }
}

int guideRectCount(qreal height)
{
    if (height <= 0.0)
        return 0;
    return qCeil(height / (cGuideDash + cGuideGap));
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

bool TimelineChromeItem::playing() const noexcept
{
    return m_playing;
}

void TimelineChromeItem::setPlaying(bool playing)
{
    if (m_playing == playing)
        return;
    m_playing = playing;
    emit playingChanged();
    update();
}

TimelineChromeItem::RulerTriangle TimelineChromeItem::rulerTriangle() const noexcept
{
    return m_rulerTriangle;
}

void TimelineChromeItem::setRulerTriangle(RulerTriangle rulerTriangle)
{
    if (m_rulerTriangle == rulerTriangle)
        return;
    m_rulerTriangle = rulerTriangle;
    emit rulerTriangleChanged();
    update();
}

void TimelineChromeItem::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    QQuickItem::geometryChange(newGeometry, oldGeometry);
    if (newGeometry.height() != oldGeometry.height())
        update();
}

QSGNode *TimelineChromeItem::updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *)
{
    auto *node = static_cast<TimelineChromeNode *>(oldNode);
    if (!node)
        node = new TimelineChromeNode;

    const qreal itemHeight = height();
    const bool playhead = m_kind == Kind::Playhead;
    const int rectCount =
        playhead ? 1 + cGradientStops * (m_playing ? 1 : 2) : guideRectCount(itemHeight);
    const int triangleVertices = playhead && m_rulerTriangle != RulerTriangle::None ? 3 : 0;
    QSGGeometry *const geometry = node->geometry();
    geometry->allocate(rectCount * 6 + triangleVertices);
    if (rectCount == 0 && triangleVertices == 0)
        return node;

    GeometryWriter writer(geometry->vertexDataAsColoredPoint2D());
    if (playhead) {
        appendPlayhead(writer, itemHeight, m_playing, m_rulerTriangle);
    } else {
        const themes::Role role = m_kind == Kind::Hover ? themes::Role::song_view_secondary_text
                                                        : themes::Role::song_view_edit_cursor;
        appendGuide(writer, itemHeight, themes::color(role));
    }
    geometry->markVertexDataDirty();
    node->markDirty(QSGNode::DirtyGeometry);
    return node;
}

} // namespace songview
