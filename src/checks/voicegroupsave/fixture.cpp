#include "checks/voicegroupsave/tst_voicegroupsave.h"

#include <QDir>
#include <QFile>
#include <QSettings>
#include <QtTest>

#include "checks/support/asyncwait.h"
#include "checks/support/songfixture.h"
#include "checks/support/voicegroupbrowserdriver.h"
#include "mainwindow.h"
#include "project/projectidentity.h"
#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/workspaceui.h"
#include <variant>

namespace checks {

VoicegroupSaveTest::VoicegroupSaveTest(const QString &projectRoot, const QString &songLabel,
                                       const QString &screenshotPath)
    : m_sourceRoot(projectRoot)
    , m_songLabel(songLabel)
    , m_screenshotPath(screenshotPath)
{}

VoicegroupSaveTest::~VoicegroupSaveTest() = default;

void VoicegroupSaveTest::init()
{
    m_settingsDirectory = std::make_unique<QTemporaryDir>();
    QVERIFY2(m_settingsDirectory && m_settingsDirectory->isValid(),
             "could not create isolated QSettings directory");
    QSettings::setDefaultFormat(QSettings::IniFormat);
    QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, m_settingsDirectory->path());
    QSettings::setPath(QSettings::NativeFormat, QSettings::UserScope, m_settingsDirectory->path());

    QString error;
    m_project = ProjectFixture::copyOf(m_sourceRoot, error);
    QVERIFY2(m_project, qPrintable(error));

    m_window = std::make_unique<MainWindow>();
    m_window->m_persistSession = false;
    QVERIFY2(m_window->m_audioOk, "VoicegroupSave requires a working application audio engine");
    QVERIFY2(openSong(error), qPrintable(error));
}

void VoicegroupSaveTest::cleanup()
{
    disconnect(m_receiptConnection);
    m_browser.reset();
    m_document = nullptr;
    m_tab = nullptr;
    m_window.reset();
    m_project.reset();
    m_homeId.reset();
    m_failures.clear();
    m_savedReceipts = 0;
    m_settingsDirectory.reset();
}

bool VoicegroupSaveTest::openSong(QString &error)
{
    const std::optional<SongName> name = SongName::create(m_songLabel);
    if (!name) {
        error = QStringLiteral("invalid song label '%1'").arg(m_songLabel);
        return false;
    }
    const SongName openedName = *name;

    WorkspaceUi &workspace = *m_window->m_workspace;
    workspace.requestProjectOpenAt(m_project->root());
    if (async_wait::waitUntil([] { return true; },
                              [&workspace] {
                                  return workspace.projectState().state == ProjectOpenState::Ready;
                              }) != async_wait::Result::Ready) {
        error = QStringLiteral("project did not reach Ready");
        return false;
    }

    const SongInfo *target = nullptr;
    for (const SongInfo &song : workspace.projectState().snapshot.songs()) {
        if (song.label == m_songLabel && song.isPlayable()) {
            target = &song;
            break;
        }
    }
    if (!target) {
        error = QStringLiteral("no playable song '%1'").arg(m_songLabel);
        return false;
    }

    workspace.requestSongOpen(openedName);
    m_tab = workspace.selectedSongTab();
    if (!m_tab) {
        error = QStringLiteral("opening '%1' did not select a SongTab").arg(m_songLabel);
        return false;
    }
    if (!settle([&workspace, this, &openedName] {
            return workspace.songTabFor(openedName) == m_tab && m_tab->isReady();
        })) {
        error = QStringLiteral("song did not reach VoicegroupBound");
        return false;
    }
    if (!settle([&workspace, this] {
            return workspace.openProjectEnabled() && m_window->m_audio.songLoaded() &&
                   m_tab->voicegroupId() != nullptr;
        })) {
        error = QStringLiteral("song did not bind the audio engine");
        return false;
    }

    m_document = m_tab->view().document();
    if (!m_document) {
        error = QStringLiteral("SongView did not expose its document");
        return false;
    }
    m_browser = std::make_unique<VoicegroupBrowserDriver>(workspace);
    if (!m_browser->isAvailable()) {
        error = QStringLiteral("voicegroup browser was not constructed");
        return false;
    }
    const LoadedBankView *const initial = m_browser->selectedBankView();
    if (!initial || !m_tab->voicegroupId()) {
        error = QStringLiteral("no initial voicegroup binding was published");
        return false;
    }
    m_homeId = *m_tab->voicegroupId();
    m_homeArg = m_document->cfg().voicegroupArg;
    m_voicegroupPath = QDir(m_project->root()).filePath(m_homeId->sourceRelativePath());
    m_loadName = initial->loadName;
    m_voicegroupBytes = readFileBytes(m_voicegroupPath);
    m_midiBytes = readFileBytes(m_document->midPath());
    if (m_voicegroupBytes.isEmpty() || m_midiBytes.isEmpty()) {
        error = QStringLiteral("fixture is missing the bound voicegroup or MIDI bytes");
        return false;
    }
    if (!selectFirstDirectSoundVoice(error) || !selectFirstPlayableTrack(error))
        return false;

    m_receiptConnection =
        connect(m_window->m_projectWorkspace.get(), &ProjectWorkspace::songUpdatePublished, this,
                [this, expected = openedName](const SongUpdate &update) {
                    if (update.song != expected)
                        return;
                    if (std::holds_alternative<SongSaved>(update.payload))
                        ++m_savedReceipts;
                    else if (const auto *const failed = std::get_if<SongFailed>(&update.payload))
                        m_failures.append(failed->message);
                });
    return true;
}

bool VoicegroupSaveTest::selectFirstDirectSoundVoice(QString &error)
{
    const LoadedBankView *const view = m_browser->selectedBankView();
    if (!view) {
        error = QStringLiteral("voicegroup view disappeared before slot selection");
        return false;
    }
    for (int slot = 0; slot < VOICEGROUP_SIZE; ++slot) {
        const std::optional<VgVoice> &voice = view->slotViews.at(slot).voice;
        if (voice && (voice->macro == VgMacro::DirectSound ||
                      voice->macro == VgMacro::DirectSoundNoResample ||
                      voice->macro == VgMacro::DirectSoundAlt)) {
            m_dsSlot = slot;
            m_originalVoice = *voice;
            return true;
        }
    }
    error = QStringLiteral("fixture has no DirectSound-family voice");
    return false;
}

bool VoicegroupSaveTest::selectFirstPlayableTrack(QString &error)
{
    for (int track = 0; track < m_document->engineTrackCount(); ++track) {
        if (!m_document->notesForTrack(track).empty()) {
            m_track = track;
            return true;
        }
    }
    error = QStringLiteral("fixture song has no note-bearing track");
    return false;
}

int VoicegroupSaveTest::firstBlankSlot() const
{
    const LoadedBankView *const view = m_browser->selectedBankView();
    if (!view)
        return -1;
    for (int slot = 0; slot < VOICEGROUP_SIZE; ++slot) {
        if (!view->slotViews.at(slot).voice)
            return slot;
    }
    return -1;
}

int VoicegroupSaveTest::firstCgbSlot() const
{
    const LoadedBankView *const view = m_browser->selectedBankView();
    if (!view)
        return -1;
    for (int slot = 0; slot < VOICEGROUP_SIZE; ++slot) {
        const std::optional<VgVoice> &voice = view->slotViews.at(slot).voice;
        if (voice && vgMacroIsCgb(voice->macro))
            return slot;
    }
    return -1;
}

int VoicegroupSaveTest::firstSynthableSlot() const
{
    const VgSynthCatalog catalog = VoicegroupSource::synthInstruments(m_project->root());
    const LoadedBankView *const view = m_browser->selectedBankView();
    if (!view)
        return -1;
    for (int slot = 0; slot < VOICEGROUP_SIZE; ++slot) {
        const std::optional<VgVoice> &voice = view->slotViews.at(slot).voice;
        if (voice &&
            (voice->macro == VgMacro::DirectSound ||
             voice->macro == VgMacro::DirectSoundNoResample ||
             voice->macro == VgMacro::DirectSoundAlt) &&
            !catalog.find(voice->symbol))
            return slot;
    }
    return -1;
}

QString VoicegroupSaveTest::otherVoicegroupArg() const
{
    const QString current = m_document->cfg().voicegroupArg;
    for (const QString &arg : m_window->m_workspace->projectState().catalog.groupArgs) {
        if (arg != current)
            return arg;
    }
    return QString();
}

QByteArray VoicegroupSaveTest::readFileBytes(const QString &path) const
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return QByteArray();
    return file.readAll();
}

bool VoicegroupSaveTest::refreshCatalog()
{
    m_window->m_projectWorkspace->submit(ProjectOperation{RefreshCatalogInput{}});
    return settle([this] { return !m_browser->isLoading(); });
}

bool VoicegroupSaveTest::saveSelectedSong()
{
    const LoadedBankView *const bank = m_browser->selectedBankView();
    if (!m_document->isDirty() && !(bank && bank->dirty))
        return false;
    m_window->m_workspace->saveSelectedSong();
    return true;
}

void VoicegroupSaveTest::requestUndo()
{
    m_window->m_workspace->requestUndo();
}

void VoicegroupSaveTest::requestRedo()
{
    m_window->m_workspace->requestRedo();
}

bool VoicegroupSaveTest::settle(const std::function<bool()> &predicate) const
{
    return async_wait::waitUntil(
               [this] {
                   return m_window && m_tab && m_window->m_workspace->selectedSongTab() == m_tab;
               },
               [this, &predicate] {
                   return m_window->m_workspace->openProjectEnabled() && predicate();
               }) == async_wait::Result::Ready;
}

bool VoicegroupSaveTest::waitForBankRelease(int slot, int release, bool dirty) const
{
    return settle([this, slot, release, dirty] {
        const LoadedBankView *const bank = m_browser->selectedBankView();
        const LoadedVoiceGroup *const engine = m_window->m_audio.voicegroup();
        return bank && bank->dirty == dirty && bank->slotViews.at(slot).voice &&
               bank->slotViews.at(slot).voice->release == release && engine &&
               engine->voices[slot].release == static_cast<uint8_t>(release);
    });
}

bool VoicegroupSaveTest::waitForVoicegroup(const QString &arg, const VoicegroupId &id) const
{
    return settle([this, &arg, &id] {
        return m_document->cfg().voicegroupArg == arg && m_tab->voicegroupId() &&
               *m_tab->voicegroupId() == id;
    });
}

bool VoicegroupSaveTest::waitForCleanSave(int receiptsBefore) const
{
    return settle([this, receiptsBefore] {
        const LoadedBankView *const bank = m_browser->selectedBankView();
        return m_savedReceipts > receiptsBefore && !m_document->isDirty() && !(bank && bank->dirty);
    });
}
} // namespace checks

int runVoicegroupSaveCheck(const QString &projectRoot, const QString &songLabel,
                           const QString &screenshotPath, const QStringList &qtArguments)
{
    checks::VoicegroupSaveTest test(projectRoot, songLabel, screenshotPath);
    QStringList arguments{QStringLiteral("voicegroup-save")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
