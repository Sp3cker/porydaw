#pragma once

#include <cstdint>

// Stable per-note identity: an opaque token minted for each note-on record
// by the owning SongDocument (at load and whenever an edit creates a new
// note), so code can tell records apart even when every MIDI byte is equal.
// Token 0 means unassigned. Tokens are transient — scoped to one document,
// never serialized as MIDI data, and never reused across documents.
class NoteId
{
  public:
    constexpr NoteId() = default;
    explicit constexpr NoteId(uint64_t token) : m_token(token) {}

    friend constexpr bool operator==(NoteId a, NoteId b) { return a.m_token == b.m_token; }
    friend constexpr bool operator!=(NoteId a, NoteId b) { return !(a == b); }
    friend constexpr bool operator<(NoteId a, NoteId b) { return a.m_token < b.m_token; }

    constexpr bool isAssigned() const { return m_token != 0; }

  private:
    uint64_t m_token = 0;
};

// One entry of a batch velocity write (SongDocument::setNotesVelocities).
struct NoteVelocity {
    NoteId noteId;
    int velocity = 1;
};
