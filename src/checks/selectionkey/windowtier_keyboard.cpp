// Selection keyboard routing through the production Quick window: parameter
// labels keep activation local and leave shared editing commands to SongView.
// Drawer grips and toggles retain their existing keyboard behavior.

#include "checks/selectionkey/tst_windowtier.h"

#include "checks/automation/automationvalueprompt.h"

#include "checks/support/timelinequickcheck.h"

#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/layout.h"
#include "ui/songview/clipmime.h"
#include <QClipboard>
#include <QGuiApplication>
#include <QQuickItem>
#include <QStringList>
#include <QStyleHints>
#include <QUndoStack>
#include <cstdio>

namespace {

constexpr int kTrack = 0;
constexpr uint8_t kController = 10;
constexpr uint8_t kSecondController = 1;

// Full-control Tab traversal precondition, scoped to the keyboard traversal
// cases. macOS hosts commonly run the text-only keyboard navigation policy
// (AppleKeyboardUIMode 0); Qt Quick then skips every non-text control during
// Tab traversal — QQuickItemPrivate::canAcceptTabFocus only honors
// activeFocusOnTab for editable text and list/table roles — so plan 13's real
// Tab delivery to the drawer grip and toggle could never arrive no
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
    return 2 * document.engineTrackCount() + 21;
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

void SelectionWindowTierTest::parameterLabelActivationAndSharedCommands()
{
    SongView &view = this->view();
    SongDocument &document = this->document();
    const selectionkey::ScenarioRollback rollback(view, document);
    view.selectTrack(kTrack);
    view.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    view.setDrawerSectionHeight(EditorDrawerPage::Automations, 200);
    constexpr uint64_t tick = 5760;
    constexpr uint64_t pasteTick = 7680;
    document.addLanePoint(kTrack, kController, tick, 32);
    document.addLanePoint(kTrack, kSecondController, tick, 96);
    document.addLanePoint(kTrack, 7, tick, 48);
    const auto pair = addNotePair(document, kTrack, 2400);
    QVERIFY(pair.has_value());
    QVERIFY(focusAutomationBand(view));
    auto *const canvas = view.editorDrawer()->automationPage()->canvas();
    auto *const quick = selectionkey::quickCanvas(view);
    QVERIFY(canvas && quick);
    QTRY_VERIFY(quickWindow()->isActive() && QGuiApplication::focusWindow() == quickWindow());

    songview::EditorSelectionModel::TimeSelection selected;
    selected.startTick = tick;
    selected.endTick = tick + 24;
    selected.scope = songview::EditorSelectionModel::TimeSelection::Lanes;
    selected.lanes = {{kTrack, kController}, {kTrack, kSecondController}};
    view.selectionModel().setTimeSelection(selected);
    const auto selectionUnchanged = [&] {
        const auto &actual = view.selectionModel().timeSelection();
        return actual.startTick == selected.startTick && actual.endTick == selected.endTick &&
               actual.scope == selected.scope && actual.lanes == selected.lanes &&
               actual.tempo == selected.tempo && view.selectionModel().noteSelection().empty();
    };
    const QByteArray before = document.smf().write();
    const int undoBefore = document.undoStack()->index();
    const uint64_t cursorBefore = view.editCursorTick();
    QPointer<QQuickItem> label;
    const auto focusParameter = [&](uint8_t controller) {
        const int index = checks::support::automationParameterIndex(
            *canvas, {EditorAutomationRowKind::ControlChange, kTrack, controller});
        if (index < 0 || !QTest::qWaitFor([&] {
                label = checks::support::visualDescendant(
                    quick->rootObject(), QStringLiteral("automationParameterTab%1").arg(index));
                return label && label->window() == quickWindow() && label->isVisible() &&
                       label->isEnabled() && label->width() > 0 && label->height() > 0;
            }))
            return false;
        label->forceActiveFocus(Qt::OtherFocusReason);
        selectionkey::settle();
        return label && label->hasActiveFocus();
    };
    QVERIFY(focusParameter(kController));
    QVERIFY(selectionUnchanged());
    const auto activeBeforeSpace = canvas->parameterRow(canvas->activeParameter());
    selectionkey::deliverKey(quickWindow(), Qt::Key_Space);
    const EditorAutomationRowId pan{EditorAutomationRowKind::ControlChange, kTrack, kController};
    QCOMPARE(canvas->parameterRow(canvas->activeParameter()), std::optional{pan});
    QVERIFY(activeBeforeSpace != std::optional{pan});
    QCOMPARE(document.smf().write(), before);
    QVERIFY(selectionUnchanged());

    // Only the advertised extension needs an exactly-once integration guard.
    QSignalSpy parameterChanges(canvas, &AutomationCanvas::activeParameterChanged);
    QVERIFY(focusParameter(kSecondController));
    selectionkey::deliverKey(quickWindow(), Qt::Key_Enter);
    const EditorAutomationRowId modulation{EditorAutomationRowKind::ControlChange, kTrack,
                                           kSecondController};
    QCOMPARE(canvas->parameterRow(canvas->activeParameter()), std::optional{modulation});
    QCOMPARE(parameterChanges.count(), 1);
    QVERIFY(selectionUnchanged());
    QVERIFY(focusParameter(7));
    selectionkey::deliverKey(quickWindow(), Qt::Key_Return);
    const EditorAutomationRowId volume{EditorAutomationRowKind::ControlChange, kTrack, 7};
    QCOMPARE(canvas->parameterRow(canvas->activeParameter()), std::optional{volume});
    QCOMPARE(parameterChanges.count(), 2);
    QCOMPARE(document.smf().write(), before);
    QCOMPARE(document.undoStack()->index(), undoBefore);
    QCOMPARE(view.editCursorTick(), cursorBefore);
    QCOMPARE(view.selectionModel().primaryTrack(), kTrack);
    QVERIFY(selectionUnchanged());

    // Up is a shared lane-selection no-op, not selector navigation.
    selectionkey::deliverKey(quickWindow(), Qt::Key_Up);
    QCOMPARE(document.smf().write(), before);
    QCOMPARE(canvas->parameterRow(canvas->activeParameter()), std::optional{volume});
    QVERIFY(selectionUnchanged());
    const auto copy = selectionkey::firstBinding(QStringLiteral("roll.copy"));
    const auto remove = selectionkey::firstBinding(QStringLiteral("roll.delete"));
    const auto selectAll = selectionkey::firstBinding(QStringLiteral("roll.select_all"));
    const auto paste = selectionkey::firstBinding(QStringLiteral("roll.paste"));
    QVERIFY(copy && remove && selectAll && paste);
    const int copiesBefore = m_counts.copy;
    // A prompt opened over label focus temporarily owns text commands.
    std::optional<LaneHandle> volumeLane;
    const auto &rows = canvas->rows();
    for (size_t index = 0; index < rows.size(); ++index) {
        if (rows[index].id == volume)
            volumeLane = LaneHandle{int(index) + 1};
    }
    QVERIFY(volumeLane.has_value());
    QVERIFY(canvas->openValuePromptForInsertion(*volumeLane, tick + 48, 48));
    QTRY_VERIFY(canvas->valuePromptVisible() && quickWindow()->activeFocusItem() != label.data() &&
                automation_valueprompt::focusedTextInput(*quickWindow()));
    QPointer<QQuickItem> prompt = automation_valueprompt::focusedTextInput(*quickWindow());
    const int promptCopiesBefore = m_counts.copy;
    selectionkey::deliverKey(quickWindow(), selectAll->key(), selectAll->keyboardModifiers());
    QVERIFY(prompt);
    const QString selectedText = prompt->property("selectedText").toString();
    QCOMPARE(selectedText, QStringLiteral("48"));
    selectionkey::deliverKey(quickWindow(), copy->key(), copy->keyboardModifiers());
    QCOMPARE(QGuiApplication::clipboard()->text(), selectedText);
    QCOMPARE(m_counts.copy, promptCopiesBefore);
    selectionkey::deliverKey(quickWindow(), remove->key(), remove->keyboardModifiers());
    QVERIFY(prompt && prompt->property("text").toString().isEmpty());
    selectionkey::deliverKey(quickWindow(), paste->key(), paste->keyboardModifiers());
    QVERIFY(prompt && prompt->property("text").toString() == selectedText);
    QCOMPARE(document.smf().write(), before);
    QVERIFY(selectionUnchanged());
    selectionkey::deliverKey(quickWindow(), Qt::Key_Escape);
    QTRY_VERIFY(!canvas->valuePromptVisible());
    QCOMPARE(document.smf().write(), before);
    QVERIFY(selectionUnchanged());
    QVERIFY(focusParameter(7));
    selectionkey::deliverKey(quickWindow(), copy->key(), copy->keyboardModifiers());
    QCOMPARE(m_counts.copy, copiesBefore + 1);
    QVERIFY(songview::clipboardHasClipMime());
    QCOMPARE(document.smf().write(), before);
    QVERIFY(selectionUnchanged());
    selectionkey::deliverKey(quickWindow(), remove->key(), remove->keyboardModifiers());
    QVERIFY(!document.findLanePoint(kTrack, kController, tick, nullptr));
    QVERIFY(!document.findLanePoint(kTrack, kSecondController, tick, nullptr));
    QVERIFY(document.findLanePoint(kTrack, 7, tick, nullptr));
    QVERIFY(notePairUnchanged(document, *pair));
    QVERIFY(label && label->hasActiveFocus());

    selectionkey::deliverKey(quickWindow(), selectAll->key(), selectAll->keyboardModifiers());
    QVERIFY(view.selectionModel().isNoteSelected(pair->ids[0]));
    QVERIFY(view.selectionModel().isNoteSelected(pair->ids[1]));
    QVERIFY(!view.selectionModel().timeSelection().active());
    view.selectionModel().clearBothSelections();
    view.commitEditCursor(pasteTick);
    selectionkey::deliverKey(quickWindow(), paste->key(), paste->keyboardModifiers());
    DocLanePoint point;
    QVERIFY(document.findLanePoint(kTrack, kController, pasteTick, &point));
    QCOMPARE(point.value, 32);
    QVERIFY(document.findLanePoint(kTrack, kSecondController, pasteTick, &point));
    QCOMPARE(point.value, 96);
    QVERIFY(!document.findLanePoint(kTrack, 7, pasteTick, nullptr));
    QVERIFY(notePairUnchanged(document, *pair));
    QCOMPARE(canvas->parameterRow(canvas->activeParameter()), std::optional{volume});

    view.selectionModel().setNoteSelection({pair->ids[0], pair->ids[1]});
    QVERIFY(label && label->hasActiveFocus());
    const uint64_t gridStep =
        view.grid().snapTickUp(double(pair->notes[0].tick) + 1.0) - pair->notes[0].tick;
    selectionkey::deliverKey(quickWindow(), Qt::Key_Right);
    selectionkey::deliverKey(quickWindow(), Qt::Key_Up);
    for (size_t index = 0; index < pair->ids.size(); ++index) {
        const auto moved = selectionkey::noteById(document, pair->ids[index]);
        QVERIFY(moved.has_value());
        QCOMPARE(moved->tick, pair->notes[index].tick + gridStep);
        QCOMPARE(moved->key, uint8_t(pair->notes[index].key + 1));
    }
    QCOMPARE(canvas->parameterRow(canvas->activeParameter()), std::optional{volume});
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
