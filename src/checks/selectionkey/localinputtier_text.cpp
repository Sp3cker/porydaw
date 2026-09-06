// Selection keyboard routing, protected-local-input tier: text surfaces. The
// real QML track-rename TextInput, a real QWidget line edit (the song search
// field), and the modal numeric-entry QInputDialog opened by an automation
// lane double click each visibly own the keyboard: delivered command bindings
// edit only the focused surface, Copy carries the surface's own text, and
// window commands resume exactly once after each surface closes (plan 9).

#include "checks/selectionkey/tst_localinputtier.h"

#include "checks/automation/automationmodalguard.h"
#include "checks/selectionkey/automationprobe.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/timelinebandlayout.h"
#include "ui/songview/trackheadermodel.h"

#include <QApplication>
#include <QClipboard>
#include <QInputDialog>
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
    const auto pencil = selectionkey::firstBinding(QStringLiteral("automation.pencil_mode"));
    QVERIFY2(pencil.has_value() && renameGuard,
             "Pencil typing requires a live rename input and binding");
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

void SelectionLocalInputTierTest::numericDialogOwnsKeys()
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
    // The dialog must come from an actual empty lane point rather than from a
    // hardcoded off-camera tick or an existing fixture node.
    QPoint scene;
    QVERIFY2(probe->emptyNodePoint(32, scene, &coordinateDiagnostics),
             qUtf8Printable(coordinateDiagnostics));

    const QByteArray before = document.smf().write();
    const int soloBefore = m_counts.solo;
    QString diagnostic = QStringLiteral("the double click did not observe a dialog");
    bool dialogOpened = false;
    bool digitsLanded = false;
    bool numericEditorFocused = false;
    bool fullTextSelectedForCopy = false;
    bool soloMaskAfter = false;
    QString copiedText;
    QString copiedFrom;
    QString numericTextBeforeSolo;
    QString expectedTextAfterSolo;
    QString textAfterSoloKey;
    {
        const auto interaction =
            automation_modal::scheduleInputDialogInteraction(diagnostic, [&](QInputDialog &dialog) {
                dialogOpened = true;
                QLineEdit *const edit = dialog.findChild<QLineEdit *>();
                if (!edit) {
                    diagnostic = QStringLiteral("QInputDialog has no numeric QLineEdit");
                    return;
                }
                numericEditorFocused = edit->hasFocus();
                QTest::keyClick(edit, Qt::Key_A, Qt::ControlModifier);
                QTest::keyClicks(edit, QStringLiteral("12"));
                digitsLanded = edit->text() == QStringLiteral("12");

                // Copy owns only the selected numeric text. Inspect and save
                // that selection before delivery; Ctrl+C with only a caret
                // legitimately copies nothing.
                QTest::keyClick(edit, Qt::Key_A, Qt::ControlModifier);
                numericTextBeforeSolo = edit->text();
                copiedFrom = edit->selectedText();
                fullTextSelectedForCopy =
                    !numericTextBeforeSolo.isEmpty() && copiedFrom == numericTextBeforeSolo;
                QApplication::clipboard()->clear();
                QTest::keyClick(edit, copy->key(), copy->keyboardModifiers());
                copiedText = QApplication::clipboard()->text();

                // A numeric validator legitimately rejects the default Solo
                // letter. If a user rebinds Solo to a plain accepted digit,
                // use the validator's actual replacement contract instead.
                expectedTextAfterSolo = numericTextBeforeSolo;
                if (soloText) {
                    QString candidate = *soloText;
                    int cursorPosition = candidate.size();
                    const QValidator *const validator = edit->validator();
                    if (!validator ||
                        validator->validate(candidate, cursorPosition) != QValidator::Invalid) {
                        expectedTextAfterSolo = candidate;
                    }
                }
                QTest::keyClick(edit, solo->key(), solo->keyboardModifiers());
                textAfterSoloKey = edit->text();
                soloMaskAfter = view.trackSoloed(kTrack);
            });
        Q_UNUSED(interaction);
        QTest::mouseDClick(quickWindow, Qt::LeftButton, Qt::NoModifier, scene);
        selectionkey::settle();
    }
    selectionkey::settle();
    QVERIFY2(dialogOpened, "an automation double click did not open the numeric dialog");
    QVERIFY2(digitsLanded,
             qPrintable(QStringLiteral("numeric digit entry mismatch: text-before-Solo='%1'")
                            .arg(numericTextBeforeSolo)));
    QVERIFY2(fullTextSelectedForCopy && copiedFrom == QStringLiteral("12") &&
                 copiedText == copiedFrom,
             qPrintable(QStringLiteral("numeric Copy mismatch: field='%1' selected='%2' "
                                       "clipboard='%3' full-selection=%4")
                            .arg(numericTextBeforeSolo, copiedFrom, copiedText)
                            .arg(fullTextSelectedForCopy)));
    QVERIFY2(textAfterSoloKey == expectedTextAfterSolo,
             qPrintable(QStringLiteral("numeric Solo-key contract mismatch: before='%1' "
                                       "expected='%2' actual='%3' editor-focus=%4")
                            .arg(numericTextBeforeSolo, expectedTextAfterSolo, textAfterSoloKey)
                            .arg(numericEditorFocused)));
    QVERIFY2(m_counts.solo == soloBefore && !soloMaskAfter,
             qPrintable(QStringLiteral("Solo escaped the numeric dialog: action-delta=%1 "
                                       "track-soloed=%2")
                            .arg(m_counts.solo - soloBefore)
                            .arg(soloMaskAfter)));
    QVERIFY2(diagnostic.isEmpty(), qUtf8Printable(diagnostic));
    QVERIFY2(document.smf().write() == before,
             "numeric dialog typing mutated the automation lane or the song");

    // Commands resume after the dialog closed without accepting a value.
    activateShellForCommands();
    QVERIFY2(view.focusTimelineBand(songview::TimelineBand::Automation, Qt::MouseFocusReason),
             "could not refocus the automation band after the dialog");
    selectionkey::deliverKey(quickWindow, solo->key(), solo->keyboardModifiers());
    QVERIFY2(m_counts.solo == soloBefore + 1 && view.trackSoloed(kTrack),
             "Solo did not resume after the numeric dialog closed");
    selectionkey::deliverKey(quickWindow, solo->key(), solo->keyboardModifiers());
    QVERIFY2(!view.trackSoloed(kTrack), "Solo did not untoggle after the dialog");
}
