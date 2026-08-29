#pragma once

#include "core/noteid.h"

#include <QAbstractListModel>
#include <QColor>
#include <QFont>
#include <QHash>
#include <QObject>
#include <QQuickItem>
#include <QQuickWidget>
#include <QRectF>
#include <QString>
#include <QVariant>
#include <array>
#include <compare>
#include <span>
#include <vector>

namespace songview {

class PianoRoll;
struct PianoRollQuickScene;

enum class PianoRollQuickDirty : quint32 {
    None = 0,
    Grid = 1u << 0,
    NoteFills = 1u << 1,
    DrawPreviewFill = 1u << 2,
    NoteBordersAndSelection = 1u << 3,
    Overlay = 1u << 4,
    KeyboardKeys = 1u << 5,
    KeyboardHighlights = 1u << 6,
    NoteText = 1u << 7,
    LoadingText = 1u << 8,
    KeyboardText = 1u << 9,
    HoverChip = 1u << 10,
    All = (1u << 11) - 1,
};
Q_DECLARE_FLAGS(PianoRollQuickDirtySet, PianoRollQuickDirty)
Q_DECLARE_OPERATORS_FOR_FLAGS(PianoRollQuickDirtySet)
// The plot layers: everything the roll paints from the timeline, the
// projection, and the x camera. The keyboard layers, hover chip, and text
// models read vertical geometry, projection, hover state, and fonts, never
// the x camera, so a horizontal camera change dirties exactly this.
inline constexpr PianoRollQuickDirtySet cPlotDirty =
    PianoRollQuickDirty::Grid | PianoRollQuickDirty::NoteFills |
    PianoRollQuickDirty::DrawPreviewFill | PianoRollQuickDirty::NoteBordersAndSelection |
    PianoRollQuickDirty::Overlay | PianoRollQuickDirty::NoteText;
// The plot layers plus the text models, whose records wrap to the roll
// width: exactly what a width-only resize changes, and the generic
// document/model replacement union for an unclassified updateSong handoff.
inline constexpr PianoRollQuickDirtySet cPlotAndLoadingDirty =
    cPlotDirty | PianoRollQuickDirty::LoadingText;
// A committed note mutation (move/resize/draw) changes a note's fill, its
// border/selection ring, and its label; nothing else reads note geometry.
inline constexpr PianoRollQuickDirtySet cNoteMutationDirty =
    PianoRollQuickDirty::NoteFills | PianoRollQuickDirty::NoteBordersAndSelection |
    PianoRollQuickDirty::NoteText;
// A velocity change (preview or commit) re-tints fills and labels; borders
// and selection rings are velocity-independent.
inline constexpr PianoRollQuickDirtySet cVelocityMutationDirty =
    PianoRollQuickDirty::NoteFills | PianoRollQuickDirty::NoteText;
// A draw-drag commit: the new note mutates, and clearing drag state removes
// the preview fill it replaced and the drag's overlay band.
inline constexpr PianoRollQuickDirtySet cDrawCommitDirty =
    cNoteMutationDirty | PianoRollQuickDirty::DrawPreviewFill | PianoRollQuickDirty::Overlay;

struct PianoRollQuickRect {
    QRectF rect;
    QColor topLeft;
    QColor topRight;
    QColor bottomRight;
    QColor bottomLeft;
};

struct PianoRollQuickLayerData {
    std::vector<PianoRollQuickRect> rects;
    quint64 revision = 0;
};

// Identity of one text-model row. The label kind, the complete NoteId, and a
// full-width fallback ordinal stay separate comparable fields, so records
// never collide: differing kinds, note tokens, or ordinals compare unequal.
enum class PianoRollQuickTextKeyKind : quint8 {
    NoteName,
    NoteVelocity,
    DrawPreview,
    MidiLabel,
    Loading,
};

struct PianoRollQuickTextKey {
    PianoRollQuickTextKeyKind kind = PianoRollQuickTextKeyKind::NoteName;
    NoteId noteId;
    quint64 ordinal = 0;

    friend constexpr auto operator<=>(const PianoRollQuickTextKey &,
                                      const PianoRollQuickTextKey &) = default;
};

class PianoRollQuickTextModel final : public QAbstractListModel
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(PianoRollQuickTextModel)

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
        PianoRollQuickTextKey key;
        QRectF rect;
        QString text;
        QColor color;
        QFont font;
        Qt::Alignment horizontalAlignment = Qt::AlignLeft;
        Qt::Alignment verticalAlignment = Qt::AlignVCenter;
    };

    explicit PianoRollQuickTextModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    void setRecords(std::span<const Record> records);

  private:
    struct KeyRowEntry {
        PianoRollQuickTextKey key;
        int row = 0;
    };

    std::vector<Record> m_records;
    // Sorted key->row scratch for setRecords(); cleared per call, capacity reused.
    std::vector<KeyRowEntry> m_targetRows;
    std::vector<KeyRowEntry> m_currentRows;
    QHash<int, QByteArray> m_roleNames;
};

class PianoRollQuickItem : public QQuickItem
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(PianoRollQuickItem)

  public:
    enum class Layer : quint8 {
        Grid,
        NoteFills,
        DrawPreviewFill,
        NoteBordersAndSelection,
        Overlay,
        KeyboardKeys,
        KeyboardHighlights,
        Count,
    };
    Q_ENUM(Layer)

    Q_PROPERTY(Layer sceneLayer READ sceneLayer WRITE setSceneLayer NOTIFY sceneLayerChanged FINAL)

    explicit PianoRollQuickItem(QQuickItem *parent = nullptr);

    Layer sceneLayer() const noexcept;
    void setSceneLayer(Layer layer);
    void setScene(PianoRollQuickScene *scene);

  signals:
    void sceneLayerChanged();

  protected:
    QSGNode *updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *) override;

  private:
    PianoRollQuickScene *m_scene = nullptr;
    Layer m_layer = Layer::Grid;
};

using PianoRollQuickLayer = PianoRollQuickItem::Layer;

struct PianoRollQuickScene final : public QObject {
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(PianoRollQuickScene)

    Q_PROPERTY(QAbstractItemModel *noteTextModel READ noteTextModel CONSTANT FINAL)
    Q_PROPERTY(QAbstractItemModel *loadingTextModel READ loadingTextModel CONSTANT FINAL)
    Q_PROPERTY(QAbstractItemModel *keyboardTextModel READ keyboardTextModel CONSTANT FINAL)
    Q_PROPERTY(bool hoverChipVisible READ hoverChipVisible NOTIFY hoverChipChanged FINAL)
    Q_PROPERTY(QRectF hoverChipRect READ hoverChipRect NOTIFY hoverChipChanged FINAL)
    Q_PROPERTY(QString hoverChipText READ hoverChipText NOTIFY hoverChipChanged FINAL)
    Q_PROPERTY(QColor hoverChipFill READ hoverChipFill NOTIFY hoverChipChanged FINAL)
    Q_PROPERTY(QFont hoverChipFont READ hoverChipFont NOTIFY hoverChipChanged FINAL)
    Q_PROPERTY(qreal hoverChipRadius READ hoverChipRadius NOTIFY hoverChipChanged FINAL)

  public:
    explicit PianoRollQuickScene(QObject *parent = nullptr);

    QAbstractItemModel *noteTextModel() const noexcept;
    QAbstractItemModel *loadingTextModel() const noexcept;
    QAbstractItemModel *keyboardTextModel() const noexcept;

    const PianoRollQuickLayerData &layer(PianoRollQuickLayer layer) const noexcept;
    PianoRollQuickLayerData &layer(PianoRollQuickLayer layer) noexcept;

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
    friend class PianoRollQuickView;
    std::array<PianoRollQuickLayerData, static_cast<std::size_t>(PianoRollQuickLayer::Count)>
        m_layers{};
    PianoRollQuickTextModel *m_noteTextModel = nullptr;
    PianoRollQuickTextModel *m_loadingTextModel = nullptr;
    PianoRollQuickTextModel *m_keyboardTextModel = nullptr;

    bool m_hoverChipVisible = false;
    QRectF m_hoverChipRect;
    QString m_hoverChipText;
    QColor m_hoverChipFill;
    QFont m_hoverChipFont;
    qreal m_hoverChipRadius = 0.0;
};

class PianoRollQuickView final : public QQuickWidget
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(PianoRollQuickView)

  public:
    explicit PianoRollQuickView(PianoRoll &roll);

    // The one appearance seam: re-reads the theme's opaque roll background
    // into the clear color and requests All.
    void syncAppearance();
    void requestUpdate(PianoRollQuickDirtySet dirty);

  protected:
    void resizeEvent(QResizeEvent *event) override;

  private:
    void flushUpdate();
    void synchronize(PianoRollQuickDirtySet dirty);

    void rebuildGrid();
    void rebuildNoteFills();
    void rebuildDrawPreviewFill();
    void rebuildNoteBordersAndSelection();
    void rebuildOverlay();
    void rebuildKeyboardKeys();
    void rebuildKeyboardHighlights();
    void synchronizeNoteText();
    void synchronizeLoadingText();
    void synchronizeKeyboardText();
    void synchronizeHoverChip();

    PianoRoll &m_roll;
    PianoRollQuickScene *m_scene = nullptr;
    std::array<PianoRollQuickItem *, static_cast<std::size_t>(PianoRollQuickLayer::Count)>
        m_items{};
    PianoRollQuickDirtySet m_pendingDirty = {PianoRollQuickDirty::None};
    bool m_flushScheduled = false;
    std::vector<PianoRollQuickTextModel::Record> m_noteTextRecords;
    std::vector<PianoRollQuickTextModel::Record> m_loadingTextRecords;
    std::vector<PianoRollQuickTextModel::Record> m_keyboardTextRecords;
};

} // namespace songview
