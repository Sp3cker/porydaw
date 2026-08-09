#pragma once

#include <cstdint>
#include <optional>
#include <vector>

#include "core/noteid.h"

// Deferred velocity edits shared by piano-roll and velocity-area gestures.
// The model stores document identities and preview values only; callers own
// pointer mapping, painting, and the eventual document mutation.
class VelocityGestureModel
{
  public:
    struct Completion {
        uint64_t expectedRevision = 0;
        std::vector<NoteVelocity> targets;
    };

    bool begin(uint64_t expectedRevision, std::vector<NoteVelocity> targets);
    bool active() const noexcept { return m_session.has_value(); }

    bool update(const std::vector<NoteVelocity> &updates);
    bool updateByDelta(int delta);
    std::optional<uint8_t> previewVelocity(NoteId noteId) const;
    std::optional<Completion> takeCompletion();
    bool cancel();

  private:
    struct Session {
        uint64_t expectedRevision = 0;
        std::vector<NoteVelocity> targets;
        std::vector<uint8_t> originalVelocities;
        std::vector<uint8_t> updateMarks;
    };
    size_t targetIndex(NoteId noteId) const;

    std::optional<Session> m_session;
};
