#pragma once

#include <QKeySequence>
#include <QString>

#include <array>
#include <cstdint>

class QAction;

namespace live_shortcuts {

enum class Command : std::uint8_t {
  Undo = 0,
  Redo = 1,
  Cut = 2,
  Copy = 3,
  Paste = 4,
  SelectAll = 5,
  Delete = 6,
  Duplicate = 7,
  Split = 8,
  Join = 9,
  PlayPause = 10,
  ContinuePlayback = 11,
  GoToStart = 12,
  Loop = 13,
  FollowPlayback = 14,
  SelectLoopContents = 15,
  MoveNotesLeft = 16,
  MoveNotesRight = 17,
  TransposeNotesUp = 18,
  TransposeNotesDown = 19,
  TransposeNotesUpOneOctave = 20,
  TransposeNotesDownOneOctave = 21,
  ShortenNotes = 22,
  LengthenNotes = 23,
  DecreaseVelocity = 24,
  IncreaseVelocity = 25,
  NarrowGrid = 26,
  WidenGrid = 27,
  TripletGrid = 28,
  ToggleSnapToGrid = 29,
  FixedAdaptiveGrid = 30,
  ZoomToSelection = 31,
  ZoomToFullSong = 32,
  ZoomIn = 33,
  ZoomOut = 34,
};

struct ShortcutKey {
  Qt::KeyboardModifiers modifiers;
  Qt::Key key;
};

struct Descriptor {
  Command command;
  const char *shortcutId;
  const char *label;
  const char *translationContext;
  QKeySequence::StandardKey standardKey;
  std::array<ShortcutKey, 3> keys;
  std::uint8_t keyCount;
  Qt::ShortcutContext context;
};

const std::array<Descriptor, 35> &descriptors();
const Descriptor &descriptor(Command command);
QString translatedLabel(Command command);
void configureAction(QAction &action, Command command);

} // namespace live_shortcuts
