#include "ui/workspaceui.h"

#include <QDialog>
#include <QDir>
#include <QFile>
#include <QFileDialog>
#include <QFileInfo>
#include <QMainWindow>
#include <QMessageBox>
#include <QRegularExpression>
#include <QSettings>

#include <optional>
#include <utility>

#include "audio/auditionslots.h"
#include "audio/sampledata.h"
#include "audio/sampleimport.h"
#include "audio/sf2reader.h"
#include "core/smf.h"
#include "project/samplereg.h"
#include "ui/newsongwizard.h"
#include "ui/sampleeditordialog.h"
#include "ui/sf2zonepicker.h"
#include "ui/songtab.h"

namespace {
const QString kSampleSlotPrefix = QStringLiteral("DirectSoundWaveData_");
} // namespace

// ---- New song / MIDI import --------------------------------------------------

void WorkspaceUi::runNewSongWizard()
{
    if (!m_state.snapshot.isOpen() || projectBusy() || m_dialogOps > 0)
        return;
    const NewSongWizard::ProjectData data{m_state.snapshot.songs(), m_state.snapshot.players(),
                                          m_state.catalog.groupArgs,
                                          m_state.catalog.perFileVoicegroups};
    NewSongWizard wizard(data, &m_host);
    if (wizard.exec() != QDialog::Accepted)
        return;
    submitCreateSong(wizard);
}

void WorkspaceUi::runMidiImport()
{
    if (!m_state.snapshot.isOpen() || projectBusy() || m_dialogOps > 0)
        return;
    QSettings settings;
    const QString startDir =
        settings.value(QStringLiteral("lastImportDir"), QDir::homePath()).toString();
    const QString path =
        QFileDialog::getOpenFileName(&m_host, tr("Import MIDI"), startDir, tr("MIDI (*.mid)"));
    if (path.isEmpty())
        return;
    QString error;
    SmfFile smf;
    if (!SmfFile::readFile(path, &smf, &error)) {
        QMessageBox::warning(&m_host, tr("Import MIDI"), error);
        return;
    }
    settings.setValue(QStringLiteral("lastImportDir"), QFileInfo(path).path());
    const NewSongWizard::ProjectData data{m_state.snapshot.songs(), m_state.snapshot.players(),
                                          m_state.catalog.groupArgs,
                                          m_state.catalog.perFileVoicegroups};
    NewSongWizard wizard(data, std::move(smf), path, &m_host);
    if (wizard.exec() != QDialog::Accepted)
        return;
    submitCreateSong(wizard);
}

void WorkspaceUi::submitCreateSong(NewSongWizard &wizard)
{
    if (!m_state.snapshot.isOpen() || projectBusy() || m_dialogOps > 0)
        return;
    CreateSongInput input{wizard.label(), wizard.constant(),          wizard.player(),
                          wizard.cfg(),   wizard.newVoicegroupName(), wizard.songFile()};
    m_pendingCreatedLabel = input.label;
    m_pendingCreatedNewVoicegroup = !input.newVoicegroup.isEmpty();
    m_dialogOps++;
    updateOpenGate();
    emit projectOperationRequested(ProjectOperation{std::move(input)});
}

// ---- Audition sample set ------------------------------------------------------

void WorkspaceUi::ensureSampleSet()
{
    // One load in flight: browse auditions and badge lookups re-enter this
    // while the request is on the FIFO, and the set lands only once.
    if (m_sampleSet || !m_state.snapshot.isOpen() || projectBusy() || m_dialogOps > 0)
        return;
    m_dialogOps++;
    updateOpenGate();
    emit projectOperationRequested(ProjectOperation{LoadSampleSetInput{
        m_state.catalog.directSound, m_state.catalog.progWave, m_state.catalog.keysplits}});
}

void WorkspaceUi::importSample()
{
    runImportFlow(std::nullopt); // the general import has no destination slot
}

void WorkspaceUi::runImportFlow(std::optional<int> slot)
{
    if (!m_state.snapshot.isOpen() || projectBusy() || m_dialogOps > 0)
        return;
    ensureSampleSet();
    // The flows are exclusive: entering one drops the other's commit-time
    // bookkeeping so a later commit can never reuse a stale slot.
    m_pendingEditSampleName.clear();
    m_pendingEditSampleSlot = -1;
    m_pendingImportSlot = slot;
    m_dialogOps++;
    updateOpenGate();
    emit projectOperationRequested(ProjectOperation{ProbeSamplesInput{}});
}

void WorkspaceUi::continueImportFlow(const SampleFormatProbe &probe)
{
    const auto slot = m_pendingImportSlot;
    m_pendingImportSlot.reset();
    if (!m_state.snapshot.isOpen() || projectBusy())
        return;
    if (!probe.ok()) {
        QMessageBox::warning(&m_host, tr("Import Sample"), probe.refusal);
        return;
    }
    QSettings settings;
    const QString startDir =
        settings.value(QStringLiteral("lastSampleDir"), QDir::homePath()).toString();
    const QString path = QFileDialog::getOpenFileName(
        &m_host, tr("Import Sample"), startDir,
        tr("Audio files (*.wav *.aif *.aiff *.mp3 *.flac *.ogg *.sf2);;"
           "All files (*)"));
    if (path.isEmpty())
        return;
    settings.setValue(QStringLiteral("lastSampleDir"), QFileInfo(path).path());

    QFile sourceFile(path);
    if (!sourceFile.open(QIODevice::ReadOnly)) {
        QMessageBox::warning(&m_host, tr("Import Sample"), tr("Cannot read %1.").arg(path));
        return;
    }
    const QByteArray sourceBytes = sourceFile.readAll();
    sourceFile.close();

    ImportedSample sample;
    QString error;
    // Decode choices beyond the source bytes, recorded in the provenance
    // sidecar so "Edit sample…" can re-decode identically.
    bool leftOnly = false;
    int sf2Zone = -1;
    const auto fail = [this, &path, &error](const char *context) {
        QMessageBox::warning(&m_host, context, tr("%1: %2").arg(QFileInfo(path).fileName(), error));
    };
    if (sf2Magic(sourceBytes)) {
        // SoundFonts hold many samples: pick a zone first (FORMATS.md §5);
        // the chosen zone then rides the ordinary editor pipeline.
        Sf2File font;
        if (!readSf2Bytes(sourceBytes, path, &font, &error)) {
            fail("Import Sample");
            return;
        }
        Sf2ZonePicker picker(font, &m_host);
        if (picker.exec() != QDialog::Accepted)
            return;
        if (!extractSf2Zone(font, picker.selectedZone(), &sample, &error)) {
            fail("Import Sample");
            return;
        }
        sf2Zone = picker.selectedZone();
    } else {
        if (!importAudioBytes(sourceBytes, path, &sample, &error)) {
            fail("Import Sample");
            return;
        }
        if (sample.phaseCancelStereo &&
            QMessageBox::question(&m_host, tr("Import Sample"),
                                  tr("The left and right channels of %1 are phase-cancelling — "
                                     "the mono mix may sound hollow.\n\n"
                                     "Import the left channel only instead?")
                                      .arg(QFileInfo(path).fileName())) == QMessageBox::Yes) {
            if (!importAudioBytes(sourceBytes, path, &sample, &error, true)) {
                fail("Import Sample");
                return;
            }
            leftOnly = true;
        }
    }

    AuditionSlots::Adsr destAdsr;
    bool hasDestAdsr = false;
    SongTab *const requested = m_selectedTab;
    if (slot && requested && requested->isReady()) {
        const LoadedBankView *const view = bankViewFor(*requested);
        const VgVoice *dest = nullptr;
        if (view && *slot >= 0 && *slot < view->slotViews.size() && view->slotViews.at(*slot).voice)
            dest = &*view->slotViews.at(*slot).voice;
        if (dest && !vgMacroIsCgb(dest->macro)) {
            destAdsr = {uint8_t(dest->attack), uint8_t(dest->decay), uint8_t(dest->sustain),
                        uint8_t(dest->release)};
            hasDestAdsr = true;
        }
    }
    SampleEditorDialog::NameValidator validateSampleName = [this](const QString &name,
                                                                  QString *validationError) {
        return validateNewSampleName(name, validationError);
    };
    std::optional<SampleEditorDialog> dialog;
    if (m_sampleAuditionEngine) {
        dialog.emplace(std::move(sample), std::move(validateSampleName),
                       m_sampleAuditionEngine->get(), hasDestAdsr ? &destAdsr : nullptr, &m_host);
    } else {
        dialog.emplace(std::move(sample), std::move(validateSampleName),
                       SampleEditorDialog::NoAudio{}, hasDestAdsr ? &destAdsr : nullptr, &m_host);
    }
    if (dialog->exec() != QDialog::Accepted)
        return;

    if (!m_state.snapshot.isOpen() || projectBusy() || m_dialogOps > 0)
        return;
    CommitSampleInput input;
    input.name = dialog->sampleName();
    input.wavBytes = dialog->wavBytes();
    SampleSidecar sidecar;
    sidecar.sourcePath = QFileInfo(path).absoluteFilePath();
    sidecar.sourceSha256 = SampleRegistrar::sourceHashHex(sourceBytes);
    sidecar.leftOnly = leftOnly;
    sidecar.sf2Zone = sf2Zone;
    sidecar.params = dialog->document()->params();
    input.sidecar = std::move(sidecar);
    m_pendingImportSlot = slot; // for the committed assignment
    m_dialogOps++;
    updateOpenGate();
    emit projectOperationRequested(ProjectOperation{std::move(input)});
}

bool WorkspaceUi::validateNewSampleName(const QString &name, QString *error) const
{
    const auto valid = QRegularExpression(QStringLiteral("^[a-z0-9_]+$")).match(name);
    if (name.isEmpty() || !valid.hasMatch()) {
        if (error)
            *error = QStringLiteral("use lowercase letters, digits, and '_'.");
        return false;
    }
    if (m_state.catalog.directSound.contains(kSampleSlotPrefix + name)) {
        if (error)
            *error = QStringLiteral("a sample with that name already exists.");
        return false;
    }
    return true;
}

// ---- Sample edit (reopen committed sample) ------------------------------------

void WorkspaceUi::runEditSampleFlow(int slot)
{
    SongTab *const tab = m_selectedTab;
    if (!m_state.snapshot.isOpen() || projectBusy() || m_dialogOps > 0 || !tab || !tab->isReady())
        return;
    const LoadedBankView *const view = bankViewFor(*tab);
    if (!view || slot < 0 || slot >= view->slotViews.size() || !view->slotViews.at(slot).voice)
        return;
    const QString symbol = view->slotViews.at(slot).voice->symbol;
    if (!symbol.startsWith(kSampleSlotPrefix)) {
        QMessageBox::warning(&m_host, tr("Edit Sample"),
                             tr("This voice does not reference a project sample."));
        return;
    }
    m_dialogOps++;
    updateOpenGate();
    // Flows are exclusive: a leftover import destination from an abandoned
    // import must never ride this flow's commit.
    m_pendingImportSlot.reset();
    m_pendingEditSampleName = symbol.mid(kSampleSlotPrefix.size());
    m_pendingEditSampleSlot = slot;
    emit projectOperationRequested(ProjectOperation{ReadSampleInput{m_pendingEditSampleName}});
}

void WorkspaceUi::continueEditSampleFlow(const SampleRead &read)
{
    const int slot = m_pendingEditSampleSlot;
    m_pendingEditSampleSlot = -1;
    const QString name = m_pendingEditSampleName;
    m_pendingEditSampleName.clear();
    SongTab *const tab = m_selectedTab;
    if (!m_state.snapshot.isOpen() || projectBusy() || !tab || !tab->isReady())
        return;

    // Re-decode from the provenance sidecar when its source file still
    // hashes identically; otherwise decode the committed 8-bit .wav.
    bool fromSource = false;
    bool leftOnly = false;
    int sf2Zone = -1;
    SampleSidecar sidecar = read.sidecar;
    ImportedSample sample;
    QString error;
    if (read.sidecarLoaded) {
        QFile sourceFile(sidecar.sourcePath);
        if (sourceFile.open(QIODevice::ReadOnly)) {
            // One read feeds both the identity hash and the re-decode.
            const QByteArray sourceBytes = sourceFile.readAll();
            sourceFile.close();
            if (SampleRegistrar::sourceHashHex(sourceBytes) == sidecar.sourceSha256) {
                bool decoded = false;
                if (sidecar.sf2Zone >= 0) {
                    Sf2File font;
                    if (readSf2Bytes(sourceBytes, sidecar.sourcePath, &font, &error) &&
                        extractSf2Zone(font, sidecar.sf2Zone, &sample, &error)) {
                        decoded = true;
                        sf2Zone = sidecar.sf2Zone;
                    }
                } else if (importAudioBytes(sourceBytes, sidecar.sourcePath, &sample, &error,
                                            sidecar.leftOnly)) {
                    decoded = true;
                    leftOnly = sidecar.leftOnly;
                }
                fromSource = decoded;
            }
        }
    }
    if (!fromSource && !importAudioBytes(read.wavBytes, read.wavPath, &sample, &error)) {
        QMessageBox::warning(&m_host, tr("Edit Sample"), error);
        return;
    }

    const LoadedBankView *const view = bankViewFor(*tab);
    const VgVoice *voice = nullptr;
    if (view && slot >= 0 && slot < view->slotViews.size() && view->slotViews.at(slot).voice)
        voice = &*view->slotViews.at(slot).voice;
    if (!voice)
        return;
    AuditionSlots::Adsr destAdsr;
    bool hasDestAdsr = false;
    if (!vgMacroIsCgb(voice->macro)) {
        destAdsr = {uint8_t(voice->attack), uint8_t(voice->decay), uint8_t(voice->sustain),
                    uint8_t(voice->release)};
        hasDestAdsr = true;
    }
    SampleEditorDialog::NameValidator validateSampleName = [name](const QString &candidate,
                                                                  QString *validationError) {
        if (candidate == name)
            return true;
        if (validationError)
            *validationError = QObject::tr("the sample keeps its registered name (%1).").arg(name);
        return false;
    };
    std::optional<SampleEditorDialog> dialog;
    if (m_sampleAuditionEngine) {
        dialog.emplace(std::move(sample), std::move(validateSampleName),
                       m_sampleAuditionEngine->get(), hasDestAdsr ? &destAdsr : nullptr, &m_host);
    } else {
        dialog.emplace(std::move(sample), std::move(validateSampleName),
                       SampleEditorDialog::NoAudio{}, hasDestAdsr ? &destAdsr : nullptr, &m_host);
    }
    dialog->setEditTarget(name);
    if (fromSource)
        dialog->applyParamsExternal(sidecar.params);
    if (dialog->exec() != QDialog::Accepted)
        return;

    if (!m_state.snapshot.isOpen() || projectBusy() || m_dialogOps > 0)
        return;
    CommitSampleInput input;
    input.name = name;
    input.wavBytes = dialog->wavBytes();
    if (fromSource) {
        sidecar.params = dialog->document()->params();
        input.sidecar = std::move(sidecar);
    } else {
        input.removeSidecar = true;
    }
    input.update = true;
    m_pendingEditSampleSlot = slot; // for the committed refresh
    m_dialogOps++;
    updateOpenGate();
    emit projectOperationRequested(ProjectOperation{std::move(input)});
}

// ---- Sample commit completion -------------------------------------------------

void WorkspaceUi::handleSampleCommitted(const SampleCommitted &committed)
{
    // The commit is finished either way: drop both flows' bookkeeping
    // before anything can early-return with it still armed.
    const auto importSlot = m_pendingImportSlot;
    m_pendingImportSlot.reset();
    const int editSlot = std::exchange(m_pendingEditSampleSlot, -1);
    if (!committed.committed) {
        QMessageBox::warning(&m_host, tr("Sample"), tr("Sample commit failed."));
        return;
    }
    m_sampleSet.reset();
    if (!committed.sidecarSaved && !committed.sidecarError.isEmpty())
        showStatus(tr("Sample imported, but saving its edit history failed: %1")
                       .arg(committed.sidecarError),
                   8000);
    m_dialogOps++;
    updateOpenGate();
    emit projectOperationRequested(ProjectOperation{RefreshCatalogInput{}});

    // A browser-initiated import points its slot's voice at the new sample
    // through the ordinary bank-edit path.
    const auto slot = importSlot;
    SongTab *const tab = m_selectedTab;
    if (slot && *slot >= 0 && tab && tab->isReady() && bankActionsEnabled()) {
        const LoadedBankView *const view = bankViewFor(*tab);
        const VgVoice *dest = nullptr;
        if (view && *slot < view->slotViews.size() && view->slotViews.at(*slot).voice)
            dest = &*view->slotViews.at(*slot).voice;
        const bool keepDest = dest && (dest->macro == VgMacro::DirectSound ||
                                       dest->macro == VgMacro::DirectSoundNoResample ||
                                       dest->macro == VgMacro::DirectSoundAlt);
        VgVoice voice;
        if (keepDest) {
            voice = *dest;
        } else {
            voice.macro = VgMacro::DirectSound;
            voice.key = 60;
            voice.pan = 0;
            const VgAdsr adsr = vgDefaultAdsr(m_state.catalog.typicalAdsr, voice.macro,
                                              kSampleSlotPrefix + committed.name);
            voice.attack = adsr.attack;
            voice.decay = adsr.decay;
            voice.sustain = adsr.sustain;
            voice.release = adsr.release;
        }
        voice.symbol = kSampleSlotPrefix + committed.name;
        submitPickerEdit(*slot, voice);
        m_voicegroupBrowser->revealSlot(*slot);
    }
    showStatus(
        editSlot >= 0
            ? tr("Saved %1 — the ROM's .bin recompiles on the next build").arg(committed.name)
            : tr("Imported %1 — %2%1 is now available to voicegroups")
                  .arg(committed.name, kSampleSlotPrefix),
        8000);
}
