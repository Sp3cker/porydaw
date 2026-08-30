#include <algorithm>
#include <vector>

#include "checks/editcheck/support.h"
#include "core/xcmd.h"

namespace {

bool trackSorted(const SmfTrack &track)
{
    for (size_t i = 1; i < track.events.size(); i++) {
        if (track.events[i].tick < track.events[i - 1].tick)
            return false;
    }
    return true;
}

int pickChunk(const SongDocument &doc)
{
    const int mapped = doc.smfTrackFor(0);
    if (mapped >= 0)
        return mapped;
    for (size_t t = 0; t < doc.smf().tracks.size(); t++) {
        if (!doc.smf().tracks[t].events.empty())
            return int(t);
    }
    return doc.smf().tracks.empty() ? -1 : 0;
}

size_t countMatching(const SmfTrack &track, const SmfEvent &target)
{
    return size_t(std::count(track.events.begin(), track.events.end(), target));
}

long long indexOf(const SmfTrack &track, const SmfEvent &target)
{
    const auto it = std::find(track.events.begin(), track.events.end(), target);
    return it == track.events.end() ? -1 : (long long)(it - track.events.begin());
}

} // namespace

namespace editcheck {

void checkSongRawEventContracts(SongEditScenario &scenario)
{
    SongDocument &doc = scenario.doc;
    const QByteArray baseline = doc.smf().write();
    QUndoStack *const undoStack = doc.undoStack();
    const int entryUndoIndex = undoStack->index();
    const int entryUndoCount = undoStack->count();
    const int chunk = pickChunk(doc);
    if (chunk < 0)
        return;

    auto undoToEntry = [&] {
        while (undoStack->index() > entryUndoIndex)
            undoStack->undo();
    };
    auto fail = [&scenario](const char *what) { scenario.fail(what); };
    const auto &track = doc.smf().tracks[chunk];

    uint8_t channel = 0;
    for (const SmfEvent &event : track.events) {
        if (event.isChannel()) {
            channel = event.channel();
            break;
        }
    }
    uint64_t base = 0;
    for (const SmfTrack &candidate : doc.smf().tracks)
        base = std::max(base, candidate.endTick);
    base += 100;

    const size_t before = track.events.size();
    bool ok = true;

    // Insert: appended past everything, and the EOT follows it out.
    SmfEvent event;
    event.tick = base;
    event.status = uint8_t(0xB0 | channel);
    event.data0 = 7;
    event.data1 = 64;
    doc.insertRawEvent(chunk, event);
    if (track.events.size() != before + 1 || !trackSorted(track) ||
        countMatching(track, event) != 1 || track.endTick != base) {
        fail("insertRawEvent produced wrong content");
        ok = false;
    }

    // Same-tick modify: in place, no reorder.
    if (ok) {
        const long long index = indexOf(track, event);
        SmfEvent edited = event;
        edited.data1 = 99;
        doc.modifyRawEvent(chunk, size_t(index), edited);
        if (indexOf(track, edited) != index || !trackSorted(track)) {
            fail("same-tick modifyRawEvent produced wrong content");
            ok = false;
        }
        event = edited;
    }

    // Tick-moving modify: re-inserted at the new position, still sorted.
    if (ok) {
        const long long index = indexOf(track, event);
        SmfEvent moved = event;
        moved.tick = 0;
        const size_t movedBefore = countMatching(track, moved);
        doc.modifyRawEvent(chunk, size_t(index), moved);
        if (countMatching(track, moved) != movedBefore + 1 || !trackSorted(track) ||
            track.events.size() != before + 1) {
            fail("tick-moving modifyRawEvent produced wrong content");
            ok = false;
        }
        event = moved;
    }

    // Delete brings the chunk back to its original event count.
    if (ok) {
        const size_t had = countMatching(track, event);
        doc.deleteRawEvents(chunk, {size_t(indexOf(track, event))});
        if (track.events.size() != before || countMatching(track, event) != had - 1) {
            fail("deleteRawEvents produced wrong content");
            ok = false;
        }
    }

    // End-of-track moves freely forward but clamps at the last event.
    if (ok) {
        doc.setTrackEndTick(chunk, base + 500);
        if (track.endTick != base + 500) {
            fail("setTrackEndTick did not move the end");
            ok = false;
        }
        const uint64_t lastTick = track.events.empty() ? 0 : track.events.back().tick;
        doc.setTrackEndTick(chunk, 0);
        if (track.endTick != lastTick) {
            fail("setTrackEndTick not clamped at the last event");
            ok = false;
        }
    }

    // Reorder: a same-tick setup pair swaps by explicit position — the one
    // raw edit that picks position — while the clamp keeps setup ahead of the
    // group's note-on and refuses to leave the tick.
    if (ok) {
        const uint64_t group = base + 1000;
        SmfEvent ccA;
        ccA.tick = group;
        ccA.status = uint8_t(0xB0 | channel);
        ccA.data0 = 7;
        ccA.data1 = 1;
        SmfEvent ccB = ccA;
        ccB.data0 = 10;
        ccB.data1 = 2;
        SmfEvent on;
        on.tick = group;
        on.status = uint8_t(0x90 | channel);
        on.data0 = 60;
        on.data1 = 100;
        doc.insertRawEvent(chunk, ccA);
        doc.insertRawEvent(chunk, ccB);
        doc.insertRawEvent(chunk, on);
        const long long iA = indexOf(track, ccA);
        const long long iB = indexOf(track, ccB);
        const long long iN = indexOf(track, on);
        if (iA < 0 || iB != iA + 1 || iN != iA + 2) {
            fail("reorder scaffold not in canonical order");
            ok = false;
        }
        size_t first = 0;
        size_t last = 0;
        if (ok) {
            // The CC roams its setup run, never past the note-on; the note-on
            // is pinned behind the whole run.
            if (!doc.rawEventMoveBounds(chunk, size_t(iA), &first, &last) || first != size_t(iA) ||
                last != size_t(iB)) {
                fail("rawEventMoveBounds wrong for a same-tick setup event");
                ok = false;
            }
            if (!doc.rawEventMoveBounds(chunk, size_t(iN), &first, &last) || first != size_t(iN) ||
                last != size_t(iN)) {
                fail("rawEventMoveBounds lets a note-on cross its setup run");
                ok = false;
            }
        }
        if (ok) {
            doc.moveRawEvent(chunk, size_t(iA), size_t(iB));
            if (indexOf(track, ccB) != iA || indexOf(track, ccA) != iB ||
                indexOf(track, on) != iN || !trackSorted(track)) {
                fail("moveRawEvent did not swap the same-tick pair");
                ok = false;
            }
        }
        if (ok) {
            // Clamped moves that land on the current position are no-ops and
            // must not grow the undo stack: past the note-on (the event
            // already sits at its last legal slot) and across the tick
            // boundary toward index 0.
            const int undoCount = undoStack->count();
            doc.moveRawEvent(chunk, size_t(iB), size_t(iN));
            doc.moveRawEvent(chunk, size_t(iA), 0);
            if (undoStack->count() != undoCount || indexOf(track, ccA) != iB ||
                indexOf(track, ccB) != iA) {
                fail("a clamped no-op move mutated the chunk or undo stack");
                ok = false;
            }
        }
        if (ok) {
            // Direct undo/redo of the move: the final undo-all cannot see a
            // broken MoveEvent revert, because the whole scaffold group is
            // erased by the insert undos either way.
            undoStack->undo();
            if (indexOf(track, ccA) != iA || indexOf(track, ccB) != iB) {
                fail("undoing the reorder did not restore the order");
                ok = false;
            }
            undoStack->redo();
            if (indexOf(track, ccA) != iB || indexOf(track, ccB) != iA) {
                fail("redoing the reorder did not reapply the swap");
                ok = false;
            }
        }
    }

    // Undo everything: byte-identical; redo deterministic. (Most of the
    // script is net-zero — insert, move, delete, EOT clamped back — so the
    // redone bytes are compared against the captured edited state, not
    // against "anything but the baseline". The reorder scaffold above stays
    // in, putting the swap itself under both comparisons.)
    const QByteArray edited = doc.smf().write();
    undoToEntry();
    if (doc.smf().write() != baseline) {
        fail("undo-all did not restore the original bytes");
    } else {
        while (undoStack->canRedo())
            undoStack->redo();
        const QByteArray redone = doc.smf().write();
        undoToEntry();
        if (doc.smf().write() != baseline)
            fail("undo after redo did not restore the original bytes");
        else if (redone != edited)
            fail("redo-all did not reproduce the edited state");
    }

    // This first per-song stage starts from a clean document; drop its redo
    // entries before the independent edit topics begin.
    if (entryUndoIndex == 0 && entryUndoCount == 0)
        undoStack->clear();
}

void checkSongXcmdSaveSnapshot(SongEditScenario &scenario)
{
    if (scenario.track < 0)
        return;
    SongDocument &doc = scenario.doc;
    const int smfTrack = doc.smfTrackFor(scenario.track);
    const uint8_t channel = doc.channelFor(scenario.track);
    const uint8_t status = uint8_t(0xB0 | (channel & 0x0F));

    SmfEvent sel1;
    sel1.tick = scenario.base + scenario.step;
    sel1.status = status;
    sel1.data0 = xcmd::kSelectorController;
    sel1.data1 = 0x08;
    doc.insertRawEvent(smfTrack, sel1);

    SmfEvent payload;
    payload.tick = scenario.base + 2 * scenario.step;
    payload.status = status;
    payload.data0 = xcmd::kPayloadController;
    payload.data1 = 34;
    doc.insertRawEvent(smfTrack, payload);

    SmfEvent sel2;
    sel2.tick = scenario.base + 3 * scenario.step;
    sel2.status = status;
    sel2.data0 = xcmd::kSelectorController;
    sel2.data1 = 0x09;
    doc.insertRawEvent(smfTrack, sel2);

    const QByteArray liveSmfBytes = doc.smf().write();
    const int liveUndoIndex = doc.undoStack()->index();
    const bool liveDirty = doc.isDirty();

    const SongSaveSnapshot snapshot = doc.captureSaveSnapshot();

    if (doc.smf().write() != liveSmfBytes)
        scenario.fail("captureSaveSnapshot mutated live SMF bytes");
    if (doc.undoStack()->index() != liveUndoIndex)
        scenario.fail("captureSaveSnapshot mutated undo index");
    if (doc.isDirty() != liveDirty)
        scenario.fail("captureSaveSnapshot mutated dirty state");

    if (smfTrack < 0 || size_t(smfTrack) >= snapshot.smf.tracks.size()) {
        scenario.fail("save snapshot missing SMF track");
        return;
    }
    const SmfTrack &snapTrack = snapshot.smf.tracks[size_t(smfTrack)];
    bool hasFirstSelector = false;
    bool hasDanglingSelector = false;
    std::vector<SmfEvent> payloadEvents;
    for (const SmfEvent &event : snapTrack.events) {
        if (event.tick == scenario.base + scenario.step && event.isChannel() &&
            event.data0 == xcmd::kSelectorController) {
            hasFirstSelector = true;
        } else if (event.tick == scenario.base + 2 * scenario.step && event.isChannel() &&
                   (event.data0 == xcmd::kSelectorController ||
                    event.data0 == xcmd::kPayloadController)) {
            payloadEvents.push_back(event);
        } else if (event.tick == scenario.base + 3 * scenario.step && event.isChannel() &&
                   event.data0 == xcmd::kSelectorController) {
            hasDanglingSelector = true;
        }
    }

    if (hasFirstSelector)
        scenario.fail("save snapshot retained delayed CC30 selector at first tick");
    if (payloadEvents.size() != 2 || payloadEvents[0].data0 != xcmd::kSelectorController ||
        payloadEvents[0].data1 != 0x08 || payloadEvents[1].data0 != xcmd::kPayloadController ||
        payloadEvents[1].data1 != 34) {
        scenario.fail(
            "save snapshot did not emit exact ordered CC30=0x08 then CC29=34 at payload tick");
    }
    if (hasDanglingSelector)
        scenario.fail("save snapshot retained dangling CC30 selector");
}

} // namespace editcheck
