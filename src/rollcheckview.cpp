#include "rollcheckfixture.hpp"

#include <QAction>
#include <QDialog>
#include <QLabel>
#include <QLineEdit>
#include <QTimer>
#include <QToolButton>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>
#include <vector>

#include "checkinput.hpp"

namespace {

struct TrackNotePosition {
  uint64_t tick = 0;
  uint8_t key = 0;
};

} // namespace

void runRollStaticViewScenario(RollCheckFixture &fixture) {
  constexpr auto expectedUndoDelta = 0;
  const auto scenarioStart = fixture.undoCheckpoint();
  auto &document = fixture.document();
  auto &view = fixture.view();
  auto &roll = fixture.roll();
  const auto track = fixture.track();
  auto *gridLabel = view.findChild<QLabel *>(QStringLiteral("gridLabel"));
  if (!gridLabel || gridLabel->text() != QStringLiteral("Grid"))
    fixture.fail("grid control is not a static Grid label");
  for (auto *button : view.findChildren<QToolButton *>()) {
    if (button->text() == QStringLiteral("Grid"))
      fixture.fail("Grid is still an interactive tool button");
  }
  const auto zoomBefore = view.pxPerTick();
  const auto scrollBefore = -view.contentX(0.0);
  check_input::sendKey(roll, Qt::Key_Equal, Qt::NoModifier);
  fixture.processEvents();
  if (view.pxPerTick() == zoomBefore)
    fixture.fail("Equals shortcut did not zoom in");
  check_input::sendKey(roll, Qt::Key_Minus, Qt::NoModifier);
  fixture.processEvents();
  if (std::abs(view.pxPerTick() - zoomBefore) > 0.000001)
    fixture.fail("Minus shortcut did not zoom back out");
  const auto zoomAnchor = std::max(0, roll.width() - songview::kKeyboardW) / 2;
  const auto fullSongVisible = [&fixture, &view, zoomAnchor] {
    return view.contentX(0.0) == 0 &&
           view.contentX(double(fixture.timeline().lengthTicks)) <=
               2 * zoomAnchor + 1;
  };
  view.zoomAroundContentX(4.0, zoomAnchor);
  const auto selectionZoomBefore = view.pxPerTick();
  auto zoomSelection = SongView::TimeSelection{};
  zoomSelection.endTick = uint64_t(fixture.timeline().ticksPerBeat) * 4;
  view.setTimeSelection(zoomSelection);
  check_input::sendKey(roll, Qt::Key_Z, Qt::NoModifier);
  fixture.processEvents();
  if (view.pxPerTick() == selectionZoomBefore)
    fixture.fail("Z shortcut did not zoom to the time selection");
  const auto selectionZoom = view.pxPerTick();
  check_input::sendKey(roll, Qt::Key_X, Qt::NoModifier);
  fixture.processEvents();
  if (view.pxPerTick() == selectionZoom || !fullSongVisible())
    fixture.fail("X shortcut did not zoom out to the full song");
  view.clearTimeSelection();
  view.zoomAroundContentX(zoomBefore / view.pxPerTick(), zoomAnchor);
  const auto gridSize = view.gridMinDenom();
  check_input::sendKey(roll, Qt::Key_1, Qt::ControlModifier);
  if (view.gridMinDenom() != gridSize * 2)
    fixture.fail("Ctrl+1 did not make the grid finer");
  check_input::sendKey(roll, Qt::Key_2, Qt::ControlModifier);
  if (view.gridMinDenom() != gridSize)
    fixture.fail("Ctrl+2 did not make the grid coarser");
  const auto gridFeel = view.gridFeel();
  check_input::sendKey(roll, Qt::Key_3, Qt::ControlModifier);
  if (view.gridFeel() == gridFeel)
    fixture.fail("Ctrl+3 did not toggle the triplet grid");
  check_input::sendKey(roll, Qt::Key_3, Qt::ControlModifier);
  if (view.gridFeel() != gridFeel)
    fixture.fail("Ctrl+3 did not restore the grid feel");
  const auto snapToGrid = view.snapToGrid();
  check_input::sendKey(roll, Qt::Key_4, Qt::ControlModifier);
  if (view.snapToGrid() == snapToGrid)
    fixture.fail("Ctrl+4 did not toggle grid snapping");
  check_input::sendKey(roll, Qt::Key_4, Qt::ControlModifier);
  if (view.snapToGrid() != snapToGrid)
    fixture.fail("Ctrl+4 did not restore grid snapping");
  const auto fixedGrid = view.gridMinDenom();
  check_input::sendKey(roll, Qt::Key_5, Qt::ControlModifier);
  if (view.gridMinDenom() != 0)
    fixture.fail("Ctrl+5 did not enable the adaptive grid");
  check_input::sendKey(roll, Qt::Key_5, Qt::ControlModifier);
  if (view.gridMinDenom() != fixedGrid)
    fixture.fail("Ctrl+5 did not restore the fixed grid");
  view.scrollByPx(scrollBefore + view.contentX(0.0));
  const auto verifyShortcut = [&fixture, &view,
                               &roll](live_shortcuts::Command command, int key,
                                      Qt::KeyboardModifiers modifiers) {
    auto *action = check_input::findAction(roll, command);
    const auto label = live_shortcuts::translatedLabel(command);
    if (!action) {
      const auto message =
          QStringLiteral("%1 action is not attached").arg(label).toUtf8();
      fixture.fail(message.constData());
      return;
    }
    auto invoked = false;
    const auto connection = QObject::connect(action, &QAction::triggered, &view,
                                             [&invoked] { invoked = true; });
    check_input::sendKey(roll, key, modifiers);
    QObject::disconnect(connection);
    if (!invoked) {
      const auto message =
          QStringLiteral("%1 shortcut did not invoke its action")
              .arg(label)
              .toUtf8();
      fixture.fail(message.constData());
    }
  };
  const auto shortcutNotes = document.notesForTrack(track);
  const auto boundedNote =
      std::find_if(shortcutNotes.begin(), shortcutNotes.end(),
                   [](const auto &note) { return !note.unterminated(); });
  if (boundedNote == shortcutNotes.end()) {
    fixture.fail("no bounded note available for shortcut dispatch checks");
  } else {
    const auto sourceTick = boundedNote->tick;
    const auto sourceDuration = boundedNote->duration;
    const auto sourceKey = boundedNote->key;
    const auto source = SongView::NoteId{uint32_t(sourceTick), sourceKey};
    const auto selectSource = [&view, source] { view.setSelection({source}); };
    selectSource();
    const auto noteZoomBefore = view.pxPerTick();
    check_input::sendKey(roll, Qt::Key_Z, Qt::NoModifier);
    if (view.pxPerTick() == noteZoomBefore ||
        view.contentX(double(sourceTick)) < 0 ||
        view.contentX(double(sourceTick + sourceDuration)) >
            2 * zoomAnchor + 1) {
      fixture.fail("Z shortcut did not frame the selected note");
    }
    check_input::sendKey(roll, Qt::Key_X, Qt::NoModifier);
    if (!fullSongVisible())
      fixture.fail("X shortcut did not show the full song after note zoom");
    view.zoomAroundContentX(zoomBefore / view.pxPerTick(), zoomAnchor);
    view.scrollByPx(scrollBefore + view.contentX(0.0));
    selectSource();
    verifyShortcut(live_shortcuts::Command::Copy, Qt::Key_C,
                   Qt::ControlModifier);
    if (view.clipboard().empty())
      fixture.fail("Command+C did not populate the note clipboard");
    auto temporaryUndo = fixture.undoCheckpoint();
    verifyShortcut(live_shortcuts::Command::Cut, Qt::Key_X,
                   Qt::ControlModifier);
    auto cutResult = DocNote{};
    if (document.findNote(track, sourceTick, sourceKey, &cutResult))
      fixture.fail("Command+X did not remove the selected note");
    fixture.undoTo(temporaryUndo);
    selectSource();
    temporaryUndo = fixture.undoCheckpoint();
    verifyShortcut(live_shortcuts::Command::Delete, Qt::Key_Delete,
                   Qt::NoModifier);
    auto deletedResult = DocNote{};
    if (document.findNote(track, sourceTick, sourceKey, &deletedResult))
      fixture.fail("Delete did not remove the selected note");
    fixture.undoTo(temporaryUndo);
    selectSource();
    verifyShortcut(live_shortcuts::Command::SelectAll, Qt::Key_A,
                   Qt::ControlModifier);
    if (std::find(view.selection().begin(), view.selection().end(), source) ==
        view.selection().end()) {
      fixture.fail("Command+A did not select the source note");
    }
    auto pasteTick = uint64_t{0};
    for (const auto &trackNote : document.notesForTrack(track)) {
      if (!trackNote.unterminated())
        pasteTick = std::max(pasteTick, trackNote.tick + trackNote.duration);
    }
    pasteTick += view.gridTicksAt(pasteTick);
    const auto cursorBefore = view.editCursorTick();
    view.setEditCursorTick(pasteTick);
    temporaryUndo = fixture.undoCheckpoint();
    verifyShortcut(live_shortcuts::Command::Paste, Qt::Key_V,
                   Qt::ControlModifier);
    auto pastedResult = DocNote{};
    if (!document.findNote(track, pasteTick, sourceKey, &pastedResult))
      fixture.fail("Command+V did not paste at the edit cursor");
    fixture.undoTo(temporaryUndo);
    view.setEditCursorTick(cursorBefore);
    selectSource();
    temporaryUndo = fixture.undoCheckpoint();
    verifyShortcut(live_shortcuts::Command::Duplicate, Qt::Key_D,
                   Qt::ControlModifier);
    fixture.undoTo(temporaryUndo);
    view.clearSelection();
  }
  view.scrollByPx(scrollBefore + view.contentX(0.0));
  fixture.verifyScenarioUndoAndBaseline("static-view scenario", scenarioStart,
                                        expectedUndoDelta);
}

void runRollNavigationScenario(RollCheckFixture &fixture) {
  const auto scenarioStart = fixture.undoCheckpoint();
  auto &document = fixture.document();
  auto &view = fixture.view();
  auto &roll = fixture.roll();
  const auto track = fixture.track();
  const auto viewWidth = std::max(50, roll.width() - songview::kKeyboardW);
  const auto trackNotes = document.notesForTrack(track);
  auto navigationTick = uint64_t{0};
  auto navigationDuration = uint64_t{0};
  auto navigationKey = uint8_t{0};
  auto foundNavigationCell = false;
  for (auto key = 115; key >= 24 && !foundNavigationCell; --key) {
    const auto y = (127 - key) * view.keyHeight() - view.scrollY();
    if (y < 0 || y + view.keyHeight() > roll.height())
      continue;
    for (auto probe = 8; probe < viewWidth - 40; probe += 24) {
      const auto tick = view.snapTickDown(view.tickAtContentX(probe));
      const auto duration = view.gridTicksAt(tick);
      const auto x0 = songview::kKeyboardW + view.contentX(double(tick));
      const auto x1 =
          songview::kKeyboardW + view.contentX(double(tick + duration));
      if (x0 < songview::kKeyboardW || x1 - x0 < 12 || x1 >= roll.width())
        continue;
      if (view.contentX(double(fixture.timeline().lengthTicks)) -
              view.contentX(double(tick + duration)) <
          viewWidth - 60) {
        continue;
      }
      const auto occupied = std::any_of(
          trackNotes.begin(), trackNotes.end(),
          [tick, duration, key](const auto &note) {
            if (note.key != key)
              return false;
            const auto noteEnd = note.unterminated()
                                     ? std::numeric_limits<uint64_t>::max()
                                     : note.tick + note.duration + duration;
            return note.tick < tick + 2 * duration && noteEnd > tick;
          });
      if (occupied)
        continue;
      navigationTick = tick;
      navigationDuration = duration;
      navigationKey = uint8_t(key);
      foundNavigationCell = true;
      break;
    }
  }
  if (!foundNavigationCell) {
    fixture.fail("could not find a local navigation note with timeline tail");
    fixture.verifyScenarioUndoAndBaseline("navigation scenario", scenarioStart,
                                          0);
    return;
  }
  document.addNote(track, navigationTick, navigationKey, navigationDuration,
                   100);
  auto navigationNote = DocNote{};
  if (!document.findNote(track, navigationTick, navigationKey,
                         &navigationNote)) {
    fixture.fail("could not seed the navigation note");
  }
  view.setSelection({{uint32_t(navigationTick), navigationKey}});
  const auto keyHeight = view.keyHeight();
  const auto keyNow = int(navigationKey);
  view.scrollRollBy((129 - keyNow) * keyHeight - view.scrollY());
  if ((128 - keyNow) * keyHeight - view.scrollY() > 0)
    fixture.fail("could not park the note's row above the viewport");
  check_input::sendKey(roll, Qt::Key_Up, Qt::NoModifier);
  auto transposedUp = DocNote{};
  if (!document.findNote(track, navigationTick, uint8_t(navigationKey + 1),
                         &transposedUp)) {
    fixture.fail("Up did not transpose the navigation note");
  }
  if (view.scrollY() != (126 - keyNow) * keyHeight)
    fixture.fail(
        "Up above the viewport did not scroll the row flush to the top");
  check_input::sendKey(roll, Qt::Key_Down, Qt::NoModifier);
  auto restoredPitch = DocNote{};
  if (!document.findNote(track, navigationTick, navigationKey, &restoredPitch))
    fixture.fail("Down did not restore the navigation note's pitch");
  auto currentStart = navigationTick;
  view.scrollByPx(view.contentX(double(currentStart + navigationDuration)) +
                  40);
  if (view.contentX(double(currentStart + navigationDuration)) >= 0)
    fixture.fail("could not park the note past the left edge");
  check_input::sendKey(roll, Qt::Key_Right, Qt::NoModifier);
  currentStart += navigationDuration;
  auto nudgedRight = DocNote{};
  if (!document.findNote(track, currentStart, navigationKey, &nudgedRight))
    fixture.fail("Right did not nudge the navigation note");
  if (view.contentX(double(currentStart)) != 0) {
    fixture.fail("Right off-screen-left did not scroll the start flush to the "
                 "left edge");
  }
  const auto cellPixels =
      view.contentX(double(currentStart + navigationDuration)) -
      view.contentX(double(currentStart));
  const auto rideCount =
      (viewWidth - view.contentX(double(currentStart + navigationDuration))) /
          cellPixels +
      2;
  for (auto ride = 0; ride < rideCount; ++ride) {
    check_input::sendKey(roll, Qt::Key_Right, Qt::NoModifier);
    currentStart += navigationDuration;
    auto riddenRight = DocNote{};
    if (!document.findNote(track, currentStart, navigationKey, &riddenRight))
      fixture.fail("repeated Right lost the navigation note");
  }
  if (view.contentX(double(currentStart + navigationDuration)) !=
      viewWidth - 1) {
    fixture.fail(
        "riding the nudge right did not keep the note's end at the right edge");
  }
  for (auto ride = 0; ride < rideCount + 1; ++ride) {
    check_input::sendKey(roll, Qt::Key_Left, Qt::NoModifier);
    currentStart -= navigationDuration;
    auto riddenLeft = DocNote{};
    if (!document.findNote(track, currentStart, navigationKey, &riddenLeft))
      fixture.fail("repeated Left lost the navigation note");
  }
  auto homeNote = DocNote{};
  if (!document.findNote(track, navigationTick, navigationKey, &homeNote))
    fixture.fail("the ride right and back did not return the note home");
  constexpr auto expectedUndoDelta = 2;
  fixture.verifyScenarioUndoAndBaseline("navigation scenario", scenarioStart,
                                        expectedUndoDelta);
}

void runRollTimeRangeScenario(RollCheckFixture &fixture) {
  constexpr auto expectedUndoDelta = 3;
  const auto scenarioStart = fixture.undoCheckpoint();
  auto &document = fixture.document();
  auto &view = fixture.view();
  auto &roll = fixture.roll();
  const auto track = fixture.track();
  auto lastNoteEnd = uint64_t{0};
  for (const auto &note : document.notesForTrack(track)) {
    if (!note.unterminated())
      lastNoteEnd = std::max(lastNoteEnd, note.tick + note.duration);
  }
  const auto timeRangeTick = view.snapTickUp(double(lastNoteEnd + 1));
  const auto timeRangeDuration = view.gridTicksAt(timeRangeTick);
  const auto timeRangeKey = uint8_t{60};
  document.addNote(track, timeRangeTick, timeRangeKey, timeRangeDuration, 100);
  auto timeRangeNote = DocNote{};
  if (!document.findNote(track, timeRangeTick, timeRangeKey, &timeRangeNote))
    fixture.fail("could not seed the time-range note");
  auto timeBand = SongView::TimeSelection{};
  timeBand.startTick = timeRangeTick;
  timeBand.endTick = timeRangeTick + timeRangeDuration;
  view.setTimeSelection(timeBand);
  check_input::sendKey(roll, Qt::Key_Up, Qt::NoModifier);
  auto transposedInBand = DocNote{};
  if (!document.findNote(track, timeRangeTick, uint8_t(timeRangeKey + 1),
                         &transposedInBand)) {
    fixture.fail("time-selection Up did not transpose the covered note");
  }
  check_input::sendKey(roll, Qt::Key_Right, Qt::NoModifier);
  auto nudgedInBand = DocNote{};
  if (!document.findNote(track, timeRangeTick + timeRangeDuration,
                         uint8_t(timeRangeKey + 1), &nudgedInBand)) {
    fixture.fail("time-selection Right did not nudge the covered note");
  }
  if (view.timeSelection().startTick != timeRangeTick + timeRangeDuration) {
    fixture.fail("time-selection band did not follow the nudge");
  }
  auto *lanes = fixture.automationLanes();
  if (!lanes)
    fixture.fail("automation area not found");
  const auto viewWidth = std::max(50, roll.width() - songview::kKeyboardW);
  {
    const auto home = view.contentX(0.0);
    const auto farTick =
        uint64_t(std::max(0.0, view.tickAtContentX(viewWidth * 2)));
    view.setFollowPlayback(false);
    view.setPlayheadSample(fixture.timeline().sampleForTick(farTick), true);
    if (view.contentX(0.0) != home)
      fixture.fail("disabled Follow Playback still scrolled the view");
    view.setFollowPlayback(true);
    view.setPlayheadSample(fixture.timeline().sampleForTick(farTick), true);
    if (view.contentX(0.0) == home)
      fixture.fail("enabled Follow Playback did not scroll the view");
    view.setPlayheadSample(0, false);
    view.scrollByPx(view.contentX(0.0) - home);
  }
  for (auto *pannedWidget : {&roll, lanes}) {
    if (!pannedWidget)
      continue;
    const auto home = view.contentX(0.0);
    const auto farTick =
        uint64_t(std::max(0.0, view.tickAtContentX(viewWidth * 2)));
    const auto middle =
        QPoint(pannedWidget->width() / 2, pannedWidget->height() / 2);
    check_input::sendMouse(*pannedWidget, QEvent::MouseButtonPress, middle,
                           Qt::MiddleButton, Qt::MiddleButton);
    view.setPlayheadSample(fixture.timeline().sampleForTick(farTick), true);
    if (view.contentX(0.0) != home) {
      fixture.fail(
          "playhead follow-scroll moved the view during a pan gesture");
    }
    check_input::sendMouse(*pannedWidget, QEvent::MouseButtonRelease, middle,
                           Qt::MiddleButton, Qt::NoButton);
    view.setPlayheadSample(fixture.timeline().sampleForTick(farTick), true);
    if (view.contentX(0.0) == home) {
      fixture.fail("playhead follow-scroll did not resume after the pan ended");
    }
    view.setPlayheadSample(0, false);
    view.scrollByPx(view.contentX(0.0) - home);
  }
  fixture.verifyScenarioUndoAndBaseline("time-range scenario", scenarioStart,
                                        expectedUndoDelta);
}

void runRollTrackHeaderScenario(RollCheckFixture &fixture) {
  const auto scenarioStart = fixture.undoCheckpoint();
  auto &document = fixture.document();
  auto &view = fixture.view();
  const auto track = fixture.track();
  const auto selectedTrackName = document.trackName(track);
  const auto returnRenameEffective =
      selectedTrackName != QStringLiteral("Rolled");
  const auto hasReorder = document.engineTrackCount() >= 2;
  auto trackMovePerformed = false;
  auto dragRenameEffective = false;
  auto dragRenamed = false;
  {
    view.renameTrack(track);
    auto *editor =
        view.findChild<QLineEdit *>(QStringLiteral("trackRenameEditor"));
    if (!editor || editor->isHidden()) {
      fixture.fail("rename editor did not open");
    } else {
      editor->setText(QStringLiteral("Rolled"));
      check_input::sendKey(*editor, Qt::Key_Return, Qt::NoModifier);
      fixture.processEvents();
      if (document.trackName(track) != QStringLiteral("Rolled"))
        fixture.fail("inline rename did not apply on Return");
    }
    view.renameTrack(track);
    editor = view.findChild<QLineEdit *>(QStringLiteral("trackRenameEditor"));
    if (!editor || editor->isHidden()) {
      fixture.fail("rename editor did not reopen after the rebuild");
    } else {
      editor->setText(QStringLiteral("Discarded"));
      check_input::sendKey(*editor, Qt::Key_Escape, Qt::NoModifier);
      fixture.processEvents();
      if (document.trackName(track) != QStringLiteral("Rolled"))
        fixture.fail("Escape did not discard the rename");
    }
    view.renameTrack(track);
    editor = view.findChild<QLineEdit *>(QStringLiteral("trackRenameEditor"));
    if (editor && !editor->isHidden()) {
      const auto commandCount = document.undoStack()->count();
      editor->setText(QStringLiteral("["));
      check_input::sendKey(*editor, Qt::Key_Return, Qt::NoModifier);
      fixture.processEvents();
      if (document.trackName(track) != QStringLiteral("Rolled") ||
          document.undoStack()->count() != commandCount) {
        fixture.fail("loop-marker name was not refused");
      }
    }
  }
  {
    view.setEditCursorTick(0);
    const auto baseProgram = view.currentProgram(track);
    const auto changedProgram = baseProgram == 5 ? 6 : 5;
    const auto voiceChangeTick = 4 * view.gridTicksAt(0);
    document.addLanePoint(track, DOC_CC_VOICE, voiceChangeTick, changedProgram);
    const auto startProgram = baseProgram < 0 ? changedProgram : baseProgram;
    if (view.currentProgram(track) != startProgram)
      fixture.fail("voice label at the start did not show the priming program");
    view.setEditCursorTick(voiceChangeTick);
    if (view.currentProgram(track) != changedProgram)
      fixture.fail(
          "voice label did not follow the edit cursor past the change");
    view.setEditCursorTick(0);
    view.setPlayheadSample(
        fixture.timeline().sampleForTick(voiceChangeTick + 1), true);
    if (view.currentProgram(track) != changedProgram)
      fixture.fail("voice label did not follow the playing playhead");
    view.setPlayheadSample(0, false);
    if (view.currentProgram(track) != startProgram)
      fixture.fail("voice label did not return to the edit cursor after stop");
  }
  fixture.processEvents();
  const auto voiceNavigationUndo = fixture.undoCheckpoint();
  const auto voiceNavigationSmf = document.smf().write();
  {
    (void)view.grab();
    auto *row = view.findChild<QWidget *>(
        QStringLiteral("trackHeaderRow%1").arg(track));
    if (!row) {
      fixture.fail("track header row for the edited track not found");
    } else {
      auto revealedProgram = -1;
      auto revealCount = 0;
      const auto connection =
          QObject::connect(&view, &SongView::revealVoiceRequested,
                           [&revealedProgram, &revealCount](int program) {
                             revealedProgram = program;
                             ++revealCount;
                           });
      const auto voicePosition = QPoint(row->width() / 2, 30);
      check_input::click(*row, voicePosition);
      if (revealCount != 1 || revealedProgram != view.currentProgram(track))
        fixture.fail("voice-line click did not request the track's program");
      check_input::click(*row, QPoint(row->width() / 2, 10));
      if (revealCount != 1)
        fixture.fail("a name-line click requested a voice reveal");
      check_input::sendMouse(*row, QEvent::MouseButtonPress, voicePosition,
                             Qt::LeftButton, Qt::LeftButton);
      check_input::sendMouse(*row, QEvent::MouseMove,
                             voicePosition + QPoint(0, 25), Qt::NoButton,
                             Qt::LeftButton);
      check_input::sendMouse(*row, QEvent::MouseButtonRelease,
                             voicePosition + QPoint(0, 25), Qt::LeftButton,
                             Qt::NoButton);
      fixture.processEvents();
      if (revealCount != 1)
        fixture.fail("a reorder drag from the voice line requested a reveal");
      QTimer pickerPoll;
      pickerPoll.setInterval(0);
      auto pickerSeen = false;
      QObject::connect(&pickerPoll, &QTimer::timeout, [&view, &pickerSeen] {
        if (auto *dialog = view.findChild<QDialog *>()) {
          pickerSeen = true;
          dialog->reject();
        }
      });
      pickerPoll.start();
      check_input::sendMouse(*row, QEvent::MouseButtonDblClick, voicePosition,
                             Qt::LeftButton, Qt::LeftButton);
      check_input::sendMouse(*row, QEvent::MouseButtonRelease, voicePosition,
                             Qt::LeftButton, Qt::NoButton);
      fixture.processEvents();
      pickerPoll.stop();
      if (!pickerSeen)
        fixture.fail("voice-line double-click did not open the voice picker");
      auto *renameEditor =
          view.findChild<QLineEdit *>(QStringLiteral("trackRenameEditor"));
      if (renameEditor && !renameEditor->isHidden())
        fixture.fail("voice-line double-click opened the rename editor");
      const auto namePosition = QPoint(row->width() / 2, 10);
      check_input::sendMouse(*row, QEvent::MouseButtonDblClick, namePosition,
                             Qt::LeftButton, Qt::LeftButton);
      check_input::sendMouse(*row, QEvent::MouseButtonRelease, namePosition,
                             Qt::LeftButton, Qt::NoButton);
      renameEditor =
          view.findChild<QLineEdit *>(QStringLiteral("trackRenameEditor"));
      if (!renameEditor || renameEditor->isHidden()) {
        fixture.fail(
            "name-line double-click no longer opens the rename editor");
      } else {
        check_input::sendKey(*renameEditor, Qt::Key_Escape, Qt::NoModifier);
      }
      fixture.processEvents();
      if (fixture.activeUndoDelta(voiceNavigationUndo) != 0 ||
          document.smf().write() != voiceNavigationSmf) {
        fixture.fail("voice navigation unexpectedly mutated active undo "
                     "position or SMF bytes");
      }
      QObject::disconnect(connection);
    }
  }
  if (hasReorder) {
    (void)view.grab();
    auto *firstRow =
        view.findChild<QWidget *>(QStringLiteral("trackHeaderRow0"));
    auto *secondRow =
        view.findChild<QWidget *>(QStringLiteral("trackHeaderRow1"));
    if (!firstRow || !secondRow) {
      fixture.fail("track header rows not found");
    } else {
      const auto preDropTrackName = document.trackName(0);
      auto firstTrackNotes = std::vector<TrackNotePosition>{};
      for (const auto &note : document.notesForTrack(0))
        firstTrackNotes.push_back({note.tick, note.key});
      view.setTrackMute(0, true);
      const auto start =
          QPoint(firstRow->width() / 2, firstRow->height() * 3 / 4);
      const auto drop =
          QPoint(firstRow->width() / 2, firstRow->height() * 8 / 5);
      const auto preDragUndoCount = document.undoStack()->count();
      check_input::sendMouse(*firstRow, QEvent::MouseButtonPress, start,
                             Qt::LeftButton, Qt::LeftButton);
      check_input::sendMouse(*firstRow, QEvent::MouseMove, drop, Qt::NoButton,
                             Qt::LeftButton);
      check_input::sendMouse(*firstRow, QEvent::MouseButtonRelease, drop,
                             Qt::RightButton, Qt::LeftButton);
      check_input::sendMouse(*firstRow, QEvent::MouseButtonRelease, drop,
                             Qt::LeftButton, Qt::NoButton);
      fixture.processEvents();
      if (document.undoStack()->count() != preDragUndoCount)
        fixture.fail("right-button release mid-drag committed the reorder");
      view.renameTrack(0);
      auto *editor =
          view.findChild<QLineEdit *>(QStringLiteral("trackRenameEditor"));
      if (editor && !editor->isHidden()) {
        editor->setText(QStringLiteral("Dragged"));
        dragRenamed = true;
        dragRenameEffective = preDropTrackName != QStringLiteral("Dragged");
      }
      check_input::sendMouse(*firstRow, QEvent::MouseButtonPress, start,
                             Qt::LeftButton, Qt::LeftButton);
      check_input::sendMouse(*firstRow, QEvent::MouseMove, drop, Qt::NoButton,
                             Qt::LeftButton);
      check_input::sendMouse(*firstRow, QEvent::MouseButtonRelease, drop,
                             Qt::LeftButton, Qt::NoButton);
      fixture.processEvents();
      const auto movedNotes = document.notesForTrack(1);
      auto movedCorrectly = movedNotes.size() == firstTrackNotes.size();
      for (auto index = size_t{0}; movedCorrectly && index < movedNotes.size();
           ++index) {
        movedCorrectly =
            movedNotes[index].tick == firstTrackNotes[index].tick &&
            movedNotes[index].key == firstTrackNotes[index].key;
      }
      if (!movedCorrectly) {
        fixture.fail("header drag did not move the track's notes to slot 1");
      } else if (!view.trackMuted(1) || view.trackMuted(0)) {
        fixture.fail("header drag did not move the mute flag with the track");
      } else {
        trackMovePerformed = true;
        if (dragRenamed && document.trackName(1) != QStringLiteral("Dragged")) {
          fixture.fail("the open rename editor's text was lost in the drop");
        }
        document.undoStack()->undo();
        if (!view.trackMuted(0) || view.trackMuted(1))
          fixture.fail("undoing the move left the mute flag behind");
        document.undoStack()->redo();
        if (!view.trackMuted(1) || view.trackMuted(0))
          fixture.fail("redoing the move did not re-move the mute flag");
      }
      view.setTrackMute(1, false);
    }
  }
  const auto expectedUndoDelta = 1 + returnRenameEffective +
                                 (hasReorder && trackMovePerformed) +
                                 dragRenameEffective;
  fixture.verifyScenarioUndoAndBaseline("track-header scenario", scenarioStart,
                                        expectedUndoDelta);
}
