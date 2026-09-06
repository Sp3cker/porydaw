#include "checks/voicegroupsave/tst_voicegroupsave.h"

#include <QComboBox>
#include <QtTest>

#include "checks/support/songfixture.h"
#include "checks/support/voicegroupbrowserdriver.h"
#include "core/songdocument.h"
#include "mainwindow.h"
#include "ui/songtab.h"
#include "ui/workspaceui.h"

namespace checks {
namespace {

int adjacentRelease(int value)
{
    return value < 255 ? value + 1 : value - 1;
}

} // namespace

void VoicegroupSaveTest::switchCarriesUnsavedBankEdit()
{
    const QString other = otherVoicegroupArg();
    QVERIFY2(m_window->m_workspace->projectState().catalog.groupArgs.size() >= 2 &&
                 !other.isEmpty(),
             "required staged voicegroups missing: >=2 groupArgs via sound/voice_groups.inc and "
             "sound/voicegroups/fixture_alt.inc");
    const QString homeArg = m_document->cfg().voicegroupArg;
    VgVoice edited = m_originalVoice;
    edited.release = adjacentRelease(edited.release);
    m_browser->submitPickerEdit(m_dsSlot, edited);
    QVERIFY2(waitForBankRelease(m_dsSlot, edited.release, true),
             "worker did not apply setup voice edit");

    SongCfg cfg = m_document->cfg();
    cfg.voicegroupArg = other;
    m_document->setCfg(cfg);
    QVERIFY2(settle([this, &other] {
                 return m_document->cfg().voicegroupArg == other && m_tab->voicegroupId() &&
                        *m_tab->voicegroupId() != *m_homeId;
             }),
             "-G switch did not load the other voicegroup");

    requestUndo();
    QVERIFY2(waitForVoicegroup(homeArg, *m_homeId), "undo did not reopen the home voicegroup");
    QVERIFY2(settle([this, &edited] {
                 const LoadedBankView *const bank = m_browser->selectedBankView();
                 const LoadedVoiceGroup *const engine = m_window->m_audio.voicegroup();
                 return bank && bank->loadName == m_loadName && bank->dirty &&
                        bank->slotViews.at(m_dsSlot).voice &&
                        bank->slotViews.at(m_dsSlot).voice->release == edited.release && engine &&
                        engine->voices[m_dsSlot].release == edited.release;
             }),
             "undo restored cfg but did not replay the canonical unsaved bank edit");
    requestUndo();
    QVERIFY2(settle([this] {
                 const LoadedBankView *const bank = m_browser->selectedBankView();
                 return bank && !bank->dirty && !m_document->isDirty();
             }),
             "undoing replayed bank edit did not restore clean state");
    QCOMPARE(readFileBytes(m_voicegroupPath), m_voicegroupBytes);
}

void VoicegroupSaveTest::selectorSwitchUsesUndoableCfgEdit()
{
    const QString other = otherVoicegroupArg();
    QVERIFY2(m_window->m_workspace->projectState().catalog.groupArgs.size() >= 2 &&
                 !other.isEmpty(),
             "required staged voicegroups missing: >=2 groupArgs via sound/voice_groups.inc and "
             "sound/voicegroups/fixture_alt.inc");
    const QString homeArg = m_document->cfg().voicegroupArg;
    QComboBox *const selector = m_browser->voicegroupSelector();
    QVERIFY(selector);
    const QString shownHome = SongRegistry::voicegroupDisplayName(homeArg);
    QCOMPARE(selector->currentText(), shownHome);
    QVERIFY(selector->findText(SongRegistry::voicegroupDisplayName(other)) >= 0);

    selector->setCurrentText(SongRegistry::voicegroupDisplayName(other));
    QVERIFY(QMetaObject::invokeMethod(selector, "activated", Qt::DirectConnection, Q_ARG(int, 0)));
    QVERIFY2(settle([this, &other] {
                 return m_document->cfg().voicegroupArg == other && m_document->isDirty() &&
                        m_tab->voicegroupId() && *m_tab->voicegroupId() != *m_homeId;
             }),
             "selector did not drive the undoable -G seam");
    requestUndo();
    QVERIFY2(waitForVoicegroup(homeArg, *m_homeId), "selector undo did not restore home binding");
    QVERIFY(!m_document->isDirty());
    QTRY_COMPARE(selector->currentText(), shownHome);
}

void VoicegroupSaveTest::valueCommandSurvivesSourceReplacement()
{
    const QString other = otherVoicegroupArg();
    QVERIFY2(m_window->m_workspace->projectState().catalog.groupArgs.size() >= 2 &&
                 !other.isEmpty(),
             "required staged voicegroups missing: >=2 groupArgs via sound/voice_groups.inc and "
             "sound/voicegroups/fixture_alt.inc");
    const QString homeArg = m_document->cfg().voicegroupArg;
    const auto reopenCleanHome = [this, &other, &homeArg] {
        const QByteArray disk = readFileBytes(m_voicegroupPath);
        SongCfg cfg = m_document->cfg();
        cfg.voicegroupArg = other;
        m_document->setCfg(cfg);
        if (!settle([this, &other] {
                return m_document->cfg().voicegroupArg == other && m_tab->voicegroupId() &&
                       *m_tab->voicegroupId() != *m_homeId;
            }))
            return false;
        requestUndo();
        return settle([this, &homeArg, &disk] {
            const LoadedBankView *const bank = m_browser->selectedBankView();
            return m_document->cfg().voicegroupArg == homeArg && m_tab->voicegroupId() &&
                   *m_tab->voicegroupId() == *m_homeId && bank && bank->loadName == m_loadName &&
                   !bank->dirty && readFileBytes(m_voicegroupPath) == disk;
        });
    };

    VgVoice edited = m_originalVoice;
    edited.release = adjacentRelease(edited.release);
    m_browser->submitPickerEdit(m_dsSlot, edited);
    QVERIFY2(waitForBankRelease(m_dsSlot, edited.release, true), "value command did not apply");
    const int firstSave = m_savedReceipts;
    QVERIFY(saveSelectedSong());
    QVERIFY2(waitForCleanSave(firstSave), "value command save did not settle");
    QVERIFY2(reopenCleanHome(), "clean -G round trip did not replace the home source");
    const QByteArray refreshed = readFileBytes(m_voicegroupPath);

    requestUndo();
    QVERIFY2(settle([this, &refreshed] {
                 const LoadedBankView *const bank = m_browser->selectedBankView();
                 return bank && bank->dirty && !m_document->isDirty() &&
                        bank->slotViews.at(m_dsSlot).voice &&
                        bank->slotViews.at(m_dsSlot).voice->release == m_originalVoice.release &&
                        readFileBytes(m_voicegroupPath) == refreshed;
             }),
             "executed value undo after rebind did not resolve current bytes");
    requestRedo();
    QVERIFY2(settle([this, &edited, &refreshed] {
                 const LoadedBankView *const bank = m_browser->selectedBankView();
                 return bank && !bank->dirty && !m_document->isDirty() &&
                        bank->slotViews.at(m_dsSlot).voice &&
                        bank->slotViews.at(m_dsSlot).voice->release == edited.release &&
                        readFileBytes(m_voicegroupPath) == refreshed;
             }),
             "executed value redo after rebind did not resolve current bytes");

    requestUndo();
    QVERIFY2(settle([this] {
                 return m_browser->selectedBankView() && m_browser->selectedBankView()->dirty;
             }),
             "undo before redo-tail refresh did not apply");
    const int restoreSave = m_savedReceipts;
    QVERIFY(saveSelectedSong());
    QVERIFY2(waitForCleanSave(restoreSave), "baseline restoration save did not settle");
    QCOMPARE(readFileBytes(m_voicegroupPath), m_voicegroupBytes);
    requestRedo();
    QVERIFY2(settle([this, &edited] {
                 const LoadedBankView *const bank = m_browser->selectedBankView();
                 return bank && bank->dirty && !m_document->isDirty() &&
                        bank->slotViews.at(m_dsSlot).voice &&
                        bank->slotViews.at(m_dsSlot).voice->release == edited.release &&
                        readFileBytes(m_voicegroupPath) == m_voicegroupBytes;
             }),
             "redo-tail command did not reapply to refreshed canonical bytes");
    requestUndo();
    QVERIFY2(settle([this] {
                 const LoadedBankView *const bank = m_browser->selectedBankView();
                 return bank && !bank->dirty && !m_document->isDirty() &&
                        bank->slotViews.at(m_dsSlot).voice &&
                        bank->slotViews.at(m_dsSlot).voice->release == m_originalVoice.release;
             }),
             "redo-tail undo did not restore clean baseline");
}

void VoicegroupSaveTest::blankTokenRebasesAcrossSourceReplacement()
{
    const QString other = otherVoicegroupArg();
    QVERIFY2(m_window->m_workspace->projectState().catalog.groupArgs.size() >= 2 &&
                 !other.isEmpty(),
             "required staged voicegroups missing: >=2 groupArgs via sound/voice_groups.inc and "
             "sound/voicegroups/fixture_alt.inc");
    const int blank = firstBlankSlot();
    QVERIFY2(blank >= 0, "fixture must provide a blank slot for structural-token rebasing");
    const QString homeArg = m_document->cfg().voicegroupArg;
    const auto reopenCleanHome = [this, &other, &homeArg] {
        SongCfg cfg = m_document->cfg();
        cfg.voicegroupArg = other;
        m_document->setCfg(cfg);
        if (!settle([this, &other] {
                return m_document->cfg().voicegroupArg == other && m_tab->voicegroupId() &&
                       *m_tab->voicegroupId() != *m_homeId;
            }))
            return false;
        requestUndo();
        return waitForVoicegroup(homeArg, *m_homeId) && settle([this] {
                   return m_browser->selectedBankView() && !m_browser->selectedBankView()->dirty;
               });
    };

    const VgVoice materialized = m_originalVoice;
    m_browser->submitPickerEdit(blank, materialized);
    QVERIFY2(settle([this, blank, &materialized] {
                 const LoadedBankView *const bank = m_browser->selectedBankView();
                 return bank && bank->dirty && bank->slotViews.at(blank).voice &&
                        *bank->slotViews.at(blank).voice == materialized;
             }),
             "blank slot did not materialize under a reversible token");
    const int saveBefore = m_savedReceipts;
    QVERIFY(saveSelectedSong());
    QVERIFY2(waitForCleanSave(saveBefore), "materialized blank did not save");

    VoicegroupSource sibling;
    QString error;
    VgVoice unrelated = m_originalVoice;
    unrelated.release = adjacentRelease(unrelated.release);
    QVERIFY2(sibling.open(m_project->root(), homeArg, &error), qPrintable(error));
    QVERIFY2(sibling.setVoice(m_dsSlot, unrelated), "could not update sibling source slot");
    QVERIFY2(sibling.save(&error), qPrintable(error));
    QVERIFY2(reopenCleanHome(), "external source refresh did not rebind cleanly");
    const QByteArray refreshed = readFileBytes(m_voicegroupPath);
    QVERIFY2(settle([this, blank, &unrelated] {
                 const LoadedBankView *const bank = m_browser->selectedBankView();
                 return bank && bank->slotViews.at(blank).voice &&
                        bank->slotViews.at(m_dsSlot).voice &&
                        bank->slotViews.at(m_dsSlot).voice->release == unrelated.release;
             }),
             "reopened source did not contain structural and unrelated edits");

    requestUndo();
    QVERIFY2(settle([this, blank, &unrelated, &refreshed] {
                 const LoadedBankView *const bank = m_browser->selectedBankView();
                 return bank && !bank->slotViews.at(blank).voice &&
                        bank->slotViews.at(m_dsSlot).voice &&
                        bank->slotViews.at(m_dsSlot).voice->release == unrelated.release &&
                        bank->dirty && readFileBytes(m_voicegroupPath) == refreshed;
             }),
             "blank undo restored stale file bytes instead of rebasing its token");
    requestRedo();
    QVERIFY2(settle([this, blank, &materialized, &unrelated, &refreshed] {
                 const LoadedBankView *const bank = m_browser->selectedBankView();
                 return bank && bank->slotViews.at(blank).voice &&
                        *bank->slotViews.at(blank).voice == materialized &&
                        bank->slotViews.at(m_dsSlot).voice &&
                        bank->slotViews.at(m_dsSlot).voice->release == unrelated.release &&
                        !bank->dirty && readFileBytes(m_voicegroupPath) == refreshed;
             }),
             "blank redo did not preserve unrelated refreshed bytes");

    requestUndo();
    QVERIFY2(settle([this, blank] {
                 return m_browser->selectedBankView() &&
                        !m_browser->selectedBankView()->slotViews.at(blank).voice;
             }),
             "cleanup blank undo did not apply");
    m_browser->submitPickerEdit(m_dsSlot, m_originalVoice);
    QVERIFY2(waitForBankRelease(m_dsSlot, m_originalVoice.release, true),
             "restoring unrelated slot did not settle");
    const int finalSave = m_savedReceipts;
    QVERIFY(saveSelectedSong());
    QVERIFY2(waitForCleanSave(finalSave), "cleanup source save did not settle");
    QCOMPARE(readFileBytes(m_voicegroupPath), m_voicegroupBytes);
}

} // namespace checks
