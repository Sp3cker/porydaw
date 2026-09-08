#include "checks/nativegraphics/tst_renderingplayhead.h"

#include <QtTest>

#include <QCoreApplication>
#include <QEvent>
#include <QEventLoop>
#include <QImage>
#include <QQuickWindow>
#include <QScopeGuard>

#include <array>
#include <memory>
#include <optional>

#include "checks/nativegraphics/nativegraphics_fixture.h"
#include "checks/support/quickframebuffer.h"
#include "checks/support/songfixture.h"
#include "core/miditimeline.h"
#include "ui/layout.h"
#include "ui/playheadoverlay.h"
#include "ui/songview.h"
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
    std::unique_ptr<checks::nativegraphics::Rig> rig = checks::nativegraphics::makeRig(
        projectRoot, songLabel,
        QSize{90 * layout::space(layout::Space::One), 65 * layout::space(layout::Space::One)}, true,
        error);
    if (!rig)
        QTest::qFail(qPrintable(error), __FILE__, __LINE__);
    return rig;
}

bool frameHasPlayhead(const QImage &frame, const QRect &logicalRect, const QColor &color)
{
    if (frame.isNull())
        return false;

    const QRect pixels = checks::support::devicePixelRect(frame, logicalRect);
    const int minimumRun = (std::max)(4, pixels.height() / 2);
    const int solidAlpha = (std::max)(64, color.alpha() / 2);
    for (int x = pixels.left(); x <= pixels.right(); ++x) {
        int run = 0;
        for (int y = pixels.top(); y <= pixels.bottom(); ++y) {
            const QColor actual = frame.pixelColor(x, y);
            if (actual.alpha() >= solidAlpha && checks::support::isPlayheadPixel(actual, color)) {
                if (++run >= minimumRun)
                    return true;
            } else {
                run = 0;
            }
        }
    }
    return false;
}

bool frameHasPlayhead(const QImage &frame, const QColor &color)
{
    return frameHasPlayhead(frame, QRect{QPoint{}, frame.deviceIndependentSize().toSize()}, color);
}

class UpdateRequestProbe final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(UpdateRequestProbe)

  public:
    UpdateRequestProbe() = default;

    int count() const noexcept { return m_count; }
    void reset() noexcept { m_count = 0; }

  protected:
    bool eventFilter(QObject *, QEvent *event) override
    {
        if (event->type() == QEvent::UpdateRequest)
            ++m_count;
        return false;
    }

  private:
    int m_count = 0;
};

void drainUpdateRequests(QQuickWindow &window, UpdateRequestProbe &probe)
{
    QCoreApplication::sendPostedEvents(&window, QEvent::UpdateRequest);
    QCoreApplication::processEvents(QEventLoop::AllEvents);
    QCoreApplication::sendPostedEvents(&window, QEvent::UpdateRequest);
    probe.reset();
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
    const QImage rollFrame = checks::support::captureQuickBand(view, roll->rect, &captureError);
    QVERIFY2(!rollFrame.isNull(), qPrintable(captureError));
    if (kQuickCarriesPlayhead)
        QVERIFY(frameHasPlayhead(rollFrame, color));
    else
        QVERIFY(!checks::support::hasSolidPlayheadPixel(rollFrame, rollFrame.rect(), color));

    const auto assertBand = [&](songview::TimelineBand band, const char *name,
                                const char *retainedLayerName) {
        QQuickItem *const retainedLayer =
            quick->rootObject()->findChild<QQuickItem *>(QString::fromLatin1(retainedLayerName));
        QVERIFY2(retainedLayer, name);
        const std::optional<songview::TimelineBandGeometry> &geometry =
            view.timelineBandLayout().geometry(band);
        QCOMPARE(retainedLayer->isVisible(), geometry.has_value());
        if (!geometry)
            return;
        const QImage frame = checks::support::captureQuickBand(view, geometry->rect, &captureError);
        QVERIFY2(!frame.isNull(), qPrintable(captureError));
        const QRect plot =
            geometry->plotRect.translated(-geometry->rect.topLeft()).intersected(frame.rect());
        const QRect gutter{0, 0, (std::max)(0, plot.left()), frame.height()};
        const int probeRadius = (std::max)(1, qCeil(songview::playheadLineWidth()));
        const QRect coreProbe{plot.left() - probeRadius, plot.top(), 2 * probeRadius + 1,
                              plot.height()};
        if (kQuickCarriesPlayhead) {
            QVERIFY(!checks::support::hasSolidPlayheadPixel(frame, coreProbe.intersected(gutter),
                                                            color));
            QVERIFY(frameHasPlayhead(frame, coreProbe.intersected(plot), color));
        } else {
            overlay->setPlayhead(0.0, false, playing);
            checks::support::pumpQuick();
            const QImage hiddenFrame =
                checks::support::captureQuickBand(view, geometry->rect, &captureError);
            overlay->setPlayhead(0.0, true, playing);
            checks::support::pumpQuick();
            QVERIFY2(!hiddenFrame.isNull(), qPrintable(captureError));

            const QRect deviceProbe = checks::support::devicePixelRect(frame, coreProbe);
            const bool unchanged = frame.copy(deviceProbe) == hiddenFrame.copy(deviceProbe);
            QVERIFY2(unchanged,
                     qPrintable(QStringLiteral("%1: Quick pixels changed against hidden baseline; "
                                               "logical probe=[%2,%3 %4x%5], plot=[%6,%7 %8x%9], "
                                               "band-rect=[%10,%11 %12x%13], "
                                               "band-plot=[%14,%15 %16x%17]")
                                    .arg(QString::fromLatin1(name))
                                    .arg(coreProbe.x())
                                    .arg(coreProbe.y())
                                    .arg(coreProbe.width())
                                    .arg(coreProbe.height())
                                    .arg(plot.x())
                                    .arg(plot.y())
                                    .arg(plot.width())
                                    .arg(plot.height())
                                    .arg(geometry->rect.x())
                                    .arg(geometry->rect.y())
                                    .arg(geometry->rect.width())
                                    .arg(geometry->rect.height())
                                    .arg(geometry->plotRect.x())
                                    .arg(geometry->plotRect.y())
                                    .arg(geometry->plotRect.width())
                                    .arg(geometry->plotRect.height())));
        }
    };
    assertBand(songview::TimelineBand::Roll, "roll", "timelineQuickPianoGrid");
    assertBand(songview::TimelineBand::Automation, "automation", "timelineQuickAutomationGrid");
    assertBand(songview::TimelineBand::OtherEvents, "other events",
               "timelineQuickOtherEventsChrome");

    const bool velocityWasVisible = view.drawerSectionVisible(EditorDrawerPage::Velocity);
    const bool voiceChangesWasVisible = view.drawerSectionVisible(EditorDrawerPage::VoiceChanges);
    const EditorDrawerPage originalActivePage = view.drawerActivePage();
    view.setDrawerActivePage(EditorDrawerPage::Velocity);
    view.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
    checks::support::pumpQuick();
    QVERIFY(view.timelineBandLayout().geometry(songview::TimelineBand::Velocity));
    assertBand(songview::TimelineBand::Velocity, "velocity", "timelineQuickVelocityGrid");

    view.setDrawerSectionVisible(EditorDrawerPage::Velocity, velocityWasVisible);
    view.setDrawerActivePage(EditorDrawerPage::VoiceChanges);
    view.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, true);
    checks::support::pumpQuick();
    QVERIFY(view.timelineBandLayout().geometry(songview::TimelineBand::VoiceChanges));
    assertBand(songview::TimelineBand::VoiceChanges, "voice changes",
               "timelineQuickVoiceChangesGrid");

    view.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, voiceChangesWasVisible);
    view.setDrawerActivePage(originalActivePage);
    checks::support::pumpQuick();

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
        QVERIFY(!checks::support::hasSolidPlayheadPixel(rulerFrame, rulerFrame.rect(), color));
    }
    const std::optional<songview::TimelineBandGeometry> &headers =
        view.timelineBandLayout().geometry(songview::TimelineBand::TrackHeaders);
    QVERIFY(headers);
    const QImage headerFrame =
        checks::support::captureQuickBand(view, headers->rect, &captureError);
    QVERIFY2(!headerFrame.isNull(), qPrintable(captureError));
    overlay->setPlayhead(0.0, false, playing);
    checks::support::pumpQuick();
    const QImage hiddenHeaderFrame =
        checks::support::captureQuickBand(view, headers->rect, &captureError);
    overlay->setPlayhead(0.0, true, playing);
    checks::support::pumpQuick();
    QVERIFY2(!hiddenHeaderFrame.isNull(), qPrintable(captureError));
    QVERIFY2(headerFrame == hiddenHeaderFrame,
             "track headers changed against hidden-playhead baseline");

    const qreal columnWidth = (std::max)(0, view.width() - view.timelineSplitX());
    overlay->setPlayhead(columnWidth, true, playing);
    checks::support::pumpQuick();
    QVERIFY(!quick->playheadVisible());
    const QImage edgeRuler = checks::support::captureQuickBand(view, ruler->rect, &captureError);
    const QImage edgeRoll = checks::support::captureQuickBand(view, roll->rect, &captureError);
    QVERIFY2(!edgeRuler.isNull() && !edgeRoll.isNull(), qPrintable(captureError));
    QVERIFY(!checks::support::hasSolidPlayheadPixel(edgeRuler, edgeRuler.rect(), color));
    QVERIFY(!checks::support::hasSolidPlayheadPixel(edgeRoll, edgeRoll.rect(), color));

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
    QVERIFY(!checks::support::hasSolidPlayheadPixel(negativeRuler, negativeRuler.rect(), color));
    QVERIFY(!checks::support::hasSolidPlayheadPixel(negativeRoll, negativeRoll.rect(), color));

    overlay->setPlayhead(0.0, false, false);
    checks::support::pumpQuick();
    QVERIFY(!quick->playheadVisible());
    const QImage hiddenRoll = checks::support::captureQuickBand(view, roll->rect, &captureError);
    QVERIFY2(!hiddenRoll.isNull(), qPrintable(captureError));
    QVERIFY(!checks::support::hasSolidPlayheadPixel(hiddenRoll, hiddenRoll.rect(), color));
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
    const QRectF staticSurface{body->x(), body->y(), body->width(), body->height()};

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
    if (kQuickCarriesPlayhead) {
        QVERIFY(frameHasPlayhead(paused, color));
        QVERIFY(frameHasPlayhead(playing, color));
    } else {
        QVERIFY(!checks::support::hasSolidPlayheadPixel(paused, paused.rect(), color));
        QVERIFY(!checks::support::hasSolidPlayheadPixel(playing, playing.rect(), color));
    }
#ifdef __APPLE__
    QQuickWindow *window = quick->quickWindow();
    QVERIFY(window);
    UpdateRequestProbe probe;
    window->installEventFilter(&probe);
    const auto removeProbe = qScopeGuard([window, &probe] { window->removeEventFilter(&probe); });
    drainUpdateRequests(*window, probe);
#endif

    const checks::support::TimelineQuickLayerRevisions before =
        checks::support::timelineQuickLayerRevisions(*scene);
    for (uint64_t move = 1; move <= 128; ++move)
        view.setPlayheadSample(timeline.sampleForTick(move), true);
    checks::support::pumpQuick();
    QCOMPARE(checks::support::timelineQuickLayerRevisions(*scene), before);
    const QRectF movedSurface{body->x(), body->y(), body->width(), body->height()};
    QCOMPARE(movedSurface, staticSurface);
#ifdef __APPLE__
    QCOMPARE(probe.count(), 0);
#endif
}

void RenderingPlayheadTest::quickUpdateRequestControl()
{
    std::unique_ptr<checks::nativegraphics::Rig> rig = quickRig(m_projectRoot, m_songLabel);
    QVERIFY(rig);
    auto *quick = rig->song->view().quickView();
    QVERIFY(quick && quick->quickWindow());
    QQuickWindow &window = *quick->quickWindow();
    UpdateRequestProbe probe;
    window.installEventFilter(&probe);
    const auto removeProbe = qScopeGuard([&window, &probe] { window.removeEventFilter(&probe); });
    drainUpdateRequests(window, probe);
    window.update();
    QTRY_VERIFY_WITH_TIMEOUT(probe.count() > 0, 1'000);
}

#include "tst_playhead_quick.moc"
