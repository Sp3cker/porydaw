#include "eventtablemodel.h"
#include "ui/songview/quick/eventlistcontroller.h"

#include <QApplication>
#include <QColor>
#include <algorithm>
#include <limits>

#include "core/smf.h"
#include "core/songdocument.h"
#include "eventtabletypes.h"
#include "ui/songview.h"
#include "ui/typography.h"

namespace eventlist {

namespace {

QString tempoBpmText(const TempoPoint &point)
{
    const double bpm = 60000000.0 / point.microsecondsPerQuarterNote;
    if (60000000U % point.microsecondsPerQuarterNote == 0)
        return QString::number(qRound(bpm));
    return QString::number(bpm, 'f', 2);
}

} // namespace

bool EventTableModel::usesNumericFont(int column)
{
    return column == ColTick || column == ColChannel || column == ColData1 || column == ColData2;
}

QList<std::pair<QString, int>> EventTableModel::typeChoices(bool includeTempo)
{
    QList<std::pair<QString, int>> choices;
    for (int kind = 0; kind < TypeKindCount; kind++) {
        if (kind != TypeTempo || includeTempo)
            choices.append({typeKindName(kind), kind});
    }
    return choices;
}

int EventTableModel::qmlRawIndexForRow(int row) const
{
    const auto index = rawEventIndexForRow(row);
    return index && *index <= size_t(std::numeric_limits<int>::max()) ? int(*index) : -1;
}

bool EventTableModel::qmlHasTempo(int row) const
{
    return tempoPointForRow(row).has_value();
}

QString EventTableModel::qmlTickString(int row) const
{
    if (const auto tick = exactTickForRow(row))
        return QString::number(*tick);
    const SmfTrack *tr = track();
    return tr && row == int(m_rows.size()) ? QString::number(tr->endTick) : QString();
}

int EventTableModel::qmlRowForRawIndex(qulonglong eventIndex) const
{
    if (eventIndex > qulonglong(std::numeric_limits<size_t>::max()))
        return -1;
    return rowForRawEventIndex(size_t(eventIndex));
}

int EventTableModel::qmlTempoRowForTick(const QString &tickDigits) const
{
    bool ok = false;
    const qulonglong tick = tickDigits.toULongLong(&ok);
    return ok ? tempoRowForExactTick(uint64_t(tick)) : -1;
}

bool EventTableModel::qmlUsesNumericFont(int column)
{
    return usesNumericFont(column);
}

QHash<int, QByteArray> EventTableModel::roleNames() const
{
    return {
        {Qt::DisplayRole, QByteArrayLiteral("display")},
        {Qt::EditRole, QByteArrayLiteral("edit")},
        {Qt::FontRole, QByteArrayLiteral("cellFont")},
        {Qt::TextAlignmentRole, QByteArrayLiteral("alignment")},
        {TickStringRole, QByteArrayLiteral("tickString")},
        {TickValueRole, QByteArrayLiteral("tickValue")},
        {TypeKindRole, QByteArrayLiteral("typeKind")},
        {TypeNameRole, QByteArrayLiteral("typeName")},
        {ChannelRole, QByteArrayLiteral("channel")},
        {Data1Role, QByteArrayLiteral("data1")},
        {Data2Role, QByteArrayLiteral("data2")},
        {BlobRole, QByteArrayLiteral("blob")},
        {BlobDisplayRole, QByteArrayLiteral("blobDisplay")},
        {SummaryRole, QByteArrayLiteral("summary")},
        {RowKindRole, QByteArrayLiteral("rowKind")},
    };
}

EventTableModel::EventTableModel(SongView *sv, QObject *parent)
    : QAbstractTableModel(parent)
    , m_sv(sv)
{
    m_bodyFont = QApplication::font();
    m_bodyItalicFont = typography::italic(m_bodyFont);
    m_numericFont = typography::tableMono(m_bodyFont);
    m_numericItalicFont = typography::italic(m_numericFont);
}

void EventTableModel::setSource(SongDocument *doc, int chunk)
{
    beginResetModel();
    m_doc = doc;
    m_chunk = doc && chunk >= 0 && chunk < int(doc->smf().tracks.size()) ? chunk : -1;
    rebuildRows();
    endResetModel();
}

void EventTableModel::setFilter(int mask)
{
    beginResetModel();
    m_filter = mask;
    rebuildRows();
    endResetModel();
}

void EventTableModel::reload()
{
    beginResetModel();
    if (m_doc && m_chunk >= int(m_doc->smf().tracks.size()))
        m_chunk = -1;
    rebuildRows();
    endResetModel();
}

EventTableModel::RowKind EventTableModel::rowKind(const RowKey &key)
{
    return std::holds_alternative<TempoRow>(key) ? RowKind::Tempo : RowKind::Raw;
}

std::optional<size_t> EventTableModel::rawEventIndexForRow(int row) const
{
    if (row < 0 || row >= int(m_rows.size()))
        return std::nullopt;
    const auto *raw = std::get_if<RawRow>(&m_rows[row]);
    if (!raw)
        return std::nullopt;
    return raw->eventIndex;
}

std::optional<TempoPoint> EventTableModel::tempoPointForRow(int row) const
{
    if (row < 0 || row >= int(m_rows.size()))
        return std::nullopt;
    const auto *tempo = std::get_if<TempoRow>(&m_rows[row]);
    if (!tempo)
        return std::nullopt;
    const TempoPoint *found = tempoPoint(tempo->tick);
    if (!found)
        return std::nullopt;
    return *found;
}

int EventTableModel::rowForRawEventIndex(size_t index) const
{
    const auto it = std::find_if(m_rows.begin(), m_rows.end(), [index](const RowKey &key) {
        const auto *raw = std::get_if<RawRow>(&key);
        return raw && raw->eventIndex == index;
    });
    return it == m_rows.end() ? -1 : int(it - m_rows.begin());
}

int EventTableModel::tempoRowForExactTick(uint64_t tick) const
{
    const auto it = std::find_if(m_rows.begin(), m_rows.end(), [tick](const RowKey &key) {
        const auto *tempo = std::get_if<TempoRow>(&key);
        return tempo && tempo->tick == tick;
    });
    return it == m_rows.end() ? -1 : int(it - m_rows.begin());
}

std::optional<uint64_t> EventTableModel::exactTickForRow(int row) const
{
    if (row < 0 || row >= int(m_rows.size()))
        return std::nullopt;
    const uint64_t tick = rowTick(m_rows[row]);
    if (tick == std::numeric_limits<uint64_t>::max())
        return std::nullopt;
    return tick;
}

int EventTableModel::playheadRowAtOrBeforeTick(double tick) const
{
    const SmfTrack *tr = track();
    if (!tr || tick < 0)
        return -1;
    if (tick >= double(tr->endTick))
        return int(m_rows.size());
    const auto it =
        std::upper_bound(m_rows.begin(), m_rows.end(), tick,
                         [this](double t, const RowKey &key) { return t < double(rowTick(key)); });
    return int(it - m_rows.begin()) - 1;
}

void EventTableModel::setPlayRow(int row)
{
    if (row == m_playRow)
        return;
    const int old = m_playRow;
    m_playRow = row;
    const auto repaint = [this](int r) {
        if (r >= 0 && r < rowCount())
            emit dataChanged(index(r, ColTick), index(r, ColCount - 1), {Qt::BackgroundRole});
    };
    repaint(old);
    repaint(row);
}

uint8_t EventTableModel::fallbackChannel() const
{
    const SmfTrack *tr = track();
    if (tr) {
        for (const SmfEvent &ev : tr->events)
            if (ev.isChannel())
                return ev.channel();
    }
    return 0;
}

bool EventTableModel::filterMatches(int mask, const SmfEvent &ev)
{
    if (isTempoMeta(ev))
        return false;
    switch (typeKindOf(ev)) {
    case TypeNoteOff:
    case TypeNoteOn:
        return mask & FilterNotes;
    case TypeCc:
        return mask & FilterCc;
    case TypeProgram:
        return mask & FilterProgram;
    case TypeBend:
        return mask & FilterBend;
    case TypePolyTouch:
    case TypeChanTouch:
        return mask & FilterTouch;
    case TypeSysEx0:
    case TypeSysEx7:
        return mask & FilterSysEx;
    default:
        return mask & FilterMeta;
    }
}

int EventTableModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid() || !track())
        return 0;
    return int(m_rows.size()) + 1;
}

int EventTableModel::columnCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : ColCount;
}

QVariant EventTableModel::headerData(int section, Qt::Orientation orientation, int role) const
{
    if (orientation == Qt::Horizontal && role == Qt::TextAlignmentRole) {
        const Qt::Alignment alignment = usesNumericFont(section) ? Qt::AlignRight | Qt::AlignVCenter
                                                                 : Qt::AlignLeft | Qt::AlignVCenter;
        return int(alignment);
    }
    if (orientation == Qt::Horizontal && role == Qt::DisplayRole) {
        switch (section) {
        case ColTick:
            return EventListController::tr("Tick");
        case ColType:
            return EventListController::tr("Type");
        case ColChannel:
            return EventListController::tr("Ch");
        case ColData1:
            return EventListController::tr("Data 1");
        case ColData2:
            return EventListController::tr("Data 2");
        case ColData:
            return EventListController::tr("Data");
        case ColSummary:
            return EventListController::tr("Summary");
        }
    }
    return QAbstractTableModel::headerData(section, orientation, role);
}

QVariant EventTableModel::data(const QModelIndex &index, int role) const
{
    const SmfTrack *tr = track();
    if (!tr || !index.isValid())
        return {};

    if (role >= TickStringRole && role <= RowKindRole) {
        if (index.row() == int(m_rows.size())) {
            switch (role) {
            case TickStringRole:
                return QString::number(tr->endTick);
            case TickValueRole:
                return qulonglong(tr->endTick);
            case TypeKindRole:
                return -1;
            case TypeNameRole:
                return EventListController::tr("End of track");
            case RowKindRole:
                return 2;
            default:
                return {};
            }
        }
        if (index.row() < 0 || index.row() >= int(m_rows.size()))
            return {};

        const RowKey &key = m_rows[index.row()];
        if (const auto *tempo = std::get_if<TempoRow>(&key)) {
            const TempoPoint *point = tempoPoint(tempo->tick);
            if (!point)
                return {};
            switch (role) {
            case TickStringRole:
                return QString::number(point->tick);
            case TickValueRole:
                return qulonglong(point->tick);
            case TypeKindRole:
                return TypeTempo;
            case TypeNameRole:
                return typeKindName(TypeTempo);
            case SummaryRole:
                return EventListController::tr("Tempo %1 BPM").arg(tempoBpmText(*point));
            case RowKindRole:
                return 1;
            default:
                return {};
            }
        }

        const auto *raw = std::get_if<RawRow>(&key);
        if (!raw || raw->eventIndex >= tr->events.size())
            return {};
        const SmfEvent &ev = tr->events[raw->eventIndex];
        const int kind = typeKindOf(ev);
        switch (role) {
        case TickStringRole:
            return QString::number(ev.tick);
        case TickValueRole:
            return qulonglong(ev.tick);
        case TypeKindRole:
            return kind;
        case TypeNameRole:
            return typeKindName(kind);
        case ChannelRole:
            return ev.isChannel() ? QVariant(ev.channel() + 1) : QVariant();
        case Data1Role:
            if (ev.isMeta())
                return ev.metaType;
            return ev.isChannel() ? QVariant(ev.data0) : QVariant();
        case Data2Role:
            return hasData2(kind) ? QVariant(ev.data1) : QVariant();
        case BlobRole:
            return ev.isMeta() || ev.isSysEx() ? QVariant(blobText(ev)) : QVariant();
        case BlobDisplayRole:
            return ev.isMeta() || ev.isSysEx() ? QVariant(blobDisplayText(ev)) : QVariant();
        case SummaryRole:
            return summaryText(ev, m_sv);
        case RowKindRole:
            return 0;
        default:
            return {};
        }
    }

    if (role == Qt::FontRole) {
        // Every modeled cell needs a valid font: the QML delegate binds
        // required font properties straight to this role.
        const bool numeric = usesNumericFont(index.column());
        if (index.row() == int(m_rows.size()))
            return numeric ? m_numericItalicFont : m_bodyItalicFont;
        return numeric ? m_numericFont : m_bodyFont;
    }
    if (role == Qt::TextAlignmentRole) {
        if (index.column() == ColTick || index.column() == ColChannel ||
            index.column() == ColData1 || index.column() == ColData2)
            return int(Qt::AlignRight | Qt::AlignVCenter);
        return {};
    }
    if (role == Qt::BackgroundRole) {
        if (index.row() == m_playRow)
            return QColor(226, 66, 66, 44);
        return {};
    }
    if (index.row() == int(m_rows.size())) {
        if (role == Qt::DisplayRole || role == Qt::EditRole) {
            if (index.column() == ColTick)
                return qulonglong(tr->endTick);
            if (index.column() == ColType && role == Qt::DisplayRole)
                return EventListController::tr("End of track");
        }
        return {};
    }
    if (role != Qt::DisplayRole && role != Qt::EditRole)
        return {};
    const RowKey &key = m_rows[index.row()];
    if (rowKind(key) == RowKind::Tempo) {
        const auto *tempo = std::get_if<TempoRow>(&key);
        const TempoPoint *point = tempo ? tempoPoint(tempo->tick) : nullptr;
        if (!point)
            return {};
        switch (index.column()) {
        case ColTick:
            return qulonglong(point->tick);
        case ColType:
            return role == Qt::EditRole ? QVariant(TypeTempo) : QVariant(typeKindName(TypeTempo));
        case ColData:
            return role == Qt::EditRole
                       ? QVariant(tempoBpmText(*point))
                       : QVariant(EventListController::tr("%1 BPM").arg(tempoBpmText(*point)));
        case ColSummary:
            return role == Qt::DisplayRole
                       ? QVariant(EventListController::tr("Tempo %1 BPM").arg(tempoBpmText(*point)))
                       : QVariant();
        default:
            return {};
        }
    }
    const auto *raw = std::get_if<RawRow>(&key);
    if (!raw || raw->eventIndex >= tr->events.size())
        return {};
    const SmfEvent &ev = tr->events[raw->eventIndex];
    const int kind = typeKindOf(ev);
    switch (index.column()) {
    case ColTick:
        return qulonglong(ev.tick);
    case ColType:
        return role == Qt::EditRole ? QVariant(kind) : QVariant(typeKindName(kind));
    case ColChannel:
        return ev.isChannel() ? QVariant(ev.channel() + 1) : QVariant();
    case ColData1:
        if (ev.isMeta())
            return ev.metaType;
        return ev.isChannel() ? QVariant(ev.data0) : QVariant();
    case ColData2:
        return hasData2(kind) ? QVariant(ev.data1) : QVariant();
    case ColData:
        if (!ev.isMeta() && !ev.isSysEx())
            return {};
        return role == Qt::EditRole ? QVariant(blobText(ev)) : QVariant(blobDisplayText(ev));
    case ColSummary:
        return role == Qt::DisplayRole ? QVariant(summaryText(ev, m_sv)) : QVariant();
    }
    return {};
}

Qt::ItemFlags EventTableModel::flags(const QModelIndex &index) const
{
    Qt::ItemFlags f = Qt::ItemIsEnabled | Qt::ItemIsSelectable;
    const SmfTrack *tr = track();
    if (!tr)
        return f;
    if (!index.isValid())
        return f;
    if (index.row() == int(m_rows.size())) {
        if (index.column() == ColTick)
            f |= Qt::ItemIsEditable;
        return f;
    }
    const RowKey &key = m_rows[index.row()];
    if (rowKind(key) == RowKind::Tempo) {
        if (index.column() == ColTick || index.column() == ColType || index.column() == ColData)
            f |= Qt::ItemIsEditable;
        return f;
    }
    const auto *raw = std::get_if<RawRow>(&key);
    if (!raw || raw->eventIndex >= tr->events.size())
        return f;
    const SmfEvent &ev = tr->events[raw->eventIndex];
    switch (index.column()) {
    case ColTick:
    case ColType:
        f |= Qt::ItemIsEditable;
        break;
    case ColChannel:
        if (ev.isChannel())
            f |= Qt::ItemIsEditable;
        break;
    case ColData1:
        if (ev.isChannel() || ev.isMeta())
            f |= Qt::ItemIsEditable;
        break;
    case ColData2:
        if (hasData2(typeKindOf(ev)))
            f |= Qt::ItemIsEditable;
        break;
    case ColData:
        if (ev.isMeta() || ev.isSysEx())
            f |= Qt::ItemIsEditable;
        break;
    }
    return f;
}

const SmfTrack *EventTableModel::track() const
{
    if (!m_doc || m_chunk < 0 || m_chunk >= int(m_doc->smf().tracks.size()))
        return nullptr;
    return &m_doc->smf().tracks[m_chunk];
}

const TempoPoint *EventTableModel::tempoPoint(uint64_t tick) const
{
    if (!m_doc || m_chunk != 0)
        return nullptr;
    const auto &points = m_doc->tempoPoints();
    const auto it =
        std::lower_bound(points.begin(), points.end(), tick,
                         [](const TempoPoint &point, uint64_t t) { return point.tick < t; });
    return it != points.end() && it->tick == tick ? &*it : nullptr;
}

uint64_t EventTableModel::rowTick(const RowKey &key) const
{
    if (const auto *tempo = std::get_if<TempoRow>(&key))
        return tempo->tick;
    const auto *raw = std::get_if<RawRow>(&key);
    const SmfTrack *tr = track();
    if (!raw || !tr || raw->eventIndex >= tr->events.size())
        return std::numeric_limits<uint64_t>::max();
    return tr->events[raw->eventIndex].tick;
}

void EventTableModel::rebuildRows()
{
    m_rows.clear();
    m_playRow = -1;
    const SmfTrack *tr = track();
    if (!tr)
        return;
    std::vector<RowKey> raw;
    raw.reserve(tr->events.size());
    for (size_t i = 0; i < tr->events.size(); i++) {
        if (filterMatches(m_filter, tr->events[i]))
            raw.push_back(RawRow{i});
    }
    if (m_chunk != 0 || !(m_filter & FilterMeta)) {
        m_rows = std::move(raw);
        return;
    }
    const auto &tempo = m_doc->tempoPoints();
    m_rows.reserve(raw.size() + tempo.size());
    size_t rawIndex = 0;
    size_t tempoIndex = 0;
    while (rawIndex < raw.size() || tempoIndex < tempo.size()) {
        if (tempoIndex < tempo.size() &&
            (rawIndex == raw.size() || tempo[tempoIndex].tick <= rowTick(raw[rawIndex]))) {
            m_rows.push_back(TempoRow{tempo[tempoIndex].tick});
            tempoIndex++;
        } else {
            m_rows.push_back(raw[rawIndex]);
            rawIndex++;
        }
    }
}

void EventTableModel::setSelectionHandler(std::function<void(int, uint64_t)> handler)
{
    m_select = std::move(handler);
}

} // namespace eventlist
