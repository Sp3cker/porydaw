// Selection keyboard routing, window tier: real key delivery through the
// shown Quick window of a full production MainWindow shell. Covers the plan
// scenarios that only exist at window scope:
//
// * window Copy with timeline/automation focus executes exactly once, Copy
//   lands the note clip on the clipboard, and an unrecognized key is a
//   terminal no-op (selectionkeywindow plan 5);
// * deliberately keyboard-focused chrome reached by real Tab traversal — the
//   drawer resize grip and the automation scrollbar — keeps its advertised
//   local keys while a focused drawer toggle keeps Space activation and still
//   routes note arrows to the selected notes (plan 13);
// * a live drawer resize drag or automation scrollbar thumb drag holds the
//   pointer: shared editing keys cannot mutate the selected notes, Escape
//   cancels only the gesture, and the next idle Escape clears it (plan 6);
// * A/B tab switching, drawer hide/show, a primary-track change, and closing
//   plus reopening a song tab leave routing bound to the live view, with no
//   stale callback mutating a background document (plan 10).
//
// Scenarios are isolated: each one rolls its document edits back through the
// real undo stack at scope end, so the lifecycle scenario starts from the
// project's saved state instead of inheriting dirty documents (a dirty tab is
// what turns the second-song open into an unsaved-changes prompt). Programmatic
// staging (focusBand, selection, document inserts, drawer geometry) is setup;
// asserted keys use QTest and pointer gestures send Qt mouse events through the
// shown production QQuickWindow.
// Reserved note ticks per song: 960 (Copy scenario), 2400 (chrome and
// gesture scenarios), 3840 (reselected first tab), track-1 960 (primary-track
// change) — distinct so scenario rollbacks can never collide.
//
// Protected local input surfaces (rename, text entry, numeric dialogs, the
// pitch-bend overlay, the event-list table) live in localinput.cpp. Native OS
// key injection is unavailable to the harness; delivery here enters the real
// QQuickWindow and QWidget tree, which is Qt delivery evidence, not OS-injection proof.
// which is Qt delivery evidence, not OS-injection proof.

#include "checks/selectionkey/session.h"

#include "checks/support/eventsynth.h"
#include "core/noteid.h"
#include "core/songdocument.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/layout.h"
#include "ui/songview/clipmime.h"
#include "ui/songview/timelinebandlayout.h"

#include <QApplication>
#include <QCloseEvent>
#include <QGuiApplication>
#include <QQuickItem>
#include <QQuickWindow>
#include <QStringList>
#include <QStyleHints>
#include <QtTest>

#include <array>
#include <cstdint>
#include <cstdio>
#include <optional>
#include <vector>

namespace {

constexpr int kTrack = 0;
constexpr uint8_t kController = 10;
// A second CC lane next to kController: two lanes plus the tempo lane keep
// the automation content taller than the short gesture/scrollbar viewports.
constexpr uint8_t kSecondController = 74;
using checks::async_wait::Result;
using checks::async_wait::waitUntil;
using selectionkey::ActionCounts;
using selectionkey::check;
using selectionkey::DeclineModalsWithin;
using selectionkey::deliverKey;
using selectionkey::fail;
using selectionkey::firstBinding;
using selectionkey::insertIsolatedNotes;
using selectionkey::makeSelectedTabClean;
using selectionkey::noteById;
using selectionkey::observeWindowActions;
using selectionkey::ScenarioRollback;

struct NotePair {
    std::array<NoteId, 2> ids{};
    std::array<DocNote, 2> notes{};
};

std::optional<NotePair> addNotePair(SongDocument &document, int track, uint64_t firstTick,
                                    QString &error)
{
    const std::vector<SongDocument::NewNote> specs{{firstTick, 60, 48, 100},
                                                   {firstTick + 96, 64, 48, 96}};
    const std::vector<NoteId> inserted = insertIsolatedNotes(document, track, specs, error);
    if (inserted.size() != 2)
        return std::nullopt;
    NotePair pair;
    pair.ids = {inserted[0], inserted[1]};
    for (int index = 0; index < 2; ++index) {
        const std::optional<DocNote> note = noteById(document, pair.ids[std::size_t(index)]);
        if (!note) {
            error = QStringLiteral("the inserted note pair vanished from the document");
            return std::nullopt;
        }
        pair.notes[std::size_t(index)] = *note;
    }
    return pair;
}

bool notePairUnchanged(SongDocument &document, const NotePair &pair)
{
    for (int index = 0; index < 2; ++index) {
        const std::optional<DocNote> note = noteById(document, pair.ids[std::size_t(index)]);
        if (!note)
            return false;
        const DocNote &original = pair.notes[std::size_t(index)];
        if (note->tick != original.tick || note->key != original.key)
            return false;
    }
    return true;
}

// Full-control Tab traversal fixture precondition, scoped to the keyboard
// traversal scenario. macOS hosts commonly run the text-only keyboard
// navigation policy (AppleKeyboardUIMode 0); Qt Quick then skips every
// non-text control during Tab traversal — QQuickItemPrivate::canAcceptTabFocus
// only honors activeFocusOnTab for editable text and list/table roles — so
// plan 13's real Tab delivery to the drawer grip, scrollbar, and toggle could
// never arrive no matter how the fixture is staged. Qt exposes the policy as
// per-process in-memory state: this guard sets Qt::TabFocusAllControls and
// restores the previous Qt value at scope end. It never touches the user's OS
// settings and never substitutes focus synthesis; the traversal itself stays
// real Tab key delivery with visible-focus assertions.
class FullControlTabTraversal final
{
  public:
    FullControlTabTraversal() : m_previous(QGuiApplication::styleHints()->tabFocusBehavior())
    {
        QGuiApplication::styleHints()->setTabFocusBehavior(Qt::TabFocusAllControls);
    }

    ~FullControlTabTraversal() { QGuiApplication::styleHints()->setTabFocusBehavior(m_previous); }

    FullControlTabTraversal(const FullControlTabTraversal &) = delete;
    FullControlTabTraversal &operator=(const FullControlTabTraversal &) = delete;

  private:
    Qt::TabFocusBehavior m_previous;
};

// Real Tab traversal from the currently focused item until one of the named
// chrome controls owns active focus. The step bound follows the live tab chain:
// every track row contributes two header toggles plus the add-track row, and
// the ruler controls, the three scrollbars, and the visible drawer chrome come
// after (or wrap before) them. On exhaustion it reports where traversal ended
// so a failure names the trap, not just "never arrived".
QQuickItem *tabTo(QQuickWindow *window, const QStringList &targets, int maxSteps)
{
    QString lastFocus;
    for (int step = 0; step < maxSteps; ++step) {
        QTest::keyClick(window, Qt::Key_Tab);
        selectionkey::settle();
        QQuickItem *const focus = window->activeFocusItem();
        if (!focus)
            continue;
        lastFocus = focus->objectName();
        if (targets.contains(lastFocus))
            return focus;
    }
    std::fprintf(stderr, "selectionkeywindowcheck: tab traversal stopped at '%s' after %d steps\n",
                 qPrintable(lastFocus), maxSteps);
    return nullptr;
}

bool focusAutomationBand(SongView &view, int &failures)
{
    return check(failures,
                 view.focusTimelineBand(songview::TimelineBand::Automation, Qt::MouseFocusReason),
                 "could not focus the automation band");
}

// Bounded wait for both layers of Quick focus to finish: the requested band
// must own the scene's active item, and Qt's native focus object/window must
// have caught up with that internal selection. focusBand() can satisfy only
// the first condition while QWindowContainer's FocusIn is still pending.
bool automationBandHasCompletedNativeFocus(songview::TimelineQuickView *quick)
{
    QQuickWindow *const window = quick ? quick->quickWindow() : nullptr;
    QQuickItem *const activeItem = window ? window->activeFocusItem() : nullptr;
    return quick && quick->focusedBand() == songview::TimelineBand::Automation && activeItem &&
           QGuiApplication::focusObject() == activeItem && QGuiApplication::focusWindow() == window;
}

bool automationBandOwnsFocus(songview::TimelineQuickView *quick)
{
    return waitUntil([] { return true; },
                     [quick] { return automationBandHasCompletedNativeFocus(quick); }, 5000,
                     10) == Result::Ready;
}

QString quickFocusState(songview::TimelineQuickView *quick)
{
    QQuickWindow *const window = quick ? quick->quickWindow() : nullptr;
    QQuickItem *const activeItem = window ? window->activeFocusItem() : nullptr;
    return QStringLiteral("active=%1 QWidget=%2 QGui-object=%3 QGui-window=%4 quick-window=%5")
        .arg(selectionkey::focusObjectIdentity(activeItem))
        .arg(selectionkey::focusObjectIdentity(QApplication::focusWidget()))
        .arg(selectionkey::focusObjectIdentity(QGuiApplication::focusObject()))
        .arg(selectionkey::focusObjectIdentity(QGuiApplication::focusWindow()))
        .arg(selectionkey::focusObjectIdentity(window));
}

// Real pointer delivery onto a chrome control: hover priming (the proven
// automation-fixture pattern), press, drag-distance activation step, then the
// actual drag move. Pressing never changes focus, so a focused band keeps
// owning the keys delivered during the gesture.
bool pressAndDrag(QQuickWindow *window, QQuickItem &surface, const QPointF &pressPoint,
                  const QPointF &dragPoint, int &failures, const char *what)
{
    if (!check(failures, checks::events::primeMouseMove(*window, surface, pressPoint.toPoint()),
               qPrintable(QStringLiteral("could not prime the hover move onto %1").arg(what))))
        return false;
    selectionkey::sendMouseEvent(*window, QEvent::MouseButtonPress, pressPoint, Qt::LeftButton);
    selectionkey::settle();
    const qreal activation = QGuiApplication::styleHints()->startDragDistance() + 1.0;
    const qreal activationStep = dragPoint.y() >= pressPoint.y() ? activation : -activation;
    selectionkey::sendMouseEvent(*window, QEvent::MouseMove,
                                 pressPoint + QPointF(0.0, activationStep), Qt::NoButton);
    selectionkey::settle();
    selectionkey::sendMouseEvent(*window, QEvent::MouseMove, dragPoint, Qt::NoButton);
    selectionkey::settle();
    return true;
}

void windowCopySoloExecutesExactlyOnce(ActionCounts &counts, SongTab &tab, int &failures)
{
    SongView &view = tab.view();
    SongDocument &document = tab.document();
    const ScenarioRollback rollback(view, document);
    view.selectTrack(kTrack);
    view.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    selectionkey::settle();
    QString error;
    const std::optional<NotePair> pair = addNotePair(document, kTrack, 960, error);
    if (!check(failures, pair.has_value(), qPrintable(error)))
        return;
    songview::TimelineQuickView *const quick = selectionkey::quickCanvas(view);
    QQuickWindow *const quickWindow = quick ? quick->quickWindow() : nullptr;
    if (!check(failures, quickWindow != nullptr && quick->rootObject() != nullptr,
               "the tab Quick surface is missing"))
        return;
    if (!focusAutomationBand(view, failures))
        return;
    const auto copy = firstBinding(QStringLiteral("roll.copy"));
    const auto solo = firstBinding(QStringLiteral("roll.solo_tracks"));
    if (!check(failures, copy.has_value() && solo.has_value(),
               "window Copy/Solo have no single-key bindings"))
        return;

    view.selectionModel().setNoteSelection({pair->ids[0], pair->ids[1]});
    const QByteArray before = document.smf().write();

    deliverKey(quickWindow, copy->key(), copy->keyboardModifiers());
    check(failures, counts.copy == 1,
          "window Copy with timeline/automation focus did not execute exactly once");
    check(failures, songview::clipboardHasClipMime(),
          "window Copy from timeline/automation focus did not capture the selected notes");
    check(failures, document.smf().write() == before, "window Copy mutated the document");

    deliverKey(quickWindow, solo->key(), solo->keyboardModifiers());
    check(failures, counts.solo == 1, "window Solo did not execute exactly once from band focus");
    check(failures, view.trackSoloed(kTrack), "one Solo press did not leave the track soloed once");

    deliverKey(quickWindow, solo->key(), solo->keyboardModifiers());
    check(failures, counts.solo == 2 && !view.trackSoloed(kTrack),
          "the second Solo press did not untoggle exactly once");

    deliverKey(quickWindow, Qt::Key_F24);
    check(failures, counts.copy == 1 && counts.solo == 2 && document.smf().write() == before,
          "an unrecognized key triggered a window action or mutated the song");

    view.selectionModel().clearNoteSelection();
}

void chromeKeyboardKeepsAdvertisedKeysAndRoutesButtons(ActionCounts &counts, SongTab &tab,
                                                       int &failures)
{
    SongView &view = tab.view();
    SongDocument &document = tab.document();
    EditorDrawer *const drawer = view.editorDrawer();
    const ScenarioRollback rollback(view, document);
    const FullControlTabTraversal fullControlTabTraversal;
    view.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    view.setDrawerSectionHeight(EditorDrawerPage::Automations, 200);
    view.selectTrack(kTrack);
    // Two controller lanes guarantee the automation content overflows a short
    // viewport, so the scrollbar scenario exercises real scrolling.
    document.addLanePoint(kTrack, kController, 48, 32);
    document.addLanePoint(kTrack, kController, 96, 64);
    document.addLanePoint(kTrack, kSecondController, 48, 96);
    selectionkey::settle();
    QString error;
    const std::optional<NotePair> pair = addNotePair(document, kTrack, 2400, error);
    if (!check(failures, pair.has_value(), qPrintable(error)))
        return;
    songview::TimelineQuickView *const quick = selectionkey::quickCanvas(view);
    QQuickWindow *const quickWindow = quick ? quick->quickWindow() : nullptr;
    if (!check(failures, quickWindow != nullptr && quick->rootObject() != nullptr,
               "the Quick surface is missing for chrome keyboard checks"))
        return;
    const int copyBefore = counts.copy;
    const int soloBefore = counts.solo;
    view.selectionModel().setNoteSelection({pair->ids[0], pair->ids[1]});

    // The resize grip: real Tab traversal from the focused automation band to
    // the grip, whose visible focus border is activeFocus-driven.
    if (!focusAutomationBand(view, failures))
        return;
    const QPointer<QQuickItem> grip = tabTo(quickWindow, {QStringLiteral("drawerAutomationHandle")},
                                            2 * document.engineTrackCount() + 12);
    if (!check(failures, grip != nullptr, "Tab traversal never reached the automation resize grip"))
        return;
    check(failures, grip->hasActiveFocus(),
          "the automation resize grip does not show its advertised active focus");
    const int gripStep = layout::space(layout::Space::Two);
    const int heightBefore = view.drawerSectionHeight(EditorDrawerPage::Automations);
    deliverKey(quickWindow, Qt::Key_Up);
    const int heightAfterUp = view.drawerSectionHeight(EditorDrawerPage::Automations);
    check(failures, heightAfterUp == heightBefore + gripStep,
          qPrintable(QStringLiteral("the focused grip's Up key did not grow the drawer by exactly "
                                    "one step (before %1, after %2, step %3)")
                         .arg(heightBefore)
                         .arg(heightAfterUp)
                         .arg(gripStep)));
    deliverKey(quickWindow, Qt::Key_Down);
    const int heightAfterDown = view.drawerSectionHeight(EditorDrawerPage::Automations);
    check(failures, heightAfterDown == heightBefore,
          qPrintable(QStringLiteral("the focused grip's Down key did not shrink the drawer back "
                                    "by exactly one step (after Up %1, after Down %2)")
                         .arg(heightAfterUp)
                         .arg(heightAfterDown)));
    check(failures, notePairUnchanged(document, *pair), "grip arrow keys moved the selected notes");
    check(failures, counts.copy == copyBefore && counts.solo == soloBefore,
          "grip arrow keys triggered a window action");
    deliverKey(quickWindow, Qt::Key_Left);
    deliverKey(quickWindow, Qt::Key_Right);
    check(failures, view.drawerSectionHeight(EditorDrawerPage::Automations) == heightBefore,
          "cross-axis arrows resized the drawer from the focused grip");
    check(failures, notePairUnchanged(document, *pair),
          "cross-axis arrows on the focused grip moved the selected notes");
    view.setDrawerSectionHeight(EditorDrawerPage::Automations, 200);
    view.selectionModel().setNoteSelection({pair->ids[0], pair->ids[1]});

    // The automation scrollbar: it is a tab stop only while it is scrollable
    // (activeFocusOnTab: scrollable || activeFocus), so the short viewport is
    // configured and the overflow confirmed before traversal starts.
    view.setDrawerSectionHeight(EditorDrawerPage::Automations, 90);
    if (!focusAutomationBand(view, failures))
        return;
    const QPointer<QQuickItem> scrollbar =
        tabTo(quickWindow, {QStringLiteral("drawerAutomationScrollBar")},
              2 * document.engineTrackCount() + 12);
    if (!check(failures, scrollbar != nullptr,
               "Tab traversal never reached the automation scrollbar"))
        return;
    check(failures, scrollbar->hasActiveFocus(),
          "the automation scrollbar does not show its advertised active focus");
    const bool scrollable =
        waitUntil([&] { return bool(scrollbar); },
                  [&] { return scrollbar && scrollbar->property("maximum").toDouble() > 0.0; },
                  2000, 10) == Result::Ready;
    const double maximum = scrollbar ? scrollbar->property("maximum").toDouble() : 0.0;
    if (check(failures, scrollable && maximum > 0.0,
              "the automation scrollbar is not scrollable in this fixture")) {
        if (AutomationPage *const automationPage = drawer ? drawer->automationPage() : nullptr) {
            automationPage->setVerticalScroll(0);
            selectionkey::settle();
        }
        if (!check(failures, scrollbar,
                   "the automation scrollbar was destroyed while resetting its value"))
            return;
        const double valueBefore = scrollbar->property("value").toDouble();
        deliverKey(quickWindow, Qt::Key_Down);
        if (!check(failures, scrollbar, "the automation scrollbar was destroyed by its Down key"))
            return;
        const double valueAfterDown = scrollbar->property("value").toDouble();
        check(failures, valueAfterDown > valueBefore && valueAfterDown <= maximum,
              "the focused scrollbar's Down key did not increase its bounded value");
        deliverKey(quickWindow, Qt::Key_Up);
        if (!check(failures, scrollbar, "the automation scrollbar was destroyed by its Up key"))
            return;
        const double valueAfterUp = scrollbar->property("value").toDouble();
        check(failures, valueAfterUp < valueAfterDown && valueAfterUp == valueBefore,
              "the focused scrollbar's inverse Up key did not restore its prior value");
        deliverKey(quickWindow, Qt::Key_Left);
        deliverKey(quickWindow, Qt::Key_Right);
        check(failures, scrollbar && scrollbar->property("value").toDouble() == valueAfterUp,
              "cross-axis arrows scrolled or destroyed the focused scrollbar");
        check(failures, notePairUnchanged(document, *pair),
              "scrollbar arrow keys moved the selected notes");
    }
    view.setDrawerSectionHeight(EditorDrawerPage::Automations, 200);
    view.selectionModel().setNoteSelection({pair->ids[0], pair->ids[1]});

    // The drawer toggle: activation keys stay local, and the note arrows route
    // to the selected notes with the exact production effect.
    if (!focusAutomationBand(view, failures))
        return;
    const QPointer<QQuickItem> toggle =
        tabTo(quickWindow, {QStringLiteral("drawerAutomationToggle")},
              2 * document.engineTrackCount() + 12);
    if (!check(failures, toggle != nullptr,
               "Tab traversal never reached the automation drawer toggle"))
        return;
    check(failures, toggle->hasActiveFocus(),
          "the automation drawer toggle does not show its advertised active focus");
    const std::optional<DocNote> beforeRight = noteById(document, pair->ids[0]);
    if (!check(failures, beforeRight.has_value(), "the selected note vanished before Right"))
        return;
    deliverKey(quickWindow, Qt::Key_Right);
    const std::optional<DocNote> afterRight = noteById(document, pair->ids[0]);
    // Production nudges the selection anchor to the next snap tick; both
    // selected notes advance by that same grid step, keys untouched.
    const uint64_t gridStep =
        view.grid().snapTickUp(double(beforeRight->tick) + 1.0) - beforeRight->tick;
    check(failures,
          afterRight.has_value() && afterRight->tick == beforeRight->tick + gridStep &&
              afterRight->key == beforeRight->key,
          "the routed Right arrow did not advance exactly the selected notes by one grid step");
    deliverKey(quickWindow, Qt::Key_Up);
    const std::optional<DocNote> afterUp = noteById(document, pair->ids[0]);
    check(failures,
          afterUp.has_value() && afterUp->key == uint8_t(beforeRight->key + 1) &&
              afterUp->tick == afterRight->tick,
          "the routed Up arrow did not transpose exactly the selected notes");
    const std::optional<DocNote> beforeActivation = noteById(document, pair->ids[0]);
    const bool visibleBefore = view.drawerSectionVisible(EditorDrawerPage::Automations);
    deliverKey(quickWindow, Qt::Key_Space);
    check(failures, view.drawerSectionVisible(EditorDrawerPage::Automations) != visibleBefore,
          "Space did not activate the focused drawer toggle");
    deliverKey(quickWindow, Qt::Key_Space);
    check(failures, view.drawerSectionVisible(EditorDrawerPage::Automations) == visibleBefore,
          "the second Space press did not restore the drawer toggle");
    const std::optional<DocNote> afterActivation = noteById(document, pair->ids[0]);
    check(failures,
          afterActivation.has_value() && beforeActivation.has_value() &&
              afterActivation->tick == beforeActivation->tick &&
              afterActivation->key == beforeActivation->key,
          "toggle activation keys moved or edited the selected notes");

    view.selectionModel().clearNoteSelection();
}

// Real Quick pointer-gesture protection (plan 6 at window tier): a live drawer
// resize drag or scrollbar thumb drag owns the surface, so shared editing keys
// are a consumed no-op while it holds the pointer; the first Escape cancels
// only the gesture and keeps the selection, and the next idle Escape clears.
// The press lands on the reachable grip/thumb without moving focus, so the
// gesture is not cancelled before the mid-gesture keys are delivered.
void drawerPointerGesturesProtectSelectedNotes(SongTab &tab, int &failures)
{
    SongView &view = tab.view();
    SongDocument &document = tab.document();
    const ScenarioRollback rollback(view, document);
    const bool velocityWasVisible = view.drawerSectionVisible(EditorDrawerPage::Velocity);
    const bool voiceChangesWasVisible = view.drawerSectionVisible(EditorDrawerPage::VoiceChanges);
    // Isolate the automation body from the host-height allocation consumed by
    // unrelated open drawers. The resize assertion below uses the canonical
    // body rectangle, not merely the requested/stored section height.
    view.setDrawerSectionVisible(EditorDrawerPage::Velocity, false);
    view.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, false);
    view.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    view.setDrawerSectionHeight(EditorDrawerPage::Automations, 200);
    view.selectTrack(kTrack);
    QString error;
    const std::optional<NotePair> pair = addNotePair(document, kTrack, 2400, error);
    if (!check(failures, pair.has_value(), qPrintable(error)))
        return;
    songview::TimelineQuickView *const quick = selectionkey::quickCanvas(view);
    QQuickWindow *const quickWindow = quick ? quick->quickWindow() : nullptr;
    const QPointer<QQuickItem> root = quick ? quick->rootObject() : nullptr;
    if (!check(failures, quickWindow != nullptr && root != nullptr,
               "the Quick surface is missing for pointer gesture checks"))
        return;
    EditorDrawer *const drawer = view.editorDrawer();
    AutomationPage *const automationPage = drawer ? drawer->automationPage() : nullptr;
    const QRect quickBounds(QPoint(0, 0), quickWindow->size());
    const auto mapsIntoWindow = [&quickBounds](QQuickItem *item) {
        return item && item->isVisible() &&
               quickBounds.contains(
                   item->mapToScene(QPointF{item->width() / 2.0, item->height() / 2.0}).toPoint());
    };
    const auto nudge = firstBinding(QStringLiteral("roll.nudge_right"));
    const auto remove = firstBinding(QStringLiteral("roll.delete"));
    if (!check(failures, nudge.has_value() && remove.has_value(),
               "nudge Right/Delete have no single-key bindings"))
        return;
    const std::vector<NoteId> selected{pair->ids[0], pair->ids[1]};
    const auto selectionKept = [&view, &selected] {
        return view.selectionModel().noteSelection() == selected;
    };
    const auto releaseAt = [&](const QPointF &point) {
        selectionkey::sendMouseEvent(*quickWindow, QEvent::MouseButtonRelease, point,
                                     Qt::LeftButton);
        selectionkey::settle();
    };
    const auto center = [](const QPointer<QQuickItem> &item) {
        return item ? item->mapToScene(item->boundingRect().center()) : QPointF{};
    };
    const auto findItem = [quick](const QString &name) {
        QQuickItem *const currentRoot = quick ? quick->rootObject() : nullptr;
        return QPointer<QQuickItem>(currentRoot ? currentRoot->findChild<QQuickItem *>(name)
                                                : nullptr);
    };

    // Live resize grip drag: the pressed grip resizes and owns the surface;
    // editing keys cannot mutate the notes until Escape cancels the drag. The
    // chrome snapshot and the mapped grip geometry must both be live before
    // the press, or the press lands on nothing and the drag never starts.
    QPointer<QQuickItem> grip = findItem(QStringLiteral("drawerAutomationHandleInput"));
    if (!check(failures,
               grip != nullptr && grip->width() > 0 && grip->height() > 0 && drawer != nullptr &&
                   drawer->chrome().automationHandleVisible() &&
                   waitUntil([] { return true; }, [&] { return mapsIntoWindow(grip); }, 2000, 10) ==
                       Result::Ready,
               "the automation resize grip input is missing or never mapped into the window"))
        return;
    if (!focusAutomationBand(view, failures) ||
        !check(failures, automationBandOwnsFocus(quick),
               qPrintable(QStringLiteral("the automation band never completed native focus "
                                         "before the gesture (%1)")
                              .arg(quickFocusState(quick)))))
        return;
    view.selectionModel().setNoteSelection(selected);
    const std::optional<DocNote> secondBeforeGrip = noteById(document, pair->ids[1]);
    if (!check(failures, secondBeforeGrip.has_value(),
               "the second selected note vanished before the resize gesture baseline"))
        return;
    const QByteArray beforeGrip = document.smf().write();
    const auto actualAutomationHeight = [drawer] {
        const std::optional<QRect> body = drawer->bodyRect(EditorDrawerPage::Automations);
        return body ? body->height() : -1;
    };
    const int requestedHeightBeforeDrag = view.drawerSectionHeight(EditorDrawerPage::Automations);
    const int actualHeightBeforeDrag = actualAutomationHeight();
    const int minimumHeight = drawer->minimumSectionHeight();
    constexpr int dragDistance = 40;
    if (!check(failures,
               actualHeightBeforeDrag == requestedHeightBeforeDrag &&
                   actualHeightBeforeDrag >= minimumHeight + dragDistance,
               qPrintable(QStringLiteral("the automation resize baseline is not an unclamped "
                                         "canonical body with room to shrink (requested %1, "
                                         "actual %2, minimum %3, drag distance %4)")
                              .arg(requestedHeightBeforeDrag)
                              .arg(actualHeightBeforeDrag)
                              .arg(minimumHeight)
                              .arg(dragDistance))))
        return;
    const QPointF gripPoint = center(grip);
    const QPointF dragPoint = gripPoint + QPointF(0.0, dragDistance);
    if (!pressAndDrag(quickWindow, *grip, gripPoint, dragPoint, failures,
                      "the automation resize grip"))
        return;
    check(failures, automationBandHasCompletedNativeFocus(quick),
          qPrintable(QStringLiteral("the grip press disturbed completed native Quick focus (%1)")
                         .arg(quickFocusState(quick))));
    const bool resizeGestureActive = quick->gestureActive();
    const bool resizeLive =
        waitUntil([] { return true; },
                  [&] { return actualAutomationHeight() < actualHeightBeforeDrag; }, 2000,
                  10) == Result::Ready;
    const int requestedHeightAfterDrag = view.drawerSectionHeight(EditorDrawerPage::Automations);
    const int actualHeightAfterDrag = actualAutomationHeight();
    if (!check(
            failures, resizeLive,
            qPrintable(QStringLiteral("the pressed grip did not shrink the live canonical "
                                      "body (requested before %1, actual before %2, minimum "
                                      "%3, press %4,%5, endpoint %6,%7, requested after %8, "
                                      "actual after %9, gesture active %10, focus %11)")
                           .arg(requestedHeightBeforeDrag)
                           .arg(actualHeightBeforeDrag)
                           .arg(minimumHeight)
                           .arg(gripPoint.x())
                           .arg(gripPoint.y())
                           .arg(dragPoint.x())
                           .arg(dragPoint.y())
                           .arg(requestedHeightAfterDrag)
                           .arg(actualHeightAfterDrag)
                           .arg(resizeGestureActive ? QStringLiteral("yes") : QStringLiteral("no"))
                           .arg(quickFocusState(quick))))) {
        releaseAt(dragPoint);
        return;
    }
    check(failures, document.smf().write() == beforeGrip && selectionKept(),
          "the live resize drag mutated the document or dropped the selection");
    deliverKey(quickWindow, nudge->key(), nudge->keyboardModifiers());
    deliverKey(quickWindow, remove->key(), remove->keyboardModifiers());
    check(failures, document.smf().write() == beforeGrip && selectionKept(),
          "Right/Delete during the live resize drag mutated the notes or dropped the selection");
    deliverKey(quickWindow, Qt::Key_Escape);
    check(failures, selectionKept(),
          "gesture Escape cleared the selection instead of canceling the resize drag");
    const int heightAfterCancel = view.drawerSectionHeight(EditorDrawerPage::Automations);
    selectionkey::sendMouseEvent(*quickWindow, QEvent::MouseMove, gripPoint, Qt::NoButton);
    selectionkey::settle();
    check(failures, view.drawerSectionHeight(EditorDrawerPage::Automations) == heightAfterCancel,
          "the resize drag survived its Escape cancellation");
    releaseAt(gripPoint);
    deliverKey(quickWindow, nudge->key(), nudge->keyboardModifiers());
    DocNote resumed;
    check(failures,
          document.findNote(pair->ids[1], &resumed) && resumed.tick != secondBeforeGrip->tick,
          "Right after the Escape cancellation did not resume note editing");
    deliverKey(quickWindow, Qt::Key_Escape);
    check(failures, view.selectionModel().noteSelection().empty(),
          "the second idle Escape did not clear the selection after the resize drag");
    view.setDrawerSectionHeight(EditorDrawerPage::Automations, 200);

    // Live scrollbar thumb drag: the same protection on QML-only drag state.
    view.setDrawerSectionHeight(EditorDrawerPage::Automations, 90);
    if (automationPage) {
        automationPage->setVerticalScroll(0);
        selectionkey::settle();
    }
    QPointer<QQuickItem> scrollbar = findItem(QStringLiteral("drawerAutomationScrollBar"));
    QPointer<QQuickItem> thumb = findItem(QStringLiteral("drawerAutomationScrollThumb"));
    const bool thumbReady =
        waitUntil([&] { return bool(quick); },
                  [&] {
                      if (!scrollbar)
                          scrollbar = findItem(QStringLiteral("drawerAutomationScrollBar"));
                      if (!thumb)
                          thumb = findItem(QStringLiteral("drawerAutomationScrollThumb"));
                      return scrollbar && thumb && thumb->isVisible() &&
                             automationPage != nullptr &&
                             automationPage->automationContentHeight() >
                                 automationPage->automationViewportSize().height();
                  },
                  2000, 10) == Result::Ready;
    if (!check(failures, thumbReady,
               "the automation scrollbar thumb is missing or not scrollable in this fixture"))
        return;
    if (!focusAutomationBand(view, failures))
        return;
    if (!check(failures, automationBandOwnsFocus(quick),
               qPrintable(QStringLiteral("the automation band never completed native focus "
                                         "before the scrollbar gesture (%1)")
                              .arg(quickFocusState(quick)))))
        return;
    view.selectionModel().setNoteSelection(selected);
    const std::optional<DocNote> secondBeforeThumb = noteById(document, pair->ids[1]);
    if (!check(failures, secondBeforeThumb.has_value(),
               "the second selected note vanished before the scrollbar gesture baseline"))
        return;
    const QByteArray beforeThumb = document.smf().write();
    const int scrollBeforeDrag = automationPage->verticalScroll();
    const QPointF thumbPoint = center(thumb);
    if (!check(failures, thumb, "the automation scrollbar thumb vanished before its drag") ||
        !pressAndDrag(quickWindow, *thumb, thumbPoint, thumbPoint + QPointF(0.0, 60.0), failures,
                      "the automation scrollbar thumb"))
        return;
    check(failures, automationBandHasCompletedNativeFocus(quick),
          qPrintable(QStringLiteral("the thumb press disturbed completed native Quick focus (%1)")
                         .arg(quickFocusState(quick))));
    const bool dragLive =
        waitUntil([] { return true; },
                  [&] { return automationPage->verticalScroll() > scrollBeforeDrag; }, 2000,
                  10) == Result::Ready;
    if (!check(failures, dragLive, "the pressed scrollbar thumb did not begin a live drag")) {
        releaseAt(thumbPoint + QPointF(0.0, 60.0));
        return;
    }
    check(failures, document.smf().write() == beforeThumb && selectionKept(),
          "the live scrollbar drag mutated the document or dropped the selection");
    deliverKey(quickWindow, nudge->key(), nudge->keyboardModifiers());
    deliverKey(quickWindow, remove->key(), remove->keyboardModifiers());
    check(failures, document.smf().write() == beforeThumb && selectionKept(),
          "Right/Delete during the live scrollbar drag mutated the notes or dropped the selection");
    deliverKey(quickWindow, Qt::Key_Escape);
    check(failures, selectionKept(),
          "gesture Escape cleared the selection instead of canceling the scrollbar drag");
    const int scrollAfterCancel = automationPage->verticalScroll();
    selectionkey::sendMouseEvent(*quickWindow, QEvent::MouseMove, thumbPoint, Qt::NoButton);
    selectionkey::settle();
    check(failures, automationPage->verticalScroll() == scrollAfterCancel,
          "the scrollbar drag survived its Escape cancellation");
    releaseAt(thumbPoint);
    deliverKey(quickWindow, nudge->key(), nudge->keyboardModifiers());
    check(failures,
          document.findNote(pair->ids[1], &resumed) && resumed.tick != secondBeforeThumb->tick,
          "Right after the Escape cancellation did not resume note editing");
    deliverKey(quickWindow, Qt::Key_Escape);
    check(failures, view.selectionModel().noteSelection().empty(),
          "the second idle Escape did not clear the selection after the scrollbar drag");
    view.setDrawerSectionHeight(EditorDrawerPage::Automations, 200);
    view.setDrawerSectionVisible(EditorDrawerPage::Velocity, velocityWasVisible);
    view.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, voiceChangesWasVisible);
    selectionkey::settle();
}

void tabsDocumentsAndPrimaryTrackLifetime(selectionkey::WindowSession &session,
                                          const QString &songA, const QString &songB, int &failures)
{
    WorkspaceUi &workspace = *session.workspace;
    QString error;
    SongTab *const tabA = workspace.songTabFor(*SongName::create(songA));
    if (!check(failures, tabA != nullptr, "the first song tab is missing"))
        return;
    SongView &viewA = tabA->view();
    SongDocument &documentA = tabA->document();
    viewA.selectTrack(kTrack);
    viewA.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    songview::TimelineQuickView *const quickA = selectionkey::quickCanvas(viewA);
    QQuickWindow *const windowA = quickA ? quickA->quickWindow() : nullptr;
    if (!check(failures, windowA != nullptr, "the first tab Quick window is missing"))
        return;

    // The isolated scenarios above leave the first tab at its saved state; the
    // explicit undo-to-clean gate keeps that true in its own right, so the
    // second-song open runs production's genuine clean lifecycle (a dirty tab
    // here is what turns the open into an unsaved-changes prompt). The clean
    // bytes then double as the cross-tab mutation baseline.
    makeSelectedTabClean(workspace, documentA,
                         "the first tab stayed dirty before the second-song open", failures);
    if (workspace.selectedSongDirty())
        return; // makeSelectedTabClean already recorded the precise failure
    const int tabCountBeforeSecondOpen = workspace.openTabCount();
    const QByteArray documentAClean = documentA.smf().write();

    SongTab *const tabB = selectionkey::openSongTab(session, songB, true, error);
    if (!check(failures, tabB != nullptr, qPrintable(error)))
        return;
    if (!check(failures,
               workspace.selectedSongTab() == tabB &&
                   workspace.openTabCount() == tabCountBeforeSecondOpen + 1 &&
                   workspace.songTabFor(tabA->name()) == tabA,
               "opening the second song did not add and select a distinct tab while retaining "
               "the first"))
        return;
    SongView &viewB = tabB->view();
    SongDocument &documentB = tabB->document();
    viewB.selectTrack(kTrack);
    viewB.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    const std::optional<NotePair> pairB = addNotePair(documentB, kTrack, 960, error);
    if (!check(failures, pairB.has_value(), qPrintable(error)))
        return;
    songview::TimelineQuickView *const quickB = selectionkey::quickCanvas(viewB);
    QQuickWindow *const windowB = quickB ? quickB->quickWindow() : nullptr;
    if (!check(failures, windowB != nullptr, "the second tab Quick window is missing"))
        return;
    viewB.selectionModel().setNoteSelection({pairB->ids[0], pairB->ids[1]});
    if (!focusAutomationBand(viewB, failures))
        return;
    deliverKey(windowB, Qt::Key_Right);
    check(failures, !notePairUnchanged(documentB, *pairB),
          "arrows did not move the selected notes on the second tab");
    check(failures, documentA.smf().write() == documentAClean,
          "key delivery to the second tab mutated the first tab's document");
    const QByteArray documentBAfterMove = documentB.smf().write();

    workspace.selectSongTab(tabA);
    selectionkey::settle();
    if (!check(failures, workspace.selectedSongTab() == tabA, "the first tab did not reselect"))
        return;
    const std::optional<NotePair> pairA = addNotePair(documentA, kTrack, 3840, error);
    if (!check(failures, pairA.has_value(), qPrintable(error)))
        return;
    viewA.selectionModel().setNoteSelection({pairA->ids[0], pairA->ids[1]});
    if (!focusAutomationBand(viewA, failures))
        return;
    deliverKey(windowA, Qt::Key_Up);
    DocNote noteA;
    check(failures,
          documentA.findNote(pairA->ids[0], &noteA) &&
              noteA.key == uint8_t(pairA->notes[0].key + 1),
          "the Up arrow did not transpose the first tab's selection after reselecting it");
    check(failures, documentB.smf().write() == documentBAfterMove,
          "key delivery to the first tab mutated the second tab's document");

    viewA.setDrawerSectionVisible(EditorDrawerPage::Automations, false);
    selectionkey::settle();
    viewA.selectionModel().setNoteSelection({pairA->ids[0], pairA->ids[1]});
    const std::optional<DocNote> beforeHide = noteById(documentA, pairA->ids[0]);
    if (!check(failures, beforeHide.has_value(),
               "the first selected note vanished before the hidden-drawer baseline"))
        return;
    deliverKey(windowA, Qt::Key_Right);
    check(failures, documentA.findNote(pairA->ids[0], &noteA) && noteA.tick != beforeHide->tick,
          "note arrows stopped routing while the drawer was hidden");
    viewA.setDrawerSectionVisible(EditorDrawerPage::Automations, true);

    // The primary-track change clears the selection and retargets routing.
    if (!check(failures, documentA.engineTrackCount() > 1,
               "the rich fixture needs a second track for primary-track routing"))
        return;
    const std::optional<NotePair> pairT1 = addNotePair(documentA, 1, 960, error);
    if (!check(failures, pairT1.has_value(), qPrintable(error)))
        return;
    viewA.selectTrack(1);
    check(failures, viewA.selectionModel().noteSelection().empty(),
          "the primary-track change did not clear the note selection");
    viewA.selectionModel().setNoteSelection({pairT1->ids[0], pairT1->ids[1]});
    if (!focusAutomationBand(viewA, failures))
        return;
    deliverKey(windowA, Qt::Key_Up);
    DocNote trackOneNote;
    check(failures,
          documentA.findNote(pairT1->ids[0], &trackOneNote) &&
              trackOneNote.key == uint8_t(pairT1->notes[0].key + 1),
          "the Up arrow did not transpose the new primary track's selection");

    // Return both tabs to their saved state so the close, the reopen, and the
    // final window close take production's genuine clean lifecycle instead of
    // blocking in an unsaved-changes prompt.
    makeSelectedTabClean(workspace, documentA,
                         "the first tab stayed dirty before closing the second tab", failures);
    workspace.selectSongTab(tabB);
    selectionkey::settle();
    makeSelectedTabClean(workspace, documentB, "the second tab stayed dirty before its close",
                         failures);
    if (!check(failures, !workspace.selectedSongDirty(),
               "the second tab is dirty right before its close request"))
        return;
    const QPointer<SongTab> closingTab = tabB;
    {
        DeclineModalsWithin guard(QStringLiteral("closing the clean second song tab"));
        workspace.requestCloseSelectedTab();
    }
    selectionkey::settle();
    if (!check(failures,
               workspace.songTabFor(*SongName::create(songB)) == nullptr && closingTab.isNull(),
               "the clean second tab did not close and destroy its session"))
        return;
    const int tabCountBeforeReopen = workspace.openTabCount();
    SongTab *const reopened = selectionkey::openSongTab(session, songB, true, error);
    if (!check(failures, reopened != nullptr, qPrintable(error)))
        return;
    if (!check(failures,
               workspace.selectedSongTab() == reopened &&
                   workspace.openTabCount() == tabCountBeforeReopen + 1 &&
                   workspace.songTabFor(tabA->name()) == tabA,
               "reopening the second song did not create and select its replacement while "
               "retaining the first tab"))
        return;
    SongView &viewR = reopened->view();
    SongDocument &documentR = reopened->document();
    viewR.selectTrack(kTrack);
    viewR.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    const std::optional<NotePair> pairR = addNotePair(documentR, kTrack, 960, error);
    if (!check(failures, pairR.has_value(), qPrintable(error)))
        return;
    songview::TimelineQuickView *const quickR = selectionkey::quickCanvas(viewR);
    QQuickWindow *const windowR = quickR ? quickR->quickWindow() : nullptr;
    if (!check(failures, windowR != nullptr, "the reopened tab Quick window is missing"))
        return;
    viewR.selectionModel().setNoteSelection({pairR->ids[0], pairR->ids[1]});
    if (!focusAutomationBand(viewR, failures))
        return;
    deliverKey(windowR, Qt::Key_Right);
    check(failures, !notePairUnchanged(documentR, *pairR),
          "the reopened tab's routing is stale or dead after document replacement");
    makeSelectedTabClean(workspace, documentR,
                         "the reopened tab stayed dirty before the window close", failures);
}

} // namespace

int runSelectionKeyWindowCheck(const QString &projectRoot, const QString &songA,
                               const QString &songB)
{
    int failures = 0;
    // The window-owned action connections capture this counter by reference,
    // so it must outlive WindowSession and any signals emitted during teardown.
    ActionCounts counts;
    selectionkey::WindowSession session;
    QString error;
    if (!selectionkey::openWindowSession(session, projectRoot, error)) {
        fail(failures, error);
        return 1;
    }
    SongTab *const tab = selectionkey::openSongTab(session, songA, false, error);
    if (!tab) {
        fail(failures, error);
        return 1;
    }
    if (!observeWindowActions(*session.window, counts)) {
        fail(failures, QStringLiteral("the production shell is missing the window actions"));
        return 1;
    }

    // Qt::WindowShortcut actions match only while the shell is
    // QApplication's active window (the qWidgetShortcutContextMatcher
    // prerequisite RoutingRuntimeRepair measured), and a gated background
    // process can have macOS deny activation outright. Activate before any
    // band focus — activating after focusing a Quick band clears the scene's
    // activeFocusItem — then observe the prerequisite honestly so a denial
    // is its own attributed failure instead of shortcut assertions
    // masquerading as routing regressions.
    session.window->activateWindow();
    check(failures,
          waitUntil([] { return true; },
                    [&] { return QApplication::activeWindow() == session.window.get(); }, 2000,
                    10) == Result::Ready,
          "the production shell never became the active window, so window shortcuts cannot fire");

    windowCopySoloExecutesExactlyOnce(counts, *tab, failures);
    chromeKeyboardKeepsAdvertisedKeysAndRoutesButtons(counts, *tab, failures);
    drawerPointerGesturesProtectSelectedNotes(*tab, failures);
    tabsDocumentsAndPrimaryTrackLifetime(session, songA, songB, failures);

    // The session ends the way a clean user session ends: every tab is back
    // at its saved state. Confirm that clean state explicitly — a dirty tab
    // here means the production close path would prompt, and the guard below
    // must never be what hides that regression.
    check(failures, !session.workspace->selectedSongDirty(),
          "the selected tab is dirty right before the explicit close event");
    check(failures, !session.workspace->hasPendingSaveWork(),
          "a tab still has unsaved work right before the explicit close event");
    {
        DeclineModalsWithin guard(QStringLiteral("closing the window session"));
        QCloseEvent closeEvent;
        QApplication::sendEvent(session.window.get(), &closeEvent);
        check(failures, closeEvent.isAccepted(),
              "the clean session close was not accepted by the production shell");
        session.window->close();
        selectionkey::settle();
    }
    std::fprintf(stderr, "selectionkeywindowcheck: %s\n", failures == 0 ? "PASS" : "FAIL");
    return failures == 0 ? 0 : 1;
}
