#pragma once

#include <compare>
#include <cstdint>

// A NoteId identifies each note-on record in one document.
// The NoteId lets code tell records apart when they have equal MIDI fields.
// Token 0 means no ID. A nonzero token identifies a note-on record.
// Each token belongs to one document. Tokens do not go to a different document or into MIDI data.
class NoteId
{
  public:
    constexpr NoteId() = default;
    explicit constexpr NoteId(uint64_t token) : m_token(token) {}

    friend constexpr auto operator<=>(NoteId, NoteId) = default;

    constexpr bool isAssigned() const { return m_token != 0; }

  private:
    uint64_t m_token = 0;
};

struct NoteVelocity {
    NoteId noteId;
    int velocity = 1;
};
