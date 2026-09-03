#include "eventlistview.h"

#include <QAbstractItemView>
#include <QAction>
#include <QApplication>
#include <QComboBox>
#include <QHBoxLayout>
#include <QHeaderView>
#include <QItemSelectionModel>
#include <QLabel>
#include <QLineEdit>
#include <QMenu>
#include <QMouseEvent>
#include <QRegularExpression>
#include <QRegularExpressionValidator>
#include <QSpinBox>
#include <QStyledItemDelegate>
#include <QTableView>
#include <QToolButton>
#include <QVBoxLayout>
#include <algorithm>
#include <cmath>

#include "core/smf.h"
#include "core/songdocument.h"
#include "eventtablemodel.h"
#include "ui/songview.h"
#include "ui/typography.h"

namespace {

class CheckMenu : public QMenu
{
  public:
    using QMenu::QMenu;

  protected:
    void mouseReleaseEvent(QMouseEvent *event) override
    {
        QAction *action = actionAt(event->pos());
        if (action && action->isCheckable()) {
            action->trigger();
            return;
        }
        QMenu::mouseReleaseEvent(event);
    }
};

class EventItemDelegate : public QStyledItemDelegate
{
  public:
    using QStyledItemDelegate::QStyledItemDelegate;

    QWidget *createEditor(QWidget *parent, const QStyleOptionViewItem &option,
                          const QModelIndex &index) const override
    {
        const auto spin = [parent](int min, int max) {
            auto *box = new QSpinBox(parent);
            box->setRange(min, max);
            box->setFrame(false);
            box->setFont(typography::tableMono(box->font()));
            return box;
        };
        switch (index.column()) {
        case eventlist::EventTableModel::ColTick: {
            auto *edit = new QLineEdit(parent);
            edit->setFrame(false);
            edit->setFont(typography::tableMono(edit->font()));
            static const QRegularExpression digits(QStringLiteral("[0-9]{1,19}"));
            edit->setValidator(new QRegularExpressionValidator(digits, edit));
            return edit;
        }
        case eventlist::EventTableModel::ColChannel:
            return spin(1, 16);
        case eventlist::EventTableModel::ColData1:
        case eventlist::EventTableModel::ColData2:
            return spin(0, 127);
        case eventlist::EventTableModel::ColType: {
            auto *combo = new QComboBox(parent);
            const auto *model = static_cast<const eventlist::EventTableModel *>(index.model());
            for (const auto &[name, kind] :
                 eventlist::EventTableModel::typeChoices(model->chunk() == 0))
                combo->addItem(name, kind);
            connect(combo, QOverload<int>::of(&QComboBox::activated), this, [this, combo] {
                auto *self = const_cast<EventItemDelegate *>(this);
                emit self->commitData(combo);
                emit self->closeEditor(combo);
            });
            return combo;
        }
        default:
            return QStyledItemDelegate::createEditor(parent, option, index);
        }
    }

    void setEditorData(QWidget *editor, const QModelIndex &index) const override
    {
        if (index.column() == eventlist::EventTableModel::ColType) {
            auto *combo = static_cast<QComboBox *>(editor);
            combo->setCurrentIndex(combo->findData(index.data(Qt::EditRole)));
            return;
        }
        QStyledItemDelegate::setEditorData(editor, index);
    }

    void setModelData(QWidget *editor, QAbstractItemModel *model,
                      const QModelIndex &index) const override
    {
        if (index.column() == eventlist::EventTableModel::ColType) {
            model->setData(index, static_cast<QComboBox *>(editor)->currentData(), Qt::EditRole);
            return;
        }
        QStyledItemDelegate::setModelData(editor, model, index);
    }
};

} // namespace

using namespace eventlist;

EventListView::EventListView(SongView *sv, QWidget *parent) : QWidget(parent), m_sv(sv)
{
    m_model = new EventTableModel(sv, this);
    m_model->setSelectionHandler(
        [this](int chunk, uint64_t tick) { selectRowAtTick(chunk, tick); });
    auto *bar = new QHBoxLayout;
    bar->setContentsMargins(4, 2, 4, 2);
    bar->setSpacing(4);
    m_chunk = new QComboBox(this);
    m_chunk->setObjectName(QStringLiteral("eventListChunk"));
    m_chunk->setToolTip(tr("The MIDI file chunk shown (follows the selected track)"));
    bar->addWidget(m_chunk);
    m_filter = new QToolButton(this);
    m_filter->setObjectName(QStringLiteral("eventListFilter"));
    m_filter->setAutoRaise(true);
    m_filter->setPopupMode(QToolButton::InstantPopup);
    m_filter->setToolTip(tr("Which event types are shown"));
    m_filterMenu = new CheckMenu(this);
    m_filterMenu->setObjectName(QStringLiteral("eventListFilterMenu"));
    const std::pair<QString, int> categories[] = {
        {tr("Notes"), EventTableModel::FilterNotes},
        {tr("Control changes"), EventTableModel::FilterCc},
        {tr("Program changes"), EventTableModel::FilterProgram},
        {tr("Pitch bends"), EventTableModel::FilterBend},
        {tr("Aftertouch"), EventTableModel::FilterTouch},
        {tr("SysEx"), EventTableModel::FilterSysEx},
        {tr("Meta"), EventTableModel::FilterMeta},
    };
    for (const auto &category : categories) {
        QAction *action = m_filterMenu->addAction(category.first);
        action->setCheckable(true);
        action->setChecked(true);
        action->setData(category.second);
        connect(action, &QAction::toggled, this, &EventListView::filterChanged);
    }
    m_filter->setMenu(m_filterMenu);
    updateFilterText();
    bar->addWidget(m_filter);
    auto *add = new QToolButton(this);
    add->setObjectName(QStringLiteral("eventListAdd"));
    add->setText(tr("+ Add"));
    add->setAutoRaise(true);
    add->setToolTip(tr("Insert an event at the edit cursor (a copy of the current row, if any)"));
    connect(add, &QToolButton::clicked, this, &EventListView::addEvent);
    bar->addWidget(add);
    auto *remove = new QToolButton(this);
    remove->setObjectName(QStringLiteral("eventListRemove"));
    remove->setText(tr("Delete"));
    remove->setAutoRaise(true);
    remove->setToolTip(tr("Delete the selected events (Del)"));
    connect(remove, &QToolButton::clicked, this, &EventListView::deleteSelected);
    bar->addWidget(remove);
    bar->addStretch();
    m_count = new QLabel(this);
    bar->addWidget(m_count);
    m_table = new QTableView(this);
    m_table->setObjectName(QStringLiteral("eventListTable"));
    m_table->setModel(m_model);
    m_table->setItemDelegate(new EventItemDelegate(m_table));
    m_table->setSelectionBehavior(QAbstractItemView::SelectRows);
    m_table->setSelectionMode(QAbstractItemView::ExtendedSelection);
    m_table->setEditTriggers(QAbstractItemView::DoubleClicked | QAbstractItemView::EditKeyPressed |
                             QAbstractItemView::SelectedClicked);
    m_table->setDragEnabled(true);
    m_table->setAcceptDrops(true);
    m_table->setDropIndicatorShown(true);
    m_table->setDragDropMode(QAbstractItemView::InternalMove);
    m_table->setDragDropOverwriteMode(false);
    m_table->setDefaultDropAction(Qt::MoveAction);
    m_model->setReorderHandler([this](size_t from, size_t dest) { reorderEvent(from, dest); });
    m_table->setAlternatingRowColors(true);
    m_table->setFrameShape(QFrame::NoFrame);
    m_table->verticalHeader()->setDefaultSectionSize(m_table->fontMetrics().height() + 6);
    const auto rowIndexFont = typography::caption(typography::bodyMono(m_table->font()));
    m_table->verticalHeader()->setFont(rowIndexFont);
    m_table->horizontalHeader()->setHighlightSections(false);
    m_table->horizontalHeader()->setStretchLastSection(true);
    m_table->setColumnWidth(EventTableModel::ColTick, 70);
    m_table->setColumnWidth(EventTableModel::ColType, 120);
    m_table->setColumnWidth(EventTableModel::ColChannel, 36);
    m_table->setColumnWidth(EventTableModel::ColData1, 56);
    m_table->setColumnWidth(EventTableModel::ColData2, 56);
    m_table->setColumnWidth(EventTableModel::ColData, 140);
    m_table->installEventFilter(this);
    m_table->setContextMenuPolicy(Qt::CustomContextMenu);
    connect(m_table, &QTableView::customContextMenuRequested, this,
            &EventListView::showContextMenu);
    setFocusProxy(m_table);
    auto *layout = new QVBoxLayout(this);
    layout->setContentsMargins(0, 0, 0, 0);
    layout->setSpacing(0);
    layout->addLayout(bar);
    layout->addWidget(m_table, 1);
    connect(m_chunk, QOverload<int>::of(&QComboBox::activated), this, &EventListView::chunkPicked);
    connect(m_sv, &SongView::selectedTrackChanged, this, [this](int) { syncTrackSelection(); });
    connect(m_table->selectionModel(), &QItemSelectionModel::currentRowChanged, this,
            [this](const QModelIndex &current, const QModelIndex &) {
                if (!m_settingCurrent && current.isValid())
                    jumpCursorToRow(current.row());
            });
    connect(m_table, &QTableView::clicked,
            [this](const QModelIndex &index) { jumpCursorToRow(index.row()); });
}

void EventListView::setDocument(SongDocument *document)
{
    if (m_document != document) {
        if (m_document)
            disconnect(m_document, nullptr, this, nullptr);
        m_document = document;
        m_documentRevision = m_document ? m_document->revision() : 0;
        m_currentChunk = -1;
        m_chunkRemapped = false;
        if (m_document) {
            connect(m_document, &SongDocument::tracksRemapped, this,
                    &EventListView::onTracksRemapped);
            connect(m_document, &SongDocument::documentChanged, this, &EventListView::refresh);
        }
    }
    rebuildChunkCombo();
    syncTrackSelection();
}

void EventListView::refresh()
{
    if (!m_document) {
        m_documentRevision = 0;
        m_model->setSource(nullptr, -1);
        m_chunk->clear();
        updateCountLabel();
        return;
    }
    if (isHidden())
        return;
    if (m_chunkRemapped) {
        const int target = m_currentChunk;
        m_chunkRemapped = false;
        m_settingCurrent = true;
        rebuildChunkCombo();
        m_syncing = true;
        m_chunk->setCurrentIndex(target >= 0 ? m_chunk->findData(target) : -1);
        m_syncing = false;
        m_currentChunk = target;
        if (target < 0 && m_table->selectionModel())
            m_table->selectionModel()->clear();
        m_model->setSource(m_document, target);
        m_settingCurrent = false;
    } else if (m_chunk->count() != int(m_document->smf().tracks.size())) {
        rebuildChunkCombo();
        syncTrackSelection();
    } else {
        const QModelIndex current = m_table->currentIndex();
        QList<int> selectedRows;
        if (m_table->selectionModel()) {
            const QModelIndexList rows = m_table->selectionModel()->selectedRows();
            for (const QModelIndex &row : rows)
                selectedRows.append(row.row());
        }
        m_settingCurrent = true;
        m_model->reload();
        const int rowCount = m_model->rowCount();
        if (current.isValid() && rowCount > 0) {
            const int row = std::min(current.row(), rowCount - 1);
            m_table->setCurrentIndex(m_model->index(row, current.column()));
        }
        if (selectedRows.size() > 1 && m_table->selectionModel()) {
            QItemSelection selection;
            for (int row : selectedRows) {
                if (row < rowCount)
                    selection.select(m_model->index(row, 0),
                                     m_model->index(row, m_model->columnCount() - 1));
            }
            m_table->selectionModel()->select(selection, QItemSelectionModel::ClearAndSelect);
        }
        m_settingCurrent = false;
    }
    updateCountLabel();
    updatePlayRow();
    m_documentRevision = m_document->revision();
}

void EventListView::syncTrackSelection()
{
    if (m_syncing || !m_document || isHidden() || m_document->revision() != m_documentRevision)
        return;
    const int chunk = m_document->smfTrackFor(m_sv->selectionModel().primaryTrack());
    if (chunk < 0 || chunk == currentChunk())
        return;
    const int comboIndex = m_chunk->findData(chunk);
    if (comboIndex < 0)
        return;
    m_syncing = true;
    m_chunk->setCurrentIndex(comboIndex);
    m_syncing = false;
    m_currentChunk = chunk;
    m_model->setSource(m_document, chunk);
    updateCountLabel();
    updatePlayRow();
}

void EventListView::onTracksRemapped(const TrackRemap &remap)
{
    m_currentChunk =
        m_currentChunk >= 0 && static_cast<size_t>(m_currentChunk) < remap.smfTrackMap.size()
            ? remap.smfTrackMap[static_cast<size_t>(m_currentChunk)]
            : -1;
    m_chunkRemapped = true;
}

void EventListView::setPlayheadTick(double tick, bool playing)
{
    if (m_playTick == tick && m_playing == playing)
        return;
    m_playTick = tick;
    m_playing = playing;
    updatePlayRow();
}

void EventListView::setFollowPlayhead(bool on)
{
    m_followPlayhead = on;
}

void EventListView::updatePlayRow()
{
    if (isHidden())
        return;
    int row = m_model->playheadRowAtOrBeforeTick(m_playTick);
    const QModelIndex current = m_table->currentIndex();
    if (m_playTick >= 0 && current.isValid() && current.row() != row) {
        const auto currentTick = m_model->exactTickForRow(current.row());
        if (currentTick && std::abs(double(*currentTick) - m_playTick) < 0.5)
            row = current.row();
    }
    if (row == m_model->playRow())
        return;
    m_model->setPlayRow(row);
    if (!m_playing || row < 0 || !m_followPlayhead || QApplication::mouseButtons() != Qt::NoButton)
        return;
    QWidget *focus = QApplication::focusWidget();
    if (focus && focus != m_table && m_table->isAncestorOf(focus))
        return;
    m_table->scrollTo(m_model->index(row, EventTableModel::ColTick));
}

void EventListView::jumpCursorToRow(int row)
{
    const int chunk = m_model->chunk();
    if (!m_document || chunk < 0 || chunk >= int(m_document->smf().tracks.size()))
        return;
    const auto rowTick = m_model->exactTickForRow(row);
    uint64_t tick;
    if (rowTick) {
        tick = *rowTick;
    } else {
        if (row != int(m_model->shownEvents()))
            return;
        tick = m_document->smf().tracks[chunk].endTick;
    }
    if (tick != m_sv->editCursorTick()) {
        m_sv->commitEditCursor(tick);
        m_sv->ensureTickVisible(tick);
    }
    updatePlayRow();
}

void EventListView::rebuildChunkCombo()
{
    m_syncing = true;
    const int previous = currentChunk();
    m_chunk->clear();
    if (m_document) {
        const SmfFile &smf = m_document->smf();
        for (int t = 0; t < int(smf.tracks.size()); t++) {
            int engineTrack = -1;
            for (int e = 0; e < m_document->engineTrackCount(); e++) {
                if (m_document->smfTrackFor(e) == t) {
                    engineTrack = e;
                    break;
                }
            }
            const QString label = engineTrack >= 0
                                      ? tr("Chunk %1 — Track %2").arg(t).arg(engineTrack + 1)
                                      : tr("Chunk %1 (tempo/meta)").arg(t);
            m_chunk->addItem(label, t);
        }
        const int restore = m_chunk->findData(previous);
        m_chunk->setCurrentIndex(restore >= 0 ? restore : 0);
    }
    m_currentChunk = m_chunk->currentIndex() >= 0 ? m_chunk->currentData().toInt() : -1;
    m_syncing = false;
    m_model->setSource(m_document, currentChunk());
    updateCountLabel();
    updatePlayRow();
}

void EventListView::chunkPicked(int comboIndex)
{
    if (m_syncing)
        return;
    m_currentChunk = comboIndex >= 0 ? m_chunk->itemData(comboIndex).toInt() : -1;
    m_model->setSource(m_document, currentChunk());
    updateCountLabel();
    updatePlayRow();
    if (!m_document)
        return;
    for (int e = 0; e < m_document->engineTrackCount(); e++) {
        if (m_document->smfTrackFor(e) == currentChunk()) {
            if (e != m_sv->selectionModel().primaryTrack()) {
                m_syncing = true;
                m_sv->selectTrack(e);
                m_syncing = false;
            }
            break;
        }
    }
}

void EventListView::filterChanged()
{
    m_model->setFilter(filterMask());
    updateFilterText();
    updateCountLabel();
    updatePlayRow();
}

int EventListView::filterMask() const
{
    int mask = 0;
    for (QAction *action : m_filterMenu->actions()) {
        if (action->isChecked())
            mask |= action->data().toInt();
    }
    return mask;
}

void EventListView::updateFilterText()
{
    const QList<QAction *> actions = m_filterMenu->actions();
    QStringList checked;
    for (QAction *action : actions) {
        if (action->isChecked())
            checked.append(action->text());
    }
    QString text;
    if (checked.size() == actions.size())
        text = tr("All events");
    else if (checked.isEmpty())
        text = tr("No events");
    else if (checked.size() == 1)
        text = checked.first();
    else
        text = tr("%1 +%2").arg(checked.first()).arg(checked.size() - 1);
    m_filter->setText(text);
}

int EventListView::currentChunk() const
{
    return m_currentChunk;
}

void EventListView::selectEventRow(int chunk, const SmfEvent &target)
{
    if (!m_document || chunk < 0 || chunk >= int(m_document->smf().tracks.size()) ||
        m_model->chunk() != chunk)
        return;
    const auto &events = m_document->smf().tracks[chunk].events;
    for (size_t i = 0; i < events.size(); i++) {
        if (events[i] == target) {
            const int row = m_model->rowForRawEventIndex(i);
            if (row >= 0) {
                const QModelIndex idx = m_model->index(row, EventTableModel::ColTick);
                m_settingCurrent = true;
                m_table->setCurrentIndex(idx);
                m_settingCurrent = false;
                m_table->scrollTo(idx);
            }
            return;
        }
    }
}

void EventListView::selectRowAtTick(int chunk, uint64_t tick)
{
    if (!m_document || m_model->chunk() != chunk)
        return;
    const int row = m_model->tempoRowForExactTick(tick);
    if (row < 0)
        return;
    const QModelIndex idx = m_model->index(row, EventTableModel::ColTick);
    m_settingCurrent = true;
    m_table->setCurrentIndex(idx);
    m_settingCurrent = false;
    m_table->scrollTo(idx);
}
