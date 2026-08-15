#pragma once

#include <functional>
#include <memory>

#include <QUndoCommand>

#include "project/voicegroupsource.h"

struct SongSession;
using VoicegroupEditApplied = std::function<void(SongSession &, int, bool)>;

// Creates the voicegroup-owned undo operation for the source currently open
// in session. Existing voices use mergeable value edits; materializing a blank
// slot uses exact source snapshots. Null means the request is invalid or a no-op.
std::unique_ptr<QUndoCommand> makeUndoableVoicegroupEdit(SongSession &session, int slot,
                                                         const VgVoice &voice, bool structural,
                                                         VoicegroupEditApplied applied);

// Reapplies this session's executed voicegroup operations after its source was
// reopened from disk.
void reapplyVoicegroupEditsToReopenedSource(SongSession &session);
