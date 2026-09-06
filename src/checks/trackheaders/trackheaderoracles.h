#pragma once

#include <QImage>

#include <optional>

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
