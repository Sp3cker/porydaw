#include <cmath>
#include <cstdio>

#include "ui/activity/trackactivity.h"

namespace {

constexpr auto kTolerance = 0.0001f;

bool nearlyEqual(float actual, float expected)
{
    return std::abs(actual - expected) <= kTolerance;
}

bool dark(TrackActivityIntensity intensity)
{
    return intensity.left == 0.0f && intensity.right == 0.0f;
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
    TrackActivityLevels levels{};
    for (int track = 0; track < int(kMaxTracks); ++track)
        check(dark(activity.intensity(track)), "new activity must be dark");
    check(dark(activity.intensity(-1)), "invalid negative track must be dark");
    check(dark(activity.intensity(int(kMaxTracks))), "invalid high track must be dark");

    constexpr auto isolatedTrack = 3;
    levels[isolatedTrack] = {128, 32};
    check(activity.advance(levels, 0.017f, true), "playing activity must require another tick");
    const auto firstAttack = activity.intensity(isolatedTrack);
    check(firstAttack.left > 0.0f && firstAttack.left < 128.0f / 255.0f,
          "left attack must approach the peak without snapping");
    check(firstAttack.right > 0.0f && firstAttack.right < 32.0f / 255.0f,
          "right attack must approach the peak without snapping");
    check(firstAttack.left > firstAttack.right, "stereo sides must retain independent targets");
    for (int track = 0; track < int(kMaxTracks); ++track) {
        if (track != isolatedTrack)
            check(dark(activity.intensity(track)), "a peak must not light another track");
    }

    TrackActivity leftOnlyActivity;
    TrackActivityLevels leftOnlyLevels{};
    leftOnlyLevels[isolatedTrack] = {255, 0};
    leftOnlyActivity.advance(leftOnlyLevels, 0.017f, true);
    const auto leftOnly = leftOnlyActivity.intensity(isolatedTrack);
    check(leftOnly.left > 0.0f && leftOnly.right == 0.0f,
          "left-only activity must not leak into the right channel");

    TrackActivity rightOnlyActivity;
    TrackActivityLevels rightOnlyLevels{};
    rightOnlyLevels[isolatedTrack] = {0, 255};
    rightOnlyActivity.advance(rightOnlyLevels, 0.017f, true);
    const auto rightOnly = rightOnlyActivity.intensity(isolatedTrack);
    check(rightOnly.left == 0.0f && rightOnly.right > 0.0f,
          "right-only activity must not leak into the left channel");

    levels.fill({});
    auto previous = activity.intensity(isolatedTrack);
    activity.advance(levels, 0.125f, true);
    auto current = activity.intensity(isolatedTrack);
    check(current.left > previous.left * 0.5f && current.right > previous.right * 0.5f,
          "ordinary release must remain visibly gradual");
    previous = current;
    for (auto step = 0; step < 23; ++step) {
        activity.advance(levels, 0.125f, true);
        current = activity.intensity(isolatedTrack);
        check(current.left <= previous.left && current.right <= previous.right,
              "ordinary release must decay monotonically on both sides");
        previous = current;
    }
    check(dark(activity.intensity(isolatedTrack)), "released activity must settle at zero");

    activity.reset();
    levels[isolatedTrack] = {255, 255};
    activity.advance(levels, 0.015f, true);
    levels.fill({});
    activity.advance(levels, 2.0f, true);
    check(dark(activity.intensity(isolatedTrack)),
          "the visible floor must remove an imperceptible release tail");

    constexpr auto retriggerTrack = 7;
    levels[retriggerTrack] = {48, 0};
    activity.advance(levels, 0.017f, true);
    levels.fill({});
    activity.advance(levels, 1.0f, true);
    const auto decayed = activity.intensity(retriggerTrack);
    levels[retriggerTrack] = {224, 64};
    activity.advance(levels, 0.017f, true);
    const auto retriggered = activity.intensity(retriggerTrack);
    check(retriggered.left > decayed.left && retriggered.right > decayed.right,
          "a new peak must retrigger each side independently");
    check(retriggered.left < 224.0f / 255.0f && retriggered.right < 64.0f / 255.0f,
          "a retrigger must retain thermal attack inertia");

    activity.reset();
    for (int track = 0; track < int(kMaxTracks); ++track)
        check(dark(activity.intensity(track)), "reset must clear every light");

    levels[isolatedTrack] = {255, 64};
    activity.advance(levels, 0.015f, true);
    const auto beforePause = activity.intensity(isolatedTrack);
    levels.fill({});
    check(activity.advance(levels, 0.015f, false), "paused fill must require another tick");
    const auto filling = activity.intensity(isolatedTrack);
    check(filling.left > beforePause.left && filling.right > beforePause.right,
          "paused fill must gently approach full brightness");
    check(!activity.advance(levels, 10.0f, false), "settled paused fill must stop ticks");
    for (int track = 0; track < int(kMaxTracks); ++track) {
        const auto settled = activity.intensity(track);
        check(settled.left == 1.0f && settled.right == 1.0f,
              "paused fill must settle every side at full brightness");
    }
    check(!activity.advance(levels, 0.0f, false), "settled pause must remain settled");

    activity.resetPaused();
    check(activity.advance(levels, 0.075f, true), "resuming activity must require another tick");
    const auto resumed = activity.intensity(isolatedTrack);
    check(nearlyEqual(resumed.left, std::exp(-0.075f / 0.015f)),
          "resuming descent must use the 75 ms fast window");
    activity.advance(levels, 0.015f, true);
    const auto ordinaryRelease = activity.intensity(isolatedTrack);
    check(nearlyEqual(ordinaryRelease.left, resumed.left * std::exp(-0.015f / 0.250f)),
          "release must return to 250 ms after the resume window");
    check(ordinaryRelease.left > resumed.left * std::exp(-0.015f / 0.015f),
          "ordinary release must not retain the fast resume descent");

    activity.resetPaused();
    activity.advance(levels, 0.050f, true);
    activity.advance(levels, 0.001f, false);
    const auto beforeRapidResume = activity.intensity(isolatedTrack);
    activity.advance(levels, 0.015f, true);
    const auto rapidResume = activity.intensity(isolatedTrack);
    check(rapidResume.left < beforeRapidResume.left * std::exp(-0.015f / 0.250f),
          "a rapid pause/resume must restart fast descent");

    activity.reset();
    levels[isolatedTrack] = {255, 255};
    check(activity.advance(levels, -1.0f, true),
          "playing must require ticks with negative elapsed");
    check(dark(activity.intensity(isolatedTrack)), "negative elapsed must not move activity");
    activity.advance(levels, 0.0f, true);
    check(dark(activity.intensity(isolatedTrack)), "zero elapsed must not move activity");

    if (failures == 0)
        std::printf("trackactivitycheck: PASS\n");
    return failures == 0 ? 0 : 1;
}
