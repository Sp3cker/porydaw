// Selection keyboard routing, protected-local-input tier: the pitch-bend
// overlay. The Quick popup session visibly owns the keyboard: the graph-local
// Solo toggles one mask once without touching the window action, Copy and
// unrelated roll commands cannot escape to the window owner, graph strokes
// push exactly one undoable vertex with popup-local Undo, the numeric
// TextInput keeps its own Copy and validator contract, Escape closes the
// popup, and window commands resume exactly once afterward (plan 9).

#include "checks/selectionkey/tst_localinputtier.h"

#include "checks/support/eventsynth.h"

#include "ui/pitchbendeditor.hpp"
#include "ui/pitchbendgraph.hpp"
#include "ui/songview/quick/quickpopupsession.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/timelinebandlayout.h"
#include "ui/songviewmodel.h"

#include <QApplication>
#include <QClipboard>
#include <QEvent>
#include <QGuiApplication>
#include <QMetaObject>
#include <QPointer>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRect>
#include <QSignalSpy>

#include <QtTest>

#include <algorithm>
#include <cstdint>

namespace {

constexpr int kTrack = 0;
constexpr uint8_t kBendController = DOC_CC_BEND;

QQuickItem *findPopupItem(songview::QuickPopupSession *session, const QString &name)
{
    // Popup content is QObject-parented to the session (only visually under
    // the window), so a window-subtree findChild cannot see it. Search the
    // session's content instead: the same subtree the retired native view's
    // rootObject() search covered.
    QQuickItem *content = session ? session->contentItem() : nullptr;
    if (!content)
        return nullptr;
    if (content->objectName() == name)
        return content;
    return content->findChild<QQuickItem *>(name);
}

bool hasCompletedQuickFocus(const QQuickWindow *window, const QQuickItem *item)
{
    return window && item && item->hasActiveFocus() && window->activeFocusItem() == item &&
           QGuiApplication::focusObject() == item && QGuiApplication::focusWindow() == window;
}

checks::async_wait::Result requestCompletedQuickFocus(QQuickWindow *window, QQuickItem *item,
                                                      Qt::FocusReason reason)
{
    const QPointer<QQuickWindow> liveWindow(window);
    const QPointer<QQuickItem> liveItem(item);
    if (!liveWindow || !liveItem)
        return checks::async_wait::Result::Destroyed;
    liveWindow->requestActivate();
    liveItem->forceActiveFocus(reason);
    return checks::async_wait::waitUntil([liveWindow, liveItem] { return liveWindow && liveItem; },
                                         [liveWindow, liveItem] {
                                             return liveWindow && liveItem &&
                                                    hasCompletedQuickFocus(liveWindow, liveItem);
                                         },
                                         5000, 10);
}

// Delivers the standard platform Undo shortcut through the shared canvas
// window, so "the popup claimed Undo" means the real QKeySequence
// arbitration, not a synthesized undo call.
bool sendStandardUndo(QQuickWindow *window)
{
    if (!window)
        return false;
    const auto bindings = QKeySequence::keyBindings(QKeySequence::Undo);
    if (bindings.empty())
        return false;
    const QKeyCombination binding = bindings.front()[0];
    QKeyEvent overrideEvent(QEvent::ShortcutOverride, binding.key(), binding.keyboardModifiers());
    QCoreApplication::sendEvent(window, &overrideEvent);
    if (!overrideEvent.isAccepted())
        return false;
    return selectionkey::deliverKey(window, binding.key(), binding.keyboardModifiers());
}

void drainPopupDeletes()
{
    QCoreApplication::processEvents();
    QCoreApplication::sendPostedEvents(nullptr, QEvent::DeferredDelete);
}

} // namespace

void SelectionLocalInputTierTest::pitchBendOverlayOwnsKeys()
{
    SongView &view = this->view();
    SongDocument &document = this->document();
    const selectionkey::ScenarioRollback rollback(view, document);
    activateShellForCommands();
    const auto opener = selectionkey::firstBinding(QStringLiteral("roll.pitch_bend"));
    const auto solo = selectionkey::firstBinding(QStringLiteral("roll.solo_tracks"));
    const auto copy = selectionkey::firstBinding(QStringLiteral("roll.copy"));
    const auto mute = selectionkey::firstBinding(QStringLiteral("roll.mute_tracks"));
    QVERIFY2(opener.has_value() && solo.has_value() && copy.has_value() && mute.has_value(),
             "pitch-bend/Solo/Copy/Mute have no single-key bindings");

    view.selectTrack(kTrack);
    view.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    selectionkey::settle();
    const std::optional<NoteRef> note = addNote(kTrack, 4800, 62, 96);
    QVERIFY2(note.has_value(),
             "the reserved tick-4800 pitch-bend note could not be inserted and resolved");
    QQuickWindow *const quickWindow = m_quickWindow.data();
    QVERIFY2(quickWindow, "the timeline Quick window is missing");

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
    QVERIFY2(checks::async_wait::waitUntil([] { return true; }, notePublished, 5000, 10) ==
                 checks::async_wait::Result::Ready,
             qPrintable(QStringLiteral("pitch-bend note was not published: model-notes=%1 "
                                       "primary=%2")
                            .arg(view.model().notes.size())
                            .arg(view.selectionModel().primaryTrack())));
    view.selectionModel().setNoteSelection({routedNoteId});
    selectionkey::settle();
    const auto targetReady = [&] {
        return view.selectionModel().primaryTrack() == kTrack &&
               view.selectionModel().noteSelection() == std::vector<NoteId>{routedNoteId} &&
               !view.selectionModel().timeSelection().active();
    };
    QVERIFY2(targetReady(),
             qPrintable(QStringLiteral("pitch-bend target mismatch: primary=%1 notes=%2 "
                                       "time-selection=%3")
                            .arg(view.selectionModel().primaryTrack())
                            .arg(view.selectionModel().noteSelection().size())
                            .arg(view.selectionModel().timeSelection().active())));
    QVERIFY2(view.focusTimelineBand(songview::TimelineBand::Roll, Qt::MouseFocusReason),
             "could not request roll focus for the pitch-bend opener");
    const auto rollHasFocus = [&] {
        QQuickItem *const activeItem = quickWindow->activeFocusItem();
        return view.focusedTimelineBand() == songview::TimelineBand::Roll && activeItem &&
               QGuiApplication::focusObject() == activeItem &&
               QGuiApplication::focusWindow() == quickWindow;
    };
    QVERIFY2(checks::async_wait::waitUntil([] { return true; }, rollHasFocus, 5000, 10) ==
                 checks::async_wait::Result::Ready,
             qPrintable(QStringLiteral("pitch-bend Roll origin never focused: band=%1 active=%2 %3")
                            .arg(view.focusedTimelineBand() ? int(*view.focusedTimelineBand()) : -1)
                            .arg(quickWindow->activeFocusItem()
                                     ? quickWindow->activeFocusItem()->objectName()
                                     : QStringLiteral("none"),
                                 applicationFocusState())));

    const auto visiblePopup = [&]() -> songview::PitchBendEditor * {
        auto *popup = view.findChild<songview::PitchBendEditor *>(QStringLiteral("pitchBendPopup"),
                                                                  Qt::FindDirectChildrenOnly);
        return popup && popup->isOpen() ? popup : nullptr;
    };
    const auto popupState = [&] {
        songview::PitchBendEditor *const popup = visiblePopup();
        songview::QuickPopupSession *const session =
            popup && view.quickView() ? view.quickView()->popupSession() : nullptr;
        return QStringLiteral("session=%1 content=%2 active=%3 %4")
            .arg(popup != nullptr)
            .arg(session && session->isOpen() && session->contentItem() != nullptr)
            .arg(session && session->window() && session->window()->activeFocusItem()
                     ? session->window()->activeFocusItem()->objectName()
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
    QVERIFY2(
        popup,
        qPrintable(
            QStringLiteral("pitch-bend opener did not reveal Quick popup: %1").arg(popupState())));
    songview::QuickPopupSession *session =
        view.quickView() ? view.quickView()->popupSession() : nullptr;
    QPointer<songview::PitchBendGraph> graph = qobject_cast<songview::PitchBendGraph *>(
        findPopupItem(session, QStringLiteral("pitchBendGraph")));
    QPointer<QQuickItem> numericEdit = findPopupItem(session, QStringLiteral("bendRangeInput"));
    QVERIFY2(graph && numericEdit, "the Quick pitch-bend graph or numeric TextInput is missing");

    // Graph focus: Solo is intentionally owned by the popup session, not the
    // MainWindow QAction. One key press produces one mask change.
    const QString graphFocusBefore = applicationFocusState();
    QVERIFY2(requestCompletedQuickFocus(quickWindow, graph, Qt::OtherFocusReason) ==
                 checks::async_wait::Result::Ready,
             qPrintable(QStringLiteral("pitch-bend graph did not complete native Quick focus: "
                                       "before={%1} after={%2}")
                            .arg(graphFocusBefore, applicationFocusState())));
    const int actionSoloBefore = m_counts.solo;
    const uint32_t soloMaskBefore = view.soloMask();
    QSignalSpy soloChanges(&view, &SongView::soloMaskChanged);
    selectionkey::deliverKey(quickWindow, solo->key(), solo->keyboardModifiers());
    QVERIFY2(soloChanges.count() == 1 && m_counts.solo == actionSoloBefore &&
                 view.soloMask() == (soloMaskBefore ^ (uint32_t{1} << kTrack)),
             qPrintable(QStringLiteral("graph-local Solo mismatch: signals=%1 "
                                       "action-delta=%2 before=%3 after=%4")
                            .arg(soloChanges.count())
                            .arg(m_counts.solo - actionSoloBefore)
                            .arg(soloMaskBefore)
                            .arg(view.soloMask())));
    view.setTrackSolo(kTrack, (soloMaskBefore & (uint32_t{1} << kTrack)) != 0);

    // Copy stays popup-local: the window owner must not fire and the sentinel
    // clipboard text must survive untouched.
    const int graphCopyBefore = m_counts.copy;
    const QString clipboardSentinel = QStringLiteral("pitch-bend-graph-local");
    QApplication::clipboard()->setText(clipboardSentinel);
    selectionkey::deliverKey(quickWindow, copy->key(), copy->keyboardModifiers());
    QVERIFY2(m_counts.copy == graphCopyBefore &&
                 QApplication::clipboard()->text() == clipboardSentinel &&
                 document.smf().write() == before,
             qPrintable(QStringLiteral("graph Copy escaped to the window owner: "
                                       "action-delta=%1 clipboard='%2'")
                            .arg(m_counts.copy - graphCopyBefore)
                            .arg(QApplication::clipboard()->text())));

    // An unrelated roll command is absorbed by the popup: it must neither
    // audition nor alter track/document state.
    const uint32_t muteMaskBefore = view.muteMask();
    const QByteArray protectedDocument = document.smf().write();
    int playbackRequests = 0;
    const QMetaObject::Connection playbackConnection =
        QObject::connect(&view, &SongView::playPauseFromRequested,
                         [&playbackRequests](uint64_t) { ++playbackRequests; });
    selectionkey::deliverKey(quickWindow, mute->key(), mute->keyboardModifiers());
    QObject::disconnect(playbackConnection);
    QVERIFY2(playbackRequests == 0 && view.muteMask() == muteMaskBefore &&
                 document.smf().write() == protectedDocument,
             "a non-audition roll command escaped the pitch-bend graph");

    // Draw through the real QQuickItem input path, select one interior vertex,
    // delete it through window arbitration, and prove popup Undo restores both
    // edits without touching notes.
    const QRect canvas = graph->canvasRect();
    QVERIFY2(!canvas.isEmpty(), "pitch-bend graph has no editable canvas");
    const QPointF stroke(canvas.center().x(), canvas.top() + std::max(1, canvas.height() / 4));
    checks::events::sendMouse(*graph, QEvent::MouseButtonPress, stroke, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(*graph, QEvent::MouseButtonRelease, stroke, Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
    selectionkey::settle();
    const std::vector<DocLanePoint> drawn = document.lanePoints(kTrack, kBendController);
    const auto interior =
        std::find_if(drawn.cbegin(), drawn.cend(), [&](const DocLanePoint &point) {
            return point.tick > note->note.tick && point.tick < popup->endTick();
        });
    QVERIFY2(document.undoStack()->index() == undoBefore + 1 && interior != drawn.cend(),
             "graph input did not create one undoable interior bend vertex");
    const QByteArray afterDraw = document.smf().write();
    const uint64_t selectedTick = interior->tick;
    graph->setSelectedTick(selectedTick);
    selectionkey::deliverKey(quickWindow, Qt::Key_Delete);
    selectionkey::settle();
    QVERIFY2(document.undoStack()->index() == undoBefore + 2 &&
                 !document.findLanePoint(kTrack, kBendController, selectedTick, nullptr),
             "graph-local Delete did not remove exactly one selected vertex");
    QVERIFY2(sendStandardUndo(quickWindow),
             "pitch-bend popup did not claim the standard Undo shortcut");
    selectionkey::settle();
    QVERIFY2(document.undoStack()->index() == undoBefore + 1 && document.smf().write() == afterDraw,
             "popup Undo did not restore the deleted bend vertex");
    QVERIFY2(sendStandardUndo(quickWindow),
             "pitch-bend popup did not claim Undo for the graph edit");
    selectionkey::settle();
    QVERIFY2(document.undoStack()->index() == undoBefore && document.smf().write() == before,
             "popup Undo did not restore the pre-edit document");

    while (popup && document.undoStack()->index() > undoBefore) {
        if (!sendStandardUndo(quickWindow))
            break;
        selectionkey::settle();
    }

    // The numeric TextInput keeps its own Copy and validator contract, and the
    // routing proof never changes the stored BENDR value.
    const QString textBefore = numericEdit->property("text").toString();
    const QString numericFocusBefore = applicationFocusState();
    QVERIFY2(requestCompletedQuickFocus(quickWindow, numericEdit, Qt::OtherFocusReason) ==
                 checks::async_wait::Result::Ready,
             qPrintable(QStringLiteral("pitch-bend numeric TextInput did not complete native "
                                       "Quick focus: before={%1} after={%2}")
                            .arg(numericFocusBefore, applicationFocusState())));
    const bool selectedForCopy = QMetaObject::invokeMethod(numericEdit, "selectAll");
    const QString selectedText = numericEdit->property("selectedText").toString();
    const int copyBefore = m_counts.copy;
    QApplication::clipboard()->clear();
    selectionkey::deliverKey(quickWindow, copy->key(), copy->keyboardModifiers());
    QVERIFY2(hasCompletedQuickFocus(quickWindow, numericEdit) && selectedForCopy &&
                 !selectedText.isEmpty() && m_counts.copy == copyBefore &&
                 QApplication::clipboard()->text() == selectedText,
             qPrintable(QStringLiteral("pitch-bend numeric Copy mismatch: delta=%1 "
                                       "selected='%2' clipboard='%3' %4")
                            .arg(m_counts.copy - copyBefore)
                            .arg(selectedText, QApplication::clipboard()->text(),
                                 applicationFocusState())));

    QMetaObject::invokeMethod(numericEdit, "selectAll");
    const int numericSoloBefore = m_counts.solo;
    const uint32_t numericSoloMaskBefore = view.soloMask();
    selectionkey::deliverKey(quickWindow, solo->key(), solo->keyboardModifiers());
    const QString soloText = singleKeyText(*solo).value_or(QString());
    const QString expectedText =
        soloText.size() == 1 && soloText.front().isDigit() ? soloText : textBefore;
    QVERIFY2(numericEdit->property("text").toString() == expectedText &&
                 m_counts.solo == numericSoloBefore && view.soloMask() == numericSoloMaskBefore,
             qPrintable(QStringLiteral("numeric Solo-key mismatch: text='%1' expected='%2' "
                                       "action-delta=%3 mask-before=%4 mask-after=%5")
                            .arg(numericEdit->property("text").toString(), expectedText)
                            .arg(m_counts.solo - numericSoloBefore)
                            .arg(numericSoloMaskBefore)
                            .arg(view.soloMask())));
    if (numericEdit->property("text").toString() != textBefore)
        numericEdit->setProperty("text", textBefore);
    QCOMPARE(popup->bendRange(), textBefore.toInt());

    // Space is the transport command, not numeric text: the focused field
    // yields it and the window command toggles playback.
    QVERIFY(QMetaObject::invokeMethod(numericEdit, "selectAll"));
    QSignalSpy playPause(m_workspace, &WorkspaceUi::playPauseRequested);
    selectionkey::deliverKey(quickWindow, Qt::Key_Space);
    QVERIFY2(playPause.count() == 1 && numericEdit->property("text").toString() == textBefore &&
                 hasCompletedQuickFocus(quickWindow, numericEdit) && popup->isOpen(),
             qPrintable(QStringLiteral("Space in the pitch-bend field did not toggle the "
                                       "transport: triggers=%1 text='%2' expected='%3' open=%4 %5")
                            .arg(playPause.count())
                            .arg(numericEdit->property("text").toString(), textBefore)
                            .arg(popup->isOpen())
                            .arg(applicationFocusState())));
    selectionkey::deliverKey(quickWindow, Qt::Key_Space);
    QVERIFY2(playPause.count() == 2,
             qPrintable(QStringLiteral("Space did not toggle the transport twice: triggers=%1")
                            .arg(playPause.count())));

    requestCompletedQuickFocus(quickWindow, graph, Qt::OtherFocusReason);
    selectionkey::deliverKey(quickWindow, Qt::Key_Escape);
    selectionkey::settle();
    const bool popupClosedByEscape = !popup || !popup->isOpen();
    if (!popupClosedByEscape)
        popup->cancelAndCloseWithoutFocus();
    QVERIFY2(popupClosedByEscape, "Escape did not close the pitch-bend Quick popup");
    drainPopupDeletes();
    QVERIFY2(document.smf().write() == before,
             "the pitch-bend popup session left document changes behind");

    // Measure command resumption independently from popup-pass-through failures.
    activateShellForCommands();
    QVERIFY2(view.focusTimelineBand(songview::TimelineBand::Roll, Qt::MouseFocusReason),
             "could not request Roll focus after the popup");
    QVERIFY2(checks::async_wait::waitUntil([] { return true; }, rollHasFocus, 5000, 10) ==
                 checks::async_wait::Result::Ready,
             "Roll focus did not become active after the popup");
    const int resumeBefore = m_counts.solo;
    const bool trackBefore = view.trackSoloed(kTrack);
    selectionkey::deliverKey(quickWindow, solo->key(), solo->keyboardModifiers());
    QVERIFY2(m_counts.solo == resumeBefore + 1 && view.trackSoloed(kTrack) != trackBefore,
             qPrintable(QStringLiteral("Solo resume mismatch: delta=%1 before=%2 after=%3")
                            .arg(m_counts.solo - resumeBefore)
                            .arg(trackBefore)
                            .arg(view.trackSoloed(kTrack))));
    selectionkey::deliverKey(quickWindow, solo->key(), solo->keyboardModifiers());
    QVERIFY2(m_counts.solo == resumeBefore + 2 && view.trackSoloed(kTrack) == trackBefore,
             qPrintable(QStringLiteral("Solo resume untoggle mismatch: delta=%1 before=%2 after=%3")
                            .arg(m_counts.solo - resumeBefore)
                            .arg(trackBefore)
                            .arg(view.trackSoloed(kTrack))));
    view.selectionModel().clearNoteSelection();
}
