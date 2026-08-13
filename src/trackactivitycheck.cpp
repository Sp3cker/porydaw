#include <QImage>
#include <QPainter>

#include <cmath>
#include <cstdio>

#include "ui/activity/trackactivity.h"

namespace {

constexpr auto kTolerance = 0.0001f;

bool nearlyEqual(float actual, float expected)
{
    return std::abs(actual - expected) <= kTolerance;
}

} // namespace

int runTrackActivityCheck()
{
    auto failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        if (!condition) {
            std::fprintf(stderr, "trackactivitycheck: FAIL: %s\n", message);
            ++failures;
        }
    };
    TrackActivity activity;
    std::array<uint8_t, MAX_TRACKS> levels{};
    for (auto track = 0; track < MAX_TRACKS; ++track)
        check(activity.intensity(track) == 0.0f, "new activity must be dark");
    constexpr auto isolatedTrack = 3;
    levels[isolatedTrack] = 128;
    activity.advance(levels, 0.017f);
    const auto firstAttack = activity.intensity(isolatedTrack);
    check(firstAttack > 0.0f && firstAttack < 128.0f / 255.0f,
          "thermal attack must approach the peak without snapping");
    for (auto track = 0; track < MAX_TRACKS; ++track) {
        if (track != isolatedTrack)
            check(activity.intensity(track) == 0.0f, "a peak must not light another track");
    }
    levels.fill(0);
    auto previous = activity.intensity(isolatedTrack);
    for (auto step = 0; step < 24; ++step) {
        activity.advance(levels, 0.125f);
        const auto current = activity.intensity(isolatedTrack);
        check(current <= previous, "release must decay monotonically");
        previous = current;
    }
    activity.advance(levels, 10.0f);
    check(activity.intensity(isolatedTrack) == 0.0f, "a released light must reach zero");
    constexpr auto retriggerTrack = 7;
    levels[retriggerTrack] = 48;
    activity.advance(levels, 0.017f);
    levels.fill(0);
    activity.advance(levels, 1.0f);
    const auto decayed = activity.intensity(retriggerTrack);
    levels[retriggerTrack] = 224;
    activity.advance(levels, 0.017f);
    check(activity.intensity(retriggerTrack) > decayed, "a new peak must retrigger a faded light");
    check(activity.intensity(retriggerTrack) < 224.0f / 255.0f,
          "a retrigger must retain thermal attack inertia");
    auto image = QImage(16, 16, QImage::Format_ARGB32_Premultiplied);
    image.fill(Qt::transparent);
    {
        auto painter = QPainter(&image);
        activity.paintLight(painter, retriggerTrack, QRectF(0.0, 0.0, 4.0, 16.0), QColor(Qt::red));
    }
    check(image.pixelColor(2, 8).alpha() > 0, "an active light must paint its color strip");
    check(image.pixelColor(4, 8).alpha() == 0,
          "an activity light must not paint beyond its color strip");
    activity.reset();
    for (auto track = 0; track < MAX_TRACKS; ++track)
        check(activity.intensity(track) == 0.0f, "reset must clear every light");
    if (failures == 0)
        std::printf("trackactivitycheck: PASS\n");
    return failures == 0 ? 0 : 1;
}
