#include "ui/songviewautomationarea_p.hpp"

#include <QAction>
#include <QMenu>
#include <QMessageBox>
#include <QMouseEvent>

#include <utility>

#include "core/mid2agbtables.h"
#include "liveshortcuts.hpp"
#include "ui/songview.h"

namespace songview {

void AutomationArea::State::showTimeSelectionContextMenu(const QPoint &globalPosition)
{
    showTimeRangeMenu(globalPosition);
}

void AutomationArea::State::createTimeRangeActions()
{
    const auto createAction = [this](const QString &text) {
        auto *action = new QAction(text, this);
        addAction(action);
        return action;
    };
    const auto createRangeShortcutAction = [&createAction](live_shortcuts::Command command) {
        QAction *action = createAction({});
        live_shortcuts::configureAction(*action, command);
        return action;
    };
    const auto createRangeNavigationAction = [&createRangeShortcutAction](
                                                 live_shortcuts::Command command,
                                                 const QString &text) {
        QAction *action = createRangeShortcutAction(command);
        action->setText(text);
        return action;
    };

    m_timeRangeActions.copy = createRangeShortcutAction(live_shortcuts::Command::Copy);
    m_timeRangeActions.copy->setText(SongView::tr("Copy range"));
    QObject::connect(m_timeRangeActions.copy, &QAction::triggered, this, [this] {
        if (canEditTimeRange())
            m_sv->copyTimeSelection();
    });
    m_timeRangeActions.cut = createRangeShortcutAction(live_shortcuts::Command::Cut);
    m_timeRangeActions.cut->setText(SongView::tr("Cut range"));
    QObject::connect(m_timeRangeActions.cut, &QAction::triggered, this, [this] {
        if (!canEditTimeRange())
            return;
        m_sv->copyTimeSelection();
        m_sv->deleteTimeSelection();
    });
    m_timeRangeActions.deleteRange =
        createRangeShortcutAction(live_shortcuts::Command::Delete);
    m_timeRangeActions.deleteRange->setText(SongView::tr("Delete range"));
    QObject::connect(m_timeRangeActions.deleteRange, &QAction::triggered, this, [this] {
        if (canEditTimeRange())
            m_sv->deleteTimeSelection();
    });
    m_timeRangeActions.paste = createRangeShortcutAction(live_shortcuts::Command::Paste);
    m_timeRangeActions.paste->setText(SongView::tr("Paste at edit cursor"));
    QObject::connect(m_timeRangeActions.paste, &QAction::triggered, this, [this] {
        if (canPasteTimeRange())
            m_sv->pasteRangeAtEditCursor();
    });
    m_timeRangeActions.removeContents =
        createAction(SongView::tr("Remove contents (shift left)"));
    QObject::connect(m_timeRangeActions.removeContents, &QAction::triggered, this, [this] {
        if (canEditTimeRange())
            m_sv->removeTimeSelectionContents();
    });
    m_timeRangeActions.clear = createAction(SongView::tr("Clear selection"));
    QObject::connect(m_timeRangeActions.clear, &QAction::triggered, this, [this] {
        m_sv->clearTimeSelection();
    });

    m_timeRangeActions.nudgeLeft = createRangeNavigationAction(
        live_shortcuts::Command::MoveNotesLeft, SongView::tr("Move range left"));
    QObject::connect(m_timeRangeActions.nudgeLeft, &QAction::triggered, this, [this] {
        if (canEditTimeRange())
            m_sv->nudgeTimeSelection(false);
    });
    m_timeRangeActions.nudgeRight = createRangeNavigationAction(
        live_shortcuts::Command::MoveNotesRight, SongView::tr("Move range right"));
    QObject::connect(m_timeRangeActions.nudgeRight, &QAction::triggered, this, [this] {
        if (canEditTimeRange())
            m_sv->nudgeTimeSelection(true);
    });
    m_timeRangeActions.transposeUp = createRangeNavigationAction(
        live_shortcuts::Command::TransposeNotesUp, SongView::tr("Transpose range up"));
    QObject::connect(m_timeRangeActions.transposeUp, &QAction::triggered, this, [this] {
        if (canEditTimeRange())
            m_sv->transposeTimeSelection(1);
    });
    m_timeRangeActions.transposeDown = createRangeNavigationAction(
        live_shortcuts::Command::TransposeNotesDown, SongView::tr("Transpose range down"));
    QObject::connect(m_timeRangeActions.transposeDown, &QAction::triggered, this, [this] {
        if (canEditTimeRange())
            m_sv->transposeTimeSelection(-1);
    });
    m_timeRangeActions.transposeUpOctave = createRangeNavigationAction(
        live_shortcuts::Command::TransposeNotesUpOneOctave,
        SongView::tr("Transpose range up an octave"));
    QObject::connect(m_timeRangeActions.transposeUpOctave, &QAction::triggered, this, [this] {
        if (canEditTimeRange())
            m_sv->transposeTimeSelection(12);
    });
    m_timeRangeActions.transposeDownOctave = createRangeNavigationAction(
        live_shortcuts::Command::TransposeNotesDownOneOctave,
        SongView::tr("Transpose range down an octave"));
    QObject::connect(m_timeRangeActions.transposeDownOctave, &QAction::triggered, this, [this] {
        if (canEditTimeRange())
            m_sv->transposeTimeSelection(-12);
    });
    m_timeRangeActions.shortenNotes = createRangeNavigationAction(
        live_shortcuts::Command::ShortenNotes, SongView::tr("Shorten range notes"));
    QObject::connect(m_timeRangeActions.shortenNotes, &QAction::triggered, this, [this] {
        if (canEditTimeRange())
            m_sv->resizeTimeSelectionNotes(false);
    });
    m_timeRangeActions.lengthenNotes = createRangeNavigationAction(
        live_shortcuts::Command::LengthenNotes, SongView::tr("Lengthen range notes"));
    QObject::connect(m_timeRangeActions.lengthenNotes, &QAction::triggered, this, [this] {
        if (canEditTimeRange())
            m_sv->resizeTimeSelectionNotes(true);
    });
    m_timeRangeActions.decreaseVelocity = createRangeNavigationAction(
        live_shortcuts::Command::DecreaseVelocity,
        SongView::tr("Decrease range note velocity"));
    QObject::connect(m_timeRangeActions.decreaseVelocity, &QAction::triggered, this, [this] {
        if (canEditTimeRange())
            m_sv->nudgeTimeSelectionVelocity(-1);
    });
    m_timeRangeActions.increaseVelocity = createRangeNavigationAction(
        live_shortcuts::Command::IncreaseVelocity,
        SongView::tr("Increase range note velocity"));
    QObject::connect(m_timeRangeActions.increaseVelocity, &QAction::triggered, this, [this] {
        if (canEditTimeRange())
            m_sv->nudgeTimeSelectionVelocity(1);
    });
}

bool AutomationArea::State::canEditTimeRange() const
{
    return m_sv->document() && m_sv->timeSelection().active();
}

bool AutomationArea::State::canPasteTimeRange() const
{
    const SongView::Clip &rangeClipboard = m_sv->clipboard();
    return m_sv->document() && rangeClipboard.span > 0 && !rangeClipboard.empty();
}

void AutomationArea::State::showTimeRangeMenu(const QPoint &globalPosition)
{
    if (!canEditTimeRange())
        return;
    const bool pasteWasEnabled = m_timeRangeActions.paste->isEnabled();
    m_timeRangeActions.paste->setEnabled(canPasteTimeRange());
    QMenu menu(m_area);
    menu.addAction(m_timeRangeActions.copy);
    menu.addAction(m_timeRangeActions.cut);
    menu.addAction(m_timeRangeActions.deleteRange);
    menu.addAction(m_timeRangeActions.removeContents);
    menu.addAction(m_timeRangeActions.paste);
    menu.addSeparator();
    menu.addAction(m_timeRangeActions.clear);
    menu.exec(globalPosition);
    m_timeRangeActions.paste->setEnabled(pasteWasEnabled);
}

std::pair<int, uint8_t> AutomationArea::State::rowIdentity(const Row &row) const
{
    switch (row.kind) {
    case Row::Tempo:
        return {-1, DOC_CC_TEMPO};
    case Row::Voice:
        return {m_sv->selectedTrack(), DOC_CC_VOICE};
    case Row::Lane:
        return {row.lane->track, row.lane->cc};
    }
    return {-1, 0};
}

void AutomationArea::State::rightClickInPlace(QMouseEvent *event)
{
    SongDocument *doc = m_sv->document();
    if (!doc || m_rightRow < 0 || m_rightRow >= int(m_rows.size()))
        return;
    const Row &row = m_rows[m_rightRow];
    const std::pair<int, uint8_t> id = rowIdentity(row);
    const SongView::TimeSelection &sel = m_sv->timeSelection();
    const double tick = rawTickAt(event->pos().x());
    if (sel.active() && m_sv->timeSelectionCoversRow(id.first, id.second)
        && tick >= double(sel.startTick) && tick < double(sel.endTick)) {
        showTimeRangeMenu(event->globalPosition().toPoint());
        return;
    }
    if (row.kind == Row::Voice) {
        DocLanePoint hit;
        if (voiceChangeNear(event->pos().x(), &hit))
            doc->deleteLanePoints(m_sv->selectedTrack(), DOC_CC_VOICE, {hit});
        return;
    }
    uint8_t cc;
    int track;
    if (!rowTarget(row, &cc, &track))
        return;
    if (const LanePoint *nearPt = nearestPoint(row, event->pos().x())) {
        DocLanePoint pt;
        if (doc->findLanePoint(track, cc, nearPt->tick, &pt))
            doc->deleteLanePoints(track, cc, {pt});
        return;
    }
    m_sv->clearTimeSelection();
}

void AutomationArea::State::showAddLaneMenu(const QPoint &globalPosition)
{
    const int track = m_sv->selectedTrack();
    QMenu menu;
    static constexpr uint8_t kAudibleCcs[] = {0x01, 0x07, 0x0A, 0x14, 0x15,
                                              LANE_CC_BEND};
    for (uint8_t cc : kAudibleCcs) {
        if (m_sv->model().findLane(track, cc))
            continue;
        QString label;
        if (cc == LANE_CC_BEND) {
            label = SongView::tr("Pitch bend (BEND)");
        } else {
            const M4aCcInfo info = m4aClassifyCc(cc);
            label = QStringLiteral("%1 (%2)").arg(QLatin1String(info.display),
                                                  QLatin1String(info.name));
        }
        menu.addAction(label)->setData(int(cc));
    }
    if (menu.isEmpty())
        menu.addAction(SongView::tr("All parameters already have lanes"))
            ->setEnabled(false);
    QAction *chosen = menu.exec(globalPosition);
    if (chosen && chosen->data().isValid())
        m_sv->addEmptyLane(track, uint8_t(chosen->data().toInt()));
}

void AutomationArea::State::showLaneMenu(const AutoLane &lane, const QPoint &globalPosition)
{
    const int track = lane.track;
    const uint8_t cc = lane.cc;
    const QString name = lane.name;
    const bool empty = lane.points.empty();

    QMenu menu;
    QAction *copyLane = menu.addAction(SongView::tr("Copy lane"));
    copyLane->setEnabled(!empty);
    QAction *pasteLane = menu.addAction(SongView::tr("Paste lane (replace)"));
    {
        const SongView::Clip &clip = m_sv->clipboard();
        pasteLane->setEnabled(clip.wholeLane && clip.lanes.size() == 1
                              && !clip.lanes.front().points.empty());
    }
    menu.addSeparator();
    QAction *clear = menu.addAction(SongView::tr("Clear events"));
    clear->setEnabled(!empty);
    QAction *del = menu.addAction(empty ? SongView::tr("Remove empty lane")
                                        : SongView::tr("Delete lane"));
    QAction *chosen = menu.exec(globalPosition);
    if (!chosen)
        return;

    SongDocument *doc = m_sv->document();
    const std::vector<DocLanePoint> points = doc->lanePoints(track, cc);
    if (chosen == copyLane) {
        if (points.empty())
            return;
        SongView::Clip clip;
        clip.wholeLane = true;
        clip.span = points.back().tick + 1;
        SongView::ClipLane clipLane{track, cc, {}};
        for (const DocLanePoint &point : points)
            clipLane.points.push_back({uint32_t(point.tick), point.value});
        clip.lanes.push_back(std::move(clipLane));
        m_sv->clipboard() = std::move(clip);
        m_sv->announce(SongView::tr("Copied the %1 lane (%n point(s))", nullptr,
                                    int(points.size()))
                           .arg(name));
        return;
    }
    if (chosen == pasteLane) {
        SongDocument::RangeEdit edit;
        edit.removePoints = points;
        SongDocument::RangeEdit::LaneWrite laneWrite{track, cc, {}};
        for (const std::pair<uint32_t, int> &point :
             m_sv->clipboard().lanes.front().points)
            laneWrite.points.push_back({uint64_t(point.first), point.second});
        edit.addPoints.push_back(std::move(laneWrite));
        doc->applyRangeEdit(SongView::tr("paste lane"), edit);
        m_sv->announce(SongView::tr("Replaced the %1 lane").arg(name));
        return;
    }
    if (chosen == clear) {
        if (points.empty())
            return;
        m_sv->addEmptyLane(track, cc);
        doc->deleteLanePoints(track, cc, points);
    } else if (chosen == del) {
        if (!points.empty()
            && QMessageBox::question(
                   this, SongView::tr("Delete lane"),
                   SongView::tr("Delete the %1 lane and its %2 events?")
                       .arg(name)
                       .arg(points.size()))
                   != QMessageBox::Yes)
            return;
        m_sv->removeEmptyLane(track, cc);
        if (!points.empty())
            doc->deleteLanePoints(track, cc, points);
    }
}

} // namespace songview
