#pragma once

#include <optional>
#include <vector>

#include "core/songdocument.h"
#include "ui/editordrawer/nodelane/nodelane.h"

namespace nodelane {

struct CcResolvedMoves {
    std::vector<DocLanePoint> removePoints;
    SongDocument::RangeEdit::LaneWrite write;

    bool empty() const noexcept { return removePoints.empty() && write.points.empty(); }
};

struct CcDeleteRequest {
    int engineTrack = -1;
    uint8_t controller = 0;
    std::vector<uint64_t> ticks;
};

std::optional<TempoEdit> resolveTempoMoves(const SongDocument &document,
                                           const std::vector<NodePointMove> &moves);
std::optional<CcResolvedMoves> resolveCcMoves(const SongDocument &document, int engineTrack,
                                              uint8_t controller,
                                              const std::vector<NodePointMove> &moves);
std::optional<SongDocument::RangeEdit>
resolveBatchDeletes(const SongDocument &document, const std::vector<uint64_t> &tempoTicks,
                    const std::vector<CcDeleteRequest> &ccDeletes);

void appendResolvedTempoMoves(SongDocument::RangeEdit &edit, const TempoEdit &resolved);
void appendResolvedCcMoves(SongDocument::RangeEdit &edit, const CcResolvedMoves &resolved);

} // namespace nodelane
