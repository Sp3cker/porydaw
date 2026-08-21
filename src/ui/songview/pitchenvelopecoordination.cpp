#include "ui/songview/pitchenvelopecoordination.h"

#include "core/songdocument.h"
#include "ui/m4asemantics.h"
#include "ui/songview.h"
#include "ui/songview/pitchenvelopehost.h"

#include <cstddef>

namespace {
constexpr int kEngineTrackCount = 16;
}

namespace songview {

bool PitchEnvelopeUiState::set(int track, int selectedTrack) noexcept
{
    if (track < 0 || track >= kEngineTrackCount || track != selectedTrack || m_openTrack == track)
        return false;
    m_openTrack = track;
    return true;
}

bool PitchEnvelopeUiState::clear(int track) noexcept
{
    if (!m_openTrack || *m_openTrack != track)
        return false;
    m_openTrack.reset();
    return true;
}

bool PitchEnvelopeUiState::clear() noexcept
{
    if (!m_openTrack)
        return false;
    m_openTrack.reset();
    return true;
}

bool PitchEnvelopeUiState::remap(const TrackRemap &remap)
{
    if (!m_openTrack)
        return false;
    const int track = *m_openTrack;
    const int mappedTrack =
        track >= 0 && static_cast<std::size_t>(track) < remap.engineTrackMap.size()
            ? remap.engineTrackMap[static_cast<std::size_t>(track)]
            : -1;
    if (mappedTrack >= 0 && mappedTrack < remap.newEngineTrackCount &&
        mappedTrack < kEngineTrackCount) {
        if (mappedTrack == track)
            return false;
        m_openTrack = mappedTrack;
        return true;
    }
    m_openTrack.reset();
    return true;
}

bool PitchEnvelopeUiState::applySelectionTransition(int selectedTrack) noexcept
{
    if (!m_openTrack || *m_openTrack == selectedTrack)
        return false;
    m_openTrack.reset();
    return true;
}

} // namespace songview

using namespace songview;

bool SongView::trackHasPitchEnvelopeVoice(int track) const
{
    if (!m_timeline || !m_voicegroup || track < 0 || track >= 16 || !m_timeline->tracks[track].used)
        return false;
    const auto supportsPitchEnvelope = [this](int program) {
        return program >= 0 && program < VOICEGROUP_SIZE &&
               voiceSupportsPitchEnvelope(m_voicegroup->voices[program].type);
    };
    if (supportsPitchEnvelope(m_timeline->tracks[track].firstProgram))
        return true;
    for (const VoiceChange &change : m_model.voices) {
        if (change.track == track && supportsPitchEnvelope(change.program))
            return true;
    }
    return false;
}

bool SongView::pitchEnvelopeCreationEnabled(int track) const
{
    if (!m_document || track != m_selectionModel.primaryTrack())
        return false;
    for (const DocNote &note : m_document->notesForTrack(track)) {
        const DrawerPageVoiceContext context = voiceContext(note.tick);
        if (context.voice && voiceSupportsPitchEnvelope(context.voice->type))
            return true;
    }
    return false;
}

void SongView::setPitchEnvelopeVisible(int track, bool visible)
{
    if (!visible) {
        if (m_pitchEnvelopeState.clear(track))
            refreshPitchEnvelopeState();
        return;
    }
    if (!pitchEnvelopeCreationEnabled(track) ||
        !m_pitchEnvelopeState.set(track, m_selectionModel.primaryTrack()))
        return;
    refreshPitchEnvelopeState();
}

void SongView::refreshPitchEnvelopeState()
{
    const bool visible = m_pitchEnvelopeState.openTrack().has_value();
    m_pitchEnvelopeHost->setEnvelopeVisible(visible);
    if (visible)
        updatePitchEnvelopeGeometry();
    emit pitchEnvelopeVisibilityChanged();
}
