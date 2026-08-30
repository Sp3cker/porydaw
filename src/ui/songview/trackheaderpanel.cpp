// ---------------------------------------------------------- TrackHeaderPanel

#include "ui/songview/trackheaderpanel.h"

#include "ui/activity/trackactivitypresentation.h"
#include "ui/activity/trackactivityrender.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/trackheaderrow.h"

#include <QApplication>
#include <QEvent>
#include <QPushButton>
#include <QVBoxLayout>
#include <cstddef>

namespace lyt = ::layout;
using Space = lyt::Space;

namespace songview {

TrackHeaderPanel::Geometry TrackHeaderPanel::Geometry::resolve()
{
    // The row height comes from the single formula in TrackHeaderRow.
    return {lyt::fontPx(0.25), TrackHeaderRow::resolvedHeight()};
}

void TrackHeaderPanel::refreshGeometry()
{
    m_geometry = Geometry::resolve();
    m_indicator->setFixedHeight(m_geometry.trackHeaderReorderIndicatorHeight);
    if (m_indicator->isVisible())
        m_indicator->resize(width(), m_geometry.trackHeaderReorderIndicatorHeight);
    // Rows settle their own FontChange around this event, but the stride is
    // already final: rows and panel both consume TrackHeaderRow::resolvedHeight.
    // The presentation re-applies its cached activity synchronously.
    synchronizeTrackDefinitions();
    update();
}

TrackHeaderPanel::TrackHeaderPanel(SongView *sv)
    : QWidget(nullptr)
    , m_sv(sv)
    , m_geometry(Geometry::resolve())
{
    setObjectName(QStringLiteral("trackHeaderPanel"));
    setAttribute(Qt::WA_StyledBackground);
    m_layout = new QVBoxLayout(this);
    m_layout->setContentsMargins(lyt::space(Space::Zero), lyt::space(Space::Zero),
                                 lyt::space(Space::Zero), lyt::space(Space::Zero));
    m_layout->setSpacing(lyt::space(Space::Zero));
    m_addButton = new QPushButton(SongView::tr("+ Add track"), this);
    m_addButton->setFocusPolicy(Qt::NoFocus);
    m_addButton->setToolTip(SongView::tr("Add a track (picks its voice first)"));
    connect(m_addButton, &QPushButton::clicked, m_sv,
            [sv = m_sv] { sv->queueHeaderMutation([sv] { sv->addTrack(); }); });
    m_addButton->hide();
    m_layout->addWidget(m_addButton);
    m_layout->addStretch();
    // Reorder-drag drop indicator: a thin line floating over the rows at
    // the insertion point.
    m_indicator = new QWidget(this);
    m_indicator->setFixedHeight(m_geometry.trackHeaderReorderIndicatorHeight);
    m_indicator->setStyleSheet(QStringLiteral("background: palette(highlight);"));
    m_indicator->hide();
    // Platform presentation owns one retained activity column for every row.
    m_activityPresentation = std::make_unique<TrackActivityPresentation>(*this);
}

TrackHeaderPanel::~TrackHeaderPanel() = default;

void TrackHeaderPanel::cancelTransientState()
{
    endRowDrag(false);
    for (const auto &entry : m_rowByTrack)
        entry.second->cancelRename();
}

TrackHeaderRow *TrackHeaderPanel::reconcileRow(int track, std::map<int, TrackHeaderRow *> &previous)
{
    const auto it = previous.find(track);
    if (it == previous.end()) {
        auto *row = new TrackHeaderRow(m_sv, track, this);
        row->setObjectName(QStringLiteral("trackHeaderRow%1").arg(track));
        row->updateToolTip();
        return row;
    }

    TrackHeaderRow *row = it->second;
    previous.erase(it);
    row->resyncSong();
    return row;
}

void TrackHeaderPanel::retireRows(const std::map<int, TrackHeaderRow *> &rows)
{
    // Retired rows drop their identity and leave the layout now but stay
    // parented until the event loop frees them: a rebuild can arrive from
    // inside a row's own mouse press, whose handler must finish first.
    for (const auto &entry : rows) {
        TrackHeaderRow *row = entry.second;
        row->cancelRename();
        row->hide();
        // Name lookups (including rename-editor and harness hooks) must
        // only ever see the live rows.
        row->setObjectName(QString());
        for (QWidget *child : row->findChildren<QWidget *>())
            child->setObjectName(QString());
        m_layout->removeWidget(row);
        row->deleteLater();
    }
}

void TrackHeaderPanel::synchronizeLayout()
{
    for (size_t i = 0; i < m_trackRows.size(); i++) {
        const auto item = m_layout->itemAt(int(i));
        if (item && item->widget() == m_trackRows[i])
            continue;
        m_layout->insertWidget(int(i), m_trackRows[i]);
    }

    const int addButtonIndex = int(m_trackRows.size());
    const auto addButtonItem = m_layout->itemAt(addButtonIndex);
    if (!addButtonItem || addButtonItem->widget() != m_addButton)
        m_layout->insertWidget(addButtonIndex, m_addButton);
}

void TrackHeaderPanel::rebuild(const TrackActivity &activity, bool playing)
{
    cancelTransientState();

    const MidiTimeline *tl = m_sv->timeline();
    SongDocument *doc = m_sv->document();
    const bool canAdd = tl && doc && doc->canAddTrack();

    std::map<int, TrackHeaderRow *> previous = std::move(m_rowByTrack);
    m_rowByTrack.clear();
    m_trackRows.clear();
    for (int track = 0; track < 16; track++) {
        if (!tl || !tl->tracks[track].used)
            continue;
        TrackHeaderRow *row = reconcileRow(track, previous);
        m_rowByTrack[track] = row;
        m_trackRows.push_back(row);
    }

    retireRows(previous);
    synchronizeLayout();
    m_addButton->setVisible(canAdd);
    synchronizeTrackDefinitions();
    m_activityPresentation->present(activity, playing);
}

void TrackHeaderPanel::syncSelection()
{
    for (const auto &entry : m_rowByTrack)
        entry.second->update();
}

void TrackHeaderPanel::beginRename(int track)
{
    const auto it = m_rowByTrack.find(track);
    if (it != m_rowByTrack.end())
        it->second->beginRename();
}

// Called on every playhead/cursor move; each row repaints only when its
// shown program actually changes.
void TrackHeaderPanel::syncVoices()
{
    for (const auto &entry : m_rowByTrack)
        entry.second->syncVoice();
}

void TrackHeaderPanel::synchronizeTrackDefinitions()
{
    std::vector<TrackActivityPresentation::TrackDefinition> definitions;
    definitions.reserve(m_trackRows.size());
    for (const TrackHeaderRow *row : m_trackRows) {
        const int track = row->track();
        definitions.push_back({track, SongView::trackColor(track)});
    }
    const int rowHeight = m_geometry.trackHeaderRowHeight;
    const int meterHeight = rowHeight - lyt::singlePixel();
    m_activityPresentation->setTracks(definitions,
                                      track_activity_render::RowGeometry{rowHeight, meterHeight});
}

void TrackHeaderPanel::syncActivity(const TrackActivity &activity, bool playing)
{
    m_activityPresentation->present(activity, playing);
}

// --- header-row reorder drag (driven by TrackHeaderRow's mouse events;
// the panel owns the state so a mid-drag rebuild can abandon it) ---

bool TrackHeaderPanel::beginRowDrag(int track)
{
    if (m_dragFrom >= 0 || m_trackRows.size() < 2)
        return false;
    m_dragFrom = track;
    m_dropSlot = -1;
    QApplication::setOverrideCursor(Qt::ClosedHandCursor);
    return true;
}

void TrackHeaderPanel::dragRowTo(QPoint pos)
{
    if (m_dragFrom < 0)
        return;
    // Insertion slot: before the first row whose center is below the
    // cursor; past the last row otherwise.
    int slot = 0;
    for (const TrackHeaderRow *row : m_trackRows) {
        if (pos.y() > row->y() + row->height() / 2)
            slot++;
    }
    m_dropSlot = slot;
    const int y = slot < int(m_trackRows.size())
                      ? m_trackRows[size_t(slot)]->y()
                      : m_trackRows.back()->y() + m_trackRows.back()->height();
    m_indicator->setGeometry(lyt::space(Space::Zero), y - lyt::singlePixel(), width(),
                             m_geometry.trackHeaderReorderIndicatorHeight);
    m_indicator->raise();
    m_indicator->show();
}

std::optional<int> TrackHeaderPanel::reorderTarget(int fromTrack, int dropSlot) const
{
    if (dropSlot < 0 || dropSlot > int(m_trackRows.size()))
        return std::nullopt;

    int fromIndex = -1;
    for (size_t i = 0; i < m_trackRows.size(); i++) {
        if (m_trackRows[i]->track() == fromTrack) {
            fromIndex = int(i);
            break;
        }
    }

    // The slots immediately before and after the source preserve its position.
    if (fromIndex < 0 || dropSlot == fromIndex || dropSlot == fromIndex + 1)
        return std::nullopt;

    const int targetIndex = dropSlot > fromIndex ? dropSlot - 1 : dropSlot;
    return m_trackRows[size_t(targetIndex)]->track();
}

void TrackHeaderPanel::endRowDrag(bool commit)
{
    if (m_dragFrom < 0)
        return;
    const int from = m_dragFrom;
    const int slot = m_dropSlot;
    m_dragFrom = -1;
    m_dropSlot = -1;
    m_indicator->hide();
    QApplication::restoreOverrideCursor();
    if (!commit || slot < 0)
        return;

    const std::optional<int> target = reorderTarget(from, slot);
    if (!target)
        return;

    // The move's rebuild cancels open rename editors, silently dropping
    // what was typed: commit them Reaper-style first. Its queued commit
    // runs before the queued move below, and renameTrack renumbers
    // nothing, so both captured track numbers stay valid.
    for (const auto &entry : m_rowByTrack)
        entry.second->commitOpenRename();
    // Queued: the move rebuilds this panel from inside the release
    // handler.
    m_sv->queueHeaderMutation([sv = m_sv, from, target = *target] { sv->moveTrack(from, target); });
}

bool TrackHeaderPanel::event(QEvent *event)
{
    const bool handled = QWidget::event(event);
    if (event->type() == QEvent::FontChange)
        refreshGeometry();
    return handled;
}

} // namespace songview
