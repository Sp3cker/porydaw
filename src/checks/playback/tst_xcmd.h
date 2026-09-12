#pragma once

#include <cstdint>

#include <QObject>

#include "core/xcmd.h"

namespace checks {

// XCMD protocol contracts migrated from the legacy --xcmdcheck runner.
// Selector CC 0x1E opens an epoch and payload CCs 0x1D/0x1F complete known
// points (one point per payload byte); everything else is opaque protocol
// traffic preserved byte-for-byte. Every emitted point is an explicit
// selector+payload pair — never shared, never restored — and consumed
// identities are a sorted, de-duplicated raw-index set.
class XcmdTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(XcmdTest)
  public:
    XcmdTest() = default;

  private slots:
    // Projection.
    void sharedSelectorServesTwoCompletions();
    void unknownSelectorEpochStaysOpaque();
    void danglingKnownSelectorProjectsOpaque();
    void leadingStrayPayloadsStayOpaque();
    void streamsProjectIndependently();
    void consumedIsSortedDedupIndexSet();

    // Canonical lane rewrites.
    void addOnEmptyTrackEmitsCanonicalPair();
    void addUnderActiveStateEmitsFullPair();
    void replaceRebuildsEpochWithExplicitPair();
    void deleteSharedPointRebuildsSurvivorAsPair();
    void deleteLastPointRemovesDeadEpoch();
    void inSpanWriteRebuildsAffectedEpoch();
    void laneWriteClampsToDescriptorMaximum();
    void unknownLaneRejectedAndDuplicatesCollapse();
    void sameTickPairsRetainActiveWriteOrder();

    // Opaque preservation and rejection.
    void writeAfterOpaqueEpochLeavesItUntouched();
    void writeInsideOpaqueEpochRejected();
    void writeInsideStrayRunSpanRejected();
    void unknownRemoveIdentitiesRejected();

    // Raw reconciliation.
    void wholeOpaqueRelocationIsByteExact();
    void partialOpaqueOperationsRejected();
    void conflictingDuplicateRawOpsRejected();
    void wholeOpaqueCopyDuplicatesBytes();
    void wholeEpochRemovalLeavesNothingBehind();
    void wholeStrayRunRelocationIsByteExact();
    void knownPointMoveRebuildsEpoch();
    void knownPointCopyRebuildsBothCanonically();
    void mixedKnownEpochOpsRebuildPointByPoint();
    void rawRemovalOfLonePointKillsEpoch();
    void staleAndCrossEpochRawDestinationsRejected();
    void knownSelectorGlueIgnoredAndOwnEpochMoveRebuilt();
    void cutVacatesSpanForLaterMove();
    void relocatedEpochVacatesItsSpan();

    // Export canonicalization.
    void sharedSelectorRebuiltAsSameTickPairs();
    void danglingKnownSelectorRemoved();
    void unknownEpochAndStrayRunPreservedVerbatim();
    void explicitPointsRebuiltInTickOrder();
};

// Test-local event adapters (the legacy ev()/makeEvents()/project()).
xcmd::Event ev(uint64_t index, Tick tick, uint8_t stream, uint8_t controller, uint8_t value,
               uint8_t channel = 0);

template <typename... Events>
std::vector<xcmd::Event> makeEvents(Events... events)
{
    return std::vector<xcmd::Event>{static_cast<xcmd::Event>(events)...};
}

xcmd::Projection project(const std::vector<xcmd::Event> &events);

} // namespace checks
