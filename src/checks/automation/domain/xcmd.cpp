#include "checks/automation/domain/tst_automationdomain.h"

#include <limits>
#include <utility>
#include <vector>

#include <QtTest>

#include "core/xcmd.h"
#include "ui/editordrawer/cclanes.h"

namespace {

constexpr int kTrack = 0;

struct CcByte {
    uint64_t tick = 0;
    uint8_t controller = 0;
    uint8_t value = 0;

    bool operator==(const CcByte &) const = default;
};

std::vector<std::pair<uint8_t, uint8_t>> xcmdBytesAt(const SongDocument &document, int track,
                                                     uint64_t tick)
{
    std::vector<std::pair<uint8_t, uint8_t>> bytes;
    const int smfTrack = document.smfTrackFor(track);
    if (smfTrack < 0 || smfTrack >= int(document.smf().tracks.size()))
        return bytes;
    for (const SmfEvent &event : document.smf().tracks[std::size_t(smfTrack)].events) {
        if (event.tick == tick && event.typeNibble() == 0xB &&
            (event.data0 == xcmd::kSelectorController || event.data0 == xcmd::kPayloadController ||
             event.data0 == xcmd::kAlternatePayloadController)) {
            bytes.emplace_back(event.data0, event.data1);
        }
    }
    return bytes;
}

std::vector<std::pair<uint8_t, uint8_t>> xcmdBytes(const SongDocument &document, int track)
{
    std::vector<std::pair<uint8_t, uint8_t>> bytes;
    const int smfTrack = document.smfTrackFor(track);
    if (smfTrack < 0 || smfTrack >= int(document.smf().tracks.size()))
        return bytes;
    for (const SmfEvent &event : document.smf().tracks[std::size_t(smfTrack)].events) {
        if (event.typeNibble() == 0xB &&
            (event.data0 == xcmd::kSelectorController || event.data0 == xcmd::kPayloadController ||
             event.data0 == xcmd::kAlternatePayloadController)) {
            bytes.emplace_back(event.data0, event.data1);
        }
    }
    return bytes;
}

std::vector<CcByte> ccChain(const SongDocument &document, int track)
{
    std::vector<CcByte> bytes;
    const int smfTrack = document.smfTrackFor(track);
    if (smfTrack < 0 || smfTrack >= int(document.smf().tracks.size()))
        return bytes;
    for (const SmfEvent &event : document.smf().tracks[std::size_t(smfTrack)].events) {
        if (event.typeNibble() != 0xB)
            continue;
        if (event.data0 == 7 || event.data0 == 10 || event.data0 == xcmd::kSelectorController ||
            event.data0 == xcmd::kPayloadController ||
            event.data0 == xcmd::kAlternatePayloadController) {
            bytes.push_back({event.tick, event.data0, event.data1});
        }
    }
    return bytes;
}

std::vector<SmfEvent> notes(const SongDocument &document, int track)
{
    std::vector<SmfEvent> result;
    const int smfTrack = document.smfTrackFor(track);
    if (smfTrack < 0 || smfTrack >= int(document.smf().tracks.size()))
        return result;
    for (const SmfEvent &event : document.smf().tracks[std::size_t(smfTrack)].events) {
        if (event.isNoteOn() || event.isNoteEnd())
            result.push_back(event);
    }
    return result;
}

void clearXcmd(SongDocument &document)
{
    document.writeLanePoints(kTrack, DOC_CC_ECHO_VOLUME, 0, std::numeric_limits<uint64_t>::max(),
                             {});
    document.writeLanePoints(kTrack, DOC_CC_ECHO_LENGTH, 0, std::numeric_limits<uint64_t>::max(),
                             {});
}

void seedBaseline(SongDocument &document)
{
    document.writeLanePoints(kTrack, 10, 0, std::numeric_limits<uint64_t>::max(),
                             {{0, 80}, {384, 110}});
    document.writeLanePoints(kTrack, 7, 0, std::numeric_limits<uint64_t>::max(),
                             {{0, 64}, {288, 48}});
}

} // namespace

void AutomationDomainTest::xcmdCanonicalEdits()
{
    SongDocument &doc = document();
    const Snapshot before = snapshot();
    doc.addLanePoint(kTrack, DOC_CC_ECHO_VOLUME, 96, 34);
    doc.addLanePoint(kTrack, DOC_CC_ECHO_LENGTH, 96, 17);
    QVERIFY(samePoints(CCLaneAdapter(doc, kTrack, DOC_CC_ECHO_VOLUME).points(), {{96, 34}}));
    QVERIFY(samePoints(CCLaneAdapter(doc, kTrack, DOC_CC_ECHO_LENGTH).points(), {{96, 17}}));
    QVERIFY(xcmdBytesAt(doc, kTrack, 96) ==
            (std::vector<std::pair<uint8_t, uint8_t>>{{xcmd::kSelectorController, 0x08},
                                                      {xcmd::kPayloadController, 34},
                                                      {xcmd::kSelectorController, 0x09},
                                                      {xcmd::kPayloadController, 17}}));

    const Snapshot moveBefore = snapshot();
    const DocLanePoint volume = doc.lanePoints(kTrack, DOC_CC_ECHO_VOLUME).front();
    doc.moveLanePoints({{kTrack, DOC_CC_ECHO_VOLUME, volume, 192, 35}});
    QVERIFY(isOneEdit(moveBefore, snapshot()));
    QVERIFY(samePoints(CCLaneAdapter(doc, kTrack, DOC_CC_ECHO_VOLUME).points(), {{192, 35}}));
    QVERIFY(xcmdBytesAt(doc, kTrack, 192) ==
            (std::vector<std::pair<uint8_t, uint8_t>>{{xcmd::kSelectorController, 0x08},
                                                      {xcmd::kPayloadController, 35}}));

    doc.undoStack()->undo();
    doc.undoStack()->undo();
    doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), before.smf);
    QVERIFY(doc.lanePoints(kTrack, DOC_CC_ECHO_VOLUME).empty());
    QVERIFY(doc.lanePoints(kTrack, DOC_CC_ECHO_LENGTH).empty());
}

void AutomationDomainTest::xcmdOccurrencesAndOpaqueProtection()
{
    SongDocument &doc = document();
    doc.addLanePoint(kTrack, DOC_CC_ECHO_VOLUME, 96, 34);
    doc.addLanePoint(kTrack, DOC_CC_ECHO_VOLUME, 192, 35);
    auto volume = doc.lanePoints(kTrack, DOC_CC_ECHO_VOLUME);
    QVERIFY(volume.size() == 2);
    QVERIFY(xcmdBytesAt(doc, kTrack, 96) ==
            (std::vector<std::pair<uint8_t, uint8_t>>{{xcmd::kSelectorController, 0x08},
                                                      {xcmd::kPayloadController, 34}}));
    QVERIFY(xcmdBytesAt(doc, kTrack, 192) ==
            (std::vector<std::pair<uint8_t, uint8_t>>{{xcmd::kSelectorController, 0x08},
                                                      {xcmd::kPayloadController, 35}}));
    doc.deleteLanePoints(kTrack, DOC_CC_ECHO_VOLUME, {volume.front()});
    volume = doc.lanePoints(kTrack, DOC_CC_ECHO_VOLUME);
    QVERIFY(samePoints(CCLaneAdapter(doc, kTrack, DOC_CC_ECHO_VOLUME).points(), {{192, 35}}));
    QVERIFY(xcmdBytesAt(doc, kTrack, 96).empty());
    QVERIFY(xcmdBytesAt(doc, kTrack, 192) ==
            (std::vector<std::pair<uint8_t, uint8_t>>{{xcmd::kSelectorController, 0x08},
                                                      {xcmd::kPayloadController, 35}}));
    doc.deleteLanePoints(kTrack, DOC_CC_ECHO_VOLUME, {volume.front()});
    QVERIFY(doc.lanePoints(kTrack, DOC_CC_ECHO_VOLUME).empty());
    QVERIFY(xcmdBytes(doc, kTrack).empty());

    doc.addLanePoint(kTrack, DOC_CC_ECHO_VOLUME, 96, 34);
    doc.addLanePoint(kTrack, DOC_CC_ECHO_VOLUME, 192, 35);
    volume = doc.lanePoints(kTrack, DOC_CC_ECHO_VOLUME);
    doc.moveLanePoints({{kTrack, DOC_CC_ECHO_VOLUME, volume.front(), 384, 36}});
    QVERIFY(samePoints(CCLaneAdapter(doc, kTrack, DOC_CC_ECHO_VOLUME).points(),
                       {{192, 35}, {384, 36}}));
    QVERIFY(xcmdBytesAt(doc, kTrack, 192) ==
            (std::vector<std::pair<uint8_t, uint8_t>>{{xcmd::kSelectorController, 0x08},
                                                      {xcmd::kPayloadController, 35}}));
    QVERIFY(xcmdBytesAt(doc, kTrack, 384) ==
            (std::vector<std::pair<uint8_t, uint8_t>>{{xcmd::kSelectorController, 0x08},
                                                      {xcmd::kPayloadController, 36}}));

    clearXcmd(doc);
    doc.addLanePoint(kTrack, DOC_CC_ECHO_VOLUME, 96, 34);
    doc.addLanePoint(kTrack, DOC_CC_ECHO_LENGTH, 96, 17);
    doc.addLanePoint(kTrack, DOC_CC_ECHO_LENGTH, 192, 18);
    const DocLanePoint moveVolume = doc.lanePoints(kTrack, DOC_CC_ECHO_VOLUME).front();
    doc.moveLanePoints({{kTrack, DOC_CC_ECHO_VOLUME, moveVolume, 160, 36}});
    QVERIFY(samePoints(CCLaneAdapter(doc, kTrack, DOC_CC_ECHO_VOLUME).points(), {{160, 36}}));
    QVERIFY(xcmdBytesAt(doc, kTrack, 96) ==
            (std::vector<std::pair<uint8_t, uint8_t>>{{xcmd::kSelectorController, 0x09},
                                                      {xcmd::kPayloadController, 17}}));
    QVERIFY(xcmdBytesAt(doc, kTrack, 160) ==
            (std::vector<std::pair<uint8_t, uint8_t>>{{xcmd::kSelectorController, 0x08},
                                                      {xcmd::kPayloadController, 36}}));
    QVERIFY(xcmdBytesAt(doc, kTrack, 192) ==
            (std::vector<std::pair<uint8_t, uint8_t>>{{xcmd::kSelectorController, 0x09},
                                                      {xcmd::kPayloadController, 18}}));

    clearXcmd(doc);
    insertCc(doc, kTrack, xcmd::kSelectorController, 0, 0x01);
    insertCc(doc, kTrack, xcmd::kPayloadController, 1, 1);
    insertCc(doc, kTrack, xcmd::kPayloadController, 2, 2);
    const Snapshot opaqueBefore = snapshot();
    doc.addLanePoint(kTrack, DOC_CC_ECHO_VOLUME, 1, 30);
    QVERIFY(snapshot() == opaqueBefore);

    while (doc.undoStack()->index() > 0)
        doc.undoStack()->undo();
    insertCc(doc, kTrack, xcmd::kSelectorController, 4, 0x01);
    insertCc(doc, kTrack, xcmd::kPayloadController, 5, 1);
    insertCc(doc, kTrack, xcmd::kPayloadController, 6, 2);
    insertCc(doc, kTrack, xcmd::kSelectorController, 8, 0x03);
    insertCc(doc, kTrack, xcmd::kPayloadController, 9, 99);
    const Snapshot malformedBefore = snapshot();
    doc.addLanePoint(kTrack, DOC_CC_ECHO_VOLUME, 400, 30);
    QVERIFY(isOneEdit(malformedBefore, snapshot()));
    QVERIFY(xcmdBytes(doc, kTrack) ==
            (std::vector<std::pair<uint8_t, uint8_t>>{{xcmd::kSelectorController, 0x01},
                                                      {xcmd::kPayloadController, 1},
                                                      {xcmd::kPayloadController, 2},
                                                      {xcmd::kSelectorController, 0x03},
                                                      {xcmd::kPayloadController, 99},
                                                      {xcmd::kSelectorController, 0x08},
                                                      {xcmd::kPayloadController, 30}}));
    const Snapshot rejectedBefore = snapshot();
    doc.writeLanePoints(kTrack, DOC_CC_ECHO_VOLUME, 8, 8, {{8, 30}});
    QVERIFY(snapshot() == rejectedBefore);
}

void AutomationDomainTest::xcmdTimeRangeCuts()
{
    SongDocument &doc = document();
    doc.addLanePoint(kTrack, DOC_CC_ECHO_VOLUME, 96, 34);
    doc.addLanePoint(kTrack, DOC_CC_ECHO_LENGTH, 96, 17);
    const Snapshot rangeBefore = snapshot();
    SongDocument::TimeScope volumeScope;
    volumeScope.lanes = {{kTrack, DOC_CC_ECHO_VOLUME}};
    QVERIFY(doc.removeTimeRange({96, 192}, volumeScope));
    QVERIFY(doc.lanePoints(kTrack, DOC_CC_ECHO_VOLUME).empty());
    QVERIFY(xcmdBytesAt(doc, kTrack, 96) ==
            (std::vector<std::pair<uint8_t, uint8_t>>{{xcmd::kSelectorController, 0x09},
                                                      {xcmd::kPayloadController, 17}}));
    doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), rangeBefore.smf);

    doc.undoStack()->redo();
    doc.undoStack()->undo();
    clearXcmd(doc);
    doc.addLanePoint(kTrack, DOC_CC_ECHO_VOLUME, 96, 34);
    doc.addLanePoint(kTrack, DOC_CC_ECHO_LENGTH, 96, 17);
    doc.addLanePoint(kTrack, DOC_CC_ECHO_LENGTH, 192, 18);
    const Snapshot cutBefore = snapshot();
    SongDocument::TimeScope wholeSong;
    wholeSong.wholeSong = true;
    QVERIFY(doc.removeTimeRange({96, 192}, wholeSong));
    QVERIFY(doc.lanePoints(kTrack, DOC_CC_ECHO_VOLUME).empty());
    QVERIFY(samePoints(CCLaneAdapter(doc, kTrack, DOC_CC_ECHO_LENGTH).points(), {{96, 18}}));
    QVERIFY(xcmdBytesAt(doc, kTrack, 96) ==
            (std::vector<std::pair<uint8_t, uint8_t>>{{xcmd::kSelectorController, 0x09},
                                                      {xcmd::kPayloadController, 18}}));
    doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), cutBefore.smf);
    doc.undoStack()->redo();
    QVERIFY(doc.lanePoints(kTrack, DOC_CC_ECHO_VOLUME).empty());
    QVERIFY(samePoints(CCLaneAdapter(doc, kTrack, DOC_CC_ECHO_LENGTH).points(), {{96, 18}}));
}

void AutomationDomainTest::xcmdSweepPreservesNotes()
{
    SongDocument &doc = document();
    const Snapshot before = snapshot();
    constexpr uint64_t kDragBegin = 8736;
    constexpr uint64_t kNoteBegin = 8772;
    constexpr uint64_t kNoteEnd = 8808;
    constexpr uint64_t kExistingPoint = 8844;
    SmfEvent noteOn{.tick = kNoteBegin,
                    .status = uint8_t(0x90 | (doc.channelFor(kTrack) & 0x0F)),
                    .data0 = 60,
                    .data1 = 100};
    SmfEvent noteOff = noteOn;
    noteOff.tick = kNoteEnd;
    noteOff.status = uint8_t(0x80 | (doc.channelFor(kTrack) & 0x0F));
    noteOff.data1 = 0;
    doc.insertRawEvent(doc.smfTrackFor(kTrack), noteOn);
    doc.insertRawEvent(doc.smfTrackFor(kTrack), noteOff);
    doc.addLanePoint(kTrack, DOC_CC_ECHO_VOLUME, kExistingPoint, 48);
    const std::vector<SmfEvent> beforeSweepNotes = notes(doc, kTrack);

    CCLaneAdapter lane(doc, kTrack, DOC_CC_ECHO_VOLUME);
    lane.replaceSpan(kDragBegin, kExistingPoint, {{kDragBegin, 32}, {kExistingPoint, 48}});
    QVERIFY(notes(doc, kTrack) == beforeSweepNotes);
    QVERIFY(samePoints(lane.points(), {{kDragBegin, 32}, {kExistingPoint, 48}}));

    while (doc.undoStack()->index() > before.undoIndex)
        doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), before.smf);
}

void AutomationDomainTest::xcmdRangeRemoveOnly()
{
    SongDocument &doc = document();
    doc.addLanePoint(kTrack, DOC_CC_ECHO_VOLUME, 96, 34);
    doc.addLanePoint(kTrack, DOC_CC_ECHO_VOLUME, 192, 35);
    doc.addLanePoint(kTrack, DOC_CC_ECHO_LENGTH, 96, 17);
    seedBaseline(doc);
    const Snapshot before = snapshot();
    SongDocument::RangeEdit edit;
    edit.removePoints.push_back(doc.lanePoints(kTrack, DOC_CC_ECHO_VOLUME).front());
    edit.removePoints.push_back(doc.lanePoints(kTrack, DOC_CC_ECHO_LENGTH).front());
    doc.applyRangeEdit(QStringLiteral("xcmd remove-only"), edit);
    QVERIFY(isOneEdit(before, snapshot()));
    const Snapshot after = snapshot();
    QVERIFY(samePoints(CCLaneAdapter(doc, kTrack, DOC_CC_ECHO_VOLUME).points(), {{192, 35}}));
    QVERIFY(doc.lanePoints(kTrack, DOC_CC_ECHO_LENGTH).empty());
    QVERIFY(ccChain(doc, kTrack) == (std::vector<CcByte>{{0, 0x0A, 80},
                                                         {0, 0x07, 64},
                                                         {192, xcmd::kSelectorController, 0x08},
                                                         {192, xcmd::kPayloadController, 35},
                                                         {288, 0x07, 48},
                                                         {384, 0x0A, 110}}));
    doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), before.smf);
    doc.undoStack()->redo();
    QCOMPARE(snapshot().smf, after.smf);
}

void AutomationDomainTest::xcmdRangeMoves()
{
    SongDocument &doc = document();
    doc.addLanePoint(kTrack, DOC_CC_ECHO_LENGTH, 96, 17);
    doc.addLanePoint(kTrack, DOC_CC_ECHO_LENGTH, 192, 18);
    doc.addLanePoint(kTrack, DOC_CC_ECHO_VOLUME, 192, 34);
    seedBaseline(doc);
    const Snapshot leftBefore = snapshot();
    doc.moveRange({}, doc.lanePoints(kTrack, DOC_CC_ECHO_VOLUME), -48);
    QVERIFY(isOneEdit(leftBefore, snapshot()));
    const Snapshot leftAfter = snapshot();
    QVERIFY(ccChain(doc, kTrack) == (std::vector<CcByte>{{0, 0x0A, 80},
                                                         {0, 0x07, 64},
                                                         {96, xcmd::kSelectorController, 0x09},
                                                         {96, xcmd::kPayloadController, 17},
                                                         {144, xcmd::kSelectorController, 0x08},
                                                         {144, xcmd::kPayloadController, 34},
                                                         {192, xcmd::kSelectorController, 0x09},
                                                         {192, xcmd::kPayloadController, 18},
                                                         {288, 0x07, 48},
                                                         {384, 0x0A, 110}}));
    doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), leftBefore.smf);
    doc.undoStack()->redo();
    QCOMPARE(snapshot().smf, leftAfter.smf);

    clearXcmd(doc);
    doc.addLanePoint(kTrack, DOC_CC_ECHO_LENGTH, 96, 17);
    doc.addLanePoint(kTrack, DOC_CC_ECHO_LENGTH, 192, 18);
    doc.addLanePoint(kTrack, DOC_CC_ECHO_VOLUME, 96, 34);
    const Snapshot rightBefore = snapshot();
    doc.moveRange({}, doc.lanePoints(kTrack, DOC_CC_ECHO_VOLUME), 96);
    QVERIFY(isOneEdit(rightBefore, snapshot()));
    const Snapshot rightAfter = snapshot();
    QVERIFY(ccChain(doc, kTrack) == (std::vector<CcByte>{{0, 0x0A, 80},
                                                         {0, 0x07, 64},
                                                         {96, xcmd::kSelectorController, 0x09},
                                                         {96, xcmd::kPayloadController, 17},
                                                         {192, xcmd::kSelectorController, 0x09},
                                                         {192, xcmd::kPayloadController, 18},
                                                         {192, xcmd::kSelectorController, 0x08},
                                                         {192, xcmd::kPayloadController, 34},
                                                         {288, 0x07, 48},
                                                         {384, 0x0A, 110}}));
    doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), rightBefore.smf);
    doc.undoStack()->redo();
    QCOMPARE(snapshot().smf, rightAfter.smf);
}

void AutomationDomainTest::xcmdExpansionPaste()
{
    SongDocument &doc = document();
    const int newTrack = doc.engineTrackCount();
    const Snapshot before = snapshot();
    SongDocument::RangeEdit edit;
    edit.minimumEngineTrackCount = newTrack + 1;
    edit.addNotes.push_back({newTrack, {{0, 60, 96, 100}}});
    edit.addPoints.push_back({newTrack, DOC_CC_ECHO_VOLUME, {{96, 34}}});
    doc.applyRangeEdit(QStringLiteral("xcmd expansion paste"), edit);
    QVERIFY(isOneEdit(before, snapshot()));
    const Snapshot after = snapshot();
    QCOMPARE(doc.engineTrackCount(), newTrack + 1);
    QVERIFY(samePoints(CCLaneAdapter(doc, newTrack, DOC_CC_ECHO_VOLUME).points(), {{96, 34}}));
    QVERIFY(ccChain(doc, newTrack) == (std::vector<CcByte>{{96, xcmd::kSelectorController, 0x08},
                                                           {96, xcmd::kPayloadController, 34}}));
    doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), before.smf);
    doc.undoStack()->redo();
    QCOMPARE(snapshot().smf, after.smf);
}
