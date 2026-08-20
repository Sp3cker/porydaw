#include "eventlistview.h"

#include <QAbstractItemView>
#include <QApplication>
#include <QItemSelectionModel>
#include <QKeyEvent>
#include <QLabel>
#include <QMenu>
#include <QTableView>
#include <algorithm>

#include "core/smf.h"
#include "core/songdocument.h"
#include "eventtablemodel.h"
#include "eventtabletypes.h"
#include "ui/keymap.h"
#include "ui/songview.h"

using namespace eventlist;

void EventListView::reorderEvent(size_t from, size_t dest)
{
    const int chunk = m_model->chunk();
    if (!m_document || chunk < 0 || chunk >= int(m_document->smf().tracks.size()))
        return;
    size_t first, last;
    if (!m_document->rawEventMoveBounds(chunk, from, &first, &last))
        return;
    dest = std::clamp(dest, first, last);
    if (dest == from)
        return;
    m_document->moveRawEvent(chunk, from, dest);
    const int row = m_model->rowForRawEventIndex(dest);
    if (row >= 0) {
        const QModelIndex idx = m_model->index(row, EventTableModel::ColTick);
        m_settingCurrent = true;
        m_table->setCurrentIndex(idx);
        m_settingCurrent = false;
        m_table->scrollTo(idx);
    }
    updatePlayRow();
}

long long EventListView::moveDestForRow(int row, int delta, QString *why) const
{
    const int chunk = m_model->chunk();
    if (!m_document || chunk < 0 || chunk >= int(m_document->smf().tracks.size()))
        return -1;
    const auto src = m_model->rawEventIndexForRow(row);
    const auto target = m_model->rawEventIndexForRow(row + delta);
    if (!src || !target)
        return -1;
    const auto &events = m_document->smf().tracks[chunk].events;
    if (*src >= events.size() || *target >= events.size())
        return -1;
    if (events[*target].tick != events[*src].tick) {
        if (why)
            *why = tr("Events reorder within their tick — edit the Tick cell to retime");
        return -1;
    }
    size_t first, last;
    if (!m_document->rawEventMoveBounds(chunk, *src, &first, &last))
        return -1;
    if (*target < first || *target > last) {
        if (why)
            *why =
                tr("Setup events stay ahead of same-tick notes, and note ends ahead of note-ons");
        return -1;
    }
    return static_cast<long long>(*target);
}

void EventListView::moveCurrentRow(int delta)
{
    const int row = m_table->currentIndex().row();
    QString why;
    const long long dest = moveDestForRow(row, delta, &why);
    if (dest < 0) {
        if (!why.isEmpty() && m_sv)
            m_sv->announce(why);
        return;
    }
    const auto src = m_model->rawEventIndexForRow(row);
    if (src)
        reorderEvent(*src, size_t(dest));
}

bool EventListView::eventFilter(QObject *watched, QEvent *event)
{
    if (watched == m_table) {
        if (event->type() == QEvent::ShortcutOverride) {
            auto *keyEvent = static_cast<QKeyEvent *>(event);
            if (keyEvent->key() == Qt::Key_Space && keyEvent->modifiers() == Qt::NoModifier) {
                keyEvent->ignore();
                return true;
            }
        }
        if (event->type() == QEvent::KeyPress) {
            auto *keyEvent = static_cast<QKeyEvent *>(event);
            if (keyEvent->key() == Qt::Key_Delete || keyEvent->key() == Qt::Key_Backspace) {
                deleteSelected();
                return true;
            }
            const auto &keys = keymap::Registry::instance();
            if (keys.matches(keyEvent, QStringLiteral("eventlist.move_up"))) {
                moveCurrentRow(-1);
                return true;
            }
            if (keys.matches(keyEvent, QStringLiteral("eventlist.move_down"))) {
                moveCurrentRow(1);
                return true;
            }
        }
    }
    return QWidget::eventFilter(watched, event);
}

void EventListView::addEvent()
{
    const int chunk = currentChunk();
    if (!m_document || chunk < 0 || chunk >= int(m_document->smf().tracks.size()))
        return;
    if (chunk == 0) {
        if (const auto tempo = m_model->tempoPointForRow(m_table->currentIndex().row())) {
            const TempoPoint copy{m_sv->editCursorTick(), tempo->microsecondsPerQuarterNote};
            m_document->applyTempoEdit({{}, {copy}});
            selectRowAtTick(chunk, copy.tick);
            return;
        }
    }
    const auto &events = m_document->smf().tracks[chunk].events;
    SmfEvent ev;
    const auto src = m_model->rawEventIndexForRow(m_table->currentIndex().row());
    if (src && *src < events.size()) {
        ev = events[*src];
    } else {
        ev.status = uint8_t(0xB0 | m_model->fallbackChannel());
        ev.data0 = 7;
        ev.data1 = 100;
    }
    ev.tick = m_sv->editCursorTick();
    m_document->insertRawEvent(chunk, ev);
    selectEventRow(chunk, ev);
}

void EventListView::insertCopyOfRow(int row)
{
    const int chunk = currentChunk();
    if (!m_document || chunk < 0 || chunk >= int(m_document->smf().tracks.size()))
        return;
    if (chunk == 0) {
        if (const auto tempo = m_model->tempoPointForRow(row)) {
            m_document->applyTempoEdit({{}, {*tempo}});
            selectRowAtTick(chunk, tempo->tick);
            return;
        }
    }
    const auto &events = m_document->smf().tracks[chunk].events;
    const auto src = m_model->rawEventIndexForRow(row);
    if (!src || *src >= events.size())
        return;
    const SmfEvent ev = events[*src];
    m_document->insertRawEvent(chunk, ev);
    selectEventRow(chunk, ev);
}

void EventListView::showContextMenu(const QPoint &pos)
{
    const int chunk = currentChunk();
    if (!m_document || chunk < 0 || chunk >= int(m_document->smf().tracks.size()))
        return;
    const QModelIndex idx = m_table->indexAt(pos);
    if (idx.isValid() && m_table->selectionModel() &&
        !m_table->selectionModel()->isRowSelected(idx.row(), QModelIndex()))
        m_table->setCurrentIndex(m_model->index(idx.row(), EventTableModel::ColTick));
    const auto src =
        idx.isValid() ? m_model->rawEventIndexForRow(idx.row()) : std::optional<size_t>{};
    const bool selectedTempo = idx.isValid() && m_model->tempoPointForRow(idx.row()).has_value();
    int deletable = 0;
    if (m_table->selectionModel()) {
        for (const QModelIndex &row : m_table->selectionModel()->selectedRows()) {
            if (m_model->rawEventIndexForRow(row.row()) ||
                m_model->tempoPointForRow(row.row()).has_value())
                deletable++;
        }
    }
    QMenu menu(this);
    QAction *insert = menu.addAction(tr("Insert event"));
    QAction *showVoice = nullptr;
    int showProgram = -1;
    const auto &events = m_document->smf().tracks[chunk].events;
    if (src && *src < events.size() && typeKindOf(events[*src]) == TypeProgram) {
        showProgram = events[*src].data0;
        showVoice = menu.addAction(tr("Show voice in voicegroup"));
    }
    QAction *moveUp = nullptr;
    QAction *moveDown = nullptr;
    if (src) {
        menu.addSeparator();
        moveUp = menu.addAction(tr("Move up within tick"));
        moveUp->setEnabled(moveDestForRow(idx.row(), -1, nullptr) >= 0);
        moveDown = menu.addAction(tr("Move down within tick"));
        moveDown->setEnabled(moveDestForRow(idx.row(), 1, nullptr) >= 0);
    }
    menu.addSeparator();
    QAction *del =
        menu.addAction(deletable > 0 ? tr("Delete %n event(s)", nullptr, deletable) : tr("Delete"));
    del->setEnabled(deletable > 0);
    QAction *chosen = menu.exec(m_table->viewport()->mapToGlobal(pos));
    if (!chosen)
        return;
    if (chosen == insert) {
        if (src || selectedTempo)
            insertCopyOfRow(idx.row());
        else
            addEvent();
    } else if ((moveUp && chosen == moveUp) || (moveDown && chosen == moveDown)) {
        const long long dest = moveDestForRow(idx.row(), chosen == moveUp ? -1 : 1, nullptr);
        const auto src = m_model->rawEventIndexForRow(idx.row());
        if (dest >= 0 && src)
            reorderEvent(*src, size_t(dest));
    } else if (showVoice && chosen == showVoice) {
        m_sv->revealVoice(showProgram);
    } else if (chosen == del) {
        deleteSelected();
    }
}

void EventListView::deleteSelected()
{
    const int chunk = currentChunk();
    if (!m_document || chunk < 0 || chunk >= int(m_document->smf().tracks.size()) ||
        !m_table->selectionModel())
        return;
    std::vector<size_t> indices;
    TempoEdit tempoEdit;
    for (const QModelIndex &row : m_table->selectionModel()->selectedRows()) {
        const auto index = m_model->rawEventIndexForRow(row.row());
        if (index) {
            indices.push_back(*index);
            continue;
        }
        if (const auto tempo = m_model->tempoPointForRow(row.row()))
            tempoEdit.remove.push_back(*tempo);
    }
    if (indices.empty() && tempoEdit.empty())
        return;
    if (indices.size() + tempoEdit.remove.size() > 1)
        m_table->selectionModel()->clear();
    if (!indices.empty() && !tempoEdit.empty()) {
        const auto count = int(indices.size() + tempoEdit.remove.size());
        m_document->removeRawEventsAndEditTempo(tr("delete %n event(s)", nullptr, count), chunk,
                                                std::move(indices), tempoEdit);
    } else if (!indices.empty()) {
        m_document->deleteRawEvents(chunk, std::move(indices));
    } else {
        m_document->applyTempoEdit(tempoEdit);
    }
}

void EventListView::updateCountLabel()
{
    const int chunk = currentChunk();
    if (!m_document || chunk < 0 || chunk >= int(m_document->smf().tracks.size())) {
        m_count->clear();
        return;
    }
    const size_t total = m_document->smf().tracks[chunk].events.size() +
                         (chunk == 0 ? m_document->tempoPoints().size() : 0);
    const size_t shown = m_model->shownEvents();
    m_count->setText(shown == total ? tr("%n event(s)", nullptr, int(total))
                                    : tr("%1 of %2 events").arg(shown).arg(total));
}
