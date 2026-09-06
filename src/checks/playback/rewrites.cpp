#include <QTest>
#include <vector>

#include "checks/playback/tst_xcmd.h"

namespace checks {

// Add on an empty track: canonical selector support + payload, both on the
// requested channel.
void XcmdTest::addOnEmptyTrackEmitsCanonicalPair()
{
    const std::vector<xcmd::PointWrite> writes = {{5, xcmd::kEchoVolumeLane, 40, 0, 7}};
    const auto patch = xcmd::rewritePoints({}, {}, writes);
    QVERIFY2(patch && patch->removeEvents.empty() && patch->inserts.size() == 2 &&
                 patch->inserts[0].tick == 5 &&
                 patch->inserts[0].controller == xcmd::kSelectorController &&
                 patch->inserts[0].value == 0x08 && patch->inserts[0].channel == 7 &&
                 patch->inserts[1].controller == xcmd::kPayloadController &&
                 patch->inserts[1].value == 40,
             "add did not emit canonical selector+payload");
}

// Add under already-active matching state still emits a full explicit pair:
// no selector reuse ever.
void XcmdTest::addUnderActiveStateEmitsFullPair()
{
    const auto events = makeEvents(ev(0, 1, 0, xcmd::kSelectorController, 0x08),
                                   ev(1, 2, 0, xcmd::kPayloadController, 34));
    const std::vector<xcmd::PointWrite> writes = {{5, xcmd::kEchoVolumeLane, 40, 0, 7}};
    const auto patch = xcmd::rewritePoints(events, {}, writes);
    QVERIFY2(patch && patch->inserts.size() == 2 &&
                 patch->inserts[0].controller == xcmd::kSelectorController &&
                 patch->inserts[0].value == 0x08 &&
                 patch->inserts[1].controller == xcmd::kPayloadController &&
                 patch->removeEvents.empty(),
             "write did not emit a self-contained pair under active state");
}

// Replace the point on a tick: its whole epoch is rebuilt; the survivor set
// is empty so only the write's canonical pair lands.
void XcmdTest::replaceRebuildsEpochWithExplicitPair()
{
    const auto events = makeEvents(ev(0, 1, 0, xcmd::kSelectorController, 0x08),
                                   ev(1, 2, 0, xcmd::kPayloadController, 34));
    const std::vector<xcmd::PointWrite> writes = {{2, xcmd::kEchoVolumeLane, 40, 0, 7}};
    const auto patch = xcmd::rewritePoints(events, {}, writes);
    QVERIFY2(patch && patch->removeEvents == std::vector<uint64_t>({0, 1}) &&
                 patch->inserts.size() == 2 && patch->inserts[0].value == 0x08 &&
                 patch->inserts[1].value == 40,
             "replace did not rebuild the epoch with an explicit pair");
}

// Delete one of two points sharing a selector: the epoch is rebuilt and the
// survivor is re-emitted as its own explicit pair (no shared selector
// output).
void XcmdTest::deleteSharedPointRebuildsSurvivorAsPair()
{
    const auto events = makeEvents(ev(0, 1, 0, xcmd::kSelectorController, 0x08),
                                   ev(1, 2, 0, xcmd::kPayloadController, 34),
                                   ev(2, 3, 0, xcmd::kPayloadController, 35));
    const xcmd::Projection projection = project(events);
    const std::vector<uint64_t> removeIdentities = {projection.points[0].index};
    const auto patch = xcmd::rewritePoints(events, removeIdentities, {});
    QVERIFY2(patch && patch->removeEvents == std::vector<uint64_t>({0, 1, 2}) &&
                 patch->inserts.size() == 2 && patch->inserts[0].tick == 3 &&
                 patch->inserts[0].value == 0x08 && patch->inserts[1].value == 35,
             "deleting one shared point did not rebuild the survivor as a pair");
}

// Delete the last point of an epoch: the whole epoch leaves, nothing is
// inserted.
void XcmdTest::deleteLastPointRemovesDeadEpoch()
{
    const auto events = makeEvents(ev(0, 1, 0, xcmd::kSelectorController, 0x08),
                                   ev(1, 2, 0, xcmd::kPayloadController, 34));
    const xcmd::Projection projection = project(events);
    const std::vector<uint64_t> removeIdentities = {projection.points[0].index};
    const auto patch = xcmd::rewritePoints(events, removeIdentities, {});
    QVERIFY2(patch && patch->removeEvents == std::vector<uint64_t>({0, 1}) &&
                 patch->inserts.empty(),
             "deleting the last point left the dead epoch behind");
}

// A write inside a known epoch's span (between two shared points of a
// different lane) rebuilds that epoch: survivor pairs replace it, and the
// write lands as its own explicit pair. No selector restoration.
void XcmdTest::inSpanWriteRebuildsAffectedEpoch()
{
    const auto events = makeEvents(
        ev(0, 1, 0, xcmd::kSelectorController, 0x08), ev(1, 2, 0, xcmd::kPayloadController, 34),
        ev(2, 10, 0, xcmd::kSelectorController, 0x09), ev(3, 13, 0, xcmd::kPayloadController, 17));
    const std::vector<xcmd::PointWrite> writes = {{12, xcmd::kEchoVolumeLane, 40, 0, 0}};
    const auto patch = xcmd::rewritePoints(events, {}, writes);
    // The 0x09 epoch [10,13] is affected: events 2,3 leave; survivor
    // point@13 re-emitted as its own pair; write pair@12.
    QVERIFY2(patch && patch->removeEvents == std::vector<uint64_t>({2, 3}) &&
                 patch->inserts.size() == 4 && patch->inserts[0].tick == 12 &&
                 patch->inserts[0].value == 0x08 && patch->inserts[1].value == 40 &&
                 patch->inserts[2].tick == 13 && patch->inserts[2].value == 0x09 &&
                 patch->inserts[3].value == 17,
             "in-span write did not rebuild the epoch canonically");
}

// Values clamp to the descriptor range.
void XcmdTest::laneWriteClampsToDescriptorMaximum()
{
    const std::vector<xcmd::PointWrite> writes = {{5, xcmd::kEchoLengthLane, 200, 0, 0}};
    const auto patch = xcmd::rewritePoints({}, {}, writes);
    QVERIFY2(patch && patch->inserts[1].value == 127,
             "lane write did not clamp to the descriptor maximum");
}

// Unknown lane rejects; duplicate writes collapse to the later one.
void XcmdTest::unknownLaneRejectedAndDuplicatesCollapse()
{
    const std::vector<xcmd::PointWrite> unknownLane = {{5, 0x77, 40, 0, 0}};
    QVERIFY2(!xcmd::rewritePoints({}, {}, unknownLane),
             "write on an unknown lane was not rejected");
    const std::vector<xcmd::PointWrite> duplicates = {{5, xcmd::kEchoVolumeLane, 40, 0, 0},
                                                      {5, xcmd::kEchoVolumeLane, 55, 0, 0}};
    const auto patch = xcmd::rewritePoints({}, {}, duplicates);
    QVERIFY2(patch && patch->inserts.size() == 2 && patch->inserts[1].value == 55,
             "duplicate same-slot write did not collapse to the later value");
}

// Same-tick canonical pairs retain active-write order after the stable tick
// sort, rather than interleaving selectors and payloads by lane.
void XcmdTest::sameTickPairsRetainActiveWriteOrder()
{
    const std::vector<xcmd::PointWrite> writes = {
        {5, xcmd::kEchoVolumeLane, 40, 0, 4},
        {5, xcmd::kEchoLengthLane, 55, 0, 5},
    };
    const auto patch = xcmd::rewritePoints({}, {}, writes);
    QVERIFY2(patch && patch->inserts.size() == 4 && patch->inserts[0].value == 0x08 &&
                 patch->inserts[0].channel == 4 && patch->inserts[1].value == 40 &&
                 patch->inserts[1].channel == 4 && patch->inserts[2].value == 0x09 &&
                 patch->inserts[2].channel == 5 && patch->inserts[3].value == 55 &&
                 patch->inserts[3].channel == 5,
             "same-tick writes did not retain canonical pair order");
}

} // namespace checks
