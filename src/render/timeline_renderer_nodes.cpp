#include "timeline_renderer.h"

#include <algorithm>
#include <cmath>
#include <memory>
#include <unordered_map>
#include <vector>

#include <QtGui/qcolor.h>
#include <QtGui/qfont.h>
#include <QtGui/qmatrix4x4.h>
#include <QtGui/qtextlayout.h>
#include <QtGui/qtextoption.h>
#include <QtQuick/qquickwindow.h>
#include <QtQuick/qsggeometry.h>
#include <QtQuick/qsgnode.h>
#include <QtQuick/qsgrectanglenode.h>
#include <QtQuick/qsgrendernode.h>
#include <QtGui/qpainter.h>
#include <QtQuick/qsgrendererinterface.h>
#include <QtQuick/qsgtextnode.h>
#include <QtQuick/qsgvertexcolormaterial.h>

using RollProjection::Rect;
using RollRender::Label;

namespace {

bool drawable(const Rect &rect)
{
    return rect.w > 0 && rect.h > 0 && (rect.argb >> 24) != 0;
}

QRectF pixelCoverage(const Rect &rect, double dpr, QPointF origin)
{
    auto edge = [dpr](double v, double offset) {
        return std::ceil((v + offset) * dpr - 0.5) / dpr - offset;
    };
    const double left = edge(rect.x, origin.x());
    const double top = edge(rect.y, origin.y());
    return QRectF(left, top, edge(rect.x + rect.w, origin.x()) - left,
                  edge(rect.y + rect.h, origin.y()) - top);
}

class RectGeometryNode final : public QSGGeometryNode
{
  public:
    RectGeometryNode() : m_geometry(QSGGeometry::defaultAttributes_ColoredPoint2D(), 0)
    {
        m_geometry.setDrawingMode(QSGGeometry::DrawTriangles);
        m_geometry.setVertexDataPattern(QSGGeometry::DynamicPattern);
        setGeometry(&m_geometry);
        setMaterial(&m_material);
    }

    void commit(const std::vector<Rect> &rects)
    {
        const int count = int(std::count_if(rects.begin(), rects.end(), drawable));
        if (m_rectCount != count) {
            m_geometry.allocate(count * 6);
            m_rectCount = count;
        }
        QSGGeometry::ColoredPoint2D *v = m_geometry.vertexDataAsColoredPoint2D();
        for (const Rect &rect : rects) {
            if (!drawable(rect))
                continue;
            const float left = float(rect.x);
            const float top = float(rect.y);
            const float right = float(rect.x + rect.w);
            const float bottom = float(rect.y + rect.h);
            const auto alpha = uchar(rect.argb >> 24);
            const auto red = uchar((((rect.argb >> 16) & 0xFF) * alpha + 127) / 255);
            const auto green = uchar((((rect.argb >> 8) & 0xFF) * alpha + 127) / 255);
            const auto blue = uchar(((rect.argb & 0xFF) * alpha + 127) / 255);
            v[0].set(left, top, red, green, blue, alpha);
            v[1].set(left, bottom, red, green, blue, alpha);
            v[2].set(right, top, red, green, blue, alpha);
            v[3].set(right, top, red, green, blue, alpha);
            v[4].set(left, bottom, red, green, blue, alpha);
            v[5].set(right, bottom, red, green, blue, alpha);
            v += 6;
        }
        m_geometry.markVertexDataDirty();
        markDirty(QSGNode::DirtyGeometry);
    }

  private:
    QSGGeometry m_geometry;
    QSGVertexColorMaterial m_material;
    int m_rectCount = 0;
};

class PainterRectNode final : public QSGRenderNode
{
  public:
    explicit PainterRectNode(QQuickWindow *window) : m_window(window) {}

    void commit(const std::vector<Rect> &rects)
    {
        m_rects.clear();
        m_bounds = QRectF();
        for (const Rect &rect : rects) {
            if (!drawable(rect))
                continue;
            const QRectF area(rect.x, rect.y, rect.w, rect.h);
            m_rects.push_back({area, QColor::fromRgba(rect.argb)});
            m_bounds = m_bounds.united(area);
        }
        markDirty(QSGNode::DirtyMaterial);
    }

    StateFlags changedStates() const override { return {}; }
    RenderingFlags flags() const override { return BoundedRectRendering; }
    QRectF rect() const override { return m_bounds; }

    void render(const RenderState *state) override
    {
        auto *painter = static_cast<QPainter *>(m_window->rendererInterface()->getResource(
            m_window, QSGRendererInterface::PainterResource));
        painter->save();
        const QRegion *clip = state->clipRegion();
        if (clip && !clip->isEmpty())
            painter->setClipRegion(*clip, Qt::ReplaceClip);
        painter->setTransform(matrix()->toTransform());
        painter->setOpacity(inheritedOpacity());
        painter->setRenderHint(QPainter::Antialiasing, false);
        for (const auto &[area, color] : m_rects)
            painter->fillRect(area, color);
        painter->restore();
    }

  private:
    QQuickWindow *m_window;
    std::vector<std::pair<QRectF, QColor>> m_rects;
    QRectF m_bounds;
};

class RectLayerNode final : public QSGTransformNode
{
  public:
    RectLayerNode(bool software, QQuickWindow *window)
    {
        if (software) {
            m_painter = new PainterRectNode(window);
            appendChildNode(m_painter);
        } else {
            m_geometry = new RectGeometryNode;
            appendChildNode(m_geometry);
        }
    }

    void commit(const std::vector<Rect> &rects)
    {
        if (m_geometry)
            m_geometry->commit(rects);
        else
            m_painter->commit(rects);
    }

  private:
    RectGeometryNode *m_geometry = nullptr;
    PainterRectNode *m_painter = nullptr;
};

class RectClipNode final : public QSGClipNode
{
  public:
    RectClipNode() : m_geometry(QSGGeometry::defaultAttributes_Point2D(), 4)
    {
        setGeometry(&m_geometry);
        setIsRectangular(true);
    }

    void setRect(const QRectF &rect)
    {
        setClipRect(rect);
        QSGGeometry::updateRectGeometry(&m_geometry, rect);
        markDirty(QSGNode::DirtyGeometry);
    }

  private:
    QSGGeometry m_geometry;
};

struct LayoutKey {
    QString text;
    QString family;
    int pixelSize = 0;
    int weight = 0;
    double letterSpacing = 0;
    int alignment = 0;
    double width = 0;

    bool operator==(const LayoutKey &) const = default;
};

struct LayoutKeyHash {
    size_t operator()(const LayoutKey &key) const
    {
        return qHashMulti(0, key.text, key.family, key.pixelSize, key.weight, key.letterSpacing,
                          key.alignment, key.width);
    }
};

struct CachedLayout {
    std::unique_ptr<QTextLayout> layout;
    double naturalWidth = 0;
    double height = 0;
    quint64 serial = 0;
    quint64 frame = 0;
};

class LayoutCache
{
  public:
    void beginFrame() { ++m_frame; }

    const CachedLayout &acquire(const Label &label)
    {
        auto [it, inserted] = m_entries.try_emplace(
            LayoutKey{label.text, label.family, label.pixelSize, label.weight, label.letterSpacing,
                      label.horizontalAlignment,
                      label.horizontalAlignment == Qt::AlignLeft ? 0.0 : label.rect.w});
        CachedLayout &entry = it->second;
        if (inserted)
            layOut(entry, label);
        entry.frame = m_frame;
        return entry;
    }

    void purge()
    {
        std::erase_if(m_entries, [this](const auto &item) { return item.second.frame != m_frame; });
    }

  private:
    void layOut(CachedLayout &entry, const Label &label)
    {
        QFont font(label.family);
        font.setPixelSize(label.pixelSize);
        font.setWeight(QFont::Weight(label.weight));
        font.setLetterSpacing(QFont::AbsoluteSpacing, label.letterSpacing);
        font.setHintingPreference(QFont::PreferNoHinting);
        font.setFeature(QFont::Tag("tnum"), 1);
        QTextOption option;
        option.setAlignment(Qt::Alignment(label.horizontalAlignment));
        option.setWrapMode(QTextOption::NoWrap);
        option.setUseDesignMetrics(false);
        entry.layout = std::make_unique<QTextLayout>(label.text, font);
        entry.layout->setCacheEnabled(true);
        entry.layout->setTextOption(option);
        entry.layout->beginLayout();
        QTextLine line = entry.layout->createLine();
        if (line.isValid()) {
            line.setLineWidth(label.rect.w);
            line.setPosition(QPointF(0, 0));
            entry.naturalWidth = line.naturalTextWidth();
            entry.height = line.height();
        }
        entry.layout->endLayout();
        entry.serial = ++m_serial;
    }

    std::unordered_map<LayoutKey, CachedLayout, LayoutKeyHash> m_entries;
    quint64 m_frame = 0;
    quint64 m_serial = 0;
};

struct LabelSlot {
    QSGTransformNode *holder = nullptr;
    QSGRectangleNode *background = nullptr;
    RectClipNode *clip = nullptr;
    QSGTextNode *text = nullptr;
    QPointF origin{qQNaN(), qQNaN()};
    quint64 layoutSerial = 0;
    double dy = 0;
    uint32_t color = 0;
};

class LabelLayerNode final : public QSGTransformNode
{
  public:
    void commit(const std::vector<Label> &labels, QQuickWindow *window, double width,
                double height, QPointF origin)
    {
        m_layouts.beginFrame();
        size_t used = 0;
        for (const Label &label : labels) {
            const Rect &r = label.rect;
            if (!(r.w > 0 && r.h > 0) || r.x >= width || r.x + r.w <= 0 || r.y >= height
                || r.y + r.h <= 0)
                continue;
            const CachedLayout &layout = m_layouts.acquire(label);
            if (used == m_slots.size()) {
                LabelSlot &created = m_slots.emplace_back();
                created.holder = new QSGTransformNode;
                appendChildNode(created.holder);
            }
            realize(m_slots[used++], label, layout, window, origin);
        }
        while (m_slots.size() > used) {
            QSGTransformNode *holder = m_slots.back().holder;
            m_slots.pop_back();
            removeChildNode(holder);
            delete holder;
        }
        m_layouts.purge();
    }

  private:
    static void realize(LabelSlot &slot, const Label &label, const CachedLayout &layout,
                        QQuickWindow *window, QPointF sceneOrigin)
    {
        const Rect &r = label.rect;
        const QPointF origin(r.x, r.y);
        if (slot.origin != origin) {
            QMatrix4x4 matrix;
            matrix.translate(float(r.x), float(r.y));
            slot.holder->setMatrix(matrix);
            slot.origin = origin;
        }

        if (label.hasBackground) {
            if (!slot.background) {
                slot.background = window->createRectangleNode();
                slot.holder->prependChildNode(slot.background);
            }
            const Rect &b = label.background;
            slot.background->setRect(pixelCoverage(Rect{b.x - r.x, b.y - r.y, b.w, b.h},
                                                   window->effectiveDevicePixelRatio(),
                                                   sceneOrigin + origin));
            slot.background->setColor(QColor::fromRgba(b.argb));
        } else if (slot.background) {
            slot.holder->removeChildNode(slot.background);
            delete slot.background;
            slot.background = nullptr;
        }

        if (!slot.text) {
            slot.text = window->createTextNode();
            slot.text->setRenderType(QSGTextNode::NativeRendering);
            slot.holder->appendChildNode(slot.text);
            slot.layoutSerial = 0;
        }
        const bool clipped = layout.naturalWidth > r.w || layout.height > r.h;
        if (clipped && !slot.clip) {
            slot.holder->removeChildNode(slot.text);
            slot.clip = new RectClipNode;
            slot.clip->appendChildNode(slot.text);
            slot.holder->appendChildNode(slot.clip);
        } else if (!clipped && slot.clip) {
            slot.clip->removeChildNode(slot.text);
            slot.holder->removeChildNode(slot.clip);
            delete slot.clip;
            slot.clip = nullptr;
            slot.holder->appendChildNode(slot.text);
        }
        if (slot.clip)
            slot.clip->setRect(QRectF(0, 0, r.w, r.h));

        const double dy = (r.h - layout.height) / 2;
        if (slot.layoutSerial != layout.serial || slot.dy != dy || slot.color != label.color) {
            slot.text->clear();
            slot.text->setColor(QColor::fromRgba(label.color));
            slot.text->addTextLayout(QPointF(0, dy), layout.layout.get());
            slot.layoutSerial = layout.serial;
            slot.dy = dy;
            slot.color = label.color;
        }
    }

    LayoutCache m_layouts;
    std::vector<LabelSlot> m_slots;
};

class RollRootNode final : public QSGTransformNode
{
  public:
    RollRootNode(int band, bool software, QQuickWindow *window)
        : band(band), software(software), under(new RectLayerNode(software, window)),
          over(new RectLayerNode(software, window)), labels(new LabelLayerNode)
    {
        appendChildNode(under);
        if (band == 1) {
            appendChildNode(over);
            appendChildNode(labels);
        } else {
            appendChildNode(labels);
            appendChildNode(over);
        }
    }

    const int band;
    const bool software;
    RectLayerNode *const under;
    RectLayerNode *const over;
    LabelLayerNode *const labels;
};

} // namespace

QSGNode *TimelineRenderer::updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *)
{
    QQuickWindow *win = window();
    const bool software =
        win->rendererInterface()->graphicsApi() == QSGRendererInterface::Software;
    auto *root = static_cast<RollRootNode *>(oldNode);
    if (root && (root->band != m_bandRole || root->software != software)) {
        delete root;
        root = nullptr;
    }
    if (!root)
        root = new RollRootNode(m_bandRole, software, win);
    const QPointF sceneOrigin = mapToScene(QPointF(0, 0));
    root->under->commit(m_under);
    root->over->commit(m_over);
    root->labels->commit(m_labels, win, width(), height(), sceneOrigin);
    return root;
}
