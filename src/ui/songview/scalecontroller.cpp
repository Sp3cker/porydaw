#include "ui/songview/scalecontroller.h"

#include <algorithm>
#include <cstdint>
#include <span>
#include <vector>

#include "ui/pitchprojection.h"

namespace songview {

void ScaleController::setScaleHighlight(bool enabled)
{
    m_scaleHighlight = enabled;
}

void ScaleController::setScaleFold(bool enabled)
{
    m_scaleFold = enabled;
}

void ScaleController::setScaleRoot(int root)
{
    m_scaleRoot = std::clamp(root, 0, 11);
}

void ScaleController::setScaleId(porydaw_scale::ScaleId id)
{
    m_scaleId = id;
}

bool ScaleController::isScalePitch(int midiPitch) const
{
    if (midiPitch < 0 || midiPitch > 127)
        return false;
    return m_isScalePitch[static_cast<std::size_t>(midiPitch)];
}

int ScaleController::nextScalePitch(int midiPitch, int steps) const
{
    return porydaw_scale::nextScalePitch(m_scaleId, m_scaleRoot, midiPitch, steps);
}

bool ScaleController::resolveFoldDestinations(std::vector<DocNote> &notes, int degreeDelta,
                                              std::vector<uint8_t> &destinations) const
{
    if (notes.empty() || degreeDelta == 0)
        return false;
    std::sort(notes.begin(), notes.end(),
              [](const DocNote &a, const DocNote &b) { return a.key < b.key; });
    std::vector<uint8_t> sources(notes.size());
    std::vector<int> degrees(notes.size(), degreeDelta);
    for (std::size_t i = 0; i < notes.size(); i++)
        sources[i] = notes[i].key;
    destinations.resize(notes.size());
    return porydaw_scale::resolveDiatonicDestinations(m_scaleId, m_scaleRoot, std::span(sources),
                                                      std::span(degrees), std::span(destinations));
}

void ScaleController::rebuildProjection(PitchProjection &projection,
                                        std::span<const bool, 128> occupancy)
{
    if (m_scaleFold) {
        std::array<uint8_t, 128> visiblePitches;
        int count = 0;
        for (int pitch = 0; pitch < 128; pitch++) {
            if (occupancy[pitch])
                visiblePitches[count++] = static_cast<uint8_t>(pitch);
        }
        projection.buildFromPitches(std::span(visiblePitches).first(count));
    } else {
        projection.buildChromatic();
    }
}

void ScaleController::rebuildClassification(PitchProjection &projection)
{
    for (int pitch = 0; pitch < 128; pitch++)
        m_isScalePitch[static_cast<std::size_t>(pitch)] =
            porydaw_scale::isScalePitch(m_scaleId, m_scaleRoot, pitch);
    projection.setScalePitchClassification(std::span<const bool, 128>(m_isScalePitch));
}

} // namespace songview