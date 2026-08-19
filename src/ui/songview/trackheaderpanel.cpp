// ---------------------------------------------------------- TrackHeaderPanel

#include "ui/songview/trackheaderpanel.h"

#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/trackheaderrow.h"

#include <QApplication>
#include <QEvent>
#include <QMetaObject>
#include <QPushButton>
#include <QVBoxLayout>
#include <cstddef>

namespace lyt = ::layout;
using Space = lyt::Space;

namespace songview {

TrackHeaderPanel::Geometry TrackHeaderPanel::Geometry::resolve()
{
    return {lyt::fontPx(0.25)};
}

void TrackHeaderPanel::refreshGeometry()
{
    m_geometry = Geometry::resolve();
    m_indicator->setFixedHeight(m_geometry.trackHeaderReorderIndicatorHeight);
    if (m_indicator->isVisible())
        m_indicator->resize(width(), m_geometry.trackHeaderReorderIndicatorHeight);
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
    m_layout->addStretch();
    // Reorder-drag drop indicator: a thin line floating over the rows at
    // the insertion point.
    m_indicator = new QWidget(this);
    m_indicator->setFixedHeight(m_geometry.trackHeaderReorderIndicatorHeight);
    m_indicator->setStyleSheet(QStringLiteral("background: palette(highlight);"));
    m_indicator->hide();
}

void TrackHeaderPanel::rebuild()
{
    // A document edit mid-drag rebuilds the rows, deleting the dragged
    // one out from under its own gesture; abandon the drag first.
    endRowDrag(false);
    // Deferred deletion: a rebuild can arrive from inside a row's own
    // mouse press (clicking a header focuses the roll, which fires an
    // editor field's editingFinished; a structural voice commit then
    // swaps the voicegroup into every view). Freeing the rows here
    // would leave that row's event handler running on freed memory.
    // Keep them parented (their mouse handlers cast parentWidget())
    // but hidden and anonymous until the event loop collects them.
    for (QWidget *row : m_rows) {
        row->hide();
        // Anonymous, children included: name lookups (the rename
        // editor, harness hooks) must only ever see the live rows.
        row->setObjectName(QString());
        for (QWidget *child : row->findChildren<QWidget *>())
            child->setObjectName(QString());
        m_layout->removeWidget(row);
        row->deleteLater();
    }
    m_rows.clear();
    m_rowByTrack.clear();
    m_trackRows.clear();
    const MidiTimeline *tl = m_sv->timeline();
    if (tl) {
        for (int t = 0; t < 16; t++) {
            if (!tl->tracks[t].used)
                continue;
            auto *row = new TrackHeaderRow(m_sv, t, this);
            row->setObjectName(QStringLiteral("trackHeaderRow%1").arg(t));
            m_rowByTrack[t] = row;
            row->updateToolTip();
            m_layout->insertWidget(m_layout->count() - 1, row);
            m_rows.push_back(row);
            m_trackRows.push_back(row);
        }
        SongDocument *doc = m_sv->document();
        if (doc && doc->canAddTrack()) {
            auto *add = new QPushButton(SongView::tr("+ Add track"), this);
            add->setFocusPolicy(Qt::NoFocus);
            add->setToolTip(SongView::tr("Add a track (picks its voice first)"));
            // Queued: the edit rebuilds this panel, deleting the button
            // out from under its own clicked handler.
            connect(
                add, &QPushButton::clicked, m_sv, [sv = m_sv] { sv->addTrack(); },
                Qt::QueuedConnection);
            m_layout->insertWidget(m_layout->count() - 1, add);
            m_rows.push_back(add);
        }
    }
}

void TrackHeaderPanel::syncSelection()
{
    for (QWidget *row : m_rows)
        row->update();
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

void TrackHeaderPanel::syncActivity(const TrackActivity &activity, bool playing)
{
    for (const auto &entry : m_rowByTrack)
        entry.second->setActivity(activity.intensity(entry.first), playing);
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
    int fromIdx = -1;
    for (size_t i = 0; i < m_trackRows.size(); i++) {
        if (m_trackRows[i]->track() == from)
            fromIdx = int(i);
    }
    // The slots adjacent to the dragged row leave it where it was.
    if (fromIdx < 0 || slot == fromIdx || slot == fromIdx + 1)
        return;
    const int target = m_trackRows[size_t(slot > fromIdx ? slot - 1 : slot)]->track();
    // The move's rebuild would destroy an open rename editor without a
    // focus-out (rows take no focus): commit it Reaper-style first. Its
    // queued commit runs before the queued move below, and renameTrack
    // renumbers nothing, so both captured track numbers stay valid.
    for (const auto &entry : m_rowByTrack)
        entry.second->commitOpenRename();
    // Queued: the edit rebuilds this panel, deleting the dragged row out
    // from under its own mouse-release handler.
    QMetaObject::invokeMethod(
        m_sv, [sv = m_sv, from, target] { sv->moveTrack(from, target); }, Qt::QueuedConnection);
}

bool TrackHeaderPanel::event(QEvent *event)
{
    const bool handled = QWidget::event(event);
    if (event->type() == QEvent::FontChange)
        refreshGeometry();
    return handled;
}

} // namespace songview
