#include <QTest>
#include <vector>

#include "checks/playback/tst_xcmd.h"

namespace checks {

// One shared selector serves two one-byte completions: two known points at
// their terminal ticks, and every protocol event consumed.
void XcmdTest::sharedSelectorServesTwoCompletions()
{
    const auto events = makeEvents(ev(0, 1, 0, xcmd::kSelectorController, 0x08),
                                   ev(1, 2, 0, xcmd::kPayloadController, 34),
                                   ev(2, 3, 0, xcmd::kPayloadController, 35));
    const xcmd::Projection result = project(events);
    QVERIFY2(result.points.size() == 2 && result.points[0].lane == xcmd::kEchoVolumeLane &&
                 result.points[0].value == 34 && result.points[0].tick == 2 &&
                 result.points[0].index == 1 && result.points[1].value == 35 &&
                 result.points[1].tick == 3 && result.points[1].index == 2 &&
                 result.consumed == std::vector<uint64_t>({0, 1, 2}),
             "shared-selector projection did not expose both points and consumed indices");
}

// An unknown selector epoch (0x01, multi-byte) is one opaque block: no
// points, but the whole epoch is consumed protocol traffic.
void XcmdTest::unknownSelectorEpochStaysOpaque()
{
    const auto events = makeEvents(ev(0, 1, 0, xcmd::kSelectorController, 0x01),
                                   ev(1, 2, 0, xcmd::kPayloadController, 1),
                                   ev(2, 3, 0, xcmd::kPayloadController, 2));
    const xcmd::Projection result = project(events);
    QVERIFY2(result.points.empty() && result.consumed == std::vector<uint64_t>({0, 1, 2}),
             "unknown-selector epoch did not stay opaque with consumed bytes");
}

// A known selector with no payload at all is a dangling epoch: no point,
// selector still consumed.
void XcmdTest::danglingKnownSelectorProjectsOpaque()
{
    const auto events = makeEvents(ev(0, 1, 0, xcmd::kSelectorController, 0x08));
    const xcmd::Projection result = project(events);
    QVERIFY2(result.points.empty() && result.consumed == std::vector<uint64_t>({0}),
             "payload-less selector epoch did not project as opaque");
}

// Leading stray payloads (before any selector) are their own opaque block:
// no point, consumed bytes.
void XcmdTest::leadingStrayPayloadsStayOpaque()
{
    const auto events = makeEvents(ev(0, 1, 0, xcmd::kPayloadController, 99),
                                   ev(1, 2, 0, xcmd::kSelectorController, 0x09),
                                   ev(2, 3, 0, xcmd::kPayloadController, 17));
    const xcmd::Projection result = project(events);
    QVERIFY2(result.points.size() == 1 && result.points[0].value == 17 &&
                 result.consumed == std::vector<uint64_t>({0, 1, 2}),
             "leading stray payload run was not kept opaque");
}

// Per-stream separation: traffic on different streams projects as separate
// points, never merged into one epoch.
void XcmdTest::streamsProjectIndependently()
{
    const auto events = makeEvents(
        ev(0, 1, 0, xcmd::kSelectorController, 0x08), ev(1, 2, 0, xcmd::kPayloadController, 34),
        ev(2, 1, 1, xcmd::kSelectorController, 0x09), ev(3, 2, 1, xcmd::kPayloadController, 17));
    const xcmd::Projection result = project(events);
    QVERIFY2(result.points.size() == 2 && result.points[0].stream == 0 &&
                 result.points[0].lane == xcmd::kEchoVolumeLane && result.points[1].stream == 1 &&
                 result.points[1].lane == xcmd::kEchoLengthLane && result.points[1].value == 17,
             "streams did not project independently");
}

// Consumed identities are a sorted, de-duplicated protocol index set,
// independent of the caller's raw-index order.
void XcmdTest::consumedIsSortedDedupIndexSet()
{
    const auto events = makeEvents(ev(9, 1, 0, xcmd::kSelectorController, 0x08),
                                   ev(2, 2, 0, xcmd::kPayloadController, 34),
                                   ev(7, 3, 0, xcmd::kAlternatePayloadController, 35));
    const xcmd::Projection result = project(events);
    QVERIFY2(result.consumed == std::vector<uint64_t>({2, 7, 9}),
             "protocol consumption was not a sorted raw-index set");
}

} // namespace checks
