// Selection keyboard routing, protected-local-input tier: a production
// MainWindow shell proves that surfaces which visibly own the keyboard keep
// it, and that window commands resume exactly once after each surface closes.
// Covers the plan scenarios:
//
// * the real QML track-rename TextInput, a real QWidget line edit (the song
//   search field), the modal numeric-entry QInputDialog opened by an
//   automation lane double click, and the pitch-bend overlay: keys delivered
//   into the surface that visibly holds focus edit only that surface, Copy
//   carries the surface's own text, and every window command that production
//   routes out of a surface fires exactly once through its window owner
//   (plan 9);
// * the event list keeps row-local navigation, Delete, Alt reorder and
//   Select All, with no new selected-note Cut/Delete fallback and exactly one
//   window Copy owner (plan 11).
//
// All deliveries are QTest input into the real QQuickWindow or QWidget under
// test; native OS key injection is unavailable to the harness and is not
// claimed. The destructive event-list Delete runs last in its scenario.

#include "checks/automation/automationmodalguard.h"
#include "checks/selectionkey/automationprobe.h"
#include "checks/selectionkey/session.h"
#include "checks/support/eventsynth.h"

#include "core/noteid.h"
#include "core/smf.h"
#include "core/songdocument.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/eventtablemodel.h"
#include "ui/pitchbendeditor.hpp"
#include "ui/pitchbendgraph.hpp"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/timelinebandlayout.h"
#include "ui/songview/trackheadermodel.h"
#include "ui/songviewmodel.h"

#include <QApplication>
#include <QClipboard>
#include <QGuiApplication>
#include <QInputDialog>
#include <QItemSelectionModel>
#include <QKeyEvent>
#include <QKeySequence>
#include <QLineEdit>
#include <QPointer>
#include <QQuickItem>
#include <QQuickView>
#include <QQuickWindow>
#include <QTableView>
#include <QValidator>
#include <QWidget>
#include <QtTest>

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <optional>
#include <vector>

namespace {

using selectionkey::ActionCounts;
using selectionkey::check;
using selectionkey::deliverKey;
using selectionkey::fail;
using selectionkey::firstBinding;
using selectionkey::makeSelectedTabClean;
using selectionkey::ScenarioRollback;

constexpr int kTrack = 0;
constexpr uint8_t kController = 10;

// The typed-text expectation for a delivered command binding: only a plain
// printable key derives a character, so a rebound F-key keeps the assertion
// honest ("text unchanged") instead of fabricating text from an arbitrary
// nonprintable binding.
std::optional<QString> singleKeyText(const QKeyCombination &binding)
{
    if (binding.keyboardModifiers() != Qt::NoModifier)
        return std::nullopt;
    const int key = int(binding.key());
    if (key >= int(Qt::Key_A) && key <= int(Qt::Key_Z))
        return QString(QChar::fromLatin1(char('a' + (key - int(Qt::Key_A)))));
    if (key >= int(Qt::Key_0) && key <= int(Qt::Key_9))
        return QString(QChar::fromLatin1(char('0' + (key - int(Qt::Key_0)))));
    return std::nullopt;
}

struct NoteRef {
    NoteId id{};
    DocNote note{};
};

std::optional<NoteRef> addNote(SongDocument &document, int track, uint64_t tick, uint8_t key,
                               uint32_t duration, QString &error)
{
    const std::vector<NoteId> inserted =
        selectionkey::insertIsolatedNotes(document, track, {{tick, key, duration, 100}}, error);
    if (inserted.size() != 1)
        return std::nullopt;
    const std::optional<DocNote> note = selectionkey::noteById(document, inserted.front());
    if (!note) {
        error = QStringLiteral("the inserted note vanished from the document");
        return std::nullopt;
    }
    return NoteRef{inserted.front(), *note};
}

using selectionkey::observeWindowActions;

// Window-scoped shortcuts fire only while the shell is the active window;
// modal dialogs and the pitch-bend overlay activate themselves, so the shell
// must be restored and observed before resumed-command deliveries. Runs
// before band (re)focus and before every window-scoped shortcut delivery:
// activating after a Quick band takes focus clears its activeFocusItem
// (probe-measured), so the shell is activated first everywhere.
void activateShellForCommands(const SongView &view, int &failures)
{
    QWidget *const shell = view.window();
    if (!check(failures, shell != nullptr, "the view has no shell window for resumed commands"))
        return;
    shell->activateWindow();
    checks::async_wait::waitUntil([] { return true; }, [shell] { return shell->isActiveWindow(); },
                                  5000, 10);
    check(failures, shell->isActiveWindow(),
          "the production shell did not become the active window for resumed commands");
}

QString applicationFocusState()
{
    return QStringLiteral("QWidget=%1 QGui-object=%2 QGui-window=%3")
        .arg(selectionkey::focusObjectIdentity(QApplication::focusWidget()),
             selectionkey::focusObjectIdentity(QGuiApplication::focusObject()),
             selectionkey::focusObjectIdentity(QGuiApplication::focusWindow()));
}

bool hasCompletedNativeFocus(const QWidget *target)
{
    const QWidget *const topLevel = target ? target->window() : nullptr;
    return target && QApplication::focusWidget() == target &&
           QGuiApplication::focusObject() == target && topLevel && topLevel->windowHandle() &&
           QGuiApplication::focusWindow() == topLevel->windowHandle();
}

checks::async_wait::Result requestCompletedNativeFocus(QWidget *target, Qt::FocusReason reason)
{
    const QPointer<QWidget> liveTarget(target);
    if (!liveTarget)
        return checks::async_wait::Result::Destroyed;
    liveTarget->window()->activateWindow();
    liveTarget->setFocus(reason);
    return checks::async_wait::waitUntil(
        [liveTarget] { return bool(liveTarget); },
        [liveTarget] { return liveTarget && hasCompletedNativeFocus(liveTarget); }, 5000, 10);
}

QQuickItem *findPopupItem(QQuickView *view, const QString &name)
{
    return view && view->rootObject() ? view->rootObject()->findChild<QQuickItem *>(name) : nullptr;
}

bool hasCompletedQuickFocus(const QQuickView *view, const QQuickItem *item)
{
    return view && item && item->hasActiveFocus() && view->activeFocusItem() == item &&
           QGuiApplication::focusObject() == item && QGuiApplication::focusWindow() == view;
}

checks::async_wait::Result requestCompletedQuickFocus(QQuickView *view, QQuickItem *item,
                                                      Qt::FocusReason reason)
{
    const QPointer<QQuickView> liveView(view);
    const QPointer<QQuickItem> liveItem(item);
    if (!liveView || !liveItem)
        return checks::async_wait::Result::Destroyed;
    liveView->requestActivate();
    liveItem->forceActiveFocus(reason);
    return checks::async_wait::waitUntil([liveView, liveItem] { return liveView && liveItem; },
                                         [liveView, liveItem] {
                                             return liveView && liveItem &&
                                                    hasCompletedQuickFocus(liveView, liveItem);
                                         },
                                         5000, 10);
}

bool sendStandardUndo(QQuickView *view)
{
    if (!view)
        return false;
    const auto bindings = QKeySequence::keyBindings(QKeySequence::Undo);
    if (bindings.empty())
        return false;
    const QKeyCombination binding = bindings.front()[0];
    QKeyEvent overrideEvent(QEvent::ShortcutOverride, binding.key(), binding.keyboardModifiers());
    QCoreApplication::sendEvent(view, &overrideEvent);
    if (!overrideEvent.isAccepted())
        return false;
    return deliverKey(view, binding.key(), binding.keyboardModifiers());
}

void drainPopupDeletes()
{
    QCoreApplication::processEvents();
    QCoreApplication::sendPostedEvents(nullptr, QEvent::DeferredDelete);
}

void renameTextInputOwnsKeys(ActionCounts &counts, SongTab &tab, int &failures)
{
    SongView &view = tab.view();
    SongDocument &document = tab.document();
    const ScenarioRollback rollback(view, document);
    // Shell first: activating after Quick focus would clear the rename
    // field's activeFocusItem, so the shell is raised before beginRename.
    activateShellForCommands(view, failures);
    auto *const headers = view.findChild<songview::TrackHeaderModel *>(
        QStringLiteral("trackHeaderModel"), Qt::FindDirectChildrenOnly);
    songview::TimelineQuickView *const quick = selectionkey::quickCanvas(view);
    QQuickWindow *const quickWindow = quick ? quick->quickWindow() : nullptr;
    QQuickItem *const root = quick ? quick->rootObject() : nullptr;
    if (!check(failures, headers && quickWindow && root, "the rename surface is unavailable"))
        return;
    const auto solo = firstBinding(QStringLiteral("roll.solo_tracks"));
    const auto copy = firstBinding(QStringLiteral("roll.copy"));
    if (!check(failures, solo.has_value() && copy.has_value(),
               "Solo/Copy have no single-key bindings"))
        return;
    int renameTrack = -1;
    for (int row = 0; row < headers->rowCount() && renameTrack < 0; ++row) {
        const QModelIndex index = headers->index(row, 0);
        if (!headers->data(index, songview::TrackHeaderModel::IsAddTrackRole).toBool())
            renameTrack = headers->data(index, songview::TrackHeaderModel::TrackRole).toInt();
    }
    if (!check(failures, renameTrack >= 0, "no renamable track row exists"))
        return;
    // Match the working native route: focus the embedded Quick host through a
    // real band before beginRename asks the QML delegate to take active focus.
    if (!check(failures, view.focusTimelineBand(songview::TimelineBand::Roll, Qt::OtherFocusReason),
               "could not focus the Quick host before track rename"))
        return;
    const auto quickBandReady = [&] {
        return view.focusedTimelineBand() == songview::TimelineBand::Roll &&
               quickWindow->activeFocusItem() != nullptr;
    };
    if (!check(failures,
               checks::async_wait::waitUntil([] { return true; }, quickBandReady, 5000, 10) ==
                   checks::async_wait::Result::Ready,
               "the Quick host did not acquire an active focus band before track rename"))
        return;
    const QByteArray before = tab.document().smf().write();
    const int copyBefore = counts.copy;
    const int soloBefore = counts.solo;

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
    if (!check(failures, isLiveRename(rename),
               qPrintable(QStringLiteral("rename focus mismatch: renaming-track=%1 "
                                         "candidates=%2 visible=%3 active=%4")
                              .arg(headers->renamingTrack())
                              .arg(renameCandidates.size())
                              .arg(visibleCandidates)
                              .arg(activeName)))) {
        headers->cancelRename();
        return;
    }
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
    check(failures, renameGuard && selectedForTyping && draftAfter == expectedDraft,
          qPrintable(QStringLiteral("rename typing mismatch: before='%1' expected='%2' "
                                    "actual='%3' selected=%4")
                         .arg(draftBefore, expectedDraft, draftAfter)
                         .arg(selectedForTyping)));
    check(failures, counts.copy == copyBefore && counts.solo == soloBefore,
          qPrintable(QStringLiteral("rename typing triggered a window action: copy-delta=%1 "
                                    "solo-delta=%2")
                         .arg(counts.copy - copyBefore)
                         .arg(counts.solo - soloBefore)));
    check(failures, !view.trackSoloed(kTrack), "Solo leaked into the rename TextInput");
    check(failures, tab.document().smf().write() == before, "rename typing mutated the song");

    // Copy with rename focus copies the selected draft itself; clear the
    // clipboard first so stale clipboard contents cannot satisfy the check.
    QApplication::clipboard()->clear();
    const bool selectedForCopy = QMetaObject::invokeMethod(rename, "selectAll");
    const QString selectedDraft = rename->property("selectedText").toString();
    QTest::keyClick(quickWindow, copy->key(), copy->keyboardModifiers());
    selectionkey::settle();
    const QString clipboardText = QApplication::clipboard()->text();
    check(failures, counts.copy == copyBefore,
          qPrintable(QStringLiteral("Copy with rename focus triggered the window action: "
                                    "copy-delta=%1")
                         .arg(counts.copy - copyBefore)));
    check(failures,
          selectedForCopy && !selectedDraft.isEmpty() && selectedDraft == draftAfter &&
              clipboardText == selectedDraft,
          qPrintable(QStringLiteral("rename Copy mismatch: text='%1' selected='%2' "
                                    "clipboard='%3' selectAll=%4")
                         .arg(draftAfter, selectedDraft, clipboardText)
                         .arg(selectedForCopy)));
    const auto pencil = firstBinding(QStringLiteral("automation.pencil_mode"));
    if (check(failures, pencil.has_value() && renameGuard,
              "Pencil typing requires a live rename input and binding")) {
        const QPointer<AutomationCanvas> canvas = view.editorDrawer()->automationPage()->canvas();
        const bool pencilBefore = canvas->pencilMode();
        QMetaObject::invokeMethod(renameGuard, "selectAll");
        QTest::keyClick(quickWindow, pencil->key(), pencil->keyboardModifiers());
        selectionkey::settle();
        check(failures,
              renameGuard && renameGuard->property("text").toString() ==
                                 singleKeyText(*pencil).value_or(draftAfter),
              "Pencil binding did not remain local rename text input");
        check(failures, canvas && canvas->pencilMode() == pencilBefore,
              "Pencil mode toggled while typing into the rename TextInput");
    }
    QTest::keyClick(quickWindow, Qt::Key_Escape);
    selectionkey::settle();
    if (!check(failures, !renameGuard || !rename->isVisible(),
               "Escape did not close the rename TextInput"))
        headers->cancelRename(); // failed-close cleanup keeps later scenarios independent
    check(failures, tab.document().smf().write() == before,
          "cancelling the rename mutated the song");
}

void widgetLineEditOwnsKeys(selectionkey::WindowSession &session, ActionCounts &counts,
                            SongTab &tab, int &failures)
{
    SongView &view = tab.view();
    SongDocument &document = tab.document();
    const ScenarioRollback rollback(view, document);
    // Earlier scenarios leave the Quick canvas owning application focus; the
    // workspace can only redirect keyboard focus into the widget window once
    // that window is active again.
    activateShellForCommands(view, failures);
    session.workspace->focusSongSearch();
    selectionkey::settle();
    auto *const search = qobject_cast<QLineEdit *>(QApplication::focusWidget());
    if (!check(
            failures, search != nullptr,
            qPrintable(QStringLiteral("song search focus did not land on a line edit (focus: %1)")
                           .arg(QApplication::focusWidget()
                                    ? QString::fromLatin1(
                                          QApplication::focusWidget()->metaObject()->className())
                                    : QStringLiteral("none")))))
        return;
    search->clear();
    selectionkey::settle();
    const int copyBefore = counts.copy;
    const int soloBefore = counts.solo;
    const QByteArray before = tab.document().smf().write();

    QTest::keyClicks(search, QStringLiteral("ab"));
    selectionkey::settle();
    check(failures, search->text() == QStringLiteral("ab"),
          "plain keys did not land in the focused line edit");
    check(failures, counts.copy == copyBefore && counts.solo == soloBefore,
          "a window command fired while the line edit owned the keys");
    check(failures, !view.trackSoloed(kTrack), "Solo leaked into the search line edit");
    check(failures, tab.document().smf().write() == before, "line-edit typing mutated the song");

    // Copy with search focus must carry the line edit's own text: whether the
    // widget copies internally or the sole window Copy owner delegates back
    // into it, the clipboard holds the field's text, never the song selection.
    const auto copy = firstBinding(QStringLiteral("roll.copy"));
    if (check(failures, copy.has_value(), "Copy has no single-key binding")) {
        QTest::keyClick(search, Qt::Key_A, Qt::ControlModifier);
        QTest::keyClick(search, copy->key(), copy->keyboardModifiers());
        selectionkey::settle();
        check(failures, QApplication::clipboard()->text() == search->text(),
              "Copy with search focus did not copy the line edit's own text");
    }
    search->clear();
    selectionkey::settle();

    // Commands resume once the text field no longer owns the keys.
    const auto solo = firstBinding(QStringLiteral("roll.solo_tracks"));
    if (!check(failures, solo.has_value(), "Solo has no single-key binding"))
        return;
    // The automation band's input item exists only while its drawer section
    // is visible; the numeric-dialog scenario shows it later on its own.
    view.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    selectionkey::settle();
    if (!check(failures,
               view.focusTimelineBand(songview::TimelineBand::Automation, Qt::MouseFocusReason),
               "could not refocus the automation band after text entry"))
        return;
    songview::TimelineQuickView *const quick = selectionkey::quickCanvas(view);
    QQuickWindow *const quickWindow = quick ? quick->quickWindow() : nullptr;
    if (!check(failures, quickWindow != nullptr, "the Quick window is missing after text entry"))
        return;
    deliverKey(quickWindow, solo->key(), solo->keyboardModifiers());
    check(failures, counts.solo == soloBefore + 1 && view.trackSoloed(kTrack),
          "Solo did not resume after text entry");
    deliverKey(quickWindow, solo->key(), solo->keyboardModifiers());
    check(failures, !view.trackSoloed(kTrack), "Solo did not untoggle after text entry");
}

void numericDialogOwnsKeys(ActionCounts &counts, SongTab &tab, int &failures)
{
    SongView &view = tab.view();
    SongDocument &document = tab.document();
    const ScenarioRollback rollback(view, document);
    activateShellForCommands(view, failures);
    const auto solo = firstBinding(QStringLiteral("roll.solo_tracks"));
    const auto copy = firstBinding(QStringLiteral("roll.copy"));
    if (!check(failures, solo.has_value() && copy.has_value(),
               "Solo/Copy have no single-key bindings"))
        return;
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
    if (!check(failures, quickWindow && automation, "the automation canvas surface is unavailable"))
        return;

    QString coordinateDiagnostics;
    const auto probe = selectionkey::AutomationProbe::locate(view, automation, kTrack, kController,
                                                             &coordinateDiagnostics);
    if (!check(failures, probe.has_value(), qPrintable(coordinateDiagnostics)))
        return;
    // The dialog must come from an actual empty lane point rather than from a
    // hardcoded off-camera tick or an existing fixture node.
    QPoint scene;
    if (!check(failures, probe->emptyNodePoint(32, scene, &coordinateDiagnostics),
               qPrintable(coordinateDiagnostics)))
        return;

    const QByteArray before = document.smf().write();
    const int soloBefore = counts.solo;
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
                soloMaskAfter = tab.view().trackSoloed(kTrack);
            });
        Q_UNUSED(interaction);
        QTest::mouseDClick(quickWindow, Qt::LeftButton, Qt::NoModifier, scene);
        selectionkey::settle();
    }
    selectionkey::settle();
    check(failures, dialogOpened, "an automation double click did not open the numeric dialog");
    check(failures, digitsLanded,
          qPrintable(QStringLiteral("numeric digit entry mismatch: text-before-Solo='%1'")
                         .arg(numericTextBeforeSolo)));
    check(failures,
          fullTextSelectedForCopy && copiedFrom == QStringLiteral("12") && copiedText == copiedFrom,
          qPrintable(QStringLiteral("numeric Copy mismatch: field='%1' selected='%2' "
                                    "clipboard='%3' full-selection=%4")
                         .arg(numericTextBeforeSolo, copiedFrom, copiedText)
                         .arg(fullTextSelectedForCopy)));
    check(failures, textAfterSoloKey == expectedTextAfterSolo,
          qPrintable(QStringLiteral("numeric Solo-key contract mismatch: before='%1' "
                                    "expected='%2' actual='%3' editor-focus=%4")
                         .arg(numericTextBeforeSolo, expectedTextAfterSolo, textAfterSoloKey)
                         .arg(numericEditorFocused)));
    check(failures, counts.solo == soloBefore && !soloMaskAfter,
          qPrintable(QStringLiteral("Solo escaped the numeric dialog: action-delta=%1 "
                                    "track-soloed=%2")
                         .arg(counts.solo - soloBefore)
                         .arg(soloMaskAfter)));
    check(failures, diagnostic.isEmpty(), qPrintable(diagnostic));
    check(failures, document.smf().write() == before,
          "numeric dialog typing mutated the automation lane or the song");

    // Commands resume after the dialog closed without accepting a value.
    activateShellForCommands(view, failures);
    if (!check(failures,
               view.focusTimelineBand(songview::TimelineBand::Automation, Qt::MouseFocusReason),
               "could not refocus the automation band after the dialog"))
        return;
    deliverKey(quickWindow, solo->key(), solo->keyboardModifiers());
    check(failures, counts.solo == soloBefore + 1 && view.trackSoloed(kTrack),
          "Solo did not resume after the numeric dialog closed");
    deliverKey(quickWindow, solo->key(), solo->keyboardModifiers());
    check(failures, !view.trackSoloed(kTrack), "Solo did not untoggle after the dialog");
}

void pitchBendOverlayOwnsKeys(ActionCounts &counts, SongTab &tab, int &failures)
{
    SongView &view = tab.view();
    SongDocument &document = tab.document();
    const ScenarioRollback rollback(view, document);
    activateShellForCommands(view, failures);
    const auto opener = firstBinding(QStringLiteral("roll.pitch_bend"));
    const auto solo = firstBinding(QStringLiteral("roll.solo_tracks"));
    const auto copy = firstBinding(QStringLiteral("roll.copy"));
    const auto mute = firstBinding(QStringLiteral("roll.mute_tracks"));
    if (!check(failures,
               opener.has_value() && solo.has_value() && copy.has_value() && mute.has_value(),
               "pitch-bend/Solo/Copy/Mute have no single-key bindings"))
        return;

    view.selectTrack(kTrack);
    view.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    selectionkey::settle();
    QString error;
    const std::optional<NoteRef> note = addNote(document, kTrack, 4800, 62, 96, error);
    if (!check(failures, note.has_value(), qPrintable(error)))
        return;
    songview::TimelineQuickView *const quick = selectionkey::quickCanvas(view);
    QQuickWindow *const quickWindow = quick ? quick->quickWindow() : nullptr;
    if (!check(failures, quickWindow != nullptr, "the timeline Quick window is missing"))
        return;

    // The production opener has no tool-mode predicate: its exact inputs are
    // one selected primary-track note, a published ViewNote, and Roll origin.
    view.ensureTickVisible(note->note.tick + note->note.duration / 2);
    const NoteId routedNoteId = note->id;
    const auto notePublished = [&] {
        const auto &notes = view.model().notes;
        return std::any_of(notes.cbegin(), notes.cend(), [routedNoteId](const ViewNote &candidate) {
            return candidate.noteId == routedNoteId;
        });
    };
    if (!check(failures,
               checks::async_wait::waitUntil([] { return true; }, notePublished, 5000, 10) ==
                   checks::async_wait::Result::Ready,
               qPrintable(QStringLiteral("pitch-bend note was not published: model-notes=%1 "
                                         "primary=%2")
                              .arg(view.model().notes.size())
                              .arg(view.selectionModel().primaryTrack()))))
        return;
    view.selectionModel().setNoteSelection({routedNoteId});
    selectionkey::settle();
    const auto targetReady = [&] {
        return view.selectionModel().primaryTrack() == kTrack &&
               view.selectionModel().noteSelection() == std::vector<NoteId>{routedNoteId} &&
               !view.selectionModel().timeSelection().active();
    };
    if (!check(failures, targetReady(),
               qPrintable(QStringLiteral("pitch-bend target mismatch: primary=%1 notes=%2 "
                                         "time-selection=%3")
                              .arg(view.selectionModel().primaryTrack())
                              .arg(view.selectionModel().noteSelection().size())
                              .arg(view.selectionModel().timeSelection().active()))))
        return;
    if (!check(failures, view.focusTimelineBand(songview::TimelineBand::Roll, Qt::MouseFocusReason),
               "could not request roll focus for the pitch-bend opener"))
        return;
    const auto rollHasFocus = [&] {
        QQuickItem *const activeItem = quickWindow->activeFocusItem();
        return view.focusedTimelineBand() == songview::TimelineBand::Roll && activeItem &&
               QGuiApplication::focusObject() == activeItem &&
               QGuiApplication::focusWindow() == quickWindow;
    };
    if (!check(
            failures,
            checks::async_wait::waitUntil([] { return true; }, rollHasFocus, 5000, 10) ==
                checks::async_wait::Result::Ready,
            qPrintable(QStringLiteral("pitch-bend Roll origin never focused: band=%1 active=%2 %3")
                           .arg(view.focusedTimelineBand() ? int(*view.focusedTimelineBand()) : -1)
                           .arg(quickWindow->activeFocusItem()
                                    ? quickWindow->activeFocusItem()->objectName()
                                    : QStringLiteral("none"),
                                applicationFocusState()))))
        return;

    const auto visiblePopup = [&]() -> songview::PitchBendEditor * {
        auto *popup = view.findChild<songview::PitchBendEditor *>(QStringLiteral("pitchBendPopup"),
                                                                  Qt::FindDirectChildrenOnly);
        return popup && popup->isOpen() && popup->view() && popup->view()->isVisible() ? popup
                                                                                       : nullptr;
    };
    const auto popupState = [&] {
        songview::PitchBendEditor *const popup = visiblePopup();
        QQuickView *const surface = popup ? popup->view() : nullptr;
        return QStringLiteral("session=%1 surface=%2 active=%3 %4")
            .arg(popup != nullptr)
            .arg(surface && surface->isVisible())
            .arg(surface && surface->activeFocusItem() ? surface->activeFocusItem()->objectName()
                                                       : QStringLiteral("none"),
                 applicationFocusState());
    };
    const auto openPopup = [&]() -> songview::PitchBendEditor * {
        QTest::keyClick(quickWindow, opener->key(), opener->keyboardModifiers());
        checks::async_wait::waitUntil([] { return true; },
                                      [&] { return visiblePopup() != nullptr; }, 5000, 10);
        selectionkey::settle();
        return visiblePopup();
    };

    const QByteArray before = document.smf().write();
    const int undoBefore = document.undoStack()->index();
    QPointer<songview::PitchBendEditor> popup = openPopup();
    check(
        failures, popup,
        qPrintable(
            QStringLiteral("pitch-bend opener did not reveal Quick popup: %1").arg(popupState())));
    if (popup) {
        QPointer<QQuickView> surface = popup->view();
        QPointer<songview::PitchBendGraph> graph = qobject_cast<songview::PitchBendGraph *>(
            findPopupItem(surface, QStringLiteral("pitchBendGraph")));
        QPointer<QQuickItem> numericEdit = findPopupItem(surface, QStringLiteral("bendRangeInput"));
        check(failures, surface && graph && numericEdit,
              "the Quick pitch-bend graph or numeric TextInput is missing");

        if (surface && graph) {
            const QString graphFocusBefore = applicationFocusState();
            const bool graphFocusReady = check(
                failures,
                requestCompletedQuickFocus(surface, graph, Qt::OtherFocusReason) ==
                    checks::async_wait::Result::Ready,
                qPrintable(QStringLiteral("pitch-bend graph did not complete native Quick focus: "
                                          "before={%1} after={%2}")
                               .arg(graphFocusBefore, applicationFocusState())));
            if (graphFocusReady) {
                // Solo is intentionally owned by the popup session, not the
                // MainWindow QAction. One key press produces one mask change.
                const int actionSoloBefore = counts.solo;
                const uint32_t soloMaskBefore = view.soloMask();
                QSignalSpy soloChanges(&view, &SongView::soloMaskChanged);
                deliverKey(surface, solo->key(), solo->keyboardModifiers());
                check(failures,
                      soloChanges.count() == 1 && counts.solo == actionSoloBefore &&
                          view.soloMask() == (soloMaskBefore ^ (uint32_t{1} << kTrack)),
                      qPrintable(QStringLiteral("graph-local Solo mismatch: signals=%1 "
                                                "action-delta=%2 before=%3 after=%4")
                                     .arg(soloChanges.count())
                                     .arg(counts.solo - actionSoloBefore)
                                     .arg(soloMaskBefore)
                                     .arg(view.soloMask())));
                view.setTrackSolo(kTrack, (soloMaskBefore & (uint32_t{1} << kTrack)) != 0);
                const int graphCopyBefore = counts.copy;
                const QString clipboardSentinel = QStringLiteral("pitch-bend-graph-local");
                QApplication::clipboard()->setText(clipboardSentinel);
                deliverKey(surface, copy->key(), copy->keyboardModifiers());
                check(failures,
                      counts.copy == graphCopyBefore &&
                          QApplication::clipboard()->text() == clipboardSentinel &&
                          document.smf().write() == before,
                      qPrintable(QStringLiteral("graph Copy escaped to the window owner: "
                                                "action-delta=%1 clipboard='%2'")
                                     .arg(counts.copy - graphCopyBefore)
                                     .arg(QApplication::clipboard()->text())));

                // An unrelated roll command is absorbed by the popup: it must
                // neither audition nor alter track/document state.
                const uint32_t muteMaskBefore = view.muteMask();
                const QByteArray protectedDocument = document.smf().write();
                int playbackRequests = 0;
                const QMetaObject::Connection playbackConnection =
                    QObject::connect(&view, &SongView::playPauseFromRequested,
                                     [&playbackRequests](uint64_t) { ++playbackRequests; });
                deliverKey(surface, mute->key(), mute->keyboardModifiers());
                QObject::disconnect(playbackConnection);
                check(failures,
                      playbackRequests == 0 && view.muteMask() == muteMaskBefore &&
                          document.smf().write() == protectedDocument,
                      "a non-audition roll command escaped the pitch-bend graph");

                // Draw through the real QQuickItem input path, select one
                // interior vertex, delete it through window arbitration, and
                // prove popup Undo restores both edits without touching notes.
                const QRect canvas = graph->canvasRect();
                if (check(failures, !canvas.isEmpty(), "pitch-bend graph has no editable canvas")) {
                    const QPointF stroke(canvas.center().x(),
                                         canvas.top() + std::max(1, canvas.height() / 4));
                    checks::events::sendMouse(*graph, QEvent::MouseButtonPress, stroke,
                                              Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
                    checks::events::sendMouse(*graph, QEvent::MouseButtonRelease, stroke,
                                              Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
                    selectionkey::settle();
                    const std::vector<DocLanePoint> drawn =
                        document.lanePoints(kTrack, DOC_CC_BEND);
                    const auto interior =
                        std::find_if(drawn.cbegin(), drawn.cend(), [&](const DocLanePoint &point) {
                            return point.tick > note->note.tick && point.tick < popup->endTick();
                        });
                    const bool drewInterior = check(
                        failures,
                        document.undoStack()->index() == undoBefore + 1 && interior != drawn.cend(),
                        "graph input did not create one undoable interior bend vertex");
                    if (drewInterior) {
                        const QByteArray afterDraw = document.smf().write();
                        const uint64_t selectedTick = interior->tick;
                        graph->setSelectedTick(selectedTick);
                        deliverKey(surface, Qt::Key_Delete);
                        selectionkey::settle();
                        check(
                            failures,
                            document.undoStack()->index() == undoBefore + 2 &&
                                !document.findLanePoint(kTrack, DOC_CC_BEND, selectedTick, nullptr),
                            "graph-local Delete did not remove exactly one selected vertex");
                        check(failures, sendStandardUndo(surface),
                              "pitch-bend popup did not claim the standard Undo shortcut");
                        selectionkey::settle();
                        check(failures,
                              document.undoStack()->index() == undoBefore + 1 &&
                                  document.smf().write() == afterDraw,
                              "popup Undo did not restore the deleted bend vertex");
                        check(failures, sendStandardUndo(surface),
                              "pitch-bend popup did not claim Undo for the graph edit");
                        selectionkey::settle();
                        check(failures,
                              document.undoStack()->index() == undoBefore &&
                                  document.smf().write() == before,
                              "popup Undo did not restore the pre-edit document");
                    }
                }
            }
        }

        while (surface && popup && document.undoStack()->index() > undoBefore) {
            if (!sendStandardUndo(surface))
                break;
            selectionkey::settle();
        }

        if (surface && numericEdit) {
            const QString textBefore = numericEdit->property("text").toString();
            const QString numericFocusBefore = applicationFocusState();
            const bool numericFocusReady = check(
                failures,
                requestCompletedQuickFocus(surface, numericEdit, Qt::OtherFocusReason) ==
                    checks::async_wait::Result::Ready,
                qPrintable(QStringLiteral("pitch-bend numeric TextInput did not complete native "
                                          "Quick focus: before={%1} after={%2}")
                               .arg(numericFocusBefore, applicationFocusState())));
            if (numericFocusReady) {
                const bool selectedForCopy = QMetaObject::invokeMethod(numericEdit, "selectAll");
                const QString selectedText = numericEdit->property("selectedText").toString();
                const int copyBefore = counts.copy;
                QApplication::clipboard()->clear();
                deliverKey(surface, copy->key(), copy->keyboardModifiers());
                check(failures,
                      hasCompletedQuickFocus(surface, numericEdit) && selectedForCopy &&
                          !selectedText.isEmpty() && counts.copy == copyBefore &&
                          QApplication::clipboard()->text() == selectedText,
                      qPrintable(QStringLiteral("pitch-bend numeric Copy mismatch: delta=%1 "
                                                "selected='%2' clipboard='%3' %4")
                                     .arg(counts.copy - copyBefore)
                                     .arg(selectedText, QApplication::clipboard()->text(),
                                          applicationFocusState())));

                QMetaObject::invokeMethod(numericEdit, "selectAll");
                const int numericSoloBefore = counts.solo;
                const uint32_t numericSoloMaskBefore = view.soloMask();
                deliverKey(surface, solo->key(), solo->keyboardModifiers());
                const QString soloText = singleKeyText(*solo).value_or(QString());
                const QString expectedText =
                    soloText.size() == 1 && soloText.front().isDigit() ? soloText : textBefore;
                check(
                    failures,
                    numericEdit->property("text").toString() == expectedText &&
                        counts.solo == numericSoloBefore &&
                        view.soloMask() == numericSoloMaskBefore,
                    qPrintable(QStringLiteral("numeric Solo-key mismatch: text='%1' expected='%2' "
                                              "action-delta=%3 mask-before=%4 mask-after=%5")
                                   .arg(numericEdit->property("text").toString(), expectedText)
                                   .arg(counts.solo - numericSoloBefore)
                                   .arg(numericSoloMaskBefore)
                                   .arg(view.soloMask())));
                if (numericEdit->property("text").toString() != textBefore)
                    numericEdit->setProperty("text", textBefore);
                check(failures, popup->bendRange() == textBefore.toInt(),
                      "numeric routing proof changed the stored BENDR value");
            }
        }

        if (surface && graph)
            requestCompletedQuickFocus(surface, graph, Qt::OtherFocusReason);
        if (surface)
            deliverKey(surface, Qt::Key_Escape);
        selectionkey::settle();
        if (!check(failures, !popup || !popup->isOpen(),
                   "Escape did not close the pitch-bend Quick popup"))
            popup->cancelAndCloseWithoutFocus();
        drainPopupDeletes();
    }
    check(failures, document.smf().write() == before,
          "the pitch-bend popup session left document changes behind");

    // Measure command resumption independently from popup-pass-through failures.
    activateShellForCommands(view, failures);
    if (!check(failures, view.focusTimelineBand(songview::TimelineBand::Roll, Qt::MouseFocusReason),
               "could not request Roll focus after the popup"))
        return;
    if (!check(failures,
               checks::async_wait::waitUntil([] { return true; }, rollHasFocus, 5000, 10) ==
                   checks::async_wait::Result::Ready,
               "Roll focus did not become active after the popup"))
        return;
    const int resumeBefore = counts.solo;
    const bool trackBefore = view.trackSoloed(kTrack);
    deliverKey(quickWindow, solo->key(), solo->keyboardModifiers());
    check(failures, counts.solo == resumeBefore + 1 && view.trackSoloed(kTrack) != trackBefore,
          qPrintable(QStringLiteral("Solo resume mismatch: delta=%1 before=%2 after=%3")
                         .arg(counts.solo - resumeBefore)
                         .arg(trackBefore)
                         .arg(view.trackSoloed(kTrack))));
    deliverKey(quickWindow, solo->key(), solo->keyboardModifiers());
    check(failures, counts.solo == resumeBefore + 2 && view.trackSoloed(kTrack) == trackBefore,
          qPrintable(QStringLiteral("Solo resume untoggle mismatch: delta=%1 before=%2 after=%3")
                         .arg(counts.solo - resumeBefore)
                         .arg(trackBefore)
                         .arg(view.trackSoloed(kTrack))));
    view.selectionModel().clearNoteSelection();
}

int totalEvents(const SongDocument &document)
{
    int total = 0;
    for (const SmfTrack &track : document.smf().tracks)
        total += int(track.events.size());
    return total;
}

QString rowSummary(const eventlist::EventTableModel *model, int row)
{
    return model->data(model->index(row, eventlist::EventTableModel::ColSummary), Qt::DisplayRole)
        .toString();
}

void eventListKeepsRowLocalKeys(ActionCounts &counts, SongTab &tab, int &failures)
{
    SongView &view = tab.view();
    SongDocument &document = tab.document();
    const ScenarioRollback rollback(view, document);
    // The pitch-bend overlay self-activated on top of the shell; the window
    // Copy owner below only fires while the shell is the active window again.
    activateShellForCommands(view, failures);
    view.setEventListVisible(true);
    selectionkey::settle();
    auto *const table = view.findChild<QTableView *>(QStringLiteral("eventListTable"));
    if (!check(failures, table && table->isVisible(), "the event list table is unavailable"))
        return;
    auto *const model = dynamic_cast<eventlist::EventTableModel *>(table->model());
    if (!check(failures, model != nullptr, "the event list model is missing"))
        return;
    const int rows = model->rowCount();
    if (!check(failures, rows >= 4, "the event-list fixture has too few rows"))
        return;
    const int copyBefore = counts.copy;

    // Row navigation stays table-local.
    table->setFocus(Qt::OtherFocusReason);
    selectionkey::settle();
    table->setCurrentIndex(model->index(0, 0));
    selectionkey::settle();
    QTest::keyClick(table, Qt::Key_Down);
    selectionkey::settle();
    check(failures, table->currentIndex().row() == 1, "Down did not move the event-list cursor");
    QTest::keyClick(table, Qt::Key_Up);
    selectionkey::settle();
    check(failures, table->currentIndex().row() == 0, "Up did not move the event-list cursor back");

    // Select All stays local to the table rows.
    QTest::keyClick(table, Qt::Key_A, Qt::ControlModifier);
    selectionkey::settle();
    check(failures, table->selectionModel()->selectedRows().count() == rows,
          "Ctrl+A did not select the event-list rows locally");

    // The registered reorder binding swaps adjacent rows without changing the
    // event set.
    const auto moveUp = firstBinding(QStringLiteral("eventlist.move_up"));
    if (check(failures, moveUp.has_value(), "eventlist.move_up has no single binding")) {
        const int totalBefore = totalEvents(document);
        const QString row0Before = rowSummary(model, 0);
        const QString row1Before = rowSummary(model, 1);
        table->setCurrentIndex(model->index(1, 0));
        selectionkey::settle();
        QTest::keyClick(table, moveUp->key(), moveUp->keyboardModifiers());
        selectionkey::settle();
        check(failures, rowSummary(model, 0) == row1Before && rowSummary(model, 1) == row0Before,
              "the reorder key did not swap the first two rows");
        check(failures, model->rowCount() == rows && totalEvents(document) == totalBefore,
              "reordering changed the event count");
    }

    // Copy with event-list focus keeps exactly one window Copy owner; the
    // delivery is window-scoped, so the shell must be the active window.
    const auto copy = firstBinding(QStringLiteral("roll.copy"));
    if (check(failures, copy.has_value(), "Copy has no single-key binding")) {
        activateShellForCommands(view, failures);
        QTest::keyClick(table, copy->key(), copy->keyboardModifiers());
        selectionkey::settle();
        check(failures, counts.copy == copyBefore + 1,
              "Copy with event-list focus did not fire through its one window owner");
    }

    // Delete removes the selected rows; a note that is selected in the song
    // but whose row is not selected must survive untouched.
    QString error;
    const std::optional<NoteRef> protectedNote = addNote(document, kTrack, 6720, 60, 48, error);
    if (!check(failures, protectedNote.has_value(), qPrintable(error)))
        return;
    selectionkey::settle();
    selectionkey::settle();
    const uint64_t protectedEndTick = protectedNote->note.tick + protectedNote->note.duration;
    int protectedRow = -1;
    for (int row = 0; row < model->rowCount(); ++row) {
        const auto tick = model->exactTickForRow(row);
        if (tick && *tick == protectedNote->note.tick) {
            if (protectedRow >= 0) {
                check(failures, false, "the protected tick is not unique in the fixture");
                return;
            }
            protectedRow = row;
        }
    }
    if (!check(failures, protectedRow >= 0, "the protected note row is missing"))
        return;
    // Victims need a table-unique tick so the post-delete scan cannot be
    // confused by a second event sharing their tick. Only raw-event rows
    // qualify: a tempo row's Delete is the tempo-map operation, not the
    // raw-event removal this scenario asserts, and the protected note's
    // note-end row belongs to the note that must survive untouched.
    const auto countRowsWithTick = [&](uint64_t tick) {
        int count = 0;
        for (int row = 0; row < model->rowCount(); ++row) {
            const auto rowTick = model->exactTickForRow(row);
            if (rowTick && *rowTick == tick)
                ++count;
        }
        return count;
    };
    std::vector<int> victimRows;
    std::vector<uint64_t> victimTicks;
    for (int row = 0; row < model->rowCount() && int(victimRows.size()) < 2; ++row) {
        const auto tick = model->exactTickForRow(row);
        if (!tick || !model->rawEventIndexForRow(row).has_value() || row == protectedRow ||
            *tick == protectedNote->note.tick || *tick == protectedEndTick ||
            countRowsWithTick(*tick) != 1)
            continue;
        victimRows.push_back(row);
        victimTicks.push_back(*tick);
    }
    if (!check(failures, victimRows.size() == 2, "no two deletable victim rows exist"))
        return;
    // Select All ran earlier and every document refresh restores multi-row
    // selections (EventListView::refresh re-selects captured rows after each
    // model reset), so drop whatever selection survived before staging the
    // two victims — otherwise Delete would remove every selected raw event.
    table->selectionModel()->clearSelection();
    selectionkey::settle();
    QItemSelection selection;
    for (const int row : victimRows)
        selection.select(model->index(row, 0), model->index(row, model->columnCount() - 1));
    table->selectionModel()->select(selection,
                                    QItemSelectionModel::Select | QItemSelectionModel::Rows);
    selectionkey::settle();
    view.selectionModel().setNoteSelection({protectedNote->id});

    const int rowsBeforeDelete = model->rowCount();
    const int totalBeforeDelete = totalEvents(document);
    QTest::keyClick(table, Qt::Key_Delete);
    selectionkey::settle();
    check(failures, model->rowCount() == rowsBeforeDelete - 2,
          "Delete did not remove exactly the selected rows");
    check(failures, totalEvents(document) == totalBeforeDelete - 2,
          "Delete did not remove exactly the selected raw events");
    int victimRowsRemaining = 0;
    for (int row = 0; row < model->rowCount(); ++row) {
        const auto tick = model->exactTickForRow(row);
        if (tick && std::find(victimTicks.begin(), victimTicks.end(), *tick) != victimTicks.end())
            ++victimRowsRemaining;
    }
    check(failures, victimRowsRemaining == 0, "the deleted rows are still present");
    const std::optional<DocNote> survivor = selectionkey::noteById(document, protectedNote->id);
    check(failures,
          survivor.has_value() && survivor->tick == protectedNote->note.tick &&
              survivor->key == protectedNote->note.key && !survivor->unterminated(),
          "event-list Delete mutated the note-selection target instead of its rows");

    view.setEventListVisible(false);
    selectionkey::settle();
}

} // namespace

int runSelectionKeyLocalInputCheck(const QString &projectRoot, const QString &songLabel)
{
    int failures = 0;
    // Window-context observer callbacks capture this by reference, so it must
    // outlive WindowSession and its MainWindow teardown.
    ActionCounts counts;
    selectionkey::WindowSession session;
    QString error;
    if (!selectionkey::openWindowSession(session, projectRoot, error)) {
        fail(failures, error);
        return 1;
    }
    SongTab *const tab = selectionkey::openSongTab(session, songLabel, false, error);
    if (!tab) {
        fail(failures, error);
        return 1;
    }
    if (!observeWindowActions(*session.window, counts)) {
        fail(failures, QStringLiteral("the production shell is missing the window actions"));
        return 1;
    }

    renameTextInputOwnsKeys(counts, *tab, failures);
    widgetLineEditOwnsKeys(session, counts, *tab, failures);
    numericDialogOwnsKeys(counts, *tab, failures);
    pitchBendOverlayOwnsKeys(counts, *tab, failures);
    eventListKeepsRowLocalKeys(counts, *tab, failures);
    // ScenarioRollback restores each scenario independently. Keep the final
    // clean-state assertion as a shell-lifecycle guard before closing.
    makeSelectedTabClean(*session.workspace, tab->document(),
                         "undoing the scenario edits left the tab dirty", failures);
    session.window->close();
    selectionkey::settle();
    std::fprintf(stderr, "selectionkeylocalinputcheck: %s\n", failures == 0 ? "PASS" : "FAIL");
    return failures == 0 ? 0 : 1;
}
