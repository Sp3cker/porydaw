#include <QTest>
#include <cstdint>
#include <span>
#include <vector>

#include "checks/playback/tst_xcmd.h"

namespace checks {
namespace {

// One canonical pair: a fresh selector CC immediately followed by a fresh
// payload CC at the same tick and channel.
bool isCanonicalPair(const xcmd::Emission &selectorEvent, const xcmd::Emission &payloadEvent,
                     uint8_t selector, uint8_t value)
{
    return selectorEvent.controller == xcmd::kSelectorController &&
           selectorEvent.value == selector && payloadEvent.controller == xcmd::kPayloadController &&
           payloadEvent.value == value && selectorEvent.tick == payloadEvent.tick &&
           selectorEvent.channel == payloadEvent.channel && selectorEvent.sourceIndex == SIZE_MAX &&
           payloadEvent.sourceIndex == SIZE_MAX;
}

} // namespace

// One shared selector serves two payloads at later ticks: all source bytes
// leave and each payload becomes its own same-tick explicit pair.
void XcmdTest::sharedSelectorRebuiltAsSameTickPairs()
{
    const auto events = makeEvents(ev(0, 1, 0, xcmd::kSelectorController, 0x08),
                                   ev(1, 4, 0, xcmd::kPayloadController, 34, 3),
                                   ev(2, 9, 0, xcmd::kAlternatePayloadController, 35, 3));
    const xcmd::Patch patch = xcmd::canonicalizeForExport(std::span<const xcmd::Event>(events));
    QVERIFY2(patch.removeEvents == std::vector<uint64_t>({0, 1, 2}) && patch.inserts.size() == 4 &&
                 isCanonicalPair(patch.inserts[0], patch.inserts[1], 0x08, 34) &&
                 patch.inserts[0].tick == 4 && patch.inserts[0].channel == 3 &&
                 isCanonicalPair(patch.inserts[2], patch.inserts[3], 0x08, 35) &&
                 patch.inserts[2].tick == 9,
             "shared selector was not rebuilt as same-tick explicit pairs");
}

// A known selector with no payload is inaudible and stock mid2agb drops the
// wait that follows it: the dangling byte is removed outright.
void XcmdTest::danglingKnownSelectorRemoved()
{
    const auto events = makeEvents(ev(0, 7, 0, xcmd::kSelectorController, 0x09));
    const xcmd::Patch patch = xcmd::canonicalizeForExport(std::span<const xcmd::Event>(events));
    QVERIFY2(patch.removeEvents == std::vector<uint64_t>({0}) && patch.inserts.empty(),
             "payload-less known selector was not removed");
}

// Unknown selector epochs and stray payload runs stay byte-for-byte:
// nothing removed, nothing inserted.
void XcmdTest::unknownEpochAndStrayRunPreservedVerbatim()
{
    const auto events = makeEvents(ev(0, 1, 0, xcmd::kPayloadController, 99),
                                   ev(1, 2, 0, xcmd::kSelectorController, 0x03),
                                   ev(2, 3, 0, xcmd::kPayloadController, 9),
                                   ev(3, 4, 0, xcmd::kAlternatePayloadController, 10));
    const xcmd::Patch patch = xcmd::canonicalizeForExport(std::span<const xcmd::Event>(events));
    QVERIFY2(patch.removeEvents.empty() && patch.inserts.empty(),
             "unknown epoch or stray payload run was not preserved verbatim");
}

// Already-explicit points rebuild to their own canonical pairs, still
// tick-ordered in final-stream order, with per-pair channels preserved.
void XcmdTest::explicitPointsRebuiltInTickOrder()
{
    const auto events = makeEvents(ev(0, 20, 0, xcmd::kSelectorController, 0x09),
                                   ev(1, 20, 0, xcmd::kPayloadController, 17, 2),
                                   ev(2, 4, 1, xcmd::kSelectorController, 0x08),
                                   ev(3, 4, 1, xcmd::kAlternatePayloadController, 65, 6));
    const xcmd::Patch patch = xcmd::canonicalizeForExport(std::span<const xcmd::Event>(events));
    QVERIFY2(patch.removeEvents == std::vector<uint64_t>({0, 1, 2, 3}) &&
                 patch.inserts.size() == 4 &&
                 isCanonicalPair(patch.inserts[0], patch.inserts[1], 0x08, 65) &&
                 patch.inserts[0].tick == 4 && patch.inserts[0].channel == 6 &&
                 isCanonicalPair(patch.inserts[2], patch.inserts[3], 0x09, 17) &&
                 patch.inserts[2].tick == 20 && patch.inserts[2].channel == 2,
             "explicit points were not rebuilt semantically identically in tick order");
}

} // namespace checks
