#pragma once

#include <QEvent>
#include <QObject>

#include <QPoint>
#include <QRect>

#include <cstdint>
#include <functional>
#include <memory>
#include <vector>
class QColor;

class QAction;
class QPainter;
class QWidget;
struct DocNote;
struct ViewNote;
class SongView;

namespace live_shortcuts {
enum class Command : std::uint8_t;
}

namespace songview {

namespace piano_roll_internal {
class NoteContextMenu;
}
class PianoRollShortcutAuditionEvent final : public QEvent {
public:
  PianoRollShortcutAuditionEvent(int key, int velocity)
      : QEvent(QEvent::Type(QEvent::User + 1)), key(key), velocity(velocity) {}

  int key;
  int velocity;
};

class PianoRollCommands final : public QObject {
public:
  PianoRollCommands(QWidget *actionTarget, SongView *songView,
                    std::function<void(QPoint)> retargetMenu,
                    std::function<void(uint8_t)> latchVelocity);
  ~PianoRollCommands() override;
  void showMenuAt(QPoint globalPosition);
  std::vector<DocNote> selectedNotes() const;

protected:
  bool eventFilter(QObject *watched, QEvent *event) override;

private:
  QAction *createShortcutAction(live_shortcuts::Command command,
                                void (PianoRollCommands::*handler)());
  void copyActiveSelection();
  void cutActiveSelection();
  void pasteActiveSelection();
  void duplicateSelection();
  void splitNotes();
  void joinSelection();
  void deleteActiveSelection();
  void selectAllNotes();
  void moveNotesLeft();
  void moveNotesRight();
  void transposeNotesUp();
  void transposeNotesDown();
  void transposeNotesUpOctave();
  void transposeNotesDownOctave();
  void shortenNotes();
  void lengthenNotes();
  void decreaseVelocity();
  void increaseVelocity();
  void editVelocity();
  void zoomIn();
  void zoomOut();
  void zoomToSelection();
  void zoomToFullSong();
  void copyNotes(const std::vector<DocNote> &notes);
  void pasteAtEditCursor();
  void moveSelection(bool right);
  void nudgeSelection(bool right);
  void transposeSelectionBy(int semitones);
  void transposeSelection(int semitones);
  void resizeSelection(bool lengthen);
  void resizeSelectedNotes(bool lengthen);
  void nudgeVelocity(int delta);
  void nudgeSelectedVelocity(int delta);
  void zoomBy(double factor);
  void auditionTransposedNote(int key, int velocity);

  QWidget *m_actionTarget;
  SongView *m_songView;
  std::function<void(uint8_t)> m_latchVelocity;
  std::unique_ptr<piano_roll_internal::NoteContextMenu> m_noteMenu;
  bool m_shortcutAudition = false;
};

namespace piano_roll_rendering {
QColor playheadColor();

bool isBlackKey(int key);
int keyToY(const SongView &songView, int key);
int yToKey(const SongView &songView, int y);
QRect noteRect(const SongView &songView, const ViewNote &note);
QRect noteRect(const SongView &songView, uint64_t startTick, uint64_t endTick,
               int key);
bool nearRightEdge(const SongView &songView, const ViewNote &note,
                   QPoint position);
bool nearLeftEdge(const SongView &songView, const ViewNote &note,
                  QPoint position);
bool nearVelocityHandle(const SongView &songView, const ViewNote &note,
                        QPoint position);
void drawOverlays(QPainter &painter, const SongView &songView,
                  const QRect &rect, int origin, bool timeSelectionCovered);
void drawKeyboard(QPainter &painter, const SongView &songView, int height,
                  int soundingKey);

} // namespace piano_roll_rendering

} // namespace songview
