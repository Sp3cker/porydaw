#pragma once

#include <QColor>
#include <QtGlobal>

#include "audio/trackactivitylevel.h"

namespace track_activity_render {

struct State {
    TrackActivityIntensity intensity;
    bool playing = true;
    float maximumIntensity = 1.0f;

    bool operator==(const State &) const = default;
};

struct RowGeometry {
    int stride;
    int meterHeight;

    bool operator==(const RowGeometry &) const = default;
};

struct RenderKey {
    int leftHeight;
    int rightHeight;
    bool playing;

    bool operator==(const RenderKey &) const = default;
};

struct Colors {
    QColor dim;
    QColor active;
};

int physicalHeight(const State &state, float channelIntensity, int meterHeight,
                   qreal devicePixelRatio);
RenderKey renderKey(const State &state, int meterHeight, qreal devicePixelRatio);
qreal snappedHeight(const State &state, float channelIntensity, int meterHeight,
                    qreal devicePixelRatio);
Colors colors(const QColor &identityColor);

} // namespace track_activity_render
