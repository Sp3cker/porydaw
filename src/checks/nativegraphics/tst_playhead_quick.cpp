#include "checks/nativegraphics/tst_renderingplayhead.h"

#include <QtTest>

#include <QImage>
#include <QQuickWindow>

#include <memory>
#include <optional>

#include "checks/nativegraphics/nativegraphics_fixture.h"
#include "checks/support/quickframebuffer.h"
#include "checks/support/songfixture.h"
#include "core/miditimeline.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editorviewstate.h"
#include "ui/layout.h"
#include "ui/playheadoverlay.h"
#include "ui/songview.h"
#include "ui/songview/pianoroll.h"
#include "ui/songview/quick/playheadquick.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/timelinebandlayout.h"
#include "ui/theme/themeruntime.h"

namespace {

#ifdef __APPLE__
constexpr bool kQuickCarriesPlayhead = false;
#else
constexpr bool kQuickCarriesPlayhead = true;
#endif

std::unique_ptr<checks::nativegraphics::Rig> quickRig(const QString &projectRoot,
                                                      const QString &songLabel)
{
    QString error;
    // This case opens all three drawer pages at once; the window must leave
    // the roll pane room above their font-derived minimum bodies. Matches the
    // sibling native playhead rigs.
    std::unique_ptr<checks::nativegraphics::Rig> rig =
        checks::nativegraphics::makeRig(projectRoot, songLabel, QSize{1280, 800}, error);
    if (!rig)
        QTest::qFail(qPrintable(error), __FILE__, __LINE__);
    return rig;
}

bool frameHasPlayhead(const QImage &frame, const QColor &color)
{
    return !frame.isNull() && checks::support::hasSolidPlayheadPixel(frame, frame.rect(), color);
}

bool polarityMatches(bool present)
{
    return kQuickCarriesPlayhead ? present : !present;
}

} // namespace

void RenderingPlayheadTest::quickPolarityAndEdges_data()
{
    QTest::addColumn<bool>("playing");
    QTest::newRow("paused") << false;
    QTest::newRow("playing") << true;
}

void RenderingPlayheadTest::quickPolarityAndEdges()
{
    QFETCH(bool, playing);
    std::unique_ptr<checks::nativegraphics::Rig> rig = quickRig(m_projectRoot, m_songLabel);
    QVERIFY(rig);
    SongView &view = rig->song->view();
    const MidiTimeline &timeline = rig->song->timeline();
    auto *quick = view.quickView();
    auto *overlay = view.findChild<songview::PlayheadOverlay *>();
    QVERIFY(quick && quick->rootObject() && quick->quickWindow());
    QVERIFY(overlay);
    // This case exercises every plot; other cases retain their own drawer state.
    const std::optional<songview::TimelineBandGeometry> &headers =
        view.timelineBandLayout().geometry(songview::TimelineBand::TrackHeaders);
    auto *drawer = view.editorDrawer();
    QVERIFY(headers && drawer);
    const int fixedViewportHeight = quick->quickWindow()->height() - headers->rect.height();
    for (const EditorDrawerPage page : {EditorDrawerPage::Automations, EditorDrawerPage::Velocity,
                                        EditorDrawerPage::VoiceChanges}) {
        view.setDrawerSectionVisible(page, true);
        view.setDrawerSectionHeight(page, drawer->minimumSectionHeight());
    }
    const int minimumRollHeight =
        songview::pianoroll_detail::PianoRollGeometry::resolve(view.pianoKeyboardWidth())
            .minimumVisiblePianoRollHeight;
    quick->quickWindow()->resize(quick->quickWindow()->width(),
                                 fixedViewportHeight + drawer->overlayHeight() + minimumRollHeight);
    checks::support::pumpQuick();
    const std::optional<songview::TimelineBandGeometry> &ruler =
        view.timelineBandLayout().geometry(songview::TimelineBand::Ruler);
    const std::optional<songview::TimelineBandGeometry> &roll =
        view.timelineBandLayout().geometry(songview::TimelineBand::Roll);
    QVERIFY(ruler && roll);
    QQuickItem *body =
        quick->rootObject()->findChild<QQuickItem *>(QStringLiteral("timelineQuickRollPlayhead"));
    QVERIFY(body);

    SongView::ViewState parked = view.viewState();
    parked.scrollPx = 0.0;
    view.applyViewState(parked);
    view.setFollowPlayhead(false);
    view.setPlayheadSample(timeline.sampleForTick(0), playing);
    checks::support::pumpQuick();
    const QColor color = themes::color(themes::Role::song_view_playhead);
    if (kQuickCarriesPlayhead) {
        QVERIFY(body->isVisible());
        QVERIFY(body->width() >= 1.0 && body->height() >= 1.0);
        QVERIFY(qAbs(body->x() - quick->rulerPlotOrigin()) <= 0.01);
        QVERIFY(quick->playheadVisible());
    } else {
        QVERIFY(!body->isVisible());
        QVERIFY(!quick->playheadVisible());
    }

    QString captureError;
    const qreal initialTimelineX = view.camera().contentX(0.0);
    overlay->setPlayhead(initialTimelineX, false, playing);
    checks::support::pumpQuick();
    QVERIFY(headers);
    const QImage headerWithoutPlayhead =
        checks::support::captureQuickBand(view, headers->rect, &captureError);
    QVERIFY2(!headerWithoutPlayhead.isNull(), qPrintable(captureError));

    overlay->setPlayhead(initialTimelineX, true, playing);
    checks::support::pumpQuick();
    const QImage headerFrame =
        checks::support::captureQuickBand(view, headers->rect, &captureError);
    QVERIFY2(!headerFrame.isNull(), qPrintable(captureError));
    const auto firstDifferingPixel = [](const QImage &a, const QImage &b) -> QString {
        if (a.size() != b.size())
            return QStringLiteral("size %1x%2 vs %3x%4")
                .arg(a.width())
                .arg(a.height())
                .arg(b.width())
                .arg(b.height());
        for (int y = 0; y < a.height(); ++y) {
            for (int x = 0; x < a.width(); ++x) {
                if (a.pixel(x, y) != b.pixel(x, y))
                    return QStringLiteral("pixel (%1, %2) #%3 vs #%4")
                        .arg(x)
                        .arg(y)
                        .arg(QString::number(a.pixel(x, y), 16),
                             QString::number(b.pixel(x, y), 16));
            }
        }
        return QStringLiteral("identical images");
    };
    // Header content can legitimately use hues near the playhead color. Its
    // pixels must nevertheless be unchanged when the playhead is shown.
    QVERIFY2(headerFrame == headerWithoutPlayhead,
             qPrintable(QStringLiteral("playhead changed header pixels; first difference at %1")
                            .arg(firstDifferingPixel(headerFrame, headerWithoutPlayhead))));

    const QImage rollFrame = checks::support::captureQuickBand(view, roll->rect, &captureError);
    QVERIFY2(!rollFrame.isNull(), qPrintable(captureError));
    QVERIFY(polarityMatches(frameHasPlayhead(rollFrame, color)));

    const auto assertBand = [&](songview::TimelineBand band, const char *name) {
        const std::optional<songview::TimelineBandGeometry> &geometry =
            view.timelineBandLayout().geometry(band);
        QVERIFY2(geometry, name);
        if (!geometry)
            return;
        const QImage frame = checks::support::captureQuickBand(view, geometry->rect, &captureError);
        QVERIFY2(!frame.isNull(), qPrintable(captureError));
        const QRect plot =
            geometry->plotRect.translated(-geometry->rect.topLeft()).intersected(frame.rect());
        const QRect gutter{0, 0, (std::max)(0, plot.left()), frame.height()};
        if (kQuickCarriesPlayhead) {
            QVERIFY(!checks::support::hasSolidPlayheadPixel(frame, gutter, color));
            QVERIFY(checks::support::hasSolidPlayheadPixel(frame, plot, color));
        } else {
            // A lane's controls can use the same theme hue as the playhead.
            // Native-only movement must leave its Quick pixels unchanged.
            overlay->setPlayhead(initialTimelineX, false, playing);
            checks::support::pumpQuick();
            const QImage hiddenFrame =
                checks::support::captureQuickBand(view, geometry->rect, &captureError);
            QVERIFY2(!hiddenFrame.isNull(), qPrintable(captureError));
            QVERIFY2(frame == hiddenFrame, name);
            overlay->setPlayhead(initialTimelineX, true, playing);
            checks::support::pumpQuick();
        }
    };
    assertBand(songview::TimelineBand::Roll, "roll");
    assertBand(songview::TimelineBand::Automation, "automation");
    assertBand(songview::TimelineBand::Velocity, "velocity");
    assertBand(songview::TimelineBand::VoiceChanges, "voice changes");
    assertBand(songview::TimelineBand::OtherEvents, "other events");

    const QImage rulerFrame = checks::support::captureQuickBand(view, ruler->rect, &captureError);
    QVERIFY2(!rulerFrame.isNull(), qPrintable(captureError));
    const QRect rulerPlot =
        ruler->plotRect.translated(-ruler->rect.topLeft()).intersected(rulerFrame.rect());
    const int forbiddenWidth =
        (std::max)(0, rulerPlot.left() - songview::playheadTriangleHalfWidth());
    const QRect forbidden{0, 0, forbiddenWidth, rulerFrame.height()};
    const QRect permitted{forbiddenWidth, 0, rulerPlot.left() - forbiddenWidth,
                          rulerFrame.height()};
    if (kQuickCarriesPlayhead) {
        QVERIFY(!checks::support::hasSolidPlayheadPixel(rulerFrame, forbidden, color));
        QVERIFY(checks::support::hasSolidPlayheadPixel(rulerFrame, permitted, color));
        QVERIFY(frameHasPlayhead(rulerFrame, color));
    } else {
        QVERIFY(!frameHasPlayhead(rulerFrame, color));
    }

    const qreal columnWidth = (std::max)(0, quick->quickWindow()->width() - view.timelineSplitX());
    overlay->setPlayhead(columnWidth, true, playing);
    checks::support::pumpQuick();
    QVERIFY(!quick->playheadVisible());
    const QImage edgeRuler = checks::support::captureQuickBand(view, ruler->rect, &captureError);
    const QImage edgeRoll = checks::support::captureQuickBand(view, roll->rect, &captureError);
    QVERIFY2(!edgeRuler.isNull() && !edgeRoll.isNull(), qPrintable(captureError));
    QVERIFY(!frameHasPlayhead(edgeRuler, color));
    QVERIFY(!frameHasPlayhead(edgeRoll, color));

    const songview::TimelineBandLayout originalLayout = view.timelineBandLayout();
    songview::TimelineBandLayout rulerless = originalLayout;
    rulerless.geometry(songview::TimelineBand::Ruler).reset();
    overlay->updateBands(rulerless);
    overlay->setPlayhead(0.0, true, playing);
    checks::support::pumpQuick();
    QVERIFY(!quick->playheadVisible());
    overlay->updateBands(originalLayout);

    SongView::ViewState negative = parked;
    negative.scrollPx = layout::singlePixel();
    view.applyViewState(negative);
    view.setPlayheadSample(timeline.sampleForTick(0), playing);
    checks::support::pumpQuick();
    QVERIFY(view.camera().contentX(view.playheadTick()) < 0.0);
    QVERIFY(!quick->playheadVisible());
    const QImage negativeRuler =
        checks::support::captureQuickBand(view, ruler->rect, &captureError);
    const QImage negativeRoll = checks::support::captureQuickBand(view, roll->rect, &captureError);
    QVERIFY2(!negativeRuler.isNull() && !negativeRoll.isNull(), qPrintable(captureError));
    QVERIFY(!frameHasPlayhead(negativeRuler, color));
    QVERIFY(!frameHasPlayhead(negativeRoll, color));

    overlay->setPlayhead(0.0, false, false);
    checks::support::pumpQuick();
    QVERIFY(!quick->playheadVisible());
    const QImage hiddenRoll = checks::support::captureQuickBand(view, roll->rect, &captureError);
    QVERIFY2(!hiddenRoll.isNull(), qPrintable(captureError));
    QVERIFY(!frameHasPlayhead(hiddenRoll, color));
}

void RenderingPlayheadTest::positionOnlyDoesNotRebuild()
{
    std::unique_ptr<checks::nativegraphics::Rig> rig = quickRig(m_projectRoot, m_songLabel);
    QVERIFY(rig);
    SongView &view = rig->song->view();
    const MidiTimeline &timeline = rig->song->timeline();
    auto *quick = view.quickView();
    auto *scene = quick ? quick->findChild<songview::TimelineQuickScene *>() : nullptr;
    const std::optional<songview::TimelineBandGeometry> &ruler =
        view.timelineBandLayout().geometry(songview::TimelineBand::Ruler);
    QVERIFY(quick && scene && ruler);
    QQuickItem *body =
        quick->rootObject()->findChild<QQuickItem *>(QStringLiteral("timelineQuickRollPlayhead"));
    QVERIFY(body);
    auto *playhead = qobject_cast<songview::TimelinePlayheadItem *>(body);
    QVERIFY(playhead);

    view.setFollowPlayhead(false);
    view.setPlayheadSample(timeline.sampleForTick(0), false);
    checks::support::pumpQuick();
    QString error;
    const QImage paused = checks::support::captureQuickBand(view, ruler->rect, &error);
    view.setPlayheadSample(timeline.sampleForTick(0), true);
    checks::support::pumpQuick();
    const QImage playing = checks::support::captureQuickBand(view, ruler->rect, &error);
    QVERIFY2(!paused.isNull() && !playing.isNull(), qPrintable(error));
    const QColor color = themes::color(themes::Role::song_view_playhead);
    QVERIFY(polarityMatches(frameHasPlayhead(paused, color)));
    QVERIFY(polarityMatches(frameHasPlayhead(playing, color)));
    const QRectF staticSurface{body->x(), body->y(), body->width(), body->height()};
    const qreal quickLocalXBefore = quick->playheadLocalX();
    const bool quickVisibleBefore = quick->playheadVisible();
    const bool quickPlayingBefore = quick->playheadPlaying();
    const bool quickTrianglePointsUpBefore = quick->playheadTrianglePointsUp();
    const qreal itemLocalXBefore = playhead->localX();

#ifdef __APPLE__
    QQuickWindow *window = quick->quickWindow();
    QVERIFY(window);
    int renderedFrames = 0;
    QObject frameProbe;
    QObject::connect(
        window, &QQuickWindow::frameSwapped, &frameProbe, [&renderedFrames] { ++renderedFrames; },
        Qt::QueuedConnection);
    // Prove the probe observes a requested frame before testing silence.
    window->update();
    QTRY_VERIFY(renderedFrames > 0);
    checks::support::pumpQuick();
    renderedFrames = 0;
#endif

    const checks::support::TimelineQuickLayerRevisions before =
        checks::support::timelineQuickLayerRevisions(*scene);
    for (uint64_t move = 1; move <= 128; ++move)
        view.setPlayheadSample(timeline.sampleForTick(move), true);
    checks::support::pumpQuick();
    QCOMPARE(checks::support::timelineQuickLayerRevisions(*scene), before);
    const QRectF movedSurface{body->x(), body->y(), body->width(), body->height()};
    QCOMPARE(movedSurface, staticSurface);

    if (kQuickCarriesPlayhead) {
        const qreal expectedLocalX = view.camera().contentX(view.playheadTick());
        QCOMPARE(quick->playheadLocalX(), expectedLocalX);
        QCOMPARE(playhead->localX(), expectedLocalX);
    } else {
        // Playback reaches the native Core Animation overlay on macOS; it
        // must leave the Quick playhead model and its QML-bound item inert.
        QCOMPARE(quick->playheadLocalX(), quickLocalXBefore);
        QCOMPARE(quick->playheadVisible(), quickVisibleBefore);
        QCOMPARE(quick->playheadPlaying(), quickPlayingBefore);
        QCOMPARE(quick->playheadTrianglePointsUp(), quickTrianglePointsUpBefore);
        QCOMPARE(playhead->localX(), itemLocalXBefore);
    }
#ifdef __APPLE__
    QVERIFY2(!QTest::qWaitFor([&renderedFrames] { return renderedFrames != 0; }, 100),
             "Position-only native playhead movement rendered a Quick frame");
#endif
}
