#include <QTemporaryDir>

#include <array>
#include <iterator>
#include <vector>

#include <cstdio>

#include "core/miditimeline.h"

#include "checks/editcheck/support.h"

namespace editcheck {

int timeRangeContractFailures()
{
    int failures = 0;
    const auto fail = [&failures](const char *what) {
        std::fprintf(stderr, "editcheck: FAIL time-range-contracts: %s\n", what);
        failures++;
    };
    const auto channel = [](uint8_t status, uint64_t tick, uint8_t data0, uint8_t data1) {
        SmfEvent event;
        event.tick = tick;
        event.status = status;
        event.data0 = data0;
        event.data1 = data1;
        return event;
    };
    const auto meta = [](uint8_t type, uint64_t tick, const QByteArray &blob) {
        SmfEvent event;
        event.tick = tick;
        event.status = 0xFF;
        event.metaType = type;
        event.blob = blob;
        return event;
    };
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;
    smf.tracks.push_back({{}, 200});
    smf.tracks.push_back({{channel(0xC0, 0, 1, 0)}, 200});
    smf.tracks.push_back({{channel(0xC1, 0, 2, 0)}, 200});
    QTemporaryDir temporary;
    QString error;
    SongInfo info;
    info.label = QStringLiteral("time-range-contracts");
    info.midPath = temporary.path() + QStringLiteral("/time-range.mid");
    info.hasMid = true;
    SongDocument doc;
    if (!temporary.isValid() || !smf.writeFile(info.midPath, &error) || !doc.load(info, &error)) {
        fail("could not write/load the time-range fixture");
        return failures;
    }
    const auto expect = [&fail](bool condition, const char *what) {
        if (!condition)
            fail(what);
    };
    const auto noteEndsBeforeOnsAt = [&doc](int engineTrack, uint64_t tick) {
        const int smfTrack = doc.smfTrackFor(engineTrack);
        if (smfTrack < 0)
            return true;
        bool sawNoteOn = false;
        for (const SmfEvent &event : doc.smf().tracks[size_t(smfTrack)].events) {
            if (event.tick != tick || !event.isChannel())
                continue;
            if (event.isNoteOn())
                sawNoteOn = true;
            else if (event.isNoteEnd() && sawNoteOn)
                return false;
        }
        return true;
    };
    const auto checkNoOp =
        [&doc, &fail](const SongDocument::TimeRange &range, const SongDocument::TimeScope &scope,
                      bool (SongDocument::*operation)(const SongDocument::TimeRange &,
                                                      const SongDocument::TimeScope &),
                      const char *what) {
            const QByteArray before = doc.smf().write();
            const auto beforeTempo = doc.tempoPoints();
            const int undoCount = doc.undoStack()->count();
            if ((doc.*operation)(range, scope) || doc.smf().write() != before ||
                doc.tempoPoints() != beforeTempo || doc.undoStack()->count() != undoCount)
                fail(what);
        };
    SongDocument::TimeScope emptyScope;
    checkNoOp({20, 20}, emptyScope, &SongDocument::removeTimeRange,
              "empty remove range/scope was not a no-op");
    checkNoOp({20, 10}, emptyScope, &SongDocument::insertBlankTime,
              "backward insert range/scope was not a no-op");
    checkNoOp({20, 10}, emptyScope, &SongDocument::duplicateTimeRange,
              "backward duplicate range/scope was not a no-op");
    SongDocument::TimeScope invalidScope;
    invalidScope.tracks = {99};
    checkNoOp({20, 30}, invalidScope, &SongDocument::removeTimeRange,
              "invalid remove scope was not a no-op");
    checkNoOp({20, 30}, invalidScope, &SongDocument::insertBlankTime,
              "invalid insert scope was not a no-op");
    checkNoOp({20, 30}, invalidScope, &SongDocument::duplicateTimeRange,
              "invalid duplicate scope was not a no-op");

    const auto checkRoundTrip =
        [&doc, &fail](const SongDocument::TimeRange &range, const SongDocument::TimeScope &scope,
                      bool (SongDocument::*operation)(const SongDocument::TimeRange &,
                                                      const SongDocument::TimeScope &),
                      const char *what) {
            const QByteArray before = doc.smf().write();
            const auto beforeTempo = doc.tempoPoints();
            const int undoCount = doc.undoStack()->count();
            if (!(doc.*operation)(range, scope)) {
                fail(what);
                return false;
            }
            const QByteArray after = doc.smf().write();
            const auto afterTempo = doc.tempoPoints();
            if (doc.undoStack()->count() != undoCount + 1) {
                fail("time edit pushed more than one undo command");
                return false;
            }
            doc.undoStack()->undo();
            if (doc.smf().write() != before) {
                fail("time edit undo did not restore exact SMF bytes");
                return false;
            }
            if (doc.tempoPoints() != beforeTempo) {
                fail("time edit undo did not restore tempo points");
                return false;
            }
            doc.undoStack()->redo();
            if (doc.smf().write() != after || doc.tempoPoints() != afterTempo) {
                fail("time edit redo did not restore exact document state");
                return false;
            }
            return true;
        };

    SongDocument::TimeScope trackScope;
    trackScope.tracks = {0};
    doc.addNote(0, 35, 60, 10, 90);
    doc.addNote(0, 60, 61, 5, 80);
    DocNote crossing, later;
    expect(doc.findNote(0, 35, 60, &crossing) && doc.findNote(0, 60, 61, &later),
           "insert fixture notes were not created");
    const NoteId laterId = later.noteId;
    if (checkRoundTrip({40, 45}, trackScope, &SongDocument::insertBlankTime,
                       "blank insertion did not commit")) {
        DocNote left, right, shifted;
        expect(doc.findNote(0, 35, 60, &left) && left.duration == 5 &&
                   doc.findNote(0, 45, 60, &right) && right.duration == 5 &&
                   doc.findNote(0, 65, 61, &shifted) && shifted.noteId == laterId,
               "blank insertion did not split the crossing note and shift the later note");
    }

    doc.addLanePoint(0, 7, 300, 10);
    doc.addLanePoint(0, 10, 300, 20);
    doc.addLanePoint(1, 7, 300, 30);
    SongDocument::TimeScope laneScope;
    laneScope.lanes = {{0, 7}};
    const uint64_t laneEndBefore = doc.smf().tracks[1].endTick;
    if (checkRoundTrip({300, 320}, laneScope, &SongDocument::insertBlankTime,
                       "lane-only blank insertion did not commit")) {
        DocLanePoint point;
        expect(doc.findLanePoint(0, 7, 320, &point) && point.value == 10 &&
                   doc.findLanePoint(0, 10, 300, &point) && point.value == 20 &&
                   doc.findLanePoint(1, 7, 300, &point) && point.value == 30 &&
                   doc.smf().tracks[1].endTick == laneEndBefore + 20,
               "lane-only insertion leaked into another lane or track or missed EOT");
    }
    doc.addNote(0, 400, 62, 5, 90);
    doc.addNote(1, 400, 63, 5, 90);
    doc.addLanePoint(0, 7, 400, 40);
    doc.addLanePoint(1, 7, 400, 50);
    const uint64_t selectedEndBefore = doc.smf().tracks[1].endTick;
    const uint64_t untouchedEndBefore = doc.smf().tracks[2].endTick;
    if (checkRoundTrip({400, 420}, trackScope, &SongDocument::insertBlankTime,
                       "track blank insertion did not commit")) {
        DocNote shiftedTrack, untouchedTrack;
        expect(doc.findNote(0, 420, 62, &shiftedTrack) &&
                   doc.findNote(1, 400, 63, &untouchedTrack) &&
                   doc.smf().tracks[1].endTick == selectedEndBefore + 20 &&
                   doc.smf().tracks[2].endTick == untouchedEndBefore,
               "track insertion did not isolate the named engine track");
    }
    if (!doc.load(info, &error)) {
        fail("could not reload for the unterminated-note fixture");
        return failures;
    }
    const int noteSmfTrack = doc.smfTrackFor(0);
    doc.insertRawEvent(noteSmfTrack, channel(0x90, 220, 68, 77));
    DocNote unterminated;
    expect(doc.findNote(0, 220, 68, &unterminated) && unterminated.unterminated(),
           "unterminated-note fixture was not created");
    const NoteId leftNoteId = unterminated.noteId;
    if (checkRoundTrip({240, 250}, trackScope, &SongDocument::insertBlankTime,
                       "unterminated blank insertion did not commit")) {
        DocNote left, right;
        bool leftBytesPreserved = false;
        bool rightBytesPreserved = false;
        bool matchingOff = false;
        for (const SmfEvent &event : doc.smf().tracks[size_t(noteSmfTrack)].events) {
            if (event.tick == 220 && event.status == 0x90 && event.data0 == 68 && event.data1 == 77)
                leftBytesPreserved = true;
            if (event.tick == 240 && event.status == 0x80 && event.data0 == 68 && event.data1 == 0)
                matchingOff = true;
            if (event.tick == 250 && event.status == 0x90 && event.data0 == 68 && event.data1 == 77)
                rightBytesPreserved = true;
        }
        expect(doc.findNote(0, 220, 68, &left) && !left.unterminated() && left.duration == 20 &&
                   doc.findNote(0, 250, 68, &right) && right.unterminated() &&
                   left.noteId == leftNoteId && right.noteId != left.noteId && leftBytesPreserved &&
                   matchingOff && rightBytesPreserved,
               "unterminated note was not silenced and resumed with a fresh raw note-on");
    }

    const uint64_t duplicateStart = 600;
    doc.addNote(0, duplicateStart + 10, 64, 10, 90); // contained, ends at e
    doc.addNote(0, duplicateStart - 5, 65, 15, 80);  // crosses s only
    doc.addNote(0, duplicateStart + 10, 66, 20, 70); // crosses e only
    doc.addNote(0, duplicateStart - 5, 67, 30, 60);  // crosses both
    DocNote contained, leftCrossing, rightCrossing, bothCrossing;
    expect(doc.findNote(0, duplicateStart + 10, 64, &contained) &&
               doc.findNote(0, duplicateStart - 5, 65, &leftCrossing) &&
               doc.findNote(0, duplicateStart + 10, 66, &rightCrossing) &&
               doc.findNote(0, duplicateStart - 5, 67, &bothCrossing),
           "duplicate boundary fixture notes were not created");
    const std::array<NoteId, 4> originalIds = {contained.noteId, leftCrossing.noteId,
                                               rightCrossing.noteId, bothCrossing.noteId};
    if (checkRoundTrip({duplicateStart, duplicateStart + 20}, trackScope,
                       &SongDocument::duplicateTimeRange, "time-range duplicate did not commit")) {
        DocNote copyContained, copyLeft, copyRight, copyBoth;
        expect(doc.findNote(0, duplicateStart + 30, 64, &copyContained) &&
                   copyContained.duration == 10 &&
                   doc.findNote(0, duplicateStart + 20, 65, &copyLeft) && copyLeft.duration == 10 &&
                   doc.findNote(0, duplicateStart + 30, 66, &copyRight) &&
                   copyRight.duration == 10 &&
                   doc.findNote(0, duplicateStart + 20, 67, &copyBoth) && copyBoth.duration == 20,
               "duplicate did not clip contained and boundary-crossing notes");
        const std::array<NoteId, 4> copiedIds = {copyContained.noteId, copyLeft.noteId,
                                                 copyRight.noteId, copyBoth.noteId};
        for (size_t i = 0; i < copiedIds.size(); i++) {
            for (size_t j = i + 1; j < copiedIds.size(); j++)
                expect(copiedIds[i] != copiedIds[j], "duplicated note-ons shared a NoteId");
            for (const NoteId id : originalIds)
                expect(copiedIds[i] != id, "duplicated note-on preserved an original NoteId");
        }
    }
    if (!doc.load(info, &error)) {
        fail("could not reload for canonical time-edit ordering");
        return failures;
    }
    const int canonicalTrack = doc.smfTrackFor(0);
    doc.insertRawEvent(canonicalTrack, channel(0x80, 700, 72, 0));
    doc.insertRawEvent(canonicalTrack, channel(0x90, 700, 72, 55));
    if (checkRoundTrip({700, 720}, trackScope, &SongDocument::duplicateTimeRange,
                       "canonical duplicate did not commit"))
        expect(noteEndsBeforeOnsAt(0, 720),
               "duplicate did not canonicalize same-tick note-end before note-on");
    doc.insertRawEvent(canonicalTrack, channel(0x80, 800, 73, 0));
    doc.insertRawEvent(canonicalTrack, channel(0x90, 800, 73, 66));
    if (checkRoundTrip({800, 820}, trackScope, &SongDocument::insertBlankTime,
                       "canonical split did not commit"))
        expect(noteEndsBeforeOnsAt(0, 820),
               "split did not canonicalize same-tick note-end before note-on");

    if (!doc.load(info, &error)) {
        fail("could not reload the clean time-range fixture");
        return failures;
    }
    const int orphanTrack = doc.smfTrackFor(0);
    doc.addNote(0, 40, 60, 10, 90);
    doc.insertRawEvent(orphanTrack, channel(0x90, 90, 61, 11));
    doc.insertRawEvent(orphanTrack, channel(0x80, 120, 66, 13));
    doc.insertRawEvent(orphanTrack, channel(0x90, 110, 62, 22));
    doc.insertRawEvent(orphanTrack, channel(0x80, 130, 63, 12));
    doc.insertRawEvent(orphanTrack, channel(0x90, 130, 64, 33));
    doc.insertRawEvent(orphanTrack, channel(0x90, 140, 65, 44));
    if (checkRoundTrip({100, 130}, trackScope, &SongDocument::removeTimeRange,
                       "orphan-note remove did not commit")) {
        bool beforeBytes = false;
        bool removedBytes = false;
        bool endBytes = false;
        bool removedEnd = false;
        bool endOnBytes = false;
        bool afterBytes = false;
        for (const SmfEvent &event : doc.smf().tracks[size_t(orphanTrack)].events) {
            if (event.tick == 90 && event.status == 0x90 && event.data0 == 61 && event.data1 == 11)
                beforeBytes = true;
            if (event.tick == 110 && event.status == 0x90 && event.data0 == 62 && event.data1 == 22)
                removedBytes = true;
            if (event.status == 0x80 && event.data0 == 66 && event.data1 == 13)
                removedEnd = true;
            if (event.tick == 100 && event.status == 0x80 && event.data0 == 63 && event.data1 == 12)
                endBytes = true;
            if (event.tick == 100 && event.status == 0x90 && event.data0 == 64 && event.data1 == 33)
                endOnBytes = true;
            if (event.tick == 110 && event.status == 0x90 && event.data0 == 65 && event.data1 == 44)
                afterBytes = true;
        }
        DocNote paired;
        expect(beforeBytes && !removedBytes && endBytes && endOnBytes && afterBytes &&
                   !removedEnd && noteEndsBeforeOnsAt(0, 100) && doc.findNote(0, 40, 60, &paired) &&
                   !paired.unterminated() && paired.duration == 10,
               "orphan note events did not close half-open without double-handling paired notes");
    }
    if (!doc.load(info, &error)) {
        fail("could not reload after orphan-note remove");
        return failures;
    }

    const uint64_t seamStart = 1000;
    doc.addLanePoint(0, 7, seamStart - 20, 33);
    doc.addLanePoint(0, 7, seamStart + 10, 44);
    if (checkRoundTrip({seamStart, seamStart + 40}, laneScope, &SongDocument::duplicateTimeRange,
                       "automation seam duplicate did not commit")) {
        DocLanePoint point;
        expect(doc.findLanePoint(0, 7, seamStart + 40, &point) && point.value == 33 &&
                   doc.findLanePoint(0, 7, seamStart + 50, &point) && point.value == 44,
               "automation duplicate did not preserve the effective seam value");
    }
    if (!doc.load(info, &error)) {
        fail("could not reload before implicit-default checks");
        return failures;
    }
    struct DefaultCase {
        uint8_t cc;
        int sourceValue;
        int expected;
    };
    const DefaultCase defaults[] = {
        {0x01, 11, 0}, {0x05, 12, 0}, {0x07, 80, 127}, {0x0A, 81, 64},        {0x14, 3, 2},
        {0x15, 4, 22}, {0x17, 5, 0},  {0x19, 6, 0},    {DOC_CC_BEND, 500, 0},
    };
    for (size_t remaining = std::size(defaults); remaining > 0; --remaining) {
        const size_t i = remaining - 1;
        const uint64_t start = 1100 + i * 40;
        doc.addLanePoint(0, defaults[i].cc, start + 10, defaults[i].sourceValue);
        SongDocument::TimeScope defaultLane;
        defaultLane.lanes = {{0, defaults[i].cc}};
        if (checkRoundTrip({start, start + 20}, defaultLane, &SongDocument::duplicateTimeRange,
                           "implicit automation default duplicate did not commit")) {
            DocLanePoint point;
            expect(doc.findLanePoint(0, defaults[i].cc, start + 20, &point) &&
                       point.value == defaults[i].expected,
                   "duplicate did not use the shared implicit automation default");
        }
    }
    const uint64_t tempoStart = 1500;
    SongDocument::TimeScope tempoScope;
    tempoScope.tempo = true;
    doc.applyTempoEdit({{tempoPoint(0, 120)}, {tempoPoint(tempoStart + 10, 150)}});
    if (checkRoundTrip({tempoStart, tempoStart + 20}, tempoScope, &SongDocument::duplicateTimeRange,
                       "tempo default duplicate did not commit")) {
        expect(containsTempoPoint(doc, tempoPoint(tempoStart + 20, 120)) &&
                   containsTempoPoint(doc, tempoPoint(tempoStart + 30, 150)),
               "tempo duplicate did not use the 120 BPM default");
    }
    auto timeline = doc.buildTimeline(44100.0);
    expect(timeline && !timeline->tempoMap.empty() && timeline->tempoMap.front().bpm == 120.0,
           "timeline tempo map did not retain the 120 BPM implicit default");
    doc.addLanePoint(0, DOC_CC_VOICE, 1610, 12);
    SongDocument::TimeScope voiceScope;
    voiceScope.lanes = {{0, DOC_CC_VOICE}};
    if (checkRoundTrip({1600, 1620}, voiceScope, &SongDocument::duplicateTimeRange,
                       "voice duplicate did not commit")) {
        DocLanePoint voice;
        expect(doc.findLanePoint(0, DOC_CC_VOICE, 1620, &voice) && voice.value == 1 &&
                   doc.findLanePoint(0, DOC_CC_VOICE, 1630, &voice) && voice.value == 12,
               "voice duplicate did not preserve the authored program state");
    }

    const uint64_t downstreamStart = 1700;
    doc.addLanePoint(0, 7, downstreamStart, 11);
    doc.addLanePoint(0, 7, downstreamStart + 20, 99);
    if (checkRoundTrip({downstreamStart, downstreamStart + 20}, laneScope,
                       &SongDocument::duplicateTimeRange,
                       "downstream boundary duplicate did not commit")) {
        DocLanePoint point;
        expect(doc.findLanePoint(0, 7, downstreamStart + 20, &point) && point.value == 11 &&
                   doc.findLanePoint(0, 7, downstreamStart + 40, &point) && point.value == 99,
               "event at duplicate end was copied instead of shifted downstream");
    }
    if (!doc.load(info, &error)) {
        fail("could not reload before whole-song duplicate");
        return failures;
    }

    doc.addNote(0, 1900, 70, 5, 50);
    const uint64_t globalStart = 1800;
    doc.setTimeSig(globalStart + 10, 3, 2);
    doc.applyTempoEdit({{}, {tempoPoint(globalStart + 10, 180)}});
    doc.insertRawEvent(0, meta(0x01, globalStart + 15, QByteArrayLiteral("global")));
    SongDocument::TimeScope wholeSong;
    wholeSong.wholeSong = true;
    if (checkRoundTrip({globalStart, globalStart + 20}, wholeSong,
                       &SongDocument::duplicateTimeRange, "whole-song duplicate did not commit")) {
        bool copiedMeta = false;
        for (const SmfEvent &event : doc.smf().tracks[0].events) {
            if (event.tick == globalStart + 35 && event.isMeta() && event.metaType == 0x01 &&
                event.blob == QByteArrayLiteral("global"))
                copiedMeta = true;
        }
        bool copiedSig = false;
        for (const DocTimeSig &sig : doc.timeSigs()) {
            if (sig.tick == globalStart + 30 && sig.numerator == 3)
                copiedSig = true;
        }
        DocNote shiftedNote;
        const int noteTrack = doc.smfTrackFor(0);
        expect(copiedMeta && copiedSig &&
                   containsTempoPoint(doc, tempoPoint(globalStart + 20, 120)) &&
                   containsTempoPoint(doc, tempoPoint(globalStart + 30, 180)) &&
                   doc.findNote(0, 1920, 70, &shiftedNote) && noteTrack >= 0 &&
                   doc.smf().tracks[size_t(noteTrack)].endTick >=
                       shiftedNote.tick + shiftedNote.duration,
               "whole-song duplicate mishandled globals or track ends");
    }
    return failures;
}
} // namespace editcheck
