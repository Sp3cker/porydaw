#include "checks/audio/tst_trackactivity.h"
#include "checks/fwd.hpp"

#include <QtTest>

#include <cmath>

#include "ui/activity/trackactivity.h"

namespace checks {
namespace {

constexpr float kTolerance = 0.0001f;
constexpr int kIsolatedTrack = 3;

bool nearlyEqual(float actual, float expected)
{
    return std::abs(actual - expected) <= kTolerance;
}

bool dark(TrackActivityIntensity intensity)
{
    return intensity.left == 0.0f && intensity.right == 0.0f;
}

bool everyTrackDark(const TrackActivity &activity)
{
    for (int track = 0; track < int(kMaxTracks); ++track) {
        if (!dark(activity.intensity(track)))
            return false;
    }
    return true;
}

} // namespace

void TrackActivityTest::freshActivityIsDark()
{
    TrackActivity activity;
    for (int track = 0; track < int(kMaxTracks); ++track)
        QVERIFY2(dark(activity.intensity(track)), "new activity must be dark");
    QVERIFY2(dark(activity.intensity(-1)), "invalid negative track must be dark");
    QVERIFY2(dark(activity.intensity(int(kMaxTracks))), "invalid high track must be dark");
}

void TrackActivityTest::attackRetainsStereoTargets_data()
{
    QTest::addColumn<uint8_t>("peakLeft");
    QTest::addColumn<uint8_t>("peakRight");

    QTest::newRow("asymmetric") << uint8_t{128} << uint8_t{32};
    QTest::newRow("left-only") << uint8_t{255} << uint8_t{0};
    QTest::newRow("right-only") << uint8_t{0} << uint8_t{255};
}

void TrackActivityTest::attackRetainsStereoTargets()
{
    QFETCH(uint8_t, peakLeft);
    QFETCH(uint8_t, peakRight);

    TrackActivity activity;
    TrackActivityLevels levels{};
    levels[kIsolatedTrack] = {peakLeft, peakRight};
    QVERIFY2(activity.advance(levels, 0.017f, true), "playing activity must require another tick");

    const auto first = activity.intensity(kIsolatedTrack);
    // A side with a peak attacks toward it without snapping; a silent side
    // stays exactly at zero (hard-panned peaks never cross-bleed).
    const auto approaches = [](float value, uint8_t peak) {
        return peak > 0 ? (value > 0.0f && value < peak / 255.0f) : value == 0.0f;
    };
    QVERIFY2(approaches(first.left, peakLeft),
             "left attack must approach the peak without snapping");
    QVERIFY2(approaches(first.right, peakRight),
             "right attack must approach the peak without snapping");
    QVERIFY2(peakLeft > peakRight ? first.left > first.right : first.right > first.left,
             "stereo sides must retain independent targets with no channel bleed");
    for (int track = 0; track < int(kMaxTracks); ++track) {
        if (track != kIsolatedTrack)
            QVERIFY2(dark(activity.intensity(track)), "a peak must not light another track");
    }
}

void TrackActivityTest::releaseIsGradualAndMonotonic()
{
    TrackActivity activity;
    TrackActivityLevels levels{};
    levels[kIsolatedTrack] = {128, 32};
    activity.advance(levels, 0.017f, true);

    levels.fill({});
    auto previous = activity.intensity(kIsolatedTrack);
    activity.advance(levels, 0.125f, true);
    auto current = activity.intensity(kIsolatedTrack);
    QVERIFY2(current.left > previous.left * 0.5f && current.right > previous.right * 0.5f,
             "ordinary release must remain visibly gradual");
    previous = current;
    for (auto step = 0; step < 23; ++step) {
        activity.advance(levels, 0.125f, true);
        current = activity.intensity(kIsolatedTrack);
        QVERIFY2(current.left <= previous.left && current.right <= previous.right,
                 "ordinary release must decay monotonically on both sides");
        previous = current;
    }
    QVERIFY2(dark(activity.intensity(kIsolatedTrack)), "released activity must settle at zero");
}

void TrackActivityTest::imperceptibleTailSnapsToZero()
{
    TrackActivity activity;
    TrackActivityLevels levels{};
    levels[kIsolatedTrack] = {255, 255};
    activity.advance(levels, 0.015f, true);
    levels.fill({});
    activity.advance(levels, 2.0f, true);
    QVERIFY2(dark(activity.intensity(kIsolatedTrack)),
             "the visible floor must remove an imperceptible release tail");
}

void TrackActivityTest::retriggerRetainsInertia()
{
    constexpr int kRetriggerTrack = 7;
    TrackActivity activity;
    TrackActivityLevels levels{};

    levels[kRetriggerTrack] = {48, 0};
    activity.advance(levels, 0.017f, true);
    levels.fill({});
    activity.advance(levels, 1.0f, true);
    const auto decayed = activity.intensity(kRetriggerTrack);

    levels[kRetriggerTrack] = {224, 64};
    activity.advance(levels, 0.017f, true);
    const auto retriggered = activity.intensity(kRetriggerTrack);
    QVERIFY2(retriggered.left > decayed.left && retriggered.right > decayed.right,
             "a new peak must retrigger each side independently");
    QVERIFY2(retriggered.left < 224.0f / 255.0f && retriggered.right < 64.0f / 255.0f,
             "a retrigger must retain thermal attack inertia");
}

void TrackActivityTest::resetClearsEveryLight()
{
    TrackActivity activity;
    TrackActivityLevels levels{};
    levels[kIsolatedTrack] = {200, 120};
    activity.advance(levels, 0.017f, true);
    activity.reset();
    QVERIFY2(everyTrackDark(activity), "reset must clear every light");
}

void TrackActivityTest::pausedFillSettlesEveryTrack()
{
    TrackActivity activity;
    TrackActivityLevels levels{};

    levels[kIsolatedTrack] = {255, 64};
    activity.advance(levels, 0.015f, true);
    const auto beforePause = activity.intensity(kIsolatedTrack);
    levels.fill({});
    QVERIFY2(activity.advance(levels, 0.015f, false), "paused fill must require another tick");
    const auto filling = activity.intensity(kIsolatedTrack);
    QVERIFY2(filling.left > beforePause.left && filling.right > beforePause.right,
             "paused fill must gently approach full brightness");
    QVERIFY2(!activity.advance(levels, 10.0f, false), "settled paused fill must stop ticks");
    for (int track = 0; track < int(kMaxTracks); ++track) {
        const auto settled = activity.intensity(track);
        QVERIFY2(settled.left == 1.0f && settled.right == 1.0f,
                 "paused fill must settle every side at full brightness");
    }
    QVERIFY2(!activity.advance(levels, 0.0f, false), "settled pause must remain settled");
}

void TrackActivityTest::resumeUsesFastWindowThenOrdinaryRelease()
{
    TrackActivity activity;
    TrackActivityLevels levels{};

    activity.resetPaused();
    QVERIFY2(activity.advance(levels, 0.075f, true), "resuming activity must require another tick");
    const auto resumed = activity.intensity(kIsolatedTrack);
    QVERIFY2(nearlyEqual(resumed.left, std::exp(-0.075f / 0.015f)),
             "resuming descent must use the 75 ms fast window");
    activity.advance(levels, 0.015f, true);
    const auto ordinaryRelease = activity.intensity(kIsolatedTrack);
    QVERIFY2(nearlyEqual(ordinaryRelease.left, resumed.left * std::exp(-0.015f / 0.250f)),
             "release must return to 250 ms after the resume window");
    QVERIFY2(ordinaryRelease.left > resumed.left * std::exp(-0.015f / 0.015f),
             "ordinary release must not retain the fast resume descent");
}

void TrackActivityTest::rapidPauseRearmsFastDescent()
{
    TrackActivity activity;
    TrackActivityLevels levels{};

    activity.resetPaused();
    activity.advance(levels, 0.050f, true);
    activity.advance(levels, 0.001f, false);
    const auto beforeRapidResume = activity.intensity(kIsolatedTrack);
    activity.advance(levels, 0.015f, true);
    const auto rapidResume = activity.intensity(kIsolatedTrack);
    QVERIFY2(rapidResume.left < beforeRapidResume.left * std::exp(-0.015f / 0.250f),
             "a rapid pause/resume must restart fast descent");
}

void TrackActivityTest::clampedElapsedNeedsTicksWithoutMovement()
{
    TrackActivity activity;
    TrackActivityLevels levels{};
    levels[kIsolatedTrack] = {255, 255};
    QVERIFY2(activity.advance(levels, -1.0f, true),
             "playing must require ticks with negative elapsed");
    QVERIFY2(dark(activity.intensity(kIsolatedTrack)), "negative elapsed must not move activity");
    activity.advance(levels, 0.0f, true);
    QVERIFY2(dark(activity.intensity(kIsolatedTrack)), "zero elapsed must not move activity");
}

} // namespace checks

int runTrackActivityCheck(const QStringList &qtArguments)
{
    checks::TrackActivityTest test;
    QStringList arguments{QStringLiteral("trackactivitycheck")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
