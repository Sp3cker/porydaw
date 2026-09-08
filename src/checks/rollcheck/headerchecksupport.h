#pragma once

#include <QImage>
#include <QModelIndex>
#include <QObject>
#include <optional>

#include "checks/rollcheck/rollcheck.h"
#include "core/miditimeline.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/trackheadermodel.h"

namespace checks::rollcheck::headercheck {

inline songview::TrackHeaderModel *model(SongView &view)
{
    return view.findChild<songview::TrackHeaderModel *>(QStringLiteral("trackHeaderModel"));
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

inline QImage captureBand(PianoRollFixture &check, SongView &view)
{
    const auto geometry = view.timelineBandLayout().geometry(songview::TimelineBand::TrackHeaders);
    return geometry ? check.captureQuickBand(geometry->rect) : QImage{};
}

struct ModelChanges {
    int resets = 0;
    void clear() { resets = 0; }
};

} // namespace checks::rollcheck::headercheck
