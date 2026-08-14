#pragma once

#include <cstdint>
#include <optional>
#include <vector>

#include "core/noteid.h"

// Deferred velocity edits: the bookkeeping behind a velocity gesture that
// must not touch the document until it is released. The model holds document
// identities and preview values only — the caller owns hit-testing, painting,
// and the eventual SongDocument::setNotesVelocities call, which is why the
// completion carries the revision the gesture started at (a document that
// moved underneath must reject the write rather than land it blind).
// Ported from specker/cleanup/psg-velocity-history-pr.
class VelocityGestureModel
{
  public:
    struct Completion {
        uint64_t expectedRevision = 0;
        std::vector<NoteVelocity> targets;
    };

    // Starts a session over targets (their current velocities are the
    // origins updateByDelta measures from). Refuses an empty, unassigned,
    // out-of-range, or duplicated target set, and never replaces a live
    // session.
    bool begin(uint64_t expectedRevision, std::vector<NoteVelocity> targets);
    bool active() const noexcept { return m_session.has_value(); }

    // Absolute preview write. All-or-nothing: an update naming a note the
    // session does not hold, or naming one twice, changes nothing.
    bool update(const std::vector<NoteVelocity> &updates);
    // Relative preview write: every target moves delta from ITS OWN origin,
    // clamped to 1-127, so a drag that returns to the press restores the
    // exact starting values instead of accumulating clamp damage.
    bool updateByDelta(int delta);
    std::optional<uint8_t> previewVelocity(NoteId noteId) const;
    // Ends the session and hands back what to commit.
    std::optional<Completion> takeCompletion();
    bool cancel();

  private:
    struct Session {
        uint64_t expectedRevision = 0;
        std::vector<NoteVelocity> targets; // sorted by NoteId (binary search)
        std::vector<uint8_t> originalVelocities;
        std::vector<uint8_t> updateMarks; // duplicate detection within one update
    };
    size_t targetIndex(NoteId noteId) const;

    std::optional<Session> m_session;
};
