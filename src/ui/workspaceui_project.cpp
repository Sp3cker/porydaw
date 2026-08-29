#include "ui/workspaceui.h"

#include <QCheckBox>
#include <QComboBox>
#include <QDialog>
#include <QDialogButtonBox>
#include <QDir>
#include <QFileDialog>
#include <QFileInfo>
#include <QFormLayout>
#include <QLineEdit>
#include <QMainWindow>
#include <QMessageBox>
#include <QRegularExpression>
#include <QRegularExpressionValidator>
#include <QSettings>

#include <memory>
#include <type_traits>
#include <utility>

#include "project/songregistry.h"
#include "ui/newsongwizard.h"
#include "ui/songlistpanel.h"
#include "ui/songtab.h"
#include "ui/songview.h"

namespace {
const QString kLastProjectDirKey = QStringLiteral("lastProjectDir");
const QString kLastOpenSongsKey = QStringLiteral("lastOpenSongs");
const QString kLastSongLabelKey = QStringLiteral("lastSongLabel");

// The registration files' display names: the labels SongInfo::registrationGaps
// records for the Songs list badge, so the confirmation dialogs name every
// file exactly as the badge does. src/debug.c keeps its src/ prefix; the
// other registration files reduce to their file name.
QString registrationFileName(const QString &path)
{
    return path == QLatin1String("src/debug.c") ? path : QFileInfo(path).fileName();
}

} // namespace

// ---- The Open Project gate ---------------------------------------------------

bool WorkspaceUi::openProjectEnabled() const noexcept
{
    if (m_state.state == ProjectOpenState::Loading)
        return false;
    if (m_state.state == ProjectOpenState::Closed || m_state.state == ProjectOpenState::Failed)
        return !m_openRequested;
    // Ready: the action stays disabled while any placeholder lacks a
    // terminal song payload or any workspace-submitted work is in flight.
    if (m_openRequested)
        return false;
    for (const auto &page : m_tabPages) {
        if (!page->isReady())
            return false;
    }
    return m_inFlightLoads.empty() && m_inFlightSaves.empty() && m_dialogOps == 0 &&
           m_tombstones.isEmpty() && bankActionsEnabled();
}

void WorkspaceUi::updateOpenGate()
{
    const bool enabled = openProjectEnabled();
    if (enabled == m_openGatePublished)
        return;
    m_openGatePublished = enabled;
    emit openProjectEnabledChanged(enabled);
}

// ---- Project state publication ----------------------------------------------

void WorkspaceUi::applyProjectState(ProjectState state)
{
    if (m_state.catalog.directSound != state.catalog.directSound ||
        m_state.catalog.progWave != state.catalog.progWave ||
        m_state.catalog.keysplits != state.catalog.keysplits)
        m_sampleSet.reset();
    m_state = std::move(state);

    if (m_state.state == ProjectOpenState::Loading) {
        // The prior snapshot stays visible while the open runs.
        updateOpenGate();
        return;
    }

    if (m_state.state == ProjectOpenState::Failed) {
        if (m_awaitingStartupOpen) {
            // A failed startup open tears the placeholders down, clears the
            // saved song keys, and re-enables Open Project; the saved
            // project path stays recorded for retry.
            m_awaitingStartupOpen = false;
            teardownStartupPlaceholders();
            clearStartupSongKeys();
            showStatus(tr("Couldn't reopen last project %1: %2")
                           .arg(m_startRecipe.projectPath, m_state.error.value_or(QString())),
                       0);
        } else if (m_openRequested) {
            m_openRequested = false;
            // Failure changes nothing else: snapshot, tabs, cache state,
            // and the persisted project/song settings are untouched.
            QMessageBox::warning(&m_host, tr("Open Project"), m_state.error.value_or(QString()));
        }
        updateOpenGate();
        return;
    }

    // Ready.
    const bool userSwitch = m_openRequested;
    const bool acceptedOpen = userSwitch || m_awaitingStartupOpen;
    m_openRequested = false;
    if (userSwitch && !m_awaitingStartupOpen) {
        // Accepted project replacement: destroy the tabs, clear the cache
        // and the transient state, and start with a clean slate. The song
        // keys were already cleared by the queued startup of this switch.
        destroyAllTabs();
        m_cache.clear();
        m_tombstones.clear();
        m_inFlightLoads.clear();
        m_inFlightSaves.clear();
        m_closeAfterSave.clear();
        m_rebindSkip.clear();
        m_boundArgs.clear();
        m_startupPlaceholders.clear();
        m_pendingSynths.clear();
        m_sampleSet.reset();
        clearStartupSongKeys();
        m_songList->setSongs(m_state.snapshot.songs());
        m_songList->setCurrentSong(-1);
        rebuildVoicegroupPresentation();
    } else if (m_awaitingStartupOpen) {
        // Startup open accepted: the named placeholders stay visible; the
        // saved songs arrive as ordinary keyed SongUpdates.
        m_awaitingStartupOpen = false;
        m_songList->setSongs(m_state.snapshot.songs());
        if (m_selectedTab) {
            if (const SongInfo *const song = songInfoFor(m_selectedTab->name()))
                m_songList->setCurrentSong(song->id);
        }
    } else {
        // A register/delete/create/catalog republication of the same project.
        // Every non-open publication completes exactly one counted workspace
        // operation: the delete's fresh snapshot, the reload's re-read, or
        // the new-voicegroup / refresh-catalog scan.
        consumeDialogOperation();
        reconcileSnapshot();
    }
    if (acceptedOpen) {
        showStatus(tr("Opened %1 — %2 songs")
                       .arg(QDir(m_state.snapshot.root()).dirName())
                       .arg(m_state.snapshot.songs().size()));
    }
    updateOpenGate();
    emit selectedSongStateChanged();
}

void WorkspaceUi::teardownStartupPlaceholders()
{
    destroyAllTabs();
    m_cache.clear();
    m_tombstones.clear();
    m_inFlightLoads.clear();
    m_boundArgs.clear();
    m_startupPlaceholders.clear();
}

void WorkspaceUi::clearStartupSongKeys()
{
    QSettings settings;
    settings.remove(kLastOpenSongsKey);
    settings.remove(kLastSongLabelKey);
}

void WorkspaceUi::reconcileSnapshot()
{
    m_songList->setSongs(m_state.snapshot.songs());
    if (m_selectedTab) {
        // Re-resolve the selected song's snapshot row after registration or
        // creation changed ids.
        if (const SongInfo *const song = songInfoFor(m_selectedTab->name()))
            m_songList->setCurrentSong(song->id);
    }

    // A completed delete closes its tab; the song no longer exists.
    if (!m_pendingDeleteSong.isEmpty()) {
        if (const auto name = SongName::create(m_pendingDeleteSong)) {
            if (SongTab *const tab = songTabFor(*name))
                closeTabNow(tab);
        }
        m_pendingDeleteSong.clear();
    }
    // A created song with a fresh voicegroup opens in a new tab.
    if (m_pendingCreatedNewVoicegroup && !m_pendingCreatedLabel.isEmpty()) {
        const auto name = SongName::create(m_pendingCreatedLabel);
        if (name && songInfoFor(*name)) {
            if (!songTabFor(*name))
                createLoadTab(*name, /*activate=*/true);
            m_pendingCreatedLabel.clear();
            m_pendingCreatedNewVoicegroup = false;
        }
    }
    // A freshly created voicegroup assigns itself to the selected song; the
    // document edit triggers the bank rebind through onTabEdited.
    if (!m_pendingVoicegroupArg.isEmpty() && m_selectedTab && m_selectedTab->isReady()) {
        SongCfg cfg = m_selectedTab->document().cfg();
        if (cfg.voicegroupArg != m_pendingVoicegroupArg) {
            cfg.voicegroupArg = m_pendingVoicegroupArg;
            m_selectedTab->document().setCfg(cfg);
            showStatus(tr("Created sound/voicegroups/%1.inc and assigned it to %2.")
                           .arg(m_pendingVoicegroupArg.mid(1), m_selectedTab->name().value()),
                       10000);
        }
        m_pendingVoicegroupArg.clear();
    }

    rebuildVoicegroupPresentation();
    emit selectedSongStateChanged();
}

// ---- Open / reload actions ---------------------------------------------------

void WorkspaceUi::requestProjectOpen()
{
    if (m_state.state == ProjectOpenState::Loading || m_openRequested)
        return;
    if (m_dialogOps > 0 || !bankActionsEnabled()) {
        showStatus(tr("A project change is still in progress; finish it before switching "
                      "projects."),
                   5000);
        return;
    }
    QSettings settings;
    const QString startDir = settings.value(kLastProjectDirKey, QDir::homePath()).toString();
    const QString dir =
        QFileDialog::getExistingDirectory(&m_host, tr("Open Decomp Project"), startDir);
    if (dir.isEmpty())
        return;
    requestProjectOpenAt(dir);
}

void WorkspaceUi::requestProjectOpenAt(const QString &root)
{
    if (m_state.state == ProjectOpenState::Loading || m_openRequested)
        return;
    if (m_dialogOps > 0 || !bankActionsEnabled()) {
        showStatus(tr("A project change is still in progress; finish it before switching "
                      "projects."),
                   5000);
        return;
    }
    // Every prompt before the project (or any tab) changes: a Cancel aborts
    // the switch, though Saves answered before it have already queued —
    // standard save-all behavior, not a transaction.
    promptSaveAll([this, root](bool proceed) {
        if (proceed)
            beginProjectSwitch(root);
    });
}

void WorkspaceUi::beginProjectSwitch(const QString &dir)
{
    if (m_state.state == ProjectOpenState::Loading || m_openRequested)
        return;
    if (m_dialogOps > 0 || !bankActionsEnabled()) {
        showStatus(tr("A project change is still in progress; finish it before switching "
                      "projects."),
                   5000);
        return;
    }
    // Unconfirmed plan/delete dialogs die with the switch.
    if (m_registerConfirmation) {
        QMessageBox *const box = m_registerConfirmation.data();
        m_registerConfirmation = nullptr;
        box->close();
    }
    if (m_deleteConfirmation) {
        QMessageBox *const box = m_deleteConfirmation.data();
        m_deleteConfirmation = nullptr;
        box->close();
    }
    cleanupPreview();
    m_openRequested = true;
    updateOpenGate();
    emit projectOpenRequested(OpenProjectInput{dir});
}

void WorkspaceUi::requestProjectReload()
{
    if (!m_state.snapshot.isOpen() || projectBusy() || m_dialogOps > 0)
        return;
    m_dialogOps++;
    updateOpenGate();
    emit projectOperationRequested(ProjectOperation{RefreshProjectInput{}});
}

// The save-all prompt chain for the interactive project switch.
void WorkspaceUi::promptSaveAll(const std::function<void(bool)> &continuation)
{
    auto names = std::make_shared<std::vector<SongName>>();
    names->reserve(m_tabPages.size());
    for (const auto &page : m_tabPages)
        names->push_back(page->name());
    auto completion = std::make_shared<std::function<void(bool)>>(continuation);
    auto next = std::make_shared<std::function<void(size_t)>>();
    const std::weak_ptr<std::function<void(size_t)>> weakNext = next;
    *next = [this, names, completion, weakNext](size_t index) {
        if (index >= names->size()) {
            if (*completion)
                (*completion)(true);
            return;
        }
        SongTab *const tab = songTabFor(names->at(index));
        if (!tab) {
            if (const auto step = weakNext.lock())
                (*step)(index + 1);
            return;
        }
        maybeSaveTab(tab, [completion, weakNext, index](bool proceed) {
            if (!proceed) {
                if (*completion)
                    (*completion)(false);
                return;
            }
            if (const auto step = weakNext.lock())
                (*step)(index + 1);
        });
    };
    (*next)(0);
}

// ---- Project events ----------------------------------------------------------

void WorkspaceUi::applyProjectEvent(ProjectEvent event)
{
    std::visit(
        [this](auto &&published) {
            using T = std::decay_t<decltype(published)>;
            if constexpr (std::is_same_v<T, LoadedBankView>) {
                applyBankView(std::move(published));
            } else if constexpr (std::is_same_v<T, VoicegroupEditApplied>) {
                resolveBankApplied(published);
            } else if constexpr (std::is_same_v<T, VoicegroupEditConflict>) {
                resolveBankConflict(published);
            } else if constexpr (std::is_same_v<T, RegistrationPlanResult>) {
                consumeDialogOperation();
                confirmRegistration(published);
            } else if constexpr (std::is_same_v<T, DeletionPlanResult>) {
                consumeDialogOperation();
                confirmDeletion(published);
            } else if constexpr (std::is_same_v<T, SongCreated>) {
                consumeDialogOperation();
                handleSongCreated(published);
            } else if constexpr (std::is_same_v<T, PreviewPlan>) {
                consumeDialogOperation();
            } else if constexpr (std::is_same_v<T, PreviewReady>) {
                consumeDialogOperation();
            } else if constexpr (std::is_same_v<T, SampleSetReady>) {
                m_sampleSet = published.sampleSet;
                consumeDialogOperation();
                rebuildVoicegroupPresentation();
            } else if constexpr (std::is_same_v<T, SamplesProbed>) {
                consumeDialogOperation();
                continueImportFlow(published.probe);
            } else if constexpr (std::is_same_v<T, SampleRead>) {
                consumeDialogOperation();
                continueEditSampleFlow(published);
            } else if constexpr (std::is_same_v<T, SampleCommitted>) {
                consumeDialogOperation();
                handleSampleCommitted(published);
            } else if constexpr (std::is_same_v<T, ProjectMutationFailure>) {
                // ProjectMutationFailure is itself a variant: the keyed
                // failures only surface through a second visit. The bank
                // coordinator consumes its dialog op itself.
                std::visit(
                    [this](auto &&failure) {
                        using F = std::decay_t<decltype(failure)>;
                        if constexpr (std::is_same_v<F, SongMutationFailed>) {
                            consumeDialogOperation();
                            QMessageBox::warning(&m_host, tr("Project Change"), failure.message);
                        } else if constexpr (std::is_same_v<F, VoicegroupMutationFailed>) {
                            resolveBankHardError(failure);
                        } else if constexpr (std::is_same_v<F, SampleMutationFailed>) {
                            consumeDialogOperation();
                            QMessageBox::warning(&m_host, tr("Sample"), failure.message);
                        } else if constexpr (std::is_same_v<F, CatalogMutationFailed>) {
                            consumeDialogOperation();
                            showStatus(failure.message, 8000);
                        } else {
                            static_assert(std::is_void_v<F>, "Unhandled project mutation failure");
                        }
                    },
                    std::move(published));
            } else {
                static_assert(std::is_void_v<T>, "Unhandled project event");
            }
        },
        std::move(event));
}

void WorkspaceUi::consumeDialogOperation()
{
    if (m_dialogOps > 0)
        m_dialogOps--;
    updateOpenGate();
}

// ---- Register / delete flows -------------------------------------------------

const SongInfo *WorkspaceUi::listedSongAt(int songId) const
{
    const auto &songs = m_state.snapshot.songs();
    if (songId < 0 || songId >= songs.size())
        return nullptr;
    return &songs.at(songId);
}

void WorkspaceUi::registerSelectedSong()
{
    SongTab *const tab = m_selectedTab;
    if (!tab || !tab->isReady() || projectBusy() || m_dialogOps > 0)
        return;
    const SongInfo *const song = songInfoFor(tab->name());
    if (song && !song->registrationGaps.isEmpty())
        runRegisterFlow(*song);
}

void WorkspaceUi::deleteSelectedSong()
{
    SongTab *const tab = m_selectedTab;
    if (!tab || !tab->isReady())
        return;
    if (const SongInfo *const song = songInfoFor(tab->name()))
        runDeleteFlow(*song);
}

void WorkspaceUi::runRegisterFlow(const SongInfo &song)
{
    if (projectBusy() || m_dialogOps > 0)
        return;
    const QString constant =
        song.constant.isEmpty() ? SongRegistry::constantForLabel(song.label) : song.constant;
    const QString player = song.player.isEmpty() ? QStringLiteral("MUSIC_PLAYER_BGM") : song.player;
    m_dialogOps++;
    updateOpenGate();
    emit projectOperationRequested(
        ProjectOperation{RegistrationPlanInput{song.label, constant, player}});
}

void WorkspaceUi::confirmRegistration(const RegistrationPlanResult &result)
{
    QStringList files;
    if (!result.status.inSongTable)
        files << registrationFileName("sound/song_table.inc");
    if (!result.status.inSongsH)
        files << registrationFileName("include/constants/songs.h");
    if (result.status.ldApplicable && !result.status.inLdScript)
        files << registrationFileName("ld_script.ld");
    if (result.status.charmapApplicable && !result.status.inCharmap)
        files << registrationFileName("charmap.txt");
    if (result.status.debugApplicable && !result.status.inDebugMenu)
        files << registrationFileName("src/debug.c");
    auto *const box =
        new QMessageBox(QMessageBox::Question, tr("Register Song"),
                        tr("Register %1 as %2?").arg(result.plan.label, result.plan.constant),
                        QMessageBox::NoButton, &m_host);
    box->setAttribute(Qt::WA_DeleteOnClose);
    box->setInformativeText(files.isEmpty()
                                ? QString()
                                : tr("The following registration files need updates:\n  - %1")
                                      .arg(files.join(QStringLiteral("\n  - "))));
    auto *const registerButton = box->addButton(tr("Register"), QMessageBox::AcceptRole);
    box->addButton(QMessageBox::Cancel);
    m_registerConfirmation = box;
    connect(box, &QMessageBox::finished, this, [this, box, result, registerButton](int) {
        if (m_registerConfirmation == box)
            m_registerConfirmation = nullptr;
        if (box->clickedButton() != registerButton)
            return;
        if (projectBusy() || m_dialogOps > 0)
            return;
        m_dialogOps++;
        updateOpenGate();
        emit projectOperationRequested(ProjectOperation{
            RegisterSongInput{result.plan.label, result.plan.constant, result.plan.player}});
    });
    box->open();
}

void WorkspaceUi::runDeleteFlow(const SongInfo &song)
{
    if (projectBusy() || m_dialogOps > 0)
        return;
    const auto name = SongName::create(song.label);
    if (!name)
        return;
    const QString constant =
        song.constant.isEmpty() ? SongRegistry::constantForLabel(song.label) : song.constant;
    m_dialogOps++;
    updateOpenGate();
    emit projectOperationRequested(ProjectOperation{DeletionPlanInput{*name, constant}});
}

void WorkspaceUi::confirmDeletion(const DeletionPlanResult &result)
{
    if (result.plan.tableIndex == 0) {
        QMessageBox::warning(&m_host, tr("Delete Song"),
                             tr("%1 is the first usable table entry (song ID 0); the engine's "
                                "fallback. It cannot be deleted.")
                                 .arg(result.song.value()));
        return;
    }
    QStringList details;
    if (result.plan.lastEntry)
        details << tr("Its song_table.inc line is removed outright.");
    else
        details << tr("Its song_table.inc entry becomes a reusable free slot, so no other "
                      "song's ID changes.");
    if (result.plan.inSongsH)
        details << registrationFileName("include/constants/songs.h");
    if (result.plan.inLdScript)
        details << registrationFileName("ld_script.ld");
    if (result.plan.inCharmap)
        details << registrationFileName("charmap.txt");
    if (result.plan.inDebugMenu)
        details << registrationFileName("src/debug.c");

    auto *const box =
        new QMessageBox(QMessageBox::Warning, tr("Delete Song"),
                        tr("Delete %1?").arg(result.song.value()), QMessageBox::NoButton, &m_host);
    box->setAttribute(Qt::WA_DeleteOnClose);
    box->setInformativeText(details.isEmpty() ? QString()
                                              : tr("* Its .mid moves to .porydaw/trash.\n* %1")
                                                    .arg(details.join(QStringLiteral("\n* "))));
    QCheckBox *const alsoVoicegroup = [&box, &result]() -> QCheckBox * {
        if (result.deletableVoicegroupName.isEmpty())
            return nullptr;
        auto *check = new QCheckBox(
            tr("Also delete voicegroup %1 (used only by this song)")
                .arg(SongRegistry::voicegroupDisplayName(result.deletableVoicegroupName)),
            box);
        check->setChecked(true);
        box->setCheckBox(check);
        return check;
    }();
    auto *const deleteButton = box->addButton(tr("Delete"), QMessageBox::DestructiveRole);
    box->addButton(QMessageBox::Cancel);
    m_deleteConfirmation = box;
    connect(box, &QMessageBox::finished, this,
            [this, box, result, deleteButton, alsoVoicegroup](int) {
                if (m_deleteConfirmation == box)
                    m_deleteConfirmation = nullptr;
                if (box->clickedButton() != deleteButton)
                    return;
                if (projectBusy() || m_dialogOps > 0)
                    return;
                // The executed delete carries the same identity the plan ran with:
                // the snapshot's constant when present, the label-derived default
                // otherwise (DeletionPlanResult does not repeat the constant).
                const SongInfo *const info = songInfoFor(result.song);
                DeleteSongInput input{result.song,
                                      info && !info->constant.isEmpty()
                                          ? info->constant
                                          : SongRegistry::constantForLabel(result.song.value()),
                                      alsoVoicegroup && alsoVoicegroup->isChecked()
                                          ? result.deletableVoicegroupName
                                          : QString()};
                m_pendingDeleteSong = result.song.value();
                m_dialogOps++;
                updateOpenGate();
                emit projectOperationRequested(ProjectOperation{std::move(input)});
            });
    box->open();
}

// ---- Song creation -----------------------------------------------------------

void WorkspaceUi::handleSongCreated(const SongCreated &created)
{
    QString message;
    if (created.midiOk && created.flagsOk && created.registered) {
        message = tr("Created and registered %1 (song ID %2)")
                      .arg(created.song.value(), QString::number(created.songId));
    } else if (created.midiOk) {
        message = tr("Created %1 mid; use File > Register Song to register it.")
                      .arg(created.song.value());
    } else {
        message =
            tr("Creating %1 failed; use File > Register Song to retry.").arg(created.song.value());
    }
    showStatus(message, 8000);
}

// ---- New voicegroup ----------------------------------------------------------

void WorkspaceUi::runCreateVoicegroupFlow()
{
    if (!m_state.snapshot.isOpen() || projectBusy() || m_dialogOps > 0)
        return;
    const VoicegroupCatalog &catalog = m_state.catalog;
    if (catalog.groupArgs.isEmpty() && catalog.directSound.isEmpty() &&
        catalog.progWave.isEmpty()) {
        showStatus(tr("Loading voicegroup catalog…"), 5000);
        return;
    }
    if (!catalog.perFileVoicegroups) {
        QMessageBox::information(&m_host, tr("New Voicegroup"),
                                 tr("This project keeps all voicegroups in one file; creating "
                                    "new per-file voicegroups isn't supported for that layout."));
        return;
    }
    // The selected tab's voicegroup identity carries the copy source across
    // the seam: the project-relative source path plus its section label.
    const VoicegroupId *activeId =
        m_selectedTab && m_selectedTab->isReady() ? m_selectedTab->voicegroupId() : nullptr;
    QDialog dialog(&m_host);
    dialog.setWindowTitle(tr("New Voicegroup"));
    auto *const form = new QFormLayout(&dialog);
    auto *const nameEdit = new QLineEdit(&dialog);
    nameEdit->setValidator(new QRegularExpressionValidator(
        QRegularExpression(QStringLiteral("[A-Za-z][A-Za-z0-9_]*")), nameEdit));
    form->addRow(tr("Name"), nameEdit);
    auto *const sourceCombo = new QComboBox(&dialog);
    if (activeId) {
        sourceCombo->addItem(
            tr("Copy of %1").arg(QFileInfo(activeId->sourceRelativePath()).fileName()),
            QDir(m_state.snapshot.root()).filePath(activeId->sourceRelativePath()));
    }
    sourceCombo->addItem(tr("Empty (dummy template)"), QString());
    auto *const buttons =
        new QDialogButtonBox(QDialogButtonBox::Ok | QDialogButtonBox::Cancel, &dialog);
    connect(buttons, &QDialogButtonBox::accepted, &dialog, &QDialog::accept);
    connect(buttons, &QDialogButtonBox::rejected, &dialog, &QDialog::reject);
    if (dialog.exec() != QDialog::Accepted)
        return;
    if (!m_state.snapshot.isOpen() || projectBusy() || m_dialogOps > 0)
        return;
    const QString name = nameEdit->text().trimmed();
    if (name.isEmpty())
        return;
    if (catalog.groupArgs.contains(QStringLiteral("_") + name)) {
        QMessageBox::warning(&m_host, tr("New Voicegroup"),
                             tr("A voicegroup named %1 already exists.").arg(name));
        return;
    }
    CreateVoicegroupInput input{name, sourceCombo->currentData().toString(),
                                activeId ? activeId->sectionLabel() : QString()};
    m_pendingVoicegroupArg = QStringLiteral("_") + name;
    m_dialogOps++;
    updateOpenGate();
    emit projectOperationRequested(ProjectOperation{std::move(input)});
}
