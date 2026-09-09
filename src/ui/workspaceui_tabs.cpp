#include "ui/workspaceui.h"

#include <QMainWindow>
#include <QMessageBox>
#include <QSettings>

#include <algorithm>
#include <utility>

#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/workspacequick/songtabsmodel.h"
#include "ui/workspacequick/workspacequickhost.h"

namespace {
const QString kLastOpenSongsKey = QStringLiteral("lastOpenSongs");
const QString kLastSongLabelKey = QStringLiteral("lastSongLabel");
} // namespace

// ---- Tab creation, selection, removal, and order ----------------------------

SongTab *WorkspaceUi::createTab(SongName name, bool activate)
{
    auto page = std::make_unique<SongTab>(std::move(name));
    SongTab *const tab = page.get();
    tab->setSampleRate(m_audioSampleRate);
    tab->view().setVelocityColorMode(m_velocityColorMode);
    tab->view().setNoteNameMode(m_noteNameMode);
    tab->view().setFollowPlayhead(m_followPlayhead);
    tab->view().applyEditorViewState(m_editorViewState);
    wireTab(tab);
    // append() owns the structural notification and explicitly publishes
    // CppOwnership; adding a row never changes the selection authority.
    m_tabModel->append(std::move(page));
    if (activate)
        selectTab(tab);
    return tab;
}

void WorkspaceUi::removeTab(SongTab *tab)
{
    if (!tab)
        return;
    const int row = m_tabModel->rowFor(tab);
    if (row < 0)
        return;
    const bool wasSelected = tab == m_selectedTab;
    if (wasSelected) {
        // Keep routed note-off and gesture cancellation attached to the
        // outgoing authority, then unload audio while the tab's bank lease
        // remains alive. The host sees null before the removal bracket
        // detaches the page; a final selection is published below.
        m_quickHost->deactivateSelection();
        m_selectedTab = nullptr;
        emit selectedSongTabChanged(nullptr);
        m_tabModel->notifySelectionChanged();
    }

    // take() brackets the authoritative vector mutation and lets the host
    // detach the page while this session is still alive. Destroy only after
    // the model's rows have settled.
    std::unique_ptr<SongTab> removed = m_tabModel->take(*tab);
    removed.reset();

    if (!wasSelected || m_tabPages.empty())
        return;
    // Match the old next-or-previous close policy without another selection
    // owner: the row that shifted into the removed slot wins, else the last.
    selectTab(m_tabModel->songAt(std::min(row, int(m_tabPages.size()) - 1)));
}

void WorkspaceUi::destroyAllTabs()
{
    // No intermediate selection/persistence publication escapes teardown.
    // Cancel the outgoing page while it is still authoritative, unload audio
    // before its lease can die, detach every page inside the model bracket,
    // destroy the sessions, then leave the empty host for its later teardown.
    m_tearingDown = true;
    if (m_selectedTab) {
        m_quickHost->deactivateSelection();
        m_selectedTab = nullptr;
        emit selectedSongTabChanged(nullptr);
    }
    std::vector<std::unique_ptr<SongTab>> removed = m_tabModel->takeAll();
    removed.clear();
    m_tearingDown = false;
    rebuildVoicegroupPresentation();
}

void WorkspaceUi::selectTab(SongTab *tab)
{
    if (!tab || tab == m_selectedTab || m_tabModel->rowFor(tab) < 0)
        return;
    // Frozen handoff order: the outgoing scene first cancels while the old
    // selection still owns routing; publish the new authority and audio
    // handoff synchronously; only then let model signals reveal and enable
    // the incoming page. MainWindow's queued focus runs after this call.
    m_quickHost->deactivateSelection();
    m_selectedTab = tab;
    publishSelection();
    m_tabModel->notifySelectionChanged();
}

void WorkspaceUi::selectSongTab(SongTab *tab)
{
    if (tab && songTabFor(tab->name()) == tab)
        selectTab(tab);
}

void WorkspaceUi::publishSelection()
{
    rebuildVoicegroupPresentation();
    persistTabs();
    emit selectedSongTabChanged(m_selectedTab);
    emit selectedSongStateChanged();
}

void WorkspaceUi::moveTab(SongTab *tab, int destinationIndex)
{
    if (!tab || !m_tabModel->move(*tab, destinationIndex))
        return;
    // move() preserves the selected session identity and emits only its
    // derived index change. Persist the model's new authoritative order.
    emit sessionsReordered();
    persistTabs();
}

std::vector<SongTab *> WorkspaceUi::tabsInDisplayOrder() const
{
    std::vector<SongTab *> tabs;
    tabs.reserve(m_tabPages.size());
    for (const auto &page : m_tabPages)
        tabs.push_back(page.get());
    return tabs;
}

SongTab *WorkspaceUi::songTabFor(const SongName &name) const noexcept
{
    for (const auto &page : m_tabPages) {
        if (page->name() == name)
            return page.get();
    }
    return nullptr;
}

// ---- Persistence and dirty state --------------------------------------------

void WorkspaceUi::persistTabs()
{
    // Never persist mid-teardown: during a project switch the settings
    // already point at the NEW project, and the dying tabs' labels would
    // be recorded against it if a crash landed in this window.
    if (m_tearingDown || !m_state.snapshot.isOpen())
        return;
    QSettings settings;
    QStringList labels;
    for (const auto &page : m_tabPages)
        labels << page->name().value();
    if (labels.isEmpty()) {
        settings.remove(kLastOpenSongsKey);
        settings.remove(kLastSongLabelKey);
        return;
    }
    settings.setValue(kLastOpenSongsKey, labels);
    settings.setValue(kLastSongLabelKey,
                      m_selectedTab ? m_selectedTab->name().value() : labels.first());
}

bool WorkspaceUi::bankDirty(const SongTab &tab) const noexcept
{
    const LoadedBankView *const view = bankViewFor(tab);
    return view && view->dirty;
}

const LoadedBankView *WorkspaceUi::bankViewFor(const SongTab &tab) const noexcept
{
    if (!tab.voicegroupId())
        return nullptr;
    return m_cache.find(*tab.voicegroupId());
}

bool WorkspaceUi::selectedSongDirty() const noexcept
{
    SongTab *const tab = m_selectedTab;
    return tab && tab->isReady() && !m_inFlightSaves.contains(tab->name()) &&
           (tab->document().isDirty() || bankDirty(*tab));
}

bool WorkspaceUi::hasPendingSaveWork() const noexcept
{
    for (const auto &page : m_tabPages) {
        SongTab *const tab = page.get();
        if (!tab->isReady())
            continue;
        if (m_inFlightSaves.contains(tab->name()) || tab->document().isDirty() || bankDirty(*tab))
            return true;
    }
    return false;
}

void WorkspaceUi::onTabEdited(SongTab *tab)
{
    if (tab != m_selectedTab)
        return;
    // The -G switch (or its undo/redo) rebinds the tab's shared bank through
    // the project worker; the document's live edits stay on the tab.
    if (tab->isReady() && bankActionsEnabled() && !m_inFlightLoads.contains(tab->name())) {
        const QString arg = tab->document().cfg().voicegroupArg;
        const QString bound = m_boundArgs.value(tab->name());
        if (arg != bound && !(arg.isEmpty() && bound == QLatin1String("_dummy")))
            startVoicegroupRebind(*tab);
    }
    rebuildVoicegroupPresentation();
    emit selectedSongStateChanged();
}

void WorkspaceUi::startVoicegroupRebind(SongTab &tab)
{
    // One rebind per name; only the bank binding moves.
    if (m_inFlightLoads.contains(tab.name()))
        return;
    m_rebindSkip.insert(tab.name());
    m_inFlightLoads.insert(tab.name());
    updateOpenGate();
    emit projectOperationRequested(
        ProjectOperation{ReloadSongInput{tab.name(), tab.document().cfg().voicegroupArg}});
}

// ---- Song updates -----------------------------------------------------------

void WorkspaceUi::applySongUpdate(SongUpdate update)
{
    const SongName name = update.song;
    std::visit([this, &name](auto &&staged) { applyStagedUpdate(name, staged); }, update.payload);
}

void WorkspaceUi::applyStagedUpdate(const SongName &name, MidiStage &stage)
{
    if (m_tombstones.contains(name))
        return; // closed while loading: staged publications are dropped
    SongTab *const tab = songTabFor(name);
    if (!tab)
        return; // unmatched updates stay ignored
    if (m_rebindSkip.contains(name))
        return; // bank rebind: the document keeps its live state
    tab->applyMidiStage(std::move(stage.info), std::move(stage.smf), stage.trackBudget);
}

void WorkspaceUi::applyStagedUpdate(const SongName &name, VoicegroupBound &bound)
{
    // Terminal: erases the tombstone and the load gate even for a tab that
    // no longer exists; the terminal is consumed only for that.
    m_tombstones.remove(name);
    m_rebindSkip.remove(name);
    m_inFlightLoads.remove(name);
    updateOpenGate();
    SongTab *const tab = songTabFor(name);
    if (!tab)
        return;
    // The preceding LoadedBankView event already updated the cache; adopt
    // the published lease by the incoming id before the bind. The tab's
    // voicegroupId is not yet installed (applyMidiStage reset it) or stale
    // from a rebind, so tab-keyed lookup would miss or pick the wrong entry.
    if (const LoadedBankView *const view = m_cache.find(bound.id))
        tab->applyBankView(*view);
    // Terminal: the bind completes readiness and is the final operation
    // that may enable the tab.
    tab->applyVoicegroupBound(std::move(bound.id));
    m_boundArgs.insert(name, tab->document().cfg().voicegroupArg);
    m_tabModel->refresh(*tab);
    m_startupPlaceholders.remove(name);
    persistTabs();
    emit songTabReady(tab);
    if (tab == m_selectedTab) {
        rebuildVoicegroupPresentation();
        emit selectedSongStateChanged();
    }
}

void WorkspaceUi::applyStagedUpdate(const SongName &name, SongSaved &saved)
{
    m_inFlightSaves.remove(name);
    SongTab *const tab = songTabFor(name);
    if (tab) {
        tab->applySongSaved(saved.savedSnapshot, saved.flagsWritten);
        dropSavedPendingSynths(*tab);
        m_tabModel->refresh(*tab);
        showStatus(tr("Saved %1").arg(saved.savedSnapshot.midPath));
    }
    updateOpenGate();
    if (m_closeAfterSave.remove(name))
        closeTabNow(tab);
    emit selectedSongStateChanged();
}

void WorkspaceUi::applyStagedUpdate(const SongName &name, SongFailed &failed)
{
    handleSongFailed(name, std::move(failed));
}

void WorkspaceUi::handleSongFailed(const SongName &name, SongFailed failed)
{
    m_tombstones.remove(name);
    const bool rebind = m_rebindSkip.remove(name);
    m_inFlightLoads.remove(name);
    m_inFlightSaves.remove(name);
    updateOpenGate();
    SongTab *const tab = songTabFor(name);
    if (failed.stage == SongStage::Save) {
        // A fatal save failure keeps the loaded tab; the independent bank
        // event, if any, was already applied through the cache.
        m_closeAfterSave.remove(name);
        if (tab)
            tab->applySongFailed(failed.message);
        QMessageBox::warning(&m_host, tr("Save Song"), failed.message);
        emit selectedSongStateChanged();
        return;
    }
    if (rebind) {
        // A failed bank rebind keeps the tab loaded with its previous
        // binding, like any other failed voicegroup reload.
        showStatus(failed.message, 8000);
        emit selectedSongStateChanged();
        return;
    }
    const bool startup = m_startupPlaceholders.remove(name);
    if (tab)
        closeTabNow(tab);
    if (!startup)
        QMessageBox::warning(&m_host, tr("Load Song"), failed.message);
    emit selectedSongStateChanged();
}

// ---- Song browser placement policy ------------------------------------------

void WorkspaceUi::requestSongOpen(const SongName &name, bool newTab)
{
    // The browser placement policy keyed by the stable SongName instead of a
    // snapshot-local row id; unknown or unplayable names are a no-op.
    const auto &songs = m_state.snapshot.songs();
    for (int songId = 0; songId < songs.size(); ++songId) {
        if (songs.at(songId).label == name.value()) {
            openSongFromList(songId, newTab);
            return;
        }
    }
}

void WorkspaceUi::openSongFromList(int songId, bool newTab)
{
    if (projectBusy())
        return;
    const SongInfo *const song = listedSongAt(songId);
    if (!song || !song->isPlayable())
        return;
    const auto name = SongName::create(song->label);
    if (!name)
        return;
    if (m_tombstones.contains(*name)) {
        showStatus(tr("%1 is still closing; try again in a moment.").arg(name->value()));
        return;
    }
    if (SongTab *const live = songTabFor(*name)) {
        if (live != m_selectedTab || newTab) {
            selectTab(live); // one live tab per song: focus it
            return;
        }
        // Re-activating the current tab's song is the in-place reload path
        // (an externally changed .mid, or an explicit refresh).
        maybeSaveTab(live, [this, name = *name](bool proceed) {
            if (!proceed || m_inFlightLoads.contains(name))
                return;
            SongTab *const tab = songTabFor(name);
            if (!tab)
                return;
            m_inFlightLoads.insert(name);
            updateOpenGate();
            tab->beginMidiReload();
            if (tab == m_selectedTab)
                emit selectedSongStateChanged();
            emit projectOperationRequested(ProjectOperation{ReloadSongInput{name}});
        });
        return;
    }
    maybeSaveTab(m_selectedTab, [this, name = *name, newTab](bool proceed) {
        if (!proceed)
            return;
        if (SongTab *const opened = songTabFor(name)) {
            selectTab(opened); // focused meanwhile
            return;
        }
        if (!newTab && m_selectedTab && m_selectedTab->isReady())
            closeTabNow(m_selectedTab); // replacement: the prompt already ran
        createLoadTab(name, /*activate=*/true);
    });
}

SongTab *WorkspaceUi::createLoadTab(const SongName &name, bool activate)
{
    SongTab *const tab = createTab(name, activate);
    m_inFlightLoads.insert(name);
    updateOpenGate();
    syncVoicegroupLoading();
    emit projectOperationRequested(ProjectOperation{OpenSongInput{name}});
    return tab;
}

// ---- Save flow --------------------------------------------------------------

void WorkspaceUi::saveSelectedSong()
{
    submitSaveForTab(m_selectedTab, {});
}

void WorkspaceUi::submitSaveForTab(SongTab *tab, const std::function<void(bool)> &continuation)
{
    const auto complete = [&continuation](bool ok) {
        if (continuation)
            continuation(ok);
    };
    if (!tab || !tab->isReady() || tab->document().midPath().isEmpty()) {
        complete(false);
        return;
    }
    const SongName name = tab->name();
    if (m_inFlightSaves.contains(name)) {
        complete(false);
        return;
    }
    const bool documentDirty = tab->document().isDirty();
    const LoadedBankView *const view = bankViewFor(*tab);
    if (!documentDirty && !(view && view->dirty)) {
        complete(true); // nothing to save
        return;
    }
    SaveSongInput input{name, tab->captureSaveSnapshot(), std::nullopt};
    if (view && view->dirty) {
        // The bank recipe rides the semantic save: the worker writes the
        // voicegroup source (plus minted synth definitions), refreshes the
        // bank, and publishes the resulting view before the MIDI write.
        input.voicegroup = SaveVoicegroupInput{view->id, pendingSynthDefsFor(*view)};
    }
    m_inFlightSaves.insert(name);
    updateOpenGate();
    emit selectedSongStateChanged();
    // One semantic song-save operation; the terminal outcome arrives as a
    // keyed SongSaved or SongFailed publication.
    emit projectOperationRequested(ProjectOperation{std::move(input)});
    complete(true);
}

// ---- Close flow -------------------------------------------------------------

void WorkspaceUi::requestCloseSelectedTab()
{
    requestCloseTab(m_selectedTab);
}

void WorkspaceUi::requestCloseTab(SongTab *tab)
{
    if (!tab)
        return;
    const SongName name = tab->name();
    // The origin-aware close gate: only the pending transition's tab refuses.
    if (!m_cache.closeEnabledFor(name))
        return;
    // A tab whose semantic save is in flight refuses to close until the
    // terminal publication lands.
    if (m_inFlightSaves.contains(name))
        return;
    if (!tab->isReady() || !tab->document().isDirty()) {
        closeTabNow(tab);
        return;
    }
    // Show the tab being asked about: Save/Discard for edits the user
    // can't see is a data-loss trap.
    selectTab(tab);
    const bool withBank = bankDirty(*tab);
    const QMessageBox::StandardButton choice = QMessageBox::question(
        &m_host, tr("Unsaved Changes"),
        withBank ? tr("%1 has unsaved changes (including voicegroup edits). Save them?")
                       .arg(tab->document().label())
                 : tr("%1 has unsaved changes. Save them?").arg(tab->document().label()),
        QMessageBox::Save | QMessageBox::Discard | QMessageBox::Cancel, QMessageBox::Save);
    if (choice == QMessageBox::Cancel)
        return;
    if (choice == QMessageBox::Discard) {
        closeTabNow(tab);
        return;
    }
    submitSaveForTab(tab, [this, name](bool ok) {
        // The close completes when the terminal publication lands; a save
        // that refuses to start keeps the tab open.
        if (ok)
            m_closeAfterSave.insert(name);
    });
}

void WorkspaceUi::closeTabNow(SongTab *tab)
{
    if (!tab)
        return;
    const SongName name = tab->name();
    if (m_inFlightLoads.contains(name))
        m_tombstones.insert(name); // closed loading: refuse reopen until terminal
    m_closeAfterSave.remove(name);
    m_rebindSkip.remove(name);
    m_boundArgs.remove(name);
    m_startupPlaceholders.remove(name);
    removeTab(tab);
    persistTabs();
    updateOpenGate();
    rebuildVoicegroupPresentation();
    emit selectedSongStateChanged();
}

// ---- Dirty prompts (project switch and close orchestration) -----------------

void WorkspaceUi::maybeSaveTab(SongTab *tab, const std::function<void(bool)> &continuation)
{
    if (!tab) {
        continuation(true);
        return;
    }
    if (!tab->isReady()) {
        continuation(true); // nothing saveable
        return;
    }
    const SongName name = tab->name();
    if (m_inFlightSaves.contains(name)) {
        continuation(false); // a save is already in flight for this tab
        return;
    }
    if (!tab->document().isDirty() && !bankDirty(*tab)) {
        continuation(true);
        return;
    }
    selectTab(tab);
    const bool withBank = bankDirty(*tab);
    const QMessageBox::StandardButton choice = QMessageBox::question(
        &m_host, tr("Unsaved Changes"),
        withBank ? tr("%1 has unsaved changes (including voicegroup edits). Save them?")
                       .arg(tab->document().label())
                 : tr("%1 has unsaved changes. Save them?").arg(tab->document().label()),
        QMessageBox::Save | QMessageBox::Discard | QMessageBox::Cancel, QMessageBox::Save);
    if (choice == QMessageBox::Cancel) {
        continuation(false);
        return;
    }
    if (choice == QMessageBox::Discard) {
        continuation(true);
        return;
    }
    // The semantic save queues ahead of whatever the continuation submits
    // (a project open, say); the FIFO carries it out in order.
    submitSaveForTab(tab, [continuation](bool ok) { continuation(ok); });
}

// ---- Sample rate ------------------------------------------------------------

void WorkspaceUi::applySampleRateToTabs()
{
    for (const auto &page : m_tabPages)
        page->setSampleRate(m_audioSampleRate);
}
