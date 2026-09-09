#include "checks/nativegraphics/tst_renderingplayhead.h"

#include <QtTest>

#include <QQuickWindow>

#include <memory>
#include <optional>

#include "checks/nativegraphics/nativegraphics_fixture.h"
#include "checks/support/quickframebuffer.h"
#include "checks/support/songfixture.h"
#include "core/miditimeline.h"
#include "ui/editorviewstate.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/quick/playheadquick.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/timelinebandlayout.h"

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
        QSize{90 * layout::space(layout::Space::One), 65 * layout::space(layout::Space::One)},
        error);
    if (!rig)
        QTest::qFail(qPrintable(error), __FILE__, __LINE__);
    return rig;
}

} // namespace

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
    view.setPlayheadSample(timeline.sampleForTick(0), true);
    checks::support::pumpQuick();
    const QRectF staticSurface{body->x(), body->y(), body->width(), body->height()};
    const qreal quickLocalXBefore = quick->playheadLocalX();
    const bool quickVisibleBefore = quick->playheadVisible();
    const bool quickPlayingBefore = quick->playheadPlaying();
    const bool quickTrianglePointsUpBefore = quick->playheadTrianglePointsUp();
    const qreal itemLocalXBefore = playhead->localX();

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
}
