#include "ui/songview/quick/timelinequickscene.h"

#include <QList>
#include <QSGGeometry>
#include <QSGGeometryNode>
#include <QSGVertexColorMaterial>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <numbers>

#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/detail.h"
#include "ui/theme/themeruntime.h"

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
    if (oldRecord.clipRect != newRecord.clipRect)
        roles |= 1 << 6;
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
    if (mask & (1 << 6))
        roles.append(TimelineQuickTextModel::ClipRectRole);
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
    m_roleNames.insert(ClipRectRole, QByteArrayLiteral("labelClipRect"));
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
    case ClipRectRole:
        return record.clipRect;
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
    m_velocityTextModel = new TimelineQuickTextModel(this);
    m_voiceChangesTextModel = new TimelineQuickTextModel(this);
    m_voiceChangesHoverTextModel = new TimelineQuickTextModel(this);
    m_automationTextModel = new TimelineQuickTextModel(this);
    m_automationHoverTextModel = new TimelineQuickTextModel(this);
    m_automationTransientTextModel = new TimelineQuickTextModel(this);
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

QAbstractItemModel *TimelineQuickScene::velocityTextModel() const noexcept
{
    return m_velocityTextModel;
}

QAbstractItemModel *TimelineQuickScene::voiceChangesTextModel() const noexcept
{
    return m_voiceChangesTextModel;
}

QAbstractItemModel *TimelineQuickScene::voiceChangesHoverTextModel() const noexcept
{
    return m_voiceChangesHoverTextModel;
}

QAbstractItemModel *TimelineQuickScene::automationTextModel() const noexcept
{
    return m_automationTextModel;
}

QAbstractItemModel *TimelineQuickScene::automationHoverTextModel() const noexcept
{
    return m_automationHoverTextModel;
}

QAbstractItemModel *TimelineQuickScene::automationTransientTextModel() const noexcept
{
    return m_automationTransientTextModel;
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

void TimelineQuickScene::setVelocityTextRecords(
    std::span<const TimelineQuickTextModel::Record> records)
{
    m_velocityTextModel->setRecords(records);
}

void TimelineQuickScene::setVoiceChangesTextRecords(
    std::span<const TimelineQuickTextModel::Record> records)
{
    m_voiceChangesTextModel->setRecords(records);
}

void TimelineQuickScene::setVoiceChangesHoverTextRecords(
    std::span<const TimelineQuickTextModel::Record> records)
{
    m_voiceChangesHoverTextModel->setRecords(records);
}

void TimelineQuickScene::setAutomationTextRecords(
    std::span<const TimelineQuickTextModel::Record> records)
{
    m_automationTextModel->setRecords(records);
}

void TimelineQuickScene::setAutomationHoverTextRecords(
    std::span<const TimelineQuickTextModel::Record> records)
{
    m_automationHoverTextModel->setRecords(records);
}

void TimelineQuickScene::setAutomationTransientTextRecords(
    std::span<const TimelineQuickTextModel::Record> records)
{
    m_automationTransientTextModel->setRecords(records);
}

const TimelineQuickLayerData &TimelineQuickScene::layer(TimelineQuickLayer layer) const noexcept
{
    return m_layers[static_cast<std::size_t>(layer)];
}

TimelineQuickLayerData &TimelineQuickScene::layer(TimelineQuickLayer layer) noexcept
{
    return m_layers[static_cast<std::size_t>(layer)];
}

namespace timeline_quick {

namespace {

constexpr int kEllipseSegments = 24;
constexpr int kSelectionFillAlpha = 30;
constexpr qreal kSelectionDashMultiplier = 4.0;
constexpr qreal kSelectionGapMultiplier = 2.0;

struct ClippedPolygon {
    std::array<QPointF, 8> points;
    int size = 0;
};

enum class ClipEdge {
    Left,
    Right,
    Top,
    Bottom,
};

ClippedPolygon clipToEdge(const ClippedPolygon &input, const QRectF &clip, ClipEdge edge)
{
    ClippedPolygon output;
    if (input.size == 0)
        return output;
    const auto coordinate = [edge](const QPointF &point) {
        return edge == ClipEdge::Left || edge == ClipEdge::Right ? point.x() : point.y();
    };
    const qreal boundary = edge == ClipEdge::Left    ? clip.left()
                           : edge == ClipEdge::Right ? clip.right()
                           : edge == ClipEdge::Top   ? clip.top()
                                                     : clip.bottom();
    const bool keepGreater = edge == ClipEdge::Left || edge == ClipEdge::Top;
    const auto inside = [coordinate, boundary, keepGreater](const QPointF &point) {
        return keepGreater ? coordinate(point) >= boundary : coordinate(point) <= boundary;
    };
    QPointF previous = input.points[static_cast<std::size_t>(input.size - 1)];
    bool previousInside = inside(previous);
    for (int index = 0; index < input.size; ++index) {
        const QPointF current = input.points[static_cast<std::size_t>(index)];
        const bool currentInside = inside(current);
        if (currentInside != previousInside) {
            const qreal from = coordinate(previous);
            const qreal to = coordinate(current);
            const qreal fraction = (boundary - from) / (to - from);
            output.points[static_cast<std::size_t>(output.size++)] =
                previous + (current - previous) * fraction;
        }
        if (currentInside)
            output.points[static_cast<std::size_t>(output.size++)] = current;
        previous = current;
        previousInside = currentInside;
    }
    return output;
}

} // namespace

void resetLayer(TimelineQuickScene &scene, TimelineQuickLayer layer)
{
    TimelineQuickLayerData &data = scene.layer(layer);
    data.rects.clear();
    data.triangles.clear();
    ++data.revision;
}

void addRect(TimelineQuickScene &scene, TimelineQuickLayer layer, const QRectF &rect,
             const QColor &color, const QRectF &clip)
{
    const QRectF clipped = rect.normalized().intersected(clip);
    if (clipped.width() <= 0.0 || clipped.height() <= 0.0)
        return;
    scene.layer(layer).rects.push_back({clipped, color, color, color, color});
}

void addHorizontalGradient(TimelineQuickScene &scene, TimelineQuickLayer layer, const QRectF &rect,
                           const QColor &left, const QColor &right, const QRectF &clip)
{
    const QRectF source = rect.normalized();
    const QRectF clipped = source.intersected(clip.normalized());
    if (clipped.width() <= 0.0 || clipped.height() <= 0.0)
        return;
    const qreal fullWidth = source.width();
    const auto interpolationAt = [source, fullWidth](qreal x) {
        const qreal interpolation = (x - source.left()) / fullWidth;
        return (std::min)(1.0, (std::max)(0.0, interpolation));
    };
    const auto mix = [](const QColor &a, const QColor &b, qreal t) {
        return QColor::fromRgbF(
            a.redF() + (b.redF() - a.redF()) * t, a.greenF() + (b.greenF() - a.greenF()) * t,
            a.blueF() + (b.blueF() - a.blueF()) * t, a.alphaF() + (b.alphaF() - a.alphaF()) * t);
    };
    const QColor clippedLeft = mix(left, right, interpolationAt(clipped.left()));
    const QColor clippedRight = mix(left, right, interpolationAt(clipped.right()));
    scene.layer(layer).rects.push_back(
        {clipped, clippedLeft, clippedRight, clippedRight, clippedLeft});
}

void addHorizontalLine(TimelineQuickScene &scene, TimelineQuickLayer layer, qreal x0, qreal x1,
                       qreal y, qreal width, const QColor &color, const QRectF &clip)
{
    addRect(scene, layer, QRectF(x0, y - width / 2.0, x1 - x0, width), color, clip);
}

void addVerticalLine(TimelineQuickScene &scene, TimelineQuickLayer layer, qreal x, qreal y0,
                     qreal y1, qreal width, const QColor &color, const QRectF &clip)
{
    addRect(scene, layer, QRectF(x - width / 2.0, y0, width, y1 - y0), color, clip);
}

void composeBandedGrid(TimelineQuickScene &scene, TimelineQuickLayer layer, const ::SongView &owner,
                       const QRectF &plot, int origin, qreal dpr)
{
    const qreal physicalPixel = detail::logicalPhysicalPixel(dpr);
    const qreal roundingMargin = physicalPixel / 2.0;
    const double t0 =
        std::max(0.0, owner.tickAtContentX(plot.left() - qreal(origin) - roundingMargin));
    const double t1 =
        owner.tickAtContentX(plot.right() - physicalPixel - qreal(origin) + roundingMargin) + 1.0;
    if (!std::isfinite(t0) || !std::isfinite(t1) || t1 <= t0)
        return;
    const std::array<QColor, 6> gridColors = {
        detail::gridLineColor(125), detail::gridLineColor(100), detail::gridLineColor(75),
        detail::gridLineColor(160), detail::gridLineColor(200), detail::gridLineColor()};
    const int detailMinimumPixelsPerBeat = ::layout::fontPx(5.0 / 6.0);
    const qreal gridWidth = ::layout::fontPx(1.0 / 6.0) * physicalPixel;
    detail::forEachSubGridLine(
        &owner, t0, t1, detailMinimumPixelsPerBeat, [&](uint64_t tick, int level) {
            const qreal x = owner.displayX(double(tick), origin, dpr);
            addVerticalLine(scene, layer, x, plot.top(), plot.bottom(), gridWidth,
                            gridColors[std::size_t(level - 1)], plot);
        });
    const bool drawBeats = owner.pxPerBeat() >= detailMinimumPixelsPerBeat;
    owner.forEachGridLine(uint64_t(t0), uint64_t(t1), [&](uint64_t tick, bool isBar, int, int) {
        if (!isBar && !drawBeats)
            return;
        const bool finest = owner.document() && owner.gridTicksAt(tick) == owner.fineGridTicks();
        const std::size_t color = isBar ? 5u : finest ? 4u : 3u;
        const qreal x = owner.displayX(double(tick), origin, dpr);
        addVerticalLine(scene, layer, x, plot.top(), plot.bottom(), gridWidth, gridColors[color],
                        plot);
    });
}

void addDashedVertical(TimelineQuickScene &scene, TimelineQuickLayer layer, qreal x, qreal y0,
                       qreal y1, qreal width, qreal dash, qreal gap, const QColor &color,
                       const QRectF &clip)
{
    for (qreal y = y0; y < y1; y += dash + gap)
        addVerticalLine(scene, layer, x, y, (std::min)(y + dash, y1), width, color, clip);
}

void addDashedHorizontal(TimelineQuickScene &scene, TimelineQuickLayer layer, qreal x0, qreal x1,
                         qreal y, qreal width, qreal dash, qreal gap, const QColor &color,
                         const QRectF &clip)
{
    for (qreal x = x0; x < x1; x += dash + gap)
        addHorizontalLine(scene, layer, x, std::min(x + dash, x1), y, width, color, clip);
}

void addSelectionReticle(TimelineQuickScene &scene, TimelineQuickLayer layer, const QRectF &rect,
                         const QRectF &clip)
{
    QColor fill = themes::color(themes::Role::song_view_selection_fill);
    fill.setAlpha(kSelectionFillAlpha);
    addRect(scene, layer, rect, fill, clip);
    const QColor edge = themes::color(themes::Role::song_view_selection_edge);
    const qreal width = ::layout::singlePixel();
    const qreal dash = kSelectionDashMultiplier * width;
    const qreal gap = kSelectionGapMultiplier * width;
    addDashedHorizontal(scene, layer, rect.left(), rect.right(), rect.top(), width, dash, gap, edge,
                        clip);
    addDashedHorizontal(scene, layer, rect.left(), rect.right(), rect.bottom(), width, dash, gap,
                        edge, clip);
    addDashedVertical(scene, layer, rect.left(), rect.top(), rect.bottom(), width, dash, gap, edge,
                      clip);
    addDashedVertical(scene, layer, rect.right(), rect.top(), rect.bottom(), width, dash, gap, edge,
                      clip);
}

void addClippedTriangle(TimelineQuickScene &scene, TimelineQuickLayer layer, const QPointF &first,
                        const QPointF &second, const QPointF &third, const QColor &color,
                        const QRectF &clip)
{
    ClippedPolygon polygon{{first, second, third}, 3};
    polygon = clipToEdge(polygon, clip, ClipEdge::Left);
    polygon = clipToEdge(polygon, clip, ClipEdge::Right);
    polygon = clipToEdge(polygon, clip, ClipEdge::Top);
    polygon = clipToEdge(polygon, clip, ClipEdge::Bottom);
    TimelineQuickLayerData &data = scene.layer(layer);
    for (int index = 1; index + 1 < polygon.size; ++index) {
        data.triangles.push_back(
            {polygon.points[0], polygon.points[static_cast<std::size_t>(index)],
             polygon.points[static_cast<std::size_t>(index + 1)], color, color, color});
    }
}

void addLine(TimelineQuickScene &scene, TimelineQuickLayer layer, const QPointF &from,
             const QPointF &to, qreal width, const QColor &color, const QRectF &clip)
{
    const QPointF delta = to - from;
    const qreal length = std::hypot(delta.x(), delta.y());
    if (length == 0.0)
        return;
    const QPointF normal(-delta.y() * width / (2.0 * length), delta.x() * width / (2.0 * length));
    addClippedTriangle(scene, layer, from + normal, to + normal, to - normal, color, clip);
    addClippedTriangle(scene, layer, from + normal, to - normal, from - normal, color, clip);
}

void addEllipse(TimelineQuickScene &scene, TimelineQuickLayer layer, const QPointF &center,
                qreal radiusX, qreal radiusY, const QColor &color, const QRectF &clip)
{
    for (int index = 0; index < kEllipseSegments; ++index) {
        const qreal firstAngle =
            2.0 * std::numbers::pi_v<qreal> * qreal(index) / qreal(kEllipseSegments);
        const qreal secondAngle =
            2.0 * std::numbers::pi_v<qreal> * qreal(index + 1) / qreal(kEllipseSegments);
        const QPointF first(center.x() + radiusX * std::cos(firstAngle),
                            center.y() + radiusY * std::sin(firstAngle));
        const QPointF second(center.x() + radiusX * std::cos(secondAngle),
                             center.y() + radiusY * std::sin(secondAngle));
        addClippedTriangle(scene, layer, center, first, second, color, clip);
    }
}

void addEllipseRing(TimelineQuickScene &scene, TimelineQuickLayer layer, const QPointF &center,
                    qreal radiusX, qreal radiusY, qreal width, const QColor &color,
                    const QRectF &clip)
{
    const qreal outerX = radiusX + width / 2.0;
    const qreal outerY = radiusY + width / 2.0;
    const qreal innerX = std::max<qreal>(0.0, radiusX - width / 2.0);
    const qreal innerY = std::max<qreal>(0.0, radiusY - width / 2.0);
    for (int index = 0; index < kEllipseSegments; ++index) {
        const qreal firstAngle =
            2.0 * std::numbers::pi_v<qreal> * qreal(index) / qreal(kEllipseSegments);
        const qreal secondAngle =
            2.0 * std::numbers::pi_v<qreal> * qreal(index + 1) / qreal(kEllipseSegments);
        const QPointF outerFirst(center.x() + outerX * std::cos(firstAngle),
                                 center.y() + outerY * std::sin(firstAngle));
        const QPointF outerSecond(center.x() + outerX * std::cos(secondAngle),
                                  center.y() + outerY * std::sin(secondAngle));
        const QPointF innerFirst(center.x() + innerX * std::cos(firstAngle),
                                 center.y() + innerY * std::sin(firstAngle));
        const QPointF innerSecond(center.x() + innerX * std::cos(secondAngle),
                                  center.y() + innerY * std::sin(secondAngle));
        addClippedTriangle(scene, layer, outerFirst, outerSecond, innerSecond, color, clip);
        addClippedTriangle(scene, layer, outerFirst, innerSecond, innerFirst, color, clip);
    }
}

} // namespace timeline_quick

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
