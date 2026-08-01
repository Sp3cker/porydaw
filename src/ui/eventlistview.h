#pragma once

#include <cstdint>

#include <QWidget>

class QComboBox;
class QLabel;
class QMenu;
class QTableView;
class QToolButton;
class SongDocument;
class SongView;
struct SmfEvent;
struct TrackRemap;

namespace eventlist {
class EventTableModel;
}

// Raw MIDI event list: every event of one SMF chunk as an editable table row
// (tick, type, channel, data bytes, meta/sysex payload, plus a read-only
// decoded summary), ending with the chunk's end-of-track marker. An
// alternative to the piano roll in the same screen space (SongView stacks
// the two); the ruler and automation lanes stay visible around it. Edits go
// through SongDocument's raw-event API, so they share the undo stack and
// refresh through documentChanged like every other editor.
class EventListView : public QWidget
{
    Q_OBJECT

  public:
    explicit EventListView(SongView *sv, QWidget *parent = nullptr);

    // May be null (read-only sessions have no raw model to show).
    void setDocument(SongDocument *document);
    // Re-read the SMF (any mutation, undo/redo, or in-place reload). Keeps
    // the chunk/filter choice and the cursor row; idempotent.
    void refresh();
    // Follow the roll's track selection into the matching chunk.
    void syncTrackSelection();
    // Playhead marker: tints the row the play cursor last passed and, while
    // playing, keeps it scrolled into view (never while the user is holding
    // a mouse button or editing a cell). SongView pushes this every UI tick;
    // cheap when the row didn't change.
    void setPlayheadTick(double tick, bool playing);
    // App-wide Follow Playhead toggle: off, the playing row is still tinted
    // but the table stops scrolling to it.
    void setFollowPlayhead(bool on);
    // Context-menu insert: a copy of the given table row's event at that
    // row's own tick. Public because the menu itself blocks in exec() and
    // can't be driven by the offscreen harness.
    void insertCopyOfRow(int row);

  protected:
    bool eventFilter(QObject *watched, QEvent *event) override;
    void changeEvent(QEvent *event) override;

  private:
    void applyRowIndexFont();
    void rebuildChunkCombo();
    void chunkPicked(int comboIndex);
    void filterChanged();
    int filterMask() const;
    void updateFilterText();
    void addEvent();
    void deleteSelected();
    void reorderEvent(size_t from, size_t dest);
    long long moveDestForRow(int row, int delta, QString *why) const;
    void moveCurrentRow(int delta);
    void showContextMenu(const QPoint &pos);
    void updateCountLabel();
    void updatePlayRow();
    void jumpCursorToRow(int row);
    int currentChunk() const;
    void selectEventRow(int chunk, const SmfEvent &event);
    void onTracksRemapped(const TrackRemap &remap);

    SongView *m_sv;
    SongDocument *m_document = nullptr;
    // The newest document revision whose owner mapping is reflected above.
    // SongView remaps its selected engine slot before this view receives the
    // same TrackRemap, so selection notifications from a newer revision
    // cannot replace the old SMF owner before it is remapped.
    uint64_t m_documentRevision = 0;
    eventlist::EventTableModel *m_model;
    QTableView *m_table;
    QComboBox *m_chunk;
    QToolButton *m_filter; // opens m_filterMenu; text summarizes the checks
    QMenu *m_filterMenu;   // one checkable action per event category
    QLabel *m_count;
    bool m_syncing = false;
    bool m_settingCurrent = false; // programmatic row changes must not
                                   // commit the edit cursor
    // The selected raw SMF owner, kept independently from the combo while
    // SongView updates its selected engine slot during a TrackRemap.
    int m_currentChunk = -1;
    // A remap has updated m_currentChunk and documentChanged must rebuild the
    // combo and table from that owner.
    bool m_chunkRemapped = false;
    double m_playTick = -1.0; // last playhead tick pushed (-1 = none)
    bool m_playing = false;
    bool m_followPlayhead = true; // scroll to the playing row (transport bar)
};
