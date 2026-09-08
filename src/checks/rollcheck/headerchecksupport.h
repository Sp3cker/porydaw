#pragma once

#include <QImage>
#include <QObject>

#include "checks/rollcheck/rollcheck.h"
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

inline QImage captureBand(PianoRollFixture &check, SongView &view)
{
    const auto geometry = view.timelineBandLayout().geometry(songview::TimelineBand::TrackHeaders);
    return geometry ? check.captureQuickBand(geometry->rect) : QImage{};
}

} // namespace checks::rollcheck::headercheck
