#include "rollcheckplayhead.h"

#include "checks/support/quickframebuffer.h"
#include "checks/support/songfixture.h"

#include <QColor>
#include <QImage>
#include <QPoint>
#include <QQuickItem>
#include <QtGlobal>

#include <algorithm>
#include <cstdio>
#include <memory>
#include <optional>

#include "core/miditimeline.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/layout.h"
#include "ui/playheadoverlay.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/timelinebandlayout.h"
#include "ui/theme/themeruntime.h"

QStringList quickScenePlayheadCheckFailures(const MidiTimeline &timeline)
{
    QStringList failures;

    SongView probe;
    const int unit = layout::space(layout::Space::One);
    probe.resize(90 * unit, 65 * unit);
    probe.setSong(&timeline, nullptr);
    probe.setFollowPlayhead(false);
    probe.show();
    checks::support::pumpQuick();

    auto *overlay = probe.findChild<songview::PlayheadOverlay *>();
    auto *quick = probe.quickView();
    const songview::TimelineBandLayout &bandLayout = probe.timelineBandLayout();
    const auto rollBandRect = [&bandLayout] {
        const std::optional<songview::TimelineBandGeometry> &band =
            bandLayout.geometry(songview::TimelineBand::Roll);
        return band ? band->rect : QRect{};
    };
    const auto rollTimelineOrigin = [&bandLayout] {
        const std::optional<songview::TimelineBandGeometry> &band =
            bandLayout.geometry(songview::TimelineBand::Roll);
        return band ? band->timelineOrigin : 0;
    };
    if (!overlay || !quick || !bandLayout.geometry(songview::TimelineBand::Ruler) ||
        !rollBandRect().isValid()) {
        failures.append("default Quick playhead scene did not expose its rendering surfaces");
        probe.hide();
        checks::support::pumpQuick();
        return failures;
    }

    const uint64_t tick =
        uint64_t(std::max(0.0, probe.camera().tickAtContentX(std::max<qreal>(
                                   1.0, probe.width() / 2.0 - probe.timelinePlotOrigin()))));
    const QColor color = themes::color(themes::Role::song_view_playhead);
    const QRect rollRect = rollBandRect();
    // captureQuickBand crops are band-local logical coordinates; scan the full
    // band so the pixel proof never depends on camera-X vs QML-X agreement.
    const QRect bandLocalRect{0, 0, rollRect.width(), rollRect.height()};

    probe.setPlayheadSample(timeline.sampleForTick(tick), false);
    checks::support::pumpQuick();
    QQuickItem *body =
        quick->rootObject()->findChild<QQuickItem *>(QStringLiteral("timelineQuickRollPlayhead"));
    if (!body) {
        failures.append("Quick playhead scene did not expose the timelineQuickRollPlayhead item");
    } else if (kQuickCarriesPlayhead &&
               (!body->isVisible() || body->width() < 1 || body->height() < 1)) {
        failures.append(
            QStringLiteral("timelineQuickRollPlayhead item was hidden or undersized "
                           "(visible=%1 width=%2 height=%3)")
                .arg(body->isVisible() ? QStringLiteral("true") : QStringLiteral("false"))
                .arg(body->width())
                .arg(body->height()));
    } else if (!kQuickCarriesPlayhead && body->isVisible()) {
        failures.append("macOS default playhead left the timelineQuickRollPlayhead item visible");
    }
    assertQuickPlayheadPresent(failures, quick->playheadVisible(),
                               "SongView playhead sample did not publish visibility to the "
                               "Quick canvas");
    assertQuickPlayheadAbsent(failures, quick->playheadVisible(),
                              "macOS default playhead published visibility to the Quick canvas");
    QString captureError;
    const QImage rollFrame = checks::support::captureQuickBand(probe, rollRect, &captureError);
    if (rollFrame.isNull()) {
        failures.append(
            QStringLiteral("Quick playhead roll-band capture failed: %1").arg(captureError));
    } else {
        const bool rollBandHasPlayhead =
            checks::support::hasPlayheadPixel(rollFrame, bandLocalRect, color);
        assertQuickPlayheadPresent(failures, rollBandHasPlayhead,
                                   "Quick playhead body was not rendered into the piano roll band");
        assertQuickPlayheadAbsent(failures, rollBandHasPlayhead,
                                  "macOS default playhead painted into the Quick roll band");
        if (kQuickCarriesPlayhead && !rollBandHasPlayhead && body) {
            const QPointF bodyCenterInCanvas = body->mapToItem(
                quick->rootObject(), QPointF{body->width() / 2, body->height() / 2});
            failures.append(QStringLiteral("timelineQuickRollPlayhead item geometry: "
                                           "x=%1 y=%2 width=%3 height=%4 canvas-center=%5,%6")
                                .arg(body->x())
                                .arg(body->y())
                                .arg(body->width())
                                .arg(body->height())
                                .arg(bodyCenterInCanvas.x())
                                .arg(bodyCenterInCanvas.y()));
        }
    }

    // Park the playhead just inside the plot: timeline X is relative to the plot
    // origin, so 1.0 puts the core ~1px past it and the bloom would cross into
    // the gutter unless the Quick renderer clips to the plot strip.
    overlay->setPlayhead(1.0, true, true);
    checks::support::pumpQuick();
    const QImage gutterFrame = checks::support::captureQuickBand(probe, rollRect, &captureError);
    const int timelineOrigin = rollTimelineOrigin();
    if (gutterFrame.isNull()) {
        failures.append(
            QStringLiteral("Quick playhead gutter roll-band capture failed: %1").arg(captureError));
    } else {
        if (timelineOrigin > 0) {
            const QRect gutterRect{0, 0, timelineOrigin, rollRect.height()};
            if (checks::support::hasPlayheadPixel(gutterFrame, gutterRect, color))
                failures.append("Quick playhead painted into the timelineOrigin gutter");
        }
        if (kQuickCarriesPlayhead) {
            const QRect plotStripRect{timelineOrigin, 0, rollRect.width() - timelineOrigin,
                                      rollRect.height()};
            if (!checks::support::hasPlayheadPixel(gutterFrame, plotStripRect, color))
                failures.append("Quick playhead gutter proof left no pixel in the roll plot strip");
        }
    }
    overlay->setPlayhead(0, false, false);
    checks::support::pumpQuick();
    if (quick->playheadVisible())
        failures.append("hidden Quick playhead still reported visibility to the Quick canvas");
    const QImage hiddenFrame = checks::support::captureQuickBand(probe, rollRect, &captureError);
    if (hiddenFrame.isNull()) {
        failures.append(
            QStringLiteral("hidden Quick playhead roll-band capture failed: %1").arg(captureError));
    } else if (checks::support::hasPlayheadPixel(hiddenFrame, bandLocalRect, color)) {
        failures.append("hidden Quick playhead retained pixels in the piano roll band");
    }

    probe.hide();
    checks::support::pumpQuick();
    return failures;
}

int runRenderingPlayheadCheck(const QString &scratchProject, const QString &songLabel,
                              const QString &screenshotPath)
{
    (void)screenshotPath;

    QString error;
    auto loadedSong = checks::LoadedSong::load(scratchProject, songLabel, error);
    if (!loadedSong) {
        std::fprintf(stderr, "rendering-playhead: %s\n", qUtf8Printable(error));
        return 1;
    }
    auto rig = checks::SongViewRig::create(std::move(loadedSong), 48000.0, error);
    if (!rig) {
        std::fprintf(stderr, "rendering-playhead: %s\n", qUtf8Printable(error));
        return 1;
    }

    const QStringList failures = timelineChromeCheckFailures(rig->view(), rig->timeline());
    for (const QString &failure : failures)
        std::fprintf(stderr, "rendering-playhead: FAIL: %s\n", qUtf8Printable(failure));
    if (failures.isEmpty())
        std::fprintf(stderr, "rendering-playhead: PASS\n");
    return failures.isEmpty() ? 0 : 1;
}
