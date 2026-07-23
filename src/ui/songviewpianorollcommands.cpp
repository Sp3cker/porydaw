#include "ui/songviewpianorollinternal.hpp"

#include <QAction>
#include <QApplication>
#include <QCoreApplication>
#include <QInputDialog>
#include <QKeyEvent>
#include <QMenu>
#include <QMouseEvent>
#include <QProxyStyle>
#include <QWidget>

#include <algorithm>
#include <climits>
#include <cmath>
#include <map>
#include <memory>
#include <utility>

#include "core/mid2agbtables.h"
#include "core/songdocument.h"
#include "liveshortcuts.hpp"
#include "ui/songview.h"

namespace songview {

namespace piano_roll_internal {

class NoteMenuStyle final : public QProxyStyle {
public:
  NoteMenuStyle() : QProxyStyle(QApplication::style()->name()) {}

  int styleHint(StyleHint hint, const QStyleOption *option,
                const QWidget *widget,
                QStyleHintReturn *returnData) const override {
    if (hint == SH_Menu_FlashTriggeredItem)
      return 0;
    return QProxyStyle::styleHint(hint, option, widget, returnData);
  }
};

struct NoteMenuActions {
  QAction *velocity;
  QAction *copy;
  QAction *cut;
  QAction *paste;
  QAction *duplicate;
  QAction *split;
  QAction *join;
  QAction *deleteNotes;
  QAction *selectAll;
  QAction *moveNotesLeft;
  QAction *moveNotesRight;
  QAction *transposeNotesUp;
  QAction *transposeNotesDown;
  QAction *transposeNotesUpOctave;
  QAction *transposeNotesDownOctave;
  QAction *shortenNotes;
  QAction *lengthenNotes;
  QAction *decreaseVelocity;
  QAction *increaseVelocity;
  QAction *zoomIn;
  QAction *zoomOut;
  QAction *zoomToSelection;
  QAction *zoomToFullSong;
};

class NoteContextMenu final : public QMenu {
public:
  NoteContextMenu(QWidget *parent, std::function<void(QPoint)> retargetMenu,
                  const NoteMenuActions &actions)
      : QMenu(parent), m_retargetMenu(std::move(retargetMenu)),
        m_velocityAction(actions.velocity) {
    auto *menuStyle = new NoteMenuStyle;
    menuStyle->setParent(this);
    setStyle(menuStyle);
    addAction(actions.velocity);
    addSeparator();
    addAction(actions.copy);
    addAction(actions.cut);
    addAction(actions.paste);
    addAction(actions.duplicate);
    addAction(actions.split);
    addAction(actions.join);
    addSeparator();
    addAction(actions.deleteNotes);
    addAction(actions.selectAll);
    addSeparator();
    auto *editMenu = addMenu(SongView::tr("Edit Notes"));
    editMenu->addAction(actions.moveNotesLeft);
    editMenu->addAction(actions.moveNotesRight);
    editMenu->addAction(actions.transposeNotesUp);
    editMenu->addAction(actions.transposeNotesDown);
    editMenu->addAction(actions.transposeNotesUpOctave);
    editMenu->addAction(actions.transposeNotesDownOctave);
    editMenu->addAction(actions.shortenNotes);
    editMenu->addAction(actions.lengthenNotes);
    editMenu->addAction(actions.decreaseVelocity);
    editMenu->addAction(actions.increaseVelocity);
    addSeparator();
    addAction(actions.zoomIn);
    addAction(actions.zoomOut);
    addAction(actions.zoomToSelection);
    addAction(actions.zoomToFullSong);
  }

  void showMenuAt(QPoint globalPosition, int velocity) {
    m_velocityAction->setText(SongView::tr("Set Velocity (%1)").arg(velocity));
    popup(globalPosition);
  }

protected:
  void mousePressEvent(QMouseEvent *event) override {
    if (event->button() == Qt::RightButton &&
        !rect().contains(event->position().toPoint())) {
      m_retargetMenu(event->globalPosition().toPoint());
      event->accept();
      return;
    }
    QMenu::mousePressEvent(event);
  }

private:
  std::function<void(QPoint)> m_retargetMenu;
  QAction *m_velocityAction = nullptr;
};

} // namespace piano_roll_internal

PianoRollCommands::~PianoRollCommands() = default;

PianoRollCommands::PianoRollCommands(QWidget *actionTarget, SongView *songView,
                                     std::function<void(QPoint)> retargetMenu,
                                     std::function<void(uint8_t)> latchVelocity)
    : m_actionTarget(actionTarget), m_songView(songView),
      m_latchVelocity(std::move(latchVelocity)) {
  auto *velocityAction = new QAction(m_actionTarget);
  QObject::connect(velocityAction, &QAction::triggered, this,
                   &PianoRollCommands::editVelocity);
  auto *copyAction = createShortcutAction(
      live_shortcuts::Command::Copy, &PianoRollCommands::copyActiveSelection);
  auto *cutAction = createShortcutAction(
      live_shortcuts::Command::Cut, &PianoRollCommands::cutActiveSelection);
  auto *pasteAction = createShortcutAction(
      live_shortcuts::Command::Paste, &PianoRollCommands::pasteActiveSelection);
  auto *duplicateAction =
      createShortcutAction(live_shortcuts::Command::Duplicate,
                           &PianoRollCommands::duplicateSelection);
  auto *splitAction = createShortcutAction(live_shortcuts::Command::Split,
                                           &PianoRollCommands::splitNotes);
  auto *joinAction = createShortcutAction(live_shortcuts::Command::Join,
                                          &PianoRollCommands::joinSelection);
  auto *deleteAction =
      createShortcutAction(live_shortcuts::Command::Delete,
                           &PianoRollCommands::deleteActiveSelection);
  auto *selectAllAction = createShortcutAction(
      live_shortcuts::Command::SelectAll, &PianoRollCommands::selectAllNotes);
  auto *moveNotesLeftAction =
      createShortcutAction(live_shortcuts::Command::MoveNotesLeft,
                           &PianoRollCommands::moveNotesLeft);
  auto *moveNotesRightAction =
      createShortcutAction(live_shortcuts::Command::MoveNotesRight,
                           &PianoRollCommands::moveNotesRight);
  auto *transposeNotesUpAction =
      createShortcutAction(live_shortcuts::Command::TransposeNotesUp,
                           &PianoRollCommands::transposeNotesUp);
  auto *transposeNotesDownAction =
      createShortcutAction(live_shortcuts::Command::TransposeNotesDown,
                           &PianoRollCommands::transposeNotesDown);
  auto *transposeNotesUpOctaveAction =
      createShortcutAction(live_shortcuts::Command::TransposeNotesUpOneOctave,
                           &PianoRollCommands::transposeNotesUpOctave);
  auto *transposeNotesDownOctaveAction =
      createShortcutAction(live_shortcuts::Command::TransposeNotesDownOneOctave,
                           &PianoRollCommands::transposeNotesDownOctave);
  auto *shortenNotesAction = createShortcutAction(
      live_shortcuts::Command::ShortenNotes, &PianoRollCommands::shortenNotes);
  auto *lengthenNotesAction =
      createShortcutAction(live_shortcuts::Command::LengthenNotes,
                           &PianoRollCommands::lengthenNotes);
  auto *decreaseVelocityAction =
      createShortcutAction(live_shortcuts::Command::DecreaseVelocity,
                           &PianoRollCommands::decreaseVelocity);
  auto *increaseVelocityAction =
      createShortcutAction(live_shortcuts::Command::IncreaseVelocity,
                           &PianoRollCommands::increaseVelocity);
  auto *zoomInAction = createShortcutAction(live_shortcuts::Command::ZoomIn,
                                            &PianoRollCommands::zoomIn);
  auto *zoomOutAction = createShortcutAction(live_shortcuts::Command::ZoomOut,
                                             &PianoRollCommands::zoomOut);
  auto *zoomToSelectionAction =
      createShortcutAction(live_shortcuts::Command::ZoomToSelection,
                           &PianoRollCommands::zoomToSelection);
  auto *zoomToFullSongAction =
      createShortcutAction(live_shortcuts::Command::ZoomToFullSong,
                           &PianoRollCommands::zoomToFullSong);
  m_noteMenu = std::make_unique<piano_roll_internal::NoteContextMenu>(
      m_actionTarget, std::move(retargetMenu),
      piano_roll_internal::NoteMenuActions{velocityAction,
                                           copyAction,
                                           cutAction,
                                           pasteAction,
                                           duplicateAction,
                                           splitAction,
                                           joinAction,
                                           deleteAction,
                                           selectAllAction,
                                           moveNotesLeftAction,
                                           moveNotesRightAction,
                                           transposeNotesUpAction,
                                           transposeNotesDownAction,
                                           transposeNotesUpOctaveAction,
                                           transposeNotesDownOctaveAction,
                                           shortenNotesAction,
                                           lengthenNotesAction,
                                           decreaseVelocityAction,
                                           increaseVelocityAction,
                                           zoomInAction,
                                           zoomOutAction,
                                           zoomToSelectionAction,
                                           zoomToFullSongAction});
  m_actionTarget->installEventFilter(this);
}

QAction *
PianoRollCommands::createShortcutAction(live_shortcuts::Command command,
                                        void (PianoRollCommands::*handler)()) {
  auto *action = new QAction(m_actionTarget);
  live_shortcuts::configureAction(*action, command);
  m_actionTarget->addAction(action);
  QObject::connect(action, &QAction::triggered, this, handler);
  return action;
}

bool PianoRollCommands::eventFilter(QObject *watched, QEvent *event) {
  if (watched == m_actionTarget && m_shortcutAudition &&
      event->type() == QEvent::KeyRelease) {
    const auto *keyEvent = static_cast<QKeyEvent *>(event);
    if (!keyEvent->isAutoRepeat()) {
      auditionTransposedNote(0, 0);
      m_shortcutAudition = false;
    }
  }
  return QObject::eventFilter(watched, event);
}

void PianoRollCommands::auditionTransposedNote(int key, int velocity) {
  PianoRollShortcutAuditionEvent event(key, velocity);
  QCoreApplication::sendEvent(m_actionTarget, &event);
}

void PianoRollCommands::showMenuAt(QPoint globalPosition) {
  const std::vector<DocNote> notes = selectedNotes();
  if (!notes.empty())
    m_noteMenu->showMenuAt(globalPosition, notes.front().velocity);
}

std::vector<DocNote> PianoRollCommands::selectedNotes() const {
  std::vector<DocNote> notes;
  SongDocument *document = m_songView->document();
  if (!document)
    return notes;
  for (const SongView::NoteId &id : m_songView->selection()) {
    DocNote note;
    if (document->findNote(m_songView->selectedTrack(), id.tick, id.key, &note))
      notes.push_back(note);
  }
  return notes;
}

void PianoRollCommands::copyNotes(const std::vector<DocNote> &notes) {
  uint64_t base = UINT64_MAX;
  for (const DocNote &note : notes)
    base = std::min(base, note.tick);
  SongView::Clip clip;
  SongView::ClipTrack track{m_songView->selectedTrack(), {}};
  for (const DocNote &note : notes)
    track.notes.push_back({uint32_t(note.tick - base), note.key,
                           note.duration
                               ? note.duration
                               : uint32_t(m_songView->gridTicksAt(note.tick)),
                           note.velocity});
  clip.tracks.push_back(std::move(track));
  m_songView->clipboard() = std::move(clip);
  m_songView->announce(
      SongView::tr("Copied %n note(s)", nullptr, int(notes.size())));
}

void PianoRollCommands::pasteAtEditCursor() {
  SongDocument *document = m_songView->document();
  const SongView::Clip &clip = m_songView->clipboard();
  if (!document || clip.span != 0 || clip.tracks.empty() ||
      clip.tracks.front().notes.empty())
    return;
  const uint64_t base =
      m_songView->snapTick(double(m_songView->editCursorTick()));
  std::vector<SongDocument::NewNote> notes;
  std::vector<SongView::NoteId> ids;
  uint64_t end = base;
  for (const SongView::ClipNote &clipNote : clip.tracks.front().notes) {
    const uint64_t tick = base + clipNote.relTick;
    notes.push_back({tick, clipNote.key, clipNote.duration, clipNote.velocity});
    ids.push_back({uint32_t(tick), clipNote.key});
    end = std::max(end, tick + clipNote.duration);
  }
  document->addNotes(m_songView->selectedTrack(), notes);
  m_songView->setSelection(std::move(ids));
  m_songView->commitEditCursor(end);
  m_songView->ensureTickVisible(base);
  m_songView->announce(
      SongView::tr("Pasted %n note(s)", nullptr, int(notes.size())));
}

void PianoRollCommands::copyActiveSelection() {
  SongDocument *document = m_songView->document();
  if (!document)
    return;
  if (m_songView->timeSelection().active()) {
    m_songView->copyTimeSelection();
    return;
  }
  const std::vector<DocNote> notes = selectedNotes();
  if (!notes.empty())
    copyNotes(notes);
}

void PianoRollCommands::cutActiveSelection() {
  SongDocument *document = m_songView->document();
  if (!document)
    return;
  if (m_songView->timeSelection().active()) {
    m_songView->copyTimeSelection();
    m_songView->deleteTimeSelection();
    return;
  }
  const std::vector<DocNote> notes = selectedNotes();
  if (notes.empty())
    return;
  copyNotes(notes);
  document->deleteNotes(notes);
  m_songView->clearSelection();
}

void PianoRollCommands::pasteActiveSelection() {
  if (!m_songView->document())
    return;
  const SongView::Clip &clip = m_songView->clipboard();
  if (clip.span > 0 && !clip.empty())
    m_songView->pasteRangeAtEditCursor();
  else
    pasteAtEditCursor();
}

void PianoRollCommands::deleteActiveSelection() {
  SongDocument *document = m_songView->document();
  if (!document)
    return;
  if (m_songView->timeSelection().active()) {
    m_songView->deleteTimeSelection();
    return;
  }
  const std::vector<DocNote> notes = selectedNotes();
  if (notes.empty())
    return;
  document->deleteNotes(notes);
  m_songView->clearSelection();
}
void PianoRollCommands::selectAllNotes() {
  if (!m_songView->document())
    return;
  std::vector<SongView::NoteId> ids;
  for (const ViewNote &note : m_songView->model().notes) {
    if (note.track == m_songView->selectedTrack())
      ids.push_back({note.startTick, note.key});
  }
  m_songView->setSelection(std::move(ids));
}

void PianoRollCommands::editVelocity() {
  SongDocument *document = m_songView->document();
  if (!document || m_songView->timeSelection().active())
    return;
  const std::vector<DocNote> notes = selectedNotes();
  if (notes.empty())
    return;
  bool accepted = false;
  const int velocity = QInputDialog::getInt(
      m_actionTarget, SongView::tr("Note velocity"),
      SongView::tr("Velocity (1-127, plays as %1-127 in steps of 4):")
          .arg(mid2agbEffectiveVelocity(1)),
      notes.front().velocity, 1, 127, 1, &accepted);
  if (!accepted)
    return;
  document->setNotesVelocity(notes, uint8_t(velocity));
  m_latchVelocity(uint8_t(velocity));
}

void PianoRollCommands::moveNotesLeft() { moveSelection(false); }

void PianoRollCommands::moveNotesRight() { moveSelection(true); }

void PianoRollCommands::moveSelection(bool right) {
  if (m_songView->timeSelection().active())
    m_songView->nudgeTimeSelection(right);
  else
    nudgeSelection(right);
}

void PianoRollCommands::nudgeSelection(bool right) {
  SongDocument *document = m_songView->document();
  const std::vector<DocNote> notes = selectedNotes();
  if (!document || notes.empty())
    return;
  uint64_t anchor = UINT64_MAX;
  for (const DocNote &note : notes)
    anchor = std::min(anchor, note.tick);
  const uint64_t snapped = right
                               ? m_songView->snapTickUp(double(anchor) + 1.0)
                               : m_songView->snapTickDown(double(anchor) - 1.0);
  const int64_t deltaTick = int64_t(snapped) - int64_t(anchor);
  if (deltaTick == 0)
    return;
  document->moveNotes(notes, deltaTick, 0, /*mergeable=*/true);
  std::vector<SongView::NoteId> ids;
  for (const DocNote &note : notes)
    ids.push_back({uint32_t(int64_t(note.tick) + deltaTick), note.key});
  m_songView->setSelection(std::move(ids));
  uint64_t low = UINT64_MAX;
  uint64_t high = 0;
  for (const DocNote &note : notes) {
    const uint64_t tick = uint64_t(int64_t(note.tick) + deltaTick);
    low = std::min(low, tick);
    high = std::max(high, tick + note.duration);
  }
  m_songView->ensureRangeVisible(low, high, right);
  m_actionTarget->update();
}

void PianoRollCommands::transposeNotesUp() { transposeSelectionBy(1); }

void PianoRollCommands::transposeNotesDown() { transposeSelectionBy(-1); }

void PianoRollCommands::transposeNotesUpOctave() { transposeSelectionBy(12); }

void PianoRollCommands::transposeNotesDownOctave() {
  transposeSelectionBy(-12);
}

void PianoRollCommands::transposeSelectionBy(int semitones) {
  if (m_songView->timeSelection().active())
    m_songView->transposeTimeSelection(semitones);
  else
    transposeSelection(semitones);
}

void PianoRollCommands::transposeSelection(int semitones) {
  SongDocument *document = m_songView->document();
  const std::vector<DocNote> notes = selectedNotes();
  if (!document || notes.empty())
    return;
  for (const DocNote &note : notes) {
    const int key = int(note.key) + semitones;
    if (key < 0 || key > 127)
      return;
  }
  document->moveNotes(notes, 0, semitones, /*mergeable=*/true);
  std::vector<SongView::NoteId> ids;
  for (const DocNote &note : notes)
    ids.push_back({uint32_t(note.tick), uint8_t(int(note.key) + semitones)});
  m_songView->setSelection(std::move(ids));
  int edge = int(notes.front().key) + semitones;
  for (const DocNote &note : notes) {
    const int key = int(note.key) + semitones;
    edge = semitones > 0 ? std::max(edge, key) : std::min(edge, key);
  }
  m_songView->ensureKeyVisible(edge);
  m_shortcutAudition = true;
  auditionTransposedNote(int(notes.front().key) + semitones,
                         notes.front().velocity);
  m_actionTarget->update();
}

void PianoRollCommands::shortenNotes() { resizeSelection(false); }

void PianoRollCommands::lengthenNotes() { resizeSelection(true); }

void PianoRollCommands::resizeSelection(bool lengthen) {
  if (m_songView->timeSelection().active())
    m_songView->resizeTimeSelectionNotes(lengthen);
  else
    resizeSelectedNotes(lengthen);
}

void PianoRollCommands::resizeSelectedNotes(bool lengthen) {
  SongDocument *document = m_songView->document();
  const std::vector<DocNote> notes = selectedNotes();
  if (!document || notes.empty())
    return;
  uint64_t anchor = UINT64_MAX;
  for (const DocNote &note : notes)
    anchor = std::min(anchor, note.tick);
  const int64_t step = int64_t(m_songView->gridTicksAt(anchor));
  document->resizeNotes(notes, lengthen ? step : -step);
}

void PianoRollCommands::decreaseVelocity() { nudgeVelocity(-1); }

void PianoRollCommands::increaseVelocity() { nudgeVelocity(1); }

void PianoRollCommands::nudgeVelocity(int delta) {
  if (m_songView->timeSelection().active())
    m_songView->nudgeTimeSelectionVelocity(delta);
  else
    nudgeSelectedVelocity(delta);
}

void PianoRollCommands::nudgeSelectedVelocity(int delta) {
  SongDocument *document = m_songView->document();
  const std::vector<DocNote> notes = selectedNotes();
  if (!document || notes.empty())
    return;
  document->nudgeNotesVelocity(notes, delta);
  m_latchVelocity(
      uint8_t(std::clamp(int(notes.front().velocity) + delta, 1, 127)));
}

void PianoRollCommands::zoomIn() { zoomBy(1.25); }

void PianoRollCommands::zoomOut() { zoomBy(0.8); }

void PianoRollCommands::zoomBy(double factor) {
  if (!m_songView->document())
    return;
  m_songView->zoomAroundContentX(
      factor, std::max(0, m_actionTarget->width() - kKeyboardW) / 2);
}

void PianoRollCommands::zoomToFullSong() {
  if (m_songView->document())
    m_songView->zoomToFullSong();
}

void PianoRollCommands::splitNotes() {
  SongDocument *document = m_songView->document();
  if (!document)
    return;
  const std::vector<DocNote> selected = selectedNotes();
  const auto isSelected = [&](const DocNote &note) {
    return std::any_of(
        selected.begin(), selected.end(), [&](const DocNote &candidate) {
          return candidate.tick == note.tick && candidate.key == note.key;
        });
  };
  const auto nextGridTick = [&](uint64_t tick) {
    const SongView::GridSeg segment = m_songView->gridSegAt(tick);
    const uint64_t grid = std::max<uint64_t>(1, m_songView->gridTicksAt(tick));
    const uint64_t next =
        segment.start + ((tick - segment.start) / grid + 1) * grid;
    return std::min(next, segment.next);
  };
  std::vector<DocNote> notesToRemove;
  std::vector<SongDocument::NewNote> replacementNotes;
  std::vector<SongView::NoteId> selection = m_songView->selection();
  int splitCount = 0;
  for (const DocNote &note : selected) {
    if (note.unterminated())
      continue;
    const uint64_t end = note.tick + note.duration;
    uint64_t boundary = nextGridTick(note.tick);
    if (boundary <= note.tick || boundary >= end)
      continue;
    notesToRemove.push_back(note);
    const SongView::NoteId oldId{uint32_t(note.tick), note.key};
    selection.erase(std::remove(selection.begin(), selection.end(), oldId),
                    selection.end());
    uint64_t partTick = note.tick;
    while (boundary > partTick && boundary < end) {
      replacementNotes.push_back(
          {partTick, note.key, uint32_t(boundary - partTick), note.velocity});
      selection.push_back({uint32_t(partTick), note.key});
      partTick = boundary;
      boundary = nextGridTick(partTick);
      splitCount++;
    }
    replacementNotes.push_back(
        {partTick, note.key, uint32_t(end - partTick), note.velocity});
    selection.push_back({uint32_t(partTick), note.key});
  }
  const uint64_t playheadTick =
      uint64_t(std::max(0.0, std::round(m_songView->playheadTick())));
  for (const DocNote &note :
       document->notesForTrack(m_songView->selectedTrack())) {
    const uint64_t end = note.tick + note.duration;
    if (note.unterminated() || isSelected(note) || playheadTick <= note.tick ||
        playheadTick >= end)
      continue;
    notesToRemove.push_back(note);
    replacementNotes.push_back({note.tick, note.key,
                                uint32_t(playheadTick - note.tick),
                                note.velocity});
    replacementNotes.push_back(
        {playheadTick, note.key, uint32_t(end - playheadTick), note.velocity});
  }
  if (notesToRemove.empty())
    return;
  const int sourceCount = int(notesToRemove.size());
  SongDocument::RangeEdit rangeEdit;
  rangeEdit.removeNotes = std::move(notesToRemove);
  SongDocument::RangeEdit::TrackNotes replacementNotesByTrack{
      m_songView->selectedTrack(), std::move(replacementNotes)};
  rangeEdit.addNotes.push_back(std::move(replacementNotesByTrack));
  document->applyRangeEdit(
      SongDocument::tr("edit %n note(s)", nullptr, sourceCount), rangeEdit);
  m_songView->setSelection(std::move(selection));
  m_songView->announce(SongView::tr("Split %n note(s)", nullptr, splitCount));
}

void PianoRollCommands::joinSelection() {
  SongDocument *document = m_songView->document();
  std::vector<DocNote> notesToRemove = selectedNotes();
  if (!document || notesToRemove.size() < 2)
    return;
  std::map<uint8_t, std::vector<DocNote>> byKey;
  for (const DocNote &note : notesToRemove)
    byKey[note.key].push_back(note);
  std::vector<SongDocument::NewNote> replacementNotes;
  std::vector<SongView::NoteId> selection;
  bool joined = false;
  for (auto &[key, group] : byKey) {
    std::sort(
        group.begin(), group.end(),
        [](const DocNote &a, const DocNote &b) { return a.tick < b.tick; });
    const bool canJoin =
        group.size() > 1 &&
        std::none_of(group.begin(), group.end(),
                     [](const DocNote &note) { return note.unterminated(); });
    if (!canJoin) {
      for (const DocNote &note : group) {
        replacementNotes.push_back(
            {note.tick, note.key, note.duration, note.velocity});
        selection.push_back({uint32_t(note.tick), note.key});
      }
      continue;
    }
    const uint64_t start = group.front().tick;
    uint64_t end = start;
    for (const DocNote &note : group)
      end = std::max(end, note.tick + note.duration);
    replacementNotes.push_back(
        {start, key, uint32_t(std::min<uint64_t>(UINT32_MAX, end - start)),
         group.front().velocity});
    selection.push_back({uint32_t(start), key});
    joined = true;
  }
  if (!joined)
    return;
  const int sourceCount = int(notesToRemove.size());
  const int replacementCount = int(replacementNotes.size());
  SongDocument::RangeEdit rangeEdit;
  rangeEdit.removeNotes = std::move(notesToRemove);
  SongDocument::RangeEdit::TrackNotes replacementNotesByTrack{
      m_songView->selectedTrack(), std::move(replacementNotes)};
  rangeEdit.addNotes.push_back(std::move(replacementNotesByTrack));
  document->applyRangeEdit(
      SongDocument::tr("edit %n note(s)", nullptr, sourceCount), rangeEdit);
  m_songView->setSelection(std::move(selection));
  m_songView->announce(SongView::tr("Joined %n note(s)", nullptr,
                                    sourceCount - replacementCount));
}

void PianoRollCommands::duplicateSelection() {
  if (!m_songView->document())
    return;
  if (m_songView->timeSelection().active()) {
    const uint64_t destination = m_songView->timeSelection().endTick;
    m_songView->copyTimeSelection();
    m_songView->commitEditCursor(destination);
    m_songView->pasteRangeAtEditCursor();
    return;
  }
  SongDocument *document = m_songView->document();
  const std::vector<DocNote> notes = selectedNotes();
  if (!document || notes.empty())
    return;
  uint64_t start = UINT64_MAX;
  uint64_t end = 0;
  for (const DocNote &note : notes) {
    start = std::min(start, note.tick);
    const uint32_t duration =
        note.duration ? note.duration
                      : uint32_t(m_songView->gridTicksAt(note.tick));
    end = std::max(end, note.tick + duration);
  }
  const uint64_t span = std::max<uint64_t>(1, end - start);
  std::vector<SongDocument::NewNote> duplicate;
  duplicate.reserve(notes.size());
  std::vector<SongView::NoteId> selection;
  selection.reserve(notes.size());
  for (const DocNote &note : notes) {
    const uint64_t tick = note.tick + span;
    const uint32_t duration =
        note.duration ? note.duration
                      : uint32_t(m_songView->gridTicksAt(note.tick));
    duplicate.push_back({tick, note.key, duration, note.velocity});
    selection.push_back({uint32_t(tick), note.key});
  }
  document->addNotes(m_songView->selectedTrack(), duplicate);
  m_songView->setSelection(std::move(selection));
  m_songView->ensureRangeVisible(start + span, end + span, true);
  m_songView->announce(
      SongView::tr("Duplicated %n note(s)", nullptr, int(duplicate.size())));
}

void PianoRollCommands::zoomToSelection() {
  if (!m_songView->document())
    return;
  const SongView::TimeSelection &timeSelection = m_songView->timeSelection();
  if (timeSelection.active()) {
    m_songView->zoomToTickRange(timeSelection.startTick, timeSelection.endTick);
    return;
  }
  const std::vector<DocNote> notes = selectedNotes();
  uint64_t start = UINT64_MAX;
  uint64_t end = 0;
  for (const DocNote &note : notes) {
    start = std::min(start, note.tick);
    const uint64_t duration =
        note.duration ? note.duration : m_songView->gridTicksAt(note.tick);
    end = std::max(end, note.tick + duration);
  }
  if (start != UINT64_MAX && end > start)
    m_songView->zoomToTickRange(start, end);
}

} // namespace songview
