#include "ui/workspaceui.h"

#include <QDockWidget>

#include <optional>
#include <utility>
#include <variant>

#include "core/songhistory.h"
#include "ui/songtab.h"
#include "ui/songview.h"

// ---- The shared-bank coordinator --------------------------------------------
//
// WorkspaceUi owns the one optional pending transition (inside
// VoicegroupViewCache) and retains no parallel origin, kind, draft, or
// blank-token fields. Undo/redo preparation crosses SongHistory first; the
// returned bank draft constructs the transition, begin() arms the FIFO gate
// BEFORE the worker submission, and the keyed terminal outcome resolves
// through the origin tab's history.

void WorkspaceUi::beginBankTransition(PendingBankTransition transition,
                                      const VoicegroupEditInput &draft)
{
    if (!m_cache.begin(std::move(transition)))
        return; // a transition is already pending; the gate made this unreachable
    emit bankActionsChanged(false);
    updateOpenGate();
    emit projectOperationRequested(ProjectOperation{draft});
}

void WorkspaceUi::submitPickerEdit(int slot, const VgVoice &voice)
{
    SongTab *const tab = m_selectedTab;
    if (!tab || !tab->isReady() || !bankActionsEnabled())
        return;
    const LoadedBankView *const view = bankViewFor(*tab);
    if (!view || slot < 0 || slot >= view->slotViews.size())
        return;
    if (!view->dirty)
        tab->history().sealBankMerge();
    // The current bank voice is the expected state; nullopt submits a blank
    // materialization. The worker is the only validator.
    const SetVoicegroupSlot edit{slot, voice, view->slotViews.at(slot).voice};
    const VoicegroupEditInput draft{view->id, edit};
    PendingBankTransition transition{draft.id, tab->name(), PendingBankTransition::Kind::Initial,
                                     draft};
    // Initial bank edits submit without pushing.
    beginBankTransition(std::move(transition), draft);
}

void WorkspaceUi::requestUndo()
{
    routeHistoryRequest(/*undo=*/true);
}

void WorkspaceUi::requestRedo()
{
    routeHistoryRequest(/*undo=*/false);
}

void WorkspaceUi::routeHistoryRequest(bool undo)
{
    SongTab *const tab = m_selectedTab;
    if (!tab || !tab->isReady() || !bankActionsEnabled())
        return;
    SongHistory &history = tab->history();
    if (undo ? !history.canUndo() : !history.canRedo())
        return;
    // A document entry crosses synchronously (the tab's edited() signal has
    // already run by the time this returns); a shared-bank entry returns the
    // exact draft for the worker without moving the stack index.
    const HistoryRequest request = undo ? history.requestUndo() : history.requestRedo();
    const auto *const draft = std::get_if<VoicegroupEditInput>(&request);
    if (!draft)
        return;
    PendingBankTransition transition{
        draft->id, tab->name(),
        undo ? PendingBankTransition::Kind::Undo : PendingBankTransition::Kind::Redo, *draft};
    beginBankTransition(std::move(transition), *draft);
}

void WorkspaceUi::applyBankView(LoadedBankView view)
{
    // The cache install precedes every resolution; tabs holding the identity
    // refresh their lease from the new view, others stay isolated.
    const VoicegroupId id = view.id;
    m_cache.applyView(std::move(view));
    for (const auto &page : m_tabPages) {
        if (page->voicegroupId() && *page->voicegroupId() == id)
            page->applyBankView(*m_cache.find(id));
    }
    if (m_selectedTab && m_selectedTab->voicegroupId() && *m_selectedTab->voicegroupId() == id) {
        rebuildVoicegroupPresentation();
        emit selectedSongStateChanged();
    }
}

void WorkspaceUi::resolveBankApplied(const VoicegroupEditApplied &outcome)
{
    const std::optional<SongName> origin = m_cache.pendingOrigin();
    if (!origin)
        return;
    SongTab *const tab = songTabFor(*origin);
    if (!tab) {
        // Unreachable through the gates (the origin cannot close while it
        // holds the pending transition); fail the transition explicitly.
        resolveBankHardError(
            VoicegroupMutationFailed{outcome.voicegroup, tr("The origin tab was closed.")});
        return;
    }
    // The view was already installed by the preceding LoadedBankView event;
    // the pending Kind selects the canonical confirmation operation.
    m_cache.resolveApplied(outcome, tab->history());
    emit bankActionsChanged(true);
    updateOpenGate();
    updateVoicegroupDockTitle();
    emit selectedSongStateChanged();
}

void WorkspaceUi::resolveBankConflict(const VoicegroupEditConflict &outcome)
{
    const std::optional<SongName> origin = m_cache.pendingOrigin();
    if (!origin)
        return;
    SongTab *const tab = songTabFor(*origin);
    if (!tab) {
        resolveBankHardError(
            VoicegroupMutationFailed{outcome.voicegroup, tr("The origin tab was closed.")});
        return;
    }
    // The direction-specific stale-transition method from the owned Kind; an
    // initial conflict calls no history method. The current view is unchanged.
    m_cache.resolveConflict(outcome, tab->history());
    emit bankActionsChanged(true);
    updateOpenGate();
    emit selectedSongStateChanged();
}

void WorkspaceUi::resolveBankHardError(const VoicegroupMutationFailed &failure)
{
    const bool gateBefore = bankActionsEnabled();
    // resolveHardError ends the pending transition without crossing it when
    // the failure names it; other voicegroup failures fall through.
    m_cache.resolveHardError(failure);
    if (!gateBefore && bankActionsEnabled()) {
        emit bankActionsChanged(true);
        updateOpenGate();
        emit selectedSongStateChanged();
        return;
    }
    // Bank submissions never open a dialog operation, so a foreign-voicegroup
    // failure consumes nothing: the status line is the whole surface.
    showStatus(failure.message, 8000);
}

// ---- Voicegroup picker presentation -----------------------------------------

void WorkspaceUi::rebuildVoicegroupPresentation()
{
    updateVoicegroupDockTitle();
    SongTab *const tab = m_selectedTab;
    const LoadedBankView *const view =
        tab && tab->voicegroupId() ? m_cache.find(*tab->voicegroupId()) : nullptr;
    if (!view) {
        // No bank view: the browser tears down to its detached state (the
        // null setSource also exits loading); the loading overlay, if any,
        // is reapplied below over the final rows.
        m_bankView.reset();
        m_voicegroupBrowser->setSource(nullptr, {}, {}, {}, {});
        m_voicegroupBrowser->setCurrentVoicegroupArg(QString());
    } else {
        // The browser reads this owned presentation copy: bank events
        // replace cache entries wholesale, so the picker never borrows a
        // QHash element or any worker state.
        m_bankView = *view;
        const VoicegroupCatalog &catalog = m_state.catalog;
        // Project-scoped wiring: the selector's -G choices and the picker's
        // badge/detail metadata come from the published catalog and the
        // audition sample set, never from the bank view.
        m_voicegroupBrowser->setVoicegroupChoices(catalog.groupArgs);
        m_voicegroupBrowser->setSampleInfoProvider([this](const QString &symbol) {
            ensureSampleSet();
            return samplePickInfoFor(symbol);
        });
        m_voicegroupBrowser->setSource(
            &*m_bankView, catalog.directSound, catalog.progWave, catalog.keysplits,
            catalog.drumkits, catalog.typicalAdsr, catalog.synths, m_pendingSynths,
            [this](const VgSynthDesc &desc) { return mintSynthSymbol(desc); });
        // After setSource: the arg setter resets the envelope history when
        // the voicegroup binding actually changed.
        const QString arg = tab->document().cfg().voicegroupArg;
        m_voicegroupBrowser->setCurrentVoicegroupArg(arg.isEmpty() ? QStringLiteral("_dummy")
                                                                   : arg);
        if (tab->isReady())
            m_voicegroupBrowser->setUsedVoices(tab->view().usedVoices());
    }
    syncVoicegroupLoading();
}

void WorkspaceUi::syncVoicegroupLoading()
{
    const bool loading = m_selectedTab && !m_selectedTab->isReady() &&
                         m_inFlightLoads.contains(m_selectedTab->name());
    m_voicegroupBrowser->setLoading(loading);
}

void WorkspaceUi::updateVoicegroupDockTitle()
{
    const bool dirty = m_selectedTab && bankDirty(*m_selectedTab);
    m_voicegroupDock->setWindowTitle(dirty ? tr("Voicegroup*") : tr("Voicegroup"));
}

SamplePickInfo WorkspaceUi::samplePickInfoFor(const QString &symbol) const
{
    // Same seam as the audition path: the lease's waves array is parallel
    // to the catalog's DirectSound list the load request carried, so an
    // index into the current list resolves the committed WaveData.
    SamplePickInfo info;
    if (!m_sampleSet)
        return info;
    const int index = m_state.catalog.directSound.indexOf(symbol);
    if (index < 0 || index >= m_sampleSet->count)
        return info;
    const WaveData *const wave = m_sampleSet->waves[index];
    if (!wave || !wave->data || wave->size == 0)
        return info;
    info.known = true;
    info.looped = (wave->status & 0x4000) != 0;
    info.rateHz = int(wave->freq / 1024);
    info.seconds = info.rateHz > 0 ? double(wave->size) / info.rateHz : 0.0;
    return info;
}

// ---- Minted synth definitions ------------------------------------------------

QString WorkspaceUi::mintSynthSymbol(const VgSynthDesc &desc)
{
    // A pending symbol for the descriptor — nothing is written; the
    // definition reaches disk when a voicegroup referencing it saves.
    // Value-equal definitions (on disk or pending) are reused.
    const VgSynthCatalog &synths = m_state.catalog.synths;
    const QString existing = synths.symbolFor(desc);
    if (!existing.isEmpty())
        return existing;
    for (auto it = m_pendingSynths.constBegin(); it != m_pendingSynths.constEnd(); ++it) {
        if (it.value() == desc)
            return it.key();
    }
    if (!synths.creatable()) {
        showStatus(tr("Cannot create synth instrument: this project doesn't define the "
                      "set_synth_* macros (Golden Sun synths need ipatix's improved mixer)."),
                   8000);
        return QString();
    }
    // Param-named; a hand-written symbol with the same name but different
    // bytes (or a plain sample) forces a suffix.
    const QString base = vgSynthSymbolName(desc);
    QString symbol = base;
    for (int i = 2; synths.find(symbol) || m_state.catalog.directSound.contains(symbol); i++)
        symbol = base + QStringLiteral("_%1").arg(i);
    m_pendingSynths.insert(symbol, desc);
    return symbol;
}

QList<QPair<QString, VgSynthDesc>>
WorkspaceUi::pendingSynthDefsFor(const LoadedBankView &view) const
{
    // The minted definitions the view's voices reference: the save recipe
    // hands them to the worker, which derives everything else from the
    // canonical record.
    QList<QPair<QString, VgSynthDesc>> defs;
    for (const auto &slot : view.slotViews) {
        if (!slot.voice)
            continue;
        const auto it = m_pendingSynths.constFind(slot.voice->symbol);
        if (it == m_pendingSynths.constEnd())
            continue;
        const QPair<QString, VgSynthDesc> definition{it.key(), it.value()};
        if (!defs.contains(definition))
            defs.append(definition);
    }
    return defs;
}

void WorkspaceUi::dropSavedPendingSynths(const SongTab &tab)
{
    // The definitions that landed on disk stop being pending once the saved
    // bank came back clean; a still-dirty view means the save refused them.
    const LoadedBankView *const view = bankViewFor(tab);
    if (!view || view->dirty)
        return;
    for (const auto &definition : pendingSynthDefsFor(*view))
        m_pendingSynths.remove(definition.first);
    rebuildVoicegroupPresentation();
}
