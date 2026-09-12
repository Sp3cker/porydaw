#pragma once

#include "ui/eventtablemodel.h"
#include "ui/songview/quick/timelineinput.h"

#include <QList>
#include <QObject>
#include <QPointF>
#include <QSet>
#include <QString>
#include <QStringList>
#include <QVariantMap>
#include <cstddef>
#include <cstdint>

class QKeyEvent;
class SongDocument;
class SongView;
namespace songview {
class QuickMenuHost;
class QuickPopupSession;
class QuickMenuModel;
class EventListInteraction;
} // namespace songview
struct SmfEvent;
struct TrackRemap;

class EventListController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(eventlist::EventTableModel *model READ model CONSTANT FINAL)
    Q_PROPERTY(QVariantMap appearance READ appearance NOTIFY appearanceChanged FINAL)
    Q_PROPERTY(int chunk READ chunk NOTIFY chunkChanged FINAL)
    Q_PROPERTY(QStringList chunkLabels READ chunkLabels NOTIFY chunkLabelsChanged FINAL)
    Q_PROPERTY(int filterMask READ filterMask NOTIFY filterMaskChanged FINAL)
    Q_PROPERTY(QString filterSummary READ filterSummary NOTIFY filterSummaryChanged FINAL)
    Q_PROPERTY(QString countText READ countText NOTIFY countTextChanged FINAL)
    Q_PROPERTY(QStringList headerLabels READ headerLabels CONSTANT FINAL)
    Q_PROPERTY(int currentRow READ currentRow NOTIFY currentRowChanged FINAL)
    Q_PROPERTY(int playRow READ playRow NOTIFY playRowChanged FINAL)
    Q_PROPERTY(QList<double> columnWidths READ columnWidths NOTIFY columnWidthsChanged FINAL)
    Q_PROPERTY(QList<int> selectedRows READ selectedRows NOTIFY selectedRowsChanged FINAL)
    Q_PROPERTY(bool followPlayhead READ followPlayhead WRITE setFollowPlayhead NOTIFY
                   followPlayheadChanged FINAL)
    Q_PROPERTY(bool visible READ isVisible WRITE setVisible NOTIFY visibleChanged FINAL)
    Q_PROPERTY(bool editing READ isEditing NOTIFY editingChanged FINAL)
    Q_PROPERTY(int editingRow READ editingRow NOTIFY editingChanged FINAL)
    Q_PROPERTY(int editingColumn READ editingColumn NOTIFY editingChanged FINAL)
    Q_PROPERTY(bool menuOpen READ menuOpen NOTIFY menuOpenChanged FINAL)

  public:
    explicit EventListController(SongView *songView, QObject *parent = nullptr);

    eventlist::EventTableModel *model() const noexcept { return m_model; }
    QVariantMap appearance() const { return m_appearance; }
    int chunk() const noexcept { return m_currentChunk; }
    QStringList chunkLabels() const { return m_chunkLabels; }
    int filterMask() const noexcept { return m_filterMask; }
    QString filterSummary() const;
    QString countText() const;
    QStringList headerLabels() const;
    int currentRow() const noexcept { return m_currentRow; }
    int playRow() const noexcept { return m_playRow; }
    bool followPlayhead() const noexcept { return m_followPlayhead; }
    QList<double> columnWidths() const { return m_columnWidths; }
    QList<int> selectedRows() const { return m_selectedRows; }
    bool isVisible() const noexcept { return m_visible; }
    bool isEditing() const noexcept { return m_editingRow >= 0; }
    int editingRow() const noexcept { return m_editingRow; }
    int editingColumn() const noexcept { return m_editingColumn; }
    bool menuOpen() const noexcept { return m_menuOpen; }
    // Semantic event-action eligibility. The controller owns row visibility,
    // editor state, and same-tick destination legality; unrelated song
    // selections do not participate.
    bool canMoveCurrentRow(int delta) const;

    // The controller owns document and track-selection signal registration.
    void setDocument(SongDocument *document);
    void refresh();
    void syncTrackSelection();
    void onTracksRemapped(const TrackRemap &remap);
    void syncAppearance();
    void setPlayheadTick(double tick, bool playing);
    void setFollowPlayhead(bool on);

    Q_INVOKABLE void chunkPicked(int comboIndex);
    void setPopupSession(songview::QuickPopupSession *session);
    Q_INVOKABLE void filterToggled(int bit);
    Q_INVOKABLE void addEvent();
    Q_INVOKABLE void insertCopyOfRow(int row);
    Q_INVOKABLE void deleteSelected();
    Q_INVOKABLE void reorderRows(int fromRow, int toRow);
    Q_INVOKABLE void moveCurrentRow(int delta);
    Q_INVOKABLE bool isLegalDrop(int fromRow, int gap) const;
    Q_INVOKABLE void commitDrop(int fromRow, int gap);
    Q_INVOKABLE qlonglong moveDestForRow(int row, int delta) const;
    Q_INVOKABLE bool commitCellEdit(int row, int column, const QString &text);
    Q_INVOKABLE bool validateCellEdit(int row, int column, const QString &text) const;
    Q_INVOKABLE bool isCellEditable(int row, int column) const;
    Q_INVOKABLE bool beginEditing(int row, int column);
    // Invalid committed text returns false and leaves this session open for correction.
    Q_INVOKABLE bool finishEditing(const QString &text, bool commit);
    Q_INVOKABLE bool canStepEditing() const;
    Q_INVOKABLE QString steppedEditingText(const QString &currentText, int delta) const;
    Q_INVOKABLE void resizeColumn(int column, double width);
    Q_INVOKABLE QString rowTickString(int row) const;
    Q_INVOKABLE void selectRow(int row, int modifiers);
    Q_INVOKABLE bool isSelected(int row) const;
    Q_INVOKABLE void focusRow(int row);
    Q_INVOKABLE void selectAll();
    Q_INVOKABLE void setPointerDown(bool pointerDown);
    Q_INVOKABLE void setVisible(bool visible);
    Q_INVOKABLE void openChunkMenu(const QPointF &scenePosition);
    Q_INVOKABLE void openFilterMenu(const QPointF &scenePosition);
    Q_INVOKABLE void openRowMenu(const QPointF &scenePosition);
    Q_INVOKABLE void openTypeMenu(const QPointF &scenePosition);
    Q_INVOKABLE int headerAlignment(int column) const;

    // Direct key bridge retained for the shared timeline input interaction.
    bool handleKey(QKeyEvent *event);

  signals:
    void appearanceChanged();
    void chunkChanged();
    void chunkLabelsChanged();
    void filterMaskChanged();
    void filterSummaryChanged();
    void countTextChanged();
    void currentRowChanged();
    void playRowChanged(int row);
    void followPlayheadChanged();
    void columnWidthsChanged();
    void selectedRowsChanged();
    void visibleChanged();
    void editingChanged();
    void menuOpenChanged();
    void scrollToRow(int row);
    void announce(const QString &text);
    void revealVoice(int program);

  private:
    friend class songview::EventListInteraction;

    void rebuildAppearance();
    void rebuildChunks();
    void setChunk(int chunk, bool followTrack);
    void updateCountText();
    void updatePlayRow();
    void setCurrentRow(int row);
    void setSelectedRows(QList<int> rows);
    void selectRowAtTick(int chunk, uint64_t tick);
    void jumpCursorToRow(int row);
    void selectEventRow(int chunk, const SmfEvent &event);
    bool editValueFor(int row, int column, const QString &text, QVariant *value) const;
    void clearEditing();
    bool isLegalRawMove(size_t source, size_t destination) const;
    void reorderRawEvent(size_t from, size_t destination);
    bool handleLocalKey(int key, Qt::KeyboardModifiers modifiers);
    bool dropDestinationForGap(int fromRow, int gap, size_t *source, size_t *destination) const;
    qlonglong moveDestForRow(int row, int delta, QString *why) const;
    void openMenu(songview::QuickMenuModel *model, const QPointF &scenePosition);
    void rebuildChunkMenu();
    void rebuildFilterMenu();
    void rebuildRowMenu(int row);
    void rebuildTypeMenu();
    void updateMenuOpen(bool open);

    SongView *m_songView = nullptr;
    SongDocument *m_document = nullptr;
    eventlist::EventTableModel *m_model = nullptr;
    songview::QuickMenuHost *m_menuHost = nullptr;
    songview::QuickMenuModel *m_chunkMenu = nullptr;
    songview::QuickMenuModel *m_filterMenu = nullptr;
    songview::QuickMenuModel *m_rowMenu = nullptr;
    songview::QuickMenuModel *m_typeMenu = nullptr;
    QVariantMap m_appearance;
    QStringList m_chunkLabels;
    QList<double> m_columnWidths{70.0, 120.0, 36.0, 56.0, 56.0, 140.0};
    QList<int> m_selectedRows;
    QSet<int> m_selectedRowSet;
    uint64_t m_documentRevision = 0;
    int m_currentChunk = -1;
    int m_filterMask = eventlist::EventTableModel::FilterAll;
    int m_currentRow = -1;
    int m_selectionAnchor = -1;
    int m_playRow = -1;
    int m_menuRow = -1;
    double m_playTick = -1.0;
    bool m_playing = false;
    bool m_followPlayhead = true;
    bool m_chunkRemapped = false;
    bool m_syncing = false;
    bool m_visible = false;
    int m_editingRow = -1;
    int m_editingColumn = -1;
    bool m_pointerDown = false;
    bool m_menuOpen = false;
};
namespace songview {

// The EventList input participates in TimelineQuickView's policy chain but
// owns only the four widget-era local commands. Everything else falls through
// to the shared SongView policy unchanged.
class EventListInteraction final : public TimelineBandInteraction
{
  public:
    explicit EventListInteraction(EventListController &controller) : m_controller(controller) {}

    void attachInputHost(TimelineInputHost &host) override;
    void detachInputHost(TimelineInputHost &host) override;
    bool keyPress(const TimelineKeyInput &input) override;

  private:
    EventListController &m_controller;
};

} // namespace songview
