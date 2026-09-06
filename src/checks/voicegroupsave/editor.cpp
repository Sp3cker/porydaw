#include "checks/voicegroupsave/tst_voicegroupsave.h"

#include <QCoreApplication>
#include <QLineEdit>
#include <QtTest>

#include "checks/support/eventsynth.h"
#include "checks/support/voicegroupbrowserdriver.h"
#include "mainwindow.h"
#include "ui/dragspinbox.h"
#include "ui/songtab.h"
#include "ui/workspaceui.h"

namespace checks {

void VoicegroupSaveTest::releaseEditorUsesBankUndoPipeline_data()
{
    QTest::addColumn<int>("pixelsUp");
    QTest::addColumn<Qt::KeyboardModifiers>("modifiers");
    QTest::addColumn<int>("expected");
    QTest::newRow("set-value") << 0 << Qt::KeyboardModifiers(Qt::NoModifier) << -1;
    QTest::newRow("drag-up") << 12 << Qt::KeyboardModifiers(Qt::NoModifier) << 106;
    QTest::newRow("drag-down") << -12 << Qt::KeyboardModifiers(Qt::NoModifier) << 94;
    QTest::newRow("precision-drag") << 20 << Qt::KeyboardModifiers(Qt::ShiftModifier) << 104;
}

void VoicegroupSaveTest::releaseEditorUsesBankUndoPipeline()
{
    QFETCH(int, pixelsUp);
    QFETCH(Qt::KeyboardModifiers, modifiers);
    QFETCH(int, expected);

    m_browser->selectSlot(m_dsSlot);
    DragSpinBox *const spin = m_browser->releaseSpinBox();
    QLineEdit *const field = m_browser->releaseField();
    QVERIFY(spin);
    QVERIFY(field);
    const int target = expected < 0 ? (m_originalVoice.release < 255 ? m_originalVoice.release + 1
                                                                     : m_originalVoice.release - 1)
                                    : expected;
    if (pixelsUp == 0) {
        spin->setValue(target);
    } else {
        spin->setValue(100);
        QVERIFY2(settle([this] {
                     const LoadedBankView *const bank = m_browser->selectedBankView();
                     return bank && bank->slotViews.at(m_dsSlot).voice &&
                            bank->slotViews.at(m_dsSlot).voice->release == 100;
                 }),
                 "drag baseline did not reach the voicegroup worker");
        const QPoint start = field->rect().center();
        const int direction = pixelsUp > 0 ? 1 : -1;
        const QPoint activated = start - QPoint(0, direction * 3);
        const QPoint finish = activated - QPoint(0, pixelsUp);
        const QSize minimumBefore = m_browser->browserMinimumSizeHint();
        field->clearFocus();
        events::sendMouse(*field, QEvent::MouseButtonPress, QPointF(start), Qt::LeftButton,
                          Qt::LeftButton, modifiers);
        QVERIFY(!field->hasFocus());
        events::sendMouse(*field, QEvent::MouseMove, QPointF(activated), Qt::NoButton,
                          Qt::LeftButton, modifiers);
        events::sendMouse(*field, QEvent::MouseMove, QPointF(finish), Qt::NoButton, Qt::LeftButton,
                          modifiers);
        events::sendMouse(*field, QEvent::MouseButtonRelease, QPointF(finish), Qt::LeftButton,
                          Qt::NoButton, modifiers);
        QCOMPARE(m_browser->browserMinimumSizeHint(), minimumBefore);
    }
    QVERIFY2(waitForBankRelease(m_dsSlot, target, true),
             "editor value change did not use the bank edit pipeline");
    QCOMPARE(spin->value(), target);
    requestUndo();
    QVERIFY2(waitForBankRelease(m_dsSlot, m_originalVoice.release, false),
             "editor undo did not restore the original release and engine");
    QVERIFY(!m_document->isDirty());
    QCOMPARE(spin->value(), m_originalVoice.release);
}

void VoicegroupSaveTest::blankTemplateMaterializesUndoably()
{
    const int blank = firstBlankSlot();
    QVERIFY2(blank >= 0, "fixture must provide an undefined slot for the template contract");
    const QStringList blankRow = m_browser->slotRowText(blank);
    QVERIFY(blankRow.size() == 3);
    QCOMPARE(blankRow.at(0),
             QStringLiteral("%1  %2").arg(blank, 3, 10, QLatin1Char('0')).arg(tr("[Blank]")));
    QVERIFY(blankRow.at(1).isEmpty());
    QVERIFY(blankRow.at(2).isEmpty());

    m_browser->selectSlot(blank);
    QVERIFY(m_browser->editorNoticeText().isEmpty());
    QVERIFY(m_browser->editorNoticeIsHidden());
    QVERIFY(m_browser->sampleActionButtonsHaveMatchingFixedSize());
    QCOMPARE(m_browser->visibleVoiceTypeData(), int(VgMacro::DirectSound));
    QVERIFY(m_browser->activateVoiceType(VgMacro::Square1));
    QVERIFY2(settle([this, blank] {
                 const LoadedBankView *const bank = m_browser->selectedBankView();
                 const LoadedVoiceGroup *const engine = m_window->m_audio.voicegroup();
                 return bank && bank->dirty && !m_document->isDirty() &&
                        bank->slotViews.at(blank).voice &&
                        bank->slotViews.at(blank).voice->macro == VgMacro::Square1 && engine &&
                        engine->voices[blank].type == VOICE_SQUARE_1;
             }),
             "blank template did not materialize and reload Square1");
    requestUndo();
    QVERIFY2(settle([this, blank] {
                 const LoadedBankView *const bank = m_browser->selectedBankView();
                 const QStringList row = m_browser->slotRowText(blank);
                 return bank && !bank->dirty && !m_document->isDirty() &&
                        !bank->slotViews.at(blank).voice && row.size() == 3 &&
                        row.at(0) == QStringLiteral("%1  %2")
                                         .arg(blank, 3, 10, QLatin1Char('0'))
                                         .arg(tr("[Blank]")) &&
                        row.at(1).isEmpty() && row.at(2).isEmpty();
             }),
             "blank template undo did not restore the structural row");
    requestRedo();
    QVERIFY2(settle([this, blank] {
                 const LoadedBankView *const bank = m_browser->selectedBankView();
                 const LoadedVoiceGroup *const engine = m_window->m_audio.voicegroup();
                 return bank && bank->slotViews.at(blank).voice &&
                        bank->slotViews.at(blank).voice->macro == VgMacro::Square1 && engine &&
                        engine->voices[blank].type == VOICE_SQUARE_1;
             }),
             "blank template redo did not reload Square1");
    requestUndo();
    QVERIFY2(settle([this, blank] {
                 return m_browser->selectedBankView() &&
                        !m_browser->selectedBankView()->slotViews.at(blank).voice;
             }),
             "final blank template undo did not settle");
}

void VoicegroupSaveTest::dockMinimumWidthIsFamilyInvariant()
{
    const int cgb = firstCgbSlot();
    QVERIFY2(cgb >= 0, "required staged CGB voice missing for dock-width invariant via "
                       "sound/voicegroups/fixture_rich.inc");
    m_window->show();
    QCoreApplication::processEvents();
    m_browser->selectSlot(cgb);
    QCoreApplication::processEvents();
    const int cgbMinimum = m_browser->browserMinimumSizeHint().width();
    m_browser->selectSlot(m_dsSlot);
    QCoreApplication::processEvents();
    QCOMPARE(m_browser->browserMinimumSizeHint().width(), cgbMinimum);
}

} // namespace checks
