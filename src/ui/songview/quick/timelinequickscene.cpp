#include "ui/songview/quick/timelinequickscene.h"

#include <QList>
#include <QSGGeometry>
#include <QSGGeometryNode>
#include <QSGVertexColorMaterial>

#include <algorithm>
#include <cstddef>

namespace songview {
namespace {

constexpr int cVerticesPerChunk = 1536;

class TimelineQuickGeometryChunkNode final : public QSGGeometryNode
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

class TimelineQuickLayerNode final : public QSGNode
{
  public:
    const TimelineQuickScene *builtScene = nullptr;
    TimelineQuickLayer builtLayer = TimelineQuickLayer::Count;
    quint64 builtRevision = 0;
};

TimelineQuickGeometryChunkNode *newGeometryChunk()
{
    auto *node = new TimelineQuickGeometryChunkNode;
    auto *geometry =
        new QSGGeometry(QSGGeometry::defaultAttributes_ColoredPoint2D(), cVerticesPerChunk);
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
    for (int vertex = usedVertices; vertex < cVerticesPerChunk; ++vertex)
        vertices[vertex].set(0.0f, 0.0f, 0, 0, 0, 0);
}

void blockChunks(QSGNode *chunk)
{
    while (chunk) {
        auto *geometryChunk = static_cast<TimelineQuickGeometryChunkNode *>(chunk);
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

void writeRect(QSGGeometry::ColoredPoint2D *&vertices, const TimelineQuickRect &primitive)
{
    const QRectF rect = primitive.rect.normalized();
    setVertex(*vertices++, rect.topLeft(), primitive.topLeft);
    setVertex(*vertices++, rect.bottomLeft(), primitive.bottomLeft);
    setVertex(*vertices++, rect.topRight(), primitive.topRight);
    setVertex(*vertices++, rect.topRight(), primitive.topRight);
    setVertex(*vertices++, rect.bottomLeft(), primitive.bottomLeft);
    setVertex(*vertices++, rect.bottomRight(), primitive.bottomRight);
}

void writeTriangle(QSGGeometry::ColoredPoint2D *&vertices, const TimelineQuickTriangle &primitive)
{
    setVertex(*vertices++, primitive.first, primitive.firstColor);
    setVertex(*vertices++, primitive.second, primitive.secondColor);
    setVertex(*vertices++, primitive.third, primitive.thirdColor);
}

int changedRoles(const TimelineQuickTextModel::Record &oldRecord,
                 const TimelineQuickTextModel::Record &newRecord)
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
        roles.append(TimelineQuickTextModel::RectRole);
    if (mask & (1 << 1))
        roles.append(TimelineQuickTextModel::TextRole);
    if (mask & (1 << 2))
        roles.append(TimelineQuickTextModel::ColorRole);
    if (mask & (1 << 3))
        roles.append(TimelineQuickTextModel::FontRole);
    if (mask & (1 << 4))
        roles.append(TimelineQuickTextModel::HorizontalAlignmentRole);
    if (mask & (1 << 5))
        roles.append(TimelineQuickTextModel::VerticalAlignmentRole);
    return roles;
}

} // namespace

TimelineQuickTextModel::TimelineQuickTextModel(QObject *parent) : QAbstractListModel(parent)
{
    m_roleNames.insert(RectRole, QByteArrayLiteral("labelRect"));
    m_roleNames.insert(TextRole, QByteArrayLiteral("labelText"));
    m_roleNames.insert(ColorRole, QByteArrayLiteral("labelColor"));
    m_roleNames.insert(FontRole, QByteArrayLiteral("labelFont"));
    m_roleNames.insert(HorizontalAlignmentRole, QByteArrayLiteral("labelHorizontalAlignment"));
    m_roleNames.insert(VerticalAlignmentRole, QByteArrayLiteral("labelVerticalAlignment"));
}

int TimelineQuickTextModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid())
        return 0;
    return static_cast<int>(m_records.size());
}

QVariant TimelineQuickTextModel::data(const QModelIndex &index, int role) const
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

QHash<int, QByteArray> TimelineQuickTextModel::roleNames() const
{
    return m_roleNames;
}

void TimelineQuickTextModel::setRecords(std::span<const Record> records)
{
    const auto keyFirst = [](const KeyRowEntry &entry, const TimelineQuickTextKey &key) {
        return entry.key < key;
    };
    const auto byKey = [](const KeyRowEntry &left, const KeyRowEntry &right) {
        return left.key < right.key;
    };
    const auto rowFor = [&keyFirst](std::vector<KeyRowEntry> &index,
                                    const TimelineQuickTextKey &key) -> int * {
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
            if (rowFor(m_currentRows, record.key) == nullptr)
                m_records.push_back(record);
        }
        endInsertRows();

        m_currentRows.clear();
        for (int row = 0; row < static_cast<int>(m_records.size()); ++row)
            m_currentRows.push_back({m_records[static_cast<std::size_t>(row)].key, row});
        std::sort(m_currentRows.begin(), m_currentRows.end(), byKey);
    }

    for (int target = 0; target < static_cast<int>(records.size()); ++target) {
        const TimelineQuickTextKey &key = records[static_cast<std::size_t>(target)].key;
        const int source = *rowFor(m_currentRows, key);
        if (source == target)
            continue;
        beginMoveRows(QModelIndex(), source, source, QModelIndex(), target);
        for (int row = target; row < source; ++row)
            ++*rowFor(m_currentRows, m_records[static_cast<std::size_t>(row)].key);
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

TimelineQuickScene::TimelineQuickScene(QObject *parent) : QObject(parent)
{
    m_pianoNoteTextModel = new TimelineQuickTextModel(this);
    m_pianoLoadingTextModel = new TimelineQuickTextModel(this);
    m_pianoKeyboardTextModel = new TimelineQuickTextModel(this);
    m_rulerTextModel = new TimelineQuickTextModel(this);
    m_otherEventsTextModel = new TimelineQuickTextModel(this);
}

QAbstractItemModel *TimelineQuickScene::pianoNoteTextModel() const noexcept
{
    return m_pianoNoteTextModel;
}

QAbstractItemModel *TimelineQuickScene::pianoLoadingTextModel() const noexcept
{
    return m_pianoLoadingTextModel;
}

QAbstractItemModel *TimelineQuickScene::pianoKeyboardTextModel() const noexcept
{
    return m_pianoKeyboardTextModel;
}

QAbstractItemModel *TimelineQuickScene::rulerTextModel() const noexcept
{
    return m_rulerTextModel;
}

QAbstractItemModel *TimelineQuickScene::otherEventsTextModel() const noexcept
{
    return m_otherEventsTextModel;
}

void TimelineQuickScene::setRulerTextRecords(
    std::span<const TimelineQuickTextModel::Record> records)
{
    m_rulerTextModel->setRecords(records);
}

void TimelineQuickScene::setOtherEventsTextRecords(
    std::span<const TimelineQuickTextModel::Record> records)
{
    m_otherEventsTextModel->setRecords(records);
}

const TimelineQuickLayerData &TimelineQuickScene::layer(TimelineQuickLayer layer) const noexcept
{
    return m_layers[static_cast<std::size_t>(layer)];
}

TimelineQuickLayerData &TimelineQuickScene::layer(TimelineQuickLayer layer) noexcept
{
    return m_layers[static_cast<std::size_t>(layer)];
}

bool TimelineQuickScene::hoverChipVisible() const noexcept
{
    return m_hoverChipVisible;
}

QRectF TimelineQuickScene::hoverChipRect() const noexcept
{
    return m_hoverChipRect;
}

QString TimelineQuickScene::hoverChipText() const
{
    return m_hoverChipText;
}

QColor TimelineQuickScene::hoverChipFill() const
{
    return m_hoverChipFill;
}

QFont TimelineQuickScene::hoverChipFont() const
{
    return m_hoverChipFont;
}

qreal TimelineQuickScene::hoverChipRadius() const noexcept
{
    return m_hoverChipRadius;
}

void TimelineQuickScene::setHoverChip(bool visible, const QRectF &rect, const QString &text,
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

TimelineQuickItem::TimelineQuickItem(QQuickItem *parent) : QQuickItem(parent)
{
    setFlag(ItemHasContents, true);
}

TimelineQuickLayer TimelineQuickItem::sceneLayer() const noexcept
{
    return m_layer;
}

void TimelineQuickItem::setSceneLayer(TimelineQuickLayer layer)
{
    if (layer >= TimelineQuickLayer::Count) {
        qWarning().noquote() << "Qt Quick timeline item rejected invalid scene layer"
                             << static_cast<int>(layer);
        return;
    }
    if (layer == m_layer)
        return;
    m_layer = layer;
    emit sceneLayerChanged();
    update();
}

void TimelineQuickItem::setScene(TimelineQuickScene *scene)
{
    if (m_scene == scene)
        return;
    m_scene = scene;
    update();
}

QSGNode *TimelineQuickItem::updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *)
{
    const TimelineQuickScene *scene = m_scene;
    const TimelineQuickLayer layerIndex = m_layer;
    const TimelineQuickLayerData *layer = scene ? &scene->layer(layerIndex) : nullptr;
    auto *node = static_cast<TimelineQuickLayerNode *>(oldNode);
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
        node = new TimelineQuickLayerNode;

    QSGNode *child = node->firstChild();
    std::size_t rect = 0;
    std::size_t triangle = 0;
    while (rect < layer->rects.size() || triangle < layer->triangles.size()) {
        if (!child) {
            auto *newChunk = newGeometryChunk();
            node->appendChildNode(newChunk);
            child = newChunk;
        }
        auto *chunk = static_cast<TimelineQuickGeometryChunkNode *>(child);
        child = child->nextSibling();
        chunk->setBlocked(false);

        QSGGeometry *geometry = chunk->geometry();
        auto *nextVertex = geometry->vertexDataAsColoredPoint2D();
        int usedVertices = 0;
        while (rect < layer->rects.size() && usedVertices + 6 <= cVerticesPerChunk) {
            writeRect(nextVertex, layer->rects[rect++]);
            usedVertices += 6;
        }
        while (triangle < layer->triangles.size() && usedVertices + 3 <= cVerticesPerChunk) {
            writeTriangle(nextVertex, layer->triangles[triangle++]);
            usedVertices += 3;
        }
        clearUnusedVertices(geometry->vertexDataAsColoredPoint2D(), usedVertices);
        geometry->markVertexDataDirty();
        chunk->markDirty(QSGNode::DirtyGeometry);
    }
    blockChunks(child);

    node->builtScene = scene;
    node->builtLayer = layerIndex;
    node->builtRevision = layer->revision;
    return node;
}

} // namespace songview
