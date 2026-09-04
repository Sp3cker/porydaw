#include "rollcheckplayhead.h"

#include "checks/support/quickframebuffer.h"
#include "checks/support/songfixture.h"

#include <QColor>
#include <QImage>
#include <QPoint>
#include <QQuickItem>
#include <QRectF>
#include <QtGlobal>

#include <algorithm>
#include <cstdio>
#include <initializer_list>
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
    if (!overlay || !quick || !bandLayout.geometry(songview::TimelineBand::Ruler) ||
        !rollBandRect().isValid()) {
        failures.append("default Quick playhead scene did not expose its rendering surfaces");
        probe.hide();
        checks::support::pumpQuick();
        return failures;
    }

    const uint64_t tick =
        uint64_t(std::max(0.0, probe.camera().tickAtContentX(std::max<qreal>(
                                   1.0, probe.width() / 2.0 - probe.timelineSplitX()))));
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
    if (kQuickCarriesPlayhead && body && qAbs(body->x() - quick->rulerPlotOrigin()) > 0.01) {
        failures.append(QStringLiteral("Quick playhead surface was not anchored at the "
                                       "host-local timeline split (x=%1 split=%2)")
                            .arg(body->x())
                            .arg(quick->rulerPlotOrigin()));
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

    if (kQuickCarriesPlayhead && body) {
        const QRectF staticSurface{body->x(), body->y(), body->width(), body->height()};
        const qreal initialLocalX = probe.camera().contentX(probe.playheadTick());
        for (int move = 1; move <= 128; ++move)
            overlay->setPlayhead(initialLocalX + qreal(move) / 3.0, true, true);
        checks::support::pumpQuick();
        const QRectF movedSurface{body->x(), body->y(), body->width(), body->height()};
        if (movedSurface != staticSurface) {
            failures.append("128 position-only Quick playhead moves changed its static "
                            "timeline-column surface");
        }
        overlay->setPlayhead(initialLocalX, true, false);
        checks::support::pumpQuick();
    }

    const auto checkFixedGutter = [&](songview::TimelineBand band, const char *name,
                                      const QString &state) {
        const std::optional<songview::TimelineBandGeometry> &geometry =
            probe.timelineBandLayout().geometry(band);
        if (!geometry)
            return;
        QString error;
        const QImage frame = checks::support::captureQuickBand(probe, geometry->rect, &error);
        if (frame.isNull()) {
            failures.append(QStringLiteral("%1 Quick %2-band capture failed: %3")
                                .arg(state, QString::fromLatin1(name), error));
            return;
        }
        const QRect plotRect =
            geometry->plotRect.translated(-geometry->rect.topLeft()).intersected(frame.rect());
        const QRect fixedGutter{0, 0, plotRect.left(), geometry->rect.height()};
        if (kQuickCarriesPlayhead &&
            checks::support::hasSolidPlayheadPixel(frame, fixedGutter, color)) {
            failures.append(QStringLiteral("%1 Quick playhead body painted left of timelineSplitX "
                                           "in the %2 fixed gutter")
                                .arg(state, QString::fromLatin1(name)));
        }
        const QRect plotStrip = plotRect;
        if (kQuickCarriesPlayhead &&
            !checks::support::hasSolidPlayheadPixel(frame, plotStrip, color)) {
            failures.append(QStringLiteral("%1 Quick playhead body left no core pixel in the %2 "
                                           "plot strip")
                                .arg(state, QString::fromLatin1(name)));
        }
    };
    const auto checkRulerAtSplit = [&](const QString &state) {
        const std::optional<songview::TimelineBandGeometry> &geometry =
            probe.timelineBandLayout().geometry(songview::TimelineBand::Ruler);
        if (!geometry)
            return;
        QString error;
        const QImage frame = checks::support::captureQuickBand(probe, geometry->rect, &error);
        if (frame.isNull()) {
            failures.append(
                QStringLiteral("%1 Quick ruler-band capture failed: %2").arg(state, error));
            return;
        }
        const QRect plotRect =
            geometry->plotRect.translated(-geometry->rect.topLeft()).intersected(frame.rect());
        const int forbiddenWidth =
            std::max(0, plotRect.left() - songview::playheadTriangleHalfWidth());
        const QRect beyondTriangleWing{0, 0, forbiddenWidth, geometry->rect.height()};
        if (kQuickCarriesPlayhead &&
            checks::support::hasSolidPlayheadPixel(frame, beyondTriangleWing, color)) {
            failures.append(QStringLiteral("%1 Quick ruler playhead exceeded the permitted "
                                           "triangle half-width left of timelineSplitX")
                                .arg(state));
        }
        const QRect permittedTriangleWing{forbiddenWidth, 0, plotRect.left() - forbiddenWidth,
                                          geometry->rect.height()};
        if (kQuickCarriesPlayhead && !permittedTriangleWing.isEmpty() &&
            !checks::support::hasSolidPlayheadPixel(frame, permittedTriangleWing, color)) {
            failures.append(QStringLiteral("%1 Quick ruler playhead clipped the permitted "
                                           "triangle half-width left of timelineSplitX")
                                .arg(state));
        }
        if (kQuickCarriesPlayhead &&
            !checks::support::hasSolidPlayheadPixel(frame, frame.rect(), color)) {
            failures.append(
                QStringLiteral("%1 Quick ruler capture left no core or triangle pixel").arg(state));
        }
    };
    const auto checkTrackHeadersExcluded = [&](const QString &state) {
        const std::optional<songview::TimelineBandGeometry> &geometry =
            probe.timelineBandLayout().geometry(songview::TimelineBand::TrackHeaders);
        if (!geometry)
            return;
        QString error;
        const QImage frame = checks::support::captureQuickBand(probe, geometry->rect, &error);
        if (frame.isNull()) {
            failures.append(
                QStringLiteral("%1 Quick track-header capture failed: %2").arg(state, error));
        } else if (kQuickCarriesPlayhead &&
                   checks::support::hasSolidPlayheadPixel(frame, frame.rect(), color)) {
            failures.append(
                QStringLiteral("%1 Quick playhead painted into the excluded track-header column")
                    .arg(state));
        }
    };
    const auto checkSplitClipping = [&](bool playing) {
        SongView::ViewState stateAtSplit = probe.viewState();
        stateAtSplit.scrollPx = 0.0;
        probe.applyViewState(stateAtSplit);
        probe.setPlayheadSample(timeline.sampleForTick(0), playing);
        checks::support::pumpQuick();

        const QString state = playing ? QStringLiteral("playing") : QStringLiteral("paused");
        if (qAbs(probe.camera().contentX(probe.playheadTick())) > 0.5) {
            failures.append(
                QStringLiteral("%1 Quick split probe did not park tick zero at timelineSplitX")
                    .arg(state));
        }
        checkRulerAtSplit(state);
        checkFixedGutter(songview::TimelineBand::Roll, "roll", state);
        checkFixedGutter(songview::TimelineBand::Automation, "automation", state);
        checkFixedGutter(songview::TimelineBand::Velocity, "velocity", state);
        checkFixedGutter(songview::TimelineBand::VoiceChanges, "voice-changes", state);
        checkFixedGutter(songview::TimelineBand::OtherEvents, "other-events", state);
        checkTrackHeadersExcluded(state);
    };
    checkSplitClipping(false);
    checkSplitClipping(true);

    const auto checkOutOfRangeRight = [&](bool playing) {
        if (!body)
            return;
        overlay->setPlayhead(body->width(), true, playing);
        checks::support::pumpQuick();
        const QString state = playing ? QStringLiteral("playing") : QStringLiteral("paused");
        if (kQuickCarriesPlayhead && quick->playheadVisible()) {
            failures.append(QStringLiteral("%1 Quick playhead remained visible at the "
                                           "timeline-column right edge")
                                .arg(state));
        }
        for (const songview::TimelineBand band :
             {songview::TimelineBand::Ruler, songview::TimelineBand::Roll}) {
            const std::optional<songview::TimelineBandGeometry> &geometry =
                probe.timelineBandLayout().geometry(band);
            if (!geometry)
                continue;
            QString error;
            const QImage frame = checks::support::captureQuickBand(probe, geometry->rect, &error);
            if (frame.isNull()) {
                failures.append(
                    QStringLiteral("%1 right-edge Quick capture failed: %2").arg(state, error));
            } else if (kQuickCarriesPlayhead &&
                       checks::support::hasSolidPlayheadPixel(frame, frame.rect(), color)) {
                failures.append(
                    QStringLiteral("%1 right-edge Quick playhead retained pixels").arg(state));
            }
        }
    };
    checkOutOfRangeRight(false);
    checkOutOfRangeRight(true);

    const songview::TimelineBandLayout layout = probe.timelineBandLayout();
    songview::TimelineBandLayout rulerlessLayout = layout;
    rulerlessLayout.geometry(songview::TimelineBand::Ruler).reset();
    overlay->updateBands(rulerlessLayout);
    overlay->setPlayhead(0.0, true, false);
    checks::support::pumpQuick();
    if (kQuickCarriesPlayhead && quick->playheadVisible())
        failures.append("Quick playhead remained visible without a ruler plot");
    overlay->updateBands(layout);
    checks::support::pumpQuick();

    SongView::ViewState negativeState = probe.viewState();
    negativeState.scrollPx = qreal(unit);
    probe.applyViewState(negativeState);
    const auto checkNegativeContentX = [&](bool playing) {
        probe.setPlayheadSample(timeline.sampleForTick(0), playing);
        checks::support::pumpQuick();
        const QString state = playing ? QStringLiteral("playing") : QStringLiteral("paused");
        if (probe.camera().contentX(probe.playheadTick()) >= 0.0) {
            failures.append(
                QStringLiteral("%1 Quick negative-X probe did not produce negative camera contentX")
                    .arg(state));
            return;
        }
        if (kQuickCarriesPlayhead && quick->playheadVisible()) {
            failures.append(
                QStringLiteral("%1 Quick playhead remained visible with negative camera contentX")
                    .arg(state));
        }
        const std::optional<songview::TimelineBandGeometry> &ruler =
            probe.timelineBandLayout().geometry(songview::TimelineBand::Ruler);
        const std::optional<songview::TimelineBandGeometry> &roll =
            probe.timelineBandLayout().geometry(songview::TimelineBand::Roll);
        QString error;
        const QImage rulerFrame =
            ruler ? checks::support::captureQuickBand(probe, ruler->rect, &error) : QImage{};
        if (!ruler || rulerFrame.isNull()) {
            failures.append(
                QStringLiteral("%1 negative-X Quick ruler capture failed: %2").arg(state, error));
        } else if (kQuickCarriesPlayhead &&
                   checks::support::hasSolidPlayheadPixel(rulerFrame, rulerFrame.rect(), color)) {
            failures.append(QStringLiteral("%1 negative-X Quick ruler retained a core or triangle "
                                           "pixel")
                                .arg(state));
        }
        const QImage rollFrame =
            roll ? checks::support::captureQuickBand(probe, roll->rect, &error) : QImage{};
        if (!roll || rollFrame.isNull()) {
            failures.append(
                QStringLiteral("%1 negative-X Quick roll capture failed: %2").arg(state, error));
        } else if (kQuickCarriesPlayhead &&
                   checks::support::hasSolidPlayheadPixel(rollFrame, rollFrame.rect(), color)) {
            failures.append(
                QStringLiteral("%1 negative-X Quick roll retained a playhead body pixel")
                    .arg(state));
        }
    };
    checkNegativeContentX(false);
    checkNegativeContentX(true);

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
