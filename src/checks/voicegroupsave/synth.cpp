#include "checks/voicegroupsave/tst_voicegroupsave.h"

#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QSpinBox>
#include <QUndoStack>
#include <QtTest>

#include <array>

#include "checks/support/songfixture.h"
#include "checks/support/voicegroupbrowserdriver.h"
#include "core/songdocument.h"
#include "mainwindow.h"
#include "ui/workspaceui.h"

namespace checks {

void VoicegroupSaveTest::synthDefinitionsStayMemoryOnlyUntilSave()
{
    const QString synthPath =
        m_project->root() + QStringLiteral("/sound/direct_sound_synth_data.inc");
    const QString macroDir = m_project->root() + QStringLiteral("/asm/macros");
    QVERIFY(QDir().mkpath(macroDir));
    {
        QFile macros(macroDir + QStringLiteral("/vgsavecheck_synth.inc"));
        QVERIFY(macros.open(QIODevice::WriteOnly));
        QCOMPARE(macros.write("\t.macro set_synth_pulse base_duty=0x80, duty_step=0x00, "
                              "mod_depth=0x00, duty_phase=0x00\n\t.endm\n"
                              "\t.macro set_synth_saw\n\t.endm\n"
                              "\t.macro set_synth_triangle\n\t.endm\n") > 0,
                 true);
    }
    {
        QFile data(synthPath);
        QVERIFY(data.open(QIODevice::WriteOnly | QIODevice::Append));
        QCOMPARE(data.write("\n\t.align 2\nVgSaveCheckSaw::\n\tset_synth_saw\n") > 0, true);
    }
    QVERIFY2(refreshCatalog(), "synth catalog refresh did not settle");
    QVERIFY2(settle([this] {
                 return m_window->m_workspace->projectState().catalog.synths.find(
                            QStringLiteral("VgSaveCheckSaw")) != nullptr;
             }),
             "synth setup definition did not reach the published catalog");
    const VgSynthCatalog setupCatalog = VoicegroupSource::synthInstruments(m_project->root());
    const int definitionsAfterSetup = setupCatalog.defs.size();
    const QByteArray synthBytesSetup = readFileBytes(synthPath);
    const int undoIndexBeforeSynth = m_document->undoStack()->index();

    const int synthSlot = firstSynthableSlot();
    QVERIFY2(synthSlot >= 0, "fixture must provide a non-synth DirectSound voice for synth flow");
    const VgVoice original = *m_browser->selectedBankView()->slotViews.at(synthSlot).voice;
    m_browser->selectSlot(synthSlot);
    QVERIFY(m_browser->hasSynthEditorControls());
    QVERIFY(m_browser->activateSynthType());
    QVERIFY2(settle([this, synthSlot, &original] {
                 const LoadedBankView *const bank = m_browser->selectedBankView();
                 const LoadedVoiceGroup *const engine = m_window->m_audio.voicegroup();
                 return bank && bank->slotViews.at(synthSlot).voice &&
                        bank->slotViews.at(synthSlot).voice->symbol != original.symbol && engine &&
                        engine->voices[synthSlot].wav && engine->voices[synthSlot].wav->size == 0;
             }),
             "synth type did not create a memory-only tone");
    QVERIFY(m_browser->activateSynthWave(0));
    const QString defaultPulse = vgSynthSymbolName(VgSynthDesc{});
    QVERIFY2(settle([this, synthSlot, &defaultPulse] {
                 const LoadedBankView *const bank = m_browser->selectedBankView();
                 return bank && bank->slotViews.at(synthSlot).voice &&
                        bank->slotViews.at(synthSlot).voice->symbol == defaultPulse;
             }),
             "pulse selection did not adopt the 50 percent default");

    struct Param final {
        int value;
        int VgSynthDesc::*field;
    };
    const std::array<Param, 4> script = {{{0x21, &VgSynthDesc::baseDuty},
                                          {0x43, &VgSynthDesc::dutyStep},
                                          {0x65, &VgSynthDesc::modDepth},
                                          {0x87, &VgSynthDesc::phase}}};
    VgSynthDesc soFar{};
    for (int index = 0; index < int(script.size()); ++index) {
        QSpinBox *const field = m_browser->synthParameterField(index);
        QVERIFY(field);
        soFar.*script.at(size_t(index)).field = script.at(size_t(index)).value;
        field->setValue(script.at(size_t(index)).value);
        const QString expected = vgSynthSymbolName(soFar);
        QVERIFY2(settle([this, synthSlot, &expected] {
                     const LoadedBankView *const bank = m_browser->selectedBankView();
                     return bank && bank->slotViews.at(synthSlot).voice &&
                            bank->slotViews.at(synthSlot).voice->symbol == expected;
                 }),
                 "synth parameter did not apply as a param-named definition");
    }
    const QString wanted = vgSynthSymbolName(VgSynthDesc{0, 0x21, 0x43, 0x65, 0x87});
    QCOMPARE(m_browser->selectedBankView()->slotViews.at(synthSlot).voice->symbol, wanted);
    QCOMPARE(readFileBytes(synthPath), synthBytesSetup);
    QVERIFY(!m_browser->visibleSymbolComboContains(wanted));
    QVERIFY2(settle([this, synthSlot, &wanted] {
                 const LoadedVoiceGroup *const engine = m_window->m_audio.voicegroup();
                 return engine && engine->voices[synthSlot].wav &&
                        engine->voices[synthSlot].wav->size == 0 &&
                        uint8_t(engine->voices[synthSlot].wav->data[1]) == 0 &&
                        uint8_t(engine->voices[synthSlot].wav->data[2]) == 0x21 &&
                        uint8_t(engine->voices[synthSlot].wav->data[5]) == 0x87 &&
                        QString::fromUtf8(engine->voiceNames[synthSlot]) == wanted;
             }),
             "loaded synth tone did not carry the edited waveform bytes");

    const int saveReceipt = m_savedReceipts;
    QVERIFY(saveSelectedSong());
    QVERIFY2(waitForCleanSave(saveReceipt), "synth save did not settle");
    QVERIFY(readFileBytes(synthPath).contains(wanted.toUtf8() + "::"));
    bool wired = false;
    for (const QString &directory :
         {m_project->root() + QStringLiteral("/data"), m_project->root()}) {
        QDirIterator files(directory, {QStringLiteral("*.s")}, QDir::Files);
        while (files.hasNext() && !wired)
            wired = readFileBytes(files.next()).contains("direct_sound_synth_data.inc");
    }
    QVERIFY(wired);
    QCOMPARE(VoicegroupSource::synthInstruments(m_project->root()).defs.size(),
             definitionsAfterSetup + 1);
    QVERIFY2(refreshCatalog(), "saved synth catalog refresh did not settle");
    QVERIFY2(settle([this, &wanted] {
                 return m_window->m_workspace->projectState().catalog.synths.find(wanted) !=
                        nullptr;
             }),
             "saved synth definition did not enter the published catalog");
    QVERIFY(m_browser->visibleSymbolComboContains(wanted));

    const int undoIndexBeforeFlips = m_document->undoStack()->index();
    QVERIFY(m_browser->activateSynthWave(1));
    QVERIFY2(settle([this, synthSlot, &wanted] {
                 const LoadedBankView *const bank = m_browser->selectedBankView();
                 return bank && bank->slotViews.at(synthSlot).voice &&
                        bank->slotViews.at(synthSlot).voice->symbol != wanted;
             }),
             "saw waveform selection did not land");
    const QString sawSymbol = m_browser->selectedBankView()->slotViews.at(synthSlot).voice->symbol;
    QCOMPARE(sawSymbol, QStringLiteral("VgSaveCheckSaw"));
    const VgSynthCatalog sawCatalog = VoicegroupSource::synthInstruments(m_project->root());
    const VgSynthDesc *const saw = sawCatalog.find(sawSymbol);
    QVERIFY(saw);
    QCOMPARE(saw->waveform, 1);
    QVERIFY(m_browser->activateSynthWave(0));
    QVERIFY2(settle([this, synthSlot, &sawSymbol] {
                 const LoadedBankView *const bank = m_browser->selectedBankView();
                 return bank && bank->slotViews.at(synthSlot).voice &&
                        bank->slotViews.at(synthSlot).voice->symbol != sawSymbol;
             }),
             "return to pulse did not land");
    const QString pulseSymbol =
        m_browser->selectedBankView()->slotViews.at(synthSlot).voice->symbol;
    const VgSynthCatalog pulseCatalog = VoicegroupSource::synthInstruments(m_project->root());
    const VgSynthDesc *const pulse = pulseCatalog.find(pulseSymbol);
    QVERIFY((pulse && *pulse == VgSynthDesc{}) || pulseSymbol == defaultPulse);
    while (m_document->undoStack()->index() > undoIndexBeforeFlips) {
        const int before = m_document->undoStack()->index();
        requestUndo();
        QVERIFY2(settle([this, before] { return m_document->undoStack()->index() == before - 1; }),
                 "waveform undo did not apply exactly one history command");
    }
    QCOMPARE(m_browser->selectedBankView()->slotViews.at(synthSlot).voice->symbol, wanted);

    const QByteArray synthBytesSaved = readFileBytes(synthPath);
    while (m_document->undoStack()->index() > undoIndexBeforeSynth) {
        const int before = m_document->undoStack()->index();
        requestUndo();
        QVERIFY2(settle([this, before] { return m_document->undoStack()->index() == before - 1; }),
                 "synth undo did not apply exactly one history command");
    }
    const int postUndoSave = m_savedReceipts;
    QVERIFY(saveSelectedSong());
    QVERIFY2(waitForCleanSave(postUndoSave), "post-undo synth save did not settle");
    QCOMPARE(readFileBytes(m_voicegroupPath), m_voicegroupBytes);
    QCOMPARE(readFileBytes(synthPath), synthBytesSaved);
}

} // namespace checks
