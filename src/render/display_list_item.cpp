#include "display_list_item.h"

#include <QtCore/qmetaobject.h>
#include <QtCore/qstring.h>
#include <QtGui/qcolor.h>
#include <QtGui/qfont.h>
#include <QtGui/qmatrix4x4.h>
#include <QtGui/qpainter.h>
#include <QtGui/qtextlayout.h>
#include <QtGui/qtextoption.h>
#include <QtQuick/qquickwindow.h>
#include <QtQuick/qsggeometry.h>
#include <QtQuick/qsgnode.h>
#include <QtQuick/qsgrendererinterface.h>
#include <QtQuick/qsgrendernode.h>
#include <QtQuick/qsgtextnode.h>
#include <QtQuick/qsgvertexcolormaterial.h>
#include <cmath>
#include <memory>
#include <unordered_map>
#include <utility>
#include <vector>

namespace {

bool drawable(const PdDlRect &rect)
{
    return rect.w > 0 && rect.h > 0 && (rect.argb >> 24) != 0;
}

bool onLayer(const PdDlRect &rect, bool over)
{
    return drawable(rect) && bool(rect.flags & PD_DL_RECT_OVER) == over;
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

    void commit(const PdDlView &view, bool over)
    {
        const PdDlRect *rects = view.header ? view.rects : nullptr;
        const uint32_t count = view.header ? view.header->rectCount : 0;
        int visible = 0;
        for (uint32_t i = 0; i < count; ++i)
            visible += onLayer(rects[i], over);
        // Capacity only grows: allocate() invalidates the buffer and a fresh
        // allocation per visible-count change would churn every scroll frame.
        if (visible > m_rectCapacity) {
            m_geometry.allocate(visible * 6);
            m_rectCapacity = visible;
        }
        m_geometry.setVertexCount(visible * 6);
        QSGGeometry::ColoredPoint2D *v = m_geometry.vertexDataAsColoredPoint2D();
        for (uint32_t i = 0; i < count; ++i) {
            const PdDlRect &rect = rects[i];
            if (!onLayer(rect, over))
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
    int m_rectCapacity = 0;
};

class PainterRectNode final : public QSGRenderNode
{
  public:
    explicit PainterRectNode(QQuickWindow *window) : m_window(window) {}

    void commit(const PdDlView &view, bool over)
    {
        m_rects.clear();
        m_bounds = QRectF();
        const uint32_t count = view.header ? view.header->rectCount : 0;
        for (uint32_t i = 0; i < count; ++i) {
            const PdDlRect &rect = view.rects[i];
            if (!onLayer(rect, over))
                continue;
            const QRectF area(rect.x, rect.y, rect.w, rect.h);
            m_rects.emplace_back(area, QColor::fromRgba(rect.argb));
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

    void commit(const PdDlView &view, bool over)
    {
        if (m_geometry)
            m_geometry->commit(view, over);
        else
            m_painter->commit(view, over);
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

struct FontKey {
    QString family;
    int pixelSize = 0;
    int weight = 0;
    double letterSpacing = 0;

    bool operator==(const FontKey &) const = default;
};

struct FontKeyHash {
    size_t operator()(const FontKey &key) const
    {
        return qHashMulti(0, key.family, key.pixelSize, key.weight, key.letterSpacing);
    }
};

struct LayoutKey {
    QString text;
    FontKey font;
    int alignment = 0;
    double width = 0;

    bool operator==(const LayoutKey &) const = default;
};

struct LayoutKeyHash {
    size_t operator()(const LayoutKey &key) const
    {
        return qHashMulti(0, key.text, key.font.family, key.font.pixelSize, key.font.weight,
                          key.font.letterSpacing, key.alignment, key.width);
    }
};

struct CachedLayout {
    std::unique_ptr<QTextLayout> layout;
    double height = 0;
    quint64 serial = 0;
    quint64 frame = 0;
};

struct CachedFont {
    QFont font;
    quint64 frame = 0;
};

class LayoutCache
{
  public:
    void beginFrame() { ++m_frame; }

    const CachedLayout &acquire(const PdDlLabel &label, const PdDlView &view,
                                const PdDlFont &font)
    {
        const QString text = QString::fromUtf8(view.text + label.textOffset, label.textLength);
        FontKey fontKey = {QString::fromUtf8(view.text + font.familyOffset, font.familyLength),
                           int(label.pixelSize), font.weight, font.letterSpacing};
        const uint32_t align = label.flags & PD_DL_LABEL_ALIGN_MASK;
        const int alignment = align == PD_DL_LABEL_ALIGN_RIGHT ? Qt::AlignRight
                            : align == PD_DL_LABEL_ALIGN_CENTER ? Qt::AlignHCenter
                                                                 : Qt::AlignLeft;
        LayoutKey key = {text, fontKey, alignment, alignment == Qt::AlignLeft ? 0.0 : label.w};
        auto [it, inserted] = m_entries.try_emplace(std::move(key));
        CachedLayout &entry = it->second;
        if (inserted)
            layOut(entry, text, fontKey, alignment, label.w);
        fontFor(fontKey).frame = m_frame;
        entry.frame = m_frame;
        return entry;
    }

    void purge()
    {
        std::erase_if(m_entries, [this](const auto &item) { return item.second.frame != m_frame; });
        std::erase_if(m_fonts, [this](const auto &item) { return item.second.frame != m_frame; });
    }

  private:
    CachedFont &fontFor(const FontKey &key)
    {
        auto [fontIt, inserted] = m_fonts.try_emplace(key);
        if (inserted) {
            QFont &font = fontIt->second.font;
            font.setFamily(key.family);
            font.setPixelSize(key.pixelSize);
            font.setWeight(QFont::Weight(key.weight));
            font.setLetterSpacing(QFont::AbsoluteSpacing, key.letterSpacing);
            font.setHintingPreference(QFont::PreferNoHinting);
            font.setFeature(QFont::Tag("tnum"), 1);
        }
        return fontIt->second;
    }

    void layOut(CachedLayout &entry, const QString &text, const FontKey &key,
                int alignment, double width)
    {
        CachedFont &cached = fontFor(key);
        QTextOption option;
        option.setAlignment(Qt::Alignment(alignment));
        option.setWrapMode(QTextOption::NoWrap);
        option.setUseDesignMetrics(false);
        entry.layout = std::make_unique<QTextLayout>(text, cached.font);
        entry.layout->setCacheEnabled(true);
        entry.layout->setTextOption(option);
        entry.layout->beginLayout();
        QTextLine line = entry.layout->createLine();
        if (line.isValid()) {
            line.setLineWidth(width);
            line.setPosition(QPointF(0, 0));
            entry.height = line.height();
        }
        entry.layout->endLayout();
        entry.serial = ++m_serial;
    }

    std::unordered_map<FontKey, CachedFont, FontKeyHash> m_fonts;
    std::unordered_map<LayoutKey, CachedLayout, LayoutKeyHash> m_entries;
    quint64 m_frame = 0;
    quint64 m_serial = 0;
};

struct LabelSlot {
    QSGTransformNode *holder = nullptr;
    RectClipNode *clip = nullptr;
    QSGTextNode *text = nullptr;
    QPointF origin = {qQNaN(), qQNaN()};
    quint64 layoutSerial = 0;
    double dy = 0;
    uint32_t color = 0;
};

class LabelLayerNode final : public QSGTransformNode
{
  public:
    void commit(const PdDlView &view, QQuickWindow *window)
    {
        m_layouts.beginFrame();
        size_t used = 0;
        const uint32_t count = view.header ? view.header->labelCount : 0;
        for (uint32_t i = 0; i < count; ++i) {
            const PdDlLabel &label = view.labels[i];
            const PdDlFont *font = nullptr;
            for (uint32_t j = 0; j < view.header->fontCount; ++j) {
                if (view.fonts[j].id == label.fontId) {
                    font = &view.fonts[j];
                    break;
                }
            }
            if (!font)
                qFatal("DisplayList: label references missing font %u", label.fontId);
            const CachedLayout &layout = m_layouts.acquire(label, view, *font);
            if (used == m_slots.size()) {
                LabelSlot &created = m_slots.emplace_back();
                created.holder = new QSGTransformNode;
                appendChildNode(created.holder);
            }
            realize(m_slots[used++], label, layout, window);
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
    static void realize(LabelSlot &slot, const PdDlLabel &label,
                        const CachedLayout &layout, QQuickWindow *window)
    {
        const QPointF origin(label.x, label.y);
        if (slot.origin != origin) {
            QMatrix4x4 matrix;
            matrix.translate(float(label.x), float(label.y));
            slot.holder->setMatrix(matrix);
            slot.origin = origin;
        }
        if (!slot.text) {
            slot.text = window->createTextNode();
            slot.text->setRenderType(QSGTextNode::NativeRendering);
            slot.holder->appendChildNode(slot.text);
            slot.layoutSerial = 0;
        }
        const bool clipped = (label.flags & PD_DL_LABEL_CLIP) != 0;
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
            slot.clip->setRect(QRectF(0, 0, label.w, label.h));

        const double dy = (label.h - layout.height) / 2;
        if (slot.layoutSerial != layout.serial || slot.dy != dy || slot.color != label.argb) {
            slot.text->clear();
            slot.text->setColor(QColor::fromRgba(label.argb));
            slot.text->addTextLayout(QPointF(0, dy), layout.layout.get());
            slot.layoutSerial = layout.serial;
            slot.dy = dy;
            slot.color = label.argb;
        }
    }

    LayoutCache m_layouts;
    std::vector<LabelSlot> m_slots;
};

class DisplayRootNode final : public QSGTransformNode
{
  public:
    DisplayRootNode(bool software, QQuickWindow *window)
        : software(software), window(window), under(new RectLayerNode(software, window)),
          labels(new LabelLayerNode), over(new RectLayerNode(software, window))
    {
        appendChildNode(under);
        appendChildNode(labels);
        appendChildNode(over);
    }

    const bool software;
    QQuickWindow *const window;
    RectLayerNode *const under;
    LabelLayerNode *const labels;
    RectLayerNode *const over;
};

} // namespace

DisplayList::DisplayList(QQuickItem *parent) : QQuickItem(parent)
{
    setFlag(ItemHasContents, true);
}

DisplayList::~DisplayList()
{
    QObject::disconnect(m_afterAnimating);
    QObject::disconnect(m_sourceDestroyed);
}

void DisplayList::clearFrame()
{
    m_view = {};
    m_blob.clear();
    if (m_fetchedRevision != -1) {
        m_fetchedRevision = -1;
        emit fetchedRevisionChanged();
    }
    update();
}

void DisplayList::setSource(QObject *source)
{
    if (m_source == source)
        return;
    QObject::disconnect(m_sourceDestroyed);
    m_source = source;
    if (source) {
        m_sourceDestroyed = connect(source, &QObject::destroyed, this, [this] {
            clearFrame();
            emit sourceChanged();
        });
    }
    clearFrame();
    emit sourceChanged();
}

void DisplayList::setList(int list)
{
    if (m_list == list)
        return;
    m_list = list;
    clearFrame();
    emit listChanged();
}

void DisplayList::setRevision(int revision)
{
    if (m_revision == revision)
        return;
    m_revision = revision;
    update();
    emit revisionChanged();
}

QVariantMap DisplayList::face(double id) const
{
    if (!m_view.header || !std::isfinite(id) || id < 0 || id >= 0x1p64)
        return {};
    const uint64_t wanted = uint64_t(id);
    for (uint32_t i = 0; i < m_view.header->rectCount; ++i) {
        const PdDlRect &rect = m_view.rects[i];
        if (rect.id == wanted) {
            return {{QStringLiteral("x"), rect.x}, {QStringLiteral("y"), rect.y},
                    {QStringLiteral("width"), rect.w}, {QStringLiteral("height"), rect.h},
                    {QStringLiteral("fill"), QColor::fromRgba(rect.argb)}};
        }
    }
    return {};
}

void DisplayList::itemChange(ItemChange change, const ItemChangeData &data)
{
    QQuickItem::itemChange(change, data);
    if (change != ItemSceneChange)
        return;
    QObject::disconnect(m_afterAnimating);
    m_afterAnimating = {};
    if (data.window)
        m_afterAnimating = connect(data.window, &QQuickWindow::afterAnimating,
                                   this, &DisplayList::pullFrame, Qt::DirectConnection);
}

void DisplayList::pullFrame()
{
    if (!m_source || !window())
        return;
    const int liveRevision = m_source->property("displayRevision").toInt();
    if (liveRevision == m_fetchedRevision)
        return;
    QByteArray blob;
    if (!QMetaObject::invokeMethod(m_source, "displayList", Qt::DirectConnection,
                                   Q_RETURN_ARG(QByteArray, blob), Q_ARG(int, m_list)))
        qFatal("DisplayList: displayList(int) invocation failed");
    PdDlView view = {};
    if (!pd_dl_decode(blob.constData(), size_t(blob.size()), &view))
        qFatal("DisplayList: invalid display list");
    m_blob = std::move(blob);
    m_view = view;
    m_fetchedRevision = liveRevision;
    emit fetchedRevisionChanged();
    update();
}

QSGNode *DisplayList::updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *)
{
    QQuickWindow *win = window();
    const bool software =
        win->rendererInterface()->graphicsApi() == QSGRendererInterface::Software;
    auto *root = static_cast<DisplayRootNode *>(oldNode);
    if (root && (root->software != software || root->window != win)) {
        delete root;
        root = nullptr;
    }
    if (!root)
        root = new DisplayRootNode(software, win);
    root->under->commit(m_view, false);
    root->labels->commit(m_view, win);
    root->over->commit(m_view, true);
    return root;
}
