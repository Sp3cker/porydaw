#include "eventlistview.h"
#include "eventtablemodel.h"

#include <QMetaObject>
#include <algorithm>
#include <cmath>

#include "core/smf.h"
#include "core/songdocument.h"
#include "eventtabletypes.h"
#include "ui/songview.h"

namespace eventlist {

namespace {

TempoPoint tempoPointForBpm(uint64_t tick, int bpm)
{
    return {tick, uint32_t(std::lround(60000000.0 / bpm))};
}

} // namespace

bool EventTableModel::handleEndTick(const QVariant &value)
{
    const auto doc = m_doc;
    const auto chunk = m_chunk;
    const auto tick = uint64_t(value.toULongLong());
    QMetaObject::invokeMethod(
        this, [doc, chunk, tick] { doc->setTrackEndTick(chunk, tick); }, Qt::QueuedConnection);
    return true;
}

void EventTableModel::queueTempoEdit(const TempoEdit &edit, uint64_t selectTick)
{
    const auto doc = m_doc;
    const auto select = m_select;
    const auto chunk = m_chunk;
    QMetaObject::invokeMethod(
        this,
        [doc, edit, select, chunk, selectTick] {
            doc->applyTempoEdit(edit);
            if (select)
                select(chunk, selectTick);
        },
        Qt::QueuedConnection);
}

bool EventTableModel::handleTempoTick(const TempoPoint &point, const QVariant &value)
{
    const auto tick = uint64_t(value.toULongLong());
    queueTempoEdit({{point}, {{tick, point.microsecondsPerQuarterNote}}}, tick);
    return true;
}

bool EventTableModel::handleTempoTypeChange(const TempoPoint &point, const QVariant &value)
{
    const auto kind = value.toInt();
    if (kind == TypeTempo)
        return true;
    if (kind < 0 || kind >= TypeKindCount)
        return false;
    auto raw = SmfEvent{};
    raw.tick = point.tick;
    raw.status = 0xFF;
    raw.metaType = 0x06;
    raw = retyped(raw, kind, fallbackChannel());
    const auto doc = m_doc;
    const auto chunk = m_chunk;
    const auto select = m_select;
    QMetaObject::invokeMethod(
        this,
        [doc, chunk, point, raw, select] {
            doc->replaceTempoPointWithRawEvent(EventListView::tr("convert tempo to event"), chunk,
                                               point, raw);
            if (select)
                select(chunk, raw.tick);
        },
        Qt::QueuedConnection);
    return true;
}

bool EventTableModel::handleTempoBpm(const TempoPoint &point, const QVariant &value)
{
    bool ok = false;
    const auto bpm = value.toString().trimmed().toInt(&ok);
    if (!ok || bpm < 20 || bpm > 255) {
        if (m_sv)
            m_sv->announce(EventListView::tr("Tempo must be a whole BPM from 20 through 255"));
        return false;
    }
    queueTempoEdit({{point}, {tempoPointForBpm(point.tick, bpm)}}, point.tick);
    return true;
}

bool EventTableModel::handleRawTick(size_t eventIndex, const SmfEvent &event, const QVariant &value)
{
    auto next = event;
    next.tick = value.toULongLong();
    return commitRawEdit(eventIndex, next);
}

bool EventTableModel::handleRawTypeToTempo(size_t eventIndex, const SmfEvent &event)
{
    if (m_chunk != 0)
        return false;
    const auto point = TempoPoint{event.tick, 500000};
    const auto doc = m_doc;
    const auto chunk = m_chunk;
    const auto select = m_select;
    QMetaObject::invokeMethod(
        this,
        [doc, chunk, eventIndex, point, select] {
            doc->removeRawEventsAndEditTempo(EventListView::tr("convert event to tempo"), chunk,
                                             {eventIndex}, {{}, {point}});
            if (select)
                select(chunk, point.tick);
        },
        Qt::QueuedConnection);
    return true;
}

bool EventTableModel::handleRawTypeChange(size_t eventIndex, const SmfEvent &event,
                                          const QVariant &value)
{
    const auto kind = value.toInt();
    if (kind == TypeTempo)
        return handleRawTypeToTempo(eventIndex, event);
    if (kind < 0 || kind >= TypeKindCount)
        return false;
    return commitRawEdit(eventIndex, retyped(event, kind, fallbackChannel()));
}

bool EventTableModel::handleRawChannel(size_t eventIndex, const SmfEvent &event,
                                       const QVariant &value)
{
    if (!event.isChannel())
        return false;
    auto next = event;
    next.status = uint8_t((next.status & 0xF0) | uint8_t(std::clamp(value.toInt() - 1, 0, 15)));
    return commitRawEdit(eventIndex, next);
}

bool EventTableModel::handleRawData1(size_t eventIndex, const SmfEvent &event,
                                     const QVariant &value)
{
    auto next = event;
    if (next.isMeta())
        next.metaType = uint8_t(std::clamp(value.toInt(), 0, 127));
    else if (next.isChannel())
        next.data0 = uint8_t(std::clamp(value.toInt(), 0, 127));
    else
        return false;
    return commitRawEdit(eventIndex, next);
}

bool EventTableModel::handleRawData2(size_t eventIndex, const SmfEvent &event,
                                     const QVariant &value)
{
    if (!hasData2(typeKindOf(event)))
        return false;
    auto next = event;
    next.data1 = uint8_t(std::clamp(value.toInt(), 0, 127));
    return commitRawEdit(eventIndex, next);
}

bool EventTableModel::handleRawBlob(size_t eventIndex, const SmfEvent &event, const QVariant &value)
{
    QByteArray blob;
    if (!parseBlob(value.toString(), &blob)) {
        if (m_sv)
            m_sv->announce(
                EventListView::tr("Data must be hex bytes (\"4F 12 ...\") or \"quoted text\""));
        return false;
    }
    auto next = event;
    next.blob = blob;
    return commitRawEdit(eventIndex, next);
}

bool EventTableModel::commitRawEdit(size_t eventIndex, const SmfEvent &event)
{
    const auto doc = m_doc;
    const auto chunk = m_chunk;
    QMetaObject::invokeMethod(
        this, [doc, chunk, eventIndex, event] { doc->modifyRawEvent(chunk, eventIndex, event); },
        Qt::QueuedConnection);
    return true;
}

bool EventTableModel::setData(const QModelIndex &index, const QVariant &value, int role)
{
    if (role != Qt::EditRole || !index.isValid())
        return false;
    const auto *tr = track();
    if (!tr)
        return false;
    if (index.row() == int(m_rows.size()))
        return index.column() == ColTick && handleEndTick(value);
    if (index.row() < 0 || index.row() >= int(m_rows.size()))
        return false;
    const auto &key = m_rows[index.row()];
    if (rowKind(key) == RowKind::Tempo) {
        const auto *tempo = std::get_if<TempoRow>(&key);
        const auto *point = tempo ? tempoPoint(tempo->tick) : nullptr;
        if (!point)
            return false;
        switch (index.column()) {
        case ColTick:
            return handleTempoTick(*point, value);
        case ColType:
            return handleTempoTypeChange(*point, value);
        case ColData:
            return handleTempoBpm(*point, value);
        default:
            return false;
        }
    }
    const auto *raw = std::get_if<RawRow>(&key);
    if (!raw || raw->eventIndex >= tr->events.size())
        return false;
    const auto &event = tr->events[raw->eventIndex];
    switch (index.column()) {
    case ColTick:
        return handleRawTick(raw->eventIndex, event, value);
    case ColType:
        return handleRawTypeChange(raw->eventIndex, event, value);
    case ColChannel:
        return handleRawChannel(raw->eventIndex, event, value);
    case ColData1:
        return handleRawData1(raw->eventIndex, event, value);
    case ColData2:
        return handleRawData2(raw->eventIndex, event, value);
    case ColData:
        return handleRawBlob(raw->eventIndex, event, value);
    default:
        return false;
    }
}

} // namespace eventlist
