// Selection keyboard routing, window tier: keyboard scenarios. Window
// Copy/Solo execute exactly once from timeline/automation focus and an
// unrecognized key is a terminal no-op (plan 5); deliberately keyboard-focused
// chrome reached by real Tab traversal — the drawer resize grip, the
// automation scrollbar, and the drawer toggle — keeps its advertised local
// keys while the focused toggle still routes note arrows to the selected notes
// with the exact production effect (plan 13). macOS commonly runs the
// text-only keyboard navigation policy, so the chrome cases wrap traversal in
// the process-local Qt::TabFocusAllControls guard; the traversal itself stays
// real Tab key delivery with visible-focus assertions.

#include "checks/selectionkey/tst_windowtier.h"

#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/layout.h"
#include "ui/songview/clipmime.h"
#include <QGuiApplication>
#include <QQuickItem>
#include <QStringList>
#include <QStyleHints>
#include <cstdio>

namespace {

constexpr int kTrack = 0;
// A second CC lane next to kController: two lanes plus the tempo lane keep
// the automation content taller than the short scrollbar viewport.
constexpr uint8_t kController = 10;
constexpr uint8_t kSecondController = 74;

// Full-control Tab traversal precondition, scoped to the keyboard traversal
// cases. macOS hosts commonly run the text-only keyboard navigation policy
// (AppleKeyboardUIMode 0); Qt Quick then skips every non-text control during
// Tab traversal — QQuickItemPrivate::canAcceptTabFocus only honors
// activeFocusOnTab for editable text and list/table roles — so plan 13's real
// Tab delivery to the drawer grip, scrollbar, and toggle could never arrive no
// matter how the fixture is staged. Qt exposes the policy as per-process
// in-memory state: this guard sets Qt::TabFocusAllControls and restores the
// previous Qt value at scope end. It never touches the user's OS settings and
// never substitutes focus synthesis.
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

int chromeTraversalBound(SongDocument &document)
{
    return 2 * document.engineTrackCount() + 12;
}

} // namespace

void SelectionWindowTierTest::windowCopySoloExecutesExactlyOnce()
{
    SongView &view = this->view();
    const selectionkey::ScenarioRollback rollback(view, document());
    view.selectTrack(kTrack);
    view.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    selectionkey::settle();
    const std::optional<NotePair> pair = addNotePair(document(), kTrack, 960);
    QVERIFY2(pair.has_value(),
             "the reserved tick-960 note pair could not be inserted and resolved");
    QVERIFY2(focusAutomationBand(view), "could not focus the automation band");
    const auto copy = selectionkey::firstBinding(QStringLiteral("roll.copy"));
    const auto solo = selectionkey::firstBinding(QStringLiteral("roll.solo_tracks"));
    QVERIFY2(copy.has_value() && solo.has_value(), "window Copy/Solo have no single-key bindings");

    view.selectionModel().setNoteSelection({pair->ids[0], pair->ids[1]});
    const QByteArray before = document().smf().write();

    selectionkey::deliverKey(quickWindow(), copy->key(), copy->keyboardModifiers());
    QCOMPARE(m_counts.copy, 1);
    QVERIFY2(songview::clipboardHasClipMime(),
             "window Copy from timeline/automation focus did not capture the selected notes");
    QVERIFY2(document().smf().write() == before, "window Copy mutated the document");

    selectionkey::deliverKey(quickWindow(), solo->key(), solo->keyboardModifiers());
    QCOMPARE(m_counts.solo, 1);
    QVERIFY2(view.trackSoloed(kTrack), "one Solo press did not leave the track soloed once");

    selectionkey::deliverKey(quickWindow(), solo->key(), solo->keyboardModifiers());
    QVERIFY2(m_counts.solo == 2 && !view.trackSoloed(kTrack),
             "the second Solo press did not untoggle exactly once");

    selectionkey::deliverKey(quickWindow(), Qt::Key_F24);
    QVERIFY2(m_counts.copy == 1 && m_counts.solo == 2 && document().smf().write() == before,
             "an unrecognized key triggered a window action or mutated the song");

    view.selectionModel().clearNoteSelection();
}

void SelectionWindowTierTest::chromeGridCommandsReachRootFallbackExactlyOnce()
{
    SongView &view = this->view();
    SongDocument &document = this->document();
    const selectionkey::ScenarioRollback rollback(view, document);
    const FullControlTabTraversal fullControlTabTraversal;
    view.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    view.setDrawerSectionHeight(EditorDrawerPage::Automations, 200);
    view.selectTrack(kTrack);
    QVERIFY2(focusAutomationBand(view), "could not focus the automation band before traversal");

    const QPointer<QQuickItem> toggle = tabTo(
        quickWindow(), {QStringLiteral("drawerAutomationToggle")}, chromeTraversalBound(document));
    QVERIFY2(toggle && toggle->hasActiveFocus(),
             "Tab traversal did not give the drawer toggle live Quick focus");
    const auto narrow = selectionkey::firstBinding(QStringLiteral("roll.grid_narrow"));
    const auto widen = selectionkey::firstBinding(QStringLiteral("roll.grid_widen"));
    const auto triplet = selectionkey::firstBinding(QStringLiteral("roll.grid_triplet"));
    QVERIFY2(narrow.has_value() && widen.has_value() && triplet.has_value(),
             "the three grid commands need single-key bindings");

    const auto hasGridState = [&view](songview::GridSelection selection, songview::GridFeel feel,
                                      uint64_t ticks) {
        return view.gridSelection() == selection && view.grid().feel() == feel &&
               view.grid().snapTicksAt(0) == ticks;
    };
    view.setGridFeel(songview::GridFeel::Straight);
    view.setGridSelection(songview::GridSelection::musical(16));
    QVERIFY2(hasGridState(songview::GridSelection::musical(16), songview::GridFeel::Straight, 6),
             "the 24-PPQN window fixture did not stage a six-tick grid");

    // The toggle has no local grid shortcut. Each QTest key reaches its live
    // chrome focus item first, then the TimelineCanvas fallback exactly once.
    selectionkey::deliverKey(quickWindow(), narrow->key(), narrow->keyboardModifiers());
    QVERIFY2(
        toggle && toggle->hasActiveFocus() &&
            hasGridState(songview::GridSelection::musical(32), songview::GridFeel::Straight, 3),
        "one chrome-delivered narrow chord did not make exactly the 6-to-3 step");
    selectionkey::deliverKey(quickWindow(), widen->key(), widen->keyboardModifiers());
    QVERIFY2(
        toggle && toggle->hasActiveFocus() &&
            hasGridState(songview::GridSelection::musical(16), songview::GridFeel::Straight, 6),
        "one chrome-delivered widen chord did not make exactly the 3-to-6 step");
    selectionkey::deliverKey(quickWindow(), triplet->key(), triplet->keyboardModifiers());
    QVERIFY2(toggle && toggle->hasActiveFocus() &&
                 hasGridState(songview::GridSelection::musical(16), songview::GridFeel::Triplet, 4),
             "one chrome-delivered triplet chord did not toggle exactly once");
}

void SelectionWindowTierTest::chromeGripKeysStayLocal()
{
    SongView &view = this->view();
    SongDocument &document = this->document();
    const selectionkey::ScenarioRollback rollback(view, document);
    const FullControlTabTraversal fullControlTabTraversal;
    view.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    view.setDrawerSectionHeight(EditorDrawerPage::Automations, 200);
    view.selectTrack(kTrack);
    const std::optional<NotePair> pair = addNotePair(document, kTrack, 2400);
    QVERIFY2(pair.has_value(),
             "the reserved tick-2400 note pair could not be inserted and resolved");
    QVERIFY2(focusAutomationBand(view), "could not focus the automation band");
    view.selectionModel().setNoteSelection({pair->ids[0], pair->ids[1]});
    // The resize grip: real Tab traversal from the focused automation band to
    // the grip, whose visible focus border is activeFocus-driven.
    const QPointer<QQuickItem> grip = tabTo(
        quickWindow(), {QStringLiteral("drawerAutomationHandle")}, chromeTraversalBound(document));
    QVERIFY2(grip, "Tab traversal never reached the automation resize grip");
    QVERIFY2(grip->hasActiveFocus(),
             "the automation resize grip does not show its advertised active focus");
    const int copyBefore = m_counts.copy;
    const int soloBefore = m_counts.solo;
    const int gripStep = layout::space(layout::Space::Two);
    const int heightBefore = view.drawerSectionHeight(EditorDrawerPage::Automations);
    selectionkey::deliverKey(quickWindow(), Qt::Key_Up);
    const int heightAfterUp = view.drawerSectionHeight(EditorDrawerPage::Automations);
    QCOMPARE(heightAfterUp, heightBefore + gripStep);
    selectionkey::deliverKey(quickWindow(), Qt::Key_Down);
    const int heightAfterDown = view.drawerSectionHeight(EditorDrawerPage::Automations);
    QCOMPARE(heightAfterDown, heightBefore);
    QVERIFY2(notePairUnchanged(document, *pair), "grip arrow keys moved the selected notes");
    QVERIFY2(m_counts.copy == copyBefore && m_counts.solo == soloBefore,
             "grip arrow keys triggered a window action");
    selectionkey::deliverKey(quickWindow(), Qt::Key_Left);
    selectionkey::deliverKey(quickWindow(), Qt::Key_Right);
    QCOMPARE(view.drawerSectionHeight(EditorDrawerPage::Automations), heightBefore);
    QVERIFY2(notePairUnchanged(document, *pair),
             "cross-axis arrows on the focused grip moved the selected notes");
}

void SelectionWindowTierTest::chromeScrollbarKeysStayLocal()
{
    SongView &view = this->view();
    SongDocument &document = this->document();
    EditorDrawer *const drawer = view.editorDrawer();
    const selectionkey::ScenarioRollback rollback(view, document);
    const FullControlTabTraversal fullControlTabTraversal;
    view.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    view.selectTrack(kTrack);
    // Two controller lanes guarantee the automation content overflows the
    // short viewport, so the scrollbar case exercises real scrolling, and the
    // scrollbar is a tab stop only while it is scrollable
    // (activeFocusOnTab: scrollable || activeFocus).
    document.addLanePoint(kTrack, kController, 48, 32);
    document.addLanePoint(kTrack, kController, 96, 64);
    document.addLanePoint(kTrack, kSecondController, 48, 96);
    view.setDrawerSectionHeight(EditorDrawerPage::Automations, 90);
    const std::optional<NotePair> pair = addNotePair(document, kTrack, 2400);
    QVERIFY2(pair.has_value(),
             "the reserved tick-2400 note pair could not be inserted and resolved");
    QVERIFY2(focusAutomationBand(view), "could not focus the automation band");
    view.selectionModel().setNoteSelection({pair->ids[0], pair->ids[1]});
    const QPointer<QQuickItem> scrollbar =
        tabTo(quickWindow(), {QStringLiteral("drawerAutomationScrollBar")},
              chromeTraversalBound(document));
    QVERIFY2(scrollbar, "Tab traversal never reached the automation scrollbar");
    QVERIFY2(scrollbar->hasActiveFocus(),
             "the automation scrollbar does not show its advertised active focus");
    const bool scrollable =
        checks::async_wait::waitUntil(
            [&] { return bool(scrollbar); },
            [&] { return scrollbar && scrollbar->property("maximum").toDouble() > 0.0; }, 2000,
            10) == checks::async_wait::Result::Ready;
    const double maximum = scrollbar ? scrollbar->property("maximum").toDouble() : 0.0;
    QVERIFY2(scrollable && maximum > 0.0,
             "the automation scrollbar is not scrollable in this fixture");
    if (AutomationPage *const automationPage = drawer ? drawer->automationPage() : nullptr) {
        automationPage->setVerticalScroll(0);
        selectionkey::settle();
    }
    QVERIFY2(scrollbar, "the automation scrollbar was destroyed while resetting its value");
    const int copyBefore = m_counts.copy;
    const int soloBefore = m_counts.solo;
    const double valueBefore = scrollbar->property("value").toDouble();
    selectionkey::deliverKey(quickWindow(), Qt::Key_Down);
    QVERIFY2(scrollbar, "the automation scrollbar was destroyed by its Down key");
    const double valueAfterDown = scrollbar->property("value").toDouble();
    QVERIFY2(valueAfterDown > valueBefore && valueAfterDown <= maximum,
             "the focused scrollbar's Down key did not increase its bounded value");
    selectionkey::deliverKey(quickWindow(), Qt::Key_Up);
    QVERIFY2(scrollbar, "the automation scrollbar was destroyed by its Up key");
    const double valueAfterUp = scrollbar->property("value").toDouble();
    QVERIFY2(valueAfterUp < valueAfterDown && valueAfterUp == valueBefore,
             "the focused scrollbar's inverse Up key did not restore its prior value");
    selectionkey::deliverKey(quickWindow(), Qt::Key_Left);
    selectionkey::deliverKey(quickWindow(), Qt::Key_Right);
    QVERIFY2(scrollbar && scrollbar->property("value").toDouble() == valueAfterUp,
             "cross-axis arrows scrolled or destroyed the focused scrollbar");
    QVERIFY2(notePairUnchanged(document, *pair), "scrollbar arrow keys moved the selected notes");
    QVERIFY2(m_counts.copy == copyBefore && m_counts.solo == soloBefore,
             "scrollbar arrow keys triggered a window action");
}

void SelectionWindowTierTest::chromeToggleRoutesNoteArrows()
{
    SongView &view = this->view();
    SongDocument &document = this->document();
    const selectionkey::ScenarioRollback rollback(view, document);
    const FullControlTabTraversal fullControlTabTraversal;
    view.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    view.setDrawerSectionHeight(EditorDrawerPage::Automations, 200);
    view.selectTrack(kTrack);
    const std::optional<NotePair> pair = addNotePair(document, kTrack, 2400);
    QVERIFY2(pair.has_value(),
             "the reserved tick-2400 note pair could not be inserted and resolved");
    QVERIFY2(focusAutomationBand(view), "could not focus the automation band");
    view.selectionModel().setNoteSelection({pair->ids[0], pair->ids[1]});

    // The drawer toggle: activation keys stay local, and the note arrows route
    // to the selected notes with the exact production effect.
    const QPointer<QQuickItem> toggle = tabTo(
        quickWindow(), {QStringLiteral("drawerAutomationToggle")}, chromeTraversalBound(document));
    QVERIFY2(toggle, "Tab traversal never reached the automation drawer toggle");
    QVERIFY2(toggle->hasActiveFocus(),
             "the automation drawer toggle does not show its advertised active focus");
    const std::optional<DocNote> beforeRight = selectionkey::noteById(document, pair->ids[0]);
    QVERIFY2(beforeRight.has_value(), "the selected note vanished before Right");
    selectionkey::deliverKey(quickWindow(), Qt::Key_Right);
    const std::optional<DocNote> afterRight = selectionkey::noteById(document, pair->ids[0]);
    // Production nudges the selection anchor to the next snap tick; both
    // selected notes advance by that same grid step, keys untouched.
    const uint64_t gridStep =
        view.grid().snapTickUp(double(beforeRight->tick) + 1.0) - beforeRight->tick;
    QVERIFY2(afterRight.has_value() && afterRight->tick == beforeRight->tick + gridStep &&
                 afterRight->key == beforeRight->key,
             "the routed Right arrow did not advance exactly the selected notes by one grid step");
    selectionkey::deliverKey(quickWindow(), Qt::Key_Up);
    const std::optional<DocNote> afterUp = selectionkey::noteById(document, pair->ids[0]);
    QVERIFY2(afterUp.has_value() && afterUp->key == uint8_t(beforeRight->key + 1) &&
                 afterUp->tick == afterRight->tick,
             "the routed Up arrow did not transpose exactly the selected notes");
    const std::optional<DocNote> beforeActivation = selectionkey::noteById(document, pair->ids[0]);
    const bool visibleBefore = view.drawerSectionVisible(EditorDrawerPage::Automations);
    selectionkey::deliverKey(quickWindow(), Qt::Key_Space);
    QVERIFY2(view.drawerSectionVisible(EditorDrawerPage::Automations) != visibleBefore,
             "Space did not activate the focused drawer toggle");
    selectionkey::deliverKey(quickWindow(), Qt::Key_Space);
    QVERIFY2(view.drawerSectionVisible(EditorDrawerPage::Automations) == visibleBefore,
             "the second Space press did not restore the drawer toggle");
    const std::optional<DocNote> afterActivation = selectionkey::noteById(document, pair->ids[0]);
    QVERIFY2(afterActivation.has_value() && beforeActivation.has_value() &&
                 afterActivation->tick == beforeActivation->tick &&
                 afterActivation->key == beforeActivation->key,
             "toggle activation keys moved or edited the selected notes");

    view.selectionModel().clearNoteSelection();
}
