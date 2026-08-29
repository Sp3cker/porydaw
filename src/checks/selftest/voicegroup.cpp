#include "harness.h"

#include "checks/support/asyncwait.h"
#include "checks/support/voicegroupbrowserdriver.h"
#include "mainwindow.h"

#include <QDir>
#include <QFile>
#include <QLineEdit>

#include "ui/dragspinbox.h"
#include "ui/songtab.h"
#include "ui/voicegroupbrowser.h"
#include "ui/workspaceui.h"

namespace checks {

bool SelfTestHarness::runVoicegroupScenario()
{
    VoicegroupBrowser *const browser = m_window.findChild<VoicegroupBrowser *>();
    if (!browser) {
        qWarning("selftest-voicegroup: voicegroup browser not found");
        return false;
    }
    const LoadedVoiceGroup *const bank = m_window.m_audio.voicegroup();
    if (!m_tab->voicegroupId() || !bank) {
        qInfo("selftest-voicegroup: skipped (no editable source)");
        return closeCleanly();
    }
    VoicegroupBrowserDriver voicegroupDriver(*m_window.m_workspace);
    const auto rowSymbol = [&voicegroupDriver](int slot) {
        return voicegroupDriver.slotRowText(slot).value(0).mid(5);
    };
    auto directSoundSlot = -1;
    auto donorSlot = -1;
    for (auto i = 0; i < VOICEGROUP_SIZE; ++i) {
        const ToneData &tone = bank->voices[i];
        const bool directSound = tone.type == VOICE_DIRECTSOUND ||
                                 tone.type == VOICE_DIRECTSOUND_NO_RESAMPLE ||
                                 tone.type == VOICE_DIRECTSOUND_ALT;
        if (!directSound || QByteArray(bank->voiceNames[i]).isEmpty())
            continue;
        if (directSoundSlot < 0)
            directSoundSlot = i;
        else if (donorSlot < 0 && rowSymbol(i) != rowSymbol(directSoundSlot))
            donorSlot = i;
    }
    if (directSoundSlot < 0) {
        qInfo("selftest-voicegroup: skipped (no sample voices)");
        return closeCleanly();
    }
    browser->selectSlot(directSoundSlot);
    DragSpinBox *const releaseSpin = voicegroupDriver.releaseSpinBox();
    if (!releaseSpin || releaseSpin->value() != int(bank->voices[directSoundSlot].release)) {
        qWarning("selftest-voicegroup: editor did not show slot %d", directSoundSlot);
        return false;
    }
    const int originalRelease = bank->voices[directSoundSlot].release;
    const ToneData originalTone = bank->voices[directSoundSlot];
    const QByteArray originalName(bank->voiceNames[directSoundSlot]);
    const QByteArray donorName =
        donorSlot >= 0 ? QByteArray(bank->voiceNames[donorSlot]) : QByteArray{};
    const QString donorSymbol = donorSlot >= 0 ? rowSymbol(donorSlot) : QString{};
    const QString sourcePath =
        QDir(m_projectRoot).filePath(m_tab->voicegroupId()->sourceRelativePath());
    QFile source(sourcePath);
    if (!source.open(QIODevice::ReadOnly)) {
        qWarning("selftest-voicegroup: cannot read source %s", qUtf8Printable(sourcePath));
        return false;
    }
    const QByteArray fileBefore = source.readAll();
    source.close();
    const auto waitForBankOperation = [this](const auto &applied, uint64_t before) {
        return async_wait::waitUntil([this] { return tabIsLive(); },
                                     [this, &applied, before] {
                                         return m_window.m_workspace->bankActionsEnabled() &&
                                                m_window.m_audio.voicegroup() && applied() &&
                                                m_window.m_audio.transport() ==
                                                    Transport::Playing &&
                                                m_window.m_audio.playheadSamples() > before;
                                     });
    };
    if (!beginObservedPlayback())
        return false;
    const uint64_t beforeScalarEdit = m_window.m_audio.playheadSamples();
    const int flippedRelease = originalRelease == 25 ? 26 : 25;
    releaseSpin->setValue(flippedRelease);
    const auto scalarWait = waitForBankOperation(
        [this, directSoundSlot, flippedRelease] {
            return m_window.m_audio.voicegroup()->voices[directSoundSlot].release == flippedRelease;
        },
        beforeScalarEdit);
    if (scalarWait != async_wait::Result::Ready || !m_window.m_workspace->selectedSongDirty() ||
        m_tab->document().isDirty()) {
        qWarning("selftest-voicegroup: scalar edit did not reload the bank while playing");
        return false;
    }
    auto structuralEditApplied = false;
    if (donorSlot >= 0) {
        if (!beginObservedPlayback())
            return false;
        const uint64_t beforeStructuralEdit = m_window.m_audio.playheadSamples();
        voicegroupDriver.openSamplePickerPopup();
        QLineEdit *const search = voicegroupDriver.samplePickerFilterField();
        if (search && voicegroupDriver.samplePickerPopupIsVisible()) {
            search->setText(donorSymbol);
            if (voicegroupDriver.currentPickerRowSymbol() == donorSymbol) {
                voicegroupDriver.clickCurrentPickerRow();
                voicegroupDriver.clickCurrentPickerRow();
                const auto structuralWait = waitForBankOperation(
                    [this, directSoundSlot, &donorName] {
                        return QByteArray(
                                   m_window.m_audio.voicegroup()->voiceNames[directSoundSlot]) ==
                               donorName;
                    },
                    beforeStructuralEdit);
                if (structuralWait != async_wait::Result::Ready) {
                    qWarning("selftest-voicegroup: structural edit did not reload the bank while "
                             "playing");
                    return false;
                }
                structuralEditApplied = true;
            } else {
                voicegroupDriver.hideSamplePickerPopup();
                qInfo("selftest-voicegroup: structural edit skipped (donor row not selectable)");
            }
        } else {
            voicegroupDriver.hideSamplePickerPopup();
            qInfo("selftest-voicegroup: structural edit skipped (picker unavailable)");
        }
    }
    if (structuralEditApplied) {
        if (!beginObservedPlayback())
            return false;
        const uint64_t beforeStructuralUndo = m_window.m_audio.playheadSamples();
        m_window.m_workspace->requestUndo();
        if (waitForBankOperation(
                [this, directSoundSlot, &originalName] {
                    return QByteArray(m_window.m_audio.voicegroup()->voiceNames[directSoundSlot]) ==
                           originalName;
                },
                beforeStructuralUndo) != async_wait::Result::Ready) {
            qWarning("selftest-voicegroup: structural undo did not restore the bank while "
                     "playing");
            return false;
        }
    }
    if (!beginObservedPlayback())
        return false;
    const uint64_t beforeScalarUndo = m_window.m_audio.playheadSamples();
    m_window.m_workspace->requestUndo();
    if (waitForBankOperation(
            [this, directSoundSlot, originalRelease, &originalName] {
                const LoadedVoiceGroup *const current = m_window.m_audio.voicegroup();
                return current->voices[directSoundSlot].release == originalRelease &&
                       QByteArray(current->voiceNames[directSoundSlot]) == originalName;
            },
            beforeScalarUndo) != async_wait::Result::Ready) {
        qWarning("selftest-voicegroup: scalar undo did not restore the bank while playing");
        return false;
    }
    if (!source.open(QIODevice::ReadOnly)) {
        qWarning("selftest-voicegroup: cannot reread source %s", qUtf8Printable(sourcePath));
        return false;
    }
    const QByteArray fileAfter = source.readAll();
    const ToneData &restored = m_window.m_audio.voicegroup()->voices[directSoundSlot];
    const bool restoredExactly =
        !m_window.m_workspace->selectedSongDirty() && !m_tab->document().isDirty() &&
        fileAfter == fileBefore && restored.type == originalTone.type &&
        restored.key == originalTone.key && restored.length == originalTone.length &&
        restored.panSweep == originalTone.panSweep && restored.attack == originalTone.attack &&
        restored.decay == originalTone.decay && restored.sustain == originalTone.sustain &&
        restored.release == originalTone.release &&
        QByteArray(m_window.m_audio.voicegroup()->voiceNames[directSoundSlot]) == originalName;
    if (!restoredExactly) {
        qWarning("selftest-voicegroup: edit and undo did not restore the exact source state");
        return false;
    }
    qInfo("selftest-voicegroup: edit + bank reload + undo OK (slot %d, donor %d)", directSoundSlot,
          donorSlot);
    return closeCleanly();
}

} // namespace checks
