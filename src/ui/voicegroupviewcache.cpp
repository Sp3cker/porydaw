#include "ui/voicegroupviewcache.h"

#include "core/songhistory.h"

#include <utility>

const LoadedBankView *VoicegroupViewCache::find(VoicegroupId voicegroup) const
{
    const auto it = m_views.constFind(voicegroup);
    return it == m_views.constEnd() ? nullptr : &it.value();
}

bool VoicegroupViewCache::begin(PendingBankTransition transition)
{
    if (m_pending)
        return false;
    m_pending = std::move(transition);
    return true;
}

std::optional<SongName> VoicegroupViewCache::pendingOrigin() const
{
    if (!m_pending)
        return std::nullopt;
    return m_pending->origin;
}

void VoicegroupViewCache::applyView(LoadedBankView view)
{
    m_views.insert(view.id, std::move(view));
}

// applyView() must precede this: the installed view is the canonical bank
// replacement, and only then does the origin history record the transition.
void VoicegroupViewCache::resolveApplied(VoicegroupEditApplied outcome, SongHistory &originHistory)
{
    if (!m_pending || !(m_pending->voicegroup == outcome.voicegroup))
        return;
    const auto &pending = *m_pending;
    switch (pending.kind) {
    case PendingBankTransition::Kind::Initial:
        originHistory.pushConfirmedBank(pending.draft, outcome.materialization);
        break;
    case PendingBankTransition::Kind::Undo:
        originHistory.crossConfirmedBankUndo(outcome.materialization);
        break;
    case PendingBankTransition::Kind::Redo:
        originHistory.crossConfirmedBankRedo(outcome.materialization);
        break;
    }
    m_pending.reset();
}

void VoicegroupViewCache::resolveConflict(VoicegroupEditConflict outcome,
                                          SongHistory &originHistory)
{
    if (!m_pending || !(m_pending->voicegroup == outcome.voicegroup))
        return;
    switch (m_pending->kind) {
    case PendingBankTransition::Kind::Initial:
        break; // an initial conflict leaves the history unchanged
    case PendingBankTransition::Kind::Undo:
        originHistory.resolveBankUndoConflict();
        break;
    case PendingBankTransition::Kind::Redo:
        originHistory.resolveBankRedoConflict();
        break;
    }
    m_pending.reset();
}

// A hard worker error for the pending voicegroup ends the one in-flight
// transition without crossing it: the history index stays fixed and the
// current view is unchanged.
void VoicegroupViewCache::resolveHardError(VoicegroupMutationFailed failure)
{
    if (!m_pending || !(m_pending->voicegroup == failure.voicegroup))
        return;
    m_pending.reset();
}

void VoicegroupViewCache::clear()
{
    m_views.clear();
    m_pending.reset();
}

bool VoicegroupViewCache::bankActionsEnabled() const
{
    return !m_pending.has_value();
}

bool VoicegroupViewCache::closeEnabledFor(SongName origin) const
{
    return !(m_pending && m_pending->origin == origin);
}
