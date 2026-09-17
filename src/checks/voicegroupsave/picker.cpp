#include "checks/voicegroupsave/tst_voicegroupsave.h"

#include <QFileInfo>
#include <QLineEdit>
#include <QtTest>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <span>
#include <vector>

#include "audio/audioengine.h"
#include "checks/support/audioengineaccess.h"
#include "checks/support/eventsynth.h"
#include "checks/support/voicegroupbrowserdriver.h"
#include "core/songdocument.h"
#include "mainwindow.h"
#include "ui/soundbrowser/soundbrowser.h"
#include "ui/theme/themeruntime.h"
#include "ui/workspaceui.h"

namespace checks {
namespace {

double pickerPeak(const std::vector<float> &pcm)
{
    double result = 0.0;
    for (const float sample : pcm)
        result = std::max(result, std::abs(double(sample)));
    return result;
}

std::vector<float> renderParkedSeconds(AudioEngine &engine, double seconds)
{
    const auto frames = std::max(uint32_t{1}, uint32_t(std::ceil(seconds * engine.sampleRate())));
    std::vector<float> pcm(static_cast<std::size_t>(frames) * 2);
    AudioEngineTestAccess::renderParked(engine, std::span<float>(pcm));
    return pcm;
}

} // namespace

void VoicegroupSaveTest::backgroundBankPublicationKeepsAudition()
{
    QVERIFY(AudioEngineTestAccess::parkDevice(m_window->m_audio));
    QObject owner;
    WorkspaceUi &workspace = *m_window->m_workspace;
    workspace.soundBrowser()->previewVoice(&owner, m_dsSlot, 60, 112);

    LoadedBankView background = *m_browser->selectedBankView();
    const auto id = VoicegroupId::create(QStringLiteral("sound/voicegroups/background.inc"), {});
    QVERIFY(id);
    QVERIFY(*id != background.id);
    background.id = *id;
    workspace.applyProjectEvent(ProjectEvent{std::move(background)});

    QVERIFY2(pickerPeak(renderParkedSeconds(m_window->m_audio, 0.1)) >= 0.01,
             "an unrelated bank publication must not cancel the selected bank audition");
}

void VoicegroupSaveTest::samplePickerAuditionsAndCommits()
{
    m_window->show();
    m_browser->revealSlot(m_dsSlot);
    QCoreApplication::processEvents();
    QCOMPARE(m_browser->visibleVoiceTypeData(), int(m_originalVoice.macro));
    QVERIFY(m_browser->hasSamplePickerEditor());
    QVERIFY(m_browser->samplePickerReplacesSymbolCombo());
    const VgVoice before = *m_browser->selectedBankView()->slotViews.at(m_dsSlot).voice;
    QCOMPARE(m_browser->samplePickerCurrentSymbol(), before.symbol);

    // Real playback through the workspace routing: park the device for
    // deterministic capture, then prove a ready selection sounds and its
    // close releases.
    QVERIFY2(AudioEngineTestAccess::parkDevice(m_window->m_audio),
             "sample picker parks the device for deterministic PCM capture");
    m_browser->openSamplePickerPopup();
    QLineEdit *search = m_browser->samplePickerFilterField();
    QVERIFY(search);
    QVERIFY(m_browser->samplePickerPopupIsVisible());
    QCOMPARE(m_browser->samplePickerPopupCornerColor(), themes::color(themes::Role::menu_outline));
    QVERIFY(m_browser->samplePickerSymbolRowCount() >= 2);

    QVERIFY2(settle([this] { return m_browser->samplePickerBadgedRowCount() > 0; }),
             "picker did not render a loop badge after its production lazy load");
    if (!m_screenshotPath.isEmpty()) {
        QVERIFY(m_browser->saveSamplePickerPopup(m_screenshotPath));
        const QFileInfo path(m_screenshotPath);
        QVERIFY(m_browser->saveBrowser(path.path() + QLatin1Char('/') + path.completeBaseName() +
                                       QStringLiteral("-dock.") + path.suffix()));
    }

    const QString target = m_browser->firstAlternatePlainPickerSymbol(before.symbol);
    QVERIFY2(!target.isEmpty(), "fixture has no alternate plain sample for picker commit contract");
    search->setText(target);
    QVERIFY2(settle([this] { return m_window->m_workspace->sampleSet() != nullptr; }),
             "first picker audition did not load the shared sample set");
    QCOMPARE(m_browser->currentPickerRowSymbol(), target);
    QCoreApplication::processEvents();
    QVERIFY2(pickerPeak(renderParkedSeconds(m_window->m_audio, 1.0)) >= 0.01,
             "a ready popup selection starts audible playback through the workspace routing");
    m_browser->clickCurrentPickerRow();
    QVERIFY(m_browser->samplePickerPopupIsVisible());
    QCOMPARE(m_browser->selectedBankView()->slotViews.at(m_dsSlot).voice->symbol, before.symbol);
    m_browser->clickCurrentPickerRow();
    QVERIFY(!m_browser->samplePickerPopupIsVisible());
    QVERIFY2(settle([this, &target] {
                 const LoadedBankView *const bank = m_browser->selectedBankView();
                 return bank && bank->slotViews.at(m_dsSlot).voice &&
                        bank->slotViews.at(m_dsSlot).voice->symbol == target;
             }),
             "second picker click did not commit selected sample symbol");
    QVERIFY(!m_document->isDirty());
    // The popup close stops the picker's owned request; drain the real
    // release envelope before asserting digital silence.
    renderParkedSeconds(m_window->m_audio, 2.5);
    QVERIFY2(pickerPeak(renderParkedSeconds(m_window->m_audio, 0.1)) <= 1.0e-7,
             "closing the popup releases the picker's playback");
    QVERIFY(m_browser->selectedBankView()->dirty);
    requestUndo();
    QVERIFY2(settle([this, &before] {
                 const LoadedBankView *const bank = m_browser->selectedBankView();
                 return bank && bank->slotViews.at(m_dsSlot).voice &&
                        bank->slotViews.at(m_dsSlot).voice->symbol == before.symbol;
             }),
             "sample picker undo did not restore the voice symbol");
    QCOMPARE(m_browser->samplePickerCurrentSymbol(), before.symbol);

    m_browser->openSamplePickerPopup();
    search = m_browser->samplePickerFilterField();
    QVERIFY(search);
    const QString unlisted = QStringLiteral("VgSaveCheckUnlisted");
    search->setText(unlisted);
    events::sendKey(*search, QEvent::KeyPress, Qt::Key_Return, Qt::NoModifier, QString(), false, 1);
    QVERIFY2(settle([this, &unlisted] {
                 const LoadedBankView *const bank = m_browser->selectedBankView();
                 return bank && bank->slotViews.at(m_dsSlot).voice &&
                        bank->slotViews.at(m_dsSlot).voice->symbol == unlisted;
             }),
             "unlisted typed picker symbol did not commit");
    requestUndo();
    QVERIFY2(settle([this, &before] {
                 const LoadedBankView *const bank = m_browser->selectedBankView();
                 return bank && bank->slotViews.at(m_dsSlot).voice &&
                        bank->slotViews.at(m_dsSlot).voice->symbol == before.symbol;
             }),
             "unlisted typed picker symbol undo did not restore clean voice");
}

void VoicegroupSaveTest::samplePickerWaveModeAuditionsAndCommits()
{
    const QStringList waves = m_window->m_workspace->projectState().catalog.progWave;
    QVERIFY2(waves.size() >= 2, "required staged programmable waves missing: >=2 entries via "
                                "sound/programmable_wave_data.inc");
    m_window->show();
    m_browser->revealSlot(m_dsSlot);
    QCoreApplication::processEvents();
    const VgVoice before = *m_browser->selectedBankView()->slotViews.at(m_dsSlot).voice;
    // Input, popup, commit/undo and typed-symbol behavior below; audible
    // browse routing is proven with real PCM in samplePickerAuditionsAndCommits
    // and the browse* samplecheck slots, never via forwarding spies.
    QVERIFY(m_browser->activateVoiceType(VgMacro::ProgWave));
    QVERIFY2(settle([this] {
                 const LoadedBankView *const bank = m_browser->selectedBankView();
                 return bank && bank->slotViews.at(m_dsSlot).voice &&
                        bank->slotViews.at(m_dsSlot).voice->macro == VgMacro::ProgWave;
             }),
             "switching the DirectSound slot to programmable wave did not settle");
    QCOMPARE(m_browser->visibleVoiceTypeData(), int(VgMacro::ProgWave));
    const VgVoice waveVoice = *m_browser->selectedBankView()->slotViews.at(m_dsSlot).voice;
    QVERIFY(m_browser->samplePickerIsVisible());
    QCOMPARE(m_browser->samplePickerCurrentSymbol(), waveVoice.symbol);
    m_browser->openSamplePickerPopup();
    const QStringList listed = m_browser->pickerSymbols();
    QVERIFY(std::all_of(listed.cbegin(), listed.cend(),
                        [&waves](const QString &symbol) { return waves.contains(symbol); }));
    QVERIFY(m_browser->pickerRowsShowFullSymbols());
    const QString alternative = m_browser->firstAlternatePickerSymbol(waveVoice.symbol);
    QVERIFY2(!alternative.isEmpty(),
             "required staged programmable waves missing: alternate entry via "
             "sound/programmable_wave_data.inc");
    QLineEdit *const search = m_browser->samplePickerFilterField();
    QVERIFY(search);
    search->setText(alternative);
    events::sendKey(*search, QEvent::KeyPress, Qt::Key_Return, Qt::NoModifier, QString(), false, 1);
    QVERIFY2(settle([this, &alternative] {
                 const LoadedBankView *const bank = m_browser->selectedBankView();
                 return bank && bank->slotViews.at(m_dsSlot).voice &&
                        bank->slotViews.at(m_dsSlot).voice->symbol == alternative;
             }),
             "typed wave picker commit did not apply");
    requestUndo();
    QVERIFY2(settle([this, &waveVoice] {
                 const LoadedBankView *const bank = m_browser->selectedBankView();
                 return bank && bank->slotViews.at(m_dsSlot).voice &&
                        *bank->slotViews.at(m_dsSlot).voice == waveVoice;
             }),
             "wave symbol undo did not restore the wave preview");
    requestUndo();
    QVERIFY2(settle([this, &before] {
                 const LoadedBankView *const bank = m_browser->selectedBankView();
                 return bank && bank->slotViews.at(m_dsSlot).voice &&
                        bank->slotViews.at(m_dsSlot).voice->macro == before.macro &&
                        bank->slotViews.at(m_dsSlot).voice->symbol == before.symbol;
             }),
             "wave type undo did not restore DirectSound voice");
}

} // namespace checks
