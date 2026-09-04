#include "ui/songview/quick/playheadquick.h"

#include <QMatrix4x4>
#include <QSGClipNode>
#include <QSGGeometry>
#include <QSGGeometryNode>
#include <QSGTransformNode>
#include <QSGVertexColorMaterial>

#include <algorithm>
#include <array>

namespace songview {
namespace {

// Quadratic bloom tessellation: 9 stops per side, alpha = peak * t^2 with
// t = 0 at the outer edge and 1 at the core, baked directly into vertex
// colors (each segment interpolates linearly between its boundary stops).
constexpr int kBloomSegments = 8;
constexpr int kBloomStops = kBloomSegments + 1;

class PlayheadNode final : public QSGGeometryNode
{
  public:
    PlayheadNode()
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

class PlayheadClipNode final : public QSGClipNode
{
  public:
    PlayheadClipNode()
    {
        auto *geometry = new QSGGeometry(QSGGeometry::defaultAttributes_Point2D(), 4);
        geometry->setDrawingMode(QSGGeometry::DrawTriangleStrip);
        setGeometry(geometry);
        setFlag(OwnsGeometry);
        setIsRectangular(true);

        m_transform = new QSGTransformNode;
        appendChildNode(m_transform);
        m_transform->appendChildNode(new PlayheadNode);
    }

    PlayheadNode *content() const { return static_cast<PlayheadNode *>(m_transform->firstChild()); }

    void setContentTransform(const QMatrix4x4 &transform) { m_transform->setMatrix(transform); }

  private:
    QSGTransformNode *m_transform = nullptr;
};

class PlayheadRootNode final : public QSGNode
{
  public:
    PlayheadRootNode()
    {
        m_bodyRoot = new QSGNode;
        appendChildNode(m_bodyRoot);
        m_triangleClip = new PlayheadClipNode;
        appendChildNode(m_triangleClip);
    }

    void setBodyStripCount(int count)
    {
        while (m_bodyRoot->childCount() > count) {
            QSGNode *node = m_bodyRoot->lastChild();
            m_bodyRoot->removeChildNode(node);
            delete node;
        }
        while (m_bodyRoot->childCount() < count)
            m_bodyRoot->appendChildNode(new PlayheadClipNode);
    }

    int bodyStripCount() const { return m_bodyRoot->childCount(); }

    PlayheadClipNode *bodyStrip(int index) const
    {
        QSGNode *node = m_bodyRoot->firstChild();
        for (int current = 0; current < index; ++current)
            node = node->nextSibling();
        return static_cast<PlayheadClipNode *>(node);
    }

    PlayheadClipNode *triangleClip() const { return m_triangleClip; }

    void setContentX(qreal x)
    {
        QMatrix4x4 transform;
        transform.translate(x, 0.0);
        for (QSGNode *node = m_bodyRoot->firstChild(); node; node = node->nextSibling())
            static_cast<PlayheadClipNode *>(node)->setContentTransform(transform);
        m_triangleClip->setContentTransform(transform);
    }

  private:
    QSGNode *m_bodyRoot = nullptr;
    PlayheadClipNode *m_triangleClip = nullptr;
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

    void triangle(const std::array<QPointF, 3> &points, const QColor &color)
    {
        setVertex(*m_vertices++, points[0], color);
        setVertex(*m_vertices++, points[1], color);
        setVertex(*m_vertices++, points[2], color);
    }

  private:
    QSGGeometry::ColoredPoint2D *m_vertices = nullptr;
};

void setRectangularClip(PlayheadClipNode *clip, const QRectF &rect)
{
    clip->setClipRect(rect);
    QSGGeometry::Point2D *const vertices = clip->geometry()->vertexDataAsPoint2D();
    vertices[0].set(float(rect.left()), float(rect.top()));
    vertices[1].set(float(rect.left()), float(rect.bottom()));
    vertices[2].set(float(rect.right()), float(rect.top()));
    vertices[3].set(float(rect.right()), float(rect.bottom()));
    clip->geometry()->markVertexDataDirty();
    clip->markDirty(QSGNode::DirtyGeometry);
}

// Quadratic ramp alpha = peak * t^2 evaluated at position x, t running 0 at
// the outer edge to 1 at the core. Evaluating from the position (not the stop
// index) keeps the gradient continuous where a clip rect truncates segments.
qreal bloomAlphaAt(qreal x, qreal coreX, qreal span, qreal peakAlpha)
{
    const qreal t = 1.0 - std::abs(x - coreX) / span;
    return peakAlpha * t * t;
}

struct BloomSegment {
    qreal left = 0.0;
    qreal right = 0.0;
    qreal leftAlpha = 0.0;
    qreal rightAlpha = 0.0;
};

struct BloomSideGeometry {
    std::array<BloomSegment, kBloomSegments> segments{};
    int quads = 0;
};

// One bloom half over clip: glowOnLeft places the core on the segment's right
// edge. Built once so the vertex count and the fill traversal share numbers.
BloomSideGeometry buildBloomSide(const QRectF &clip, qreal coreX, qreal span, bool glowOnLeft,
                                 qreal peakAlpha)
{
    BloomSideGeometry side;
    if (span <= 0.0 || clip.isEmpty())
        return side;
    const qreal direction = glowOnLeft ? -1.0 : 1.0;
    std::array<qreal, kBloomStops> x{};
    std::array<qreal, kBloomStops> alpha{};
    for (int i = 0; i < kBloomStops; ++i) {
        const qreal t = qreal(i) / qreal(kBloomSegments);
        x[i] = std::clamp(coreX + direction * span * (1.0 - t), clip.left(), clip.right());
        alpha[i] = bloomAlphaAt(x[i], coreX, span, peakAlpha);
    }
    // Writer.rect wants ascending columns; the right glow traverses
    // outer-to-core, i.e. descending x.
    if (direction > 0.0) {
        std::reverse(x.begin(), x.end());
        std::reverse(alpha.begin(), alpha.end());
    }
    for (int i = 0; i < kBloomSegments; ++i) {
        if (x[i + 1] > x[i])
            side.segments[side.quads++] = BloomSegment{x[i], x[i + 1], alpha[i], alpha[i + 1]};
    }
    return side;
}

void writeBloomSide(GeometryWriter &writer, const BloomSideGeometry &side, qreal top, qreal bottom,
                    const QColor &color)
{
    for (int i = 0; i < side.quads; ++i) {
        const BloomSegment &segment = side.segments[i];
        QColor leftColor = color;
        leftColor.setAlphaF(segment.leftAlpha);
        QColor rightColor = color;
        rightColor.setAlphaF(segment.rightAlpha);
        writer.rect(segment.left, top, segment.right, bottom, leftColor, rightColor);
    }
}

// Ruler triangle in the mapped band's local coordinates: apex on the core,
// sitting on the band's continuous bottom (QRectF::bottom() == y + height).
std::array<QPointF, 3> rulerTriangle(qreal coreX, const QRectF &band, int halfWidth, int height,
                                     bool pointsUp)
{
    const qreal top = band.bottom() - height;
    const qreal bottom = top + height;
    if (pointsUp)
        return {QPointF{coreX, top}, QPointF{coreX - halfWidth, bottom},
                QPointF{coreX + halfWidth, bottom}};
    return {QPointF{coreX, bottom}, QPointF{coreX - halfWidth, top},
            QPointF{coreX + halfWidth, top}};
}

} // namespace

TimelinePlayheadItem::TimelinePlayheadItem(QQuickItem *parent) : QQuickItem(parent)
{
    setFlag(ItemHasContents, true);
}

qreal TimelinePlayheadItem::localX() const noexcept
{
    return m_localX;
}

void TimelinePlayheadItem::setLocalX(qreal x) noexcept
{
    if (m_localX == x)
        return;
    m_localX = x;
    markTransformDirty();
    emit localXChanged();
}

QColor TimelinePlayheadItem::color() const
{
    return m_color;
}

void TimelinePlayheadItem::setColor(const QColor &color)
{
    if (m_color == color)
        return;
    m_color = color;
    markGeometryDirty();
    emit colorChanged();
}

qreal TimelinePlayheadItem::peakAlpha() const noexcept
{
    return m_peakAlpha;
}

void TimelinePlayheadItem::setPeakAlpha(qreal alpha) noexcept
{
    if (m_peakAlpha == alpha)
        return;
    m_peakAlpha = alpha;
    markGeometryDirty();
    emit colorChanged();
}

qreal TimelinePlayheadItem::glowLeft() const noexcept
{
    return m_glowLeft;
}

void TimelinePlayheadItem::setGlowLeft(qreal extent) noexcept
{
    if (m_glowLeft == extent)
        return;
    m_glowLeft = extent;
    m_geometryDirty = true;
    m_transformDirty = true;
    update();
    emit shapeChanged();
}

qreal TimelinePlayheadItem::glowRight() const noexcept
{
    return m_glowRight;
}

void TimelinePlayheadItem::setGlowRight(qreal extent) noexcept
{
    if (m_glowRight == extent)
        return;
    m_glowRight = extent;
    markGeometryDirty();
    emit shapeChanged();
}

qreal TimelinePlayheadItem::lineWidthPx() const noexcept
{
    return m_lineWidthPx;
}

void TimelinePlayheadItem::setLineWidthPx(qreal width) noexcept
{
    if (m_lineWidthPx == width)
        return;
    m_lineWidthPx = width;
    markGeometryDirty();
    emit shapeChanged();
}

bool TimelinePlayheadItem::trianglePointsUp() const noexcept
{
    return m_trianglePointsUp;
}

void TimelinePlayheadItem::setTrianglePointsUp(bool pointsUp) noexcept
{
    if (m_trianglePointsUp == pointsUp)
        return;
    m_trianglePointsUp = pointsUp;
    markGeometryDirty();
    emit shapeChanged();
}

int TimelinePlayheadItem::triangleHalfWidthPx() const noexcept
{
    return m_triangleHalfWidthPx;
}

void TimelinePlayheadItem::setTriangleHalfWidthPx(int halfWidth) noexcept
{
    if (m_triangleHalfWidthPx == halfWidth)
        return;
    m_triangleHalfWidthPx = halfWidth;
    m_geometryDirty = true;
    m_clipDirty = true;
    update();
    emit shapeChanged();
}

int TimelinePlayheadItem::triangleHeightPx() const noexcept
{
    return m_triangleHeightPx;
}

void TimelinePlayheadItem::setTriangleHeightPx(int height) noexcept
{
    if (m_triangleHeightPx == height)
        return;
    m_triangleHeightPx = height;
    markGeometryDirty();
    emit shapeChanged();
}

QRectF TimelinePlayheadItem::rulerPlotRect() const
{
    return m_rulerPlotRect;
}

void TimelinePlayheadItem::setRulerPlotRect(const QRectF &rect)
{
    if (m_rulerPlotRect == rect)
        return;
    m_rulerPlotRect = rect;
    m_geometryDirty = true;
    m_clipDirty = true;
    update();
    emit clipsChanged();
}

QVariantList TimelinePlayheadItem::bodyPlotRects() const
{
    return QVariantList{m_bodyPlotRects.cbegin(), m_bodyPlotRects.cend()};
}

void TimelinePlayheadItem::setBodyPlotRects(const QVariantList &rects)
{
    QList<QRectF> converted;
    converted.reserve(rects.size());
    for (const QVariant &value : rects) {
        if (value.canConvert<QRectF>())
            converted.append(value.toRectF());
    }
    if (converted == m_bodyPlotRects)
        return;
    m_bodyPlotRects = std::move(converted);
    markClipDirty();
    emit clipsChanged();
}

void TimelinePlayheadItem::markClipDirty()
{
    m_clipDirty = true;
    syncBodyClips();
    update();
}

void TimelinePlayheadItem::markGeometryDirty()
{
    m_geometryDirty = true;
    update();
}

void TimelinePlayheadItem::markTransformDirty()
{
    m_transformDirty = true;
    update();
}

void TimelinePlayheadItem::syncBodyClips()
{
    m_bodyClips.clear();
    m_bodyClips.reserve(m_bodyPlotRects.size());
    const QRectF bounds = boundingRect();
    for (const QRectF &plot : m_bodyPlotRects) {
        const QRectF clipped = plot.translated(0.0, -y()).intersected(bounds);
        if (!clipped.isEmpty())
            m_bodyClips.append(clipped);
    }
}

QRectF TimelinePlayheadItem::triangleClipRect() const
{
    if (!m_rulerPlotRect.isValid())
        return {};
    return m_rulerPlotRect.translated(0.0, -y()).adjusted(-m_triangleHalfWidthPx, 0.0, 0.0, 0.0);
}

void TimelinePlayheadItem::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    QQuickItem::geometryChange(newGeometry, oldGeometry);
    if (newGeometry == oldGeometry)
        return;
    m_geometryDirty = true;
    markClipDirty();
}

QSGNode *TimelinePlayheadItem::updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *)
{
    const bool newNode = !oldNode;
    auto *root = static_cast<PlayheadRootNode *>(oldNode);
    if (!root)
        root = new PlayheadRootNode;
    if (newNode) {
        m_clipDirty = true;
        m_geometryDirty = true;
        m_transformDirty = true;
    }
    if (!m_clipDirty && !m_geometryDirty && !m_transformDirty)
        return root;

    const int oldStripCount = root->bodyStripCount();
    if (m_clipDirty)
        root->setBodyStripCount(m_bodyClips.size());
    const bool fillBodyGeometry = m_geometryDirty || oldStripCount != root->bodyStripCount();

    if (m_clipDirty) {
        for (int index = 0; index < root->bodyStripCount(); ++index)
            setRectangularClip(root->bodyStrip(index), m_bodyClips.at(index));
        setRectangularClip(root->triangleClip(), triangleClipRect());
    }
    if (fillBodyGeometry) {
        for (int index = 0; index < root->bodyStripCount(); ++index) {
            PlayheadNode *content = root->bodyStrip(index)->content();
            writeBodyGeometry(content->geometry());
            content->markDirty(QSGNode::DirtyGeometry);
        }
    }
    if (m_geometryDirty) {
        PlayheadNode *triangle = root->triangleClip()->content();
        writeTriangleGeometry(triangle->geometry());
        triangle->markDirty(QSGNode::DirtyGeometry);
    }
    if (m_transformDirty)
        root->setContentX(m_localX - m_glowLeft);

    m_clipDirty = false;
    m_geometryDirty = false;
    m_transformDirty = false;
    return root;
}

int TimelinePlayheadItem::bodyVertexCount() const
{
    const QRectF bounds = boundingRect();
    const qreal coreHalfWidth = m_lineWidthPx / 2.0;
    int vertices = 6 * (buildBloomSide(bounds, m_glowLeft, m_glowLeft, true, m_peakAlpha).quads +
                        buildBloomSide(bounds, m_glowLeft, m_glowRight, false, m_peakAlpha).quads);
    if ((std::min)(m_glowLeft + coreHalfWidth, bounds.right()) >
        (std::max)(m_glowLeft - coreHalfWidth, bounds.left()))
        vertices += 6;
    return vertices;
}

void TimelinePlayheadItem::writeBodyGeometry(QSGGeometry *geometry) const
{
    geometry->allocate(bodyVertexCount());
    GeometryWriter writer(geometry->vertexDataAsColoredPoint2D());
    const QRectF bounds = boundingRect();
    const qreal coreHalfWidth = m_lineWidthPx / 2.0;
    writeBloomSide(writer, buildBloomSide(bounds, m_glowLeft, m_glowLeft, true, m_peakAlpha),
                   bounds.top(), bounds.bottom(), m_color);
    writeBloomSide(writer, buildBloomSide(bounds, m_glowLeft, m_glowRight, false, m_peakAlpha),
                   bounds.top(), bounds.bottom(), m_color);
    const qreal coreLeft = (std::max)(m_glowLeft - coreHalfWidth, bounds.left());
    const qreal coreRight = (std::min)(m_glowLeft + coreHalfWidth, bounds.right());
    if (coreRight > coreLeft)
        writer.rect(coreLeft, bounds.top(), coreRight, bounds.bottom(), m_color, m_color);
    geometry->markVertexDataDirty();
}

void TimelinePlayheadItem::writeTriangleGeometry(QSGGeometry *geometry) const
{
    const bool paintsTriangle =
        m_triangleHeightPx > 0 && m_triangleHalfWidthPx > 0 && m_rulerPlotRect.isValid();
    geometry->allocate(paintsTriangle ? 3 : 0);
    if (!paintsTriangle)
        return;
    GeometryWriter writer(geometry->vertexDataAsColoredPoint2D());
    writer.triangle(rulerTriangle(m_glowLeft, m_rulerPlotRect.translated(0.0, -y()),
                                  m_triangleHalfWidthPx, m_triangleHeightPx, m_trianglePointsUp),
                    m_color);
    geometry->markVertexDataDirty();
}

} // namespace songview
