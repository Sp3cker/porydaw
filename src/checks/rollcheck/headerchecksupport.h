#pragma once

#include <QEvent>
#include <QImage>
#include <QList>
#include <QModelIndex>
#include <QObject>
#include <QPointF>
#include <QString>
#include <algorithm>
#include <optional>
#include <vector>

#include "checks/rollcheck/rollcheck.h"
#include "checks/support/eventsynth.h"
#include "core/miditimeline.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/trackheadermodel.h"

namespace checks::rollcheck::headercheck {

inline songview::TrackHeaderModel *model(SongView &view)
{
    return view.findChild<songview::TrackHeaderModel *>(QStringLiteral("trackHeaderModel"));
}

inline songview::TimelineInputItem *input(SongView &view)
{
    auto *quick =
        view.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
    return quick && quick->rootObject()
               ? quick->rootObject()->findChild<songview::TimelineInputItem *>(
                     QStringLiteral("timelineTrackHeadersInput"))
               : nullptr;
}

inline QObject *renameInput(SongView &view)
{
    auto *quick =
        view.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
    return quick && quick->rootObject() ? quick->rootObject()->findChild<QObject *>(
                                              QStringLiteral("timelineTrackHeaderRename"))
                                        : nullptr;
}

inline std::optional<int> rowForTrack(const songview::TrackHeaderModel &headers, int track)
{
    for (int row = 0; row < headers.rowCount(); ++row) {
        const QModelIndex index = headers.index(row, 0);
        if (!headers.data(index, songview::TrackHeaderModel::IsAddTrackRole).toBool() &&
            headers.data(index, songview::TrackHeaderModel::TrackRole).toInt() == track) {
            return row;
        }
    }
    return std::nullopt;
}

inline std::optional<int> addTrackRow(const songview::TrackHeaderModel &headers)
{
    for (int row = 0; row < headers.rowCount(); ++row) {
        const QModelIndex index = headers.index(row, 0);
        if (headers.data(index, songview::TrackHeaderModel::IsAddTrackRole).toBool() &&
            headers.data(index, songview::TrackHeaderModel::TrackRole).toInt() == -1) {
            return row;
        }
    }
    return std::nullopt;
}

inline bool recordsMatchTimeline(const songview::TrackHeaderModel &headers,
                                 const MidiTimeline &timeline, bool canAddTrack)
{
    int row = 0;
    for (int track = 0; track < 16; ++track) {
        if (!timeline.tracks[track].used)
            continue;
        if (row >= headers.rowCount())
            return false;
        const QModelIndex index = headers.index(row, 0);
        if (headers.data(index, songview::TrackHeaderModel::IsAddTrackRole).toBool() ||
            headers.data(index, songview::TrackHeaderModel::TrackRole).toInt() != track) {
            return false;
        }
        ++row;
    }
    if (!canAddTrack)
        return row == headers.rowCount();
    if (row + 1 != headers.rowCount())
        return false;
    const QModelIndex add = headers.index(row, 0);
    return headers.data(add, songview::TrackHeaderModel::IsAddTrackRole).toBool() &&
           headers.data(add, songview::TrackHeaderModel::TrackRole).toInt() == -1;
}

inline QPointF rowPoint(const songview::TrackHeaderModel &headers,
                        const songview::TimelineInputItem &headerInput, int row, QPointF local)
{
    const qreal maximumX = std::max<qreal>(0.0, headerInput.width() - 1.0);
    return {std::clamp(local.x(), 0.0, maximumX),
            row * headers.rowHeight() - headers.scrollY() + local.y()};
}

inline QPointF titlePoint(const songview::TrackHeaderModel &headers,
                          const songview::TimelineInputItem &headerInput, int row)
{
    return rowPoint(headers, headerInput, row,
                    {headers.voiceLineRect().center().x(), headers.rowHeight() / 4.0});
}

inline QPointF voicePoint(const songview::TrackHeaderModel &headers,
                          const songview::TimelineInputItem &headerInput, int row)
{
    return rowPoint(headers, headerInput, row, headers.voiceLineRect().center());
}

inline void click(songview::TimelineInputItem &headerInput, const QPointF &position)
{
    checks::events::sendMouse(headerInput, QEvent::MouseButtonPress, position, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(headerInput, QEvent::MouseButtonRelease, position, Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
}

inline QImage captureBand(Harness &check, SongView &view)
{
    const auto geometry = view.timelineBandLayout().geometry(songview::TimelineBand::TrackHeaders);
    return geometry ? check.captureQuickBand(geometry->rect) : QImage{};
}

struct ModelChange {
    int firstRow = -1;
    int lastRow = -1;
    QList<int> roles;
};

struct ModelChanges {
    int resets = 0;
    std::vector<ModelChange> data;

    void clear()
    {
        resets = 0;
        data.clear();
    }
};

inline bool includesRole(const std::vector<ModelChange> &changes, int row, int role)
{
    return std::any_of(changes.cbegin(), changes.cend(), [row, role](const ModelChange &change) {
        return change.firstRow <= row && row <= change.lastRow && change.roles.contains(role);
    });
}

} // namespace checks::rollcheck::headercheck
