#include "songdocument.h"

#include <algorithm>
#include <set>

#include "core/timedefaults.h"

namespace {

[[maybe_unused]] bool tempoPointsAreNormalized(const std::vector<TempoPoint> &points)
{
    for (size_t i = 0; i < points.size(); i++) {
        const TempoPoint &point = points[i];
        if (point.microsecondsPerQuarterNote !=
            CoreTimeDefaults::clampTempoUspqn(point.microsecondsPerQuarterNote))
            return false;
        if (i > 0 && points[i - 1].tick >= point.tick)
            return false;
    }
    return true;
}

std::vector<TempoPoint> editedTempoPointCandidates(const std::vector<TempoPoint> &current,
                                                   const TempoEdit &edit)
{
    auto next = current;
    std::set<uint64_t> removeTicks;
    for (const TempoPoint &point : edit.remove)
        removeTicks.insert(point.tick);
    std::erase_if(next, [&](const TempoPoint &point) { return removeTicks.contains(point.tick); });
    next.insert(next.end(), edit.add.begin(), edit.add.end());
    return next;
}

} // namespace

std::vector<TempoPoint> SongDocument::normalizeTempoPoints(std::vector<TempoPoint> points)
{
    std::stable_sort(points.begin(), points.end(),
                     [](const TempoPoint &a, const TempoPoint &b) { return a.tick < b.tick; });
    std::vector<TempoPoint> out;
    out.reserve(points.size());
    for (const TempoPoint &point : points) {
        const auto clamped = TempoPoint{
            point.tick, CoreTimeDefaults::clampTempoUspqn(point.microsecondsPerQuarterNote)};
        if (!out.empty() && out.back().tick == clamped.tick)
            out.back() = clamped;
        else
            out.push_back(clamped);
    }
    return out;
}

namespace song_document_tempo {
namespace {

SmfEvent makeTempoMeta(const TempoPoint &point)
{
    SmfEvent event;
    event.tick = point.tick;
    event.status = 0xFF;
    event.metaType = 0x51;
    event.blob.resize(3);
    event.blob[0] = char((point.microsecondsPerQuarterNote >> 16) & 0xFF);
    event.blob[1] = char((point.microsecondsPerQuarterNote >> 8) & 0xFF);
    event.blob[2] = char(point.microsecondsPerQuarterNote & 0xFF);
    return event;
}
} // namespace

void removeTempoMetas(SmfFile &smf)
{
    for (SmfTrack &track : smf.tracks)
        std::erase_if(track.events, [](const SmfEvent &event) { return isTempoMeta(event); });
}

void writeTempoMetas(SmfFile &smf, const std::vector<TempoPoint> &points)
{
    if (smf.tracks.empty())
        smf.tracks.emplace_back();
    removeTempoMetas(smf);
    auto &seq = smf.tracks.front();
    std::vector<SmfEvent> merged;
    merged.reserve(seq.events.size() + points.size());
    size_t i = 0;
    for (const TempoPoint &point : points) {
        while (i < seq.events.size() && seq.events[i].tick < point.tick)
            merged.push_back(seq.events[i++]);
        merged.push_back(makeTempoMeta(point));
        while (i < seq.events.size() && seq.events[i].tick == point.tick)
            merged.push_back(seq.events[i++]);
    }
    while (i < seq.events.size())
        merged.push_back(seq.events[i++]);
    seq.events = std::move(merged);
}

} // namespace song_document_tempo

class TempoEditCommand : public QUndoCommand
{
  public:
    TempoEditCommand(SongDocument *doc, std::vector<TempoPoint> next)
        : QUndoCommand(SongDocument::tr("edit tempo"))
        , m_doc(doc)
        , m_prev(doc->m_tempoPoints)
        , m_next(std::move(next))
    {}

    void redo() override
    {
        m_doc->replaceTempoPoints(m_next);
        m_doc->publishMutation(m_doc->currentTrackRemap());
    }

    void undo() override
    {
        m_doc->replaceTempoPoints(m_prev);
        m_doc->publishMutation(m_doc->currentTrackRemap());
    }

  private:
    SongDocument *m_doc;
    std::vector<TempoPoint> m_prev;
    std::vector<TempoPoint> m_next;
};

class MixedEditCommand : public QUndoCommand
{
  public:
    MixedEditCommand(SongDocument *doc, const QString &text, std::vector<SongDocument::EditOp> ops,
                     std::vector<TempoPoint> nextTempo)
        : QUndoCommand(text)
        , m_doc(doc)
        , m_ops(std::move(ops))
        , m_prevTempo(doc->m_tempoPoints)
        , m_nextTempo(std::move(nextTempo))
    {}

    void redo() override
    {
        const auto before = m_doc->trackMapState();
        if (!m_ops.empty())
            m_doc->applyOps(m_ops);
        m_doc->replaceTempoPoints(m_nextTempo);
        m_doc->rebuildTrackMap();
        m_remap = m_ops.empty() ? m_doc->currentTrackRemap() : m_doc->trackRemap(before, m_ops);
        m_doc->publishMutation(m_remap);
    }

    void undo() override
    {
        m_doc->replaceTempoPoints(m_prevTempo);
        if (!m_ops.empty())
            m_doc->revertOps(m_ops);
        m_doc->rebuildTrackMap();
        m_doc->publishMutation(m_remap.inverse());
    }

  private:
    SongDocument *m_doc;
    std::vector<SongDocument::EditOp> m_ops;
    std::vector<TempoPoint> m_prevTempo;
    std::vector<TempoPoint> m_nextTempo;
    TrackRemap m_remap;
};

void SongDocument::pushEdit(const QString &text, std::vector<EditOp> ops,
                            std::vector<TempoPoint> nextTempo)
{
    auto normalized = normalizeTempoPoints(std::move(nextTempo));
    if (ops.empty() && normalized == m_tempoPoints)
        return;
    m_undoStack.push(new MixedEditCommand(this, text, std::move(ops), std::move(normalized)));
}

void SongDocument::replaceTempoPoints(std::vector<TempoPoint> normalized)
{
    Q_ASSERT(tempoPointsAreNormalized(normalized));
    m_tempoPoints = std::move(normalized);
}

std::vector<TempoPoint> SongDocument::tempoPointsFromSmf(const SmfFile &smf)
{
    std::vector<TempoPoint> points;
    if (smf.tracks.empty())
        return points;
    const auto &events = smf.tracks.front().events;
    points.reserve(events.size());
    for (const SmfEvent &event : events) {
        if (!isTempoMeta(event) || event.blob.size() != 3)
            continue;
        const auto *bytes = reinterpret_cast<const uint8_t *>(event.blob.constData());
        const auto us = (uint32_t(bytes[0]) << 16) | (uint32_t(bytes[1]) << 8) | bytes[2];
        points.push_back({event.tick, us});
    }
    return points;
}

void SongDocument::removeRawEventsAndEditTempo(const QString &text, int smfTrack,
                                               std::vector<size_t> rawIndices,
                                               const TempoEdit &tempo)
{
    if (smfTrack < 0 || smfTrack >= int(m_smf.tracks.size()))
        return;
    const auto count = m_smf.tracks[smfTrack].events.size();
    std::erase_if(rawIndices, [count](size_t index) { return index >= count; });
    std::vector<EditOp> ops;
    if (!rawIndices.empty())
        appendRemoveOps(ops, smfTrack, std::move(rawIndices));
    pushEdit(text, std::move(ops), editedTempoPointCandidates(m_tempoPoints, tempo));
}

void SongDocument::replaceTempoPointWithRawEvent(const QString &text, int smfTrack,
                                                 const TempoPoint &point, SmfEvent event)
{
    if (smfTrack < 0 || smfTrack >= int(m_smf.tracks.size()) || isTempoMeta(event))
        return;
    const auto it =
        std::find_if(m_tempoPoints.begin(), m_tempoPoints.end(),
                     [point](const TempoPoint &current) { return current.tick == point.tick; });
    if (it == m_tempoPoints.end())
        return;
    EditOp insert;
    insert.type = EditOp::InsertEvent;
    insert.smfTrack = smfTrack;
    insert.event = std::move(event);
    std::vector<EditOp> ops;
    ops.push_back(std::move(insert));
    const auto nextTempo = editedTempoPointCandidates(m_tempoPoints, {{*it}, {}});
    pushEdit(text, std::move(ops), std::move(nextTempo));
}

void SongDocument::applyTempoEdit(const TempoEdit &edit)
{
    if (edit.empty())
        return;
    auto next = normalizeTempoPoints(editedTempoPointCandidates(m_tempoPoints, edit));
    if (next == m_tempoPoints)
        return;
    m_undoStack.push(new TempoEditCommand(this, std::move(next)));
}
