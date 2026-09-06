#include <QTest>
#include <vector>

#include "checks/playback/tst_xcmd.h"

namespace checks {

// A write past an unknown-selector epoch keeps the opaque bytes entirely
// untouched (no removal, no re-role).
void XcmdTest::writeAfterOpaqueEpochLeavesItUntouched()
{
    const auto events = makeEvents(
        ev(0, 1, 0, xcmd::kSelectorController, 0x03), ev(1, 2, 0, xcmd::kPayloadController, 9),
        ev(2, 5, 0, xcmd::kSelectorController, 0x08), ev(3, 6, 0, xcmd::kPayloadController, 34));
    const std::vector<xcmd::PointWrite> writes = {{8, xcmd::kEchoVolumeLane, 40, 0, 0}};
    const auto patch = xcmd::rewritePoints(events, {}, writes);
    QVERIFY2(patch && patch->removeEvents.empty() && patch->inserts.size() == 2 &&
                 patch->inserts[0].tick == 8 && patch->inserts[1].tick == 8,
             "write after an opaque epoch touched the opaque traffic");
}

// A write at an opaque epoch's interior tick would re-roll surviving bytes:
// rejected, including the opaque selector's own tick.
void XcmdTest::writeInsideOpaqueEpochRejected()
{
    const auto events = makeEvents(ev(0, 1, 0, xcmd::kSelectorController, 0x03),
                                   ev(1, 2, 0, xcmd::kPayloadController, 9),
                                   ev(2, 3, 0, xcmd::kPayloadController, 10));
    std::vector<xcmd::PointWrite> writes = {{2, xcmd::kEchoVolumeLane, 40, 0, 0}};
    QVERIFY2(!xcmd::rewritePoints(events, {}, writes),
             "write inside an opaque epoch was not rejected");
    writes[0].tick = 1; // the opaque selector's own tick
    QVERIFY2(!xcmd::rewritePoints(events, {}, writes),
             "write on an opaque epoch's first tick was not rejected");
}

// A write inside a leading stray run's occupied span is rejected too.
void XcmdTest::writeInsideStrayRunSpanRejected()
{
    const auto events = makeEvents(ev(0, 1, 0, xcmd::kPayloadController, 99),
                                   ev(1, 2, 0, xcmd::kPayloadController, 98));
    const std::vector<xcmd::PointWrite> writes = {{1, xcmd::kEchoVolumeLane, 40, 0, 0}};
    QVERIFY2(!xcmd::rewritePoints(events, {}, writes),
             "write inside a stray-run span was not rejected");
}

// Remove identities that are not known points reject: opaque member,
// selector byte, and unknown index.
void XcmdTest::unknownRemoveIdentitiesRejected()
{
    const auto events = makeEvents(
        ev(0, 1, 0, xcmd::kSelectorController, 0x03), ev(1, 2, 0, xcmd::kPayloadController, 9),
        ev(2, 3, 0, xcmd::kSelectorController, 0x08), ev(3, 4, 0, xcmd::kPayloadController, 34));
    const std::vector<uint64_t> opaqueMember = {1};
    QVERIFY2(!xcmd::rewritePoints(events, opaqueMember, {}),
             "removing an opaque member was not rejected");
    const std::vector<uint64_t> selectorByte = {2};
    QVERIFY2(!xcmd::rewritePoints(events, selectorByte, {}),
             "removing a known selector was not rejected");
    const std::vector<uint64_t> staleIdentity = {999};
    QVERIFY2(!xcmd::rewritePoints(events, staleIdentity, {}),
             "removing a stale identity was not rejected");
}

} // namespace checks
