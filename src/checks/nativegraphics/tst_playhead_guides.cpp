#include "checks/nativegraphics/tst_renderingplayhead.h"

#include <QtTest>

#include <QQuickItem>

#include <array>
#include <cmath>
#include <memory>
#include <optional>

#include "checks/nativegraphics/nativegraphics_fixture.h"
#include "checks/support/quickframebuffer.h"
#include "checks/support/songfixture.h"
#include "checks/support/timelinequickcheck.h"
#include "core/miditimeline.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelinequickchrome.h"
#include "ui/songview/quick/timelinequickview.h"
#include <QQuickWindow>

namespace {

QSize staticSize()
{
    return QSize{90 * layout::space(layout::Space::One), 65 * layout::space(layout::Space::One)};
}
constexpr qreal kGuideTolerance = 0.2;

struct ChromePair {
    const char *name;
    songview::TimelineChromeItem *hover = nullptr;
    songview::TimelineChromeItem *edit = nullptr;
};

std::array<ChromePair, 7> chromePairs(QQuickItem &root)
{
    std::array<ChromePair, 7> pairs{{{"Ruler"},
                                     {"Roll"},
                                     {"Automation"},
                                     {"Velocity"},
                                     {"VoiceChanges"},
                                     {"OtherEvents"},
                                     {"TrackHeaders"}}};
    for (ChromePair &pair : pairs) {
        const QString prefix = QStringLiteral("timelineQuick") + QString::fromLatin1(pair.name);
        pair.hover =
            root.findChild<songview::TimelineChromeItem *>(prefix + QStringLiteral("HoverChrome"));
        pair.edit =
            root.findChild<songview::TimelineChromeItem *>(prefix + QStringLiteral("EditChrome"));
    }
    return pairs;
}

std::unique_ptr<checks::nativegraphics::Rig> staticRig(const QString &projectRoot,
                                                       const QString &songLabel)
{
    QString error;
    std::unique_ptr<checks::nativegraphics::Rig> rig =
        checks::nativegraphics::makeRig(projectRoot, songLabel, staticSize(), error);
    if (!rig)
        QTest::qFail(qPrintable(error), __FILE__, __LINE__);
    return rig;
}

} // namespace

void RenderingPlayheadTest::guidesResizeScrollAndOwnership()
{
    std::unique_ptr<checks::nativegraphics::Rig> rig = staticRig(m_projectRoot, m_songLabel);
    QVERIFY(rig);
    SongView &view = rig->song->view();
    auto *quick = view.quickView();
    QVERIFY(quick && quick->rootObject());
    QQuickItem *root = quick->rootObject();
    const std::array<ChromePair, 7> pairs = chromePairs(*root);
    for (const ChromePair &pair : pairs) {
        QVERIFY2(pair.hover && pair.edit, pair.name);
        QCOMPARE(pair.hover->z(), 9.0);
        QCOMPARE(pair.edit->z(), 10.0);
    }

    const std::optional<songview::TimelineBandGeometry> &ruler =
        view.timelineBandLayout().geometry(songview::TimelineBand::Ruler);
    QVERIFY(ruler);
    const auto songX = [&view, &ruler](uint64_t tick) {
        return qreal(ruler->plotRect.x()) + view.camera().contentX(tick);
    };
    // The Quick window is the full canonical viewport, so song-view x and
    // Quick-root x are the same coordinate; no host translation remains.
    const auto rootX = [](qreal x) { return x; };
    const auto allVisible = [&pairs](bool hover, bool edit) {
        for (const ChromePair &pair : pairs) {
            const bool bandVisible = pair.hover->parentItem()->isVisible();
            if (pair.hover->isVisible() != (hover && bandVisible) ||
                pair.edit->isVisible() != (edit && bandVisible))
                return false;
        }
        return true;
    };

    const qreal beforeStart = songX(0) - layout::singlePixel();
    view.clearTimelineQuickHover(songview::TimelineQuickHoverOwner::Automation);
    quick->synchronizeGuides(view.timelineSplitX(), beforeStart);
    quick->publishHover(songview::TimelineQuickHoverOwner::Automation, 0, beforeStart);
    checks::support::pumpQuick();
    QVERIFY(!quick->hoverVisible());
    QVERIFY(!quick->editVisible());
    QVERIFY(allVisible(false, false));

    const uint64_t tick = uint64_t((std::max)(0.0, view.camera().tickAtContentX(1.0)));
    view.setEditCursorTick(0);
    quick->synchronizeGuides(view.timelineSplitX(), songX(0));
    checks::support::pumpQuick();
    QVERIFY(quick->editVisible());
    QVERIFY(!quick->hoverVisible());
    QVERIFY(allVisible(false, true));
    QVERIFY(qAbs(quick->editRootContentX() - rootX(songX(0))) <= kGuideTolerance);

    quick->publishHover(songview::TimelineQuickHoverOwner::Automation, tick, songX(tick));
    checks::support::pumpQuick();
    QVERIFY(quick->hoverVisible());
    QVERIFY(!quick->editVisible());
    QVERIFY(allVisible(true, false));
    QVERIFY(qAbs(quick->hoverRootContentX() - rootX(songX(tick))) <= kGuideTolerance);
    for (const ChromePair &pair : pairs) {
        QVERIFY(qAbs(checks::support::quickRootX(*pair.hover, *root) - rootX(songX(tick))) <=
                kGuideTolerance);
        QVERIFY(qAbs(checks::support::quickRootX(*pair.edit, *root) - rootX(songX(0))) <=
                kGuideTolerance);
    }

    view.publishTimelineQuickHover(songview::TimelineQuickHoverOwner::VoiceChanges, tick + 1);
    view.clearTimelineQuickHover(songview::TimelineQuickHoverOwner::Automation);
    checks::support::pumpQuick();
    QVERIFY(quick->hoverVisible());
    QVERIFY(qAbs(quick->hoverRootContentX() - rootX(songX(tick + 1))) <= kGuideTolerance);
    view.clearTimelineQuickHover(songview::TimelineQuickHoverOwner::VoiceChanges);
    checks::support::pumpQuick();
    QVERIFY(!quick->hoverVisible());
    QVERIFY(quick->editVisible());
    QVERIFY(allVisible(false, true));
    // Window-level resize stands in for the widget envelope: the canonical
    // viewport itself shrinks and restores, and guide alignment survives.
    QQuickWindow *window = quick->quickWindow();
    QVERIFY(window);
    const QSize originalSize = window->size();
    const QSize shrunkSize(originalSize.width(),
                           originalSize.height() - 4 * layout::space(layout::Space::One));
    window->resize(shrunkSize);
    checks::support::pumpQuick();
    QVERIFY(qAbs(quick->editRootContentX() - rootX(songX(0))) <= kGuideTolerance);
    window->resize(originalSize);
    checks::support::pumpQuick();

    const SongView::ViewState original = view.viewState();
    const qreal editBeforeScroll = quick->editRootContentX();
    view.setEditorHorizontalScroll(original.scrollPx + view.camera().pxPerBeat());
    checks::support::pumpQuick();
    QVERIFY(view.camera().scrollX() != original.scrollPx);
    QVERIFY(quick->editRootContentX() != editBeforeScroll);
    QVERIFY(qAbs(quick->editRootContentX() - rootX(songX(0))) <= kGuideTolerance);
}

void RenderingPlayheadTest::followScroll()
{
    std::unique_ptr<checks::nativegraphics::Rig> rig = staticRig(m_projectRoot, m_songLabel);
    QVERIFY(rig);
    SongView &view = rig->song->view();
    SongView::ViewState parked = view.viewState();
    parked.scrollPx = 0.0;
    parked.pxPerBeat = 512.0;
    view.applyViewState(parked);
    view.setFollowPlayhead(true);
    const uint64_t endTick = rig->song->timeline().lengthTicks;
    QVERIFY(endTick > 1);
    auto *quick = view.quickView();
    QVERIFY(quick && quick->quickWindow());
    const uint64_t farTick =
        (std::min)(endTick - 1,
                   uint64_t(quick->quickWindow()->width() * 4.0 / view.camera().pxPerTick()) + 1);
    QVERIFY(farTick > 0);
    const uint64_t sample = rig->song->timeline().sampleForTick(farTick);
    view.setPlayheadSample(sample, true);
    checks::support::pumpQuick();
    QVERIFY(view.camera().scrollX() > 0.0);

    view.applyViewState(parked);
    view.setFollowPlayhead(false);
    view.setPlayheadSample(sample, true);
    checks::support::pumpQuick();
    QCOMPARE(view.camera().scrollX(), 0.0);
    view.setFollowPlayhead(true);
    view.setPlayheadSample(sample, true);
    checks::support::pumpQuick();
    QVERIFY(view.camera().scrollX() > 0.0);
}
