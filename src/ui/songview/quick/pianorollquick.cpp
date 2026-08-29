#include "ui/songview/quick/pianorollquick.h"

#include "ui/songview/pianoroll.h"
#include "ui/theme/themeruntime.h"

#include <QList>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickWindow>
#include <QResizeEvent>
#include <QSGGeometry>
#include <QSGGeometryNode>
#include <QSGVertexColorMaterial>
#include <QUrl>
#include <QtQml>

#include <algorithm>
#include <cstddef>
#include <mutex>
#include <utility>

namespace songview {
namespace {

constexpr int cRectanglesPerGeometryChunk = 256;
constexpr int cVerticesPerRectangle = 6;
constexpr int cVerticesPerGeometryChunk = cRectanglesPerGeometryChunk * cVerticesPerRectangle;

class PianoRollQuickGeometryChunkNode final : public QSGGeometryNode
{
  public:
    bool isSubtreeBlocked() const override { return m_blocked; }

    void setBlocked(bool blocked)
    {
        if (m_blocked == blocked)
            return;
        m_blocked = blocked;
        markDirty(DirtySubtreeBlocked);
    }

  private:
    bool m_blocked = false;
};

class PianoRollQuickLayerNode final : public QSGNode
{
  public:
    const PianoRollQuickScene *builtScene = nullptr;
    PianoRollQuickItem::Layer builtLayer = PianoRollQuickItem::Layer::Count;
    quint64 builtRevision = 0;
};

PianoRollQuickGeometryChunkNode *newGeometryChunk()
{
    auto *node = new PianoRollQuickGeometryChunkNode;
    auto *geometry =
        new QSGGeometry(QSGGeometry::defaultAttributes_ColoredPoint2D(), cVerticesPerGeometryChunk);
    geometry->setDrawingMode(QSGGeometry::DrawTriangles);
    geometry->setVertexDataPattern(QSGGeometry::DynamicPattern);
    node->setGeometry(geometry);
    node->setFlag(QSGNode::OwnsGeometry);
    auto *material = new QSGVertexColorMaterial;
    material->setFlag(QSGMaterial::Blending);
    node->setMaterial(material);
    node->setFlag(QSGNode::OwnsMaterial);
    return node;
}

void clearUnusedVertices(QSGGeometry::ColoredPoint2D *vertices, int usedVertices)
{
    for (int vertex = usedVertices; vertex < cVerticesPerGeometryChunk; ++vertex)
        vertices[vertex].set(0.0f, 0.0f, 0, 0, 0, 0);
}

void blockChunks(QSGNode *chunk)
{
    while (chunk) {
        auto *geometryChunk = static_cast<PianoRollQuickGeometryChunkNode *>(chunk);
        chunk = chunk->nextSibling();
        geometryChunk->setBlocked(true);
    }
}

void setVertex(QSGGeometry::ColoredPoint2D &vertex, const QPointF &point, const QColor &color)
{
    const int alpha = color.alpha();
    const auto premultiplied = [alpha](int component) {
        return uchar((component * alpha + 127) / 255);
    };
    vertex.set(float(point.x()), float(point.y()), premultiplied(color.red()),
               premultiplied(color.green()), premultiplied(color.blue()), uchar(alpha));
}

void writeRect(QSGGeometry::ColoredPoint2D *&vertices, const PianoRollQuickRect &primitive)
{
    const QRectF rect = primitive.rect.normalized();
    setVertex(*vertices++, rect.topLeft(), primitive.topLeft);
    setVertex(*vertices++, rect.bottomLeft(), primitive.bottomLeft);
    setVertex(*vertices++, rect.topRight(), primitive.topRight);
    setVertex(*vertices++, rect.topRight(), primitive.topRight);
    setVertex(*vertices++, rect.bottomLeft(), primitive.bottomLeft);
    setVertex(*vertices++, rect.bottomRight(), primitive.bottomRight);
}

int changedRoles(const PianoRollQuickTextModel::Record &oldRecord,
                 const PianoRollQuickTextModel::Record &newRecord)
{
    int roles = 0;
    if (oldRecord.rect != newRecord.rect)
        roles |= 1 << 0;
    if (oldRecord.text != newRecord.text)
        roles |= 1 << 1;
    if (oldRecord.color != newRecord.color)
        roles |= 1 << 2;
    if (oldRecord.font != newRecord.font)
        roles |= 1 << 3;
    if (oldRecord.horizontalAlignment != newRecord.horizontalAlignment)
        roles |= 1 << 4;
    if (oldRecord.verticalAlignment != newRecord.verticalAlignment)
        roles |= 1 << 5;
    return roles;
}

QList<int> roleList(int mask)
{
    QList<int> roles;
    if (mask & (1 << 0))
        roles.append(PianoRollQuickTextModel::RectRole);
    if (mask & (1 << 1))
        roles.append(PianoRollQuickTextModel::TextRole);
    if (mask & (1 << 2))
        roles.append(PianoRollQuickTextModel::ColorRole);
    if (mask & (1 << 3))
        roles.append(PianoRollQuickTextModel::FontRole);
    if (mask & (1 << 4))
        roles.append(PianoRollQuickTextModel::HorizontalAlignmentRole);
    if (mask & (1 << 5))
        roles.append(PianoRollQuickTextModel::VerticalAlignmentRole);
    return roles;
}

} // namespace

PianoRollQuickTextModel::PianoRollQuickTextModel(QObject *parent) : QAbstractListModel(parent)
{
    m_roleNames.insert(RectRole, QByteArrayLiteral("labelRect"));
    m_roleNames.insert(TextRole, QByteArrayLiteral("labelText"));
    m_roleNames.insert(ColorRole, QByteArrayLiteral("labelColor"));
    m_roleNames.insert(FontRole, QByteArrayLiteral("labelFont"));
    m_roleNames.insert(HorizontalAlignmentRole, QByteArrayLiteral("labelHorizontalAlignment"));
    m_roleNames.insert(VerticalAlignmentRole, QByteArrayLiteral("labelVerticalAlignment"));
}

int PianoRollQuickTextModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid())
        return 0;
    return static_cast<int>(m_records.size());
}

QVariant PianoRollQuickTextModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= static_cast<int>(m_records.size()))
        return {};

    const Record &record = m_records[static_cast<std::size_t>(index.row())];
    switch (role) {
    case RectRole:
        return record.rect;
    case TextRole:
        return record.text;
    case ColorRole:
        return record.color;
    case FontRole:
        return record.font;
    case HorizontalAlignmentRole:
        return static_cast<int>(record.horizontalAlignment);
    case VerticalAlignmentRole:
        return static_cast<int>(record.verticalAlignment);
    }
    return {};
}

QHash<int, QByteArray> PianoRollQuickTextModel::roleNames() const
{
    return m_roleNames;
}

void PianoRollQuickTextModel::setRecords(std::span<const Record> records)
{
    const auto keyFirst = [](const KeyRowEntry &entry, const PianoRollQuickTextKey &key) {
        return entry.key < key;
    };
    const auto byKey = [](const KeyRowEntry &left, const KeyRowEntry &right) {
        return left.key < right.key;
    };
    const auto rowFor = [&keyFirst](std::vector<KeyRowEntry> &index,
                                    const PianoRollQuickTextKey &key) -> int * {
        const auto found = std::lower_bound(index.begin(), index.end(), key, keyFirst);
        if (found == index.end() || found->key != key)
            return nullptr;
        return &found->row;
    };

    m_targetRows.clear();
    for (int target = 0; target < static_cast<int>(records.size()); ++target)
        m_targetRows.push_back({records[static_cast<std::size_t>(target)].key, target});
    std::sort(m_targetRows.begin(), m_targetRows.end(), byKey);
    Q_ASSERT(std::adjacent_find(m_targetRows.begin(), m_targetRows.end(),
                                [](const KeyRowEntry &left, const KeyRowEntry &right) {
                                    return left.key == right.key;
                                }) == m_targetRows.end());

    for (int row = static_cast<int>(m_records.size()) - 1; row >= 0;) {
        if (rowFor(m_targetRows, m_records[static_cast<std::size_t>(row)].key) != nullptr) {
            --row;
            continue;
        }

        const int end = row;
        while (row >= 0 &&
               rowFor(m_targetRows, m_records[static_cast<std::size_t>(row)].key) == nullptr)
            --row;
        const int first = row + 1;
        beginRemoveRows(QModelIndex(), first, end);
        m_records.erase(m_records.begin() + first, m_records.begin() + end + 1);
        endRemoveRows();
    }

    m_currentRows.clear();
    for (int row = 0; row < static_cast<int>(m_records.size()); ++row)
        m_currentRows.push_back({m_records[static_cast<std::size_t>(row)].key, row});
    std::sort(m_currentRows.begin(), m_currentRows.end(), byKey);

    int appended = 0;
    for (const Record &record : records) {
        if (rowFor(m_currentRows, record.key) == nullptr)
            ++appended;
    }
    if (appended > 0) {
        beginInsertRows(QModelIndex(), rowCount(), rowCount() + appended - 1);
        for (const Record &record : records) {
            if (rowFor(m_currentRows, record.key) != nullptr)
                continue;
            m_records.push_back(record);
        }
        endInsertRows();

        m_currentRows.clear();
        for (int row = 0; row < static_cast<int>(m_records.size()); ++row)
            m_currentRows.push_back({m_records[static_cast<std::size_t>(row)].key, row});
        std::sort(m_currentRows.begin(), m_currentRows.end(), byKey);
    }

    for (int target = 0; target < static_cast<int>(records.size()); ++target) {
        const PianoRollQuickTextKey &key = records[static_cast<std::size_t>(target)].key;
        const int source = *rowFor(m_currentRows, key);
        if (source == target)
            continue;

        beginMoveRows(QModelIndex(), source, source, QModelIndex(), target);
        for (int row = target; row < source; ++row) {
            ++*rowFor(m_currentRows, m_records[static_cast<std::size_t>(row)].key);
        }
        std::rotate(m_records.begin() + target, m_records.begin() + source,
                    m_records.begin() + source + 1);
        endMoveRows();
        *rowFor(m_currentRows, key) = target;
    }

    const int count = static_cast<int>(records.size());
    for (int row = 0; row < count;) {
        const int mask = changedRoles(m_records[static_cast<std::size_t>(row)],
                                      records[static_cast<std::size_t>(row)]);
        if (mask == 0) {
            ++row;
            continue;
        }

        int end = row + 1;
        while (end < count && changedRoles(m_records[static_cast<std::size_t>(end)],
                                           records[static_cast<std::size_t>(end)]) == mask) {
            ++end;
        }

        std::copy(records.begin() + row, records.begin() + end, m_records.begin() + row);
        emit dataChanged(index(row), index(end - 1), roleList(mask));
        row = end;
    }
}

PianoRollQuickScene::PianoRollQuickScene(QObject *parent) : QObject(parent)
{
    m_noteTextModel = new PianoRollQuickTextModel(this);
    m_loadingTextModel = new PianoRollQuickTextModel(this);
    m_keyboardTextModel = new PianoRollQuickTextModel(this);
}

QAbstractItemModel *PianoRollQuickScene::noteTextModel() const noexcept
{
    return m_noteTextModel;
}

QAbstractItemModel *PianoRollQuickScene::loadingTextModel() const noexcept
{
    return m_loadingTextModel;
}

QAbstractItemModel *PianoRollQuickScene::keyboardTextModel() const noexcept
{
    return m_keyboardTextModel;
}

const PianoRollQuickLayerData &PianoRollQuickScene::layer(PianoRollQuickLayer layer) const noexcept
{
    return m_layers[static_cast<std::size_t>(layer)];
}

PianoRollQuickLayerData &PianoRollQuickScene::layer(PianoRollQuickLayer layer) noexcept
{
    return m_layers[static_cast<std::size_t>(layer)];
}

bool PianoRollQuickScene::hoverChipVisible() const noexcept
{
    return m_hoverChipVisible;
}

QRectF PianoRollQuickScene::hoverChipRect() const noexcept
{
    return m_hoverChipRect;
}

QString PianoRollQuickScene::hoverChipText() const
{
    return m_hoverChipText;
}

QColor PianoRollQuickScene::hoverChipFill() const
{
    return m_hoverChipFill;
}

QFont PianoRollQuickScene::hoverChipFont() const
{
    return m_hoverChipFont;
}

qreal PianoRollQuickScene::hoverChipRadius() const noexcept
{
    return m_hoverChipRadius;
}

void PianoRollQuickScene::setHoverChip(bool visible, const QRectF &rect, const QString &text,
                                       const QColor &fill, const QFont &font, qreal radius)
{
    if (m_hoverChipVisible == visible && m_hoverChipRect == rect && m_hoverChipText == text &&
        m_hoverChipFill == fill && m_hoverChipFont == font && m_hoverChipRadius == radius) {
        return;
    }

    m_hoverChipVisible = visible;
    m_hoverChipRect = rect;
    m_hoverChipText = text;
    m_hoverChipFill = fill;
    m_hoverChipFont = font;
    m_hoverChipRadius = radius;
    emit hoverChipChanged();
}

PianoRollQuickItem::PianoRollQuickItem(QQuickItem *parent) : QQuickItem(parent)
{
    setFlag(ItemHasContents, true);
}

PianoRollQuickLayer PianoRollQuickItem::sceneLayer() const noexcept
{
    return m_layer;
}

void PianoRollQuickItem::setSceneLayer(PianoRollQuickLayer layer)
{
    if (layer >= PianoRollQuickLayer::Count) {
        qWarning().noquote() << "Qt Quick piano roll item rejected invalid scene layer"
                             << static_cast<int>(layer);
        return;
    }
    if (layer == m_layer)
        return;
    m_layer = layer;
    emit sceneLayerChanged();
    update();
}

void PianoRollQuickItem::setScene(PianoRollQuickScene *scene)
{
    if (m_scene == scene)
        return;
    m_scene = scene;
    update();
}

QSGNode *PianoRollQuickItem::updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *)
{
    const PianoRollQuickScene *scene = m_scene;
    const PianoRollQuickLayer layerIndex = m_layer;
    const PianoRollQuickLayerData *layer = scene ? &scene->layer(layerIndex) : nullptr;
    auto *node = static_cast<PianoRollQuickLayerNode *>(oldNode);
    if (!layer) {
        if (node) {
            blockChunks(node->firstChild());
            node->builtScene = nullptr;
        }
        return node;
    }
    if (node && node->builtScene == scene && node->builtRevision == layer->revision &&
        node->builtLayer == layerIndex) {
        return node;
    }
    if (!node)
        node = new PianoRollQuickLayerNode;

    QSGNode *child = node->firstChild();
    std::size_t first = 0;
    while (first < layer->rects.size()) {
        if (!child) {
            auto *newChunk = newGeometryChunk();
            node->appendChildNode(newChunk);
            child = newChunk;
        }

        auto *chunk = static_cast<PianoRollQuickGeometryChunkNode *>(child);
        child = child->nextSibling();
        chunk->setBlocked(false);

        const auto remaining = layer->rects.size() - first;
        const int rectanglesInChunk = static_cast<int>(
            std::min(remaining, static_cast<std::size_t>(cRectanglesPerGeometryChunk)));
        QSGGeometry *geometry = chunk->geometry();
        auto *vertices = geometry->vertexDataAsColoredPoint2D();
        auto *nextVertex = vertices;
        for (int rect = 0; rect < rectanglesInChunk; ++rect)
            writeRect(nextVertex, layer->rects[first + static_cast<std::size_t>(rect)]);
        if (rectanglesInChunk < cRectanglesPerGeometryChunk)
            clearUnusedVertices(vertices, rectanglesInChunk * cVerticesPerRectangle);
        geometry->markVertexDataDirty();
        chunk->markDirty(QSGNode::DirtyGeometry);

        first += static_cast<std::size_t>(rectanglesInChunk);
    }
    blockChunks(child);

    node->builtScene = scene;
    node->builtLayer = layerIndex;
    node->builtRevision = layer->revision;
    return node;
}

PianoRollQuickView::PianoRollQuickView(PianoRoll &roll) : QQuickWidget(&roll), m_roll(roll)
{
    static std::once_flag registered;
    std::call_once(registered, [] {
        qmlRegisterType<PianoRollQuickItem>("Porydaw.PianoRoll", 1, 0, "PianoRollQuickItem");
    });

    setObjectName(QStringLiteral("pianoRollQuickCanvas"));
    setAttribute(Qt::WA_TransparentForMouseEvents);
    setAttribute(Qt::WA_OpaquePaintEvent, true);
    // Stays a normal child widget so the separate PlayheadOverlay stacks above.
    setAttribute(Qt::WA_AlwaysStackOnTop, false);
    setFocusPolicy(Qt::NoFocus);
    setResizeMode(QQuickWidget::SizeRootObjectToView);

    m_scene = new PianoRollQuickScene(this);
    rootContext()->setContextProperty(QStringLiteral("pianoRollScene"), m_scene);

    setSource(QUrl(QStringLiteral("qrc:/Porydaw/PianoRoll/PianoRollCanvas.qml")));
    if (status() != QQuickWidget::Ready) {
        for (const QQmlError &error : errors())
            qCritical().noquote() << error.toString();
        qFatal("Qt Quick piano roll QML failed to load");
    }

    QObject *root = rootObject();
    if (!root)
        qFatal("Qt Quick piano roll QML has no root object");

    static constexpr std::array<std::pair<PianoRollQuickLayer, const char *>, 7> layers = {{
        {PianoRollQuickLayer::Grid, "pianoRollQuickGrid"},
        {PianoRollQuickLayer::NoteFills, "pianoRollQuickNoteFills"},
        {PianoRollQuickLayer::DrawPreviewFill, "pianoRollQuickDrawPreviewFill"},
        {PianoRollQuickLayer::NoteBordersAndSelection, "pianoRollQuickNoteBordersAndSelection"},
        {PianoRollQuickLayer::Overlay, "pianoRollQuickOverlay"},
        {PianoRollQuickLayer::KeyboardKeys, "pianoRollQuickKeyboardKeys"},
        {PianoRollQuickLayer::KeyboardHighlights, "pianoRollQuickKeyboardHighlights"},
    }};
    for (const auto &[layer, name] : layers) {
        PianoRollQuickItem *item = root->findChild<PianoRollQuickItem *>(QString::fromLatin1(name));
        if (!item)
            qFatal("Qt Quick piano roll QML has no item '%s' for scene layer %d", name,
                   static_cast<int>(layer));
        if (item->sceneLayer() != layer)
            qFatal("Qt Quick piano roll item '%s' declares scene layer %d, expected %d", name,
                   static_cast<int>(item->sceneLayer()), static_cast<int>(layer));
        item->setScene(m_scene);
        m_items[static_cast<std::size_t>(layer)] = item;
    }

    syncAppearance();
}

void PianoRollQuickView::syncAppearance()
{
    setClearColor(themes::color(themes::Role::song_view_piano_roll_background));
    requestUpdate(PianoRollQuickDirty::All);
}

void PianoRollQuickView::requestUpdate(PianoRollQuickDirtySet dirty)
{
    if (dirty == PianoRollQuickDirty::None)
        return;

    m_pendingDirty |= dirty;
    if (m_flushScheduled)
        return;

    m_flushScheduled = true;
    QMetaObject::invokeMethod(this, [this] { flushUpdate(); }, Qt::QueuedConnection);
}

void PianoRollQuickView::resizeEvent(QResizeEvent *event)
{
    QQuickWidget::resizeEvent(event);
    // Width-only changes re-wrap the plot domains; a height change re-lays
    // out every row. The invalid oldSize of the first resize stays All.
    const bool widthOnly =
        event->oldSize().isValid() && event->oldSize().height() == event->size().height();
    requestUpdate(widthOnly ? cPlotAndLoadingDirty : PianoRollQuickDirty::All);
}

void PianoRollQuickView::flushUpdate()
{
    m_flushScheduled = false;
    const PianoRollQuickDirtySet dirty = std::exchange(m_pendingDirty, PianoRollQuickDirty::None);
    if (dirty == PianoRollQuickDirty::None)
        return;
    synchronize(dirty);
}

} // namespace songview
