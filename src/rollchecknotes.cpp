#include "rollcheckfixture.hpp"

#include <QAction>
#include <QApplication>
#include <QImage>
#include <QMenu>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <limits>
#include <vector>

#include "checkinput.hpp"

namespace {

struct RollCell {
  uint64_t tick = 0;
  uint64_t duration = 0;
  int key = -1;
  QPoint center;
  QPoint handle;
};

void drawNote(QWidget &roll, QPoint position) {
  check_input::sendMouse(roll, QEvent::MouseButtonDblClick, position,
                         Qt::LeftButton, Qt::LeftButton);
  check_input::sendMouse(roll, QEvent::MouseButtonRelease, position,
                         Qt::LeftButton, Qt::NoButton);
}

bool cellIsOccupied(RollCheckFixture &fixture, uint64_t tick, uint64_t duration,
                    int key) {
  for (const auto &note : fixture.document().notesForTrack(fixture.track())) {
    if (int(note.key) != key)
      continue;
    const auto noteEnd = note.unterminated()
                             ? std::numeric_limits<uint64_t>::max()
                             : note.tick + note.duration + duration;
    if (note.tick < tick + 2 * duration && noteEnd > tick)
      return true;
  }
  return false;
}

RollCell findFreeCell(RollCheckFixture &fixture) {
  auto &view = fixture.view();
  auto &roll = fixture.roll();
  const auto keyHeight = view.keyHeight();
  for (auto key = 115; key >= 24; --key) {
    const auto y = (127 - key) * keyHeight - view.scrollY();
    if (y < 0 || y + keyHeight > roll.height())
      continue;
    for (auto probe = 8; probe < roll.width() - songview::kKeyboardW - 40;
         probe += 24) {
      const auto tick = view.snapTickDown(view.tickAtContentX(probe));
      const auto duration = view.gridTicksAt(tick);
      const auto x0 = songview::kKeyboardW + view.contentX(double(tick));
      const auto x1 =
          songview::kKeyboardW + view.contentX(double(tick + duration));
      if (x0 < songview::kKeyboardW || x1 - x0 < 12 || x1 >= roll.width())
        continue;
      if (cellIsOccupied(fixture, tick, duration, key))
        continue;
      return {tick, duration, key, QPoint((x0 + x1) / 2, y + keyHeight / 2 + 1),
              QPoint((x0 + x1) / 2, y + 2)};
    }
  }
  return {};
}

} // namespace

void runRollDrawnNotesScenario(RollCheckFixture &fixture,
                               const QString &screenshotPath) {
  constexpr auto expectedUndoDelta = 6;
  const auto scenarioStart = fixture.undoCheckpoint();
  const auto finish = [&fixture, &screenshotPath, scenarioStart,
                       expectedUndoDelta] {
    // Capture the draw fixture after its gestures and before its undo cleanup.
    const QImage image = fixture.view().grab().toImage();
    if (image.isNull())
      fixture.fail("offscreen render produced no image");
    if (!screenshotPath.isEmpty()) {
      image.save(screenshotPath);
      std::printf("rollcheck: wrote %s\n", qUtf8Printable(screenshotPath));
    }
    fixture.verifyScenarioUndoAndBaseline("drawn-notes scenario", scenarioStart,
                                          expectedUndoDelta);
  };
  auto &document = fixture.document();
  auto &view = fixture.view();
  auto &roll = fixture.roll();
  const auto track = fixture.track();
  const auto firstCell = findFreeCell(fixture);
  if (firstCell.key < 0) {
    fixture.fail("no free grid cell to draw in");
    finish();
    return;
  }
  drawNote(roll, firstCell.center);
  auto firstDrawn = DocNote{};
  if (!document.findNote(track, firstCell.tick, uint8_t(firstCell.key),
                         &firstDrawn)) {
    fixture.fail("pencil draw produced no note");
    finish();
    return;
  }
  if (firstDrawn.velocity != 100)
    fixture.fail("fresh document does not draw at velocity 100");
  document.setNotesVelocity({firstDrawn}, 73);
  check_input::click(roll, firstCell.center);
  const auto secondCell = findFreeCell(fixture);
  if (secondCell.key < 0) {
    fixture.fail("no free grid cell for the click-latch draw");
    finish();
    return;
  }
  drawNote(roll, secondCell.center);
  auto secondDrawn = DocNote{};
  if (!document.findNote(track, secondCell.tick, uint8_t(secondCell.key),
                         &secondDrawn)) {
    fixture.fail("click-latch draw produced no note");
    finish();
    return;
  }
  if (secondDrawn.velocity != 73)
    fixture.fail("clicked note's velocity did not latch into the next draw");
  check_input::sendMouse(roll, QEvent::MouseButtonPress, secondCell.center,
                         Qt::RightButton, Qt::RightButton);
  check_input::sendMouse(roll, QEvent::MouseButtonRelease, secondCell.center,
                         Qt::RightButton, Qt::NoButton);
  fixture.processEvents();
  auto *noteMenu = roll.findChild<QMenu *>();
  if (!noteMenu || !noteMenu->isVisible()) {
    fixture.fail("right-click did not open the note menu");
  } else {
    const auto firstGlobalPosition = roll.mapToGlobal(firstCell.center);
    check_input::sendMouse(*noteMenu, QEvent::MouseButtonPress,
                           noteMenu->mapFromGlobal(firstGlobalPosition),
                           Qt::RightButton, Qt::RightButton);
    check_input::sendMouse(*noteMenu, QEvent::MouseButtonRelease,
                           noteMenu->mapFromGlobal(firstGlobalPosition),
                           Qt::RightButton, Qt::NoButton);
    fixture.processEvents();
    const auto firstId =
        SongView::NoteId{uint32_t(firstCell.tick), uint8_t(firstCell.key)};
    const auto &selection = view.selection();
    if (!noteMenu->isVisible())
      fixture.fail("retargeting hid the open note menu");
    if (selection.size() != 1 || !(selection.front() == firstId))
      fixture.fail("retargeting did not select the new note");
    noteMenu->hide();
    fixture.processEvents();
  }
  check_input::sendMouse(roll, QEvent::MouseButtonPress, secondCell.handle,
                         Qt::LeftButton, Qt::LeftButton);
  check_input::sendMouse(roll, QEvent::MouseMove,
                         secondCell.handle - QPoint(0, 20), Qt::NoButton,
                         Qt::LeftButton);
  check_input::sendMouse(roll, QEvent::MouseButtonRelease,
                         secondCell.handle - QPoint(0, 20), Qt::LeftButton,
                         Qt::NoButton);
  auto draggedNote = DocNote{};
  if (!document.findNote(track, secondCell.tick, uint8_t(secondCell.key),
                         &draggedNote) ||
      draggedNote.velocity != 93) {
    fixture.fail("velocity-handle drag did not land at 93");
  }
  const auto ctrlVelCheck = fixture.undoCheckpoint();
  // Cmd/Ctrl hover over note sets updown arrows cursor
  check_input::sendMouse(roll, QEvent::MouseMove, secondCell.center,
                         Qt::NoButton, Qt::NoButton, Qt::ControlModifier);
  if (roll.cursor().shape() != Qt::SizeVerCursor) {
    fixture.fail("Cmd/Ctrl hover over note did not set updown arrows cursor");
  }
  check_input::sendMouse(roll, QEvent::MouseMove, secondCell.center,
                         Qt::NoButton, Qt::NoButton, Qt::NoModifier);
  if (roll.cursor().shape() == Qt::SizeVerCursor) {
    fixture.fail("plain hover over note center unexpectedly set updown arrows cursor");
  }
  // Cmd/Ctrl + left drag on note adjusts note velocity
  check_input::sendMouse(roll, QEvent::MouseButtonPress, secondCell.center,
                         Qt::LeftButton, Qt::LeftButton, Qt::ControlModifier);
  check_input::sendMouse(roll, QEvent::MouseMove,
                         secondCell.center - QPoint(0, 10), Qt::NoButton,
                         Qt::LeftButton, Qt::ControlModifier);
  check_input::sendMouse(roll, QEvent::MouseButtonRelease,
                         secondCell.center - QPoint(0, 10), Qt::LeftButton,
                         Qt::NoButton, Qt::ControlModifier);
  auto ctrlDraggedNote = DocNote{};
  if (!document.findNote(track, secondCell.tick, uint8_t(secondCell.key),
                         &ctrlDraggedNote) ||
      ctrlDraggedNote.velocity != 103) {
    fixture.fail("Cmd/Ctrl click-drag did not adjust note velocity to 103");
  }
  fixture.undoTo(ctrlVelCheck);
  check_input::click(roll, secondCell.center);
  const auto thirdCell = findFreeCell(fixture);
  if (thirdCell.key < 0) {
    fixture.fail("no free grid cell for the drag-latch draw");
    finish();
    return;
  }
  drawNote(roll, thirdCell.center);
  auto thirdDrawn = DocNote{};
  if (!document.findNote(track, thirdCell.tick, uint8_t(thirdCell.key),
                         &thirdDrawn)) {
    fixture.fail("drag-latch draw produced no note");
    finish();
    return;
  }
  if (thirdDrawn.velocity != 93)
    fixture.fail("dragged velocity did not latch into the next draw");
  check_input::sendMouse(roll, QEvent::MouseButtonDblClick, thirdCell.center,
                         Qt::LeftButton, Qt::LeftButton);
  check_input::sendMouse(roll, QEvent::MouseButtonRelease, thirdCell.center,
                         Qt::LeftButton, Qt::NoButton);
  auto deletedNote = DocNote{};
  if (document.findNote(track, thirdCell.tick, uint8_t(thirdCell.key),
                        &deletedNote)) {
    fixture.fail("double-click on a note did not delete it");
  }
  {
    auto soundedKeys = std::vector<int>{};
    auto releasedKeys = std::vector<int>{};
    auto shortestAudition = std::numeric_limits<quint32>::max();
    const auto connection = QObject::connect(
        &view, &SongView::auditionNoteTimed, &view,
        [&soundedKeys, &releasedKeys,
         &shortestAudition](int, int key, int velocity, quint32 duration) {
          if (velocity > 0) {
            soundedKeys.push_back(key);
            shortestAudition = std::min(shortestAudition, duration);
          } else {
            releasedKeys.push_back(key);
          }
        });
    const auto preBandUndoCount = document.undoStack()->count();
    const auto sweepStart = QPoint(songview::kKeyboardW + 1, 0);
    const auto sweepEnd =
        QPoint(std::max(firstCell.center.x(), secondCell.center.x()) + 4,
               std::max(firstCell.center.y(), secondCell.center.y()) + 4);
    check_input::sendMouse(roll, QEvent::MouseButtonPress, sweepStart,
                           Qt::RightButton, Qt::RightButton);
    check_input::sendMouse(roll, QEvent::MouseMove,
                           firstCell.center + QPoint(4, 4), Qt::NoButton,
                           Qt::RightButton);
    if (std::find(soundedKeys.begin(), soundedKeys.end(), firstCell.key) ==
        soundedKeys.end()) {
      fixture.fail("sweeping the band over a note did not audition it");
    }
    check_input::sendMouse(roll, QEvent::MouseMove, sweepStart + QPoint(4, 4),
                           Qt::NoButton, Qt::RightButton);
    if (std::find(releasedKeys.begin(), releasedKeys.end(), firstCell.key) ==
        releasedKeys.end()) {
      fixture.fail("shrinking the band did not release the departed note");
    }
    check_input::sendMouse(roll, QEvent::MouseMove, sweepEnd, Qt::NoButton,
                           Qt::RightButton);
    check_input::sendMouse(roll, QEvent::MouseButtonRelease, sweepEnd,
                           Qt::RightButton, Qt::NoButton);
    QObject::disconnect(connection);
    if (std::count(soundedKeys.begin(), soundedKeys.end(), firstCell.key) < 2) {
      fixture.fail("re-covering a note did not re-audition it");
    }
    const auto &selection = view.selection();
    const auto firstId =
        SongView::NoteId{uint32_t(firstCell.tick), uint8_t(firstCell.key)};
    const auto secondId =
        SongView::NoteId{uint32_t(secondCell.tick), uint8_t(secondCell.key)};
    if (selection.size() < 2 ||
        std::find(selection.begin(), selection.end(), firstId) ==
            selection.end() ||
        std::find(selection.begin(), selection.end(), secondId) ==
            selection.end()) {
      fixture.fail("band release did not select the swept notes");
    }
    const auto uniqueKeys = [](auto keys) {
      std::sort(keys.begin(), keys.end());
      keys.erase(std::unique(keys.begin(), keys.end()), keys.end());
      return keys;
    };
    if (uniqueKeys(soundedKeys) != uniqueKeys(releasedKeys))
      fixture.fail("band sweep left auditioned keys unreleased");
    if (!soundedKeys.empty() && shortestAudition == 0)
      fixture.fail("band sweep auditioned a zero-length note");
    if (document.undoStack()->count() != preBandUndoCount)
      fixture.fail("band sweep pushed an undo command");
    view.clearSelection();
  }
  finish();
}

void runRollEditingScenario(RollCheckFixture &fixture) {
  constexpr auto expectedUndoDelta = 6;
  const auto scenarioStart = fixture.undoCheckpoint();
  const auto finish = [&fixture, scenarioStart, expectedUndoDelta] {
    fixture.verifyScenarioUndoAndBaseline("editing scenario", scenarioStart,
                                          expectedUndoDelta);
  };
  auto &document = fixture.document();
  auto &view = fixture.view();
  auto &roll = fixture.roll();
  const auto track = fixture.track();
  const auto keyHeight = view.keyHeight();
  const auto zoomAnchor = std::max(0, roll.width() - songview::kKeyboardW) / 2;
  const auto editCell = findFreeCell(fixture);
  if (editCell.key < 0) {
    fixture.fail("no free grid cell for the off-grid resize");
    finish();
    return;
  }
  const auto offGridDuration =
      uint32_t(editCell.duration + editCell.duration / 4);
  document.addNote(track, editCell.tick, uint8_t(editCell.key), offGridDuration,
                   100);
  const auto rowY =
      (127 - editCell.key) * keyHeight - view.scrollY() + keyHeight / 2 + 1;
  const auto firstEdge =
      QPoint(songview::kKeyboardW +
                 view.contentX(double(editCell.tick + offGridDuration)),
             rowY);
  const auto firstPull = QPoint(
      songview::kKeyboardW + view.contentX(double(editCell.tick) +
                                           1.75 * double(editCell.duration)),
      rowY);
  check_input::sendMouse(roll, QEvent::MouseButtonPress, firstEdge,
                         Qt::LeftButton, Qt::LeftButton);
  check_input::sendMouse(roll, QEvent::MouseMove, firstPull, Qt::NoButton,
                         Qt::LeftButton);
  check_input::sendMouse(roll, QEvent::MouseButtonRelease, firstPull,
                         Qt::LeftButton, Qt::NoButton);
  auto resizedNote = DocNote{};
  if (!document.findNote(track, editCell.tick, uint8_t(editCell.key),
                         &resizedNote) ||
      resizedNote.duration != 2 * editCell.duration) {
    fixture.fail(
        "off-grid right-edge drag did not snap the end to the ruler grid");
  }
  const auto secondEdge =
      QPoint(songview::kKeyboardW +
                 view.contentX(double(editCell.tick + 2 * editCell.duration)),
             rowY);
  const auto overshoot = QPoint(
      songview::kKeyboardW + view.contentX(double(editCell.tick) -
                                           0.5 * double(editCell.duration)),
      rowY);
  check_input::sendMouse(roll, QEvent::MouseButtonPress, secondEdge,
                         Qt::LeftButton, Qt::LeftButton);
  check_input::sendMouse(roll, QEvent::MouseMove, overshoot, Qt::NoButton,
                         Qt::LeftButton);
  check_input::sendMouse(roll, QEvent::MouseButtonRelease, overshoot,
                         Qt::LeftButton, Qt::NoButton);
  auto collapsedNote = DocNote{};
  if (!document.findNote(track, editCell.tick, uint8_t(editCell.key),
                         &collapsedNote) ||
      collapsedNote.duration != editCell.duration) {
    fixture.fail("overshot right-edge drag did not stop at one grid cell");
  }
  const auto editCenter = QPoint(
      songview::kKeyboardW + view.contentX(double(editCell.tick) +
                                           0.5 * double(editCell.duration)),
      rowY);
  check_input::click(roll, editCenter);
  check_input::sendKey(roll, Qt::Key_Up, Qt::NoModifier);
  auto transposedNote = DocNote{};
  if (!document.findNote(track, editCell.tick, uint8_t(editCell.key + 1),
                         &transposedNote)) {
    fixture.fail("Up did not transpose up a semitone");
  }
  check_input::sendKey(roll, Qt::Key_Down, Qt::ShiftModifier);
  if (!document.findNote(track, editCell.tick, uint8_t(editCell.key - 11),
                         &transposedNote)) {
    fixture.fail("Shift+Down did not transpose down an octave");
  }
  check_input::sendKey(roll, Qt::Key_Right, Qt::NoModifier);
  if (!document.findNote(track, editCell.tick + editCell.duration,
                         uint8_t(editCell.key - 11), &transposedNote)) {
    fixture.fail("Right did not nudge one grid cell right");
  }
  const auto shortcutVelocity = transposedNote.velocity;
  const auto modifierStart = fixture.undoCheckpoint();
  check_input::sendKey(roll, Qt::Key_Right, Qt::ShiftModifier);
  if (!document.findNote(track, editCell.tick + editCell.duration,
                         uint8_t(editCell.key - 11), &transposedNote) ||
      transposedNote.duration != 2 * editCell.duration) {
    fixture.fail("Shift+Right did not lengthen by one grid cell");
  }
  check_input::sendKey(roll, Qt::Key_Left, Qt::ShiftModifier);
  if (!document.findNote(track, editCell.tick + editCell.duration,
                         uint8_t(editCell.key - 11), &transposedNote) ||
      transposedNote.duration != editCell.duration) {
    fixture.fail("Shift+Left did not restore the note length");
  }
  check_input::sendKey(roll, Qt::Key_Up, Qt::ControlModifier);
  if (!document.findNote(track, editCell.tick + editCell.duration,
                         uint8_t(editCell.key - 11), &transposedNote) ||
      transposedNote.velocity != uint8_t(shortcutVelocity + 1)) {
    fixture.fail("Command+Up did not increase velocity");
  }
  check_input::sendKey(roll, Qt::Key_Down, Qt::ControlModifier);
  if (!document.findNote(track, editCell.tick + editCell.duration,
                         uint8_t(editCell.key - 11), &transposedNote) ||
      transposedNote.velocity != shortcutVelocity) {
    fixture.fail("Command+Down did not restore velocity");
  }
  fixture.undoTo(modifierStart);
  const auto sourceTick = editCell.tick + editCell.duration;
  const auto sourceKey = uint8_t(editCell.key - 11);
  auto *duplicateAction =
      check_input::findAction(roll, live_shortcuts::Command::Duplicate);
  if (!duplicateAction) {
    fixture.fail("Duplicate action is not attached to the piano roll");
  } else {
    const auto duplicateStart = fixture.undoCheckpoint();
    duplicateAction->trigger();
    auto duplicatedNote = DocNote{};
    if (!document.findNote(track, sourceTick + editCell.duration, sourceKey,
                           &duplicatedNote)) {
      fixture.fail("Duplicate did not copy the selected note one span right");
    }
    fixture.undoTo(duplicateStart);
    auto restoredNote = DocNote{};
    if (!document.findNote(track, sourceTick, sourceKey, &restoredNote)) {
      fixture.fail("undoing Duplicate did not restore the source note");
    }
    view.setSelection({{uint32_t(sourceTick), sourceKey}});
  }
  auto *splitAction =
      check_input::findAction(roll, live_shortcuts::Command::Split);
  const auto triggerSplit = [&roll, splitAction] {
    if (QApplication::platformName() == QStringLiteral("cocoa"))
      check_input::sendKey(roll, Qt::Key_E, Qt::ControlModifier);
    else
      splitAction->trigger();
  };
  if (!splitAction || editCell.duration < 2) {
    fixture.fail("Split action or splittable note is unavailable");
  } else {
    const auto oldGridDenom = view.gridMinDenom();
    const auto oldZoom = view.pxPerTick();
    view.setGridMinDenom(8);
    for (auto attempt = 0;
         view.gridTicksAt(sourceTick) >= editCell.duration && attempt < 4;
         ++attempt) {
      view.zoomAroundContentX(2.0, zoomAnchor);
    }
    const auto splitGrid = view.gridTicksAt(sourceTick);
    if (splitGrid >= editCell.duration || editCell.duration % splitGrid != 0) {
      fixture.fail("could not establish a finer grid for selected-note Split");
    } else {
      const auto selectedSplitStart = fixture.undoCheckpoint();
      triggerSplit();
      for (auto tick = sourceTick; tick < sourceTick + editCell.duration;
           tick += splitGrid) {
        auto splitPart = DocNote{};
        if (!document.findNote(track, tick, sourceKey, &splitPart) ||
            splitPart.duration != splitGrid) {
          fixture.fail(
              "Split did not divide the selected note across the grid");
          break;
        }
      }
      auto *joinAction =
          check_input::findAction(roll, live_shortcuts::Command::Join);
      if (!joinAction) {
        fixture.fail("Join action is not attached to the piano roll");
      } else {
        joinAction->trigger();
        auto joinedNote = DocNote{};
        if (!document.findNote(track, sourceTick, sourceKey, &joinedNote) ||
            joinedNote.duration != editCell.duration) {
          fixture.fail("Join did not merge the selected split notes");
        }
      }
      fixture.undoTo(selectedSplitStart);
      auto restoredSplitSource = DocNote{};
      if (!document.findNote(track, sourceTick, sourceKey,
                             &restoredSplitSource)) {
        fixture.fail(
            "undoing selected-note Split did not restore the source note");
      }
    }
    view.setGridMinDenom(oldGridDenom);
    view.zoomAroundContentX(oldZoom / view.pxPerTick(), zoomAnchor);
    view.clearSelection();
    const auto playheadSplitTick = sourceTick + editCell.duration / 2;
    view.setPlayheadSample(fixture.timeline().sampleForTick(playheadSplitTick),
                           true);
    const auto playheadSplitStart = fixture.undoCheckpoint();
    triggerSplit();
    auto firstHalf = DocNote{};
    auto secondHalf = DocNote{};
    if (!document.findNote(track, sourceTick, sourceKey, &firstHalf) ||
        !document.findNote(track, playheadSplitTick, sourceKey, &secondHalf) ||
        firstHalf.duration != editCell.duration / 2 ||
        secondHalf.duration != editCell.duration - editCell.duration / 2) {
      fixture.fail(
          "Split did not divide the unselected note under the playhead");
    }
    fixture.undoTo(playheadSplitStart);
    auto restoredPlayheadSplitSource = DocNote{};
    if (!document.findNote(track, sourceTick, sourceKey,
                           &restoredPlayheadSplitSource)) {
      fixture.fail("undoing playhead Split did not restore the source note");
    }
    view.setPlayheadSample(0, false);
    view.setSelection({{uint32_t(sourceTick), sourceKey}});
  }
  auto *snapAction =
      check_input::findAction(view, live_shortcuts::Command::ToggleSnapToGrid);
  if (!snapAction) {
    fixture.fail("Toggle Snap to Grid action is not attached to the song view");
  } else {
    const auto rawTick =
        double(editCell.tick) + double(editCell.duration) * 0.37;
    const auto snappedTick = view.snapTick(rawTick);
    const auto gridDenom = view.gridMinDenom();
    snapAction->trigger();
    if (view.snapTick(rawTick) != uint64_t(std::llround(rawTick)))
      fixture.fail("disabling snap did not preserve the raw tick");
    snapAction->trigger();
    if (view.snapTick(rawTick) != snappedTick ||
        view.gridMinDenom() != gridDenom) {
      fixture.fail("re-enabling snap did not restore the previous grid");
    }
  }
  auto sourceBeforeOffGridMove = DocNote{};
  if (!document.findNote(track, sourceTick, sourceKey,
                         &sourceBeforeOffGridMove)) {
    fixture.fail("could not re-resolve the source note for off-grid nudge");
    finish();
    return;
  }
  document.moveNotes({sourceBeforeOffGridMove}, int64_t(editCell.duration / 4),
                     0);
  const auto offGridTick = sourceTick + editCell.duration / 4;
  view.setSelection({{uint32_t(offGridTick), sourceKey}});
  check_input::sendKey(roll, Qt::Key_Left, Qt::NoModifier);
  auto snappedNote = DocNote{};
  if (!document.findNote(track, sourceTick, sourceKey, &snappedNote))
    fixture.fail("Left did not snap the off-grid note back to the grid");
  finish();
}
