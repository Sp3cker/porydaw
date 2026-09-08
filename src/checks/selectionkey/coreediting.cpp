#include "checks/selectionkey/tst_selectionkeycore.h"

#include "checks/clipcheck_support.h"
#include "checks/support/eventsynth.h"

#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"

#include <QCoreApplication>
#include <QEvent>
#include <QKeyEvent>
#include <QQuickItem>
#include <QQuickWindow>
#include <QtTest>

#include <optional>
#include <utility>
#include <vector>

using selectionkey::clickTimelineInput;
using selectionkey::coreLaneRange;
using selectionkey::coreTrackRange;
using selectionkey::deliverKey;
using selectionkey::drawerPageForBand;
using selectionkey::firstBinding;
using selectionkey::focusTimelineInput;
using selectionkey::kController;
using selectionkey::kFirstNoteTick;
using selectionkey::kFirstPointTick;
using selectionkey::kInsidePointTick;
using selectionkey::kOutsidePointTick;
using selectionkey::kPasteTick;
using selectionkey::kSecondPointTick;
using selectionkey::kTrack;
using selectionkey::moveMouseToTimelineInput;
using selectionkey::noteExists;

namespace {

// Direct QEvent-level delivery for the audition lifecycle, which needs
// autoRepeat control that QTest::keyClick does not expose.
bool deliverKeyEvent(QQuickWindow *window, QEvent::Type type, int key, bool autoRepeat)
{
    if (!window)
        return false;
    checks::events::sendKey(*window, type, key, Qt::NoModifier, QString{}, autoRepeat, 1);
    selectionkey::settle();
    return true;
}

// QTest keyClick does not expose repeat state. This sends the same key event
// through the live Quick window while retaining acceptance as the evidence
// that a terminal grid no-op did not leak into another owner.
bool deliverGridKeyEvent(QQuickWindow *window, QKeyCombination binding, bool autoRepeat)
{
    if (!window)
        return false;
    QKeyEvent event(QEvent::KeyPress, binding.key(), binding.keyboardModifiers(), QString{},
                    autoRepeat, 1);
    event.setAccepted(false);
    QCoreApplication::sendEvent(window, &event);
    selectionkey::settle();
    return event.isAccepted();
}

bool gridHasState(const SongView &view, songview::GridSelection selection, songview::GridFeel feel,
                  uint64_t ticks)
{
    return view.gridSelection() == selection && view.grid().feel() == feel &&
           view.grid().snapTicksAt(0) == ticks;
}

enum class PencilScenario {
    NotePrecedence,
    TimePrecedence,
    HoverDelete,
    HoverMiss,
};

} // namespace

void SelectionKeyCoreTest::drawerTransposeAuditionReleasesOnPhysicalKeyUp()
{
    m_fixture = createFixture(EditorDrawerPage::Automations);
    QVERIFY2(m_fixture, qPrintable(QStringLiteral("could not create drawer-audition fixture: %1")
                                       .arg(m_lastFixtureError)));
    QQuickWindow *const quick = m_fixture->window();
    SongView &songView = m_fixture->view();
    QVERIFY2(focusTimelineInput(quick, m_fixture->input("timelineAutomationInput")),
             "could not focus the automation drawer for transpose audition");
    songView.selectionModel().setNoteSelection({m_fixture->notes()[0]});

    std::vector<std::pair<int, int>> auditions;
    const QMetaObject::Connection connection = QObject::connect(
        &songView, &SongView::auditionNote, &songView,
        [&auditions](int, int key, int velocity) { auditions.emplace_back(key, velocity); });

    QVERIFY2(deliverKeyEvent(quick, QEvent::KeyPress, Qt::Key_Up, false),
             "drawer transpose key-down did not reach the Quick window");
    const std::size_t started = auditions.size();
    QVERIFY2(started == 1 && auditions.back().second > 0,
             "drawer transpose key-down did not start a live audition");

    QVERIFY2(deliverKeyEvent(quick, QEvent::KeyRelease, Qt::Key_Up, true),
             "drawer autorepeat key-up did not reach the Quick window");
    QVERIFY2(auditions.size() == started,
             "drawer autorepeat key-up prematurely ended the live audition");

    QVERIFY2(deliverKeyEvent(quick, QEvent::KeyRelease, Qt::Key_Up, false),
             "drawer physical key-up did not reach the Quick window");
    // The shared release path ends the audition with the velocity-0
    // release of the engine's single preview slot; that emission repeats
    // the slot, not the sounding key (AudioEngine::previewNote replaces
    // whatever preview sounded).
    QVERIFY2(auditions.size() == started + 1 && auditions.back().second == 0,
             "drawer physical key-up did not end the transposed note audition");
    QObject::disconnect(connection);
}

void SelectionKeyCoreTest::automationRangeAndReboundDelete()
{
    m_fixture = createFixture(EditorDrawerPage::Automations);
    QVERIFY2(m_fixture, qPrintable(QStringLiteral("could not create automation-range fixture: %1")
                                       .arg(m_lastFixtureError)));
    QQuickWindow *const quick = m_fixture->window();
    songview::TimelineInputItem *const automation = m_fixture->input("timelineAutomationInput");
    const auto points =
        m_fixture->laneWindowPoints({{kFirstPointTick, 80}, {kOutsidePointTick, 80}});
    QVERIFY2(quick && automation && points, "automation Quick range surface is unavailable");

    QVERIFY2(m_fixture->focusBand(songview::TimelineBand::Automation),
             "could not stage automation focus for range delivery");
    m_fixture->view().selectionModel().setNoteSelection({m_fixture->notes()[0]});
    selectionkey::settle();
    QVERIFY2(moveMouseToTimelineInput(quick, automation, points->at(0)),
             "automation range start did not reach the Quick input item");
    stageMousePress(Qt::RightButton, points->at(0));
    stageMouseMove(points->at(1));
    stageMouseRelease(Qt::RightButton, points->at(1));
    selectionkey::settle();

    const auto &selection = m_fixture->view().selectionModel().timeSelection();
    // Hoisted: the lane pair's commas would split the QVERIFY2 macro args.
    const bool rangeReady =
        selection.active() && selection.startTick == kFirstPointTick &&
        selection.endTick == kOutsidePointTick &&
        selection.scope == songview::EditorSelectionModel::TimeSelection::Lanes &&
        selection.lanes == std::vector<std::pair<int, uint8_t>>{{kTrack, kController}} &&
        m_fixture->view().selectionModel().noteSelection().empty();
    QVERIFY2(rangeReady, "actual automation range did not replace note selection with lane scope");

    m_keymap->registry().setBinding(QStringLiteral("roll.delete"),
                                    QKeySequence(QStringLiteral("Alt+Backspace")));
    QVERIFY2(deliverKey(quick, Qt::Key_Backspace, Qt::AltModifier),
             "rebound Delete did not reach the Quick automation surface");
    QVERIFY2(
        !m_fixture->document().findLanePoint(kTrack, kController, kFirstPointTick, nullptr) &&
            !m_fixture->document().findLanePoint(kTrack, kController, kInsidePointTick, nullptr) &&
            !m_fixture->document().findLanePoint(kTrack, kController, kSecondPointTick, nullptr) &&
            m_fixture->document().findLanePoint(kTrack, kController, kOutsidePointTick, nullptr),
        "automation range Delete did not affect only its selected points");
}

void SelectionKeyCoreTest::pencilHoverDeletePrecedence_data()
{
    QTest::addColumn<int>("scenario");
    QTest::newRow("note selection wins over hover") << int(PencilScenario::NotePrecedence);
    QTest::newRow("track time selection wins over hover") << int(PencilScenario::TimePrecedence);
    QTest::newRow("eligible hover delete") << int(PencilScenario::HoverDelete);
    QTest::newRow("hover miss keeps document") << int(PencilScenario::HoverMiss);
}

void SelectionKeyCoreTest::pencilHoverDeletePrecedence()
{
    QFETCH(int, scenario);
    const auto kind = PencilScenario(scenario);
    const bool miss = kind == PencilScenario::HoverMiss;

    // The shipped roll.delete defaults ("Delete;Backspace") drive the
    // precedence matrix; automationRangeAndReboundDelete is the explicit
    // rebound-binding coverage, and init() resets overrides between cases.
    const auto deleteKey = firstBinding(QStringLiteral("roll.delete"));
    QVERIFY2(deleteKey.has_value(),
             "roll.delete has no single-key default binding for the pencil-hover surface");
    m_fixture = createFixture(EditorDrawerPage::Automations);
    QVERIFY2(m_fixture, qPrintable(QStringLiteral("could not create the pencil-hover fixture: %1")
                                       .arg(m_lastFixtureError)));
    QQuickWindow *const quick = m_fixture->window();
    songview::TimelineInputItem *const automation = m_fixture->input("timelineAutomationInput");
    m_fixture->view().editorDrawer()->automationPage()->canvas()->setPencilMode(true);
    QVERIFY2(m_fixture->focusBand(songview::TimelineBand::Automation),
             "could not stage automation focus for pencil-hover delete");
    switch (kind) {
    case PencilScenario::NotePrecedence:
        m_fixture->view().selectionModel().setNoteSelection({m_fixture->notes()[0]});
        break;
    case PencilScenario::TimePrecedence:
        m_fixture->view().selectionModel().setTimeSelection(
            coreTrackRange(kFirstNoteTick, kFirstNoteTick + 24));
        break;
    case PencilScenario::HoverDelete:
    case PencilScenario::HoverMiss:
        break;
    }
    // Mode, focus, and selection publications land before the hover target is
    // projected, and the hover move is the final staging step so Delete sees
    // exactly the hover it intends to exercise.
    selectionkey::settle();
    const auto point =
        m_fixture->laneWindowPoint(miss ? kOutsidePointTick + 24 : kSecondPointTick, miss ? 1 : 64);
    QVERIFY2(quick && automation && point, "automation hover fixture is unavailable");
    QVERIFY2(moveMouseToTimelineInput(quick, automation, *point),
             "automation hover did not reach the Quick input item");
    const QByteArray before = m_fixture->document().smf().write();
    QVERIFY2(deliverKey(quick, deleteKey->key(), deleteKey->keyboardModifiers()),
             "default Delete did not reach the pencil-hover surface");

    const bool pointAlive =
        m_fixture->document().findLanePoint(kTrack, kController, kSecondPointTick, nullptr);
    switch (kind) {
    case PencilScenario::NotePrecedence:
        QVERIFY2(!noteExists(m_fixture->document(), m_fixture->notes()[0]) && pointAlive,
                 "selected notes did not win over pencil hover Delete");
        break;
    case PencilScenario::TimePrecedence:
        QVERIFY2(!noteExists(m_fixture->document(), m_fixture->notes()[0]) && pointAlive,
                 "track time selection did not win over pencil hover Delete");
        break;
    case PencilScenario::HoverDelete:
        QVERIFY2(!pointAlive, "eligible pencil hover Delete did not remove the hovered point");
        break;
    case PencilScenario::HoverMiss:
        QVERIFY2(m_fixture->document().smf().write() == before,
                 "pencil hover miss Delete changed the document");
        break;
    }
}

void SelectionKeyCoreTest::laneScopedVerticalArrowLeavesDocumentUntouched()
{
    m_fixture = createFixture(EditorDrawerPage::Automations);
    QVERIFY2(
        m_fixture,
        qPrintable(
            QStringLiteral("could not create lane-nudge fixture: %1").arg(m_lastFixtureError)));
    QVERIFY2(m_fixture->focusBand(songview::TimelineBand::Automation),
             "could not focus the automation Quick band");
    m_fixture->view().selectionModel().setTimeSelection(
        coreLaneRange(kSecondPointTick, kOutsidePointTick));
    const QByteArray beforeVertical = m_fixture->document().smf().write();
    QVERIFY2(deliverKey(m_fixture->window(), Qt::Key_Up),
             "Quick window did not accept the lane-scoped vertical arrow");
    QVERIFY2(m_fixture->document().smf().write() == beforeVertical,
             "lane-scoped vertical arrow mutated automation or hidden notes");
}

void SelectionKeyCoreTest::laneScopedHorizontalArrowNudgesPointsAndInterval()
{
    m_fixture = createFixture(EditorDrawerPage::Automations);
    QVERIFY2(
        m_fixture,
        qPrintable(
            QStringLiteral("could not create lane-nudge fixture: %1").arg(m_lastFixtureError)));
    QVERIFY2(m_fixture->focusBand(songview::TimelineBand::Automation),
             "could not focus the automation Quick band");
    m_fixture->view().selectionModel().setTimeSelection(
        coreLaneRange(kSecondPointTick, kOutsidePointTick));

    const uint64_t destination =
        m_fixture->view().grid().snapTickUp(double(kSecondPointTick) + 1.0);
    QVERIFY2(deliverKey(m_fixture->window(), Qt::Key_Right),
             "Quick window did not accept the lane-scoped horizontal arrow");
    const auto &moved = m_fixture->view().selectionModel().timeSelection();
    QVERIFY2(
        m_fixture->document().findLanePoint(kTrack, kController, destination, nullptr) &&
            !m_fixture->document().findLanePoint(kTrack, kController, kSecondPointTick, nullptr) &&
            moved.startTick == destination &&
            moved.endTick == kOutsidePointTick + destination - kSecondPointTick,
        "lane-scoped horizontal arrow did not nudge points and the selected interval");
}

void SelectionKeyCoreTest::keyboardClipboardParity_data()
{
    QTest::addColumn<int>("destinationBand");
    QTest::newRow("roll") << int(songview::TimelineBand::Roll);
    QTest::newRow("automation drawer") << int(songview::TimelineBand::Automation);
}

void SelectionKeyCoreTest::keyboardClipboardParity()
{
    QFETCH(int, destinationBand);
    const auto band = songview::TimelineBand(destinationBand);

    // roll.copy writes the process-global QClipboard; the guard restores it
    // even when the row aborts, so clipboard state cannot leak across rows.
    const clipcheck_support::ClipboardStateGuard clipboardGuard;

    const auto copy = firstBinding(QStringLiteral("roll.copy"));
    const auto paste = firstBinding(QStringLiteral("roll.paste"));
    QVERIFY2(copy.has_value() && paste.has_value(),
             "keyboard clipboard commands have no single-key binding");

    m_fixture = createFixture(drawerPageForBand(band));
    QVERIFY2(
        m_fixture,
        qPrintable(
            QStringLiteral("could not create the clipboard fixture: %1").arg(m_lastFixtureError)));
    SongView &songView = m_fixture->view();
    QQuickWindow *const quick = m_fixture->window();
    songView.selectionModel().setNoteSelection({m_fixture->notes()[0]});
    QVERIFY2(m_fixture->focusBand(songview::TimelineBand::Roll),
             "could not focus the roll for keyboard Copy");
    QVERIFY2(deliverKey(quick, copy->key(), copy->keyboardModifiers()),
             "Quick window did not accept the keyboard Copy binding");
    songView.selectionModel().clearNoteSelection();
    songView.commitEditCursor(kPasteTick);
    QVERIFY2(m_fixture->focusBand(band), "could not focus paste destination band");
    QVERIFY2(deliverKey(quick, paste->key(), paste->keyboardModifiers()),
             "Quick window did not accept the keyboard Paste binding");
    QVERIFY2(noteExists(m_fixture->document(), kTrack, kPasteTick, 60),
             "keyboard Paste did not land the roll-copied note clip at the committed cursor");
}

void SelectionKeyCoreTest::gridCommandsFromBandAndRootFallback()
{
    const auto triplet = firstBinding(QStringLiteral("roll.grid_triplet"));
    QVERIFY2(triplet.has_value(), "the triplet grid command needs a single-key binding");

    m_fixture = createFixture(std::nullopt);
    QVERIFY2(
        m_fixture,
        qPrintable(
            QStringLiteral("could not create grid-input fixture: %1").arg(m_lastFixtureError)));
    SongView &view = m_fixture->view();
    QQuickWindow *const quick = m_fixture->window();
    QQuickItem *const root = m_fixture->root();
    songview::TimelineInputItem *const roll = m_fixture->input("timelineRollInput");
    QVERIFY2(quick && root && roll, "the roll input or TimelineCanvas root is unavailable");

    view.setGridFeel(songview::GridFeel::Straight);
    view.setGridSelection(songview::GridSelection::musical(16));
    QVERIFY2(
        gridHasState(view, songview::GridSelection::musical(16), songview::GridFeel::Straight, 6),
        "the 24-PPQN core fixture did not stage the independent six-tick grid");
    QVERIFY2(focusTimelineInput(quick, roll), "could not focus the live roll input");
    QVERIFY2(deliverKey(quick, Qt::Key_1, Qt::ControlModifier),
             "literal Ctrl/Cmd+1 did not reach the live roll input");
    QVERIFY2(
        gridHasState(view, songview::GridSelection::musical(8), songview::GridFeel::Straight, 12),
        "one band-delivered Ctrl/Cmd+1 did not widen the grid exactly from 6 to 12 ticks");

    // The root owns unclaimed chrome keys. Give it focus explicitly, then
    // deliver literal Ctrl/Cmd+2 through the same shown Quick window; this
    // must be one semantic narrow, never a band-plus-root double delivery.
    root->forceActiveFocus(Qt::OtherFocusReason);
    selectionkey::settle();
    QVERIFY2(root->hasActiveFocus(), "TimelineCanvas root did not acquire active focus");
    QVERIFY2(deliverKey(quick, Qt::Key_2, Qt::ControlModifier),
             "literal Ctrl/Cmd+2 did not reach TimelineCanvas root fallback");
    QVERIFY2(
        gridHasState(view, songview::GridSelection::musical(16), songview::GridFeel::Straight, 6),
        "one root-fallback Ctrl/Cmd+2 did not narrow the grid exactly from 12 to 6 ticks");
    QVERIFY2(deliverKey(quick, triplet->key(), triplet->keyboardModifiers()),
             "the triplet-grid chord did not reach TimelineCanvas root fallback");
    QVERIFY2(
        gridHasState(view, songview::GridSelection::musical(16), songview::GridFeel::Triplet, 4),
        "root-fallback triplet chord did not toggle the live grid exactly once");
}

void SelectionKeyCoreTest::gridCommandRepeatAndBoundsAreConsumed()
{
    const auto narrow = firstBinding(QStringLiteral("roll.grid_narrow"));
    const auto widen = firstBinding(QStringLiteral("roll.grid_widen"));
    const auto triplet = firstBinding(QStringLiteral("roll.grid_triplet"));
    QVERIFY2(narrow.has_value() && widen.has_value() && triplet.has_value(),
             "the three grid commands need single-key bindings");

    m_fixture = createFixture(std::nullopt);
    QVERIFY2(
        m_fixture,
        qPrintable(
            QStringLiteral("could not create grid-repeat fixture: %1").arg(m_lastFixtureError)));
    SongView &view = m_fixture->view();
    QQuickWindow *const quick = m_fixture->window();
    songview::TimelineInputItem *const roll = m_fixture->input("timelineRollInput");
    QVERIFY2(focusTimelineInput(quick, roll), "could not focus the roll before grid repeats");

    view.setGridFeel(songview::GridFeel::Straight);
    view.setGridSelection(songview::GridSelection::musical(16));
    QVERIFY2(deliverKey(quick, narrow->key(), narrow->keyboardModifiers()),
             "initial narrow-grid key did not reach the roll");
    QVERIFY2(
        deliverGridKeyEvent(quick, *narrow, true) &&
            gridHasState(view, songview::GridSelection::clock(), songview::GridFeel::Straight, 1),
        "narrow-grid autorepeat was not a consumed 3-to-Clock step");

    view.setGridSelection(songview::GridSelection::musical(32));
    QVERIFY2(deliverKey(quick, widen->key(), widen->keyboardModifiers()),
             "initial widen-grid key did not reach the roll");
    QVERIFY2(deliverGridKeyEvent(quick, *widen, true) &&
                 gridHasState(view, songview::GridSelection::musical(8),
                              songview::GridFeel::Straight, 12),
             "widen-grid autorepeat was not a consumed 6-to-12 step");

    view.setGridSelection(songview::GridSelection::musical(16));
    QVERIFY2(deliverKey(quick, triplet->key(), triplet->keyboardModifiers()),
             "initial triplet-grid key did not reach the roll");
    QVERIFY2(deliverGridKeyEvent(quick, *triplet, true) &&
                 gridHasState(view, songview::GridSelection::musical(16),
                              songview::GridFeel::Triplet, 4),
             "triplet-grid autorepeat changed feel or leaked past its consumed key path");

    view.setGridFeel(songview::GridFeel::Straight);
    view.setGridSelection(songview::GridSelection::clock());
    QVERIFY2(
        deliverGridKeyEvent(quick, *narrow, false) &&
            gridHasState(view, songview::GridSelection::clock(), songview::GridFeel::Straight, 1),
        "bound narrow-grid no-op was not consumed at Clock");

    view.setGridSelection(songview::GridSelection::musical(4));
    QVERIFY2(deliverGridKeyEvent(quick, *widen, false) &&
                 gridHasState(view, songview::GridSelection::musical(4),
                              songview::GridFeel::Straight, 24),
             "bound widen-grid no-op was not consumed at the coarse endpoint");
}

void SelectionKeyCoreTest::reboundGridCommandDeliversAndRestoresDefault()
{
    const auto originalNarrow = firstBinding(QStringLiteral("roll.grid_narrow"));
    QVERIFY2(originalNarrow.has_value(), "Narrow Grid has no single-key default binding");

    m_fixture = createFixture(std::nullopt);
    QVERIFY2(
        m_fixture,
        qPrintable(
            QStringLiteral("could not create grid-rebind fixture: %1").arg(m_lastFixtureError)));
    SongView &view = m_fixture->view();
    QQuickWindow *const quick = m_fixture->window();
    songview::TimelineInputItem *const roll = m_fixture->input("timelineRollInput");
    QVERIFY2(focusTimelineInput(quick, roll), "could not focus the roll before rebinding");

    const QKeySequence reboundSequence(QStringLiteral("Alt+9"));
    QVERIFY2(m_keymap->registry()
                 .conflicts(QStringLiteral("roll.grid_narrow"), keymap::Context::Timeline,
                            reboundSequence)
                 .isEmpty(),
             "Alt+9 is not an unused Timeline chord for the rebound delivery proof");
    m_keymap->registry().setBinding(QStringLiteral("roll.grid_narrow"), reboundSequence);
    const auto reboundNarrow = firstBinding(QStringLiteral("roll.grid_narrow"));
    QVERIFY2(reboundNarrow.has_value() && *reboundNarrow == reboundSequence[0],
             "Narrow Grid did not install the unused Alt+9 binding");

    view.setGridFeel(songview::GridFeel::Straight);
    view.setGridSelection(songview::GridSelection::musical(16));
    QVERIFY2(deliverKey(quick, originalNarrow->key(), originalNarrow->keyboardModifiers()) &&
                 gridHasState(view, songview::GridSelection::musical(16),
                              songview::GridFeel::Straight, 6),
             "the replaced Narrow Grid chord still delivered after rebinding");
    QVERIFY2(deliverKey(quick, reboundNarrow->key(), reboundNarrow->keyboardModifiers()) &&
                 gridHasState(view, songview::GridSelection::musical(32),
                              songview::GridFeel::Straight, 3),
             "the rebound Narrow Grid chord did not deliver through the roll");

    m_keymap->registry().resetBinding(QStringLiteral("roll.grid_narrow"));
    const auto restoredNarrow = firstBinding(QStringLiteral("roll.grid_narrow"));
    QVERIFY2(restoredNarrow.has_value() && *restoredNarrow == *originalNarrow,
             "resetBinding did not restore Narrow Grid's original chord");
    view.setGridSelection(songview::GridSelection::musical(16));
    QVERIFY2(deliverKey(quick, restoredNarrow->key(), restoredNarrow->keyboardModifiers()) &&
                 gridHasState(view, songview::GridSelection::musical(32),
                              songview::GridFeel::Straight, 3),
             "the restored Narrow Grid chord did not deliver through the roll");
}

void SelectionKeyCoreTest::gridCommandIgnoredByRenameTextInput()
{
    const auto narrow = firstBinding(QStringLiteral("roll.grid_narrow"));
    QVERIFY2(narrow.has_value(), "Narrow Grid has no single-key binding");

    m_fixture = createFixture(std::nullopt);
    QVERIFY2(
        m_fixture,
        qPrintable(
            QStringLiteral("could not create rename-grid fixture: %1").arg(m_lastFixtureError)));
    SongView &view = m_fixture->view();
    QQuickWindow *const quick = m_fixture->window();
    QQuickItem *const root = m_fixture->root();
    QVERIFY2(quick && root, "the Quick rename surface is unavailable");
    QVERIFY2(view.focusTimelineBand(songview::TimelineBand::Roll, Qt::OtherFocusReason),
             "could not focus the Quick host before requesting track rename");

    // The core rig is the focused offscreen Qt Quick probe. SongView owns the
    // normal focus bridge; its QML delegate creates and focuses the TextInput.
    view.renameTrack(kTrack);
    selectionkey::settle();
    const QString renameObjectName = QStringLiteral("timelineTrackHeaderRename");
    QQuickItem *rename = quick->activeFocusItem();
    const auto isLiveRename = [quick, &renameObjectName](const QQuickItem *item) {
        return item && item->objectName() == renameObjectName && item->isVisible() &&
               item->window() == quick;
    };
    if (!isLiveRename(rename)) {
        const QList<QQuickItem *> candidates = root->findChildren<QQuickItem *>(renameObjectName);
        if (candidates.size() == 1 && isLiveRename(candidates.front())) {
            candidates.front()->forceActiveFocus(Qt::OtherFocusReason);
            selectionkey::settle();
            rename = quick->activeFocusItem();
        }
    }
    QVERIFY2(isLiveRename(rename), "the QML track-rename TextInput did not acquire focus");

    view.setGridFeel(songview::GridFeel::Straight);
    view.setGridSelection(songview::GridSelection::musical(16));
    QVERIFY2(deliverGridKeyEvent(quick, *narrow, false),
             "the modified Narrow Grid chord was not accepted while rename owned focus");
    QVERIFY2(view.gridSelection() == songview::GridSelection::musical(16),
             "the focused rename TextInput changed the grid selection through root fallback");
    QVERIFY2(view.grid().feel() == songview::GridFeel::Straight,
             "the focused rename TextInput changed the grid feel through root fallback");
    QCOMPARE(view.grid().snapTicksAt(0), uint64_t{6});
    QTest::keyClick(quick, Qt::Key_Escape);
    selectionkey::settle();
}

void SelectionKeyCoreTest::selectAllFromEmptySelection()
{
    const auto shortcut = firstBinding(QStringLiteral("roll.select_all"));
    QVERIFY2(shortcut.has_value(), "Select All Notes has no single-key binding");

    m_fixture = createFixture(EditorDrawerPage::Velocity);
    QVERIFY2(
        m_fixture,
        qPrintable(
            QStringLiteral("could not create Select All fixture: %1").arg(m_lastFixtureError)));
    SongView &songView = m_fixture->view();
    QQuickWindow *const quick = m_fixture->window();
    songView.selectionModel().clearBothSelections();
    selectionkey::settle();
    QVERIFY2(focusTimelineInput(quick, m_fixture->input("timelineVelocityInput")),
             "could not focus the velocity band before Select All");
    QVERIFY2(m_fixture->focusBand(songview::TimelineBand::Velocity),
             "could not stage velocity focus before Select All");
    QVERIFY2(deliverKey(quick, shortcut->key(), shortcut->keyboardModifiers()),
             "Select All key did not reach the velocity band");
    // >= is deliberate: the project fixture carries pre-existing primary-track notes.
    QVERIFY2(songView.selectionModel().noteSelection().size() >= m_fixture->notes().size() &&
                 !songView.selectionModel().timeSelection().active(),
             "Select All Notes from empty selection did not select primary-track notes");
}

void SelectionKeyCoreTest::selectAllReplacesTimeSelectionAfterRulerClick()
{
    const auto shortcut = firstBinding(QStringLiteral("roll.select_all"));
    QVERIFY2(shortcut.has_value(), "Select All Notes has no single-key binding");

    m_fixture = createFixture(EditorDrawerPage::Velocity);
    QVERIFY2(
        m_fixture,
        qPrintable(
            QStringLiteral("could not create Select All fixture: %1").arg(m_lastFixtureError)));
    SongView &songView = m_fixture->view();
    QQuickWindow *const quick = m_fixture->window();

    songView.selectionModel().setTimeSelection(coreTrackRange(kFirstNoteTick, kFirstNoteTick + 48));
    selectionkey::settle();
    m_fixture->configureDrawerSurface(std::nullopt);
    songview::TimelineInputItem *const ruler = m_fixture->input("timelineRulerInput");
    const auto rulerPoint = ruler ? m_fixture->plainRulerPoint(ruler) : std::optional<QPoint>{};
    QVERIFY2(ruler && rulerPoint && clickTimelineInput(quick, ruler, *rulerPoint),
             "could not deliver the ruler click before Select All");
    QVERIFY2(m_fixture->focusBand(songview::TimelineBand::Ruler),
             "could not stage ruler focus before Select All");
    QVERIFY2(deliverKey(quick, shortcut->key(), shortcut->keyboardModifiers()),
             "Select All key did not reach the ruler band");
    // >= is deliberate: the project fixture carries pre-existing primary-track notes.
    QVERIFY2(songView.selectionModel().noteSelection().size() >= m_fixture->notes().size() &&
                 !songView.selectionModel().timeSelection().active(),
             "Select All Notes did not replace a time selection from incidental chrome");
}
