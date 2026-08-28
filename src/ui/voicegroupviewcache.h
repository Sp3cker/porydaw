#pragma once

#include <QHash>
#include <optional>

#include "project/projectworkspace.h"
#include "project/voicegroupsource.h"

class SongHistory;

// The one bank transition in flight: the copied input submitted to the worker,
// plus the routing facts (identity, origin tab, and which confirmation the
// applied or conflicted outcome selects). There is no per-identity pending
// map, request id, tab pointer, or second history stack.
struct PendingBankTransition {
    enum class Kind { Initial, Undo, Redo };
    VoicegroupId voicegroup;
    SongName origin;
    Kind kind = Kind::Initial;
    VoicegroupEditInput draft; // copied submitted input; draft.id == voicegroup
};

// WorkspaceUi's private shared-bank coordinator. It owns the published GUI
// bank views keyed by VoicegroupId plus the single optional
// PendingBankTransition, and routes each typed outcome to the origin tab's
// SongHistory before ending the transition.
class VoicegroupViewCache
{
  public:
    const LoadedBankView *find(VoicegroupId voicegroup) const;
    bool begin(PendingBankTransition transition);
    std::optional<SongName> pendingOrigin() const;
    void applyView(LoadedBankView view);
    void resolveApplied(VoicegroupEditApplied outcome, SongHistory &originHistory);
    void resolveConflict(VoicegroupEditConflict outcome, SongHistory &originHistory);
    void resolveHardError(VoicegroupMutationFailed failure);
    void clear();
    bool bankActionsEnabled() const;
    bool closeEnabledFor(SongName origin) const;

  private:
    QHash<VoicegroupId, LoadedBankView> m_views;
    std::optional<PendingBankTransition> m_pending;
};
