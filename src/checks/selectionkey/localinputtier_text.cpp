// Selection keyboard routing, protected-local-input tier: text surfaces. The
// real QML track-rename TextInput, a real QWidget line edit (the song search
// field), and the inline automation value prompt opened by an automation lane
// double click each visibly own the keyboard: delivered command bindings edit
// only the focused surface, Copy carries the surface's own text, and window
// commands resume exactly once after each surface closes (plan 9).

#include "checks/selectionkey/tst_localinputtier.h"

#include "checks/automation/automationvalueprompt.h"
#include "checks/selectionkey/automationprobe.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/timelinebandlayout.h"
#include "ui/songview/trackheadermodel.h"

#include <QApplication>
#include <QClipboard>
#include <QLineEdit>
#include <QPointer>
#include <QQuickItem>
#include <QQuickWindow>
#include <QValidator>
#include <QWidget>

#include <QtTest>

namespace {

constexpr int kTrack = 0;
constexpr uint8_t kController = 10;

} // namespace

void SelectionLocalInputTierTest::renameTextInputOwnsKeys()
{
    SongView &view = this->view();
    const selectionkey::ScenarioRollback rollback(view, document());
    // Shell first: activating after Quick focus would clear the rename
    // field's activeFocusItem, so the shell is raised before beginRename.
    activateShellForCommands();
    auto *const headers = view.findChild<songview::TrackHeaderModel *>(
        QStringLiteral("trackHeaderModel"), Qt::FindDirectChildrenOnly);
    songview::TimelineQuickView *const quick = selectionkey::quickCanvas(view);
    QQuickWindow *const quickWindow = quick ? quick->quickWindow() : nullptr;
    QQuickItem *const root = quick ? quick->rootObject() : nullptr;
    QVERIFY2(headers && quickWindow && root, "the rename surface is unavailable");
    const auto solo = selectionkey::firstBinding(QStringLiteral("roll.solo_tracks"));
    const auto copy = selectionkey::firstBinding(QStringLiteral("roll.copy"));
    QVERIFY2(solo.has_value() && copy.has_value(), "Solo/Copy have no single-key bindings");
    int renameTrack = -1;
    for (int row = 0; row < headers->rowCount() && renameTrack < 0; ++row) {
        const QModelIndex index = headers->index(row, 0);
        if (!headers->data(index, songview::TrackHeaderModel::IsAddTrackRole).toBool())
            renameTrack = headers->data(index, songview::TrackHeaderModel::TrackRole).toInt();
    }
    QVERIFY2(renameTrack >= 0, "no renamable track row exists");
    // Match the working native route: focus the embedded Quick host through a
    // real band before beginRename asks the QML delegate to take active focus.
    QVERIFY2(view.focusTimelineBand(songview::TimelineBand::Roll, Qt::OtherFocusReason),
             "could not focus the Quick host before track rename");
    const auto quickBandReady = [&] {
        return view.focusedTimelineBand() == songview::TimelineBand::Roll &&
               quickWindow->activeFocusItem() != nullptr;
    };
    QVERIFY2(checks::async_wait::waitUntil([] { return true; }, quickBandReady, 5000, 10) ==
                 checks::async_wait::Result::Ready,
             "the Quick host did not acquire an active focus band before track rename");
    const QByteArray before = document().smf().write();
    const int copyBefore = m_counts.copy;
    const int soloBefore = m_counts.solo;

    headers->beginRename(renameTrack);
    selectionkey::settle();
    const QString renameObjectName = QStringLiteral("timelineTrackHeaderRename");
    const QList<QQuickItem *> renameCandidates = root->findChildren<QQuickItem *>(renameObjectName);
    const auto isLiveRename = [quickWindow, &renameObjectName](const QQuickItem *item) {
        return item && item->objectName() == renameObjectName && item->isVisible() &&
               item->window() == quickWindow;
    };
    int visibleCandidates = 0;
    QQuickItem *onlyVisibleRename = nullptr;
    for (QQuickItem *candidate : renameCandidates) {
        if (!isLiveRename(candidate))
            continue;
        ++visibleCandidates;
        onlyVisibleRename = candidate;
    }
    // beginRename's QML delegate focuses itself. Prefer that live focus item:
    // a recursive findChild can return a stale delegate from an older scene.
    QQuickItem *rename = quickWindow->activeFocusItem();
    if (!isLiveRename(rename) && visibleCandidates == 1) {
        onlyVisibleRename->forceActiveFocus(Qt::OtherFocusReason);
        selectionkey::settle();
        rename = quickWindow->activeFocusItem();
    }
    const QString activeName = rename
                                   ? (rename->objectName().isEmpty()
                                          ? QString::fromLatin1(rename->metaObject()->className())
                                          : rename->objectName())
                                   : QStringLiteral("none");
    const bool renameFocused = isLiveRename(rename);
    if (!renameFocused)
        headers->cancelRename();
    QVERIFY2(renameFocused, qPrintable(QStringLiteral("rename focus mismatch: renaming-track=%1 "
                                                      "candidates=%2 visible=%3 active=%4")
                                           .arg(headers->renamingTrack())
                                           .arg(renameCandidates.size())
                                           .arg(visibleCandidates)
                                           .arg(activeName)));
    QPointer<QQuickItem> renameGuard = rename;
    const QString draftBefore = rename->property("text").toString();

    // The registered Solo binding key must edit the draft, not fire the
    // window action. SelectAll first so a printable binding has a
    // deterministic replacement result.
    const bool selectedForTyping = QMetaObject::invokeMethod(rename, "selectAll");
    QTest::keyClick(quickWindow, solo->key(), solo->keyboardModifiers());
    selectionkey::settle();
    const QString expectedDraft = singleKeyText(*solo).value_or(draftBefore);
    const QString draftAfter = renameGuard ? rename->property("text").toString() : QString();
    QVERIFY2(renameGuard && selectedForTyping && draftAfter == expectedDraft,
             qPrintable(QStringLiteral("rename typing mismatch: before='%1' expected='%2' "
                                       "actual='%3' selected=%4")
                            .arg(draftBefore, expectedDraft, draftAfter)
                            .arg(selectedForTyping)));
    QVERIFY2(m_counts.copy == copyBefore && m_counts.solo == soloBefore,
             qPrintable(QStringLiteral("rename typing triggered a window action: copy-delta=%1 "
                                       "solo-delta=%2")
                            .arg(m_counts.copy - copyBefore)
                            .arg(m_counts.solo - soloBefore)));
    QVERIFY2(!view.trackSoloed(kTrack), "Solo leaked into the rename TextInput");
    QVERIFY2(document().smf().write() == before, "rename typing mutated the song");

    // Copy with rename focus copies the selected draft itself; clear the
    // clipboard first so stale clipboard contents cannot satisfy the check.
    QApplication::clipboard()->clear();
    const bool selectedForCopy = QMetaObject::invokeMethod(rename, "selectAll");
    const QString selectedDraft = rename->property("selectedText").toString();
    QTest::keyClick(quickWindow, copy->key(), copy->keyboardModifiers());
    selectionkey::settle();
    const QString clipboardText = QApplication::clipboard()->text();
    QVERIFY2(m_counts.copy == copyBefore,
             qPrintable(QStringLiteral("Copy with rename focus triggered the window action: "
                                       "copy-delta=%1")
                            .arg(m_counts.copy - copyBefore)));
    QVERIFY2(selectedForCopy && !selectedDraft.isEmpty() && selectedDraft == draftAfter &&
                 clipboardText == selectedDraft,
             qPrintable(QStringLiteral("rename Copy mismatch: text='%1' selected='%2' "
                                       "clipboard='%3' selectAll=%4")
                            .arg(draftAfter, selectedDraft, clipboardText)
                            .arg(selectedForCopy)));

    // Regression guard for the Quick IME pencil guard: with the Automations
    // drawer visible and the pencil shortcut armed, the bare pencil key must
    // stay rename text and never toggle pencil mode.
    const auto pencil = selectionkey::firstBinding(QStringLiteral("automation.pencil_mode"));
    QVERIFY2(pencil.has_value() && renameGuard,
             "Pencil typing requires a live rename input and binding");
    view.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    selectionkey::settle();
    const QPointer<AutomationCanvas> canvas = view.editorDrawer()->automationPage()->canvas();
    const bool pencilBefore = canvas->pencilMode();
    QMetaObject::invokeMethod(renameGuard, "selectAll");
    QTest::keyClick(quickWindow, pencil->key(), pencil->keyboardModifiers());
    selectionkey::settle();
    QVERIFY2(renameGuard && renameGuard->property("text").toString() ==
                                singleKeyText(*pencil).value_or(draftAfter),
             "Pencil binding did not remain local rename text input");
    QVERIFY2(canvas && canvas->pencilMode() == pencilBefore,
             "Pencil mode toggled while typing into the rename TextInput");
    QMetaObject::invokeMethod(renameGuard, "selectAll");
    QTest::keyClick(quickWindow, pencil->key(), Qt::NoModifier);
    selectionkey::settle();
    QVERIFY2(renameGuard && renameGuard->property("text").toString() ==
                                singleKeyText(*pencil).value_or(draftAfter),
             "The bare pencil key did not remain rename text input");
    QVERIFY2(canvas && canvas->pencilMode() == pencilBefore,
             "The bare pencil key toggled pencil mode during rename");
    QTest::keyClick(quickWindow, Qt::Key_Escape);
    selectionkey::settle();
    const bool renameClosed = !renameGuard || !rename->isVisible();
    if (!renameClosed)
        headers->cancelRename(); // failed-close cleanup keeps the close path observable
    QVERIFY2(renameClosed, "Escape did not close the rename TextInput");
    QVERIFY2(document().smf().write() == before, "cancelling the rename mutated the song");
}

void SelectionLocalInputTierTest::songSearchLineEditOwnsKeys()
{
    SongView &view = this->view();
    const selectionkey::ScenarioRollback rollback(view, document());
    // Earlier scenarios leave the Quick canvas owning application focus; the
    // workspace can only redirect keyboard focus into the widget window once
    // that window is active again.
    activateShellForCommands();
    m_session.workspace->focusSongSearch();
    selectionkey::settle();
    auto *const search = qobject_cast<QLineEdit *>(QApplication::focusWidget());
    QVERIFY2(search,
             qPrintable(QStringLiteral("song search focus did not land on a line edit (focus: %1)")
                            .arg(QApplication::focusWidget()
                                     ? QString::fromLatin1(
                                           QApplication::focusWidget()->metaObject()->className())
                                     : QStringLiteral("none"))));
    search->clear();
    selectionkey::settle();
    const int soloBefore = m_counts.solo;

    QTest::keyClicks(search, QStringLiteral("ab"));
    selectionkey::settle();
    QCOMPARE(search->text(), QStringLiteral("ab"));

    // Copy with search focus must carry the line edit's own text: whether the
    // widget copies internally or the sole window Copy owner delegates back
    // into it, the clipboard holds the field's text, never the song selection.
    const auto copy = selectionkey::firstBinding(QStringLiteral("roll.copy"));
    QVERIFY2(copy.has_value(), "Copy has no single-key binding");
    QApplication::clipboard()->clear();
    QTest::keyClick(search, Qt::Key_A, Qt::ControlModifier);
    QTest::keyClick(search, copy->key(), copy->keyboardModifiers());
    selectionkey::settle();
    QCOMPARE(QApplication::clipboard()->text(), search->text());
    search->clear();
    selectionkey::settle();

    // Commands resume once the text field no longer owns the keys.
    const auto solo = selectionkey::firstBinding(QStringLiteral("roll.solo_tracks"));
    QVERIFY2(solo.has_value(), "Solo has no single-key binding");
    // The automation band's input item exists only while its drawer section
    // is visible; the numeric-dialog scenario shows it later on its own.
    view.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    selectionkey::settle();
    QVERIFY2(view.focusTimelineBand(songview::TimelineBand::Automation, Qt::MouseFocusReason),
             "could not refocus the automation band after text entry");
    QVERIFY2(m_quickWindow, "the Quick window is missing after text entry");
    selectionkey::deliverKey(m_quickWindow, solo->key(), solo->keyboardModifiers());
    QVERIFY2(m_counts.solo == soloBefore + 1 && view.trackSoloed(kTrack),
             "Solo did not resume after text entry");
    selectionkey::deliverKey(m_quickWindow, solo->key(), solo->keyboardModifiers());
    QVERIFY2(!view.trackSoloed(kTrack), "Solo did not untoggle after text entry");
}

void SelectionLocalInputTierTest::numericPromptOwnsKeys()
{
    SongView &view = this->view();
    SongDocument &document = this->document();
    const selectionkey::ScenarioRollback rollback(view, document);
    activateShellForCommands();
    const auto solo = selectionkey::firstBinding(QStringLiteral("roll.solo_tracks"));
    const auto copy = selectionkey::firstBinding(QStringLiteral("roll.copy"));
    QVERIFY2(solo.has_value() && copy.has_value(), "Solo/Copy have no single-key bindings");
    const std::optional<QString> soloText = singleKeyText(*solo);
    document.addLanePoint(kTrack, kController, 48, 32);
    document.addLanePoint(kTrack, kController, 96, 64);
    view.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    selectionkey::settle();
    songview::TimelineQuickView *const quick = selectionkey::quickCanvas(view);
    QQuickWindow *const quickWindow = quick ? quick->quickWindow() : nullptr;
    QQuickItem *const root = quick ? quick->rootObject() : nullptr;
    auto *const automation = root ? root->findChild<songview::TimelineInputItem *>(
                                        QStringLiteral("timelineAutomationInput"))
                                  : nullptr;
    QVERIFY2(quickWindow && automation, "the automation canvas surface is unavailable");

    QString coordinateDiagnostics;
    const auto probe = selectionkey::AutomationProbe::locate(view, automation, kTrack, kController,
                                                             &coordinateDiagnostics);
    QVERIFY2(probe.has_value(), qUtf8Printable(coordinateDiagnostics));
    // The prompt must come from an actual empty lane point rather than from a
    // hardcoded off-camera tick or an existing fixture node.
    QPoint scene;
    QVERIFY2(probe->emptyNodePoint(32, scene, &coordinateDiagnostics),
             qUtf8Printable(coordinateDiagnostics));

    // A selected note makes a shared-edit leak observable: arrow keys with the
    // prompt focused must stay local, so the selection anchors the contract.
    const auto note = addNote(kTrack, 24, 60, 24);
    QVERIFY2(note.has_value(), "the fixture note was not created");
    view.selectionModel().setNoteSelection({note->id});
    selectionkey::settle();
    QVERIFY2(view.selectionModel().noteSelection() == std::vector<NoteId>{note->id},
             "the fixture note selection did not settle");

    const QByteArray before = document.smf().write();
    const int soloBefore = m_counts.solo;
    DrawerChrome &chrome = view.editorDrawer()->chrome();

    QTest::mouseDClick(quickWindow, Qt::LeftButton, Qt::NoModifier, scene);
    QTRY_VERIFY(automation_valueprompt::promptVisible(chrome));
    QPointer<QQuickItem> prompt(automation_valueprompt::focusedTextInput(*quickWindow));
    QVERIFY2(prompt, "the value prompt did not take active focus after the double click");
    // The prompt opens with the plotted insertion value selected, so the
    // delivered digits replace that selection.
    QTest::keyClick(quickWindow, Qt::Key_1);
    QTest::keyClick(quickWindow, Qt::Key_2);
    selectionkey::settle();
    QVERIFY2(prompt && prompt->property("text").toString() == QStringLiteral("12"),
             "the delivered digits did not land in the value prompt");

    // Copy owns only the selected numeric text. Inspect and save that
    // selection before delivery; Ctrl+C with only a caret legitimately copies
    // nothing.
    QApplication::clipboard()->clear();
    QVERIFY(QMetaObject::invokeMethod(prompt, "selectAll"));
    const QString numericText = prompt->property("text").toString();
    const QString copiedFrom = prompt->property("selectedText").toString();
    QTest::keyClick(quickWindow, copy->key(), copy->keyboardModifiers());
    selectionkey::settle();
    const QString copiedText = QApplication::clipboard()->text();
    QVERIFY2(numericText == QStringLiteral("12") && copiedFrom == numericText &&
                 copiedText == copiedFrom,
             qPrintable(QStringLiteral("numeric Copy mismatch: field='%1' selected='%2' "
                                       "clipboard='%3'")
                            .arg(numericText, copiedFrom, copiedText)));

    // Arrow keys with the prompt focused must not leak shared edit commands:
    // the selected note, the song, and the prompt itself all stay frozen.
    QTest::keyClick(quickWindow, Qt::Key_Up);
    selectionkey::settle();
    QTest::keyClick(quickWindow, Qt::Key_Down);
    selectionkey::settle();
    QVERIFY2(automation_valueprompt::promptVisible(chrome),
             "the value prompt closed while arrow keys were delivered");
    QVERIFY2(view.selectionModel().noteSelection() == std::vector<NoteId>{note->id},
             "prompt arrow keys leaked into the note selection");
    QVERIFY2(document.smf().write() == before,
             "prompt arrow keys leaked a shared edit command into the song");

    // A numeric validator legitimately rejects the default Solo letter. If a
    // user rebinds Solo to a plain accepted digit, use the validator's actual
    // replacement contract instead; either way the binding must stay local to
    // the prompt text and never fire the track action.
    QVERIFY(QMetaObject::invokeMethod(prompt, "selectAll"));
    QString expectedAfterSolo = numericText;
    if (soloText) {
        QString candidate = *soloText;
        int cursorPosition = candidate.size();
        const QVariant validatorValue = prompt->property("validator");
        QValidator *const validator = validatorValue.value<QValidator *>();
        if (!validator || validator->validate(candidate, cursorPosition) != QValidator::Invalid)
            expectedAfterSolo = candidate;
    }
    QTest::keyClick(quickWindow, solo->key(), solo->keyboardModifiers());
    selectionkey::settle();
    QVERIFY2(prompt && prompt->property("text").toString() == expectedAfterSolo,
             qPrintable(QStringLiteral("numeric Solo-key contract mismatch: expected='%1' "
                                       "actual='%2'")
                            .arg(expectedAfterSolo,
                                 prompt ? prompt->property("text").toString() : QString())));
    QVERIFY2(m_counts.solo == soloBefore && !view.trackSoloed(kTrack),
             qPrintable(QStringLiteral("Solo escaped the value prompt: action-delta=%1 "
                                       "track-soloed=%2")
                            .arg(m_counts.solo - soloBefore)
                            .arg(view.trackSoloed(kTrack))));
    QVERIFY2(document.smf().write() == before,
             "value prompt typing mutated the automation lane or the song");

    // Escape cancels the pending edit without writing, and window commands
    // resume exactly once the prompt no longer owns the keys.
    QTest::keyClick(quickWindow, Qt::Key_Escape);
    QTRY_VERIFY(!automation_valueprompt::promptVisible(chrome));
    QVERIFY2(document.smf().write() == before, "cancelling the value prompt mutated the song");
    activateShellForCommands();
    QVERIFY2(view.focusTimelineBand(songview::TimelineBand::Automation, Qt::MouseFocusReason),
             "could not refocus the automation band after the prompt");
    selectionkey::deliverKey(m_quickWindow, solo->key(), solo->keyboardModifiers());
    QVERIFY2(m_counts.solo == soloBefore + 1 && view.trackSoloed(kTrack),
             "Solo did not resume after the value prompt closed");
    selectionkey::deliverKey(m_quickWindow, solo->key(), solo->keyboardModifiers());
    QVERIFY2(!view.trackSoloed(kTrack), "Solo did not untoggle after the prompt");
}
