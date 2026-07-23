#include "liveshortcuts.hpp"

#include <QAction>
#include <QCoreApplication>
#include <QList>
#include <QtGlobal>

#include <cstddef>

namespace {

using live_shortcuts::Command;
using live_shortcuts::Descriptor;
using live_shortcuts::ShortcutKey;

constexpr std::size_t kCommandCount = 35;

constexpr ShortcutKey shortcutKey(Qt::KeyboardModifiers modifiers,
                                  Qt::Key key) {
  return {modifiers, key};
}

constexpr std::array<ShortcutKey, 3> shortcutKeys() { return {}; }

constexpr std::array<ShortcutKey, 3> shortcutKeys(ShortcutKey first) {
  return {first, {}, {}};
}

constexpr std::array<ShortcutKey, 3> shortcutKeys(ShortcutKey first,
                                                  ShortcutKey second) {
  return {first, second, {}};
}

constexpr std::array<ShortcutKey, 3>
shortcutKeys(ShortcutKey first, ShortcutKey second, ShortcutKey third) {
  return {first, second, third};
}

const std::array<Descriptor, kCommandCount> kDescriptors = {{
    {Command::Undo, "undo", "&Undo", "MainWindow", QKeySequence::Undo,
     shortcutKeys(), 0, Qt::WindowShortcut},
    {Command::Redo, "redo", "&Redo", "MainWindow", QKeySequence::UnknownKey,
     shortcutKeys(
         shortcutKey(Qt::ControlModifier | Qt::ShiftModifier, Qt::Key_Z)),
     1, Qt::WindowShortcut},
    {Command::Cut, "cut", "Cut", "SongView", QKeySequence::Cut, shortcutKeys(),
     0, Qt::WidgetShortcut},
    {Command::Copy, "copy", "Copy", "SongView", QKeySequence::Copy,
     shortcutKeys(), 0, Qt::WidgetShortcut},
    {Command::Paste, "paste", "Paste", "SongView", QKeySequence::Paste,
     shortcutKeys(), 0, Qt::WidgetShortcut},
    {Command::SelectAll, "select_all", "Select All", "SongView",
     QKeySequence::SelectAll, shortcutKeys(), 0, Qt::WidgetShortcut},
    {Command::Delete, "delete", "Delete", "SongView", QKeySequence::UnknownKey,
     shortcutKeys(shortcutKey(Qt::NoModifier, Qt::Key_Delete),
                  shortcutKey(Qt::NoModifier, Qt::Key_Backspace)),
     2, Qt::WidgetShortcut},
    {Command::Duplicate, "duplicate", "Duplicate", "SongView",
     QKeySequence::UnknownKey,
     shortcutKeys(shortcutKey(Qt::ControlModifier, Qt::Key_D)), 1,
     Qt::WidgetShortcut},
    {Command::Split, "split", "Split", "SongView", QKeySequence::UnknownKey,
     shortcutKeys(shortcutKey(Qt::ControlModifier, Qt::Key_E)), 1,
     Qt::WidgetShortcut},
    {Command::Join, "join", "Join", "SongView", QKeySequence::UnknownKey,
     shortcutKeys(shortcutKey(Qt::ControlModifier, Qt::Key_J)), 1,
     Qt::WidgetShortcut},
    {Command::PlayPause, "play_pause", "Play/Pause", "MainWindow",
     QKeySequence::UnknownKey,
     shortcutKeys(shortcutKey(Qt::NoModifier, Qt::Key_Space)), 1,
     Qt::WindowShortcut},
    {Command::ContinuePlayback, "continue_playback", "Continue Playback",
     "MainWindow", QKeySequence::UnknownKey,
     shortcutKeys(shortcutKey(Qt::ShiftModifier, Qt::Key_Space)), 1,
     Qt::WindowShortcut},
    {Command::GoToStart, "go_to_start", "Go to Start", "MainWindow",
     QKeySequence::UnknownKey,
     shortcutKeys(shortcutKey(Qt::NoModifier, Qt::Key_Home)), 1,
     Qt::WindowShortcut},
    {Command::Loop, "loop", "Loop", "MainWindow", QKeySequence::UnknownKey,
     shortcutKeys(shortcutKey(Qt::ControlModifier, Qt::Key_L)), 1,
     Qt::WindowShortcut},
    {Command::FollowPlayback, "follow_playback", "Follow Playback",
     "MainWindow", QKeySequence::UnknownKey,
     shortcutKeys(shortcutKey(Qt::AltModifier | Qt::ShiftModifier, Qt::Key_F)),
     1, Qt::WindowShortcut},
    {Command::SelectLoopContents, "select_loop_contents",
     "Select Loop Contents", "SongView", QKeySequence::UnknownKey,
     shortcutKeys(
         shortcutKey(Qt::ControlModifier | Qt::ShiftModifier, Qt::Key_L)),
     1, Qt::WidgetWithChildrenShortcut},
    {Command::MoveNotesLeft, "move_notes_left", "Move Notes Left", "SongView",
     QKeySequence::UnknownKey,
     shortcutKeys(shortcutKey(Qt::NoModifier, Qt::Key_Left)), 1,
     Qt::WidgetShortcut},
    {Command::MoveNotesRight, "move_notes_right", "Move Notes Right",
     "SongView", QKeySequence::UnknownKey,
     shortcutKeys(shortcutKey(Qt::NoModifier, Qt::Key_Right)), 1,
     Qt::WidgetShortcut},
    {Command::TransposeNotesUp, "transpose_notes_up", "Transpose Notes Up",
     "SongView", QKeySequence::UnknownKey,
     shortcutKeys(shortcutKey(Qt::NoModifier, Qt::Key_Up)), 1,
     Qt::WidgetShortcut},
    {Command::TransposeNotesDown, "transpose_notes_down",
     "Transpose Notes Down", "SongView", QKeySequence::UnknownKey,
     shortcutKeys(shortcutKey(Qt::NoModifier, Qt::Key_Down)), 1,
     Qt::WidgetShortcut},
    {Command::TransposeNotesUpOneOctave, "transpose_notes_up_one_octave",
     "Transpose Notes Up One Octave", "SongView", QKeySequence::UnknownKey,
     shortcutKeys(shortcutKey(Qt::ShiftModifier, Qt::Key_Up)), 1,
     Qt::WidgetShortcut},
    {Command::TransposeNotesDownOneOctave, "transpose_notes_down_one_octave",
     "Transpose Notes Down One Octave", "SongView", QKeySequence::UnknownKey,
     shortcutKeys(shortcutKey(Qt::ShiftModifier, Qt::Key_Down)), 1,
     Qt::WidgetShortcut},
    {Command::ShortenNotes, "shorten_notes", "Shorten Notes", "SongView",
     QKeySequence::UnknownKey,
     shortcutKeys(shortcutKey(Qt::ShiftModifier, Qt::Key_Left)), 1,
     Qt::WidgetShortcut},
    {Command::LengthenNotes, "lengthen_notes", "Lengthen Notes", "SongView",
     QKeySequence::UnknownKey,
     shortcutKeys(shortcutKey(Qt::ShiftModifier, Qt::Key_Right)), 1,
     Qt::WidgetShortcut},
    {Command::DecreaseVelocity, "decrease_velocity", "Decrease Velocity",
     "SongView", QKeySequence::UnknownKey,
     shortcutKeys(shortcutKey(Qt::ControlModifier, Qt::Key_Down)), 1,
     Qt::WidgetShortcut},
    {Command::IncreaseVelocity, "increase_velocity", "Increase Velocity",
     "SongView", QKeySequence::UnknownKey,
     shortcutKeys(shortcutKey(Qt::ControlModifier, Qt::Key_Up)), 1,
     Qt::WidgetShortcut},
    {Command::NarrowGrid, "narrow_grid", "Narrow Grid", "SongView",
     QKeySequence::UnknownKey,
     shortcutKeys(shortcutKey(Qt::ControlModifier, Qt::Key_1)), 1,
     Qt::WidgetWithChildrenShortcut},
    {Command::WidenGrid, "widen_grid", "Widen Grid", "SongView",
     QKeySequence::UnknownKey,
     shortcutKeys(shortcutKey(Qt::ControlModifier, Qt::Key_2)), 1,
     Qt::WidgetWithChildrenShortcut},
    {Command::TripletGrid, "triplet_grid", "Triplet Grid", "SongView",
     QKeySequence::UnknownKey,
     shortcutKeys(shortcutKey(Qt::ControlModifier, Qt::Key_3)), 1,
     Qt::WidgetWithChildrenShortcut},
    {Command::ToggleSnapToGrid, "toggle_snap_to_grid", "Toggle Snap to Grid",
     "SongView", QKeySequence::UnknownKey,
     shortcutKeys(shortcutKey(Qt::ControlModifier, Qt::Key_4)), 1,
     Qt::WidgetWithChildrenShortcut},
    {Command::FixedAdaptiveGrid, "fixed_adaptive_grid", "Fixed/Adaptive Grid",
     "SongView", QKeySequence::UnknownKey,
     shortcutKeys(shortcutKey(Qt::ControlModifier, Qt::Key_5)), 1,
     Qt::WidgetWithChildrenShortcut},
    {Command::ZoomToSelection, "zoom_to_selection", "Zoom to Selection",
     "SongView", QKeySequence::UnknownKey,
     shortcutKeys(shortcutKey(Qt::NoModifier, Qt::Key_Z)), 1,
     Qt::WidgetShortcut},
    {Command::ZoomToFullSong, "zoom_to_full_song", "Zoom to Full Song",
     "SongView", QKeySequence::UnknownKey,
     shortcutKeys(shortcutKey(Qt::NoModifier, Qt::Key_X)), 1,
     Qt::WidgetShortcut},
    {Command::ZoomIn, "zoom_in", "Zoom In", "SongView",
     QKeySequence::UnknownKey,
     shortcutKeys(shortcutKey(Qt::NoModifier, Qt::Key_Equal),
                  shortcutKey(Qt::NoModifier, Qt::Key_Plus),
                  shortcutKey(Qt::ShiftModifier, Qt::Key_Plus)),
     3, Qt::WidgetShortcut},
    {Command::ZoomOut, "zoom_out", "Zoom Out", "SongView",
     QKeySequence::UnknownKey,
     shortcutKeys(shortcutKey(Qt::NoModifier, Qt::Key_Minus)), 1,
     Qt::WidgetShortcut},
}};

QList<QKeySequence> shortcutSequences(const Descriptor &shortcut) {
  if (shortcut.standardKey != QKeySequence::UnknownKey)
    return {QKeySequence(shortcut.standardKey)};
  auto sequences = QList<QKeySequence>{};
  sequences.reserve(shortcut.keyCount);
  for (auto index = std::uint8_t{0}; index < shortcut.keyCount; ++index) {
    const auto &key = shortcut.keys[index];
    sequences.append(QKeySequence(QKeyCombination(key.modifiers, key.key)));
  }
  return sequences;
}

} // namespace

namespace live_shortcuts {

const std::array<Descriptor, 35> &descriptors() { return kDescriptors; }

const Descriptor &descriptor(Command command) {
  const auto index = static_cast<std::size_t>(command);
  Q_ASSERT(index < kDescriptors.size());
  return kDescriptors[index];
}

QString translatedLabel(Command command) {
  const auto &shortcut = descriptor(command);
  return QCoreApplication::translate(shortcut.translationContext,
                                     shortcut.label);
}

void configureAction(QAction &action, Command command) {
  const auto &shortcut = descriptor(command);
  action.setText(translatedLabel(command));
  action.setShortcuts(shortcutSequences(shortcut));
  action.setShortcutContext(shortcut.context);
  action.setProperty("liveShortcutId",
                     QString::fromLatin1(shortcut.shortcutId));
}

} // namespace live_shortcuts
