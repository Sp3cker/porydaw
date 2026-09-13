#include "eventlistcontroller.h"

#include "core/smf.h"
#include "core/songdocument.h"
#include "core/timedefaults.h"
#include "ui/eventtabletypes.h"
#include "ui/keymap.h"
#include "ui/songview.h"
#include "ui/songview/editactions.h"
#include "ui/songview/quick/quickmenumodel.h"
#include "ui/songview/quick/quickpopupsession.h"
#include "ui/songview/quick/retirehostmenu.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/theme/themeruntime.h"
#include "ui/typography.h"

#include <QApplication>
#include <QColor>
#include <QEvent>
#include <QFont>
#include <QKeyEvent>
#include <algorithm>
#include <cmath>
#include <iterator>
#include <utility>

#include <vector>
namespace {

struct FilterCategory {
    int bit;
    const char *text;
};

constexpr FilterCategory kFilterCategories[] = {
    {eventlist::EventTableModel::FilterNotes, "Notes"},
    {eventlist::EventTableModel::FilterCc, "Control changes"},
    {eventlist::EventTableModel::FilterProgram, "Program changes"},
    {eventlist::EventTableModel::FilterBend, "Pitch bends"},
    {eventlist::EventTableModel::FilterTouch, "Aftertouch"},
    {eventlist::EventTableModel::FilterSysEx, "SysEx"},
    {eventlist::EventTableModel::FilterMeta, "Meta"},
};

constexpr int kRowMenuInsert = 1;
constexpr int kRowMenuShowVoice = 2;
constexpr int kRowMenuMoveUp = 3;
constexpr int kRowMenuMoveDown = 4;
constexpr int kRowMenuDelete = 5;

songview::QuickMenuItem menuItem(int id, const QString &text, bool enabled = true)
{
    songview::QuickMenuItem item;
    item.id = id;
    item.text = text;
    item.enabled = enabled;
    return item;
}

bool hasChunk(const SongDocument *document, int chunk)
{
    return document && chunk >= 0 && chunk < int(document->smf().tracks.size());
}

} // namespace

EventListController::EventListController(SongView *songView, QObject *parent)
    : QObject(parent)
    , m_songView(songView)
    , m_model(new eventlist::EventTableModel(songView, this))
{
    m_model->setSelectionHandler([this](int chunk, Tick tick) { selectRowAtTick(chunk, tick); });
    m_menuHost = new songview::QuickMenuHost(this);
    m_chunkMenu = new songview::QuickMenuModel(this);
    m_filterMenu = new songview::QuickMenuModel(this);
    m_rowMenu = new songview::QuickMenuModel(this);
    m_typeMenu = new songview::QuickMenuModel(this);
    connect(m_menuHost, &songview::QuickMenuHost::isOpenChanged, this,
            [this] { updateMenuOpen(m_menuHost->isOpen()); });
    if (m_songView) {
        connect(m_songView, &SongView::selectedTrackChanged, this,
                [this](int) { syncTrackSelection(); });
        // The owned row menu retires whenever its target context moves:
        // row/chunk/filter/selection changes on this controller and the
        // view's document/selection invalidation. The session lookup stays
        // lazy so an unhosted controller never touches the canvas.
        const auto retireRowMenu = [this](bool restoreFocus) {
            songview::TimelineQuickView *const quick =
                m_songView ? m_songView->quickView() : nullptr;
            songview::retireHostMenu(quick ? quick->popupSession() : nullptr, m_menuHost, m_rowMenu,
                                     restoreFocus);
        };
        connect(m_songView, &SongView::contextMenusInvalidated, this, retireRowMenu);
        connect(this, &EventListController::currentRowChanged, this,
                [retireRowMenu] { retireRowMenu(true); });
        connect(this, &EventListController::chunkChanged, this,
                [retireRowMenu] { retireRowMenu(true); });
        connect(this, &EventListController::filterMaskChanged, this,
                [retireRowMenu] { retireRowMenu(true); });
        connect(this, &EventListController::selectedRowsChanged, this,
                [retireRowMenu] { retireRowMenu(true); });
    }
    connect(m_chunkMenu, &songview::QuickMenuModel::activated, this,
            &EventListController::chunkPicked);
    connect(m_filterMenu, &songview::QuickMenuModel::activated, this,
            &EventListController::filterToggled);
    connect(m_rowMenu, &songview::QuickMenuModel::activated, this, [this](int id) {
        switch (id) {
        case kRowMenuInsert:
            if (m_model->rawEventIndexForRow(m_menuRow) || m_model->qmlHasTempo(m_menuRow))
                insertCopyOfRow(m_menuRow);
            else
                addEvent();
            break;
        case kRowMenuShowVoice: {
            if (!hasChunk(m_document, m_model->chunk()))
                break;
            const auto index = m_model->rawEventIndexForRow(m_menuRow);
            const auto &events = m_document->smf().tracks[m_model->chunk()].events;
            if (index && *index < events.size() &&
                eventlist::typeKindOf(events[*index]) == eventlist::TypeProgram) {
                emit revealVoice(events[*index].data0);
            }
            break;
        }
        // Move up/down are action-backed rows: the host triggers the
        // canonical MoveEventUp/MoveEventDown QActions directly, so no
        // activated case exists for them.
        case kRowMenuDelete:
            deleteSelected();
            break;
        }
    });
    connect(m_typeMenu, &songview::QuickMenuModel::activated, this, [this](int type) {
        if (m_menuRow >= 0) {
            commitCellEdit(m_menuRow, eventlist::EventTableModel::ColType, QString::number(type));
        }
        m_menuRow = -1;
    });
    rebuildAppearance();
}

void EventListController::rebuildAppearance()
{
    const QFont body = QApplication::font();
    const QFont tableFont = typography::tableMono(body);
    QVariantMap next;
    next.insert(QStringLiteral("tableBackground"), themes::color(themes::Role::item_background));
    next.insert(QStringLiteral("tableAlternateBackground"),
                themes::color(themes::Role::item_alternate_background));
    next.insert(QStringLiteral("tableText"), themes::color(themes::Role::item_text));
    next.insert(QStringLiteral("tableSecondaryText"), themes::color(themes::Role::secondary_text));
    next.insert(QStringLiteral("tableSelectedBackground"),
                themes::color(themes::Role::item_selected_background));
    next.insert(QStringLiteral("tableSelectedText"),
                themes::color(themes::Role::item_selected_text));
    next.insert(QStringLiteral("tableOutline"), themes::color(themes::Role::palette_outline));
    next.insert(QStringLiteral("playheadTint"), QColor(226, 66, 66, 44));
    next.insert(QStringLiteral("headerBackground"), themes::color(themes::Role::header_background));
    next.insert(QStringLiteral("headerText"), themes::color(themes::Role::header_text));
    next.insert(QStringLiteral("headerOutline"), themes::color(themes::Role::header_outline));
    next.insert(QStringLiteral("buttonBackground"), themes::color(themes::Role::button_background));
    next.insert(QStringLiteral("buttonText"), themes::color(themes::Role::button_text));
    next.insert(QStringLiteral("buttonHoverBackground"),
                themes::color(themes::Role::button_hover_background));
    next.insert(QStringLiteral("buttonPressedBackground"),
                themes::color(themes::Role::button_pressed_background));
    next.insert(QStringLiteral("buttonOutline"), themes::color(themes::Role::button_outline));
    next.insert(QStringLiteral("scrollbarHandle"), themes::color(themes::Role::scrollbar_handle));
    next.insert(QStringLiteral("scrollbarHandleHover"),
                themes::color(themes::Role::scrollbar_handle_hover_background));
    next.insert(QStringLiteral("toolTipBackground"),
                themes::color(themes::Role::tooltip_background));
    next.insert(QStringLiteral("toolTipText"), themes::color(themes::Role::tooltip_text));
    next.insert(QStringLiteral("toolTipOutline"), themes::color(themes::Role::tooltip_outline));
    next.insert(QStringLiteral("inputBackground"), themes::color(themes::Role::input_background));
    next.insert(QStringLiteral("inputText"), themes::color(themes::Role::input_text));
    next.insert(QStringLiteral("inputOutline"), themes::color(themes::Role::input_outline));
    next.insert(QStringLiteral("focusOutline"), themes::color(themes::Role::focus_outline));
    next.insert(QStringLiteral("bodyFont"), QVariant::fromValue(body));
    next.insert(QStringLiteral("bodyItalicFont"), QVariant::fromValue(typography::italic(body)));
    next.insert(QStringLiteral("tableFont"), QVariant::fromValue(tableFont));
    next.insert(QStringLiteral("tableItalicFont"),
                QVariant::fromValue(typography::italic(tableFont)));
    next.insert(QStringLiteral("headerFont"),
                QVariant::fromValue(typography::caption(typography::bodyMono(body))));
    next.insert(QStringLiteral("controlFont"), QVariant::fromValue(body));
    if (next == m_appearance)
        return;
    m_appearance = std::move(next);
    if (m_menuHost) {
        QVariantMap menuAppearance;
        menuAppearance.insert(QStringLiteral("font"), QVariant::fromValue(body));
        menuAppearance.insert(QStringLiteral("background"),
                              themes::color(themes::Role::menu_background));
        menuAppearance.insert(QStringLiteral("outline"), themes::color(themes::Role::menu_outline));
        menuAppearance.insert(QStringLiteral("text"), themes::color(themes::Role::menu_text));
        menuAppearance.insert(QStringLiteral("hoverBackground"),
                              themes::color(themes::Role::menu_item_hover_background));
        menuAppearance.insert(QStringLiteral("hoverText"),
                              themes::color(themes::Role::menu_item_hover_text));
        menuAppearance.insert(QStringLiteral("pressedBackground"),
                              themes::color(themes::Role::menu_item_pressed_background));
        menuAppearance.insert(QStringLiteral("pressedText"),
                              themes::color(themes::Role::menu_item_pressed_text));
        menuAppearance.insert(QStringLiteral("disabledText"),
                              themes::color(themes::Role::disabled_text));
        menuAppearance.insert(QStringLiteral("separator"),
                              themes::color(themes::Role::menu_separator));
        m_menuHost->setAppearance(std::move(menuAppearance));
    }
    emit appearanceChanged();
}

QString EventListController::filterSummary() const
{
    QStringList checked;
    for (const FilterCategory &category : kFilterCategories) {
        if (m_filterMask & category.bit)
            checked.append(tr(category.text));
    }
    if (checked.size() == int(std::size(kFilterCategories)))
        return tr("All events");
    if (checked.isEmpty())
        return tr("No events");
    if (checked.size() == 1)
        return checked.first();
    return tr("%1 +%2").arg(checked.first()).arg(checked.size() - 1);
}

QString EventListController::countText() const
{
    if (!hasChunk(m_document, m_currentChunk))
        return {};
    const size_t total = m_document->smf().tracks[m_currentChunk].events.size() +
                         (m_currentChunk == 0 ? m_document->tempoPoints().size() : 0);
    const size_t shown = m_model->shownEvents();
    return shown == total ? tr("%n event(s)", nullptr, int(total))
                          : tr("%1 of %2 events").arg(shown).arg(total);
}

QStringList EventListController::headerLabels() const
{
    return {tr("Tick"),   tr("Type"), tr("Ch"),     tr("Data 1"),
            tr("Data 2"), tr("Data"), tr("Summary")};
}

int EventListController::headerAlignment(int column) const
{
    return m_model->headerData(column, Qt::Horizontal, Qt::TextAlignmentRole).toInt();
}

void EventListController::rebuildChunks()
{
    QStringList labels;
    if (m_document) {
        const SmfFile &smf = m_document->smf();
        labels.reserve(int(smf.tracks.size()));
        for (int chunk = 0; chunk < int(smf.tracks.size()); ++chunk) {
            int engineTrack = -1;
            for (int track = 0; track < m_document->engineTrackCount(); ++track) {
                if (m_document->smfTrackFor(track) == chunk) {
                    engineTrack = track;
                    break;
                }
            }
            labels.append(engineTrack >= 0
                              ? tr("Chunk %1 — Track %2").arg(chunk).arg(engineTrack + 1)
                              : tr("Chunk %1 (tempo/meta)").arg(chunk));
        }
    }
    if (labels == m_chunkLabels)
        return;
    m_chunkLabels = std::move(labels);
    emit chunkLabelsChanged();
}

void EventListController::setDocument(SongDocument *document)
{
    if (m_document == document) {
        rebuildChunks();
        const int target = hasChunk(m_document, m_currentChunk)
                               ? m_currentChunk
                               : (m_chunkLabels.isEmpty() ? -1 : 0);
        setChunk(target, false);
        return;
    }

    if (m_document)
        disconnect(m_document, nullptr, this, nullptr);
    m_document = document;
    m_documentRevision = document ? document->revision() : 0;
    m_chunkRemapped = false;
    if (m_document) {
        connect(m_document, &SongDocument::tracksRemapped, this,
                &EventListController::onTracksRemapped);
        connect(m_document, &SongDocument::documentChanged, this, &EventListController::refresh);
    }

    rebuildChunks();
    const int target =
        hasChunk(m_document, m_currentChunk) ? m_currentChunk : (m_chunkLabels.isEmpty() ? -1 : 0);
    if (target != m_currentChunk) {
        m_currentChunk = target;
        emit chunkChanged();
    }
    m_model->setSource(m_document, target);
    m_selectionAnchor = -1;
    setCurrentRow(-1);
    setSelectedRows({});
    updateCountText();
    updatePlayRow();
    if (m_visible)
        syncTrackSelection();
}

void EventListController::setChunk(int chunk, bool followTrack)
{
    const int target = hasChunk(m_document, chunk) ? chunk : -1;
    if (target == m_currentChunk && m_model->chunk() == target)
        return;

    m_currentChunk = target;
    emit chunkChanged();
    m_model->setSource(m_document, target);
    m_selectionAnchor = -1;
    setCurrentRow(-1);
    setSelectedRows({});
    updateCountText();
    updatePlayRow();

    if (!followTrack || target < 0 || !m_songView)
        return;
    for (int track = 0; track < m_document->engineTrackCount(); ++track) {
        if (m_document->smfTrackFor(track) != target)
            continue;
        if (track != m_songView->selectionModel().primaryTrack()) {
            m_syncing = true;
            m_songView->selectTrack(track);
            m_syncing = false;
        }
        break;
    }
}

void EventListController::refresh()
{
    if (!m_document) {
        m_documentRevision = 0;
        m_model->setSource(nullptr, -1);
        rebuildChunks();
        setCurrentRow(-1);
        setSelectedRows({});
        updateCountText();
        return;
    }
    if (!m_visible)
        return;

    const int savedCurrent = m_currentRow;
    const QList<int> savedSelection = m_selectedRows;
    const bool chunkCountChanged = m_chunkLabels.size() != int(m_document->smf().tracks.size());
    if (m_chunkRemapped || chunkCountChanged) {
        const int target = hasChunk(m_document, m_currentChunk) ? m_currentChunk : -1;
        m_chunkRemapped = false;
        rebuildChunks();
        if (target != m_currentChunk) {
            m_currentChunk = target;
            emit chunkChanged();
        }
        m_model->setSource(m_document, target);
    } else {
        m_model->reload();
    }

    const int rows = m_model->rowCount();
    setCurrentRow(savedCurrent >= 0 && rows > 0 ? std::min(savedCurrent, rows - 1) : -1);
    QList<int> restored;
    for (int row : savedSelection) {
        if (row >= 0 && row < rows)
            restored.append(row);
    }
    setSelectedRows(std::move(restored));
    updateCountText();
    updatePlayRow();
    m_documentRevision = m_document->revision();
}

void EventListController::syncTrackSelection()
{
    if (m_syncing || !m_visible || !m_document || m_document->revision() != m_documentRevision ||
        !m_songView)
        return;
    const int chunk = m_document->smfTrackFor(m_songView->selectionModel().primaryTrack());
    if (chunk < 0 || chunk == m_currentChunk)
        return;
    setChunk(chunk, false);
}

void EventListController::onTracksRemapped(const TrackRemap &remap)
{
    const int remapped = m_currentChunk >= 0 && size_t(m_currentChunk) < remap.smfTrackMap.size()
                             ? remap.smfTrackMap[size_t(m_currentChunk)]
                             : -1;
    if (remapped != m_currentChunk) {
        m_currentChunk = remapped;
        emit chunkChanged();
    }
    m_chunkRemapped = true;
}

void EventListController::setVisible(bool visible)
{
    if (m_visible == visible)
        return;
    m_visible = visible;
    if (!visible) {
        m_menuHost->close();
        clearEditing();
    }
    emit visibleChanged();
    if (visible) {
        refresh();
        syncTrackSelection();
    }
}

void EventListController::setPlayheadTick(double tick, bool playing)
{
    if (m_playTick == tick && m_playing == playing)
        return;
    m_playTick = tick;
    m_playing = playing;
    updatePlayRow();
}

void EventListController::setFollowPlayhead(bool on)
{
    if (m_followPlayhead == on)
        return;
    m_followPlayhead = on;
    emit followPlayheadChanged();
}

void EventListController::syncAppearance()
{
    rebuildAppearance();
}

void EventListController::updatePlayRow()
{
    if (!m_visible)
        return;
    int row = m_model->playheadRowAtOrBeforeTick(m_playTick);
    if (m_playTick >= 0 && m_currentRow >= 0 && m_currentRow != row) {
        if (const auto tick = m_model->exactTickForRow(m_currentRow)) {
            if (std::abs(double(*tick) - m_playTick) < 0.5)
                row = m_currentRow;
        }
    }
    if (row == m_playRow && row == m_model->playRow())
        return;

    m_model->setPlayRow(row);
    if (m_playRow != row) {
        m_playRow = row;
        emit playRowChanged(row);
    }
    if (!m_playing || row < 0 || !m_followPlayhead || m_pointerDown || isEditing() || m_menuOpen ||
        QApplication::mouseButtons() != Qt::NoButton)
        return;
    emit scrollToRow(row);
}

void EventListController::setCurrentRow(int row)
{
    const int count = m_model->rowCount();
    const int next = row >= 0 && count > 0 ? std::min(row, count - 1) : -1;
    if (next == m_currentRow)
        return;
    m_currentRow = next;
    emit currentRowChanged();
}

void EventListController::setSelectedRows(QList<int> rows)
{
    const int count = m_model->rowCount();
    rows.erase(std::remove_if(rows.begin(), rows.end(),
                              [count](int row) { return row < 0 || row >= count; }),
               rows.end());
    std::sort(rows.begin(), rows.end());
    rows.erase(std::unique(rows.begin(), rows.end()), rows.end());
    if (rows == m_selectedRows)
        return;
    m_selectedRows = std::move(rows);
    m_selectedRowSet.clear();
    for (int row : m_selectedRows)
        m_selectedRowSet.insert(row);
    emit selectedRowsChanged();
}

bool EventListController::isSelected(int row) const
{
    return m_selectedRowSet.contains(row);
}

void EventListController::selectRow(int row, int modifiers)
{
    if (row < 0 || row >= m_model->rowCount()) {
        m_selectionAnchor = -1;
        setCurrentRow(-1);
        setSelectedRows({});
        return;
    }

    const Qt::KeyboardModifiers keys = Qt::KeyboardModifiers(modifiers);
    const bool control = keys.testFlag(Qt::ControlModifier);
    const bool shift = keys.testFlag(Qt::ShiftModifier);
    QList<int> next = control ? m_selectedRows : QList<int>{};
    if (shift) {
        const int anchor =
            m_selectionAnchor >= 0 ? m_selectionAnchor : (m_currentRow >= 0 ? m_currentRow : row);
        const int first = std::min(anchor, row);
        const int last = std::max(anchor, row);
        if (!control)
            next.clear();
        for (int selected = first; selected <= last; ++selected)
            next.append(selected);
    } else if (control) {
        const auto it = std::find(next.begin(), next.end(), row);
        if (it == next.end())
            next.append(row);
        else
            next.erase(it);
    } else {
        next = {row};
        m_selectionAnchor = row;
    }
    if (!shift && control && m_selectionAnchor < 0)
        m_selectionAnchor = row;
    setSelectedRows(std::move(next));
    setCurrentRow(row);
    jumpCursorToRow(row);
}

void EventListController::focusRow(int row)
{
    if (row < 0 || row >= m_model->rowCount())
        return;
    setCurrentRow(row);
    jumpCursorToRow(row);
}

void EventListController::selectAll()
{
    QList<int> all;
    const int count = m_model->rowCount();
    all.reserve(count);
    for (int row = 0; row < count; ++row)
        all.append(row);
    setSelectedRows(std::move(all));
    if (m_currentRow < 0 && count > 0)
        setCurrentRow(0);
}

void EventListController::clearEditing()
{
    if (!isEditing())
        return;
    m_editingRow = -1;
    m_editingColumn = -1;
    emit editingChanged();
}

void EventListController::setPointerDown(bool pointerDown)
{
    m_pointerDown = pointerDown;
}

void EventListController::jumpCursorToRow(int row)
{
    if (!hasChunk(m_document, m_model->chunk()) || !m_songView)
        return;
    const auto rowTick = m_model->exactTickForRow(row);
    Tick tick = 0;
    if (rowTick) {
        tick = *rowTick;
    } else {
        if (row != int(m_model->shownEvents()))
            return;
        tick = m_document->smf().tracks[m_model->chunk()].endTick;
    }
    if (tick != m_songView->editCursorTick()) {
        m_songView->commitEditCursor(tick);
        m_songView->ensureTickVisible(tick);
    }
    updatePlayRow();
}

void EventListController::chunkPicked(int comboIndex)
{
    if (!m_syncing)
        setChunk(comboIndex, true);
}

void EventListController::filterToggled(int bit)
{
    if ((bit & eventlist::EventTableModel::FilterAll) != bit || bit == 0)
        return;
    m_filterMask ^= bit;
    m_model->setFilter(m_filterMask);
    rebuildFilterMenu();
    m_selectionAnchor = -1;
    setCurrentRow(-1);
    setSelectedRows({});
    emit filterMaskChanged();
    emit filterSummaryChanged();
    updateCountText();
    updatePlayRow();
}

void EventListController::addEvent()
{
    const int currentChunk = m_currentChunk;
    if (!hasChunk(m_document, currentChunk) || !m_songView)
        return;
    if (currentChunk == 0) {
        if (const auto tempo = m_model->tempoPointForRow(m_currentRow)) {
            const TempoPoint copy{Tick(m_songView->editCursorTick()),
                                  tempo->microsecondsPerQuarterNote};
            m_document->applyTempoEdit({{}, {copy}});
            selectRowAtTick(currentChunk, copy.tick);
            return;
        }
    }
    const auto &events = m_document->smf().tracks[currentChunk].events;
    SmfEvent event;
    const auto source = m_model->rawEventIndexForRow(m_currentRow);
    if (source && *source < events.size()) {
        event = events[*source];
    } else {
        event.status = uint8_t(0xB0 | m_model->fallbackChannel());
        event.data0 = 7;
        event.data1 = 100;
    }
    event.tick = m_songView->editCursorTick();
    m_document->insertRawEvent(currentChunk, event);
    selectEventRow(currentChunk, event);
}

void EventListController::insertCopyOfRow(int row)
{
    const int currentChunk = m_currentChunk;
    if (!hasChunk(m_document, currentChunk))
        return;
    if (currentChunk == 0) {
        if (const auto tempo = m_model->tempoPointForRow(row)) {
            m_document->applyTempoEdit({{}, {*tempo}});
            selectRowAtTick(currentChunk, tempo->tick);
            return;
        }
    }
    const auto &events = m_document->smf().tracks[currentChunk].events;
    const auto source = m_model->rawEventIndexForRow(row);
    if (!source || *source >= events.size())
        return;
    const SmfEvent event = events[*source];
    m_document->insertRawEvent(currentChunk, event);
    selectEventRow(currentChunk, event);
}

void EventListController::deleteSelected()
{
    const int currentChunk = m_currentChunk;
    if (!hasChunk(m_document, currentChunk))
        return;
    std::vector<size_t> indices;
    TempoEdit tempoEdit;
    for (int row : m_selectedRows) {
        if (const auto index = m_model->rawEventIndexForRow(row)) {
            indices.push_back(*index);
            continue;
        }
        if (const auto tempo = m_model->tempoPointForRow(row))
            tempoEdit.remove.push_back(*tempo);
    }
    if (indices.empty() && tempoEdit.empty())
        return;
    if (indices.size() + tempoEdit.remove.size() > 1) {
        m_selectionAnchor = -1;
        setCurrentRow(-1);
        setSelectedRows({});
    }
    if (!indices.empty() && !tempoEdit.empty()) {
        const int count = int(indices.size() + tempoEdit.remove.size());
        m_document->removeRawEventsAndEditTempo(tr("delete %n event(s)", nullptr, count),
                                                currentChunk, std::move(indices), tempoEdit);
    } else if (!indices.empty()) {
        m_document->deleteRawEvents(currentChunk, std::move(indices));
    } else {
        m_document->applyTempoEdit(tempoEdit);
    }
}

void EventListController::reorderRawEvent(size_t from, size_t destination)
{
    const int currentChunk = m_model->chunk();
    if (!hasChunk(m_document, currentChunk))
        return;
    size_t first = 0;
    size_t last = 0;
    if (!m_document->rawEventMoveBounds(currentChunk, from, &first, &last))
        return;
    destination = std::clamp(destination, first, last);
    if (destination == from)
        return;
    m_document->moveRawEvent(currentChunk, from, destination);
    const int row = m_model->rowForRawEventIndex(destination);
    if (row >= 0) {
        setCurrentRow(row);
        setSelectedRows({row});
        emit scrollToRow(row);
    }
    updatePlayRow();
}

bool EventListController::isLegalRawMove(size_t source, size_t destination) const
{
    const int currentChunk = m_model->chunk();
    if (!hasChunk(m_document, currentChunk))
        return false;
    size_t first = 0;
    size_t last = 0;
    return m_document->rawEventMoveBounds(currentChunk, source, &first, &last) &&
           destination >= first && destination <= last && destination != source;
}

bool EventListController::dropDestinationForGap(int fromRow, int gap, size_t *source,
                                                size_t *destination) const
{
    if (!source || !destination || gap < 0)
        return false;
    const auto rawSource = m_model->rawEventIndexForRow(fromRow);
    if (!rawSource)
        return false;

    const int eventRows = int(m_model->shownEvents());
    if (eventRows < 1 || gap > eventRows)
        return false;
    size_t rawDestination = *rawSource;
    if (gap < eventRows) {
        const auto rawTarget = m_model->rawEventIndexForRow(gap);
        if (!rawTarget)
            return false;
        rawDestination = *rawTarget > *rawSource ? *rawTarget - 1 : *rawTarget;
    } else {
        const auto rawTarget = m_model->rawEventIndexForRow(eventRows - 1);
        if (!rawTarget)
            return false;
        rawDestination = *rawTarget > *rawSource ? *rawTarget : *rawSource;
    }
    const auto anchor = m_model->rawEventIndexForRow(gap > 0 ? gap - 1 : 0);
    const int currentChunk = m_model->chunk();
    if (!anchor || !hasChunk(m_document, currentChunk))
        return false;
    const auto &events = m_document->smf().tracks[currentChunk].events;
    if (*rawSource >= events.size() || *anchor >= events.size() ||
        events[*rawSource].tick != events[*anchor].tick)
        return false;
    size_t first = 0;
    size_t last = 0;
    if (!m_document->rawEventMoveBounds(currentChunk, *rawSource, &first, &last))
        return false;
    rawDestination = std::clamp(rawDestination, first, last);
    *source = *rawSource;
    *destination = rawDestination;
    return true;
}

bool EventListController::isLegalDrop(int fromRow, int gap) const
{
    size_t source = 0;
    size_t destination = 0;
    return dropDestinationForGap(fromRow, gap, &source, &destination) &&
           isLegalRawMove(source, destination);
}

void EventListController::commitDrop(int fromRow, int gap)
{
    size_t source = 0;
    size_t destination = 0;
    if (!dropDestinationForGap(fromRow, gap, &source, &destination) ||
        !isLegalRawMove(source, destination))
        return;
    reorderRawEvent(source, destination);
}

void EventListController::reorderRows(int fromRow, int toRow)
{
    const auto source = m_model->rawEventIndexForRow(fromRow);
    const auto target = m_model->rawEventIndexForRow(toRow);
    if (!source || !target || !isLegalRawMove(*source, *target))
        return;
    reorderRawEvent(*source, *target);
}

qlonglong EventListController::moveDestForRow(int row, int delta, QString *why) const
{
    const int currentChunk = m_model->chunk();
    if (!hasChunk(m_document, currentChunk))
        return -1;
    const auto source = m_model->rawEventIndexForRow(row);
    const auto target = m_model->rawEventIndexForRow(row + delta);
    if (!source || !target)
        return -1;
    const auto &events = m_document->smf().tracks[currentChunk].events;
    if (*source >= events.size() || *target >= events.size())
        return -1;
    if (events[*target].tick != events[*source].tick) {
        if (why)
            *why = tr("Events reorder within their tick — edit the Tick cell to retime");
        return -1;
    }
    size_t first = 0;
    size_t last = 0;
    if (!m_document->rawEventMoveBounds(currentChunk, *source, &first, &last))
        return -1;
    if (*target < first || *target > last) {
        if (why) {
            *why = tr("Setup events stay ahead of same-tick notes, and note ends ahead of "
                      "note-ons");
        }
        return -1;
    }
    return qlonglong(*target);
}

qlonglong EventListController::moveDestForRow(int row, int delta) const
{
    return moveDestForRow(row, delta, nullptr);
}

bool EventListController::canMoveCurrentRow(int delta) const
{
    return m_visible && !isEditing() && m_currentRow >= 0 &&
           moveDestForRow(m_currentRow, delta) >= 0;
}

void EventListController::moveCurrentRow(int delta)
{
    QString why;
    const qlonglong destination = moveDestForRow(m_currentRow, delta, &why);
    if (destination < 0) {
        if (!why.isEmpty())
            emit announce(why);
        return;
    }
    if (const auto source = m_model->rawEventIndexForRow(m_currentRow))
        reorderRawEvent(*source, size_t(destination));
}

bool EventListController::isCellEditable(int row, int column) const
{
    const QModelIndex index = m_model->index(row, column);
    return index.isValid() && m_model->flags(index).testFlag(Qt::ItemIsEditable);
}

bool EventListController::editValueFor(int row, int column, const QString &text,
                                       QVariant *value) const
{
    if (!value || !isCellEditable(row, column))
        return false;

    bool ok = false;
    switch (column) {
    case eventlist::EventTableModel::ColTick: {
        text.toULongLong(&ok);
        if (!ok || text.toULongLong() > CoreTimeDefaults::kMaxTick)
            return false;
        *value = text;
        return true;
    }
    case eventlist::EventTableModel::ColType: {
        const int type = text.toInt(&ok);
        if (!ok || type < 0 || type >= eventlist::TypeKindCount ||
            (type == eventlist::TypeTempo && !m_model->qmlHasTempo(row) && m_model->chunk() != 0))
            return false;
        *value = type;
        return true;
    }
    case eventlist::EventTableModel::ColChannel: {
        const int channel = text.toInt(&ok);
        if (!ok || channel < 1 || channel > 16)
            return false;
        *value = channel;
        return true;
    }
    case eventlist::EventTableModel::ColData1:
    case eventlist::EventTableModel::ColData2: {
        const int data = text.toInt(&ok);
        if (!ok || data < 0 || data > 127)
            return false;
        *value = data;
        return true;
    }
    case eventlist::EventTableModel::ColData:
        if (m_model->qmlHasTempo(row)) {
            const int bpm = text.trimmed().toInt(&ok);
            if (!ok || bpm < 20 || bpm > 255)
                return false;
        } else {
            QByteArray blob;
            if (!eventlist::parseBlob(text, &blob))
                return false;
        }
        *value = text;
        return true;
    default:
        return false;
    }
}

bool EventListController::validateCellEdit(int row, int column, const QString &text) const
{
    QVariant value;
    return editValueFor(row, column, text, &value);
}

bool EventListController::commitCellEdit(int row, int column, const QString &text)
{
    QVariant value;
    return editValueFor(row, column, text, &value) &&
           m_model->setData(m_model->index(row, column), value, Qt::EditRole);
}

bool EventListController::beginEditing(int row, int column)
{
    if (isEditing() || !isCellEditable(row, column))
        return false;
    m_editingRow = row;
    m_editingColumn = column;
    emit editingChanged();
    return true;
}

bool EventListController::finishEditing(const QString &text, bool commit)
{
    if (!isEditing())
        return false;
    if (commit && !commitCellEdit(m_editingRow, m_editingColumn, text))
        return false;
    clearEditing();
    return true;
}

bool EventListController::canStepEditing() const
{
    if (!isEditing())
        return false;
    switch (m_editingColumn) {
    case eventlist::EventTableModel::ColChannel:
    case eventlist::EventTableModel::ColData1:
    case eventlist::EventTableModel::ColData2:
        return true;
    case eventlist::EventTableModel::ColData:
        return m_model->qmlHasTempo(m_editingRow);
    default:
        return false;
    }
}

QString EventListController::steppedEditingText(const QString &currentText, int delta) const
{
    if (!canStepEditing() || delta == 0)
        return currentText;
    int minimum = 0;
    int maximum = 0;
    switch (m_editingColumn) {
    case eventlist::EventTableModel::ColChannel:
        minimum = 1;
        maximum = 16;
        break;
    case eventlist::EventTableModel::ColData1:
    case eventlist::EventTableModel::ColData2:
        maximum = 127;
        break;
    case eventlist::EventTableModel::ColData:
        if (!m_model->qmlHasTempo(m_editingRow))
            return currentText;
        minimum = 20;
        maximum = 255;
        break;
    default:
        return currentText;
    }
    bool ok = false;
    const qlonglong current = currentText.toLongLong(&ok);
    if (!ok || current < minimum || current > maximum)
        return currentText;
    return QString::number(
        std::clamp(current + qlonglong(delta), qlonglong(minimum), qlonglong(maximum)));
}

QString EventListController::rowTickString(int row) const
{
    return m_model->qmlTickString(row);
}

void EventListController::resizeColumn(int column, double width)
{
    if (column < eventlist::EventTableModel::ColTick ||
        column > eventlist::EventTableModel::ColData || !std::isfinite(width))
        return;
    const double next = std::max(24.0, width);
    if (m_columnWidths[column] == next)
        return;
    m_columnWidths[column] = next;
    emit columnWidthsChanged();
}

void EventListController::setPopupSession(songview::QuickPopupSession *session)
{
    m_menuHost->setPopupSession(session);
}

void EventListController::rebuildChunkMenu()
{
    std::vector<songview::QuickMenuItem> items;
    items.reserve(size_t(m_chunkLabels.size()));
    for (int chunk = 0; chunk < m_chunkLabels.size(); ++chunk) {
        songview::QuickMenuItem item = menuItem(chunk, m_chunkLabels[chunk]);
        item.checkable = true;
        item.checked = chunk == m_currentChunk;
        items.push_back(std::move(item));
    }
    m_chunkMenu->setItems(std::move(items));
}

void EventListController::rebuildFilterMenu()
{
    std::vector<songview::QuickMenuItem> items;
    items.reserve(std::size(kFilterCategories));
    for (const FilterCategory &category : kFilterCategories) {
        songview::QuickMenuItem item = menuItem(category.bit, tr(category.text));
        item.checkable = true;
        item.checked = m_filterMask & category.bit;
        item.stayOpen = true;
        items.push_back(std::move(item));
    }
    m_filterMenu->setItems(std::move(items));
}

void EventListController::rebuildRowMenu(int row)
{
    std::vector<songview::QuickMenuItem> items;
    items.push_back(menuItem(kRowMenuInsert, tr("Insert event")));
    const auto source = m_model->rawEventIndexForRow(row);
    if (source && hasChunk(m_document, m_model->chunk())) {
        const auto &events = m_document->smf().tracks[m_model->chunk()].events;
        if (*source < events.size() &&
            eventlist::typeKindOf(events[*source]) == eventlist::TypeProgram)
            items.push_back(menuItem(kRowMenuShowVoice, tr("Show voice in voicegroup")));
    }
    if (source) {
        // The canonical actions carry text, shortcut and live eligibility;
        // the host triggers them directly on the current row established
        // before open.
        const songview::EditActions *const actions =
            m_songView ? m_songView->editActions() : nullptr;
        QAction *const moveUp =
            actions ? actions->action(SongView::EditCommand::MoveEventUp) : nullptr;
        QAction *const moveDown =
            actions ? actions->action(SongView::EditCommand::MoveEventDown) : nullptr;
        if (moveUp && moveDown) {
            items.push_back(songview::QuickMenuItem::makeSeparator());
            items.push_back(songview::QuickMenuItem::fromAction(*moveUp, kRowMenuMoveUp));
            items.push_back(songview::QuickMenuItem::fromAction(*moveDown, kRowMenuMoveDown));
        }
    }
    items.push_back(songview::QuickMenuItem::makeSeparator());

    int deletable = 0;
    for (int selected : m_selectedRows) {
        if (m_model->rawEventIndexForRow(selected) || m_model->qmlHasTempo(selected))
            ++deletable;
    }
    items.push_back(menuItem(
        kRowMenuDelete, deletable > 0 ? tr("Delete %n event(s)", nullptr, deletable) : tr("Delete"),
        deletable > 0));
    m_rowMenu->setItems(std::move(items));
}

void EventListController::rebuildTypeMenu()
{
    std::vector<songview::QuickMenuItem> items;
    const QModelIndex current = m_model->index(m_menuRow, eventlist::EventTableModel::ColType);
    const int selected = current.isValid() ? current.data(Qt::EditRole).toInt() : -1;
    for (int type = 0; type < eventlist::TypeKindCount; ++type) {
        if (type == eventlist::TypeTempo && m_model->chunk() != 0)
            continue;
        songview::QuickMenuItem item = menuItem(type, eventlist::typeKindName(type));
        item.checkable = true;
        item.checked = type == selected;
        items.push_back(std::move(item));
    }
    m_typeMenu->setItems(std::move(items));
}

void EventListController::updateMenuOpen(bool open)
{
    if (m_menuOpen == open)
        return;
    m_menuOpen = open;
    emit menuOpenChanged();
}

void EventListController::openMenu(songview::QuickMenuModel *model, const QPointF &scenePosition)
{
    if (!model || !m_menuHost)
        return;
    m_menuHost->open(model, scenePosition);
    updateMenuOpen(m_menuHost->isOpen());
}

void EventListController::openChunkMenu(const QPointF &scenePosition)
{
    rebuildChunkMenu();
    openMenu(m_chunkMenu, scenePosition);
}

void EventListController::openFilterMenu(const QPointF &scenePosition)
{
    rebuildFilterMenu();
    openMenu(m_filterMenu, scenePosition);
}

void EventListController::openRowMenu(const QPointF &scenePosition)
{
    const int row = m_currentRow;
    m_menuRow = row;
    rebuildRowMenu(row);
    openMenu(m_rowMenu, scenePosition);
}

void EventListController::openTypeMenu(const QPointF &scenePosition)
{
    const QModelIndex typeIndex = m_model->index(m_currentRow, eventlist::EventTableModel::ColType);
    if (!typeIndex.isValid() || !m_model->flags(typeIndex).testFlag(Qt::ItemIsEditable))
        return;
    m_menuRow = m_currentRow;
    rebuildTypeMenu();
    openMenu(m_typeMenu, scenePosition);
}

void EventListController::selectRowAtTick(int chunk, Tick tick)
{
    if (!m_document || m_model->chunk() != chunk)
        return;
    int row = m_model->tempoRowForExactTick(tick);
    if (row < 0) {
        for (int candidate = 0; candidate < m_model->rowCount(); ++candidate) {
            if (!m_model->rawEventIndexForRow(candidate))
                continue;
            const auto candidateTick = m_model->exactTickForRow(candidate);
            if (candidateTick && *candidateTick == tick) {
                row = candidate;
                break;
            }
        }
    }
    if (row < 0)
        return;
    setCurrentRow(row);
    setSelectedRows({row});
    emit scrollToRow(row);
}

void EventListController::selectEventRow(int chunk, const SmfEvent &target)
{
    if (!hasChunk(m_document, chunk) || m_model->chunk() != chunk)
        return;
    const auto &events = m_document->smf().tracks[chunk].events;
    for (size_t index = 0; index < events.size(); ++index) {
        if (events[index] != target)
            continue;
        const int row = m_model->rowForRawEventIndex(index);
        if (row >= 0) {
            setCurrentRow(row);
            setSelectedRows({row});
            emit scrollToRow(row);
        }
        return;
    }
}

void EventListController::updateCountText()
{
    emit countTextChanged();
}

bool EventListController::handleLocalKey(int key, Qt::KeyboardModifiers modifiers)
{
    if (isEditing() || m_menuOpen || (key == Qt::Key_Space && modifiers == Qt::NoModifier))
        return false;
    if ((key == Qt::Key_Up || key == Qt::Key_Down) &&
        (modifiers == Qt::NoModifier || modifiers == Qt::ShiftModifier)) {
        const int count = m_model->rowCount();
        if (count > 0) {
            const int current = m_currentRow >= 0 ? m_currentRow : 0;
            const int delta = key == Qt::Key_Up ? -1 : 1;
            const int target = std::clamp(current + delta, 0, count - 1);
            if (target != current || m_currentRow < 0) {
                selectRow(target, int(modifiers));
                emit scrollToRow(target);
            }
        }
        return true;
    }
    if (key == Qt::Key_Delete || key == Qt::Key_Backspace) {
        deleteSelected();
        return true;
    }
    const keymap::Registry &keys = keymap::Registry::instance();
    if (keys.matches(key, modifiers, QStringLiteral("roll.select_all"))) {
        selectAll();
        return true;
    }
    // eventlist.move_up/move_down deliberately have no local matcher: the
    // shared editor arbitration triggers the canonical MoveEventRow actions,
    // which delegate to canMoveCurrentRow/moveCurrentRow.
    return false;
}

bool EventListController::handleKey(QKeyEvent *event)
{
    if (!event)
        return false;
    if (event->type() == QEvent::ShortcutOverride) {
        if (!isEditing() && !m_menuOpen && event->key() == Qt::Key_Space &&
            event->modifiers() == Qt::NoModifier)
            event->ignore();
        return false;
    }
    if (event->type() != QEvent::KeyPress)
        return false;
    return handleLocalKey(event->key(), event->modifiers());
}

void songview::EventListInteraction::attachInputHost(TimelineInputHost &host)
{
    Q_UNUSED(host);
}

void songview::EventListInteraction::detachInputHost(TimelineInputHost &host)
{
    Q_UNUSED(host);
}

bool songview::EventListInteraction::keyPress(const TimelineKeyInput &input)
{
    return m_controller.handleLocalKey(input.key, input.modifiers);
}
