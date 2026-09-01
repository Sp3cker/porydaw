#pragma once

#include "core/noteid.h"

#include <QAbstractListModel>
#include <QColor>
#include <QFont>
#include <QHash>
#include <QObject>
#include <QQuickItem>
#include <QRectF>
#include <QString>
#include <QVariant>
#include <array>
#include <compare>
#include <span>
#include <vector>

class SongView;

namespace songview {

class TimelineQuickView;

struct TimelineQuickRect {
    QRectF rect;
    QColor topLeft;
    QColor topRight;
    QColor bottomRight;
    QColor bottomLeft;
};

struct TimelineQuickTriangle {
    QPointF first;
    QPointF second;
    QPointF third;
    QColor firstColor;
    QColor secondColor;
    QColor thirdColor;
};

struct TimelineQuickLayerData {
    std::vector<TimelineQuickRect> rects;
    std::vector<TimelineQuickTriangle> triangles;
    quint64 revision = 0;
};

enum class TimelineQuickTextKeyKind : quint8 {
    PianoNoteName,
    PianoNoteVelocity,
    PianoDrawPreview,
    PianoMidiLabel,
    PianoLoading,
    Ruler,
    OtherEvents,
    VelocityAxis,
    VoiceChanges,
    VoiceChangesHover,
};

struct TimelineQuickTextKey {
    TimelineQuickTextKeyKind kind = TimelineQuickTextKeyKind::PianoNoteName;
    NoteId noteId;
    quint64 ordinal = 0;

    friend constexpr auto operator<=>(const TimelineQuickTextKey &,
                                      const TimelineQuickTextKey &) = default;
};

class TimelineQuickTextModel final : public QAbstractListModel
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(TimelineQuickTextModel)

  public:
    enum Role : int {
        RectRole = Qt::UserRole + 1,
        TextRole,
        ColorRole,
        FontRole,
        HorizontalAlignmentRole,
        VerticalAlignmentRole,
    };

    struct Record {
        TimelineQuickTextKey key;
        QRectF rect;
        QString text;
        QColor color;
        QFont font;
        Qt::Alignment horizontalAlignment = Qt::AlignLeft;
        Qt::Alignment verticalAlignment = Qt::AlignVCenter;
    };

    explicit TimelineQuickTextModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    void setRecords(std::span<const Record> records);

  private:
    struct KeyRowEntry {
        TimelineQuickTextKey key;
        int row = 0;
    };

    std::vector<Record> m_records;
    std::vector<KeyRowEntry> m_targetRows;
    std::vector<KeyRowEntry> m_currentRows;
    QHash<int, QByteArray> m_roleNames;
};

class TimelineQuickItem : public QQuickItem
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(TimelineQuickItem)

  public:
    enum class Layer : quint8 {
        RulerChrome,
        RulerMarks,
        PianoGrid,
        PianoNoteFills,
        PianoDrawPreviewFill,
        PianoNoteBordersAndSelection,
        PianoOverlay,
        PianoKeyboardKeys,
        PianoKeyboardHighlights,
        OtherEventsChrome,
        OtherEventsMarkers,
        VelocityChrome,
        VelocityAxis,
        VelocityGrid,
        VelocityBands,
        VelocityStems,
        VelocityNodes,
        VelocityTransient,
        VoiceChangesChrome,
        VoiceChangesGrid,
        VoiceChangesSpans,
        VoiceChangesMarkers,
        VoiceChangesTransient,
        VoiceChangesHover,
        Count,
    };
    Q_ENUM(Layer)

    Q_PROPERTY(Layer sceneLayer READ sceneLayer WRITE setSceneLayer NOTIFY sceneLayerChanged FINAL)

    explicit TimelineQuickItem(QQuickItem *parent = nullptr);

    Layer sceneLayer() const noexcept;
    void setSceneLayer(Layer layer);
    void setScene(class TimelineQuickScene *scene);

  signals:
    void sceneLayerChanged();

  protected:
    QSGNode *updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *) override;

  private:
    class TimelineQuickScene *m_scene = nullptr;
    Layer m_layer = Layer::RulerChrome;
};

using TimelineQuickLayer = TimelineQuickItem::Layer;

struct TimelineQuickScene final : public QObject {
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(TimelineQuickScene)

    Q_PROPERTY(QAbstractItemModel *pianoNoteTextModel READ pianoNoteTextModel CONSTANT FINAL)
    Q_PROPERTY(QAbstractItemModel *pianoLoadingTextModel READ pianoLoadingTextModel CONSTANT FINAL)
    Q_PROPERTY(
        QAbstractItemModel *pianoKeyboardTextModel READ pianoKeyboardTextModel CONSTANT FINAL)
    Q_PROPERTY(QAbstractItemModel *rulerTextModel READ rulerTextModel CONSTANT FINAL)
    Q_PROPERTY(QAbstractItemModel *otherEventsTextModel READ otherEventsTextModel CONSTANT FINAL)
    Q_PROPERTY(QAbstractItemModel *velocityTextModel READ velocityTextModel CONSTANT FINAL)
    Q_PROPERTY(QAbstractItemModel *voiceChangesTextModel READ voiceChangesTextModel CONSTANT FINAL)
    Q_PROPERTY(QAbstractItemModel *voiceChangesHoverTextModel READ voiceChangesHoverTextModel
                   CONSTANT FINAL)
    Q_PROPERTY(bool hoverChipVisible READ hoverChipVisible NOTIFY hoverChipChanged FINAL)
    Q_PROPERTY(QRectF hoverChipRect READ hoverChipRect NOTIFY hoverChipChanged FINAL)
    Q_PROPERTY(QString hoverChipText READ hoverChipText NOTIFY hoverChipChanged FINAL)
    Q_PROPERTY(QColor hoverChipFill READ hoverChipFill NOTIFY hoverChipChanged FINAL)
    Q_PROPERTY(QFont hoverChipFont READ hoverChipFont NOTIFY hoverChipChanged FINAL)
    Q_PROPERTY(qreal hoverChipRadius READ hoverChipRadius NOTIFY hoverChipChanged FINAL)

  public:
    explicit TimelineQuickScene(QObject *parent = nullptr);

    QAbstractItemModel *pianoNoteTextModel() const noexcept;
    QAbstractItemModel *pianoLoadingTextModel() const noexcept;
    QAbstractItemModel *pianoKeyboardTextModel() const noexcept;
    QAbstractItemModel *rulerTextModel() const noexcept;
    QAbstractItemModel *otherEventsTextModel() const noexcept;
    QAbstractItemModel *velocityTextModel() const noexcept;
    QAbstractItemModel *voiceChangesTextModel() const noexcept;
    QAbstractItemModel *voiceChangesHoverTextModel() const noexcept;
    void setRulerTextRecords(std::span<const TimelineQuickTextModel::Record> records);
    void setOtherEventsTextRecords(std::span<const TimelineQuickTextModel::Record> records);
    void setVelocityTextRecords(std::span<const TimelineQuickTextModel::Record> records);
    void setVoiceChangesTextRecords(std::span<const TimelineQuickTextModel::Record> records);
    void setVoiceChangesHoverTextRecords(std::span<const TimelineQuickTextModel::Record> records);

    const TimelineQuickLayerData &layer(TimelineQuickLayer layer) const noexcept;
    TimelineQuickLayerData &layer(TimelineQuickLayer layer) noexcept;

    bool hoverChipVisible() const noexcept;
    QRectF hoverChipRect() const noexcept;
    QString hoverChipText() const;
    QColor hoverChipFill() const;
    QFont hoverChipFont() const;
    qreal hoverChipRadius() const noexcept;

    void setHoverChip(bool visible, const QRectF &rect, const QString &text, const QColor &fill,
                      const QFont &font, qreal radius);

  signals:
    void hoverChipChanged();

  private:
    friend class TimelineQuickView;
    std::array<TimelineQuickLayerData, static_cast<std::size_t>(TimelineQuickLayer::Count)>
        m_layers{};
    TimelineQuickTextModel *m_pianoNoteTextModel = nullptr;
    TimelineQuickTextModel *m_pianoLoadingTextModel = nullptr;
    TimelineQuickTextModel *m_pianoKeyboardTextModel = nullptr;
    TimelineQuickTextModel *m_rulerTextModel = nullptr;
    TimelineQuickTextModel *m_otherEventsTextModel = nullptr;
    TimelineQuickTextModel *m_velocityTextModel = nullptr;
    TimelineQuickTextModel *m_voiceChangesTextModel = nullptr;
    TimelineQuickTextModel *m_voiceChangesHoverTextModel = nullptr;

    bool m_hoverChipVisible = false;
    QRectF m_hoverChipRect;
    QString m_hoverChipText;
    QColor m_hoverChipFill;
    QFont m_hoverChipFont;
    qreal m_hoverChipRadius = 0.0;
};

namespace timeline_quick {

void resetLayer(TimelineQuickScene &scene, TimelineQuickLayer layer);
void addRect(TimelineQuickScene &scene, TimelineQuickLayer layer, const QRectF &rect,
             const QColor &color, const QRectF &clip);
void addHorizontalGradient(TimelineQuickScene &scene, TimelineQuickLayer layer, const QRectF &rect,
                           const QColor &left, const QColor &right, const QRectF &clip);
void addHorizontalLine(TimelineQuickScene &scene, TimelineQuickLayer layer, qreal x0, qreal x1,
                       qreal y, qreal width, const QColor &color, const QRectF &clip);
void addVerticalLine(TimelineQuickScene &scene, TimelineQuickLayer layer, qreal x, qreal y0,
                     qreal y1, qreal width, const QColor &color, const QRectF &clip);
void composeBandedGrid(TimelineQuickScene &scene, TimelineQuickLayer layer, const ::SongView &owner,
                       const QRectF &plot, int origin, qreal dpr);
void addDashedVertical(TimelineQuickScene &scene, TimelineQuickLayer layer, qreal x, qreal y0,
                       qreal y1, qreal width, qreal dash, qreal gap, const QColor &color,
                       const QRectF &clip);
void addClippedTriangle(TimelineQuickScene &scene, TimelineQuickLayer layer, const QPointF &first,
                        const QPointF &second, const QPointF &third, const QColor &color,
                        const QRectF &clip);
void addLine(TimelineQuickScene &scene, TimelineQuickLayer layer, const QPointF &from,
             const QPointF &to, qreal width, const QColor &color, const QRectF &clip);
void addEllipse(TimelineQuickScene &scene, TimelineQuickLayer layer, const QPointF &center,
                qreal radiusX, qreal radiusY, const QColor &color, const QRectF &clip);
void addEllipseRing(TimelineQuickScene &scene, TimelineQuickLayer layer, const QPointF &center,
                    qreal radiusX, qreal radiusY, qreal width, const QColor &color,
                    const QRectF &clip);

} // namespace timeline_quick

} // namespace songview
