#include "rollcheckpsgvelocitymixed.h"

#include <QCoreApplication>
#include <QEvent>
#include <QMouseEvent>
#include <QWidget>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <optional>
#include <utility>
#include <vector>

#include "core/songdocument.h"
#include "ui/songview.h"
#include "ui/velocityarea.h"

namespace {

struct Cell {
  uint64_t tick = 0;
  uint64_t duration = 0;
  int key = -1;
};

void sendMouse(QWidget *widget, QEvent::Type type, QPoint position,
               Qt::MouseButton button, Qt::MouseButtons buttons) {
  QMouseEvent event(type, QPointF(position),
                    QPointF(widget->mapToGlobal(position)), button, buttons,
                    Qt::NoModifier);
  QCoreApplication::sendEvent(widget, &event);
}

void undoTo(SongDocument &document, int index) {
  while (document.undoStack()->index() > index)
    document.undoStack()->undo();
}

Cell findFreeCell(SongDocument &document, SongView &view, QWidget &roll,
                  int track) {
  const qreal dpr = roll.devicePixelRatioF();
  const auto &notes = document.notesForTrack(track);
  const auto edge = [&](int row) {
    return std::round((row * view.keyHeight() - view.scrollY()) * dpr) / dpr;
  };
  for (int key = 115; key >= 24; --key) {
    if (edge(127 - key) < 0 || edge(128 - key) > roll.height())
      continue;
    for (int probe = 8; probe < roll.width() - songview::kKeyboardW - 40;
         probe += 24) {
      const uint64_t tick = view.snapTickDown(view.tickAtContentX(probe));
      const uint64_t duration = view.gridTicksAt(tick);
      const int x0 = songview::kKeyboardW + view.contentX(double(tick));
      const int x1 =
          songview::kKeyboardW + view.contentX(double(tick + duration));
      const int xs = songview::kKeyboardW +
                     view.contentX(double(tick + view.snapTicksAt(tick)));
      if (x0 < songview::kKeyboardW || x1 - x0 < 12 || xs - x0 < 8 ||
          x1 >= roll.width()) {
        continue;
      }
      const bool occupied =
          std::any_of(notes.begin(), notes.end(), [&](const DocNote &note) {
            if (int(note.key) != key)
              return false;
            const uint64_t end = note.unterminated()
                                     ? UINT64_MAX
                                     : note.tick + note.duration + duration;
            return note.tick < tick + 2 * duration && end > tick;
          });
      DocLanePoint point;
      if (occupied ||
          document.findLanePoint(track, DOC_CC_VOICE, tick, &point) ||
          document.findLanePoint(track, 0x07, tick, &point) ||
          document.findLanePoint(track, 0x0A, tick, &point)) {
        continue;
      }
      return {tick, duration, key};
    }
  }
  return {};
}

} // namespace

int runRollCheckPsgVelocityMixed(
    const RollCheckPsgVelocityMixedContext &context) {
  SongDocument &doc = context.document;
  SongView &view = context.view;
  const int track = context.track;
  int failures = 0;
  const auto fail = [&](const char *what) {
    std::fprintf(stderr, "rollcheck: FAIL %s: %s\n",
                 qUtf8Printable(context.songLabel), what);
    ++failures;
  };

  auto *roll = view.findChild<QWidget *>(QStringLiteral("pianoRoll"));
  auto *velocityArea = static_cast<songview::VelocityArea *>(
      view.findChild<QWidget *>(QStringLiteral("velocityArea")));
  if (!roll || !velocityArea) {
    fail("mixed-context PSG sweep fixture had no velocity widgets");
    return failures;
  }

  const int fixtureIndex = doc.undoStack()->index();
  const std::vector<SongView::NoteId> savedSelection = view.selection();
  const QSize savedSize = velocityArea->size();
  const int savedMinimumHeight = velocityArea->minimumHeight();
  const int savedMaximumHeight = velocityArea->maximumHeight();

  const auto runFixture = [&] {
    const Cell first = findFreeCell(doc, view, *roll, track);
    if (first.key < 0) {
      fail("no free first cell for mixed-context PSG sweep");
      return;
    }
    doc.addLanePoint(track, DOC_CC_VOICE, first.tick, context.cgbSlot);
    doc.addLanePoint(track, 0x07, first.tick, 127);
    doc.addLanePoint(track, 0x0A, first.tick, 64);
    doc.addNote(track, first.tick, uint8_t(first.key), uint32_t(first.duration),
                64);

    const Cell second = findFreeCell(doc, view, *roll, track);
    if (second.key < 0) {
      fail("no free second cell for mixed-context PSG sweep");
      return;
    }
    doc.addLanePoint(track, DOC_CC_VOICE, second.tick, context.cgbSlot);
    doc.addLanePoint(track, 0x07, second.tick, 64);
    doc.addLanePoint(track, 0x0A, second.tick, 64);
    doc.addNote(track, second.tick, uint8_t(second.key),
                uint32_t(second.duration), 64);

    const SongView::NoteId firstId{uint32_t(first.tick), uint8_t(first.key)};
    const SongView::NoteId secondId{uint32_t(second.tick), uint8_t(second.key)};
    const auto firstDetents = view.velocityAxisDetents(track, {firstId});
    const auto secondDetents = view.velocityAxisDetents(track, {secondId});
    const songview::VelocityAxis capturedAxis(velocityArea->height(),
                                              firstDetents);
    const int resizedHeight =
        std::max(savedSize.height() + 53, savedSize.height() * 2);
    const songview::VelocityAxis rebuiltAxis(resizedHeight, firstDetents);

    std::optional<uint8_t> sweepLevel;
    std::optional<uint8_t> expectedFirst;
    std::optional<uint8_t> expectedSecond;
    if (!firstDetents || !secondDetents ||
        capturedAxis.compatibleWith(secondDetents)) {
      fail("mixed-context PSG sweep fixture did not produce incompatible "
           "detent models");
    } else {
      for (std::size_t level = 0; level < firstDetents->levels.size();
           ++level) {
        const auto firstVelocity = view.velocityForLevel(
            track, firstId.tick, firstId.key, uint8_t(level));
        const auto secondCategorical = view.velocityForLevel(
            track, secondId.tick, secondId.key, uint8_t(level));
        const int y = qRound(capturedAxis.levelToY(int(level)));
        const uint8_t continuousVelocity = view.canonicalNoteVelocity(
            track, secondId.tick, secondId.key, capturedAxis.yToVelocity(y));
        const auto rebuiltFirst = view.velocityForLevel(
            track, firstId.tick, firstId.key, uint8_t(rebuiltAxis.yToLevel(y)));
        const uint8_t rebuiltSecond = view.canonicalNoteVelocity(
            track, secondId.tick, secondId.key, rebuiltAxis.yToVelocity(y));
        const bool resizeDiscriminates = firstVelocity && rebuiltFirst &&
                                         (*rebuiltFirst != *firstVelocity ||
                                          rebuiltSecond != continuousVelocity);
        if (firstVelocity && secondCategorical && *firstVelocity != 64 &&
            *secondCategorical != 64 &&
            continuousVelocity != *secondCategorical && resizeDiscriminates) {
          sweepLevel = uint8_t(level);
          expectedFirst = firstVelocity;
          expectedSecond = continuousVelocity;
          break;
        }
      }
    }
    if (!sweepLevel) {
      fail("mixed-context PSG sweep had no discriminating hardware level");
      return;
    }

    view.setSelection({firstId});
    (void)velocityArea->grab();
    QCoreApplication::processEvents();
    const QString categoricalDescription =
        velocityArea->accessibleDescription();
    if (!categoricalDescription.contains(QStringLiteral("16 levels"))) {
      fail("mixed-context PSG sweep did not start on the categorical axis");
    }

    const qreal dpr = roll->devicePixelRatioF();
    const int firstX =
        qRound(view.displayX(double(first.tick), songview::kGutterW, dpr));
    const int secondX =
        qRound(view.displayX(double(second.tick), songview::kGutterW, dpr));
    const int sweepY = qRound(capturedAxis.levelToY(int(*sweepLevel)));
    const QPoint start(firstX - 7, sweepY);
    const QPoint midpoint((firstX + secondX) / 2, sweepY);
    const QPoint end(secondX + 7, sweepY);
    if (start.x() < songview::kGutterW || secondX <= firstX) {
      fail("mixed-context PSG sweep fixture lacked an ordered blank lead-in");
      return;
    }

    enum class Path { Single, Segmented, Resized };
    std::optional<std::pair<uint8_t, uint8_t>> firstRun;
    const auto runSweep = [&](Path path) {
      const int sweepIndex = doc.undoStack()->index();
      sendMouse(velocityArea, QEvent::MouseButtonPress, start, Qt::LeftButton,
                Qt::LeftButton);
      if (velocityArea->accessibleDescription() != categoricalDescription) {
        fail("mixed-context PSG sweep changed its latched axis");
      }

      if (path == Path::Resized) {
        velocityArea->setMinimumHeight(resizedHeight);
        velocityArea->setMaximumHeight(resizedHeight);
        QCoreApplication::processEvents();
        if (velocityArea->height() != resizedHeight)
          fail("mixed-context PSG resize fixture did not resize the velocity "
               "area");
        if (velocityArea->accessibleDescription() != categoricalDescription) {
          fail("mixed-context PSG resize changed its latched accessibility "
               "axis");
        }
      } else if (path == Path::Segmented) {
        sendMouse(velocityArea, QEvent::MouseMove, midpoint, Qt::NoButton,
                  Qt::LeftButton);
        (void)velocityArea->grab();
        QCoreApplication::processEvents();
        if (velocityArea->accessibleDescription() != categoricalDescription) {
          fail("mixed-context PSG sweep changed its latched axis");
        }
      }

      sendMouse(velocityArea, QEvent::MouseMove, end, Qt::NoButton,
                Qt::LeftButton);
      (void)velocityArea->grab();
      QCoreApplication::processEvents();
      if (velocityArea->accessibleDescription() != categoricalDescription) {
        fail("mixed-context PSG sweep changed its latched axis after crossing "
             "the incompatible note");
      }
      sendMouse(velocityArea, QEvent::MouseButtonRelease, end, Qt::LeftButton,
                Qt::NoButton);

      DocNote firstCommitted;
      DocNote secondCommitted;
      const bool foundFirst =
          doc.findNote(track, firstId.tick, firstId.key, &firstCommitted);
      const bool foundSecond =
          doc.findNote(track, secondId.tick, secondId.key, &secondCommitted);
      if (doc.undoStack()->index() != sweepIndex + 1)
        fail("mixed-context PSG sweep was not exactly one batch undo");
      if (!foundFirst || firstCommitted.velocity != *expectedFirst) {
        fail("mixed-context PSG sweep missed the first note's targeted "
             "hardware level");
      }
      if (!foundSecond || secondCommitted.velocity != *expectedSecond) {
        fail("mixed-context PSG sweep did not use continuous mapping for the "
             "incompatible note");
      }

      if (foundFirst && foundSecond) {
        const auto committed =
            std::make_pair(firstCommitted.velocity, secondCommitted.velocity);
        if (firstRun && committed != *firstRun) {
          fail(path == Path::Resized ? "mixed-context PSG sweep depended on a "
                                       "resize during the gesture"
                                     : "mixed-context PSG sweep depended on "
                                       "move-event segmentation");
        }
        if (!firstRun)
          firstRun = committed;
      }

      undoTo(doc, sweepIndex);
      DocNote firstRestored;
      DocNote secondRestored;
      if (!doc.findNote(track, firstId.tick, firstId.key, &firstRestored) ||
          !doc.findNote(track, secondId.tick, secondId.key, &secondRestored) ||
          firstRestored.velocity != 64 || secondRestored.velocity != 64) {
        fail("undo did not restore both mixed-context PSG notes");
      }

      if (path == Path::Resized) {
        velocityArea->setMinimumHeight(savedMinimumHeight);
        velocityArea->setMaximumHeight(savedMaximumHeight);
        velocityArea->resize(savedSize);
        QCoreApplication::processEvents();
      }
    };

    runSweep(Path::Single);
    runSweep(Path::Segmented);
    runSweep(Path::Resized);
  };

  runFixture();
  undoTo(doc, fixtureIndex);
  view.setSelection(savedSelection);
  velocityArea->setMinimumHeight(savedMinimumHeight);
  velocityArea->setMaximumHeight(savedMaximumHeight);
  velocityArea->resize(savedSize);
  QCoreApplication::processEvents();
  return failures;
}
