#pragma once

#include <functional>
#include <memory>

#include <QUndoCommand>

#include "project/voicegroupsource.h"

class QUndoStack;

using VoicegroupEditApplied = std::function<void(VoicegroupSource &, int, bool)>;

// Creates the voicegroup-owned undo operation for the holder's current open
// source. Commands retain the holder and source load name, resolving the
// current source for every transition. Null means the request is invalid or
// a no-op.
std::unique_ptr<QUndoCommand> makeUndoableVoicegroupEdit(VoicegroupSourceHolder &target, int slot,
                                                         const VgVoice &voice, bool structural,
                                                         VoicegroupEditApplied applied);

// Reapplies only the executed prefix of this holder's voicegroup operations
// after its current source was reopened. Structural replay refreshes the
// command's materialization token for that source so a later undo reverts the
// exact insertion. Replay never invokes callbacks.
void reapplyVoicegroupEditsToReopenedSource(const QUndoStack &undoStack,
                                            VoicegroupSourceHolder &target);
