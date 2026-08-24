#pragma once

#include <algorithm>
#include <vector>

#include "core/noteid.h"

// Feature-internal helpers shared by the velocityarea translation units.
// Not part of VelocityArea's public interface; do not include from outside
// src/ui/editordrawer/velocityarea/.
namespace velocityarea::detail {

// Linear membership test for transient NoteId vectors (gesture staging,
// band preview). Queries against the model's active selection belong on
// EditorSelectionModel::isNoteSelected instead.
inline bool contains(const std::vector<NoteId> &notes, NoteId noteId)
{
    return std::find(notes.begin(), notes.end(), noteId) != notes.end();
}

} // namespace velocityarea::detail
