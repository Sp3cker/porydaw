#pragma once

#include <QImage>
#include <QModelIndex>

#include <optional>

#include "core/miditimeline.h"
#include "ui/songview/trackheadermodel.h"

namespace trackheaders_test {

inline std::optional<int> rowForTrack(const songview::TrackHeaderModel &model, int track)
{
    for (int row = 0; row < model.rowCount(); ++row) {
        const QModelIndex index = model.index(row, 0);
        if (!model.data(index, songview::TrackHeaderModel::IsAddTrackRole).toBool() &&
            model.data(index, songview::TrackHeaderModel::TrackRole).toInt() == track) {
            return row;
        }
    }
    return std::nullopt;
}

inline std::optional<int> addTrackRow(const songview::TrackHeaderModel &model)
{
    for (int row = 0; row < model.rowCount(); ++row) {
        const QModelIndex index = model.index(row, 0);
        if (model.data(index, songview::TrackHeaderModel::IsAddTrackRole).toBool() &&
            model.data(index, songview::TrackHeaderModel::TrackRole).toInt() == -1) {
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

struct ModelChanges {
    int resets = 0;
    void clear() { resets = 0; }
};

inline int devicePixelSpan(int origin, int length, qreal devicePixelRatio)
{
    return qRound((origin + length) * devicePixelRatio) - qRound(origin * devicePixelRatio);
}

inline bool isOpaque(const QImage &image)
{
    if (image.isNull())
        return false;
    for (int y = 0; y < image.height(); ++y) {
        const QRgb *const row = reinterpret_cast<const QRgb *>(image.constScanLine(y));
        for (int x = 0; x < image.width(); ++x) {
            if (qAlpha(row[x]) != 255)
                return false;
        }
    }
    return true;
}

} // namespace trackheaders_test
