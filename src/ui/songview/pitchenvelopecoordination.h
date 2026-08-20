#pragma once

#include <optional>

struct TrackRemap;

namespace songview {

class PitchEnvelopeUiState
{
  public:
    std::optional<int> openTrack() const noexcept { return m_openTrack; }

    bool set(int track, int selectedTrack) noexcept;
    bool clear(int track) noexcept;
    bool clear() noexcept;
    bool remap(const TrackRemap &remap);
    bool applySelectionTransition(int selectedTrack) noexcept;

  private:
    std::optional<int> m_openTrack;
};

} // namespace songview
