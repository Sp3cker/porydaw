#include <QElapsedTimer>
#include <QFileInfo>
#include <QString>

#include <algorithm>
#include <cstdio>
#include <map>
#include <set>
#include <utility>
#include <vector>

#include "core/songdocument.h"
#include "profiling.h"

namespace {

struct NoteId {
    uint64_t tick;
    uint8_t key;
};

struct Workload {
    const char *position;
    std::vector<NoteId> notes;
};

struct Durations {
    std::vector<qint64> notesForTrack;
    std::vector<qint64> resolve;
    std::vector<qint64> erase;
};

size_t eventCount(const SongDocument &doc)
{
    size_t count = 0;
    for (const SmfTrack &track : doc.smf().tracks)
        count += track.events.size();
    return count;
}

std::vector<DocNote> eligibleNotes(const SongDocument &doc, int track)
{
    const std::vector<DocNote> notes = doc.notesForTrack(track);
    std::map<std::pair<uint64_t, uint8_t>, size_t> idCounts;
    for (const DocNote &note : notes)
        idCounts[{note.tick, note.key}]++;

    std::set<size_t> claimedEvents;
    std::vector<DocNote> eligible;
    for (const DocNote &note : notes) {
        if (idCounts[{note.tick, note.key}] != 1 || claimedEvents.count(note.onIndex)
            || (!note.unterminated() && claimedEvents.count(note.endIndex)))
            continue;
        claimedEvents.insert(note.onIndex);
        if (!note.unterminated())
            claimedEvents.insert(note.endIndex);
        eligible.push_back(note);
    }
    return eligible;
}

void appendWorkload(std::vector<Workload> &out, std::set<std::vector<size_t>> &seen,
                    const char *position, const std::vector<DocNote> &notes,
                    std::vector<size_t> indices)
{
    if (!seen.insert(indices).second)
        return;
    Workload workload;
    workload.position = position;
    workload.notes.reserve(indices.size());
    for (size_t index : indices)
        workload.notes.push_back({notes[index].tick, notes[index].key});
    out.push_back(std::move(workload));
}

std::vector<Workload> workloadsFor(const std::vector<DocNote> &notes, size_t count)
{
    std::vector<Workload> out;
    std::set<std::vector<size_t>> seen;
    const size_t total = notes.size();

    std::vector<size_t> indices(count);
    for (size_t i = 0; i < count; i++)
        indices[i] = i;
    appendWorkload(out, seen, count == total ? "all" : "begin", notes, indices);
    if (count == total)
        return out;

    const size_t middle = (total - count) / 2;
    for (size_t i = 0; i < count; i++)
        indices[i] = middle + i;
    appendWorkload(out, seen, "middle", notes, indices);

    for (size_t i = 0; i < count; i++)
        indices[i] = total - count + i;
    appendWorkload(out, seen, "end", notes, indices);

    if (count > 1) {
        for (size_t i = 0; i < count; i++)
            indices[i] = i * (total - 1) / (count - 1);
        appendWorkload(out, seen, "distributed", notes, indices);
    }
    return out;
}

bool runIteration(SongDocument &doc, int track, const Workload &workload,
                  size_t trackNotes, const QByteArray &baseline,
                  size_t baselineEvents, int iteration, qint64 *notesForTrackNs,
                  qint64 *resolveNs, qint64 *eraseNs)
{
    QElapsedTimer timer;
    std::vector<DocNote> resolved;
    resolved.reserve(workload.notes.size());

    // The first warmup's undo invalidates the cache, so this is a cold build;
    // the findNote loop immediately below then measures cache hits.
    timer.start();
    const auto &notes = doc.notesForTrack(track);
    *notesForTrackNs = timer.nsecsElapsed();
    if (notes.size() != trackNotes) {
        std::fprintf(stderr,
                     "deletebench: track %d note count changed before deletion\n",
                     track);
        return false;
    }

#if defined(PORYDAW_SIGNPOSTS)
    const os_log_t log = profiling::midiNoteDeleteLog();
    os_signpost_id_t resolveId = OS_SIGNPOST_ID_INVALID;
    if (iteration >= 0) {
        resolveId = os_signpost_id_generate(log);
        os_signpost_interval_begin(
            log, resolveId, "BenchmarkResolve",
            "track=%{public}d notes=%{public}lu position=%{public}s iteration=%{public}d",
            track, static_cast<unsigned long>(workload.notes.size()), workload.position,
            iteration);
    }
#endif
    timer.restart();
    for (const NoteId &id : workload.notes) {
        DocNote note;
        if (!doc.findNote(track, id.tick, id.key, &note)) {
            std::fprintf(stderr,
                         "deletebench: failed to resolve track %d tick %llu key %u\n",
                         track, static_cast<unsigned long long>(id.tick), id.key);
            return false;
        }
        resolved.push_back(note);
    }
    *resolveNs = timer.nsecsElapsed();
#if defined(PORYDAW_SIGNPOSTS)
    if (iteration >= 0)
        os_signpost_interval_end(log, resolveId, "BenchmarkResolve");
#endif

    std::set<std::pair<int, size_t>> removedEvents;
    for (const DocNote &note : resolved) {
        removedEvents.insert({note.smfTrack, note.onIndex});
        if (!note.unterminated())
            removedEvents.insert({note.smfTrack, note.endIndex});
    }

#if defined(PORYDAW_SIGNPOSTS)
    os_signpost_id_t eraseId = OS_SIGNPOST_ID_INVALID;
    if (iteration >= 0) {
        eraseId = os_signpost_id_generate(log);
        os_signpost_interval_begin(
            log, eraseId, "BenchmarkDeleteStorage",
            "events=%{public}lu notes=%{public}lu position=%{public}s iteration=%{public}d",
            static_cast<unsigned long>(baselineEvents),
            static_cast<unsigned long>(resolved.size()), workload.position, iteration);
    }
#endif
    timer.restart();
    doc.deleteNotes(resolved);
    *eraseNs = timer.nsecsElapsed();
#if defined(PORYDAW_SIGNPOSTS)
    if (iteration >= 0)
        os_signpost_interval_end(log, eraseId, "BenchmarkDeleteStorage");
#endif

    const size_t expectedEvents = baselineEvents - removedEvents.size();
    if (eventCount(doc) != expectedEvents || !doc.undoStack()->canUndo()) {
        std::fprintf(stderr,
                     "deletebench: deletion invariant failed for %s/%lu\n",
                     workload.position,
                     static_cast<unsigned long>(workload.notes.size()));
        return false;
    }
    doc.undoStack()->undo();
    if (doc.smf().write() != baseline) {
        std::fprintf(stderr,
                     "deletebench: undo failed to restore %s/%lu byte-for-byte\n",
                     workload.position,
                     static_cast<unsigned long>(workload.notes.size()));
        return false;
    }
    doc.undoStack()->clear();
    return true;
}

qint64 percentile(std::vector<qint64> values, size_t numerator)
{
    std::sort(values.begin(), values.end());
    const size_t index = (numerator * values.size() + 99) / 100 - 1;
    return values[index];
}

void printStats(size_t events, size_t eligible, int track, size_t deleted,
                const char *position, const char *phase, const std::vector<qint64> &values)
{
    const auto [minimum, maximum] = std::minmax_element(values.begin(), values.end());
    std::printf("%lu,%lu,%d,%lu,%s,%s,%lu,%lld,%lld,%lld,%lld\n",
                static_cast<unsigned long>(events),
                static_cast<unsigned long>(eligible), track,
                static_cast<unsigned long>(deleted), position, phase,
                static_cast<unsigned long>(values.size()),
                static_cast<long long>(*minimum),
                static_cast<long long>(percentile(values, 50)),
                static_cast<long long>(percentile(values, 95)),
                static_cast<long long>(*maximum));
}

} // namespace

int runDeleteBench(const QString &midiPath, int iterations)
{
    SongInfo song;
    song.label = QFileInfo(midiPath).completeBaseName();
    song.midPath = QFileInfo(midiPath).absoluteFilePath();
    song.hasMid = true;

    QString error;
    SongDocument doc;
    if (!doc.load(song, &error)) {
        std::fprintf(stderr, "deletebench: %s\n", qUtf8Printable(error));
        return 1;
    }

    int track = -1;
    std::vector<DocNote> notes;
    for (int candidate = 0; candidate < doc.engineTrackCount(); candidate++) {
        std::vector<DocNote> candidateNotes = eligibleNotes(doc, candidate);
        if (candidateNotes.size() > notes.size()) {
            track = candidate;
            notes = std::move(candidateNotes);
        }
    }
    if (track < 0 || notes.empty()) {
        std::fprintf(stderr, "deletebench: MIDI contains no uniquely addressable notes\n");
        return 1;
    }

    const QByteArray baseline = doc.smf().write();
    const size_t events = eventCount(doc);
    const size_t trackNotes = doc.notesForTrack(track).size();
    std::vector<size_t> sizes = {1, 10, 100, 1000, notes.size()};
    sizes.erase(std::remove_if(sizes.begin(), sizes.end(),
                               [&](size_t size) { return size > notes.size(); }),
                sizes.end());
    std::sort(sizes.begin(), sizes.end());
    sizes.erase(std::unique(sizes.begin(), sizes.end()), sizes.end());

    std::printf("track_events,eligible_notes,engine_track,delete_count,position,phase,"
                "iterations,min_ns,median_ns,p95_ns,max_ns\n");
    const size_t trackEvents =
        doc.smf().tracks[size_t(doc.smfTrackFor(track))].events.size();
    for (size_t size : sizes) {
        for (const Workload &workload : workloadsFor(notes, size)) {
            qint64 ignoredResolve = 0;
            qint64 ignoredErase = 0;
            qint64 ignoredNotesForTrack = 0;
            for (int warmup = 0; warmup < 2; warmup++) {
                if (!runIteration(doc, track, workload, trackNotes, baseline, events,
                                  -1, &ignoredNotesForTrack, &ignoredResolve,
                                  &ignoredErase))
                    return 1;
            }

            Durations durations;
            durations.notesForTrack.reserve(size_t(iterations));
            durations.resolve.reserve(size_t(iterations));
            durations.erase.reserve(size_t(iterations));
            for (int iteration = 0; iteration < iterations; iteration++) {
                qint64 notesForTrackNs = 0;
                qint64 resolveNs = 0;
                qint64 eraseNs = 0;
                if (!runIteration(doc, track, workload, trackNotes, baseline, events,
                                  iteration, &notesForTrackNs, &resolveNs, &eraseNs))
                    return 1;
                durations.notesForTrack.push_back(notesForTrackNs);
                durations.resolve.push_back(resolveNs);
                durations.erase.push_back(eraseNs);
            }
            printStats(trackEvents, notes.size(), track, size, workload.position,
                       "notes_for_track_cold", durations.notesForTrack);
            printStats(trackEvents, notes.size(), track, size, workload.position,
                       "resolve_hot_cache", durations.resolve);
            printStats(trackEvents, notes.size(), track, size, workload.position,
                       "delete_storage", durations.erase);
        }
    }
    return 0;
}
