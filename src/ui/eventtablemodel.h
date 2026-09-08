#pragma once

#include "core/tempo.h"
#include <QAbstractTableModel>
#include <QByteArray>
#include <QFont>
#include <QHash>
#include <QList>
#include <QString>
#include <cstdint>
#include <functional>
#include <memory>
#include <optional>
#include <variant>
#include <vector>

class SongDocument;
class SongView;
struct SmfEvent;
struct SmfTrack;
struct TempoEdit;

namespace eventlist {

class EventTableModel : public QAbstractTableModel
{
    Q_OBJECT

  public:
    enum Col { ColTick, ColType, ColChannel, ColData1, ColData2, ColData, ColSummary, ColCount };
    enum FilterBit {
        FilterNotes = 1 << 0,
        FilterCc = 1 << 1,
        FilterProgram = 1 << 2,
        FilterBend = 1 << 3,
        FilterTouch = 1 << 4,
        FilterSysEx = 1 << 5,
        FilterMeta = 1 << 6,
        FilterAll = (1 << 7) - 1
    };
    enum EventRoles {
        TickStringRole = Qt::UserRole + 1,
        TickValueRole,
        TypeKindRole,
        TypeNameRole,
        ChannelRole,
        Data1Role,
        Data2Role,
        BlobRole,
        BlobDisplayRole,
        SummaryRole,
        RowKindRole,
    };
    Q_ENUM(EventRoles)

    static bool usesNumericFont(int column);
    static QList<std::pair<QString, int>> typeChoices(bool includeTempo);
    Q_INVOKABLE int qmlRawIndexForRow(int row) const;
    Q_INVOKABLE bool qmlHasTempo(int row) const;
    Q_INVOKABLE QString qmlTickString(int row) const;
    Q_INVOKABLE int qmlRowForRawIndex(qulonglong eventIndex) const;
    Q_INVOKABLE int qmlTempoRowForTick(const QString &tickDigits) const;
    Q_INVOKABLE static bool qmlUsesNumericFont(int column);

    explicit EventTableModel(SongView *sv, QObject *parent);
    void setSource(SongDocument *doc, int chunk);
    void setFilter(int mask);
    void reload();
    int chunk() const { return m_chunk; }
    size_t shownEvents() const { return m_rows.size(); }
    std::optional<size_t> rawEventIndexForRow(int row) const;
    std::optional<TempoPoint> tempoPointForRow(int row) const;
    // QModelIndex-compatible row lookups return -1 when no row matches.
    int rowForRawEventIndex(size_t index) const;
    int tempoRowForExactTick(uint64_t tick) const;
    std::optional<uint64_t> exactTickForRow(int row) const;
    int playheadRowAtOrBeforeTick(double tick) const;
    int playRow() const { return m_playRow; }
    void setPlayRow(int row);
    uint8_t fallbackChannel() const;
    void setSelectionHandler(std::function<void(int, uint64_t)> handler);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    int columnCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant headerData(int section, Qt::Orientation orientation, int role) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    Qt::ItemFlags flags(const QModelIndex &index) const override;
    bool setData(const QModelIndex &index, const QVariant &value, int role) override;

  private:
    enum class RowKind { Raw, Tempo };
    struct PendingRawEdit;
    struct RawRow {
        size_t eventIndex;
    };
    struct TempoRow {
        uint64_t tick;
    };
    using RowKey = std::variant<RawRow, TempoRow>;

    static RowKind rowKind(const RowKey &key);
    const SmfTrack *track() const;
    static bool filterMatches(int mask, const SmfEvent &ev);
    const TempoPoint *tempoPoint(uint64_t tick) const;
    bool handleEndTick(const QVariant &value);
    bool handleTempoTick(const TempoPoint &point, const QVariant &value);
    bool handleTempoTypeChange(const TempoPoint &point, const QVariant &value);
    bool handleTempoBpm(const TempoPoint &point, const QVariant &value);
    bool handleRawTick(size_t eventIndex, const SmfEvent &event, const QVariant &value);
    bool handleRawTypeChange(size_t eventIndex, const SmfEvent &event, const QVariant &value);
    bool handleRawTypeToTempo(size_t eventIndex, const SmfEvent &event);
    bool handleRawChannel(size_t eventIndex, const SmfEvent &event, const QVariant &value);
    bool handleRawData1(size_t eventIndex, const SmfEvent &event, const QVariant &value);
    bool handleRawData2(size_t eventIndex, const SmfEvent &event, const QVariant &value);
    bool handleRawBlob(size_t eventIndex, const SmfEvent &event, const QVariant &value);
    SmfEvent pendingRawEvent(size_t eventIndex, const SmfEvent &fallback) const;
    bool commitRawEdit(size_t eventIndex, const SmfEvent &event);
    void queueTempoEdit(const TempoEdit &edit, uint64_t selectTick);
    uint64_t rowTick(const RowKey &key) const;
    void rebuildRows();

    QFont m_bodyFont;
    QFont m_bodyItalicFont;
    QFont m_numericFont;
    QFont m_numericItalicFont;
    SongView *m_sv;
    SongDocument *m_doc = nullptr;
    int m_chunk = -1;
    int m_filter = FilterAll;
    int m_playRow = -1;
    std::vector<RowKey> m_rows;
    std::vector<std::shared_ptr<PendingRawEdit>> m_pendingRawEdits;
    std::function<void(int, uint64_t)> m_select;
};

} // namespace eventlist
