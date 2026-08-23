#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <span>
#include <vector>

#include "core/songdocument.h"
#include "porydaw_scale.h"

namespace songview {

class PitchProjection;

// Per-view scale controls: scale id/root, the Fold and Highlight toggles,
// and the cached pitch classification they feed. A plain value object — no
// callbacks, no host, no allocation. SongView owns every side effect
// (signals, roll repaint, the anchored rebuild) and drives it directly
// around these state setters and the rebuild math. The toggles are
// independent per-tab runtime state; neither is persisted with the song or
// its view sidecar.
//
// Classification: rebuildClassification() re-derives the 128-pitch
// membership cache (the single source for draw/command checks) and pushes
// it into the PitchProjection rows; porydaw_scale is only touched here and
// in the fold math. The projection is passed in as a sink argument, so the
// controller stays a value object while PitchProjection remains pure.
class ScaleController
{
  public:
    bool scaleHighlight() const { return m_scaleHighlight; }
    void setScaleHighlight(bool enabled);
    bool scaleFold() const { return m_scaleFold; }
    void setScaleFold(bool enabled);
    int scaleRoot() const { return m_scaleRoot; } // 0-11 (C=0)
    void setScaleRoot(int root);
    porydaw_scale::ScaleId scaleId() const { return m_scaleId; }
    void setScaleId(porydaw_scale::ScaleId id);

    // Cached scale membership for a MIDI pitch, refreshed by every
    // rebuildClassification(); the single classification source for the
    // roll's drawing and command checks.
    bool isScalePitch(int midiPitch) const;

    // Fold-mode pitch stepping through the cached scale state.
    int nextScalePitch(int midiPitch, int steps) const;

    // Diatonic transpose of the notes through the cached scale (their keys
    // are sorted in place; repeated keys share the first occurrence's
    // destination). Boundary failure fills destinations with uint8_t(-1)
    // and returns false.
    bool resolveFoldDestinations(std::vector<DocNote> &notes, int degreeDelta,
                                 std::vector<uint8_t> &destinations) const;

    // Rebuild the row mapping (Fold: from the occupancy span's occupied
    // pitches; Off/Highlight: full chromatic) into the projection. The
    // occupancy span is only read in Fold mode; SongView supplies it from
    // the view model.
    void rebuildProjection(PitchProjection &projection, std::span<const bool, 128> occupancy);

    // Recompute the pitch classification cache from the current root/scale
    // and push it into the projection's rows.
    void rebuildClassification(PitchProjection &projection);

  private:
    bool m_scaleHighlight = false;
    bool m_scaleFold = false;
    int m_scaleRoot = 0; // C
    porydaw_scale::ScaleId m_scaleId = porydaw_scale::ScaleId::major;
    std::array<bool, 128> m_isScalePitch{}; // pitch-indexed membership cache
};

} // namespace songview